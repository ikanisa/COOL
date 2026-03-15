-- ==========================================================================
-- Cool App — Restrict Operational Health Telemetry
-- ==========================================================================

-- Revoke direct insert access for authenticated users to protect telemetry integrity.
-- Only the service role (via Edge Functions) should be able to insert events.
drop policy if exists operational_health_events_insert_authenticated
  on public.operational_health_events;

-- Re-enable insert only for service role (implicit, as no other policy allows it for authenticated/anon)
-- Note: We keep the select policy for admins so the dashboard remains functional.
