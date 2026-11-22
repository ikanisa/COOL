-- PRIVATE SOURCE-ONLY clean-source upgrade candidate. No lost-work resolver.
-- Apply only after committed quiesce + genuine v1 drain; remain FENCED.
BEGIN ISOLATION LEVEL READ COMMITTED READ WRITE;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SET LOCAL search_path=pg_catalog,pg_temp;
DO $preflight$
DECLARE owner_name name;c private.collect_fence_control%ROWTYPE;s jsonb;
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM private._collect_fence_require_rc(true);
 SELECT pg_get_userbyid(relowner) INTO owner_name FROM pg_class WHERE oid='private.collect_fence_control'::regclass;
 IF current_setting('server_version_num')::integer/10000<>17 OR current_user<>owner_name
  OR to_regclass('private.collect_fence_source_upgrades') IS NOT NULL
  OR to_regprocedure('private.collect_fence_upgrade_source_v2(uuid,uuid,bigint,text,text,text,text,text)') IS NOT NULL THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_upgrade_install_precondition';END IF;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 s:=private._collect_fence_scheduler_status();
 -- Installation supports an uninitialized fresh numeric chain, or the
 -- existing committed, genuinely drained hosted controller. It never opens or
 -- initializes a controller and never treats missing history as settled work.
 IF s->'checked' IS DISTINCT FROM 'true'::jsonb OR s->'coverageVerified' IS DISTINCT FROM 'true'::jsonb
  OR s->'blocking' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_upgrade_install_precondition';END IF;
 IF c.singleton IS NULL THEN
  IF EXISTS(SELECT 1 FROM private.collect_fence_control)
   OR EXISTS(SELECT 1 FROM private.collect_fence_admissions)
   OR EXISTS(SELECT 1 FROM private.collect_fence_operations)
   OR EXISTS(SELECT 1 FROM private.collect_fence_scheduler_lifecycle) THEN
   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_upgrade_install_precondition';END IF;
 ELSE
  IF c.mode<>'fenced' OR c.project_ref<>'rrlduytparvsjfmegalh'
   OR c.baseline_manifest_sha256<>'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3'
   OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND NOT(
    -- A released SAVEPOINT child has a different xmin from the top XID.
    -- Accept only a normal xmin strictly preceding this top XID under the
    -- native half-range ordering, or FrozenXID2. No clock/status inference.
    xmin='2'::xid OR (xmin::text::bigint BETWEEN 3 AND 4294967295 AND
     mod((pg_current_xact_id()::xid)::text::bigint-xmin::text::bigint+4294967296,4294967296)
      BETWEEN 1 AND 2147483647)))
   OR NOT EXISTS(SELECT 1 FROM private.collect_fence_operations
    WHERE operation_id=c.operation_id AND action='drain' AND epoch=c.epoch AND source_sha256=c.source_sha256)
   OR EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE state IN('active','unresolved')) THEN
   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_upgrade_install_precondition';END IF;
 END IF;
 -- Exact source-body preimage checks are inserted by the sealed source builder.
  IF (SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname='_collect_fence_transition' AND p.prosecdef AND p.proowner=(SELECT relowner FROM pg_class WHERE oid='private.collect_fence_control'::regclass)) IS DISTINCT FROM '95809ea4826715023812e82f63c6d0bd10d99182f4a0c06c10945233a79654b6' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_upgrade_body_preimage';END IF;
 IF (SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname='_collect_fence_resources' AND p.prosecdef AND p.proowner=(SELECT relowner FROM pg_class WHERE oid='private.collect_fence_control'::regclass)) IS DISTINCT FROM 'ff4d56012a5bcff45b60db20f8785acad3add035df00466f0f9d496805745d07' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_upgrade_body_preimage';END IF;
 IF (SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname='_collect_fence_scheduler_capacity' AND p.prosecdef AND p.proowner=(SELECT relowner FROM pg_class WHERE oid='private.collect_fence_control'::regclass)) IS DISTINCT FROM '512e45b07ee1ff877ae8e54bf9fdda4d585aa8e8ad2d4a6d48ce2d84e3f2dd15' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_upgrade_body_preimage';END IF;
 IF (SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname='collect_fence_begin_quiesce' AND p.prosecdef AND p.proowner=(SELECT relowner FROM pg_class WHERE oid='private.collect_fence_control'::regclass)) IS DISTINCT FROM 'e95f4e4a115ecb2476b4a64408449f432b8676c6df75ecbbb60e3d324f2cbfea' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_upgrade_body_preimage';END IF;
 IF (SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname='collect_fence_drain' AND p.prosecdef AND p.proowner=(SELECT relowner FROM pg_class WHERE oid='private.collect_fence_control'::regclass)) IS DISTINCT FROM '294a1c9448ea34b14533c0a3c1d216329d9c09c49f2f4ba3c3d39f9d35238508' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_upgrade_body_preimage';END IF;
 IF (SELECT encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname='collect_fence_release' AND p.prosecdef AND p.proowner=(SELECT relowner FROM pg_class WHERE oid='private.collect_fence_control'::regclass)) IS DISTINCT FROM 'd495670c3e4de3a66b73776ba5ed37de9dc0db50f91bc1dd8fb6b66d812ecabf' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_upgrade_body_preimage';END IF;
END;$preflight$;

CREATE TABLE private.collect_fence_source_upgrades(
 operation_id uuid PRIMARY KEY,
 prior_fence_operation_id uuid NOT NULL,
 project_ref text NOT NULL CHECK(project_ref='rrlduytparvsjfmegalh'),
 baseline_manifest_sha256 text NOT NULL CHECK(baseline_manifest_sha256='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3'),
 old_source_sha256 text NOT NULL CHECK(old_source_sha256 ~ '^[a-f0-9]{64}$'),
 old_epoch bigint NOT NULL UNIQUE CHECK(old_epoch BETWEEN 1 AND 9007199254740989),
 new_source_sha256 text NOT NULL UNIQUE CHECK(new_source_sha256 ~ '^[a-f0-9]{64}$' AND new_source_sha256<>old_source_sha256),
 new_epoch bigint NOT NULL UNIQUE CHECK(new_epoch=old_epoch+1),
 prior_control_snapshot jsonb NOT NULL CHECK(jsonb_typeof(prior_control_snapshot)='object'),
 plan_sha256 text NOT NULL CHECK(plan_sha256 ~ '^[a-f0-9]{64}$'),
 qualification_sha256 text NOT NULL CHECK(qualification_sha256 ~ '^[a-f0-9]{64}$'),
 deployment_readback_sha256 text NOT NULL CHECK(deployment_readback_sha256 ~ '^[a-f0-9]{64}$'),
 recorded_transaction text NOT NULL DEFAULT pg_current_xact_id()::text,
 recorded_by text NOT NULL DEFAULT session_user::text,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(operation_id<>prior_fence_operation_id)
);
ALTER TABLE private.collect_fence_source_upgrades ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER collect_fence_no_erasure BEFORE UPDATE OR DELETE OR TRUNCATE ON private.collect_fence_source_upgrades
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.collect_fence_source_upgrades ENABLE ALWAYS TRIGGER collect_fence_no_erasure;

CREATE FUNCTION private._collect_fence_require_upgrade_locks() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM private._collect_fence_require_operator();PERFORM private._collect_fence_require_rc(true);
 IF (SELECT count(DISTINCT objid) FROM pg_locks WHERE locktype='advisory' AND pid=pg_backend_pid()
  AND database=(SELECT oid FROM pg_database WHERE datname=current_database())
  AND classid=7346371::oid AND objid IN(1::oid,2::oid) AND objsubid=2 AND mode='ExclusiveLock' AND granted)<>2 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_upgrade_locks_required';END IF;
END;$fn$;

CREATE FUNCTION private._collect_fence_upgrade_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;s jsonb;r jsonb;receipt_count bigint;
BEGIN
 PERFORM private._collect_fence_require_upgrade_locks();
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
  OR EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE state IN('active','unresolved'))
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
CREATE TRIGGER collect_fence_upgrade_insert BEFORE INSERT ON private.collect_fence_source_upgrades
 FOR EACH ROW EXECUTE FUNCTION private._collect_fence_upgrade_insert();
ALTER TABLE private.collect_fence_source_upgrades ENABLE ALWAYS TRIGGER collect_fence_upgrade_insert;

CREATE FUNCTION private.collect_fence_source_upgrade_status_v2(p_operation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE u private.collect_fence_source_upgrades%ROWTYPE;c private.collect_fence_control%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF p_operation IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_maintenance';END IF;
 SELECT * INTO u FROM private.collect_fence_source_upgrades WHERE operation_id=p_operation;
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton;
 RETURN jsonb_build_object('contractVersion',2,'found',u.operation_id IS NOT NULL,
  'upgrade',CASE WHEN u.operation_id IS NULL THEN NULL ELSE to_jsonb(u) END,
  'control',CASE WHEN c.singleton IS NULL THEN NULL ELSE to_jsonb(c) END,
  'lostWorkResolutionSupported',false,'providerSettlement',false,'wholeSystemAcceptance',false,'sb29Satisfied',false);
END;$fn$;

CREATE FUNCTION private.collect_fence_upgrade_source_v2(p_operation uuid,p_fence_operation uuid,p_epoch bigint,
 p_source text,p_next_source text,p_plan text,p_qualification text,p_deployment text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_operator();PERFORM private._collect_fence_require_rc(true);
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
  old_source_sha256,old_epoch,new_source_sha256,new_epoch,prior_control_snapshot,plan_sha256,qualification_sha256,deployment_readback_sha256)
 VALUES(p_operation,p_fence_operation,c.project_ref,c.baseline_manifest_sha256,p_source,p_epoch,p_next_source,p_epoch+1,to_jsonb(c),p_plan,p_qualification,p_deployment);
 UPDATE private.collect_fence_control SET source_sha256=p_next_source,epoch=p_epoch+1,operation_id=p_operation,
  changed_at=clock_timestamp() WHERE singleton;
 RETURN private.collect_fence_source_upgrade_status_v2(p_operation);
END;$fn$;
CREATE OR REPLACE FUNCTION private._collect_fence_transition() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF TG_TABLE_NAME='collect_fence_admissions' THEN
  IF (NEW.admission_id,NEW.epoch,NEW.source_sha256,NEW.kind,NEW.created_at) IS DISTINCT FROM
   (OLD.admission_id,OLD.epoch,OLD.source_sha256,OLD.kind,OLD.created_at)
   OR OLD.state<>'active' OR NEW.state NOT IN('settled','unresolved') THEN
   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_history_immutable';END IF;
 ELSIF TG_TABLE_NAME='collect_fence_control' THEN
  IF OLD.mode='fenced' AND NEW.mode='fenced' AND NEW.source_sha256<>OLD.source_sha256 THEN
   PERFORM private._collect_fence_require_upgrade_locks();
   IF (NEW.singleton,NEW.project_ref,NEW.baseline_manifest_sha256) IS DISTINCT FROM
    (OLD.singleton,OLD.project_ref,OLD.baseline_manifest_sha256)
    OR NEW.epoch<>OLD.epoch+1 OR NEW.operation_id=OLD.operation_id
    OR NOT EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades u WHERE u.operation_id=NEW.operation_id
     AND u.prior_fence_operation_id=OLD.operation_id AND u.old_source_sha256=OLD.source_sha256
     AND u.old_epoch=OLD.epoch AND u.new_source_sha256=NEW.source_sha256 AND u.new_epoch=NEW.epoch
     AND u.project_ref=OLD.project_ref AND u.baseline_manifest_sha256=OLD.baseline_manifest_sha256
     AND u.prior_control_snapshot=to_jsonb(OLD) AND u.recorded_transaction=pg_current_xact_id()::text) THEN
    RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
   RETURN NEW;
  END IF;
  IF (NEW.singleton,NEW.project_ref,NEW.baseline_manifest_sha256,NEW.source_sha256) IS DISTINCT FROM
   (OLD.singleton,OLD.project_ref,OLD.baseline_manifest_sha256,OLD.source_sha256)
   OR NOT((OLD.mode='open' AND NEW.mode='quiescing' AND NEW.epoch=OLD.epoch AND NEW.operation_id<>OLD.operation_id)
    OR(OLD.mode='quiescing' AND NEW.mode='fenced' AND NEW.epoch=OLD.epoch AND NEW.operation_id=OLD.operation_id)
    OR(OLD.mode='fenced' AND NEW.mode='open' AND NEW.epoch=OLD.epoch+1 AND NEW.operation_id<>OLD.operation_id)) THEN
   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 ELSE RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_history_immutable';
 END IF;
 RETURN NEW;
END;$fn$;

CREATE OR REPLACE FUNCTION private._collect_fence_resources() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE total_count bigint;active_count bigint;operation_count bigint;proof_count bigint;
BEGIN
 SELECT count(*),count(*) FILTER(WHERE state IN('active','unresolved')) INTO total_count,active_count FROM private.collect_fence_admissions;
 SELECT (SELECT count(*) FROM private.collect_fence_operations)+(SELECT count(*) FROM private.collect_fence_source_upgrades) INTO operation_count;
 SELECT count(*) INTO proof_count FROM private.collect_fence_scheduler_lifecycle;
 RETURN jsonb_build_object('retainedAdmissionLimit',100000,'activeWorkLimit',8,'operationReceiptLimit',10000,'schedulerLifecycleProofLimit',10000,
  'retainedAdmissions',total_count,'activeAndUnresolvedAdmissions',active_count,'operationReceipts',operation_count,'schedulerLifecycleProofs',proof_count,
  'settledRetentionEnabled',false,'operationReceiptSaturated',operation_count>=10000,
  'capacityBlocked',total_count>=100000 OR active_count>=8 OR operation_count>=9998 OR proof_count>=10000);
END;$fn$;

CREATE OR REPLACE FUNCTION private._collect_fence_scheduler_capacity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM private._collect_fence_require_rc(true);
 -- This short owner-only INSERT serializes with registration/control operations;
 -- it never acquires WORK/WRITE or performs provider/business work afterward.
 PERFORM 1 FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 IF (TG_TABLE_NAME='collect_fence_scheduler_lifecycle' AND (SELECT count(*) FROM private.collect_fence_scheduler_lifecycle)>=10000)
  OR(TG_TABLE_NAME='collect_fence_operations' AND (private._collect_fence_resources()->>'operationReceipts')::bigint>=10000) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 IF TG_TABLE_NAME='collect_fence_operations' THEN
  IF EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=NEW.operation_id) THEN
   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 END IF;
 RETURN NEW;
END;$fn$;

CREATE OR REPLACE FUNCTION private.collect_fence_begin_quiesce(p_operation uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM private._collect_fence_require_rc(true);
 IF p_operation IS NULL OR p_epoch IS NULL OR p_source IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_control';END IF;
 -- Do not wait for WORK here. This short committed CAS closes NEW admission
 -- before a later, independently committed drain waits for existing work.
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 IF c.mode<>'open' OR c.epoch<>p_epoch OR c.source_sha256<>p_source OR (EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id=p_operation) OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=p_operation)) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 UPDATE private.collect_fence_control SET mode='quiescing',operation_id=p_operation,changed_at=clock_timestamp() WHERE singleton;
 -- Emergency closure remains available even if the bounded audit log is full.
 -- The authoritative singleton retains the exact original operation UUID/mode;
 -- owner_status explicitly reports saturation. Reopening cannot proceed at cap.
 IF (private._collect_fence_resources()->>'operationReceipts')::bigint<10000 THEN
  INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES(p_operation,'begin_quiesce',p_epoch,p_source);END IF;
 RETURN private.collect_fence_owner_status();
END;$fn$;

CREATE OR REPLACE FUNCTION private.collect_fence_drain(p_operation uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;scheduler jsonb;
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM private._collect_fence_require_rc(true);
 IF p_operation IS NULL OR p_epoch IS NULL OR p_source IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_control';END IF;
 -- Global order WORK exclusive, then WRITE exclusive. Never hold a control
 -- row lock while waiting for WORK: completion needs a separate close tx.
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 IF c.mode NOT IN('quiescing','fenced') OR c.operation_id<>p_operation OR c.epoch<>p_epoch OR c.source_sha256<>p_source THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 IF c.mode='fenced' THEN RETURN private.collect_fence_owner_status();END IF;
 scheduler:=private._collect_fence_scheduler_status();
 IF EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE state IN('active','unresolved')) OR scheduler->'blocking' IS DISTINCT FROM 'false'::jsonb THEN
  RETURN private.collect_fence_owner_status();END IF;
 UPDATE private.collect_fence_control SET mode='fenced',changed_at=clock_timestamp() WHERE singleton;
 IF (private._collect_fence_resources()->>'operationReceipts')::bigint<10000 THEN
  INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES(p_operation,'drain',p_epoch,p_source);END IF;
 RETURN private.collect_fence_owner_status();
END;$fn$;

CREATE OR REPLACE FUNCTION private.collect_fence_release(p_operation uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;scheduler jsonb;
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM private._collect_fence_require_rc(true);
 IF p_operation IS NULL OR p_epoch IS NULL OR p_source IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_control';END IF;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 IF EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=c.operation_id AND recorded_transaction=pg_current_xact_id()::text) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 scheduler:=private._collect_fence_scheduler_status();
 IF c.mode<>'fenced' OR c.epoch<>p_epoch OR c.epoch>=9007199254740991 OR c.source_sha256<>p_source
 OR EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE state IN('active','unresolved'))
 OR (EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id=p_operation) OR EXISTS(SELECT 1 FROM private.collect_fence_source_upgrades WHERE operation_id=p_operation))
 OR scheduler->'blocking' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 -- Reserve this release receipt plus a future begin/drain pair before OPEN.
 -- No automatic retention policy is inferred to free audit capacity.
 IF (private._collect_fence_resources()->>'operationReceipts')::bigint+1>=9998
  OR(private._collect_fence_resources()->>'operationReceipts')::bigint+3>10000
  OR(SELECT count(*) FROM private.collect_fence_admissions)>=100000
  OR(SELECT count(*) FROM private.collect_fence_scheduler_lifecycle)>=10000 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 UPDATE private.collect_fence_control SET mode='open',epoch=epoch+1,operation_id=p_operation,changed_at=clock_timestamp() WHERE singleton;
 INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES(p_operation,'release',p_epoch+1,p_source);
 RETURN private.collect_fence_owner_status();
END;$fn$;

DO $acl$
DECLARE p regprocedure;r name;a record;
BEGIN
 REVOKE ALL ON TABLE private.collect_fence_source_upgrades FROM PUBLIC;
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_runtime','collect_importer'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN
   EXECUTE format('REVOKE ALL ON TABLE private.collect_fence_source_upgrades FROM %I',r);END IF;
 END LOOP;
 FOREACH p IN ARRAY ARRAY[
  'private._collect_fence_require_upgrade_locks()'::regprocedure,
  'private._collect_fence_upgrade_insert()'::regprocedure,
  'private.collect_fence_source_upgrade_status_v2(uuid)'::regprocedure,
  'private.collect_fence_upgrade_source_v2(uuid,uuid,bigint,text,text,text,text,text)'::regprocedure] LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',p);
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_runtime','collect_importer'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',p,r);END IF;
  END LOOP;
 END LOOP;
 -- Remove any inherited/custom default ACL on these new owner-only objects.
 FOR a IN SELECT x.grantee FROM pg_class t CROSS JOIN LATERAL aclexplode(coalesce(t.relacl,acldefault('r',t.relowner))) x
  WHERE t.oid='private.collect_fence_source_upgrades'::regclass AND x.grantee<>t.relowner LOOP
  IF a.grantee=0 THEN REVOKE ALL ON TABLE private.collect_fence_source_upgrades FROM PUBLIC;
  ELSE EXECUTE format('REVOKE ALL ON TABLE private.collect_fence_source_upgrades FROM %I',pg_get_userbyid(a.grantee));END IF;
 END LOOP;
 FOR a IN SELECT f.oid::regprocedure AS signature,x.grantee FROM pg_proc f CROSS JOIN LATERAL aclexplode(coalesce(f.proacl,acldefault('f',f.proowner))) x
  WHERE f.oid IN('private._collect_fence_require_upgrade_locks()'::regprocedure,
   'private._collect_fence_upgrade_insert()'::regprocedure,
   'private.collect_fence_source_upgrade_status_v2(uuid)'::regprocedure,
   'private.collect_fence_upgrade_source_v2(uuid,uuid,bigint,text,text,text,text,text)'::regprocedure) AND x.grantee<>f.proowner LOOP
  IF a.grantee=0 THEN EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',a.signature);
  ELSE EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',a.signature,pg_get_userbyid(a.grantee));END IF;
 END LOOP;
END;$acl$;


-- Root composed ordered fragment: 01_admin_email_kernel.sql
-- PRIVATE additive migration fragment. Root composes one required migration.
-- No historical migration is edited; no AAL2/MFA field is manufactured.
CREATE TABLE private.admin_email_operations (
 challenge_id text PRIMARY KEY REFERENCES private.supabase_otp_challenges(id),
 purpose text NOT NULL DEFAULT 'admin_sensitive_operations' CHECK(purpose='admin_sensitive_operations'),
 mode text NOT NULL CHECK(mode IN('initial','reauth')),
 admin_id text NOT NULL REFERENCES app.admin_users(id),
 principal_id text NOT NULL REFERENCES app.users(id),
 original_auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 original_session_id uuid NOT NULL,
 cookie_hash text NOT NULL CHECK(cookie_hash ~ '^[0-9a-f]{64}$'),
 public_session_id text NOT NULL,
 auth_version bigint NOT NULL CHECK(auth_version>=1),
 origin text NOT NULL CHECK(origin ~ '^https://[^/?#@]+$'),
 identity_value text NOT NULL,
 created_at bigint NOT NULL,
 send_claim uuid,
 verification_state text NOT NULL DEFAULT 'not_started' CHECK(verification_state IN('not_started','verifying','rejected','unconfirmed','verified')),
 verification_operation_id uuid,
 verify_receipts jsonb NOT NULL DEFAULT '{}'::jsonb CHECK(jsonb_typeof(verify_receipts)='object' AND octet_length(verify_receipts::text)<=4096),
 cleanup_state text NOT NULL DEFAULT 'not_started' CHECK(cleanup_state IN('not_started','claimed','confirmed','unconfirmed','not_required')),
 cleanup_claim uuid,
 verified_session_id uuid,
 verified_amr_at bigint,
 CHECK((mode='initial' AND verification_state='verified' AND cleanup_state='not_required'
         AND verified_session_id=original_session_id)
    OR (mode='reauth' AND cleanup_state<>'not_required'
         AND (verified_session_id IS NULL OR verified_session_id<>original_session_id))),
 CHECK((verification_state='verified')=(verified_session_id IS NOT NULL AND verified_amr_at IS NOT NULL)),
 CHECK(cleanup_state NOT IN('claimed','confirmed') OR (cleanup_claim IS NOT NULL AND verification_state='verified'))
);
CREATE INDEX admin_email_original_session ON private.admin_email_operations(original_session_id,created_at DESC);

CREATE TABLE private.admin_sensitive_email_proofs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 challenge_id text NOT NULL UNIQUE REFERENCES private.admin_email_operations(challenge_id),
 purpose text NOT NULL DEFAULT 'admin_sensitive_operations' CHECK(purpose='admin_sensitive_operations'),
 admin_id text NOT NULL REFERENCES app.admin_users(id),
 principal_id text NOT NULL REFERENCES app.users(id),
 auth_user_id uuid NOT NULL REFERENCES auth.users(id),
 original_session_id uuid NOT NULL,
 cookie_hash text NOT NULL CHECK(cookie_hash ~ '^[0-9a-f]{64}$'),
 public_session_id text NOT NULL,
 auth_version bigint NOT NULL CHECK(auth_version>=1),
 origin text NOT NULL,
 identity_value text NOT NULL,
 verified_session_id uuid NOT NULL,
 verified_at bigint NOT NULL CHECK(verified_at>0),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(verified_session_id,verified_at)
);
CREATE INDEX admin_sensitive_email_current ON private.admin_sensitive_email_proofs(cookie_hash,verified_at DESC,id DESC);

CREATE FUNCTION private.trg_admin_email_immutable() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'retain_admin_email_provenance' USING ERRCODE='42501';END$$;
CREATE TRIGGER admin_sensitive_email_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON private.admin_sensitive_email_proofs
 FOR EACH STATEMENT EXECUTE FUNCTION private.trg_admin_email_immutable();
CREATE TRIGGER admin_email_operations_no_delete BEFORE DELETE OR TRUNCATE ON private.admin_email_operations
 FOR EACH STATEMENT EXECUTE FUNCTION private.trg_admin_email_immutable();

CREATE FUNCTION private.trg_admin_email_operation_identity() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE item record; next_receipt jsonb;
BEGIN
 IF to_jsonb(OLD)-ARRAY['send_claim','verification_state','verification_operation_id','verify_receipts','cleanup_state','cleanup_claim','verified_session_id','verified_amr_at']
  IS DISTINCT FROM to_jsonb(NEW)-ARRAY['send_claim','verification_state','verification_operation_id','verify_receipts','cleanup_state','cleanup_claim','verified_session_id','verified_amr_at']
 THEN RAISE EXCEPTION 'admin_email_binding_changed' USING ERRCODE='42501';END IF;
 IF (OLD.send_claim IS NOT NULL AND NEW.send_claim IS DISTINCT FROM OLD.send_claim)
  OR (OLD.cleanup_claim IS NOT NULL AND NEW.cleanup_claim IS DISTINCT FROM OLD.cleanup_claim)
  OR (OLD.verification_state IN('verified','unconfirmed') AND
      jsonb_build_array(NEW.verification_state,NEW.verification_operation_id,NEW.verify_receipts,NEW.verified_session_id,NEW.verified_amr_at)
      IS DISTINCT FROM jsonb_build_array(OLD.verification_state,OLD.verification_operation_id,OLD.verify_receipts,OLD.verified_session_id,OLD.verified_amr_at))
  OR (OLD.cleanup_state IN('confirmed','unconfirmed','not_required') AND NEW.cleanup_state<>OLD.cleanup_state)
  OR (OLD.cleanup_state='claimed' AND NEW.cleanup_state NOT IN('claimed','confirmed','unconfirmed'))
 THEN RAISE EXCEPTION 'admin_email_state_regression' USING ERRCODE='42501';END IF;
 FOR item IN SELECT key,value FROM jsonb_each(OLD.verify_receipts) LOOP
  next_receipt:=NEW.verify_receipts->item.key;
  IF next_receipt IS NULL OR next_receipt->'admitted_at' IS DISTINCT FROM item.value->'admitted_at'
   OR (item.value->>'state'<>'verifying' AND next_receipt IS DISTINCT FROM item.value)
   OR (item.value->>'state'='verifying' AND next_receipt->>'state' NOT IN('verifying','rejected','unconfirmed','verified'))
  THEN RAISE EXCEPTION 'admin_email_state_regression' USING ERRCODE='42501';END IF;
 END LOOP;
 IF (SELECT count(*) FROM jsonb_object_keys(NEW.verify_receipts))>5 THEN RAISE EXCEPTION 'admin_email_attempt_limit' USING ERRCODE='42501';END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER admin_email_operation_identity BEFORE UPDATE ON private.admin_email_operations
 FOR EACH ROW EXECUTE FUNCTION private.trg_admin_email_operation_identity();

-- The complete original browser/actor tuple is derived from server-only rows.
-- The sole candidate-claims path passes p_match_claims=false inside a definer
-- helper, then independently proves the candidate OTP subject/session below.
CREATE FUNCTION private._admin_email_actor(p_actor text,p_cookie text,p_origin text,p_public text,p_match_claims boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; claims jsonb:=private.request_claims();
BEGIN
 IF current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true'
  OR p_actor IS NULL OR p_cookie IS NULL OR p_cookie !~ '^[0-9a-f]{64}$'
  OR p_origin IS NULL OR length(p_origin)>2048 OR p_origin !~ '^https://[^/?#@]+$'
  OR p_public IS NULL OR length(p_public) NOT BETWEEN 1 AND 200
 THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 SELECT jsonb_build_object('admin_id',a.id,'principal_id',u.id,'auth_user_id',managed.user_id::text,
   'session_id',s.id,'cookie_hash',c.token_hash,'public_session_id',c.public_id,'auth_version',a.auth_version,
   'origin',c.origin,'identity_value',lower(a.email),'role',a.role,'auth_at',s.auth_at,'created_at',c.created_at)
 INTO actor FROM app.admin_users a
 JOIN app.admin_principal_links l ON l.admin_user_id=a.id
 JOIN app.users u ON u.id=l.user_id AND u.access_status='active'
 JOIN app.admin_sessions c ON c.user_id=a.id AND c.auth_version=a.auth_version
 JOIN app.auth_sessions s ON s.id=c.auth_session_id AND s.user_id=u.id
 JOIN private.bff_sessions b ON b.token_hash=c.token_hash AND b.auth_session_id::text=s.id
 JOIN private.auth_principal_links p ON p.auth_user_id=b.auth_user_id AND p.user_id=u.id
 JOIN auth.sessions managed ON managed.id=b.auth_session_id AND managed.user_id=b.auth_user_id
 JOIN auth.users auth_user ON auth_user.id=managed.user_id
 WHERE a.id=p_actor AND a.status='active' AND c.token_hash=p_cookie AND c.origin=p_origin AND c.public_id=p_public
  AND s.surface='admin' AND s.revoked_at IS NULL AND s.expires_at>app.unixepoch() AND c.expires_at>app.unixepoch()
  AND b.refresh_lease IS NULL AND auth_user.email_confirmed_at IS NOT NULL AND lower(auth_user.email)=lower(a.email)
  AND lower(a.email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' AND length(a.email)<=254
  AND to_jsonb(auth_user)->>'deleted_at' IS NULL
  AND (to_jsonb(auth_user)->>'banned_until' IS NULL OR (to_jsonb(auth_user)->>'banned_until')::timestamptz<=now())
  AND (to_jsonb(managed)->>'not_after' IS NULL OR (to_jsonb(managed)->>'not_after')::timestamptz>now())
  -- AAL1 is fully supported. An existing AAL2 claim must remain truthful;
  -- this consistency branch never requires enrollment or fresh TOTP.
  AND (s.assurance_level=1 OR (s.assurance_level=2 AND to_jsonb(managed)->>'aal'='aal2'
   AND EXISTS(SELECT 1 FROM private.managed_mfa_proofs m JOIN auth.mfa_factors f ON f.id=m.factor_id AND f.user_id=m.user_id
    WHERE m.session_id=managed.id AND m.user_id=managed.user_id AND m.factor_id::text=s.mfa_factor_id
     AND m.verified_at_epoch=s.mfa_at AND f.status::text='verified'
     AND (to_jsonb(managed)->>'factor_id' IS NULL OR to_jsonb(managed)->>'factor_id'=m.factor_id::text))))
  AND (c.issued_assurance_level=1 OR (c.issued_assurance_level=2 AND s.assurance_level=2
   AND c.issued_mfa_at=s.mfa_at AND c.issued_mfa_factor_id=s.mfa_factor_id))
  AND (NOT p_match_claims OR (claims->>'role'='authenticated' AND claims->>'sub'=b.auth_user_id::text AND claims->>'session_id'=s.id))
 FOR SHARE OF a,l,u,c,s,b,p,managed,auth_user;
 IF actor IS NULL THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 RETURN actor;
END$$;

CREATE FUNCTION private.set_admin_email_context(p_actor text,p_cookie text,p_origin text,p_public text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb;
BEGIN
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);
 PERFORM set_config('collect.admin_email_context',jsonb_build_object('admin_id',p_actor,'cookie_hash',p_cookie,'origin',p_origin,'public_session_id',p_public)::text,true);
 RETURN jsonb_build_object('contract_version',1,'public_session_id',actor->>'public_session_id');
END$$;

CREATE FUNCTION private._admin_email_context() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE context jsonb;
BEGIN
 BEGIN context:=nullif(current_setting('collect.admin_email_context',true),'')::jsonb;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END;
 IF context IS NULL OR jsonb_typeof(context)<>'object' OR (SELECT count(*) FROM jsonb_object_keys(context))<>4
 THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 RETURN private._admin_email_actor(context->>'admin_id',context->>'cookie_hash',context->>'origin',context->>'public_session_id',true);
END$$;

CREATE FUNCTION private._admin_email_same(p_operation private.admin_email_operations,p_actor jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_array(p_operation.admin_id,p_operation.principal_id,p_operation.original_auth_user_id::text,
  p_operation.original_session_id::text,p_operation.cookie_hash,p_operation.public_session_id,p_operation.auth_version,p_operation.origin,p_operation.identity_value)
 =jsonb_build_array(p_actor->>'admin_id',p_actor->>'principal_id',p_actor->>'auth_user_id',p_actor->>'session_id',
  p_actor->>'cookie_hash',p_actor->>'public_session_id',(p_actor->>'auth_version')::bigint,p_actor->>'origin',p_actor->>'identity_value')
$$;

CREATE FUNCTION private._admin_email_result(p_operation private.admin_email_operations,p_created boolean DEFAULT false,p_claimed boolean DEFAULT false)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('created',p_created,'claimed',p_claimed,'challenge',jsonb_build_object(
  'id',c.id,'identity_value',c.identity_value,'created_at',c.created_at,'expires_at',c.expires_at,'delivery_status',c.delivery_status,
  'verification_state',p_operation.verification_state,'cleanup_state',p_operation.cleanup_state,
  'original_auth_user_id',p_operation.original_auth_user_id,'original_session_id',p_operation.original_session_id,
  'principal_id',p_operation.principal_id,'verified_session_id',p_operation.verified_session_id,'verified_amr_at',p_operation.verified_amr_at))
 FROM private.supabase_otp_challenges c WHERE c.id=p_operation.challenge_id
$$;

CREATE FUNCTION private._admin_email_operation(p_actor jsonb,p_challenge text) RETURNS private.admin_email_operations
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE operation private.admin_email_operations%ROWTYPE;
BEGIN
 SELECT * INTO operation FROM private.admin_email_operations WHERE challenge_id=p_challenge FOR UPDATE;
 IF NOT FOUND OR NOT coalesce(private._admin_email_same(operation,p_actor),false)
 THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 RETURN operation;
END$$;

CREATE FUNCTION private.admin_email_prepare(p_actor text,p_cookie text,p_origin text,p_public text,p_challenge text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; operation private.admin_email_operations%ROWTYPE; at bigint:=app.unixepoch();
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);
 IF p_challenge IS NULL OR p_challenge !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 THEN RAISE EXCEPTION 'admin_email_invalid' USING ERRCODE='22023';END IF;
 IF EXISTS(SELECT 1 FROM private.admin_email_operations WHERE challenge_id=p_challenge) THEN
  operation:=private._admin_email_operation(actor,p_challenge);RETURN private._admin_email_result(operation);
 END IF;
 INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at)
 VALUES(p_challenge,encode(sha256(convert_to('email:'||(actor->>'identity_value'),'UTF8')),'hex'),'email',actor->>'identity_value','admin',0,at,at+300);
 INSERT INTO private.admin_email_operations(challenge_id,mode,admin_id,principal_id,original_auth_user_id,original_session_id,
   cookie_hash,public_session_id,auth_version,origin,identity_value,created_at)
 VALUES(p_challenge,'reauth',actor->>'admin_id',actor->>'principal_id',(actor->>'auth_user_id')::uuid,(actor->>'session_id')::uuid,
   p_cookie,p_public,(actor->>'auth_version')::bigint,p_origin,actor->>'identity_value',at) RETURNING * INTO operation;
 RETURN private._admin_email_result(operation,true,false);
END$$;

CREATE FUNCTION private.admin_email_send_claim(p_actor text,p_cookie text,p_origin text,p_public text,p_challenge text,p_claim uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; operation private.admin_email_operations%ROWTYPE; challenge private.supabase_otp_challenges%ROWTYPE;
BEGIN
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);operation:=private._admin_email_operation(actor,p_challenge);
 SELECT * INTO challenge FROM private.supabase_otp_challenges WHERE id=p_challenge FOR UPDATE;
 IF p_claim IS NULL OR operation.mode<>'reauth' THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 IF operation.send_claim IS NOT NULL OR challenge.delivery_status<>'reserved' OR challenge.expires_at<app.unixepoch()
 THEN RETURN private._admin_email_result(operation);END IF;
 UPDATE private.admin_email_operations SET send_claim=p_claim WHERE challenge_id=p_challenge RETURNING * INTO operation;
 RETURN private._admin_email_result(operation,false,true);
END$$;

CREATE FUNCTION private.admin_email_send_finish(p_actor text,p_cookie text,p_origin text,p_public text,p_challenge text,p_claim uuid,p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; operation private.admin_email_operations%ROWTYPE; previous text;
BEGIN
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);operation:=private._admin_email_operation(actor,p_challenge);
 IF operation.send_claim IS DISTINCT FROM p_claim OR p_claim IS NULL OR p_status IS NULL OR p_status NOT IN('accepted','rejected','unknown')
 THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 SELECT delivery_status INTO previous FROM private.supabase_otp_challenges WHERE id=p_challenge FOR UPDATE;
 IF previous='reserved' THEN UPDATE private.supabase_otp_challenges SET delivery_status=p_status WHERE id=p_challenge;
 ELSIF previous<>p_status THEN RAISE EXCEPTION 'admin_email_outcome_conflict' USING ERRCODE='42501';END IF;
 RETURN private._admin_email_result(operation);
END$$;

CREATE FUNCTION private.admin_email_verify_claim(p_actor text,p_cookie text,p_origin text,p_public text,p_challenge text,p_operation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; operation private.admin_email_operations%ROWTYPE; challenge private.supabase_otp_challenges%ROWTYPE;
BEGIN
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);operation:=private._admin_email_operation(actor,p_challenge);
 SELECT * INTO challenge FROM private.supabase_otp_challenges WHERE id=p_challenge FOR UPDATE;
 IF p_operation IS NULL OR operation.mode<>'reauth' THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 IF operation.verify_receipts ? p_operation::text OR operation.verification_state NOT IN('not_started','rejected')
  OR challenge.consumed_at IS NOT NULL OR challenge.attempts>=5 OR challenge.delivery_status NOT IN('accepted','unknown')
  OR app.unixepoch() NOT BETWEEN challenge.created_at AND challenge.expires_at
  OR EXISTS(SELECT 1 FROM private.supabase_otp_challenges c WHERE c.identity_hash=challenge.identity_hash AND c.surface='admin' AND c.created_at>challenge.created_at)
 THEN RETURN private._admin_email_result(operation);END IF;
 UPDATE private.supabase_otp_challenges SET attempts=attempts+1 WHERE id=p_challenge;
 UPDATE private.admin_email_operations SET verification_state='verifying',verification_operation_id=p_operation,
  verify_receipts=verify_receipts||jsonb_build_object(p_operation::text,jsonb_build_object('state','verifying','admitted_at',app.unixepoch()))
 WHERE challenge_id=p_challenge RETURNING * INTO operation;
 RETURN private._admin_email_result(operation,false,true);
END$$;

CREATE FUNCTION private.admin_email_verify_finish(p_actor text,p_cookie text,p_origin text,p_public text,p_challenge text,p_operation uuid,p_outcome text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; operation private.admin_email_operations%ROWTYPE;
BEGIN
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);operation:=private._admin_email_operation(actor,p_challenge);
 IF p_operation IS NULL OR operation.verification_operation_id IS DISTINCT FROM p_operation
  OR p_outcome IS NULL OR p_outcome NOT IN('rejected','unconfirmed')
 THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 IF operation.verification_state=p_outcome THEN RETURN private._admin_email_result(operation);END IF;
 IF operation.verification_state<>'verifying' THEN RAISE EXCEPTION 'admin_email_outcome_conflict' USING ERRCODE='42501';END IF;
 UPDATE private.admin_email_operations SET verification_state=p_outcome,
  verify_receipts=jsonb_set(verify_receipts,ARRAY[p_operation::text,'state'],to_jsonb(p_outcome))
 WHERE challenge_id=p_challenge RETURNING * INTO operation;
 RETURN private._admin_email_result(operation);
END$$;

-- SQL validates the actual provider OTP event, not iat/auth_at, and the server
-- exclusively supplies authenticated claims from /verify type:'email'. AMR's
-- method='otp' does not independently encode the delivery channel.
CREATE FUNCTION private._admin_email_candidate(p_actor jsonb,p_challenge private.supabase_otp_challenges,p_initial boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE claims jsonb:=private.request_claims(); candidate uuid; subject uuid; event_at bigint;
BEGIN
 candidate:=(claims->>'session_id')::uuid;subject:=(claims->>'sub')::uuid;
 IF candidate='00000000-0000-0000-0000-000000000000'::uuid OR subject='00000000-0000-0000-0000-000000000000'::uuid
  OR claims->>'role' IS DISTINCT FROM 'authenticated' OR subject::text IS DISTINCT FROM p_actor->>'auth_user_id'
  OR (p_initial AND candidate::text IS DISTINCT FROM p_actor->>'session_id')
  OR (NOT p_initial AND candidate::text=p_actor->>'session_id')
  OR NOT coalesce(private.is_managed_session(subject,candidate),false)
  OR p_challenge.identity_type<>'email' OR p_challenge.surface<>'admin' OR p_challenge.registration_allowed<>0
  OR p_challenge.privacy_mode IS NOT NULL OR p_challenge.identity_value IS DISTINCT FROM p_actor->>'identity_value'
  OR p_challenge.delivery_status NOT IN('accepted','unknown') OR p_challenge.attempts NOT BETWEEN 1 AND 5
  OR p_challenge.expires_at>p_challenge.created_at+300 OR app.unixepoch()>p_challenge.expires_at
 THEN RAISE EXCEPTION 'admin_email_candidate_denied' USING ERRCODE='42501';END IF;
 PERFORM 1 FROM auth.users u WHERE u.id=subject AND u.email_confirmed_at IS NOT NULL AND lower(u.email)=p_challenge.identity_value FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_email_candidate_denied' USING ERRCODE='42501';END IF;
 SELECT max(floor(extract(epoch FROM updated_at))::bigint) INTO event_at FROM auth.mfa_amr_claims
 WHERE session_id=candidate AND authentication_method='otp';
 IF event_at IS NULL OR event_at NOT BETWEEN greatest(1,p_challenge.created_at) AND least(app.unixepoch(),p_challenge.expires_at)
  OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(claims->'amr')='array' THEN claims->'amr' ELSE '[]'::jsonb END) item
   WHERE item->>'method'='otp' AND jsonb_typeof(item->'timestamp')='number' AND item->>'timestamp' ~ '^[0-9]{1,16}$'
    AND abs((item->>'timestamp')::bigint-event_at)<=1)
  OR (p_initial AND (p_actor->>'auth_at')::bigint<>event_at)
  OR (NOT p_initial AND EXISTS(SELECT 1 FROM app.auth_sessions WHERE id=candidate::text))
 THEN RAISE EXCEPTION 'admin_email_candidate_denied' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('session_id',candidate,'amr_at',event_at);
END$$;

CREATE FUNCTION private.admin_email_record(p_actor text,p_cookie text,p_origin text,p_public text,p_challenge text,p_operation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; operation private.admin_email_operations%ROWTYPE; challenge private.supabase_otp_challenges%ROWTYPE; candidate jsonb;
BEGIN
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,false);operation:=private._admin_email_operation(actor,p_challenge);
 SELECT * INTO challenge FROM private.supabase_otp_challenges WHERE id=p_challenge FOR UPDATE;
 IF operation.mode<>'reauth' OR p_operation IS NULL OR operation.verification_operation_id IS DISTINCT FROM p_operation
  OR operation.verification_state<>'verifying' OR challenge.consumed_at IS NOT NULL
 THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 candidate:=private._admin_email_candidate(actor,challenge,false);
 UPDATE private.supabase_otp_challenges SET consumed_at=app.unixepoch() WHERE id=p_challenge;
 UPDATE private.admin_email_operations SET verification_state='verified',verified_session_id=(candidate->>'session_id')::uuid,
  verified_amr_at=(candidate->>'amr_at')::bigint,
  verify_receipts=jsonb_set(verify_receipts,ARRAY[p_operation::text,'state'],'"verified"'::jsonb)
 WHERE challenge_id=p_challenge RETURNING * INTO operation;
 INSERT INTO private.admin_sensitive_email_proofs(challenge_id,admin_id,principal_id,auth_user_id,original_session_id,cookie_hash,
  public_session_id,auth_version,origin,identity_value,verified_session_id,verified_at)
 VALUES(p_challenge,operation.admin_id,operation.principal_id,operation.original_auth_user_id,operation.original_session_id,
  operation.cookie_hash,operation.public_session_id,operation.auth_version,operation.origin,operation.identity_value,
  operation.verified_session_id,operation.verified_amr_at);
 INSERT INTO app.admin_account_audit(id,actor_id,subject_id,action,occurred_at)
 VALUES(gen_random_uuid()::text,operation.admin_id,operation.admin_id,'admin_email_proof_recorded',app.unixepoch());
 RETURN private._admin_email_result(operation);
END$$;

CREATE FUNCTION private.admin_email_record_initial(p_actor text,p_cookie text,p_origin text,p_public text,p_challenge text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; operation private.admin_email_operations%ROWTYPE; challenge private.supabase_otp_challenges%ROWTYPE; candidate jsonb;
BEGIN
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);
 SELECT * INTO challenge FROM private.supabase_otp_challenges WHERE id=p_challenge FOR UPDATE;
 IF NOT FOUND OR challenge.consumed_at IS NULL OR challenge.consumed_at NOT BETWEEN challenge.created_at AND challenge.expires_at
  OR (actor->>'created_at')::bigint<> (actor->>'auth_at')::bigint
 THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 candidate:=private._admin_email_candidate(actor,challenge,true);
 IF (candidate->>'amr_at')::bigint>challenge.consumed_at THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 IF EXISTS(SELECT 1 FROM private.admin_email_operations WHERE challenge_id=p_challenge) THEN
  operation:=private._admin_email_operation(actor,p_challenge);
  IF operation.mode<>'initial' THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
  RETURN private._admin_email_result(operation);
 END IF;
 INSERT INTO private.admin_email_operations(challenge_id,mode,admin_id,principal_id,original_auth_user_id,original_session_id,
  cookie_hash,public_session_id,auth_version,origin,identity_value,created_at,verification_state,cleanup_state,verified_session_id,verified_amr_at)
 VALUES(p_challenge,'initial',actor->>'admin_id',actor->>'principal_id',(actor->>'auth_user_id')::uuid,(actor->>'session_id')::uuid,
  p_cookie,p_public,(actor->>'auth_version')::bigint,p_origin,actor->>'identity_value',challenge.created_at,'verified','not_required',
  (candidate->>'session_id')::uuid,(candidate->>'amr_at')::bigint) RETURNING * INTO operation;
 INSERT INTO private.admin_sensitive_email_proofs(challenge_id,admin_id,principal_id,auth_user_id,original_session_id,cookie_hash,
  public_session_id,auth_version,origin,identity_value,verified_session_id,verified_at)
 VALUES(p_challenge,operation.admin_id,operation.principal_id,operation.original_auth_user_id,operation.original_session_id,
  operation.cookie_hash,operation.public_session_id,operation.auth_version,operation.origin,operation.identity_value,
  operation.verified_session_id,operation.verified_amr_at);
 INSERT INTO app.admin_account_audit(id,actor_id,subject_id,action,occurred_at)
 VALUES(gen_random_uuid()::text,operation.admin_id,operation.admin_id,'admin_initial_email_proof_recorded',app.unixepoch());
 RETURN private._admin_email_result(operation,true,false);
END$$;

CREATE FUNCTION private.admin_email_cleanup_claim(p_actor text,p_cookie text,p_origin text,p_public text,p_challenge text,p_operation uuid,p_claim uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; operation private.admin_email_operations%ROWTYPE;
BEGIN
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);operation:=private._admin_email_operation(actor,p_challenge);
 IF operation.mode<>'reauth' OR operation.verification_state<>'verified' OR p_claim IS NULL
  OR p_operation IS NULL OR operation.verification_operation_id IS DISTINCT FROM p_operation
 THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 IF operation.cleanup_state<>'not_started' OR operation.cleanup_claim IS NOT NULL THEN RETURN private._admin_email_result(operation);END IF;
 UPDATE private.admin_email_operations SET cleanup_state='claimed',cleanup_claim=p_claim
 WHERE challenge_id=p_challenge RETURNING * INTO operation;
 RETURN private._admin_email_result(operation,false,true);
END$$;

CREATE FUNCTION private.admin_email_cleanup_finish(p_actor text,p_cookie text,p_origin text,p_public text,p_challenge text,p_operation uuid,p_claim uuid,p_outcome text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; operation private.admin_email_operations%ROWTYPE;
BEGIN
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);operation:=private._admin_email_operation(actor,p_challenge);
 IF operation.mode<>'reauth' OR p_claim IS NULL OR operation.cleanup_claim IS DISTINCT FROM p_claim
  OR p_operation IS NULL OR operation.verification_operation_id IS DISTINCT FROM p_operation
  OR p_outcome IS NULL OR p_outcome NOT IN('confirmed','unconfirmed')
 THEN RAISE EXCEPTION 'admin_email_denied' USING ERRCODE='42501';END IF;
 IF operation.cleanup_state=p_outcome THEN RETURN private._admin_email_result(operation);END IF;
 IF operation.cleanup_state<>'claimed' THEN RAISE EXCEPTION 'admin_email_outcome_conflict' USING ERRCODE='42501';END IF;
 IF p_outcome='confirmed' AND (operation.verified_session_id=operation.original_session_id
   OR EXISTS(SELECT 1 FROM auth.sessions WHERE id=operation.verified_session_id)
   OR EXISTS(SELECT 1 FROM app.auth_sessions WHERE id=operation.verified_session_id::text))
 THEN RAISE EXCEPTION 'admin_email_cleanup_unconfirmed' USING ERRCODE='42501';END IF;
 UPDATE private.admin_email_operations SET cleanup_state=p_outcome WHERE challenge_id=p_challenge RETURNING * INTO operation;
 RETURN private._admin_email_result(operation);
END$$;

CREATE FUNCTION private._admin_email_latest(p_actor jsonb)
RETURNS private.admin_sensitive_email_proofs LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE proof private.admin_sensitive_email_proofs%ROWTYPE;
BEGIN
 SELECT p.* INTO proof FROM private.admin_sensitive_email_proofs p
 JOIN private.admin_email_operations o ON o.challenge_id=p.challenge_id
 WHERE private._admin_email_same(o,p_actor) AND o.verification_state='verified'
  AND o.cleanup_state IN('confirmed','not_required') AND p.purpose='admin_sensitive_operations'
  AND ROW(p.admin_id,p.principal_id,p.auth_user_id,p.original_session_id,p.cookie_hash,p.public_session_id,p.auth_version,p.origin,p.identity_value)
   IS NOT DISTINCT FROM ROW(o.admin_id,o.principal_id,o.original_auth_user_id,o.original_session_id,o.cookie_hash,o.public_session_id,o.auth_version,o.origin,o.identity_value)
  AND p.verified_at=o.verified_amr_at AND p.verified_session_id=o.verified_session_id
  AND p.verified_at>0 AND p.verified_at<=app.unixepoch()
 ORDER BY p.verified_at DESC,p.recorded_at DESC,p.id DESC LIMIT 1;
 RETURN proof;
END$$;

CREATE FUNCTION private._admin_email_current(p_actor jsonb,p_max_age bigint DEFAULT 300)
RETURNS private.admin_sensitive_email_proofs LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE proof private.admin_sensitive_email_proofs%ROWTYPE;
BEGIN
 IF p_max_age IS NULL OR p_max_age NOT BETWEEN 1 AND 86400 THEN RAISE EXCEPTION 'admin_email_policy_invalid' USING ERRCODE='42501';END IF;
 proof:=private._admin_email_latest(p_actor);
 IF proof.id IS NULL OR proof.verified_at<app.unixepoch()-p_max_age
 THEN RAISE EXCEPTION 'recent_email_sign_in_required' USING ERRCODE='42501';END IF;
 RETURN proof;
END$$;

CREATE FUNCTION private.assert_admin_email_context(p_max_age bigint DEFAULT 300)
RETURNS private.admin_sensitive_email_proofs LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN RETURN private._admin_email_current(private._admin_email_context(),p_max_age);END$$;
CREATE FUNCTION private.admin_email_is_current(p_max_age bigint DEFAULT 300) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN PERFORM private.assert_admin_email_context(p_max_age);RETURN true;
EXCEPTION WHEN SQLSTATE '42501' THEN RETURN false;END$$;
CREATE FUNCTION private.admin_email_status(p_actor text,p_cookie text,p_origin text,p_public text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; proof private.admin_sensitive_email_proofs%ROWTYPE;
BEGIN
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);
 proof:=private._admin_email_latest(actor);
 RETURN jsonb_build_object('contract_version',1,'public_session_id',actor->>'public_session_id',
  'email_verified_at',proof.verified_at,'proof_id',proof.id);
END$$;

ALTER TABLE private.admin_email_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.admin_sensitive_email_proofs ENABLE ROW LEVEL SECURITY;
CREATE POLICY edge_runtime_read ON private.admin_email_operations FOR SELECT TO collect_runtime USING(true);
CREATE POLICY edge_runtime_read ON private.admin_sensitive_email_proofs FOR SELECT TO collect_runtime USING(true);
REVOKE ALL ON private.admin_email_operations,private.admin_sensitive_email_proofs FROM PUBLIC,anon,authenticated,collect_runtime;
GRANT SELECT ON private.admin_email_operations,private.admin_sensitive_email_proofs TO collect_runtime;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.admin_email_operations
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.admin_email_operations ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.admin_sensitive_email_proofs
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.admin_sensitive_email_proofs ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
-- Exact function grants/revocations and exact fence/archive/retention coverage
-- are supplied by the composition fragment; no public RPC is added.

-- Root composed ordered fragment: 02_admin_only_gate_replacements.sql
-- Private additive successor: member/MFA proof and projection truth unchanged.
CREATE OR REPLACE FUNCTION private.assert_actor(p_permission text DEFAULT NULL,p_collection_id text DEFAULT NULL,p_group_role text DEFAULT NULL,p_min_aal bigint DEFAULT 1,p_fresh_seconds bigint DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=app,pg_catalog AS $$
DECLARE principal text;claims jsonb;projected app.auth_sessions%ROWTYPE;managed jsonb;
 now_seconds bigint:=app.unixepoch();admin_actor jsonb;email_ttl bigint;
BEGIN
 claims:=private.request_claims();principal:=api.current_principal_id();
 IF principal IS NULL OR claims->>'role' IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 SELECT s.* INTO projected FROM app.auth_sessions s JOIN app.users u ON u.id=s.user_id
 WHERE s.id=api.current_session_id() AND s.user_id=principal AND s.revoked_at IS NULL
 AND s.expires_at>now_seconds AND u.access_status='active' FOR SHARE OF s,u;
 IF NOT FOUND THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 SELECT to_jsonb(s) INTO managed FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id
 WHERE s.id::text=projected.id AND u.id::text=claims->>'sub' AND to_jsonb(u)->>'deleted_at' IS NULL
 AND (to_jsonb(u)->>'banned_until' IS NULL OR (to_jsonb(u)->>'banned_until')::timestamptz<=now())
 AND (to_jsonb(s)->>'not_after' IS NULL OR (to_jsonb(s)->>'not_after')::timestamptz>now()) FOR SHARE OF s,u;
 IF managed IS NULL THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
 IF projected.surface='admin' THEN
  admin_actor:=private._admin_email_context();
  IF admin_actor->>'principal_id' IS DISTINCT FROM principal OR admin_actor->>'session_id' IS DISTINCT FROM projected.id
  THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501';END IF;
  -- Requested policy thresholds remain unchanged in stored mutation guards.
  -- Admin policy is satisfied by email possession/current intent, not fake AAL2.
  IF p_min_aal>1 OR p_fresh_seconds IS NOT NULL THEN
   email_ttl:=CASE WHEN p_min_aal>1 THEN least(300,coalesce(p_fresh_seconds,300)) ELSE p_fresh_seconds END;
   PERFORM private.assert_admin_email_context(email_ttl);
  END IF;
  IF p_permission IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.admin_account_role_capabilities c
    WHERE c.role=admin_actor->>'role' AND c.permission=p_permission)
  THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 ELSE
  -- Exact preexisting managed MFA and freshness conditions for members.
  IF p_min_aal>1 AND (claims->>'aal' IS DISTINCT FROM 'aal2' OR managed->>'aal' IS DISTINCT FROM 'aal2' OR projected.assurance_level<>2 OR projected.mfa_at IS NULL OR projected.mfa_at<now_seconds-300 OR NOT EXISTS(SELECT 1 FROM private.managed_mfa_proofs proof JOIN auth.mfa_factors f ON f.id=proof.factor_id AND f.user_id=proof.user_id WHERE proof.session_id::text=projected.id AND proof.user_id::text=claims->>'sub' AND proof.factor_id::text=projected.mfa_factor_id AND f.status::text='verified' AND proof.verified_at_epoch=projected.mfa_at)) THEN RAISE EXCEPTION 'mfa_required' USING ERRCODE='42501';END IF;
  IF p_fresh_seconds IS NOT NULL AND greatest(projected.auth_at,coalesce(projected.mfa_at,0))<now_seconds-p_fresh_seconds THEN RAISE EXCEPTION 'fresh_auth_required' USING ERRCODE='42501';END IF;
 END IF;
 IF p_permission IS NOT NULL AND (projected.surface<>'admin' OR NOT EXISTS(SELECT 1 FROM app.admin_grants g WHERE g.user_id=principal AND g.permission=p_permission)) THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501';END IF;
 IF p_collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.memberships m JOIN app.collections c ON c.id=m.collection_id WHERE m.user_id=principal AND m.collection_id=p_collection_id AND m.active=1 AND c.status='active' AND (p_group_role IS NULL OR m.role=p_group_role OR (p_group_role='admin' AND m.role='owner'))) THEN RAISE EXCEPTION 'group_access_denied' USING ERRCODE='42501';END IF;
 RETURN principal;
END$$;

CREATE OR REPLACE FUNCTION private.trg_mutation_authority() RETURNS trigger
LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
DECLARE admin_surface boolean;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN users u ON u.id=s.user_id WHERE s.id=NEW.session_id AND s.user_id=NEW.user_id AND s.revoked_at IS NULL AND s.expires_at>NEW.now_seconds AND u.access_status='active') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='session_changed';END IF;
 SELECT s.surface='admin' INTO admin_surface FROM auth_sessions s WHERE s.id=NEW.session_id;
 IF admin_surface THEN
  PERFORM private.assert_actor(NEW.permission,NEW.collection_id,NEW.required_group_role,coalesce(NEW.minimum_assurance,1),NEW.fresh_seconds);
  IF NEW.expected_mfa_at IS NOT NULL THEN RAISE EXCEPTION 'admin_email_mfa_field_must_remain_null' USING ERRCODE='42501';END IF;
 ELSE
  IF NEW.fresh_seconds IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth_sessions s WHERE s.id=NEW.session_id AND (CASE WHEN s.assurance_level=2 THEN s.mfa_at ELSE s.auth_at END)>=NEW.now_seconds-NEW.fresh_seconds) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='fresh_auth_required';END IF;
  IF NEW.minimum_assurance IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN auth_mfa_factors f ON f.id=s.mfa_factor_id AND f.status='verified' WHERE s.id=NEW.session_id AND s.assurance_level>=NEW.minimum_assurance AND s.mfa_at=NEW.expected_mfa_at AND s.mfa_at>=NEW.now_seconds-300 AND s.mfa_factor_id IS NOT NULL) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='mfa_required';END IF;
 END IF;
 IF NEW.permission IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN admin_grants g ON g.user_id=s.user_id WHERE s.id=NEW.session_id AND s.surface='admin' AND g.permission=NEW.permission) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='permission_denied';END IF;
 IF NEW.collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM memberships m JOIN collections c ON c.id=m.collection_id WHERE m.collection_id=NEW.collection_id AND m.user_id=NEW.user_id AND m.active=1 AND c.status='active' AND (NEW.required_group_role IS NULL OR m.role=NEW.required_group_role OR (NEW.required_group_role='admin' AND m.role='owner'))) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='group_access_denied';END IF;
 IF NEW.invite_collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM collections c WHERE c.id=NEW.invite_collection_id AND c.status='active' AND c.share_code_hash=NEW.expected_share_hash AND c.share_code_version=NEW.expected_share_version) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='invitation_changed';END IF;
 IF NEW.recipient_user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM memberships m JOIN users u ON u.id=m.user_id WHERE m.user_id=NEW.recipient_user_id AND m.collection_id=NEW.recipient_collection_id AND m.active=1 AND u.access_status='active') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='recipient_changed';END IF;
 IF NEW.expected_preference_revision IS NOT NULL AND coalesce((SELECT revision FROM notification_preferences WHERE user_id=NEW.user_id),1)!=NEW.expected_preference_revision THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='stale_preferences';END IF;
 IF NEW.expected_collection_revision IS NOT NULL AND NOT EXISTS(SELECT 1 FROM collections c WHERE c.id=NEW.collection_id AND c.revision=NEW.expected_collection_revision) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='stale_collection';END IF;
 IF NEW.expected_payment_revision IS NOT NULL AND NOT EXISTS(SELECT 1 FROM payments p WHERE p.id=NEW.payment_id AND p.revision=NEW.expected_payment_revision) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='stale_payment';END IF;
 RETURN NEW;
END$$;

CREATE OR REPLACE FUNCTION private.trg_roster_upload_authority() RETURNS trigger
LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
DECLARE principal text;
BEGIN
 principal:=private.assert_actor('roster.import',NULL,NULL,2,300);
 IF NEW.session_id IS DISTINCT FROM api.current_session_id() OR NEW.user_id IS DISTINCT FROM principal
 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='roster_session_changed';END IF;
 IF (SELECT count(*) FROM roster_imports WHERE user_id=NEW.user_id AND created_seconds>=unixepoch()-86400)>=20 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='roster_import_limit';END IF;
 IF NEW.collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM collections WHERE id=NEW.collection_id AND status='active') THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='roster_collection_changed';END IF;
 RETURN NEW;
END$$;
CREATE OR REPLACE FUNCTION private.trg_roster_current_authority() RETURNS trigger
LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
DECLARE principal text;
BEGIN
 IF NEW.now_seconds NOT BETWEEN unixepoch()-5 AND unixepoch()+5 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='roster_current_dispatch_expired';END IF;
 principal:=private.assert_actor(NEW.permission,NULL,NULL,2,300);
 IF NEW.session_id IS DISTINCT FROM api.current_session_id() OR NEW.actor_user_id IS DISTINCT FROM principal
 OR NOT EXISTS(SELECT 1 FROM roster_imports i JOIN auth_sessions s ON s.id=i.session_id JOIN users u ON u.id=i.user_id JOIN admin_grants g ON g.user_id=u.id
  WHERE i.id=NEW.import_id AND i.user_id=NEW.actor_user_id AND i.session_id=NEW.session_id
  AND i.expires_seconds>greatest(NEW.now_seconds,unixepoch()) AND i.state=NEW.expected_state AND i.latest_revision_id IS NOT DISTINCT FROM NEW.expected_latest_revision
  AND s.surface='admin' AND s.revoked_at IS NULL AND s.expires_at>greatest(NEW.now_seconds,unixepoch()) AND u.access_status='active' AND g.permission=NEW.permission)
 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='roster_session_or_revision_changed';END IF;
 IF NEW.revision_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM roster_revisions r WHERE r.id=NEW.revision_id AND r.import_id=NEW.import_id AND r.human_reviewed=1) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='roster_review_required';END IF;
 IF NEW.collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM collections c WHERE c.id=NEW.collection_id AND c.status='active' AND c.revision=NEW.expected_collection_revision) THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='roster_collection_changed';END IF;
 RETURN NEW;
END$$;

CREATE OR REPLACE FUNCTION private.admin_invitation_actor(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb;principal text;
BEGIN
 BEGIN
  PERFORM private.set_admin_email_context(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
  principal:=private.assert_actor('admin_users.manage',NULL,NULL,2,300);
  actor:=private._admin_email_context();
  IF actor->>'principal_id' IS DISTINCT FROM principal OR actor->>'role' IS DISTINCT FROM 'owner'
   OR actor->>'identity_value' IS DISTINCT FROM 'info@ikanisa.com'
  THEN RAISE EXCEPTION 'admin_invitation_authority';END IF;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE='42501' AND SQLERRM='recent_email_sign_in_required' THEN RAISE;END IF;
  RAISE EXCEPTION 'admin_invitation_authority' USING ERRCODE='42501';
 END;
 RETURN (actor->>'session_id')::uuid;
END$$;

-- The managed mutation trigger already calls private.assert_actor; retention
-- retry/private inventory helpers already call it with privacy.review/2/300.
-- Their original guard minimum_assurance=2 and per-action TTL remain intact.
-- Do NOT alter record_mfa_projection, managed_mfa_proofs, any member privacy
-- OTP helper, auth projection triggers or genuine optional MFA cookie binding.

-- Root composed ordered fragment: 03_assisted_sms_email_provenance.sql
-- Existing rows keep their actual MFA timestamp. New email-policy claims have
-- explicit proof provenance and a NULL MFA timestamp; no history is rewritten.
ALTER TABLE app.assisted_sms_claims ADD COLUMN actor_email_proof_id uuid REFERENCES private.admin_sensitive_email_proofs(id),
 ADD COLUMN actor_email_verified_at bigint;
ALTER TABLE app.assisted_sms_claims ALTER COLUMN actor_mfa_at DROP NOT NULL;
ALTER TABLE app.assisted_sms_claims ADD CONSTRAINT assisted_sms_authentication_provenance CHECK(
 (actor_email_proof_id IS NULL AND actor_email_verified_at IS NULL AND actor_mfa_at IS NOT NULL)
 OR (actor_email_proof_id IS NOT NULL AND actor_email_verified_at>0 AND actor_mfa_at IS NULL));

CREATE FUNCTION private._admin_email_original_is_live(p_actor text,p_cookie text,p_origin text,p_public text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN PERFORM private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,false);RETURN true;
EXCEPTION WHEN SQLSTATE '42501' THEN RETURN false;END$$;

CREATE OR REPLACE VIEW app.assisted_sms_current_sessions WITH(security_invoker=true) AS
 SELECT a.id AS admin_id,l.user_id,s.auth_session_id,s.public_id,a.role,a.auth_version,
  s.issued_mfa_at AS mfa_at,s.origin,c.permission,p.id AS email_proof_id,p.verified_at AS email_verified_at
 FROM app.admin_sessions s JOIN app.admin_users a ON a.id=s.user_id
 JOIN app.admin_principal_links l ON l.admin_user_id=a.id JOIN app.users u ON u.id=l.user_id
 JOIN app.auth_sessions ss ON ss.id=s.auth_session_id AND ss.user_id=u.id
 JOIN app.admin_grants g ON g.user_id=u.id
 JOIN app.admin_account_role_capabilities c ON c.permission=g.permission AND c.role=a.role
 JOIN LATERAL(
  SELECT proof.* FROM private.admin_sensitive_email_proofs proof
  JOIN private.admin_email_operations o ON o.challenge_id=proof.challenge_id
  WHERE proof.admin_id=a.id AND proof.principal_id=u.id AND proof.original_session_id::text=s.auth_session_id
   AND proof.cookie_hash=s.token_hash AND proof.public_session_id=s.public_id AND proof.auth_version=a.auth_version
   AND proof.origin=s.origin AND proof.identity_value=lower(a.email) AND proof.purpose='admin_sensitive_operations'
   AND o.verification_state='verified' AND o.cleanup_state IN('confirmed','not_required')
   AND proof.verified_session_id=o.verified_session_id AND proof.verified_at=o.verified_amr_at
   AND proof.verified_at BETWEEN app.unixepoch()-300 AND app.unixepoch()
  ORDER BY proof.verified_at DESC,proof.recorded_at DESC,proof.id DESC LIMIT 1
 ) p ON true
 WHERE a.status='active' AND a.auth_version=s.auth_version AND u.access_status='active' AND ss.surface='admin'
  AND s.expires_at>app.unixepoch() AND ss.expires_at>app.unixepoch() AND ss.revoked_at IS NULL
  AND private._admin_email_original_is_live(a.id,s.token_hash,s.origin,s.public_id);

CREATE FUNCTION private._admin_sms_claim_email_current(p_claim app.assisted_sms_claims) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM app.assisted_sms_current_sessions s
  WHERE s.admin_id=p_claim.actor_admin_id AND s.user_id=p_claim.actor_user_id
   AND s.auth_session_id=p_claim.originating_session_id AND s.public_id=p_claim.public_session_id
   AND s.role=p_claim.actor_role AND s.auth_version=p_claim.actor_auth_version
   AND s.origin=p_claim.origin AND s.permission='assisted_sms.manage'
   AND ((p_claim.actor_email_proof_id IS NOT NULL AND p_claim.actor_mfa_at IS NULL
      AND s.email_proof_id=p_claim.actor_email_proof_id AND s.email_verified_at=p_claim.actor_email_verified_at)
    OR (p_claim.actor_email_proof_id IS NULL AND p_claim.actor_email_verified_at IS NULL
      AND p_claim.actor_mfa_at IS NOT NULL AND s.mfa_at=p_claim.actor_mfa_at)))
$$;

CREATE OR REPLACE FUNCTION private.trg_assisted_sms_claim_current() RETURNS trigger
LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
BEGIN
 -- Only existing immutable legacy rows use the legacy branch during continuation.
 IF NEW.actor_mfa_at IS NOT NULL OR NEW.actor_email_proof_id IS NULL OR NEW.actor_email_verified_at IS NULL
  OR NOT private._admin_sms_claim_email_current(NEW)
 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='sms_original_session_changed';END IF;
 IF NEW.created_seconds!=unixepoch() OR NEW.expires_seconds<=unixepoch() OR NEW.expires_seconds>unixepoch()+120
  OR NOT EXISTS(SELECT 1 FROM assisted_sms_current_jobs j WHERE j.id=NEW.job_id AND j.fence=NEW.previous_fence
   AND (j.state='queued' OR (j.state='claimed' AND EXISTS(SELECT 1 FROM assisted_sms_claims old WHERE old.id=j.active_claim_id AND old.expires_seconds<=unixepoch()))))
 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='sms_claim_changed';END IF;
 RETURN NEW;
END$$;

CREATE OR REPLACE FUNCTION private.trg_assisted_sms_confirmation_current() RETURNS trigger
LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM assisted_sms_claims claim JOIN assisted_sms_current_jobs j ON j.id=claim.job_id
  WHERE private._admin_sms_claim_email_current(claim) AND claim.id=NEW.claim_id AND claim.job_id=NEW.job_id
   AND j.state='claimed' AND j.active_claim_id=claim.id AND j.fence=NEW.fence AND claim.fence=NEW.fence
   AND claim.actor_admin_id=NEW.actor_admin_id AND claim.actor_user_id=NEW.actor_user_id
   AND claim.originating_session_id=NEW.originating_session_id AND claim.public_session_id=NEW.public_session_id
   AND claim.expires_seconds>unixepoch() AND NEW.confirmed_seconds=unixepoch() AND NEW.expires_seconds>unixepoch()
   AND NEW.expires_seconds<=least(claim.expires_seconds,unixepoch()+120)
   AND j.body_sha256=NEW.body_sha256 AND j.destination_sha256=NEW.destination_sha256 AND j.destination_revision=NEW.destination_revision)
 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='sms_confirmation_changed';END IF;
 RETURN NEW;
END$$;

CREATE OR REPLACE FUNCTION private.trg_assisted_sms_send_current() RETURNS trigger
LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM assisted_sms_confirmations confirmation JOIN assisted_sms_claims claim ON claim.id=confirmation.claim_id
  JOIN assisted_sms_current_jobs j ON j.id=claim.job_id
  WHERE private._admin_sms_claim_email_current(claim) AND confirmation.id=NEW.confirmation_id AND confirmation.claim_id=NEW.claim_id
   AND confirmation.fence=NEW.fence AND confirmation.job_id=NEW.job_id AND j.active_claim_id=claim.id
   AND j.fence=NEW.fence AND j.state='claimed' AND confirmation.actor_admin_id=NEW.actor_admin_id
   AND confirmation.actor_user_id=NEW.actor_user_id AND confirmation.originating_session_id=NEW.originating_session_id
   AND confirmation.public_session_id=NEW.public_session_id AND claim.expires_seconds>unixepoch()
   AND confirmation.expires_seconds>unixepoch() AND NEW.started_seconds=unixepoch()
   AND confirmation.body_sha256=NEW.body_sha256 AND confirmation.destination_sha256=NEW.destination_sha256
   AND confirmation.destination_revision=NEW.destination_revision AND j.body_sha256=NEW.body_sha256
   AND j.destination_sha256=NEW.destination_sha256 AND j.destination_revision=NEW.destination_revision)
 THEN RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='sms_send_start_changed';END IF;
 RETURN NEW;
END$$;

-- Existing claim-head, confirmation/send journal identity, job fences, consent,
-- source receipt, job-current, financial reversal and provider unknown guards
-- remain unchanged. No replay, new recipient or message send is authorized here.

-- Root composed ordered fragment: 04_exact_grants.sql
REVOKE ALL ON FUNCTION
 private.trg_admin_email_immutable(),private.trg_admin_email_operation_identity(),
 private._admin_email_actor(text,text,text,text,boolean),private._admin_email_context(),
 private._admin_email_same(private.admin_email_operations,jsonb),private._admin_email_result(private.admin_email_operations,boolean,boolean),
 private._admin_email_operation(jsonb,text),private._admin_email_candidate(jsonb,private.supabase_otp_challenges,boolean),
 private._admin_email_latest(jsonb),private._admin_email_current(jsonb,bigint),private.set_admin_email_context(text,text,text,text),
 private.admin_email_prepare(text,text,text,text,text),private.admin_email_send_claim(text,text,text,text,text,uuid),
 private.admin_email_send_finish(text,text,text,text,text,uuid,text),private.admin_email_verify_claim(text,text,text,text,text,uuid),
 private.admin_email_verify_finish(text,text,text,text,text,uuid,text),private.admin_email_record(text,text,text,text,text,uuid),
 private.admin_email_record_initial(text,text,text,text,text),private.admin_email_cleanup_claim(text,text,text,text,text,uuid,uuid),
 private.admin_email_cleanup_finish(text,text,text,text,text,uuid,uuid,text),private.assert_admin_email_context(bigint),
 private.admin_email_is_current(bigint),private.admin_email_status(text,text,text,text),
 private._admin_email_original_is_live(text,text,text,text),private._admin_sms_claim_email_current(app.assisted_sms_claims)
 FROM PUBLIC,anon,authenticated,collect_runtime;

GRANT EXECUTE ON FUNCTION
 private.set_admin_email_context(text,text,text,text),private.admin_email_prepare(text,text,text,text,text),
 private.admin_email_send_claim(text,text,text,text,text,uuid),private.admin_email_send_finish(text,text,text,text,text,uuid,text),
 private.admin_email_verify_claim(text,text,text,text,text,uuid),private.admin_email_verify_finish(text,text,text,text,text,uuid,text),
 private.admin_email_record(text,text,text,text,text,uuid),private.admin_email_record_initial(text,text,text,text,text),
 private.admin_email_cleanup_claim(text,text,text,text,text,uuid,uuid),private.admin_email_cleanup_finish(text,text,text,text,text,uuid,uuid,text),
 private.assert_admin_email_context(bigint),private.admin_email_is_current(bigint),private.admin_email_status(text,text,text,text),
 private._admin_email_original_is_live(text,text,text,text),private._admin_sms_claim_email_current(app.assisted_sms_claims)
 TO collect_runtime;
-- _admin_email_context is needed by the invoker mutation trigger through the
-- SECURITY DEFINER assert_actor, not directly by collect_runtime. All replaced
-- functions keep their previous owner/ACL; CREATE OR REPLACE preserves these.

-- Root composed ordered fragment: 05_admin_password_change_guard.sql
-- Existing current-password policy guard. No password hash leaves SQL.
CREATE FUNCTION private.assert_admin_password_change_context() RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; claims jsonb; has_password boolean;
BEGIN
 PERFORM private.assert_admin_email_context(300);
 actor:=private._admin_email_context();claims:=private.request_claims();
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(claims->'amr')='array' THEN claims->'amr' ELSE '[]'::jsonb END) item
  WHERE item->>'method' IN('otp','magiclink','recovery'))
  OR EXISTS(SELECT 1 FROM auth.mfa_amr_claims m WHERE m.session_id::text=actor->>'session_id' AND m.authentication_method IN('otp','magiclink','recovery')) THEN
  RAISE EXCEPTION 'password_recovery_required' USING ERRCODE='42501';END IF;
 SELECT u.encrypted_password IS NOT NULL AND u.encrypted_password<>'' INTO has_password
 FROM auth.users u WHERE u.id::text=actor->>'auth_user_id' FOR SHARE;
 IF NOT coalesce(has_password,false) THEN RAISE EXCEPTION 'password_recovery_required' USING ERRCODE='42501';END IF;
 RETURN true;
END$$;
REVOKE ALL ON FUNCTION private.assert_admin_password_change_context() FROM PUBLIC,anon,authenticated,service_role,collect_runtime;
GRANT EXECUTE ON FUNCTION private.assert_admin_password_change_context() TO collect_runtime;

COMMIT;
