-- ============================================================
-- QA FIX: Tighten admin_audit_log INSERT policy
-- Before: any authenticated user could insert
-- After: only admin users can insert
-- ============================================================

-- Drop the overly-permissive policy
DROP POLICY IF EXISTS "Authenticated users can insert audit log" ON public.admin_audit_log;

-- Create admin-only INSERT policy
CREATE POLICY "Admins can insert audit log"
  ON public.admin_audit_log
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = (SELECT auth.uid())
        AND u.is_admin = true
    )
  );

-- Keep service_role INSERT as-is (it bypasses RLS anyway)
