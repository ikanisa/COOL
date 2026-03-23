create table if not exists public.biopay_match_rate_events (
  id uuid primary key default gen_random_uuid(),
  requester_user_id uuid not null references public.users(id) on delete cascade,
  scope text not null check (scope in ('user', 'ip')),
  actor_key text not null,
  outcome text not null check (
    outcome in (
      'match',
      'miss',
      'blocked_user_rate_limit',
      'blocked_ip_rate_limit',
      'lockout_started',
      'blocked_lockout'
    )
  ),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

comment on table public.biopay_match_rate_events is
  'Service-role-only BioPay match risk and rate-limit telemetry keyed by hashed user and IP actors.';

create index if not exists biopay_match_rate_events_scope_actor_created_idx
  on public.biopay_match_rate_events (scope, actor_key, created_at desc);

create index if not exists biopay_match_rate_events_requester_created_idx
  on public.biopay_match_rate_events (requester_user_id, created_at desc);

grant select, insert on public.biopay_match_rate_events to service_role;
revoke all on public.biopay_match_rate_events from anon, authenticated;

alter table public.biopay_match_rate_events enable row level security;

insert into public.app_config (key, value, description) values
  (
    'biopay_match_rate_window_seconds',
    '60',
    'Sliding window in seconds for BioPay per-user and per-IP match rate limiting'
  ),
  (
    'biopay_match_user_max_attempts',
    '8',
    'Maximum BioPay match attempts a user can make inside the rate-limit window'
  ),
  (
    'biopay_match_ip_max_attempts',
    '20',
    'Maximum BioPay match attempts allowed from one IP inside the rate-limit window'
  ),
  (
    'biopay_match_miss_window_seconds',
    '600',
    'Sliding window in seconds used to evaluate repeated failed BioPay matches'
  ),
  (
    'biopay_match_miss_lockout_threshold',
    '5',
    'Failed BioPay matches per user inside the miss window before temporary lockout begins'
  ),
  (
    'biopay_match_lockout_seconds',
    '900',
    'Seconds a user remains locked out after repeated failed BioPay matches'
  )
on conflict (key) do update
set
  value = excluded.value,
  description = excluded.description;
