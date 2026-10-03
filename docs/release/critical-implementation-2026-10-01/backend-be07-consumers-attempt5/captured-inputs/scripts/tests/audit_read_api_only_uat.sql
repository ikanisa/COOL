\set ON_ERROR_STOP on
-- Network-none runner-owned synthetic target only; every row rolls back.
begin;
do $$begin
 if current_setting('collect.audit_qa',true)is distinct from 'isolated_clone'
 or exists(select 1 from auth.users where id::text like '99590000-%')then
  raise exception 'Fresh task-owned audit boundary fixture required';end if;
end$$;
create temp table audit_results(label text primary key);
grant all on audit_results to authenticated,anon,service_role;
create function pg_temp.audit_assert(ok boolean,label text)returns void language plpgsql as $$begin
 if ok is not true then raise exception 'FAIL: %',label;end if;
 insert into pg_temp.audit_results values(label);end$$;
create function pg_temp.audit_deny(command text,label text)returns void language plpgsql as $$
declare caught text;begin
 begin execute command;exception when others then get stacked diagnostics caught=returned_sqlstate;end;
 perform pg_temp.audit_assert(caught='42501',label);end$$;
insert into auth.users(id,aud,role,email,email_confirmed_at,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)values
 ('99590000-0000-4000-8000-000000000001','authenticated','authenticated','audit-owner@example.test',clock_timestamp(),'250788995901',clock_timestamp(),'{}','{}'),
 ('99590000-0000-4000-8000-000000000002','authenticated','authenticated','audit-member@example.test',clock_timestamp(),'250788995902',clock_timestamp(),'{}','{}'),
 ('99590000-0000-4000-8000-000000000003','authenticated','authenticated','audit-outsider@example.test',clock_timestamp(),'250788995903',clock_timestamp(),'{}','{}'),
 ('99590000-0000-4000-8000-000000000004','authenticated','authenticated','audit-operator@example.test',clock_timestamp(),'250788995904',clock_timestamp(),'{}','{}');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99590000-0000-4000-8000-000000000004',id,'Synthetic audit reader authority',clock_timestamp()-interval '1 minute'
from public.admin_roles where name='platform_owner';
insert into collect_admin_access.email_approvals(user_id,email,approved_at,reason)values
 ('99590000-0000-4000-8000-000000000004','audit-operator@example.test',clock_timestamp()-interval '2 minutes','Synthetic audit reader approval only');
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
select ('99590000-0000-4000-8000-00000000001'||n)::uuid,('99590000-0000-4000-8000-00000000000'||n)::uuid,
 clock_timestamp(),clock_timestamp(),clock_timestamp()+interval '1 hour','aal1'::auth.aal_level
from generate_series(1,4)n;
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type,
 contribution_visibility,allow_anonymous,diaspora_enabled,creation_origin)values
 ('99590000-0000-4000-8000-000000000051','audit-api-only-qa','99590000-0000-4000-8000-000000000001',
 'Synthetic private audit group','Family / friends','private','private','ikimina','members',false,false,'member_app');
insert into public.collection_members(collection_id,user_id,role,status)values
 ('99590000-0000-4000-8000-000000000051','99590000-0000-4000-8000-000000000001','owner','active'),
 ('99590000-0000-4000-8000-000000000051','99590000-0000-4000-8000-000000000002','member','active');
select pg_temp.audit_assert(not has_table_privilege('authenticated','public.audit_logs','SELECT')
 and not has_any_column_privilege('authenticated','public.audit_logs','SELECT')
 and not has_table_privilege('anon','public.audit_logs','SELECT')
 and not has_any_column_privilege('anon','public.audit_logs','SELECT'),'all effective client table and column audit read grants absent');

set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)values
 ('99590000-0000-4000-8000-000000000001','AUDIT-API-ONLY-SYNTHETIC','collection','99590000-0000-4000-8000-000000000051','{"synthetic":true}');
select pg_temp.audit_assert(exists(select 1 from public.audit_logs where action='AUDIT-API-ONLY-SYNTHETIC'),'retained service audit write succeeds');
reset role;
create temp table audit_contexts(n integer,label text);
insert into audit_contexts values(1,'owner'),(2,'member'),(3,'outsider'),(4,'approved operator');
grant select on audit_contexts to authenticated;
set local role authenticated;
do $$declare r record;begin
 for r in select * from pg_temp.audit_contexts order by n loop
  perform set_config('request.jwt.claims',jsonb_build_object('sub','99590000-0000-4000-8000-00000000000'||r.n,
   'role','authenticated','session_id','99590000-0000-4000-8000-00000000001'||r.n,'exp',extract(epoch from clock_timestamp()+interval '1 hour')::bigint)::text,true);
  perform pg_temp.audit_deny('select count(*)from public.audit_logs',r.label||' direct table audit read denied');
  perform pg_temp.audit_deny('select metadata from public.audit_logs',r.label||' direct column audit read denied');
  if r.n<>4 then
   perform pg_temp.audit_deny('select public.admin_list_audit_logs(''AUDIT-API-ONLY-SYNTHETIC'',null)',r.label||' cannot cross into Admin audit RPC');
  end if;
 end loop;
end$$;
select pg_temp.audit_assert(jsonb_array_length(public.admin_list_audit_logs('AUDIT-API-ONLY-SYNTHETIC',null)->'rows')=1,
 'approved current audit.read operator can use retained owned RPC');
reset role;
update auth.sessions set not_after=clock_timestamp()-interval '1 second'where id='99590000-0000-4000-8000-000000000014';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"99590000-0000-4000-8000-000000000004","role":"authenticated","session_id":"99590000-0000-4000-8000-000000000014"}',true);
select pg_temp.audit_deny('select public.admin_list_audit_logs(''AUDIT-API-ONLY-SYNTHETIC'',null)','expired operator cannot use audit RPC');
reset role;
update auth.sessions set not_after=clock_timestamp()+interval '1 hour'where id='99590000-0000-4000-8000-000000000014';
delete from public.admin_role_permissions where permission_name='audit.read'and role_id=(select id from public.admin_roles where name='platform_owner');
set local role authenticated;
select pg_temp.audit_deny('select public.admin_list_audit_logs(''AUDIT-API-ONLY-SYNTHETIC'',null)','revoked audit.read permission cannot use owned RPC');
reset role;
set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select pg_temp.audit_deny('select id from public.audit_logs','anonymous direct audit column read denied');
select pg_temp.audit_deny('select public.admin_list_audit_logs(null,null)','anonymous audit RPC execute denied');
reset role;
select label from audit_results order by label;
select 'AUDIT_READ_API_ONLY_UAT_PASS: '||count(*)||' actual SQL boundary assertions'from audit_results;
rollback;
