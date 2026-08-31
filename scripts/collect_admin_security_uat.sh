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

tmp_sql="$(mktemp)"
trap 'rm -f "$tmp_sql"' EXIT

cat > "$tmp_sql" <<'SQL'
begin;

do $$
declare
  owner_id uuid := gen_random_uuid();
  contributor_id uuid := gen_random_uuid();
  compliance_admin_id uuid := gen_random_uuid();
  payments_admin_id uuid := gen_random_uuid();
  support_admin_id uuid := gen_random_uuid();
  read_only_admin_id uuid := gen_random_uuid();
  collection_id uuid;
  raw_sms_id uuid;
  payment_intent record;
  parsed_event_id uuid;
  notification_event_id uuid;
  reparse_response jsonb;
  metadata_response jsonb;
  reveal_response jsonb;
  admin_response jsonb;
  role_id uuid;
  role_matrix_user_id uuid;
  role_row record;
  permission_row record;
  expected_permission boolean;
  actual_permission boolean;
  role_index integer := 0;
  feature_flag_key text;
  feature_flag_enabled boolean;
  raw_body text := 'You have received 7,777 RWF from Admin UAT Sender +250788654321. Financial Transaction Id: ADMIN-UAT-001. New balance is 900,000 RWF.';
  receiver_phone text := '+250788111222';
  receiver_hash text := encode(extensions.digest('+250788111222', 'sha256'), 'hex');
begin
  if exists (
    select 1
    from information_schema.routine_privileges
    where specific_schema = 'public'
      and routine_name = 'admin_bootstrap_whatsapp_operator'
      and privilege_type = 'EXECUTE'
      and grantee in ('PUBLIC', 'anon', 'authenticated')
  ) then
    raise exception 'admin_bootstrap_whatsapp_operator must not be executable by browser roles';
  end if;

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
    (compliance_admin_id, 'authenticated', 'authenticated', '+250781100003', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (payments_admin_id, 'authenticated', 'authenticated', '+250781100005', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (support_admin_id, 'authenticated', 'authenticated', '+250781100006', now(), '{}'::jsonb, '{}'::jsonb, now(), now()),
    (read_only_admin_id, 'authenticated', 'authenticated', '+250781100007', now(), '{}'::jsonb, '{}'::jsonb, now(), now());

  update profiles
    set display_name = 'Admin UAT Owner',
        momo_number = receiver_phone,
        momo_number_hash = receiver_hash,
        is_platform_admin = true
    where id = owner_id;

  update profiles
    set momo_number = '+250781100002',
        momo_number_hash = encode(
          extensions.digest('+250781100002', 'sha256'),
          'hex'
        )
    where id = contributor_id;

  insert into receiver_mode_consents (
    user_id,
    enabled,
    momo_number_hash,
    build_channel,
    device_label
  ) values (
    owner_id,
    true,
    receiver_hash,
    'uat',
    'rollback-admin-security'
  );

  for role_id in select id from admin_roles where name = 'compliance_admin' loop
    insert into admin_user_roles (user_id, role_id, granted_by, reason)
    values (compliance_admin_id, role_id, owner_id, 'Rollback UAT compliance role');
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

  for role_row in select id, name from admin_roles order by name loop
    role_index := role_index + 1;
    role_matrix_user_id := gen_random_uuid();
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
    ) values (
      role_matrix_user_id,
      'authenticated',
      'authenticated',
      '+2507891' || lpad(role_index::text, 5, '0'),
      now(),
      '{}'::jsonb,
      '{}'::jsonb,
      now(),
      now()
    );
    insert into admin_user_roles (user_id, role_id, granted_by, reason)
    values (
      role_matrix_user_id,
      role_row.id,
      owner_id,
      'Rollback UAT exhaustive role matrix'
    );

    perform set_config('request.jwt.claim.sub', role_matrix_user_id::text, true);
    for permission_row in select name from admin_permissions order by name loop
      select exists (
        select 1
        from admin_role_permissions matrix_permission
        where matrix_permission.role_id = role_row.id
          and matrix_permission.permission_name = permission_row.name
      ) into expected_permission;
      actual_permission := current_user_has_admin_permission(
        permission_row.name
      );
      if actual_permission is distinct from expected_permission then
        raise exception 'Role matrix mismatch: role %, permission %, expected %, actual %',
          role_row.name,
          permission_row.name,
          expected_permission,
          actual_permission;
      end if;
    end loop;

    admin_response := admin_current_user();
    if not coalesce(admin_response->'roles' ? role_row.name, false) then
      raise exception 'Admin identity omitted active role %', role_row.name;
    end if;
    if jsonb_array_length(coalesce(admin_response->'permissions', '[]'::jsonb))
       <> (
         select count(*)
         from admin_role_permissions matrix_permission
         where matrix_permission.role_id = role_row.id
       ) then
      raise exception 'Admin identity permission count mismatch for role %',
        role_row.name;
    end if;
  end loop;

  perform set_config('request.jwt.claim.sub', contributor_id::text, true);
  if admin_current_user() <> '{}'::jsonb then
    raise exception 'Non-admin identity unexpectedly entered the admin control plane';
  end if;
  if exists (
    select 1
    from admin_permissions permission
    where current_user_has_admin_permission(permission.name)
  ) then
    raise exception 'Non-admin identity unexpectedly received an admin permission';
  end if;
  if exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and left(procedure.proname, 6) = 'admin_'
      and has_function_privilege('anon', procedure.oid, 'EXECUTE')
  ) then
    raise exception 'Anonymous role can execute an admin function';
  end if;

  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  collection_id := create_group_with_owner(
    'Admin security UAT group',
    'Rollback-only admin security UAT',
    receiver_phone,
    receiver_hash,
    'Admin UAT receiver'
  );

  insert into collection_members (collection_id, user_id, role, status)
  values (collection_id, contributor_id, 'member', 'active');

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

  perform set_config('request.jwt.claim.sub', contributor_id::text, true);
  select * into payment_intent
  from create_contribution_intent(
    collection_id,
    7777,
    encode(extensions.digest('+250781100002', 'sha256'), 'hex')
  );

  perform set_config('request.jwt.claim.sub', owner_id::text, true);
  admin_response := admin_current_user();
  if not coalesce(admin_response->'roles' ? 'platform_owner', false)
     or not coalesce(admin_response->'permissions' ? 'admin_users.manage', false) then
    raise exception 'legacy platform owner did not receive the effective control-plane identity';
  end if;
  admin_response := admin_list_payment_intents((
    select intent.contribution_code
    from payment_intents intent
    where intent.id = payment_intent.id
  ));
  if not exists (
    select 1
    from jsonb_array_elements(
      coalesce(admin_response->'rows', '[]'::jsonb)
    ) response_row
    where response_row->>'id' = payment_intent.id::text
  ) then
    raise exception 'payment intent control-plane list did not return the UAT intent';
  end if;
  perform admin_grant_user_role(
    support_admin_id,
    'read_only_admin',
    'Rollback UAT role grant'
  );
  perform admin_revoke_user_role(
    support_admin_id,
    'read_only_admin',
    'Rollback UAT role revoke'
  );
  if not exists (
    select 1 from audit_logs
    where actor_user_id = owner_id
      and entity_id = support_admin_id
      and action = 'admin.role.granted'
  ) or not exists (
    select 1 from audit_logs
    where actor_user_id = owner_id
      and entity_id = support_admin_id
      and action = 'admin.role.revoked'
  ) then
    raise exception 'admin role-management audit trail is incomplete';
  end if;

  select key, enabled
  into feature_flag_key, feature_flag_enabled
  from feature_flags
  order by key
  limit 1;
  if feature_flag_key is null then
    raise exception 'Feature flag control-plane UAT requires at least one flag';
  end if;
  begin
    perform admin_set_feature_flag(feature_flag_key, feature_flag_enabled, '');
    raise exception 'Feature flag update unexpectedly accepted a blank reason';
  exception
    when others then
      if sqlerrm not like 'Feature flag change reason is required%' then
        raise exception 'unexpected feature flag reason error: %', sqlerrm;
      end if;
  end;
  perform admin_set_feature_flag(
    feature_flag_key,
    feature_flag_enabled,
    'Rollback UAT feature flag review'
  );
  if not exists (
    select 1 from audit_logs
    where actor_user_id = owner_id
      and action = 'admin.feature_flag.updated'
      and metadata->>'reason' = 'Rollback UAT feature flag review'
  ) then
    raise exception 'Feature flag audit trail is incomplete';
  end if;

  begin
    perform admin_update_collection_support_status(collection_id, 'private', '');
    raise exception 'Collection moderation unexpectedly accepted a blank reason';
  exception
    when others then
      if sqlerrm not like 'Reason is required%' then
        raise exception 'unexpected collection moderation reason error: %', sqlerrm;
      end if;
  end;
  perform admin_update_collection_support_status(
    collection_id,
    'private',
    'Rollback UAT group moderation'
  );
  if not exists (
    select 1 from audit_logs
    where actor_user_id = owner_id
      and entity_id = collection_id
      and action = 'collection.support_status.updated'
      and metadata->>'reason' = 'Rollback UAT group moderation'
  ) then
    raise exception 'Collection moderation audit trail is incomplete';
  end if;

  insert into notification_device_tokens (
    user_id,
    platform,
    provider,
    token,
    token_hash,
    token_last_four,
    environment,
    enabled
  ) values (
    owner_id,
    'ios',
    'apns',
    repeat(md5(owner_id::text), 2),
    encode(
      extensions.digest(repeat(md5(owner_id::text), 2), 'sha256'),
      'hex'
    ),
    right(repeat(md5(owner_id::text), 2), 4),
    'sandbox',
    true
  );
  insert into notification_events (
    user_id,
    collection_id,
    type,
    title,
    body,
    status,
    last_error_code
  ) values (
    owner_id,
    collection_id,
    'security_notice',
    'Rollback UAT notification',
    'Synthetic rollback-only notification retry.',
    'failed',
    'rollback_uat'
  ) returning id into notification_event_id;
  update notification_deliveries
  set status = 'failed',
      attempt_count = 2,
      last_error_code = 'rollback_uat'
  where event_id = notification_event_id;

  begin
    perform admin_retry_notification(notification_event_id, '');
    raise exception 'Notification retry unexpectedly accepted a blank reason';
  exception
    when others then
      if sqlerrm not like 'Reason is required%' then
        raise exception 'unexpected notification retry reason error: %', sqlerrm;
      end if;
  end;
  perform admin_retry_notification(
    notification_event_id,
    'Rollback UAT notification retry'
  );
  if not exists (
    select 1 from notification_deliveries
    where event_id = notification_event_id
      and status = 'queued'
      and prior_attempt_count = 2
      and attempt_count = 0
  ) or not exists (
    select 1 from audit_logs
    where actor_user_id = owner_id
      and entity_id = notification_event_id
      and action = 'notification.delivery.retried'
      and metadata->>'reason' = 'Rollback UAT notification retry'
  ) then
    raise exception 'Notification retry state or audit trail is incomplete';
  end if;

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
    perform admin_reparse_payment_event(
      parsed_event_id,
      'Read-only should not request reparse'
    );
    raise exception 'read_only_admin unexpectedly requested reparse';
  exception
    when others then
      if sqlerrm not like 'Admin permission payment_events.reparse required%' then
        raise exception 'unexpected read_only_admin reparse error: %', sqlerrm;
      end if;
  end;

  perform set_config('request.jwt.claim.sub', payments_admin_id::text, true);
  reparse_response := admin_reparse_payment_event(
    parsed_event_id,
    'Rollback UAT payments admin reparse'
  );
  if coalesce(reparse_response->>'ok', 'false') <> 'true' then
    raise exception 'payments admin reparse did not return ok response';
  end if;
  if not exists (
    select 1 from audit_logs
    where actor_user_id = payments_admin_id
      and action = 'payment_event.reparse.requested'
      and entity_id = parsed_event_id
  ) then
    raise exception 'audit log missing for payments admin reparse';
  end if;

  raise notice 'Collect admin/security rollback UAT passed: collection %, raw_sms %, event %',
    collection_id, raw_sms_id, parsed_event_id;
end;
$$;

rollback;
SQL

if [[ "$SUPABASE_DB_QUERY_MODE" == "local" ]]; then
  local_db_container="${SUPABASE_LOCAL_DB_CONTAINER:-supabase_db_collect}"
  if ! docker inspect "$local_db_container" >/dev/null 2>&1; then
    printf '[collect-admin-uat][FAIL] Local Supabase database container is unavailable: %s\n' "$local_db_container" >&2
    exit 1
  fi
  docker exec -i "$local_db_container" \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 < "$tmp_sql"
  printf '[collect-admin-uat] rollback admin/security UAT passed via local database query\n'
  exit 0
fi

if [[ "$SUPABASE_DB_QUERY_MODE" != "direct" ]]; then
  if (SUPABASE_ACCESS_TOKEN="$SUPABASE_ACCESS_TOKEN" supabase_cli db query --linked -f "$tmp_sql" -o json --agent=yes >/dev/null); then
    printf '[collect-admin-uat] rollback admin/security UAT passed via linked database query\n'
    exit 0
  fi
  printf '[collect-admin-uat][WARN] Linked database query failed; trying the Management API query path.\n' >&2

  if [[ -n "${SUPABASE_ACCESS_TOKEN:-}" && -n "${SUPABASE_PROJECT_REF:-}" ]] &&
    supabase_management_query_file "$tmp_sql" >/dev/null; then
    printf '[collect-admin-uat] rollback admin/security UAT passed via Supabase Management API query\n'
    exit 0
  fi
  printf '[collect-admin-uat][WARN] Management API query failed; falling back to READINESS_DATABASE_URL.\n' >&2
fi

psql_cli "$READINESS_DATABASE_URL" -v ON_ERROR_STOP=1 -f "$tmp_sql"
printf '[collect-admin-uat] rollback admin/security UAT passed via direct database query\n'
