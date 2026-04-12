-- ==========================================================================
-- Phase 1C: supported_languages table
-- ==========================================================================
-- Promotes the JSON string in app_config('supported_languages') to a
-- proper queryable table. Enables admin CRUD for language management.
-- ==========================================================================

-- 1. Create table
CREATE TABLE IF NOT EXISTS public.supported_languages (
  code        TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  flag_emoji  TEXT NOT NULL DEFAULT '🏳️',
  is_active   BOOLEAN NOT NULL DEFAULT true,
  sort_order  INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Seed from existing app_config JSON
INSERT INTO public.supported_languages (code, name, flag_emoji, sort_order) VALUES
  ('en', 'English',   '🇬🇧', 0),
  ('fr', 'Français',  '🇫🇷', 1),
  ('rw', 'Kinyarwanda', '🇷🇼', 2)
ON CONFLICT (code) DO NOTHING;

-- 3. Remove the old JSON string from app_config
DELETE FROM public.app_config WHERE key = 'supported_languages';

-- 4. RLS: public read, admin write
ALTER TABLE public.supported_languages ENABLE ROW LEVEL SECURITY;

CREATE POLICY supported_languages_select_all
  ON public.supported_languages FOR SELECT
  USING (true);

CREATE POLICY supported_languages_insert_admin
  ON public.supported_languages FOR INSERT
  WITH CHECK (public.is_admin_user());

CREATE POLICY supported_languages_update_admin
  ON public.supported_languages FOR UPDATE
  USING (public.is_admin_user());

CREATE POLICY supported_languages_delete_admin
  ON public.supported_languages FOR DELETE
  USING (public.is_admin_user());

-- 5. updated_at trigger
DROP TRIGGER IF EXISTS trg_supported_languages_set_updated_at ON public.supported_languages;
CREATE TRIGGER trg_supported_languages_set_updated_at
  BEFORE UPDATE ON public.supported_languages
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
