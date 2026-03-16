-- ============================================================================
-- Seed Mock Data for Bank Baskets & Bank Loans Features
-- ----------------------------------------------------------------------------
-- This script leverages the established test user base and partner records to
-- populate the newly implemented Bank Admin features (loans and savings baskets).
-- ============================================================================

begin;

-- ============================================================================
-- 1. Setup Runtime Context (Resolving existing core seed records)
-- ============================================================================
create temp table demo_context (
  mock_batch text primary key,
  bank_partner_id uuid not null,
  group_kigali_id uuid not null,
  group_western_id uuid not null,
  user_aline uuid not null,
  user_jean_claude uuid not null,
  user_diane uuid not null,
  user_matteo uuid not null
) on commit drop;

insert into demo_context (
  mock_batch,
  bank_partner_id,
  group_kigali_id,
  group_western_id,
  user_aline,
  user_jean_claude,
  user_diane,
  user_matteo
)
select
  'app_demo_seed_20260311',
  (select id from public.partners where slug = 'urwego-finance' limit 1),
  (select id from public.groups where invite_code = 'KGLM2026' limit 1),
  (select id from public.groups where invite_code = 'DBPL2026' limit 1),
  (select id from public.users where phone = '+250788767816' limit 1),
  (select id from public.users where phone = '+25075588248' limit 1),
  (select id from public.users where phone = '+25088817592' limit 1),
  (select id from public.users where phone = '+35677186193' limit 1);

do $$
begin
  if exists (
    select 1
    from demo_context
    where bank_partner_id is null
       or group_kigali_id is null
       or group_western_id is null
       or user_aline is null
       or user_jean_claude is null
       or user_diane is null
       or user_matteo is null
  ) then
    raise exception
      'Core demo users, groups, or partners missing. Expected 20260311214500_demo_users_and_comprehensive_mock_seed.sql to have run first.';
  end if;
end $$;


-- ============================================================================
-- 2. Seed Bank Baskets (Savings Targets)
-- ============================================================================
insert into public.bank_baskets (
  id,
  partner_id,
  group_id,
  name,
  target_amount,
  current_amount,
  deadline,
  status,
  is_mock,
  mock_batch,
  created_at
)
select
  gen_random_uuid(),
  ctx.bank_partner_id,
  group_id,
  name,
  target_amount,
  current_amount,
  deadline,
  status,
  true,
  ctx.mock_batch,
  created_at
from demo_context ctx
cross join (
  values
    -- Kigali Group: Active saving towards rent renewal
    (
      (select group_kigali_id from demo_context),
      'Q2 Market Rent Renewal',
      500000,
      150000,
      now() + interval '30 days',
      'active',
      now() - interval '15 days'
    ),
    -- Kigali Group: Completed saving
    (
      (select group_kigali_id from demo_context),
      'Emergency Buffer Pool',
      200000,
      200000,
      now() - interval '2 days',
      'completed',
      now() - interval '45 days'
    ),
    -- Western Group: Active Saving
    (
      (select group_western_id from demo_context),
      'Travel Fund - Huye Away Day',
      300000,
      80000,
      now() + interval '10 days',
      'active',
      now() - interval '5 days'
    )
) as baskets(
  group_id, name, target_amount, current_amount, deadline, status, created_at
);


-- ============================================================================
-- 3. Seed Bank Loans (Coverage for diverse statuses)
-- ============================================================================
insert into public.bank_loans (
  id,
  partner_id,
  group_id,
  member_user_id,
  amount,
  interest_rate,
  repaid_amount,
  status,
  disbursed_at,
  due_at,
  notes,
  is_mock,
  mock_batch,
  created_at
)
select
  gen_random_uuid(),
  ctx.bank_partner_id,
  group_id,
  member_user_id,
  amount,
  interest_rate,
  repaid_amount,
  status,
  disbursed_at,
  due_at,
  notes,
  true,
  ctx.mock_batch,
  created_at
from demo_context ctx
cross join (
  values
    ---------------------------------------------------------------------------
    -- Aline: Actively repaying a larger loan
    ---------------------------------------------------------------------------
    (
      (select group_western_id from demo_context),
      (select user_aline from demo_context),
      350000.00,
      2.50,
      120000.00,
      'repaying',
      now() - interval '20 days',
      now() + interval '10 days',
      'Stock expansion loan approved by group mandate.',
      now() - interval '25 days'
    ),
    -- Aline: A previous completed cycle
    (
      (select group_western_id from demo_context),
      (select user_aline from demo_context),
      100000.00,
      1.50,
      101500.00,
      'completed',
      now() - interval '60 days',
      now() - interval '30 days',
      'Short term float cash, fully settled.',
      now() - interval '65 days'
    ),
    ---------------------------------------------------------------------------
    -- Jean Claude: Pending review
    ---------------------------------------------------------------------------
    (
      (select group_kigali_id from demo_context),
      (select user_jean_claude from demo_context),
      150000.00,
      3.00,
      0.00,
      'pending',
      null,
      null,
      'Requested for moto maintenance.',
      now() - interval '2 days'
    ),
    ---------------------------------------------------------------------------
    -- Diane: Defaulted
    ---------------------------------------------------------------------------
    (
      (select group_western_id from demo_context),
      (select user_diane from demo_context),
      80000.00,
      4.00,
      20000.00,
      'defaulted',
      now() - interval '45 days',
      now() - interval '15 days',
      'Reconciliation missed 3 consecutive cycles. Escalated.',
      now() - interval '50 days'
    ),
    ---------------------------------------------------------------------------
    -- Matteo: Rejected (Example of poor group standing)
    ---------------------------------------------------------------------------
    (
      (select group_kigali_id from demo_context),
      (select user_matteo from demo_context),
      500000.00,
      5.00,
      0.00,
      'rejected',
      null,
      null,
      'High principal request without historical consistency.',
      now() - interval '7 days'
    ),
    ---------------------------------------------------------------------------
    -- General: Approved but awaiting disbursement
    ---------------------------------------------------------------------------
    (
      (select group_kigali_id from demo_context),
      (select user_diane from demo_context),
      50000.00,
      2.00,
      0.00,
      'approved',
      null,
      now() + interval '30 days',
      'Urwego KYC step pending before release.',
      now() - interval '1 days'
    )
) as loans(
  group_id, member_user_id, amount, interest_rate, repaid_amount, status,
  disbursed_at, due_at, notes, created_at
);

-- ============================================================================
-- 4. Mark existing Nexus Opportunities as active batch members
-- ============================================================================
update public.nexus_opportunities
set 
  is_mock = true,
  mock_batch = (select mock_batch from demo_context)
where title IN ('Urwego Agri-Loan', 'Moto Subscription');

commit;
