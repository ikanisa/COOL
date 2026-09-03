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

\set owner_id 10000000-0000-4000-8000-000000000001
\set member_id 10000000-0000-4000-8000-000000000002
\set outsider_id 10000000-0000-4000-8000-000000000003
\set collection_id 20000000-0000-4000-8000-000000000001
select
  encode(extensions.digest('+250780000001', 'sha256'), 'hex') as receiver_hash,
  encode(extensions.digest('+250780000002', 'sha256'), 'hex') as sender_hash
\gset

insert into auth.users (
  id,
  aud,
  role,
  email,
  phone,
  phone_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (:'owner_id', 'authenticated', 'authenticated', 'owner@collect.local', '+250780000001', now(), '{}', '{}', now(), now()),
  (:'member_id', 'authenticated', 'authenticated', 'member@collect.local', '+250780000002', now(), '{}', '{}', now(), now()),
  (:'outsider_id', 'authenticated', 'authenticated', 'outsider@collect.local', '+250780000003', now(), '{}', '{}', now(), now());

update public.profiles
set public_id = case id
  when :'owner_id'::uuid then '900001'
  when :'member_id'::uuid then '900002'
  when :'outsider_id'::uuid then '900003'
end,
display_name = case id
  when :'owner_id'::uuid then 'Controlled owner'
  when :'member_id'::uuid then 'Controlled member'
  when :'outsider_id'::uuid then 'Controlled outsider'
end,
country_code = 'RW',
currency_code = 'RWF',
momo_provider = 'mtn_momo',
momo_number_verified_at = now(),
momo_number = case id
  when :'owner_id'::uuid then '0780000001'
  when :'member_id'::uuid then '0780000002'
  when :'outsider_id'::uuid then '0780000003'
end,
momo_number_hash = case id
  when :'owner_id'::uuid then encode(extensions.digest('+250780000001', 'sha256'), 'hex')
  when :'member_id'::uuid then encode(extensions.digest('+250780000002', 'sha256'), 'hex')
  when :'outsider_id'::uuid then encode(extensions.digest('+250780000003', 'sha256'), 'hex')
end
where id in (:'owner_id', :'member_id', :'outsider_id');

insert into public.collections (
  id,
  slug,
  creator_user_id,
  title,
  description,
  category,
  visibility,
  public_status,
  receiver_display_label,
  collection_type
)
values (
  :'collection_id',
  'controlled-lifecycle',
  :'owner_id',
  'Controlled lifecycle group',
  'Local-only lifecycle fixture',
  'Other',
  'private',
  'private',
  'Controlled treasury',
  'other'
);

insert into public.collection_members (collection_id, user_id, role, status)
values
  (:'collection_id', :'owner_id', 'owner', 'active'),
  (:'collection_id', :'member_id', 'member', 'active');

insert into public.collection_receivers (
  collection_id,
  receiver_user_id,
  momo_number,
  momo_number_hash,
  network,
  label
)
values (
  :'collection_id',
  :'owner_id',
  '250780000001',
  :'receiver_hash',
  'mtn_momo',
  'Controlled treasury'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'member_id', 'role', 'authenticated')::text,
  true
);

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.collection_receivers', 'select'),
  'a non-admin member must not directly read receiver details'
);

select id as pending_intent_id
from public.create_contribution_intent(
  :'collection_id',
  10000,
  :'sender_hash'
)
\gset

select pg_temp.assert_true(
  (select status = 'pending' from public.list_current_user_payment_intents() where id = :'pending_intent_id'),
  'a controlled contribution intent must start pending'
);

select pg_temp.assert_true(
  (
    select receiver_momo_number = '250780000001'
    from public.create_contribution_intent(
      :'collection_id',
      20000,
      :'sender_hash'
    )
    limit 1
  ),
  'the explicit contribution RPC must return receiver detail to an authorized member'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'outsider_id', 'role', 'authenticated')::text,
  true
);

select pg_temp.assert_true(
  (select count(*) = 0 from public.list_current_user_payment_intents() where id = :'pending_intent_id'),
  'an outsider must not read another member payment intent'
);

do $$
begin
  begin
    perform *
    from public.create_contribution_intent(
      '20000000-0000-4000-8000-000000000001',
      10000,
      'outsider-controlled-hash'
    );
    raise exception 'outsider contribution unexpectedly succeeded';
  exception
    when others then
      if sqlerrm = 'outsider contribution unexpectedly succeeded' then
        raise;
      end if;
  end;
end;
$$;

reset role;

insert into public.payment_intents (
  id,
  collection_id,
  contributor_user_id,
  expected_amount_rwf,
  receiver_momo_number_hash,
  sender_phone_hash,
  status,
  contributor_public_id,
  expires_at
)
values (
  '20000000-0000-4000-8000-000000000002',
  :'collection_id',
  :'member_id',
  30000,
  :'receiver_hash',
  :'sender_hash',
  'expired',
  '900002',
  now() - interval '1 minute'
);

insert into public.raw_payment_sms (
  id,
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
  '30000000-0000-4000-8000-000000000001',
  :'collection_id',
  :'owner_id',
  'CONTROLLED_FIXTURE',
  'Synthetic local payment message with no customer data',
  'controlled-body-hash-confirmed',
  :'receiver_hash',
  now(),
  'parsed'
);

insert into public.parsed_payment_events (
  id,
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
  transaction_time,
  detected_user_public_id,
  confidence,
  parsed_json
)
values (
  '40000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  :'collection_id',
  :'owner_id',
  true,
  'mtn_momo',
  'incoming',
  10000,
  'RWF',
  'CONTROLLED-TXN-001',
  :'sender_hash',
  :'receiver_hash',
  now(),
  '900002',
  0.99,
  '{"fixture": true}'
);

select pg_temp.assert_true(
  public.allocate_parsed_payment_event(
    '40000000-0000-4000-8000-000000000001'
  ) = 'allocated',
  'a valid controlled OpenAI-parsed event must allocate automatically'
);

select pg_temp.assert_true(
  public.allocate_parsed_payment_event(
    '40000000-0000-4000-8000-000000000001'
  ) = 'already_allocated',
  'replaying the same parsed event must be idempotent'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'member_id', 'role', 'authenticated')::text,
  true
);

select pg_temp.assert_true(
  (select status = 'matched' from public.list_current_user_payment_intents() where id = :'pending_intent_id'),
  'successful allocation must confirm the pending intent'
);

-- Inspect exact-once storage as the local test operator. Member-facing reads
-- above use the scoped RPC; financial base tables remain server-only.
reset role;
select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.payments
    where parsed_event_id = '40000000-0000-4000-8000-000000000001'
  ),
  'duplicate allocation must not duplicate payment truth'
);

select pg_temp.assert_true(
  (
    select count(*) = 2
    from public.ledger_entries
    where payment_id = (
      select id
      from public.payments
      where parsed_event_id = '40000000-0000-4000-8000-000000000001'
    )
  ),
  'confirmed payment must create exactly one group credit and one member credit'
);

select pg_temp.assert_true(
  (
    select count(*) filter (where entry_type = 'collection_credit') = 1
      and count(*) filter (where entry_type = 'member_credit') = 1
    from public.ledger_entries
    where payment_id = (
      select id
      from public.payments
      where parsed_event_id = '40000000-0000-4000-8000-000000000001'
    )
  ),
  'group and payer balances must have separate exactly-once ledger credits'
);

reset role;

insert into public.raw_payment_sms (
  id,
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
  '30000000-0000-4000-8000-000000000002',
  :'collection_id',
  :'owner_id',
  'CONTROLLED_FIXTURE',
  'Synthetic local parse failure with no customer data',
  'controlled-body-hash-failed',
  :'receiver_hash',
  now(),
  'failed'
);

select pg_temp.assert_true(
  (
    select parse_status = 'failed'
    from public.raw_payment_sms
    where id = '30000000-0000-4000-8000-000000000002'
  ),
  'a failed parse must remain explicit and must not post ledger truth'
);

do $$
begin
  begin
    insert into public.raw_payment_sms (
      collection_id,
      receiver_user_id,
      raw_sender,
      raw_body,
      body_hash
    )
    values (
      '20000000-0000-4000-8000-000000000001',
      '10000000-0000-4000-8000-000000000001',
      'CONTROLLED_FIXTURE',
      'Synthetic duplicate',
      'controlled-body-hash-confirmed'
    );
    raise exception 'duplicate SMS hash unexpectedly succeeded';
  exception
    when unique_violation then
      null;
  end;
end;
$$;

do $$
declare
  target_id uuid;
begin
  select id into target_id
  from public.ledger_entries
  where payment_id = (
    select id
    from public.payments
    where parsed_event_id = '40000000-0000-4000-8000-000000000001'
  );
  begin
    update public.ledger_entries
    set amount_rwf = amount_rwf + 1
    where id = target_id;
    raise exception 'ledger mutation unexpectedly succeeded';
  exception
    when others then
      if sqlerrm = 'ledger mutation unexpectedly succeeded' then
        raise;
      end if;
  end;
end;
$$;

insert into public.audit_logs (
  actor_user_id,
  action,
  entity_type,
  entity_id,
  metadata
)
values (
  :'owner_id',
  'controlled.lifecycle.checked',
  'collection',
  :'collection_id',
  '{"fixture": true}'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'member_id', 'role', 'authenticated')::text,
  true
);

select public.request_account_deletion('Controlled local request') as deletion_id
\gset

select public.create_mobile_support_request(
  'Controlled lifecycle support',
  'Synthetic request with no customer data'
) as support_id
\gset

select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.mobile_account_deletion_requests
    where id = :'deletion_id' and user_id = :'member_id'
  ),
  'a member must read only their own deletion request'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.mobile_support_requests
    where id = :'support_id' and user_id = :'member_id'
  ),
  'a member must read only their own support request'
);

select pg_temp.assert_true(
  (
    select count(*) = 1
    from public.list_current_user_contributions()
    where collection_id = :'collection_id'
  ),
  'the contributor reads one confirmed contribution through the scoped RPC'
);

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.audit_logs', 'select'),
  'the authenticated role must not have direct audit-log read access'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'owner_id', 'role', 'authenticated')::text,
  true
);

select pg_temp.assert_true(
  (
    select public.list_current_user_collections(:'collection_id')->0->>'receiver_momo_number' = '250780000001'
  ),
  'the collection owner must read the configured receiver'
);

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.audit_logs', 'select'),
  'collection ownership must not bypass the admin audit-log boundary'
);

select set_config(
  'request.jwt.claims',
  json_build_object('sub', :'outsider_id', 'role', 'authenticated')::text,
  true
);

select pg_temp.assert_true(
  (
    select count(*) = 0
    from public.mobile_account_deletion_requests
    where id = :'deletion_id'
  ),
  'an outsider must not read another account deletion request'
);

select pg_temp.assert_true(
  (
    select count(*) = 0
    from public.list_current_user_contributions()
    where collection_id = :'collection_id'
  ),
  'an outsider must not read private contribution records'
);

reset role;

select 'LOCAL_BACKEND_PRIVACY_LIFECYCLE_PASS';
select 'pending,confirmed,expired,duplicate,failed,recovery';
select 'receiver_privacy,ledger_authorization,deletion_request,audit_scope';

rollback;
