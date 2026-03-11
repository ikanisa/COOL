-- Cool Status seed data: 1 active season + 2 missions
-- Matches the actual schema from migrations

-- ── Active Season ────────────────────────────────────────────────
INSERT INTO public.cool_seasons (
  title, theme, emoji, starts_at, ends_at, is_active, rewards_description
) VALUES (
  'Rise Season',
  'supporter',
  '🏅',
  '2026-03-01'::timestamptz,
  '2026-06-01'::timestamptz,
  true,
  'Earn points across groups, matches, trips, and support to climb the leaderboard.'
) ON CONFLICT DO NOTHING;

-- ── Mission 1: Group challenge ───────────────────────────────────
INSERT INTO public.cool_missions (
  title, description, mission_type, target_value, scope_type,
  emoji, starts_at, ends_at, reward_points, reward_description, is_active
) VALUES (
  'Community Builders',
  'Collectively reach 50 group contributions this month.',
  'savings_sprint',
  50,
  'global',
  '👥',
  '2026-03-01'::timestamptz,
  '2026-04-01'::timestamptz,
  100,
  'Bonus 100 pts for all contributors',
  true
) ON CONFLICT DO NOTHING;

-- ── Mission 2: Match attendance ──────────────────────────────────
INSERT INTO public.cool_missions (
  title, description, mission_type, target_value, scope_type,
  emoji, starts_at, ends_at, reward_points, reward_description, is_active
) VALUES (
  'Matchday Heroes',
  'Attend 3 Rayon Sports matches this season.',
  'matchday_month',
  3,
  'global',
  '⚽',
  '2026-03-01'::timestamptz,
  '2026-06-01'::timestamptz,
  50,
  'Bonus 50 pts for loyal fans',
  true
) ON CONFLICT DO NOTHING;
