-- PRIVATE UNEXECUTED CANDIDATE. Root native qualification and adoption required.
-- No managed Auth/Storage object is created, changed, or written.
-- Contract accepted fe916f8a458902ed1dd110b1297fb4744e10253ccd29b97f85b2909a8c66c025.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SET LOCAL search_path=pg_catalog,pg_temp;
DO $preflight$
BEGIN
 IF current_setting('server_version_num')::integer/10000<>17 OR to_regnamespace('private') IS NULL
  OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='collect_runtime') THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_install_precondition';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private' AND left(c.relname,14)='collect_fence_')
 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND (left(p.proname,14)='collect_fence_' OR left(p.proname,15)='_collect_fence_')) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_existing_objects_require_reconciliation';
 END IF;
END;$preflight$;

CREATE TABLE private.collect_fence_control(
 singleton boolean PRIMARY KEY CHECK(singleton),
 project_ref text NOT NULL CHECK(project_ref='rrlduytparvsjfmegalh'),
 baseline_manifest_sha256 text NOT NULL CHECK(baseline_manifest_sha256='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3'),
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 epoch bigint NOT NULL CHECK(epoch BETWEEN 1 AND 9007199254740991),
 mode text NOT NULL CHECK(mode IN('open','quiescing','fenced')),
 operation_id uuid NOT NULL,
 changed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.collect_fence_admissions(
 admission_id uuid PRIMARY KEY,
 epoch bigint NOT NULL CHECK(epoch BETWEEN 1 AND 9007199254740991),
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 kind text NOT NULL CHECK(kind IN('http_collect','http_admin','jobs')),
 state text NOT NULL CHECK(state IN('active','settled','unresolved')),
 reason text CHECK(reason IN('completed','completed_with_unknown_obligation','work_failed_before_dispatch','dispatch_unconfirmed','lease_lost','work_lost','close_unconfirmed','cancelled_before_work')),
 external_dispatches integer NOT NULL DEFAULT 0 CHECK(external_dispatches>=0),
 uncertain_dispatches integer NOT NULL DEFAULT 0 CHECK(uncertain_dispatches BETWEEN 0 AND external_dispatches),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 closed_at timestamptz,
 CHECK((state='active' AND reason IS NULL AND closed_at IS NULL AND external_dispatches=0 AND uncertain_dispatches=0)
  OR(state<>'active' AND reason IS NOT NULL AND closed_at IS NOT NULL)),
 CHECK(state<>'settled' OR (uncertain_dispatches=0 AND reason IN('completed','work_failed_before_dispatch','cancelled_before_work'))
  OR(uncertain_dispatches>0 AND reason='completed_with_unknown_obligation')),
 CHECK(reason NOT IN('work_failed_before_dispatch','cancelled_before_work') OR external_dispatches=0)
);
CREATE INDEX collect_fence_admissions_open ON private.collect_fence_admissions(state,epoch) WHERE state<>'settled';
CREATE TABLE private.collect_fence_operations(
 operation_id uuid NOT NULL,
 action text NOT NULL CHECK(action IN('initialize','begin_quiesce','drain','release')),
 epoch bigint NOT NULL CHECK(epoch BETWEEN 1 AND 9007199254740991),
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(operation_id,action)
);
-- Separate append-only owner evidence. This never changes original scheduler
-- states/receipts. A mere timeout, TTL, missing queue row, or reviewed_unknown
-- label is not local-lifecycle evidence. Root must supply actual qualified proof.
CREATE TABLE private.collect_fence_scheduler_lifecycle(
 dispatch_id uuid PRIMARY KEY,
 native_epoch text NOT NULL CHECK(native_epoch ~ '^[a-f0-9]{64}$'),
 evidence_sha256 text NOT NULL CHECK(evidence_sha256 ~ '^[a-f0-9]{64}$'),
 review_operation_id uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE private.collect_fence_control ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_fence_admissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_fence_operations ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_fence_scheduler_lifecycle ENABLE ROW LEVEL SECURITY;
-- Deliberately no singleton INSERT here. Missing control fails closed until the
-- integrated runtime has qualified and Root explicitly initializes its source.

CREATE FUNCTION private._collect_fence_no_erasure() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_history_immutable';
END;$fn$;
CREATE FUNCTION private._collect_fence_transition() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF TG_TABLE_NAME='collect_fence_admissions' THEN
  IF (NEW.admission_id,NEW.epoch,NEW.source_sha256,NEW.kind,NEW.created_at) IS DISTINCT FROM
   (OLD.admission_id,OLD.epoch,OLD.source_sha256,OLD.kind,OLD.created_at)
   OR OLD.state<>'active' OR NEW.state NOT IN('settled','unresolved') THEN
   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_history_immutable';END IF;
 ELSIF TG_TABLE_NAME='collect_fence_control' THEN
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
CREATE TRIGGER collect_fence_no_erasure BEFORE DELETE OR TRUNCATE ON private.collect_fence_control FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
CREATE TRIGGER collect_fence_no_erasure BEFORE DELETE OR TRUNCATE ON private.collect_fence_admissions FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
CREATE TRIGGER collect_fence_no_erasure BEFORE UPDATE OR DELETE OR TRUNCATE ON private.collect_fence_operations FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
CREATE TRIGGER collect_fence_no_erasure BEFORE UPDATE OR DELETE OR TRUNCATE ON private.collect_fence_scheduler_lifecycle FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
CREATE TRIGGER collect_fence_transition BEFORE UPDATE ON private.collect_fence_control FOR EACH ROW EXECUTE FUNCTION private._collect_fence_transition();
CREATE TRIGGER collect_fence_transition BEFORE UPDATE ON private.collect_fence_admissions FOR EACH ROW EXECUTE FUNCTION private._collect_fence_transition();

CREATE FUNCTION private._collect_fence_operator() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT coalesce(current_setting('role',true),'none') IN('none',pg_get_userbyid(c.relowner))
  AND (session_user=pg_get_userbyid(c.relowner) OR pg_has_role(session_user,c.relowner,'MEMBER'))
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='private' AND c.relname='collect_fence_control'
$fn$;
CREATE FUNCTION private._collect_fence_require_operator() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF private._collect_fence_operator() IS DISTINCT FROM true THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='collect_fence_forbidden';
 END IF;
END;$fn$;
CREATE FUNCTION private._collect_fence_require_runtime() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'collect_runtime'
  OR current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='collect_fence_forbidden';
 END IF;
END;$fn$;
CREATE FUNCTION private._collect_fence_require_rc(p_writing boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 -- A transaction with an older RR/SERIALIZABLE snapshot must not read stale
 -- OPEN after the controller committed FENCED and released WRITE exclusive.
 IF current_setting('transaction_isolation')<>'read committed'
  OR(p_writing AND current_setting('transaction_read_only')<>'off') THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
END;$fn$;
CREATE FUNCTION private._collect_fence_resources() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE total_count bigint;active_count bigint;operation_count bigint;proof_count bigint;
BEGIN
 SELECT count(*),count(*) FILTER(WHERE state IN('active','unresolved')) INTO total_count,active_count FROM private.collect_fence_admissions;
 SELECT count(*) INTO operation_count FROM private.collect_fence_operations;
 SELECT count(*) INTO proof_count FROM private.collect_fence_scheduler_lifecycle;
 RETURN jsonb_build_object('retainedAdmissionLimit',100000,'activeWorkLimit',8,'operationReceiptLimit',10000,'schedulerLifecycleProofLimit',10000,
  'retainedAdmissions',total_count,'activeAndUnresolvedAdmissions',active_count,'operationReceipts',operation_count,'schedulerLifecycleProofs',proof_count,
  'settledRetentionEnabled',false,'operationReceiptSaturated',operation_count>=10000,
  'capacityBlocked',total_count>=100000 OR active_count>=8 OR operation_count>=9998 OR proof_count>=10000);
END;$fn$;
CREATE FUNCTION private._collect_fence_scheduler_capacity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM private._collect_fence_require_rc(true);
 -- This short owner-only INSERT serializes with registration/control operations;
 -- it never acquires WORK/WRITE or performs provider/business work afterward.
 PERFORM 1 FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 IF (TG_TABLE_NAME='collect_fence_scheduler_lifecycle' AND (SELECT count(*) FROM private.collect_fence_scheduler_lifecycle)>=10000)
  OR(TG_TABLE_NAME='collect_fence_operations' AND (SELECT count(*) FROM private.collect_fence_operations)>=10000) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_fence_scheduler_capacity BEFORE INSERT ON private.collect_fence_scheduler_lifecycle FOR EACH ROW EXECUTE FUNCTION private._collect_fence_scheduler_capacity();
CREATE TRIGGER collect_fence_operation_capacity BEFORE INSERT ON private.collect_fence_operations FOR EACH ROW EXECUTE FUNCTION private._collect_fence_scheduler_capacity();

CREATE FUNCTION private._collect_fence_admission(p_id uuid,p_epoch bigint,p_source text)
RETURNS private.collect_fence_admissions
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;a private.collect_fence_admissions%ROWTYPE;
BEGIN
 IF p_id IS NULL OR p_epoch IS NULL OR p_source IS NULL OR p_source !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_admission';
 END IF;
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 IF c.mode NOT IN('open','quiescing') THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_closed';END IF;
 SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=p_id;
 IF NOT FOUND OR a.state<>'active' OR a.epoch<>p_epoch OR c.epoch<>p_epoch OR a.source_sha256<>p_source OR c.source_sha256<>p_source THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';
 END IF;
 RETURN a;
END;$fn$;

CREATE FUNCTION private.collect_fence_register(p_id uuid,p_source text,p_kind text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 PERFORM private._collect_fence_require_rc(true);
 IF p_id IS NULL OR p_source IS NULL OR p_source !~ '^[a-f0-9]{64}$' OR p_kind IS NULL OR p_kind NOT IN('http_collect','http_admin','jobs') THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_admission';END IF;
 PERFORM pg_advisory_xact_lock_shared(7346371,1);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 IF c.mode<>'open' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_closed';END IF;
 IF c.source_sha256<>p_source OR EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE admission_id=p_id) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 -- The control-row lock serializes all supported registrations, so concurrent
 -- requests cannot overshoot either bound. No deletion/TTL is used to make room.
 IF private._collect_fence_resources()->'capacityBlocked'='true'::jsonb THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,state) VALUES(p_id,c.epoch,p_source,p_kind,'active');
 RETURN jsonb_build_object('contractVersion',1,'admissionId',p_id,'epoch',c.epoch,'sourceSha256',p_source,'state','active','mode','open','kind',p_kind);
END;$fn$;

CREATE FUNCTION private.collect_fence_assert_work(p_id uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a private.collect_fence_admissions%ROWTYPE;v_mode text;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 PERFORM private._collect_fence_require_rc(false);
 IF NOT EXISTS(SELECT 1 FROM pg_locks WHERE locktype='advisory' AND pid=pg_backend_pid() AND database=(SELECT oid FROM pg_database WHERE datname=current_database())
  AND classid=7346371::oid AND objid=1::oid AND objsubid=2 AND mode='ShareLock' AND granted) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 a:=private._collect_fence_admission(p_id,p_epoch,p_source);
 SELECT mode INTO v_mode FROM private.collect_fence_control WHERE singleton;
 RETURN jsonb_build_object('contractVersion',1,'admissionId',p_id,'epoch',p_epoch,'sourceSha256',p_source,'state','active','mode',v_mode);
END;$fn$;

CREATE FUNCTION private.collect_fence_assert_write(p_id uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_rc(true);
 PERFORM pg_advisory_xact_lock_shared(7346371,2);
 IF p_id IS NULL AND p_epoch IS NULL AND p_source IS NULL THEN
  PERFORM private._collect_fence_require_operator();
  SELECT * INTO c FROM private.collect_fence_control WHERE singleton;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
  IF c.mode<>'open' THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_closed';END IF;
  IF private._collect_fence_resources()->'capacityBlocked'='true'::jsonb THEN
   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 ELSE
  PERFORM private._collect_fence_require_runtime();
  PERFORM private._collect_fence_admission(p_id,p_epoch,p_source);
  SELECT * INTO c FROM private.collect_fence_control WHERE singleton;
 END IF;
 RETURN jsonb_build_object('contractVersion',1,'mode',c.mode,'epoch',c.epoch);
END;$fn$;

CREATE FUNCTION private.collect_fence_close(p_id uuid,p_epoch bigint,p_source text,p_outcome text,p_reason text,p_external integer,p_uncertain integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 PERFORM private._collect_fence_require_rc(true);
 IF p_id IS NULL OR p_epoch IS NULL OR p_source IS NULL OR p_source !~ '^[a-f0-9]{64}$'
 OR p_outcome IS NULL OR p_outcome NOT IN('settled','unresolved') OR p_reason IS NULL
 OR p_reason NOT IN('completed','completed_with_unknown_obligation','work_failed_before_dispatch','dispatch_unconfirmed','lease_lost','work_lost','close_unconfirmed','cancelled_before_work')
 OR p_external IS NULL OR p_uncertain IS NULL OR p_external<0 OR p_uncertain<0 OR p_uncertain>p_external
 OR (p_outcome='settled' AND NOT((p_uncertain=0 AND p_reason IN('completed','work_failed_before_dispatch','cancelled_before_work')) OR(p_uncertain>0 AND p_reason='completed_with_unknown_obligation')))
 OR (p_outcome='unresolved' AND p_reason NOT IN('dispatch_unconfirmed','lease_lost','work_lost','close_unconfirmed'))
 OR (p_reason IN('work_failed_before_dispatch','cancelled_before_work') AND p_external<>0) THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_close';END IF;
 SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=p_id FOR UPDATE;
 IF NOT FOUND OR a.epoch<>p_epoch OR a.source_sha256<>p_source THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 IF a.state='active' THEN
  UPDATE private.collect_fence_admissions SET state=p_outcome,reason=p_reason,external_dispatches=p_external,uncertain_dispatches=p_uncertain,closed_at=clock_timestamp() WHERE admission_id=p_id;
 ELSIF a.state<>p_outcome OR a.reason<>p_reason OR a.external_dispatches<>p_external OR a.uncertain_dispatches<>p_uncertain THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 RETURN jsonb_build_object('contractVersion',1,'admissionId',p_id,'epoch',p_epoch,'sourceSha256',p_source,'state',p_outcome,'reason',p_reason,'externalDispatches',p_external,'uncertainDispatches',p_uncertain);
END;$fn$;

CREATE FUNCTION private.collect_fence_work_status(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a private.collect_fence_admissions%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 IF p_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_admission';END IF;
 SELECT * INTO a FROM private.collect_fence_admissions WHERE admission_id=p_id;
 IF NOT FOUND THEN RETURN jsonb_build_object('contractVersion',1,'found',false,'admissionId',p_id);END IF;
 RETURN jsonb_build_object('contractVersion',1,'found',true,'admissionId',p_id,'epoch',a.epoch,'sourceSha256',a.source_sha256,'state',a.state,'reason',a.reason,'externalDispatches',a.external_dispatches,'uncertainDispatches',a.uncertain_dispatches);
END;$fn$;

CREATE FUNCTION private._collect_fence_scheduler_status() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE active_jobs bigint:=0;queued bigint:=0;awaiting bigint:=0;unconfirmed bigint:=0;reviewed bigint:=0;unproven bigint:=0;
 missing_guards bigint:=0;guard_count bigint:=0;unexpected_functions bigint:=0;ops_exists boolean:=to_regnamespace('collect_ops') IS NOT NULL;has_config boolean:=to_regclass('collect_ops.jobs_config') IS NOT NULL;
 has_dispatch boolean:=to_regclass('collect_ops.jobs_dispatches') IS NOT NULL;coverage boolean:=true;
BEGIN
 -- Read counts only. Never select Vault/queue header/body/response content.
 IF to_regclass('cron.job') IS NOT NULL THEN
  EXECUTE $q$SELECT count(*) FROM cron.job WHERE jobname IN('collect-jobs-maintenance-v1','collect-google-ciphertext-expiry-v1') AND active$q$ INTO active_jobs;
 END IF;
 IF to_regclass('net.http_request_queue') IS NOT NULL THEN EXECUTE 'SELECT count(*) FROM net.http_request_queue' INTO queued;END IF;
 IF has_config IS DISTINCT FROM has_dispatch THEN coverage:=false;END IF;
 IF has_dispatch THEN
  EXECUTE $q$SELECT count(*) FILTER(WHERE state='awaiting'),count(*) FILTER(WHERE state='unconfirmed'),count(*) FILTER(WHERE state='reviewed_unknown'),
   count(*) FILTER(WHERE state IN('awaiting','unconfirmed','reviewed_unknown') AND NOT EXISTS(
    SELECT 1 FROM private.collect_fence_scheduler_lifecycle p WHERE p.dispatch_id=d.id AND p.native_epoch=d.native_epoch))
   FROM collect_ops.jobs_dispatches d$q$ INTO awaiting,unconfirmed,reviewed,unproven;
 END IF;
 SELECT count(*),count(*) FILTER(WHERE strpos(p.prosrc,E'BEGIN\n -- collect_fence_sql2_write_guard_v1\n PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);')=0
   OR p.prosecdef OR pg_get_userbyid(p.proowner)<>(SELECT pg_get_userbyid(c.relowner) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private' AND c.relname='collect_fence_control'))
 INTO guard_count,missing_guards FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='collect_ops' AND (p.proname,p.proargtypes::text) IN(('cleanup_google_expired',''),('record_jobs_readiness','3802'),('reconcile_jobs',''),('dispatch_jobs','25 2950'),('activate_jobs','25'),('review_unknown_jobs','2950 25'),('tick_jobs',''));
 SELECT count(*) INTO unexpected_functions FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='collect_ops' AND (p.prokind<>'f' OR
  (p.proname,p.proargtypes::text) NOT IN(('cleanup_google_expired',''),('record_jobs_readiness','3802'),('reconcile_jobs',''),('dispatch_jobs','25 2950'),('activate_jobs','25'),('review_unknown_jobs','2950 25'),('tick_jobs',''),('native_jobs_epoch',''),('jobs_state',''),('pause_jobs',''))
  OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE')
  OR EXISTS(SELECT 1 FROM pg_roles r WHERE r.rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer') AND has_function_privilege(r.oid,p.oid,'EXECUTE')));
 IF ops_exists AND guard_count=0 THEN coverage:=false;END IF;
 IF has_dispatch AND guard_count NOT IN(6,7) THEN coverage:=false;END IF;
 IF NOT has_dispatch AND ops_exists AND guard_count<>1 THEN coverage:=false;END IF;
 coverage:=coverage AND missing_guards=0 AND unexpected_functions=0;
 RETURN jsonb_build_object('checked',true,'coverageVerified',coverage,'namedActiveJobs',active_jobs,'pendingNativeRequests',queued,
  'awaitingDispatches',awaiting,'unconfirmedDispatches',unconfirmed,'reviewedUnknownDispatches',reviewed,'lifecycleUnproven',unproven,
  'blocking',NOT coverage OR active_jobs>0 OR queued>0 OR unproven>0);
EXCEPTION WHEN OTHERS THEN
 -- Counts are unobserved sentinels when checked=false, never evidence of absence.
 -- Returning this blocker rather than raising lets begin_quiesce COMMIT its
 -- admission closure even when a separate scheduler observation is unavailable.
 RETURN jsonb_build_object('checked',false,'coverageVerified',false,'namedActiveJobs',0,'pendingNativeRequests',0,
  'awaitingDispatches',0,'unconfirmedDispatches',0,'reviewedUnknownDispatches',0,'lifecycleUnproven',0,'blocking',true);
END;$fn$;

CREATE FUNCTION private.collect_fence_owner_status() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;active_count bigint;lost_count bigint;unknown_count bigint;scheduler jsonb;
BEGIN
 PERFORM private._collect_fence_require_operator();
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 SELECT count(*) FILTER(WHERE state='active'),count(*) FILTER(WHERE state='unresolved'),coalesce(sum(uncertain_dispatches) FILTER(WHERE state='settled'),0)
 INTO active_count,lost_count,unknown_count FROM private.collect_fence_admissions;
 scheduler:=private._collect_fence_scheduler_status();
 RETURN jsonb_build_object('contractVersion',1,'projectRef',c.project_ref,'mode',c.mode,'epoch',c.epoch,'sourceSha256',c.source_sha256,'operationId',c.operation_id,
  'activeAdmissions',active_count,'unresolvedAdmissions',lost_count,'retainedUnknownObligations',unknown_count,'schedulerStatus',scheduler,
  'applicationFenceComplete',c.mode='fenced' AND active_count=0 AND lost_count=0 AND scheduler->'blocking'='false'::jsonb,
  'wholeSystemAcceptance',false,'managedInternalWritesFenced',false,'humanMessagesFenced',false,'atomicRecoverySnapshot',false,'providerSettlement',false,'sb29Satisfied',false,
  'resourceLimits',private._collect_fence_resources());
END;$fn$;

CREATE FUNCTION private.collect_fence_initialize(p_operation uuid,p_source text,p_baseline text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM private._collect_fence_require_rc(true);
 IF p_operation IS NULL OR p_source IS NULL OR p_source !~ '^[a-f0-9]{64}$' OR p_baseline IS DISTINCT FROM 'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3' THEN
  RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_initialization';END IF;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 IF EXISTS(SELECT 1 FROM private.collect_fence_control) OR EXISTS(SELECT 1 FROM private.collect_fence_admissions) OR EXISTS(SELECT 1 FROM private.collect_fence_operations) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id)
 VALUES(true,'rrlduytparvsjfmegalh',p_baseline,p_source,1,'open',p_operation);
 INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES(p_operation,'initialize',1,p_source);
 RETURN private.collect_fence_owner_status();
END;$fn$;

CREATE FUNCTION private.collect_fence_begin_quiesce(p_operation uuid,p_epoch bigint,p_source text) RETURNS jsonb
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
 IF c.mode<>'open' OR c.epoch<>p_epoch OR c.source_sha256<>p_source OR EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id=p_operation) THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 UPDATE private.collect_fence_control SET mode='quiescing',operation_id=p_operation,changed_at=clock_timestamp() WHERE singleton;
 -- Emergency closure remains available even if the bounded audit log is full.
 -- The authoritative singleton retains the exact original operation UUID/mode;
 -- owner_status explicitly reports saturation. Reopening cannot proceed at cap.
 IF (SELECT count(*) FROM private.collect_fence_operations)<10000 THEN
  INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES(p_operation,'begin_quiesce',p_epoch,p_source);END IF;
 RETURN private.collect_fence_owner_status();
END;$fn$;

CREATE FUNCTION private.collect_fence_drain(p_operation uuid,p_epoch bigint,p_source text) RETURNS jsonb
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
 IF (SELECT count(*) FROM private.collect_fence_operations)<10000 THEN
  INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES(p_operation,'drain',p_epoch,p_source);END IF;
 RETURN private.collect_fence_owner_status();
END;$fn$;

CREATE FUNCTION private.collect_fence_release(p_operation uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE c private.collect_fence_control%ROWTYPE;scheduler jsonb;
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM private._collect_fence_require_rc(true);
 IF p_operation IS NULL OR p_epoch IS NULL OR p_source IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='collect_fence_invalid_control';END IF;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
 scheduler:=private._collect_fence_scheduler_status();
 IF c.mode<>'fenced' OR c.epoch<>p_epoch OR c.epoch>=9007199254740991 OR c.source_sha256<>p_source
 OR EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE state IN('active','unresolved'))
 OR EXISTS(SELECT 1 FROM private.collect_fence_operations WHERE operation_id=p_operation)
 OR scheduler->'blocking' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_conflict';END IF;
 -- Reserve this release receipt plus a future begin/drain pair before OPEN.
 -- No automatic retention policy is inferred to free audit capacity.
 IF (SELECT count(*) FROM private.collect_fence_operations)+1>=9998
  OR(SELECT count(*) FROM private.collect_fence_operations)+3>10000
  OR(SELECT count(*) FROM private.collect_fence_admissions)>=100000
  OR(SELECT count(*) FROM private.collect_fence_scheduler_lifecycle)>=10000 THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_capacity';END IF;
 UPDATE private.collect_fence_control SET mode='open',epoch=epoch+1,operation_id=p_operation,changed_at=clock_timestamp() WHERE singleton;
 INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES(p_operation,'release',p_epoch+1,p_source);
 RETURN private.collect_fence_owner_status();
END;$fn$;

CREATE FUNCTION private._collect_fence_statement() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE id_text text;epoch_text text;source_text text;
BEGIN
 IF current_setting('role',true)='collect_runtime' THEN
  id_text:=current_setting('collect.fence_admission_id',true);
  epoch_text:=current_setting('collect.fence_epoch',true);
  source_text:=current_setting('collect.fence_source_sha256',true);
  IF id_text IS NULL OR id_text !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
   OR epoch_text IS NULL OR epoch_text !~ '^[1-9][0-9]{0,15}$' OR source_text IS NULL OR source_text !~ '^[a-f0-9]{64}$' THEN
   RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_unavailable';END IF;
  PERFORM private.collect_fence_assert_write(id_text::uuid,epoch_text::bigint,source_text);
 ELSE
  PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 END IF;
 RETURN NULL;
END;$fn$;

-- The exact reviewed 110-relation trigger installation and all explicit grants
-- are appended by generate.py in candidate.sql, before its final COMMIT.

DO $scope$
DECLARE expected jsonb:='["app.admin_account_audit","app.admin_account_guards","app.admin_account_role_capabilities","app.admin_bridge_guards","app.admin_bridge_reconciliation_snapshots","app.admin_bridge_requests","app.admin_challenges","app.admin_email_events","app.admin_email_otp_challenges","app.admin_grants","app.admin_operator_notes","app.admin_owner_bootstrap_claims","app.admin_principal_links","app.admin_rate_limits","app.admin_role_assignments","app.admin_sessions","app.admin_users","app.assisted_sms_authorizations","app.assisted_sms_claims","app.assisted_sms_confirmations","app.assisted_sms_jobs","app.assisted_sms_outcomes","app.assisted_sms_policies","app.assisted_sms_send_starts","app.audit_log","app.auth_google_flows","app.auth_google_identities","app.auth_identity_rate_aliases","app.auth_mfa_budgets","app.auth_mfa_challenges","app.auth_mfa_claims","app.auth_mfa_factors","app.auth_mfa_revocations","app.auth_otp_challenges","app.auth_otp_throttles","app.auth_otp_verifications","app.auth_rate_buckets","app.auth_rate_claims","app.auth_refresh_tokens","app.auth_sessions","app.collections","app.contribution_posting_snapshots","app.deletion_requests","app.deletion_reviews","app.ledger_entries","app.memberships","app.momo_financial_links","app.momo_gateway_bindings","app.momo_gateway_captures","app.momo_gateway_credentials","app.momo_gateway_pairings","app.momo_parse_attempts","app.momo_processing_guards","app.momo_processing_jobs","app.momo_receiving_accounts","app.momo_source_resolutions","app.momo_transaction_sources","app.momo_transactions","app.mutation_guards","app.native_capabilities","app.native_capability_claims","app.native_completions","app.native_consents","app.native_phases","app.native_reservations","app.notification_devices","app.notification_events","app.notification_preferences","app.payment_evidence","app.payment_intents","app.payments","app.privacy_holds","app.privacy_retention_barriers","app.privacy_retention_claims","app.privacy_retention_effects","app.privacy_retention_guards","app.privacy_retention_outcomes","app.privacy_retention_plans","app.privacy_retention_tasks","app.privacy_review_claims","app.privacy_review_heads","app.privacy_review_outcomes","app.privacy_submissions","app.reconciliations","app.request_receipts","app.roster_commit_guards","app.roster_dispatch_phases","app.roster_imports","app.roster_intents","app.roster_members","app.roster_processing_records","app.roster_revisions","app.runtime_config","app.sms_receipts","app.support_requests","app.upload_objects","app.users","private.admin_invitation_attempts","private.auth_principal_links","private.bff_sessions","private.google_flow_context","private.managed_mfa_proofs","private.managed_phone_verifications","private.storage_delete_intents","private.storage_namespace","private.storage_objects","private.storage_payload_reservations","private.storage_put_intents","private.storage_upload_attempts","private.supabase_otp_challenges"]'::jsonb;observed jsonb;
BEGIN
 SELECT jsonb_agg(n.nspname||'.'||c.relname ORDER BY n.nspname,c.relname) INTO observed
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname IN('app','private') AND c.relkind IN('r','p') AND NOT(n.nspname='private' AND c.relname IN('collect_fence_control','collect_fence_admissions','collect_fence_operations','collect_fence_scheduler_lifecycle'));
 IF observed IS DISTINCT FROM expected THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='collect_fence_table_scope_drift';END IF;
END;$scope$;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_account_audit" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_account_audit" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_account_guards" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_account_guards" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_account_role_capabilities" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_account_role_capabilities" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_bridge_guards" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_bridge_guards" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_bridge_reconciliation_snapshots" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_bridge_reconciliation_snapshots" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_bridge_requests" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_bridge_requests" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_challenges" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_challenges" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_email_events" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_email_events" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_email_otp_challenges" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_email_otp_challenges" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_grants" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_grants" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_operator_notes" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_operator_notes" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_owner_bootstrap_claims" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_owner_bootstrap_claims" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_principal_links" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_principal_links" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_rate_limits" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_rate_limits" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_role_assignments" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_role_assignments" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_sessions" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_sessions" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."admin_users" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."admin_users" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."assisted_sms_authorizations" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."assisted_sms_authorizations" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."assisted_sms_claims" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."assisted_sms_claims" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."assisted_sms_confirmations" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."assisted_sms_confirmations" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."assisted_sms_jobs" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."assisted_sms_jobs" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."assisted_sms_outcomes" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."assisted_sms_outcomes" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."assisted_sms_policies" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."assisted_sms_policies" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."assisted_sms_send_starts" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."assisted_sms_send_starts" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."audit_log" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."audit_log" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_google_flows" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_google_flows" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_google_identities" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_google_identities" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_identity_rate_aliases" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_identity_rate_aliases" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_mfa_budgets" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_mfa_budgets" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_mfa_challenges" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_mfa_challenges" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_mfa_claims" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_mfa_claims" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_mfa_factors" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_mfa_factors" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_mfa_revocations" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_mfa_revocations" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_otp_challenges" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_otp_challenges" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_otp_throttles" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_otp_throttles" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_otp_verifications" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_otp_verifications" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_rate_buckets" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_rate_buckets" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_rate_claims" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_rate_claims" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_refresh_tokens" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_refresh_tokens" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."auth_sessions" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."auth_sessions" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."collections" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."collections" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."contribution_posting_snapshots" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."contribution_posting_snapshots" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."deletion_requests" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."deletion_requests" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."deletion_reviews" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."deletion_reviews" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."ledger_entries" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."ledger_entries" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."memberships" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."memberships" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_financial_links" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_financial_links" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_gateway_bindings" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_gateway_bindings" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_gateway_captures" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_gateway_captures" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_gateway_credentials" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_gateway_credentials" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_gateway_pairings" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_gateway_pairings" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_parse_attempts" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_parse_attempts" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_processing_guards" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_processing_guards" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_processing_jobs" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_processing_jobs" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_receiving_accounts" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_receiving_accounts" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_source_resolutions" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_source_resolutions" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_transaction_sources" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_transaction_sources" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."momo_transactions" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."momo_transactions" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."mutation_guards" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."mutation_guards" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."native_capabilities" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."native_capabilities" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."native_capability_claims" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."native_capability_claims" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."native_completions" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."native_completions" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."native_consents" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."native_consents" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."native_phases" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."native_phases" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."native_reservations" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."native_reservations" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."notification_devices" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."notification_devices" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."notification_events" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."notification_events" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."notification_preferences" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."notification_preferences" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."payment_evidence" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."payment_evidence" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."payment_intents" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."payment_intents" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."payments" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."payments" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_holds" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_holds" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_retention_barriers" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_retention_barriers" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_retention_claims" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_retention_claims" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_retention_effects" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_retention_effects" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_retention_guards" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_retention_guards" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_retention_outcomes" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_retention_outcomes" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_retention_plans" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_retention_plans" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_retention_tasks" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_retention_tasks" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_review_claims" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_review_claims" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_review_heads" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_review_heads" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_review_outcomes" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_review_outcomes" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."privacy_submissions" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."privacy_submissions" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."reconciliations" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."reconciliations" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."request_receipts" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."request_receipts" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."roster_commit_guards" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."roster_commit_guards" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."roster_dispatch_phases" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."roster_dispatch_phases" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."roster_imports" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."roster_imports" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."roster_intents" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."roster_intents" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."roster_members" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."roster_members" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."roster_processing_records" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."roster_processing_records" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."roster_revisions" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."roster_revisions" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."runtime_config" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."runtime_config" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."sms_receipts" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."sms_receipts" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."support_requests" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."support_requests" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."upload_objects" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."upload_objects" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "app"."users" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "app"."users" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."admin_invitation_attempts" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."admin_invitation_attempts" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."auth_principal_links" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."auth_principal_links" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."bff_sessions" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."bff_sessions" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."google_flow_context" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."google_flow_context" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."managed_mfa_proofs" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."managed_mfa_proofs" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."managed_phone_verifications" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."managed_phone_verifications" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."storage_delete_intents" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."storage_delete_intents" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."storage_namespace" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."storage_namespace" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."storage_objects" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."storage_objects" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."storage_payload_reservations" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."storage_payload_reservations" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."storage_put_intents" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."storage_put_intents" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."storage_upload_attempts" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."storage_upload_attempts" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON "private"."supabase_otp_challenges" FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE "private"."supabase_otp_challenges" ENABLE ALWAYS TRIGGER collect_fence_statement_v1;

-- Explicit revokes cover every newly created function, including functions
-- created after any prior schema-wide revoke/default privilege setting.
DO $acl$
DECLARE routine record;r text;t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['collect_fence_control','collect_fence_admissions','collect_fence_operations','collect_fence_scheduler_lifecycle'] LOOP
  EXECUTE format('REVOKE ALL ON TABLE private.%I FROM PUBLIC',t);
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_runtime','collect_importer'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('REVOKE ALL ON TABLE private.%I FROM %I',t,r);END IF;
  END LOOP;
 END LOOP;
 FOR routine IN SELECT f.oid::regprocedure AS signature FROM pg_proc f JOIN pg_namespace n ON n.oid=f.pronamespace
 WHERE n.nspname='private' AND (left(f.proname,14)='collect_fence_' OR left(f.proname,15)='_collect_fence_') LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',routine.signature);
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_runtime','collect_importer'] LOOP
   IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('REVOKE ALL ON FUNCTION %s FROM %I',routine.signature,r);END IF;
  END LOOP;
 END LOOP;
END;$acl$;
GRANT EXECUTE ON FUNCTION private.collect_fence_register(uuid,text,text),private.collect_fence_assert_work(uuid,bigint,text),private.collect_fence_assert_write(uuid,bigint,text),private.collect_fence_close(uuid,bigint,text,text,text,integer,integer),private.collect_fence_work_status(uuid) TO collect_runtime;
COMMIT;
