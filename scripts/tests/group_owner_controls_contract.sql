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
  begin
    execute statement;
  exception when others then
    if sqlstate = expected_state then return; end if;
    raise;
  end;
  raise exception 'Unexpectedly allowed: %', statement;
end $$;

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select ('95000000-0000-4000-8000-' || lpad(i::text,12,'0'))::uuid,
  'authenticated','authenticated','25078895000'||i,now(),'{}','{}'
from generate_series(1,5) i;
update public.profiles set public_id='95000'||right(id::text,1)
where id::text like '95000000-0000-4000-8000-%';

insert into public.collections(id,slug,creator_user_id,title,category,visibility,public_status,collection_type,is_platform_sponsored)
values
 ('95000000-0000-4000-8000-000000000010','owner-controls-private','95000000-0000-4000-8000-000000000001','Synthetic owner controls','Other','private','private','other',false),
 ('95000000-0000-4000-8000-000000000011','owner-controls-platform','95000000-0000-4000-8000-000000000001','Synthetic official group','Other','public_approved','public_approved','other',true);
insert into public.collection_members(collection_id,user_id,role,status) values
 ('95000000-0000-4000-8000-000000000010','95000000-0000-4000-8000-000000000001','owner','active'),
 ('95000000-0000-4000-8000-000000000010','95000000-0000-4000-8000-000000000002','member','active'),
 ('95000000-0000-4000-8000-000000000010','95000000-0000-4000-8000-000000000003','admin','active'),
 ('95000000-0000-4000-8000-000000000010','95000000-0000-4000-8000-000000000004','owner','removed');
insert into public.collection_receivers(collection_id,receiver_user_id,momo_number,momo_number_hash,network,label)
values ('95000000-0000-4000-8000-000000000010','95000000-0000-4000-8000-000000000001',
 '0788950001',encode(extensions.digest('+250788950001','sha256'),'hex'),'mtn_momo','Synthetic route');
insert into public.admin_user_roles(user_id,role_id,granted_by,reason)
select '95000000-0000-4000-8000-000000000005',id,'95000000-0000-4000-8000-000000000005','Isolated owner controls test'
from public.admin_roles where name='platform_owner';

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
-- Positive path first: this failed with 42501 before the scoped repair.
select public.transfer_group_ownership('95000000-0000-4000-8000-000000000010','950002');
reset role;
select pg_temp.assert_true((select creator_user_id='95000000-0000-4000-8000-000000000002' from public.collections
 where id='95000000-0000-4000-8000-000000000010'),'new owner is authoritative');
select pg_temp.assert_true((select count(*)=1 from public.collection_members where collection_id='95000000-0000-4000-8000-000000000010'
 and role='owner' and status='active'),'one active owner role');
select pg_temp.assert_true(exists(select 1 from public.collection_members where collection_id='95000000-0000-4000-8000-000000000010'
 and user_id='95000000-0000-4000-8000-000000000001' and role='admin' and status='active'),'former owner remains a group admin');
select pg_temp.assert_true(exists(select 1 from public.collection_receivers where collection_id='95000000-0000-4000-8000-000000000010'
 and receiver_user_id='95000000-0000-4000-8000-000000000001' and momo_number='0788950001' and is_active),'transfer never changes payment route');
select pg_temp.assert_true((select count(*)=1 from public.audit_logs where entity_id='95000000-0000-4000-8000-000000000010'
 and action='collection.ownership_transferred'),'one ownership audit event');
select pg_temp.assert_true(not exists(select 1 from public.admin_user_roles where user_id in
 ('95000000-0000-4000-8000-000000000001','95000000-0000-4000-8000-000000000002')),'no platform privileges granted');

set local role authenticated;
-- Former owner, group admin, removed member, and platform operator cannot use
-- the member owner endpoint. Central Admin has a separate audited lifecycle.
do $$ declare candidate text; begin
  foreach candidate in array array['001','003','004','005'] loop
    perform set_config('request.jwt.claims',jsonb_build_object('sub','95000000-0000-4000-8000-000000000'||candidate,'role','authenticated')::text,true);
    perform pg_temp.expect_denied($q$select public.archive_group('95000000-0000-4000-8000-000000000010')$q$);
    perform pg_temp.expect_denied($q$select public.transfer_group_ownership('95000000-0000-4000-8000-000000000010','950004')$q$);
  end loop;
end $$;
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select pg_temp.assert_true(not public.has_admin_permission('admin_users.write'),'new group owner has no platform Admin rights');
select pg_temp.expect_denied($q$update public.collections set creator_user_id='95000000-0000-4000-8000-000000000002' where id='95000000-0000-4000-8000-000000000011'$q$);
select pg_temp.expect_denied($q$insert into public.collection_members(collection_id,user_id,role,status) values ('95000000-0000-4000-8000-000000000011','95000000-0000-4000-8000-000000000002','owner','active')$q$);
select pg_temp.expect_denied($q$select public.transfer_group_ownership('95000000-0000-4000-8000-000000000010','abc950004')$q$,'22023');
select pg_temp.expect_denied($q$select public.transfer_group_ownership('95000000-0000-4000-8000-000000000010','950002')$q$,'22023');
select pg_temp.expect_denied($q$select public.transfer_group_ownership('95000000-0000-4000-8000-000000000010','999999')$q$,'22023');
select pg_temp.expect_denied($q$select public.archive_group('95000000-0000-4000-8000-000000000099')$q$);
select public.archive_group('95000000-0000-4000-8000-000000000010');
select public.archive_group('95000000-0000-4000-8000-000000000010');
select pg_temp.expect_denied($q$select public.transfer_group_ownership('95000000-0000-4000-8000-000000000010','950003')$q$,'22023');
select pg_temp.assert_true(public.list_current_user_collections('95000000-0000-4000-8000-000000000010')->0->>'moderation_status'='archived','member catalogue reflects archived state');
-- Even the creator must use central Admin controls for a sponsored group.
select set_config('request.jwt.claims','{"sub":"95000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select pg_temp.expect_denied($q$select public.archive_group('95000000-0000-4000-8000-000000000011')$q$);
select pg_temp.expect_denied($q$select public.transfer_group_ownership('95000000-0000-4000-8000-000000000011','950003')$q$);
select set_config('request.jwt.claims','{}',true);
select pg_temp.expect_denied($q$select public.archive_group('95000000-0000-4000-8000-000000000010')$q$,'28000');
select pg_temp.expect_denied($q$select public.transfer_group_ownership('95000000-0000-4000-8000-000000000010','950003')$q$,'28000');
reset role;
select pg_temp.assert_true((select archived_at is not null and visibility='archived' and public_status='archived'
 from public.collections where id='95000000-0000-4000-8000-000000000010'),'archive state consistent');
select pg_temp.assert_true((select count(*)=1 from public.audit_logs where entity_id='95000000-0000-4000-8000-000000000010'
 and action='collection.archived'),'archive retries do not duplicate audit');
select pg_temp.assert_true((select archived_at is null and creator_user_id='95000000-0000-4000-8000-000000000001'
 from public.collections where id='95000000-0000-4000-8000-000000000011'),'official group unchanged');
select pg_temp.assert_true(not has_function_privilege('anon','public.archive_group(uuid)','execute')
 and not has_function_privilege('anon','public.transfer_group_ownership(uuid,text)','execute'),'anonymous API denied');
select pg_temp.assert_true(not has_schema_privilege('authenticated','private','usage'),
 'existing private helper namespace remains inaccessible');
select pg_temp.assert_true(not has_schema_privilege('authenticated','collect_member_actions','create')
 and not has_schema_privilege('anon','collect_member_actions','usage'),'action namespace cannot be modified or used anonymously');
select pg_temp.assert_true(not has_function_privilege('anon','collect_member_actions.archive_owned_group(uuid)','execute')
 and not has_function_privilege('anon','collect_member_actions.transfer_owned_group(uuid,text)','execute'),'implementation functions deny anonymous execution');
select 'GROUP_OWNER_CONTROLS_CONTRACT_PASS';
rollback;
