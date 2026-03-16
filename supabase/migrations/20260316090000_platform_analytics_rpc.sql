-- ═══════════════════════════════════════════════════════════════════════
-- Platform Analytics Summary RPC
-- ═══════════════════════════════════════════════════════════════════════
-- Returns a single JSON object with all key platform metrics.
-- Platform admin only (checked via is_admin()).

CREATE OR REPLACE FUNCTION public.get_platform_analytics_summary()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: platform admin access required.';
  END IF;

  SELECT jsonb_build_object(
    -- ── Core counts ──────────────────────────────────────────────────
    'total_users',     (SELECT count(*) FROM public.users),
    'total_groups',    (SELECT count(*) FROM public.groups),
    'total_trips',     (SELECT count(*) FROM public.mobility_trips),
    'total_partners',  (SELECT count(*) FROM public.partners),
    'total_drivers',   (SELECT count(*) FROM public.users WHERE is_driver = true),
    'total_admins',    (SELECT count(*) FROM public.users WHERE is_admin = true),
    'mock_users',      (SELECT count(*) FROM public.users WHERE is_mock = true),
    'real_users',      (SELECT count(*) FROM public.users WHERE is_mock IS NOT TRUE),

    -- ── Signups ──────────────────────────────────────────────────────
    'signups_7d',      (SELECT count(*) FROM public.users
                        WHERE created_at >= now() - interval '7 days'),
    'signups_30d',     (SELECT count(*) FROM public.users
                        WHERE created_at >= now() - interval '30 days'),

    -- ── Active entities ──────────────────────────────────────────────
    'active_groups',   (SELECT count(*) FROM public.groups
                        WHERE (SELECT count(*) FROM public.group_members gm
                               WHERE gm.group_id = groups.id) > 0),
    'trips_7d',        (SELECT count(*) FROM public.mobility_trips
                        WHERE created_at >= now() - interval '7 days'),
    'active_partners', (SELECT count(*) FROM public.partners
                        WHERE is_active = true),

    -- ── Role distribution ────────────────────────────────────────────
    'role_distribution', (
      SELECT coalesce(jsonb_object_agg(role, cnt), '{}'::jsonb)
      FROM (
        SELECT role, count(*) AS cnt
        FROM public.admin_role_assignments
        WHERE is_active = true
        GROUP BY role
      ) sub
    ),

    -- ── Event distribution (last 30d) ────────────────────────────────
    'event_distribution', (
      SELECT coalesce(jsonb_object_agg(event_type, cnt), '{}'::jsonb)
      FROM (
        SELECT event_type, count(*) AS cnt
        FROM public.cool_events
        WHERE created_at >= now() - interval '30 days'
        GROUP BY event_type
      ) sub
    ),

    -- ── Audit log stats ──────────────────────────────────────────────
    'audit_actions_7d', (
      SELECT count(*) FROM public.admin_audit_log
      WHERE created_at >= now() - interval '7 days'
    ),

    -- ── Timestamp ────────────────────────────────────────────────────
    'generated_at', now()
  ) INTO result;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_platform_analytics_summary()
  TO authenticated;
