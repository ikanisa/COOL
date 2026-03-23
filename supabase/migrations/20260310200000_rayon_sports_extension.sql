-- ============================================================================
-- Cool App — Rayon Sports FC Extension
-- ============================================================================

insert into public.partners (
  name,
  category,
  country,
  description,
  fan_count,
  club_count,
  game_count
)
select
  'Rayon Sports FC',
  'football',
  'RW',
  'Gikundiro supporter services: registry, clubs, initiatives, tickets, and shop.',
  0,
  0,
  0
where not exists (
  select 1
  from public.partners
  where lower(name) = 'rayon sports fc'
);
create table if not exists public.rs_fan_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  tier text not null default 'blue'
    check (tier in ('blue', 'silver', 'gold', 'platinum')),
  points int not null default 0,
  joined_at timestamptz not null default now(),
  chapter text,
  membership_number text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, partner_id)
);
create table if not exists public.rs_fan_clubs (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  name text not null,
  region text not null,
  description text,
  member_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.rs_fan_club_members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.rs_fan_clubs(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (club_id, user_id)
);
create table if not exists public.rs_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  badge_type text not null,
  earned_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create table if not exists public.rs_shop_products (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  name text not null,
  category text not null,
  price int not null check (price >= 0),
  image_emoji text not null default '🛍️',
  stock int not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.rs_shop_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  items jsonb not null default '[]'::jsonb,
  subtotal int not null default 0,
  discount int not null default 0,
  total int not null default 0,
  delivery_address text,
  momo_reference text,
  status text not null default 'pending'
    check (status in ('pending', 'paid', 'fulfilled', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.rs_initiatives (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  title text not null,
  description text,
  category text not null,
  target_amount int not null default 0,
  raised_amount int not null default 0,
  supporter_count int not null default 0,
  is_active boolean not null default true,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.rs_initiative_contributions (
  id uuid primary key default gen_random_uuid(),
  initiative_id uuid not null references public.rs_initiatives(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  amount int not null default 0,
  momo_reference text,
  status text not null default 'pending'
    check (status in ('pending', 'confirmed', 'failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.rs_matches (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  home_team text not null,
  away_team text not null,
  competition text not null,
  venue text not null,
  match_date date not null,
  kickoff_time time not null,
  is_on_sale boolean not null default true,
  ticket_general_price int not null default 0,
  ticket_vip_price int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.rs_tickets (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.rs_matches(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  seat_type text not null,
  amount_paid int not null default 0,
  qr_code text,
  momo_reference text,
  status text not null default 'pending'
    check (status in ('pending', 'valid', 'used', 'cancelled')),
  purchased_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_rs_fan_memberships_partner
  on public.rs_fan_memberships (partner_id, tier, points desc);
create index if not exists idx_rs_fan_memberships_user
  on public.rs_fan_memberships (user_id);
create index if not exists idx_rs_fan_clubs_partner
  on public.rs_fan_clubs (partner_id, region);
create index if not exists idx_rs_fan_club_members_club
  on public.rs_fan_club_members (club_id);
create index if not exists idx_rs_fan_club_members_user
  on public.rs_fan_club_members (user_id);
create index if not exists idx_rs_achievements_user_partner
  on public.rs_achievements (user_id, partner_id, earned_at desc);
create index if not exists idx_rs_shop_products_partner
  on public.rs_shop_products (partner_id, is_active, category);
create index if not exists idx_rs_shop_orders_user
  on public.rs_shop_orders (user_id, created_at desc);
create index if not exists idx_rs_initiatives_partner
  on public.rs_initiatives (partner_id, is_active, ends_at);
create index if not exists idx_rs_initiative_contributions_initiative
  on public.rs_initiative_contributions (initiative_id, status);
create index if not exists idx_rs_matches_partner
  on public.rs_matches (partner_id, match_date);
create index if not exists idx_rs_tickets_user
  on public.rs_tickets (user_id, purchased_at desc);
drop trigger if exists trg_rs_fan_memberships_set_updated_at on public.rs_fan_memberships;
create trigger trg_rs_fan_memberships_set_updated_at
  before update on public.rs_fan_memberships
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_rs_fan_clubs_set_updated_at on public.rs_fan_clubs;
create trigger trg_rs_fan_clubs_set_updated_at
  before update on public.rs_fan_clubs
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_rs_shop_products_set_updated_at on public.rs_shop_products;
create trigger trg_rs_shop_products_set_updated_at
  before update on public.rs_shop_products
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_rs_shop_orders_set_updated_at on public.rs_shop_orders;
create trigger trg_rs_shop_orders_set_updated_at
  before update on public.rs_shop_orders
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_rs_initiatives_set_updated_at on public.rs_initiatives;
create trigger trg_rs_initiatives_set_updated_at
  before update on public.rs_initiatives
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_rs_initiative_contributions_set_updated_at on public.rs_initiative_contributions;
create trigger trg_rs_initiative_contributions_set_updated_at
  before update on public.rs_initiative_contributions
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_rs_matches_set_updated_at on public.rs_matches;
create trigger trg_rs_matches_set_updated_at
  before update on public.rs_matches
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_rs_tickets_set_updated_at on public.rs_tickets;
create trigger trg_rs_tickets_set_updated_at
  before update on public.rs_tickets
  for each row
  execute function public.set_updated_at();
alter table public.rs_fan_memberships enable row level security;
alter table public.rs_fan_clubs enable row level security;
alter table public.rs_fan_club_members enable row level security;
alter table public.rs_achievements enable row level security;
alter table public.rs_shop_products enable row level security;
alter table public.rs_shop_orders enable row level security;
alter table public.rs_initiatives enable row level security;
alter table public.rs_initiative_contributions enable row level security;
alter table public.rs_matches enable row level security;
alter table public.rs_tickets enable row level security;
drop policy if exists "rs_fan_memberships_select_authenticated" on public.rs_fan_memberships;
create policy "rs_fan_memberships_select_authenticated"
  on public.rs_fan_memberships for select
  using (auth.role() = 'authenticated');
drop policy if exists "rs_fan_memberships_insert_own" on public.rs_fan_memberships;
create policy "rs_fan_memberships_insert_own"
  on public.rs_fan_memberships for insert
  with check (auth.uid() = user_id);
drop policy if exists "rs_fan_memberships_update_own" on public.rs_fan_memberships;
create policy "rs_fan_memberships_update_own"
  on public.rs_fan_memberships for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop policy if exists "rs_fan_clubs_select_authenticated" on public.rs_fan_clubs;
create policy "rs_fan_clubs_select_authenticated"
  on public.rs_fan_clubs for select
  using (auth.role() = 'authenticated');
drop policy if exists "rs_fan_club_members_select_authenticated" on public.rs_fan_club_members;
create policy "rs_fan_club_members_select_authenticated"
  on public.rs_fan_club_members for select
  using (auth.role() = 'authenticated');
drop policy if exists "rs_fan_club_members_insert_own" on public.rs_fan_club_members;
create policy "rs_fan_club_members_insert_own"
  on public.rs_fan_club_members for insert
  with check (auth.uid() = user_id);
drop policy if exists "rs_achievements_select_own" on public.rs_achievements;
create policy "rs_achievements_select_own"
  on public.rs_achievements for select
  using (auth.uid() = user_id);
drop policy if exists "rs_shop_products_select_authenticated" on public.rs_shop_products;
create policy "rs_shop_products_select_authenticated"
  on public.rs_shop_products for select
  using (auth.role() = 'authenticated');
drop policy if exists "rs_shop_orders_select_own" on public.rs_shop_orders;
create policy "rs_shop_orders_select_own"
  on public.rs_shop_orders for select
  using (auth.uid() = user_id);
drop policy if exists "rs_shop_orders_insert_own" on public.rs_shop_orders;
create policy "rs_shop_orders_insert_own"
  on public.rs_shop_orders for insert
  with check (auth.uid() = user_id);
drop policy if exists "rs_shop_orders_update_own" on public.rs_shop_orders;
create policy "rs_shop_orders_update_own"
  on public.rs_shop_orders for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop policy if exists "rs_initiatives_select_authenticated" on public.rs_initiatives;
create policy "rs_initiatives_select_authenticated"
  on public.rs_initiatives for select
  using (auth.role() = 'authenticated');
drop policy if exists "rs_initiative_contributions_select_own" on public.rs_initiative_contributions;
create policy "rs_initiative_contributions_select_own"
  on public.rs_initiative_contributions for select
  using (auth.uid() = user_id);
drop policy if exists "rs_initiative_contributions_insert_own" on public.rs_initiative_contributions;
create policy "rs_initiative_contributions_insert_own"
  on public.rs_initiative_contributions for insert
  with check (auth.uid() = user_id);
drop policy if exists "rs_initiative_contributions_update_own" on public.rs_initiative_contributions;
create policy "rs_initiative_contributions_update_own"
  on public.rs_initiative_contributions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop policy if exists "rs_matches_select_authenticated" on public.rs_matches;
create policy "rs_matches_select_authenticated"
  on public.rs_matches for select
  using (auth.role() = 'authenticated');
drop policy if exists "rs_tickets_select_own" on public.rs_tickets;
create policy "rs_tickets_select_own"
  on public.rs_tickets for select
  using (auth.uid() = user_id);
drop policy if exists "rs_tickets_insert_own" on public.rs_tickets;
create policy "rs_tickets_insert_own"
  on public.rs_tickets for insert
  with check (auth.uid() = user_id);
drop policy if exists "rs_tickets_update_own" on public.rs_tickets;
create policy "rs_tickets_update_own"
  on public.rs_tickets for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
