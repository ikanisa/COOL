-- Owner-only evidence that an old local VM executor ceased. External effects
-- and original counters remain UNKNOWN; original admission/history is retained.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SET LOCAL search_path=pg_catalog,pg_temp;
DO $preflight$
DECLARE c private.collect_fence_control%ROWTYPE;r record;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR coalesce(current_setting('role',true),'none') NOT IN('none','postgres')
  OR current_setting('transaction_isolation')<>'read committed'
  OR current_setting('transaction_read_only')<>'off'
  OR current_setting('server_version_num')::integer/10000<>17
  OR to_regclass('private.collect_fence_local_stopped_admissions') IS NOT NULL
  OR to_regprocedure('private._collect_stopped_proof_total()') IS NOT NULL
  OR to_regprocedure('private.collect_fence_record_local_stopped_v1(uuid,uuid,uuid,bigint,text,text,text,uuid,text,jsonb)') IS NOT NULL THEN
  RAISE EXCEPTION 'collect_local_stopped_install_precondition' USING ERRCODE='55000';END IF;
 FOR r IN SELECT * FROM(VALUES
  ('private._collect_stopped_matches(uuid,bigint,text,text)','4cf157fc8d9ed501dbf90a0a185fd163da1d3966d39ca6c505dcd12700945ee2'),
  ('private._collect_stopped_insert()','13cec5add252c8ce5d37bd836005f2263b99e4edafe0d8bf8f7de19c9d13df83'),
  ('private._collect_stopped_no_operation_reuse()','35a47f3022674f10120c10c93a29d1149be2372470bd3cfe36cb7c068bf9889f'),
  ('private.collect_fence_owner_status_v3()','72bf348e0d02f8e2126c90883d85bae0f21a64ba66f7b7fc22e444176d5dd2d0'),
  ('private._collect_fence_resources()','f93d854e9ac07f626007a5c8d0a17514b4830ddf8cdf96b697b80a2d18f16df7'),
  ('private.collect_fence_release_v3(uuid,bigint,text)','8df7bd144e6eb2ac67f40f79417be6e352b7cdde1b25e2d8095c14607aee7bb6'),
  ('private._collect_fence_upgrade_insert()','7933bb289fbf02c5f91fbd33a478d38610ce7314d21eb44e06166190dcd02228'),
  ('private._retention_manifest_catalog_v2()','c127d2812e4c9984112777496bc7d31c9fc660fbf6e719554af121e1c8943d8c')
 )v(signature,body_sha256) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(r.signature)
   AND pg_get_userbyid(p.proowner)='postgres'
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.body_sha256
   AND p.proconfig @> ARRAY['search_path=pg_catalog, pg_temp']
   AND p.prosecdef=(r.signature<>'private._retention_manifest_catalog_v2()')) THEN
   RAISE EXCEPTION 'collect_local_stopped_function_preimage' USING ERRCODE='55000';END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN('private.collect_fence_control'::regclass,
  'private.collect_fence_admissions'::regclass,'private.collect_fence_stopped_admissions'::regclass)
  AND pg_get_userbyid(relowner)<>'postgres') THEN
  RAISE EXCEPTION 'collect_local_stopped_owner_preimage' USING ERRCODE='55000';END IF;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 PERFORM private._collect_fence_require_upgrade_locks();
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF FOUND THEN
  IF c.mode NOT IN('quiescing','fenced') OR c.project_ref<>'rrlduytparvsjfmegalh'
   OR c.baseline_manifest_sha256<>'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3'
   OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND NOT(
    xmin='2'::xid OR (xmin::text::bigint BETWEEN 3 AND 4294967295 AND
     mod((pg_current_xact_id()::xid)::text::bigint-xmin::text::bigint+4294967296,4294967296) BETWEEN 1 AND 2147483647))) THEN
   RAISE EXCEPTION 'collect_local_stopped_committed_install_required' USING ERRCODE='55000';END IF;
 ELSIF EXISTS(SELECT 1 FROM private.collect_fence_admissions) OR EXISTS(SELECT 1 FROM private.collect_fence_operations)
   OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades) OR EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions) THEN
  RAISE EXCEPTION 'collect_local_stopped_empty_install_required' USING ERRCODE='55000';
 END IF;
END;$preflight$;

CREATE TABLE private.collect_fence_local_stopped_admissions(
 recovery_operation_id uuid PRIMARY KEY,
 admission_id uuid NOT NULL UNIQUE REFERENCES private.collect_fence_admissions(admission_id),
 project_ref text NOT NULL CHECK(project_ref='rrlduytparvsjfmegalh'),
 source_sha256 text NOT NULL CHECK(source_sha256~'^[a-f0-9]{64}$'),
 epoch bigint NOT NULL CHECK(epoch BETWEEN 1 AND 9007199254740991),
 kind text NOT NULL CHECK(kind IN('http_collect','http_admin','jobs')),
 fence_operation_id uuid NOT NULL,
 evidence_bundle_sha256 text NOT NULL CHECK(evidence_bundle_sha256~'^[a-f0-9]{64}$'),
 executor_evidence jsonb NOT NULL CHECK(jsonb_typeof(executor_evidence)='object' AND octet_length(executor_evidence::text)<=8192),
 original_admission_snapshot jsonb NOT NULL,
 original_counters_unavailable boolean NOT NULL CHECK(original_counters_unavailable),
 recovered_external_dispatches integer CHECK(recovered_external_dispatches IS NULL),
 recovered_uncertain_dispatches integer CHECK(recovered_uncertain_dispatches IS NULL),
 retained_unknown_obligation_id uuid NOT NULL UNIQUE,
 obligation_evidence_sha256 text NOT NULL CHECK(obligation_evidence_sha256~'^[a-f0-9]{64}$'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_transaction text NOT NULL DEFAULT pg_current_xact_id()::text,
 recorded_by text NOT NULL DEFAULT session_user::text
);
ALTER TABLE private.collect_fence_local_stopped_admissions ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION private._collect_stopped_proof_total() RETURNS bigint
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT(SELECT count(*) FROM private.collect_fence_stopped_admissions)
  +(SELECT count(*) FROM private.collect_fence_local_stopped_admissions)
$fn$;

-- The shared guard precedes both protocol-specific INSERT triggers. Existing CF
-- role-absence checks remain unchanged; no role is renamed, dropped or invented.
CREATE FUNCTION private._collect_stopped_shared_proof_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 IF private._collect_stopped_proof_total()>=10000 THEN
  RAISE EXCEPTION 'collect_stopped_shared_capacity' USING ERRCODE='55000';END IF;
 IF NEW.recovery_operation_id=NEW.retained_unknown_obligation_id
  OR NEW.recovery_operation_id=NEW.admission_id OR NEW.retained_unknown_obligation_id=NEW.admission_id
  OR NEW.recovery_operation_id=NEW.fence_operation_id OR NEW.retained_unknown_obligation_id=NEW.fence_operation_id
  OR EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions s WHERE s.admission_id=NEW.admission_id
   OR s.admission_id IN(NEW.recovery_operation_id,NEW.retained_unknown_obligation_id)
   OR s.recovery_operation_id IN(NEW.admission_id,NEW.recovery_operation_id,NEW.retained_unknown_obligation_id)
   OR s.retained_unknown_obligation_id IN(NEW.admission_id,NEW.recovery_operation_id,NEW.retained_unknown_obligation_id))
  OR EXISTS(SELECT 1 FROM private.collect_fence_local_stopped_admissions s WHERE s.admission_id=NEW.admission_id
   OR s.admission_id IN(NEW.recovery_operation_id,NEW.retained_unknown_obligation_id)
   OR s.recovery_operation_id IN(NEW.admission_id,NEW.recovery_operation_id,NEW.retained_unknown_obligation_id)
   OR s.retained_unknown_obligation_id IN(NEW.admission_id,NEW.recovery_operation_id,NEW.retained_unknown_obligation_id))
  OR EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE admission_id IN(NEW.recovery_operation_id,NEW.retained_unknown_obligation_id))
  OR EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id IN(NEW.recovery_operation_id,NEW.retained_unknown_obligation_id))
  OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id IN(NEW.recovery_operation_id,NEW.retained_unknown_obligation_id)) THEN
  RAISE EXCEPTION 'collect_stopped_shared_identity_conflict' USING ERRCODE='55000';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER a_collect_stopped_shared_proof BEFORE INSERT ON private.collect_fence_stopped_admissions
 FOR EACH ROW EXECUTE FUNCTION private._collect_stopped_shared_proof_guard();
ALTER TABLE private.collect_fence_stopped_admissions ENABLE ALWAYS TRIGGER a_collect_stopped_shared_proof;
CREATE TRIGGER a_collect_stopped_shared_proof BEFORE INSERT ON private.collect_fence_local_stopped_admissions
 FOR EACH ROW EXECUTE FUNCTION private._collect_stopped_shared_proof_guard();
ALTER TABLE private.collect_fence_local_stopped_admissions ENABLE ALWAYS TRIGGER a_collect_stopped_shared_proof;

CREATE FUNCTION private._collect_local_executor_valid(e jsonb,created timestamptz) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE boot_at timestamptz;edge_at timestamptz;k text;
BEGIN
 IF e IS NULL OR jsonb_typeof(e)<>'object' OR octet_length(e::text)>8192 THEN RETURN false;END IF;
 IF (SELECT array_agg(key ORDER BY key) FROM jsonb_object_keys(e) key) IS DISTINCT FROM
    ARRAY['custodyReceiptSha256','databaseBootAt','databaseId','edgeContainerId','edgeStartedAt','format',
          'resumedReceiptSha256','runtimeVolumeUuid','stoppedBindingSha256','vmIdentitySha256']
  OR EXISTS(SELECT 1 FROM jsonb_each(e) p WHERE jsonb_typeof(p.value)<>'string')
  OR e->>'format'<>'collect.local-vm-executor-stopped.v1' THEN RETURN false;END IF;
 FOREACH k IN ARRAY ARRAY['vmIdentitySha256','databaseId','edgeContainerId','stoppedBindingSha256','custodyReceiptSha256','resumedReceiptSha256'] LOOP
  IF e->>k !~ '^[a-f0-9]{64}$' THEN RETURN false;END IF;
 END LOOP;
 IF e->>'runtimeVolumeUuid' !~* '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'
  OR e->>'databaseBootAt' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|\+00:00)$'
  OR e->>'edgeStartedAt' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,9})?(Z|\+00:00)$' THEN RETURN false;END IF;
 boot_at:=(e->>'databaseBootAt')::timestamptz;edge_at:=(e->>'edgeStartedAt')::timestamptz;
 RETURN isfinite(created) AND isfinite(boot_at) AND isfinite(edge_at)
  AND boot_at=pg_postmaster_start_time() AND created<boot_at AND created<edge_at
  AND edge_at<=clock_timestamp()+interval '5 seconds';
EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN RETURN false;
END;$fn$;

CREATE FUNCTION private._collect_local_stopped_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;a private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND OR c.mode<>'quiescing' OR c.operation_id<>NEW.fence_operation_id
  OR c.project_ref<>NEW.project_ref OR c.epoch<>NEW.epoch OR c.source_sha256<>NEW.source_sha256 THEN
  RAISE EXCEPTION 'collect_local_stopped_controller_conflict' USING ERRCODE='55000';END IF;
 IF EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND NOT(
  xmin='2'::xid OR (xmin::text::bigint BETWEEN 3 AND 4294967295 AND
   mod((pg_current_xact_id()::xid)::text::bigint-xmin::text::bigint+4294967296,4294967296) BETWEEN 1 AND 2147483647))) THEN
  RAISE EXCEPTION 'collect_local_stopped_committed_quiesce_required' USING ERRCODE='55000';END IF;
 SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=NEW.admission_id FOR UPDATE;
 IF NOT FOUND OR a.state NOT IN('active','unresolved') OR a.epoch<>NEW.epoch OR a.source_sha256<>NEW.source_sha256
  OR a.kind<>NEW.kind OR to_jsonb(a) IS DISTINCT FROM NEW.original_admission_snapshot THEN
  RAISE EXCEPTION 'collect_local_stopped_original_tuple_conflict' USING ERRCODE='55000';END IF;
 IF NEW.original_counters_unavailable IS DISTINCT FROM true OR NEW.recovered_external_dispatches IS NOT NULL
  OR NEW.recovered_uncertain_dispatches IS NOT NULL OR NOT private._collect_local_executor_valid(NEW.executor_evidence,a.created_at) THEN
  RAISE EXCEPTION 'collect_local_stopped_executor_unconfirmed' USING ERRCODE='55000';END IF;
 NEW.recorded_at:=clock_timestamp();NEW.recorded_transaction:=pg_current_xact_id()::text;NEW.recorded_by:=session_user::text;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_local_stopped_insert BEFORE INSERT ON private.collect_fence_local_stopped_admissions
 FOR EACH ROW EXECUTE FUNCTION private._collect_local_stopped_insert();
ALTER TABLE private.collect_fence_local_stopped_admissions ENABLE ALWAYS TRIGGER collect_local_stopped_insert;
CREATE TRIGGER collect_local_stopped_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON private.collect_fence_local_stopped_admissions
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.collect_fence_local_stopped_admissions ENABLE ALWAYS TRIGGER collect_local_stopped_immutable;

CREATE FUNCTION private.collect_fence_local_stopped_status_v1(p_recovery uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE s private.collect_fence_local_stopped_admissions%ROWTYPE;a private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM private._collect_stopped_require_owner();
 IF p_recovery IS NULL THEN RAISE EXCEPTION 'collect_local_stopped_invalid_operation' USING ERRCODE='22023';END IF;
 SELECT * INTO s FROM private.collect_fence_local_stopped_admissions WHERE recovery_operation_id=p_recovery;
 IF s.admission_id IS NOT NULL THEN SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=s.admission_id;END IF;
 RETURN jsonb_build_object('contractVersion',1,'found',s.admission_id IS NOT NULL,'recoveryOperationId',p_recovery,
  'localStoppedLifecycle',CASE WHEN s.admission_id IS NULL THEN NULL ELSE to_jsonb(s) END,
  'originalAdmission',CASE WHEN a.admission_id IS NULL THEN NULL ELSE to_jsonb(a) END,
  'originalCountersRecovered',false,'runtimeFinishRecovered',false,'unknownObligationSettled',false,
  'retainedUnquantifiedUnknownObligation',s.admission_id IS NOT NULL,
  'providerSettlement',false,'wholeSystemAcceptance',false,'sb29Satisfied',false);
END;$fn$;

CREATE FUNCTION private.collect_fence_record_local_stopped_v1(p_recovery uuid,p_fence uuid,p_id uuid,p_epoch bigint,
 p_source text,p_kind text,p_evidence text,p_obligation uuid,p_obligation_evidence text,p_executor jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 IF p_recovery IS NULL OR p_fence IS NULL OR p_id IS NULL OR p_epoch IS NULL OR p_source IS NULL
  OR p_kind IS NULL OR p_evidence IS NULL OR p_obligation IS NULL OR p_obligation_evidence IS NULL OR p_executor IS NULL THEN
  RAISE EXCEPTION 'collect_local_stopped_invalid_operation' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 PERFORM 1 FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=p_id FOR UPDATE;
 INSERT INTO private.collect_fence_local_stopped_admissions(recovery_operation_id,fence_operation_id,project_ref,
  admission_id,epoch,source_sha256,kind,evidence_bundle_sha256,executor_evidence,original_admission_snapshot,
  original_counters_unavailable,retained_unknown_obligation_id,obligation_evidence_sha256)
 VALUES(p_recovery,p_fence,'rrlduytparvsjfmegalh',p_id,p_epoch,p_source,p_kind,p_evidence,p_executor,to_jsonb(a),true,p_obligation,p_obligation_evidence);
 RETURN private.collect_fence_local_stopped_status_v1(p_recovery);
END;$fn$;

CREATE OR REPLACE FUNCTION private._collect_stopped_matches(p_id uuid,p_epoch bigint,p_source text,p_kind text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions s
  WHERE s.admission_id=p_id AND s.epoch=p_epoch AND s.source_sha256=p_source AND s.kind=p_kind
   AND s.project_ref='rrlduytparvsjfmegalh') OR EXISTS(SELECT 1 FROM private.collect_fence_local_stopped_admissions s
  WHERE s.admission_id=p_id AND s.epoch=p_epoch AND s.source_sha256=p_source AND s.kind=p_kind
   AND s.project_ref='rrlduytparvsjfmegalh')
$fn$;

CREATE OR REPLACE FUNCTION private._collect_fence_resources() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE total_count bigint;archived_count bigint;working_count bigint;active_count bigint;raw_active bigint;
 operation_count bigint;proof_count bigint;stopped_count bigint;
BEGIN
 SELECT t.retained_total,t.archived_total,w.working_count,w.raw_active,w.active_count,w.stopped_count
 INTO STRICT total_count,archived_count,working_count,raw_active,active_count,stopped_count
 FROM private.collect_fence_admission_totals t CROSS JOIN LATERAL(
 SELECT count(*) AS working_count,count(*) FILTER(WHERE a.state IN('active','unresolved')) AS raw_active,
  count(*) FILTER(WHERE a.state IN('active','unresolved') AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)) AS active_count,
  count(*) FILTER(WHERE private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)) AS stopped_count
 FROM private.collect_fence_working_admissions w JOIN private.collect_fence_admissions a USING(admission_id)) w WHERE t.singleton;
 IF total_count-archived_count<>working_count THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_archive_index_conflict';END IF;
 SELECT (SELECT count(*) FROM private.collect_fence_operations)+(SELECT count(*) FROM private.collect_fence_source_upgrades) INTO operation_count;
 SELECT count(*) INTO proof_count FROM private.collect_fence_scheduler_lifecycle;
 RETURN jsonb_build_object('admissionBudgetVersion',4,'retainedAdmissionLimit',NULL,'workingAdmissionLimit',100000,'activeWorkLimit',8,
  'operationReceiptLimit',10000,'schedulerLifecycleProofLimit',10000,
  'retainedAdmissions',total_count,'archivedAdmissions',archived_count,'workingAdmissions',working_count,
  'activeAndUnresolvedAdmissions',active_count,'rawActiveAndUnresolvedAdmissions',raw_active,
  'stoppedLocalAdmissions',stopped_count,'retainedUnquantifiedUnknownObligations',stopped_count,
  'stoppedLifecycleProofs',private._collect_stopped_proof_total(),'stoppedProofLimit',10000,
  'operationReceipts',operation_count,'schedulerLifecycleProofs',proof_count,
  'settledRetentionEnabled',true,'archiveMode','immutable_in_place','originalRowsDeleted',false,
  'operationReceiptSaturated',operation_count>=10000,
  'capacityBlocked',working_count>=100000 OR active_count>=8 OR operation_count>=9998 OR proof_count>=10000);
END;$fn$;

CREATE OR REPLACE FUNCTION private.collect_fence_owner_status_v3() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old jsonb;raw_active bigint;raw_unresolved bigint;effective_active bigint;effective_unresolved bigint;stopped bigint;
BEGIN
 PERFORM private._collect_stopped_require_owner();old:=private.collect_fence_owner_status();
 SELECT count(*) FILTER(WHERE a.state='active'),count(*) FILTER(WHERE a.state='unresolved'),
  count(*) FILTER(WHERE a.state='active' AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)),
  count(*) FILTER(WHERE a.state='unresolved' AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)),
  count(*) FILTER(WHERE a.state IN('active','unresolved') AND private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind))
 INTO raw_active,raw_unresolved,effective_active,effective_unresolved,stopped FROM private.collect_fence_admissions a;
 -- Legacy fields retain RAW counts and legacy applicationFenceComplete stays
 -- conservative. New consumers must deliberately inspect the explicit fields.
 RETURN old||jsonb_build_object('contractVersion',3,'rawActiveAdmissions',raw_active,'rawUnresolvedAdmissions',raw_unresolved,
  'effectiveActiveAdmissions',effective_active,'effectiveUnresolvedAdmissions',effective_unresolved,
  'stoppedLocalAdmissions',stopped,'retainedUnquantifiedUnknownObligations',stopped,
  'localLeaseDrainComplete',(old->>'mode')='fenced' AND effective_active=0 AND effective_unresolved=0 AND old->'schedulerStatus'->'blocking'='false'::jsonb,
  'originalCountersRecovered',false,'runtimeFinishRecovered',false,'unknownObligationSettled',false,
  'wholeSystemAcceptance',false,'providerSettlement',false,'sb29Satisfied',false,
  'stoppedLifecycleProofs',private._collect_stopped_proof_total(),
  'stoppedCfProofs',(SELECT count(*) FROM private.collect_fence_stopped_admissions),
  'stoppedLocalVmProofs',(SELECT count(*) FROM private.collect_fence_local_stopped_admissions),'stoppedProofLimit',10000);
END;$fn$;

CREATE OR REPLACE FUNCTION private._collect_stopped_no_operation_reuse() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions WHERE admission_id=NEW.operation_id OR recovery_operation_id=NEW.operation_id OR retained_unknown_obligation_id=NEW.operation_id)
  OR EXISTS(SELECT 1 FROM private.collect_fence_local_stopped_admissions WHERE admission_id=NEW.operation_id OR recovery_operation_id=NEW.operation_id OR retained_unknown_obligation_id=NEW.operation_id) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_operation_conflict';END IF;
 RETURN NEW;
END;$fn$;

CREATE OR REPLACE FUNCTION private.collect_fence_release_v3(p_operation uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;scheduler jsonb;
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 IF p_operation IS NULL OR p_epoch IS NULL OR p_source IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_control';END IF;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 IF EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=c.operation_id AND recorded_transaction=pg_current_xact_id()::text) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 scheduler:=private._collect_fence_scheduler_status();
 IF c.mode<>'fenced' OR c.epoch<>p_epoch OR c.epoch>=9007199254740991 OR c.source_sha256<>p_source
  OR EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE a.state IN('active','unresolved')
   AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind))
  OR EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id=p_operation)
  OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=p_operation)
  OR EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions WHERE admission_id=p_operation OR recovery_operation_id=p_operation OR retained_unknown_obligation_id=p_operation)
  OR EXISTS(SELECT 1 FROM private.collect_fence_local_stopped_admissions WHERE admission_id=p_operation OR recovery_operation_id=p_operation OR retained_unknown_obligation_id=p_operation)
  OR scheduler->'blocking' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 IF (private._collect_fence_resources()->>'operationReceipts')::bigint+1>=9998
  OR(private._collect_fence_resources()->>'operationReceipts')::bigint+3>10000
  OR(private._collect_fence_resources()->>'workingAdmissions')::bigint>=100000
  OR(SELECT count(*) FROM private.collect_fence_scheduler_lifecycle)>=10000
  OR private._collect_stopped_proof_total()>=10000 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 UPDATE private.collect_fence_control SET mode='open',epoch=epoch+1,operation_id=p_operation,changed_at=clock_timestamp() WHERE singleton;
 INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES(p_operation,'release',p_epoch+1,p_source);
 RETURN private.collect_fence_owner_status_v3();
END;$fn$;

CREATE OR REPLACE FUNCTION private._collect_fence_upgrade_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;s jsonb;r jsonb;receipt_count bigint;
BEGIN
 PERFORM private._collect_fence_require_upgrade_locks();
 IF NEW.lifecycle_protocol_version=3 THEN PERFORM private._collect_stopped_require_owner();
 ELSIF NEW.lifecycle_protocol_version<>2 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_protocol_conflict';END IF;
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 s:=private._collect_fence_scheduler_status();r:=private._collect_fence_resources();
 -- SQL10's activation source is immutable. Until a separately qualified
 -- dependent-lineage protocol exists, never strand a previously bound channel.
 IF NOT EXISTS(SELECT 1 FROM private.member_realtime_control WHERE singleton AND source_sha256 IS NULL AND NOT enabled) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_source_dependency_blocked';END IF;
 receipt_count:=(r->>'operationReceipts')::bigint;
 IF c.mode<>'fenced' OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND NOT(
    -- A released SAVEPOINT child has a different xmin from the top XID.
    -- Accept only a normal xmin strictly preceding this top XID under the
    -- native half-range ordering, or FrozenXID2. No clock/status inference.
    xmin='2'::xid OR (xmin::text::bigint BETWEEN 3 AND 4294967295 AND
     mod((pg_current_xact_id()::xid)::text::bigint-xmin::text::bigint+4294967296,4294967296)
      BETWEEN 1 AND 2147483647)))
  OR NOT(EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id=c.operation_id AND action='drain' AND epoch=c.epoch AND source_sha256=c.source_sha256)
   OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=c.operation_id AND new_epoch=c.epoch AND new_source_sha256=c.source_sha256))
  OR c.operation_id<>NEW.prior_fence_operation_id OR c.epoch<>NEW.old_epoch
  OR c.source_sha256<>NEW.old_source_sha256 OR c.project_ref<>NEW.project_ref
  OR c.baseline_manifest_sha256<>NEW.baseline_manifest_sha256 OR to_jsonb(c)<>NEW.prior_control_snapshot
  OR NEW.new_epoch<>c.epoch+1 OR NEW.new_source_sha256=c.source_sha256
  OR NEW.recorded_transaction<>pg_current_xact_id()::text OR NEW.recorded_by<>session_user::text
  OR EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE a.state IN('active','unresolved')
   AND (NEW.lifecycle_protocol_version=2 OR NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)))
  OR EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions WHERE admission_id=NEW.operation_id OR recovery_operation_id=NEW.operation_id OR retained_unknown_obligation_id=NEW.operation_id)
  OR EXISTS(SELECT 1 FROM private.collect_fence_local_stopped_admissions WHERE admission_id=NEW.operation_id OR recovery_operation_id=NEW.operation_id OR retained_unknown_obligation_id=NEW.operation_id)
  OR EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id=NEW.operation_id)
  OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=NEW.operation_id
       OR old_source_sha256=NEW.new_source_sha256 OR new_source_sha256=NEW.new_source_sha256)
  OR s->'checked' IS DISTINCT FROM 'true'::jsonb OR s->'coverageVerified' IS DISTINCT FROM 'true'::jsonb
  OR s->'blocking' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 -- Upgrade + separate release must fit and leave the existing OPEN admission
 -- threshold/future emergency begin+drain reserve. No history is pruned.
 IF c.epoch>9007199254740989 OR receipt_count+2>=9998 OR receipt_count+4>10000
  OR (r->>'workingAdmissions')::bigint>=100000 OR (r->>'schedulerLifecycleProofs')::bigint>=10000
  OR private._collect_stopped_proof_total()>=10000 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 RETURN NEW;
END;$fn$;

-- Preserve the exact current catalog payload and add this one blocked shared
-- class. Existing manifests/policy hashes remain immutable and become stale.
DO $catalog$
DECLARE body text;next_body text;
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure;
 body:=regexp_replace(body,';\s*$','');
 next_body:='SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||''{"name":"private:collect_fence_local_stopped_admissions","relation":"private.collect_fence_local_stopped_admissions","scope":"shared_fence","purpose":"Immutable owner proof of stopped local work, original admission snapshot and unquantified unknown obligation; blocked shared operational copy, no recovered counters, provider settlement or subject-empty assertion","blocked":true}''::jsonb) FROM ('||body||') prior(base)';
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
END;$catalog$;

DO $acl$
DECLARE r record;p record;
BEGIN
 REVOKE ALL ON TABLE private.collect_fence_local_stopped_admissions FROM PUBLIC;
 FOR r IN SELECT DISTINCT x.grantee FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x
  WHERE c.oid='private.collect_fence_local_stopped_admissions'::regclass AND x.grantee<>c.relowner AND x.grantee<>0 LOOP
  EXECUTE format('REVOKE ALL ON TABLE private.collect_fence_local_stopped_admissions FROM %I',pg_get_userbyid(r.grantee));
 END LOOP;
 FOR r IN SELECT rolname FROM pg_roles WHERE rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer','collect_edge','collect_sms_edge','collect_sms_runtime') LOOP
  EXECUTE format('REVOKE ALL ON TABLE private.collect_fence_local_stopped_admissions FROM %I',r.rolname);
 END LOOP;
 FOR p IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='private'::regnamespace
  AND proname IN('_collect_stopped_proof_total','_collect_stopped_shared_proof_guard','_collect_local_executor_valid',
   '_collect_local_stopped_insert','collect_fence_local_stopped_status_v1','collect_fence_record_local_stopped_v1') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',p.signature);
  FOR r IN SELECT rolname FROM pg_roles WHERE rolname<>'postgres' LOOP
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',p.signature,r.rolname);
  END LOOP;
 END LOOP;
END;$acl$;
COMMIT;
