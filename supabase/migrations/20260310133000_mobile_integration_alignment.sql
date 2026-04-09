-- ==========================================================================
-- Cool App - Mobile integration alignment
-- ==========================================================================
-- Aligns the SQL schema with the Flutter repositories and edge functions.
-- Adds missing profile and payment fields.
-- ==========================================================================

-- -- Users -----------------------------------------------------------------

alter table public.users
  add column if not exists momo_provider text not null default '';
-- -- Groups ----------------------------------------------------------------

alter table public.groups
  add column if not exists type text not null default 'saving',
  add column if not exists amount int not null default 0,
  add column if not exists target_amount int not null default 0,
  add column if not exists monthly_contribution int,
  add column if not exists bank_partner text,
  add column if not exists momo_number text;
update public.groups
set
  amount = coalesce(amount, contribution_amount, 0),
  monthly_contribution = coalesce(monthly_contribution, contribution_amount)
where true;
-- -- Group contributions ---------------------------------------------------

alter table public.group_contributions
  add column if not exists momo_reference text;
create unique index if not exists idx_group_contributions_momo_reference
  on public.group_contributions (momo_reference)
  where momo_reference is not null;
-- -- Pending transactions --------------------------------------------------

create table if not exists public.pending_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete set null,
  group_id uuid references public.groups(id) on delete set null,
  group_contribution_id uuid references public.group_contributions(id) on delete set null,
  reference text not null unique,
  recipient_momo text not null,
  amount int not null default 0,
  provider text,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'failed')),
  raw_payload jsonb,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.pending_transactions
  add column if not exists group_id uuid references public.groups(id) on delete set null,
  add column if not exists group_contribution_id uuid references public.group_contributions(id) on delete set null;
create unique index if not exists idx_pending_transactions_reference
  on public.pending_transactions (reference);
create index if not exists idx_pending_transactions_user
  on public.pending_transactions (user_id);
create index if not exists idx_pending_transactions_group
  on public.pending_transactions (group_id);
create index if not exists idx_pending_transactions_status
  on public.pending_transactions (status);
-- -- Shared helpers --------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_users_set_updated_at on public.users;
create trigger trg_users_set_updated_at
  before update on public.users
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_groups_set_updated_at on public.groups;
create trigger trg_groups_set_updated_at
  before update on public.groups
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_pending_transactions_set_updated_at on public.pending_transactions;
create trigger trg_pending_transactions_set_updated_at
  before update on public.pending_transactions
  for each row
  execute function public.set_updated_at();
create or replace function public.sync_group_member_count()
returns trigger
language plpgsql
as $$
declare
  target_group_id uuid := coalesce(new.group_id, old.group_id);
begin
  if target_group_id is null then
    return coalesce(new, old);
  end if;

  update public.groups
  set
    member_count = (
      select count(*)
      from public.group_members gm
      where gm.group_id = target_group_id
    ),
    updated_at = now()
  where id = target_group_id;

  return coalesce(new, old);
end;
$$;
drop trigger if exists trg_sync_group_member_count on public.group_members;
create trigger trg_sync_group_member_count
  after insert or update or delete on public.group_members
  for each row
  execute function public.sync_group_member_count();
create or replace function public.sync_group_financials()
returns trigger
language plpgsql
as $$
declare
  target_group_id uuid := coalesce(new.group_id, old.group_id);
  target_user_id uuid := coalesce(new.user_id, old.user_id);
begin
  if target_group_id is null then
    return coalesce(new, old);
  end if;

  update public.groups
  set
    amount = coalesce((
      select sum(gc.amount)
      from public.group_contributions gc
      where gc.group_id = target_group_id
        and gc.status = 'confirmed'
    ), 0),
    updated_at = now()
  where id = target_group_id;

  update public.group_members gm
  set contribution_amount = coalesce((
    select sum(gc.amount)
    from public.group_contributions gc
    where gc.group_id = gm.group_id
      and gc.user_id = gm.user_id
      and gc.status = 'confirmed'
  ), 0)
  where gm.group_id = target_group_id
    and (target_user_id is null or gm.user_id = target_user_id);

  return coalesce(new, old);
end;
$$;
drop trigger if exists trg_sync_group_financials on public.group_contributions;
create trigger trg_sync_group_financials
  after insert or update or delete on public.group_contributions
  for each row
  execute function public.sync_group_financials();
-- -- RLS -------------------------------------------------------------------

alter table public.pending_transactions enable row level security;
drop policy if exists "pending_transactions_select_own" on public.pending_transactions;
create policy "pending_transactions_select_own"
  on public.pending_transactions for select
  using (auth.uid() = user_id);
drop policy if exists "pending_transactions_insert_authenticated" on public.pending_transactions;
create policy "pending_transactions_insert_authenticated"
  on public.pending_transactions for insert
  with check (auth.uid() is not null);
drop policy if exists "pending_transactions_update_own" on public.pending_transactions;
create policy "pending_transactions_update_own"
  on public.pending_transactions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
