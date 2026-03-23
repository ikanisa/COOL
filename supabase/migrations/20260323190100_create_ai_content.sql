-- ════════════════════════════════════════════════════════════════
-- AI Content (Nexus Recommendations)
--
-- This DDL was missing from checked-in migrations.
-- The table was previously created directly in the remote project.
-- Reconciling here so local reproducibility is complete.
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

-- ── RLS ──────────────────────────────────────────────────────
ALTER TABLE public.ai_content ENABLE ROW LEVEL SECURITY;

-- Approved + active content is publicly readable by any authenticated user.
DROP POLICY IF EXISTS "ai_content_read_active" ON public.ai_content;
CREATE POLICY "ai_content_read_active"
  ON public.ai_content
  FOR SELECT
  TO authenticated
  USING (status = 'approved' AND is_active = true);

-- Admins can read all content (any status).
DROP POLICY IF EXISTS "ai_content_admin_read_all" ON public.ai_content;
CREATE POLICY "ai_content_admin_read_all"
  ON public.ai_content
  FOR SELECT
  TO authenticated
  USING ((auth.jwt()->'app_metadata'->>'is_admin')::boolean = true);

-- Admins can insert, update, and delete.
DROP POLICY IF EXISTS "ai_content_admin_write" ON public.ai_content;
CREATE POLICY "ai_content_admin_write"
  ON public.ai_content
  FOR ALL
  TO authenticated
  USING ((auth.jwt()->'app_metadata'->>'is_admin')::boolean = true)
  WITH CHECK ((auth.jwt()->'app_metadata'->>'is_admin')::boolean = true);
