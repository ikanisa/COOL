alter table public.mobility_trips
  add column if not exists client_request_id text;
create unique index if not exists idx_mobility_trips_user_client_request_id
  on public.mobility_trips (user_id, client_request_id)
  where client_request_id is not null;
