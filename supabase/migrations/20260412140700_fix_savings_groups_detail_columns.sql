-- Fix admin_get_savings_groups_detail: remove references to non-existent
-- is_active and is_closed columns on the groups table

DO $$
DECLARE
  fn_body text;
BEGIN
  SELECT prosrc INTO fn_body FROM pg_proc WHERE proname = 'admin_get_savings_groups_detail';

  -- Remove is_active/is_closed from active count
  fn_body := replace(fn_body,
    E'SELECT count(*) FROM public.groups WHERE type = ''saving'' AND is_active = true AND COALESCE(is_closed, false) = false',
    E'SELECT count(*) FROM public.groups WHERE type = ''saving''');

  -- Remove is_closed/is_active from savings group object
  fn_body := replace(fn_body,
    E'''is_closed'', COALESCE(g.is_closed, false),\n          ''is_active'', COALESCE(g.is_active, true),',
    '');

  -- Remove is_closed from community group object
  fn_body := replace(fn_body,
    E'''is_closed'', COALESCE(g.is_closed, false),\n          ''created_at''',
    E'''created_at''');

  EXECUTE format(
    'CREATE OR REPLACE FUNCTION public.admin_get_savings_groups_detail() '
    'RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER '
    'SET search_path TO ''public'' AS $fn$ %s $fn$',
    fn_body
  );
END$$;
