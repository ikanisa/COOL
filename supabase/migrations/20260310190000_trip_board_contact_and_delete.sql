alter table public.mobility_trips
  add column if not exists contact_phone text,
  add column if not exists contact_name text;

update public.mobility_trips mt
set
  contact_phone = coalesce(mt.contact_phone, u.phone),
  contact_name = coalesce(mt.contact_name, nullif(u.full_name, ''))
from public.users u
where u.id = mt.user_id;

create or replace function public.sync_mobility_trip_contact()
returns trigger
language plpgsql
as $$
declare
  profile_phone text;
  profile_name text;
begin
  if new.user_id is null then
    return new;
  end if;

  select u.phone, nullif(u.full_name, '')
  into profile_phone, profile_name
  from public.users u
  where u.id = new.user_id;

  new.contact_phone := coalesce(nullif(new.contact_phone, ''), profile_phone);
  new.contact_name := coalesce(nullif(new.contact_name, ''), profile_name);
  return new;
end;
$$;

drop trigger if exists trg_sync_mobility_trip_contact on public.mobility_trips;
create trigger trg_sync_mobility_trip_contact
  before insert or update of user_id, contact_phone, contact_name
  on public.mobility_trips
  for each row
  execute function public.sync_mobility_trip_contact();

drop policy if exists "trips_delete_own" on public.mobility_trips;
create policy "trips_delete_own"
  on public.mobility_trips for delete
  using (auth.uid() = user_id);
