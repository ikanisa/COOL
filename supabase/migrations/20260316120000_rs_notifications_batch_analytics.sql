-- ══════════════════════════════════════════════════════════════
-- RS Notifications + Batch Ticket Ops + Fan Analytics
-- ══════════════════════════════════════════════════════════════

-- 1) Match notifications table
CREATE TABLE IF NOT EXISTS public.rs_notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id uuid NOT NULL REFERENCES public.rs_matches(id) ON DELETE CASCADE,
  title text NOT NULL,
  body text NOT NULL,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','sent','failed')),
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

ALTER TABLE public.rs_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY rs_notifications_admin ON public.rs_notifications FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.admin_role_assignments ara
    WHERE ara.user_id = auth.uid()
      AND ara.is_active = true
      AND (ara.role = 'admin' OR ara.role = 'rayon_sport')
  )
);

-- RPC: send match notification (draft → sent)
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
  INSERT INTO public.rs_notifications (match_id, title, body, status, sent_at, created_by)
  VALUES (p_match_id, p_title, p_body, 'sent', now(), auth.uid())
  RETURNING id INTO v_notif_id;

  RETURN v_notif_id;
END;
$$;

-- RPC: get notification history
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

-- 2) Batch ticket operations
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
  UPDATE public.rs_tickets
  SET status = 'voided', updated_at = now()
  WHERE id = ANY(p_ticket_ids)
    AND status != 'voided';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

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
  UPDATE public.rs_tickets
  SET status = 'refunded', updated_at = now()
  WHERE id = ANY(p_ticket_ids)
    AND status NOT IN ('voided','refunded');

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- 3) Fan analytics RPC
CREATE OR REPLACE FUNCTION public.get_rs_fan_analytics()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'total_members', (SELECT count(*) FROM public.rs_fan_club_members),
    'active_memberships', (SELECT count(*) FROM public.rs_fan_memberships WHERE status = 'active'),
    'total_tickets_sold', (SELECT count(*) FROM public.rs_tickets WHERE status = 'confirmed'),
    'ticket_revenue', (SELECT COALESCE(sum(price), 0) FROM public.rs_tickets WHERE status = 'confirmed'),
    'total_matches', (SELECT count(*) FROM public.rs_matches),
    'upcoming_matches', (SELECT count(*) FROM public.rs_matches WHERE match_date > now()),
    'membership_packages', (SELECT count(*) FROM public.rs_membership_packages WHERE is_active = true),
    'notifications_sent', (SELECT count(*) FROM public.rs_notifications WHERE status = 'sent')
  ) INTO result;

  RETURN result;
END;
$$;
