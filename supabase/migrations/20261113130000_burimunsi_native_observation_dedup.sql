-- Reinstall-stable source identity for NEW native inbox observations only.
-- Legacy requests stay unchanged; no source is promoted or credited here.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR to_regprocedure('private.burimunsi_observation_context()') IS NULL
  OR to_regclass('private.burimunsi_observation_requests') IS NULL THEN
  RAISE EXCEPTION 'burimunsi_observation_dedup_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

ALTER TABLE private.burimunsi_observation_requests
 ADD COLUMN source_key text,
 ADD COLUMN source_key_content_sha256 text,
 ADD COLUMN source_key_body_sha256 text,
 ADD CONSTRAINT burimunsi_observation_source_key_shape CHECK (
  (source_key IS NULL AND source_key_content_sha256 IS NULL AND source_key_body_sha256 IS NULL) OR
  (source_key IS NOT NULL AND source_key_content_sha256 IS NOT NULL AND source_key_body_sha256 IS NOT NULL AND
   source_key ~ '^[a-f0-9]{64}$' AND source_key_content_sha256 ~ '^[a-f0-9]{64}$' AND source_key_body_sha256 ~ '^[a-f0-9]{64}$')),
 ADD CONSTRAINT burimunsi_observation_source_key_unique UNIQUE(collection_id,source_key);

-- The current authorized actor can reconcile an exact source inside the same
-- collection, including after an authorized operator/installation switch. No
-- body, phone identifier or original principal is returned to the caller.
CREATE FUNCTION private.burimunsi_observation_key_lookup(p_key text,p_content text,p_body text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(false);c jsonb:=private.burimunsi_observation_consent_current();
 q private.burimunsi_observation_requests%ROWTYPE;r private.burimunsi_unresolved_observations%ROWTYPE;
 old_frame text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 IF c->'enabled' IS DISTINCT FROM 'true'::jsonb OR p_key !~ '^[a-f0-9]{64}$' OR p_content !~ '^[a-f0-9]{64}$'
  OR p_body !~ '^[a-f0-9]{64}$' OR p_key IS NULL OR p_content IS NULL OR p_body IS NULL THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO q FROM private.burimunsi_observation_requests WHERE collection_id=a->>'collectionId' AND source_key=p_key;
 IF NOT FOUND THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RETURN NULL;END IF;
 IF q.source_key_content_sha256 IS DISTINCT FROM p_content OR q.source_key_body_sha256 IS DISTINCT FROM p_body THEN
  RAISE EXCEPTION 'burimunsi_observation_source_conflict' USING ERRCODE='23505';END IF;
 SELECT * INTO r FROM private.burimunsi_unresolved_observations WHERE source_id=q.source_id AND collection_id=q.collection_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_observation_source_pending' USING ERRCODE='55000';END IF;
 IF r.body_sha256 IS DISTINCT FROM p_body OR NOT private.burimunsi_observation_storage_matches(r.object_key,
  jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id),r.object_sha256) THEN
  RAISE EXCEPTION 'burimunsi_observation_storage_changed' USING ERRCODE='55000';END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('sourceId',r.source_id,'requestId',r.request_id,'bodySha256',r.body_sha256,
  'object_key',r.object_key,'object_sha256',r.object_sha256,'size_bytes',r.size_bytes,'id',r.source_id,
  'createdAt',r.created_at,'principalUserId',r.principal_user_id,'sessionId',a->>'sessionId',
  'consentGeneration',(c->>'generation')::bigint,'fingerprint',r.fingerprint);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_key_lookup(text,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_key_lookup(text,text,text) TO collect_runtime;

CREATE FUNCTION private.burimunsi_observation_key_prepare(p_key text,p_content text,p_body text,p_request uuid,
 p_fingerprint text,p_source text,p_profile_version text,p_profile_sha text,p_consent_generation bigint) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;ctx jsonb;prior private.burimunsi_observation_requests%ROWTYPE;matched jsonb;h text;expected_id text;
 old_frame text:=current_setting('burimunsi.observation_frame',true);at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 PERFORM private.burimunsi_setup_fence();a:=private.burimunsi_observation_actor(false);ctx:=private.burimunsi_observation_context();
 IF p_key IS NULL OR p_key !~ '^[a-f0-9]{64}$' OR p_content IS NULL OR p_content !~ '^[a-f0-9]{64}$'
  OR p_body IS NULL OR p_body !~ '^[a-f0-9]{64}$' OR p_request IS NULL OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$'
  OR p_profile_sha IS NULL OR p_profile_sha !~ '^[a-f0-9]{64}$' OR p_profile_version IS NULL
  OR length(p_profile_version) NOT BETWEEN 1 AND 128 OR p_consent_generation IS NULL OR p_consent_generation<1 THEN
  RAISE EXCEPTION 'burimunsi_observation_invalid' USING ERRCODE='22023';END IF;
 IF ctx->>'profile_version' IS DISTINCT FROM p_profile_version OR ctx->>'profile_sha256' IS DISTINCT FROM p_profile_sha
  OR (ctx->>'consentGeneration')::bigint IS DISTINCT FROM p_consent_generation THEN
  RAISE EXCEPTION 'burimunsi_observation_profile_changed' USING ERRCODE='40001';END IF;
 h:=encode(sha256(convert_to('collect.storage.entity.v1'||E'\n'||'burimunsi.native.observation.v1'||E'\n'||(a->>'principalUserId')||E'\n'||p_request::text,'UTF8')),'hex');
 expected_id:=substr(h,1,8)||'-'||substr(h,9,4)||'-5'||substr(h,14,3)||'-8'||substr(h,18,3)||'-'||substr(h,21,12);
 IF p_source IS DISTINCT FROM expected_id THEN RAISE EXCEPTION 'burimunsi_observation_invalid' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended((a->>'collectionId')||':'||p_key,7346371));
 PERFORM pg_advisory_xact_lock(hashtextextended(a->>'principalUserId',7346370));
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO prior FROM private.burimunsi_observation_requests WHERE collection_id=a->>'collectionId' AND source_key=p_key FOR UPDATE;
 IF FOUND THEN
  IF prior.source_key_content_sha256 IS DISTINCT FROM p_content OR prior.source_key_body_sha256 IS DISTINCT FROM p_body THEN
   RAISE EXCEPTION 'burimunsi_observation_source_conflict' USING ERRCODE='23505';END IF;
  IF prior.source_id=p_source AND prior.request_id=p_request THEN
   IF prior.fingerprint IS DISTINCT FROM p_fingerprint OR prior.account_id IS DISTINCT FROM (a->>'accountId')::uuid
    OR prior.principal_user_id IS DISTINCT FROM a->>'principalUserId' OR prior.installation_id IS DISTINCT FROM (a->>'installationId')::uuid
    OR prior.grant_id IS DISTINCT FROM (a->>'grantId')::uuid OR prior.grant_version IS DISTINCT FROM (a->>'grantVersion')::bigint
    OR prior.initial_profile_tuple_sha256 IS DISTINCT FROM ctx->>'profile_tuple_sha256' THEN
    RAISE EXCEPTION 'burimunsi_observation_conflict' USING ERRCODE='23505';END IF;
   PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
   RETURN jsonb_build_object('kind','new','context',ctx||jsonb_build_object('sourceId',p_source,'requestId',p_request,'fingerprint',p_fingerprint));
  END IF;
  matched:=private.burimunsi_observation_key_lookup(p_key,p_content,p_body);
  PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
  RETURN jsonb_build_object('kind','duplicate','record',matched);
 END IF;
 IF (SELECT count(*) FROM private.burimunsi_observation_requests r WHERE r.principal_user_id=a->>'principalUserId'
   AND NOT EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations o WHERE o.source_id=r.source_id))>=16
  OR (SELECT count(*) FROM private.burimunsi_observation_requests WHERE principal_user_id=a->>'principalUserId' AND created_at>=at_ms-60000)>=60
  OR (SELECT count(*) FROM private.burimunsi_observation_requests WHERE principal_user_id=a->>'principalUserId' AND created_at>=at_ms-86400000)>=1000 THEN
  RAISE EXCEPTION 'burimunsi_observation_budget' USING ERRCODE='54000';END IF;
 INSERT INTO private.burimunsi_observation_requests(source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,
  native_session_id,request_id,fingerprint,initial_profile_version,initial_profile_sha256,initial_profile_tuple_sha256,initial_consent_generation,created_at,
  source_key,source_key_content_sha256,source_key_body_sha256)
 VALUES(p_source,a->>'collectionId',(a->>'accountId')::uuid,a->>'principalUserId',(a->>'installationId')::uuid,
  (a->>'grantId')::uuid,(a->>'grantVersion')::bigint,(a->>'sessionId')::uuid,p_request,p_fingerprint,p_profile_version,
  p_profile_sha,ctx->>'profile_tuple_sha256',p_consent_generation,at_ms,p_key,p_content,p_body);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('kind','new','context',ctx||jsonb_build_object('sourceId',p_source,'requestId',p_request,'fingerprint',p_fingerprint));
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_key_prepare(text,text,text,uuid,text,text,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_key_prepare(text,text,text,uuid,text,text,text,text,bigint) TO collect_runtime;

-- One non-identifying bit lets a new installation hold its preexisting inbox
-- instead of guessing which legacy observations correspond to which rows.
CREATE FUNCTION private.burimunsi_observation_legacy_present() RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(false);c jsonb:=private.burimunsi_observation_consent_current();
 answer boolean;old_frame text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 IF c->'enabled' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_observation_requests WHERE collection_id=a->>'collectionId' AND source_key IS NULL) INTO answer;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RETURN answer;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_legacy_present() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_legacy_present() TO collect_runtime;

-- A legacy request may finish its original admitted upload, but a new unkeyed
-- native observation cannot bypass source-key uniqueness after upgrade.
CREATE FUNCTION private.burimunsi_observation_legacy_retry_prepare(p_request uuid,p_fingerprint text,p_source text,
 p_profile_version text,p_profile_sha text,p_consent_generation bigint) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(false);prior private.burimunsi_observation_requests%ROWTYPE;
 old_frame text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO prior FROM private.burimunsi_observation_requests WHERE collection_id=a->>'collectionId'
  AND account_id=(a->>'accountId')::uuid AND request_id=p_request AND source_key IS NULL FOR UPDATE;
 IF NOT FOUND OR prior.source_id IS DISTINCT FROM p_source OR prior.fingerprint IS DISTINCT FROM p_fingerprint
  OR prior.principal_user_id IS DISTINCT FROM a->>'principalUserId' OR prior.installation_id IS DISTINCT FROM (a->>'installationId')::uuid
  OR prior.grant_id IS DISTINCT FROM (a->>'grantId')::uuid OR prior.grant_version IS DISTINCT FROM (a->>'grantVersion')::bigint THEN
  RAISE EXCEPTION 'burimunsi_observation_source_key_required' USING ERRCODE='55000';END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN private.burimunsi_observation_prepare(p_request,p_fingerprint,p_source,p_profile_version,p_profile_sha,p_consent_generation);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_legacy_retry_prepare(uuid,text,text,text,text,bigint) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_legacy_retry_prepare(uuid,text,text,text,text,bigint) TO collect_runtime;
COMMIT;
