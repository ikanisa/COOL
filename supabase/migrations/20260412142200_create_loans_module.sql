-- ============================================================
-- Loans Module: tables, sequences, triggers, RLS, RPC
-- ============================================================

-- 1. Loan code sequence
CREATE SEQUENCE IF NOT EXISTS public.loan_code_seq START 1001;

-- 2. Loans table
CREATE TABLE IF NOT EXISTS public.loans (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_code           text UNIQUE NOT NULL DEFAULT ('L-' || nextval('public.loan_code_seq')::text),
  member_id           uuid NOT NULL REFERENCES public.users(id),
  group_id            uuid NOT NULL REFERENCES public.groups(id),
  loan_type           text NOT NULL DEFAULT 'general'
                      CHECK (loan_type IN ('solar','insurance','taxes','emoto','general')),
  initial_amount      numeric NOT NULL CHECK (initial_amount > 0),
  total_paid          numeric NOT NULL DEFAULT 0,
  repayment_amount    numeric NOT NULL CHECK (repayment_amount > 0),
  repayment_frequency text NOT NULL DEFAULT 'daily'
                      CHECK (repayment_frequency IN ('daily','weekly','monthly')),
  status              text NOT NULL DEFAULT 'active'
                      CHECK (status IN ('active','completed','non_performing','defaulted')),
  issued_at           timestamptz NOT NULL DEFAULT now(),
  due_date            timestamptz,
  completed_at        timestamptz,
  notes               text,
  created_by          uuid REFERENCES public.users(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- Balance is computed: initial_amount - total_paid (no stored generated col needed,
-- we compute it in queries for max compat)

CREATE INDEX IF NOT EXISTS idx_loans_member ON public.loans(member_id);
CREATE INDEX IF NOT EXISTS idx_loans_group ON public.loans(group_id);
CREATE INDEX IF NOT EXISTS idx_loans_status ON public.loans(status);

-- 3. Loan repayments table
CREATE TABLE IF NOT EXISTS public.loan_repayments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  loan_id     uuid NOT NULL REFERENCES public.loans(id) ON DELETE CASCADE,
  amount      numeric NOT NULL CHECK (amount > 0),
  method      text NOT NULL DEFAULT 'cash'
              CHECK (method IN ('cash','momo')),
  reference   text,
  recorded_by uuid REFERENCES public.users(id),
  notes       text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_loan_repayments_loan ON public.loan_repayments(loan_id);

-- 4. Trigger: after repayment insert → update loan.total_paid + status
CREATE OR REPLACE FUNCTION public.trg_loan_repayment_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_total numeric;
  v_initial numeric;
BEGIN
  -- Sum all repayments for this loan
  SELECT COALESCE(sum(amount), 0) INTO v_total
  FROM public.loan_repayments WHERE loan_id = NEW.loan_id;

  -- Get initial amount
  SELECT initial_amount INTO v_initial
  FROM public.loans WHERE id = NEW.loan_id;

  -- Update loan
  UPDATE public.loans SET
    total_paid = v_total,
    status = CASE
      WHEN v_total >= v_initial THEN 'completed'
      ELSE status  -- preserve current status
    END,
    completed_at = CASE
      WHEN v_total >= v_initial AND completed_at IS NULL THEN now()
      ELSE completed_at
    END,
    updated_at = now()
  WHERE id = NEW.loan_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_loan_repayment_after_insert ON public.loan_repayments;
CREATE TRIGGER trg_loan_repayment_after_insert
  AFTER INSERT ON public.loan_repayments
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_loan_repayment_update();

-- 5. RLS policies
ALTER TABLE public.loans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loan_repayments ENABLE ROW LEVEL SECURITY;

-- Admin full access
CREATE POLICY loans_admin_all ON public.loans
  FOR ALL USING (public.is_admin());

CREATE POLICY loan_repayments_admin_all ON public.loan_repayments
  FOR ALL USING (public.is_admin());

-- Members can read their own loans
CREATE POLICY loans_member_read ON public.loans
  FOR SELECT USING (member_id = auth.uid());

CREATE POLICY loan_repayments_member_read ON public.loan_repayments
  FOR SELECT USING (
    loan_id IN (SELECT id FROM public.loans WHERE member_id = auth.uid())
  );

-- 6. Admin RPC: get_admin_loans_summary
CREATE OR REPLACE FUNCTION public.get_admin_loans_summary()
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin access required.';
  END IF;

  SELECT jsonb_build_object(
    'total_loans',       (SELECT count(*) FROM public.loans),
    'active_loans',      (SELECT count(*) FROM public.loans WHERE status = 'active'),
    'completed_loans',   (SELECT count(*) FROM public.loans WHERE status = 'completed'),
    'non_performing',    (SELECT count(*) FROM public.loans WHERE status = 'non_performing'),
    'defaulted_loans',   (SELECT count(*) FROM public.loans WHERE status = 'defaulted'),
    'total_disbursed',   (SELECT COALESCE(sum(initial_amount), 0) FROM public.loans),
    'total_collected',   (SELECT COALESCE(sum(total_paid), 0) FROM public.loans),
    'outstanding_balance', (SELECT COALESCE(sum(initial_amount - total_paid), 0) FROM public.loans WHERE status IN ('active','non_performing')),
    'generated_at', now()
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- 7. No production seed data.
-- Loan rows must be created through admin write contracts so staging/production
-- data remains auditable and deterministic.
