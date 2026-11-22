-- Forward Cloud compatibility: include retained managed executor tombstones in
-- the existing lifecycle, then allow only this project's canonical profile.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(7346371,11);
SELECT pg_advisory_xact_lock(7346371,1);
SELECT pg_advisory_xact_lock(7346371,2);
DO $preflight$ BEGIN
 PERFORM private._collect_stopped_require_owner();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced'
  AND project_ref='rrlduytparvsjfmegalh')
  OR to_regclass('private.collect_managed_executor_retirements') IS NULL
  OR to_regclass('private.collect_fence_local_stopped_admissions') IS NULL
  OR EXISTS(SELECT 1 FROM private.collect_deployment_identity) THEN
  RAISE EXCEPTION 'cloud_binding_precondition' USING ERRCODE='55000';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure('private._collect_stopped_matches(uuid,bigint,text,text)')) IS DISTINCT FROM '70b91013ab3c1a6bca0343ec825db292e00838bae803a8766500cacfeb78c4a7' THEN RAISE EXCEPTION 'cloud_binding_function_preimage' USING ERRCODE='55000';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure('private._collect_stopped_proof_total()')) IS DISTINCT FROM '16095c3e3b283500fe5afd79a81b8875dfd2d72c6190f4f91c7c4f9997cb9dd1' THEN RAISE EXCEPTION 'cloud_binding_function_preimage' USING ERRCODE='55000';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid=to_regprocedure('private.collect_bind_deployment(uuid,text,text)')) IS DISTINCT FROM '43a5857fdee8adb0def82775328210c9f08403d988e7655ef9281609f22c4ec5' THEN RAISE EXCEPTION 'cloud_binding_function_preimage' USING ERRCODE='55000';END IF;
END;$preflight$;

CREATE OR REPLACE FUNCTION private._collect_stopped_matches(p_id uuid,p_epoch bigint,p_source text,p_kind text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions s
  WHERE s.admission_id=p_id AND s.epoch=p_epoch AND s.source_sha256=p_source AND s.kind=p_kind
   AND s.project_ref='rrlduytparvsjfmegalh') OR EXISTS(SELECT 1 FROM private.collect_fence_local_stopped_admissions s
  WHERE s.admission_id=p_id AND s.epoch=p_epoch AND s.source_sha256=p_source AND s.kind=p_kind
   AND s.project_ref='rrlduytparvsjfmegalh')
  OR private._collect_managed_retirement_matches(p_id,p_epoch,p_source,p_kind)
$fn$;
CREATE OR REPLACE FUNCTION private._collect_stopped_proof_total() RETURNS bigint
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT(SELECT count(*) FROM private.collect_fence_stopped_admissions)
  +(SELECT count(*) FROM private.collect_fence_local_stopped_admissions)
  +(SELECT count(*) FROM private.collect_managed_executor_retirements)
$fn$;

CREATE OR REPLACE FUNCTION private.collect_bind_deployment(p_operation uuid,p_profile text,p_sha256 text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old private.collect_deployment_identity%ROWTYPE;c private.collect_fence_control%ROWTYPE;
 expected text := '{"admin_origin":"https://rrlduytparvsjfmegalh.supabase.co","environment":"production","format":"collect.deployment.v1","google_callback_origin":"https://rrlduytparvsjfmegalh.supabase.co","id":"collect-managed-production-cloud","member_api_origin":"https://rrlduytparvsjfmegalh.supabase.co","mode":"managed","public_origin":"https://rrlduytparvsjfmegalh.supabase.co","supabase_origin":"https://rrlduytparvsjfmegalh.supabase.co"}';
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 IF p_operation IS NULL OR p_profile IS DISTINCT FROM expected
  OR p_sha256 IS DISTINCT FROM encode(sha256(convert_to(expected,'UTF8')),'hex') THEN
  RAISE EXCEPTION 'cloud_deployment_profile_refused' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(7346371,11);
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 LOCK TABLE private.collect_deployment_identity IN SHARE ROW EXCLUSIVE MODE;
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND OR c.mode<>'fenced' OR c.project_ref<>'rrlduytparvsjfmegalh'
  OR EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE state<>'settled'
   AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind))
  OR private._collect_fence_scheduler_status()->'blocking' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION 'cloud_deployment_requires_inactive_controller' USING ERRCODE='55000';END IF;
 SELECT * INTO old FROM private.collect_deployment_identity WHERE singleton;
 IF FOUND THEN
  IF old.operation_id=p_operation AND old.profile_sha256=p_sha256 AND old.profile_raw=p_profile THEN RETURN true;END IF;
  RAISE EXCEPTION 'deployment_identity_already_bound' USING ERRCODE='55000';END IF;
 INSERT INTO private.collect_deployment_identity(operation_id,profile_raw,profile_sha256) VALUES(p_operation,p_profile,p_sha256);
 RETURN true;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_bind_deployment(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
COMMIT;
