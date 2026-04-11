-- ============================================================================
-- Align platform-admin helpers and role RPCs with admin_role_assignments
-- ============================================================================
-- The admin PWA now depends on role-assigned platform admins being treated as
-- first-class platform administrators. Older helpers and RPCs only trusted
-- users.is_admin, which prevented newer admin-role assignments from using the
-- full admin surface.

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(
      (select u.is_admin from public.users u where u.id = auth.uid()),
      false
    )
    or exists (
      select 1
      from public.admin_role_assignments ra
      where ra.user_id = auth.uid()
        and ra.is_active = true
        and ra.role = 'admin'
    );
$$;

create or replace function public.is_admin_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin();
$$;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_admin_user() to authenticated;

create or replace function public.assign_admin_role(
  p_target_user_id uuid,
  p_role text,
  p_partner_scope_id uuid default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_id uuid;
  v_assignment_id uuid;
begin
  v_caller_id := auth.uid();

  if not public.is_admin_user() then
    raise exception 'Only platform admins can assign admin roles.';
  end if;

  if p_role not in ('admin', 'bank', 'rayon_sport') then
    raise exception 'Invalid role: %. Must be admin, bank, or rayon_sport.', p_role;
  end if;

  if p_role in ('bank', 'rayon_sport') and p_partner_scope_id is null then
    raise exception 'Partner scope is required for % role.', p_role;
  end if;

  insert into public.admin_role_assignments (
    user_id, role, partner_scope_id, granted_by, granted_at, is_active, notes
  ) values (
    p_target_user_id, p_role, p_partner_scope_id, v_caller_id, now(), true, p_notes
  )
  on conflict (user_id, role, partner_scope_id)
  do update set
    is_active = true,
    granted_by = v_caller_id,
    granted_at = now(),
    revoked_at = null,
    notes = coalesce(p_notes, admin_role_assignments.notes)
  returning id into v_assignment_id;

  return jsonb_build_object(
    'status', 'assigned',
    'assignment_id', v_assignment_id,
    'role', p_role,
    'user_id', p_target_user_id,
    'partner_scope_id', p_partner_scope_id
  );
end;
$$;

create or replace function public.revoke_admin_role(
  p_assignment_id uuid,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment record;
begin
  if not public.is_admin_user() then
    raise exception 'Only platform admins can revoke admin roles.';
  end if;

  select *
  into v_assignment
  from public.admin_role_assignments
  where id = p_assignment_id
    and is_active = true;

  if not found then
    raise exception 'Role assignment not found or already revoked.';
  end if;

  update public.admin_role_assignments
  set is_active = false,
      revoked_at = now(),
      notes = coalesce(p_notes, notes)
  where id = p_assignment_id;

  return jsonb_build_object(
    'status', 'revoked',
    'assignment_id', p_assignment_id,
    'role', v_assignment.role,
    'user_id', v_assignment.user_id
  );
end;
$$;

create or replace function public.list_admin_role_assignments(
  p_role text default null,
  p_active_only boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_admin_user() then
    raise exception 'Only platform admins can list admin role assignments.';
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', ra.id,
      'user_id', ra.user_id,
      'user_name', u.full_name,
      'user_phone', u.phone,
      'role', ra.role,
      'partner_scope_id', ra.partner_scope_id,
      'partner_name', p.name,
      'granted_by', ra.granted_by,
      'granted_at', ra.granted_at,
      'revoked_at', ra.revoked_at,
      'is_active', ra.is_active,
      'notes', ra.notes
    ) order by ra.granted_at desc
  ), '[]'::jsonb)
  into v_result
  from public.admin_role_assignments ra
  left join public.users u on u.id = ra.user_id
  left join public.partners p on p.id = ra.partner_scope_id
  where (p_role is null or ra.role = p_role)
    and (not p_active_only or ra.is_active = true);

  return v_result;
end;
$$;

create or replace function public.get_platform_analytics_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if not public.is_admin() then
    raise exception 'Forbidden: platform admin access required.';
  end if;

  select jsonb_build_object(
    'total_users',     (select count(*) from public.users),
    'total_groups',    (select count(*) from public.groups),
    'total_partners',  (select count(*) from public.partners),
    'total_admins',    (
      select count(distinct admin_user_id)
      from (
        select u.id as admin_user_id
        from public.users u
        where u.is_admin = true
        union
        select ra.user_id as admin_user_id
        from public.admin_role_assignments ra
        where ra.is_active = true
          and ra.role = 'admin'
      ) admin_users
    ),
    'mock_users',      (select count(*) from public.users where is_mock = true),
    'real_users',      (select count(*) from public.users where is_mock is not true),
    'signups_7d',      (
      select count(*)
      from public.users
      where created_at >= now() - interval '7 days'
    ),
    'signups_30d',     (
      select count(*)
      from public.users
      where created_at >= now() - interval '30 days'
    ),
    'active_groups',   (
      select count(*)
      from public.groups
      where (
        select count(*)
        from public.group_members gm
        where gm.group_id = groups.id
      ) > 0
    ),
    'active_partners', (
      select count(*)
      from public.partners
      where is_active = true
    ),
    'role_distribution', (
      select coalesce(jsonb_object_agg(role, cnt), '{}'::jsonb)
      from (
        select role, count(*) as cnt
        from public.admin_role_assignments
        where is_active = true
        group by role
      ) sub
    ),
    'event_distribution', (
      select coalesce(jsonb_object_agg(event_type, cnt), '{}'::jsonb)
      from (
        select event_type, count(*) as cnt
        from public.cool_events
        where created_at >= now() - interval '30 days'
        group by event_type
      ) sub
    ),
    'audit_actions_7d', (
      select count(*)
      from public.admin_audit_log
      where created_at >= now() - interval '7 days'
    ),
    'generated_at', now()
  ) into result;

  return result;
end;
$$;

grant execute on function public.assign_admin_role(uuid, text, uuid, text) to authenticated;
grant execute on function public.revoke_admin_role(uuid, text) to authenticated;
grant execute on function public.list_admin_role_assignments(text, boolean) to authenticated;
grant execute on function public.get_platform_analytics_summary() to authenticated;
