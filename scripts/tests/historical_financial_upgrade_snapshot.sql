\set ON_ERROR_STOP on
-- Read-only comparison of the exact synthetic historical rows. The SHA-256
-- covers complete financial/evidence rows, including their timestamps and IDs.
with evidence(family, row_id, row_body) as (
  select 'raw_payment_sms', raw.id::text, to_jsonb(raw)
  from public.raw_payment_sms raw
  where raw.id in (
    '99300000-0000-4000-8000-000000000201',
    '99300000-0000-4000-8000-000000000202',
    '99300000-0000-4000-8000-000000000203')
  union all
  select 'parsed_payment_events', event.id::text, to_jsonb(event)
  from public.parsed_payment_events event
  where event.id in (
    '99300000-0000-4000-8000-000000000211',
    '99300000-0000-4000-8000-000000000212')
  union all
  select 'payments', payment.id::text, to_jsonb(payment)
  from public.payments payment
  where payment.id in (
    '99300000-0000-4000-8000-000000000221',
    '99300000-0000-4000-8000-000000000222')
  union all
  select 'provider_confirmations', confirmation.id::text, to_jsonb(confirmation)
  from public.payment_provider_confirmations confirmation
  where confirmation.payment_id = '99300000-0000-4000-8000-000000000221'
  union all
  select 'ledger_entries', ledger.id::text, to_jsonb(ledger)
  from public.ledger_entries ledger
  where ledger.payment_id = '99300000-0000-4000-8000-000000000221'
  union all
  select 'momo_journal_entries', entry.id::text, to_jsonb(entry)
  from collect_hybrid.momo_journal_entries entry
  where entry.payment_id = '99300000-0000-4000-8000-000000000221'
  union all
  select 'momo_journal_lines', line.id::text, to_jsonb(line)
  from collect_hybrid.momo_journal_lines line
  join collect_hybrid.momo_journal_entries entry on entry.id = line.journal_entry_id
  where entry.payment_id = '99300000-0000-4000-8000-000000000221'
  union all
  select 'momo_balance_snapshots', snapshot.id::text, to_jsonb(snapshot)
  from collect_hybrid.momo_balance_snapshots snapshot
  where snapshot.payment_id = '99300000-0000-4000-8000-000000000221'
  union all
  select 'collection_balances', balance.collection_id::text, to_jsonb(balance)
  from collect_hybrid.collection_balances balance
  where balance.collection_id = '99300000-0000-4000-8000-000000000010'
  union all
  select 'member_balances', balance.collection_id::text || ':' || balance.member_record_id::text,
    to_jsonb(balance)
  from collect_hybrid.member_balances balance
  where balance.collection_id = '99300000-0000-4000-8000-000000000010'
), digest as (
  select count(*) as row_count,
    encode(extensions.digest(coalesce(string_agg(
      family || ':' || row_id || ':' || row_body::text, E'\n'
      order by family, row_id), ''), 'sha256'), 'hex') as sha256
  from evidence
)
select jsonb_build_object(
  'migration_count', (select count(*) from supabase_migrations.schema_migrations),
  'last_migration', (select max(version) from supabase_migrations.schema_migrations),
  'evidence_rows', digest.row_count,
  'evidence_sha256', digest.sha256,
  'posted_status', (select status from public.payments
    where id = '99300000-0000-4000-8000-000000000221'),
  'review_status', (select status from public.payments
    where id = '99300000-0000-4000-8000-000000000222'),
  'intent_status', (select status from public.payment_intents
    where id = '99300000-0000-4000-8000-000000000302'),
  'group_balance_rwf', (select confirmed_rwf from collect_hybrid.collection_balances
    where collection_id = '99300000-0000-4000-8000-000000000010'),
  'receipt_contract_version', public.attested_sms_contract_version()
) from digest;
