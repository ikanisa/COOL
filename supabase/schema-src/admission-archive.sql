-- Logical archival, not deletion: original admission rows and uncertain effects
-- remain immutable and queryable. Only proved settled/zero-uncertainty work can
-- leave the bounded active index. Apply after the original sixteen migrations.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
LOCK TABLE private.collect_fence_admissions IN SHARE ROW EXCLUSIVE MODE;

CREATE TABLE private.collect_fence_working_admissions(
 admission_id uuid PRIMARY KEY REFERENCES private.collect_fence_admissions(admission_id)
);
CREATE TABLE private.collect_fence_admission_archive(
 admission_id uuid PRIMARY KEY REFERENCES private.collect_fence_admissions(admission_id),
 snapshot_sha256 text NOT NULL CHECK(snapshot_sha256 ~ '^[a-f0-9]{64}$'),
 archived_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.collect_fence_admission_totals(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 retained_total bigint NOT NULL CHECK(retained_total>=0),
 archived_total bigint NOT NULL CHECK(archived_total BETWEEN 0 AND retained_total)
);
ALTER TABLE private.collect_fence_working_admissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_fence_admission_archive ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_fence_admission_totals ENABLE ROW LEVEL SECURITY;
INSERT INTO private.collect_fence_working_admissions SELECT admission_id FROM private.collect_fence_admissions;
INSERT INTO private.collect_fence_admission_totals SELECT true,count(*),0 FROM private.collect_fence_admissions;
CREATE INDEX collect_fence_archivable ON private.collect_fence_admissions(closed_at,admission_id)
 WHERE state='settled' AND uncertain_dispatches=0;

CREATE FUNCTION private._collect_archive_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a private.collect_fence_admissions%ROWTYPE;
BEGIN
 SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=NEW.admission_id;
 IF NOT FOUND OR a.state<>'settled' OR a.uncertain_dispatches<>0
  OR a.reason NOT IN('completed','work_failed_before_dispatch','cancelled_before_work')
  OR private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)
  OR NEW.snapshot_sha256 IS DISTINCT FROM encode(sha256(convert_to(to_jsonb(a)::text,'UTF8')),'hex') THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_archive_unsettled';END IF;
 NEW.archived_at:=clock_timestamp();RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_archive_guard BEFORE INSERT ON private.collect_fence_admission_archive
 FOR EACH ROW EXECUTE FUNCTION private._collect_archive_guard();
CREATE TRIGGER collect_archive_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON private.collect_fence_admission_archive
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.collect_fence_admission_archive ENABLE ALWAYS TRIGGER collect_archive_guard;
ALTER TABLE private.collect_fence_admission_archive ENABLE ALWAYS TRIGGER collect_archive_immutable;

CREATE FUNCTION private._collect_working_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF TG_OP='INSERT' THEN
  IF NOT EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE admission_id=NEW.admission_id)
   OR EXISTS(SELECT 1 FROM private.collect_fence_admission_archive WHERE admission_id=NEW.admission_id) THEN
   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_archive_index_conflict';END IF;
  RETURN NEW;
 END IF;
 IF TG_OP='DELETE' THEN
  IF NOT EXISTS(SELECT 1 FROM private.collect_fence_admission_archive h
   JOIN private.collect_fence_admissions a USING(admission_id)
   WHERE h.admission_id=OLD.admission_id AND a.state='settled' AND a.uncertain_dispatches=0
    AND h.snapshot_sha256=encode(sha256(convert_to(to_jsonb(a)::text,'UTF8')),'hex')) THEN
   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_archive_receipt_required';END IF;
  RETURN OLD;
 END IF;
 RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_archive_index_immutable';
END;$fn$;
CREATE TRIGGER collect_working_guard BEFORE INSERT OR UPDATE OR DELETE ON private.collect_fence_working_admissions
 FOR EACH ROW EXECUTE FUNCTION private._collect_working_guard();
CREATE TRIGGER collect_working_no_truncate BEFORE TRUNCATE ON private.collect_fence_working_admissions
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.collect_fence_working_admissions ENABLE ALWAYS TRIGGER collect_working_guard;
ALTER TABLE private.collect_fence_working_admissions ENABLE ALWAYS TRIGGER collect_working_no_truncate;

CREATE FUNCTION private._collect_archive_totals_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 -- Only nested lifecycle triggers maintain this derived counter. Neither
 -- client/runtime access nor a standalone owner UPDATE can manufacture room.
 IF TG_OP<>'UPDATE' OR pg_trigger_depth()<2 OR NEW.singleton IS DISTINCT FROM OLD.singleton
  OR NOT((NEW.retained_total=OLD.retained_total+1 AND NEW.archived_total=OLD.archived_total)
   OR(NEW.retained_total=OLD.retained_total AND NEW.archived_total=OLD.archived_total+1)) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_archive_counter_conflict';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_archive_totals_guard BEFORE INSERT OR UPDATE OR DELETE ON private.collect_fence_admission_totals
 FOR EACH ROW EXECUTE FUNCTION private._collect_archive_totals_guard();
CREATE TRIGGER collect_archive_totals_no_truncate BEFORE TRUNCATE ON private.collect_fence_admission_totals
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.collect_fence_admission_totals ENABLE ALWAYS TRIGGER collect_archive_totals_guard;
ALTER TABLE private.collect_fence_admission_totals ENABLE ALWAYS TRIGGER collect_archive_totals_no_truncate;

CREATE FUNCTION private._collect_archive_recorded() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 UPDATE private.collect_fence_admission_totals SET archived_total=archived_total+1 WHERE singleton;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_archive_counter_missing';END IF;
 DELETE FROM private.collect_fence_working_admissions WHERE admission_id=NEW.admission_id;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_archive_index_missing';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_archive_recorded AFTER INSERT ON private.collect_fence_admission_archive
 FOR EACH ROW EXECUTE FUNCTION private._collect_archive_recorded();
ALTER TABLE private.collect_fence_admission_archive ENABLE ALWAYS TRIGGER collect_archive_recorded;

CREATE FUNCTION private._collect_admission_archive_track() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF TG_OP='INSERT' THEN
  INSERT INTO private.collect_fence_working_admissions VALUES(NEW.admission_id);
  UPDATE private.collect_fence_admission_totals SET retained_total=retained_total+1 WHERE singleton;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_archive_counter_missing';END IF;
 END IF;
 IF NEW.state='settled' AND NEW.uncertain_dispatches=0 THEN
  INSERT INTO private.collect_fence_admission_archive(admission_id,snapshot_sha256)
   VALUES(NEW.admission_id,encode(sha256(convert_to(to_jsonb(NEW)::text,'UTF8')),'hex'));
 END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_admission_archive_track AFTER INSERT OR UPDATE ON private.collect_fence_admissions
 FOR EACH ROW EXECUTE FUNCTION private._collect_admission_archive_track();
ALTER TABLE private.collect_fence_admissions ENABLE ALWAYS TRIGGER collect_admission_archive_track;

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
  'operationReceipts',operation_count,'schedulerLifecycleProofs',proof_count,
  'settledRetentionEnabled',true,'archiveMode','immutable_in_place','originalRowsDeleted',false,
  'operationReceiptSaturated',operation_count>=10000,
  'capacityBlocked',working_count>=100000 OR active_count>=8 OR operation_count>=9998 OR proof_count>=10000);
END;$fn$;

CREATE FUNCTION private.collect_fence_archive_settled_v4(p_limit integer DEFAULT 1000) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE candidate private.collect_fence_admissions%ROWTYPE;n integer:=0;
BEGIN
 PERFORM private._collect_fence_require_operator();PERFORM private._collect_fence_require_rc(true);
 IF p_limit IS NULL OR p_limit<1 OR p_limit>5000 THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_archive_invalid_limit';END IF;
 -- Each original is locked first, just as runtime close does. Concurrent
 -- maintainers skip it; an uncertain close is never inferred from age or TTL.
 FOR candidate IN SELECT a.* FROM private.collect_fence_admissions a
  JOIN private.collect_fence_working_admissions w USING(admission_id)
  WHERE a.state='settled' AND a.uncertain_dispatches=0
  ORDER BY a.closed_at,a.admission_id LIMIT p_limit FOR UPDATE OF a SKIP LOCKED LOOP
  INSERT INTO private.collect_fence_admission_archive(admission_id,snapshot_sha256)
   VALUES(candidate.admission_id,encode(sha256(convert_to(to_jsonb(candidate)::text,'UTF8')),'hex'));
  n:=n+1;
 END LOOP;
 RETURN jsonb_build_object('contractVersion',4,'archived',n,'originalRowsDeleted',false,
  'unknownObligationSettled',false,'resourceLimits',private._collect_fence_resources());
END;$fn$;

CREATE FUNCTION private.collect_fence_archive_status_v4(p_verify boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE r jsonb;verified boolean:=false;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF p_verify THEN LOCK TABLE private.collect_fence_admissions IN SHARE MODE;END IF;
 r:=private._collect_fence_resources();
 IF p_verify IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_archive_invalid_verify';END IF;
 IF p_verify THEN
  -- An explicit operator audit, never a full-history scan on ordinary requests.
  verified:=(SELECT count(*) FROM private.collect_fence_admissions)=(r->>'retainedAdmissions')::bigint
   AND(SELECT count(*) FROM private.collect_fence_admission_archive)=(r->>'archivedAdmissions')::bigint
   AND NOT EXISTS(SELECT 1 FROM private.collect_fence_admission_archive h JOIN private.collect_fence_admissions a USING(admission_id)
    WHERE a.state<>'settled' OR a.uncertain_dispatches<>0 OR h.snapshot_sha256<>encode(sha256(convert_to(to_jsonb(a)::text,'UTF8')),'hex'))
   AND NOT EXISTS(SELECT 1 FROM private.collect_fence_admissions a
    WHERE NOT EXISTS(SELECT 1 FROM private.collect_fence_working_admissions w WHERE w.admission_id=a.admission_id)
     AND NOT EXISTS(SELECT 1 FROM private.collect_fence_admission_archive h WHERE h.admission_id=a.admission_id));
  IF NOT verified THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_archive_verification_failed';END IF;
 END IF;
 RETURN jsonb_build_object('contractVersion',4,'resourceLimits',r,'fullHistoryVerified',verified,
  'originalRowsDeleted',false,'unknownObligationSettled',false,'providerSettlement',false);
END;$fn$;

-- Latest release/source-upgrade definitions below retain their existing
-- authority, stopped-work and source-binding checks; only the admission budget
-- reads the verified working index instead of all immutable historical rows.
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
  OR EXISTS(SELECT 1 FROM private.collect_fence_stopped_admissions WHERE recovery_operation_id=p_operation)
  OR scheduler->'blocking' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 IF (private._collect_fence_resources()->>'operationReceipts')::bigint+1>=9998
  OR(private._collect_fence_resources()->>'operationReceipts')::bigint+3>10000
  OR(private._collect_fence_resources()->>'workingAdmissions')::bigint>=100000
  OR(SELECT count(*) FROM private.collect_fence_scheduler_lifecycle)>=10000
  OR(SELECT count(*) FROM private.collect_fence_stopped_admissions)>=10000 THEN
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
  OR (r->>'workingAdmissions')::bigint>=100000 OR (r->>'schedulerLifecycleProofs')::bigint>=10000 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 RETURN NEW;
END;$fn$;

DO $acl$
DECLARE r text;p record;
BEGIN
 FOR r IN SELECT rolname FROM pg_roles WHERE rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer') LOOP
  EXECUTE format('REVOKE ALL ON TABLE private.collect_fence_working_admissions,private.collect_fence_admission_archive,private.collect_fence_admission_totals FROM %I',r);
 END LOOP;
 REVOKE ALL ON TABLE private.collect_fence_working_admissions,private.collect_fence_admission_archive,private.collect_fence_admission_totals FROM PUBLIC;
 FOR p IN SELECT oid::regprocedure AS signature FROM pg_proc WHERE pronamespace='private'::regnamespace AND
  proname IN('_collect_archive_guard','_collect_working_guard','_collect_archive_totals_guard','_collect_archive_recorded',
   '_collect_admission_archive_track','collect_fence_archive_settled_v4','collect_fence_archive_status_v4') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',p.signature);
  FOR r IN SELECT rolname FROM pg_roles WHERE rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer') LOOP
   EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',p.signature,r);
  END LOOP;
 END LOOP;
END;$acl$;
COMMIT;
