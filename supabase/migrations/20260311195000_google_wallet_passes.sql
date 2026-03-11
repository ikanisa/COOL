create table if not exists public.wallet_passes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  partner_id uuid references public.partners(id) on delete set null,
  provider text not null default 'google_wallet',
  pass_type text not null
    check (pass_type in ('event_ticket', 'generic_membership')),
  entity_type text not null
    check (entity_type in ('rs_ticket', 'rs_membership')),
  entity_id uuid not null,
  google_class_id text not null,
  google_object_id text not null,
  status text not null default 'ready'
    check (status in ('ready', 'failed', 'inactive')),
  state text not null default 'ACTIVE',
  save_url text,
  payload jsonb not null default '{}'::jsonb,
  last_error text,
  last_issued_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider, google_object_id),
  unique (pass_type, entity_type, entity_id)
);

create table if not exists public.wallet_pass_events (
  id uuid primary key default gen_random_uuid(),
  wallet_pass_id uuid not null references public.wallet_passes(id) on delete cascade,
  user_id uuid references public.users(id) on delete set null,
  event_type text not null,
  status text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_wallet_passes_user
  on public.wallet_passes (user_id, created_at desc);

create index if not exists idx_wallet_passes_partner
  on public.wallet_passes (partner_id, created_at desc);

create index if not exists idx_wallet_passes_entity
  on public.wallet_passes (entity_type, entity_id);

create index if not exists idx_wallet_pass_events_pass
  on public.wallet_pass_events (wallet_pass_id, created_at desc);

drop trigger if exists trg_wallet_passes_set_updated_at on public.wallet_passes;
create trigger trg_wallet_passes_set_updated_at
  before update on public.wallet_passes
  for each row
  execute function public.set_updated_at();

alter table public.wallet_passes enable row level security;
alter table public.wallet_pass_events enable row level security;

drop policy if exists "wallet_passes_select_own" on public.wallet_passes;
create policy "wallet_passes_select_own"
  on public.wallet_passes for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "wallet_pass_events_select_own" on public.wallet_pass_events;
create policy "wallet_pass_events_select_own"
  on public.wallet_pass_events for select
  to authenticated
  using (
    exists (
      select 1
      from public.wallet_passes wp
      where wp.id = wallet_pass_events.wallet_pass_id
        and wp.user_id = auth.uid()
    )
  );
