\set ON_ERROR_STOP on
-- Read-only fingerprint of the exact synthetic predecessor record. Compare
-- the output before and after the 126-to-current migration continuation.
begin read only;
set local statement_timeout = '30s';

do $$ begin
  if current_database() <> 'postgres'
     or (select count(*) from supabase_migrations.schema_migrations)
       not in (126, 134)
     or not (
       ((select count(*) from supabase_migrations.schema_migrations) = 126
         and (select max(version) from supabase_migrations.schema_migrations)
           = '20260914213600')
       or ((select count(*) from supabase_migrations.schema_migrations) = 134
         and (select max(version) from supabase_migrations.schema_migrations)
           = '20260929110000')
     )
     or (select count(*) from auth.users) <> 2
     or (select count(*) from public.bank_transfer_intents) <> 1
     or (select count(*) from public.bank_transactions) <> 1
     or (select count(*) from public.bank_transaction_allocations) <> 1
     or (select count(*) from public.bank_transfer_destinations) <> 1
     or not exists (select 1 from public.bank_transfer_intents
       where id = '99800000-0000-4000-8000-000000000101'
         and collection_id = '99800000-0000-4000-8000-000000000010'
         and contributor_user_id = '99800000-0000-4000-8000-000000000001'
         and amount_minor = 2100 and currency = 'EUR'
         and status = 'reconciled')
     or not exists (select 1 from public.bank_transaction_allocations
       where id = '99800000-0000-4000-8000-000000000103'
         and bank_transaction_id = '99800000-0000-4000-8000-000000000102'
         and bank_transfer_intent_id =
           '99800000-0000-4000-8000-000000000101') then
    raise exception 'Exact synthetic bank fixture required';
  end if;
end $$;

select jsonb_build_object(
  'bank_destination', (select md5(to_jsonb(destination)::text)
    from public.bank_transfer_destinations destination),
  'bank_intent', (select md5(to_jsonb(intent)::text)
    from public.bank_transfer_intents intent),
  'bank_transaction', (select md5(to_jsonb(txn)::text)
    from public.bank_transactions txn),
  'bank_allocation', (select md5(to_jsonb(allocation)::text)
    from public.bank_transaction_allocations allocation),
  'foreign_profile', (select md5(jsonb_build_object(
    'id', profile.id, 'country_code', profile.country_code,
    'currency_code', profile.currency_code)::text)
    from public.profiles profile
    where id = '99800000-0000-4000-8000-000000000001'),
  'diaspora_group', (select md5(jsonb_build_object(
    'id', collection.id, 'creator_user_id', collection.creator_user_id,
    'currency', collection.currency,
    'diaspora_enabled', collection.diaspora_enabled)::text)
    from public.collections collection
    where id = '99800000-0000-4000-8000-000000000010'),
  'owner_membership', (select md5(jsonb_build_object(
    'collection_id', member.collection_id, 'user_id', member.user_id,
    'role', member.role, 'status', member.status)::text)
    from public.collection_members member
    where collection_id = '99800000-0000-4000-8000-000000000010'
      and user_id = '99800000-0000-4000-8000-000000000001')
) as synthetic_fingerprints;
rollback;
