-- Fix RPCs that use direct public.users.is_admin check instead of is_admin()
-- This breaks when auth.uid() doesn't have a matching public.users row
-- (e.g. GoTrue-created users whose public.users row has a different UUID)
--
-- Affected RPCs: get_biopay_admin_summary, get_financial_reconciliation_summary,
-- get_user_detail_for_admin
--
-- Fix: Replace inline admin check with public.is_admin() which checks BOTH
-- public.users.is_admin AND admin_role_assignments

DO $$
DECLARE
  fn_body text;
BEGIN
  -- 1. get_biopay_admin_summary
  SELECT prosrc INTO fn_body FROM pg_proc WHERE proname = 'get_biopay_admin_summary';
  IF fn_body LIKE '%public.users WHERE id = v_caller_id AND is_admin%' THEN
    fn_body := replace(fn_body,
      E'v_caller_id := auth.uid();\n  IF NOT EXISTS (\n    SELECT 1 FROM public.users WHERE id = v_caller_id AND is_admin = true\n  ) THEN\n    RAISE EXCEPTION ''Admin access required.'';',
      E'IF NOT public.is_admin() THEN\n    RAISE EXCEPTION ''Admin access required.'';');
    fn_body := replace(fn_body, E'DECLARE\n  v_caller_id uuid;\n  v_result jsonb;', E'DECLARE\n  v_result jsonb;');
    EXECUTE format('CREATE OR REPLACE FUNCTION public.get_biopay_admin_summary() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''public'' AS $fn$ %s $fn$', fn_body);
    RAISE NOTICE 'Fixed get_biopay_admin_summary';
  ELSE
    RAISE NOTICE 'get_biopay_admin_summary already fixed';
  END IF;

  -- 2. get_financial_reconciliation_summary
  SELECT prosrc INTO fn_body FROM pg_proc WHERE proname = 'get_financial_reconciliation_summary';
  IF fn_body LIKE '%public.users WHERE id = v_caller_id AND is_admin%' THEN
    fn_body := replace(fn_body,
      E'v_caller_id := auth.uid();\n  IF NOT EXISTS (\n    SELECT 1 FROM public.users WHERE id = v_caller_id AND is_admin = true\n  ) THEN\n    RAISE EXCEPTION ''Admin access required.'';',
      E'IF NOT public.is_admin() THEN\n    RAISE EXCEPTION ''Admin access required.'';');
    fn_body := replace(fn_body, E'DECLARE\n  v_caller_id uuid;\n  v_result jsonb;', E'DECLARE\n  v_result jsonb;');
    EXECUTE format('CREATE OR REPLACE FUNCTION public.get_financial_reconciliation_summary() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''public'' AS $fn$ %s $fn$', fn_body);
    RAISE NOTICE 'Fixed get_financial_reconciliation_summary';
  ELSE
    RAISE NOTICE 'get_financial_reconciliation_summary already fixed';
  END IF;

  -- 3. get_user_detail_for_admin
  SELECT prosrc INTO fn_body FROM pg_proc WHERE proname = 'get_user_detail_for_admin';
  IF fn_body LIKE '%public.users WHERE id = v_caller_id AND is_admin%' THEN
    fn_body := replace(fn_body,
      E'v_caller_id := auth.uid();\n  IF NOT EXISTS (\n    SELECT 1 FROM public.users WHERE id = v_caller_id AND is_admin = true\n  ) THEN\n    RAISE EXCEPTION ''Admin access required.'';',
      E'IF NOT public.is_admin() THEN\n    RAISE EXCEPTION ''Admin access required.'';');
    fn_body := replace(fn_body, 'v_caller_id uuid;', '');
    EXECUTE format('CREATE OR REPLACE FUNCTION public.get_user_detail_for_admin(p_user_id uuid) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO ''public'' AS $fn$ %s $fn$', fn_body);
    RAISE NOTICE 'Fixed get_user_detail_for_admin';
  ELSE
    RAISE NOTICE 'get_user_detail_for_admin already fixed';
  END IF;
END$$;
