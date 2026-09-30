\set ON_ERROR_STOP on
-- Rollback-only Admin session, approval and role fencing on the task-owned
-- synthetic historical financial fixture. No raw body is printed.
begin;
set local statement_timeout = '30s';

do $$ begin
  if current_database() <> 'postgres'
     or (select count(*) from supabase_migrations.schema_migrations) <> 133
     or (select max(version) from supabase_migrations.schema_migrations)
       <> '20260928174000'
     or (select count(*) from auth.users) <> 1
     or (select count(*) from public.payments) <> 2
     or (select count(*) from public.raw_payment_sms) <> 3
     or not exists (select 1 from public.admin_roles
       where name = 'platform_owner') then
    raise exception 'Exact isolated historical financial fixture required';
  end if;
end $$;

create temp table test_results(label text primary key);
grant all on pg_temp.test_results to authenticated;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values(label);
end $$;
create function pg_temp.expect_error(command text, fragment text, label text)
returns void language plpgsql as $$
declare caught text;
begin
  begin execute command; exception when others then caught := sqlerrm; end;
  perform pg_temp.assert_true(
    caught is not null and position(fragment in caught) > 0, label);
end $$;

insert into auth.users(
  id, aud, role, phone, phone_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values (
  '99100000-0000-4000-8000-000000000003',
  'authenticated', 'authenticated', '250788991003', now(), '{}', '{}'
);
insert into collect_admin_access.whatsapp_approvals(
  user_id, phone_e164, approved_at, reason
) values (
  '99100000-0000-4000-8000-000000000003', '+250788991003',
  now() - interval '2 seconds', 'Synthetic Admin fencing UAT'
);
insert into public.admin_user_roles(
  user_id, role_id, granted_by, reason, created_at
)
select '99100000-0000-4000-8000-000000000003', role.id,
  '99100000-0000-4000-8000-000000000003',
  'Synthetic Admin fencing UAT', now() - interval '2 seconds'
from public.admin_roles role where role.name = 'platform_owner';
insert into auth.sessions(id, user_id, created_at, updated_at, not_after)
values (
  '99100000-0000-4000-8000-000000000099',
  '99100000-0000-4000-8000-000000000003',
  now() - interval '1 second', now(), now() + interval '1 hour'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000003",'
  || '"role":"authenticated",'
  || '"session_id":"99100000-0000-4000-8000-000000000099"}', true);
select pg_temp.assert_true(
  auth.uid() = '99100000-0000-4000-8000-000000000003',
  'approved operator JWT resolves to the expected Auth user');
select pg_temp.assert_true(
  public.has_admin_permission('payments.read', auth.uid())
  and public.has_admin_permission('sms.raw.reveal', auth.uid()),
  'approved platform owner has current read and reveal permissions');
select pg_temp.assert_true(
  public.admin_get_payment('99300000-0000-4000-8000-000000000221')
    ->>'id' = '99300000-0000-4000-8000-000000000221',
  'approved operator can read a synthetic payment detail');
select pg_temp.assert_true(
  public.admin_reveal_raw_sms(
    '99300000-0000-4000-8000-000000000201',
    'Synthetic permission audit') ->>'ok' = 'true',
  'approved operator reveal succeeds with a reason');
reset role;
select pg_temp.assert_true(
  (select count(*) from public.admin_sensitive_access_logs
    where actor_user_id = '99100000-0000-4000-8000-000000000003'
      and entity_id = '99300000-0000-4000-8000-000000000201') = 1,
  'approved raw-SMS reveal creates one sensitive-access audit row');

update collect_admin_access.whatsapp_approvals
set revoked_at = clock_timestamp(),
  revoke_reason = 'Synthetic approval revocation'
where user_id = '99100000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(
  not public.has_admin_permission('payments.read', auth.uid())
  and public.admin_current_user() = '{}'::jsonb,
  'revoked approval immediately hides Admin identity and permissions');
select pg_temp.expect_error(
  $$select public.admin_reveal_raw_sms(
    '99300000-0000-4000-8000-000000000201',
    'Synthetic permission audit')$$,
  'Admin permission sms.raw.reveal required',
  'revoked approval blocks the same-session raw-SMS reveal');
reset role;

update collect_admin_access.whatsapp_approvals
set revoked_at = null, revoke_reason = null
where user_id = '99100000-0000-4000-8000-000000000003';
update public.admin_user_roles
set revoked_at = clock_timestamp(),
  revoke_reason = 'Synthetic role revocation'
where user_id = '99100000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(
  not public.has_admin_permission('payments.read', auth.uid())
  and public.admin_current_user() = '{}'::jsonb,
  'revoked platform role immediately hides Admin identity and permissions');
select pg_temp.expect_error(
  $$select public.admin_get_payment(
    '99300000-0000-4000-8000-000000000221')$$,
  'Admin permission payments.read required',
  'revoked role blocks the same-session payment detail');
reset role;

update public.admin_user_roles
set revoked_at = null, revoke_reason = null
where user_id = '99100000-0000-4000-8000-000000000003';
update auth.sessions
set not_after = now() - interval '1 second'
where id = '99100000-0000-4000-8000-000000000099';
set local role authenticated;
select pg_temp.assert_true(
  not public.has_admin_permission('payments.read', auth.uid())
  and public.admin_current_user() = '{}'::jsonb,
  'expired Auth session blocks Admin access despite approval and role');
select pg_temp.expect_error(
  $$select public.admin_get_payment(
    '99300000-0000-4000-8000-000000000221')$$,
  'Admin permission payments.read required',
  'expired session blocks payment detail');
reset role;

update auth.sessions
set not_after = now() + interval '1 hour'
where id = '99100000-0000-4000-8000-000000000099';
update collect_admin_access.whatsapp_approvals
set approved_at = clock_timestamp()
where user_id = '99100000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(
  not public.has_admin_permission('payments.read', auth.uid()),
  'session predating renewed WhatsApp approval cannot regain Admin access');
reset role;

update collect_admin_access.whatsapp_approvals
set approved_at = now() - interval '2 seconds'
where user_id = '99100000-0000-4000-8000-000000000003';
update public.admin_user_roles
set created_at = clock_timestamp()
where user_id = '99100000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.assert_true(
  not public.has_admin_permission('payments.read', auth.uid()),
  'session predating renewed platform role cannot regain Admin access');
reset role;

update public.admin_user_roles
set created_at = now() - interval '2 seconds'
where user_id = '99100000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000003",'
  || '"role":"authenticated"}', true);
select pg_temp.assert_true(
  not public.has_admin_permission('payments.read', auth.uid()),
  'Admin access requires a current Auth session claim');
reset role;

select pg_temp.assert_true(
  (select count(*) from public.payments) = 2
  and (select count(*) from public.raw_payment_sms) = 3
  and (select count(*) from public.ledger_entries) = 2,
  'Admin fencing probes preserve original financial row counts');
select 'ADMIN_PERMISSION_REVOCATION_UAT_PASS: ' || count(*)
  || ' assertions; synthetic rollback only'
from pg_temp.test_results;
rollback;
