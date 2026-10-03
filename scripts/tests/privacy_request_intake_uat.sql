\set ON_ERROR_STOP on
begin;
set local collect.privacy_intake_qa='isolated_clone';
set local statement_timeout='15s';
create temporary table privacy_checks(name text primary key);
grant select,insert on privacy_checks to authenticated,anon,service_role;
create function pg_temp.check_case(ok boolean,label text)returns void language plpgsql as $$begin
 if ok is not true then raise exception 'privacy assertion failed: %',label;end if;
 insert into privacy_checks values(label);
end$$;
create function pg_temp.denied(command text,code text,message text,label text)returns void language plpgsql as $$begin
 begin execute command;exception when others then
  if sqlstate<>code or(message is not null and sqlerrm<>message)then raise;end if;
  perform pg_temp.check_case(true,label);return;end;
 raise exception 'privacy denial unexpectedly succeeded: %',label;
end$$;
create function pg_temp.claim(subject integer,session_number integer,expiration jsonb default null)returns void language plpgsql as $$begin
 perform set_config('request.jwt.claims',jsonb_build_object('sub',
  '99860000-0000-4000-8000-'||lpad(subject::text,12,'0'),'role','authenticated',
  'session_id','99860000-0000-4000-8000-'||lpad(session_number::text,12,'0'),
  'exp',coalesce(expiration,to_jsonb((extract(epoch from clock_timestamp())+3600)::bigint)))::text,true);
end$$;
select pg_temp.check_case(current_user='postgres'and current_setting('cron.launch_active_jobs')='off'
 and current_setting('pg_net.batch_size')='0'and current_setting('listen_addresses')='', 'owned offline target guard');
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select ('99860000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'authenticated','authenticated',
 '250788986'||lpad(i::text,3,'0'),clock_timestamp(),'{}','{}'from generate_series(1,10)i;
update public.profiles set country_code='RW',currency_code='RWF'where id::text like '99860000%';
-- Actual role and approval writes complete before this operator's SID exists.
insert into public.admin_user_roles(user_id,role_id,created_at,reason)
select '99860000-0000-4000-8000-000000000003',id,clock_timestamp(),'Synthetic local support reader'
 from public.admin_roles where name='platform_owner';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,reason,approved_at)
values('99860000-0000-4000-8000-000000000003','+250788986003','Synthetic local support reader',clock_timestamp());
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
select ('99860000-0000-4000-8000-'||lpad((100+i)::text,12,'0'))::uuid,
 ('99860000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,clock_timestamp(),clock_timestamp(),clock_timestamp()+interval'1 hour','aal1'
 from generate_series(1,10)i;
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)values
 ('99860000-0000-4000-8000-000000000201','99860000-0000-4000-8000-000000000001',clock_timestamp()-interval'20 minutes',clock_timestamp(),clock_timestamp()+interval'1 hour','aal1'),
 ('99860000-0000-4000-8000-000000000202','99860000-0000-4000-8000-000000000001',clock_timestamp()+interval'1 minute',clock_timestamp(),clock_timestamp()+interval'1 hour','aal1'),
 ('99860000-0000-4000-8000-000000000203','99860000-0000-4000-8000-000000000001',clock_timestamp(),clock_timestamp(),clock_timestamp()-interval'1 minute','aal1');
insert into public.mobile_account_deletion_requests(id,user_id,reason,status)values
 ('99860000-0000-4000-8000-000000004004','99860000-0000-4000-8000-000000000004','historical','in_review');
create temporary table observed_receipts(label text primary key,value jsonb);
grant select,insert on observed_receipts to authenticated;
set local role authenticated;
select pg_temp.claim(1,101);
insert into observed_receipts values('first',public.request_account_deletion_v1('99860000-0000-4000-8000-000000004001',' reason '));
select pg_temp.check_case((select value->>'request_id'='99860000-0000-4000-8000-000000004001'
 and value->>'state'='pending_review'and value->>'scope'='own_account_eligible_data'
 and (value->>'policy_review_pending')::boolean and(value->>'subject_scope_review_pending')::boolean
 and not(value->>'erasure_completed')::boolean and not(value->>'account_access_restricted')::boolean
 and not(value->>'auth_removed')::boolean and not(value->>'retention_approval_granted')::boolean
 and not(value->>'processor_operation_started')::boolean
 and not(value ?| array['subject_id','reason','session_id','input_sha256'])from observed_receipts where label='first'), 'healthy minimized pending receipt');
select pg_temp.check_case((public.request_account_deletion_v1('99860000-0000-4000-8000-000000004001','reason')->>'replay')::boolean,'exact normalized replay');
select pg_temp.check_case(public.request_account_deletion_v1('99860000-0000-4000-8000-000000004002','reason')->>'request_id'='99860000-0000-4000-8000-000000004001','equivalent active UUID reuse');
select pg_temp.check_case(public.get_account_deletion_request_status_v1('99860000-0000-4000-8000-000000004002')->>'request_id'='99860000-0000-4000-8000-000000004001','own alias status');
select pg_temp.check_case(public.request_account_deletion('reason')='99860000-0000-4000-8000-000000004001'::uuid,'legacy UUID adapter reuses canonical');
select pg_temp.denied($q$select public.request_account_deletion_v1('99860000-0000-4000-8000-000000004001','changed')$q$,'22023','privacy_request_conflict','same UUID payload conflict');
select pg_temp.denied($q$select public.request_account_deletion_v1('99860000-0000-4000-8000-000000004003','changed')$q$,'22023','privacy_request_active_scope_conflict','active scope payload conflict');
select pg_temp.denied($q$select public.request_account_deletion_v1(null,'reason')$q$,'22023','privacy_request_invalid','typed UUID required');
select pg_temp.denied($q$select public.request_account_deletion_v1(gen_random_uuid(),repeat('x',501))$q$,'22023','privacy_request_reason_invalid','reason character bound');
select pg_temp.denied($q$select public.request_account_deletion_v1(gen_random_uuid(),E'unsafe\ntext')$q$,'22023','privacy_request_reason_invalid','reason control denial');
select pg_temp.claim(2,102);
select pg_temp.denied($q$select public.request_account_deletion_v1('99860000-0000-4000-8000-000000004001','reason')$q$,'22023','privacy_request_conflict','other subject UUID conflict');
select pg_temp.denied($q$select public.get_account_deletion_request_status_v1('99860000-0000-4000-8000-000000004001')$q$,'42501','privacy_request_unavailable','outsider safe status denial');
select pg_temp.denied($q$select public.get_account_deletion_request_status_v1('99860000-0000-4000-8000-000000099999')$q$,'42501','privacy_request_unavailable','unknown same status denial');
select pg_temp.check_case((select count(*)=0 from public.mobile_account_deletion_requests where id='99860000-0000-4000-8000-000000004001'),'outsider legacy RLS denial');
select pg_temp.claim(3,103);
select pg_temp.check_case(public.is_platform_admin(auth.uid()),'actual approved live platform owner');
select pg_temp.check_case((select count(*)=1 from public.mobile_account_deletion_requests where id='99860000-0000-4000-8000-000000004001'),'legacy Admin support read retained');
select pg_temp.denied($q$select public.get_account_deletion_request_status_v1('99860000-0000-4000-8000-000000004001')$q$,'42501','privacy_request_unavailable','Admin own-status RPC remains own-only');
select pg_temp.claim(4,104);
select pg_temp.check_case(public.request_account_deletion(' historical ')='99860000-0000-4000-8000-000000004004'::uuid,'equivalent historical pending adoption');
select pg_temp.claim(9,109);
insert into observed_receipts values('default',jsonb_build_object('id',public.request_account_deletion()));
select pg_temp.check_case(public.request_account_deletion('   ')=(select(value->>'id')::uuid from observed_receipts where label='default'),'legacy default and whitespace normalize to absent reason');
select pg_temp.check_case(not(public.get_account_deletion_request_status_v1((select(value->>'id')::uuid from observed_receipts where label='default'))->>'reason_supplied')::boolean,'absent reason stays minimized');
select pg_temp.claim(10,110);
select pg_temp.check_case((public.request_account_deletion_v1('99860000-0000-4000-8000-000000004010',repeat('🙂',500))->>'reason_supplied')::boolean,'exact 500 character 2000 byte reason accepted');
select pg_temp.claim(1,201);
select pg_temp.check_case(public.get_account_deletion_request_status_v1('99860000-0000-4000-8000-000000004001')->>'state'='pending_review','older live session status permitted');
select pg_temp.denied($q$select public.request_account_deletion('reason')$q$,'42501','privacy_request_fresh_session_required','older session intake denied');
select pg_temp.claim(1,202);
select pg_temp.denied($q$select public.request_account_deletion('reason')$q$,'42501','privacy_request_session_required','future-created SID denied');
select pg_temp.claim(1,203);
select pg_temp.denied($q$select public.request_account_deletion('reason')$q$,'42501','privacy_request_session_required','expired not-after denied');
select pg_temp.claim(1,102);
select pg_temp.denied($q$select public.request_account_deletion('reason')$q$,'42501','privacy_request_session_required','wrong-subject SID denied');
select pg_temp.claim(1,999);
select pg_temp.denied($q$select public.request_account_deletion('reason')$q$,'42501','privacy_request_session_required','nonexistent SID denied');
select pg_temp.claim(1,101,to_jsonb('999999999999999999999999999999999999999999'::numeric));
select pg_temp.denied($q$select public.request_account_deletion('reason')$q$,'42501','privacy_request_session_required','oversized numeric exp denied without cast overflow');
select pg_temp.claim(1,101,'"9999999999"');
select pg_temp.denied($q$select public.request_account_deletion('reason')$q$,'42501','privacy_request_session_required','string exp denied');
select pg_temp.claim(1,101,'1');
select pg_temp.denied($q$select public.request_account_deletion('reason')$q$,'42501','privacy_request_session_required','expired exp denied');
select pg_temp.claim(1,101);
select set_config('request.jwt.claims',(current_setting('request.jwt.claims')::jsonb-'exp')::text,true);
select pg_temp.denied($q$select public.request_account_deletion('reason')$q$,'42501','privacy_request_session_required','missing exp denied');
select pg_temp.claim(1,101);
select set_config('request.jwt.claims',jsonb_set(current_setting('request.jwt.claims')::jsonb,'{session_id}','"malformed"')::text,true);
select pg_temp.denied($q$select public.request_account_deletion('reason')$q$,'42501','privacy_request_session_required','malformed SID denied');
select pg_temp.claim(1,101);
select set_config('request.jwt.claims',jsonb_set(current_setting('request.jwt.claims')::jsonb,'{role}','"service_role"')::text,true);
select pg_temp.denied($q$select public.request_account_deletion('reason')$q$,'42501','privacy_request_session_required','mismatched role claim denied');
select pg_temp.claim(1,101);
select pg_temp.denied($q$insert into public.mobile_account_deletion_requests(user_id)values(auth.uid())$q$,'42501',null,'client direct request write denied');
select pg_temp.denied($q$select * from collect_privacy.intake_requests$q$,'42501',null,'client private intake read denied');
select pg_temp.denied($q$select collect_privacy.submit(null,null,false)$q$,'42501',null,'client private helper execute denied');
do $$declare i integer;begin for i in 3..32 loop
 perform public.request_account_deletion_v1(('99860000-0000-4000-8000-'||lpad((5000+i)::text,12,'0'))::uuid,'reason');end loop;end$$;
select pg_temp.denied($q$select public.request_account_deletion_v1('99860000-0000-4000-8000-000000006000','reason')$q$,'54000','privacy_request_submission_limit','alternate UUID bindings bounded');
select pg_temp.check_case((public.request_account_deletion_v1('99860000-0000-4000-8000-000000004001','reason')->>'replay')::boolean,'exact replay works at alias limit');
reset role;
select pg_temp.check_case((select count(*)=1 from collect_privacy.intake_requests where subject_id='99860000-0000-4000-8000-000000000001')
 and(select count(*)=32 from collect_privacy.intake_submissions where request_id='99860000-0000-4000-8000-000000004001')
 and(select count(*)=1 from public.mobile_account_deletion_requests where user_id='99860000-0000-4000-8000-000000000001'), 'failed calls and retries create one canonical with bounded aliases');
select pg_temp.check_case((select status='in_review'and reason='historical'from public.mobile_account_deletion_requests where id='99860000-0000-4000-8000-000000004004'),'historical row semantics preserved');
select pg_temp.denied($q$update collect_privacy.intake_requests set reason_supplied=false$q$,'55000','privacy_intake_evidence_immutable','private evidence update denied');
select pg_temp.denied($q$delete from collect_privacy.intake_submissions$q$,'55000','privacy_intake_evidence_immutable','private evidence delete denied');
select pg_temp.denied($q$truncate collect_privacy.intake_submissions$q$,'55000','privacy_intake_evidence_immutable','private evidence truncate denied');
delete from auth.sessions where id='99860000-0000-4000-8000-000000000101';
set local role authenticated;
select pg_temp.claim(1,101);
select pg_temp.denied($q$select public.get_account_deletion_request_status_v1('99860000-0000-4000-8000-000000004001')$q$,'42501','privacy_request_session_required','revoked own status denied');
select pg_temp.check_case((select count(*)=0 from public.mobile_account_deletion_requests where id='99860000-0000-4000-8000-000000004001'),'revoked legacy RLS read denied');
reset role;
update auth.users set banned_until=clock_timestamp()+interval'1 hour'where id='99860000-0000-4000-8000-000000000005';
update auth.users set is_anonymous=true where id='99860000-0000-4000-8000-000000000006';
update auth.users set phone_confirmed_at=null,email_confirmed_at=null where id='99860000-0000-4000-8000-000000000007';
update auth.users set deleted_at=clock_timestamp()where id='99860000-0000-4000-8000-000000000008';
set local role authenticated;
select pg_temp.claim(5,105);
select pg_temp.denied($q$select public.request_account_deletion(null)$q$,'42501','privacy_request_session_required','banned user denied');
select pg_temp.claim(6,106);
select pg_temp.denied($q$select public.request_account_deletion(null)$q$,'42501','privacy_request_session_required','anonymous user denied');
select pg_temp.claim(7,107);
select pg_temp.denied($q$select public.request_account_deletion(null)$q$,'42501','privacy_request_session_required','unconfirmed user denied');
select pg_temp.claim(8,108);
select pg_temp.denied($q$select public.request_account_deletion(null)$q$,'42501','privacy_request_session_required','deleted user denied');
reset role;
set local role service_role;
select pg_temp.claim(2,102);
select pg_temp.denied($q$select public.request_account_deletion(null)$q$,'42501',null,'service execute denied despite forged authenticated claims');
select pg_temp.denied($q$insert into public.mobile_account_deletion_requests(user_id)values('99860000-0000-4000-8000-000000000002')$q$,'42501',null,'service direct write denied');
reset role;
set local role anon;
select pg_temp.denied($q$select public.request_account_deletion(null)$q$,'42501',null,'anon execute denied');
reset role;
select jsonb_build_object('marker','PRIVACY_REQUEST_INTAKE_UAT_PASS','checks',count(*),'names',jsonb_agg(name order by name))from privacy_checks;
rollback;
