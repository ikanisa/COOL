-- ──────────────────────────────────────────────────────────────────────
-- Purge remaining Rayon-era tables and functions not covered by
-- 20260404082430_purge_rayon_sports.sql.
--
-- These tables were created in the Rayon Sports extension migrations
-- (20260310200000, 20260310213000, 20260310220000) but are no longer
-- referenced by any client or edge function code.
--
-- Tables still actively used (cool_status, cool_events, cool_missions,
-- cool_mission_progress, cool_seasons, cool_invite_attributions,
-- quest_definitions, quest_progress, season_definitions,
-- season_memberships) are NOT dropped.
-- ──────────────────────────────────────────────────────────────────────

-- Orphan referral tables (no Dart or edge function references)
DROP TABLE IF EXISTS public.referral_conversions CASCADE;
DROP TABLE IF EXISTS public.referral_invites CASCADE;

-- Orphan share_artifacts table (no references)
DROP TABLE IF EXISTS public.share_artifacts CASCADE;

-- Drop any leftover Rayon-related functions that may still exist
DROP FUNCTION IF EXISTS public.get_rayon_match_schedule();
DROP FUNCTION IF EXISTS public.get_rayon_shop_catalog();
DROP FUNCTION IF EXISTS public.get_rayon_fan_club_roster(uuid);
DROP FUNCTION IF EXISTS public.rayon_complete_initiative(uuid, uuid);
DROP FUNCTION IF EXISTS public.rayon_join_fan_club(uuid, uuid);
