-- ==========================================================================
-- Cool App — Extend OTP abuse telemetry for phone-scoped limits
-- ==========================================================================

alter table public.otp_rate_events
  drop constraint if exists otp_rate_events_action_check;
alter table public.otp_rate_events
  add constraint otp_rate_events_action_check
  check (action in ('send_ip', 'send_phone', 'verify_ip', 'verify_phone'));
comment on table public.otp_rate_events is
  'Service-role-only OTP abuse telemetry for IP- and phone-scoped send and verify limits.';
revoke all on table public.otp_rate_events from public;
revoke all on table public.otp_rate_events from anon;
revoke all on table public.otp_rate_events from authenticated;
