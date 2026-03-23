-- ==========================================================================
-- Cool App — OTP abuse hardening and deterministic auth lookup
-- ==========================================================================

create table if not exists public.otp_rate_events (
  id uuid primary key default gen_random_uuid(),
  action text not null
    check (action in ('send_ip', 'verify_ip')),
  actor_key text not null,
  outcome text not null,
  phone text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_otp_rate_events_action_actor_time
  on public.otp_rate_events (action, actor_key, created_at desc);
create index if not exists idx_otp_rate_events_phone_time
  on public.otp_rate_events (phone, created_at desc);
alter table public.otp_rate_events enable row level security;
comment on table public.otp_rate_events is
  'Service-role-only OTP abuse telemetry for IP-scoped send and verify limits.';
create or replace function public.find_auth_user_by_phone_or_email(
  p_phone text,
  p_email text
)
returns table (
  user_id uuid
)
language sql
stable
security definer
set search_path = public, auth
as $$
  select au.id as user_id
  from auth.users au
  where au.email = p_email
     or au.phone = p_phone
     or au.phone_change = p_phone
     or coalesce(au.raw_user_meta_data ->> 'phone', '') = p_phone
  order by case
    when au.email = p_email then 0
    when au.phone = p_phone then 1
    when au.phone_change = p_phone then 2
    when coalesce(au.raw_user_meta_data ->> 'phone', '') = p_phone then 3
    else 9
  end,
  au.created_at asc
  limit 1;
$$;
revoke all on function public.find_auth_user_by_phone_or_email(text, text)
  from public;
grant execute on function public.find_auth_user_by_phone_or_email(text, text)
  to service_role;
