-- ==========================================================================
-- Phase 2A: Config-driven country validation
-- ==========================================================================
-- Replaces 7 hardcoded CHECK (country = 'RW') constraints with a
-- config-driven trigger validation. Adding new countries requires only:
--   UPDATE app_config SET value = 'RW,UG' WHERE key = 'allowed_countries';
--   INSERT INTO supported_countries (...) VALUES (...);
-- Zero migrations needed.
-- ==========================================================================

-- 1. Add allowed_countries and default_country to app_config
INSERT INTO public.app_config (key, value, description) VALUES
  ('allowed_countries', 'RW', 'Comma-separated ISO codes of allowed countries'),
  ('default_country',   'RW', 'Default country for new users and groups')
ON CONFLICT (key) DO NOTHING;

-- 2. Validation helper: is this country currently allowed?
CREATE OR REPLACE FUNCTION public.is_allowed_country(p_country TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.supported_countries sc
    WHERE sc.iso_code = upper(trim(p_country))
      AND sc.is_active = true
      AND sc.iso_code = ANY(
        string_to_array(
          (SELECT value FROM public.app_config WHERE key = 'allowed_countries'),
          ','
        )
      )
  );
$$;

-- 3. Generic enforcement trigger function
CREATE OR REPLACE FUNCTION public.enforce_allowed_country()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.country IS NOT NULL AND NOT public.is_allowed_country(NEW.country) THEN
    RAISE EXCEPTION 'Country "%" is not currently allowed. Allowed: %',
      NEW.country,
      (SELECT value FROM public.app_config WHERE key = 'allowed_countries');
  END IF;
  RETURN NEW;
END;
$$;

-- 4. Enforcement trigger for supported_countries (checks iso_code, not country)
CREATE OR REPLACE FUNCTION public.enforce_allowed_country_iso()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- For supported_countries, validate iso_code against allowed list
  IF NEW.iso_code IS NOT NULL AND NOT (
    upper(trim(NEW.iso_code)) = ANY(
      string_to_array(
        (SELECT value FROM public.app_config WHERE key = 'allowed_countries'),
        ','
      )
    )
  ) THEN
    RAISE EXCEPTION 'Country ISO "%" is not currently allowed. Allowed: %',
      NEW.iso_code,
      (SELECT value FROM public.app_config WHERE key = 'allowed_countries');
  END IF;
  RETURN NEW;
END;
$$;

-- 5. Drop all 7 hardcoded CHECK constraints
ALTER TABLE public.supported_countries
  DROP CONSTRAINT IF EXISTS supported_countries_rwanda_only_check;

ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS users_country_rwanda_only_check;

ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS users_language_code_english_only_check;

ALTER TABLE public.groups
  DROP CONSTRAINT IF EXISTS groups_country_rwanda_only_check;

ALTER TABLE public.partners
  DROP CONSTRAINT IF EXISTS partners_country_rwanda_only_check;

ALTER TABLE public.partner_services
  DROP CONSTRAINT IF EXISTS partner_services_country_rwanda_only_check;

ALTER TABLE public.partner_payment_routes
  DROP CONSTRAINT IF EXISTS partner_payment_routes_country_rwanda_only_check;

ALTER TABLE public.quick_actions
  DROP CONSTRAINT IF EXISTS quick_actions_country_local_scope_check;

ALTER TABLE public.app_config
  DROP CONSTRAINT IF EXISTS app_config_country_local_scope_check;

-- 6. Add trigger-based enforcement to each table

DROP TRIGGER IF EXISTS trg_enforce_allowed_country_supported_countries ON public.supported_countries;
CREATE TRIGGER trg_enforce_allowed_country_supported_countries
  BEFORE INSERT OR UPDATE ON public.supported_countries
  FOR EACH ROW EXECUTE FUNCTION public.enforce_allowed_country_iso();

DROP TRIGGER IF EXISTS trg_enforce_allowed_country_users ON public.users;
CREATE TRIGGER trg_enforce_allowed_country_users
  BEFORE INSERT OR UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.enforce_allowed_country();

DROP TRIGGER IF EXISTS trg_enforce_allowed_country_groups ON public.groups;
CREATE TRIGGER trg_enforce_allowed_country_groups
  BEFORE INSERT OR UPDATE ON public.groups
  FOR EACH ROW EXECUTE FUNCTION public.enforce_allowed_country();

DROP TRIGGER IF EXISTS trg_enforce_allowed_country_partners ON public.partners;
CREATE TRIGGER trg_enforce_allowed_country_partners
  BEFORE INSERT OR UPDATE ON public.partners
  FOR EACH ROW EXECUTE FUNCTION public.enforce_allowed_country();

DROP TRIGGER IF EXISTS trg_enforce_allowed_country_partner_services ON public.partner_services;
CREATE TRIGGER trg_enforce_allowed_country_partner_services
  BEFORE INSERT OR UPDATE ON public.partner_services
  FOR EACH ROW EXECUTE FUNCTION public.enforce_allowed_country();

DROP TRIGGER IF EXISTS trg_enforce_allowed_country_partner_payment_routes ON public.partner_payment_routes;
CREATE TRIGGER trg_enforce_allowed_country_partner_payment_routes
  BEFORE INSERT OR UPDATE ON public.partner_payment_routes
  FOR EACH ROW EXECUTE FUNCTION public.enforce_allowed_country();

-- 7. Language validation trigger (replaces CHECK (language_code = 'en'))
CREATE OR REPLACE FUNCTION public.enforce_supported_language()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.language_code IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.supported_languages
    WHERE code = lower(trim(NEW.language_code))
      AND is_active = true
  ) THEN
    RAISE EXCEPTION 'Language "%" is not currently supported.', NEW.language_code;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_supported_language_users ON public.users;
CREATE TRIGGER trg_enforce_supported_language_users
  BEFORE INSERT OR UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.enforce_supported_language();
