\set ON_ERROR_STOP on
-- Rollback-only synthetic141 QA. No provider/pg_net calls or existing users.
begin;
set local statement_timeout='30s';
set local lock_timeout='5s';
do $$ begin
  if current_setting('collect.notification_qa',true) is distinct from 'isolated_clone'
    or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
    or (select count(*) from supabase_migrations.schema_migrations)<>141
    or (select max(version) from supabase_migrations.schema_migrations)<>'20260929180000'
    or exists(select 1 from public.notification_device_tokens)
    or exists(select 1 from public.notification_deliveries)
    or exists(select 1 from auth.users where id::text like '99710000-%') then
    raise exception 'Guarded empty synthetic141 fixture required'; end if;
end $$;
create temp table session_results(label text primary key);
grant insert on session_results to authenticated;
create function pg_temp.check_session(ok boolean,label text) returns void language plpgsql as $$ begin
  if ok is not true then raise exception 'FAIL: %',label; end if;
  insert into pg_temp.session_results values(label);
end $$;
create function pg_temp.actor(p_user text,p_session text) returns void language plpgsql as $$ begin
  perform set_config('request.jwt.claim.sub',p_user,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',p_user,'role','authenticated','session_id',p_session,'aal','aal1')::text,true);
end $$;
create function pg_temp.expect_registration_denied(label text) returns void language plpgsql as $$
declare denied boolean:=false; begin
  begin perform public.register_notification_device('android','fcm','synthetic-session-token-9971001');
  exception when others then
    if sqlerrm<>'notification_registration_session_required' then raise; end if; denied:=true; end;
  perform pg_temp.check_session(denied,label);
end $$;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99710000-0000-4000-8000-000000000001','authenticated','authenticated','250788917001',now(),'{}','{}'),
      ('99710000-0000-4000-8000-000000000002','authenticated','authenticated','250788917002',now(),'{}','{}');
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99710000-0000-4000-8000-000000000101','99710000-0000-4000-8000-000000000001',now()-interval '10 minutes',now(),now()+interval '1 hour','aal1'),
      ('99710000-0000-4000-8000-000000000102','99710000-0000-4000-8000-000000000002',now()-interval '6 minutes',now(),now()+interval '1 hour','aal1'),
      ('99710000-0000-4000-8000-000000000103','99710000-0000-4000-8000-000000000001',now()-interval '8 minutes',now(),now()+interval '1 hour','aal2');

insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99710000-0000-4000-8000-000000000105','99710000-0000-4000-8000-000000000001',
  now()-interval '6 minutes',now(),now()+interval '1 hour','aal1');
create function pg_temp.expect_registration_stale(label text) returns void language plpgsql as $$
declare denied boolean:=false; begin
  begin perform public.register_notification_device('android','fcm','synthetic-session-token-9971001');
  exception when others then
    if sqlerrm<>'notification_registration_session_stale' or sqlstate<>'42501' then raise; end if; denied:=true; end;
  perform pg_temp.check_session(denied,label);
end $$;
set local role authenticated;
select pg_temp.actor('99710000-0000-4000-8000-000000000001',null);
select pg_temp.expect_registration_denied('missing JWT session denied');
select pg_temp.actor('99710000-0000-4000-8000-000000000001','invalid');
select pg_temp.expect_registration_denied('malformed JWT session denied');
select pg_temp.actor('99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000199');
select pg_temp.expect_registration_denied('missing live session denied');
select pg_temp.actor('99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000102');
select pg_temp.expect_registration_denied('another user session denied');
select pg_temp.actor('99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000101');
select public.register_notification_device('android','fcm','synthetic-session-token-9971001');
select public.register_notification_device('android','fcm','synthetic-session-token-9971001');
reset role;
select pg_temp.check_session((select count(*)=1 and bool_and(enabled and registration_session_id='99710000-0000-4000-8000-000000000101')
  from public.notification_device_tokens),'AAL1 same-session re-registration binds exactly one token');

update auth.users set phone_confirmed_at=null,email_confirmed_at=null where id='99710000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.expect_registration_denied('unverified user cannot register');
reset role;
select pg_temp.check_session((select not enabled and disabled_reason='registration_user_revoked' from public.notification_device_tokens),'loss of verified identity disables current tokens');
update auth.users set phone_confirmed_at=now(),banned_until=now()+interval '1 hour' where id='99710000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.expect_registration_denied('banned user cannot register');
reset role;
select pg_temp.check_session((select not enabled from public.notification_device_tokens),'ordinary Auth ban leaves token disabled');
update auth.users set banned_until=null where id='99710000-0000-4000-8000-000000000001';

-- Another valid session of the same user owns this installation now. Old
-- unregister and old Auth-session deletion must not disable the replacement.
set local role authenticated;
select pg_temp.actor('99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000103');
select public.register_notification_device('android','fcm','synthetic-session-token-9971001');
select pg_temp.actor('99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000101');
select pg_temp.expect_registration_stale('older still-live same-user session cannot undo newer registration');
select public.unregister_notification_device('fcm','synthetic-session-token-9971001');
reset role;
select pg_temp.check_session((select enabled and registration_session_id='99710000-0000-4000-8000-000000000103' from public.notification_device_tokens),
  'old same-user unregister cannot disable a replacement session');
delete from auth.sessions where id='99710000-0000-4000-8000-000000000101';
select pg_temp.check_session((select enabled from public.notification_device_tokens),'old same-user session deletion leaves replacement enabled');
set local role authenticated;
select pg_temp.expect_registration_denied('late deleted-session registration denied');
select pg_temp.actor('99710000-0000-4000-8000-000000000002','99710000-0000-4000-8000-000000000102');
select public.register_notification_device('android','fcm','synthetic-session-token-9971001');
select pg_temp.actor('99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000103');
select pg_temp.expect_registration_stale('late still-live A registration cannot reclaim B token');
select pg_temp.actor('99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000105');
select pg_temp.expect_registration_stale('equal-time different session cannot win ambiguous replacement');
select pg_temp.actor('99710000-0000-4000-8000-000000000002','99710000-0000-4000-8000-000000000102');
select public.register_notification_device('android','fcm','synthetic-session-token-9971001');
reset role;
delete from auth.sessions where id='99710000-0000-4000-8000-000000000103';
select pg_temp.check_session((select enabled and user_id='99710000-0000-4000-8000-000000000002' and registration_session_id='99710000-0000-4000-8000-000000000102'
  from public.notification_device_tokens),'B replacement survives A logout');

insert into public.notification_events(id,user_id,type,title,body)
values('99710000-0000-4000-8000-000000000020','99710000-0000-4000-8000-000000000002','group_update','Private synthetic event','Retained in app only');
create temp table session_lease as select * from public.claim_notification_deliveries(2,1);
select pg_temp.check_session((select user_id='99710000-0000-4000-8000-000000000002' and title='Collect' and body='Open Collect to view your updates' from session_lease),
  'B claim is recipient-bound with generic preview');
update auth.sessions set not_after=clock_timestamp()+interval '15 seconds' where id='99710000-0000-4000-8000-000000000102';
select pg_temp.check_session((select not public.notification_delivery_is_current(delivery_id,claim_token,attempt_number) from session_lease),
  'presend requires a full30 second remaining Auth session budget');
update auth.sessions set not_after=clock_timestamp()+interval '1 hour' where id='99710000-0000-4000-8000-000000000102';
delete from auth.sessions where id='99710000-0000-4000-8000-000000000102';
select pg_temp.check_session((select not enabled and registration_session_id='99710000-0000-4000-8000-000000000102' and disabled_reason='registration_session_revoked'
  from public.notification_device_tokens),'logout disables only bound token while retaining session evidence');
select pg_temp.check_session((select registration_session_created_at=now()-interval '6 minutes' from public.notification_device_tokens), 'deleted-session registration precedence timestamp is retained');
select pg_temp.check_session((select status='failed' and claim_expires_at>clock_timestamp() from public.notification_deliveries),
  'logout cancels live delivery and preserves expiry fence');
select pg_temp.check_session((select count(*)=1 from public.notification_delivery_attempts),'logout preserves one failed-attempt record');
select pg_temp.check_session((select not public.notification_delivery_is_current(delivery_id,claim_token,attempt_number) from session_lease),
  'logged-out worker fails presend check');
do $$ declare lease record; denied boolean:=false; begin
  select * into strict lease from session_lease;
  begin perform public.complete_notification_delivery(lease.delivery_id,lease.claim_token,lease.attempt_number,true);
  exception when others then
    if sqlerrm<>'notification_delivery_fence_lost' then raise; end if; denied:=true; end;
  perform pg_temp.check_session(denied,'logged-out worker cannot complete');
end $$;
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99710000-0000-4000-8000-000000000104','99710000-0000-4000-8000-000000000001',now()-interval '4 minutes',now(),now()+interval '1 hour','aal1');
set local role authenticated;
select pg_temp.actor('99710000-0000-4000-8000-000000000001','99710000-0000-4000-8000-000000000104');
do $$ declare denied boolean:=false; begin
  begin perform public.register_notification_device('android','fcm','synthetic-session-token-9971001');
  exception when others then
    if sqlerrm<>'notification_device_in_flight' then raise; end if; denied:=true; end;
  perform pg_temp.check_session(denied,'replacement cannot bypass canceled but live lease');
end $$;
reset role;
update public.notification_deliveries set claim_expires_at=clock_timestamp()-interval '1 second';
set local role authenticated;
select public.register_notification_device('android','fcm','synthetic-session-token-9971001');
reset role;
select pg_temp.check_session((select enabled and user_id='99710000-0000-4000-8000-000000000001' from public.notification_device_tokens),
  'replacement registers after old lease expiry');

-- Future not_after update is accepted; time passing alone must still be checked.
update auth.sessions set not_after=clock_timestamp()+interval '100 milliseconds' where id='99710000-0000-4000-8000-000000000104';
select pg_sleep(0.15);
select pg_temp.check_session((select enabled from public.notification_device_tokens) and not public._notification_session_is_live(
  '99710000-0000-4000-8000-000000000104','99710000-0000-4000-8000-000000000001'),'time-based expiry is detected without relying on an Auth update trigger');
set local role authenticated;
select pg_temp.expect_registration_denied('elapsed not_after denies registration');
reset role;
insert into public.notification_events(id,user_id,type,title,body)
values('99710000-0000-4000-8000-000000000021','99710000-0000-4000-8000-000000000001','group_update','Private synthetic event','Retained in app only');
select pg_temp.check_session((select count(*)=0 from public.claim_notification_deliveries(2,1)), 'expired session cannot claim queued work');
select pg_temp.check_session((select status='failed' and last_error_code='registration_session_revoked' from public.notification_deliveries
  where event_id='99710000-0000-4000-8000-000000000021'), 'expired-session queue terminalizes instead of looping');

update auth.sessions set not_after=now()+interval '1 hour',aal='aal1' where id='99710000-0000-4000-8000-000000000104';
set local role authenticated;
select public.register_notification_device('android','fcm','synthetic-session-token-9971001');
reset role;
update auth.sessions set aal=null where id='99710000-0000-4000-8000-000000000104';
select pg_temp.check_session((select not enabled from public.notification_device_tokens),'invalidated assurance disables session-bound token');
set local role authenticated;
select pg_temp.expect_registration_denied('invalid assurance denies registration');
reset role;
update auth.sessions set aal='aal1' where id='99710000-0000-4000-8000-000000000104';
set local role authenticated;
select public.register_notification_device('android','fcm','synthetic-session-token-9971001');
reset role;
update auth.sessions set user_id='99710000-0000-4000-8000-000000000002' where id='99710000-0000-4000-8000-000000000104';
select pg_temp.check_session((select not enabled from public.notification_device_tokens),'session user reassignment disables old bound token');
select pg_temp.check_session(not has_function_privilege('authenticated','public._lock_notification_session_gate()','EXECUTE')
  and not has_function_privilege('service_role','public.lock_notification_auth_activity()','EXECUTE')
  and not has_function_privilege('authenticated','public.lock_notification_auth_revocation()','EXECUTE'), 'Auth gate helpers remain inaccessible to API roles');
select pg_temp.check_session(not has_function_privilege('authenticated','public._lock_notification_registration_session()','EXECUTE')
  and not has_function_privilege('service_role','public.revoke_notification_session_devices()','EXECUTE'), 'internal session helpers remain inaccessible to API roles');

select 'NOTIFICATION_REGISTRATION_SESSIONS_UAT_PASS' as result,count(*) as assertions from session_results;
rollback;
