\set ON_ERROR_STOP on
-- Requires receipt-v2 SQL on an isolated replay or rehearsal clone.
-- Synthetic evidence only; a stored SMS is never provider finality.
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
set local statement_timeout = '30s';
do $$ begin
  if not (
       (current_database() = 'collect_financial_revocation_uat_20260928'
        and current_setting('collect.financial_rehearsal', true) = 'staged-v2')
       or (current_database() = 'postgres'
        and current_setting('collect.local_receipt_uat', true) = 'clean-replay-current')
     )
     or to_regprocedure('public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)') is null
     or exists(select 1 from public.raw_payment_sms)
     or exists(select 1 from public.payments) then
    raise exception 'Isolated staged-v2 receipt rehearsal clone required';
  end if;
end $$;
create temp table test_results(label text primary key);
grant all on pg_temp.test_results to service_role;
create function pg_temp.assert_true(ok boolean,label text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %',label; end if;
  insert into pg_temp.test_results values(label);
end; $$;
create function pg_temp.expect_error(command text,fragment text,label text)
returns void language plpgsql as $$
declare caught text;
begin
  begin execute command; exception when others then caught:=sqlerrm; end;
  perform pg_temp.assert_true(caught is not null and position(fragment in caught)>0,label);
end; $$;

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values ('99700000-0000-4000-8000-000000000001','authenticated','authenticated',
 '250788997001',now(),'{}','{}');
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values('99700000-0000-4000-8000-000000000092','99700000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
update public.profiles set country_code='RW',currency_code='RWF',momo_provider='mtn_momo',momo_number_verified_at=clock_timestamp(),momo_number='0788997001',momo_number_hash=encode(extensions.digest('+250788997001','sha256'),'hex')where id='99700000-0000-4000-8000-000000000001';

insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,
 collection_type,contribution_visibility,allow_anonymous,diaspora_enabled,creation_origin)
values ('99700000-0000-4000-8000-000000000010','receipt-v2-uat',
 '99700000-0000-4000-8000-000000000001','Synthetic receipt UAT',
 'Family / friends','private','private','ikimina','members',false,false,'member_app');
insert into public.collection_members(collection_id,user_id,role,status)
values ('99700000-0000-4000-8000-000000000010',
 '99700000-0000-4000-8000-000000000001','owner','active');
insert into public.collection_receivers(id,collection_id,receiver_user_id,momo_number,
 momo_number_hash,network,label,is_active)
values ('99700000-0000-4000-8000-000000000020',
 '99700000-0000-4000-8000-000000000010',
 '99700000-0000-4000-8000-000000000001','0788997001',encode(extensions.digest('+250788997001','sha256'),'hex'),
 'mtn_momo','Synthetic receiver',true);
insert into public.receiver_mode_consents(id,user_id,enabled,momo_number_hash,build_channel,device_label,created_at)
values ('99700000-0000-4000-8000-000000000030',
 '99700000-0000-4000-8000-000000000001',true,encode(extensions.digest('+250788997001','sha256'),'hex'),
 'android_sms_ingest_attested','synthetic_rehearsal',now());

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.assert_true(public.attested_sms_contract_version()=2,
 'exact receipt-v2 contract is installed');
select pg_temp.fixture_integrity_capability(
 '99700000-0000-4000-8000-000000000001','99700000-0000-4000-8000-000000000092','sms.ingest',repeat('b',64),
 jsonb_build_object('receiver_momo_number_hash',encode(extensions.digest('+250788997001','sha256'),'hex'),
  'client_envelope_id','99700000-0000-4000-8000-000000000040',
  'raw_sender','M-Money',
  'raw_body_sha256',encode(extensions.digest('Synthetic received RWF 1,234. Txn ABCD1234','sha256'),'hex'),
  'received_at_device',null),
 encode(extensions.digest('+250788997001','sha256'),'hex')) as capability_id \gset
select public.accept_attested_receipt_v2(
 :'capability_id'::uuid,'99700000-0000-4000-8000-000000000001',null,
 'M-Money','Synthetic received RWF 1,234. Txn ABCD1234',
 encode(extensions.digest('Synthetic received RWF 1,234. Txn ABCD1234','sha256'),'hex'),
 '99700000-0000-4000-8000-000000000040',encode(extensions.digest('+250788997001','sha256'),'hex'),null
) as ack \gset
select pg_temp.assert_true(
 (:'ack'::jsonb->>'contract_version')::int=2
 and (:'ack'::jsonb->>'stored')::boolean
 and :'ack'::jsonb->>'owner_user_id'='99700000-0000-4000-8000-000000000001'
 and :'ack'::jsonb->>'client_envelope_id'='99700000-0000-4000-8000-000000000040'
 and :'ack'::jsonb->>'body_sha256'=encode(extensions.digest('Synthetic received RWF 1,234. Txn ABCD1234','sha256'),'hex'),
 'ACK binds the exact stored owner, envelope and body');
select pg_temp.assert_true(
 exists(select 1 from public.raw_payment_sms where id=(:'ack'::jsonb->>'raw_sms_id')::uuid
  and receiver_user_id='99700000-0000-4000-8000-000000000001'
  and native_action_capability_id=:'capability_id'::uuid
  and attestation_request_hash=repeat('b',64) and device_attested_at is not null),
 'ACK raw evidence is durable and attested in the same transaction');
select public.accept_attested_receipt_v2(
 :'capability_id'::uuid,'99700000-0000-4000-8000-000000000001',null,
 'M-Money','Synthetic received RWF 1,234. Txn ABCD1234',
 encode(extensions.digest('Synthetic received RWF 1,234. Txn ABCD1234','sha256'),'hex'),
 '99700000-0000-4000-8000-000000000040',encode(extensions.digest('+250788997001','sha256'),'hex'),null
) as replay_ack \gset
select pg_temp.assert_true(:'replay_ack'::jsonb=:'ack'::jsonb,
 'exact committed retry returns the same durable ACK');
select pg_temp.expect_error($q$
 select public.accept_attested_receipt_v2(
  '99700000-0000-4000-8000-000000000040',
  '99700000-0000-4000-8000-000000000001',null,
  'M-Money','Changed synthetic body',
  encode(extensions.digest('Changed synthetic body','sha256'),'hex'),
  '99700000-0000-4000-8000-000000000040',encode(extensions.digest('+250788997001','sha256'),'hex'),null)
$q$,'Receipt binding conflict','changed body cannot reuse an acknowledged envelope');
select public.finalize_attested_payment_sms((:'ack'::jsonb->>'raw_sms_id')::uuid) as finality \gset
select pg_temp.assert_true(
 :'finality'::jsonb->>'status'='awaiting_reconciliation'
 and :'finality'::jsonb->>'evidence_level'='sms_observed'
 and :'finality'::jsonb->>'payment_id' is null,
 'SMS observation never self-confirms financial settlement');
reset role;
select pg_temp.assert_true(
 not exists(select 1 from public.payments)
 and not exists(select 1 from public.ledger_entries)
 and not has_function_privilege('authenticated',
  'public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)','execute')
 and not has_function_privilege('authenticated','public.finalize_attested_payment_sms(uuid)','execute'),
 'SMS-only evidence creates no payment or client finality permission');
select 'RECEIPT_V2_UAT_PASS: '||count(*)||' assertions; synthetic rollback only'
from pg_temp.test_results;
rollback;
