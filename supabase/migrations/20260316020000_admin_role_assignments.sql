-- ════════════════════════════════════════════════════════════════
-- ADMIN ROLE ASSIGNMENTS — database-backed RBAC for admin panel
-- ════════════════════════════════════════════════════════════════
-- Replaces app_metadata-only admin role detection with a queryable,
-- auditable table. Supports three admin roles:
--   admin       → full platform access (super admin)
--   bank        → scoped to bank partner workspaces
--   rayon_sport → scoped to Rayon Sports workspace
-- ════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────
-- 1) admin_role_assignments table
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_role_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('admin', 'bank', 'rayon_sport')),
  -- partner_scope_id: NULL for 'admin' (global). For 'bank' role, references
  -- the bank partner. For 'rayon_sport' role, references the Rayon Sports partner.
  partner_scope_id uuid REFERENCES public.partners(id) ON DELETE CASCADE,
  granted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  granted_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  notes text,
  UNIQUE (user_id, role, partner_scope_id)
);

-- Index for fast lookup by user
CREATE INDEX IF NOT EXISTS idx_admin_role_assignments_user_id
  ON public.admin_role_assignments(user_id)
  WHERE is_active = true;

-- Index for fast lookup by role
CREATE INDEX IF NOT EXISTS idx_admin_role_assignments_role
  ON public.admin_role_assignments(role)
  WHERE is_active = true;

-- ──────────────────────────────────────────────────────────────
-- 2) RLS policies on admin_role_assignments
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.admin_role_assignments ENABLE ROW LEVEL SECURITY;

-- Super admins (is_admin in users table) can read all assignments
CREATE POLICY admin_role_assignments_select_policy
  ON public.admin_role_assignments
  FOR SELECT
  USING (
    -- User can see their own assignments
    auth.uid() = user_id
    OR
    -- Platform admins can see all
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.is_admin = true
    )
  );

-- Only platform admins can insert/update role assignments
CREATE POLICY admin_role_assignments_insert_policy
  ON public.admin_role_assignments
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.is_admin = true
    )
  );

CREATE POLICY admin_role_assignments_update_policy
  ON public.admin_role_assignments
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.is_admin = true
    )
  );

-- No delete — use soft-delete via is_active + revoked_at
CREATE POLICY admin_role_assignments_delete_policy
  ON public.admin_role_assignments
  FOR DELETE
  USING (false);

-- ──────────────────────────────────────────────────────────────
-- 3) RPC: get_admin_access_for_user
-- Returns structured admin access object for a given user.
-- Falls back to app_metadata for backward compatibility.
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_admin_access_for_user(p_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_is_platform_admin boolean := false;
  v_result jsonb;
  v_role_rows jsonb;
  v_bank_ids jsonb;
  v_partner_ids jsonb;
  v_has_rayon boolean := false;
BEGIN
  -- Use current user if not specified
  v_user_id := COALESCE(p_user_id, auth.uid());

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'has_platform_access', false,
      'has_bank_access', false,
      'has_rayon_access', false,
      'bank_partner_ids', '[]'::jsonb,
      'partner_admin_ids', '[]'::jsonb,
      'role_assignments', '[]'::jsonb
    );
  END IF;

  -- Check if the user is a platform admin (from users table)
  SELECT COALESCE(u.is_admin, false)
  INTO v_is_platform_admin
  FROM public.users u
  WHERE u.id = v_user_id;

  -- Get active role assignments
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', ra.id,
      'role', ra.role,
      'partner_scope_id', ra.partner_scope_id,
      'partner_name', p.name,
      'granted_at', ra.granted_at,
      'is_active', ra.is_active
    )
  ), '[]'::jsonb)
  INTO v_role_rows
  FROM public.admin_role_assignments ra
  LEFT JOIN public.partners p ON p.id = ra.partner_scope_id
  WHERE ra.user_id = v_user_id AND ra.is_active = true;

  -- Extract bank partner IDs
  SELECT COALESCE(jsonb_agg(ra.partner_scope_id), '[]'::jsonb)
  INTO v_bank_ids
  FROM public.admin_role_assignments ra
  WHERE ra.user_id = v_user_id
    AND ra.is_active = true
    AND ra.role = 'bank'
    AND ra.partner_scope_id IS NOT NULL;

  -- Extract partner admin IDs (non-rayon partners)
  SELECT COALESCE(jsonb_agg(ra.partner_scope_id), '[]'::jsonb)
  INTO v_partner_ids
  FROM public.admin_role_assignments ra
  WHERE ra.user_id = v_user_id
    AND ra.is_active = true
    AND ra.role = 'rayon_sport'
    AND ra.partner_scope_id IS NOT NULL;

  -- Check rayon_sport role
  SELECT EXISTS(
    SELECT 1 FROM public.admin_role_assignments ra
    WHERE ra.user_id = v_user_id
      AND ra.is_active = true
      AND ra.role = 'rayon_sport'
  ) INTO v_has_rayon;

  -- Also check for 'admin' role assignment (in addition to users.is_admin)
  IF NOT v_is_platform_admin THEN
    SELECT EXISTS(
      SELECT 1 FROM public.admin_role_assignments ra
      WHERE ra.user_id = v_user_id
        AND ra.is_active = true
        AND ra.role = 'admin'
    ) INTO v_is_platform_admin;
  END IF;

  v_result := jsonb_build_object(
    'has_platform_access', v_is_platform_admin,
    'has_bank_access', v_is_platform_admin OR jsonb_array_length(v_bank_ids) > 0,
    'has_rayon_access', v_is_platform_admin OR v_has_rayon,
    'bank_partner_ids', v_bank_ids,
    'partner_admin_ids', v_partner_ids,
    'role_assignments', v_role_rows
  );

  RETURN v_result;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.get_admin_access_for_user(uuid) TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 4) RPC: assign_admin_role (super admin only)
-- ──────────────────────────────────────────────────────────────
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

  -- Only platform admins can assign roles
  IF NOT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = v_caller_id AND u.is_admin = true
  ) THEN
    RAISE EXCEPTION 'Only platform admins can assign admin roles.';
  END IF;

  -- Validate role
  IF p_role NOT IN ('admin', 'bank', 'rayon_sport') THEN
    RAISE EXCEPTION 'Invalid role: %. Must be admin, bank, or rayon_sport.', p_role;
  END IF;

  -- For admin role, partner_scope_id should be NULL
  -- For bank/rayon_sport, partner_scope_id should be provided
  IF p_role IN ('bank', 'rayon_sport') AND p_partner_scope_id IS NULL THEN
    RAISE EXCEPTION 'Partner scope is required for % role.', p_role;
  END IF;

  -- Upsert (reactivate if previously revoked)
  INSERT INTO public.admin_role_assignments (
    user_id, role, partner_scope_id, granted_by, granted_at, is_active, notes
  ) VALUES (
    p_target_user_id, p_role, p_partner_scope_id, v_caller_id, now(), true, p_notes
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

GRANT EXECUTE ON FUNCTION public.assign_admin_role(uuid, text, uuid, text) TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 5) RPC: revoke_admin_role (super admin only)
-- ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.revoke_admin_role(
  p_assignment_id uuid,
  p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id uuid;
  v_assignment record;
BEGIN
  v_caller_id := auth.uid();

  -- Only platform admins can revoke roles
  IF NOT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = v_caller_id AND u.is_admin = true
  ) THEN
    RAISE EXCEPTION 'Only platform admins can revoke admin roles.';
  END IF;

  -- Find and validate assignment
  SELECT * INTO v_assignment
  FROM public.admin_role_assignments
  WHERE id = p_assignment_id AND is_active = true;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Role assignment not found or already revoked.';
  END IF;

  -- Soft-delete
  UPDATE public.admin_role_assignments
  SET is_active = false,
      revoked_at = now(),
      notes = COALESCE(p_notes, notes)
  WHERE id = p_assignment_id;

  RETURN jsonb_build_object(
    'status', 'revoked',
    'assignment_id', p_assignment_id,
    'role', v_assignment.role,
    'user_id', v_assignment.user_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.revoke_admin_role(uuid, text) TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 6) RPC: list_admin_role_assignments (super admin only)
-- ──────────────────────────────────────────────────────────────
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

  -- Only platform admins can list all assignments
  IF NOT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = v_caller_id AND u.is_admin = true
  ) THEN
    RAISE EXCEPTION 'Only platform admins can list admin role assignments.';
  END IF;

  SELECT COALESCE(jsonb_agg(
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
    ) ORDER BY ra.granted_at DESC
  ), '[]'::jsonb)
  INTO v_result
  FROM public.admin_role_assignments ra
  LEFT JOIN public.users u ON u.id = ra.user_id
  LEFT JOIN public.partners p ON p.id = ra.partner_scope_id
  WHERE (p_role IS NULL OR ra.role = p_role)
    AND (NOT p_active_only OR ra.is_active = true);

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_admin_role_assignments(text, boolean) TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 7) Seed from existing app_metadata (backward compat)
-- Migrate any users who already have admin roles via app_metadata
-- into the new table so they don't lose access.
-- ──────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_user record;
  v_partner_id text;
  v_rayon_partner_id uuid;
BEGIN
  -- Find the Rayon Sports partner ID
  SELECT id INTO v_rayon_partner_id
  FROM public.partners
  WHERE slug = 'rayon-sports'
  LIMIT 1;

  -- Seed 'admin' role for users with is_admin = true
  INSERT INTO public.admin_role_assignments (user_id, role, partner_scope_id, notes)
  SELECT u.id, 'admin', NULL, 'Auto-seeded from users.is_admin flag'
  FROM public.users u
  WHERE u.is_admin = true
  ON CONFLICT (user_id, role, partner_scope_id) DO NOTHING;

  -- Seed 'bank' role from app_metadata.bank_admin_ids
  FOR v_user IN
    SELECT au.id AS auth_user_id,
           au.raw_app_meta_data->'bank_admin_ids' AS bank_ids
    FROM auth.users au
    WHERE au.raw_app_meta_data ? 'bank_admin_ids'
      AND jsonb_typeof(au.raw_app_meta_data->'bank_admin_ids') = 'array'
  LOOP
    FOR v_partner_id IN
      SELECT jsonb_array_elements_text(v_user.bank_ids)
    LOOP
      BEGIN
        INSERT INTO public.admin_role_assignments (user_id, role, partner_scope_id, notes)
        VALUES (v_user.auth_user_id, 'bank', v_partner_id::uuid, 'Auto-seeded from app_metadata.bank_admin_ids')
        ON CONFLICT (user_id, role, partner_scope_id) DO NOTHING;
      EXCEPTION WHEN OTHERS THEN
        -- Skip invalid UUIDs
        NULL;
      END;
    END LOOP;
  END LOOP;

  -- Seed 'rayon_sport' role from app_metadata.partner_admin_ids
  -- (any user with partner_admin_ids containing the rayon partner)
  IF v_rayon_partner_id IS NOT NULL THEN
    FOR v_user IN
      SELECT au.id AS auth_user_id,
             au.raw_app_meta_data->'partner_admin_ids' AS partner_ids
      FROM auth.users au
      WHERE au.raw_app_meta_data ? 'partner_admin_ids'
        AND jsonb_typeof(au.raw_app_meta_data->'partner_admin_ids') = 'array'
    LOOP
      FOR v_partner_id IN
        SELECT jsonb_array_elements_text(v_user.partner_ids)
      LOOP
        IF v_partner_id::uuid = v_rayon_partner_id THEN
          BEGIN
            INSERT INTO public.admin_role_assignments (user_id, role, partner_scope_id, notes)
            VALUES (v_user.auth_user_id, 'rayon_sport', v_rayon_partner_id, 'Auto-seeded from app_metadata.partner_admin_ids')
            ON CONFLICT (user_id, role, partner_scope_id) DO NOTHING;
          EXCEPTION WHEN OTHERS THEN
            NULL;
          END;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  -- Seed from is_bank_admin global flag
  INSERT INTO public.admin_role_assignments (user_id, role, partner_scope_id, notes)
  SELECT au.id, 'bank', p.id, 'Auto-seeded from app_metadata.is_bank_admin (global bank access)'
  FROM auth.users au
  CROSS JOIN public.partners p
  WHERE (au.raw_app_meta_data->>'is_bank_admin')::boolean = true
    AND p.category = 'bank'
  ON CONFLICT (user_id, role, partner_scope_id) DO NOTHING;

  -- Seed from is_partner_admin global flag for rayon
  IF v_rayon_partner_id IS NOT NULL THEN
    INSERT INTO public.admin_role_assignments (user_id, role, partner_scope_id, notes)
    SELECT au.id, 'rayon_sport', v_rayon_partner_id, 'Auto-seeded from app_metadata.is_partner_admin (global partner access)'
    FROM auth.users au
    WHERE (au.raw_app_meta_data->>'is_partner_admin')::boolean = true
    ON CONFLICT (user_id, role, partner_scope_id) DO NOTHING;
  END IF;
END;
$$;
