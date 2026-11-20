-- Supabase Edge executor retirement. This records a stopped executor, never
-- provider settlement. Original admission rows/counters remain unchanged.
-- Operator evidence must include readback of all three maintenance deployments.
-- The 500 second wait exceeds Supabase's published 400 second worker lifetime.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SELECT pg_advisory_xact_lock(7346371,11);
SELECT pg_advisory_xact_lock(7346371,1);
SELECT pg_advisory_xact_lock(7346371,2);
DO $preflight$ BEGIN
 PERFORM private._collect_stopped_require_owner();
 PERFORM private._collect_fence_require_rc(true);
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton
  AND project_ref='rrlduytparvsjfmegalh' AND mode IN('quiescing','fenced'))
  OR to_regclass('private.collect_managed_executor_retirements') IS NOT NULL THEN
  RAISE EXCEPTION 'managed_retirement_install_precondition' USING ERRCODE='55000';
 END IF;
END;$preflight$;

CREATE TABLE private.collect_managed_executor_retirements(
 operation_id uuid PRIMARY KEY,
 admission_id uuid NOT NULL UNIQUE REFERENCES private.collect_fence_admissions(admission_id),
 fence_operation_id uuid NOT NULL,
 epoch bigint NOT NULL,
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 kind text NOT NULL CHECK(kind IN('http_collect','http_admin','jobs')),
 project_ref text NOT NULL CHECK(project_ref='rrlduytparvsjfmegalh'),
 maintenance_verified_at timestamptz NOT NULL,
 evidence_sha256 text NOT NULL CHECK(evidence_sha256 ~ '^[a-f0-9]{64}$'),
 evidence jsonb NOT NULL CHECK(jsonb_typeof(evidence)='object' AND octet_length(evidence::text)<=16384),
 original_admission jsonb NOT NULL,
 retained_unknown_obligation_id uuid NOT NULL UNIQUE,
 external_effects_settled boolean NOT NULL DEFAULT false CHECK(NOT external_effects_settled),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.collect_managed_executor_retirements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.collect_managed_executor_retirements FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;

CREATE FUNCTION private._collect_managed_retirement_matches(p_id uuid,p_epoch bigint,p_source text,p_kind text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT EXISTS(SELECT 1 FROM private.collect_managed_executor_retirements
  WHERE admission_id=p_id AND epoch=p_epoch AND source_sha256=p_source AND kind=p_kind)
$fn$;

CREATE FUNCTION private._collect_managed_retirement_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;a private.collect_fence_admissions%ROWTYPE;f jsonb;
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND OR c.mode<>'quiescing' OR c.operation_id<>NEW.fence_operation_id
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
 IF EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id=NEW.operation_id)
  OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=NEW.operation_id)
  OR EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions WHERE recovery_operation_id=NEW.operation_id)
  OR NEW.operation_id=NEW.fence_operation_id OR (SELECT count(*) FROM private.collect_managed_executor_retirements)>=10000 THEN
  RAISE EXCEPTION 'managed_retirement_operation_conflict' USING ERRCODE='55000';
 END IF;
 NEW.recorded_at:=clock_timestamp();RETURN NEW;
END;$fn$;
CREATE TRIGGER managed_retirement_guard BEFORE INSERT ON private.collect_managed_executor_retirements
 FOR EACH ROW EXECUTE FUNCTION private._collect_managed_retirement_guard();
ALTER TABLE private.collect_managed_executor_retirements ENABLE ALWAYS TRIGGER managed_retirement_guard;
CREATE TRIGGER managed_retirement_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON private.collect_managed_executor_retirements
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.collect_managed_executor_retirements ENABLE ALWAYS TRIGGER managed_retirement_immutable;

CREATE FUNCTION private._collect_managed_no_late_close() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF private._collect_managed_retirement_matches(OLD.admission_id,OLD.epoch,OLD.source_sha256,OLD.kind) THEN
  RAISE EXCEPTION 'managed_retirement_admission_immutable' USING ERRCODE='55000';
 END IF;RETURN NEW;
END;$fn$;
CREATE TRIGGER managed_retirement_no_late_close BEFORE UPDATE ON private.collect_fence_admissions
 FOR EACH ROW EXECUTE FUNCTION private._collect_managed_no_late_close();
ALTER TABLE private.collect_fence_admissions ENABLE ALWAYS TRIGGER managed_retirement_no_late_close;

CREATE FUNCTION private.collect_fence_drain_managed_v1(p_operation uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND OR c.mode NOT IN('quiescing','fenced') OR c.operation_id IS DISTINCT FROM p_operation
  OR c.epoch IS DISTINCT FROM p_epoch OR c.source_sha256 IS DISTINCT FROM p_source
  OR c.project_ref<>'rrlduytparvsjfmegalh' THEN
  RAISE EXCEPTION 'managed_drain_control_changed' USING ERRCODE='55000';END IF;
 IF EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE a.state<>'settled'
  AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)
  AND NOT private._collect_managed_retirement_matches(a.admission_id,a.epoch,a.source_sha256,a.kind))
  OR private._collect_fence_scheduler_status()->'blocking' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION 'managed_drain_work_outstanding' USING ERRCODE='55000';END IF;
 IF c.mode='quiescing' THEN
  IF (private._collect_fence_resources()->>'operationReceipts')::bigint>=9998 THEN
   RAISE EXCEPTION 'managed_drain_capacity' USING ERRCODE='55000';END IF;
  UPDATE private.collect_fence_control SET mode='fenced',changed_at=clock_timestamp() WHERE singleton;
  INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES(p_operation,'drain',p_epoch,p_source);
 END IF;
 RETURN jsonb_build_object('mode','fenced','epoch',p_epoch,'managedExecutorsRetired',
  (SELECT count(*) FROM private.collect_managed_executor_retirements),'externalEffectsSettled',false);
END;$fn$;
REVOKE ALL ON FUNCTION private._collect_managed_retirement_matches(uuid,bigint,text,text),
 private._collect_managed_retirement_guard(),private._collect_managed_no_late_close(),
 private.collect_fence_drain_managed_v1(uuid,bigint,text) FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
COMMIT;
