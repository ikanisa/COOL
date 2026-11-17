-- DRAFT ONLY: not a migration, not wired to release, and not deployable.
-- Qualify this definition and all predecessor/ACL checks in a new ordered
-- migration before any source-bound held-recovery activation.
-- The current consent row must remain locked until the caller's transaction
-- commits the native request and its associated witness and hold.
CREATE FUNCTION private.burimunsi_sms_recovery_prepare(
 p_key text,p_content text,p_body text,p_request uuid,p_fingerprint text,
 p_source text,p_profile_version text,p_profile_sha text,p_expected_consent_generation bigint
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;consent private.burimunsi_observation_consents%ROWTYPE;result jsonb;
 prior text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 actor:=private.burimunsi_observation_actor(true);
 IF p_expected_consent_generation IS NULL OR p_expected_consent_generation NOT BETWEEN 1 AND 9007199254740991 THEN
  RAISE EXCEPTION 'sms_held_consent_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO consent FROM private.burimunsi_observation_consents c
  WHERE c.collection_id=actor->>'collectionId' AND c.account_id=(actor->>'accountId')::uuid
   AND c.installation_id=(actor->>'installationId')::uuid FOR SHARE;
 IF NOT FOUND OR consent.enabled IS DISTINCT FROM true
  OR consent.generation IS DISTINCT FROM p_expected_consent_generation
  OR consent.grant_id IS DISTINCT FROM (actor->>'grantId')::uuid
  OR consent.grant_version IS DISTINCT FROM (actor->>'grantVersion')::bigint THEN
  RAISE EXCEPTION 'sms_held_consent_changed' USING ERRCODE='40001';END IF;
 result:=private.burimunsi_observation_key_prepare(p_key,p_content,p_body,p_request,p_fingerprint,
  p_source,p_profile_version,p_profile_sha,p_expected_consent_generation);
 PERFORM set_config('burimunsi.observation_frame',coalesce(prior,''),true);RETURN result;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.observation_frame',coalesce(prior,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_sms_recovery_prepare(text,text,text,uuid,text,text,text,text,bigint) TO collect_runtime;
