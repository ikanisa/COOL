-- ==========================================================================
-- Cool App — Secure Operational Health Policy
-- ==========================================================================
-- This migration removes the direct authenticated insert policy for 
-- operational_health_events. Mobile clients must use the 
-- 'record-operational-health' Edge Function, which enforces 
-- service/component allowlists, rate limits, and metadata sanitization.

drop policy if exists operational_health_events_insert_authenticated
  on public.operational_health_events;
-- Ensure only the service role (via Edge Functions) can insert.
-- The select policy for admins remains intact.

comment on policy operational_health_events_select_admin on public.operational_health_events is
  'Admins can view the full operational health feed for triage and release monitoring.';
