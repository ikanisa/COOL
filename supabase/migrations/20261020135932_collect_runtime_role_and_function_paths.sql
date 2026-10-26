-- Additive correction after the published curated baseline.
-- PG16+ CREATEROLE auto-membership is ADMIN true, INHERIT false, SET false.
-- The Edge connection deliberately SET LOCAL ROLEs into collect_runtime.
-- Do not grant inheritance, change ADMIN, or grant anything to the importer.
-- The18 reviewed invoker bodies use only pg_catalog builtins and qualified
-- app/private helpers; no unqualified relations or caller-created functions.
-- Expected body fingerprints make an unreviewed definition change fail closed.
DO $migration$
DECLARE reviewed record; target oid; definition record;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='postgres') OR NOT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='collect_runtime') THEN
  RAISE EXCEPTION 'expected_runtime_roles_missing' USING ERRCODE='42501';
 END IF;
 IF pg_catalog.has_schema_privilege('collect_runtime','app','CREATE') OR pg_catalog.has_schema_privilege('anon','app','CREATE') OR pg_catalog.has_schema_privilege('authenticated','app','CREATE') THEN
  RAISE EXCEPTION 'trusted_application_schema_required' USING ERRCODE='42501';
 END IF;
 GRANT collect_runtime TO postgres WITH INHERIT FALSE, SET TRUE;
 FOR reviewed IN SELECT * FROM (VALUES
   ('api.current_session_id()','12ff3732feafdacdf388dd1d563353ae'),
   ('app.changes()','607e2271a1f74caaebcf7d83418c74b0'),
   ('app.json_array_length(text, text)','befaedca69db067b2bca4534cffdca20'),
   ('app.json_each(text, text)','b37c80cc6a47a2d4a0ddc4a49800e914'),
   ('app.json_extract(text, text)','f5b18e01bed57700c67c52a3192edcd5'),
   ('app.json_numeric(text, text)','feb34623e6f1f270b687c1a891f54c28'),
   ('app.json_type(text, text)','3d5eaa627ba254fb6952dbcccdfe5234'),
   ('app.json_valid(text)','b272787b717ee6e9ed2bf16198686305'),
   ('app.julianday(text)','16502524f6202056d3c09346368acccd'),
   ('app.printf(text, bigint)','f46e379182842094b5c6f8adb26cb0cf'),
   ('app.strftime(text, text, text)','76f2b2e7f817dfbb11b1f1598053c0e4'),
   ('app.unixepoch()','bec4f42d613a1fa05447f3012b9413d6'),
   ('app.unixepoch(text)','95a6941519f63ccce9ec6f88e895c0e2'),
   ('private.request_claims()','0a2396fc7b7ac963b7bc4464dd31b1d5'),
   ('private.trg_auth_principal_link_identity()','45240dbcba50ed79f86d93a2b7953165'),
   ('private.trg_google_flow_context_identity()','e05477d9be8ccee7e28f9a7b43b3873d'),
   ('private.trg_managed_phone_proof_identity()','87ae089333a756bcb52c9384a3020ea3'),
   ('private.trg_supabase_otp_identity()','d754cca4336ec0c0577340a1323e7806')
 ) AS reviewed_functions(signature,body_md5) LOOP
  target:=pg_catalog.to_regprocedure(reviewed.signature);
  IF target IS NULL THEN RAISE EXCEPTION 'reviewed_function_missing: %',reviewed.signature USING ERRCODE='42501'; END IF;
  SELECT p.prosrc,p.prosecdef,p.proconfig INTO STRICT definition FROM pg_catalog.pg_proc p WHERE p.oid=target;
  IF NOT EXISTS(SELECT 1 FROM pg_catalog.unnest(coalesce(definition.proconfig,'{}'::text[])) cfg WHERE cfg LIKE 'search_path=%') THEN
   IF definition.prosecdef OR pg_catalog.md5(definition.prosrc)<>reviewed.body_md5 THEN
    RAISE EXCEPTION 'reviewed_function_body_changed: %',reviewed.signature USING ERRCODE='42501';
   END IF;
   EXECUTE pg_catalog.format('ALTER FUNCTION %s SET search_path TO pg_catalog, app',target::regprocedure);
  END IF;
 END LOOP;
END $migration$;
