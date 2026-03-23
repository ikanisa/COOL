-- ==========================================================================
-- Cool App — Mobility country scoping
-- ==========================================================================
-- Enforces country-specific mobility data by:
--   1. adding `country` to driver_profiles and mobility_trips
--   2. deriving that country from the owning user server-side
--   3. filtering the geo RPCs by country
-- ==========================================================================

-- PostGIS is required for the spatial functions below.
create extension if not exists postgis with schema extensions;
alter table public.driver_profiles
  add column if not exists country text;
alter table public.mobility_trips
  add column if not exists country text;
-- Disable triggers while backfilling to avoid MoMo validation trigger on users
-- and any future triggers on these tables.
alter table public.driver_profiles disable trigger user;
alter table public.mobility_trips disable trigger user;
update public.driver_profiles dp
set country = public.normalize_country_code(u.country)
from public.users u
where u.id = dp.user_id
  and (
    dp.country is distinct from public.normalize_country_code(u.country)
    or dp.country is null
  );
update public.mobility_trips mt
set country = public.normalize_country_code(u.country)
from public.users u
where u.id = mt.user_id
  and (
    mt.country is distinct from public.normalize_country_code(u.country)
    or mt.country is null
  );
alter table public.driver_profiles enable trigger user;
alter table public.mobility_trips enable trigger user;
create index if not exists idx_driver_profiles_country
  on public.driver_profiles (country);
create index if not exists idx_mobility_trips_country
  on public.mobility_trips (country);
create or replace function public.sync_mobility_country_from_user()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_country text;
begin
  select public.normalize_country_code(u.country)
  into v_country
  from public.users u
  where u.id = new.user_id;

  if v_country is null then
    raise exception 'Could not resolve mobility country for user %.', new.user_id;
  end if;

  new.country := v_country;
  return new;
end;
$$;
drop trigger if exists trg_driver_profiles_sync_country on public.driver_profiles;
create trigger trg_driver_profiles_sync_country
  before insert or update of user_id on public.driver_profiles
  for each row
  execute function public.sync_mobility_country_from_user();
drop trigger if exists trg_mobility_trips_sync_country on public.mobility_trips;
create trigger trg_mobility_trips_sync_country
  before insert or update of user_id on public.mobility_trips
  for each row
  execute function public.sync_mobility_country_from_user();
alter table public.driver_profiles
  alter column country set not null;
alter table public.mobility_trips
  alter column country set not null;
drop function if exists public.get_nearby_drivers(
  double precision,
  double precision,
  text,
  double precision
);
create or replace function public.get_nearby_drivers(
  p_lat double precision,
  p_lng double precision,
  p_vehicle_type text default null,
  p_country text default null,
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
    and (
      p_country is null
      or dp.country = public.normalize_country_code(p_country)
    )
    and st_dwithin(
      dp.location,
      st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
      radius_km * 1000
    )
    and (p_vehicle_type is null or dp.vehicle_type = p_vehicle_type)
  order by distance_km;
$$;
revoke all on function public.get_nearby_drivers(
  double precision,
  double precision,
  text,
  text,
  double precision
) from public;
grant execute on function public.get_nearby_drivers(
  double precision,
  double precision,
  text,
  text,
  double precision
) to anon, authenticated;
drop function if exists public.get_scheduled_trips(
  double precision,
  double precision,
  text,
  text,
  double precision
);
create or replace function public.get_scheduled_trips(
  p_lat double precision,
  p_lng double precision,
  p_vehicle_type text default null,
  p_trip_type text default null,
  p_country text default null,
  radius_km double precision default 10
)
returns table (
  id uuid,
  user_id uuid,
  role text,
  vehicle_type text,
  trip_type text,
  from_location text,
  from_lat double precision,
  from_lng double precision,
  to_location text,
  to_lat double precision,
  to_lng double precision,
  travel_time timestamptz,
  repeat_days text[],
  status text,
  contact_phone text,
  contact_name text,
  whatsapp_number text,
  created_at timestamptz,
  distance_km double precision
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  select
    mt.id,
    mt.user_id,
    mt.role,
    mt.vehicle_type,
    mt.trip_type,
    mt.from_location,
    mt.from_lat,
    mt.from_lng,
    mt.to_location,
    mt.to_lat,
    mt.to_lng,
    mt.travel_time,
    mt.repeat_days,
    mt.status,
    mt.contact_phone,
    mt.contact_name,
    mt.whatsapp_number,
    mt.created_at,
    round(
      (st_distancesphere(
        mt.origin_geo::geometry,
        st_setsrid(st_makepoint(p_lng, p_lat), 4326)
      ) / 1000.0)::numeric,
      2
    )::double precision as distance_km
  from public.mobility_trips mt
  where mt.status in ('open', 'active')
    and mt.origin_geo is not null
    and (
      p_country is null
      or mt.country = public.normalize_country_code(p_country)
    )
    and st_dwithin(
      mt.origin_geo,
      st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography,
      radius_km * 1000
    )
    and (
      p_vehicle_type is null
      or mt.vehicle_type = p_vehicle_type
    )
    and (
      p_trip_type is null
      or mt.trip_type = p_trip_type
    )
  order by mt.travel_time asc, mt.created_at desc;
$$;
revoke all on function public.get_scheduled_trips(
  double precision,
  double precision,
  text,
  text,
  text,
  double precision
) from public;
grant execute on function public.get_scheduled_trips(
  double precision,
  double precision,
  text,
  text,
  text,
  double precision
) to anon, authenticated;
