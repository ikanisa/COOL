-- Standardize bank partner services to exactly 3 CTAs.
-- This migration deletes all existing services for bank partners
-- and replaces them with exactly 3 standard services per bank.
--
-- Allowed bank CTAs:
--   1. Open a Bank Account  → internal:open_account
--   2. Get a Loan           → internal:get_loan
--   3. Create Group Saving  → internal:group_savings
--
-- Non-bank partners (Prisma, Radiant, Rayon) are NOT touched.

-- ── Step 1: Delete all existing bank partner services ─────────────────────

delete from public.partner_services
where partner_id in (
  select id
  from public.partners
  where category = 'bank'
);
-- ── Step 2: Insert exactly 3 standard services per bank partner ──────────

insert into public.partner_services (
  partner_id,
  title,
  subtitle,
  emoji,
  category,
  details,
  cta_label,
  cta_action,
  country,
  sort_order,
  is_active
)
select
  p.id,
  s.title,
  s.subtitle,
  s.emoji,
  s.category,
  s.details,
  s.cta_label,
  s.cta_action,
  p.country,
  s.sort_order,
  true
from public.partners p
cross join (
  values
    (
      'Open a Bank Account',
      'Start banking today',
      '🏦',
      'banking',
      '[]'::jsonb,
      'Open Account',
      'internal:open_account',
      0
    ),
    (
      'Get a Loan',
      'Apply for credit',
      '💰',
      'banking',
      '[]'::jsonb,
      'Get a Loan',
      'internal:get_loan',
      1
    ),
    (
      'Create Group Saving',
      'Save with others',
      '👥',
      'banking',
      '[]'::jsonb,
      'Create Group',
      'internal:group_savings',
      2
    )
) as s(title, subtitle, emoji, category, details, cta_label, cta_action, sort_order)
where p.category = 'bank';
-- ── Step 3: Add a comment documenting the guardrail ──────────────────────

comment on table public.partner_services is
  'Dynamic partner services managed via admin. '
  'GUARDRAIL: Bank partners (category=bank) must have exactly 3 services: '
  'internal:open_account, internal:get_loan, internal:group_savings. '
  'Non-bank partners have their own service schemas.';
