-- ============================================================================
-- Admin Readiness Security Hardening (Phase 4)
-- Addresses: Missing RBAC guards inside SECURITY DEFINER RPCs for Rayon Sports.
-- ============================================================================

-- ── 1. Protect: send_rs_match_notification ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.send_rs_match_notification(
  p_match_id uuid,
  p_title text,
  p_body text
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_notif_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_role_assignments ara
    WHERE ara.user_id = auth.uid()
      AND ara.is_active = true
      AND (ara.role = 'admin' OR ara.role = 'rayon_sport')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Requires admin or rayon_sport role';
  END IF;

  INSERT INTO public.rs_notifications (match_id, title, body, status, sent_at, created_by)
  VALUES (p_match_id, p_title, p_body, 'sent', now(), auth.uid())
  RETURNING id INTO v_notif_id;

  RETURN v_notif_id;
END;
$$;


-- ── 2. Protect: get_rs_notifications ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_rs_notifications(
  p_match_id uuid DEFAULT NULL,
  p_limit int DEFAULT 50,
  p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_role_assignments ara
    WHERE ara.user_id = auth.uid()
      AND ara.is_active = true
      AND (ara.role = 'admin' OR ara.role = 'rayon_sport')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Requires admin or rayon_sport role';
  END IF;

  SELECT jsonb_agg(row_to_json(t))
  INTO result
  FROM (
    SELECT
      n.id, n.match_id, n.title, n.body, n.status,
      n.sent_at, n.created_at,
      m.home_team || ' vs ' || m.away_team AS match_label,
      m.match_date
    FROM public.rs_notifications n
    JOIN public.rs_matches m ON m.id = n.match_id
    WHERE (p_match_id IS NULL OR n.match_id = p_match_id)
    ORDER BY n.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) t;

  RETURN COALESCE(result, '[]'::jsonb);
END;
$$;


-- ── 3. Protect: bulk_void_rs_tickets ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.bulk_void_rs_tickets(
  p_ticket_ids uuid[]
)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_role_assignments ara
    WHERE ara.user_id = auth.uid()
      AND ara.is_active = true
      AND (ara.role = 'admin' OR ara.role = 'rayon_sport')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Requires admin or rayon_sport role';
  END IF;

  UPDATE public.rs_tickets
  SET status = 'voided', updated_at = now()
  WHERE id = ANY(p_ticket_ids)
    AND status != 'voided';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;


-- ── 4. Protect: bulk_refund_rs_tickets ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.bulk_refund_rs_tickets(
  p_ticket_ids uuid[]
)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count int;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_role_assignments ara
    WHERE ara.user_id = auth.uid()
      AND ara.is_active = true
      AND (ara.role = 'admin' OR ara.role = 'rayon_sport')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Requires admin or rayon_sport role';
  END IF;

  UPDATE public.rs_tickets
  SET status = 'refunded', updated_at = now()
  WHERE id = ANY(p_ticket_ids)
    AND status NOT IN ('voided','refunded');

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;


-- ── 5. Protect: get_rs_fan_analytics ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_rs_fan_analytics()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_role_assignments ara
    WHERE ara.user_id = auth.uid()
      AND ara.is_active = true
      AND (ara.role = 'admin' OR ara.role = 'rayon_sport')
  ) THEN
    RAISE EXCEPTION 'Unauthorized: Requires admin or rayon_sport role';
  END IF;

  SELECT jsonb_build_object(
    'total_fans', (SELECT count(*) FROM public.rs_fan_memberships),
    'active_memberships', (SELECT count(*) FROM public.rs_fan_memberships),
    'total_tickets_sold', (
      SELECT count(*) FROM public.rs_tickets
      WHERE status IN ('valid', 'used')
    ),
    'ticket_revenue', (
      SELECT COALESCE(sum(amount_paid), 0)
      FROM public.rs_tickets
      WHERE status IN ('valid', 'used')
    ),
    'total_initiatives', (SELECT count(*) FROM public.rs_initiatives),
    'total_contributions', (
      SELECT COALESCE(sum(amount), 0)
      FROM public.rs_initiative_contributions
      WHERE status = 'confirmed'
    ),
    'total_shop_revenue', (
      SELECT COALESCE(sum(total), 0)
      FROM public.rs_shop_orders
      WHERE status IN ('paid', 'confirmed', 'packed', 'fulfilled', 'delivered')
    ),
    'tier_breakdown', (
      SELECT COALESCE(
        jsonb_object_agg(tier, cnt),
        '{}'::jsonb
      )
      FROM (
        SELECT tier, count(*) AS cnt
        FROM public.rs_fan_memberships
        GROUP BY tier
      ) t
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;
