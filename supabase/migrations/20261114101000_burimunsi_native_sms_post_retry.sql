-- Exception backoff for the existing native posting lane. This changes job
-- metadata only; it never creates, reverses or settles a financial record.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $check$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR to_regprocedure('private.burimunsi_native_sms_post_defer(text,integer)') IS NULL
  OR to_regprocedure('private.burimunsi_native_sms_post_retry(text,text)') IS NOT NULL THEN
  RAISE EXCEPTION 'native_sms_post_retry_precondition' USING ERRCODE='55000';END IF;
END;$check$;

ALTER TABLE private.burimunsi_auto_sms_jobs
 ADD COLUMN posting_failure_count integer NOT NULL DEFAULT 0 CHECK(posting_failure_count BETWEEN 0 AND 16),
 ADD COLUMN posting_last_error text CHECK(posting_last_error IS NULL OR posting_last_error IN ('source_unavailable','access_denied','posting_changed','posting_failed')),
 ADD COLUMN posting_last_failed_at bigint CHECK(posting_last_failed_at IS NULL OR posting_last_failed_at>=0),
 ADD CONSTRAINT native_sms_post_failure_shape CHECK(
  (posting_failure_count=0 AND posting_last_error IS NULL AND posting_last_failed_at IS NULL) OR
  (posting_failure_count>0 AND posting_last_error IS NOT NULL AND posting_last_failed_at IS NOT NULL));

CREATE FUNCTION private.burimunsi_native_sms_post_retry(p_source text,p_reason text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.native_receipt_frame',true);r record;changed boolean;
 at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 IF p_source IS NULL OR p_reason IS NULL OR p_reason NOT IN ('source_unavailable','access_denied','posting_changed','posting_failed')
  OR nullif(current_setting('burimunsi.collection_id',true),'') IS NULL THEN
  RAISE EXCEPTION 'native_sms_post_retry_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 UPDATE private.burimunsi_auto_sms_jobs j SET
  posting_next_attempt_at=greatest(j.posting_next_attempt_at,
   at_ms+least(900000,60000*(1 << least(j.posting_failure_count,4)))),
  posting_failure_count=least(j.posting_failure_count+1,16),posting_last_error=p_reason,posting_last_failed_at=at_ms
 WHERE j.source_id=p_source AND j.collection_id=current_setting('burimunsi.collection_id',true)
  AND j.state='completed' AND j.relation='accepted'
  AND NOT EXISTS(SELECT 1 FROM app.momo_financial_links f WHERE f.transaction_id=j.transaction_id)
 RETURNING posting_failure_count,posting_next_attempt_at INTO r;
 changed:=FOUND;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 IF NOT changed THEN RETURN jsonb_build_object('deferred',false,'state','not_eligible');END IF;
 RETURN jsonb_build_object('deferred',true,'failureCount',r.posting_failure_count,'nextAttemptAt',r.posting_next_attempt_at);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_sms_post_retry(text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_sms_post_retry(text,text) TO collect_runtime;

-- A source that reaches a normal automatic unmatched outcome has recovered
-- from the prior exception; retain the normal one-minute reconsideration.
CREATE OR REPLACE FUNCTION private.burimunsi_native_sms_post_defer(p_source text,p_delay_ms integer) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.native_receipt_frame',true);n integer;
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 IF p_delay_ms IS NULL OR p_delay_ms NOT BETWEEN 1000 AND 86400000 THEN RAISE EXCEPTION 'native_sms_posting_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 UPDATE private.burimunsi_auto_sms_jobs SET posting_next_attempt_at=floor(extract(epoch FROM clock_timestamp())*1000)::bigint+p_delay_ms,
  posting_failure_count=0,posting_last_error=NULL,posting_last_failed_at=NULL
 WHERE source_id=p_source AND collection_id=current_setting('burimunsi.collection_id',true) AND state='completed';
 GET DIAGNOSTICS n=ROW_COUNT;PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RETURN n=1;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
COMMIT;
