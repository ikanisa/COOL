-- ==========================================================================
-- Cool App - Remove obsolete MoMo webhook artifacts
-- ==========================================================================
-- Cool only supports payer-owned USSD initiation plus Android SMS-based
-- M-Money verification. There is no server-side MoMo webhook path.
-- ==========================================================================

drop table if exists public.momo_webhook_events;
