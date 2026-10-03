\set ON_ERROR_STOP on
begin;
set local statement_timeout='15s';
create temporary table privacy_current_checks(name text primary key);
grant select,insert on privacy_current_checks to authenticated,anon,service_role;
create function pg_temp.check_case(ok boolean,label text)returns void language plpgsql as $$begin
 if ok is not true then raise exception 'current privacy status assertion failed: %',label;end if;
 insert into privacy_current_checks values(label);
end$$;
create function pg_temp.denied(command text,code text,message text,label text)returns void language plpgsql as $$begin
 begin execute command;exception when others then
  if sqlstate<>code or(message is not null and sqlerrm<>message)then raise;end if;
  perform pg_temp.check_case(true,label);return;end;
 raise exception 'current privacy status denial unexpectedly succeeded: %',label;
end$$;
create function pg_temp.claim(subject integer,sid integer)returns void language plpgsql as $$begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',
  '99880000-0000-4000-8000-'||lpad(subject::text,12,'0'),'role','authenticated',
  'session_id','99880000-0000-4000-8000-'||lpad(sid::text,12,'0'),
  'exp',(extract(epoch from clock_timestamp())+3600)::bigint)::text,true);
end$$;
select pg_temp.check_case(current_user='postgres'and current_setting('cron.launch_active_jobs')='off'
 and current_setting('pg_net.batch_size')='0'and current_setting('listen_addresses')='', 'owned offline target guard');
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select ('99880000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'authenticated','authenticated',
 '250788988'||lpad(i::text,3,'0'),clock_timestamp(),'{}','{}'from generate_series(1,3)i;
update public.profiles set country_code='RW',currency_code='RWF'where id::text like '99880000%';
-- Preserve legitimate platform support access, while proving the new RPC is
-- still own-only for an approved live operator who has a canonical request.
insert into public.admin_user_roles(user_id,role_id,created_at,reason)
select '99880000-0000-4000-8000-000000000003',id,clock_timestamp(),'Synthetic current-status QA'
 from public.admin_roles where name='platform_owner';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,reason,approved_at)
values('99880000-0000-4000-8000-000000000003','+250788988003','Synthetic current-status QA',clock_timestamp());
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
select ('99880000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
 ('99880000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval'1 hour','aal1'
 from generate_series(1,3)i;
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values
 ('99880000-0000-4000-8000-000000000201','99880000-0000-4000-8000-000000000001',clock_timestamp()-interval'20 minutes',clock_timestamp(),clock_timestamp()+interval'1 hour','aal1'),
 ('99880000-0000-4000-8000-000000000202','99880000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()-interval'1 minute','aal1');
insert into public.mobile_account_deletion_requests(id,user_id,reason,status)values
 ('99880000-0000-4000-8000-000000004011','99880000-0000-4000-8000-000000000002','older historical reason','pending'),
 ('99880000-0000-4000-8000-000000004012','99880000-0000-4000-8000-000000000002','newer historical reason','in_review');
set local role authenticated;
select pg_temp.claim(1,101);
select pg_temp.check_case(public.get_current_account_deletion_request_status_v1()is null,'healthy own canonical absence returns null');
select public.request_account_deletion_v1('99880000-0000-4000-8000-000000004001','Synthetic private reason');
select public.request_account_deletion_v1('99880000-0000-4000-8000-000000004002','Synthetic private reason');
select pg_temp.check_case(public.get_current_account_deletion_request_status_v1()=
 public.get_account_deletion_request_status_v1('99880000-0000-4000-8000-000000004002'),'own canonical receipt equals authoritative alias status');
select pg_temp.check_case(public.get_current_account_deletion_request_status_v1()->>'request_id'='99880000-0000-4000-8000-000000004001', 'restart recovery uses one canonical UUID');
select pg_temp.check_case(not(public.get_current_account_deletion_request_status_v1()?|
 array['submission_id','replay','equivalent_active_request','reason','subject_id','session_id','input_sha256']), 'current receipt exposes no private or submission metadata');
select pg_temp.check_case(public.get_current_account_deletion_request_status_v1()->>'state'='pending_review'
 and(public.get_current_account_deletion_request_status_v1()->>'policy_review_pending')::boolean
 and(public.get_current_account_deletion_request_status_v1()->>'subject_scope_review_pending')::boolean
 and not(public.get_current_account_deletion_request_status_v1()->>'erasure_completed')::boolean
 and not(public.get_current_account_deletion_request_status_v1()->>'auth_removed')::boolean
 and not(public.get_current_account_deletion_request_status_v1()->>'processor_operation_started')::boolean,
 'recovery preserves unresolved policy and no erasure semantics');
select pg_temp.claim(2,102);
select pg_temp.check_case(public.get_current_account_deletion_request_status_v1()is null,'outsider legacy pending rows are not canonical or foreign recovery');
select pg_temp.denied($q$select public.get_account_deletion_request_status_v1('99880000-0000-4000-8000-000000004001')$q$,'42501','privacy_request_unavailable','outsider specific status denied');
select pg_temp.claim(3,103);
select pg_temp.check_case(public.is_platform_admin(auth.uid()),'actual approved live support operator');
select pg_temp.check_case(public.get_current_account_deletion_request_status_v1()is null,'Admin authority does not reveal another canonical request');
select pg_temp.check_case((select count(*)=1 from public.mobile_account_deletion_requests where id='99880000-0000-4000-8000-000000004001'),'legitimate session-gated legacy support read retained');
select public.request_account_deletion_v1('99880000-0000-4000-8000-000000004003',null);
select pg_temp.check_case(public.get_current_account_deletion_request_status_v1()->>'request_id'='99880000-0000-4000-8000-000000004003','Admin current-status remains own canonical request only');
select pg_temp.claim(1,201);
select pg_temp.check_case(public.get_current_account_deletion_request_status_v1()->>'request_id'='99880000-0000-4000-8000-000000004001','older live session can recover status without fresh OTP');
select pg_temp.claim(1,202);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501','privacy_request_session_required','expired not-after denied');
select pg_temp.claim(1,102);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501','privacy_request_session_required','wrong-subject actual SID denied');
select pg_temp.claim(1,999);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501','privacy_request_session_required','nonexistent actual SID denied');
select pg_temp.claim(1,101);
select set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb-'session_id')::text,true);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501','privacy_request_session_required','missing SID denied');
select pg_temp.claim(1,101);
select set_config('request.jwt.claims',jsonb_set(current_setting('request.jwt.claims')::jsonb,'{session_id}','"malformed"')::text,true);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501','privacy_request_session_required','malformed SID denied');
select pg_temp.claim(1,101);
select set_config('request.jwt.claims',jsonb_set(current_setting('request.jwt.claims')::jsonb,'{sub}','"malformed"')::text,true);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'22P02',null,'malformed UID rejected by exact retained Auth UUID parser');
select pg_temp.claim(1,101);
select set_config('request.jwt.claims',jsonb_set(current_setting('request.jwt.claims')::jsonb,'{exp}','"9999999999"')::text,true);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501','privacy_request_session_required','string expiry denied');
select pg_temp.claim(1,101);
select set_config('request.jwt.claims',jsonb_set(current_setting('request.jwt.claims')::jsonb,'{exp}','1')::text,true);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501','privacy_request_session_required','expired JWT claims denied');
select pg_temp.claim(1,101);
select set_config('request.jwt.claims',jsonb_set(current_setting('request.jwt.claims')::jsonb,'{role}','"service_role"')::text,true);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501','privacy_request_session_required','mismatched JWT role denied');
select set_config('request.jwt.claims','{}',true);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501','privacy_request_session_required','missing subject claims denied');
reset role;
delete from auth.sessions where id='99880000-0000-4000-8000-000000000101';
set local role authenticated;
select pg_temp.claim(1,101);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501','privacy_request_session_required','revoked SID cannot recover request');
reset role;
update auth.users set banned_until=clock_timestamp()+interval'1 hour'where id='99880000-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.claim(2,102);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501','privacy_request_session_required','banned subject cannot observe absence');
reset role;
set local role service_role;
select pg_temp.claim(1,201);
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501',null,'service role cannot bypass function ACL with forged authenticated claims');
reset role;
set local role anon;
select pg_temp.denied($q$select public.get_current_account_deletion_request_status_v1()$q$,'42501',null,'anon function execute denied');
reset role;
select jsonb_build_object('marker','PRIVACY_CURRENT_REQUEST_STATUS_UAT_PASS','checks',count(*),'names',jsonb_agg(name order by name))from privacy_current_checks;
rollback;
