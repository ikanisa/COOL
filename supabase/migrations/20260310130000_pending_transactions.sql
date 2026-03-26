-- ==========================================================================
-- Cool App — Add pending_transactions table and momo_reference columns
-- ==========================================================================

-- ── Pending transactions (MoMo payment reconciliation) ───────────────────

create table if not exists public.pending_transactions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.users(id) on delete cascade,
  reference       text not null,
  provider        text not null,
  amount          int not null default 0,
  recipient_momo  text,
  status          text not null default 'pending'
    check (status in ('pending', 'confirmed', 'failed')),
  confirmed_at    timestamptz,
  raw_payload     jsonb,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);
create index if not exists idx_pending_tx_user
  on public.pending_transactions (user_id);
create index if not exists idx_pending_tx_status
  on public.pending_transactions (status);
alter table public.pending_transactions enable row level security;
create policy "pending_tx_select_own"
  on public.pending_transactions for select
  using (auth.uid() = user_id);
create policy "pending_tx_insert_own"
  on public.pending_transactions for insert
  with check (auth.uid() = user_id);
create policy "pending_tx_update_own"
  on public.pending_transactions for update
  using (auth.uid() = user_id);
-- ── Add momo_reference to payment-linked tables ──────────────────────────

alter table public.group_contributions
  add column if not exists momo_reference text;
-- ── Add momo_provider to users table ─────────────────────────────────────

alter table public.users
  add column if not exists momo_provider text;
