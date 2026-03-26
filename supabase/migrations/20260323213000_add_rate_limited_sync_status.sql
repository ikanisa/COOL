-- ============================================================================
-- Add 'rate_limited' to momo_sms_sync_runs status check constraint
-- Required by client-side Fix 1: rate-limit awareness in sync loop
-- ============================================================================

alter table public.momo_sms_sync_runs
  drop constraint if exists momo_sms_sync_runs_status_check;

alter table public.momo_sms_sync_runs
  add constraint momo_sms_sync_runs_status_check
    check (status in ('running', 'succeeded', 'failed', 'rate_limited'));
