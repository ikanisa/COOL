#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "==> DATABASE_URL is not set. Please set it to run the DB smoke test (e.g., export DATABASE_URL=postgresql://postgres:postgres@localhost:54322/postgres)"
  exit 1
fi

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command psql

echo "==> DB smoke: testing payment_receiver_accounts, payment_intents, and payment_identities (rollback only)"
psql "$DATABASE_URL" <<'SQL'
\set ON_ERROR_STOP on
begin;

do $$
declare
  v_user_one uuid := gen_random_uuid();
  v_phone_one text := '+2507' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
  v_intent_id uuid;
  v_receiver_id uuid;
  v_identity_id uuid;
begin
  -- 1. Create a dummy user
  insert into auth.users (id, aud, role, phone, created_at)
  values (v_user_one, 'authenticated', 'authenticated', v_phone_one, now());

  insert into public.users (id, phone, full_name, country, language_code)
  values (v_user_one, v_phone_one, 'Smoke Tests P1', 'RW', 'en');

  -- 2. Insert payment_receiver_account
  insert into public.payment_receiver_accounts (
    code_or_number, receiver_type, owner_id, status, currency
  ) values (
    '*182*8*1*123456#', 'merchant', v_user_one, 'active', 'RWF'
  ) returning id into v_receiver_id;

  if v_receiver_id is null then
    raise exception 'Failed to create payment_receiver_account';
  end if;

  -- 3. Insert payment_intent
  insert into public.payment_intents (
    creator_id, expected_amount, currency, status, intent_type, metadata
  ) values (
    v_user_one, 5000.00, 'RWF', 'pending', 'payment', '{"order_id": "123"}'::jsonb
  ) returning id into v_intent_id;

  if v_intent_id is null then
    raise exception 'Failed to create payment_intent';
  end if;

  -- 4. Insert payment_identities
  insert into public.payment_identities (
    user_id, momo_name, momo_last_3_digits, momo_full_number, confidence_score
  ) values (
    v_user_one, 'SMOKE TEST USER', '456', '+250781234456', 1.0
  ) returning id into v_identity_id;

  if v_identity_id is null then
    raise exception 'Failed to create payment_identity';
  end if;

  raise notice '==> Success: All constraints and references valid for Phase 1 foundational schema.';
end
$$;

rollback;
SQL
echo "==> Schema tests passed."
