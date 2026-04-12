-- ==========================================================================
-- Phase 3: Admin RPCs — BioPay, Reconciliation, User Detail
-- ==========================================================================
-- Closes admin visibility gaps with database-backed RPCs.
-- All functions are SECURITY DEFINER with admin-only access checks.
-- ==========================================================================

-- ── 3A: BioPay Admin Summary ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_biopay_admin_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  v_caller_id := auth.uid();
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = v_caller_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Admin access required.';
  END IF;

  SELECT jsonb_build_object(
    'total_profiles',
      (SELECT count(*) FROM public.biopay_profiles WHERE deleted_at IS NULL),
    'active_profiles',
      (SELECT count(*) FROM public.biopay_profiles WHERE active = true AND deleted_at IS NULL),
    'revoked_profiles',
      (SELECT count(*) FROM public.biopay_profiles WHERE active = false AND deleted_at IS NULL),
    'total_matches_24h',
      (SELECT count(*) FROM public.biopay_match_events
       WHERE created_at > now() - interval '24 hours'),
    'successful_matches_24h',
      (SELECT count(*) FROM public.biopay_match_events
       WHERE matched = true AND created_at > now() - interval '24 hours'),
    'failed_matches_24h',
      (SELECT count(*) FROM public.biopay_match_events
       WHERE matched = false AND created_at > now() - interval '24 hours'),
    'avg_match_score_7d',
      (SELECT round(coalesce(avg(score), 0)::numeric, 4)
       FROM public.biopay_match_events
       WHERE matched = true AND created_at > now() - interval '7 days'),
    'enrollments_7d',
      (SELECT count(*) FROM public.biopay_enrollment_audits
       WHERE event_type = 'enrolled' AND created_at > now() - interval '7 days'),
    'revocations_7d',
      (SELECT count(*) FROM public.biopay_enrollment_audits
       WHERE event_type = 'revoked' AND created_at > now() - interval '7 days'),
    'active_embeddings',
      (SELECT count(*) FROM public.biopay_embeddings WHERE active = true),
    'payment_intents_24h',
      (SELECT count(*) FROM public.biopay_payment_intents
       WHERE created_at > now() - interval '24 hours'),
    'recent_enrollments', (
      SELECT coalesce(jsonb_agg(row_data ORDER BY enrolled_at DESC), '[]'::jsonb)
      FROM (
        SELECT jsonb_build_object(
          'profile_id', bp.id,
          'public_id', bp.public_id,
          'display_name', bp.display_name,
          'country_code', bp.country_code,
          'route_type', bp.route_type,
          'enrolled_at', bp.created_at
        ) AS row_data,
        bp.created_at AS enrolled_at
        FROM public.biopay_profiles bp
        WHERE bp.deleted_at IS NULL
        ORDER BY bp.created_at DESC
        LIMIT 10
      ) sub
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_biopay_admin_summary() TO authenticated;

-- ── 3B: Financial Reconciliation Summary ────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_financial_reconciliation_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_result jsonb;
BEGIN
  v_caller_id := auth.uid();
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = v_caller_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Admin access required.';
  END IF;

  SELECT coalesce(jsonb_agg(row_data ORDER BY gap_pct DESC NULLS LAST), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT jsonb_build_object(
      'group_id', g.id,
      'group_name', g.name,
      'type', g.type,
      'member_count', g.member_count,
      'monthly_contribution', coalesce(g.monthly_contribution, 0),
      'expected_monthly', g.member_count * coalesce(g.monthly_contribution, 0),
      'total_collected', coalesce(g.amount, 0),
      'target_amount', coalesce(g.target_amount, 0),
      'confirmed_30d', (
        SELECT coalesce(sum(gc.amount), 0)
        FROM public.group_contributions gc
        WHERE gc.group_id = g.id
          AND gc.status = 'confirmed'
          AND gc.created_at > now() - interval '30 days'
      ),
      'pending_count', (
        SELECT count(*)
        FROM public.group_contributions gc
        WHERE gc.group_id = g.id AND gc.status = 'pending'
      ),
      'gap_amount', CASE
        WHEN coalesce(g.monthly_contribution, 0) > 0
        THEN (g.member_count * g.monthly_contribution) - coalesce(g.amount, 0)
        ELSE 0
      END,
      'gap_pct', CASE
        WHEN g.member_count * coalesce(g.monthly_contribution, 0) > 0
        THEN round(
          (1.0 - least(coalesce(g.amount, 0)::numeric / (g.member_count * g.monthly_contribution), 1.0)) * 100, 1
        )
        ELSE 0
      END,
      'bank_partner', g.bank_partner,
      'created_at', g.created_at
    ) AS row_data,
    CASE
      WHEN g.member_count * coalesce(g.monthly_contribution, 0) > 0
      THEN round(
        (1.0 - least(coalesce(g.amount, 0)::numeric / (g.member_count * g.monthly_contribution), 1.0)) * 100, 1
      )
      ELSE NULL
    END AS gap_pct
    FROM public.groups g
    WHERE coalesce(g.monthly_contribution, 0) > 0
  ) sub;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_financial_reconciliation_summary() TO authenticated;

-- ── 3C: User Detail for Admin ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_user_detail_for_admin(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_user public.users;
  v_result jsonb;
BEGIN
  v_caller_id := auth.uid();
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = v_caller_id AND is_admin = true
  ) THEN
    RAISE EXCEPTION 'Admin access required.';
  END IF;

  SELECT * INTO v_user FROM public.users WHERE id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'User not found: %', p_user_id;
  END IF;

  SELECT jsonb_build_object(
    'profile', jsonb_build_object(
      'id', v_user.id,
      'phone', v_user.phone,
      'full_name', v_user.full_name,
      'country', v_user.country,
      'language_code', v_user.language_code,
      'momo_number', v_user.momo_number,
      'is_admin', v_user.is_admin,
      'created_at', v_user.created_at,
      'updated_at', v_user.updated_at
    ),
    'groups', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'group_id', g.id,
        'group_name', g.name,
        'is_admin', gm.is_admin,
        'contribution_amount', gm.contribution_amount,
        'joined_at', gm.joined_at,
        'type', g.type,
        'member_count', g.member_count
      )), '[]'::jsonb)
      FROM public.group_members gm
      JOIN public.groups g ON g.id = gm.group_id
      WHERE gm.user_id = p_user_id
    ),
    'contributions_30d', jsonb_build_object(
      'count', (
        SELECT count(*) FROM public.group_contributions
        WHERE user_id = p_user_id AND created_at > now() - interval '30 days'
      ),
      'total_amount', (
        SELECT coalesce(sum(amount), 0) FROM public.group_contributions
        WHERE user_id = p_user_id AND status = 'confirmed'
          AND created_at > now() - interval '30 days'
      )
    ),
    'biopay', (
      SELECT coalesce(jsonb_build_object(
        'has_enrollment', true,
        'profile_id', bp.id,
        'public_id', bp.public_id,
        'active', bp.active,
        'route_type', bp.route_type,
        'created_at', bp.created_at,
        'revoked_at', bp.revoked_at
      ), jsonb_build_object('has_enrollment', false))
      FROM public.biopay_profiles bp
      WHERE bp.user_id = p_user_id AND bp.deleted_at IS NULL
      LIMIT 1
    ),
    'cool_status', (
      SELECT coalesce(jsonb_build_object(
        'total_points', cs.total_points,
        'tier', cs.tier,
        'current_streak', cs.current_streak,
        'longest_streak', cs.longest_streak,
        'season_points', cs.season_points
      ), jsonb_build_object('total_points', 0, 'tier', 'blue'))
      FROM public.cool_status cs
      WHERE cs.user_id = p_user_id
      LIMIT 1
    ),
    'roles', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'role', ra.role,
        'partner_scope_id', ra.partner_scope_id,
        'is_active', ra.is_active,
        'granted_at', ra.granted_at
      )), '[]'::jsonb)
      FROM public.admin_role_assignments ra
      WHERE ra.user_id = p_user_id AND ra.is_active = true
    ),
    'sms_sync', jsonb_build_object(
      'total_ingested', (
        SELECT count(*) FROM public.momo_sms_raw WHERE user_id = p_user_id
      ),
      'parsed_count', (
        SELECT count(*) FROM public.momo_sms_parsed WHERE user_id = p_user_id
      ),
      'last_sync', (
        SELECT max(created_at) FROM public.momo_sms_raw WHERE user_id = p_user_id
      )
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_detail_for_admin(uuid) TO authenticated;
