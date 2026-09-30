\set ON_ERROR_STOP on
-- Rollback-only member/API checks after the exact predecessor bank rows have
-- survived migrations 127-134 in the dedicated local fixture.
begin;
set local statement_timeout = '30s';

do $$ begin
  if current_database() <> 'postgres'
     or (select count(*) from supabase_migrations.schema_migrations) <> 134
     or (select max(version) from supabase_migrations.schema_migrations)
       <> '20260929110000'
     or (select count(*) from auth.users) <> 2
     or (select count(*) from public.bank_transfer_intents) <> 1
     or (select count(*) from public.bank_transactions) <> 1
     or (select count(*) from public.bank_transaction_allocations) <> 1
     or not exists (select 1 from public.collections
       where id = '99800000-0000-4000-8000-000000000010'
         and diaspora_enabled and currency = 'RWF') then
    raise exception 'Exact upgraded historical bank fixture required';
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
create function pg_temp.expect_country_rejected(command text, label text)
returns void language plpgsql as $$
declare code text; detail text;
begin
  begin
    execute command;
  exception when others then
    get stacked diagnostics code = returned_sqlstate,
      detail = message_text;
  end;
  perform pg_temp.assert_true(code = 'P0001'
    and detail = 'Collect supports Rwanda profiles only', label);
end $$;

select pg_temp.assert_true(
  exists (select 1 from public.profiles
    where id = '99800000-0000-4000-8000-000000000001'
      and country_code = 'GB' and currency_code = 'GBP')
  and exists (select 1 from public.collections
    where id = '99800000-0000-4000-8000-000000000010'
      and diaspora_enabled and currency = 'RWF')
  and exists (select 1 from public.collection_members
    where collection_id = '99800000-0000-4000-8000-000000000010'
      and user_id = '99800000-0000-4000-8000-000000000001'
      and role = 'owner' and status = 'active'),
  'pre-cutover foreign profile diaspora group and membership retained'
);
select pg_temp.assert_true(
  exists (select 1 from public.bank_transfer_intents intent
    join public.bank_transaction_allocations allocation
      on allocation.bank_transfer_intent_id = intent.id
    join public.bank_transactions txn
      on txn.id = allocation.bank_transaction_id
    where intent.id = '99800000-0000-4000-8000-000000000101'
      and intent.currency = 'EUR' and intent.amount_minor = 2100
      and intent.status = 'reconciled' and txn.currency = 'EUR'
      and txn.amount_minor = 2100 and txn.status = 'reconciled'),
  'pre-cutover EUR bank relation and money values retained'
);
select pg_temp.assert_true(
  not has_table_privilege('anon',
    'public.bank_transfer_intents', 'select')
  and not has_table_privilege('authenticated',
    'public.bank_transfer_intents', 'select')
  and not has_table_privilege('service_role',
    'public.bank_transfer_intents', 'select')
  and not has_table_privilege('authenticated',
    'public.bank_transactions', 'select')
  and not has_table_privilege('service_role',
    'public.bank_transactions', 'select'),
  'retired bank storage denies API roles'
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
  'retired bank RPCs deny member and service roles'
);

-- NOT VALID accepts historical rows, but rejects attempts to create or
-- modify them into a new foreign/diaspora row after cutover.
do $$
declare seen_constraint text;
begin
  begin
    update public.profiles set currency_code = 'EUR'
    where id = '99800000-0000-4000-8000-000000000001';
  exception when check_violation then
    get stacked diagnostics seen_constraint = constraint_name;
  end;
  perform pg_temp.assert_true(seen_constraint = 'profiles_rwanda_momo_only',
    'foreign profile writes reject under Rwanda-only constraint');
end $$;
do $$
declare seen_constraint text;
begin
  begin
    update public.collections set title = 'Changed synthetic diaspora title'
    where id = '99800000-0000-4000-8000-000000000010';
  exception when check_violation then
    get stacked diagnostics seen_constraint = constraint_name;
  end;
  perform pg_temp.assert_true(seen_constraint = 'collections_rwanda_momo_only',
    'diaspora group writes reject under Rwanda-only constraint');
end $$;

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"99800000-0000-4000-8000-000000000001","role":"authenticated"}',
  true);
select pg_temp.assert_true(
  to_regprocedure('public.update_current_member_profile(text,text,text,text,text,text)')
    is null
  and to_regprocedure('public.update_current_member_profile(text,text,text,text,text)')
    is null,
  'retired profile RPC overloads are absent for older clients'
);
select pg_temp.expect_country_rejected(
  $$select public.ensure_current_member_profile('447700900123', 'GB')$$,
  'older foreign-country profile request fails before a write'
);
select pg_temp.assert_true(
  not exists (select 1
    from jsonb_array_elements(public.list_current_user_collections(null)) item
    where item->>'id' = '99800000-0000-4000-8000-000000000010'),
  'historical diaspora owner cannot list retired collection'
);
select pg_temp.assert_true(
  not exists (select 1
    from jsonb_array_elements(public.list_current_member_collection_balances()) item
    where item->>'collection_id' =
      '99800000-0000-4000-8000-000000000010'),
  'historical diaspora group has no active MoMo balance'
);
select pg_temp.assert_true(
  public.list_current_member_recent_intents(null)::text
    not like '%99800000-0000-4000-8000-000000000101%',
  'historical bank intent does not enter active MoMo intent response'
);
select pg_temp.expect_denied(
  'select count(*) from public.bank_transfer_intents',
  'member direct bank table read is denied'
);
select pg_temp.expect_denied(
  'select public.list_current_user_bank_transfer_intents()',
  'member retired bank RPC is denied'
);
reset role;

set local role service_role;
select pg_temp.expect_denied(
  'select count(*) from public.bank_transactions',
  'service role direct bank transaction read is denied'
);
reset role;

select 'HISTORICAL_BANK_UPGRADE_UAT_PASS: ' || count(*)
  || ' assertions; synthetic rollback only'
from pg_temp.test_results;
rollback;
