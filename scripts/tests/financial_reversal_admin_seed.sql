\set ON_ERROR_STOP on
-- Establish a synthetic approved platform owner only in the dedicated
-- concurrency fixture so two authenticated admin sessions can race a reversal.
begin;
set local statement_timeout = '30s';

do $$ begin
  if current_database() <> 'postgres'
     or (select count(*) from supabase_migrations.schema_migrations) <>
       (case (select max(version) from supabase_migrations.schema_migrations)
         when '20260929130000' then 136
         when '20260929140000' then 137
         when '20260929150000' then 138
         else -1 end)
     or (select count(*) from public.payments
       where status = 'posted' and transaction_id = 'RACE2500') <> 1
     or (select count(*) from public.payment_provider_confirmations) <> 1
     or (select count(*) from collect_hybrid.momo_journal_entries
       where entry_type = 'receipt') <> 1
     or (select count(*) from collect_hybrid.momo_reversal_requests) <> 0
     or (select count(*) from public.admin_user_roles link
       join public.admin_roles role on role.id = link.role_id
       where link.user_id = '99100000-0000-4000-8000-000000000001'
         and role.name = 'platform_owner') <> 1
     or exists (select 1 from auth.sessions
       where id = '99600000-0000-4000-8000-000000000901') then
    raise exception 'Exact posted synthetic concurrency fixture required';
  end if;
end $$;

update public.profiles
set country_code = 'RW', currency_code = 'RWF',
    momo_provider = 'mtn_momo', momo_number = '0788991001',
    momo_number_hash = encode(extensions.digest('+250788991001', 'sha256'), 'hex'),
    is_platform_admin = true
where id = '99100000-0000-4000-8000-000000000001';
insert into auth.sessions(id, user_id, created_at, updated_at, not_after)
values (
  '99600000-0000-4000-8000-000000000901',
  '99100000-0000-4000-8000-000000000001',
  now() - interval '1 second', now(), now() + interval '1 hour'
);
insert into collect_admin_access.whatsapp_approvals(
  user_id, phone_e164, approved_at, approved_by, reason
) values (
  '99100000-0000-4000-8000-000000000001', '+250788991001',
  now() - interval '2 seconds',
  '99100000-0000-4000-8000-000000000001',
  'Synthetic concurrency reversal approval'
);

do $$ begin
  if not exists (select 1 from public.profiles
       where id = '99100000-0000-4000-8000-000000000001'
         and country_code = 'RW' and currency_code = 'RWF'
         and is_platform_admin)
     or not exists (select 1 from auth.sessions
       where id = '99600000-0000-4000-8000-000000000901'
         and user_id = '99100000-0000-4000-8000-000000000001')
     or not exists (select 1 from collect_admin_access.whatsapp_approvals
       where user_id = '99100000-0000-4000-8000-000000000001'
         and phone_e164 = '+250788991001') then
    raise exception 'Synthetic approved Admin setup incomplete';
  end if;
end $$;
commit;
select 'FINANCIAL_REVERSAL_ADMIN_SEED_PASS';
