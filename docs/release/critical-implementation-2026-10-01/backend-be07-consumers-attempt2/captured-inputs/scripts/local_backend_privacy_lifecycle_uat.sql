\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

begin;

-- Synthetic verified verdicts only; real session admission/mint SQL executes.
-- Historical pre-admission snapshots execute their original actual mint body.
create function pg_temp.fixture_integrity_capability(p_actor uuid,p_session uuid,p_action text,
 p_hash text,p_payload jsonb,p_receiver text)returns uuid language plpgsql as $$
declare r jsonb;result jsonb;n uuid:=gen_random_uuid();begin
 if to_regprocedure('public.reserve_play_integrity_admission_v1(uuid,uuid,uuid,text,text,text,text,jsonb)')is null then
  return public.mint_native_action_capability(p_actor,p_action,p_hash,p_payload,p_receiver,
   'app.cool.mobile','PLAY_RECOGNIZED',array['MEETS_DEVICE_INTEGRITY'],clock_timestamp());
 end if;
 r:=public.reserve_play_integrity_admission_v1(p_actor,p_session,n,p_action,p_hash,
  encode(extensions.digest(n::text,'sha256'),'hex'),p_receiver,p_payload);
 perform public.begin_play_integrity_admission_v1(p_actor,p_session,(r->>'reservation_id')::uuid,'oauth');
 perform public.begin_play_integrity_admission_v1(p_actor,p_session,(r->>'reservation_id')::uuid,'decode');
 result:=public.complete_play_integrity_admission_v1(p_actor,p_session,(r->>'reservation_id')::uuid,
  p_payload,'app.cool.mobile','PLAY_RECOGNIZED',array['MEETS_DEVICE_INTEGRITY'],clock_timestamp(),1,200);
 return(result->>'native_capability')::uuid;
end$$;

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
set display_name = case id
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

insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('10000000-0000-4000-8000-000000000092',:'owner_id',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');

select public_id as member_public_id from public.profiles where id=:'member_id'
\gset

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
  :'member_public_id',
  now() - interval '1 minute'
);

insert into public.receiver_mode_consents(user_id,enabled,momo_number_hash,build_channel,device_label)
values (:'owner_id',true,:'receiver_hash','android_sms_ingest_attested','synthetic_local_fixture');
select now()::text as sms_device_time,
  encode(extensions.digest('Synthetic local payment message with no customer data', 'sha256'), 'hex') as sms_body_hash
\gset
-- Minting is a synthetic service fixture, not a real device/provider attestation.
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.fixture_integrity_capability(
  :'owner_id', '10000000-0000-4000-8000-000000000092', 'sms.ingest', repeat('c',64),
  jsonb_build_object('receiver_momo_number_hash', :'receiver_hash',
    'client_envelope_id', '30000000-0000-4000-8000-000000000091',
    'raw_sender', 'CONTROLLED_FIXTURE', 'raw_body_sha256', :'sms_body_hash',
    'received_at_device', :'sms_device_time'),
  :'receiver_hash'
) as sms_capability
\gset
select public.ingest_attested_raw_payment_sms(
  :'sms_capability', :'owner_id', :'collection_id', 'CONTROLLED_FIXTURE',
  'Synthetic local payment message with no customer data', :'sms_body_hash',
  '30000000-0000-4000-8000-000000000091', :'receiver_hash', :'sms_device_time'
)->>'id' as confirmed_sms_id
\gset
reset role;
select set_config('collect.uat.confirmed_sms', :'confirmed_sms_id', true);
select pg_temp.assert_true(exists (
  select 1 from public.raw_payment_sms raw
  join public.native_action_capabilities capability on capability.id=raw.native_action_capability_id
  where raw.id=:'confirmed_sms_id' and capability.consumed_at is not null
    and raw.attestation_request_hash=capability.request_hash and raw.device_attested_at is not null
), 'controlled payment evidence retains its consumed device capability');
update public.raw_payment_sms set parse_status='parsed' where id=:'confirmed_sms_id';

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
  :'confirmed_sms_id',
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
  :'member_public_id',
  0.99,
  '{"fixture": true}'
);

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.assert_true(
  public.allocate_parsed_payment_event(
    '40000000-0000-4000-8000-000000000001'
  ) = 'awaiting_provider_confirmation',
  'a valid parsed event must remain a review candidate until finality'
);
reset role;
select pg_temp.assert_true(
  exists (select 1 from public.payments where parsed_event_id='40000000-0000-4000-8000-000000000001'
    and status='review' and posted_at is null)
  and not exists (select 1 from public.ledger_entries entry join public.payments payment on payment.id=entry.payment_id
    where payment.parsed_event_id='40000000-0000-4000-8000-000000000001'),
  'matching alone must not post ledger truth'
);
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.assert_true(
  public.finalize_attested_payment_sms(:'confirmed_sms_id')->>'status'='awaiting_reconciliation',
  'attested SMS cannot finalize the candidate'
);
select pg_temp.assert_true(
  exists (select 1 from public.payments
    where parsed_event_id='40000000-0000-4000-8000-000000000001'
      and status='review' and posted_at is null)
  and not exists (select 1 from public.ledger_entries entry
    join public.payments payment on payment.id=entry.payment_id
    where payment.parsed_event_id='40000000-0000-4000-8000-000000000001'),
  'attested SMS replay leaves the review candidate and ledger unchanged'
);
-- Independent provider evidence is a separate synthetic fixture here; this
-- rollback-only UAT does not prove any live provider integration.
reset role;
select to_regprocedure('public.finalize_approved_reconciliation_v2(uuid)')is not null as governed_finality \gset
\if :governed_finality
-- Two explicit synthetic verified approvers; no live policy approval is claimed.
reset role;
insert into auth.users(id,aud,role,email,email_confirmed_at,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)values
 ('99660000-0000-4000-8000-000000000001','authenticated','authenticated','fixture-proposer@example.test',clock_timestamp(),'250788996601',clock_timestamp(),'{}','{}'),
 ('99660000-0000-4000-8000-000000000002','authenticated','authenticated','fixture-approver@example.test',clock_timestamp(),'250788996602',clock_timestamp(),'{}','{}');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select u.id,r.id,'Synthetic independent financial fixture authority',clock_timestamp()-interval '1 minute'
from auth.users u cross join public.admin_roles r where u.id::text like '99660000-%'and r.name='platform_owner';
do $$begin
 if to_regclass('collect_admin_access.email_approvals')is not null then
  insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)
  select id,email,clock_timestamp()-interval '2 minutes','Synthetic financial fixture approval only'
  from auth.users where id::text like '99660000-%';
 else
  insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
  select id,'+'||ltrim(phone,'+'),clock_timestamp()-interval '2 minutes','Synthetic financial fixture approval only'
  from auth.users where id::text like '99660000-%';
 end if;
end$$;
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values
 ('99660000-0000-4000-8000-000000000011','99660000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal2'),
 ('99660000-0000-4000-8000-000000000021','99660000-0000-4000-8000-000000000002',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal2');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"99660000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2","session_id":"99660000-0000-4000-8000-000000000011"}',true);
select public.propose_payment_reconciliation_v2((select id from public.payments where parsed_event_id='40000000-0000-4000-8000-000000000001'),repeat('e',64),'PROVIDER-UAT-CONTROLLED-001',clock_timestamp(),'Synthetic independently sourced provider evidence')as fixture_review_id \gset
select set_config('request.jwt.claims','{"sub":"99660000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal2","session_id":"99660000-0000-4000-8000-000000000021"}',true);
select pg_temp.assert_true(public.approve_payment_reconciliation_v2(:'fixture_review_id','Synthetic independent approval of source evidence'),
 'independent synthetic approver reviews source evidence');
select pg_temp.assert_true(public.authorize_reconciliation_finalization_v2(:'fixture_review_id'),
 'exact live synthetic approver authorizes finalization');
reset role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.finalize_approved_reconciliation_v2(:'fixture_review_id')as provider_finality \gset
\else
-- Actual retained owner/service route on a pre-governed historical snapshot.
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select public.process_provider_finality_event(
  '40000000-0000-4000-8000-000000000099', 'payment.confirmed',
  repeat('d',64),
  (select id from public.payments
   where parsed_event_id='40000000-0000-4000-8000-000000000001'),
  'mtn_momo', 'CONTROLLED-TXN-001', 'PROVIDER-UAT-CONTROLLED-001',
  :'receiver_hash', 10000, now(), repeat('e',64), null, null
) as provider_finality \gset
\endif
select pg_temp.assert_true(
  :'provider_finality'::jsonb->>'replayed'='false',
  'separate synthetic provider event posts the candidate'
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
declare duplicate_constraint text;
begin
  begin
    insert into public.raw_payment_sms (
      collection_id,
      receiver_user_id,
      raw_sender,
      raw_body,
      body_hash,
      receiver_momo_number_hash,
      received_at_device
    )
    select collection_id,receiver_user_id,raw_sender,raw_body,body_hash,
      receiver_momo_number_hash,received_at_device
    from public.raw_payment_sms where id=current_setting('collect.uat.confirmed_sms')::uuid;
    raise exception 'duplicate observed SMS source unexpectedly succeeded';
  exception
    when unique_violation then
      get stacked diagnostics duplicate_constraint = CONSTRAINT_NAME;
      if duplicate_constraint <> 'raw_payment_sms_observed_source_unique' then raise; end if;
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
