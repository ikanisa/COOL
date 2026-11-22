-- Transaction-scoped witness for a managed PostgreSQL restart. Run only while
-- holding the release locks and restore the predecessor guard before commit.
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='8s';
DO $preflight$
BEGIN
 PERFORM private._collect_stopped_require_owner();
 PERFORM private._collect_fence_require_rc(true);
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND project_ref='rrlduytparvsjfmegalh')
  OR NOT EXISTS(SELECT 1 FROM private.collect_deployment_identity WHERE singleton
   AND profile_raw::jsonb @> '{"id":"collect-managed-production-cloud","environment":"production","mode":"managed","supabase_origin":"https://rrlduytparvsjfmegalh.supabase.co"}'::jsonb)
  OR NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid='private._collect_managed_retirement_guard()'::regprocedure
   AND pg_get_userbyid(proowner)='postgres' AND prosecdef AND provolatile='v'
   AND proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND proacl::text='{postgres=X/postgres}'
   AND encode(sha256(convert_to(prosrc,'UTF8')),'hex')='94bf7763acc6f46500e39a299122c0a94c53ea4364a755394e3c1c64b784bccd') THEN
  RAISE EXCEPTION 'managed_restart_retirement_predecessor_changed' USING ERRCODE='55000';
 END IF;
END;$preflight$;

CREATE OR REPLACE FUNCTION private._collect_managed_retirement_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;a private.collect_fence_admissions%ROWTYPE;
 f jsonb;
 gateway_profile text;
 restarted boolean:=coalesce(NEW.evidence->>'format'='collect.managed-executor-restart.v1',false);
 restarted_at timestamptz:=pg_postmaster_start_time();
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND OR c.mode<>(CASE WHEN restarted THEN 'open' ELSE 'quiescing' END)
  OR c.operation_id IS DISTINCT FROM NEW.fence_operation_id
  OR c.epoch<>NEW.epoch OR c.source_sha256<>NEW.source_sha256 OR c.project_ref<>NEW.project_ref
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND
   mod((pg_current_xact_id()::xid)::text::bigint-xmin::text::bigint+4294967296,4294967296) BETWEEN 1 AND 2147483647) THEN
  RAISE EXCEPTION 'managed_retirement_committed_quiesce_required' USING ERRCODE='55000';
 END IF;
 SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=NEW.admission_id FOR UPDATE;
 IF NOT FOUND OR a.state NOT IN('active','unresolved') OR a.epoch<>NEW.epoch
  OR a.source_sha256<>NEW.source_sha256 OR a.kind<>NEW.kind OR to_jsonb(a) IS DISTINCT FROM NEW.original_admission
  OR private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind) THEN
  RAISE EXCEPTION 'managed_retirement_admission_changed' USING ERRCODE='55000';
 END IF;
 IF restarted THEN
  -- PostgreSQL has discarded the old WORK leases. The hosted Edge worker's
  -- maximum lifetime has also passed since this particular admission began.
  -- Keep the underlying admission and all external effects unresolved.
  SELECT profile_sha256 INTO gateway_profile FROM private.collect_sms_fence_admissions WHERE admission_id=a.admission_id;
  IF a.state<>'active' OR a.kind<>'http_collect' OR NOT isfinite(a.created_at)
   OR NOT isfinite(restarted_at) OR a.created_at>=restarted_at OR restarted_at>clock_timestamp()
   OR clock_timestamp()<a.created_at+interval '500 seconds'
   OR (gateway_profile IS NOT NULL AND gateway_profile IS DISTINCT FROM
    (SELECT profile_sha256 FROM private.collect_deployment_identity WHERE singleton))
   OR NEW.maintenance_verified_at IS DISTINCT FROM restarted_at
   OR NEW.evidence IS DISTINCT FROM jsonb_build_object(
    'format','collect.managed-executor-restart.v1',
    'project',c.project_ref,'controlOperationId',c.operation_id,'sourceSha256',c.source_sha256,
    'admissionId',a.admission_id,'epoch',a.epoch,
    'gatewayProfileSha256',gateway_profile,
    'postmasterStartedAt',to_char(restarted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'maximumWorkerLifetimeSeconds',400,'externalEffectsSettled',false,
    'limitsSource','https://supabase.com/docs/guides/functions/limits')
   OR encode(sha256(convert_to(NEW.evidence::text,'UTF8')),'hex')<>NEW.evidence_sha256 THEN
   RAISE EXCEPTION 'managed_restart_retirement_evidence_invalid' USING ERRCODE='55000';
  END IF;
 ELSE
  IF NOT isfinite(NEW.maintenance_verified_at) OR NEW.maintenance_verified_at<c.changed_at
   OR NEW.maintenance_verified_at<a.created_at OR clock_timestamp()<NEW.maintenance_verified_at+interval '500 seconds'
   OR NEW.evidence->>'format' IS DISTINCT FROM 'collect.managed-executor-retirement.v1'
   OR NEW.evidence->>'project' IS DISTINCT FROM NEW.project_ref
   OR NEW.evidence->>'fenceOperationId' IS DISTINCT FROM NEW.fence_operation_id::text
   OR NEW.evidence->>'maximumWorkerLifetimeSeconds' IS DISTINCT FROM '400'
   OR NEW.evidence->>'externalEffectsSettled' IS DISTINCT FROM 'false'
   OR NEW.evidence->>'maintenanceVerifiedAt' IS DISTINCT FROM to_char(NEW.maintenance_verified_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
   OR NEW.evidence->>'limitsSource' IS DISTINCT FROM 'https://supabase.com/docs/guides/functions/limits'
   OR encode(sha256(convert_to(NEW.evidence::text,'UTF8')),'hex')<>NEW.evidence_sha256
   OR jsonb_typeof(NEW.evidence->'functions') IS DISTINCT FROM 'array'
   OR jsonb_array_length(NEW.evidence->'functions')<>3 THEN
   RAISE EXCEPTION 'managed_retirement_evidence_invalid' USING ERRCODE='55000';
  END IF;
  IF (SELECT array_agg(x->>'slug' ORDER BY x->>'slug') FROM jsonb_array_elements(NEW.evidence->'functions') x)
   IS DISTINCT FROM ARRAY['admin-api','collect-api','collect-jobs'] THEN
   RAISE EXCEPTION 'managed_retirement_functions_incomplete' USING ERRCODE='55000';
  END IF;
  FOR f IN SELECT value FROM jsonb_array_elements(NEW.evidence->'functions') LOOP
   IF jsonb_typeof(f) IS DISTINCT FROM 'object'
    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(f) k) IS DISTINCT FROM
      ARRAY['bundleSha256','previousBundleSha256','previousVersion','slug','status','version']
    OR EXISTS(SELECT 1 FROM jsonb_each(f) x WHERE jsonb_typeof(x.value) IS DISTINCT FROM 'string')
    OR f->>'status' IS DISTINCT FROM 'ACTIVE' OR f->>'version' !~ '^[1-9][0-9]{0,8}$'
    OR f->>'previousVersion' !~ '^[1-9][0-9]{0,8}$'
    OR (f->>'version')::int<=(f->>'previousVersion')::int
    OR f->>'bundleSha256' !~ '^[a-f0-9]{64}$' OR f->>'previousBundleSha256' !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'managed_retirement_function_evidence_invalid' USING ERRCODE='55000';
   END IF;
  END LOOP;
 END IF;
 IF EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id=NEW.operation_id)
  OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=NEW.operation_id)
  OR EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions WHERE recovery_operation_id=NEW.operation_id)
  OR NEW.operation_id=NEW.fence_operation_id OR (SELECT count(*) FROM private.collect_managed_executor_retirements)>=10000 THEN
  RAISE EXCEPTION 'managed_retirement_operation_conflict' USING ERRCODE='55000';
 END IF;
 NEW.recorded_at:=clock_timestamp();RETURN NEW;
END;$fn$;
