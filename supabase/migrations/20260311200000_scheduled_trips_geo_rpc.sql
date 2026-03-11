-- ==========================================================================
-- Server-side geo query for scheduled trips
-- Adds PostGIS geography column to mobility_trips and creates
-- get_scheduled_trips RPC that replaces client-side filtering.
-- ==========================================================================

-- ── 1. Add geography column + spatial index ─────────────────────────────

alter table public.mobility_trips
  add column if not exists origin_geo extensions.geography(Point, 4326);

-- Backfill from existing lat/lng
update public.mobility_trips
set origin_geo = extensions.st_setsrid(
  extensions.st_makepoint(
    coalesce(longitude, from_lng),
    coalesce(latitude, from_lat)
  ),
  4326
)::extensions.geography
where origin_geo is null
  and coalesce(latitude, from_lat) is not null
  and coalesce(longitude, from_lng) is not null;

create index if not exists idx_trips_origin_geo
  on public.mobility_trips using gist (origin_geo);

-- ── 2. Update compat trigger to sync origin_geo ─────────────────────────

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
  new.travel_time := coalesce(new.travel_time, new.departure_at);
  new.departure_at := coalesce(new.departure_at, new.travel_time);
  new.from_lat := coalesce(new.from_lat, new.latitude);
  new.from_lng := coalesce(new.from_lng, new.longitude);
  new.latitude := coalesce(new.latitude, new.from_lat);
  new.longitude := coalesce(new.longitude, new.from_lng);
  new.repeat_days := coalesce(new.repeat_days, new.recurring_days, '{}');
  new.recurring_days := coalesce(new.recurring_days, new.repeat_days, '{}');
  new.role := coalesce(
    nullif(new.role, ''),
    case
      when coalesce(new.is_driver_return_trip, false) then 'DRIVER'
      else 'PASSENGER'
    end
  );
  new.whatsapp_number := coalesce(nullif(new.whatsapp_number, ''), nullif(new.contact_phone, ''));
  new.status := lower(coalesce(nullif(new.status, ''), 'open'));
  new.expires_at := coalesce(new.expires_at, new.departure_at + interval '1 hour');
  new.updated_at := now();

  -- Sync PostGIS geography from lat/lng
  if coalesce(new.latitude, new.from_lat) is not null
     and coalesce(new.longitude, new.from_lng) is not null then
    new.origin_geo := st_setsrid(
      st_makepoint(
        coalesce(new.longitude, new.from_lng),
        coalesce(new.latitude, new.from_lat)
      ),
      4326
    )::extensions.geography;
  end if;

  return new;
end;
$$;

-- ── 3. Create get_scheduled_trips RPC ───────────────────────────────────

create or replace function public.get_scheduled_trips(
  p_lat double precision,
  p_lng double precision,
  p_vehicle_type text default null,
  p_trip_type text default null,
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
  double precision, double precision, text, text, double precision
) from public;

grant execute on function public.get_scheduled_trips(
  double precision, double precision, text, text, double precision
) to authenticated;
