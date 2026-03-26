-- ==========================================================================
-- Cool App - MoMo Evidence-to-Intent Foundation Schema
-- ==========================================================================

create table if not exists public.payment_receiver_accounts (
  id uuid primary key default gen_random_uuid(),
  payee_number_or_code text not null unique,
  purpose text not null,
  owner_user_id uuid references public.users(id) on delete set null,
  partner_id uuid references public.partners(id) on delete set null,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payment_receiver_accounts_purpose_check
    check (purpose in ('personal_wallet', 'bank_custody', 'rayon_shop', 'subscription', 'system_pool'))
);
create index if not exists idx_payment_receiver_accounts_owner on public.payment_receiver_accounts (owner_user_id);
create index if not exists idx_payment_receiver_accounts_partner on public.payment_receiver_accounts (partner_id);

drop trigger if exists trg_payment_receiver_accounts_set_updated_at on public.payment_receiver_accounts;
create trigger trg_payment_receiver_accounts_set_updated_at
  before update on public.payment_receiver_accounts
  for each row execute function public.set_updated_at();

alter table public.payment_receiver_accounts enable row level security;

drop policy if exists "payment_receiver_accounts_select_auth" on public.payment_receiver_accounts;
create policy "payment_receiver_accounts_select_auth"
  on public.payment_receiver_accounts for select
  using (
    is_active = true 
    or auth.uid() = owner_user_id 
    or public.is_admin()
  );

-- ==========================================================================

create table if not exists public.payment_identities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete set null,
  normalized_name text not null,
  number_last_3 text not null,
  number_full text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payment_identities_unique_identity
    unique nulls not distinct (user_id, normalized_name, number_last_3)
);
create index if not exists idx_payment_identities_user on public.payment_identities (user_id);
create index if not exists idx_payment_identities_search on public.payment_identities (normalized_name, number_last_3);

drop trigger if exists trg_payment_identities_set_updated_at on public.payment_identities;
create trigger trg_payment_identities_set_updated_at
  before update on public.payment_identities
  for each row execute function public.set_updated_at();

alter table public.payment_identities enable row level security;

drop policy if exists "payment_identities_select_own" on public.payment_identities;
create policy "payment_identities_select_own"
  on public.payment_identities for select
  using (auth.uid() = user_id or public.is_admin());

-- ==========================================================================

create table if not exists public.payment_intents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  receiving_account_id uuid not null references public.payment_receiver_accounts(id) on delete restrict,
  target_table text not null,
  target_record_id uuid not null,
  expected_amount integer not null,
  currency text not null default 'RWF',
  status text not null default 'pending',
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint payment_intents_status_check
    check (status in ('pending', 'fulfilled', 'expired', 'cancelled'))
);
create index if not exists idx_payment_intents_user on public.payment_intents (user_id);
create index if not exists idx_payment_intents_receiver on public.payment_intents (receiving_account_id, status);
create index if not exists idx_payment_intents_target on public.payment_intents (target_table, target_record_id);

drop trigger if exists trg_payment_intents_set_updated_at on public.payment_intents;
create trigger trg_payment_intents_set_updated_at
  before update on public.payment_intents
  for each row execute function public.set_updated_at();

alter table public.payment_intents enable row level security;

drop policy if exists "payment_intents_select_auth" on public.payment_intents;
create policy "payment_intents_select_auth"
  on public.payment_intents for select
  using (
    auth.uid() = user_id
    or public.is_admin()
  );

drop policy if exists "payment_intents_insert_auth" on public.payment_intents;
create policy "payment_intents_insert_auth"
  on public.payment_intents for insert
  with check (auth.uid() = user_id);

drop policy if exists "payment_intents_update_auth" on public.payment_intents;
create policy "payment_intents_update_auth"
  on public.payment_intents for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
