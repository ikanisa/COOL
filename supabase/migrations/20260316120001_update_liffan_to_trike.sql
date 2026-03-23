UPDATE public.vehicle_types SET value = 'Trike', label = '🚐 Trike' WHERE value = 'Liffan';
UPDATE public.users SET vehicle_type = 'trike' WHERE vehicle_type = 'liffan';
UPDATE public.driver_profiles SET vehicle_type = 'trike' WHERE vehicle_type = 'liffan';
UPDATE public.mobility_trips SET vehicle_type = 'trike' WHERE vehicle_type = 'liffan';
UPDATE public.mobility_trips SET vehicle_preference = 'trike' WHERE vehicle_preference = 'liffan';
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
      when 'trike' then '🚐'
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
        when 'trike' then '🚐'
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
