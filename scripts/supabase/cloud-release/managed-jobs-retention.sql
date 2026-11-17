-- Add the opaque job ticket to shared blocked retention inventory. Existing
-- catalog bytes and the exact managed project/fence are prerequisites.
DO $managed_job_retention$
DECLARE old_body text;new_body text;classes jsonb;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced' AND project_ref='rrlduytparvsjfmegalh')
  OR to_regclass('private.collect_managed_job_tickets') IS NULL THEN
  RAISE EXCEPTION 'managed_job_retention_precondition' USING ERRCODE='55000';END IF;
 SELECT prosrc INTO STRICT old_body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure
  AND pg_get_userbyid(proowner)='postgres' AND NOT prosecdef AND provolatile='i'
  AND proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND proacl::text='{postgres=X/postgres}';
 IF encode(sha256(convert_to(old_body,'UTF8')),'hex')<>'09ecc11aca46af15d7f981b5d5c7c7d3775be6fc245c8ff73f48f61269e37671' THEN
  RAISE EXCEPTION 'managed_job_retention_preimage_changed' USING ERRCODE='55000';END IF;
 classes:='[{"name":"private:collect_managed_job_tickets","relation":"private.collect_managed_job_tickets","scope":"shared_fence","purpose":"One-use scheduled job identity and bounded source/payload with claim and completion digests; blocked shared operational copy","blocked":true}]'::jsonb;
 new_body:=format('SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||%L::jsonb) FROM (%s) prior(base)',classes::text,old_body);
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(new_body);
END;$managed_job_retention$;
