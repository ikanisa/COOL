\set ON_ERROR_STOP on
-- Rollback-only synthetic bank retention and current MoMo read-boundary check.
-- Use only the task-owned 133-migration financial fixture. No bank details,
-- raw SMS body, provider data, or customer records are printed.
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
     or (select count(*) from public.bank_transfer_intents) <> 0
     or (select count(*) from public.bank_transactions) <> 0
     or (select count(*) from public.bank_transaction_allocations) <> 0
     or (select count(*) from public.bank_transfer_destinations) <> 1
     or not exists (
       select 1 from public.collections
       where id = '99300000-0000-4000-8000-000000000010'
     ) then
    raise exception 'Exact isolated historical financial fixture required';
  end if;
end $$;

create temp table test_results(label text primary key);
grant all on pg_temp.test_results to authenticated, service_role;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values(label);
end $$;
create function pg_temp.expect_denied(command text, label text) returns void
language plpgsql as $$
declare code text;
begin
  begin
    execute command;
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
  end;
  perform pg_temp.assert_true(code = '42501', label);
end $$;

-- This is a synthetic stored historical record, inserted as the task-owned
-- fixture superuser. It is not a payment instruction or provider confirmation.
insert into public.bank_transfer_intents (
  id, collection_id, contributor_user_id, destination_id,
  destination_snapshot, transfer_reference, amount_minor, currency, status
)
select '99700000-0000-4000-8000-000000000101',
  '99300000-0000-4000-8000-000000000010',
  '99100000-0000-4000-8000-000000000001', destination.id,
  jsonb_build_object('id', destination.id, 'currency', 'EUR'),
  'COL-HISTB00001', 2100, 'EUR', 'reconciled'
from public.bank_transfer_destinations destination;
insert into public.bank_transactions (
  id, transaction_key, transfer_reference, amount_minor, currency,
  occurred_at, status
) values (
  '99700000-0000-4000-8000-000000000102', repeat('a', 64),
  'COL-HISTB00001', 2100, 'EUR', now() - interval '1 day', 'reconciled'
);
insert into public.bank_transaction_allocations (
  id, bank_transaction_id, bank_transfer_intent_id, collection_id,
  contributor_user_id, allocation_method, confidence, reason
) values (
  '99700000-0000-4000-8000-000000000103',
  '99700000-0000-4000-8000-000000000102',
  '99700000-0000-4000-8000-000000000101',
  '99300000-0000-4000-8000-000000000010',
  '99100000-0000-4000-8000-000000000001',
  'manual_maker_checker', 1, 'Synthetic retained historical relation'
);

select pg_temp.assert_true(
  (select count(*) from public.bank_transfer_intents
    where id = '99700000-0000-4000-8000-000000000101'
      and currency = 'EUR' and status = 'reconciled') = 1
  and (select count(*) from public.bank_transactions
    where id = '99700000-0000-4000-8000-000000000102'
      and currency = 'EUR') = 1
  and (select count(*) from public.bank_transaction_allocations
    where bank_transfer_intent_id =
      '99700000-0000-4000-8000-000000000101') = 1,
  'historical bank intent transaction and allocation remain relational'
);
select pg_temp.assert_true(
  not has_table_privilege('anon', 'public.bank_transfer_intents', 'select')
  and not has_table_privilege('authenticated',
    'public.bank_transfer_intents', 'select')
  and not has_table_privilege('service_role',
    'public.bank_transfer_intents', 'select')
  and not has_table_privilege('authenticated',
    'public.bank_transactions', 'select')
  and not has_table_privilege('service_role',
    'public.bank_transactions', 'select'),
  'retired bank storage is inaccessible to API roles'
);
select pg_temp.assert_true(
  not has_function_privilege('authenticated',
    'public.create_bank_transfer_intent(uuid,bigint)', 'execute')
  and not has_function_privilege('service_role',
    'public.create_bank_transfer_intent(uuid,bigint)', 'execute')
  and not has_function_privilege('authenticated',
    'public.list_current_user_bank_transfer_intents()', 'execute')
  and not has_function_privilege('service_role',
    'public.list_current_user_bank_transfer_intents()', 'execute'),
  'retired bank operations are inaccessible to member and service roles'
);
select pg_temp.assert_true(
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname ~ '(bank|diaspora|stripe|sepa)') > 0
  and not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname ~ '(bank|diaspora|stripe|sepa)'
      and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute')
        or has_function_privilege('service_role', p.oid, 'execute'))
  ),
  'every retired bank or diaspora function denies API-role execution'
);
select pg_temp.assert_true(
  (select count(*) from pg_tables
   where schemaname = 'public'
     and tablename ~ '^(bank_|daily_bank_)') > 0
  and not exists (
    select 1 from pg_tables
    where schemaname = 'public'
      and tablename ~ '^(bank_|daily_bank_)'
      and (has_table_privilege('anon',
          format('%I.%I', schemaname, tablename), 'select')
        or has_table_privilege('authenticated',
          format('%I.%I', schemaname, tablename), 'select')
        or has_table_privilege('service_role',
          format('%I.%I', schemaname, tablename), 'select'))
  ),
  'every retired bank table denies API-role reads'
);

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99100000-0000-4000-8000-000000000001","role":"authenticated"}',
  true);
select pg_temp.assert_true(
  (public.list_current_member_history_page(
    '99300000-0000-4000-8000-000000000010',
    '', 'newest', null, 50)->>'total_count')::bigint = 1,
  'current member history retains only the confirmed RWF posting'
);
select pg_temp.assert_true(
  public.list_current_member_history_page(
    '99300000-0000-4000-8000-000000000010',
    '', 'newest', null, 50)->'totals' = '{"RWF":1500}'::jsonb,
  'historical EUR bank amount cannot inflate current RWF totals'
);
select pg_temp.assert_true(
  not (public.list_current_member_recent_intents(null)::text
    like '%99700000-0000-4000-8000-000000000101%'),
  'historical bank intent is absent from active MoMo intent response'
);
select pg_temp.expect_denied(
  'select count(*) from public.bank_transfer_intents',
  'member direct bank-history table read is denied'
);
select pg_temp.expect_denied(
  'select public.list_current_user_bank_transfer_intents()',
  'member bank-intent RPC is denied'
);
reset role;

set local role service_role;
select pg_temp.expect_denied(
  'select count(*) from public.bank_transactions',
  'service-role direct retired bank transaction read is denied'
);
reset role;

select 'HISTORICAL_BANK_SCOPE_BOUNDARY_UAT_PASS: ' || count(*)
  || ' assertions; synthetic rollback only'
from pg_temp.test_results;
rollback;
