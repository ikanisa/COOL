-- Owner-only local lifecycle evidence. This does not settle external effects.
-- Historical admissions/counters and Storage/provider journals remain immutable.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SET LOCAL search_path=pg_catalog,pg_temp;
DO $preflight$
DECLARE c private.collect_fence_control%ROWTYPE;
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR coalesce(current_setting('role',true),'none') NOT IN('none','postgres')
  OR current_setting('transaction_isolation')<>'read committed'
  OR current_setting('transaction_read_only')<>'off'
  OR current_setting('server_version_num')::integer/10000<>17
  OR to_regclass('private.collect_fence_source_upgrades') IS NULL
  OR to_regclass('private.collect_fence_stopped_admissions') IS NOT NULL THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_install_precondition';END IF;
 IF (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='private._collect_fence_admission(uuid,bigint,text)'::regprocedure)
    IS DISTINCT FROM '2a67d504328792c5d8f786bf5fab4a8b13c487090619147b821b9f49c7e902dd'
  OR (SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') FROM pg_proc WHERE oid='private._collect_fence_upgrade_insert()'::regprocedure)
    IS DISTINCT FROM '2a55fc56450ea5d0a6deac69dd2c98f42ca5af239a1450d424c5130583f34213' THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_install_body_preimage';END IF;
 IF (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid='private.collect_fence_control'::regclass) IS DISTINCT FROM 'postgres'
  OR EXISTS(SELECT 1 FROM pg_proc WHERE oid IN('private._collect_fence_admission(uuid,bigint,text)'::regprocedure,'private._collect_fence_upgrade_insert()'::regprocedure)
   AND (pg_get_userbyid(proowner)<>'postgres' OR NOT prosecdef)) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_install_owner_preimage';END IF;
 -- Installation is itself one owner maintenance operation. An orphan cannot
 -- satisfy the old drain; committed QUIESCING plus actual exclusive leases is
 -- sufficient to install the missing protocol without editing that orphan.
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 PERFORM private._collect_fence_require_upgrade_locks();
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF FOUND THEN
  IF c.mode NOT IN('quiescing','fenced') OR c.project_ref<>'rrlduytparvsjfmegalh'
   OR c.baseline_manifest_sha256<>'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3'
   OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND NOT(
     xmin='2'::xid OR (xmin::text::bigint BETWEEN 3 AND 4294967295 AND
      mod((pg_current_xact_id()::xid)::text::bigint-xmin::text::bigint+4294967296,4294967296) BETWEEN 1 AND 2147483647))) THEN
   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_install_committed_quiesce_required';END IF;
 ELSIF EXISTS(SELECT 1 FROM private.collect_fence_admissions) OR EXISTS(SELECT 1 FROM private.collect_fence_operations) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_install_controller_missing';END IF;
END;$preflight$;

CREATE TABLE private.collect_fence_stopped_admissions(
 recovery_operation_id uuid PRIMARY KEY,
 admission_id uuid NOT NULL UNIQUE REFERENCES private.collect_fence_admissions(admission_id),
 project_ref text NOT NULL CHECK(project_ref='rrlduytparvsjfmegalh'),
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 epoch bigint NOT NULL CHECK(epoch BETWEEN 1 AND 9007199254740991),
 kind text NOT NULL CHECK(kind IN('http_collect','http_admin','jobs')),
 fence_operation_id uuid NOT NULL,
 evidence_bundle_sha256 text NOT NULL CHECK(evidence_bundle_sha256 ~ '^[a-f0-9]{64}$'),
 original_role_oid oid NOT NULL CHECK(original_role_oid<>0),
 original_role_name text NOT NULL CHECK(original_role_name ~ '^collect_cf_preserve_[0-9]{8}$'),
 role_absence_evidence_sha256 text NOT NULL CHECK(role_absence_evidence_sha256 ~ '^[a-f0-9]{64}$'),
 original_counters_unavailable boolean NOT NULL CHECK(original_counters_unavailable),
 recovered_external_dispatches integer CHECK(recovered_external_dispatches IS NULL),
 recovered_uncertain_dispatches integer CHECK(recovered_uncertain_dispatches IS NULL),
 retained_unknown_obligation_id uuid NOT NULL UNIQUE,
 obligation_evidence_sha256 text NOT NULL CHECK(obligation_evidence_sha256 ~ '^[a-f0-9]{64}$'),
 original_admission_snapshot jsonb NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_transaction text NOT NULL DEFAULT pg_current_xact_id()::text,
 recorded_by text NOT NULL DEFAULT session_user::text
);
ALTER TABLE private.collect_fence_stopped_admissions ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION private._collect_stopped_require_owner() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR coalesce(current_setting('role',true),'none') NOT IN('none','postgres')
  OR (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid='private.collect_fence_control'::regclass) IS DISTINCT FROM 'postgres' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='collect_stopped_owner_required';END IF;
END;$fn$;

CREATE FUNCTION private._collect_stopped_matches(p_id uuid,p_epoch bigint,p_source text,p_kind text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions s
  WHERE s.admission_id=p_id AND s.epoch=p_epoch AND s.source_sha256=p_source AND s.kind=p_kind
   AND s.project_ref='rrlduytparvsjfmegalh')
$fn$;

CREATE FUNCTION private._collect_stopped_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;a private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 -- Never wait for a native lease while holding the control/admission row lock.
 -- Exact established global order: WORK exclusive, then WRITE exclusive.
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND OR c.mode NOT IN('quiescing','fenced') OR c.operation_id<>NEW.fence_operation_id
  OR c.project_ref<>NEW.project_ref OR c.epoch<>NEW.epoch OR c.source_sha256<>NEW.source_sha256 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_controller_conflict';END IF;
 -- A short admission closure must commit independently before this owner
 -- lifecycle proof. xmin ordering also rejects a released SAVEPOINT child of
 -- the current top transaction; a matching mode/time alone is insufficient.
 IF EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND NOT(
   xmin='2'::xid OR (xmin::text::bigint BETWEEN 3 AND 4294967295 AND
    mod((pg_current_xact_id()::xid)::text::bigint-xmin::text::bigint+4294967296,4294967296) BETWEEN 1 AND 2147483647))) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_committed_quiesce_required';END IF;
 SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=NEW.admission_id FOR UPDATE;
 IF NOT FOUND OR a.state NOT IN('active','unresolved') OR a.epoch<>NEW.epoch
  OR a.source_sha256<>NEW.source_sha256 OR a.kind<>NEW.kind
  OR to_jsonb(a) IS DISTINCT FROM NEW.original_admission_snapshot THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_original_tuple_conflict';END IF;
 -- Absence is verified now by BOTH original OID and original name. OID reuse,
 -- replacement by same-name login, and surviving original-OID backends refuse.
 PERFORM pg_stat_clear_snapshot();
 IF EXISTS(SELECT 1 FROM pg_roles WHERE oid=NEW.original_role_oid OR rolname=NEW.original_role_name)
  OR EXISTS(SELECT 1 FROM pg_stat_activity WHERE usesysid=NEW.original_role_oid)
  OR EXISTS(SELECT 1 FROM pg_shdepend WHERE refclassid='pg_authid'::regclass AND refobjid=NEW.original_role_oid AND deptype IN('a','o')) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_role_not_absent';END IF;
 IF EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id=NEW.recovery_operation_id)
  OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=NEW.recovery_operation_id)
  OR NEW.recovery_operation_id=NEW.fence_operation_id OR (SELECT count(*) FROM private.collect_fence_stopped_admissions)>=10000 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_operation_conflict';END IF;
 NEW.recorded_at:=clock_timestamp();NEW.recorded_transaction:=pg_current_xact_id()::text;NEW.recorded_by:=session_user::text;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_stopped_insert BEFORE INSERT ON private.collect_fence_stopped_admissions
 FOR EACH ROW EXECUTE FUNCTION private._collect_stopped_insert();
ALTER TABLE private.collect_fence_stopped_admissions ENABLE ALWAYS TRIGGER collect_stopped_insert;
CREATE TRIGGER collect_stopped_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON private.collect_fence_stopped_admissions
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.collect_fence_stopped_admissions ENABLE ALWAYS TRIGGER collect_stopped_immutable;

-- This independent trigger also covers the existing runtime close function and
-- direct owner UPDATE. The original admission is never synthetically settled.
CREATE FUNCTION private._collect_stopped_no_late_close() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF private._collect_stopped_matches(OLD.admission_id,OLD.epoch,OLD.source_sha256,OLD.kind) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_admission_immutable';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_stopped_no_late_close BEFORE UPDATE ON private.collect_fence_admissions
 FOR EACH ROW EXECUTE FUNCTION private._collect_stopped_no_late_close();
ALTER TABLE private.collect_fence_admissions ENABLE ALWAYS TRIGGER collect_stopped_no_late_close;

CREATE FUNCTION private._collect_stopped_no_operation_reuse() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions WHERE recovery_operation_id=NEW.operation_id) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_stopped_operation_conflict';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_stopped_no_operation_reuse BEFORE INSERT ON private.collect_fence_operations
 FOR EACH ROW EXECUTE FUNCTION private._collect_stopped_no_operation_reuse();
ALTER TABLE private.collect_fence_operations ENABLE ALWAYS TRIGGER collect_stopped_no_operation_reuse;

CREATE OR REPLACE FUNCTION private._collect_fence_admission(p_id uuid,p_epoch bigint,p_source text)
RETURNS private.collect_fence_admissions
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;a private.collect_fence_admissions%ROWTYPE;
BEGIN
 IF p_id IS NULL OR p_epoch IS NULL OR p_source IS NULL OR p_source !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_admission';END IF;
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 IF c.mode NOT IN('open','quiescing') THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_closed';END IF;
 SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=p_id;
 IF NOT FOUND OR a.state<>'active' OR a.epoch<>p_epoch OR c.epoch<>p_epoch OR a.source_sha256<>p_source OR c.source_sha256<>p_source
  OR private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 RETURN a;
END;$fn$;

CREATE FUNCTION private.collect_fence_stopped_admission_status_v3(p_recovery uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE s private.collect_fence_stopped_admissions%ROWTYPE;a private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM private._collect_stopped_require_owner();
 IF p_recovery IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_stopped_invalid_operation';END IF;
 SELECT * INTO s FROM private.collect_fence_stopped_admissions WHERE recovery_operation_id=p_recovery;
 IF s.admission_id IS NOT NULL THEN SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=s.admission_id;END IF;
 RETURN jsonb_build_object('contractVersion',3,'found',s.admission_id IS NOT NULL,'recoveryOperationId',p_recovery,
  'stoppedLifecycle',CASE WHEN s.admission_id IS NULL THEN NULL ELSE to_jsonb(s) END,
  'originalAdmission',CASE WHEN a.admission_id IS NULL THEN NULL ELSE to_jsonb(a) END,
  'runtimeFinishRecovered',false,'originalCountersRecovered',false,'unknownObligationSettled',false,
  'providerSettlement',false,'wholeSystemAcceptance',false,'sb29Satisfied',false);
END;$fn$;

CREATE FUNCTION private.collect_fence_record_stopped_admission_v3(p_recovery uuid,p_fence uuid,p_project text,
 p_id uuid,p_epoch bigint,p_source text,p_kind text,p_evidence text,p_role_oid oid,p_role_name text,
 p_absence text,p_counters_unavailable boolean,p_obligation uuid,p_obligation_evidence text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 IF p_recovery IS NULL OR p_fence IS NULL OR p_id IS NULL OR p_obligation IS NULL
  OR p_counters_unavailable IS DISTINCT FROM true THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_stopped_invalid_operation';END IF;
 -- Locks precede reading the row, so the captured raw snapshot is current.
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=p_id FOR UPDATE;
 INSERT INTO private.collect_fence_stopped_admissions(recovery_operation_id,fence_operation_id,project_ref,
  admission_id,epoch,source_sha256,kind,evidence_bundle_sha256,original_role_oid,original_role_name,
  role_absence_evidence_sha256,original_counters_unavailable,retained_unknown_obligation_id,obligation_evidence_sha256,original_admission_snapshot)
 VALUES(p_recovery,p_fence,p_project,p_id,p_epoch,p_source,p_kind,p_evidence,p_role_oid,p_role_name,
  p_absence,p_counters_unavailable,p_obligation,p_obligation_evidence,to_jsonb(a));
 RETURN private.collect_fence_stopped_admission_status_v3(p_recovery);
END;$fn$;

CREATE FUNCTION private.collect_fence_owner_status_v3() RETURNS jsonb
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
  'stoppedLifecycleProofs',(SELECT count(*) FROM private.collect_fence_stopped_admissions));
END;$fn$;

CREATE FUNCTION private.collect_fence_drain_v3(p_operation uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;scheduler jsonb;
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 IF p_operation IS NULL OR p_epoch IS NULL OR p_source IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_control';END IF;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND OR c.mode NOT IN('quiescing','fenced') OR c.operation_id<>p_operation OR c.epoch<>p_epoch OR c.source_sha256<>p_source THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 IF c.mode='fenced' THEN RETURN private.collect_fence_owner_status_v3();END IF;
 scheduler:=private._collect_fence_scheduler_status();
 IF EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE a.state IN('active','unresolved')
  AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind))
  OR scheduler->'blocking' IS DISTINCT FROM 'false'::jsonb THEN RETURN private.collect_fence_owner_status_v3();END IF;
 UPDATE private.collect_fence_control SET mode='fenced',changed_at=clock_timestamp() WHERE singleton;
 IF (private._collect_fence_resources()->>'operationReceipts')::bigint<10000 THEN
  INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES(p_operation,'drain',p_epoch,p_source);END IF;
 RETURN private.collect_fence_owner_status_v3();
END;$fn$;

CREATE FUNCTION private.collect_fence_release_v3(p_operation uuid,p_epoch bigint,p_source text) RETURNS jsonb
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
  OR EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions WHERE recovery_operation_id=p_operation)
  OR scheduler->'blocking' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 IF (private._collect_fence_resources()->>'operationReceipts')::bigint+1>=9998
  OR(private._collect_fence_resources()->>'operationReceipts')::bigint+3>10000
  OR(SELECT count(*) FROM private.collect_fence_admissions)>=100000
  OR(SELECT count(*) FROM private.collect_fence_scheduler_lifecycle)>=10000
  OR(SELECT count(*) FROM private.collect_fence_stopped_admissions)>=10000 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 UPDATE private.collect_fence_control SET mode='open',epoch=epoch+1,operation_id=p_operation,changed_at=clock_timestamp() WHERE singleton;
 INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES(p_operation,'release',p_epoch+1,p_source);
 RETURN private.collect_fence_owner_status_v3();
END;$fn$;


-- Additive serialization change: old upgrade rows now expose explicit protocol2;
-- all original field values and immutable history remain unchanged. Existing
-- v2 callers/default INSERT remain2 and retain the original raw-row refusal.
ALTER TABLE private.collect_fence_source_upgrades ADD COLUMN lifecycle_protocol_version smallint NOT NULL DEFAULT 2 CHECK(lifecycle_protocol_version IN(2,3));
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
  OR EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions WHERE recovery_operation_id=NEW.operation_id)
  OR EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id=NEW.operation_id)
  OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=NEW.operation_id
       OR old_source_sha256=NEW.new_source_sha256 OR new_source_sha256=NEW.new_source_sha256)
  OR s->'checked' IS DISTINCT FROM 'true'::jsonb OR s->'coverageVerified' IS DISTINCT FROM 'true'::jsonb
  OR s->'blocking' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 -- Upgrade + separate release must fit and leave the existing OPEN admission
 -- threshold/future emergency begin+drain reserve. No history is pruned.
 IF c.epoch>9007199254740989 OR receipt_count+2>=9998 OR receipt_count+4>10000
  OR (r->>'retainedAdmissions')::bigint>=100000 OR (r->>'schedulerLifecycleProofs')::bigint>=10000 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 RETURN NEW;
END;$fn$;

CREATE FUNCTION private.collect_fence_upgrade_source_v3(p_operation uuid,p_fence_operation uuid,p_epoch bigint,
 p_source text,p_next_source text,p_plan text,p_qualification text,p_deployment text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;
BEGIN
 PERFORM private._collect_stopped_require_owner();PERFORM private._collect_fence_require_rc(true);
 IF p_operation IS NULL OR p_fence_operation IS NULL OR p_operation=p_fence_operation OR p_epoch IS NULL
  OR p_source IS NULL OR p_next_source IS NULL OR p_source=p_next_source OR p_plan IS NULL
  OR p_qualification IS NULL OR p_deployment IS NULL OR p_source !~ '^[a-f0-9]{64}$'
  OR p_next_source !~ '^[a-f0-9]{64}$' OR p_plan !~ '^[a-f0-9]{64}$'
  OR p_qualification !~ '^[a-f0-9]{64}$' OR p_deployment !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_maintenance';END IF;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 IF c.mode<>'fenced' OR c.operation_id<>p_fence_operation OR c.epoch<>p_epoch OR c.source_sha256<>p_source THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 INSERT INTO private.collect_fence_source_upgrades(operation_id,prior_fence_operation_id,project_ref,baseline_manifest_sha256,
  old_source_sha256,old_epoch,new_source_sha256,new_epoch,prior_control_snapshot,plan_sha256,qualification_sha256,deployment_readback_sha256,lifecycle_protocol_version)
 VALUES(p_operation,p_fence_operation,c.project_ref,c.baseline_manifest_sha256,p_source,p_epoch,p_next_source,p_epoch+1,to_jsonb(c),p_plan,p_qualification,p_deployment,3);
 UPDATE private.collect_fence_control SET source_sha256=p_next_source,epoch=p_epoch+1,operation_id=p_operation,
  changed_at=clock_timestamp() WHERE singleton;
 RETURN private.collect_fence_source_upgrade_status_v2(p_operation)||jsonb_build_object('contractVersion',3,'stoppedLifecycleStatus',private.collect_fence_owner_status_v3(),'runtimeFinishRecovered',false,'originalCountersRecovered',false,'unknownObligationSettled',false);
END;$fn$;

DO $acl$
DECLARE p regprocedure;a record;r name;
BEGIN
 REVOKE ALL ON TABLE private.collect_fence_stopped_admissions FROM PUBLIC;
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_runtime','collect_importer'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('REVOKE ALL ON TABLE private.collect_fence_stopped_admissions FROM %I',r);END IF;
 END LOOP;
 FOR a IN SELECT x.grantee FROM pg_class t CROSS JOIN LATERAL aclexplode(coalesce(t.relacl,acldefault('r',t.relowner))) x
  WHERE t.oid='private.collect_fence_stopped_admissions'::regclass AND x.grantee<>t.relowner LOOP
  IF a.grantee<>0 THEN EXECUTE format('REVOKE ALL ON TABLE private.collect_fence_stopped_admissions FROM %I',pg_get_userbyid(a.grantee));END IF;
 END LOOP;
 FOR p IN SELECT oid::regprocedure FROM pg_proc WHERE pronamespace='private'::regnamespace AND
  (proname LIKE '_collect_stopped_%' OR proname IN('collect_fence_stopped_admission_status_v3','collect_fence_record_stopped_admission_v3','collect_fence_owner_status_v3','collect_fence_drain_v3','collect_fence_release_v3','collect_fence_upgrade_source_v3')) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',p);
  FOR a IN SELECT x.grantee FROM pg_proc f CROSS JOIN LATERAL aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) x WHERE f.oid=p AND x.grantee<>f.proowner LOOP
   IF a.grantee<>0 THEN EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',p,pg_get_userbyid(a.grantee));END IF;
  END LOOP;
 END LOOP;
END;$acl$;
COMMIT;
