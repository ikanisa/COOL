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
  'collect_hybrid.sms_notification_attempts','public.audit_logs']loop
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
  'delete from auth.users where id=''99440000-0000-4000-8000-000000000001''',
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
