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
  intent_row record;
  second_intent record;
  third_intent record;
  expired_intent record;
  event_id uuid;
  ambiguous_event_id uuid;
  expired_event_id uuid;
  allocation_status text;
  receiver_phone text := '+250788123456';
  receiver_hash text := encode(extensions.digest('+250788123456', 'sha256'), 'hex');
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
    (contributor_id, 'authenticated', 'authenticated', '+447700900002', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

  update profiles
    set momo_number = receiver_phone,
        momo_number_hash = receiver_hash
    where id = owner_id;

  update profiles
    set momo_number = '+447700900002',
        momo_number_hash = encode(extensions.digest('+447700900002', 'sha256'), 'hex')
    where id = contributor_id
    returning public_id::text into contributor_collect_id;

  if contributor_collect_id !~ '^[0-9]{6}$' then
    raise exception 'profile public ID is not 6 numeric chars: %', contributor_collect_id;
  end if;

  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  uat_group_id := create_group_with_owner(
    'Collect SMS-first UAT group',
    'Rollback-only group',
    receiver_phone,
    receiver_hash,
    'UAT receiver'
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

  if user_can_ingest_receiver_sms(receiver_hash, uat_group_id, contributor_id) then
    raise exception 'missing receiver authorization unexpectedly passed';
  end if;

  insert into collection_members (collection_id, user_id, role, status)
  values (uat_group_id, contributor_id, 'member', 'active');

  perform set_config('request.jwt.claim.sub', contributor_id::text, true);
  select * into intent_row
  from create_contribution_intent(uat_group_id, 5000, null);

  if intent_row.status <> 'pending'
     or intent_row.expected_amount_rwf <> 5000
     or intent_row.receiver_momo_number <> receiver_phone
     or intent_row.contributor_public_id <> contributor_collect_id then
    raise exception 'payment intent SMS-first contract failed';
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
    detected_user_public_id,
    confidence,
    parser_model,
    parsed_json,
    allocation_status
  )
  values (
    uat_group_id,
    owner_id,
    true,
    'mtn_momo',
    'incoming',
    5000,
    'RWF',
    'UAT-SMS-FIRST-001',
    receiver_hash,
    contributor_collect_id,
    0.98,
    'uat-parser',
    jsonb_build_object('detected_user_public_id', contributor_collect_id),
    'unallocated'
  )
  returning id into event_id;

  allocation_status := allocate_parsed_payment_event(event_id);
  if allocation_status <> 'allocated' then
    raise exception 'expected allocated status, got %', allocation_status;
  end if;

  if (
    select count(*)
    from payments
    where parsed_event_id = event_id
      and payments.contributor_public_id = contributor_collect_id
  ) <> 1 then
    raise exception 'allocated event did not create exactly one anonymous member payment';
  end if;

  if (select count(*) from ledger_entries where collection_id = uat_group_id and amount_rwf = 5000) <> 1 then
    raise exception 'ledger entry was not created';
  end if;

  if (select status from payment_intents where id = intent_row.id) <> 'matched' then
    raise exception 'payment intent was not marked matched';
  end if;

  allocation_status := allocate_parsed_payment_event(event_id);
  if allocation_status <> 'already_allocated' then
    raise exception 'allocation was not idempotent, got %', allocation_status;
  end if;

  select * into second_intent
  from create_contribution_intent(uat_group_id, 9000, null);
  select * into third_intent
  from create_contribution_intent(uat_group_id, 9000, null);
  select * into expired_intent
  from create_contribution_intent(uat_group_id, 12000, null);

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
    uat_group_id,
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
    uat_group_id,
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

  perform second_intent.id;
  perform third_intent.id;

  raise notice 'Collect linked rollback UAT passed: group %, SMS event %',
    uat_group_id, event_id;
end;
$$;

rollback;
SQL

if [[ "${SUPABASE_DB_QUERY_MODE:-linked}" != "direct" ]]; then
  export SUPABASE_ACCESS_TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
  if run_with_timeout "$SUPABASE_LINKED_QUERY_TIMEOUT_SECONDS" supabase_cli db query --linked -f "$tmp_sql" -o json --agent=yes >/dev/null; then
    printf '[collect-linked-uat] SMS-first rollback UAT passed via linked database query\n'
    exit 0
  fi
  printf '[collect-linked-uat][WARN] Linked database query failed or timed out after %ss; falling back to READINESS_DATABASE_URL.\n' "$SUPABASE_LINKED_QUERY_TIMEOUT_SECONDS" >&2
fi

psql_cli "$READINESS_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$tmp_sql"
