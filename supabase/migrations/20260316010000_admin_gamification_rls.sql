-- ══════════════════════════════════════════════════════════════════
-- ADMIN RLS POLICIES — Missions & Seasons write access
-- ══════════════════════════════════════════════════════════════════
-- Allows users with is_admin = true in app_metadata to
-- INSERT, UPDATE, DELETE on cool_missions and cool_seasons.
-- Existing public-read SELECT policies remain unchanged.
-- ══════════════════════════════════════════════════════════════════

-- ── cool_missions: admin write ──────────────────────────────────

CREATE POLICY cool_missions_admin_insert ON public.cool_missions
  FOR INSERT WITH CHECK (
    (auth.jwt()->'app_metadata'->>'is_admin')::boolean = true
  );

CREATE POLICY cool_missions_admin_update ON public.cool_missions
  FOR UPDATE USING (
    (auth.jwt()->'app_metadata'->>'is_admin')::boolean = true
  );

CREATE POLICY cool_missions_admin_delete ON public.cool_missions
  FOR DELETE USING (
    (auth.jwt()->'app_metadata'->>'is_admin')::boolean = true
  );

-- ── cool_seasons: admin write ───────────────────────────────────

CREATE POLICY cool_seasons_admin_insert ON public.cool_seasons
  FOR INSERT WITH CHECK (
    (auth.jwt()->'app_metadata'->>'is_admin')::boolean = true
  );

CREATE POLICY cool_seasons_admin_update ON public.cool_seasons
  FOR UPDATE USING (
    (auth.jwt()->'app_metadata'->>'is_admin')::boolean = true
  );

CREATE POLICY cool_seasons_admin_delete ON public.cool_seasons
  FOR DELETE USING (
    (auth.jwt()->'app_metadata'->>'is_admin')::boolean = true
  );
