-- ==========================================================================
-- Cool App — Initial Schema Migration
-- ==========================================================================
-- Tables: otp_codes, users, groups, group_members, group_contributions,
--         mobility_trips, driver_profiles, driver_subscriptions,
--         partners, fan_memberships, credit_scores
-- Extensions: postgis, pgcrypto
-- Functions: get_nearby_drivers
-- ==========================================================================

-- ── Extensions ───────────────────────────────────────────────────────────

create extension if not exists "postgis" with schema "extensions";
create extension if not exists "pgcrypto" with schema "extensions";
-- ── OTP codes (used by Edge Functions) ───────────────────────────────────

create table if not exists public.otp_codes (
  id          uuid primary key default gen_random_uuid(),
  phone       text not null,
  code        text not null,
  expires_at  timestamptz not null,
  attempts    int default 0,
  verified    boolean default false,
  created_at  timestamptz default now()
);
create index if not exists idx_otp_codes_phone on public.otp_codes (phone);
-- ── Users (app profiles) ─────────────────────────────────────────────────

create table if not exists public.users (
  id             uuid primary key references auth.users(id) on delete cascade,
  phone          text unique not null,
  full_name      text not null default '',
  country        text not null default 'RW',
  language_code  text not null default 'en',
  momo_number    text,
  avatar_url     text,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);
create index if not exists idx_users_phone on public.users (phone);
-- ── Groups ───────────────────────────────────────────────────────────────

create table if not exists public.groups (
  id                    uuid primary key default gen_random_uuid(),
  name                  text not null,
  description           text,
  country               text not null default 'RW',
  creator_id            uuid not null references public.users(id) on delete cascade,
  visibility            text not null default 'private' check (visibility in ('public', 'private')),
  contribution_amount   int not null default 0,
  cycle_days            int not null default 30,
  member_count          int not null default 0,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
);
create index if not exists idx_groups_country on public.groups (country);
create index if not exists idx_groups_visibility on public.groups (visibility);
-- ── Group members ────────────────────────────────────────────────────────

create table if not exists public.group_members (
  id                    uuid primary key default gen_random_uuid(),
  group_id              uuid not null references public.groups(id) on delete cascade,
  user_id               uuid not null references public.users(id) on delete cascade,
  display_name          text,
  is_admin              boolean default false,
  is_anonymous          boolean default false,
  contribution_amount   int default 0,
  joined_at             timestamptz default now(),
  unique(group_id, user_id)
);
create index if not exists idx_group_members_group on public.group_members (group_id);
create index if not exists idx_group_members_user on public.group_members (user_id);
-- ── Group contributions ──────────────────────────────────────────────────

create table if not exists public.group_contributions (
  id          uuid primary key default gen_random_uuid(),
  group_id    uuid not null references public.groups(id) on delete cascade,
  user_id     uuid not null references public.users(id) on delete cascade,
  amount      int not null default 0,
  status      text not null default 'pending' check (status in ('pending', 'confirmed', 'failed')),
  created_at  timestamptz default now()
);
create index if not exists idx_contributions_group on public.group_contributions (group_id);
create index if not exists idx_contributions_user on public.group_contributions (user_id);
create index if not exists idx_contributions_status on public.group_contributions (status);
-- ── Mobility trips ───────────────────────────────────────────────────────

create table if not exists public.mobility_trips (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.users(id) on delete cascade,
  from_location         text not null,
  to_location           text not null,
  departure_at          timestamptz not null,
  return_at             timestamptz,
  vehicle_preference    text not null default 'any',
  seats_needed          int not null default 1,
  is_return_trip        boolean default false,
  is_recurring_trip     boolean default false,
  is_driver_return_trip boolean default false,
  recurring_days        text[] default '{}',
  status                text not null default 'open' check (status in ('open', 'matched', 'cancelled', 'expired')),
  latitude              double precision,
  longitude             double precision,
  expires_at            timestamptz,
  created_at            timestamptz default now(),
  updated_at            timestamptz default now()
);
create index if not exists idx_trips_status on public.mobility_trips (status);
create index if not exists idx_trips_departure on public.mobility_trips (departure_at);
create index if not exists idx_trips_user on public.mobility_trips (user_id);
-- ── Driver profiles ──────────────────────────────────────────────────────

create table if not exists public.driver_profiles (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid unique not null references public.users(id) on delete cascade,
  vehicle_type    text not null default 'moto',
  plate_number    text not null default '',
  base_location   text not null default '',
  vehicle_status  text not null default 'pending_review' check (vehicle_status in ('verified', 'pending_review', 'maintenance')),
  is_online       boolean default false,
  rating          double precision default 0,
  trips_done      int default 0,
  trips_used_this_month int default 0,
  latitude        double precision,
  longitude       double precision,
  location        extensions.geography(Point, 4326),
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);
create index if not exists idx_driver_profiles_user on public.driver_profiles (user_id);
create index if not exists idx_driver_profiles_online on public.driver_profiles (is_online) where is_online = true;
create index if not exists idx_driver_profiles_location on public.driver_profiles using gist (location);
-- ── Driver subscriptions ─────────────────────────────────────────────────

create table if not exists public.driver_subscriptions (
  id            uuid primary key default gen_random_uuid(),
  driver_id     uuid not null references public.users(id) on delete cascade,
  plan          text not null,
  amount        int not null default 0,
  status        text not null default 'pending' check (status in ('pending', 'active', 'expired', 'cancelled')),
  started_at    timestamptz,
  expires_at    timestamptz,
  cancelled_at  timestamptz,
  created_at    timestamptz default now()
);
create index if not exists idx_subscriptions_driver on public.driver_subscriptions (driver_id);
create index if not exists idx_subscriptions_status on public.driver_subscriptions (status);
-- ── Partners ─────────────────────────────────────────────────────────────

create table if not exists public.partners (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  category      text not null default 'football' check (category in ('football', 'bank', 'organization')),
  country       text not null default 'RW',
  logo_url      text,
  description   text,
  fan_count     int default 0,
  club_count    int default 0,
  game_count    int default 0,
  created_at    timestamptz default now()
);
-- ── Fan memberships ──────────────────────────────────────────────────────

create table if not exists public.fan_memberships (
  id          uuid primary key default gen_random_uuid(),
  partner_id  uuid not null references public.partners(id) on delete cascade,
  user_id     uuid not null references public.users(id) on delete cascade,
  tier        text not null default 'bronze' check (tier in ('bronze', 'silver', 'gold')),
  joined_at   timestamptz default now(),
  unique(partner_id, user_id)
);
create index if not exists idx_fan_memberships_partner on public.fan_memberships (partner_id);
create index if not exists idx_fan_memberships_user on public.fan_memberships (user_id);
-- ── Credit scores ────────────────────────────────────────────────────────

create table if not exists public.credit_scores (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references public.users(id) on delete cascade,
  score                 int not null default 0,
  saving_consistency    int not null default 0,
  group_participation   int not null default 0,
  payment_history       int not null default 0,
  community_activity    int not null default 0,
  recorded_at           timestamptz default now()
);
create index if not exists idx_credit_scores_user on public.credit_scores (user_id);
-- ==========================================================================
-- PostGIS function: get_nearby_drivers
-- ==========================================================================

create or replace function public.get_nearby_drivers(
  p_lat double precision,
  p_lng double precision,
  p_vehicle_type text default null,
  radius_km double precision default 10
)
returns table (
  user_id       uuid,
  name          text,
  vehicle_type  text,
  plate_number  text,
  rating        double precision,
  distance_km   double precision,
  lat           double precision,
  lng           double precision,
  avatar_url    text
)
language sql
stable
as $$
  select
    dp.user_id,
    u.full_name       as name,
    dp.vehicle_type,
    dp.plate_number,
    dp.rating,
    round(
      (st_distancesphere(
        dp.location::geometry,
        st_setsrid(st_makepoint(p_lng, p_lat), 4326)
      ) / 1000.0)::numeric,
      2
    )::double precision as distance_km,
    dp.latitude        as lat,
    dp.longitude       as lng,
    u.avatar_url
  from public.driver_profiles dp
  join public.users u on u.id = dp.user_id
  where dp.is_online = true
    and dp.location is not null
    and st_dwithin(
      dp.location,
      st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
      radius_km * 1000
    )
    and (p_vehicle_type is null or dp.vehicle_type = p_vehicle_type)
  order by distance_km;
$$;
-- ==========================================================================
-- Trigger: auto-update location geography column from lat/lng
-- ==========================================================================

create or replace function public.sync_driver_location()
returns trigger
language plpgsql
as $$
begin
  if new.latitude is not null and new.longitude is not null then
    new.location := st_setsrid(st_makepoint(new.longitude, new.latitude), 4326)::geography;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_sync_driver_location on public.driver_profiles;
create trigger trg_sync_driver_location
  before insert or update of latitude, longitude
  on public.driver_profiles
  for each row
  execute function public.sync_driver_location();
-- ==========================================================================
-- RLS policies
-- ==========================================================================

-- ── Enable RLS on all tables ─────────────────────────────────────────────

alter table public.otp_codes          enable row level security;
alter table public.users              enable row level security;
alter table public.groups             enable row level security;
alter table public.group_members      enable row level security;
alter table public.group_contributions enable row level security;
alter table public.mobility_trips     enable row level security;
alter table public.driver_profiles    enable row level security;
alter table public.driver_subscriptions enable row level security;
alter table public.partners           enable row level security;
alter table public.fan_memberships    enable row level security;
alter table public.credit_scores      enable row level security;
-- ── OTP codes: service role only (Edge Functions use admin client) ────────
-- No public policies — only the service_role key can access otp_codes.

-- ── Users ────────────────────────────────────────────────────────────────

create policy "users_select_own"
  on public.users for select
  using (auth.uid() = id);
create policy "users_insert_own"
  on public.users for insert
  with check (auth.uid() = id);
create policy "users_update_own"
  on public.users for update
  using (auth.uid() = id)
  with check (auth.uid() = id);
-- ── Groups ───────────────────────────────────────────────────────────────

create policy "groups_select_public"
  on public.groups for select
  using (
    visibility = 'public'
    or creator_id = auth.uid()
    or exists (
      select 1 from public.group_members gm
      where gm.group_id = id and gm.user_id = auth.uid()
    )
  );
create policy "groups_insert"
  on public.groups for insert
  with check (auth.uid() = creator_id);
create policy "groups_update_creator"
  on public.groups for update
  using (auth.uid() = creator_id);
-- ── Group members ────────────────────────────────────────────────────────

create policy "group_members_select"
  on public.group_members for select
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
    )
  );
create policy "group_members_insert"
  on public.group_members for insert
  with check (user_id = auth.uid());
create policy "group_members_delete_own"
  on public.group_members for delete
  using (user_id = auth.uid());
-- ── Group contributions ──────────────────────────────────────────────────

create policy "contributions_select"
  on public.group_contributions for select
  using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = group_id and gm.user_id = auth.uid()
    )
  );
create policy "contributions_insert"
  on public.group_contributions for insert
  with check (auth.uid() = user_id);
-- ── Mobility trips ───────────────────────────────────────────────────────

create policy "trips_select_open"
  on public.mobility_trips for select
  using (status = 'open' or user_id = auth.uid());
create policy "trips_insert_own"
  on public.mobility_trips for insert
  with check (auth.uid() = user_id);
create policy "trips_update_own"
  on public.mobility_trips for update
  using (auth.uid() = user_id);
-- ── Driver profiles ──────────────────────────────────────────────────────

create policy "driver_profiles_select_online"
  on public.driver_profiles for select
  using (is_online = true or user_id = auth.uid());
create policy "driver_profiles_insert_own"
  on public.driver_profiles for insert
  with check (auth.uid() = user_id);
create policy "driver_profiles_update_own"
  on public.driver_profiles for update
  using (auth.uid() = user_id);
-- ── Driver subscriptions ─────────────────────────────────────────────────

create policy "subscriptions_select_own"
  on public.driver_subscriptions for select
  using (auth.uid() = driver_id);
create policy "subscriptions_insert_own"
  on public.driver_subscriptions for insert
  with check (auth.uid() = driver_id);
-- ── Partners ─────────────────────────────────────────────────────────────

create policy "partners_select_all"
  on public.partners for select
  using (true);
-- ── Fan memberships ──────────────────────────────────────────────────────

create policy "fan_memberships_select"
  on public.fan_memberships for select
  using (user_id = auth.uid());
create policy "fan_memberships_insert"
  on public.fan_memberships for insert
  with check (auth.uid() = user_id);
create policy "fan_memberships_delete_own"
  on public.fan_memberships for delete
  using (auth.uid() = user_id);
-- ── Credit scores ────────────────────────────────────────────────────────

create policy "credit_scores_select_own"
  on public.credit_scores for select
  using (auth.uid() = user_id);
