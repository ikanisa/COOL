-- ════════════════════════════════════════════════════════════════
-- Periodic cleanup of edge-function rate-limit events
-- Prevents unbounded table growth.
-- ════════════════════════════════════════════════════════════════

-- pg_cron is already enabled on Supabase by default.

-- Schedule a job every 15 minutes to delete events older than 1 hour.
SELECT cron.schedule(
  'purge_edge_function_rate_events',   -- job name
  '*/15 * * * *',                       -- every 15 minutes
  $$DELETE FROM public.edge_function_rate_events WHERE created_at < now() - interval '1 hour'$$
);
