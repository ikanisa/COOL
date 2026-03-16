-- ══════════════════════════════════════════════════════════════
-- Bank Loans & Baskets tables + RPCs + RLS
-- ══════════════════════════════════════════════════════════════

-- 1) bank_loans table
CREATE TABLE IF NOT EXISTS public.bank_loans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  member_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount numeric(15,2) NOT NULL DEFAULT 0,
  interest_rate numeric(5,2) NOT NULL DEFAULT 0,
  repaid_amount numeric(15,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','disbursed','repaying','completed','defaulted','rejected')),
  disbursed_at timestamptz,
  due_at timestamptz,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.bank_loans ENABLE ROW LEVEL SECURITY;

-- RLS: platform admins see all; bank admins see only their partner scope
CREATE POLICY bank_loans_select ON public.bank_loans FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.admin_role_assignments ara
    WHERE ara.user_id = auth.uid()
      AND ara.is_active = true
      AND (
        ara.role = 'admin'
        OR (ara.role = 'bank' AND (ara.partner_scope_id IS NULL OR ara.partner_scope_id = bank_loans.partner_id))
      )
  )
);

CREATE POLICY bank_loans_modify ON public.bank_loans FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.admin_role_assignments ara
    WHERE ara.user_id = auth.uid()
      AND ara.is_active = true
      AND (
        ara.role = 'admin'
        OR (ara.role = 'bank' AND (ara.partner_scope_id IS NULL OR ara.partner_scope_id = bank_loans.partner_id))
      )
  )
);

-- 2) bank_baskets table (savings targets)
CREATE TABLE IF NOT EXISTS public.bank_baskets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id uuid NOT NULL REFERENCES public.partners(id) ON DELETE CASCADE,
  group_id uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  name text NOT NULL DEFAULT 'Savings Basket',
  target_amount numeric(15,2) NOT NULL DEFAULT 0,
  current_amount numeric(15,2) NOT NULL DEFAULT 0,
  deadline timestamptz,
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','completed','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.bank_baskets ENABLE ROW LEVEL SECURITY;

CREATE POLICY bank_baskets_select ON public.bank_baskets FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.admin_role_assignments ara
    WHERE ara.user_id = auth.uid()
      AND ara.is_active = true
      AND (
        ara.role = 'admin'
        OR (ara.role = 'bank' AND (ara.partner_scope_id IS NULL OR ara.partner_scope_id = bank_baskets.partner_id))
      )
  )
);

CREATE POLICY bank_baskets_modify ON public.bank_baskets FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.admin_role_assignments ara
    WHERE ara.user_id = auth.uid()
      AND ara.is_active = true
      AND (
        ara.role = 'admin'
        OR (ara.role = 'bank' AND (ara.partner_scope_id IS NULL OR ara.partner_scope_id = bank_baskets.partner_id))
      )
  )
);

-- 3) RPCs

-- Get loans for a bank partner
CREATE OR REPLACE FUNCTION public.get_bank_loans(
  p_partner_id uuid,
  p_status text DEFAULT NULL,
  p_limit int DEFAULT 100,
  p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO result
  FROM (
    SELECT
      bl.id, bl.partner_id, bl.group_id, bl.member_user_id,
      bl.amount, bl.interest_rate, bl.repaid_amount, bl.status,
      bl.disbursed_at, bl.due_at, bl.notes,
      bl.created_at, bl.updated_at,
      g.name AS group_name,
      u.phone AS member_phone,
      COALESCE(u.full_name, u.phone) AS member_name,
      (SELECT count(*) FROM public.bank_loans bl2
       WHERE bl2.partner_id = p_partner_id
       AND (p_status IS NULL OR bl2.status = p_status)) AS total_count
    FROM public.bank_loans bl
    JOIN public.groups g ON g.id = bl.group_id
    JOIN public.users u ON u.id = bl.member_user_id
    WHERE bl.partner_id = p_partner_id
      AND (p_status IS NULL OR bl.status = p_status)
    ORDER BY bl.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) t;

  RETURN COALESCE(result, '[]'::jsonb);
END;
$$;

-- Approve/reject a loan
CREATE OR REPLACE FUNCTION public.update_bank_loan_status(
  p_loan_id uuid,
  p_status text,
  p_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.bank_loans
  SET
    status = p_status,
    updated_at = now(),
    notes = COALESCE(p_notes, notes),
    disbursed_at = CASE WHEN p_status = 'disbursed' THEN now() ELSE disbursed_at END
  WHERE id = p_loan_id;
END;
$$;

-- Get baskets for a bank partner
CREATE OR REPLACE FUNCTION public.get_bank_baskets(
  p_partner_id uuid,
  p_status text DEFAULT NULL,
  p_limit int DEFAULT 100,
  p_offset int DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_agg(row_to_json(t))
  INTO result
  FROM (
    SELECT
      bb.id, bb.partner_id, bb.group_id, bb.name,
      bb.target_amount, bb.current_amount, bb.deadline,
      bb.status, bb.created_at, bb.updated_at,
      g.name AS group_name,
      CASE WHEN bb.target_amount > 0
        THEN ROUND((bb.current_amount / bb.target_amount) * 100, 1)
        ELSE 0
      END AS progress_pct,
      (SELECT count(*) FROM public.bank_baskets bb2
       WHERE bb2.partner_id = p_partner_id
       AND (p_status IS NULL OR bb2.status = p_status)) AS total_count
    FROM public.bank_baskets bb
    JOIN public.groups g ON g.id = bb.group_id
    WHERE bb.partner_id = p_partner_id
      AND (p_status IS NULL OR bb.status = p_status)
    ORDER BY bb.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) t;

  RETURN COALESCE(result, '[]'::jsonb);
END;
$$;

-- Bank analytics summary
CREATE OR REPLACE FUNCTION public.get_bank_analytics_summary(p_partner_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'total_groups', (SELECT count(*) FROM public.groups g
                     JOIN public.group_members gm ON gm.group_id = g.id
                     WHERE g.id IN (SELECT DISTINCT bl.group_id FROM public.bank_loans bl WHERE bl.partner_id = p_partner_id)
                        OR g.id IN (SELECT DISTINCT bb.group_id FROM public.bank_baskets bb WHERE bb.partner_id = p_partner_id)),
    'total_loans', (SELECT count(*) FROM public.bank_loans WHERE partner_id = p_partner_id),
    'active_loans', (SELECT count(*) FROM public.bank_loans WHERE partner_id = p_partner_id AND status IN ('disbursed','repaying')),
    'pending_loans', (SELECT count(*) FROM public.bank_loans WHERE partner_id = p_partner_id AND status = 'pending'),
    'defaulted_loans', (SELECT count(*) FROM public.bank_loans WHERE partner_id = p_partner_id AND status = 'defaulted'),
    'total_disbursed', (SELECT COALESCE(sum(amount), 0) FROM public.bank_loans WHERE partner_id = p_partner_id AND status NOT IN ('pending','rejected')),
    'total_repaid', (SELECT COALESCE(sum(repaid_amount), 0) FROM public.bank_loans WHERE partner_id = p_partner_id),
    'default_rate', CASE
      WHEN (SELECT count(*) FROM public.bank_loans WHERE partner_id = p_partner_id AND status NOT IN ('pending','rejected')) > 0
      THEN ROUND(
        (SELECT count(*) FROM public.bank_loans WHERE partner_id = p_partner_id AND status = 'defaulted')::numeric
        / (SELECT count(*) FROM public.bank_loans WHERE partner_id = p_partner_id AND status NOT IN ('pending','rejected'))::numeric * 100, 1)
      ELSE 0
    END,
    'total_baskets', (SELECT count(*) FROM public.bank_baskets WHERE partner_id = p_partner_id),
    'active_baskets', (SELECT count(*) FROM public.bank_baskets WHERE partner_id = p_partner_id AND status = 'active'),
    'total_basket_target', (SELECT COALESCE(sum(target_amount), 0) FROM public.bank_baskets WHERE partner_id = p_partner_id),
    'total_basket_saved', (SELECT COALESCE(sum(current_amount), 0) FROM public.bank_baskets WHERE partner_id = p_partner_id)
  ) INTO result;

  RETURN result;
END;
$$;
