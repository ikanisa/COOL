\set ON_ERROR_STOP on
begin;
set local statement_timeout = '30s';
do $$ begin
  if current_database() <> 'collect_directory_presentation_v2_uat_20260903'
     or exists (select 1 from auth.users) then
    raise exception 'Empty isolated LOCAL directory fixture required';
  end if;
end $$;
create temp table test_results(label text primary key);
grant all on pg_temp.test_results to authenticated;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$ begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values(label);
end $$;

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select ('97100000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  'authenticated','authenticated','25078897100'||n,now(),'{}','{}'
from generate_series(1,4) n;
-- A legacy boolean is deliberately wrong in both directions.
update public.profiles set is_platform_admin = (right(id::text,1) = '2');
insert into public.admin_user_roles(user_id,role_id,granted_by,reason,created_at)
select u.id,r.id,u.id,'Synthetic directory UAT',now()-interval '2 seconds'
from auth.users u cross join public.admin_roles r
where r.name='platform_owner' and right(u.id::text,1) in ('1','2','3');
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,approved_by,reason,revoked_at)
select id,'+'||phone,now()-interval '2 seconds',id,'Synthetic directory UAT',
  case when right(id::text,1)='2' then now() end
from auth.users where right(id::text,1) in ('1','2','4');
insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
values('97100000-0000-4000-8000-000000000099','97100000-0000-4000-8000-000000000001',now()-interval '1 second',now(),now()+interval '1 hour');
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type,contribution_visibility,allow_anonymous,diaspora_enabled)
values('97100000-0000-4000-8000-000000000100','synthetic-directory-uat','97100000-0000-4000-8000-000000000001','Synthetic directory UAT','Family / friends','private','private','ikimina','members',false,false);
insert into public.collection_members(collection_id,user_id,role,status)
select '97100000-0000-4000-8000-000000000100',id,'member','active' from auth.users;
insert into collect_hybrid.member_records(id,collect_id,origin,created_at)
values('97100000-0000-4000-8000-000000000200',public.generate_public_id(),'admin_assisted','2026-01-01T00:00:00Z');
insert into collect_hybrid.member_momo_identities(member_id,member_name,momo_name,momo_number)
values('97100000-0000-4000-8000-000000000200','SYNTHETIC OFFLINE','SYNTHETIC MOMO','+250788971200');
insert into public.collection_members(collection_id,member_record_id,role,status)
values('97100000-0000-4000-8000-000000000100','97100000-0000-4000-8000-000000000200','member','active');
update collect_hybrid.member_records set created_at='2026-02-01T00:00:00Z'
where linked_user_id is not null;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"97100000-0000-4000-8000-000000000001","role":"authenticated","session_id":"97100000-0000-4000-8000-000000000099"}',true);
select pg_temp.assert_true(public.admin_list_members()->>'total'='5','app and accountless member records are included');
select pg_temp.assert_true(public.admin_list_members(null,'admin')->>'total'='1','approval and active owner role override stale profile boolean');
select pg_temp.assert_true(public.admin_list_members('SYNTHETIC MOMO')->'rows'->0->>'account_state'='feature_phone','registered MoMo name finds an accountless member');
select pg_temp.assert_true(public.admin_list_members('SYNTHETIC OFFLINE')->'rows'->0->>'whatsapp_masked' is null,'offline member has no invented WhatsApp identity');
select pg_temp.assert_true(position('+250788971200' in public.admin_list_members()::text)=0,'full MoMo phone stays masked');
select pg_temp.assert_true(public.admin_list_members(null,null,2,0,'created_at_asc')->'rows'->0->>'id'='97100000-0000-4000-8000-000000000200','oldest sort survives JSON aggregation');
select pg_temp.assert_true(public.admin_list_members(null,null,2,0,'created_at_desc')->'rows'->0->>'id'='97100000-0000-4000-8000-000000000001','newest sort has deterministic identity tie break');
select pg_temp.assert_true(public.admin_list_members(null,null,2,2,'created_at_desc')->'rows'->0->>'id'='97100000-0000-4000-8000-000000000003','stable next page ordering');
select pg_temp.assert_true(public.admin_list_members(null,null,2,99)->>'total'='5' and public.admin_list_members(null,null,2,99)->'rows'='[]'::jsonb,'empty later page preserves filtered total');
reset role;
-- Internal people helper has the same ordering/count contract; it remains
-- inaccessible to browser callers and is called only by the public wrappers.
select pg_temp.assert_true(public._admin_list_people_by_membership(true,null,'admin',25,0,'created_at_asc')->>'total'='1','app people helper uses effective approval');
select pg_temp.assert_true(public._admin_list_people_by_membership(true,null,null,1,99,'created_at_asc')->>'total'='4','app people empty-page total remains correct');
select pg_temp.assert_true(not has_function_privilege('authenticated','public._admin_list_people_by_membership(boolean,text,text,integer,integer,text)','EXECUTE'),'internal people helper stays private');
select pg_temp.assert_true(not has_function_privilege('anon','public.admin_list_members(text,text,integer,integer,text)','EXECUTE'),'anonymous member directory remains denied');
select pg_temp.assert_true((select subtitle='App and feature-phone members with an active group membership.' from public.admin_queue_specs where rpc_name='admin_list_members'),'runtime queue copy includes feature-phone members');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"97100000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$ declare denied boolean:=false; begin
  begin perform public.admin_list_members(); exception when others then denied:=true; end;
  perform pg_temp.assert_true(denied,'unapproved user cannot read directory');
end $$;
reset role;
select 'PASS '||label from pg_temp.test_results order by label;
select 'HYBRID_DIRECTORY_PRESENTATION_UAT_PASS '||count(*) from pg_temp.test_results;
rollback;
