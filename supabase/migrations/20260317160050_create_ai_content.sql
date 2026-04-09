-- ════════════════════════════════════════════════════════════════
-- AI Content (Nexus Recommendations)
-- Backfilled before initial seed so historical ordering is valid.
-- ════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.ai_content (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title           text NOT NULL,
  subtitle        text,
  body            text,
  rationale       text,
  content_type    text NOT NULL DEFAULT 'recommendation',
  status          text NOT NULL DEFAULT 'draft',
  icon_emoji      text,
  cta_action      text,
  cta_label       text,
  sort_order      int NOT NULL DEFAULT 0,
  is_active       boolean NOT NULL DEFAULT false,
  country         text,
  created_by      uuid REFERENCES auth.users(id),
  reviewed_by     uuid REFERENCES auth.users(id),
  reviewed_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ai_content ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ai_content_read_active" ON public.ai_content;
CREATE POLICY "ai_content_read_active"
  ON public.ai_content
  FOR SELECT
  TO authenticated
  USING (status = 'approved' AND is_active = true);

DROP POLICY IF EXISTS "ai_content_admin_read_all" ON public.ai_content;
CREATE POLICY "ai_content_admin_read_all"
  ON public.ai_content
  FOR SELECT
  TO authenticated
  USING ((auth.jwt()->'app_metadata'->>'is_admin')::boolean = true);

DROP POLICY IF EXISTS "ai_content_admin_write" ON public.ai_content;
CREATE POLICY "ai_content_admin_write"
  ON public.ai_content
  FOR ALL
  TO authenticated
  USING ((auth.jwt()->'app_metadata'->>'is_admin')::boolean = true)
  WITH CHECK ((auth.jwt()->'app_metadata'->>'is_admin')::boolean = true);
