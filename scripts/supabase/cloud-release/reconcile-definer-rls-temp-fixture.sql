-- Demonstrates PostgreSQL role/RLS behavior only. One session; no application
-- tables or permanent roles. Run with ON_ERROR_STOP, then verify ROLLBACK.
BEGIN;
SET LOCAL row_security=on;
CREATE TEMP TABLE reconcile_rls_probe(id integer NOT NULL);
INSERT INTO pg_temp.reconcile_rls_probe VALUES(1);
ALTER TABLE pg_temp.reconcile_rls_probe ENABLE ROW LEVEL SECURITY;
ALTER TABLE pg_temp.reconcile_rls_probe FORCE ROW LEVEL SECURITY;
CREATE POLICY reconcile_probe_deny ON pg_temp.reconcile_rls_probe FOR SELECT TO PUBLIC USING(false);
GRANT SELECT ON pg_temp.reconcile_rls_probe TO collect_runtime;
DO $grant_temp$
DECLARE n text;
BEGIN
 SELECT nspname INTO STRICT n FROM pg_namespace WHERE oid=pg_my_temp_schema();
 EXECUTE format('GRANT USAGE ON SCHEMA %I TO collect_runtime',n);
 IF current_user<>'postgres' OR NOT (SELECT rolbypassrls FROM pg_roles WHERE rolname='postgres')
  OR (SELECT rolbypassrls FROM pg_roles WHERE rolname='collect_runtime') THEN
  RAISE EXCEPTION 'unexpected fixture role attributes';END IF;
END;$grant_temp$;
CREATE FUNCTION pg_temp.reconcile_probe_invoker() RETURNS integer
 LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS
 $f$SELECT count(*)::integer FROM pg_temp.reconcile_rls_probe$f$;
CREATE FUNCTION pg_temp.reconcile_probe_definer() RETURNS integer
 LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS
 $f$SELECT count(*)::integer FROM pg_temp.reconcile_rls_probe$f$;
REVOKE ALL ON FUNCTION pg_temp.reconcile_probe_invoker(),pg_temp.reconcile_probe_definer() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_temp.reconcile_probe_invoker(),pg_temp.reconcile_probe_definer() TO collect_runtime;
SET LOCAL ROLE collect_runtime;
DO $test$
BEGIN
 IF pg_temp.reconcile_probe_invoker()<>0 THEN RAISE EXCEPTION 'invoker unexpectedly bypassed RLS';END IF;
 IF pg_temp.reconcile_probe_definer()<>1 THEN RAISE EXCEPTION 'postgres definer did not bypass forced RLS';END IF;
 RAISE NOTICE 'synthetic definer/RLS role behavior passed';
END;$test$;
RESET ROLE;
ROLLBACK;
