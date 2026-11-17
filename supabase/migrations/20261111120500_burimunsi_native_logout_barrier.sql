-- An exact native device proof can revoke its own session even while account
-- authority is temporarily suspended. This operation grants no read/business
-- authority and optionally cancels a pending passcode replacement atomically.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regprocedure('private.burimunsi_pin_rotate_passcode(uuid,uuid,bigint,bigint,jsonb,text,text,bigint)') IS NULL
  OR to_regprocedure('private.burimunsi_pin_logout_barrier(text,uuid,text,text,text,text)') IS NOT NULL
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_logout_barrier_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;
CREATE FUNCTION private.burimunsi_pin_logout_barrier(p_token text,p_installation uuid,p_device text,p_profile text,
 p_collection text,p_replacement text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE prior_frame text:=current_setting('burimunsi.pin_frame',true);s private.burimunsi_sessions%ROWTYPE;
 candidate private.burimunsi_sessions%ROWTYPE;candidate_hash text;result jsonb;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 IF p_token IS NULL OR p_token !~ '^[a-f0-9]{64}$' OR p_device IS NULL OR p_device !~ '^[a-f0-9]{64}$'
  OR p_installation IS NULL OR p_profile NOT IN('staff','internal_receiver') OR p_profile IS NULL
  OR p_collection IS NULL OR p_collection !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'
  OR p_replacement IS NOT NULL AND (p_replacement !~ '^[a-f0-9]{64}$' OR p_replacement IN(p_token,p_device)) THEN RETURN NULL;END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM set_config('burimunsi.pin_frame','1',true);
 -- Do not consult mutable account/approval state: temporary suspension must
 -- not prevent a holder from permanently revoking this exact device proof.
 SELECT s0.* INTO s FROM private.burimunsi_sessions s0 JOIN private.burimunsi_device_grants d
  ON d.id=s0.grant_id AND d.collection_id=s0.collection_id AND d.installation_id=s0.installation_id
  WHERE s0.auth_method='phone_pin' AND s0.collection_id=p_collection AND s0.installation_id=p_installation
   AND s0.token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex') AND d.profile=p_profile
   AND d.token_hash=encode(sha256(convert_to(p_device,'UTF8')),'hex') FOR UPDATE OF s0,d;
 IF NOT FOUND THEN PERFORM set_config('burimunsi.pin_frame',coalesce(prior_frame,''),true);RETURN NULL;END IF;
 IF p_replacement IS NOT NULL THEN
  candidate_hash:=encode(sha256(convert_to(p_replacement,'UTF8')),'hex');
  SELECT * INTO candidate FROM private.burimunsi_sessions WHERE token_hash=candidate_hash FOR UPDATE;
  IF FOUND AND (candidate.auth_method<>'phone_pin' OR candidate.collection_id<>s.collection_id
   OR candidate.account_id<>s.account_id OR candidate.grant_id<>s.grant_id OR candidate.installation_id<>s.installation_id) THEN
   PERFORM set_config('burimunsi.pin_frame',coalesce(prior_frame,''),true);RETURN NULL;END IF;
 END IF;
 UPDATE private.burimunsi_sessions SET revoked=true WHERE id=s.id AND NOT revoked;
 IF candidate.id IS NOT NULL THEN UPDATE private.burimunsi_sessions SET revoked=true WHERE id=candidate.id AND NOT revoked;END IF;
 -- Under this same lock any delayed rotation rechecks s.revoked and cannot
 -- create a successor after this acknowledgement, including when no candidate
 -- row existed at the time of logout.
 result:=jsonb_build_object('accountId',s.account_id,'collectionId',s.collection_id);
 PERFORM set_config('burimunsi.pin_frame',coalesce(prior_frame,''),true);RETURN result;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.pin_frame',coalesce(prior_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_pin_logout_barrier(text,uuid,text,text,text,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_pin_logout_barrier(text,uuid,text,text,text,text) TO collect_runtime;
COMMIT;
