\set ON_ERROR_STOP on
begin;
do $$ begin
  if current_database() <> 'collect_uat_20260902' then
    raise exception 'Disposable Collect UAT database required';
  end if;
end $$;
create function pg_temp.assert_true(ok boolean, message text) returns void
language plpgsql as $$ begin
  if ok is not true then raise exception 'FAIL: %', message; end if;
end $$;
create function pg_temp.expect_denied(statement text, expected_state text default '42501')
returns void language plpgsql as $$ begin
  begin execute statement;
  exception when others then
    if sqlstate = expected_state then return; end if;
    raise;
  end;
  raise exception 'Unexpectedly allowed: %', statement;
end $$;

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select ('98000000-0000-4000-8000-' || lpad(i::text,12,'0'))::uuid,
  'authenticated','authenticated','25078898000'||i,now(),'{}','{}'
from generate_series(1,8) i;
update public.profiles set public_id='98000'||right(id::text,1)
where id::text like '98000000-0000-4000-8000-%';
insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type,is_platform_sponsored)
values
 ('98000000-0000-4000-8000-000000000010','admin-contract-private','98000000-0000-4000-8000-000000000001','Synthetic group admin','Other','private','private','other',false),
 ('98000000-0000-4000-8000-000000000011','admin-contract-official','98000000-0000-4000-8000-000000000001','Synthetic official','Other','public_approved','public_approved','other',true);
insert into public.collection_members(collection_id,user_id,role,status)
select '98000000-0000-4000-8000-000000000010',
  ('98000000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid,
  case when i=1 then 'owner' when i=3 then 'admin' else 'member' end::public.member_role,
  case when i=4 then 'removed' when i=5 then 'left' when i=6 then 'invited' else 'active' end::public.member_status
from generate_series(1,6)i;
insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network,label)
values ('98000000-0000-4000-8000-000000000010','98000000-0000-4000-8000-000000000001',
 '0788980001',encode(extensions.digest('+250788980001','sha256'),'hex'),'mtn_momo','Synthetic unchanged payee');
insert into public.admin_user_roles(user_id,role_id,granted_by,reason)
select '98000000-0000-4000-8000-000000000008',id,'98000000-0000-4000-8000-000000000008','Synthetic scope test'
from public.admin_roles where name='platform_owner';
create temporary table before_groups as select * from public.collections where id::text like '98000000%';
create temporary table before_receivers as select * from public.collection_receivers where collection_id::text like '98000000%';
create temporary table before_profiles as select * from public.profiles where id::text like '98000000%';
create temporary table before_roles as select * from public.admin_user_roles;

set local role authenticated;
-- Group admin, ordinary member, inactive member, outsider and central operator
-- are not the group's owner, even if they know its ID.
do $$ declare i int; begin
  for i in 2..8 loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub',
      '98000000-0000-4000-8000-'||lpad(i::text,12,'0'),'role','authenticated')::text,true);
    perform pg_temp.expect_denied($q$select public.add_group_admin('98000000-0000-4000-8000-000000000010','980002')$q$);
  end loop;
end $$;
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_temp.expect_denied($q$select public.add_group_admin('98000000-0000-4000-8000-000000000011','980002')$q$);
select pg_temp.expect_denied($q$select public.add_group_admin('98000000-0000-4000-8000-000000000099','980002')$q$);
do $$ declare target text; begin
  foreach target in array array['','98000','9800020','98-002','abc980002','980001','980004','980005','980006','980007','999999'] loop
    perform pg_temp.expect_denied(format('select public.add_group_admin(%L,%L)',
      '98000000-0000-4000-8000-000000000010',target),'22023');
  end loop;
end $$;
select pg_temp.assert_true(public.add_group_admin('98000000-0000-4000-8000-000000000010',' 980002 ')=
  '{"collection_id":"98000000-0000-4000-8000-000000000010","public_id":"980002","role":"admin","status":"active"}'::jsonb,
  'exact minimal receipt, ordinary owner and member need no phone preapproval');
select public.add_group_admin('98000000-0000-4000-8000-000000000010','980002');
select public.add_group_admin('98000000-0000-4000-8000-000000000010','980003');
select pg_temp.assert_true((select count(*)=1 from jsonb_array_elements(
  public.list_current_member_group_roster('98000000-0000-4000-8000-000000000010'))m
  where m->>'public_id'='980002' and m->>'role'='admin' and m->>'status'='active'),
  'authoritative roster exposes one active admin, not invited');
select pg_temp.expect_denied($q$update public.collection_members set role='owner' where user_id='98000000-0000-4000-8000-000000000002'$q$);
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select pg_temp.assert_true(not public.has_admin_permission('admin_users.write'),'group admin has no platform privileges');
select pg_temp.expect_denied($q$select public.add_group_admin('98000000-0000-4000-8000-000000000010','980003')$q$);
select pg_temp.expect_denied($q$select public.archive_group('98000000-0000-4000-8000-000000000010')$q$);
select set_config('request.jwt.claims','{}',true);
select pg_temp.expect_denied($q$select public.add_group_admin('98000000-0000-4000-8000-000000000010','980002')$q$,'28000');
reset role;
select pg_temp.assert_true(not exists((select * from before_groups except select * from public.collections)
  union all (select * from public.collections where id::text like '98000000%' except select * from before_groups)),
  'owner and group fields unchanged');
select pg_temp.assert_true(not exists(select * from before_receivers except select * from public.collection_receivers),'payment route unchanged');
select pg_temp.assert_true(not exists(select * from before_profiles except select * from public.profiles),'member profiles unchanged');
select pg_temp.assert_true(not exists((select * from before_roles except select * from public.admin_user_roles)
  union all (select * from public.admin_user_roles except select * from before_roles)),'platform grants exactly unchanged');
select pg_temp.assert_true((select count(*)=1 from public.audit_logs where entity_id='98000000-0000-4000-8000-000000000010'
  and action='collection.admin_added'),'one audited grant despite retry and existing admin');
select pg_temp.assert_true(not has_function_privilege('anon','public.add_group_admin(uuid,text)','execute')
  and not has_function_privilege('anon','collect_member_actions.add_owned_group_admin(uuid,text)','execute'),'anonymous execution denied');
select pg_temp.assert_true(not has_schema_privilege('authenticated','private','usage')
  and not has_schema_privilege('authenticated','collect_member_actions','create'),'no broad namespace grant');
update public.collections set archived_at=now(),public_status='archived',visibility='archived'
where id='98000000-0000-4000-8000-000000000010';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"98000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_temp.expect_denied($q$select public.add_group_admin('98000000-0000-4000-8000-000000000010','980002')$q$,'22023');
reset role;
select 'GROUP_ADMIN_CONTRACT_PASS';
rollback;
