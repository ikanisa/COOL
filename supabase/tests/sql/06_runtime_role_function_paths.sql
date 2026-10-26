-- Synthetic local regression only: requires the superuser fixture runner to
-- assume a genuinely non-superuser session identity. Never run this fixture
-- against a hosted project. Every probe object/role is rolled back.
BEGIN;
DO $$BEGIN
 IF (SELECT rolsuper OR rolcanlogin OR rolinherit OR rolcreaterole OR rolcreatedb OR rolbypassrls OR rolreplication FROM pg_catalog.pg_roles WHERE rolname='postgres') IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Expected local postgres NOLOGIN non-superuser fixture';
 END IF;
 IF NOT pg_catalog.pg_has_role('postgres','collect_runtime','SET') THEN RAISE EXCEPTION 'Edge operator cannot SET runtime role'; END IF;
 IF pg_catalog.pg_has_role('postgres','collect_runtime','USAGE') THEN RAISE EXCEPTION 'Runtime privileges inherited without SET ROLE'; END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_auth_members m WHERE m.roleid='collect_runtime'::regrole AND m.member='postgres'::regrole AND m.inherit_option) THEN RAISE EXCEPTION 'Unexpected runtime inheritance'; END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='collect_importer') THEN
  IF pg_catalog.pg_has_role('collect_importer','collect_runtime','SET') OR pg_catalog.pg_has_role('collect_importer','collect_runtime','USAGE') OR pg_catalog.has_schema_privilege('collect_importer','app','USAGE') OR pg_catalog.has_schema_privilege('collect_importer','private','USAGE') THEN RAISE EXCEPTION 'Importer gained runtime authority'; END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('app','private','api') AND NOT EXISTS(SELECT 1 FROM pg_catalog.unnest(coalesce(p.proconfig,'{}'::text[])) cfg WHERE cfg LIKE 'search_path=%')) THEN RAISE EXCEPTION 'Application function path remains caller-mutable'; END IF;
 IF EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a WHERE n.nspname IN('app','private','api') AND a.grantee=0 AND a.privilege_type='EXECUTE') THEN RAISE EXCEPTION 'PUBLIC application execute leak'; END IF;
 IF pg_catalog.has_schema_privilege('anon','app','USAGE') OR pg_catalog.has_schema_privilege('authenticated','private','USAGE') OR pg_catalog.has_schema_privilege('collect_runtime','app','CREATE') OR pg_catalog.has_table_privilege('collect_runtime','auth.users','UPDATE') THEN RAISE EXCEPTION 'Runtime/client privilege boundary changed'; END IF;
END$$;

CREATE SCHEMA collect_runtime_caller_shadow;
CREATE FUNCTION collect_runtime_caller_shadow.jsonb_typeof(jsonb) RETURNS text LANGUAGE sql AS $$SELECT 'caller_shadow'::text$$;
CREATE FUNCTION collect_runtime_caller_shadow.current_setting(text,boolean) RETURNS text LANGUAGE sql AS $$SELECT '{"session_id":"caller_shadow"}'::text$$;
GRANT USAGE ON SCHEMA collect_runtime_caller_shadow TO collect_runtime;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA collect_runtime_caller_shadow TO collect_runtime;
CREATE ROLE collect_runtime_denied_probe NOLOGIN NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB NOBYPASSRLS NOREPLICATION;

SET LOCAL SESSION AUTHORIZATION postgres;
DO $$BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR (SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname=current_user) THEN RAISE EXCEPTION 'Non-superuser session identity was not installed'; END IF;
END$$;
-- This is the exact operation the Edge PostgreSQL adapter requires. It fails
-- with SQLSTATE42501 on PG16+ creator auto-membership before the additive fix.
SET LOCAL ROLE collect_runtime;
SET LOCAL search_path=collect_runtime_caller_shadow,public,app,pg_catalog;
SET LOCAL request.jwt.claims='{"role":"authenticated","session_id":"06000000-0000-4000-8000-000000000001"}';
DO $$BEGIN
 IF current_user<>'collect_runtime' OR session_user<>'postgres' OR (SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname=current_user) THEN RAISE EXCEPTION 'SET ROLE proof still relies on superuser authority'; END IF;
 IF jsonb_typeof('{}'::jsonb)<>'caller_shadow' THEN RAISE EXCEPTION 'Caller shadow fixture is not active'; END IF;
 IF app.json_extract('{"ok":"trusted"}','$.ok')<>'trusted' OR app.json_numeric('{"ok":1}','$.ok')<>1 OR app.json_type('{"ok":true}','$.ok')<>'true' OR app.json_array_length('[1,2]')<>2 OR NOT app.json_valid('{}') THEN RAISE EXCEPTION 'Fixed compatibility path changed behavior'; END IF;
 IF api.current_session_id()<>'06000000-0000-4000-8000-000000000001' OR private.request_claims()->>'session_id'<>'06000000-0000-4000-8000-000000000001' THEN RAISE EXCEPTION 'Caller shadow controls managed request claims'; END IF;
 PERFORM count(*) FROM app.users;
 BEGIN
  EXECUTE 'CREATE TABLE app.__runtime_ddl_probe(id integer)';
  RAISE EXCEPTION 'Runtime obtained application DDL';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END$$;

SET LOCAL SESSION AUTHORIZATION collect_runtime_denied_probe;
DO $$BEGIN
 IF (SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname=current_user) THEN RAISE EXCEPTION 'Denied probe unexpectedly superuser'; END IF;
 BEGIN
  EXECUTE 'SET LOCAL ROLE collect_runtime';
  RAISE EXCEPTION 'Unrelated identity can SET runtime role';
 EXCEPTION WHEN insufficient_privilege THEN NULL;
 END;
END$$;
ROLLBACK;
