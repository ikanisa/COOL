-- Fix admin panel schema gaps discovered during UAT
-- 1. get_platform_analytics_summary referenced non-existent cool_events table
-- 2. check_admin_phone_access didn't find admins via auth.users metadata phone

-- ─── Fix 1: get_platform_analytics_summary ──────────────────────────────────
-- Replace cool_events reference with operational_health_events count
CREATE OR REPLACE FUNCTION public.get_platform_analytics_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $$
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
    'health_events_30d', (
      select count(*)
      from public.operational_health_events
      where created_at >= now() - interval '30 days'
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

-- ─── Fix 2: check_admin_phone_access ────────────────────────────────────────
-- Also check auth.users metadata phone for GoTrue-created users whose
-- public.users row may have a different UUID
CREATE OR REPLACE FUNCTION public.check_admin_phone_access(p_phone text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  -- Check via public.users join
  SELECT EXISTS (
    SELECT 1
    FROM public.users u
    JOIN public.admin_role_assignments ara ON ara.user_id = u.id
    WHERE u.phone = p_phone
      AND ara.is_active = true
      AND ara.revoked_at IS NULL
  )
  OR EXISTS (
    -- Also check via auth.users metadata phone (for new GoTrue users)
    SELECT 1
    FROM auth.users au
    JOIN public.admin_role_assignments ara ON ara.user_id = au.id
    WHERE (au.raw_user_meta_data->>'phone' = p_phone OR au.phone = replace(p_phone, '+', ''))
      AND ara.is_active = true
      AND ara.revoked_at IS NULL
  );
$$;
