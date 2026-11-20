-- Uninstalled managed-production binding candidate. The existing immutable
-- identity migration must be installed first. This is not a versioned migration.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SET LOCAL search_path=pg_catalog,pg_temp;
DO $preflight$
BEGIN
 IF session_user<>'postgres' OR current_user<>'postgres'
  OR coalesce(current_setting('role',true),'none') NOT IN('none','postgres')
  OR current_setting('transaction_isolation')<>'read committed'
  OR to_regclass('supabase_migrations.schema_migrations') IS NULL
  OR to_regclass('private.collect_deployment_identity') IS NULL
  OR to_regclass('private.collect_fence_control') IS NULL
  OR to_regclass('private.collect_fence_admissions') IS NULL
  OR to_regprocedure('private._collect_fence_scheduler_status()') IS NULL
  OR to_regprocedure('private.collect_assert_deployment(text)') IS NULL
  OR to_regprocedure('private._collect_managed_identity_preimage()') IS NOT NULL
  OR to_regprocedure('private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)') IS NOT NULL
  OR to_regprocedure('private.collect_bind_managed_deployment(uuid,text,text)') IS NOT NULL
  OR (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid='private.collect_deployment_identity'::regclass)<>'postgres'
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_install_precondition';END IF;
END;$preflight$;

-- The migration writer takes this same lock before the history table lock.
-- Source/DDL actors which do not cooperate must still be excluded externally.
SELECT pg_advisory_xact_lock(7346371,11);
LOCK TABLE supabase_migrations.schema_migrations IN SHARE MODE;

-- Pin the existing immutable table and assertion to the reviewed predecessor.
-- A table with a disabled immutability trigger or an altered assertion must not
-- be accepted merely because its names exist. This does not replace a hosted
-- review of inherited roles, fence functions, or concurrent schema actors.
CREATE FUNCTION private._collect_managed_identity_preimage() RETURNS void
LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $identity_preimage$
DECLARE col_hash text;constraint_hash text;
BEGIN
 -- A role that can SET ROLE to the owner can reach owner-only objects even
 -- when it does not inherit their privileges by default.
 IF EXISTS(SELECT 1 FROM pg_roles r WHERE NOT r.rolsuper AND r.rolname<>'postgres'
   AND pg_has_role(r.oid,'postgres'::regrole,'MEMBER'))
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_owner_role_preimage';END IF;
 IF to_regprocedure('private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)') IS NOT NULL
  AND EXISTS(SELECT 1 FROM pg_roles r WHERE NOT r.rolsuper AND r.rolname<>'postgres'
   AND (has_function_privilege(r.oid,to_regprocedure('private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)'),'EXECUTE')
    OR has_function_privilege(r.oid,to_regprocedure('private._collect_managed_identity_preimage()'),'EXECUTE')))
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_effective_privilege_preimage';END IF;
 IF (SELECT count(*) FROM supabase_migrations.schema_migrations
     WHERE version IN('20261022195747','20261101012309','20261101013157'))<>3
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
   WHERE version='20261022195747' AND name='collect_application_mutation_fence'
    AND cardinality(statements)=1
    AND encode(sha256(convert_to(statements[1],'UTF8')),'hex')='714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497')
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
   WHERE version='20261101012309' AND name='collect_admission_archive'
    AND cardinality(statements)=1
    AND encode(sha256(convert_to(statements[1],'UTF8')),'hex')='82b09d4d2abd5994429a978ccf80daa796fd83e5dc5d29bc54076f2b7565ad84')
  OR NOT EXISTS(SELECT 1 FROM supabase_migrations.schema_migrations
   WHERE version='20261101013157' AND name='collect_deployment_identity'
    AND cardinality(statements)=1
    AND encode(sha256(convert_to(statements[1],'UTF8')),'hex')='916a7b3012135484c74f0a6b4707cdda39c637959f8564233fc8f6a8f5adbdc1')
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_history_preimage';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid='private._collect_fence_scheduler_status()'::regprocedure AND pg_get_userbyid(p.proowner)='postgres'
    AND l.lanname='plpgsql' AND p.prosecdef AND p.provolatile='v' AND NOT p.proisstrict
    AND p.prorettype='jsonb'::regtype AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='5dc44f65fb52562bc6a0391a7f7b7d050c333c2276f98097943d9c1e340d926d'
    AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee<>p.proowner))
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_scheduler_preimage';END IF;
 SELECT encode(sha256(convert_to((SELECT jsonb_agg(jsonb_build_object(
   'name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'notnull',a.attnotnull,
   'identity',a.attidentity::text,'generated',a.attgenerated::text,'default',pg_get_expr(d.adbin,d.adrelid)) ORDER BY a.attnum)::text
   FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
   WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'UTF8')),'hex'),
  encode(sha256(convert_to((SELECT jsonb_agg(jsonb_build_object(
   'name',x.conname,'kind',x.contype::text,'definition',pg_get_constraintdef(x.oid),
   'deferrable',x.condeferrable,'deferred',x.condeferred,'valid',x.convalidated) ORDER BY x.conname)::text
   FROM pg_constraint x WHERE x.conrelid=c.oid),'UTF8')),'hex')
 INTO col_hash,constraint_hash FROM pg_class c WHERE c.oid='private.collect_deployment_identity'::regclass
  AND pg_get_userbyid(c.relowner)='postgres' AND c.relkind='r' AND c.relrowsecurity AND NOT c.relforcerowsecurity;
 IF col_hash IS DISTINCT FROM 'fbd3b36e805d6a2b872a7af68f0eb6bab0675ed1fd36367d95a8969f3af44db0'
  OR constraint_hash IS DISTINCT FROM '0b89609c2964471a3f544fe09529155b70992c437e62e1477ce7eb20992d913e'
  OR EXISTS(SELECT 1 FROM pg_class c,LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
   WHERE c.oid='private.collect_deployment_identity'::regclass AND a.grantee<>c.relowner)
  OR (SELECT count(*) FROM pg_trigger WHERE tgrelid='private.collect_deployment_identity'::regclass AND NOT tgisinternal)<>1
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.collect_deployment_identity'::regclass AND NOT tgisinternal
   AND tgname='collect_deployment_immutable' AND tgenabled='A' AND tgtype=58
   AND tgfoid='private._collect_deployment_immutable()'::regprocedure AND tgqual IS NULL AND tgnargs=0)
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_identity_preimage';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
  WHERE p.oid='private._collect_deployment_immutable()'::regprocedure AND pg_get_userbyid(p.proowner)='postgres'
   AND l.lanname='plpgsql' AND NOT p.prosecdef AND p.provolatile='v'
   AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='d210d7cb56bf315f01f48feb31ce1b3e77b0fdc32bffec5c90acfae22ff7878f'
   AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee<>p.proowner))
  OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid='private.collect_assert_deployment(text)'::regprocedure AND pg_get_userbyid(p.proowner)='postgres'
    AND l.lanname='plpgsql' AND p.prosecdef AND p.provolatile='s' AND p.prorettype='boolean'::regtype
    AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='94dd79ac9e0dabb5a5a02057515124e54eba66cf04e3ce2da6f7f0027df88fbd'
    AND EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
     WHERE a.grantee=(SELECT oid FROM pg_roles WHERE rolname='collect_runtime') AND a.privilege_type='EXECUTE'
      AND a.grantor=p.proowner AND NOT a.is_grantable)
    AND NOT EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
     WHERE a.grantee<>p.proowner AND (a.grantee<>(SELECT oid FROM pg_roles WHERE rolname='collect_runtime')
      OR a.grantor<>p.proowner OR a.privilege_type<>'EXECUTE' OR a.is_grantable)))
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_assertion_preimage';END IF;
END;$identity_preimage$;
SELECT private._collect_managed_identity_preimage();

-- A separate entrypoint preserves the existing self-hosted binding contract.
-- Its output is the same immutable identity consumed by the existing runtime
-- and SMS work_register assertion; it does not replace either assertion.
CREATE FUNCTION private.collect_bind_managed_deployment(p_operation uuid,p_profile text,p_sha256 text,
 p_fence_operation uuid,p_fence_epoch bigint,p_fence_source_sha256 text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp SET lock_timeout='5s' AS $fn$
DECLARE profile jsonb;old private.collect_deployment_identity%ROWTYPE;c private.collect_fence_control%ROWTYPE;
BEGIN
 IF session_user<>'postgres' OR current_user<>'postgres'
  OR coalesce(current_setting('role',true),'none') NOT IN('none','postgres')
  OR current_setting('transaction_isolation')<>'read committed'
  OR p_operation IS NULL OR p_sha256 IS NULL OR p_sha256 !~ '^[a-f0-9]{64}$'
  OR p_fence_operation IS NULL OR p_fence_epoch IS NULL OR p_fence_epoch<1
  OR p_fence_source_sha256 IS NULL OR p_fence_source_sha256 !~ '^[a-f0-9]{64}$'
  OR p_profile IS NULL OR octet_length(p_profile)>8192
  OR encode(sha256(convert_to(p_profile,'UTF8')),'hex')<>p_sha256
 THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='managed_deployment_binding_refused';END IF;
 profile:=p_profile::jsonb;
 IF jsonb_typeof(profile)<>'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(profile) k)
  IS DISTINCT FROM ARRAY['admin_origin','environment','format','google_callback_origin','id','member_api_origin','mode','public_origin','supabase_origin']::text[]
  OR EXISTS(SELECT 1 FROM jsonb_each(profile) e WHERE jsonb_typeof(e.value)<>'string')
  OR profile->>'format' IS DISTINCT FROM 'collect.deployment.v1'
  OR profile->>'mode' IS DISTINCT FROM 'managed'
  OR profile->>'environment' IS DISTINCT FROM 'production'
  OR profile->>'supabase_origin' IS DISTINCT FROM 'https://rrlduytparvsjfmegalh.supabase.co'
  OR profile->>'id' !~ '^[a-z][a-z0-9-]{0,62}$'
 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='managed_deployment_profile_invalid';END IF;
 IF p_profile IS DISTINCT FROM (SELECT '{'||string_agg(to_jsonb(e.key)::text||':'||e.value::text,',' ORDER BY e.key)||'}' FROM jsonb_each(profile) e)
  OR EXISTS(SELECT 1 FROM jsonb_each_text(profile) e WHERE e.key LIKE '%_origin' AND (
    e.value !~ '^https://[a-z0-9.-]+$' OR length(e.value)>2048
    OR length(substr(e.value,9))>253 OR strpos(substr(e.value,9),'.')=0
    OR substr(e.value,9) ~ '^[0-9.]+$'
    OR substring(substr(e.value,9) FROM '[^.]+$') ~ '^([0-9]+|0x[0-9a-f]*)$'
    OR EXISTS(SELECT 1 FROM unnest(string_to_array(substr(e.value,9),'.')) label
     WHERE label !~ '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$' OR label LIKE 'xn--%')))
  OR profile->>'google_callback_origin' NOT IN(profile->>'admin_origin',profile->>'member_api_origin')
 THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='managed_deployment_profile_not_canonical';END IF;
 PERFORM pg_advisory_xact_lock(7346371,11);
 LOCK TABLE supabase_migrations.schema_migrations IN SHARE MODE;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 -- Protect the table definition from concurrent DDL while rechecking. Other
 -- function/catalogue DDL must still be excluded by the migration operator.
 LOCK TABLE private.collect_deployment_identity IN SHARE ROW EXCLUSIVE MODE;
 PERFORM private._collect_managed_identity_preimage();
 SELECT * INTO old FROM private.collect_deployment_identity WHERE singleton;
 IF FOUND THEN
  IF old.operation_id=p_operation AND old.profile_sha256=p_sha256 AND old.profile_raw=p_profile THEN RETURN true;END IF;
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='deployment_identity_already_bound';
 END IF;
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND OR c.project_ref IS DISTINCT FROM 'rrlduytparvsjfmegalh'
  OR c.baseline_manifest_sha256 IS DISTINCT FROM 'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3'
  OR c.mode IS DISTINCT FROM 'fenced' OR c.operation_id IS DISTINCT FROM p_fence_operation
  OR c.epoch IS DISTINCT FROM p_fence_epoch OR c.source_sha256 IS DISTINCT FROM p_fence_source_sha256
  OR EXISTS(SELECT 1 FROM private.collect_fence_admissions
   WHERE state IS DISTINCT FROM 'settled' OR uncertain_dispatches IS DISTINCT FROM 0)
  OR (private._collect_fence_scheduler_status()->'blocking') IS DISTINCT FROM 'false'::jsonb
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_binding_requires_inactive_controller';END IF;
 INSERT INTO private.collect_deployment_identity(operation_id,profile_raw,profile_sha256) VALUES(p_operation,p_profile,p_sha256);
 RETURN true;
END;$fn$;

REVOKE ALL ON FUNCTION private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION private._collect_managed_identity_preimage() FROM PUBLIC;
-- Do not let custom default grants make the owner-only binding callable.
DO $acl$
DECLARE r record;
BEGIN
 FOR r IN SELECT DISTINCT a.grantee FROM pg_proc p,
  LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
  WHERE p.oid IN(to_regprocedure('private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)'),
   to_regprocedure('private._collect_managed_identity_preimage()'))
   AND a.grantee<>0 AND a.grantee<>p.proowner
 LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text) FROM %I',pg_get_userbyid(r.grantee));
  EXECUTE format('REVOKE ALL ON FUNCTION private._collect_managed_identity_preimage() FROM %I',pg_get_userbyid(r.grantee));
 END LOOP;
END;$acl$;
DO $effective_acl$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_roles r WHERE NOT r.rolsuper AND r.rolname<>'postgres'
   AND (has_function_privilege(r.oid,'private.collect_bind_managed_deployment(uuid,text,text,uuid,bigint,text)'::regprocedure,'EXECUTE')
    OR has_function_privilege(r.oid,'private._collect_managed_identity_preimage()'::regprocedure,'EXECUTE')))
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='managed_deployment_effective_privilege_preimage';END IF;
END;$effective_acl$;
COMMIT;
