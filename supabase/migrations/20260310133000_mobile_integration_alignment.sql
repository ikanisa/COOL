-- ==========================================================================
-- Cool App - Mobile integration alignment
-- ==========================================================================
-- Aligns the SQL schema with the Flutter repositories and edge functions.
-- Adds missing profile, payment, mobility, and subscription fields.
-- ==========================================================================

-- -- Users -----------------------------------------------------------------

alter table public.users
  add column if not exists momo_provider text not null default '',
  add column if not exists is_driver boolean not null default false,
  add column if not exists vehicle_type text;

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

create index if not exists idx_pending_transactions_user
  on public.pending_transactions (user_id);
create index if not exists idx_pending_transactions_group
  on public.pending_transactions (group_id);
create index if not exists idx_pending_transactions_status
  on public.pending_transactions (status);

-- -- Mobility trips --------------------------------------------------------

alter table public.mobility_trips
  add column if not exists driver_id uuid references public.users(id) on delete cascade,
  add column if not exists vehicle_type text,
  add column if not exists vehicle_emoji text,
  add column if not exists seats int,
  add column if not exists distance_km double precision,
  add column if not exists trip_type text not null default 'passenger'
    check (trip_type in ('passenger', 'driver_return'));

create index if not exists idx_trips_driver on public.mobility_trips (driver_id);
create index if not exists idx_trips_driver_return
  on public.mobility_trips (is_driver_return_trip)
  where is_driver_return_trip = true;

update public.mobility_trips
set
  driver_id = coalesce(driver_id, user_id),
  vehicle_type = coalesce(nullif(vehicle_type, ''), vehicle_preference),
  vehicle_preference = coalesce(nullif(vehicle_preference, ''), vehicle_type, 'any'),
  seats = coalesce(seats, seats_needed, 1),
  seats_needed = coalesce(seats_needed, seats, 1),
  trip_type = coalesce(
    nullif(trip_type, ''),
    case
      when coalesce(is_driver_return_trip, false) then 'driver_return'
      else 'passenger'
    end
  ),
  expires_at = coalesce(expires_at, departure_at + interval '1 hour')
where true;

-- -- Driver profiles -------------------------------------------------------

alter table public.driver_profiles
  add column if not exists vehicle_emoji text;

-- -- Driver subscriptions --------------------------------------------------

alter table public.driver_subscriptions
  add column if not exists plan_id text,
  add column if not exists plan_name text,
  add column if not exists amount_rwf int,
  add column if not exists momo_reference text,
  add column if not exists updated_at timestamptz not null default now();

update public.driver_subscriptions
set
  plan_id = coalesce(plan_id, plan),
  plan_name = coalesce(
    plan_name,
    case
      when coalesce(plan, '') = '' then null
      else initcap(replace(plan, '_', ' '))
    end
  ),
  amount_rwf = coalesce(amount_rwf, amount)
where true;

create unique index if not exists idx_driver_subscriptions_momo_reference
  on public.driver_subscriptions (momo_reference)
  where momo_reference is not null;

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

drop trigger if exists trg_driver_subscriptions_set_updated_at on public.driver_subscriptions;
create trigger trg_driver_subscriptions_set_updated_at
  before update on public.driver_subscriptions
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

create or replace function public.sync_mobility_trip_compat()
returns trigger
language plpgsql
as $$
begin
  new.user_id := coalesce(new.user_id, new.driver_id);
  new.driver_id := coalesce(new.driver_id, new.user_id);
  new.vehicle_type := coalesce(nullif(new.vehicle_type, ''), nullif(new.vehicle_preference, ''), 'any');
  new.vehicle_preference := coalesce(nullif(new.vehicle_preference, ''), nullif(new.vehicle_type, ''), 'any');
  new.seats := coalesce(new.seats, new.seats_needed, 1);
  new.seats_needed := coalesce(new.seats_needed, new.seats, 1);
  new.trip_type := coalesce(
    nullif(new.trip_type, ''),
    case
      when coalesce(new.is_driver_return_trip, false) then 'driver_return'
      else 'passenger'
    end
  );
  new.vehicle_emoji := coalesce(
    nullif(new.vehicle_emoji, ''),
    case lower(coalesce(new.vehicle_type, new.vehicle_preference, ''))
      when 'moto' then '🛺'
      when 'moto taxi' then '🛺'
      when 'cab' then '🚗'
      when 'truck' then '🚛'
      when 'liffan' then '🚐'
      else '🚗'
    end
  );
  new.expires_at := coalesce(new.expires_at, new.departure_at + interval '1 hour');
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_sync_mobility_trip_compat on public.mobility_trips;
create trigger trg_sync_mobility_trip_compat
  before insert or update on public.mobility_trips
  for each row
  execute function public.sync_mobility_trip_compat();

-- -- Replace nearby drivers RPC with a response shape that matches the app --

drop function if exists public.get_nearby_drivers(double precision, double precision, text, double precision);

create or replace function public.get_nearby_drivers(
  p_lat double precision,
  p_lng double precision,
  p_vehicle_type text default null,
  radius_km double precision default 10
)
returns table (
  driver_id uuid,
  user_id uuid,
  vehicle_type text,
  vehicle_emoji text,
  distance_km double precision,
  is_online boolean,
  rating double precision,
  trip_count int,
  scheduled_route text,
  has_return_trip boolean,
  latitude double precision,
  longitude double precision
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    dp.user_id as driver_id,
    dp.user_id,
    dp.vehicle_type,
    coalesce(
      dp.vehicle_emoji,
      case lower(dp.vehicle_type)
        when 'moto' then '🛺'
        when 'moto taxi' then '🛺'
        when 'cab' then '🚗'
        when 'truck' then '🚛'
        when 'liffan' then '🚐'
        else '🚗'
      end
    ) as vehicle_emoji,
    round(
      (st_distancesphere(
        dp.location::geometry,
        st_setsrid(st_makepoint(p_lng, p_lat), 4326)
      ) / 1000.0)::numeric,
      2
    )::double precision as distance_km,
    dp.is_online,
    dp.rating,
    dp.trips_done as trip_count,
    (
      select mt.from_location || ' -> ' || mt.to_location
      from public.mobility_trips mt
      where mt.driver_id = dp.user_id
        and mt.status = 'open'
        and mt.departure_at >= now()
      order by mt.departure_at asc
      limit 1
    ) as scheduled_route,
    exists (
      select 1
      from public.mobility_trips mt
      where mt.driver_id = dp.user_id
        and mt.status = 'open'
        and mt.is_driver_return_trip = true
        and coalesce(mt.expires_at, mt.departure_at + interval '1 hour') >= now()
    ) as has_return_trip,
    dp.latitude,
    dp.longitude
  from public.driver_profiles dp
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

revoke all on function public.get_nearby_drivers(double precision, double precision, text, double precision) from public;
grant execute on function public.get_nearby_drivers(double precision, double precision, text, double precision) to anon, authenticated;

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
