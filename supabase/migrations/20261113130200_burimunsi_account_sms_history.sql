-- Historical SMS for the same authorized native administrator. This does not
-- transfer observations, relax capture deduplication, or make ledger entries.
DO $preflight$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR to_regprocedure('private.burimunsi_observation_actor(boolean)') IS NULL
  OR to_regprocedure('private.burimunsi_observation_page(text,text,integer,integer)') IS NULL
  OR to_regprocedure('private.burimunsi_observation_storage_matches(text,jsonb,text)') IS NULL THEN
  RAISE EXCEPTION 'burimunsi_account_sms_history_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

-- This internal function is never executable by the application role. Both
-- the current device and the historical device retain their own revocation
-- boundaries; no caller may choose an account, collection or principal.
CREATE FUNCTION private.burimunsi_observation_history_rows(p_source text DEFAULT NULL)
 RETURNS SETOF private.burimunsi_unresolved_observations
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(false);c jsonb:=private.burimunsi_observation_consent_current();
 old_obs text:=current_setting('burimunsi.observation_frame',true);
 old_pin text:=current_setting('burimunsi.pin_frame',true);
BEGIN
 IF c->'enabled' IS DISTINCT FROM 'true'::jsonb THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 PERFORM set_config('burimunsi.pin_frame','1',true);
 IF current_setting('transaction_read_only')='off' THEN
  -- A current-device consent revocation must serialize with raw disclosure
  -- even when the disclosed source came from an older installation.
  PERFORM 1 FROM private.burimunsi_observation_consents current_consent
   WHERE current_consent.collection_id=a->>'collectionId' AND current_consent.account_id=(a->>'accountId')::uuid
    AND current_consent.installation_id=(a->>'installationId')::uuid AND current_consent.grant_id=(a->>'grantId')::uuid
    AND current_consent.grant_version=(a->>'grantVersion')::bigint AND current_consent.enabled FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 END IF;
 RETURN QUERY EXECUTE $q$SELECT r.* FROM private.burimunsi_unresolved_observations r
 JOIN private.burimunsi_device_grants d ON d.id=r.grant_id AND d.collection_id=r.collection_id
  AND d.installation_id=r.installation_id AND d.version=r.grant_version AND d.active AND d.profile='internal_receiver'
 JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.collection_id=r.collection_id AND da.account_id=r.account_id
 JOIN private.burimunsi_observation_consents old_consent ON old_consent.collection_id=r.collection_id
  AND old_consent.account_id=r.account_id AND old_consent.installation_id=r.installation_id
  AND old_consent.grant_id=r.grant_id AND old_consent.grant_version=r.grant_version AND old_consent.enabled
 WHERE r.collection_id=$1->>'collectionId' AND r.account_id=($1->>'accountId')::uuid
  AND r.principal_user_id=$1->>'principalUserId' AND ($2 IS NULL OR r.source_id=$2)$q$
  ||CASE WHEN current_setting('transaction_read_only')='off' THEN ' FOR SHARE OF r,d,da,old_consent' ELSE '' END
  USING a,p_source;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 RETURN;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_history_rows(text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

-- Only the native SMS page calls this existing signature. Its response remains
-- metadata-only and each list page is tied to the eligible source snapshot.
CREATE OR REPLACE FUNCTION private.burimunsi_observation_page(p_query text,p_filter text,p_limit integer,p_offset integer) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE n bigint;matched bigint;rev text;items jsonb;old_obs text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 IF p_query IS NULL OR length(p_query)>80 OR p_filter IS NULL OR p_filter NOT IN('all','queued','duplicate','synced','rejected')
  OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 100000 THEN
  RAISE EXCEPTION 'burimunsi_observation_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 IF EXISTS(SELECT 1 FROM private.burimunsi_observation_history_rows(NULL) r
  WHERE NOT private.burimunsi_observation_storage_matches(r.object_key,
   jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id),r.object_sha256)) THEN
  RAISE EXCEPTION 'burimunsi_observation_storage_changed' USING ERRCODE='55000';END IF;
 SELECT count(*),encode(sha256(convert_to(coalesce(string_agg(r.source_id||':'||r.created_at::text||':'||r.fingerprint,E'\n'
  ORDER BY r.source_id),''),'UTF8')),'hex') INTO n,rev FROM private.burimunsi_observation_history_rows(NULL) r;
 IF n>100000 THEN RAISE EXCEPTION 'burimunsi_observation_snapshot_limit' USING ERRCODE='54000';END IF;
 SELECT count(*) INTO matched FROM private.burimunsi_observation_history_rows(NULL) r
  WHERE position(lower(p_query) IN lower(r.source_id))>0 AND p_filter IN('all','synced');
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',q.source_id,'createdAt',q.created_at)
  ORDER BY q.created_at DESC,q.source_id),'[]'::jsonb) INTO items FROM (
   SELECT r.source_id,r.created_at FROM private.burimunsi_observation_history_rows(NULL) r
   WHERE position(lower(p_query) IN lower(r.source_id))>0 AND p_filter IN('all','synced')
   ORDER BY r.created_at DESC,r.source_id LIMIT p_limit OFFSET p_offset
  ) q;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 RETURN jsonb_build_object('revision',rev,'totalCount',matched,'items',items);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);RAISE;
END;$fn$;

-- The historical proof is used only by audited disclosure. The original
-- installation-bound observation_own remains unchanged for processing paths.
CREATE FUNCTION private.burimunsi_observation_history_own(p_source text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(true);c jsonb:=private.burimunsi_observation_consent_current();
 r private.burimunsi_unresolved_observations%ROWTYPE;old_obs text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 IF c->'enabled' IS DISTINCT FROM 'true'::jsonb OR p_source IS NULL THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 SELECT * INTO r FROM private.burimunsi_observation_history_rows(p_source);
 IF NOT FOUND THEN RETURN NULL;END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 IF NOT private.burimunsi_observation_storage_matches(r.object_key,
  jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id),r.object_sha256) THEN
  RAISE EXCEPTION 'burimunsi_observation_storage_changed' USING ERRCODE='55000';END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 RETURN jsonb_build_object('sourceId',r.source_id,'requestId',r.request_id,'bodySha256',r.body_sha256,
  'object_key',r.object_key,'object_sha256',r.object_sha256,'size_bytes',r.size_bytes,'id',r.source_id,
  'createdAt',r.created_at,'principalUserId',r.principal_user_id,'sessionId',a->>'sessionId',
  'consentGeneration',(c->>'generation')::bigint,'fingerprint',r.fingerprint);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_history_own(text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_history_own(text) TO collect_runtime;

-- Recheck both devices, current session, consent and the retained source after
-- retrieval, then record the same mandatory disclosure audit as before.
CREATE FUNCTION private.burimunsi_observation_history_reveal_audit(p_source text,p_request uuid,p_reason text,p_session uuid,
 p_body_sha text,p_object_sha text,p_fingerprint text,p_consent_generation bigint) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;c jsonb;r jsonb;
BEGIN
 PERFORM private.burimunsi_setup_fence();a:=private.burimunsi_observation_actor(true);c:=private.burimunsi_observation_consent_current();
 IF p_request IS NULL OR p_session IS NULL OR p_session::text IS DISTINCT FROM a->>'sessionId'
  OR p_reason IS NULL OR btrim(p_reason) IS DISTINCT FROM p_reason OR length(p_reason) NOT BETWEEN 8 AND 1000
  OR p_reason ~ '[[:cntrl:]]' OR c->'enabled' IS DISTINCT FROM 'true'::jsonb
  OR (c->>'generation')::bigint IS DISTINCT FROM p_consent_generation THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 r:=private.burimunsi_observation_history_own(p_source);
 IF r IS NULL OR r->>'bodySha256' IS DISTINCT FROM p_body_sha OR r->>'object_sha256' IS DISTINCT FROM p_object_sha
  OR r->>'fingerprint' IS DISTINCT FROM p_fingerprint THEN
  RAISE EXCEPTION 'burimunsi_observation_changed' USING ERRCODE='40001';END IF;
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
 VALUES(a->>'principalUserId',a->>'sessionId','sms.capture.revealed','burimunsi_observation',p_source,p_request::text,
  jsonb_build_object('reason',p_reason,'purpose','native_account_sms_history','source_kind','unresolved_observation',
   'collection_id',a->>'collectionId','native_actor_id',a->>'accountId','native_session_id',a->>'sessionId',
   'source_sha256',p_body_sha,'object_sha256',p_object_sha)::text,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 RETURN r;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_history_reveal_audit(text,uuid,text,uuid,text,text,text,bigint)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_history_reveal_audit(text,uuid,text,uuid,text,text,text,bigint) TO collect_runtime;
