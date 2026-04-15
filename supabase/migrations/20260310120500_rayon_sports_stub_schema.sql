-- ============================================================================
-- Rayon Sports stub schema (legacy compatibility)
-- ----------------------------------------------------------------------------
-- Creates minimal rs_* table stubs that downstream migrations reference.
-- These tables are DROP'd by 20260404082430_purge_rayon_sports.sql and
-- 20260410104900_purge_remaining_rayon_era_tables.sql.
-- ============================================================================

create table if not exists public.rs_fan_clubs (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid,
  name text not null,
  region text not null default 'Kigali',
  description text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.rs_fan_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,
  partner_id uuid references public.partners(id) on delete cascade,
  membership_number text,
  tier text default 'blue',
  points integer default 0,
  is_active boolean default true,
  chapter text,
  joined_at timestamptz default now(),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  is_mock boolean not null default false,
  mock_batch text,
  unique (user_id, partner_id)
);

create table if not exists public.rs_fan_club_members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid references public.rs_fan_clubs(id) on delete cascade,
  fan_club_id uuid references public.rs_fan_clubs(id) on delete cascade,
  user_id uuid references public.users(id) on delete cascade,
  role text default 'member',
  joined_at timestamptz default now(),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  is_mock boolean not null default false,
  mock_batch text,
  unique (club_id, user_id)
);

create table if not exists public.rs_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,
  partner_id uuid,
  achievement_type text,
  badge_type text,
  title text,
  name text,
  description text,
  emoji text,
  is_earned boolean default true,
  earned_at timestamptz default now(),
  created_at timestamptz default now(),
  is_mock boolean not null default false,
  mock_batch text,
  unique (user_id, partner_id, badge_type)
);

create table if not exists public.rs_matches (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid,
  home_team text not null,
  away_team text not null,
  match_date timestamptz not null,
  kickoff_time text,
  venue text,
  competition text,
  home_score integer,
  away_score integer,
  status text default 'scheduled',
  image_url text,
  is_on_sale boolean default false,
  ticket_general_price integer default 0,
  ticket_vip_price integer default 0,
  sale_starts_at timestamptz,
  capacity integer,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  is_mock boolean not null default false,
  mock_batch text
);

create table if not exists public.rs_shop_products (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid,
  name text not null,
  description text,
  category text not null default 'general',
  price integer not null default 0,
  image_url text,
  image_emoji text,
  stock integer default 0,
  bg_color text,
  is_new boolean default false,
  is_available boolean default true,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  is_mock boolean not null default false,
  mock_batch text
);

create table if not exists public.rs_shop_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade,
  partner_id uuid,
  product_id uuid references public.rs_shop_products(id) on delete set null,
  items jsonb,
  quantity integer default 1,
  subtotal integer default 0,
  discount integer default 0,
  total integer default 0,
  total_price integer default 0,
  delivery_address text,
  momo_reference text,
  referral_invite_id uuid,
  status text default 'pending',
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  is_mock boolean not null default false,
  mock_batch text
);

create table if not exists public.rs_initiatives (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid,
  title text not null,
  description text,
  category text not null default 'general',
  target_amount integer default 0,
  current_amount integer default 0,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.rs_initiative_contributions (
  id uuid primary key default gen_random_uuid(),
  initiative_id uuid references public.rs_initiatives(id) on delete cascade,
  user_id uuid references public.users(id) on delete cascade,
  amount integer not null,
  momo_reference text,
  status text default 'pending',
  referral_invite_id uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  is_mock boolean not null default false,
  mock_batch text
);

create table if not exists public.rs_tickets (
  id uuid primary key default gen_random_uuid(),
  match_id uuid references public.rs_matches(id) on delete cascade,
  user_id uuid references public.users(id) on delete cascade,
  ticket_type text default 'general',
  seat_type text,
  price integer default 0,
  amount_paid integer default 0,
  status text default 'active',
  qr_code text,
  momo_reference text,
  referral_invite_id uuid,
  purchased_at timestamptz default now(),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  is_mock boolean not null default false,
  mock_batch text
);

create table if not exists public.rs_notifications (
  id uuid primary key default gen_random_uuid(),
  match_id uuid references public.rs_matches(id) on delete cascade,
  title text not null,
  body text,
  status text default 'pending',
  sent_at timestamptz,
  created_by uuid,
  created_at timestamptz default now()
);

create table if not exists public.rs_home_banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subtitle text,
  badge_label text,
  cta_label text,
  route text,
  image_url text,
  match_id uuid references public.rs_matches(id) on delete set null,
  is_active boolean default true,
  sort_order integer default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table if not exists public.rs_match_predictions (
  id uuid primary key default gen_random_uuid(),
  match_id uuid references public.rs_matches(id) on delete cascade,
  user_id uuid references public.users(id) on delete cascade,
  predicted_home_score integer,
  predicted_away_score integer,
  created_at timestamptz default now()
);
alter table public.rs_match_predictions enable row level security;

create table if not exists public.rs_match_commentary (
  id uuid primary key default gen_random_uuid(),
  match_id uuid references public.rs_matches(id) on delete cascade,
  minute integer,
  event_type text,
  content text,
  created_at timestamptz default now()
);
alter table public.rs_match_commentary enable row level security;

-- Indexes downstream migrations expect
create index if not exists idx_rs_fan_memberships_user on public.rs_fan_memberships(user_id);
create index if not exists idx_rs_fan_memberships_partner on public.rs_fan_memberships(partner_id);
create index if not exists idx_rs_tickets_referral_invite on public.rs_tickets(referral_invite_id) where referral_invite_id is not null;
create index if not exists idx_rs_shop_orders_referral_invite on public.rs_shop_orders(referral_invite_id) where referral_invite_id is not null;
create index if not exists idx_rs_initiative_contributions_referral_invite on public.rs_initiative_contributions(referral_invite_id) where referral_invite_id is not null;

-- Stub functions referenced by downstream migrations
create or replace function public.rs_is_partner_admin(p_partner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select false;
$$;
grant execute on function public.rs_is_partner_admin(uuid) to authenticated, service_role;
