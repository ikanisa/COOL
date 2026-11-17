-- UNREGISTERED, DEFAULT-OFF DRAFT.  Native observations are admitted only as
-- unresolved canonical sources; this migration grants no wallet, transaction,
-- member, or ledger authority. Live rollout also requires the
-- scoped reader and retention-catalog changes documented with this draft.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR to_regclass('private.burimunsi_unresolved_observations') IS NULL
  OR to_regprocedure('private.burimunsi_observation_own(text,boolean)') IS NULL
  OR to_regclass('private.burimunsi_native_receipt_origins') IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='app.sms_receipts'::regclass
       AND attname='originating_session_id' AND attnotnull AND NOT attisdropped)
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='app.sms_receipts'::regclass
       AND attname='receiver_hash' AND attnotnull AND NOT attisdropped)
  OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='app.sms_receipts'::regclass
       AND conname='fk_sms_receipts_0' AND contype='f'
       AND confrelid='app.auth_sessions'::regclass AND convalidated)
 THEN RAISE EXCEPTION 'burimunsi_native_intake_precondition' USING ERRCODE='55000'; END IF;
END;$preflight$;

-- The genuine managed-session FK remains intact.  Its absence is allowed only
-- for a source backed by the immutable native provenance enforced below.
ALTER TABLE app.sms_receipts ALTER COLUMN originating_session_id DROP NOT NULL;
ALTER TABLE app.sms_receipts ALTER COLUMN receiver_hash DROP NOT NULL;
ALTER TABLE app.sms_receipts ADD CONSTRAINT burimunsi_native_origin_shape CHECK(
 (originating_session_id IS NOT NULL AND receiver_hash IS NOT NULL) OR
 (originating_session_id IS NULL AND receiver_hash IS NULL));

CREATE TABLE private.burimunsi_native_receipt_origins(
 source_id text PRIMARY KEY REFERENCES private.burimunsi_unresolved_observations(source_id),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 account_id uuid NOT NULL,principal_user_id text NOT NULL REFERENCES app.users(id),
 installation_id uuid NOT NULL,grant_id uuid NOT NULL,grant_version bigint NOT NULL CHECK(grant_version>0),
 capture_session_id uuid NOT NULL REFERENCES private.burimunsi_sessions(id),
 admitting_session_id uuid NOT NULL REFERENCES private.burimunsi_sessions(id),
 request_id uuid NOT NULL,fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 body_sha256 text NOT NULL CHECK(body_sha256 ~ '^[a-f0-9]{64}$'),
 object_sha256 text NOT NULL CHECK(object_sha256 ~ '^[a-f0-9]{64}$'),
 admitted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id),
 FOREIGN KEY(grant_id,collection_id) REFERENCES private.burimunsi_device_grants(id,collection_id),
 FOREIGN KEY(source_id) REFERENCES app.sms_receipts(id) DEFERRABLE INITIALLY DEFERRED
);
ALTER TABLE private.burimunsi_native_receipt_origins ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_native_receipt_origins FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_native_receipt_origins FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE POLICY burimunsi_native_receipt_origin_frame ON private.burimunsi_native_receipt_origins TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.native_receipt_frame',true)='1')
 WITH CHECK(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.native_receipt_frame',true)='1');
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
 ON private.burimunsi_native_receipt_origins FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.burimunsi_native_receipt_origins ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE FUNCTION private.burimunsi_native_receipt_origin_immutable() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN RAISE EXCEPTION 'burimunsi_native_origin_immutable' USING ERRCODE='23514'; END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_receipt_origin_immutable() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_native_receipt_origin_immutable BEFORE UPDATE OR DELETE
 ON private.burimunsi_native_receipt_origins FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_receipt_origin_immutable();
ALTER TABLE private.burimunsi_native_receipt_origins ENABLE ALWAYS TRIGGER burimunsi_native_receipt_origin_immutable;

-- At COMMIT, every null managed origin must have exactly the corresponding
-- native observation and an unresolved job.  Managed origins stay unchanged.
CREATE FUNCTION private.burimunsi_native_receipt_invariant() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE origin private.burimunsi_native_receipt_origins%ROWTYPE;
 r app.sms_receipts%ROWTYPE;j app.momo_processing_jobs%ROWTYPE;
 k text;
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 IF TG_TABLE_NAME='sms_receipts' THEN k:=NEW.id; ELSE k:=NEW.source_id; END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO origin FROM private.burimunsi_native_receipt_origins WHERE source_id=k;
 SELECT * INTO r FROM app.sms_receipts WHERE id=k;
 IF r.id IS NULL THEN RAISE EXCEPTION 'burimunsi_native_receipt_missing' USING ERRCODE='23514'; END IF;
 IF r.originating_session_id IS NULL THEN
  SELECT * INTO j FROM app.momo_processing_jobs WHERE raw_sms_id=k;
  IF origin.source_id IS NULL OR r.receiver_hash IS NOT NULL OR
    ROW(r.owner_user_id,r.client_envelope_id,r.body_sha256,r.object_sha256,r.object_key,r.evidence_level)
    IS DISTINCT FROM ROW(origin.principal_user_id,origin.request_id::text,origin.body_sha256,origin.object_sha256,'sms/'||k,'client_received') OR
    j.raw_sms_id IS NULL OR j.state NOT IN('source_unresolved','processing','needs_review') OR j.mode<>'live' OR
    j.binding_id IS NOT NULL OR j.binding_version IS NOT NULL OR j.receiving_account_id IS NOT NULL OR
    NOT coalesce(((j.state='source_unresolved' AND j.attempt_count=0 AND j.last_error IS NULL AND j.lease_token IS NULL AND j.lease_until IS NULL)
      OR (j.state='processing' AND j.attempt_count=1 AND j.last_error IN('momo_v2:preflight','momo_v2:provider_dispatch') AND j.lease_token IS NOT NULL AND j.lease_until IS NOT NULL)
      OR (j.state='needs_review' AND j.attempt_count=1 AND j.last_error IN('native_source_unverified','momo_v2:provider_outcome_unknown') AND j.lease_token IS NULL AND j.lease_until IS NULL)),false)
  THEN RAISE EXCEPTION 'burimunsi_native_receipt_mismatch' USING ERRCODE='23514'; END IF;
 ELSIF origin.source_id IS NOT NULL OR r.receiver_hash IS NULL THEN
  RAISE EXCEPTION 'burimunsi_native_receipt_mismatch' USING ERRCODE='23514';
 END IF;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RETURN NULL;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_receipt_invariant() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE CONSTRAINT TRIGGER burimunsi_native_receipt_invariant AFTER INSERT OR UPDATE ON app.sms_receipts
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_receipt_invariant();
CREATE CONSTRAINT TRIGGER burimunsi_native_origin_invariant AFTER INSERT ON private.burimunsi_native_receipt_origins
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_receipt_invariant();

-- Native jobs can enter only the narrowly bounded provisional parsing states.
-- A direct runtime UPDATE never has authority to create those transitions.
CREATE FUNCTION private.burimunsi_native_unresolved_job_guard() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE is_native boolean;
BEGIN
 SELECT EXISTS(SELECT 1 FROM app.sms_receipts WHERE id=OLD.raw_sms_id AND originating_session_id IS NULL) INTO is_native;
 IF is_native AND TG_OP='DELETE' THEN RAISE EXCEPTION 'burimunsi_native_source_unresolved' USING ERRCODE='23514';END IF;
 IF is_native AND (current_user<>'postgres' OR
  ROW(NEW.raw_sms_id,NEW.binding_id,NEW.binding_version,NEW.receiving_account_id,NEW.mode,NEW.created_at)
   IS DISTINCT FROM ROW(OLD.raw_sms_id,OLD.binding_id,OLD.binding_version,OLD.receiving_account_id,OLD.mode,OLD.created_at) OR
  NOT coalesce(((OLD.state='source_unresolved' AND NEW.state='processing' AND NEW.attempt_count=1 AND NEW.last_error='momo_v2:preflight' AND NEW.lease_token IS NOT NULL AND NEW.lease_until IS NOT NULL)
    OR (OLD.state='processing' AND OLD.last_error='momo_v2:preflight' AND NEW.state='processing' AND NEW.attempt_count=1 AND NEW.last_error IN('momo_v2:preflight','momo_v2:provider_dispatch') AND NEW.lease_token IS NOT NULL AND NEW.lease_until IS NOT NULL)
    OR (OLD.state='processing' AND OLD.last_error='momo_v2:provider_dispatch' AND NEW.state='needs_review' AND NEW.attempt_count=1 AND NEW.last_error IN('native_source_unverified','momo_v2:provider_outcome_unknown') AND NEW.lease_token IS NULL AND NEW.lease_until IS NULL)),false))
 THEN RAISE EXCEPTION 'burimunsi_native_source_unresolved' USING ERRCODE='23514'; END IF;
 IF TG_OP='DELETE' THEN RETURN OLD; END IF;RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_unresolved_job_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_native_unresolved_job_guard BEFORE UPDATE OR DELETE ON app.momo_processing_jobs
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_unresolved_job_guard();
ALTER TABLE app.momo_processing_jobs ENABLE ALWAYS TRIGGER burimunsi_native_unresolved_job_guard;

-- A provisional parse attempt is never eligible for canonical financial facts.
CREATE FUNCTION private.burimunsi_native_attempt_guard() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF EXISTS(SELECT 1 FROM app.sms_receipts r WHERE r.id=NEW.raw_sms_id AND r.originating_session_id IS NULL)
  AND (current_user<>'postgres' OR NEW.outcome<>'needs_review' OR NEW.attempt_number<>1)
 THEN RAISE EXCEPTION 'burimunsi_native_source_unresolved' USING ERRCODE='23514';END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_attempt_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_native_attempt_guard BEFORE INSERT ON app.momo_parse_attempts
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_attempt_guard();
ALTER TABLE app.momo_parse_attempts ENABLE ALWAYS TRIGGER burimunsi_native_attempt_guard;
CREATE FUNCTION private.burimunsi_native_no_financial_facts() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE blocked boolean;
BEGIN
 IF TG_TABLE_NAME='momo_transactions' THEN
  SELECT EXISTS(SELECT 1 FROM app.momo_parse_attempts a JOIN app.sms_receipts r ON r.id=a.raw_sms_id
   WHERE a.id=NEW.parse_attempt_id AND r.originating_session_id IS NULL) INTO blocked;
 ELSE
  SELECT EXISTS(SELECT 1 FROM app.sms_receipts r WHERE r.id=NEW.raw_sms_id AND r.originating_session_id IS NULL)
   OR EXISTS(SELECT 1 FROM app.momo_parse_attempts a JOIN app.sms_receipts r ON r.id=a.raw_sms_id
    WHERE a.id=NEW.parse_attempt_id AND r.originating_session_id IS NULL) INTO blocked;
 END IF;
 IF blocked THEN RAISE EXCEPTION 'burimunsi_native_source_unresolved' USING ERRCODE='23514';END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_no_financial_facts() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_native_no_financial_facts BEFORE INSERT ON app.momo_transactions
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_no_financial_facts();
CREATE TRIGGER burimunsi_native_no_financial_facts BEFORE INSERT ON app.momo_transaction_sources
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_no_financial_facts();
ALTER TABLE app.momo_transactions ENABLE ALWAYS TRIGGER burimunsi_native_no_financial_facts;
ALTER TABLE app.momo_transaction_sources ENABLE ALWAYS TRIGGER burimunsi_native_no_financial_facts;

CREATE FUNCTION private.burimunsi_stage_native_receipt(p_source text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;proof jsonb;o private.burimunsi_unresolved_observations%ROWTYPE;
 prior private.burimunsi_native_receipt_origins%ROWTYPE;r app.sms_receipts%ROWTYPE;j app.momo_processing_jobs%ROWTYPE;
 created boolean:=false;at_text text:=app.strftime('%Y-%m-%dT%H:%M:%fZ');
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
 old_observation text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();a:=private.burimunsi_observation_actor(false);
 proof:=private.burimunsi_observation_own(p_source,false);
 IF proof IS NULL THEN RAISE EXCEPTION 'burimunsi_native_source_missing' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO STRICT o FROM private.burimunsi_unresolved_observations WHERE source_id=p_source;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_observation,''),true);
 IF ROW(o.collection_id,o.account_id,o.principal_user_id,o.installation_id,o.grant_id,o.grant_version,o.body_sha256,o.object_sha256)
  IS DISTINCT FROM ROW(a->>'collectionId',(a->>'accountId')::uuid,a->>'principalUserId',(a->>'installationId')::uuid,
    (a->>'grantId')::uuid,(a->>'grantVersion')::bigint,proof->>'bodySha256',proof->>'object_sha256')
 THEN RAISE EXCEPTION 'burimunsi_native_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO prior FROM private.burimunsi_native_receipt_origins WHERE source_id=p_source;
 IF NOT FOUND THEN
  INSERT INTO private.burimunsi_native_receipt_origins(source_id,collection_id,account_id,principal_user_id,installation_id,
   grant_id,grant_version,capture_session_id,admitting_session_id,request_id,fingerprint,body_sha256,object_sha256)
  VALUES(o.source_id,o.collection_id,o.account_id,o.principal_user_id,o.installation_id,o.grant_id,o.grant_version,
   o.native_session_id,(a->>'sessionId')::uuid,o.request_id,o.fingerprint,o.body_sha256,o.object_sha256);
  INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,
   object_key,object_sha256,size_bytes,received_at_device,status,evidence_level,created_at)
  VALUES(o.source_id,o.principal_user_id,NULL,o.request_id::text,o.body_sha256,NULL,o.object_key,o.object_sha256,
   o.size_bytes,NULL,'under_review','client_received',at_text);
  INSERT INTO app.momo_processing_jobs(raw_sms_id,binding_id,binding_version,receiving_account_id,mode,state,
   available_at,created_at,updated_at) VALUES(o.source_id,NULL,NULL,NULL,'live','source_unresolved',app.unixepoch(),at_text,at_text);
  INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
   VALUES(a->>'principalUserId',a->>'sessionId','sms.native_source.admitted','sms_receipt',o.source_id,o.request_id::text,
    jsonb_build_object('source_kind','native_observation','collection_id',o.collection_id,'financial_effects',0)::text,at_text);
  created:=true;
 ELSE
  IF ROW(prior.collection_id,prior.account_id,prior.principal_user_id,prior.installation_id,prior.grant_id,prior.grant_version,
    prior.capture_session_id,prior.request_id,prior.fingerprint,prior.body_sha256,prior.object_sha256)
   IS DISTINCT FROM ROW(o.collection_id,o.account_id,o.principal_user_id,o.installation_id,o.grant_id,o.grant_version,
    o.native_session_id,o.request_id,o.fingerprint,o.body_sha256,o.object_sha256)
  THEN RAISE EXCEPTION 'burimunsi_native_source_changed' USING ERRCODE='40001';END IF;
 END IF;
 SELECT * INTO STRICT r FROM app.sms_receipts WHERE id=p_source;
 SELECT * INTO STRICT j FROM app.momo_processing_jobs WHERE raw_sms_id=p_source;
 IF r.originating_session_id IS NOT NULL OR r.receiver_hash IS NOT NULL OR r.owner_user_id IS DISTINCT FROM o.principal_user_id OR
  r.client_envelope_id IS DISTINCT FROM o.request_id::text OR r.body_sha256 IS DISTINCT FROM o.body_sha256 OR
  r.object_key IS DISTINCT FROM o.object_key OR r.object_sha256 IS DISTINCT FROM o.object_sha256 OR r.size_bytes IS DISTINCT FROM o.size_bytes OR
  j.state NOT IN('source_unresolved','processing','needs_review') OR j.binding_id IS NOT NULL OR j.binding_version IS NOT NULL OR j.receiving_account_id IS NOT NULL
 THEN RAISE EXCEPTION 'burimunsi_native_source_changed' USING ERRCODE='40001';END IF;
 IF private.burimunsi_observation_own(p_source,false) IS DISTINCT FROM proof THEN
  RAISE EXCEPTION 'burimunsi_native_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('sourceId',o.source_id,'collectionId',o.collection_id,'state','source_unresolved',
  'financialEffects',0,'created',created);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_observation,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_stage_native_receipt(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_stage_native_receipt(text) TO collect_runtime;

-- Exactly one provisional provider dispatch is allowed for this source. A
-- dispatch with an unknown result is retained and is never blindly repeated.
-- Every step independently proves the current real PIN actor, consent,
-- committed storage journal and the unchanged capture-time detection tuple.
CREATE FUNCTION private.burimunsi_native_parse_begin(p_source text,p_lease uuid,p_profile_sha text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE proof jsonb;profile jsonb;j app.momo_processing_jobs%ROWTYPE;at_s bigint:=floor(extract(epoch FROM clock_timestamp()))::bigint;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 IF p_lease IS NULL OR p_profile_sha IS NULL OR p_profile_sha !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'burimunsi_native_parse_invalid' USING ERRCODE='22023';END IF;
 proof:=private.burimunsi_observation_own(p_source,true);
 profile:=private.burimunsi_observation_hint_profile(p_source);
 IF proof IS NULL OR profile IS NULL OR profile->>'profileSha256' IS DISTINCT FROM p_profile_sha THEN
  RAISE EXCEPTION 'burimunsi_native_parse_changed' USING ERRCODE='40001';END IF;
 SELECT * INTO j FROM app.momo_processing_jobs WHERE raw_sms_id=p_source FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM app.sms_receipts WHERE id=p_source AND originating_session_id IS NULL)
  OR j.receiving_account_id IS NOT NULL OR j.binding_id IS NOT NULL OR j.binding_version IS NOT NULL OR j.mode<>'live' THEN
  RAISE EXCEPTION 'burimunsi_native_parse_changed' USING ERRCODE='40001';END IF;
 IF NOT (j.state='source_unresolved' AND j.attempt_count=0 AND j.last_error IS NULL OR
   j.state='processing' AND j.attempt_count=1 AND j.last_error='momo_v2:preflight' AND j.lease_until<=at_s) THEN
  RETURN jsonb_build_object('sourceId',p_source,'started',false,'state',j.state,'financialEffects',0);
 END IF;
 UPDATE app.momo_processing_jobs SET state='processing',attempt_count=1,lease_token=p_lease::text,lease_until=at_s+120,
  last_error='momo_v2:preflight',updated_at=app.strftime('%Y-%m-%dT%H:%M:%fZ') WHERE raw_sms_id=p_source;
 RETURN jsonb_build_object('sourceId',p_source,'started',true,'state','processing','financialEffects',0);
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_parse_begin(text,uuid,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_parse_begin(text,uuid,text) TO collect_runtime;

CREATE FUNCTION private.burimunsi_native_parse_dispatch(p_source text,p_lease uuid,p_profile_sha text) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE proof jsonb;profile jsonb;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 proof:=private.burimunsi_observation_own(p_source,true);profile:=private.burimunsi_observation_hint_profile(p_source);
 IF proof IS NULL OR profile IS NULL OR profile->>'profileSha256' IS DISTINCT FROM p_profile_sha THEN
  RAISE EXCEPTION 'burimunsi_native_parse_changed' USING ERRCODE='40001';END IF;
 UPDATE app.momo_processing_jobs SET last_error='momo_v2:provider_dispatch',updated_at=app.strftime('%Y-%m-%dT%H:%M:%fZ')
  WHERE raw_sms_id=p_source AND state='processing' AND last_error='momo_v2:preflight' AND lease_token=p_lease::text
   AND lease_until>floor(extract(epoch FROM clock_timestamp()))::bigint;
 IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_native_parse_changed' USING ERRCODE='40001';END IF;
 RETURN true;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_parse_dispatch(text,uuid,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_parse_dispatch(text,uuid,text) TO collect_runtime;

CREATE FUNCTION private.burimunsi_native_parse_finish(p_source text,p_lease uuid,p_profile_sha text,p_attempt uuid,
 p_model text,p_output jsonb,p_validation jsonb,p_unknown boolean) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE proof jsonb;profile jsonb;actor jsonb;j app.momo_processing_jobs%ROWTYPE;stamp text:=app.strftime('%Y-%m-%dT%H:%M:%fZ');
BEGIN
 PERFORM private.burimunsi_setup_fence();actor:=private.burimunsi_observation_actor(true);
 proof:=private.burimunsi_observation_own(p_source,true);profile:=private.burimunsi_observation_hint_profile(p_source);
 IF proof IS NULL OR profile IS NULL OR profile->>'profileSha256' IS DISTINCT FROM p_profile_sha OR p_attempt IS NULL
  OR p_model IS NULL OR p_model !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$' OR p_unknown IS NULL
  OR (p_output IS NOT NULL AND (jsonb_typeof(p_output)<>'object' OR octet_length(p_output::text)>65536))
  OR (p_unknown AND p_output IS NOT NULL) OR jsonb_typeof(p_validation)<>'array' OR octet_length(p_validation::text)>8192 THEN
  RAISE EXCEPTION 'burimunsi_native_parse_invalid' USING ERRCODE='22023';END IF;
 IF jsonb_array_length(p_validation)>30 OR NOT p_validation @> '[{"code":"incomplete_source"},{"code":"receiving_account_unverified"}]'::jsonb THEN
  RAISE EXCEPTION 'burimunsi_native_parse_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO j FROM app.momo_processing_jobs WHERE raw_sms_id=p_source FOR UPDATE;
 IF NOT FOUND OR j.state<>'processing' OR j.last_error<>'momo_v2:provider_dispatch' OR j.lease_token IS DISTINCT FROM p_lease::text
  OR j.lease_until<=floor(extract(epoch FROM clock_timestamp()))::bigint THEN
  RAISE EXCEPTION 'burimunsi_native_parse_changed' USING ERRCODE='40001';END IF;
 INSERT INTO app.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,
  profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at)
 VALUES(p_attempt::text,p_source,1,p_model,'momo-extraction.v1','momo-evidence.v2','momo-validation.v4',
  profile->'profile'->>'profile_version',profile->'profile'->>'profile_json',proof->>'bodySha256',p_output::text,p_validation::text,'needs_review',stamp);
 UPDATE app.momo_processing_jobs SET state='needs_review',last_error=CASE WHEN p_unknown THEN 'momo_v2:provider_outcome_unknown' ELSE 'native_source_unverified' END,
  lease_token=NULL,lease_until=NULL,updated_at=stamp WHERE raw_sms_id=p_source;
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,details_json,created_at)
  VALUES(actor->>'principalUserId',actor->>'sessionId','sms.native_source.provisional_extraction','sms_receipt',p_source,
   jsonb_build_object('source_kind','native_observation','collection_id',actor->>'collectionId','financial_effects',0,'provider_outcome_unknown',p_unknown)::text,stamp);
 RETURN jsonb_build_object('sourceId',p_source,'state','needs_review','financialEffects',0);
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_parse_finish(text,uuid,text,uuid,text,jsonb,jsonb,boolean) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_parse_finish(text,uuid,text,uuid,text,jsonb,jsonb,boolean) TO collect_runtime;
COMMIT;
