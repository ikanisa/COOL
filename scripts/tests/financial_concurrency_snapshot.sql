\set ON_ERROR_STOP on
-- Read-only digest of every synthetic RACE2500 financial/evidence row. The
-- digest excludes the migration registry, so it must match before and after
-- a function-only upgrade.
with target as (
  select id, collection_id, payment_intent_id
  from public.payments where transaction_id = 'RACE2500'
), evidence(family, row_id, body) as (
  select 'payment', payment.id::text, to_jsonb(payment)
  from public.payments payment join target on target.id = payment.id
  union all
  select 'intent', intent.id::text, to_jsonb(intent)
  from public.payment_intents intent
  where intent.id = '99600000-0000-4000-8000-000000000301'
  union all
  select 'parsed_event', event.id::text, to_jsonb(event)
  from public.parsed_payment_events event
  where event.transaction_id = 'RACE2500'
  union all
  select 'provider_request', request.request_id::text, to_jsonb(request)
  from public.provider_finality_requests request
  join target on target.id = request.payment_id
  union all
  select 'provider_confirmation', confirmation.id::text, to_jsonb(confirmation)
  from public.payment_provider_confirmations confirmation
  join target on target.id = confirmation.payment_id
  union all
  select 'ledger', ledger.id::text, to_jsonb(ledger)
  from public.ledger_entries ledger join target on target.id = ledger.payment_id
  union all
  select 'journal', journal.id::text, to_jsonb(journal)
  from collect_hybrid.momo_journal_entries journal
  join target on target.id = journal.payment_id
  union all
  select 'journal_line', line.id::text, to_jsonb(line)
  from collect_hybrid.momo_journal_lines line
  join collect_hybrid.momo_journal_entries journal
    on journal.id = line.journal_entry_id
  join target on target.id = journal.payment_id
  union all
  select 'balance_snapshot', snapshot.id::text, to_jsonb(snapshot)
  from collect_hybrid.momo_balance_snapshots snapshot
  join target on target.id = snapshot.payment_id
  union all
  select 'collection_balance', balance.collection_id::text, to_jsonb(balance)
  from collect_hybrid.collection_balances balance
  join target on target.collection_id = balance.collection_id
  union all
  select 'member_balance', balance.collection_id::text || ':' ||
    balance.member_record_id::text, to_jsonb(balance)
  from collect_hybrid.member_balances balance
  join target on target.collection_id = balance.collection_id
)
select jsonb_build_object(
  'migration_count', (select count(*) from supabase_migrations.schema_migrations),
  'last_migration', (select max(version) from supabase_migrations.schema_migrations),
  'evidence_rows', (select count(*) from evidence),
  'financial_sha256', encode(extensions.digest(coalesce((
    select string_agg(family || ':' || row_id || ':' || body::text, E'\n'
      order by family, row_id) from evidence), ''), 'sha256'), 'hex'),
  'payment_status', (select status from public.payments where transaction_id = 'RACE2500'),
  'provider_requests', (select count(*) from public.provider_finality_requests
    where payment_id in (select id from target)),
  'provider_confirmations', (select count(*) from public.payment_provider_confirmations
    where payment_id in (select id from target)),
  'receipt_journals', (select count(*) from collect_hybrid.momo_journal_entries
    where payment_id in (select id from target) and entry_type = 'receipt'),
  'reversal_journals', (select count(*) from collect_hybrid.momo_journal_entries
    where payment_id in (select id from target) and entry_type = 'reversal'),
  'confirmed_balance_rwf', (select confirmed_rwf
    from collect_hybrid.collection_balances balance
    join target on target.collection_id = balance.collection_id limit 1)
);
