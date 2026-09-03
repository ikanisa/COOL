\set ON_ERROR_STOP on
begin;
set local statement_timeout = '30s';

do $$ begin
  if coalesce(current_setting('collect.recovery_drill', true), '')
       <> 'production-archive-v1'
     and current_database() <> 'collect_hybrid_money_uat_20260903'
     or exists (
       select 1 from public.collections collection
       where collection.title like 'Roster control UAT%'
     ) then
    raise exception 'Fresh isolated hybrid roster UAT database required';
  end if;
end $$;

create temp table uat_baseline as
select count(*)::bigint as auth_user_count from auth.users;
create temp table test_results(label text primary key);
grant all on pg_temp.test_results to authenticated;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values(label);
end;
$$;
create function pg_temp.expect_error(command text, fragment text, label text)
returns void language plpgsql as $$
declare caught text;
begin
  begin execute command; exception when others then caught := sqlerrm; end;
  perform pg_temp.assert_true(
    caught is not null and position(fragment in caught) > 0,
    label
  );
end;
$$;

insert into auth.users(
  id, aud, role, phone, phone_confirmed_at, raw_app_meta_data, raw_user_meta_data
) values (
  '99000000-0000-4000-8000-000000000001',
  'authenticated',
  'authenticated',
  '250788990001',
  now(),
  '{}',
  '{}'
);
update public.profiles set is_platform_admin = true
where id = '99000000-0000-4000-8000-000000000001';
insert into public.admin_user_roles(user_id, role_id, granted_by, reason, created_at)
select
  '99000000-0000-4000-8000-000000000001',
  role.id,
  '99000000-0000-4000-8000-000000000001',
  'Synthetic roster import UAT',
  now() - interval '2 seconds'
from public.admin_roles role where role.name = 'platform_owner';
insert into auth.sessions(id, user_id, created_at, updated_at, not_after)
values (
  '99000000-0000-4000-8000-000000000099',
  '99000000-0000-4000-8000-000000000001',
  now() - interval '1 second',
  now(),
  now() + interval '1 hour'
);
do $$ begin
  if to_regclass('collect_admin_access.whatsapp_approvals') is not null then
    execute $q$
      insert into collect_admin_access.whatsapp_approvals(
        user_id, phone_e164, approved_at, approved_by, reason
      ) values (
        '99000000-0000-4000-8000-000000000001', '+250788990001',
        now() - interval '2 seconds',
        '99000000-0000-4000-8000-000000000001',
        'Synthetic roster import UAT'
      )
    $q$;
  end if;
end $$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"99000000-0000-4000-8000-000000000099"}',
  true
);
select pg_temp.expect_error(
  $q$select public.admin_create_assisted_group_with_roster(
    'Roster control UAT disabled',
    '[{"member_name":"Alice","momo_name":"ALICE","momo_number":"0788999001"}]',
    'Synthetic disabled flag check',
    '99000000-0000-4000-8000-000000000101',
    '99000000-0000-4000-8000-000000000102'
  )$q$,
  'disabled',
  'feature flag blocks assisted group and roster creation'
);
reset role;

update public.feature_flags set enabled = true
where key = 'hybrid_member_onboarding';
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"99000000-0000-4000-8000-000000000099"}',
  true
);
select set_config(
  'collect.roster_result',
  public.admin_create_assisted_group_with_roster(
    'Roster control UAT group',
    '[
      {"member_name":"Alice A","momo_name":"ALICE UWASE","momo_number":"0788999456"},
      {"member_name":"Bob B","momo_name":"BOB MUGISHA","momo_number":"0738999457"}
    ]',
    'Reviewed synthetic assisted roster',
    '99000000-0000-4000-8000-000000000103',
    '99000000-0000-4000-8000-000000000104'
  )::text,
  true
);
select pg_temp.assert_true(
  (current_setting('collect.roster_result')::jsonb->>'roster_count')::int = 2
    and current_setting('collect.roster_result')::jsonb->>'share_code_ready' = 'true',
  'one transaction creates the private group, share code and reviewed roster'
);
select pg_temp.assert_true(
  public.get_group_share_code(
    (current_setting('collect.roster_result')::jsonb->>'collection_id')::uuid
  )::uuid is not null,
  'assisted group has a usable share link and QR code secret'
);
select set_config(
  'collect.roster_additional',
  public.admin_add_assisted_roster(
    (current_setting('collect.roster_result')::jsonb->>'collection_id')::uuid,
    '[{"member_name":"Carine C","momo_name":"CARINE UWERA","momo_number":"0798999458"}]',
    '99000000-0000-4000-8000-000000000107',
    'Reviewed synthetic existing-group roster addition'
  )::text,
  true
);
select pg_temp.assert_true(
  jsonb_array_length(
    current_setting('collect.roster_additional')::jsonb->'rows'
  ) = 1,
  'public Admin roster boundary adds one reviewed member to an existing group'
);
reset role;
select pg_temp.assert_true(
  (
    select count(*) from public.collection_members membership
    where membership.collection_id = (
      current_setting('collect.roster_result')::jsonb->>'collection_id'
    )::uuid
      and membership.member_record_id is not null
      and membership.role = 'member'
      and membership.status = 'active'
  ) = 3,
  'reviewed offline members belong to the assisted group'
);
select pg_temp.assert_true(
  (select count(*) from auth.users)
    = (select auth_user_count + 1 from pg_temp.uat_baseline),
  'offline roster creates no fake Auth users'
);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"99000000-0000-4000-8000-000000000001","role":"authenticated","session_id":"99000000-0000-4000-8000-000000000099"}',
  true
);
select pg_temp.assert_true(
  public.admin_create_assisted_group_with_roster(
    'Roster control UAT group',
    '[
      {"member_name":"Alice A","momo_name":"ALICE UWASE","momo_number":"0788999456"},
      {"member_name":"Bob B","momo_name":"BOB MUGISHA","momo_number":"0738999457"}
    ]',
    'Reviewed synthetic assisted roster',
    '99000000-0000-4000-8000-000000000103',
    '99000000-0000-4000-8000-000000000104'
  )->>'replay' = 'true',
  'whole assisted creation request is idempotent'
);
select pg_temp.expect_error(
  $q$select public.admin_create_assisted_group_with_roster(
    'Roster control UAT invalid',
    '[{"member_name":"Bad","momo_name":"BAD","momo_number":"***456"}]',
    'Reviewed invalid roster rollback',
    '99000000-0000-4000-8000-000000000105',
    '99000000-0000-4000-8000-000000000106'
  )$q$,
  'Invalid Rwanda MoMo number',
  'invalid roster rolls the complete group transaction back'
);
reset role;
select pg_temp.assert_true(
  not exists (
    select 1 from public.collections collection
    where collection.title = 'Roster control UAT invalid'
  ),
  'failed roster leaves no partial group'
);
select pg_temp.assert_true(
  not has_function_privilege(
    'anon',
    'public.admin_create_assisted_group_with_roster(text,jsonb,text,uuid,uuid)',
    'EXECUTE'
  )
    and has_function_privilege(
      'authenticated',
      'public.admin_create_assisted_group_with_roster(text,jsonb,text,uuid,uuid)',
      'EXECUTE'
    )
    and not has_table_privilege(
      'authenticated',
      'collect_hybrid.member_momo_identities',
      'SELECT'
    )
    and not has_function_privilege(
      'authenticated',
      'collect_hybrid.add_roster(uuid,jsonb,uuid,text)',
      'EXECUTE'
    )
    and not has_function_privilege(
      'authenticated',
      'collect_hybrid.create_assisted_group_with_share(text,text,uuid)',
      'EXECUTE'
    ),
  'browser receives only the narrow reviewed RPC'
);

select 'PASS ' || label from pg_temp.test_results order by label;
select 'HYBRID_ROSTER_IMPORT_UAT_PASS: ' || count(*) || ' assertions; synthetic rollback only'
from pg_temp.test_results;
rollback;
