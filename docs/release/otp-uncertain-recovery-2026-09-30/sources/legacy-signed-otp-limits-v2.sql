-- Staged: quota policy must be explicitly configured by a privileged operator.
begin;
create schema if not exists collect_security;
revoke all on schema collect_security from public,anon,authenticated;
create table collect_security.otp_policy (
 singleton boolean primary key default true check(singleton),
 global_hourly_limit integer not null check(global_hourly_limit between 1 and 100000),
 global_daily_limit integer not null check(global_daily_limit between 1 and 1000000),
 enabled boolean not null default false
);
create table collect_security.signed_otp_requests (
 hook_id text primary key check(length(hook_id) between 1 and 256),
 payload_hash text not null check(payload_hash ~ '^[a-f0-9]{64}$'),
 phone_hash text not null check(phone_hash ~ '^[a-f0-9]{64}$'),
 requested_at timestamptz not null default now(),delivered_at timestamptz,
 status text not null default 'reserved' check(status in ('reserved','sent'))
);
create index signed_otp_requests_window on collect_security.signed_otp_requests(requested_at);
alter table collect_security.otp_policy enable row level security;
alter table collect_security.signed_otp_requests enable row level security;
revoke all on collect_security.otp_policy,collect_security.signed_otp_requests from public,anon,authenticated,service_role;
create function public.reserve_signed_otp_v2(p_hook_id text,p_payload_hash text,p_phone_hash text)
returns text language plpgsql security definer set search_path='' as $$
declare policy collect_security.otp_policy;prior collect_security.signed_otp_requests;t timestamptz;
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 if p_hook_id is null or length(p_hook_id) not between 1 and 256 or p_payload_hash is null or p_payload_hash !~ '^[a-f0-9]{64}$'
   or p_phone_hash is null or p_phone_hash !~ '^[a-f0-9]{64}$' then raise exception 'Invalid reservation'; end if;
 -- The row update serializes decisions and makes stale repeatable-read snapshots
 -- fail rather than admitting extra deliveries under a phantom count.
 update collect_security.otp_policy set enabled=enabled where singleton returning * into policy;
 if policy.singleton is null or not policy.enabled then raise exception 'OTP policy not configured'; end if;
 t:=clock_timestamp();
 select * into prior from collect_security.signed_otp_requests where hook_id=p_hook_id;
 if prior.hook_id is not null then
   if prior.payload_hash<>p_payload_hash or prior.phone_hash<>p_phone_hash then raise exception 'Hook identity conflict'; end if;
   return case when prior.status='sent' then 'already_sent' else 'unresolved' end;
 end if;
 if (select count(*) from collect_security.signed_otp_requests where requested_at>=t-interval '1 hour')>=policy.global_hourly_limit
  or (select count(*) from collect_security.signed_otp_requests where requested_at>=t-interval '24 hours')>=policy.global_daily_limit then return 'throttled'; end if;
 if not public.reserve_otp_request(p_phone_hash,null) then return 'throttled'; end if;
 insert into collect_security.signed_otp_requests(hook_id,payload_hash,phone_hash,requested_at) values(p_hook_id,p_payload_hash,p_phone_hash,t);
 return 'reserved';
end; $$;
create function public.complete_signed_otp_v2(p_hook_id text,p_payload_hash text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
 update collect_security.signed_otp_requests set status='sent',delivered_at=coalesce(delivered_at,now()) where hook_id=p_hook_id and payload_hash=p_payload_hash;
 return found;
end; $$;
revoke all on function public.reserve_signed_otp_v2(text,text,text),public.complete_signed_otp_v2(text,text) from public,anon,authenticated;
grant execute on function public.reserve_signed_otp_v2(text,text,text),public.complete_signed_otp_v2(text,text) to service_role;
commit;
