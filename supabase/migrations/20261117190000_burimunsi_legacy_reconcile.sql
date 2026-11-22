-- Read-only reconciliation of retained, imported unkeyed observations. This
-- does not bind a source key, enqueue work, or alter any financial record.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR to_regclass('private.collect_imported_native_history') IS NULL
  OR to_regclass('private.burimunsi_native_receipt_origins') IS NULL
  OR to_regclass('private.collect_migration_actor_lineage') IS NULL
  OR to_regprocedure('private.burimunsi_observation_history_own(text)') IS NULL
  OR to_regprocedure('private.burimunsi_observation_legacy_candidates(text)') IS NOT NULL THEN
  RAISE EXCEPTION 'burimunsi_legacy_reconcile_precondition' USING ERRCODE='55000';
 END IF;
END;$preflight$;

-- The body digest is only a bounded prefilter; it is never accepted as proof
-- of an inbox identity. Collection is the leading column of this index.
CREATE INDEX collect_imported_native_history_collection_body
 ON private.collect_imported_native_history(collection_id,body_sha256);

CREATE FUNCTION private.burimunsi_observation_legacy_candidates(p_body text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(true);
 c jsonb:=private.burimunsi_observation_consent_current();
 cid text:=a->>'collectionId'; item record; proof jsonb; result jsonb:='[]'::jsonb; n integer:=0;
 old_obs text:=current_setting('burimunsi.observation_frame',true);
 old_native text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 IF p_body IS NULL OR p_body !~ '^[a-f0-9]{64}$' OR cid IS NULL
  OR cid IS DISTINCT FROM current_setting('burimunsi.collection_id',true)
  OR c->'enabled' IS DISTINCT FROM 'true'::jsonb THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 -- Explicit predicates matter: this definer can bypass table RLS. Query at
 -- most five candidate rows, from this account and imported actor lineage;
 -- a fifth row makes the whole item uncertain instead of truncating matches.
 FOR item IN SELECT h.source_id,h.request_id,h.body_sha256,h.object_sha256,h.source_fingerprint,
   o.account_id,o.principal_user_id,o.installation_id,o.grant_id,o.grant_version,
   q.source_id AS q_source_id,q.collection_id AS q_collection_id,q.account_id AS q_account_id,
   q.principal_user_id AS q_principal_user_id,q.installation_id AS q_installation_id,
   q.grant_id AS q_grant_id,q.grant_version AS q_grant_version,q.request_id AS q_request_id,
   q.fingerprint AS q_fingerprint,o.request_id AS o_request_id,o.fingerprint AS o_fingerprint,
   o.body_sha256 AS o_body_sha256,o.object_sha256 AS o_object_sha256
  FROM private.collect_imported_native_history h
  JOIN private.burimunsi_native_receipt_origins o ON o.source_id=h.source_id AND o.collection_id=cid
  JOIN private.collect_migration_actor_lineage l ON l.source_actor_id=o.principal_user_id
   AND l.cloud_primary_id=a->>'principalUserId'
  LEFT JOIN private.burimunsi_observation_requests q ON q.source_id=h.source_id
  WHERE h.collection_id=cid AND h.body_sha256=p_body AND o.account_id=(a->>'accountId')::uuid
   AND (q.source_id IS NULL OR q.source_key IS NULL)
  ORDER BY h.source_id LIMIT 5
 LOOP
  n:=n+1;
  IF n>4 OR item.q_source_id IS NULL OR item.q_collection_id IS DISTINCT FROM cid
   OR item.q_account_id IS DISTINCT FROM item.account_id
   OR item.q_principal_user_id IS DISTINCT FROM item.principal_user_id
   OR item.q_installation_id IS DISTINCT FROM item.installation_id
   OR item.q_grant_id IS DISTINCT FROM item.grant_id OR item.q_grant_version IS DISTINCT FROM item.grant_version
   OR item.q_request_id IS DISTINCT FROM item.request_id OR item.o_request_id IS DISTINCT FROM item.request_id
   OR item.q_fingerprint IS DISTINCT FROM item.source_fingerprint OR item.o_fingerprint IS DISTINCT FROM item.source_fingerprint
   OR item.o_body_sha256 IS DISTINCT FROM item.body_sha256 OR item.o_object_sha256 IS DISTINCT FROM item.object_sha256 THEN
   RAISE EXCEPTION 'burimunsi_observation_legacy_unavailable' USING ERRCODE='55000';END IF;
  -- Reuse the normal history authority, imported lineage and storage check.
  -- The Edge function alone receives this descriptor; clients see no object.
  proof:=private.burimunsi_observation_history_own(item.source_id);
  IF proof IS NULL OR proof->>'sourceId' IS DISTINCT FROM item.source_id
   OR proof->>'requestId' IS DISTINCT FROM item.request_id::text
   OR proof->>'fingerprint' IS DISTINCT FROM item.source_fingerprint
   OR proof->>'bodySha256' IS DISTINCT FROM item.body_sha256
   OR proof->>'object_sha256' IS DISTINCT FROM item.object_sha256 THEN
   RAISE EXCEPTION 'burimunsi_observation_legacy_unavailable' USING ERRCODE='55000';END IF;
  result:=result||jsonb_build_array(proof);
 END LOOP;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 RETURN result;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_legacy_candidates(text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_legacy_candidates(text) TO collect_runtime;
COMMIT;
