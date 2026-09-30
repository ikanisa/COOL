\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if condition is not true then
    raise exception 'assertion failed: %', message;
  end if;
end;
$$;

\set owner_id 81000000-0000-4000-8000-000000000001
\set member_id 81000000-0000-4000-8000-000000000002
\set outsider_id 81000000-0000-4000-8000-000000000003
\set admin_id 81000000-0000-4000-8000-000000000004

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
  (:'owner_id', 'authenticated', 'authenticated', '+250788100001', now(), '{}', '{}', now(), now()),
  (:'member_id', 'authenticated', 'authenticated', '+250788100002', now(), '{}', '{}', now(), now()),
  (:'outsider_id', 'authenticated', 'authenticated', '+250788100003', now(), '{}', '{}', now(), now()),
  (:'admin_id', 'authenticated', 'authenticated', '+250788100004', now(), '{}', '{}', now(), now());

update public.profiles
set country_code = 'RW',
    currency_code = 'RWF',
    momo_provider = 'mtn_momo',
    momo_number_verified_at = now(),
    momo_number = case id
      when :'owner_id'::uuid then '0788100001'
      when :'member_id'::uuid then '0788100002'
      when :'outsider_id'::uuid then '0788100003'
      else null
    end,
    momo_number_hash = case id
      when :'owner_id'::uuid then encode(extensions.digest('+250788100001', 'sha256'), 'hex')
      when :'member_id'::uuid then encode(extensions.digest('+250788100002', 'sha256'), 'hex')
      when :'outsider_id'::uuid then encode(extensions.digest('+250788100003', 'sha256'), 'hex')
      else null
    end
where id in (:'owner_id', :'member_id', :'outsider_id', :'admin_id');

select public_id as member_public_id from public.profiles where id=:'member_id'
\gset

select pg_temp.assert_true(
  not has_function_privilege(
    'authenticated',
    'public._authenticated_momo_phone_hash(uuid)',
    'EXECUTE'
  ),
  'the payer identity helper must not be directly callable by app users'
);

insert into public.admin_user_roles (user_id, role_id, granted_by, reason)
select :'admin_id', role.id, :'admin_id', 'Rollback-only group journey UAT'
from public.admin_roles role
where role.name = 'platform_owner';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values (:'admin_id','+250788100004',now()-interval '2 seconds','Synthetic group journey reviewer');
insert into auth.sessions(id,user_id,created_at)
values ('81000000-0000-4000-8000-000000000092',:'admin_id',clock_timestamp());

select pg_temp.assert_true(
  not exists (
    select 1 from public.admin_user_roles
    where user_id in (:'owner_id', :'member_id') and revoked_at is null
  ) and not exists (
    select 1 from public.profiles
    where id in (:'owner_id', :'member_id') and coalesce(is_platform_admin, false)
  ),
  'ordinary group creator and group admin must have no platform Admin approval or role'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'owner_id', 'role', 'authenticated')::text,
  true
);

do $$
begin
  begin
    perform public.create_private_group_with_owner_attested(
      'Blocked without consent',
      'UAT',
      '0788100001',
      encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
      'Primary MoMo receiver',
      'ikimina',
      'group_savings',
      'Group savings',
      null
    );
    raise exception 'creation_without_consent_unexpectedly_succeeded';
  exception
    when others then
      if sqlerrm = 'creation_without_consent_unexpectedly_succeeded' then raise; end if;
      if sqlerrm not like '%Verify this Android device%' then raise; end if;
  end;
end;
$$;

reset role;
insert into public.receiver_mode_consents (
  user_id,
  enabled,
  momo_number_hash,
  build_channel,
  device_label
)
values (
  :'owner_id',
  true,
  encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
  'uat',
  'local-rollback'
);

set local role service_role;
select set_config(
  'request.jwt.claims',
  json_build_object('role', 'service_role')::text,
  true
);
select public.mint_native_action_capability(
  :'owner_id',
  'group.create',
  repeat('a', 64),
  jsonb_build_object(
    'group_name', 'Group journey UAT',
    'group_description', 'Rollback-only end-to-end group lifecycle',
    'receiver_momo_number', '0788100001',
    'receiver_momo_number_hash', encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
    'receiver_label', 'Primary MoMo receiver',
    'group_collection_type', 'ikimina',
    'group_category_subtype', 'group_savings',
    'group_purpose_label', 'Group savings',
    'group_is_public', false
  ),
  encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
  'app.cool.mobile',
  'PLAY_RECOGNIZED',
  array['MEETS_DEVICE_INTEGRITY'],
  now()
) as native_capability
\gset

reset role;
set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'owner_id', 'role', 'authenticated')::text,
  true
);
select set_config('collect.uat.native_capability', :'native_capability', true);

do $$
begin
  begin
    perform public.create_private_group_with_owner_attested(
      'Capability payload substitution',
      'Rollback-only end-to-end group lifecycle',
      '0788100001',
      encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
      'Primary MoMo receiver',
      'ikimina',
      'group_savings',
      'Group savings',
      current_setting('collect.uat.native_capability')::uuid
    );
    raise exception 'capability_payload_substitution_unexpectedly_succeeded';
  exception
    when others then
      if sqlerrm = 'capability_payload_substitution_unexpectedly_succeeded' then raise; end if;
      if sqlerrm not like '%Android verification is invalid%' then raise; end if;
  end;
end;
$$;

select public.create_private_group_with_owner_attested(
  'Group journey UAT',
  'Rollback-only end-to-end group lifecycle',
  '0788100001',
  encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
  'Primary MoMo receiver',
  'ikimina',
  'group_savings',
  'Group savings',
  :'native_capability'
) as collection_id
\gset

do $$
begin
  begin
    perform public.create_private_group_with_owner_attested(
      'Group journey UAT',
      'Rollback-only end-to-end group lifecycle',
      '0788100001',
      encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
      'Primary MoMo receiver',
      'ikimina',
      'group_savings',
      'Group savings',
      current_setting('collect.uat.native_capability')::uuid
    );
    raise exception 'consumed_capability_reuse_unexpectedly_succeeded';
  exception
    when others then
      if sqlerrm = 'consumed_capability_reuse_unexpectedly_succeeded' then raise; end if;
      if sqlerrm not like '%already used%' then raise; end if;
  end;
end;
$$;

select public.get_group_share_code(:'collection_id') as share_code
\gset

reset role;
select set_config('collect.uat.collection_id', :'collection_id', true);
select set_config('collect.uat.share_code', :'share_code', true);

select pg_temp.assert_true(
  (
    select c.public_status = 'private'
      and c.visibility = 'private'
      and c.archived_at is null
    from public.collections c
    where c.id = :'collection_id'
  ),
  'member-created groups must be private by database contract'
);

select pg_temp.assert_true(
  exists (
    select 1 from public.collection_members
    where collection_id = :'collection_id' and user_id = :'owner_id'
      and role = 'owner' and status = 'active'
  ) and not exists (
    select 1 from public.admin_user_roles where user_id = :'owner_id'
  ),
  'ordinary creator becomes group owner without acquiring platform Admin access'
);

select pg_temp.assert_true(
  (
    select receiver.momo_number_hash = encode(
      extensions.digest('+250788100001', 'sha256'),
      'hex'
    )
    from public.collection_receivers receiver
    where receiver.collection_id = :'collection_id'
      and receiver.is_active
  ),
  'the server must store its own canonical receiver hash'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'member_id', 'role', 'authenticated')::text,
  true
);
select public.join_group_by_share_code(:'share_code');
select public.join_group_by_share_code(:'share_code');

reset role;
select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.collection_members member_row
    where member_row.collection_id = :'collection_id'
      and member_row.user_id = :'member_id'
      and member_row.role = 'member'
      and member_row.status = 'active'
  ),
  'joining must be idempotent'
);
select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.audit_logs log
    where log.entity_type = 'collection'
      and log.entity_id = :'collection_id'
      and log.action = 'group.joined'
      and log.actor_user_id = :'member_id'
  ),
  'repeat joins must emit one join audit event'
);

insert into public.collection_members (collection_id, user_id, role, status)
values (:'collection_id', :'member_id', 'admin', 'active');

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'member_id', 'role', 'authenticated')::text,
  true
);
do $$
begin
  begin
    perform public.update_collection_receiver(
      current_setting('collect.uat.collection_id')::uuid,
      '0788100002',
      encode(extensions.digest('+250788100002', 'sha256'), 'hex'),
      'Delegated admin receiver'
    );
    raise exception 'delegated_admin_receiver_redirect_unexpectedly_succeeded';
  exception
    when insufficient_privilege then null; -- retired direct receiver mutation
    when others then
      if sqlerrm = 'delegated_admin_receiver_redirect_unexpectedly_succeeded' then raise; end if;
      if sqlerrm not like '%Only the group owner%' then raise; end if;
  end;
end;
$$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'member_id', 'role', 'authenticated')::text,
  true
);
do $$
begin
  begin
    perform *
    from public.create_contribution_intent(
      current_setting('collect.uat.collection_id')::uuid,
      5000,
      encode(extensions.digest('+250788100003', 'sha256'), 'hex')
    );
    raise exception 'mismatched_payer_identity_unexpectedly_succeeded';
  exception
    when others then
      if sqlerrm = 'mismatched_payer_identity_unexpectedly_succeeded' then raise; end if;
      if sqlerrm not like '%identity verification failed%' then raise; end if;
  end;
end;
$$;
select id as intent_id
from public.create_contribution_intent(
  :'collection_id',
  5000,
  encode(extensions.digest('+250788100002', 'sha256'), 'hex')
)
\gset

reset role;
-- Synthetic device verification enters through the existing service boundary.
-- This SQL fixture does not establish an actual Play Integrity/device result.
select now()::text as sms_device_time,
  encode(extensions.digest('+250788100001', 'sha256'), 'hex') as sms_receiver_hash,
  encode(extensions.digest('GROUP-JOURNEY-UAT standalone OpenAI parse result', 'sha256'), 'hex') as sms_body_hash
\gset
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.mint_native_action_capability(
  :'owner_id', 'sms.ingest', repeat('b',64),
  jsonb_build_object('receiver_momo_number_hash', :'sms_receiver_hash',
    'client_envelope_id', '81000000-0000-4000-8000-000000000091',
    'raw_sender', 'MTN MOMO', 'raw_body_sha256', :'sms_body_hash',
    'received_at_device', :'sms_device_time'),
  :'sms_receiver_hash', 'app.cool.mobile', 'PLAY_RECOGNIZED',
  array['MEETS_DEVICE_INTEGRITY'], now()
) as sms_capability
\gset
select public.ingest_attested_raw_payment_sms(
  :'sms_capability', :'owner_id', null, 'MTN MOMO',
  'GROUP-JOURNEY-UAT standalone OpenAI parse result', :'sms_body_hash',
  '81000000-0000-4000-8000-000000000091', :'sms_receiver_hash', :'sms_device_time'
)->>'id' as raw_sms_id
\gset
reset role;
select pg_temp.assert_true(exists (
  select 1 from public.raw_payment_sms raw
  join public.native_action_capabilities capability on capability.id=raw.native_action_capability_id
  where raw.id=:'raw_sms_id' and capability.consumed_at is not null
    and raw.attestation_request_hash=capability.request_hash and raw.device_attested_at is not null
), 'payment evidence retains its consumed device capability');
update public.raw_payment_sms set parse_status='parsed' where id=:'raw_sms_id';

insert into public.parsed_payment_events (
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
  parser_schema_version,
  parsed_json,
  allocation_status
)
values (
  :'raw_sms_id',
  null,
  :'owner_id',
  true,
  'mtn_momo',
  'incoming',
  5000,
  'RWF',
  'GROUP-JOURNEY-UAT-001',
  encode(extensions.digest('+250788100002', 'sha256'), 'hex'),
  null,
  :'member_public_id',
  0.99,
  'uat-stored-openai-result',
  'collect.sms_parser.openai.v2',
  jsonb_build_object('sender_phone', '[hashed]', 'receiver_phone', null),
  'unallocated'
) returning id as event_id
\gset

set local role service_role;
select set_config(
  'request.jwt.claims',
  json_build_object('role', 'service_role')::text,
  true
);
select public.allocate_parsed_payment_event(:'event_id') as allocation_status
\gset

reset role;
select pg_temp.assert_true(
  :'allocation_status' = 'awaiting_provider_confirmation',
  'parsed SMS matching must stop at a review candidate before finality'
);
select pg_temp.assert_true(
  exists (select 1 from public.payments where parsed_event_id=:'event_id' and status='review' and posted_at is null)
  and not exists (select 1 from public.ledger_entries entry join public.payments payment on payment.id=entry.payment_id
    where payment.parsed_event_id=:'event_id'),
  'candidate matching must not create ledger credits'
);
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.assert_true(
  public.finalize_attested_payment_sms(:'raw_sms_id')->>'status'='awaiting_reconciliation',
  'consumed attested SMS cannot finalize the matched payment'
);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event(:'event_id')='already_allocated'
  and exists (select 1 from public.payments
    where parsed_event_id=:'event_id' and status='review' and posted_at is null)
  and not exists (select 1 from public.ledger_entries entry
    join public.payments payment on payment.id=entry.payment_id
    where payment.parsed_event_id=:'event_id'),
  'allocation and SMS retries retain one unposted review candidate'
);
-- Synthetic independent provider fixture; the SMS body is not provider truth.
select public.process_provider_finality_event(
  '81000000-0000-4000-8000-000000000099', 'payment.confirmed',
  repeat('d',64),
  (select id from public.payments where parsed_event_id=:'event_id'),
  'mtn_momo', 'GROUP-JOURNEY-UAT-001', 'PROVIDER-UAT-GROUP-001',
  :'sms_receiver_hash', 5000, now(), repeat('e',64), null, null
) as provider_finality \gset
select pg_temp.assert_true(
  :'provider_finality'::jsonb->>'replayed'='false',
  'separate synthetic provider event posts the candidate'
);
reset role;
select pg_temp.assert_true(
  (
    select count(*) = 2
    from public.ledger_entries entry
    join public.payments payment on payment.id = entry.payment_id
    where payment.parsed_event_id = :'event_id'
      and entry.entry_type in ('collection_credit', 'member_credit')
  ),
  'separate synthetic provider finality creates group and payer credits'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'member_id', 'role', 'authenticated')::text,
  true
);
select pg_temp.assert_true(
  (
    select summary.amount_raised_rwf = 5000
      and summary.current_user_balance_rwf = 5000
      and summary.supporter_count = 1
    from public.list_current_user_collection_summaries() summary
    where summary.collection_id = :'collection_id'
  ),
  'summary must update group balance, payer balance, and distinct supporter count'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'admin_id', 'role', 'authenticated',
    'session_id','81000000-0000-4000-8000-000000000092')::text,
  true
);
do $$ begin
  perform public.admin_update_collection_support_status(
    current_setting('collect.uat.collection_id')::uuid,
    'public_approved', 'UAT private group boundary'
  );
  raise exception 'private_group_published_unexpectedly';
exception when others then
  if sqlerrm <> 'Group does not have a pending public request' then raise; end if;
end $$;

reset role;
select pg_temp.assert_true(
  (
    select c.public_status = 'private'
      and c.visibility = 'private'
    from public.collections c
    where c.id = :'collection_id'
  ),
  'member-created group must remain private after a rejected publication request'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'outsider_id', 'role', 'authenticated')::text,
  true
);

do $$
begin
  begin
    perform *
    from public.create_contribution_intent(
      current_setting('collect.uat.collection_id')::uuid,
      7000,
      encode(extensions.digest('+250788100003', 'sha256'), 'hex')
    );
    raise exception 'public_outsider_intent_unexpectedly_succeeded';
  exception
    when others then
      if sqlerrm = 'public_outsider_intent_unexpectedly_succeeded' then raise; end if;
      if sqlerrm <> 'Private group membership is required' then raise; end if;
  end;
end;
$$;

select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'owner_id', 'role', 'authenticated')::text,
  true
);
select public.rotate_group_share_code(:'collection_id') as rotated_share_code
\gset
select set_config('collect.uat.rotated_share_code', :'rotated_share_code', true);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'outsider_id', 'role', 'authenticated')::text,
  true
);
do $$
begin
  begin
    perform public.join_group_by_share_code(
      current_setting('collect.uat.share_code')
    );
    raise exception 'retired_share_code_unexpectedly_succeeded';
  exception
    when others then
      if sqlerrm = 'retired_share_code_unexpectedly_succeeded' then raise; end if;
      if sqlerrm not like '%invalid or has expired%' then raise; end if;
  end;
end;
$$;
select public.join_group_by_share_code(:'rotated_share_code');

reset role;
update public.collection_members
set status = 'removed'
where collection_id = :'collection_id'
  and user_id = :'member_id';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'member_id', 'role', 'authenticated')::text,
  true
);
do $$
begin
  begin
    perform public.join_group_by_share_code(
      current_setting('collect.uat.rotated_share_code')
    );
    raise exception 'removed_member_rejoin_unexpectedly_succeeded';
  exception
    when others then
      if sqlerrm = 'removed_member_rejoin_unexpectedly_succeeded' then raise; end if;
      if sqlerrm not like '%Membership was removed%' then raise; end if;
  end;
end;
$$;

select 'GROUP_CREATION_JOURNEY_UAT_PASS';
rollback;
