-- Existing Supabase event-trigger helper only. Fresh local schemas have no helper.
-- Preserve its implementation, owner, event trigger, search path and service_role.
DO $collect_rls_helper_permissions$
DECLARE
  helper_oid oid;
  helper record;
BEGIN
  helper_oid := pg_catalog.to_regprocedure('public.rls_auto_enable()');
  IF helper_oid IS NULL THEN
    RETURN;
  END IF;

  SELECT p.prokind, p.prorettype, p.proretset, p.prosecdef, p.proconfig,
         pg_catalog.pg_get_userbyid(p.proowner) AS owner_name,
         l.lanname AS language_name
    INTO STRICT helper
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_language l ON l.oid = p.prolang
   WHERE p.oid = helper_oid;

  IF helper.prokind IS DISTINCT FROM 'f'::"char"
     OR helper.prorettype IS DISTINCT FROM 'pg_catalog.event_trigger'::pg_catalog.regtype
     OR helper.proretset IS DISTINCT FROM false
     OR helper.prosecdef IS DISTINCT FROM true
     OR helper.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]
     OR helper.owner_name IS DISTINCT FROM 'postgres'
     OR helper.language_name IS DISTINCT FROM 'plpgsql' THEN
    RAISE EXCEPTION USING
      ERRCODE = '55000',
      MESSAGE = 'Unexpected public.rls_auto_enable() shape; permissions were not changed';
  END IF;

  REVOKE EXECUTE ON FUNCTION public.rls_auto_enable()
    FROM PUBLIC, anon, authenticated;
END;
$collect_rls_helper_permissions$;
