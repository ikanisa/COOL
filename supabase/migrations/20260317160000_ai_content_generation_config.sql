-- ════════════════════════════════════════════════════════════════
-- AI Content Generation Config
-- Admin toggle for auto-generation + scheduling metadata
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.ai_content_generation_config (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  is_enabled    boolean NOT NULL DEFAULT false,
  interval_hours int NOT NULL DEFAULT 12,
  last_generated_at timestamptz,
  updated_at    timestamptz DEFAULT now(),
  updated_by    uuid REFERENCES auth.users(id)
);

-- Insert singleton row (only one config record ever)
INSERT INTO public.ai_content_generation_config (is_enabled, interval_hours)
VALUES (false, 12)
ON CONFLICT DO NOTHING;

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.ai_content_generation_config ENABLE ROW LEVEL SECURITY;

-- Anyone authenticated can read config
DROP POLICY IF EXISTS "ai_gen_config_read" ON public.ai_content_generation_config;
CREATE POLICY "ai_gen_config_read"
  ON public.ai_content_generation_config
  FOR SELECT
  TO authenticated
  USING (true);

-- Only admins can update
DROP POLICY IF EXISTS "ai_gen_config_admin_write" ON public.ai_content_generation_config;
CREATE POLICY "ai_gen_config_admin_write"
  ON public.ai_content_generation_config
  FOR UPDATE
  TO authenticated
  USING ((auth.jwt()->'app_metadata'->>'is_admin')::boolean = true)
  WITH CHECK ((auth.jwt()->'app_metadata'->>'is_admin')::boolean = true);
