#!/usr/bin/env bash
set -euo pipefail

# Disposable PostgreSQL syntax/behavior check for the additive containment
# migration. It does not replace a complete Supabase-schema rehearsal.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NAME="collect-sms-boundary-$$"
docker image inspect postgres:17 >/dev/null
docker run --pull=never --rm -d --name "$NAME" \
  -e POSTGRES_PASSWORD=local_sms_boundary_test postgres:17 >/dev/null
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
create role service_role;
create schema auth;
create function auth.role() returns text language sql stable as $$
  select current_setting('request.jwt.claims', true)::jsonb ->> 'role';
$$;
create table public.raw_payment_sms(id uuid primary key);
create table public.payments(id uuid primary key, status text not null);
create table public.ledger_entries(id uuid primary key, payment_id uuid not null);
insert into public.raw_payment_sms values ('90000000-0000-4000-8000-000000000001');
insert into public.payments values ('90000000-0000-4000-8000-000000000002', 'review');
-- Stand in for an older deployment: the migration must replace this body.
create function public.finalize_attested_payment_sms(p_raw_sms_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  update public.payments set status = 'posted';
  return jsonb_build_object('status', 'posted');
end;
$$;
SQL

docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U postgres \
  < "$ROOT/supabase/migrations/20260928160000_sms_observation_never_settles.sql"
docker exec -i "$NAME" psql -X -v ON_ERROR_STOP=1 -U postgres \
  < "$ROOT/scripts/tests/sms_observation_sql_scratch.sql"
