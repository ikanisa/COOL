-- ==============================================================================
-- Audit Fixes: Missing Tables
-- Creates `special_products` and `supported_country_momo_reference`
-- ==============================================================================

-- ------------------------------------------------------------------------------
-- 1. Table: special_products
-- ------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.special_products (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  slug text NOT NULL UNIQUE,
  title text NOT NULL,
  subtitle text DEFAULT ''::text NOT NULL,
  description text DEFAULT ''::text NOT NULL,
  amount integer NOT NULL DEFAULT 0,
  currency text NOT NULL DEFAULT 'RWF'::text,
  icon_name text NOT NULL DEFAULT 'star'::text,
  color_hex text NOT NULL DEFAULT '#C9A84C'::text,
  interest_rate text,
  loan_multiplier text,
  momo_recipient text NOT NULL,
  momo_recipient_type text NOT NULL DEFAULT 'code'::text,
  target_audience text NOT NULL DEFAULT 'Everyone'::text,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL
);
-- RLS
ALTER TABLE public.special_products ENABLE ROW LEVEL SECURITY;
-- Policy: Anyone can read active products, auth users can read all products (or just everyone can read all)
CREATE POLICY "Public read access for special_products"
  ON public.special_products FOR SELECT
  USING (true);
-- Policy: Only admins can insert/update/delete
CREATE POLICY "Admin full access to special_products"
  ON public.special_products FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
-- ------------------------------------------------------------------------------
-- 2. Table or View: supported_country_momo_reference
-- ------------------------------------------------------------------------------
-- Dart code queries this as:
--   _client.from('supported_country_momo_reference').select(...)
-- First we check if it's already a view (it might be a view over supported_countries). 
-- If not, we create it as a view over supported_countries.

DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relname = 'supported_country_momo_reference'
      AND n.nspname = 'public'
  ) THEN
    -- In the app repo, `supported_country_momo_reference` is often just `supported_countries` 
    -- but structured slightly differently, or it's a direct alias. We will create it as a View.
    CREATE VIEW public.supported_country_momo_reference AS
      SELECT 
        iso_code, 
        country_name, 
        flag_emoji, 
        dial_code, 
        currency_code, 
        currency_name, 
        momo_provider_id, 
        country_aliases, 
        momo_provider_aliases, 
        mobile_national_number_pattern, 
        mobile_possible_lengths, 
        mobile_example_national, 
        mobile_example_e164, 
        momo_number_local_pattern, 
        momo_number_e164_pattern, 
        momo_number_ussd_template, 
        momo_number_ussd_regex, 
        momo_number_ussd_example, 
        momo_code_kind, 
        momo_code_pattern, 
        momo_code_min_length, 
        momo_code_max_length, 
        momo_code_example, 
        momo_code_ussd_template, 
        momo_code_ussd_regex, 
        momo_code_ussd_example, 
        phone_validation_source, 
        momo_ussd_source, 
        validation_notes, 
        default_lat, 
        default_lng, 
        sort_order, 
        is_active, 
        updated_at,
        -- supports_momo_code is derived in Dart but might be queried
        (momo_code_ussd_template IS NOT NULL AND momo_code_ussd_template <> '') AS supports_momo_code
      FROM public.supported_countries;

    -- Grant read access to the view
    GRANT SELECT ON public.supported_country_momo_reference TO authenticated;
    GRANT SELECT ON public.supported_country_momo_reference TO anon;
  END IF;
END $$;
