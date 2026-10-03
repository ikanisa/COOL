\set ON_ERROR_STOP on
-- Root invokes on the isolated196 fixture only; all writes roll back.
begin;
set local statement_timeout='30s';set local lock_timeout='5s';
do $$ begin
 if current_database()<>'postgres' or current_user<>'postgres'
  or current_setting('collect.roster_provenance_qa',true) is distinct from 'isolated_clone'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
  or (select count(*) from supabase_migrations.schema_migrations)<>196
  or (select max(version) from supabase_migrations.schema_migrations)<>'20261001250000'
  or exists(select 1 from auth.users where id::text like '99690000-%')
  or exists(select 1 from collect_hybrid.roster_resource_reservations where request_id::text like '99690000-%') then
  raise exception 'Exact isolated196 and unused9969 fixture required'; end if;
end $$;
create temp table integrity_checks(n integer);insert into integrity_checks values(0);
create function pg_temp.expect(stmt text,code text) returns void language plpgsql as $$
begin
 begin execute stmt; exception when others then
  if sqlerrm<>code and sqlstate<>code then raise exception 'Expected %, got %/%',code,sqlstate,sqlerrm;end if;
  update integrity_checks set n=n+1;return;
 end;raise exception 'Expected rejection %',code;
end $$;
grant all on integrity_checks to authenticated,anon,service_role;
do $$ begin execute format('grant usage on schema %I to authenticated,anon,service_role',pg_my_temp_schema()::regnamespace::text);end $$;
grant execute on function pg_temp.expect(text,text) to authenticated,anon,service_role;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99690000-0000-4000-8000-000000000001','authenticated','authenticated','250788969001',now(),'{}','{}');
update public.profiles set country_code='RW',currency_code='RWF' where id='99690000-0000-4000-8000-000000000001';
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values('99690000-0000-4000-8000-000000000001','+250788969001',now()-interval '2 minutes','Synthetic upload integrity fixture');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99690000-0000-4000-8000-000000000001',id,'Synthetic upload integrity role',now()-interval '1 minute'
from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99690000-0000-4000-8000-000000000011','99690000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal1'),
('99690000-0000-4000-8000-000000000012','99690000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal1');
update public.feature_flags set enabled=true where key='hybrid_member_onboarding';
create temp table integrity_reservations(id uuid,kind text);grant all on integrity_reservations to service_role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do $$ declare r jsonb;id uuid;v jsonb;begin
 r:=public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000101',repeat('a',64),'image',100,null);
 if r->>'state'<>'reserved' or (r->>'replayed')::boolean then raise exception 'New reservation ACK invalid';end if;
 id:=(r->>'reservation_id')::uuid;insert into integrity_reservations values(id,'image');
 perform pg_temp.expect($s$select public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000101',repeat('a',64),'image',100,null)$s$,'roster_resource_in_progress');
 perform pg_temp.expect($s$select public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000012',
 '99690000-0000-4000-8000-000000000101',repeat('a',64),'image',100,null)$s$,'roster_request_conflict');
 perform pg_temp.expect($s$select public.create_roster_import_source('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000101','image',repeat('a',64),100,'fixture.png','image/png','image/png',null,null,true,
 'roster-ai-extraction-v1','{"provider":"openai","model":"fixture-model","prompt_version":"roster-extraction-v1"}')$s$,'roster_source_unverified');
 -- All binding fields, kind summary and active reservation are valid. Each
 -- denial changes only one obsolete version and precedes the first admission.
 perform pg_temp.expect(format($s$select public.verify_roster_source_integrity(%L,'99690000-0000-4000-8000-000000000001',
 '99690000-0000-4000-8000-000000000011',repeat('b',64),repeat('d',64),'collect-roster-decoder-v1',
 '{"python":"3.12","pillow":"12.0.0","pypdfium2":"5.2.0","pypdf":"6.19.0","openpyxl":"3.1.5","defusedxml":"0.7.1"}',
 '{"frames":1,"pages":0,"pixels":100,"expanded_bytes":400}')$s$,id),'roster_input_invalid');
 perform pg_temp.expect(format($s$select public.verify_roster_source_integrity(%L,'99690000-0000-4000-8000-000000000001',
 '99690000-0000-4000-8000-000000000011',repeat('b',64),repeat('d',64),'collect-roster-decoder-v1',
 '{"python":"3.12","pillow":"12.3.0","pypdfium2":"5.2.0","pypdf":"6.7.0","openpyxl":"3.1.5","defusedxml":"0.7.1"}',
 '{"frames":1,"pages":0,"pixels":100,"expanded_bytes":400}')$s$,id),'roster_input_invalid');
 v:=public.verify_roster_source_integrity(id,'99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',repeat('b',64),repeat('d',64),
 'collect-roster-decoder-v1','{"python":"3.12","pillow":"12.3.0","pypdfium2":"5.2.0","pypdf":"6.19.0","openpyxl":"3.1.5","defusedxml":"0.7.1"}',
 '{"frames":1,"pages":0,"pixels":100,"expanded_bytes":400}');
 if v->>'verified'<>'true' or v->>'source_sha256'<>repeat('a',64) then raise exception 'Integrity ACK invalid';end if;
 perform pg_temp.expect(format($s$select public.verify_roster_source_integrity(%L,'99690000-0000-4000-8000-000000000001',
 '99690000-0000-4000-8000-000000000011',repeat('c',64),repeat('d',64),'collect-roster-decoder-v1',
 '{"python":"3.12","pillow":"12.3.0","pypdfium2":"5.2.0","pypdf":"6.19.0","openpyxl":"3.1.5","defusedxml":"0.7.1"}',
 '{"frames":1,"pages":0,"pixels":100,"expanded_bytes":400}')$s$,id),'roster_request_conflict');
 perform public.finish_roster_resources(id,'99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011','ambiguous');
 -- Ambiguous completion retains full charge AND its active slot until expiry.
 perform public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000102',repeat('a',64),'image',100,null);
 perform pg_temp.expect($s$select public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000103',repeat('a',64),'image',100,null)$s$,'roster_resource_limit');
 r:=public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000101',repeat('a',64),'image',100,null);
 if r->>'state'<>'finished' or r->>'replayed'<>'true' then raise exception 'Terminal replay invalid';end if;
 update integrity_checks set n=n+4;
end $$;
reset role;
-- Remove active-slot interference so each daily ceiling is independently
-- falsifiable. Every policy edit and attempted reservation rolls back.
create temp table integrity_policy as select * from collect_hybrid.roster_resource_policy;
update collect_hybrid.roster_resource_policy set actor_active=10,global_active=100,actor_daily_requests=2;
set local role service_role;
select pg_temp.expect($s$select public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000103',repeat('a',64),'image',100,null)$s$,'roster_resource_limit');
reset role;
update collect_hybrid.roster_resource_policy set actor_daily_requests=100,actor_daily_bytes=5242880;
set local role service_role;
select pg_temp.expect($s$select public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000103',repeat('a',64),'image',5242880,null)$s$,'roster_resource_limit');
reset role;
update collect_hybrid.roster_resource_policy set actor_daily_bytes=104857600,actor_daily_cost_units=20000;
set local role service_role;
select pg_temp.expect($s$select public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000103',repeat('a',64),'image',100,null)$s$,'roster_resource_limit');
reset role;
update collect_hybrid.roster_resource_policy set actor_daily_cost_units=100000,global_daily_requests=2;
set local role service_role;
select pg_temp.expect($s$select public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000103',repeat('a',64),'image',100,null)$s$,'roster_resource_limit');
reset role;
update collect_hybrid.roster_resource_policy set global_daily_requests=1000,global_daily_bytes=5242880;
set local role service_role;
select pg_temp.expect($s$select public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000103',repeat('a',64),'image',5242880,null)$s$,'roster_resource_limit');
reset role;
update collect_hybrid.roster_resource_policy set global_daily_bytes=1073741824,global_daily_cost_units=20000;
set local role service_role;
select pg_temp.expect($s$select public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000103',repeat('a',64),'image',100,null)$s$,'roster_resource_limit');
reset role;
update collect_hybrid.roster_resource_policy p set (actor_daily_requests,actor_daily_bytes,actor_active,global_daily_requests,
 global_daily_bytes,global_active,actor_daily_cost_units,global_daily_cost_units,ai_attempt_cost_units,version)=
 (select actor_daily_requests,actor_daily_bytes,actor_active,global_daily_requests,global_daily_bytes,global_active,
 actor_daily_cost_units,global_daily_cost_units,ai_attempt_cost_units,version from integrity_policy);
-- All private budget/provenance tables deny direct API reads/writes.
do $$ declare t text;role_name text;begin
 foreach t in array array['roster_resource_policy','roster_resource_reservations','roster_resource_completions','roster_source_verifications'] loop
  foreach role_name in array array['anon','authenticated','service_role'] loop
   if has_table_privilege(role_name,'collect_hybrid.'||t,'SELECT,INSERT,UPDATE,DELETE') then raise exception 'Direct API grant leaked';end if;
   update integrity_checks set n=n+1;
  end loop;
 end loop;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","sub":"99690000-0000-4000-8000-000000000001","session_id":"99690000-0000-4000-8000-000000000011"}',true);
select pg_temp.expect($s$select public.reserve_roster_resources('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000104',repeat('a',64),'image',100,null)$s$,'42501');
select pg_temp.expect($s$select public._create_roster_import_source_v142('99690000-0000-4000-8000-000000000001','99690000-0000-4000-8000-000000000011',
 '99690000-0000-4000-8000-000000000104','text',repeat('a',64),100,'fixture.txt','text/plain','utf8_text',null,null,false,null,null)$s$,'42501');
reset role;
do $$ begin if (select sum(cost_units) from collect_hybrid.roster_resource_reservations where actor_id='99690000-0000-4000-8000-000000000001')<>20000 then
 raise exception 'Full worst-case charge not retained';end if;end $$;
select 'ROSTER_RESOURCE_UAT_CHECKS:'||n from integrity_checks;
rollback;
