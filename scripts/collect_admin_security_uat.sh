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
  compliance_admin_id uuid := gen_random_uuid();
  moderation_admin_id uuid := gen_random_uuid();
  payments_admin_id uuid := gen_random_uuid();
  support_admin_id uuid := gen_random_uuid();
  read_only_admin_id uuid := gen_random_uuid();
  collection_id uuid;
  public_request_id uuid;
  raw_sms_id uuid;
  payment_intent record;
  parsed_event_id uuid;
  payment_response jsonb;
  metadata_response jsonb;
  reveal_response jsonb;
  role_id uuid;
  raw_body text := 'You have received 7,777 RWF from Admin UAT Sender +250788654321. Financial Transaction Id: ADMIN-UAT-001. New balance is 900,000 RWF.';
  receiver_phone text := '+250788111222';
  receiver_hash text := encode(extensions.digest('+250788111222', 'sha256'), 'hex');
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
    (owner_id, 'authenticated', 'authenticated', '+250781100001', now(), '{}'::jsonb, '{"display_name":"Admin UAT Owner"}'::jsonb, now(), now()),
    (contributor_id, 'authenticated', 'authenticated', '+250781100002', now(), '{}'::jsonb, '{"display_name":"Admin UAT Contributor"}'::jsonb, now(), now()),
    (compliance_admin_id, 'authenticated', 'authenticated', '+250781100003', now(), '{}'::jsonb, '{"display_name":"Compliance Admin"}'::jsonb, now(), now()),
    (moderation_admin_id, 'authenticated', 'authenticated', '+250781100004', now(), '{}'::jsonb, '{"display_name":"Moderation Admin"}'::jsonb, now(), now()),
    (payments_admin_id, 'authenticated', 'authenticated', '+250781100005', now(), '{}'::jsonb, '{"display_name":"Payments Admin"}'::jsonb, now(), now()),
    (support_admin_id, 'authenticated', 'authenticated', '+250781100006', now(), '{}'::jsonb, '{"display_name":"Support Admin"}'::jsonb, now(), now()),
    (read_only_admin_id, 'authenticated', 'authenticated', '+250781100007', now(), '{}'::jsonb, '{"display_name":"Read Only Admin"}'::jsonb, now(), now());

  update profiles
    set display_name = 'Admin UAT Owner',
        momo_number = receiver_phone,
        momo_number_hash = receiver_hash
    where id = owner_id;

  for role_id in select id from admin_roles where name = 'compliance_admin' loop
    insert into admin_user_roles (user_id, role_id, granted_by, reason)
    values (compliance_admin_id, role_id, owner_id, 'Rollback UAT compliance role');
  end loop;
  for role_id in select id from admin_roles where name = 'moderation_admin' loop
    insert into admin_user_roles (user_id, role_id, granted_by, reason)
    values (moderation_admin_id, role_id, owner_id, 'Rollback UAT moderation role');
  end loop;
  for role_id in select id from admin_roles where name = 'payments_admin' loop
    insert into admin_user_roles (user_id, role_id, granted_by, reason)
    values (payments_admin_id, role_id, owner_id, 'Rollback UAT payments role');
  end loop;
  for role_id in select id from admin_roles where name = 'support_admin' loop
    insert into admin_user_roles (user_id, role_id, granted_by, reason)
    values (support_admin_id, role_id, owner_id, 'Rollback UAT support role');
  end loop;
  for role_id in select id from admin_roles where name = 'read_only_admin' loop
    insert into admin_user_roles (user_id, role_id, granted_by, reason)
    values (read_only_admin_id, role_id, owner_id, 'Rollback UAT read-only role');
  end loop;

  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  collection_id := create_collection_with_owner(
    'Admin security UAT collection',
    'Rollback-only admin security UAT',
    'Community event',
    50000,
    receiver_phone,
    receiver_hash,
    'Admin UAT receiver',
    null,
    false,
    '{}'::jsonb
  );
  public_request_id := request_public_collection(collection_id);

  insert into raw_payment_sms (
    collection_id,
    receiver_user_id,
    raw_sender,
    raw_body,
    body_hash,
    receiver_momo_number_hash,
    received_at_device,
    parse_status
  )
  values (
    collection_id,
    owner_id,
    'MTN MOMO',
    raw_body,
    encode(extensions.digest(raw_body, 'sha256'), 'hex'),
    receiver_hash,
    now(),
    'parsed'
  )
  returning id into raw_sms_id;

  perform set_config('request.jwt.claim.sub', support_admin_id::text, true);
  metadata_response := admin_get_sms_metadata(raw_sms_id);
  if metadata_response->>'masked_body' like '%250788654321%' then
    raise exception 'support SMS metadata leaked raw sender phone';
  end if;
  begin
    perform admin_reveal_raw_sms(raw_sms_id, 'Support should not reveal raw SMS');
    raise exception 'support_admin unexpectedly revealed raw SMS';
  exception
    when others then
      if sqlerrm not like 'Admin permission sms.raw.reveal required%' then
        raise exception 'unexpected support_admin reveal error: %', sqlerrm;
      end if;
  end;

  perform set_config('request.jwt.claim.sub', compliance_admin_id::text, true);
  reveal_response := admin_reveal_raw_sms(raw_sms_id, 'Rollback UAT compliance reveal');
  if reveal_response->>'message' <> raw_body then
    raise exception 'compliance raw SMS reveal did not return raw body';
  end if;
  if not exists (
    select 1 from admin_sensitive_access_logs
    where actor_user_id = compliance_admin_id
      and entity_id = raw_sms_id
      and reason = 'Rollback UAT compliance reveal'
  ) then
    raise exception 'sensitive access log missing for compliance reveal';
  end if;
  if not exists (
    select 1 from audit_logs
    where actor_user_id = compliance_admin_id
      and entity_id = raw_sms_id
      and action = 'sms.raw.revealed'
  ) then
    raise exception 'audit log missing for compliance reveal';
  end if;

  perform set_config('request.jwt.claim.sub', moderation_admin_id::text, true);
  perform admin_review_public_request(public_request_id, true, 'Rollback UAT moderation approval');
  if not exists (
    select 1 from public_collection_requests
    where id = public_request_id
      and status = 'approved'
      and admin_user_id = moderation_admin_id
  ) then
    raise exception 'moderation admin did not approve public request';
  end if;

  perform set_config('request.jwt.claim.sub', contributor_id::text, true);
  select * into payment_intent
  from create_payment_intent_with_instructions(collection_id, 7777, null, 'anonymous');

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
    receiver_phone_hash,
    confidence,
    parser_model,
    parsed_json,
    allocation_status
  )
  values (
    raw_sms_id,
    collection_id,
    owner_id,
    true,
    'mtn_momo',
    'incoming',
    7777,
    'RWF',
    'ADMIN-UAT-001',
    receiver_hash,
    0.97,
    'admin-uat-parser',
    '{}'::jsonb,
    'needs_review'
  )
  returning id into parsed_event_id;

  perform set_config('request.jwt.claim.sub', read_only_admin_id::text, true);
  begin
    perform admin_manual_allocate_payment(
      parsed_event_id,
      collection_id,
      payment_intent.id,
      'Read-only should not allocate'
    );
    raise exception 'read_only_admin unexpectedly allocated payment';
  exception
    when others then
      if sqlerrm not like 'Admin permission payments.allocate required%' then
        raise exception 'unexpected read_only_admin allocation error: %', sqlerrm;
      end if;
  end;

  perform set_config('request.jwt.claim.sub', payments_admin_id::text, true);
  payment_response := admin_manual_allocate_payment(
    parsed_event_id,
    collection_id,
    payment_intent.id,
    'Rollback UAT payments admin allocation'
  );
  if coalesce(payment_response->>'ok', 'false') <> 'true' then
    raise exception 'payments admin allocation did not return ok response';
  end if;
  if not exists (
    select 1 from audit_logs
    where actor_user_id = payments_admin_id
      and action = 'payment.allocated.manual'
      and metadata->>'parsed_event_id' = parsed_event_id::text
  ) then
    raise exception 'audit log missing for payments admin allocation';
  end if;

  raise notice 'Collect admin/security rollback UAT passed: collection %, raw_sms %, event %',
    collection_id, raw_sms_id, parsed_event_id;
end;
$$;

rollback;
SQL

if [[ "${SUPABASE_DB_QUERY_MODE:-linked}" != "direct" ]]; then
  if SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli db query --linked -f "$tmp_sql" -o json --agent=yes >/dev/null; then
    printf '[collect-admin-uat] rollback admin/security UAT passed via linked database query\n'
    exit 0
  fi
  printf '[collect-admin-uat][WARN] Linked database query failed; falling back to READINESS_DATABASE_URL.\n' >&2
fi

psql_cli "$READINESS_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$tmp_sql"
printf '[collect-admin-uat] rollback admin/security UAT passed via direct database query\n'
