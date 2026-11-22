-- Authoritative shared gateway routing before native or legacy pairing.
-- Reconciled proposal SHA-256: a66a901c76036604a50ad56edc41171b599ede8ae49aa743d50e4560c01ba34a
-- No pairing, scope, grant, identity or data is seeded.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$ BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regclass('private.burimunsi_scopes') IS NULL
  OR to_regprocedure('private.burimunsi_gateway_pair_classify(text)') IS NOT NULL
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_gateway_classification_install_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

-- The existing runtime collection policy is unchanged. Only the normal table/
-- function owner can see the candidate's related scopes during this function's
-- guarded frame, including with FORCE RLS and no superuser/BYPASSRLS privilege.
-- The predicate is tied to the candidate code hash, not a caller's group or the
-- scope.enabled flag. A plain runtime SELECT cannot acquire this owner policy.
CREATE POLICY burimunsi_gateway_classification_lookup ON private.burimunsi_scopes FOR SELECT TO postgres
 USING(current_setting('role',true)='collect_runtime'
  AND current_setting('collect.edge_verified',true)='true'
  AND EXISTS(SELECT 1 FROM app.momo_gateway_pairings p
   JOIN app.momo_gateway_bindings b ON b.id=p.binding_id
   WHERE p.code_sha256=current_setting('burimunsi.gateway_classification_hash',true)
    AND (burimunsi_scopes.active_binding_id=b.id OR burimunsi_scopes.receiving_account_id=b.receiving_account_id)));

CREATE FUNCTION private.burimunsi_gateway_pair_classify(p_hash text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $fn$
DECLARE admission text:=current_setting('collect.fence_admission_id',true);
 epoch text:=current_setting('collect.fence_epoch',true);
 source text:=current_setting('collect.fence_source_sha256',true);
 old_hash text:=current_setting('burimunsi.gateway_classification_hash',true);
 candidate record;exact_count bigint;associated_count bigint;selected_group text;result jsonb;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 IF p_hash IS NULL OR octet_length(p_hash)<>64 OR p_hash !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'burimunsi_gateway_invalid_digest' USING ERRCODE='22023';END IF;
 IF admission IS NULL OR admission !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
  OR epoch IS NULL OR epoch !~ '^[1-9][0-9]{0,15}$' OR source IS NULL OR source !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'burimunsi_gateway_classification_unavailable' USING ERRCODE='55000';END IF;
 -- Same admitted READ COMMITTED/write-capable context and global mutation lock
 -- as DB.batch. Classification is a business read, never an unfenced first().
 PERFORM private.collect_fence_assert_write(admission::uuid,epoch::bigint,source);
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 SELECT p.binding_id,b.receiving_account_id INTO candidate
 FROM app.momo_gateway_pairings p JOIN app.momo_gateway_bindings b ON b.id=p.binding_id
 WHERE p.code_sha256=p_hash;
 IF NOT FOUND THEN RETURN jsonb_build_object('kind','blocked');END IF;
 BEGIN
  -- A custom CREATE FUNCTION SET property requires privileges unavailable to
  -- the retained non-super owner. Keep this transaction-local window explicit:
  -- save the caller value, scan, then restore it on normal/ordinary error paths.
  -- A query cancellation aborts the owning transaction/exception savepoint,
  -- which restores its local GUC changes; it never selects a fallback route.
  PERFORM set_config('burimunsi.gateway_classification_hash',p_hash,true);
  SELECT count(*) FILTER(WHERE s.active_binding_id=candidate.binding_id),count(*),
   min(s.collection_id) FILTER(WHERE s.active_binding_id=candidate.binding_id)
   INTO exact_count,associated_count,selected_group
  FROM private.burimunsi_scopes s
  WHERE s.active_binding_id=candidate.binding_id OR s.receiving_account_id=candidate.receiving_account_id;
  IF exact_count=1 AND selected_group IS NOT NULL THEN
   result:=jsonb_build_object('kind','burimunsi','collectionId',selected_group);
  ELSIF associated_count>0 THEN result:=jsonb_build_object('kind','blocked');
  ELSE result:=jsonb_build_object('kind','non_burimunsi');END IF;
 EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('burimunsi.gateway_classification_hash',coalesce(old_hash,''),true);RAISE;
 END;
 PERFORM set_config('burimunsi.gateway_classification_hash',coalesce(old_hash,''),true);
 PERFORM private.collect_fence_assert_write(admission::uuid,epoch::bigint,source);
 RETURN result;
END;$fn$;
ALTER FUNCTION private.burimunsi_gateway_pair_classify(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.burimunsi_gateway_pair_classify(text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.burimunsi_gateway_pair_classify(text) TO collect_runtime;
COMMIT;
