-- ══════════════════════════════════════════════════════════════════
-- COOL SEASONS — 2–4 week live-ops campaigns
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.cool_seasons (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title       text NOT NULL,
  theme       text NOT NULL,         -- 'savings', 'supporter', 'commuter', 'matchday'
  emoji       text DEFAULT '🏅',
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz NOT NULL,
  is_active   bool DEFAULT false,
  rewards_description text,
  created_at  timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.cool_seasons ENABLE ROW LEVEL SECURITY;
-- Everyone can read seasons
CREATE POLICY cool_seasons_select ON public.cool_seasons
  FOR SELECT USING (true);
-- Index for quick active season lookup
CREATE INDEX IF NOT EXISTS idx_cool_seasons_active
  ON public.cool_seasons(is_active, starts_at, ends_at);
-- Link active season to cool_status
ALTER TABLE public.cool_status
  ADD CONSTRAINT fk_cool_status_season
  FOREIGN KEY (active_season_id)
  REFERENCES public.cool_seasons(id)
  ON DELETE SET NULL;
COMMENT ON TABLE public.cool_seasons IS 'Time-limited engagement campaigns (2-4 weeks).';
