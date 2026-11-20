-- Preserve the original message identity and all observed provider outcomes.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced') THEN
  RAISE EXCEPTION 'burimunsi_payment_sms_fence_required' USING ERRCODE='55000';
 END IF;
END;$preflight$;

CREATE FUNCTION private.burimunsi_prepare_payment_sms_v2(
 p_collection_id text,p_attempt_id uuid,p_claim_token uuid,p_body_sha256 text
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 IF p_body_sha256 IS NULL OR p_body_sha256 !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'payment_sms_prepare_invalid' USING ERRCODE='22023';
 END IF;
 IF private.burimunsi_prepare_payment_sms(p_collection_id,p_attempt_id,p_claim_token,p_body_sha256) THEN
  RETURN 'prepared';
 END IF;
 -- The original prepare lock is still held. Finish can suppress only the
 -- exact unarmed send claim. An already armed or superseded claim is held.
 IF private.burimunsi_finish_payment_sms(p_collection_id,p_attempt_id,p_claim_token,'suppressed',NULL,NULL) THEN
  RETURN 'suppressed';
 END IF;
 RETURN 'held';
END;$fn$;

REVOKE ALL ON FUNCTION private.burimunsi_prepare_payment_sms_v2(text,uuid,uuid,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_prepare_payment_sms_v2(text,uuid,uuid,text) TO collect_runtime;
COMMIT;
