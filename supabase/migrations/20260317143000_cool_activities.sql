-- ══════════════════════════════════════════════════════════════════════════════
-- cool_activities: Admin-managed catalog of token-earning activities
-- ══════════════════════════════════════════════════════════════════════════════

-- 1) Table
CREATE TABLE IF NOT EXISTS public.cool_activities (
  id             uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  slug           text UNIQUE NOT NULL,
  title          text NOT NULL,
  description    text NOT NULL DEFAULT '',
  emoji          text NOT NULL DEFAULT '⭐',
  category       text NOT NULL DEFAULT 'general',
  tokens_awarded int  NOT NULL DEFAULT 20,
  is_active      boolean NOT NULL DEFAULT true,
  sort_order     int  NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.cool_activities ENABLE ROW LEVEL SECURITY;
-- Public read for all authenticated users
DROP POLICY IF EXISTS cool_activities_select ON public.cool_activities;
CREATE POLICY cool_activities_select ON public.cool_activities
  FOR SELECT USING (true);
-- Admin-only write policies
DROP POLICY IF EXISTS cool_activities_admin_insert ON public.cool_activities;
CREATE POLICY cool_activities_admin_insert ON public.cool_activities
  FOR INSERT WITH CHECK (
    (auth.jwt()->'app_metadata'->>'is_admin')::boolean = true
  );
DROP POLICY IF EXISTS cool_activities_admin_update ON public.cool_activities;
CREATE POLICY cool_activities_admin_update ON public.cool_activities
  FOR UPDATE USING (
    (auth.jwt()->'app_metadata'->>'is_admin')::boolean = true
  );
DROP POLICY IF EXISTS cool_activities_admin_delete ON public.cool_activities;
CREATE POLICY cool_activities_admin_delete ON public.cool_activities
  FOR DELETE USING (
    (auth.jwt()->'app_metadata'->>'is_admin')::boolean = true
  );
-- Index for fast active-activity lookup
CREATE INDEX IF NOT EXISTS idx_cool_activities_active
  ON public.cool_activities (is_active, sort_order);
COMMENT ON TABLE public.cool_activities
  IS 'Admin-managed catalog of all token-earning activities. Each activity defines what users can do to earn Cool Tokens.';
-- 2) Seed 24 activities across 5 categories at 20 tokens each
INSERT INTO public.cool_activities (slug, title, description, emoji, category, tokens_awarded, sort_order) VALUES
  -- ── Groups (5) ──
  ('group_contribution',   'Group Contribution',    'Make a deposit to your savings group',         '💰', 'groups',   20,  1),
  ('group_cycle_complete',  'Group Cycle Complete',  'Complete a full group savings cycle',          '🎯', 'groups',   20,  2),
  ('group_created',         'Create a Group',        'Start a new savings or community group',       '🆕', 'groups',   20,  3),
  ('group_joined',          'Join a Group',          'Join an existing savings or community group',  '🤝', 'groups',   20,  4),
  ('group_goal_reached',    'Group Goal Reached',    'Help your group reach its savings goal',       '🏁', 'groups',   20,  5),

  -- ── Rayon Sport (5) ──
  ('match_attendance',      'Match Attendance',      'Attend a Rayon Sports match in person',        '⚽', 'rayon',    20,  6),
  ('initiative_support',    'Initiative Support',    'Support a Rayon Sports initiative',            '🤝', 'rayon',    20,  7),
  ('club_joined',           'Join Fan Club',         'Become a Rayon Sports fan club member',        '🏟️', 'rayon',    20,  8),
  ('merchandise_purchase',  'Purchase Merchandise',  'Buy official Rayon Sports merchandise',        '👕', 'rayon',    20,  9),
  ('match_prediction',      'Match Prediction',      'Submit a match prediction before kickoff',     '🔮', 'rayon',    20, 10),

  -- ── Mobility (4) ──
  ('trip_completed',        'Complete a Trip',       'Complete a ride as passenger or driver',        '🚗', 'mobility', 20, 11),
  ('trip_posted',           'Post a Trip',           'Post your route to offer rides',                '📍', 'mobility', 20, 12),
  ('trip_rated',            'Rate a Trip',           'Leave a rating after completing a trip',        '⭐', 'mobility', 20, 13),
  ('first_trip',            'First Trip Bonus',      'Complete your very first trip on Cool',         '🎉', 'mobility', 20, 14),

  -- ── Social (4) ──
  ('invite_qualified',      'Invite a Friend',       'Invite a friend who completes a qualifying action', '🎉', 'social', 20, 15),
  ('profile_completed',     'Complete Your Profile', 'Fill in all your profile details',              '📝', 'social',   20, 16),
  ('app_shared',            'Share the App',         'Share Cool with friends on social media',       '📲', 'social',   20, 17),
  ('review_posted',         'Post an App Review',    'Leave a review on Google Play Store',           '✍️', 'social',   20, 18),

  -- ── General (6) ──
  ('shop_purchase',         'Shop Purchase',         'Complete a purchase in the Cool shop',          '🛍️', 'general',  20, 19),
  ('streak_maintained',     'Maintain Weekly Streak', 'Keep your weekly activity streak alive',       '🔥', 'general',  20, 20),
  ('mission_completed',     'Complete a Mission',    'Finish a cooperative mission goal',             '🏆', 'general',  20, 21),
  ('daily_login',           'Daily App Open',        'Open the app and engage daily',                 '📱', 'general',  20, 22),
  ('momo_transaction',      'MoMo Transaction Sync', 'Sync a MoMo transaction to your statement',    '💳', 'general',  20, 23),
  ('feedback_submitted',    'Submit Feedback',       'Share your feedback to improve Cool',           '💬', 'general',  20, 24)
ON CONFLICT (slug) DO UPDATE SET
  title          = EXCLUDED.title,
  description    = EXCLUDED.description,
  emoji          = EXCLUDED.emoji,
  category       = EXCLUDED.category,
  tokens_awarded = EXCLUDED.tokens_awarded,
  sort_order     = EXCLUDED.sort_order,
  updated_at     = now();
