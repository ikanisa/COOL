-- ============================================================================
-- Admin PWA sessions and browser telemetry
-- ============================================================================

create table if not exists public.admin_web_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  access_token text not null,
  refresh_token text not null,
  issued_at timestamptz not null default now(),
  last_verified_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  revoked_at timestamptz,
  revoke_reason text,
  reauth_required boolean not null default false,
  user_agent text,
  ip_hash text,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists idx_admin_web_sessions_user_active
  on public.admin_web_sessions (user_id, issued_at desc)
  where revoked_at is null;

create index if not exists idx_admin_web_sessions_expiry
  on public.admin_web_sessions (expires_at desc);

alter table public.admin_web_sessions enable row level security;

drop policy if exists admin_web_sessions_deny_anon on public.admin_web_sessions;
create policy admin_web_sessions_deny_anon
  on public.admin_web_sessions for all to anon
  using (false) with check (false);

drop policy if exists admin_web_sessions_deny_authenticated on public.admin_web_sessions;
create policy admin_web_sessions_deny_authenticated
  on public.admin_web_sessions for all to authenticated
  using (false) with check (false);

drop policy if exists admin_web_sessions_service_role on public.admin_web_sessions;
create policy admin_web_sessions_service_role
  on public.admin_web_sessions for all to service_role
  using (true) with check (true);

comment on table public.admin_web_sessions is
  'Opaque server-side sessions for the COOL Admin PWA. Browser cookie stores only the session id.';

create table if not exists public.admin_browser_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid references public.admin_web_sessions(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  event_name text not null,
  route text,
  path text,
  online boolean,
  app_version text,
  client_ts timestamptz,
  ip_hash text,
  user_agent text,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_admin_browser_events_created
  on public.admin_browser_events (created_at desc);

create index if not exists idx_admin_browser_events_event
  on public.admin_browser_events (event_name, created_at desc);

create index if not exists idx_admin_browser_events_user
  on public.admin_browser_events (user_id, created_at desc);

alter table public.admin_browser_events enable row level security;

drop policy if exists admin_browser_events_deny_anon on public.admin_browser_events;
create policy admin_browser_events_deny_anon
  on public.admin_browser_events for all to anon
  using (false) with check (false);

drop policy if exists admin_browser_events_deny_authenticated on public.admin_browser_events;
create policy admin_browser_events_deny_authenticated
  on public.admin_browser_events for all to authenticated
  using (false) with check (false);

drop policy if exists admin_browser_events_service_role on public.admin_browser_events;
create policy admin_browser_events_service_role
  on public.admin_browser_events for all to service_role
  using (true) with check (true);

comment on table public.admin_browser_events is
  'Structured browser telemetry for the COOL Admin PWA.';
