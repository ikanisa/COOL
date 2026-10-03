-- Retire the production-capable developer data generator and remove only its
-- deterministic records. Real profiles, auth users, and non-seed groups are
-- intentionally preserved.

begin;

-- Ledger rows are immutable during normal application operation. This
-- migration removes only the deterministic seed collections, so suspend the
-- delete guard for the duration of this transaction and restore it before
-- commit.
alter table public.ledger_entries
  disable trigger ledger_entries_prevent_delete;

do $$
declare
  seed_collection_ids constant uuid[] := array[
    '8db1f114-4f2b-4a6a-aec9-a0e33a1f1001'::uuid,
    '8db1f114-4f2b-4a6a-aec9-a0e33a1f1002'::uuid
  ];
begin
  delete from public.admin_notes
  where entity_type = 'collection'
    and entity_id = any(seed_collection_ids);

  delete from public.moderation_flags
  where entity_type = 'collection'
    and entity_id = any(seed_collection_ids);

  delete from public.audit_logs
  where entity_type = 'collection'
    and entity_id = any(seed_collection_ids);

  delete from public.diaspora_contribution_intents
  where collection_id = any(seed_collection_ids);

  delete from public.ledger_entries
  where collection_id = any(seed_collection_ids)
     or payment_id in (
       select id from public.payments
       where collection_id = any(seed_collection_ids)
     );

  delete from public.payment_allocations
  where collection_id = any(seed_collection_ids)
     or payment_id in (
       select id from public.payments
       where collection_id = any(seed_collection_ids)
     );

  delete from public.payments
  where collection_id = any(seed_collection_ids);

  delete from public.collections
  where id = any(seed_collection_ids);
end;
$$;

alter table public.ledger_entries
  enable trigger ledger_entries_prevent_delete;

drop function if exists public.ensure_developer_account_data();

commit;
