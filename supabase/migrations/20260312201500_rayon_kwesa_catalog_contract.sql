-- ============================================================================
-- Cool App — Rayon Sports KWESA catalog contract
-- ----------------------------------------------------------------------------
-- Upgrades the live Rayon Sports partner from the old merchandise/ticket schema
-- to the new rs_* app contract, using auth.users-compatible foreign keys and
-- seeded mock data for shop, clubs, initiatives, matches, and member registry.
-- ============================================================================

create extension if not exists pgcrypto;
create or replace function public.rs_resolve_public_identity(
  p_user_id uuid,
  p_seeded text default null
)
returns text
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_candidate text := nullif(btrim(coalesce(p_seeded, '')), '');
  v_meta_identity text;
  v_hash bigint;
begin
  if v_candidate ~ '^[0-9]{6}$' then
    return v_candidate;
  end if;

  select coalesce(
    nullif(btrim(raw_user_meta_data ->> 'public_user_id'), ''),
    nullif(btrim(raw_app_meta_data ->> 'public_user_id'), '')
  )
  into v_meta_identity
  from auth.users
  where id = p_user_id;

  if coalesce(v_meta_identity, '') ~ '^[0-9]{6}$' then
    return v_meta_identity;
  end if;

  if p_user_id is null then
    return '000000';
  end if;

  v_hash := (('x' || substr(replace(p_user_id::text, '-', ''), 1, 14))::bit(56)::bigint);
  return lpad((100000 + (v_hash % 900000))::text, 6, '0');
end;
$$;
revoke all on function public.rs_resolve_public_identity(uuid, text) from public;
grant execute on function public.rs_resolve_public_identity(uuid, text) to authenticated, service_role;
alter table public.partners
  add column if not exists slug text,
  add column if not exists category text not null default 'football',
  add column if not exists country text not null default 'RW',
  add column if not exists emoji text not null default '🤝',
  add column if not exists subtitle text,
  add column if not exists whatsapp_number text,
  add column if not exists description text,
  add column if not exists logo_url text,
  add column if not exists banner_url text,
  add column if not exists brand_primary_color text,
  add column if not exists brand_secondary_color text,
  add column if not exists website_url text,
  add column if not exists fan_count int not null default 0,
  add column if not exists club_count int not null default 0,
  add column if not exists game_count int not null default 0,
  add column if not exists is_active boolean not null default true,
  add column if not exists sort_order int not null default 0,
  add column if not exists metadata jsonb not null default '{}'::jsonb,
  add column if not exists updated_at timestamptz not null default now();
create unique index if not exists idx_partners_slug_unique
  on public.partners (slug)
  where slug is not null;
insert into public.partners (
  slug,
  name,
  category,
  country,
  emoji,
  subtitle,
  description,
  logo_url,
  banner_url,
  brand_primary_color,
  brand_secondary_color,
  whatsapp_number,
  website_url,
  fan_count,
  club_count,
  game_count,
  is_active,
  sort_order,
  metadata
)
values (
  'rayon-sports',
  'Rayon Sports FC',
  'football',
  'RW',
  '⚽',
  'Rwanda Premier League · Gikundiro Hub',
  'Rayon Sports digital hub for the Gikundiro community: memberships, fan clubs, support initiatives, tickets, and club shop.',
  'https://kwesa.rw/wp-content/uploads/2024/08/Rayon-logo.png',
  'https://kwesa.rw/wp-content/uploads/2024/08/rayon-sports-banner.jpg',
  '#0D47A1',
  '#F7C948',
  null,
  'https://kwesa.rw',
  0,
  4,
  3,
  true,
  10,
  jsonb_build_object(
    'shop_provider', 'KWESA mock catalog',
    'kit_brand', 'KWESA',
    'ticket_ussd', '*939*3*2*1#',
    'catalog_source', 'kwesa_rayon_archive_mock_2026_03_12'
  )
)
on conflict (slug) do update
set
  name = excluded.name,
  category = excluded.category,
  country = excluded.country,
  emoji = excluded.emoji,
  subtitle = excluded.subtitle,
  description = excluded.description,
  logo_url = coalesce(excluded.logo_url, public.partners.logo_url),
  banner_url = coalesce(excluded.banner_url, public.partners.banner_url),
  brand_primary_color = excluded.brand_primary_color,
  brand_secondary_color = excluded.brand_secondary_color,
  whatsapp_number = excluded.whatsapp_number,
  website_url = excluded.website_url,
  fan_count = greatest(coalesce(public.partners.fan_count, 0), excluded.fan_count),
  club_count = greatest(coalesce(public.partners.club_count, 0), excluded.club_count),
  game_count = greatest(coalesce(public.partners.game_count, 0), excluded.game_count),
  is_active = true,
  sort_order = excluded.sort_order,
  metadata = coalesce(public.partners.metadata, '{}'::jsonb) || excluded.metadata,
  updated_at = now();
create table if not exists public.rs_fan_memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  display_name text not null default '000000',
  tier text not null default 'blue'
    check (tier in ('blue', 'silver', 'gold', 'platinum')),
  points int not null default 0,
  joined_at timestamptz not null default now(),
  chapter text,
  membership_number text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_mock boolean not null default false,
  mock_batch text,
  unique (user_id, partner_id)
);
create table if not exists public.rs_fan_clubs (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  name text not null,
  region text not null,
  description text,
  member_count int not null default 0,
  event_count int not null default 0,
  rating numeric(3, 2) not null default 0,
  banner_emoji text not null default '🥁',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_mock boolean not null default false,
  mock_batch text
);
create table if not exists public.rs_fan_club_members (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.rs_fan_clubs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  is_mock boolean not null default false,
  mock_batch text,
  unique (club_id, user_id)
);
create table if not exists public.rs_achievements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  partner_id uuid not null references public.partners(id) on delete cascade,
  badge_type text not null,
  emoji text not null default '🏆',
  name text not null default 'Achievement',
  description text not null default '',
  is_earned boolean not null default true,
  earned_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  is_mock boolean not null default false,
  mock_batch text
);
create table if not exists public.rs_shop_products (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  name text not null,
  description text not null default '',
  category text not null,
  price int not null default 0 check (price >= 0),
  image_emoji text not null default '🛍️',
  image_url text,
  bg_color text not null default '#173866',
  sizes jsonb not null default '[]'::jsonb,
  badge_label text,
  collection text,
  stock int not null default 0,
  is_active boolean not null default true,
  is_new boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_mock boolean not null default false,
  mock_batch text
);
create table if not exists public.rs_shop_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  items jsonb not null default '[]'::jsonb,
  subtotal int not null default 0,
  discount_amount int not null default 0,
  discount int not null default 0,
  delivery_fee int not null default 0,
  total int not null default 0,
  delivery_address text,
  momo_reference text,
  referral_invite_id text,
  status text not null default 'pending',
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_mock boolean not null default false,
  mock_batch text
);
create table if not exists public.rs_initiatives (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  title text not null,
  description text not null default '',
  category text not null,
  target_amount int not null default 0,
  raised_amount int not null default 0,
  supporter_count int not null default 0,
  is_active boolean not null default true,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_mock boolean not null default false,
  mock_batch text
);
create table if not exists public.rs_initiative_contributions (
  id uuid primary key default gen_random_uuid(),
  initiative_id uuid not null references public.rs_initiatives(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  amount int not null default 0,
  momo_reference text,
  referral_invite_id text,
  supporter_name text,
  status text not null default 'pending',
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_mock boolean not null default false,
  mock_batch text
);
create table if not exists public.rs_matches (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partners(id) on delete cascade,
  home_team text not null,
  away_team text not null,
  competition text not null,
  venue text not null,
  match_date timestamptz not null,
  kickoff_time text not null default '15:00',
  is_on_sale boolean not null default true,
  ticket_general_price int not null default 0,
  ticket_vip_price int not null default 0,
  sale_starts_at timestamptz,
  capacity int not null default 0,
  sold_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_mock boolean not null default false,
  mock_batch text
);
create table if not exists public.rs_tickets (
  id uuid primary key default gen_random_uuid(),
  match_id uuid not null references public.rs_matches(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  seat_type text not null default 'general',
  amount_paid int not null default 0,
  qr_code text,
  momo_reference text,
  referral_invite_id text,
  status text not null default 'pending',
  confirmed_at timestamptz,
  purchased_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  is_mock boolean not null default false,
  mock_batch text
);
alter table public.rs_fan_memberships
  add column if not exists display_name text,
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
alter table public.rs_fan_clubs
  add column if not exists event_count int not null default 0,
  add column if not exists rating numeric(3, 2) not null default 0,
  add column if not exists banner_emoji text not null default '🥁',
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
alter table public.rs_fan_club_members
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
alter table public.rs_achievements
  add column if not exists emoji text not null default '🏆',
  add column if not exists name text not null default 'Achievement',
  add column if not exists description text not null default '',
  add column if not exists is_earned boolean not null default true,
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
alter table public.rs_shop_products
  add column if not exists description text not null default '',
  add column if not exists image_url text,
  add column if not exists bg_color text not null default '#173866',
  add column if not exists sizes jsonb not null default '[]'::jsonb,
  add column if not exists badge_label text,
  add column if not exists collection text,
  add column if not exists is_new boolean not null default false,
  add column if not exists sort_order int not null default 0,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
alter table public.rs_shop_orders
  add column if not exists discount_amount int not null default 0,
  add column if not exists discount int not null default 0,
  add column if not exists delivery_fee int not null default 0,
  add column if not exists referral_invite_id text,
  add column if not exists confirmed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
alter table public.rs_initiatives
  add column if not exists supporter_count int not null default 0,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
alter table public.rs_initiative_contributions
  add column if not exists referral_invite_id text,
  add column if not exists supporter_name text,
  add column if not exists confirmed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
alter table public.rs_matches
  add column if not exists sale_starts_at timestamptz,
  add column if not exists capacity int not null default 0,
  add column if not exists sold_count int not null default 0,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
alter table public.rs_tickets
  add column if not exists referral_invite_id text,
  add column if not exists confirmed_at timestamptz,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
update public.rs_fan_memberships
set
  display_name = public.rs_resolve_public_identity(user_id, display_name),
  updated_at = coalesce(updated_at, now())
where coalesce(display_name, '') = ''
   or display_name !~ '^[0-9]{6}$';
update public.rs_initiative_contributions
set supporter_name = public.rs_resolve_public_identity(user_id, supporter_name)
where coalesce(supporter_name, '') = ''
   or supporter_name !~ '^[0-9]{6}$';
update public.rs_shop_orders
set discount_amount = coalesce(discount_amount, discount, 0),
    discount = coalesce(discount, discount_amount, 0),
    delivery_fee = coalesce(delivery_fee, 0)
where discount_amount is null
   or discount is null
   or delivery_fee is null;
alter table public.rs_fan_memberships
  alter column display_name set default '000000';
update public.rs_fan_memberships
set display_name = '000000'
where display_name is null;
alter table public.rs_fan_memberships
  alter column display_name set not null;
alter table public.rs_shop_orders
  drop constraint if exists rs_shop_orders_status_check;
alter table public.rs_shop_orders
  add constraint rs_shop_orders_status_check
  check (
    status in (
      'pending',
      'paid',
      'confirmed',
      'packed',
      'shipped',
      'fulfilled',
      'delivered',
      'cancelled'
    )
  );
alter table public.rs_initiative_contributions
  drop constraint if exists rs_initiative_contributions_status_check;
alter table public.rs_initiative_contributions
  add constraint rs_initiative_contributions_status_check
  check (status in ('pending', 'confirmed', 'failed', 'cancelled'));
alter table public.rs_tickets
  drop constraint if exists rs_tickets_status_check;
alter table public.rs_tickets
  add constraint rs_tickets_status_check
  check (status in ('pending', 'valid', 'used', 'cancelled'));
create unique index if not exists idx_rs_fan_clubs_partner_name
  on public.rs_fan_clubs (partner_id, name);
create unique index if not exists idx_rs_shop_products_partner_name
  on public.rs_shop_products (partner_id, name);
create unique index if not exists idx_rs_initiatives_partner_title
  on public.rs_initiatives (partner_id, title);
create unique index if not exists idx_rs_matches_partner_fixture
  on public.rs_matches (partner_id, home_team, away_team, match_date);
create index if not exists idx_rs_fan_memberships_partner
  on public.rs_fan_memberships (partner_id, points desc, tier);
create index if not exists idx_rs_fan_memberships_user
  on public.rs_fan_memberships (user_id);
create index if not exists idx_rs_fan_club_members_user
  on public.rs_fan_club_members (user_id);
create index if not exists idx_rs_shop_products_partner_catalog
  on public.rs_shop_products (partner_id, is_active, sort_order, price, name);
create index if not exists idx_rs_shop_orders_user_created
  on public.rs_shop_orders (user_id, created_at desc);
create index if not exists idx_rs_shop_orders_momo_reference
  on public.rs_shop_orders (momo_reference)
  where momo_reference is not null;
create index if not exists idx_rs_initiatives_partner_active
  on public.rs_initiatives (partner_id, is_active, ends_at);
create index if not exists idx_rs_initiative_contributions_initiative
  on public.rs_initiative_contributions (initiative_id, created_at desc);
create index if not exists idx_rs_matches_partner_date
  on public.rs_matches (partner_id, match_date);
create index if not exists idx_rs_tickets_user_purchased
  on public.rs_tickets (user_id, purchased_at desc);
create or replace function public.rs_sync_membership_fields()
returns trigger
language plpgsql
as $$
begin
  new.points := greatest(coalesce(new.points, 0), 0);
  new.tier := case
    when new.points >= 5000 then 'platinum'
    when new.points >= 2000 then 'gold'
    when new.points >= 1000 then 'silver'
    else 'blue'
  end;
  new.chapter := coalesce(nullif(btrim(coalesce(new.chapter, '')), ''), 'Kigali Central');
  new.display_name := public.rs_resolve_public_identity(new.user_id, new.display_name);

  if coalesce(nullif(btrim(coalesce(new.membership_number, '')), ''), '') = '' then
    new.membership_number := 'RS-' ||
      to_char(coalesce(new.joined_at, now()), 'YYYY') ||
      '-' ||
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  end if;

  if tg_op = 'INSERT' then
    new.created_at := coalesce(new.created_at, now());
    new.joined_at := coalesce(new.joined_at, new.created_at, now());
  end if;

  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_rs_fan_memberships_sync_fields on public.rs_fan_memberships;
create trigger trg_rs_fan_memberships_sync_fields
  before insert or update on public.rs_fan_memberships
  for each row
  execute function public.rs_sync_membership_fields();
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
drop policy if exists rs_fan_memberships_select_authenticated on public.rs_fan_memberships;
create policy rs_fan_memberships_select_authenticated
  on public.rs_fan_memberships for select
  using (auth.role() = 'authenticated');
drop policy if exists rs_fan_memberships_insert_own on public.rs_fan_memberships;
create policy rs_fan_memberships_insert_own
  on public.rs_fan_memberships for insert
  with check (auth.uid() = user_id);
drop policy if exists rs_fan_memberships_update_own on public.rs_fan_memberships;
create policy rs_fan_memberships_update_own
  on public.rs_fan_memberships for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop policy if exists rs_fan_clubs_select_authenticated on public.rs_fan_clubs;
create policy rs_fan_clubs_select_authenticated
  on public.rs_fan_clubs for select
  using (auth.role() = 'authenticated');
drop policy if exists rs_fan_club_members_select_authenticated on public.rs_fan_club_members;
create policy rs_fan_club_members_select_authenticated
  on public.rs_fan_club_members for select
  using (auth.role() = 'authenticated');
drop policy if exists rs_fan_club_members_insert_own on public.rs_fan_club_members;
create policy rs_fan_club_members_insert_own
  on public.rs_fan_club_members for insert
  with check (auth.uid() = user_id);
drop policy if exists rs_fan_club_members_delete_own on public.rs_fan_club_members;
create policy rs_fan_club_members_delete_own
  on public.rs_fan_club_members for delete
  using (auth.uid() = user_id);
drop policy if exists rs_achievements_select_own on public.rs_achievements;
create policy rs_achievements_select_own
  on public.rs_achievements for select
  using (auth.uid() = user_id);
drop policy if exists rs_shop_products_select_authenticated on public.rs_shop_products;
create policy rs_shop_products_select_authenticated
  on public.rs_shop_products for select
  using (auth.role() = 'authenticated');
drop policy if exists rs_shop_orders_select_own on public.rs_shop_orders;
create policy rs_shop_orders_select_own
  on public.rs_shop_orders for select
  using (auth.uid() = user_id);
drop policy if exists rs_shop_orders_insert_own on public.rs_shop_orders;
create policy rs_shop_orders_insert_own
  on public.rs_shop_orders for insert
  with check (auth.uid() = user_id);
drop policy if exists rs_shop_orders_update_own on public.rs_shop_orders;
create policy rs_shop_orders_update_own
  on public.rs_shop_orders for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop policy if exists rs_initiatives_select_authenticated on public.rs_initiatives;
create policy rs_initiatives_select_authenticated
  on public.rs_initiatives for select
  using (auth.role() = 'authenticated');
drop policy if exists rs_initiative_contributions_select_authenticated on public.rs_initiative_contributions;
create policy rs_initiative_contributions_select_authenticated
  on public.rs_initiative_contributions for select
  using (auth.role() = 'authenticated');
drop policy if exists rs_initiative_contributions_insert_own on public.rs_initiative_contributions;
create policy rs_initiative_contributions_insert_own
  on public.rs_initiative_contributions for insert
  with check (auth.uid() = user_id);
drop policy if exists rs_initiative_contributions_update_own on public.rs_initiative_contributions;
create policy rs_initiative_contributions_update_own
  on public.rs_initiative_contributions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop policy if exists rs_matches_select_authenticated on public.rs_matches;
create policy rs_matches_select_authenticated
  on public.rs_matches for select
  using (auth.role() = 'authenticated');
drop policy if exists rs_tickets_select_own on public.rs_tickets;
create policy rs_tickets_select_own
  on public.rs_tickets for select
  using (auth.uid() = user_id);
drop policy if exists rs_tickets_insert_own on public.rs_tickets;
create policy rs_tickets_insert_own
  on public.rs_tickets for insert
  with check (auth.uid() = user_id);
drop policy if exists rs_tickets_update_own on public.rs_tickets;
create policy rs_tickets_update_own
  on public.rs_tickets for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create or replace function public.get_rayon_member_registry(
  p_partner_id uuid,
  p_search_query text default null,
  p_filter_tier text default null,
  p_region text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  user_id uuid,
  display_name text,
  membership_number text,
  points integer,
  tier text,
  chapter text,
  joined_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_search text := nullif(btrim(coalesce(p_search_query, '')), '');
  v_tier text := lower(nullif(btrim(coalesce(p_filter_tier, '')), ''));
  v_region text := nullif(btrim(coalesce(p_region, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  return query
  select
    membership.user_id,
    membership.display_name,
    membership.membership_number,
    membership.points,
    membership.tier,
    membership.chapter,
    membership.joined_at
  from public.rs_fan_memberships membership
  where membership.partner_id = p_partner_id
    and (v_tier is null or lower(membership.tier) = v_tier)
    and (v_region is null or coalesce(membership.chapter, '') ilike '%' || v_region || '%')
    and (
      v_search is null
      or membership.display_name ilike '%' || v_search || '%'
      or membership.membership_number ilike '%' || v_search || '%'
    )
  order by membership.points desc, membership.joined_at asc, membership.membership_number asc
  limit greatest(coalesce(p_limit, 20), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
revoke all on function public.get_rayon_member_registry(uuid, text, text, text, integer, integer) from public;
grant execute on function public.get_rayon_member_registry(uuid, text, text, text, integer, integer) to authenticated;
create or replace function public.rs_apply_membership_points(
  p_user_id uuid,
  p_partner_id uuid,
  p_points int,
  p_chapter text default null
)
returns public.rs_fan_memberships
language plpgsql
security definer
set search_path = public
as $$
declare
  v_membership public.rs_fan_memberships;
  v_chapter text := coalesce(nullif(btrim(coalesce(p_chapter, '')), ''), 'Kigali Central');
begin
  insert into public.rs_fan_memberships (
    user_id,
    partner_id,
    display_name,
    points,
    chapter,
    membership_number,
    joined_at,
    created_at,
    updated_at
  )
  values (
    p_user_id,
    p_partner_id,
    public.rs_resolve_public_identity(p_user_id),
    greatest(coalesce(p_points, 0), 0),
    v_chapter,
    'RS-' || to_char(now(), 'YYYY') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6)),
    now(),
    now(),
    now()
  )
  on conflict (user_id, partner_id) do update
    set
      points = greatest(public.rs_fan_memberships.points + coalesce(p_points, 0), 0),
      display_name = public.rs_resolve_public_identity(excluded.user_id, public.rs_fan_memberships.display_name),
      chapter = coalesce(nullif(btrim(public.rs_fan_memberships.chapter), ''), excluded.chapter),
      updated_at = now()
  returning * into v_membership;

  return v_membership;
end;
$$;
revoke all on function public.rs_apply_membership_points(uuid, uuid, int, text) from public;
grant execute on function public.rs_apply_membership_points(uuid, uuid, int, text) to authenticated, service_role;
do $$
declare
  v_partner_id uuid;
  v_mock_batch constant text := 'rayon_kwesa_2026_03_12';
begin
  select id
  into v_partner_id
  from public.partners
  where slug = 'rayon-sports'
  limit 1;

  if v_partner_id is null then
    raise exception 'Rayon Sports partner not found after upsert.';
  end if;

  insert into public.rs_fan_clubs (
    partner_id,
    name,
    region,
    description,
    member_count,
    event_count,
    rating,
    banner_emoji,
    is_mock,
    mock_batch
  )
  values
    (
      v_partner_id,
      'Kigali Blue Chapter',
      'Kigali',
      'Central Kigali supporters who coordinate matchday drums, away travel, and club shop pickups.',
      184,
      18,
      4.9,
      '🥁',
      true,
      v_mock_batch
    ),
    (
      v_partner_id,
      'Northern Blue Front',
      'Northern',
      'Supporters across Musanze and Gicumbi organizing buses for home fixtures and youth watch parties.',
      96,
      11,
      4.7,
      '🚌',
      true,
      v_mock_batch
    ),
    (
      v_partner_id,
      'Southern Blue Brigade',
      'Southern',
      'Huye-based Gikundiro chapter focused on academy fundraising and women supporters outreach.',
      72,
      9,
      4.8,
      '📣',
      true,
      v_mock_batch
    ),
    (
      v_partner_id,
      'Diaspora Blue Wave',
      'Diaspora',
      'International supporters coordinating digital campaigns, ticket gifting, and merch orders.',
      58,
      14,
      4.9,
      '🌍',
      true,
      v_mock_batch
    )
  on conflict (partner_id, name) do update
    set
      region = excluded.region,
      description = excluded.description,
      member_count = excluded.member_count,
      event_count = excluded.event_count,
      rating = excluded.rating,
      banner_emoji = excluded.banner_emoji,
      is_mock = excluded.is_mock,
      mock_batch = excluded.mock_batch,
      updated_at = now();

  insert into public.rs_shop_products (
    partner_id,
    name,
    description,
    category,
    price,
    image_emoji,
    bg_color,
    sizes,
    badge_label,
    collection,
    stock,
    is_active,
    is_new,
    sort_order,
    is_mock,
    mock_batch
  )
  values
    (v_partner_id, 'Home Replica Jersey', '2025/26 home replica in iconic royal blue.', 'replica', 35000, '👕', '#0A49C9', jsonb_build_array('S', 'M', 'L', 'XL', 'XXL'), 'BESTSELLER', '2025/26 Matchwear', 90, true, false, 10, true, v_mock_batch),
    (v_partner_id, 'Away Replica Jersey', '2025/26 away replica for travel days and away stands.', 'replica', 35000, '👕', '#F2EDE3', jsonb_build_array('S', 'M', 'L', 'XL', 'XXL'), 'NEW', '2025/26 Matchwear', 84, true, true, 20, true, v_mock_batch),
    (v_partner_id, '1968 Jersey', 'Heritage jersey celebrating the founding year of the club.', 'heritage', 25000, '🧵', '#114EA8', jsonb_build_array('S', 'M', 'L', 'XL'), null, 'Legends Collection', 40, true, false, 30, true, v_mock_batch),
    (v_partner_id, 'Warm Up Top', 'Pre-match warm-up layer styled for the Pelé Stadium tunnel.', 'training', 20000, '🏃', '#1F3E78', jsonb_build_array('S', 'M', 'L', 'XL'), null, 'Training', 55, true, false, 40, true, v_mock_batch),
    (v_partner_id, 'Rayon Hoodie', 'Heavyweight supporter hoodie for cool evening fixtures.', 'hoodie', 25000, '🧥', '#1B2D57', jsonb_build_array('M', 'L', 'XL', 'XXL'), null, 'Supporter Wear', 48, true, false, 50, true, v_mock_batch),
    (v_partner_id, 'Rayon Gilet', 'Matchday gilet for travel crews and organizing teams.', 'gilet', 15000, '🦺', '#21407D', jsonb_build_array('M', 'L', 'XL'), null, 'Supporter Wear', 36, true, false, 60, true, v_mock_batch),
    (v_partner_id, 'Rayon Cap', 'Classic cap with embroidered crest for sunny kickoffs.', 'cap', 6000, '🧢', '#D5A316', jsonb_build_array('One Size'), null, 'Accessories', 120, true, false, 70, true, v_mock_batch),
    (v_partner_id, 'Gikundiro Scarf', 'Double-sided scarf for home stands and derby nights.', 'scarf', 8000, '🧣', '#17428A', jsonb_build_array('One Size'), null, 'Accessories', 110, true, false, 80, true, v_mock_batch),
    (v_partner_id, 'Rayon Slipper', 'Relaxed slip-on footwear in club colors.', 'slipper', 15000, '🩴', '#12396E', jsonb_build_array('39', '40', '41', '42', '43'), null, 'Footwear', 44, true, false, 90, true, v_mock_batch),
    (v_partner_id, 'Rayon Sports Ball', 'Supporter-grade ball for community pitches and watch parties.', 'ball', 15000, '⚽', '#173866', jsonb_build_array('Size 5'), null, 'Training', 32, true, false, 100, true, v_mock_batch),
    (v_partner_id, 'Rayon Watch', 'Club-branded wristwatch for everyday supporters.', 'watch', 10000, '⌚', '#244B86', jsonb_build_array('One Size'), null, 'Accessories', 26, true, false, 110, true, v_mock_batch),
    (v_partner_id, 'Rayon Valeze', 'Compact travel bag for away trips and supporter roadshows.', 'valeze', 6000, '🧳', '#2C5693', jsonb_build_array('One Size'), null, 'Travel', 38, true, false, 120, true, v_mock_batch)
  on conflict (partner_id, name) do update
    set
      description = excluded.description,
      category = excluded.category,
      price = excluded.price,
      image_emoji = excluded.image_emoji,
      bg_color = excluded.bg_color,
      sizes = excluded.sizes,
      badge_label = excluded.badge_label,
      collection = excluded.collection,
      stock = excluded.stock,
      is_active = excluded.is_active,
      is_new = excluded.is_new,
      sort_order = excluded.sort_order,
      is_mock = excluded.is_mock,
      mock_batch = excluded.mock_batch,
      updated_at = now();

  insert into public.rs_initiatives (
    partner_id,
    title,
    description,
    category,
    target_amount,
    raised_amount,
    supporter_count,
    is_active,
    ends_at,
    is_mock,
    mock_batch
  )
  values
    (
      v_partner_id,
      'Academy Nutrition Drive',
      'Fund meals, hydration, and recovery support for Rayon youth squads through the second half of the season.',
      'youth',
      8500000,
      2940000,
      118,
      true,
      timestamptz '2026-04-20 21:00:00+00',
      true,
      v_mock_batch
    ),
    (
      v_partner_id,
      'Stadium Atmosphere Fund',
      'Support drums, flags, tifo materials, and safe supporter coordination for major fixtures.',
      'stadium',
      12000000,
      4850000,
      164,
      true,
      timestamptz '2026-05-05 21:00:00+00',
      true,
      v_mock_batch
    ),
    (
      v_partner_id,
      'Community Pitch Days',
      'Sponsor outreach matches, local clinics, and equipment for community football in Rayon chapters.',
      'community',
      6000000,
      1750000,
      72,
      true,
      timestamptz '2026-05-18 21:00:00+00',
      true,
      v_mock_batch
    )
  on conflict (partner_id, title) do update
    set
      description = excluded.description,
      category = excluded.category,
      target_amount = excluded.target_amount,
      raised_amount = excluded.raised_amount,
      supporter_count = excluded.supporter_count,
      is_active = excluded.is_active,
      ends_at = excluded.ends_at,
      is_mock = excluded.is_mock,
      mock_batch = excluded.mock_batch,
      updated_at = now();

  insert into public.rs_matches (
    partner_id,
    home_team,
    away_team,
    competition,
    venue,
    match_date,
    kickoff_time,
    is_on_sale,
    ticket_general_price,
    ticket_vip_price,
    sale_starts_at,
    capacity,
    sold_count,
    is_mock,
    mock_batch
  )
  values
    (
      v_partner_id,
      'Rayon Sports FC',
      'APR FC',
      'Rwanda Premier League',
      'Amahoro Stadium',
      timestamptz '2026-03-21 16:00:00+02',
      '18:00',
      true,
      3000,
      8000,
      timestamptz '2026-03-10 08:00:00+02',
      28000,
      16240,
      true,
      v_mock_batch
    ),
    (
      v_partner_id,
      'Rayon Sports FC',
      'AS Kigali',
      'Peace Cup',
      'Kigali Pelé Stadium',
      timestamptz '2026-03-29 14:00:00+02',
      '16:00',
      true,
      2500,
      7000,
      timestamptz '2026-03-18 08:00:00+02',
      18000,
      8240,
      true,
      v_mock_batch
    ),
    (
      v_partner_id,
      'Musanze FC',
      'Rayon Sports FC',
      'Rwanda Premier League',
      'Ubworoherane Stadium',
      timestamptz '2026-04-12 13:00:00+02',
      '15:00',
      false,
      2500,
      6500,
      timestamptz '2026-04-01 08:00:00+02',
      14000,
      0,
      true,
      v_mock_batch
    )
  on conflict (partner_id, home_team, away_team, match_date) do update
    set
      competition = excluded.competition,
      venue = excluded.venue,
      kickoff_time = excluded.kickoff_time,
      is_on_sale = excluded.is_on_sale,
      ticket_general_price = excluded.ticket_general_price,
      ticket_vip_price = excluded.ticket_vip_price,
      sale_starts_at = excluded.sale_starts_at,
      capacity = excluded.capacity,
      sold_count = excluded.sold_count,
      is_mock = excluded.is_mock,
      mock_batch = excluded.mock_batch,
      updated_at = now();

  with mock_users as (
    select
      id,
      row_number() over (order by created_at asc, id asc) as rn
    from auth.users
    order by created_at asc, id asc
    limit 3
  )
  insert into public.rs_fan_memberships (
    user_id,
    partner_id,
    display_name,
    tier,
    points,
    joined_at,
    chapter,
    membership_number,
    created_at,
    updated_at,
    is_mock,
    mock_batch
  )
  select
    user_id_map.id,
    v_partner_id,
    public.rs_resolve_public_identity(user_id_map.id),
    case user_id_map.rn
      when 1 then 'gold'
      when 2 then 'silver'
      else 'blue'
    end,
    case user_id_map.rn
      when 1 then 2680
      when 2 then 1425
      else 640
    end,
    now() - make_interval(days => ((user_id_map.rn * 21)::int)),
    case user_id_map.rn
      when 1 then 'Kigali Central'
      when 2 then 'Southern Province'
      else 'Diaspora'
    end,
    'RS-2026-MOCK' || lpad(user_id_map.rn::text, 3, '0'),
    now(),
    now(),
    true,
    v_mock_batch
  from mock_users user_id_map
  on conflict (user_id, partner_id) do nothing;

  with mock_users as (
    select
      id,
      row_number() over (order by created_at asc, id asc) as rn
    from auth.users
    order by created_at asc, id asc
    limit 3
  ),
  club_assignment as (
    select
      mock_users.id as user_id,
      case mock_users.rn
        when 1 then 'Kigali Blue Chapter'
        when 2 then 'Southern Blue Brigade'
        else 'Diaspora Blue Wave'
      end as club_name,
      now() - make_interval(days => ((mock_users.rn * 9)::int)) as joined_at
    from mock_users
  )
  insert into public.rs_fan_club_members (
    club_id,
    user_id,
    joined_at,
    created_at,
    is_mock,
    mock_batch
  )
  select
    clubs.id,
    club_assignment.user_id,
    club_assignment.joined_at,
    club_assignment.joined_at,
    true,
    v_mock_batch
  from club_assignment
  join public.rs_fan_clubs clubs
    on clubs.partner_id = v_partner_id
   and clubs.name = club_assignment.club_name
  on conflict (club_id, user_id) do nothing;

  with mock_users as (
    select
      id,
      row_number() over (order by created_at asc, id asc) as rn
    from auth.users
    order by created_at asc, id asc
    limit 3
  )
  insert into public.rs_achievements (
    user_id,
    partner_id,
    badge_type,
    emoji,
    name,
    description,
    is_earned,
    earned_at,
    created_at,
    is_mock,
    mock_batch
  )
  select
    mock_users.id,
    v_partner_id,
    case mock_users.rn
      when 1 then 'matchday_captain'
      when 2 then 'academy_backer'
      else 'club_shop_supporter'
    end,
    case mock_users.rn
      when 1 then '🎺'
      when 2 then '🌱'
      else '🛍️'
    end,
    case mock_users.rn
      when 1 then 'Matchday Captain'
      when 2 then 'Academy Backer'
      else 'Club Shop Supporter'
    end,
    case mock_users.rn
      when 1 then 'Joined organized away-day support and ticket campaigns.'
      when 2 then 'Contributed to the academy and youth development fund.'
      else 'Completed a first official Rayon Sports shop checkout.'
    end,
    true,
    now() - make_interval(days => ((mock_users.rn * 5)::int)),
    now(),
    true,
    v_mock_batch
  from mock_users
  where not exists (
    select 1
    from public.rs_achievements existing
    where existing.user_id = mock_users.id
      and existing.partner_id = v_partner_id
      and existing.badge_type = case mock_users.rn
        when 1 then 'matchday_captain'
        when 2 then 'academy_backer'
        else 'club_shop_supporter'
      end
  );
end;
$$;
