-- ═══════════════════════════════════════════════════════════════════════
-- FCM Push Notification Token Storage
-- ═══════════════════════════════════════════════════════════════════════
--
-- Stores Firebase Cloud Messaging tokens per user. Each user may have
-- multiple tokens (one per device). Tokens are upserted on registration,
-- refreshed automatically, and deleted on sign-out.
--
-- Used by Edge Functions to send targeted push notifications for:
--   • Payment sync confirmation
--   • Trip status updates
--   • Ticket reminders
--   • Group activity
--   • Partner offers
-- ═══════════════════════════════════════════════════════════════════════

-- ── Table ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_fcm_tokens (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token         TEXT NOT NULL,
  platform      TEXT NOT NULL DEFAULT 'android',
  device_info   JSONB DEFAULT '{}'::jsonb,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT uq_user_fcm_token UNIQUE (user_id, token)
);
-- Index for server-side lookups (send push to all devices of a user).
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user_id
  ON public.user_fcm_tokens (user_id);
-- Index for token-based cleanup (deduplicate stale tokens).
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_token
  ON public.user_fcm_tokens (token);
-- ── RLS ──────────────────────────────────────────────────────────────
ALTER TABLE public.user_fcm_tokens ENABLE ROW LEVEL SECURITY;
-- Users can read, insert, update, and delete only their own tokens.
CREATE POLICY "Users manage own FCM tokens"
  ON public.user_fcm_tokens
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
-- Service role can read all tokens (needed for Edge Functions sending push).
CREATE POLICY "Service role reads all FCM tokens"
  ON public.user_fcm_tokens
  FOR SELECT
  TO service_role
  USING (true);
-- ── Cleanup function: remove tokens older than 60 days ──────────────
-- Call periodically via pg_cron or a scheduled Edge Function.
CREATE OR REPLACE FUNCTION public.cleanup_stale_fcm_tokens()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count INTEGER;
BEGIN
  DELETE FROM public.user_fcm_tokens
  WHERE updated_at < now() - INTERVAL '60 days';

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count;
END;
$$;
