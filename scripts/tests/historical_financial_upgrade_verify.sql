\set ON_ERROR_STOP on
-- Rollback-only assertions against the task-owned upgraded historical fixture.
-- These prove local data preservation and containment, not provider authenticity.
begin;
set local statement_timeout = '30s';
do $$ begin
  if current_database() <> 'postgres'
     or (select count(*) from supabase_migrations.schema_migrations) <> 133
     or (select max(version) from supabase_migrations.schema_migrations) <> '20260928174000'
     or not exists(select 1 from auth.users
         where id = '99100000-0000-4000-8000-000000000001')
     or (select count(*) from public.raw_payment_sms) <> 3
     or (select count(*) from public.payments) <> 2 then
    raise exception 'Exact upgraded synthetic historical fixture required';
  end if;
end $$;
create temp table test_results(label text primary key);
grant all on pg_temp.test_results to service_role;
create function pg_temp.assert_true(ok boolean, label text) returns void
language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', label; end if;
  insert into pg_temp.test_results values(label);
end $$;

select pg_temp.assert_true(
  (select status = 'posted' and amount_rwf = 1500
   from public.payments where id = '99300000-0000-4000-8000-000000000221')
  and (select count(*) = 1 from public.payment_provider_confirmations
       where payment_id = '99300000-0000-4000-8000-000000000221'),
  'historical provider-confirmed payment remains posted once');
select pg_temp.assert_true(
  (select count(*) = 2 from public.ledger_entries
   where payment_id = '99300000-0000-4000-8000-000000000221')
  and (select count(*) = 1 from collect_hybrid.momo_journal_entries
       where payment_id = '99300000-0000-4000-8000-000000000221')
  and (select count(*) = 2
         and sum(line.amount_rwf) filter (where line.direction = 'debit') = 1500
         and sum(line.amount_rwf) filter (where line.direction = 'credit') = 1500
       from collect_hybrid.momo_journal_lines line
       join collect_hybrid.momo_journal_entries entry
         on entry.id = line.journal_entry_id
       where entry.payment_id = '99300000-0000-4000-8000-000000000221'),
  'historical legacy and canonical journals remain balanced');
select pg_temp.assert_true(
  (select confirmed_rwf = 1500 from collect_hybrid.collection_balances
   where collection_id = '99300000-0000-4000-8000-000000000010')
  and (select confirmed_rwf = 1500 from collect_hybrid.member_balances
   where collection_id = '99300000-0000-4000-8000-000000000010'
     and member_record_id = '99100000-0000-4000-8000-000000000001')
  and (select count(*) = 1 from collect_hybrid.momo_balance_snapshots
   where payment_id = '99300000-0000-4000-8000-000000000221'),
  'historical member and group balances remain unchanged');
select pg_temp.assert_true(
  (select status = 'cancelled' from public.payment_intents
   where id = '99300000-0000-4000-8000-000000000302')
  and (select status = 'review' from public.payments
   where id = '99300000-0000-4000-8000-000000000222')
  and not exists(select 1 from public.ledger_entries
   where payment_id = '99300000-0000-4000-8000-000000000222'),
  'unverified historical payer intent is cancelled without credit');
select pg_temp.assert_true(
  (select observed_payment_status = 'review'
      and reason = 'intent_identity_unverified'
      and review_status = 'open'
   from collect_hybrid.payer_identity_reconciliation
   where payment_id = '99300000-0000-4000-8000-000000000222'),
  'identity exception survives migration for operator review');
select pg_temp.assert_true(
  not has_function_privilege('authenticated',
      'public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)',
      'execute')
  and has_function_privilege('service_role',
      'public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text)',
      'execute')
  and not has_function_privilege('authenticated',
      'public.finalize_attested_payment_sms(uuid)', 'execute'),
  'new receipt and finality entrypoints remain service only');

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select public.attested_sms_contract_version() as contract_version \gset
select public.finalize_attested_payment_sms(
  '99300000-0000-4000-8000-000000000203') as finality \gset
reset role;
select pg_temp.assert_true(:'contract_version'::integer = 2,
  'upgraded server advertises exact receipt contract v2');
select pg_temp.assert_true(
  :'finality'::jsonb->>'status' = 'awaiting_reconciliation'
  and :'finality'::jsonb->>'evidence_level' = 'sms_observed'
  and :'finality'::jsonb->>'payment_id' is null
  and (select count(*) = 2 from public.payments)
  and (select count(*) = 2 from public.ledger_entries),
  'historical SMS-only finalizer cannot add payment or ledger credit');

insert into auth.users(id,aud,role,phone,phone_confirmed_at,
  raw_app_meta_data,raw_user_meta_data)
values ('99300000-0000-4000-8000-000000000401',
  'authenticated','authenticated','250788993401',now(),'{}','{}');
select pg_temp.assert_true(
  (select country_code is null and currency_code is null
   from public.profiles where id = '99300000-0000-4000-8000-000000000401'),
  'new Auth member can enter incomplete Rwanda onboarding after upgrade');
select 'HISTORICAL_FINANCIAL_UPGRADE_UAT_PASS: ' || count(*)
  || ' assertions; synthetic rollback only'
from pg_temp.test_results;
rollback;
