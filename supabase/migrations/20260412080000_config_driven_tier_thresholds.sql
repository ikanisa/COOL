-- ==========================================================================
-- Phase 2D: Status tier thresholds from config
-- ==========================================================================
-- Makes cool_status_tier_for_points() read thresholds from app_config
-- instead of hardcoded values.
-- ==========================================================================

-- 1. Seed tier threshold config
INSERT INTO public.app_config (key, value, description) VALUES
  ('tier_platinum_min', '5000', 'Minimum points for Platinum tier'),
  ('tier_gold_min',     '2000', 'Minimum points for Gold tier'),
  ('tier_silver_min',   '1000', 'Minimum points for Silver tier')
ON CONFLICT (key) DO NOTHING;

-- 2. Replace function with config-driven version
CREATE OR REPLACE FUNCTION public.cool_status_tier_for_points(p_points int)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN greatest(coalesce(p_points, 0), 0) >=
      coalesce(
        (SELECT value::int FROM public.app_config WHERE key = 'tier_platinum_min'),
        5000
      ) THEN 'platinum'
    WHEN greatest(coalesce(p_points, 0), 0) >=
      coalesce(
        (SELECT value::int FROM public.app_config WHERE key = 'tier_gold_min'),
        2000
      ) THEN 'gold'
    WHEN greatest(coalesce(p_points, 0), 0) >=
      coalesce(
        (SELECT value::int FROM public.app_config WHERE key = 'tier_silver_min'),
        1000
      ) THEN 'silver'
    ELSE 'blue'
  END;
$$;

COMMENT ON FUNCTION public.cool_status_tier_for_points(int) IS
  'Maps total points to status tier. Thresholds are read from app_config '
  'so they can be tuned without a migration.';
