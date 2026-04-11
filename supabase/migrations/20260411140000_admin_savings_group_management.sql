-- ==========================================================================
-- Admin Savings Group Management — RPCs, RLS, and centralized MoMo
-- ==========================================================================
-- Adds admin-scoped CRUD for savings groups, member management,
-- manual allocation, and centralized MoMo code via app_config.
-- ==========================================================================

-- ── 0. Seed centralized savings MoMo code in app_config ─────────────────

INSERT INTO public.app_config (key, value, description)
VALUES (
  'savings_momo_code',
  '*182*8*1*000000#',
  'Centralized MoMo USSD/collection code used by all savings groups. Set this to the platform''s single receiving MoMo code.'
)
ON CONFLICT (key) DO NOTHING;


-- ── 1. Admin RLS: full read/write on groups for platform admins ─────────

-- Admin can update any group (savings management)
DROP POLICY IF EXISTS "groups_admin_update" ON public.groups;
CREATE POLICY "groups_admin_update"
  ON public.groups FOR UPDATE
  USING (public.is_admin_user());

-- Admin can insert groups (create savings groups from admin panel)
DROP POLICY IF EXISTS "groups_admin_insert" ON public.groups;
CREATE POLICY "groups_admin_insert"
  ON public.groups FOR INSERT
  WITH CHECK (public.is_admin_user());

-- Admin can read all group_members
DROP POLICY IF EXISTS "group_members_admin_select" ON public.group_members;
CREATE POLICY "group_members_admin_select"
  ON public.group_members FOR SELECT
  USING (public.is_admin_user());

-- Admin can insert group_members
DROP POLICY IF EXISTS "group_members_admin_insert" ON public.group_members;
CREATE POLICY "group_members_admin_insert"
  ON public.group_members FOR INSERT
  WITH CHECK (public.is_admin_user());

-- Admin can delete group_members
DROP POLICY IF EXISTS "group_members_admin_delete" ON public.group_members;
CREATE POLICY "group_members_admin_delete"
  ON public.group_members FOR DELETE
  USING (public.is_admin_user());

-- Admin can manage group_contributions
DROP POLICY IF EXISTS "group_contributions_admin_all" ON public.group_contributions;
CREATE POLICY "group_contributions_admin_all"
  ON public.group_contributions FOR ALL
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());


-- ── 2. admin_create_savings_group ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_create_savings_group(
  p_name TEXT,
  p_description TEXT DEFAULT NULL,
  p_target_amount INT DEFAULT 0,
  p_monthly_contribution INT DEFAULT NULL,
  p_frequency TEXT DEFAULT 'monthly'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_group_id UUID;
  v_invite_code TEXT;
  v_momo_code TEXT;
BEGIN
  IF NOT public.is_admin_user() THEN
    RAISE EXCEPTION 'Forbidden: platform admin access required.';
  END IF;

  IF btrim(COALESCE(p_name, '')) = '' THEN
    RAISE EXCEPTION 'Group name is required.';
  END IF;

  -- Get centralized MoMo code from app_config
  SELECT value INTO v_momo_code
  FROM public.app_config
  WHERE key = 'savings_momo_code'
  LIMIT 1;

  -- Generate invite code
  v_invite_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));

  INSERT INTO public.groups (
    creator_id,
    name,
    description,
    type,
    visibility,
    amount,
    target_amount,
    monthly_contribution,
    frequency,
    momo_number,
    receiving_momo_code,
    receiving_momo_route_type,
    invite_code,
    country,
    is_active
  ) VALUES (
    auth.uid(),
    btrim(p_name),
    NULLIF(btrim(COALESCE(p_description, '')), ''),
    'saving',
    'private',
    0,
    COALESCE(p_target_amount, 0),
    p_monthly_contribution,
    COALESCE(NULLIF(btrim(p_frequency), ''), 'monthly'),
    v_momo_code,
    v_momo_code,
    'code',
    v_invite_code,
    'RW',
    true
  )
  RETURNING id INTO v_group_id;

  RETURN jsonb_build_object(
    'status', 'success',
    'group_id', v_group_id,
    'invite_code', v_invite_code
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_savings_group(TEXT, TEXT, INT, INT, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_create_savings_group(TEXT, TEXT, INT, INT, TEXT)
  TO authenticated;

COMMENT ON FUNCTION public.admin_create_savings_group IS
  'Creates a savings group with centralized MoMo code from app_config. Platform admin only.';


-- ── 3. admin_update_savings_group ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_update_savings_group(
  p_group_id UUID,
  p_name TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL,
  p_target_amount INT DEFAULT NULL,
  p_monthly_contribution INT DEFAULT NULL,
  p_frequency TEXT DEFAULT NULL,
  p_is_closed BOOL DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_admin_user() THEN
    RAISE EXCEPTION 'Forbidden: platform admin access required.';
  END IF;

  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'Group id is required.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id AND type = 'saving') THEN
    RAISE EXCEPTION 'Savings group not found.';
  END IF;

  UPDATE public.groups
  SET
    name = COALESCE(NULLIF(btrim(p_name), ''), name),
    description = CASE WHEN p_description IS NOT NULL THEN NULLIF(btrim(p_description), '') ELSE description END,
    target_amount = COALESCE(p_target_amount, target_amount),
    monthly_contribution = CASE WHEN p_monthly_contribution IS NOT NULL THEN p_monthly_contribution ELSE monthly_contribution END,
    frequency = COALESCE(NULLIF(btrim(p_frequency), ''), frequency),
    is_closed = COALESCE(p_is_closed, is_closed),
    is_active = CASE WHEN p_is_closed = true THEN false ELSE is_active END,
    updated_at = now()
  WHERE id = p_group_id;

  RETURN jsonb_build_object('status', 'success', 'group_id', p_group_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_savings_group(UUID, TEXT, TEXT, INT, INT, TEXT, BOOL) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_update_savings_group(UUID, TEXT, TEXT, INT, INT, TEXT, BOOL)
  TO authenticated;


-- ── 4. admin_add_group_member ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_add_group_member(
  p_group_id UUID,
  p_user_id UUID,
  p_display_name TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_display TEXT;
BEGIN
  IF NOT public.is_admin_user() THEN
    RAISE EXCEPTION 'Forbidden: platform admin access required.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'Group not found.';
  END IF;

  -- Resolve display name
  v_display := COALESCE(
    NULLIF(btrim(p_display_name), ''),
    (SELECT COALESCE(full_name, phone, 'Member') FROM public.users WHERE id = p_user_id),
    'Member'
  );

  INSERT INTO public.group_members (group_id, user_id, display_name, is_admin, is_anonymous, contribution_amount)
  VALUES (p_group_id, p_user_id, v_display, false, false, 0)
  ON CONFLICT (group_id, user_id) DO NOTHING;

  RETURN jsonb_build_object('status', 'success', 'group_id', p_group_id, 'user_id', p_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_add_group_member(UUID, UUID, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_add_group_member(UUID, UUID, TEXT)
  TO authenticated;


-- ── 5. admin_remove_group_member ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_remove_group_member(
  p_group_id UUID,
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.is_admin_user() THEN
    RAISE EXCEPTION 'Forbidden: platform admin access required.';
  END IF;

  DELETE FROM public.group_members
  WHERE group_id = p_group_id AND user_id = p_user_id;

  RETURN jsonb_build_object('status', 'success', 'group_id', p_group_id, 'user_id', p_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_remove_group_member(UUID, UUID) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_remove_group_member(UUID, UUID)
  TO authenticated;


-- ── 6. admin_bulk_add_group_members ──────────────────────────────────────
-- Accepts JSON array: [{ "phone": "+250...", "display_name": "..." }, ...]
-- Looks up users by phone, adds to group.

CREATE OR REPLACE FUNCTION public.admin_bulk_add_group_members(
  p_group_id UUID,
  p_members JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_member JSONB;
  v_phone TEXT;
  v_display TEXT;
  v_user_id UUID;
  v_added INT := 0;
  v_skipped INT := 0;
  v_not_found INT := 0;
BEGIN
  IF NOT public.is_admin_user() THEN
    RAISE EXCEPTION 'Forbidden: platform admin access required.';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id) THEN
    RAISE EXCEPTION 'Group not found.';
  END IF;

  FOR v_member IN SELECT * FROM jsonb_array_elements(p_members) LOOP
    v_phone := btrim(v_member ->> 'phone');
    v_display := COALESCE(NULLIF(btrim(v_member ->> 'display_name'), ''), v_phone);

    IF v_phone IS NULL OR v_phone = '' THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- Normalize phone to E.164
    IF NOT starts_with(v_phone, '+') THEN
      v_phone := '+' || v_phone;
    END IF;

    -- Look up user by phone
    SELECT id INTO v_user_id
    FROM public.users
    WHERE phone = v_phone
    LIMIT 1;

    IF v_user_id IS NULL THEN
      v_not_found := v_not_found + 1;
      CONTINUE;
    END IF;

    -- Check if already a member
    IF EXISTS (
      SELECT 1 FROM public.group_members
      WHERE group_id = p_group_id AND user_id = v_user_id
    ) THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    INSERT INTO public.group_members (group_id, user_id, display_name, is_admin, is_anonymous, contribution_amount)
    VALUES (p_group_id, v_user_id, v_display, false, false, 0);

    v_added := v_added + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'status', 'success',
    'added', v_added,
    'skipped', v_skipped,
    'not_found', v_not_found
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bulk_add_group_members(UUID, JSONB) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_bulk_add_group_members(UUID, JSONB)
  TO authenticated;


-- ── 7. admin_get_savings_groups_detail ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_get_savings_groups_detail()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_result JSONB;
  v_momo_code TEXT;
BEGIN
  IF NOT public.is_admin_user() THEN
    RAISE EXCEPTION 'Forbidden: platform admin access required.';
  END IF;

  -- Get centralized MoMo code
  SELECT value INTO v_momo_code
  FROM public.app_config
  WHERE key = 'savings_momo_code'
  LIMIT 1;

  SELECT jsonb_build_object(
    'savings_momo_code', COALESCE(v_momo_code, ''),
    'total_savings_groups', (SELECT count(*) FROM public.groups WHERE type = 'saving'),
    'active_savings_groups', (SELECT count(*) FROM public.groups WHERE type = 'saving' AND is_active = true AND COALESCE(is_closed, false) = false),
    'total_community_groups', (SELECT count(*) FROM public.groups WHERE type = 'community'),
    'total_members_in_savings', (
      SELECT count(*) FROM public.group_members gm
      JOIN public.groups g ON g.id = gm.group_id
      WHERE g.type = 'saving'
    ),
    'total_collected', (
      SELECT COALESCE(sum(gc.amount), 0)
      FROM public.group_contributions gc
      JOIN public.groups g ON g.id = gc.group_id
      WHERE g.type = 'saving' AND gc.status = 'confirmed'
    ),
    'savings_groups', COALESCE((
      SELECT jsonb_agg(sg ORDER BY sg->>'created_at' DESC)
      FROM (
        SELECT jsonb_build_object(
          'id', g.id,
          'name', g.name,
          'description', g.description,
          'target_amount', g.target_amount,
          'monthly_contribution', g.monthly_contribution,
          'frequency', g.frequency,
          'momo_number', g.momo_number,
          'invite_code', g.invite_code,
          'creator_id', g.creator_id,
          'is_closed', COALESCE(g.is_closed, false),
          'is_active', COALESCE(g.is_active, true),
          'created_at', g.created_at,
          'member_count', COALESCE(mc.cnt, 0),
          'total_collected', COALESCE(tc.total, 0),
          'members', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
              'user_id', gm.user_id,
              'display_name', gm.display_name,
              'phone', u.phone,
              'joined_at', gm.joined_at
            ) ORDER BY gm.joined_at ASC)
            FROM public.group_members gm
            LEFT JOIN public.users u ON u.id = gm.user_id
            WHERE gm.group_id = g.id
          ), '[]'::jsonb)
        ) AS sg
        FROM public.groups g
        LEFT JOIN LATERAL (
          SELECT count(*) AS cnt FROM public.group_members m WHERE m.group_id = g.id
        ) mc ON true
        LEFT JOIN LATERAL (
          SELECT COALESCE(sum(c.amount), 0) AS total
          FROM public.group_contributions c
          WHERE c.group_id = g.id AND c.status = 'confirmed'
        ) tc ON true
        WHERE g.type = 'saving'
      ) sub
    ), '[]'::jsonb),
    'community_groups', COALESCE((
      SELECT jsonb_agg(cg ORDER BY cg->>'created_at' DESC)
      FROM (
        SELECT jsonb_build_object(
          'id', g.id,
          'name', g.name,
          'description', g.description,
          'visibility', g.visibility,
          'creator_id', g.creator_id,
          'is_closed', COALESCE(g.is_closed, false),
          'created_at', g.created_at,
          'member_count', COALESCE(mc.cnt, 0)
        ) AS cg
        FROM public.groups g
        LEFT JOIN LATERAL (
          SELECT count(*) AS cnt FROM public.group_members m WHERE m.group_id = g.id
        ) mc ON true
        WHERE g.type = 'community'
      ) sub
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_savings_groups_detail() FROM public;
GRANT EXECUTE ON FUNCTION public.admin_get_savings_groups_detail()
  TO authenticated;

COMMENT ON FUNCTION public.admin_get_savings_groups_detail IS
  'Returns detailed savings + community group data for admin management. Platform admin only.';


-- ── 8. admin_allocate_savings_contribution ────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_allocate_savings_contribution(
  p_group_id UUID,
  p_member_user_id UUID,
  p_amount INT,
  p_reference TEXT DEFAULT NULL,
  p_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_contribution_id UUID;
  v_reference TEXT;
BEGIN
  IF NOT public.is_admin_user() THEN
    RAISE EXCEPTION 'Forbidden: platform admin access required.';
  END IF;

  IF p_group_id IS NULL OR p_member_user_id IS NULL THEN
    RAISE EXCEPTION 'Group id and member user id are required.';
  END IF;

  IF COALESCE(p_amount, 0) <= 0 THEN
    RAISE EXCEPTION 'Amount must be greater than zero.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.groups WHERE id = p_group_id AND type = 'saving'
  ) THEN
    RAISE EXCEPTION 'Savings group not found.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = p_group_id AND user_id = p_member_user_id
  ) THEN
    RAISE EXCEPTION 'User is not a member of this savings group.';
  END IF;

  v_reference := COALESCE(
    NULLIF(btrim(p_reference), ''),
    format('ADMIN-%s', gen_random_uuid())
  );

  INSERT INTO public.group_contributions (
    group_id,
    user_id,
    amount,
    status,
    momo_reference,
    notes,
    created_at
  ) VALUES (
    p_group_id,
    p_member_user_id,
    p_amount,
    'confirmed',
    v_reference,
    COALESCE(NULLIF(btrim(p_note), ''), 'Admin manual allocation'),
    now()
  )
  RETURNING id INTO v_contribution_id;

  RETURN jsonb_build_object(
    'status', 'success',
    'contribution_id', v_contribution_id,
    'group_id', p_group_id,
    'user_id', p_member_user_id,
    'amount', p_amount,
    'reference', v_reference
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_allocate_savings_contribution(UUID, UUID, INT, TEXT, TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_allocate_savings_contribution(UUID, UUID, INT, TEXT, TEXT)
  TO authenticated;

COMMENT ON FUNCTION public.admin_allocate_savings_contribution IS
  'Manually allocates a savings contribution for a member. Platform admin only.';


-- ==========================================================================
-- ROLLBACK (if needed)
-- ==========================================================================
-- DROP FUNCTION IF EXISTS public.admin_create_savings_group(TEXT, TEXT, INT, INT, TEXT);
-- DROP FUNCTION IF EXISTS public.admin_update_savings_group(UUID, TEXT, TEXT, INT, INT, TEXT, BOOL);
-- DROP FUNCTION IF EXISTS public.admin_add_group_member(UUID, UUID, TEXT);
-- DROP FUNCTION IF EXISTS public.admin_remove_group_member(UUID, UUID);
-- DROP FUNCTION IF EXISTS public.admin_bulk_add_group_members(UUID, JSONB);
-- DROP FUNCTION IF EXISTS public.admin_get_savings_groups_detail();
-- DROP FUNCTION IF EXISTS public.admin_allocate_savings_contribution(UUID, UUID, INT, TEXT, TEXT);
-- DELETE FROM public.app_config WHERE key = 'savings_momo_code';
