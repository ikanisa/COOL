#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=scripts/supabase_cli_helpers.sh
. "$ROOT_DIR/scripts/supabase_cli_helpers.sh"
# shellcheck source=scripts/load_dotenv_strict.sh
. "$ROOT_DIR/scripts/load_dotenv_strict.sh"

if [[ "${COLLECT_SKIP_DOTENV:-0}" != "1" && -f .env ]]; then
  collect_load_dotenv_strict "$ROOT_DIR/.env"
fi

SUPABASE_DB_QUERY_MODE="${SUPABASE_DB_QUERY_MODE:-linked}"
if [[ "$SUPABASE_DB_QUERY_MODE" != "local" ]]; then
  : "${DATABASE_URL:?DATABASE_URL is required}"
  READINESS_DATABASE_URL="${SUPABASE_READINESS_DATABASE_URL:-${DATABASE_POOLER_URL:-$DATABASE_URL}}"
fi
SUPABASE_LINKED_QUERY_TIMEOUT_SECONDS="${SUPABASE_LINKED_QUERY_TIMEOUT_SECONDS:-30}"

run_with_timeout() {
  local timeout_seconds="$1"
  shift

  if [[ ! "$timeout_seconds" =~ ^[0-9]+$ ]] || [[ "$timeout_seconds" -le 0 ]]; then
    "$@"
    return $?
  fi

  "$@" &
  local command_pid=$!
  (
    sleep "$timeout_seconds"
    if kill -0 "$command_pid" >/dev/null 2>&1; then
      kill -TERM "$command_pid" >/dev/null 2>&1 || true
      sleep 2
      kill -KILL "$command_pid" >/dev/null 2>&1 || true
    fi
  ) &
  local timer_pid=$!

  local status=0
  if wait "$command_pid"; then
    status=0
  else
    status=$?
  fi

  kill "$timer_pid" >/dev/null 2>&1 || true
  wait "$timer_pid" >/dev/null 2>&1 || true
  return "$status"
}

tmp_sql="$(mktemp)"
trap 'rm -f "$tmp_sql"' EXIT

cat > "$tmp_sql" <<'SQL'
begin;

do $$
declare
  owner_id uuid := gen_random_uuid();
  contributor_id uuid := gen_random_uuid();
  uat_group_id uuid;
  uat_second_group_id uuid;
  intent_row record;
  second_intent record;
  third_intent record;
  expired_intent record;
  raw_sms_id uuid;
  ambiguous_raw_sms_id uuid;
  expired_raw_sms_id uuid;
  event_id uuid;
  ambiguous_event_id uuid;
  expired_event_id uuid;
  native_capability uuid;
  allocation_status text;
  receiver_phone text := '+250788123456';
  receiver_hash text := encode(extensions.digest('+250788123456', 'sha256'), 'hex');
  contributor_phone text := '+250781000002';
  contributor_hash text := encode(extensions.digest('+250781000002', 'sha256'), 'hex');
  contributor_collect_id text;
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
    (owner_id, 'authenticated', 'authenticated', '+250781000001', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (contributor_id, 'authenticated', 'authenticated', contributor_phone, now(), '{}'::jsonb, '{}'::jsonb, now(), now());

  update profiles
    set momo_number = receiver_phone,
        momo_number_hash = receiver_hash
    where id = owner_id;

  update profiles
    set momo_number = contributor_phone,
        momo_number_hash = contributor_hash
    where id = contributor_id
    returning public_id::text into contributor_collect_id;

  if contributor_collect_id !~ '^[0-9]{6}$' then
    raise exception 'profile public ID is not 6 numeric chars: %', contributor_collect_id;
  end if;

  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform record_sms_access_consent(
    true,
    receiver_hash,
    'rollback_uat',
    'rollback_uat'
  );
  perform set_config('request.jwt.claim.role', 'service_role', true);
  native_capability := mint_native_action_capability(
    owner_id,
    'group.create',
    repeat('a', 64),
    jsonb_build_object(
      'group_name', 'Collect SMS-first UAT group',
      'group_description', 'Rollback-only group',
      'receiver_momo_number', receiver_phone,
      'receiver_momo_number_hash', receiver_hash,
      'receiver_label', 'UAT receiver',
      'group_collection_type', 'ikimina',
      'group_category_subtype', null,
      'group_purpose_label', null,
      'group_is_public', false
    ),
    receiver_hash,
    'app.cool.mobile',
    'PLAY_RECOGNIZED',
    array['MEETS_DEVICE_INTEGRITY'],
    now()
  );
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  uat_group_id := create_group_with_owner_attested(
    'Collect SMS-first UAT group',
    'Rollback-only group',
    receiver_phone,
    receiver_hash,
    'UAT receiver',
    'ikimina',
    null,
    null,
    false,
    native_capability
  );

  if not exists (
    select 1
    from collections c
    join collection_receivers cr on cr.collection_id = c.id
    where c.id = uat_group_id
      and c.visibility = 'private'
      and c.public_status = 'private'
      and cr.momo_number_hash = receiver_hash
      and cr.is_active
  ) then
    raise exception 'group defaults or receiver sync failed';
  end if;

  if not user_can_ingest_receiver_sms(receiver_hash, uat_group_id, owner_id) then
    raise exception 'MoMo SMS authorization failed for owner receiver';
  end if;

  if not user_can_ingest_receiver_sms(null::text, null::uuid, owner_id) then
    raise exception 'MoMo SMS authorization failed when provider route was omitted';
  end if;

  if user_can_ingest_receiver_sms(receiver_hash, uat_group_id, contributor_id) then
    raise exception 'missing receiver authorization unexpectedly passed';
  end if;

  insert into collection_members (collection_id, user_id, role, status)
  values (uat_group_id, contributor_id, 'member', 'active');

  perform set_config('request.jwt.claim.sub', contributor_id::text, true);
  select * into intent_row
  from create_contribution_intent(uat_group_id, 5000, contributor_hash);

  if intent_row.status <> 'pending'
     or intent_row.expected_amount_rwf <> 5000
     or intent_row.receiver_momo_number <> receiver_phone
     or intent_row.contributor_public_id <> contributor_collect_id
     or intent_row.sender_phone_hash <> contributor_hash then
    raise exception 'payment intent SMS-first contract failed';
  end if;

  if (
    select sender_phone_hash
    from payment_intents
    where id = intent_row.id
  ) is distinct from contributor_hash then
    raise exception 'payment intent sender hash was not stored';
  end if;

  insert into raw_payment_sms (
    collection_id,
    receiver_user_id,
    raw_sender,
    raw_body,
    body_hash,
    receiver_momo_number_hash,
    received_at_device,
    parse_status
  ) values (
    null,
    owner_id,
    'MTN MOMO',
    'Rollback UAT exact receipt ' || owner_id::text,
    encode(extensions.digest('rollback-exact:' || owner_id::text, 'sha256'), 'hex'),
    null,
    now(),
    'parsed'
  ) returning id into raw_sms_id;

  insert into parsed_payment_events (
    raw_sms_id,
    collection_id,
    receiver_user_id,
    is_mobile_money_payment,
    network,
    direction,
    amount_rwf,
    currency,
    transaction_id,
    sender_phone_hash,
    receiver_phone_hash,
    detected_user_public_id,
    confidence,
    parser_model,
    parsed_json,
    allocation_status
  )
  values (
    raw_sms_id,
    null,
    owner_id,
    true,
    'mtn_momo',
    'incoming',
    5000,
    'RWF',
    'UAT-SMS-FIRST-001',
    contributor_hash,
    null,
    contributor_collect_id,
    0.98,
    'uat-parser',
    jsonb_build_object('detected_user_public_id', contributor_collect_id),
    'unallocated'
  )
  returning id into event_id;

  allocation_status := allocate_parsed_payment_event(event_id);
  if allocation_status <> 'allocated' then
    raise exception 'expected automatic standalone allocation, got %', allocation_status;
  end if;

  if (
    select count(*)
    from payments
    where parsed_event_id = event_id
      and payments.contributor_public_id = contributor_collect_id
  ) <> 1 then
    raise exception 'matched event did not create exactly one anonymous member payment';
  end if;

  if (
    select count(*)
    from ledger_entries
    where collection_id = uat_group_id
      and amount_rwf = 5000
      and entry_type in ('collection_credit', 'member_credit')
  ) <> 2 then
    raise exception 'standalone allocation did not create both balanced ledger entries';
  end if;

  if (
    select coalesce(sum(amount_rwf), 0)
    from ledger_entries
    where collection_id = uat_group_id and entry_type = 'collection_credit'
  ) <> 5000 then
    raise exception 'group balance did not update exactly once';
  end if;

  if (
    select coalesce(sum(amount_rwf), 0)
    from ledger_entries
    where collection_id = uat_group_id
      and user_id = contributor_id
      and entry_type = 'member_credit'
  ) <> 5000 then
    raise exception 'payer balance did not update exactly once';
  end if;

  if (select status from payment_intents where id = intent_row.id) <> 'matched' then
    raise exception 'payment intent was not marked matched';
  end if;

  allocation_status := allocate_parsed_payment_event(event_id);
  if allocation_status <> 'already_allocated' then
    raise exception 'allocation was not idempotent, got %', allocation_status;
  end if;

  select * into expired_intent
  from create_contribution_intent(uat_group_id, 12000, contributor_hash);

  update payment_intents
    set created_at = now() - interval '4 hours',
        expires_at = now() - interval '3 hours'
    where id = expired_intent.id;

  insert into raw_payment_sms (
    collection_id,
    receiver_user_id,
    raw_sender,
    raw_body,
    body_hash,
    receiver_momo_number_hash,
    received_at_device,
    parse_status
  ) values (
    uat_group_id,
    owner_id,
    'MTN MOMO',
    'Rollback UAT expired receipt ' || owner_id::text,
    encode(extensions.digest('rollback-expired:' || owner_id::text, 'sha256'), 'hex'),
    receiver_hash,
    now(),
    'parsed'
  ) returning id into expired_raw_sms_id;

  insert into parsed_payment_events (
    raw_sms_id,
    collection_id,
    receiver_user_id,
    is_mobile_money_payment,
    network,
    direction,
    amount_rwf,
    currency,
    transaction_id,
    sender_phone_hash,
    receiver_phone_hash,
    confidence,
    parser_model,
    parsed_json,
    allocation_status
  )
  values (
    expired_raw_sms_id,
    uat_group_id,
    owner_id,
    true,
    'mtn_momo',
    'incoming',
    12000,
    'RWF',
    'UAT-EXPIRED-001',
    contributor_hash,
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

  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  native_capability := mint_native_action_capability(
    owner_id,
    'group.create',
    repeat('c', 64),
    jsonb_build_object(
      'group_name', 'Collect SMS-first UAT second group',
      'group_description', 'Rollback-only second group',
      'receiver_momo_number', receiver_phone,
      'receiver_momo_number_hash', receiver_hash,
      'receiver_label', 'Second UAT receiver',
      'group_collection_type', 'ikimina',
      'group_category_subtype', null,
      'group_purpose_label', null,
      'group_is_public', false
    ),
    receiver_hash,
    'app.cool.mobile',
    'PLAY_RECOGNIZED',
    array['MEETS_DEVICE_INTEGRITY'],
    now()
  );
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  uat_second_group_id := create_group_with_owner_attested(
    'Collect SMS-first UAT second group',
    'Rollback-only second group',
    receiver_phone,
    receiver_hash,
    'Second UAT receiver',
    'ikimina',
    null,
    null,
    false,
    native_capability
  );
  insert into collection_members (collection_id, user_id, role, status)
  values (uat_second_group_id, contributor_id, 'member', 'active');

  perform set_config('request.jwt.claim.sub', contributor_id::text, true);
  select * into second_intent
  from create_contribution_intent(uat_group_id, 9000, contributor_hash);
  select * into third_intent
  from create_contribution_intent(uat_second_group_id, 9000, contributor_hash);

  insert into raw_payment_sms (
    collection_id,
    receiver_user_id,
    raw_sender,
    raw_body,
    body_hash,
    receiver_momo_number_hash,
    received_at_device,
    parse_status
  ) values (
    null,
    owner_id,
    'MTN MOMO',
    'Rollback UAT ambiguous receipt ' || owner_id::text,
    encode(extensions.digest('rollback-ambiguous:' || owner_id::text, 'sha256'), 'hex'),
    null,
    now(),
    'parsed'
  ) returning id into ambiguous_raw_sms_id;

  insert into parsed_payment_events (
    raw_sms_id,
    collection_id,
    receiver_user_id,
    is_mobile_money_payment,
    network,
    direction,
    amount_rwf,
    currency,
    transaction_id,
    sender_phone_hash,
    receiver_phone_hash,
    confidence,
    parser_model,
    parsed_json,
    allocation_status
  )
  values (
    ambiguous_raw_sms_id,
    null,
    owner_id,
    true,
    'mtn_momo',
    'incoming',
    9000,
    'RWF',
    'UAT-AMBIGUOUS-001',
    contributor_hash,
    null,
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

  perform second_intent.id;
  perform third_intent.id;

  raise notice 'Collect linked rollback UAT passed: group %, SMS event %',
    uat_group_id, event_id;
end;
$$;

rollback;
SQL

if [[ "$SUPABASE_DB_QUERY_MODE" == "local" ]]; then
  local_db_container="${SUPABASE_LOCAL_DB_CONTAINER:-supabase_db_collect}"
  if ! docker inspect "$local_db_container" >/dev/null 2>&1; then
    printf '[collect-linked-uat][FAIL] Local Supabase database container is unavailable: %s\n' "$local_db_container" >&2
    exit 1
  fi
  docker exec -i "$local_db_container" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$tmp_sql"
  printf '[collect-linked-uat] SMS-first rollback UAT passed via local database query\n'
  exit 0
fi

if [[ "$SUPABASE_DB_QUERY_MODE" != "direct" ]]; then
  export SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
  if run_with_timeout "$SUPABASE_LINKED_QUERY_TIMEOUT_SECONDS" supabase_cli db query --linked -f "$tmp_sql" -o json --agent=yes >/dev/null; then
    printf '[collect-linked-uat] SMS-first rollback UAT passed via linked database query\n'
    exit 0
  fi
  printf '[collect-linked-uat][WARN] Linked database query failed or timed out after %ss; falling back to READINESS_DATABASE_URL.\n' "$SUPABASE_LINKED_QUERY_TIMEOUT_SECONDS" >&2
fi

psql_cli "$READINESS_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$tmp_sql"
