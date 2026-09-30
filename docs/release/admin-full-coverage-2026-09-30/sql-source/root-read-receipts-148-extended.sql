-- Root-only actual read-contract compatibility; never contacts a provider.
begin;
set local lock_timeout='5s';
do $$ begin
 if current_user<>'postgres' or current_database()<>'postgres'
  or current_setting('cron.launch_active_jobs')<>'off'
  or current_setting('pg_net.batch_size')<>'0'
  or (select count(*) from supabase_migrations.schema_migrations)<>148
  or (select max(version) from supabase_migrations.schema_migrations)<>'20260930160000'
  or exists(select 1 from auth.users where id::text like '99690000-%' or phone='250788969001')
  or exists(select 1 from collect_hybrid.member_records where collect_id='996901')
  or exists(select 1 from public.notification_device_tokens) then
  raise exception 'Exact quiet148 fixture with unused synthetic namespace required';end if;
end $$;

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99690000-0000-4000-8000-000000000001','authenticated','authenticated','250788969001',now(),'{}','{}');
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values('99690000-0000-4000-8000-000000000001','+250788969001',now()-interval '2 minutes','Synthetic read-contract fixture authority');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99690000-0000-4000-8000-000000000001',id,'Synthetic read-contract fixture role',now()-interval '1 minute'
from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99690000-0000-4000-8000-000000000011','99690000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal1');

insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,
 collection_type,contribution_visibility,allow_anonymous,diaspora_enabled,creation_origin)
values('99690000-0000-4000-8000-000000000101','synthetic-admin-read-contract',
 '99690000-0000-4000-8000-000000000001','Synthetic read contract group','Family / friends',
 'private','private','ikimina','members',false,false,'admin_assisted');
insert into public.collection_members(collection_id,user_id,role,status)
values('99690000-0000-4000-8000-000000000101','99690000-0000-4000-8000-000000000001','owner','active');
insert into collect_hybrid.member_records(id,collect_id,origin,created_by)
values('99690000-0000-4000-8000-000000000201','996901','admin_assisted','99690000-0000-4000-8000-000000000001');
insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number)
values('99690000-0000-4000-8000-000000000201','Synthetic Member','SYNTHETIC MEMBER','+250788969201');
insert into public.collection_members(collection_id,member_record_id,role,status)
values('99690000-0000-4000-8000-000000000101','99690000-0000-4000-8000-000000000201','member','active');
insert into public.raw_payment_sms(id,collection_id,receiver_user_id,raw_sender,raw_body,body_hash,ingested_at)
values('99690000-0000-4000-8000-000000000301','99690000-0000-4000-8000-000000000101',
 '99690000-0000-4000-8000-000000000001','M-Money','Synthetic private read-contract receipt',
 encode(extensions.digest('Synthetic private read-contract receipt','sha256'),'hex'),now());
insert into public.notification_events(id,user_id,collection_id,type,title,body,deep_link)
values('99690000-0000-4000-8000-000000000401','99690000-0000-4000-8000-000000000001',
 '99690000-0000-4000-8000-000000000101','security_notice','Synthetic notification',
 'Synthetic read-contract body','/groups/synthetic-admin-read-contract');

-- Fixture-only posted payment invokes real immutable balance snapshot triggers.
-- Transport is disabled; the manually seeded receipt is suppressed, not sent.
insert into public.payments(id,collection_id,member_record_id,contributor_public_id,
 receiver_user_id,receiver_momo_number_hash,amount_rwf,transaction_id,provider_network,
 source,status,anonymity_choice,posted_at)
values('99690000-0000-4000-8000-000000000501','99690000-0000-4000-8000-000000000101',
 '99690000-0000-4000-8000-000000000201','996901','99690000-0000-4000-8000-000000000001',
 repeat('a',64),1234,'SYNTHETIC-READ-9969','mtn_momo','manual_admin','posted','public_id',now());
insert into collect_hybrid.sms_notification_outbox(id,payment_id,snapshot_id,collection_id,
 member_record_id,destination_e164,destination_sha256,destination_revision,policy_revision,
 consent_revision,template_key,template_version,amount_rwf,member_balance_rwf,
 group_balance_rwf,reference,state,suppression_reason)
select '99690000-0000-4000-8000-000000000601',s.payment_id,s.id,s.collection_id,s.member_record_id,
 '+250788969201',encode(extensions.digest('+250788969201','sha256'),'hex'),1,1,1,
 'buri_munsi.payment_received',1,1234,s.member_balance_after_rwf,s.group_balance_after_rwf,
 'SYNTHETIC-READ-9969','suppressed','Synthetic fixture; transport disabled'
from collect_hybrid.momo_balance_snapshots s where s.payment_id='99690000-0000-4000-8000-000000000501'
 and not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id=s.payment_id);
select id as read_outbox_id from collect_hybrid.sms_notification_outbox where payment_id='99690000-0000-4000-8000-000000000501' \gset
do $$ begin if not exists(select 1 from collect_hybrid.sms_notification_outbox
 where payment_id='99690000-0000-4000-8000-000000000501' and state='suppressed') then
 raise exception 'Synthetic suppressed receipt was not generated';end if;end $$;

set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1","sub":"99690000-0000-4000-8000-000000000001","session_id":"99690000-0000-4000-8000-000000000011"}',true);
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_current_user','id',null,'value',public.admin_current_user())::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_overview','id',null,'value',public.admin_overview())::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_runtime_config','id',null,'value',public.admin_runtime_config())::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_user','id','99690000-0000-4000-8000-000000000001','value',public.admin_get_user('99690000-0000-4000-8000-000000000001'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_admin_user','id','99690000-0000-4000-8000-000000000001','value',public.admin_get_admin_user('99690000-0000-4000-8000-000000000001'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_collection','id','99690000-0000-4000-8000-000000000101','value',public.admin_get_collection('99690000-0000-4000-8000-000000000101'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_member_record','id','99690000-0000-4000-8000-000000000201','value',public.admin_get_member_record('99690000-0000-4000-8000-000000000201'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_collect_transaction','id','momo:99690000-0000-4000-8000-000000000301','value',public.admin_get_collect_transaction('momo:99690000-0000-4000-8000-000000000301'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_notification','id','99690000-0000-4000-8000-000000000401','value',public.admin_get_notification('99690000-0000-4000-8000-000000000401'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_hybrid_sms_receipt','id',:'read_outbox_id','value',public.admin_get_hybrid_sms_receipt(:'read_outbox_id'::uuid))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_system_health','id','system','value',public.admin_system_health('system'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_user','id','99690000-0000-4000-8000-000000000999','value',public.admin_get_user('99690000-0000-4000-8000-000000000999'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_collection','id','99690000-0000-4000-8000-000000000999','value',public.admin_get_collection('99690000-0000-4000-8000-000000000999'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_notification','id','99690000-0000-4000-8000-000000000999','value',public.admin_get_notification('99690000-0000-4000-8000-000000000999'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_hybrid_sms_receipt','id','99690000-0000-4000-8000-000000000999','value',public.admin_get_hybrid_sms_receipt('99690000-0000-4000-8000-000000000999'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_queue_sla','id','admin_list_collect_reconciliations','value',public.admin_get_queue_sla('admin_list_collect_reconciliations'))::text;
select 'ADMIN_READ_RECEIPT_JSON|'||jsonb_build_object('rpc','admin_get_whatsapp_approval','id','99690000-0000-4000-8000-000000000001','value',public.admin_get_whatsapp_approval('99690000-0000-4000-8000-000000000001'))::text;
reset role;
rollback;
