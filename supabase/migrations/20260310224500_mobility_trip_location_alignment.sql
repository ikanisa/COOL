alter table public.mobility_trips
  add column if not exists from_lat double precision,
  add column if not exists from_lng double precision,
  add column if not exists to_lat double precision,
  add column if not exists to_lng double precision,
  add column if not exists travel_time timestamptz,
  add column if not exists repeat_days text[],
  add column if not exists role text,
  add column if not exists whatsapp_number text;

update public.mobility_trips
set
  from_lat = coalesce(from_lat, latitude),
  from_lng = coalesce(from_lng, longitude),
  travel_time = coalesce(travel_time, departure_at),
  repeat_days = coalesce(repeat_days, recurring_days, '{}'),
  role = coalesce(
    nullif(role, ''),
    case
      when coalesce(is_driver_return_trip, false) then 'DRIVER'
      else 'PASSENGER'
    end
  ),
  whatsapp_number = coalesce(nullif(whatsapp_number, ''), nullif(contact_phone, ''))
where true;

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
  return new;
end;
$$;
