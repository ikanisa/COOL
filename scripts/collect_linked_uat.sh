#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

: "${DATABASE_URL:?DATABASE_URL is required}"
READINESS_DATABASE_URL="${SUPABASE_READINESS_DATABASE_URL:-${DATABASE_POOLER_URL:-$DATABASE_URL}}"

tmp_sql="$(mktemp)"
trap 'rm -f "$tmp_sql"' EXIT

cat > "$tmp_sql" <<'SQL'
begin;

do $$
declare
  owner_id uuid := gen_random_uuid();
  contributor_id uuid := gen_random_uuid();
  admin_id uuid := gen_random_uuid();
  uat_collection_id uuid;
  request_id uuid;
  intent_row record;
  second_intent record;
  third_intent record;
  expired_intent record;
  event_id uuid;
  ambiguous_event_id uuid;
  duplicate_event_id uuid;
  expired_event_id uuid;
  original_payment_id uuid;
  duplicate_payment_id uuid;
  payment_id uuid;
  allocation_status text;
  receiver_phone text := '+250788123456';
  sender_phone text := '+250788654321';
  receiver_hash text := encode(extensions.digest('+250788123456', 'sha256'), 'hex');
  sender_hash text := encode(extensions.digest('+250788654321', 'sha256'), 'hex');
  owner_public_id text;
begin
  insert into auth.users (
    id,
    aud,
    role,
    phone,
    phone_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
  )
  values
    (owner_id, 'authenticated', 'authenticated', '+250781000001', now(), '{}'::jsonb, '{"display_name":"Collect UAT Owner"}'::jsonb, now(), now()),
    (contributor_id, 'authenticated', 'authenticated', '+250781000002', now(), '{}'::jsonb, '{"display_name":"Collect UAT Contributor"}'::jsonb, now(), now()),
    (admin_id, 'authenticated', 'authenticated', '+250781000003', now(), '{}'::jsonb, '{"display_name":"Collect UAT Admin"}'::jsonb, now(), now());

  update profiles
    set display_name = 'Collect UAT Owner',
        momo_number = receiver_phone,
        momo_number_hash = receiver_hash,
        anonymity_default = 'public_id'
    where id = owner_id;
  update profiles
    set display_name = 'Collect UAT Contributor',
        momo_number = sender_phone,
        momo_number_hash = sender_hash,
        anonymity_default = 'display_name'
    where id = contributor_id;
  update profiles
    set display_name = 'Collect UAT Platform Admin',
        is_platform_admin = true
    where id = admin_id;

  if not exists (select 1 from profiles where id in (owner_id, contributor_id, admin_id) having count(*) = 3) then
    raise exception 'profile trigger did not create all UAT profiles';
  end if;

  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  uat_collection_id := create_collection_with_owner(
    'Collect linked UAT church fund',
    'Rollback-only UAT collection',
    'Church',
    100000,
    receiver_phone,
    receiver_hash,
    'UAT receiver',
    null,
    true,
    '{"frequency":"monthly","expected_amount_rwf":5000}'::jsonb
  );

  if not exists (
    select 1 from collections
    where id = uat_collection_id
      and visibility = 'private'
      and public_status = 'private'
      and currency = 'RWF'
      and is_recurring
  ) then
    raise exception 'collection defaults/recurring settings failed';
  end if;

  if not exists (
    select 1 from collection_members
    where collection_id = uat_collection_id
      and user_id = owner_id
      and role = 'owner'
      and status = 'active'
  ) then
    raise exception 'owner membership was not created';
  end if;

  if not exists (
    select 1 from recurring_periods
    where collection_id = uat_collection_id
      and status = 'open'
  ) then
    raise exception 'recurring period was not generated';
  end if;

  if not user_can_ingest_receiver_sms(receiver_hash, uat_collection_id, owner_id) then
    raise exception 'receiver SMS authorization failed for owner receiver';
  end if;

  if user_can_ingest_receiver_sms(sender_hash, uat_collection_id, contributor_id) then
    raise exception 'missing receiver authorization unexpectedly passed';
  end if;

  request_id := request_public_collection(uat_collection_id);
  if exists (select 1 from public_collections_view where id = uat_collection_id) then
    raise exception 'public_requested collection leaked into public directory';
  end if;

  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform review_public_collection(request_id, true, 'Rollback UAT approval');

  if not exists (select 1 from public_collections_view where id = uat_collection_id) then
    raise exception 'approved public collection did not appear in public directory';
  end if;

  perform set_config('request.jwt.claim.sub', contributor_id::text, true);
  select * into intent_row
  from create_payment_intent_with_instructions(uat_collection_id, 5000, sender_hash, 'anonymous');

  if intent_row.status <> 'pending'
     or intent_row.expected_amount_rwf <> 5000
     or intent_row.receiver_momo_number <> receiver_phone
     or intent_row.instruction_body not like '%' || intent_row.contribution_code || '%' then
    raise exception 'payment intent instruction contract failed';
  end if;

  perform report_payment_intent_paid(intent_row.id, 'uat-txn-001');

  insert into parsed_payment_events (
    collection_id,
    receiver_user_id,
    is_mobile_money_payment,
    network,
    direction,
    amount_rwf,
    currency,
    transaction_id,
    sender_name,
    sender_phone_hash,
    receiver_phone_hash,
    detected_collection_code,
    confidence,
    parser_model,
    parsed_json,
    allocation_status
  )
  values (
    uat_collection_id,
    owner_id,
    true,
    'mtn_momo',
    'incoming',
    5000,
    'RWF',
    'UAT-TXN-001',
    'Collect UAT Contributor',
    sender_hash,
    receiver_hash,
    null,
    0.98,
    'uat-parser',
    '{"sender_phone":"[hashed]","receiver_phone":"[hashed]"}'::jsonb,
    'unallocated'
  )
  returning id into event_id;

  allocation_status := allocate_parsed_payment_event(event_id);
  if allocation_status <> 'allocated' then
    raise exception 'expected allocated status, got %', allocation_status;
  end if;

  if (select count(*) from payments where parsed_event_id = event_id) <> 1 then
    raise exception 'allocated event did not create exactly one payment';
  end if;

  select id into original_payment_id
  from payments
  where parsed_event_id = event_id;

  if (select count(*) from ledger_entries where collection_id = uat_collection_id and amount_rwf = 5000) <> 1 then
    raise exception 'ledger entry was not created';
  end if;

  if (select status from payment_intents where id = intent_row.id) <> 'matched' then
    raise exception 'payment intent was not marked matched';
  end if;

  allocation_status := allocate_parsed_payment_event(event_id);
  if allocation_status <> 'already_allocated' then
    raise exception 'allocation was not idempotent, got %', allocation_status;
  end if;

  insert into parsed_payment_events (
    collection_id,
    receiver_user_id,
    is_mobile_money_payment,
    network,
    direction,
    amount_rwf,
    currency,
    transaction_id,
    sender_name,
    receiver_phone_hash,
    confidence,
    parser_model,
    parsed_json,
    allocation_status
  )
  values (
    uat_collection_id,
    owner_id,
    true,
    'mtn_momo',
    'incoming',
    5000,
    'RWF',
    'UAT-TXN-001',
    'Collect UAT Duplicate Sender',
    receiver_hash,
    0.99,
    'uat-parser',
    '{}'::jsonb,
    'needs_review'
  )
  returning id into duplicate_event_id;

  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  duplicate_payment_id := manual_allocate_parsed_payment_event(
    duplicate_event_id,
    uat_collection_id,
    null,
    'Rollback UAT duplicate transaction no double-post check'
  );

  if duplicate_payment_id <> original_payment_id then
    raise exception 'duplicate transaction returned different payment %, expected %',
      duplicate_payment_id,
      original_payment_id;
  end if;

  if (select count(*) from payments where transaction_id = 'UAT-TXN-001') <> 1 then
    raise exception 'duplicate transaction created a second payment';
  end if;

  if (select count(*) from ledger_entries where collection_id = uat_collection_id and amount_rwf = 5000) <> 1 then
    raise exception 'duplicate transaction created a second ledger entry';
  end if;

  if exists (
    select 1
    from public_contributions_view
    where collection_id = uat_collection_id
      and supporter_label <> 'Anonymous supporter'
  ) then
    raise exception 'anonymous public contribution label leaked identity';
  end if;

  select public_id::text into owner_public_id
  from profiles
  where id = owner_id;

  if owner_public_id !~ '^[0-9]{6}$' then
    raise exception 'profile public ID is not 6 numeric chars: %', owner_public_id;
  end if;

  select * into second_intent
  from create_payment_intent_with_instructions(uat_collection_id, 9000, null, 'anonymous');
  select * into third_intent
  from create_payment_intent_with_instructions(uat_collection_id, 9000, null, 'anonymous');
  select * into expired_intent
  from create_payment_intent_with_instructions(uat_collection_id, 12000, null, 'anonymous');

  update payment_intents
    set created_at = now() - interval '4 hours',
        expires_at = now() - interval '3 hours'
    where id = expired_intent.id;

  insert into parsed_payment_events (
    collection_id,
    receiver_user_id,
    is_mobile_money_payment,
    network,
    direction,
    amount_rwf,
    currency,
    receiver_phone_hash,
    confidence,
    parser_model,
    parsed_json,
    allocation_status
  )
  values (
    uat_collection_id,
    owner_id,
    true,
    'mtn_momo',
    'incoming',
    12000,
    'RWF',
    receiver_hash,
    0.96,
    'uat-parser',
    '{}'::jsonb,
    'unallocated'
  )
  returning id into expired_event_id;

  allocation_status := allocate_parsed_payment_event(expired_event_id);
  if allocation_status <> 'needs_review' then
    raise exception 'expired intent should not auto-match, got %', allocation_status;
  end if;

  if exists (select 1 from payments where parsed_event_id = expired_event_id) then
    raise exception 'expired intent event was posted automatically';
  end if;

  insert into parsed_payment_events (
    collection_id,
    receiver_user_id,
    is_mobile_money_payment,
    network,
    direction,
    amount_rwf,
    currency,
    transaction_id,
    receiver_phone_hash,
    confidence,
    parser_model,
    parsed_json,
    allocation_status
  )
  values (
    uat_collection_id,
    owner_id,
    true,
    'mtn_momo',
    'incoming',
    9000,
    'RWF',
    'UAT-AMBIGUOUS-001',
    receiver_hash,
    0.95,
    'uat-parser',
    '{}'::jsonb,
    'unallocated'
  )
  returning id into ambiguous_event_id;

  allocation_status := allocate_parsed_payment_event(ambiguous_event_id);
  if allocation_status <> 'ambiguous' then
    raise exception 'ambiguous payment should not auto-post, got %', allocation_status;
  end if;

  if exists (select 1 from payments where parsed_event_id = ambiguous_event_id) then
    raise exception 'ambiguous event was posted automatically';
  end if;

  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  payment_id := manual_allocate_parsed_payment_event(
    ambiguous_event_id,
    uat_collection_id,
    second_intent.id,
    'Rollback UAT manual allocation reason'
  );

  if payment_id is null then
    raise exception 'manual allocation did not return payment id';
  end if;

  if not exists (
    select 1 from audit_logs
    where entity_id = payment_id
      and action = 'payment.allocated.manual'
  ) then
    raise exception 'manual allocation audit log missing';
  end if;

  raise notice 'Collect linked rollback UAT passed: collection %, payment %, manual payment %',
    uat_collection_id, event_id, payment_id;
end;
$$;

rollback;
SQL

if [[ "${SUPABASE_DB_QUERY_MODE:-linked}" != "direct" ]]; then
  if SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli db query --linked -f "$tmp_sql" -o json --agent=yes >/dev/null; then
    printf '[collect-linked-uat] rollback UAT passed via linked database query\n'
    exit 0
  fi
  printf '[collect-linked-uat][WARN] Linked database query failed; falling back to READINESS_DATABASE_URL.\n' >&2
fi

psql_cli "$READINESS_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$tmp_sql"
