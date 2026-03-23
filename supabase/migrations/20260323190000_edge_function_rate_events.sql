-- ════════════════════════════════════════════════════════════════
-- Edge-function rate-limiting events
-- Used by supabase/functions/_shared/rate_limit.ts to enforce
-- per-user invocation budgets on functions that proxy paid APIs.
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.edge_function_rate_events (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  function_name text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Fast lookup by (user_id, function_name, created_at) for the sliding-window count.
CREATE INDEX IF NOT EXISTS idx_ef_rate_events_user_fn_ts
  ON public.edge_function_rate_events (user_id, function_name, created_at DESC);

-- Auto-purge stale rows (older than 1 hour) to bound table size.
-- NOTE: Supabase pg_cron can be used to schedule a periodic delete:
--   DELETE FROM public.edge_function_rate_events WHERE created_at < now() - interval '1 hour';

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.edge_function_rate_events ENABLE ROW LEVEL SECURITY;

-- Edge functions use the service-role client (admin), so no user-facing policies needed.
-- Deny all direct user access.
DROP POLICY IF EXISTS "ef_rate_events_deny_all" ON public.edge_function_rate_events;
CREATE POLICY "ef_rate_events_deny_all"
  ON public.edge_function_rate_events
  FOR ALL
  TO authenticated
  USING (false);
