-- ══════════════════════════════════════════════════════════════
-- Admin Audit Log + Platform Analytics Summary
-- ══════════════════════════════════════════════════════════════

-- ── 1. Audit log table ────────────────────────────────────────

create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id),
  action text not null check (action in ('create', 'update', 'delete', 'login', 'admin_action')),
  target_table text,
  target_id text,
  old_data jsonb,
  new_data jsonb,
  notes text,
  created_at timestamptz not null default now()
);

-- Ensure notes column exists (may be missing from a prior partial push)
alter table public.admin_audit_log add column if not exists notes text;

comment on table public.admin_audit_log is
  'Tracks admin actions for accountability and debugging.';

-- Indexes
create index if not exists idx_audit_log_actor on public.admin_audit_log(actor_id);
create index if not exists idx_audit_log_action on public.admin_audit_log(action);
create index if not exists idx_audit_log_created on public.admin_audit_log(created_at desc);

-- Enable RLS
alter table public.admin_audit_log enable row level security;

-- Only admins can read
create policy "Admins can read audit log"
  on public.admin_audit_log for select
  using (
    exists (
      select 1 from public.users u
      where u.id = auth.uid() and u.is_admin = true
    )
  );

-- System can insert (via SECURITY DEFINER functions)
create policy "System can insert audit log"
  on public.admin_audit_log for insert
  with check (true);

-- No deletes or updates allowed
create policy "No deletes on audit log"
  on public.admin_audit_log for delete
  using (false);

create policy "No updates on audit log"
  on public.admin_audit_log for update
  using (false);


-- ── 2. RPC: get_admin_audit_log ───────────────────────────────

-- Drop first: return type may have changed from a prior deployment
drop function if exists public.get_admin_audit_log(int, int, text, uuid);

create or replace function public.get_admin_audit_log(
  p_limit int default 50,
  p_offset int default 0,
  p_action text default null,
  p_actor_id uuid default null
)
returns setof jsonb
language sql
security definer
stable
as $$
  select jsonb_build_object(
    'id', a.id,
    'actor_id', a.actor_id,
    'actor_name', u.full_name,
    'actor_phone', u.phone,
    'action', a.action,
    'target_table', a.target_table,
    'target_id', a.target_id,
    'old_data', a.old_data,
    'new_data', a.new_data,
    'notes', a.notes,
    'created_at', a.created_at
  )
  from public.admin_audit_log a
  left join public.users u on u.id = a.actor_id
  where
    (p_action is null or a.action = p_action)
    and (p_actor_id is null or a.actor_id = p_actor_id)
    and exists (
      select 1 from public.users caller
      where caller.id = auth.uid() and caller.is_admin = true
    )
  order by a.created_at desc
  limit p_limit
  offset p_offset;
$$;


-- ── 3. RPC: get_platform_analytics_summary ────────────────────

create or replace function public.get_platform_analytics_summary()
returns jsonb
language plpgsql
security definer
stable
as $$
declare
  result jsonb;
begin
  -- Only admins can call this
  if not exists (
    select 1 from public.users where id = auth.uid() and is_admin = true
  ) then
    raise exception 'Unauthorized: admin access required';
  end if;

  select jsonb_build_object(
    -- Core counts
    'total_users', (select count(*) from public.users),
    'real_users', (select count(*) from public.users where is_mock = false),
    'mock_users', (select count(*) from public.users where is_mock = true),
    'total_admins', (select count(*) from public.users where is_admin = true),
    'total_drivers', (select count(*) from public.users where is_driver = true),
    'total_partners', (select count(*) from public.partners),
    'total_groups', (select count(*) from public.groups),
    'total_trips', (
      select count(*) from public.trips
      where exists (select 1 from information_schema.tables where table_name = 'trips' and table_schema = 'public')
    ),

    -- Growth (last 7 & 30 days)
    'signups_7d', (select count(*) from public.users where created_at >= now() - interval '7 days'),
    'signups_30d', (select count(*) from public.users where created_at >= now() - interval '30 days'),
    'trips_7d', (
      select count(*) from public.trips
      where created_at >= now() - interval '7 days'
      and exists (select 1 from information_schema.tables where table_name = 'trips' and table_schema = 'public')
    ),
    'active_partners', (select count(*) from public.partners where is_active = true),

    -- Role distribution
    'role_distribution', (
      select coalesce(jsonb_object_agg(role, cnt), '{}'::jsonb)
      from (
        select role, count(*) as cnt
        from public.admin_role_assignments
        where is_active = true
        group by role
      ) sub
    ),

    -- Audit actions last 7 days
    'audit_actions_7d', (
      select count(*) from public.admin_audit_log
      where created_at >= now() - interval '7 days'
    ),

    -- Event distribution last 30 days
    'event_distribution', (
      select coalesce(jsonb_object_agg(action, cnt), '{}'::jsonb)
      from (
        select action, count(*) as cnt
        from public.admin_audit_log
        where created_at >= now() - interval '30 days'
        group by action
      ) sub
    )
  ) into result;

  return result;
end;
$$;


-- ── 4. Helper: record_admin_action ────────────────────────────

create or replace function public.record_admin_action(
  p_action text,
  p_target_table text default null,
  p_target_id text default null,
  p_old_data jsonb default null,
  p_new_data jsonb default null,
  p_notes text default null
)
returns void
language sql
security definer
as $$
  insert into public.admin_audit_log (actor_id, action, target_table, target_id, old_data, new_data, notes)
  values (auth.uid(), p_action, p_target_table, p_target_id, p_old_data, p_new_data, p_notes);
$$;
