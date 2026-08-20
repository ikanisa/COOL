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
set public_id = case id
      when :'owner_id'::uuid then '810001'
      when :'member_id'::uuid then '810002'
      when :'outsider_id'::uuid then '810003'
      when :'admin_id'::uuid then '810004'
    end,
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
where role.name = 'group_ops_admin';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'owner_id', 'role', 'authenticated')::text,
  true
);

do $$
begin
  begin
    perform public.create_group_with_owner_attested(
      'Blocked without consent',
      'UAT',
      '0788100001',
      encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
      'Primary MoMo receiver',
      'ikimina',
      'group_savings',
      'Group savings',
      false,
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
    'group_is_public', true
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
    perform public.create_group_with_owner_attested(
      'Capability payload substitution',
      'Rollback-only end-to-end group lifecycle',
      '0788100001',
      encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
      'Primary MoMo receiver',
      'ikimina',
      'group_savings',
      'Group savings',
      true,
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

select public.create_group_with_owner_attested(
  'Group journey UAT',
  'Rollback-only end-to-end group lifecycle',
  '0788100001',
  encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
  'Primary MoMo receiver',
  'ikimina',
  'group_savings',
  'Group savings',
  true,
  :'native_capability'
) as collection_id
\gset

do $$
begin
  begin
    perform public.create_group_with_owner_attested(
      'Group journey UAT',
      'Rollback-only end-to-end group lifecycle',
      '0788100001',
      encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
      'Primary MoMo receiver',
      'ikimina',
      'group_savings',
      'Group savings',
      true,
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
    select c.public_status = 'public_requested'
      and c.visibility = 'private'
      and c.archived_at is null
    from public.collections c
    where c.id = :'collection_id'
  ),
  'new public groups must remain private while review is pending'
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
insert into public.payments (
  payment_intent_id,
  collection_id,
  contributor_user_id,
  contributor_public_id,
  receiver_user_id,
  receiver_momo_number_hash,
  amount_rwf,
  transaction_id,
  source,
  status,
  anonymity_choice,
  provider_network
)
values (
  :'intent_id',
  :'collection_id',
  :'member_id',
  '810002',
  :'owner_id',
  encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
  5000,
  'GROUP-JOURNEY-UAT-001',
  'sms_auto',
  'review',
  'public_id',
  'mtn_momo'
) returning id as payment_id
\gset

select pg_temp.assert_true(
  not exists (
    select 1 from public.ledger_entries entry
    where entry.payment_id = :'payment_id'
  ),
  'SMS-matched review candidates must not affect balances'
);

set local role service_role;
select set_config(
  'request.jwt.claims',
  json_build_object('role', 'service_role')::text,
  true
);
select public.confirm_provider_payment(
  :'payment_id',
  'mtn_momo',
  'GROUP-JOURNEY-UAT-001',
  'GROUP-JOURNEY-CONFIRM-001',
  encode(extensions.digest('+250788100001', 'sha256'), 'hex'),
  5000,
  now(),
  repeat('b', 64)
);

reset role;
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
  json_build_object('sub', :'admin_id', 'role', 'authenticated')::text,
  true
);
select public.admin_update_collection_support_status(
  :'collection_id',
  'public_approved',
  'UAT approval contract'
);

reset role;
select pg_temp.assert_true(
  (
    select c.public_status = 'public_approved'
      and c.visibility = 'public_approved'
    from public.collections c
    where c.id = :'collection_id'
  ),
  'authorized public approval must publish the group'
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
      if sqlerrm not like '%Join this group%' then raise; end if;
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
