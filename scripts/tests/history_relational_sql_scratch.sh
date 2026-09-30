#!/usr/bin/env bash
set -euo pipefail

# Runs the additive migration against a disposable PostgreSQL 17 schema. This
# verifies its SQL and scoped behavior; full Supabase replay and real plans are
# separate release checks.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAME="collect-history-keyset-$$"
docker image inspect postgres:17 >/dev/null
docker run --pull=never --rm -d --name "$NAME" \
  -e POSTGRES_PASSWORD=local_history_test postgres:17 >/dev/null
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true' EXIT

for attempt in $(seq 1 120); do
  if docker logs "$NAME" 2>&1 | rg -q 'PostgreSQL init process complete' && \
     docker exec "$NAME" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 0.25
done
docker exec "$NAME" pg_isready -U postgres >/dev/null

docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U postgres <<'SQL'
create role anon;
create role authenticated;
create schema auth;
create schema extensions;
create extension pgcrypto with schema extensions;
create schema collect_member_actions;
grant usage on schema collect_member_actions to authenticated;
create function auth.uid() returns uuid language sql stable as $$
  select (current_setting('request.jwt.claims', true)::jsonb->>'sub')::uuid;
$$;
create table public.collections (
  id uuid primary key, title text not null, readable_by uuid
);
create function public.user_can_read_collection(collection uuid, user_uuid uuid)
returns boolean language sql stable as $$
  select exists(select 1 from public.collections c
    where c.id = collection and c.readable_by = user_uuid);
$$;
create table public.payments (
  id uuid primary key, collection_id uuid not null references public.collections(id),
  contributor_user_id uuid, amount_rwf bigint not null, posted_at timestamptz,
  transaction_id text, anonymity_choice text not null,
  contributor_public_id char(6), status text not null, currency text not null
);
create table public.payment_intents (
  id uuid primary key, collection_id uuid not null references public.collections(id),
  contributor_user_id uuid, expected_amount_rwf bigint,
  receiver_momo_number_hash text, status text not null,
  created_at timestamptz not null, expires_at timestamptz not null
);
create table public.collection_receivers (
  id uuid primary key, collection_id uuid not null references public.collections(id),
  momo_number_hash text, momo_number text, label text, network text,
  created_at timestamptz not null
);
SQL

docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U postgres \
  < "$ROOT/supabase/migrations/20260928150000_relational_member_history_pages.sql"
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U postgres \
  < "$ROOT/scripts/tests/history_relational_sql_scratch.sql"
