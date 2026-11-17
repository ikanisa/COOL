-- Metadata-only collection reconciliation status. No SMS content, source
-- identifiers, grants, storage keys, or financial records are returned.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regprocedure('private.burimunsi_observation_actor(boolean)') IS NULL
  OR to_regprocedure('private.burimunsi_observation_consent_current()') IS NULL
  OR to_regprocedure('private.burimunsi_observation_storage_matches(text,jsonb,text)') IS NULL
  OR to_regclass('private.burimunsi_observation_requests') IS NULL
  OR to_regclass('private.burimunsi_unresolved_observations') IS NULL
  OR to_regclass('private.burimunsi_sms_source_scopes') IS NULL
  OR to_regprocedure('private.burimunsi_observation_reconcile_status()') IS NOT NULL THEN
  RAISE EXCEPTION 'burimunsi_reconcile_status_precondition' USING ERRCODE='55000';
 END IF;
END;$preflight$;

CREATE FUNCTION private.burimunsi_observation_reconcile_status() RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(false);c jsonb:=private.burimunsi_observation_consent_current();
 cid text:=a->>'collectionId';old_frame text:=current_setting('burimunsi.observation_frame',true);
 requests bigint;recorded bigint;canonical bigint;unmatched boolean;rev text;
BEGIN
 IF cid IS NULL OR cid IS DISTINCT FROM current_setting('burimunsi.collection_id',true)
  OR c->'enabled' IS DISTINCT FROM 'true'::jsonb THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT count(*) INTO requests FROM (SELECT 1 FROM private.burimunsi_observation_requests q
  WHERE q.collection_id=cid LIMIT 100001) bounded;
 SELECT count(*) INTO canonical FROM (SELECT 1 FROM private.burimunsi_sms_source_scopes x
  WHERE x.collection_id=cid LIMIT 100001) bounded;
 IF requests>100000 OR canonical>100000 THEN
  RAISE EXCEPTION 'burimunsi_observation_snapshot_limit' USING ERRCODE='54000';END IF;
 -- A source whose parent request or scope has changed is not absence.
 IF EXISTS(SELECT 1 FROM private.burimunsi_observation_requests q
  JOIN private.burimunsi_unresolved_observations r ON r.source_id=q.source_id
  WHERE q.collection_id=cid AND (r.collection_id IS DISTINCT FROM q.collection_id
   OR r.account_id IS DISTINCT FROM q.account_id OR r.principal_user_id IS DISTINCT FROM q.principal_user_id
   OR r.installation_id IS DISTINCT FROM q.installation_id OR r.grant_id IS DISTINCT FROM q.grant_id
   OR r.grant_version IS DISTINCT FROM q.grant_version OR r.request_id IS DISTINCT FROM q.request_id
   OR r.fingerprint IS DISTINCT FROM q.fingerprint))
  OR EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations r
   LEFT JOIN private.burimunsi_observation_requests q ON q.source_id=r.source_id
   WHERE r.collection_id=cid AND (q.source_id IS NULL OR q.collection_id IS DISTINCT FROM cid)) THEN
  RAISE EXCEPTION 'burimunsi_observation_changed' USING ERRCODE='55000';END IF;
 IF EXISTS(SELECT 1 FROM private.burimunsi_observation_requests q
  JOIN private.burimunsi_unresolved_observations r ON r.source_id=q.source_id
  LEFT JOIN private.storage_payload_reservations s ON s.object_key=r.object_key
  LEFT JOIN private.storage_objects o ON o.object_key=r.object_key
  WHERE q.collection_id=cid AND (
   NOT private.burimunsi_observation_storage_matches(r.object_key,
    jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id),r.object_sha256)
   OR s.object_key IS NULL OR s.scope IS DISTINCT FROM jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id)
   OR s.aad IS DISTINCT FROM 'sms:'||r.source_id||':'||r.object_sha256 OR s.plaintext_sha256 IS DISTINCT FROM r.object_sha256
   OR s.key_id IS NULL OR s.source_fingerprint IS DISTINCT FROM o.custom_metadata->>'source_fingerprint'
   OR s.key_id IS DISTINCT FROM o.custom_metadata->>'key_id')) THEN
  RAISE EXCEPTION 'burimunsi_observation_storage_changed' USING ERRCODE='55000';END IF;
 SELECT count(*) INTO recorded FROM private.burimunsi_observation_requests q
  JOIN private.burimunsi_unresolved_observations r ON r.source_id=q.source_id WHERE q.collection_id=cid;
 -- A canonical row counts as represented only when its source identity and
 -- custody identity are exactly the same; any other canonical association
 -- makes global SMS equality unconfirmed rather than increasing this count.
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes x
  WHERE x.collection_id=cid AND NOT EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations r
   JOIN private.burimunsi_observation_requests q ON q.source_id=r.source_id AND q.collection_id=r.collection_id
   JOIN app.sms_receipts s ON s.id=r.source_id AND s.owner_user_id=r.principal_user_id
    AND s.body_sha256=r.body_sha256 AND s.object_sha256=r.object_sha256 AND s.object_key=r.object_key
   WHERE r.collection_id=cid AND r.source_id=x.source_id AND x.owner_user_id=r.principal_user_id
    AND x.source_body_sha256=r.body_sha256 AND x.object_sha256=r.object_sha256)) INTO unmatched;
 -- Hash each row first to bound the aggregate and include the complete
 -- mutable custody descriptors without returning any of them to the caller.
 WITH entries AS (
  SELECT 'o:'||q.source_id AS k,encode(sha256(convert_to(jsonb_build_array(
   to_jsonb(q),to_jsonb(r),to_jsonb(i),to_jsonb(o),
   CASE WHEN s.object_key IS NULL THEN NULL ELSE (to_jsonb(s)-'sealed_body')||jsonb_build_object(
    'sealed_sha256',CASE WHEN s.sealed_body IS NULL THEN NULL ELSE encode(sha256(convert_to(s.sealed_body,'UTF8')),'hex') END,
    'sealed_size',CASE WHEN s.sealed_body IS NULL THEN NULL ELSE octet_length(s.sealed_body) END) END,
   to_jsonb(d))::text,'UTF8')),'hex') AS h
  FROM private.burimunsi_observation_requests q
  LEFT JOIN private.burimunsi_unresolved_observations r ON r.source_id=q.source_id
  LEFT JOIN private.storage_put_intents i ON i.object_key=r.object_key
  LEFT JOIN private.storage_objects o ON o.object_key=r.object_key
  LEFT JOIN private.storage_payload_reservations s ON s.object_key=r.object_key
  LEFT JOIN private.storage_delete_intents d ON d.object_key=r.object_key
  WHERE q.collection_id=cid
  UNION ALL
  SELECT 'c:'||x.source_id,encode(sha256(convert_to(jsonb_build_array(to_jsonb(x),to_jsonb(s))::text,'UTF8')),'hex')
   FROM private.burimunsi_sms_source_scopes x LEFT JOIN app.sms_receipts s ON s.id=x.source_id WHERE x.collection_id=cid
 ) SELECT encode(sha256(convert_to(coalesce(string_agg(h,E'\n' ORDER BY k),''),'UTF8')),'hex') INTO rev FROM entries;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('groupId',cid,'hasPending',requests>recorded,'hasRecorded',recorded>0,
  'recordedCount',recorded,'hasUnmatchedCanonical',unmatched,'revision',rev);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_reconcile_status() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_reconcile_status() TO collect_runtime;
COMMIT;
