-- Immutable public identity of this self-hosted installation. Existing logical
-- project_ref values remain migration lineage, never a claim about its host.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SET LOCAL search_path=pg_catalog,pg_temp;
DO $$BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR current_setting('transaction_isolation')<>'read committed'
  OR to_regclass('private.collect_fence_control') IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='deployment_owner_install_required';
 END IF;
END$$;
CREATE TABLE private.collect_deployment_identity(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 operation_id uuid NOT NULL UNIQUE,
 profile_raw text NOT NULL CHECK(octet_length(profile_raw)<=8192),
 profile_sha256 text NOT NULL CHECK(profile_sha256 ~ '^[a-f0-9]{64}$'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_by text NOT NULL DEFAULT session_user::text,
 CHECK(encode(sha256(convert_to(profile_raw,'UTF8')),'hex')=profile_sha256)
);
ALTER TABLE private.collect_deployment_identity ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.collect_deployment_identity FROM PUBLIC,anon,authenticated,service_role,collect_runtime;
CREATE FUNCTION private._collect_deployment_immutable() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $$BEGIN
 RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='deployment_identity_is_immutable';
END$$;
CREATE TRIGGER collect_deployment_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON private.collect_deployment_identity
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_deployment_immutable();
ALTER TABLE private.collect_deployment_identity ENABLE ALWAYS TRIGGER collect_deployment_immutable;
CREATE FUNCTION private.collect_bind_deployment(p_operation uuid,p_profile text,p_sha256 text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE profile jsonb;old private.collect_deployment_identity%ROWTYPE;c private.collect_fence_control%ROWTYPE;
BEGIN
 IF session_user<>'postgres' OR current_user<>'postgres' OR coalesce(current_setting('role',true),'none') NOT IN('none','postgres')
  OR current_setting('transaction_isolation')<>'read committed' OR p_operation IS NULL OR p_sha256 IS NULL
  OR p_sha256 !~ '^[a-f0-9]{64}$' OR p_profile IS NULL OR octet_length(p_profile)>8192
  OR encode(sha256(convert_to(p_profile,'UTF8')),'hex')<>p_sha256 THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='deployment_binding_refused';END IF;
 profile:=p_profile::jsonb;
 IF jsonb_typeof(profile)<>'object' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(profile) k)
  IS DISTINCT FROM ARRAY['admin_origin','environment','format','google_callback_origin','id','member_api_origin','mode','public_origin','supabase_origin']::text[]
  OR EXISTS(SELECT 1 FROM jsonb_each(profile) e WHERE jsonb_typeof(e.value)<>'string')
  OR profile->>'format' IS DISTINCT FROM 'collect.deployment.v1' OR profile->>'mode' IS DISTINCT FROM 'self_hosted'
  OR profile->>'environment' NOT IN('production','qualification')
  OR profile->>'id' !~ '^[a-z][a-z0-9-]{0,62}$' THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='deployment_profile_invalid';END IF;
 IF p_profile IS DISTINCT FROM (SELECT '{'||string_agg(to_jsonb(e.key)::text||':'||e.value::text,',' ORDER BY e.key)||'}' FROM jsonb_each(profile) e)
  OR EXISTS(SELECT 1 FROM jsonb_each_text(profile) e WHERE e.key LIKE '%_origin' AND (
    e.value !~ '^https://[a-z0-9][a-z0-9.-]*[a-z0-9]$' OR e.value ~ '[.]([.]|$)' OR e.value !~ '[.][a-z][a-z0-9-]*$'))
  OR profile->>'google_callback_origin' NOT IN(profile->>'admin_origin',profile->>'member_api_origin') THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='deployment_profile_not_canonical';END IF;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO old FROM private.collect_deployment_identity WHERE singleton;
 IF FOUND THEN
  IF old.operation_id=p_operation AND old.profile_sha256=p_sha256 AND old.profile_raw=p_profile THEN RETURN true;END IF;
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='deployment_identity_already_bound';END IF;
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF FOUND AND (c.mode<>'fenced' OR EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE state<>'settled')) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='deployment_binding_requires_inactive_controller';END IF;
 INSERT INTO private.collect_deployment_identity(operation_id,profile_raw,profile_sha256) VALUES(p_operation,p_profile,p_sha256);
 RETURN true;
END$$;
CREATE FUNCTION private.collect_assert_deployment(p_sha256 text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$BEGIN
 IF p_sha256 IS NULL OR p_sha256 !~ '^[a-f0-9]{64}$' OR NOT EXISTS(
  SELECT 1 FROM private.collect_deployment_identity WHERE singleton AND profile_sha256=p_sha256) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='deployment_identity_mismatch';END IF;
 RETURN true;
END$$;
REVOKE ALL ON FUNCTION private._collect_deployment_immutable(),private.collect_bind_deployment(uuid,text,text),private.collect_assert_deployment(text) FROM PUBLIC,anon,authenticated,service_role,collect_runtime;
GRANT EXECUTE ON FUNCTION private.collect_assert_deployment(text) TO collect_runtime;
-- The SMS login receives no private/app schema privileges. This one read-only
-- wrapper binds its separate database connection to the same installation.
DO $gateway$ BEGIN
 IF to_regnamespace('collect_sms') IS NOT NULL AND EXISTS(SELECT 1 FROM pg_roles WHERE rolname='collect_sms_runtime') THEN
  EXECUTE 'CREATE FUNCTION collect_sms.assert_deployment_profile(p_sha256 text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $verify$ SELECT private.collect_assert_deployment(p_sha256) $verify$';
  EXECUTE 'REVOKE ALL ON FUNCTION collect_sms.assert_deployment_profile(text) FROM PUBLIC,anon,authenticated,service_role,collect_runtime';
  EXECUTE 'GRANT EXECUTE ON FUNCTION collect_sms.assert_deployment_profile(text) TO collect_sms_runtime';
 END IF;
END;$gateway$;
COMMIT;
