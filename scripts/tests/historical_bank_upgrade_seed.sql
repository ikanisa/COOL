\set ON_ERROR_STOP on
-- Commit synthetic predecessor rows only in the dedicated 126-migration
-- historical-bank fixture. No provider call or real financial evidence.
begin;
set local statement_timeout = '30s';

do $$ begin
  if current_database() <> 'postgres'
     or (select count(*) from supabase_migrations.schema_migrations) <> 126
     or (select max(version) from supabase_migrations.schema_migrations)
       <> '20260914213600'
     or (select count(*) from auth.users) <> 1
     or (select count(*) from public.bank_transfer_intents) <> 0
     or (select count(*) from public.bank_transactions) <> 0
     or (select count(*) from public.bank_transaction_allocations) <> 0
     or (select count(*) from public.bank_transfer_destinations) <> 1
     or to_regclass('public.bank_transfer_intents') is null
     or exists (select 1 from auth.users
       where id = '99800000-0000-4000-8000-000000000001') then
    raise exception 'Exact isolated bank predecessor required';
  end if;
end $$;

insert into auth.users (
  id, aud, role, phone, phone_confirmed_at,
  raw_app_meta_data, raw_user_meta_data
) values (
  '99800000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated', '447700900123', now(), '{}', '{}'
);
update public.profiles
set country_code = 'GB', currency_code = 'GBP'
where id = '99800000-0000-4000-8000-000000000001';

-- The predecessor schema stores the group ledger currency as RWF while the
-- diaspora bank intent and transaction carry their own EUR minor units.
insert into public.collections (
  id, slug, creator_user_id, title, category, currency,
  visibility, public_status, collection_type,
  contribution_visibility, allow_anonymous, diaspora_enabled
) values (
  '99800000-0000-4000-8000-000000000010',
  'synthetic-historical-diaspora',
  '99800000-0000-4000-8000-000000000001',
  'Synthetic historical diaspora group', 'Family / friends', 'RWF',
  'private', 'private', 'ikimina', 'members', false, true
);
insert into public.collection_members (collection_id, user_id, role, status)
values (
  '99800000-0000-4000-8000-000000000010',
  '99800000-0000-4000-8000-000000000001', 'owner', 'active'
);

insert into public.bank_transfer_intents (
  id, collection_id, contributor_user_id, destination_id,
  destination_snapshot, transfer_reference, amount_minor, currency, status
)
select '99800000-0000-4000-8000-000000000101',
  '99800000-0000-4000-8000-000000000010',
  '99800000-0000-4000-8000-000000000001', destination.id,
  jsonb_build_object('id', destination.id, 'currency', 'EUR'),
  'COL-HISTB00002', 2100, 'EUR', 'reconciled'
from public.bank_transfer_destinations destination;
insert into public.bank_transactions (
  id, transaction_key, transfer_reference, amount_minor, currency,
  occurred_at, status
) values (
  '99800000-0000-4000-8000-000000000102', repeat('b', 64),
  'COL-HISTB00002', 2100, 'EUR', now() - interval '1 day', 'reconciled'
);
insert into public.bank_transaction_allocations (
  id, bank_transaction_id, bank_transfer_intent_id, collection_id,
  contributor_user_id, allocation_method, confidence, reason
) values (
  '99800000-0000-4000-8000-000000000103',
  '99800000-0000-4000-8000-000000000102',
  '99800000-0000-4000-8000-000000000101',
  '99800000-0000-4000-8000-000000000010',
  '99800000-0000-4000-8000-000000000001',
  'manual_maker_checker', 1, 'Synthetic predecessor relation'
);

do $$ begin
  if (select country_code from public.profiles
      where id = '99800000-0000-4000-8000-000000000001') <> 'GB'
     or not exists (select 1 from public.collections
       where id = '99800000-0000-4000-8000-000000000010'
         and diaspora_enabled and currency = 'RWF')
     or (select count(*) from public.bank_transfer_intents
       where id = '99800000-0000-4000-8000-000000000101'
         and currency = 'EUR' and status = 'reconciled') <> 1
     or (select count(*) from public.bank_transactions
       where id = '99800000-0000-4000-8000-000000000102'
         and currency = 'EUR') <> 1
     or (select count(*) from public.bank_transaction_allocations
       where bank_transfer_intent_id =
         '99800000-0000-4000-8000-000000000101') <> 1 then
    raise exception 'Synthetic bank predecessor seed incomplete';
  end if;
end $$;
commit;
select 'HISTORICAL_BANK_UPGRADE_SEED_PASS';
