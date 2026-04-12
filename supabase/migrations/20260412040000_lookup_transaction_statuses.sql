-- ==========================================================================
-- Phase 1D: transaction_statuses lookup table
-- ==========================================================================
-- Replaces duplicated CHECK (status IN ('pending','confirmed','failed'))
-- on group_contributions and pending_transactions with a single source
-- of truth.
-- ==========================================================================

-- 1. Create lookup table
CREATE TABLE IF NOT EXISTS public.transaction_statuses (
  code        TEXT PRIMARY KEY,
  label       TEXT NOT NULL,
  is_terminal BOOLEAN NOT NULL DEFAULT false,
  sort_order  INT NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Seed
INSERT INTO public.transaction_statuses (code, label, is_terminal, sort_order) VALUES
  ('pending',   'Pending',   false, 0),
  ('confirmed', 'Confirmed', true,  1),
  ('failed',    'Failed',    true,  2)
ON CONFLICT (code) DO NOTHING;

-- 3. Drop duplicated CHECK constraints
ALTER TABLE public.group_contributions
  DROP CONSTRAINT IF EXISTS group_contributions_status_check;

ALTER TABLE public.pending_transactions
  DROP CONSTRAINT IF EXISTS pending_transactions_status_check;

-- 4. Add FK constraints
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_group_contributions_status'
      AND table_name = 'group_contributions'
  ) THEN
    ALTER TABLE public.group_contributions
      ADD CONSTRAINT fk_group_contributions_status
      FOREIGN KEY (status) REFERENCES public.transaction_statuses(code);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'fk_pending_transactions_status'
      AND table_name = 'pending_transactions'
  ) THEN
    ALTER TABLE public.pending_transactions
      ADD CONSTRAINT fk_pending_transactions_status
      FOREIGN KEY (status) REFERENCES public.transaction_statuses(code);
  END IF;
END $$;

-- 5. RLS: public read (statuses are reference data)
ALTER TABLE public.transaction_statuses ENABLE ROW LEVEL SECURITY;

CREATE POLICY transaction_statuses_select_all
  ON public.transaction_statuses FOR SELECT
  USING (true);

CREATE POLICY transaction_statuses_admin_write
  ON public.transaction_statuses FOR ALL
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());
