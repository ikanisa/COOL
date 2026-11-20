-- SYNTHETIC-ONLY MODEL. This is not a migration or a managed-Supabase script.
-- Install only in an owned, socket-only disposable PG17 cluster. The guard is
-- intentionally the first statement; there is no managed execution mode.
DO $guard$
BEGIN
 IF current_database() !~ '^collect_admission_[0-9a-f]{32}_test$'
    OR current_setting('cluster_name',true) <> 'collect_admission_recovery_synthetic_only'
    OR current_setting('listen_addresses',true) <> ''
    OR current_setting('server_version_num')::integer / 10000 <> 17
    OR session_user <> 'fixture_bootstrap'
    OR inet_server_addr() IS NOT NULL OR inet_client_addr() IS NOT NULL
 THEN RAISE EXCEPTION 'SYNTHETIC_ONLY_REFUSAL'; END IF;
END
$guard$;

CREATE SCHEMA admission_fixture;
CREATE ROLE synthetic_admission_runtime NOLOGIN;
CREATE ROLE synthetic_admission_operator NOLOGIN;
CREATE ROLE synthetic_admission_actor_one LOGIN;
CREATE ROLE synthetic_admission_actor_two LOGIN;
GRANT synthetic_admission_runtime TO synthetic_admission_actor_one,synthetic_admission_actor_two;

CREATE TABLE admission_fixture.control(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 mode text NOT NULL CHECK(mode IN ('open','quiescing')),
 epoch bigint NOT NULL CHECK(epoch>0),
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 quiesce_operation uuid UNIQUE,
 quiesce_xid xid8,
 CHECK((mode='open' AND quiesce_operation IS NULL AND quiesce_xid IS NULL) OR
       (mode='quiescing' AND quiesce_operation IS NOT NULL AND quiesce_xid IS NOT NULL))
);
CREATE TABLE admission_fixture.used_ids(id uuid PRIMARY KEY, purpose text NOT NULL);
CREATE TABLE admission_fixture.admissions(
 admission_id uuid PRIMARY KEY,epoch bigint NOT NULL,source_sha256 text NOT NULL,
 kind text NOT NULL CHECK(kind='http_collect'),state text NOT NULL CHECK(state='active'),
 external_dispatches integer NOT NULL DEFAULT 0 CHECK(external_dispatches=0),
 uncertain_dispatches integer NOT NULL DEFAULT 0 CHECK(uncertain_dispatches=0)
);
CREATE TABLE admission_fixture.tombstones(
 admission_id uuid PRIMARY KEY REFERENCES admission_fixture.admissions(admission_id),
 recovery_operation uuid NOT NULL UNIQUE,quiesce_operation uuid NOT NULL,
 admission_preimage jsonb NOT NULL,actor_closure_proven boolean NOT NULL DEFAULT false CHECK(NOT actor_closure_proven)
);
CREATE TABLE admission_fixture.obligations(
 admission_id uuid PRIMARY KEY REFERENCES admission_fixture.tombstones(admission_id),
 recovery_operation uuid NOT NULL UNIQUE,effect_status text NOT NULL CHECK(effect_status='unknown'),
 effect_scope text NOT NULL CHECK(effect_scope='all_external_effects'),
 actor_closure_proven boolean NOT NULL DEFAULT false CHECK(NOT actor_closure_proven)
);
CREATE TABLE admission_fixture.effect_intents(
 operation_id uuid PRIMARY KEY,action_id uuid NOT NULL UNIQUE,
 admission_id uuid NOT NULL REFERENCES admission_fixture.admissions(admission_id),
 effect_status text NOT NULL CHECK(effect_status='unknown')
);

-- Append-only within this model. A privileged fixture owner can bypass or
-- disable a trigger; this is not a claim about managed privileged actors.
CREATE FUNCTION admission_fixture.reject_change() RETURNS trigger LANGUAGE plpgsql VOLATILE AS $$
BEGIN RAISE EXCEPTION 'SYNTHETIC_APPEND_ONLY'; END $$;
CREATE TRIGGER admission_no_change BEFORE UPDATE OR DELETE ON admission_fixture.admissions FOR EACH ROW EXECUTE FUNCTION admission_fixture.reject_change();
CREATE TRIGGER used_ids_no_change BEFORE UPDATE OR DELETE ON admission_fixture.used_ids FOR EACH ROW EXECUTE FUNCTION admission_fixture.reject_change();
CREATE TRIGGER tombstone_no_change BEFORE UPDATE OR DELETE ON admission_fixture.tombstones FOR EACH ROW EXECUTE FUNCTION admission_fixture.reject_change();
CREATE TRIGGER obligation_no_change BEFORE UPDATE OR DELETE ON admission_fixture.obligations FOR EACH ROW EXECUTE FUNCTION admission_fixture.reject_change();
CREATE TRIGGER intent_no_change BEFORE UPDATE OR DELETE ON admission_fixture.effect_intents FOR EACH ROW EXECUTE FUNCTION admission_fixture.reject_change();
CREATE TRIGGER admission_no_truncate BEFORE TRUNCATE ON admission_fixture.admissions FOR EACH STATEMENT EXECUTE FUNCTION admission_fixture.reject_change();
CREATE TRIGGER used_ids_no_truncate BEFORE TRUNCATE ON admission_fixture.used_ids FOR EACH STATEMENT EXECUTE FUNCTION admission_fixture.reject_change();
CREATE TRIGGER tombstone_no_truncate BEFORE TRUNCATE ON admission_fixture.tombstones FOR EACH STATEMENT EXECUTE FUNCTION admission_fixture.reject_change();
CREATE TRIGGER obligation_no_truncate BEFORE TRUNCATE ON admission_fixture.obligations FOR EACH STATEMENT EXECUTE FUNCTION admission_fixture.reject_change();
CREATE TRIGGER intent_no_truncate BEFORE TRUNCATE ON admission_fixture.effect_intents FOR EACH STATEMENT EXECUTE FUNCTION admission_fixture.reject_change();

-- All mutating operations first hold the control row. This serializes the
-- small synthetic bounds. The lock numbers are synthetic, not production keys.
CREATE FUNCTION admission_fixture.claim_id(p_id uuid,p_purpose text) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,admission_fixture AS $$
BEGIN
 IF p_id IS NULL OR p_purpose IS NULL OR (SELECT count(*) FROM admission_fixture.used_ids)>=128
 THEN RAISE EXCEPTION 'SYNTHETIC_ID_BOUND'; END IF;
 INSERT INTO admission_fixture.used_ids VALUES(p_id,p_purpose);
EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'SYNTHETIC_ID_REPLAY';
END $$;
-- A transaction may have taken a REPEATABLE READ or SERIALIZABLE snapshot
-- before quiescence. Re-reading under that snapshot does not see a later
-- tombstone, even after waiting for an advisory lock. Fail closed instead.
CREATE FUNCTION admission_fixture.require_read_committed() RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,admission_fixture AS $$
BEGIN
 IF current_setting('transaction_isolation') IS DISTINCT FROM 'read committed'
 THEN RAISE EXCEPTION 'SYNTHETIC_READ_COMMITTED_REQUIRED'; END IF;
END $$;

CREATE FUNCTION admission_fixture.register(p_id uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,admission_fixture AS $$
DECLARE c admission_fixture.control%ROWTYPE;
BEGIN
 PERFORM admission_fixture.require_read_committed();
 PERFORM pg_advisory_xact_lock_shared(777701);
 SELECT * INTO STRICT c FROM admission_fixture.control WHERE singleton FOR UPDATE;
 IF c.mode<>'open' OR c.epoch IS DISTINCT FROM p_epoch OR c.source_sha256 IS DISTINCT FROM p_source THEN RAISE EXCEPTION 'SYNTHETIC_REGISTER_REFUSED'; END IF;
 IF (SELECT count(*) FROM admission_fixture.admissions)>=16 THEN RAISE EXCEPTION 'SYNTHETIC_ADMISSION_BOUND'; END IF;
 PERFORM admission_fixture.claim_id(p_id,'admission');
 INSERT INTO admission_fixture.admissions(admission_id,epoch,source_sha256,kind,state) VALUES(p_id,p_epoch,p_source,'http_collect','active');
 RETURN jsonb_build_object('registered',true,'fixture',true);
END $$;

CREATE FUNCTION admission_fixture.assert_work(p_id uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,admission_fixture AS $$
DECLARE c admission_fixture.control%ROWTYPE;a admission_fixture.admissions%ROWTYPE;
BEGIN
 PERFORM admission_fixture.require_read_committed();
 PERFORM pg_advisory_xact_lock_shared(777701);
 SELECT * INTO STRICT c FROM admission_fixture.control WHERE singleton;
 SELECT * INTO a FROM admission_fixture.admissions WHERE admission_id=p_id;
 IF NOT FOUND OR c.mode<>'open' OR c.epoch IS DISTINCT FROM p_epoch OR c.source_sha256 IS DISTINCT FROM p_source OR
    a.epoch IS DISTINCT FROM p_epoch OR a.source_sha256 IS DISTINCT FROM p_source OR
    EXISTS(SELECT 1 FROM admission_fixture.tombstones WHERE admission_id=p_id)
 THEN RAISE EXCEPTION 'SYNTHETIC_ASSERT_REFUSED'; END IF;
 RETURN jsonb_build_object('asserted',true,'fixture',true,'external_effect_permit',false);
END $$;

-- A prepared external operation remains unknown even if the caller later
-- times out or receives an ambiguous acknowledgement. This function never
-- performs an external call, and the caller must not call one before commit.
CREATE FUNCTION admission_fixture.prepare_effect(p_admission uuid,p_epoch bigint,p_source text,p_operation uuid,p_action uuid) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,admission_fixture AS $$
DECLARE c admission_fixture.control%ROWTYPE;a admission_fixture.admissions%ROWTYPE;
BEGIN
 PERFORM admission_fixture.require_read_committed();
 PERFORM pg_advisory_xact_lock_shared(777701);
 SELECT * INTO STRICT c FROM admission_fixture.control WHERE singleton FOR UPDATE;
 SELECT * INTO a FROM admission_fixture.admissions WHERE admission_id=p_admission;
 IF NOT FOUND OR c.mode<>'open' OR c.epoch IS DISTINCT FROM p_epoch OR c.source_sha256 IS DISTINCT FROM p_source OR
    a.epoch IS DISTINCT FROM p_epoch OR a.source_sha256 IS DISTINCT FROM p_source OR p_operation IS NULL OR p_action IS NULL OR p_operation=p_action OR
    EXISTS(SELECT 1 FROM admission_fixture.tombstones WHERE admission_id=p_admission)
 THEN RAISE EXCEPTION 'SYNTHETIC_EFFECT_REFUSED'; END IF;
 IF EXISTS(SELECT 1 FROM admission_fixture.used_ids WHERE id IN (p_operation,p_action)) THEN RAISE EXCEPTION 'SYNTHETIC_ID_REPLAY'; END IF;
 -- No trustworthy production scope or provider operation identity is known.
 -- Conservatively block all further effect preparation while any effect or
 -- admission obligation remains unresolved, including a newly chosen ID.
 IF EXISTS(SELECT 1 FROM admission_fixture.effect_intents WHERE effect_status='unknown') OR
    EXISTS(SELECT 1 FROM admission_fixture.obligations WHERE effect_status='unknown')
 THEN RAISE EXCEPTION 'SYNTHETIC_UNRESOLVED_EFFECT_BLOCKS_ALL'; END IF;
 PERFORM admission_fixture.claim_id(p_operation,'effect_operation');
 PERFORM admission_fixture.claim_id(p_action,'logical_action');
 INSERT INTO admission_fixture.effect_intents VALUES(p_operation,p_action,p_admission,'unknown');
 RETURN jsonb_build_object('effect_status','unknown','fixture',true,'provider_called',false);
END $$;

-- WORK then WRITE is enforced in this candidate. Transaction-scoped locks do
-- not revoke an assertion already acknowledged to an older process.
CREATE FUNCTION admission_fixture.quiesce(p_operation uuid,p_epoch bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,admission_fixture AS $$
DECLARE c admission_fixture.control%ROWTYPE;
BEGIN
 PERFORM admission_fixture.require_read_committed();
 PERFORM pg_advisory_xact_lock(777701);
 PERFORM pg_advisory_xact_lock(777702);
 SELECT * INTO STRICT c FROM admission_fixture.control WHERE singleton FOR UPDATE;
 IF c.mode<>'open' OR c.epoch IS DISTINCT FROM p_epoch OR c.source_sha256 IS DISTINCT FROM p_source THEN RAISE EXCEPTION 'SYNTHETIC_QUIESCE_REFUSED'; END IF;
 PERFORM admission_fixture.claim_id(p_operation,'quiesce');
 UPDATE admission_fixture.control SET mode='quiescing',quiesce_operation=p_operation,quiesce_xid=pg_current_xact_id() WHERE singleton;
 RETURN jsonb_build_object('quiescence_write_pending_commit',true,'fixture',true,'actor_closure_proven',false);
END $$;

CREATE FUNCTION admission_fixture.tombstone(p_recovery uuid,p_quiesce uuid,p_admission uuid,p_preimage jsonb) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,admission_fixture AS $$
DECLARE c admission_fixture.control%ROWTYPE;actual jsonb;
BEGIN
 PERFORM admission_fixture.require_read_committed();
 PERFORM pg_advisory_xact_lock(777701);
 PERFORM pg_advisory_xact_lock(777702);
 SELECT * INTO STRICT c FROM admission_fixture.control WHERE singleton FOR UPDATE;
 IF c.mode<>'quiescing' OR c.quiesce_operation IS DISTINCT FROM p_quiesce OR
    c.quiesce_xid=pg_current_xact_id() OR pg_xact_status(c.quiesce_xid) IS DISTINCT FROM 'committed'
 THEN RAISE EXCEPTION 'SYNTHETIC_COMMITTED_QUIESCE_REQUIRED'; END IF;
 SELECT to_jsonb(a) INTO actual FROM admission_fixture.admissions a WHERE a.admission_id=p_admission;
 IF actual IS NULL OR actual IS DISTINCT FROM p_preimage OR actual->>'epoch'<>c.epoch::text OR actual->>'source_sha256'<>c.source_sha256
 THEN RAISE EXCEPTION 'SYNTHETIC_PREIMAGE_CHANGED'; END IF;
 IF (SELECT count(*) FROM admission_fixture.tombstones)>=16 THEN RAISE EXCEPTION 'SYNTHETIC_TOMBSTONE_BOUND'; END IF;
 PERFORM admission_fixture.claim_id(p_recovery,'recovery');
 INSERT INTO admission_fixture.tombstones(admission_id,recovery_operation,quiesce_operation,admission_preimage) VALUES(p_admission,p_recovery,p_quiesce,actual);
 INSERT INTO admission_fixture.obligations(admission_id,recovery_operation,effect_status,effect_scope) VALUES(p_admission,p_recovery,'unknown','all_external_effects');
 RETURN jsonb_build_object('tombstone_written',true,'effect_status','unknown','actor_closure_proven',false,'cutover_authorized',false,'fixture',true);
END $$;

CREATE FUNCTION admission_fixture.status() RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,admission_fixture AS $$
DECLARE value jsonb;
BEGIN
 PERFORM admission_fixture.require_read_committed();
 SELECT jsonb_build_object('fixture',true,'mode',c.mode,'admissions',(SELECT count(*) FROM admission_fixture.admissions),
  'tombstones',(SELECT count(*) FROM admission_fixture.tombstones),'unknown_obligations',(SELECT count(*) FROM admission_fixture.obligations WHERE effect_status='unknown'),
  'unknown_effect_intents',(SELECT count(*) FROM admission_fixture.effect_intents WHERE effect_status='unknown'),
  'actor_closure_proven',false,'cutover_authorized',false,'release_authorized',false,'provider_settlement_proven',false)
 INTO value FROM admission_fixture.control c WHERE c.singleton;
 RETURN value;
END
$$;
CREATE FUNCTION admission_fixture.close_or_release() RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,admission_fixture AS $$
BEGIN RAISE EXCEPTION 'SYNTHETIC_CLOSE_RELEASE_UNQUALIFIED'; END $$;
CREATE FUNCTION admission_fixture.resolve_unknown_effect() RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,admission_fixture AS $$
BEGIN RAISE EXCEPTION 'SYNTHETIC_EFFECT_RESOLUTION_UNIMPLEMENTED'; END $$;
CREATE FUNCTION admission_fixture.upgrade_source() RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,admission_fixture AS $$
BEGIN RAISE EXCEPTION 'SYNTHETIC_SOURCE_UPGRADE_UNQUALIFIED'; END $$;

REVOKE ALL ON SCHEMA admission_fixture FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA admission_fixture FROM PUBLIC,synthetic_admission_runtime,synthetic_admission_operator;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA admission_fixture FROM PUBLIC,synthetic_admission_runtime,synthetic_admission_operator;
GRANT USAGE ON SCHEMA admission_fixture TO synthetic_admission_runtime,synthetic_admission_operator;
GRANT EXECUTE ON FUNCTION admission_fixture.register(uuid,bigint,text),admission_fixture.assert_work(uuid,bigint,text),
 admission_fixture.prepare_effect(uuid,bigint,text,uuid,uuid),admission_fixture.close_or_release() TO synthetic_admission_runtime;
GRANT EXECUTE ON FUNCTION admission_fixture.quiesce(uuid,bigint,text),admission_fixture.tombstone(uuid,uuid,uuid,jsonb),
 admission_fixture.status(),admission_fixture.close_or_release(),admission_fixture.resolve_unknown_effect(),admission_fixture.upgrade_source() TO synthetic_admission_operator;
