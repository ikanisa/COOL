\set ON_ERROR_STOP on
-- Only the network-none runner-owned current-migration target may run this.
-- Every synthetic fixture and assertion below rolls back; no carrier is called.
begin;
set local statement_timeout='30s';
set local lock_timeout='5s';
do $$begin
 if current_database()<>'postgres' or current_setting('collect.assisted_sms_qa',true)is distinct from 'isolated_clone'
  or to_regprocedure('public.collect_worker_heartbeat_v2(uuid,uuid,text,uuid,text,jsonb)')is null
  or exists(select 1 from auth.users where id::text like '99440000-%') then
  raise exception 'Verified fresh task-owned current migration fixture required';end if;
end$$;
create temp table assisted_results(label text primary key);
create temp table assisted_values(name text primary key,value jsonb);
grant all on assisted_results,assisted_values to service_role,authenticated,anon;
do $$begin execute format('grant usage on schema %I to service_role,authenticated,anon',pg_my_temp_schema()::regnamespace);end$$;
create function pg_temp.assisted_assert(ok boolean,label text)returns void language plpgsql as $$begin
 if ok is not true then raise exception 'FAIL: %',label;end if;
 insert into pg_temp.assisted_results values(label);end$$;
create function pg_temp.assisted_snapshot()returns jsonb language plpgsql security definer set search_path=''as $$
declare result jsonb:='{}';relation text;body jsonb;begin
 foreach relation in array array['collect_hybrid.sms_operator_heartbeats','collect_hybrid.sms_notification_outbox',
  'collect_hybrid.sms_notification_claim_requests','collect_hybrid.sms_notification_confirmations',
  'collect_hybrid.sms_notification_attempts','collect_security.assisted_sms_session_evidence','public.audit_logs']loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text),''[]'')from %s t',relation::regclass)into body;
  result:=result||jsonb_build_object(relation,body);end loop;return result;end$$;
create function pg_temp.assisted_deny(command text,state text,label text)returns void language plpgsql as $$
declare caught text;before_rows jsonb:=pg_temp.assisted_snapshot();begin
 begin execute command;exception when others then get stacked diagnostics caught=returned_sqlstate;end;
 perform pg_temp.assisted_assert(caught=state,label);
 perform pg_temp.assisted_assert(before_rows=pg_temp.assisted_snapshot(),label||' has no receipt/audit write');end$$;

insert into auth.users(id,aud,role,email,email_confirmed_at,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)values
 ('99440000-0000-4000-8000-000000000001','authenticated','authenticated','assisted-owner@example.test',clock_timestamp(),'250788994401',clock_timestamp(),'{}','{}'),
 ('99440000-0000-4000-8000-000000000002','authenticated','authenticated','assisted-weak@example.test',clock_timestamp(),'250788994402',clock_timestamp(),'{}','{}');
update public.profiles set country_code='RW',currency_code='RWF',momo_number='0788994401',
 momo_number_hash=encode(extensions.digest('+250788994401','sha256'),'hex'),momo_provider='mtn_momo',momo_number_verified_at=clock_timestamp()
where id='99440000-0000-4000-8000-000000000001';
insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values
 ('99440000-0000-4000-8000-000000000001','assisted-owner@example.test',clock_timestamp()-interval '2 minutes','Synthetic assisted owner approval'),
 ('99440000-0000-4000-8000-000000000002','assisted-weak@example.test',clock_timestamp()-interval '2 minutes','Synthetic weak-role approval');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99440000-0000-4000-8000-000000000001',id,'Synthetic assisted owner grant',clock_timestamp()-interval '1 minute'
from public.admin_roles where name='platform_owner';
insert into public.admin_roles(name,description)values('assisted_weak_qa','Synthetic unsupported role with notification permissions');
insert into public.admin_role_permissions(role_id,permission_name)
select id,p from public.admin_roles cross join unnest(array['notifications.read','notifications.manage'])p where name='assisted_weak_qa';
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99440000-0000-4000-8000-000000000002',id,'Synthetic unsupported role grant',clock_timestamp()-interval '1 minute'
from public.admin_roles where name='assisted_weak_qa';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values
 ('99440000-0000-4000-8000-000000000011','99440000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
 ('99440000-0000-4000-8000-000000000012','99440000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'),
 ('99440000-0000-4000-8000-000000000013','99440000-0000-4000-8000-000000000002',clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');

do $$declare r record;begin
 for r in select p.oid::regprocedure signature,p.proname name from pg_proc p where p.pronamespace='public'::regnamespace
  and p.proname in('collect_notification_health','collect_list_pending_receipts','collect_claim_receipt','collect_get_claimed_receipt',
   'collect_confirm_receipt','collect_record_send_start','collect_record_observed_outcome','collect_release_unsent_claim','collect_worker_heartbeat')loop
  perform pg_temp.assisted_assert(not has_function_privilege('service_role',r.signature,'EXECUTE')
   and not has_function_privilege('authenticated',r.signature,'EXECUTE')and not has_function_privilege('anon',r.signature,'EXECUTE'),
   r.name||' sessionless API revoked');end loop;
 for r in select p.oid::regprocedure signature,p.proname name from pg_proc p where p.pronamespace='public'::regnamespace
  and p.proname in('collect_notification_health_v2','collect_list_pending_receipts_v2','collect_claim_receipt_v2','collect_get_claimed_receipt_v2',
   'collect_confirm_receipt_v2','collect_record_send_start_v2','collect_record_observed_outcome_v2','collect_release_unsent_claim_v2','collect_worker_heartbeat_v2')loop
  perform pg_temp.assisted_assert(has_function_privilege('service_role',r.signature,'EXECUTE')
   and not has_function_privilege('authenticated',r.signature,'EXECUTE')and not has_function_privilege('anon',r.signature,'EXECUTE'),
   r.name||' exact service-only API');end loop;
end$$;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.assisted_assert(public.collect_notification_health_v2('99440000-0000-4000-8000-000000000001','99440000-0000-4000-8000-000000000011')is not null,'approved live exact originating session can read health');
select pg_temp.assisted_assert(jsonb_typeof(public.collect_list_pending_receipts_v2('99440000-0000-4000-8000-000000000001','99440000-0000-4000-8000-000000000011'))='array','approved live originating session can read masked queue');
select pg_temp.assisted_assert(public.collect_worker_heartbeat_v2('99440000-0000-4000-8000-000000000001','99440000-0000-4000-8000-000000000011','assisted-qa','99440000-0000-4000-8000-000000000031','no_send','{}')->>'ok'='true','approved live originating session can mutate heartbeat');
select pg_temp.assisted_deny('select public.collect_notification_health_v2(''99440000-0000-4000-8000-000000000001'',''99440000-0000-4000-8000-000000000013'')','42501','other actor session cannot authorize owner');
select pg_temp.assisted_deny('select public.collect_notification_health_v2(''99440000-0000-4000-8000-000000000002'',''99440000-0000-4000-8000-000000000013'')','42501','notification permissions on unsupported role do not confer owner authority');
select pg_temp.assisted_deny('select public.collect_notification_health_v2(''99440000-0000-4000-8000-000000000001'',null)','42501','missing originating session denied');
reset role;

-- Actual current healthy receipt bridge. The installer creates two synthetic
-- canonical jobs through the retained financial API; every operator action
-- below executes its real public v2/legacy implementation as service_role.
-- No transport is called. Roll back the complete seed before deletion cases.
savepoint positive_pipeline;
update public.feature_flags set enabled=true where key='hybrid_sms_notifications';
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type,
 contribution_visibility,allow_anonymous,diaspora_enabled,creation_origin)
values('99440000-0000-4000-8000-000000000071','assisted-session-positive-qa','99440000-0000-4000-8000-000000000001',
 'Synthetic assisted session bridge','Family / friends','private','private','ikimina','members',false,false,'admin_assisted');
insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network)
values('99440000-0000-4000-8000-000000000071','99440000-0000-4000-8000-000000000001','+250788994401',
 encode(extensions.digest('+250788994401','sha256'),'hex'),'mtn_momo');
insert into collect_hybrid.member_records(id,collect_id,origin,created_by)
values('99440000-0000-4000-8000-000000000072','994410','admin_assisted','99440000-0000-4000-8000-000000000001');
insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number)
values('99440000-0000-4000-8000-000000000072','Synthetic standalone bridge member','SYNTHETIC MEMBER','+250788994410');
insert into public.collection_members(collection_id,member_record_id,role,status)
values('99440000-0000-4000-8000-000000000071','99440000-0000-4000-8000-000000000072','member','active');
insert into collect_hybrid.sms_receipt_policies(collection_id,enabled,reason,updated_by)
values('99440000-0000-4000-8000-000000000071',true,'Synthetic bridge policy only','99440000-0000-4000-8000-000000000001');
insert into collect_hybrid.sms_receipt_member_consents(member_record_id,enabled,capture_method,reason,recorded_by)
values('99440000-0000-4000-8000-000000000072',true,'written','Synthetic bridge consent only','99440000-0000-4000-8000-000000000001');
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.payments(id,collection_id,member_record_id,receiver_user_id,receiver_momo_number_hash,
 amount_rwf,transaction_id,provider_network,source,status,posted_at)
select payment,'99440000-0000-4000-8000-000000000071','99440000-0000-4000-8000-000000000072',
 '99440000-0000-4000-8000-000000000001',encode(extensions.digest('+250788994401','sha256'),'hex'),
 100,reference,'mtn_momo','manual_admin','review',null
from(values('99440000-0000-4000-8000-000000000081'::uuid,'BRIDGE-POSITIVE-1'),
 ('99440000-0000-4000-8000-000000000082'::uuid,'BRIDGE-POSITIVE-2'))p(payment,reference);
select public.confirm_provider_payment(payment,'mtn_momo',reference,'SYNTHETIC-CONF-'||reference,
 encode(extensions.digest('+250788994401','sha256'),'hex'),100,clock_timestamp(),repeat('c',64))
from(values('99440000-0000-4000-8000-000000000081'::uuid,'BRIDGE-POSITIVE-1'),
 ('99440000-0000-4000-8000-000000000082'::uuid,'BRIDGE-POSITIVE-2'))p(payment,reference);
insert into assisted_values select 'positive_job1',to_jsonb(o)from collect_hybrid.sms_notification_outbox o
 where payment_id='99440000-0000-4000-8000-000000000081';
insert into assisted_values select 'positive_job2',to_jsonb(o)from collect_hybrid.sms_notification_outbox o
 where payment_id='99440000-0000-4000-8000-000000000082';
select pg_temp.assisted_assert((select count(*)=2 from assisted_values where name like 'positive_job%'),
 'canonical synthetic setup produces two valid actual content2 jobs');
set local role service_role;
do $$declare actor constant uuid:='99440000-0000-4000-8000-000000000001';sid constant uuid:='99440000-0000-4000-8000-000000000011';
 other_sid constant uuid:='99440000-0000-4000-8000-000000000012';
 job jsonb;job2 jsonb;claim jsonb;claim2 jsonb;content jsonb;confirmation jsonb;started jsonb;outcome jsonb;replayed jsonb;
 request constant uuid:='99440000-0000-4000-8000-000000000091';confirm_id constant uuid:='99440000-0000-4000-8000-000000000092';
 fresh_sid constant uuid:='99440000-0000-4000-8000-000000000014';
begin
 select value into job from pg_temp.assisted_values where name='positive_job1';
 select value into job2 from pg_temp.assisted_values where name='positive_job2';
 claim:=public.collect_claim_receipt_v2(actor,sid,(job->>'id')::uuid,'assisted-positive',request);
 perform pg_temp.assisted_assert(claim->>'ok'='true'and claim->>'replay'='false','healthy exact session claims actual content2 job');
 replayed:=public.collect_claim_receipt_v2(actor,sid,(job->>'id')::uuid,'assisted-positive',request);
 perform pg_temp.assisted_assert(replayed->>'replay'='true'and replayed->>'claim_token'=claim->>'claim_token'
  and replayed->>'fence_version'=claim->>'fence_version','same originating session claim replay retains exact capability');
 perform pg_temp.assisted_deny(format('select public.collect_claim_receipt_v2(%L,%L,%L,%L,%L)',
  actor,other_sid,job->>'id','assisted-positive',request),'42501','another live session cannot replay original claim request');
 perform pg_temp.assisted_deny(format('select public.collect_claim_receipt_v2(%L,%L,%L,%L,%L)',
  actor,sid,job2->>'id','assisted-positive',request),'P0001','claim idempotency key cannot change job');
 content:=public.collect_get_claimed_receipt_v2(actor,sid,(job->>'id')::uuid,(claim->>'claim_token')::uuid,(claim->>'fence_version')::integer);
 perform pg_temp.assisted_assert(content->>'message_body'=job->>'message_body'and content->>'body_sha256'=job->>'body_sha256',
  'healthy original session retrieves exact server-rendered immutable content');
 -- An independently live replacement session is not the originating session
 -- of this claim. It must never inherit the original capability.
 perform pg_temp.assisted_deny(format('select public.collect_get_claimed_receipt_v2(%L,%L,%L,%L,%s)',
  actor,other_sid,job->>'id',claim->>'claim_token',claim->>'fence_version'),'42501','replacement session cannot inherit old claim capability');
 confirmation:=public.collect_confirm_receipt_v2(actor,sid,(job->>'id')::uuid,(claim->>'claim_token')::uuid,
  (claim->>'fence_version')::integer,(job->>'destination_revision')::integer,job->>'body_sha256',confirm_id);
 perform pg_temp.assisted_assert(confirmation->>'ok'='true'and confirmation->>'replay'='false','healthy original session confirms exact content');
 perform pg_temp.assisted_deny(format('select public.collect_confirm_receipt_v2(%L,%L,%L,%L,%s,%s,%L,%L)',actor,other_sid,
  job->>'id',claim->>'claim_token',claim->>'fence_version',job->>'destination_revision',job->>'body_sha256',confirm_id),
  '42501','another live session cannot reuse original confirmation');
 replayed:=public.collect_confirm_receipt_v2(actor,sid,(job->>'id')::uuid,(claim->>'claim_token')::uuid,
  (claim->>'fence_version')::integer,(job->>'destination_revision')::integer,job->>'body_sha256',confirm_id);
 perform pg_temp.assisted_assert(replayed->>'replay'='true'and replayed->>'confirmation_id'=confirm_id::text,'same originating confirmation replay is bounded and stable');
 perform pg_temp.assisted_deny(format('select public.collect_confirm_receipt_v2(%L,%L,%L,%L,%s,%s,%L,%L)',actor,sid,
  job->>'id',claim->>'claim_token',claim->>'fence_version',job->>'destination_revision',repeat('f',64),confirm_id),
  'P0001','confirmation replay rejects changed body hash');
 perform pg_temp.assisted_deny(format('select public.collect_record_send_start_v2(%L,%L,%L,%L,%s,%L)',actor,other_sid,
  job->>'id',claim->>'claim_token',claim->>'fence_version',confirm_id),'42501','another live session cannot consume original confirmation');
 started:=public.collect_record_send_start_v2(actor,sid,(job->>'id')::uuid,(claim->>'claim_token')::uuid,
  (claim->>'fence_version')::integer,confirm_id);
 perform pg_temp.assisted_assert(started->>'state'='send_started'and started->>'replay'='false','healthy original session records actual local pre-send state');
 replayed:=public.collect_record_send_start_v2(actor,sid,(job->>'id')::uuid,(claim->>'claim_token')::uuid,
  (claim->>'fence_version')::integer,confirm_id);
 perform pg_temp.assisted_assert(replayed->>'replay'='true'and replayed->>'attempt_id'=started->>'attempt_id','same originating send-start replay never allocates another attempt');
 perform pg_temp.assisted_deny(format('select public.collect_record_observed_outcome_v2(%L,%L,%L,%L,%L,%L)',actor,other_sid,
  started->>'attempt_id','uncertain','Synthetic local-only handoff observation','No carrier or network transmission occurred'),
  '42501','another live session cannot inherit old attempt capability');
 perform pg_temp.assisted_deny(format('select public.collect_record_observed_outcome_v2(%L,%L,%L,%L,%L,%L)',actor,sid,
  started->>'attempt_id','uncertain',repeat('x',501),'Synthetic no-provider fixture'),
  'P0001','outcome evidence remains bounded to500 characters');
 outcome:=public.collect_record_observed_outcome_v2(actor,sid,(started->>'attempt_id')::uuid,'uncertain',
  'Synthetic local-only handoff observation','No carrier or network transmission occurred');
 perform pg_temp.assisted_assert(outcome->>'state'='uncertain'and outcome->>'replay'='false','healthy original session records actual bounded observed outcome');
 replayed:=public.collect_record_observed_outcome_v2(actor,sid,(started->>'attempt_id')::uuid,'uncertain',
  'Synthetic local-only handoff observation','No carrier or network transmission occurred');
 perform pg_temp.assisted_assert(replayed->>'replay'='true'and replayed->>'attempt_id'=started->>'attempt_id','same originating outcome replay preserves one attempt');
 claim2:=public.collect_claim_receipt_v2(actor,sid,(job2->>'id')::uuid,'assisted-positive','99440000-0000-4000-8000-000000000093');
 perform pg_temp.assisted_deny(format('select public.collect_release_unsent_claim_v2(%L,%L,%L,%L,%s,%L)',actor,other_sid,
  job2->>'id',claim2->>'claim_token',claim2->>'fence_version','Synthetic verified no-send claim release'),
  '42501','another live session cannot release original claim');
 perform pg_temp.assisted_deny(format('select public.collect_release_unsent_claim_v2(%L,%L,%L,%L,%s,%L)',actor,sid,
  job2->>'id',claim2->>'claim_token',claim2->>'fence_version',repeat('x',501)),'P0001','release reason remains bounded to500 characters');
 replayed:=public.collect_release_unsent_claim_v2(actor,sid,(job2->>'id')::uuid,(claim2->>'claim_token')::uuid,
  (claim2->>'fence_version')::integer,'Synthetic verified no-send claim release');
 perform pg_temp.assisted_assert(replayed->>'ok'='true'and replayed->>'state'='queued','healthy original session releases actual safely unsent claim');
 insert into pg_temp.assisted_values values('positive_claim',claim),('positive_confirmation',confirmation),('positive_started',started);
 -- Fixture installer only: simulate logout and a genuinely fresh same-user
 -- session without granting service_role direct Auth writes.
 execute 'reset role';
 delete from auth.sessions where id=sid;
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
 values(fresh_sid,actor,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1');
 execute 'set local role service_role';
 perform pg_temp.assisted_deny(format('select public.collect_get_claimed_receipt_v2(%L,%L,%L,%L,%s)',
  actor,fresh_sid,job->>'id',claim->>'claim_token',claim->>'fence_version'),'42501','logout then fresh same-user session cannot inherit old claim');
 perform pg_temp.assisted_deny(format('select public.collect_confirm_receipt_v2(%L,%L,%L,%L,%s,%s,%L,%L)',actor,fresh_sid,
  job->>'id',claim->>'claim_token',claim->>'fence_version',job->>'destination_revision',job->>'body_sha256',confirm_id),
  '42501','logout then fresh same-user session cannot inherit old confirmation');
 perform pg_temp.assisted_deny(format('select public.collect_record_send_start_v2(%L,%L,%L,%L,%s,%L)',actor,fresh_sid,
  job->>'id',claim->>'claim_token',claim->>'fence_version',confirm_id),'42501','logout then fresh same-user session cannot replay old send-start');
 perform pg_temp.assisted_deny(format('select public.collect_record_observed_outcome_v2(%L,%L,%L,%L,%L,%L)',actor,fresh_sid,
  started->>'attempt_id','uncertain','Synthetic local-only handoff observation','No carrier or network transmission occurred'),
  '42501','logout then fresh same-user session cannot inherit old attempt');
 claim2:=public.collect_claim_receipt_v2(actor,fresh_sid,(job2->>'id')::uuid,'assisted-positive','99440000-0000-4000-8000-000000000094');
 perform pg_temp.assisted_assert(claim2->>'ok'='true','fresh approved session can claim queued work using a new capability');
 content:=public.collect_get_claimed_receipt_v2(actor,fresh_sid,(job2->>'id')::uuid,(claim2->>'claim_token')::uuid,(claim2->>'fence_version')::integer);
 perform pg_temp.assisted_assert(content->>'message_body'=job2->>'message_body','fresh approved session reads only its new exact capability');
 replayed:=public.collect_release_unsent_claim_v2(actor,fresh_sid,(job2->>'id')::uuid,(claim2->>'claim_token')::uuid,
  (claim2->>'fence_version')::integer,'Synthetic fresh session verified no-send release');
 perform pg_temp.assisted_assert(replayed->>'state'='queued','fresh approved session can safely release its own claim');
 -- Model retained pre-fence rows via actual legacy functions as the fixture
 -- installer only. No service-role legacy grant or mutation stub is added.
 execute 'reset role';
 claim2:=public.collect_claim_receipt(actor,(job2->>'id')::uuid,'assisted-legacy-qa','99440000-0000-4000-8000-000000000095');
 execute 'set local role service_role';
 perform pg_temp.assisted_deny(format('select public.collect_get_claimed_receipt_v2(%L,%L,%L,%L,%s)',actor,fresh_sid,
  job2->>'id',claim2->>'claim_token',claim2->>'fence_version'),'42501','unbound legacy claim is preserved and fails closed');
 execute 'reset role';
 confirmation:=public.collect_confirm_receipt(actor,(job2->>'id')::uuid,(claim2->>'claim_token')::uuid,
  (claim2->>'fence_version')::integer,(job2->>'destination_revision')::integer,job2->>'body_sha256','99440000-0000-4000-8000-000000000096');
 started:=public.collect_record_send_start(actor,(job2->>'id')::uuid,(claim2->>'claim_token')::uuid,
  (claim2->>'fence_version')::integer,'99440000-0000-4000-8000-000000000096');
 execute 'set local role service_role';
 perform pg_temp.assisted_deny(format('select public.collect_record_send_start_v2(%L,%L,%L,%L,%s,%L)',actor,fresh_sid,
  job2->>'id',claim2->>'claim_token',claim2->>'fence_version','99440000-0000-4000-8000-000000000096'),
  '42501','unbound legacy confirmation cannot be adopted by a fresh session');
 perform pg_temp.assisted_deny(format('select public.collect_record_observed_outcome_v2(%L,%L,%L,%L,%L,%L)',actor,fresh_sid,
  started->>'attempt_id','uncertain','Synthetic old no-provider handoff','Fixture has no real carrier outcome'),
  '42501','unbound legacy attempt retained without outcome rewrite');
end$$;
reset role;
select pg_temp.assisted_assert(exists(select 1 from public.audit_logs where action='notification.sms.session_fenced'
 and metadata->>'operation'='collect_confirm_receipt_v2'and metadata->>'originating_session_id'='99440000-0000-4000-8000-000000000011')
 and exists(select 1 from public.audit_logs where action='notification.sms.session_fenced'
 and metadata->>'operation'='collect_record_send_start_v2'and metadata->>'originating_session_id'='99440000-0000-4000-8000-000000000011'),
 'confirm and send-start audit retain exact originating session');
select pg_temp.assisted_assert(exists(select 1 from collect_security.assisted_sms_session_evidence
 where capability_kind='confirmation'and capability_id='99440000-0000-4000-8000-000000000092'
 and originating_session_id='99440000-0000-4000-8000-000000000011'and operator_user_id='99440000-0000-4000-8000-000000000001')
 and exists(select 1 from collect_security.assisted_sms_session_evidence e join assisted_values v
 on v.name='positive_started'and e.capability_id=(v.value->>'attempt_id')::uuid
 where e.capability_kind='attempt'and e.originating_session_id='99440000-0000-4000-8000-000000000011'
 and e.body_sha256=(select value->>'body_sha256'from assisted_values where name='positive_job1')),
 'private immutable confirmation and send-start audit retain original session after logout');
select pg_temp.assisted_deny('update collect_security.assisted_sms_session_evidence set originating_session_id=gen_random_uuid()',
 '55000','immutable originating evidence cannot be rewritten even by normal installer DML');
select pg_temp.assisted_deny('delete from collect_security.assisted_sms_session_evidence',
 '55000','immutable originating evidence cannot be deleted');
select pg_temp.assisted_deny('truncate collect_security.assisted_sms_session_evidence',
 '55000','immutable originating evidence cannot be truncated');
set local role service_role;
select pg_temp.assisted_deny('select * from collect_security.assisted_sms_session_evidence',
 '42501','service role cannot directly read private originating evidence');
select pg_temp.assisted_deny('insert into collect_security.assisted_sms_session_evidence(capability_kind,capability_id,operator_user_id,originating_session_id,outbox_id)values(''claim_request'',gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid())',
 '42501','service role cannot directly forge private originating evidence');
reset role;
do $$begin raise notice 'ASSISTED_POSITIVE_PIPELINE=PASS';end$$;
rollback to positive_pipeline;

create temp table assisted_calls(expression text primary key);
insert into assisted_calls values
 ('public.collect_notification_health_v2(''99440000-0000-4000-8000-000000000001'',''99440000-0000-4000-8000-000000000011'')'),
 ('public.collect_list_pending_receipts_v2(''99440000-0000-4000-8000-000000000001'',''99440000-0000-4000-8000-000000000011'')'),
 ('public.collect_claim_receipt_v2(''99440000-0000-4000-8000-000000000001'',''99440000-0000-4000-8000-000000000011'',null,''worker-qa'',null)'),
 ('public.collect_get_claimed_receipt_v2(''99440000-0000-4000-8000-000000000001'',''99440000-0000-4000-8000-000000000011'',null,null,1)'),
 ('public.collect_confirm_receipt_v2(''99440000-0000-4000-8000-000000000001'',''99440000-0000-4000-8000-000000000011'',null,null,1,1,repeat(''a'',64),null)'),
 ('public.collect_record_send_start_v2(''99440000-0000-4000-8000-000000000001'',''99440000-0000-4000-8000-000000000011'',null,null,1,null)'),
 ('public.collect_record_observed_outcome_v2(''99440000-0000-4000-8000-000000000001'',''99440000-0000-4000-8000-000000000011'',null,''failed_no_send'',''synthetic-evidence'',null)'),
 ('public.collect_release_unsent_claim_v2(''99440000-0000-4000-8000-000000000001'',''99440000-0000-4000-8000-000000000011'',null,null,1,''Synthetic safely unsent release'')'),
 ('public.collect_worker_heartbeat_v2(''99440000-0000-4000-8000-000000000001'',''99440000-0000-4000-8000-000000000011'',''assisted-qa'',gen_random_uuid(),''no_send'',''{}'')');
grant select on assisted_calls to service_role;
savepoint original_session;
delete from auth.sessions where id='99440000-0000-4000-8000-000000000011';
set local role service_role;
do $$declare c record;begin for c in select expression from pg_temp.assisted_calls loop
 perform pg_temp.assisted_deny('select '||c.expression,'42501','logout denies '||split_part(c.expression,'(',1));end loop;end$$;
do $$begin raise notice 'ASSISTED_LOGOUT_CASES=9';end$$;
reset role;
rollback to original_session;
select pg_temp.assisted_assert(exists(select 1 from auth.sessions where id='99440000-0000-4000-8000-000000000012'),'other active session survives but never replaces revoked originating session');

do $$declare mutation text;c record;begin
 foreach mutation in array array[
  'update auth.sessions set not_after=clock_timestamp()-interval ''1 second'' where id=''99440000-0000-4000-8000-000000000011''',
  'update auth.users set deleted_at=clock_timestamp()where id=''99440000-0000-4000-8000-000000000001''',
  -- This fixture's disposable heartbeat retains its operator FK in production.
  -- Remove only that synthetic row inside this rollback-only deletion case.
  'delete from collect_hybrid.sms_operator_heartbeats where operator_user_id=''99440000-0000-4000-8000-000000000001'';delete from auth.users where id=''99440000-0000-4000-8000-000000000001''',
  'update public.admin_user_roles set revoked_at=clock_timestamp()where user_id=''99440000-0000-4000-8000-000000000001''',
  'update collect_admin_access.email_approvals set revoked_at=clock_timestamp()where user_id=''99440000-0000-4000-8000-000000000001''',
  'delete from public.admin_role_permissions where role_id=(select id from public.admin_roles where name=''platform_owner'')and permission_name in(''notifications.read'',''notifications.manage'')']loop
  begin
   execute mutation;
   execute 'set local role service_role';
   perform set_config('request.jwt.claims','{"role":"service_role"}',true);
   for c in select expression from pg_temp.assisted_calls loop
    perform pg_temp.assisted_deny('select '||c.expression,'42501',split_part(mutation,' ',3)||' denies '||split_part(c.expression,'(',1));end loop;
   raise notice 'ASSISTED_REVOCATION_CASES=9; mutation=%',mutation;
   -- Intentional subtransaction rollback restores each authority mutation.
   raise exception 'assisted_restore_fixture'using errcode='P0002';
  exception when sqlstate 'P0002' then
   if sqlerrm<>'assisted_restore_fixture'then raise;end if;
  end;
 end loop;end$$;
-- Assertions written inside the rollback-only subtransactions are counted in
-- their explicit success NOTICE; durable result rows cover the other checks.
set local role service_role;
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
select pg_temp.assisted_deny('select public.collect_notification_health_v2(''99440000-0000-4000-8000-000000000001'',''99440000-0000-4000-8000-000000000011'')','42501','service SQL role with non-service JWT denied');
reset role;
select 'ASSISTED_SQL_ASSERTIONS='||count(*)from pg_temp.assisted_results;
rollback;
