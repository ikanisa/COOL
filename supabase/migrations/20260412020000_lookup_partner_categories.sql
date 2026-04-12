-- ==========================================================================
-- Phase 1B: partner_categories lookup table
-- ==========================================================================
-- Replaces CHECK (category IN ('football','bank','organization')) on
-- partners with a FK-backed lookup table.
-- ==========================================================================

-- 1. Create lookup table
CREATE TABLE IF NOT EXISTS public.partner_categories (
  code        TEXT PRIMARY KEY,
  label       TEXT NOT NULL,
  emoji       TEXT,
  sort_order  INT NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Seed existing values
INSERT INTO public.partner_categories (code, label, emoji, sort_order) VALUES
  ('football',     'Football Club',  '⚽', 0),
  ('bank',         'Bank / MFI',     '🏦', 1),
  ('organization', 'Organization',   '🏢', 2)
ON CONFLICT (code) DO NOTHING;

-- 3. Drop the hardcoded CHECK constraint
ALTER TABLE public.partners
  DROP CONSTRAINT IF EXISTS partners_category_check;

-- 4. Add FK constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_partners_category'
      AND table_name = 'partners'
  ) THEN
    ALTER TABLE public.partners
      ADD CONSTRAINT fk_partners_category
      FOREIGN KEY (category) REFERENCES public.partner_categories(code);
  END IF;
END $$;

-- 5. RLS: public read, admin write
ALTER TABLE public.partner_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY partner_categories_select_all
  ON public.partner_categories FOR SELECT
  USING (true);

CREATE POLICY partner_categories_insert_admin
  ON public.partner_categories FOR INSERT
  WITH CHECK (public.is_admin_user());

CREATE POLICY partner_categories_update_admin
  ON public.partner_categories FOR UPDATE
  USING (public.is_admin_user());

CREATE POLICY partner_categories_delete_admin
  ON public.partner_categories FOR DELETE
  USING (public.is_admin_user());

-- 6. updated_at trigger
DROP TRIGGER IF EXISTS trg_partner_categories_set_updated_at ON public.partner_categories;
CREATE TRIGGER trg_partner_categories_set_updated_at
  BEFORE UPDATE ON public.partner_categories
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
