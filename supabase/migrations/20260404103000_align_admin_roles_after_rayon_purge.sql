-- Align admin RBAC with the post-Rayon product surface.
-- The live admin app now supports two role types only:
--   admin -> platform-wide access
--   bank  -> scoped bank workspace access

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'admin_role_assignments'
  ) THEN
    DELETE FROM public.admin_role_assignments
    WHERE role = 'rayon_sport';

    ALTER TABLE public.admin_role_assignments
      DROP CONSTRAINT IF EXISTS admin_role_assignments_role_check;

    ALTER TABLE public.admin_role_assignments
      ADD CONSTRAINT admin_role_assignments_role_check
      CHECK (role IN ('admin', 'bank'));
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_admin_access_for_user(
  p_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_is_platform_admin boolean := false;
  v_role_rows jsonb;
  v_bank_ids jsonb;
BEGIN
  v_user_id := COALESCE(p_user_id, auth.uid());

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'has_platform_access', false,
      'has_bank_access', false,
      'has_partner_access', false,
      'bank_partner_ids', '[]'::jsonb,
      'partner_admin_ids', '[]'::jsonb,
      'role_assignments', '[]'::jsonb
    );
  END IF;

  SELECT COALESCE(u.is_admin, false)
  INTO v_is_platform_admin
  FROM public.users AS u
  WHERE u.id = v_user_id;

  IF NOT v_is_platform_admin THEN
    SELECT EXISTS(
      SELECT 1
      FROM public.admin_role_assignments AS ra
      WHERE ra.user_id = v_user_id
        AND ra.is_active = true
        AND ra.role = 'admin'
    )
    INTO v_is_platform_admin;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', ra.id,
        'user_id', ra.user_id,
        'role', ra.role,
        'partner_scope_id', ra.partner_scope_id,
        'partner_name', p.name,
        'granted_by', ra.granted_by,
        'granted_at', ra.granted_at,
        'revoked_at', ra.revoked_at,
        'is_active', ra.is_active,
        'notes', ra.notes
      )
      ORDER BY ra.granted_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_role_rows
  FROM public.admin_role_assignments AS ra
  LEFT JOIN public.partners AS p ON p.id = ra.partner_scope_id
  WHERE ra.user_id = v_user_id
    AND ra.is_active = true;

  SELECT COALESCE(jsonb_agg(ra.partner_scope_id), '[]'::jsonb)
  INTO v_bank_ids
  FROM public.admin_role_assignments AS ra
  WHERE ra.user_id = v_user_id
    AND ra.is_active = true
    AND ra.role = 'bank'
    AND ra.partner_scope_id IS NOT NULL;

  RETURN jsonb_build_object(
    'has_platform_access', v_is_platform_admin,
    'has_bank_access', v_is_platform_admin OR jsonb_array_length(v_bank_ids) > 0,
    'has_partner_access', false,
    'bank_partner_ids', v_bank_ids,
    'partner_admin_ids', '[]'::jsonb,
    'role_assignments', v_role_rows
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_admin_role(
  p_target_user_id uuid,
  p_role text,
  p_partner_scope_id uuid DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_assignment_id uuid;
BEGIN
  v_caller_id := auth.uid();

  IF NOT EXISTS (
    SELECT 1
    FROM public.users AS u
    WHERE u.id = v_caller_id
      AND u.is_admin = true
  ) THEN
    RAISE EXCEPTION 'Only platform admins can assign admin roles.';
  END IF;

  IF p_role NOT IN ('admin', 'bank') THEN
    RAISE EXCEPTION 'Invalid role: %. Must be admin or bank.', p_role;
  END IF;

  IF p_role = 'bank' AND p_partner_scope_id IS NULL THEN
    RAISE EXCEPTION 'Partner scope is required for bank role.';
  END IF;

  INSERT INTO public.admin_role_assignments (
    user_id,
    role,
    partner_scope_id,
    granted_by,
    granted_at,
    is_active,
    notes
  )
  VALUES (
    p_target_user_id,
    p_role,
    p_partner_scope_id,
    v_caller_id,
    now(),
    true,
    p_notes
  )
  ON CONFLICT (user_id, role, partner_scope_id)
  DO UPDATE SET
    is_active = true,
    granted_by = v_caller_id,
    granted_at = now(),
    revoked_at = NULL,
    notes = COALESCE(p_notes, admin_role_assignments.notes)
  RETURNING id INTO v_assignment_id;

  RETURN jsonb_build_object(
    'status', 'assigned',
    'assignment_id', v_assignment_id,
    'role', p_role,
    'user_id', p_target_user_id,
    'partner_scope_id', p_partner_scope_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.list_admin_role_assignments(
  p_role text DEFAULT NULL,
  p_active_only boolean DEFAULT true
)
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
    SELECT 1
    FROM public.users AS u
    WHERE u.id = v_caller_id
      AND u.is_admin = true
  ) THEN
    RAISE EXCEPTION 'Only platform admins can list admin role assignments.';
  END IF;

  IF p_role IS NOT NULL AND p_role NOT IN ('admin', 'bank') THEN
    RAISE EXCEPTION 'Invalid role filter: %. Must be admin or bank.', p_role;
  END IF;

  SELECT COALESCE(
    jsonb_agg(
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
      )
      ORDER BY ra.granted_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_result
  FROM public.admin_role_assignments AS ra
  LEFT JOIN public.users AS u ON u.id = ra.user_id
  LEFT JOIN public.partners AS p ON p.id = ra.partner_scope_id
  WHERE (p_role IS NULL OR ra.role = p_role)
    AND (NOT p_active_only OR ra.is_active = true);

  RETURN v_result;
END;
$$;
