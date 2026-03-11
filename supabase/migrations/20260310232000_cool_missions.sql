-- ══════════════════════════════════════════════════════════════════
-- COOL MISSIONS — Cooperative time-bound group goals
-- ══════════════════════════════════════════════════════════════════

-- 1) cool_missions: group/chapter/global mission definitions
CREATE TABLE IF NOT EXISTS public.cool_missions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id   uuid,
  title       text NOT NULL,
  description text,
  mission_type text NOT NULL,         -- 'savings_sprint', 'supporter_season', 'commuter_week', 'matchday_month'
  target_value int  NOT NULL,         -- goal: total group contributions, attendance count, etc.
  scope_type  text NOT NULL DEFAULT 'global',  -- 'group', 'chapter', 'global'
  scope_id    text,                   -- group_id, chapter name, or null for global
  emoji       text DEFAULT '🎯',
  starts_at   timestamptz NOT NULL,
  ends_at     timestamptz NOT NULL,
  reward_points int DEFAULT 0,
  reward_description text,
  is_active   bool DEFAULT true,
  created_at  timestamptz DEFAULT now() NOT NULL
);

ALTER TABLE public.cool_missions ENABLE ROW LEVEL SECURITY;

-- Everyone can read active missions
CREATE POLICY cool_missions_select ON public.cool_missions
  FOR SELECT USING (true);

-- 2) cool_mission_progress: per-user progress toward a mission
CREATE TABLE IF NOT EXISTS public.cool_mission_progress (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mission_id       uuid REFERENCES cool_missions(id) ON DELETE CASCADE NOT NULL,
  user_id          uuid REFERENCES auth.users(id)     ON DELETE CASCADE NOT NULL,
  contribution_value int DEFAULT 0 NOT NULL,
  completed_at     timestamptz,
  updated_at       timestamptz DEFAULT now() NOT NULL,
  created_at       timestamptz DEFAULT now() NOT NULL,
  UNIQUE(mission_id, user_id)
);

ALTER TABLE public.cool_mission_progress ENABLE ROW LEVEL SECURITY;

-- Users can read their own progress
CREATE POLICY cool_mission_progress_select ON public.cool_mission_progress
  FOR SELECT USING (auth.uid() = user_id);

-- Users can insert their own progress
CREATE POLICY cool_mission_progress_insert ON public.cool_mission_progress
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can update their own progress
CREATE POLICY cool_mission_progress_update ON public.cool_mission_progress
  FOR UPDATE USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_cool_missions_active ON public.cool_missions(is_active, starts_at, ends_at);
CREATE INDEX IF NOT EXISTS idx_cool_mission_progress_mission ON public.cool_mission_progress(mission_id);
CREATE INDEX IF NOT EXISTS idx_cool_mission_progress_user ON public.cool_mission_progress(user_id);

COMMENT ON TABLE public.cool_missions IS 'Time-bound cooperative missions (savings sprints, supporter seasons, etc.).';
COMMENT ON TABLE public.cool_mission_progress IS 'Per-user contribution tracking toward mission goals.';
