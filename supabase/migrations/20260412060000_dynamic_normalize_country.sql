-- ==========================================================================
-- Phase 2B: Dynamic normalize_country_code()
-- ==========================================================================
-- Replaces the 70-line hardcoded CASE statement with a dynamic lookup
-- against supported_countries table.
-- ==========================================================================

CREATE OR REPLACE FUNCTION public.normalize_country_code(raw_value text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    -- 1. Try exact ISO code match (case-insensitive)
    (SELECT sc.iso_code
     FROM public.supported_countries sc
     WHERE sc.iso_code = upper(trim(raw_value))
     LIMIT 1),

    -- 2. Try country name match (case-insensitive)
    (SELECT sc.iso_code
     FROM public.supported_countries sc
     WHERE lower(sc.country_name) = lower(trim(raw_value))
     LIMIT 1),

    -- 3. Fallback to configured default country
    (SELECT ac.value
     FROM public.app_config ac
     WHERE ac.key = 'default_country'),

    -- 4. Ultimate hardcoded fallback (should never reach here)
    'RW'
  );
$$;

COMMENT ON FUNCTION public.normalize_country_code(text) IS
  'Dynamically normalizes a country name or code to its ISO code using the '
  'supported_countries table. Replaces the previous 70-line hardcoded CASE.';
