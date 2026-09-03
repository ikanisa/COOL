\set ON_ERROR_STOP on
begin;
do $$ begin
  if current_database()<>'collect_platform_access_uat_20260902' then
    raise exception 'Dedicated platform-access UAT database required';
  end if;
end $$;
create function pg_temp.assert_true(ok boolean,message text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAIL: %',message; end if;
raise notice 'PASS %',message; end $$;
create function pg_temp.denied(statement text,expected text default null) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if expected is null or sqlstate=expected then
      raise notice 'PASS denied [%]: %',sqlstate,statement; return;
    end if;
    raise;
  end;
  raise exception 'Unexpectedly allowed: %',statement;
end $$;
create function pg_temp.actor(n int,session_number int default null) returns void language sql as $$
  select set_config('request.jwt.claims',jsonb_build_object(
    'sub','98200000-0000-4000-8000-'||lpad(n::text,12,'0'),'role','authenticated',
    'session_id','98210000-0000-4000-8000-'||lpad(coalesce(session_number,n)::text,12,'0'),
    'user_metadata',jsonb_build_object('is_platform_admin',true,'role','platform_owner'),
    'app_metadata',jsonb_build_object('role','platform_owner'))::text,true);
$$;
insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select ('98200000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,'authenticated','authenticated',
  '25078898200'||i,case when i=5 then null else now() end,'{}','{}' from generate_series(1,8)i;
update public.profiles set public_id='98200'||right(id::text,1) where id::text like '98200000%';
insert into public.admin_user_roles(user_id,role_id,reason)
select u::uuid,r.id,'Synthetic legacy grant without number approval' from public.admin_roles r,
  unnest(array['98200000-0000-4000-8000-000000000001','98200000-0000-4000-8000-000000000002'])u
where r.name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at)
select ('98210000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
  ('98200000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,clock_timestamp(),clock_timestamp()
from generate_series(1,8)i;
set local role authenticated;
select pg_temp.actor(1);
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'old role alone grants no platform access');
select pg_temp.assert_true(public.admin_current_user()='{}'::jsonb,'unapproved current identity is empty');
select pg_temp.denied($q$select public.admin_set_user_access('98200000-0000-4000-8000-000000000003',true,'No approval')$q$);
select pg_temp.denied($q$select public.admin_approve_whatsapp('98200000-0000-4000-8000-000000000003','+250788982003','Unapproved caller')$q$);
select pg_temp.denied($q$select public.admin_bootstrap_whatsapp_approval('98200000-0000-4000-8000-000000000001','+250788982001','Browser bootstrap')$q$,'42501');
select pg_temp.denied($q$select phone_e164 from collect_admin_access.whatsapp_approvals$q$,'42501');
select pg_temp.denied($q$select collect_admin_access.verified_phone('98200000-0000-4000-8000-000000000002')$q$,'42501');
reset role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.denied($q$select public.admin_bootstrap_platform_owner('98200000-0000-4000-8000-000000000001','Unapproved bootstrap')$q$,'42501');
select public.admin_bootstrap_whatsapp_approval('98200000-0000-4000-8000-000000000001','+250788982001','Explicit synthetic first Admin');
select public.admin_bootstrap_platform_owner('98200000-0000-4000-8000-000000000001','Synthetic bootstrap role');
select pg_temp.denied($q$select public.admin_bootstrap_whatsapp_approval('98200000-0000-4000-8000-000000000002','+250788982002','Second bootstrap denied')$q$,'42501');
reset role;
set local role authenticated;
select pg_temp.actor(1);
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'session predating approval is denied');
reset role;
update auth.sessions set created_at=clock_timestamp() where id='98210000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.actor(1);
select pg_temp.assert_true(public.has_admin_permission('admin_users.manage'),'approved verified operator with new session allowed');
select pg_temp.assert_true(public.admin_current_user()->>'user_id'='98200000-0000-4000-8000-000000000001','approved identity reaches Admin API');
select pg_temp.assert_true(not public.has_admin_permission('overview.read','98200000-0000-4000-8000-000000000002'),'cross-account permission probing denied');
select pg_temp.assert_true(public.admin_get_admin_user('98200000-0000-4000-8000-000000000002')->>'status'='approval_required',
 'legacy granted role is displayed as approval required, not active');
select pg_temp.assert_true((public.admin_list_admin_users(null,'active',25,0,'created_at_desc')->>'total')::int=1,
 'active Admin list excludes unapproved roles');
select pg_temp.assert_true((public.admin_list_admin_users(null,'active')->>'total')::int=1,
 'legacy two-argument list resolves to the bounded default signature');
select pg_temp.denied($q$select public.admin_set_user_access('98200000-0000-4000-8000-000000000002',true,'Role exists but no approval')$q$,'42501');
select pg_temp.denied($q$select public.admin_approve_whatsapp('98200000-0000-4000-8000-000000000003','+250788982004','Wrong verified identity')$q$,'22023');
select pg_temp.denied($q$select public.admin_approve_whatsapp('98200000-0000-4000-8000-000000000005','+250788982005','Unverified identity')$q$,'22023');
select pg_temp.denied($q$select public.admin_approve_whatsapp('98200000-0000-4000-8000-000000000003','0788982003','Local number not canonical')$q$,'22023');
select pg_temp.denied($q$select public.admin_approve_whatsapp('98200000-0000-4000-8000-000000000003','+250788982003','')$q$,'22023');
select pg_temp.denied($q$select public.admin_approve_whatsapp('98200000-0000-4000-8000-000000000001','+250788982001','Self renewal')$q$,'42501');
select pg_temp.denied($q$select public.admin_revoke_whatsapp_approval('98200000-0000-4000-8000-000000000001','Self revoke')$q$,'42501');
select pg_temp.assert_true(public.admin_approve_whatsapp('98200000-0000-4000-8000-000000000003','+250788982003','Synthetic approval')=
  '{"ok":true,"status":"approved","user_id":"98200000-0000-4000-8000-000000000003"}'::jsonb,'exact approval receipt');
select public.admin_approve_whatsapp('98200000-0000-4000-8000-000000000003','+250788982003','Retry approval');
select pg_temp.assert_true(public.admin_get_whatsapp_approval('98200000-0000-4000-8000-000000000003')->>'phone_masked'='+***2003','approval response masks number');
select pg_temp.assert_true((public.admin_list_admin_users(null,'approved',25,0,'created_at_desc')->>'total')::int=1,
 'approved account without a role is visible as pending activation');
reset role;
select pg_temp.assert_true(not exists(select 1 from public.admin_user_roles where user_id='98200000-0000-4000-8000-000000000003'),'approval alone grants no role');
select pg_temp.assert_true((select count(*)=1 from public.audit_logs where entity_id='98200000-0000-4000-8000-000000000003' and action='admin.whatsapp.approved'),'approval retry audited once');
set local role authenticated;
select pg_temp.actor(1);
select public.admin_set_user_access('98200000-0000-4000-8000-000000000003',true,'Activate approved operator');
select public.admin_set_user_access('98200000-0000-4000-8000-000000000003',true,'Retry activation');
select pg_temp.actor(3);
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'activation does not revive pre-approval session');
reset role;
update auth.sessions set created_at=clock_timestamp() where id='98210000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.actor(3);
select pg_temp.assert_true(public.has_admin_permission('overview.read'),'approved activated operator new session allowed');
select pg_temp.actor(1);
select public.admin_set_user_access('98200000-0000-4000-8000-000000000003',false,'Synthetic role-only deactivation');
select public.admin_set_user_access('98200000-0000-4000-8000-000000000003',true,'Synthetic role-only reactivation');
select pg_temp.actor(3);
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'role reactivation alone cannot revive an old session');
reset role;
update auth.sessions set created_at=clock_timestamp() where id='98210000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.actor(3);
select pg_temp.assert_true(public.has_admin_permission('overview.read'),'new session after role reactivation is allowed');
select pg_temp.actor(3,1);
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'another operator session ID is denied');
select set_config('request.jwt.claims','{"sub":"98200000-0000-4000-8000-000000000003","role":"authenticated","session_id":"invalid"}',true);
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'malformed session rejected without casting error');
reset role;
update auth.users set phone='250788982099' where id='98200000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.actor(3);
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'changed verified phone invalidates previous approval');
reset role;
update auth.users set phone='250788982003',banned_until=now()+interval '1 hour' where id='98200000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'banned operator is denied');
reset role;
update auth.users set banned_until=null where id='98200000-0000-4000-8000-000000000003';
update auth.users set deleted_at=now() where id='98200000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'soft-deleted operator is denied');
reset role;
update auth.users set deleted_at=null,is_anonymous=true where id='98200000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'anonymous identity cannot be an Admin');
reset role;
update auth.users set is_anonymous=false where id='98200000-0000-4000-8000-000000000003';
update collect_admin_access.whatsapp_approvals set approved_at=now()-interval '2 hours',expires_at=now()-interval '1 hour'
 where user_id='98200000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'expired approval is denied even with an active role');
select pg_temp.actor(1);
select pg_temp.assert_true(public.admin_get_whatsapp_approval('98200000-0000-4000-8000-000000000003')->>'status'='expired',
 'expired approval is displayed accurately');
reset role;
update collect_admin_access.whatsapp_approvals set expires_at=null where user_id='98200000-0000-4000-8000-000000000003';
update auth.sessions set not_after=now()-interval '1 second' where id='98210000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.actor(3);
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'expired session is denied');
reset role;
update auth.sessions set not_after=null where id='98210000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.actor(1);
select public.admin_revoke_whatsapp_approval('98200000-0000-4000-8000-000000000003','Synthetic revocation');
select public.admin_revoke_whatsapp_approval('98200000-0000-4000-8000-000000000003','Retry revocation');
select pg_temp.actor(3);
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'same unexpired JWT denied immediately after revocation');
select pg_temp.denied($q$select public.admin_overview()$q$);
select pg_temp.actor(1);
select public.admin_approve_whatsapp('98200000-0000-4000-8000-000000000003','+250788982003','Reapprove identity');
select pg_temp.actor(3);
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'reapproval restores neither role nor old session');
select pg_temp.actor(1);
select public.admin_set_user_access('98200000-0000-4000-8000-000000000003',true,'Reactivate approved identity');
select pg_temp.actor(3);
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'reactivation still rejects session from revoked approval');
reset role;
delete from auth.sessions where id='98210000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(not public.has_admin_permission('overview.read'),'removed session cannot use stale JWT');
select pg_temp.actor(4);
select pg_temp.assert_true(not public.has_admin_permission('admin_users.manage'),'forged JWT metadata does not grant Admin');
select pg_temp.denied($q$select public.admin_get_whatsapp_approval('98200000-0000-4000-8000-000000000001')$q$);
select pg_temp.denied($q$insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,reason) values('98200000-0000-4000-8000-000000000004','+250788982004','Self approve')$q$,'42501');
reset role;
-- A group owner/admin still works independently of platform preapproval.
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type)
values('98200000-0000-4000-8000-000000000010','platform-scope-group','98200000-0000-4000-8000-000000000004','Synthetic private group','Other','private','private','other');
insert into public.collection_members(collection_id,user_id,role,status) values
('98200000-0000-4000-8000-000000000010','98200000-0000-4000-8000-000000000004','owner','active'),
('98200000-0000-4000-8000-000000000010','98200000-0000-4000-8000-000000000006','member','active');
set local role authenticated;
select pg_temp.actor(4);
select public.add_group_admin('98200000-0000-4000-8000-000000000010','982006');
select pg_temp.actor(6);
select pg_temp.assert_true(public.user_is_collection_admin('98200000-0000-4000-8000-000000000010'),'unapproved group admin keeps group authority');
select pg_temp.assert_true(not public.is_platform_admin(),'group admin never becomes platform Admin');
reset role;
select pg_temp.assert_true(not has_function_privilege('anon','public.admin_approve_whatsapp(uuid,text,text,timestamptz)','execute')
 and not has_function_privilege('authenticated','public.admin_bootstrap_whatsapp_approval(uuid,text,text)','execute'),
 'anonymous approval and browser bootstrap grants denied');
select pg_temp.assert_true(not has_function_privilege('authenticated','public.admin_grant_user_role(uuid,text,text)','execute')
 and not has_function_privilege('service_role','public.admin_grant_user_role(uuid,text,text)','execute'),'legacy role-grant bypass revoked');
select pg_temp.assert_true(not exists(select 1 from public.audit_logs where metadata::text like '%+250788982%'),
 'audit metadata does not contain full WhatsApp numbers');
select 'PLATFORM_ADMIN_ACCESS_CONTRACT_PASS';
rollback;
