-- Cool App - canonical allowlist for approved M-Money SMS sender IDs

create table if not exists public.momo_sms_sender_allowlist (
  id uuid primary key default gen_random_uuid(),
  sender_display text not null,
  sender_token text not null,
  active boolean not null default true,
  market text not null default 'RW',
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint momo_sms_sender_allowlist_token_unique unique (sender_token)
);

create index if not exists idx_momo_sms_sender_allowlist_active_sort
  on public.momo_sms_sender_allowlist (active, sort_order, sender_display);

drop trigger if exists trg_momo_sms_sender_allowlist_set_updated_at
  on public.momo_sms_sender_allowlist;
create trigger trg_momo_sms_sender_allowlist_set_updated_at
  before update on public.momo_sms_sender_allowlist
  for each row
  execute function public.set_updated_at();

alter table public.momo_sms_sender_allowlist enable row level security;

drop policy if exists "momo_sms_sender_allowlist_select_authenticated"
  on public.momo_sms_sender_allowlist;
create policy "momo_sms_sender_allowlist_select_authenticated"
  on public.momo_sms_sender_allowlist for select
  using (auth.role() = 'authenticated');

insert into public.momo_sms_sender_allowlist (
  sender_display,
  sender_token,
  market,
  sort_order
)
values
  ('M-Money', 'mmoney', 'RW', 10),
  ('M-Money Alerts', 'mmoneyalerts', 'RW', 20),
  ('MobileMoney', 'mobilemoney', 'RW', 40),
  ('MoMo', 'momo', 'RW', 60),
  ('MoMo Alerts', 'momoalerts', 'RW', 70),
  ('MTN MoMo', 'mtnmomo', 'RW', 90),
  ('MTN MoMo Rwanda', 'mtnmomorwanda', 'RW', 110)
on conflict (sender_token) do update
set
  sender_display = excluded.sender_display,
  active = true,
  market = excluded.market,
  sort_order = excluded.sort_order;
