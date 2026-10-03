begin;

-- Preserve five requested OTPs per phone in a rolling ten-minute window.
-- A separate lock row serializes decisions even when no attempt exists yet.
-- Updating it also rejects stale REPEATABLE READ / SERIALIZABLE snapshots
-- with a serialization failure instead of admitting an extra request.
create schema if not exists collect_auth_security;
revoke all on schema collect_auth_security from public, anon, authenticated, service_role;

create table collect_auth_security.otp_phone_locks (
  phone_hash text primary key check (phone_hash ~ '^[0-9a-f]{64}$'),
  revision bigint not null default 0
);
alter table collect_auth_security.otp_phone_locks enable row level security;
revoke all on collect_auth_security.otp_phone_locks from public, anon, authenticated, service_role;

create index otp_rate_limits_phone_window_idx
  on public.otp_rate_limits (phone_hash, requested_at);

create function public.reserve_otp_request(
  p_phone_hash text,
  p_ip_hash text default null
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  request_time timestamptz;
  recent_count integer;
begin
  if p_phone_hash is null or p_phone_hash !~ '^[0-9a-f]{64}$'
    or (p_ip_hash is not null and p_ip_hash !~ '^[0-9a-f]{64}$') then
    raise exception 'Valid OTP phone and IP hashes required' using errcode = '22023';
  end if;

  insert into collect_auth_security.otp_phone_locks as phone_lock (phone_hash, revision)
  values (p_phone_hash, 1)
  on conflict (phone_hash) do update set revision = phone_lock.revision + 1;

  request_time := clock_timestamp();
  select count(*) into recent_count from public.otp_rate_limits
  where phone_hash = p_phone_hash
    and requested_at >= request_time - interval '10 minutes';
  if recent_count >= 5 then return false; end if;

  insert into public.otp_rate_limits (phone_hash, ip_hash, requested_at)
  values (p_phone_hash, p_ip_hash, request_time);
  return true;
end;
$$;

revoke all on function public.reserve_otp_request(text, text) from public, anon, authenticated, service_role;
grant execute on function public.reserve_otp_request(text, text) to service_role;

comment on function public.reserve_otp_request(text, text) is
  'Service-only atomic rolling OTP request reservation; false means quota exhausted. Errors must prevent provider delivery.';

commit;
