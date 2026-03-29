-- ═══════════════════════════════════════════════════════════════════════
-- Migration: Fan Engagement — Polls, Predictions, AI Commentary
-- File: 20260329120000_fan_engagement_polls_predictions.sql
-- Blueprint: Phase 3 — Match Polls, Predictions, AI Commentary, Leaderboard
-- ═══════════════════════════════════════════════════════════════════════

-- ── 0. Roster on matches (admin-managed player list for MOTM picks) ──

ALTER TABLE rs_matches ADD COLUMN IF NOT EXISTS roster JSONB DEFAULT '[]'::jsonb;

-- ── 1. Match Polls ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rs_match_polls (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id    UUID NOT NULL REFERENCES rs_matches(id) ON DELETE CASCADE,
  poll_type   TEXT NOT NULL DEFAULT 'custom'
              CHECK (poll_type IN ('score_prediction', 'motm', 'fan_mood', 'custom')),
  question    TEXT NOT NULL,
  options     JSONB NOT NULL DEFAULT '[]'::jsonb,
  is_active   BOOL NOT NULL DEFAULT true,
  closes_at   TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rs_match_polls_match ON rs_match_polls(match_id);
CREATE INDEX IF NOT EXISTS idx_rs_match_polls_active ON rs_match_polls(is_active) WHERE is_active = true;

-- ── 2. Poll Votes ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rs_poll_votes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id         UUID NOT NULL REFERENCES rs_match_polls(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  selected_option TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(poll_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_rs_poll_votes_poll ON rs_poll_votes(poll_id);
CREATE INDEX IF NOT EXISTS idx_rs_poll_votes_user ON rs_poll_votes(user_id);

-- ── 3. Match Predictions ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rs_match_predictions (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id              UUID NOT NULL REFERENCES rs_matches(id) ON DELETE CASCADE,
  user_id               UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  predicted_home_score  INT NOT NULL DEFAULT 0,
  predicted_away_score  INT NOT NULL DEFAULT 0,
  predicted_motm        TEXT,
  xp_awarded            INT NOT NULL DEFAULT 0,
  is_correct            BOOL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(match_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_rs_match_predictions_match ON rs_match_predictions(match_id);
CREATE INDEX IF NOT EXISTS idx_rs_match_predictions_user ON rs_match_predictions(user_id);

-- ── 4. AI Match Commentary ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rs_match_commentary (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id         UUID NOT NULL REFERENCES rs_matches(id) ON DELETE CASCADE,
  commentary_type  TEXT NOT NULL DEFAULT 'recap'
                   CHECK (commentary_type IN ('preview', 'recap', 'highlight')),
  title            TEXT NOT NULL,
  body             TEXT NOT NULL DEFAULT '',
  metadata         JSONB DEFAULT '{}'::jsonb,
  is_published     BOOL NOT NULL DEFAULT false,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_rs_match_commentary_match ON rs_match_commentary(match_id);
CREATE INDEX IF NOT EXISTS idx_rs_match_commentary_published
  ON rs_match_commentary(is_published) WHERE is_published = true;

-- ── 5. RLS ────────────────────────────────────────────────────────────

ALTER TABLE rs_match_polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE rs_poll_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE rs_match_predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE rs_match_commentary ENABLE ROW LEVEL SECURITY;

-- Polls: public read
DROP POLICY IF EXISTS "Anyone can read polls" ON rs_match_polls;
CREATE POLICY "Anyone can read polls"
  ON rs_match_polls FOR SELECT USING (true);

-- Polls: admin write
DROP POLICY IF EXISTS "Admins can manage polls" ON rs_match_polls;
CREATE POLICY "Admins can manage polls"
  ON rs_match_polls FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM auth.users
      WHERE auth.uid() = id
        AND raw_user_meta_data->>'role' IN ('admin', 'super_admin')
    )
  );

-- Votes: auth insert own
DROP POLICY IF EXISTS "Auth users can vote" ON rs_poll_votes;
CREATE POLICY "Auth users can vote"
  ON rs_poll_votes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Votes: read own + public aggregate (we'll aggregate via RPC)
DROP POLICY IF EXISTS "Users can read own votes" ON rs_poll_votes;
CREATE POLICY "Users can read own votes"
  ON rs_poll_votes FOR SELECT
  USING (auth.uid() = user_id);

-- Predictions: auth insert own
DROP POLICY IF EXISTS "Auth users can predict" ON rs_match_predictions;
CREATE POLICY "Auth users can predict"
  ON rs_match_predictions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Predictions: read own
DROP POLICY IF EXISTS "Users can read own predictions" ON rs_match_predictions;
CREATE POLICY "Users can read own predictions"
  ON rs_match_predictions FOR SELECT
  USING (auth.uid() = user_id);

-- Predictions: admin can read all + update (for XP awarding)
DROP POLICY IF EXISTS "Admins can manage predictions" ON rs_match_predictions;
CREATE POLICY "Admins can manage predictions"
  ON rs_match_predictions FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM auth.users
      WHERE auth.uid() = id
        AND raw_user_meta_data->>'role' IN ('admin', 'super_admin')
    )
  );

-- Commentary: public read when published
DROP POLICY IF EXISTS "Anyone can read published commentary" ON rs_match_commentary;
CREATE POLICY "Anyone can read published commentary"
  ON rs_match_commentary FOR SELECT
  USING (is_published = true);

-- Commentary: admin write
DROP POLICY IF EXISTS "Admins can manage commentary" ON rs_match_commentary;
CREATE POLICY "Admins can manage commentary"
  ON rs_match_commentary FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM auth.users
      WHERE auth.uid() = id
        AND raw_user_meta_data->>'role' IN ('admin', 'super_admin')
    )
  );

-- ── 6. RPC: Poll Results ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_poll_results(p_poll_id UUID)
RETURNS TABLE (
  selected_option TEXT,
  vote_count BIGINT,
  percentage NUMERIC(5,2)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  total_votes BIGINT;
BEGIN
  SELECT count(*) INTO total_votes
  FROM rs_poll_votes WHERE poll_id = p_poll_id;

  RETURN QUERY
  SELECT
    v.selected_option,
    count(*) AS vote_count,
    CASE WHEN total_votes > 0
      THEN round((count(*)::numeric / total_votes::numeric) * 100, 2)
      ELSE 0
    END AS percentage
  FROM rs_poll_votes v
  WHERE v.poll_id = p_poll_id
  GROUP BY v.selected_option
  ORDER BY vote_count DESC;
END;
$$;

-- ── 7. RPC: Fan Leaderboard ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_fan_leaderboard(
  p_limit INT DEFAULT 20,
  p_offset INT DEFAULT 0
)
RETURNS TABLE (
  rank BIGINT,
  user_id UUID,
  total_xp BIGINT,
  prediction_count BIGINT,
  correct_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    row_number() OVER (ORDER BY coalesce(sum(p.xp_awarded), 0) DESC) AS rank,
    p.user_id,
    coalesce(sum(p.xp_awarded), 0)::bigint AS total_xp,
    count(*)::bigint AS prediction_count,
    count(*) FILTER (WHERE p.is_correct = true)::bigint AS correct_count
  FROM rs_match_predictions p
  GROUP BY p.user_id
  ORDER BY total_xp DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

-- ── 8. RPC: Award Prediction XP ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.award_prediction_xp(
  p_match_id UUID,
  p_home_score INT,
  p_away_score INT,
  p_exact_xp INT DEFAULT 500,
  p_correct_result_xp INT DEFAULT 200,
  p_participation_xp INT DEFAULT 50
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated_count INT := 0;
BEGIN
  -- Exact score match
  UPDATE rs_match_predictions
  SET
    is_correct = true,
    xp_awarded = p_exact_xp
  WHERE match_id = p_match_id
    AND predicted_home_score = p_home_score
    AND predicted_away_score = p_away_score;
  GET DIAGNOSTICS updated_count = ROW_COUNT;

  -- Correct result (win/draw/loss) but wrong score
  UPDATE rs_match_predictions
  SET
    is_correct = false,
    xp_awarded = p_correct_result_xp
  WHERE match_id = p_match_id
    AND xp_awarded = 0
    AND (
      (p_home_score > p_away_score AND predicted_home_score > predicted_away_score) OR
      (p_home_score < p_away_score AND predicted_home_score < predicted_away_score) OR
      (p_home_score = p_away_score AND predicted_home_score = predicted_away_score)
    );

  -- Participation XP for everyone else
  UPDATE rs_match_predictions
  SET
    is_correct = false,
    xp_awarded = p_participation_xp
  WHERE match_id = p_match_id
    AND xp_awarded = 0;

  RETURN updated_count;
END;
$$;

-- ── 9. Realtime: Commentary ───────────────────────────────────────────

ALTER PUBLICATION supabase_realtime ADD TABLE rs_match_commentary;

-- ═══════════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ═══════════════════════════════════════════════════════════════════════
-- DROP FUNCTION IF EXISTS public.award_prediction_xp;
-- DROP FUNCTION IF EXISTS public.get_fan_leaderboard;
-- DROP FUNCTION IF EXISTS public.get_poll_results;
-- DROP TABLE IF EXISTS rs_match_commentary;
-- DROP TABLE IF EXISTS rs_match_predictions;
-- DROP TABLE IF EXISTS rs_poll_votes;
-- DROP TABLE IF EXISTS rs_match_polls;
