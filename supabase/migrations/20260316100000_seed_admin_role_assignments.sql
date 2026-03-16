-- Seed admin_role_assignments for existing is_admin users
-- who don't already have a role assignment.
-- This ensures existing platform admins are covered by the new RBAC system.

INSERT INTO public.admin_role_assignments (user_id, role, granted_by, notes)
SELECT
  u.id,
  'admin'::text,
  u.id,  -- self-granted (historical)
  'Seeded from is_admin flag during RBAC migration'
FROM public.users u
WHERE u.is_admin = true
  AND NOT EXISTS (
    SELECT 1 FROM public.admin_role_assignments ara
    WHERE ara.user_id = u.id
      AND ara.role = 'admin'
      AND ara.is_active = true
  );
