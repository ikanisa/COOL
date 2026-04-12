-- ==========================================================================
-- Phase 6: Scheduled Cleanup Functions
-- ==========================================================================
-- OTP auto-cleanup and SMS data lifecycle management.
-- Invoke via pg_cron or scheduled Edge Function.
-- ==========================================================================

-- ── 6A: Expired OTP cleanup ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cleanup_expired_otp_codes()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM public.otp_codes
  WHERE expires_at < now() - INTERVAL '24 hours';

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

COMMENT ON FUNCTION public.cleanup_expired_otp_codes() IS
  'Purges OTP codes that expired more than 24 hours ago. '
  'Schedule via pg_cron or daily Edge Function cron.';

-- Also clean up expired OTP rate events (older than 7 days)
CREATE OR REPLACE FUNCTION public.cleanup_expired_otp_rate_events()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM public.otp_rate_events
  WHERE created_at < now() - INTERVAL '7 days';

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;

-- ── 6B: SMS data lifecycle (redaction + archival) ────────────────────────

CREATE OR REPLACE FUNCTION public.archive_stale_momo_sms(
  p_days_old INT DEFAULT 90
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_redacted_count INTEGER;
  v_parse_attempts_deleted INTEGER;
BEGIN
  -- Redact SMS body for fully-processed messages older than p_days_old
  UPDATE public.momo_sms_raw
  SET
    sms_body = '[REDACTED]',
    updated_at = now()
  WHERE sms_received_at < now() - (p_days_old || ' days')::INTERVAL
    AND parse_status IN ('parsed', 'ignored')
    AND sms_body <> '[REDACTED]';

  GET DIAGNOSTICS v_redacted_count = ROW_COUNT;

  -- Delete old parse attempt details (request/response payloads can be large)
  DELETE FROM public.momo_parse_attempts
  WHERE created_at < now() - (p_days_old || ' days')::INTERVAL
    AND status IN ('success', 'failed');

  GET DIAGNOSTICS v_parse_attempts_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    'sms_redacted', v_redacted_count,
    'parse_attempts_deleted', v_parse_attempts_deleted,
    'cutoff_date', (now() - (p_days_old || ' days')::INTERVAL)::date
  );
END;
$$;

COMMENT ON FUNCTION public.archive_stale_momo_sms(int) IS
  'Redacts SMS body text and deletes parse attempt payloads older than '
  'p_days_old days. Preserves parsed transaction data for audit trail.';

-- ── Combined cleanup orchestrator ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.run_scheduled_cleanup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_otp_count INTEGER;
  v_rate_count INTEGER;
  v_fcm_count INTEGER;
  v_sms_result jsonb;
BEGIN
  -- OTP cleanup
  v_otp_count := public.cleanup_expired_otp_codes();

  -- OTP rate events cleanup
  v_rate_count := public.cleanup_expired_otp_rate_events();

  -- FCM token cleanup (already exists)
  v_fcm_count := public.cleanup_stale_fcm_tokens();

  -- SMS archival
  v_sms_result := public.archive_stale_momo_sms(90);

  RETURN jsonb_build_object(
    'otp_codes_deleted', v_otp_count,
    'otp_rate_events_deleted', v_rate_count,
    'fcm_tokens_deleted', v_fcm_count,
    'sms_archival', v_sms_result,
    'run_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.run_scheduled_cleanup() IS
  'Orchestrates all scheduled cleanup tasks. Call from pg_cron or a daily '
  'Edge Function. Returns a summary of all cleanup actions taken.';
