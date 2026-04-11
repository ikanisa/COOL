-- ═══════════════════════════════════════════════════════════════════════
-- Purge Gamification System
-- ═══════════════════════════════════════════════════════════════════════
--
-- Drops all gamification tables, triggers, functions, crons, and RLS
-- policies. The gamification system was removed from the app codebase.
--
-- Tables dropped: cool_status, cool_missions, cool_mission_progress,
--   cool_achievements, cool_rewards, cool_reward_redemptions,
--   cool_seasons, cool_events, cool_invite_attributions, cool_activities
-- ═══════════════════════════════════════════════════════════════════════

-- ── 1. Drop notification trigger for mission completion ─────────────

DROP TRIGGER IF EXISTS trg_notify_mission_completed ON public.cool_mission_progress;
DROP FUNCTION IF EXISTS public.notify_mission_completed();

-- ── 2. Drop gamification RPCs ───────────────────────────────────────

DROP FUNCTION IF EXISTS public.award_points(uuid, integer, text, text);
DROP FUNCTION IF EXISTS public.record_cool_event(uuid, text, text, integer, jsonb);
DROP FUNCTION IF EXISTS public.get_leaderboard(integer, integer);
DROP FUNCTION IF EXISTS public.complete_mission(uuid, uuid);
DROP FUNCTION IF EXISTS public.claim_reward(uuid, uuid);
DROP FUNCTION IF EXISTS public.refresh_missions();
DROP FUNCTION IF EXISTS public.get_my_missions(uuid);

-- ── 3. Drop cron jobs ───────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobname)
    FROM cron.job
    WHERE jobname IN (
      'refresh_missions',
      'season_rollover',
      'leaderboard_snapshot'
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[purge_gamification] cron cleanup skipped: %', SQLERRM;
END $$;

-- ── 4. Drop tables (cascade removes policies, indexes, triggers) ────

DROP TABLE IF EXISTS public.cool_activities CASCADE;
DROP TABLE IF EXISTS public.cool_invite_attributions CASCADE;
DROP TABLE IF EXISTS public.cool_events CASCADE;
DROP TABLE IF EXISTS public.cool_reward_redemptions CASCADE;
DROP TABLE IF EXISTS public.cool_rewards CASCADE;
DROP TABLE IF EXISTS public.cool_achievements CASCADE;
DROP TABLE IF EXISTS public.cool_mission_progress CASCADE;
DROP TABLE IF EXISTS public.cool_missions CASCADE;
DROP TABLE IF EXISTS public.cool_seasons CASCADE;
DROP TABLE IF EXISTS public.cool_status CASCADE;

-- ── 5. Drop any leftover functions from engagement_foundation ───────

DROP FUNCTION IF EXISTS public.handle_cool_event_points();
DROP FUNCTION IF EXISTS public.award_achievement_if_eligible();
DROP FUNCTION IF EXISTS public.check_season_boundaries();
DROP FUNCTION IF EXISTS public.get_cool_leaderboard(integer, integer);
