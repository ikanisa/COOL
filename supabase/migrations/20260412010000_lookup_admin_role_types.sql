-- ==========================================================================
-- Phase 1A: admin_role_types lookup table
-- ==========================================================================
-- Replaces CHECK (role IN ('admin','bank','rayon_sport')) on
-- admin_role_assignments with a FK-backed lookup table.
-- Adding new admin roles is now INSERT, not a migration.
-- ==========================================================================

-- 1. Create lookup table
CREATE TABLE IF NOT EXISTS public.admin_role_types (
  code        TEXT PRIMARY KEY,
  label       TEXT NOT NULL,
  description TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  sort_order  INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Seed existing values
INSERT INTO public.admin_role_types (code, label, description, sort_order) VALUES
  ('admin',       'Platform Admin',    'Full platform access (super admin)',      0),
  ('bank',        'Bank Admin',        'Scoped to bank partner workspaces',       1),
  ('rayon_sport', 'Rayon Sport Admin', 'Scoped to Rayon Sports partner workspace', 2)
ON CONFLICT (code) DO NOTHING;

-- 3. Drop the hardcoded CHECK constraint
ALTER TABLE public.admin_role_assignments
  DROP CONSTRAINT IF EXISTS admin_role_assignments_role_check;

-- 4. Add FK constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_admin_role_assignments_role_type'
      AND table_name = 'admin_role_assignments'
  ) THEN
    ALTER TABLE public.admin_role_assignments
      ADD CONSTRAINT fk_admin_role_assignments_role_type
      FOREIGN KEY (role) REFERENCES public.admin_role_types(code);
  END IF;
END $$;

-- 5. RLS: public read, admin write
ALTER TABLE public.admin_role_types ENABLE ROW LEVEL SECURITY;

CREATE POLICY admin_role_types_select_all
  ON public.admin_role_types FOR SELECT
  USING (true);

CREATE POLICY admin_role_types_insert_admin
  ON public.admin_role_types FOR INSERT
  WITH CHECK (public.is_admin_user());

CREATE POLICY admin_role_types_update_admin
  ON public.admin_role_types FOR UPDATE
  USING (public.is_admin_user());

CREATE POLICY admin_role_types_delete_admin
  ON public.admin_role_types FOR DELETE
  USING (public.is_admin_user());

-- 6. updated_at trigger
DROP TRIGGER IF EXISTS trg_admin_role_types_set_updated_at ON public.admin_role_types;
CREATE TRIGGER trg_admin_role_types_set_updated_at
  BEFORE UPDATE ON public.admin_role_types
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Also fix the hardcoded CHECK in assign_admin_role()
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
    SELECT 1 FROM public.users u
    WHERE u.id = v_caller_id AND u.is_admin = true
  ) THEN
    RAISE EXCEPTION 'Only platform admins can assign admin roles.';
  END IF;

  -- Validate role against lookup table (dynamic, not hardcoded)
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_role_types
    WHERE code = p_role AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Invalid or inactive role: %', p_role;
  END IF;

  -- For non-platform roles, partner_scope_id should be provided
  IF p_role <> 'admin' AND p_partner_scope_id IS NULL THEN
    RAISE EXCEPTION 'Partner scope is required for % role.', p_role;
  END IF;

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
