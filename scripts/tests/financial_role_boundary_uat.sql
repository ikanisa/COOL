\set ON_ERROR_STOP on
-- Rollback-only local role-boundary checks against the guarded historical fixture.
-- No raw SMS body or other sensitive return value is printed.
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
     or not exists (
       select 1 from public.collections
       where id = '99300000-0000-4000-8000-000000000010'
         and public_status = 'private'
     ) then
    raise exception 'Exact isolated historical financial fixture required';
  end if;
end $$;

create temp table test_results(label text primary key);
grant all on pg_temp.test_results to anon, authenticated;
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
  begin
    execute command;
  exception when others then
    caught := sqlerrm;
  end;
  perform pg_temp.assert_true(
    caught is not null and position(fragment in caught) > 0,
    label
  );
end $$;

select pg_temp.assert_true(
  not has_function_privilege('anon',
    'public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)',
    'execute')
  and not has_function_privilege('authenticated',
    'public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)',
    'execute')
  and has_function_privilege('service_role',
    'public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)',
    'execute'),
  'durable receipt ingress is service-only');
select pg_temp.assert_true(
  not has_function_privilege('anon',
    'public.finalize_attested_payment_sms(uuid)', 'execute')
  and not has_function_privilege('authenticated',
    'public.finalize_attested_payment_sms(uuid)', 'execute')
  and not has_function_privilege('authenticated',
    'public.confirm_provider_payment(uuid,text,text,text,text,bigint,timestamptz,text)',
    'execute'),
  'SMS finality and provider confirmation are not member entrypoints');
select pg_temp.assert_true(
  not has_table_privilege('anon', 'public.raw_payment_sms', 'select')
  and not has_table_privilege('authenticated', 'public.raw_payment_sms', 'select')
  and not has_column_privilege('authenticated',
    'public.raw_payment_sms', 'raw_body', 'select')
  and not has_table_privilege('authenticated', 'public.payments', 'update')
  and not has_table_privilege('authenticated', 'public.ledger_entries', 'insert')
  and has_table_privilege('service_role', 'public.raw_payment_sms', 'select'),
  'direct raw SMS and money-table grants deny public and member access');

insert into auth.users(
  id, aud, role, phone, phone_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values (
  '99100000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', '250788991002', now(), '{}', '{}'
);
select pg_temp.assert_true(
  not public.has_admin_permission('sms.raw.reveal',
    '99100000-0000-4000-8000-000000000002')
  and not public.has_admin_permission('payments.allocate',
    '99100000-0000-4000-8000-000000000002'),
  'outsider fixture has no Admin grant');

set local role anon;
select pg_temp.assert_true(auth.uid() is null,
  'anonymous context has no member identity');
select pg_temp.expect_error(
  $$select raw_body from public.raw_payment_sms limit 1$$,
  'permission denied',
  'anonymous direct raw SMS read is denied');
select pg_temp.assert_true(
  (select count(*) from public.public_collection_payment_route(
    '99300000-0000-4000-8000-000000000010')) = 0,
  'anonymous public route does not reveal a private group receiver');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000002","role":"authenticated"}',
  true);
select pg_temp.assert_true(
  auth.uid() = '99100000-0000-4000-8000-000000000002',
  'outsider JWT resolves to the synthetic non-admin member');
select pg_temp.assert_true(
  (select count(*) from public.admin_navigation_items) = 0
  and (select count(*) from public.admin_queue_specs) = 0,
  'non-admin RLS hides populated Admin configuration tables');
select pg_temp.assert_true(
  (public.list_current_member_history_page(
    '99300000-0000-4000-8000-000000000010', '', 'newest', null, 50)
    ->>'total_count')::bigint = 0,
  'outsider cannot read private group payment history');
select pg_temp.expect_error(
  $$select raw_body from public.raw_payment_sms limit 1$$,
  'permission denied',
  'member direct raw SMS read is denied');
select pg_temp.expect_error(
  $$select public.admin_get_payment(
    '99300000-0000-4000-8000-000000000221')$$,
  'Admin permission payments.read required',
  'member cannot use Admin payment detail');
select pg_temp.expect_error(
  $$select public.admin_reveal_raw_sms(
    '99300000-0000-4000-8000-000000000201', 'Boundary verification')$$,
  'Admin permission sms.raw.reveal required',
  'member cannot reveal a raw SMS through Admin RPC');
select pg_temp.expect_error(
  $$select public.admin_manual_allocate_payment(
    '99300000-0000-4000-8000-000000000211',
    '99300000-0000-4000-8000-000000000010',
    '99300000-0000-4000-8000-000000000302',
    'Boundary verification')$$,
  'Admin permission payments.allocate required',
  'member cannot allocate an observed payment');
select pg_temp.expect_error(
  $$select public.admin_reverse_momo_payment(
    '99300000-0000-4000-8000-000000000221',
    'Boundary verification',
    '99300000-0000-4000-8000-000000000499')$$,
  'Admin permission payments.allocate required',
  'member cannot reverse a posted payment');
reset role;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000001","role":"authenticated"}',
  true);
select pg_temp.assert_true(
  (public.list_current_member_history_page(
    '99300000-0000-4000-8000-000000000010', '', 'newest', null, 50)
    ->>'total_count')::bigint = 1,
  'private group owner still sees the provider-confirmed posting');
reset role;

select pg_temp.assert_true(
  (select count(*) from public.payments) = 2
  and (select count(*) from public.raw_payment_sms) = 3
  and (select count(*) from public.ledger_entries) = 2
  and (select status from public.payments
       where id = '99300000-0000-4000-8000-000000000221') = 'posted',
  'negative probes preserve the original financial state');
select 'FINANCIAL_ROLE_BOUNDARY_UAT_PASS: ' || count(*)
  || ' assertions; synthetic rollback only'
from pg_temp.test_results;
rollback;
