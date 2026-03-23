-- ══════════════════════════════════════════════════════════════════
-- COOL STATUS — Unified social-progression tables
-- ══════════════════════════════════════════════════════════════════

-- 1) cool_status: per-user cross-app points / tier / streak
CREATE TABLE IF NOT EXISTS public.cool_status (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
  total_points   int  DEFAULT 0    NOT NULL,
  tier           text DEFAULT 'blue' NOT NULL,
  current_streak int  DEFAULT 0    NOT NULL,
  longest_streak int  DEFAULT 0    NOT NULL,
  streak_grace_remaining int DEFAULT 1 NOT NULL,
  season_points  int  DEFAULT 0    NOT NULL,
  active_season_id uuid,
  updated_at  timestamptz DEFAULT now() NOT NULL,
  created_at  timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.cool_status ENABLE ROW LEVEL SECURITY;
-- Users can read their own status
CREATE POLICY cool_status_select ON public.cool_status
  FOR SELECT USING (auth.uid() = user_id);
-- Users can insert their own initial row
CREATE POLICY cool_status_insert ON public.cool_status
  FOR INSERT WITH CHECK (auth.uid() = user_id);
-- Users can update their own status
CREATE POLICY cool_status_update ON public.cool_status
  FOR UPDATE USING (auth.uid() = user_id);
-- 2) cool_events: event log for point attribution
CREATE TABLE IF NOT EXISTS public.cool_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  event_type  text NOT NULL,
  source_id   text,
  points_awarded int DEFAULT 0,
  metadata    jsonb DEFAULT '{}'::jsonb,
  referrer_id uuid,
  created_at  timestamptz DEFAULT now() NOT NULL
);
ALTER TABLE public.cool_events ENABLE ROW LEVEL SECURITY;
-- Users can read their own events
CREATE POLICY cool_events_select ON public.cool_events
  FOR SELECT USING (auth.uid() = user_id);
-- Users can insert their own events
CREATE POLICY cool_events_insert ON public.cool_events
  FOR INSERT WITH CHECK (auth.uid() = user_id);
-- 3) cool_invite_attributions: double-sided invite tracking
CREATE TABLE IF NOT EXISTS public.cool_invite_attributions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  inviter_id  uuid REFERENCES auth.users(id) NOT NULL,
  invitee_id  uuid REFERENCES auth.users(id) NOT NULL,
  qualifying_event_type text,
  qualifying_event_id   uuid,
  points_awarded_inviter int DEFAULT 0,
  points_awarded_invitee int DEFAULT 0,
  created_at  timestamptz DEFAULT now() NOT NULL,
  UNIQUE(inviter_id, invitee_id)
);
ALTER TABLE public.cool_invite_attributions ENABLE ROW LEVEL SECURITY;
-- Users can see attributions where they are inviter or invitee
CREATE POLICY cool_invite_attr_select ON public.cool_invite_attributions
  FOR SELECT USING (auth.uid() = inviter_id OR auth.uid() = invitee_id);
-- Users can insert where they are the invitee (qualifying action fires)
CREATE POLICY cool_invite_attr_insert ON public.cool_invite_attributions
  FOR INSERT WITH CHECK (auth.uid() = invitee_id);
-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_cool_status_user ON public.cool_status(user_id);
CREATE INDEX IF NOT EXISTS idx_cool_events_user ON public.cool_events(user_id);
CREATE INDEX IF NOT EXISTS idx_cool_events_type ON public.cool_events(event_type);
CREATE INDEX IF NOT EXISTS idx_cool_invite_inviter ON public.cool_invite_attributions(inviter_id);
CREATE INDEX IF NOT EXISTS idx_cool_invite_invitee ON public.cool_invite_attributions(invitee_id);
COMMENT ON TABLE public.cool_status IS 'Unified cross-app status: points, tier, streaks.';
COMMENT ON TABLE public.cool_events IS 'Event log for all point-awarding actions.';
COMMENT ON TABLE public.cool_invite_attributions IS 'Double-sided invite tracking for qualified referrals.';
