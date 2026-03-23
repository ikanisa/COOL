-- ============================================================================
-- Partner mock data seed batch
-- Adds internal-only metadata for removable partner demo rows and seeds
-- realistic partner + service content used by the app.
-- ============================================================================

alter table public.partners
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
alter table public.partner_services
  add column if not exists is_mock boolean not null default false,
  add column if not exists mock_batch text;
comment on column public.partners.is_mock is
  'Internal-only marker for removable seeded/demo partner rows. Not intended for client display.';
comment on column public.partners.mock_batch is
  'Internal batch key used to bulk remove mock partner rows from admin or SQL.';
comment on column public.partner_services.is_mock is
  'Internal-only marker for removable seeded/demo partner service rows. Not intended for client display.';
comment on column public.partner_services.mock_batch is
  'Internal batch key used to bulk remove mock partner service rows from admin or SQL.';
with partner_seed (
  name,
  slug,
  category,
  country,
  emoji,
  subtitle,
  description,
  whatsapp_number,
  fan_count,
  club_count,
  game_count,
  is_active,
  sort_order
) as (
  values
    (
      'APR FC',
      'apr-fc',
      'football',
      'RW',
      '⚽',
      'Rwanda Premier League · Official Cool Partner',
      'APR FC supporter hub with memberships, fixtures, tickets, and merch discovery.',
      null,
      12480,
      34,
      5,
      true,
      10
    ),
    (
      'Urwego Finance',
      'urwego',
      'bank',
      'RW',
      '🏦',
      'Custodian of Group Savings · Microfinance Leader',
      'Microfinance partner for group savings custody, loans, and bank accounts.',
      null,
      48,
      3200000,
      0,
      true,
      20
    ),
    (
      'Akarusho SACCO',
      'akarusho-sacco',
      'bank',
      'RW',
      '🏦',
      'Community banking for savings circles and payroll groups',
      'Community SACCO focused on group wallets, payroll collection, and seasonal working-capital products.',
      null,
      96,
      8400000,
      0,
      true,
      30
    ),
    (
      'Kivu Capital',
      'kivu-capital',
      'bank',
      'RW',
      '💳',
      'SME collections, float management, and growth lending',
      'Digital finance partner for merchant collections, SME loans, and branchless account services.',
      null,
      54,
      12800000,
      0,
      true,
      40
    ),
    (
      'Radiant Insurance',
      'radiant',
      'organization',
      'RW',
      '🛡️',
      'Group savings insurance and member protection',
      'Insurance partner providing pooled-fund protection, family cover, and claims support for savings groups.',
      '250795588248',
      0,
      0,
      0,
      true,
      10
    ),
    (
      'SafeCover Rwanda',
      'safecover-rwanda',
      'organization',
      'RW',
      '🧰',
      'Asset protection, health cover, and fleet claims support',
      'Insurance advisory partner for SMEs, cooperatives, vehicles, and employee health bundles.',
      '250795588248',
      0,
      0,
      0,
      true,
      20
    ),
    (
      'PRISMA',
      'prisma',
      'organization',
      'RW',
      '⚖️',
      'Accounting · Tax · Audit · Legal · Advisory',
      'Professional services firm providing accounting, tax, legal, and advisory support.',
      '250795588248',
      0,
      0,
      0,
      true,
      30
    ),
    (
      'Inkingi Advisory',
      'inkingi-advisory',
      'organization',
      'RW',
      '📘',
      'Finance operations, board reporting, and compliance support',
      'Advisory partner supporting internal controls, board packs, finance operations, and SME compliance.',
      '250795588248',
      0,
      0,
      0,
      true,
      40
    )
)
insert into public.partners (
  name,
  slug,
  category,
  country,
  emoji,
  subtitle,
  description,
  whatsapp_number,
  fan_count,
  club_count,
  game_count,
  is_active,
  sort_order,
  is_mock,
  mock_batch
)
select
  name,
  slug,
  category,
  country,
  emoji,
  subtitle,
  description,
  whatsapp_number,
  fan_count,
  club_count,
  game_count,
  is_active,
  sort_order,
  true,
  'partners_mock_seed_20260311'
from partner_seed
on conflict (slug) do update
set
  name = excluded.name,
  category = excluded.category,
  country = excluded.country,
  emoji = excluded.emoji,
  subtitle = excluded.subtitle,
  description = excluded.description,
  whatsapp_number = excluded.whatsapp_number,
  fan_count = excluded.fan_count,
  club_count = excluded.club_count,
  game_count = excluded.game_count,
  is_active = excluded.is_active,
  sort_order = excluded.sort_order,
  is_mock = excluded.is_mock,
  mock_batch = excluded.mock_batch,
  updated_at = now();
with service_seed (
  partner_slug,
  title,
  subtitle,
  emoji,
  category,
  details,
  cta_label,
  cta_action,
  country,
  sort_order
) as (
  values
    (
      'urwego',
      'Group Savings',
      '48 groups custodied by Urwego Finance',
      '👥',
      'savings',
      '[{"label":"Total RWF Held","value":"3.2M","icon":"💎"},{"label":"Active Groups","value":"48","icon":"📊"},{"label":"Insurance","value":"Covered","icon":"🛡️"}]',
      'View My Groups',
      'route:/groups',
      'RW',
      0
    ),
    (
      'urwego',
      'Group Expansion Loan',
      '12% APR · 12 months · Up to 5M',
      '📈',
      'loan',
      '[{"label":"APR","value":"12%","icon":"📊"},{"label":"Term","value":"12 months","icon":"📅"},{"label":"Max Amount","value":"5M RWF","icon":"💰"}]',
      'Apply via USSD *525#',
      'ussd:*525#',
      'RW',
      1
    ),
    (
      'urwego',
      'Member Emergency Loan',
      '8% APR · 6 months · Up to 500K',
      '🆘',
      'loan',
      '[{"label":"APR","value":"8%","icon":"📊"},{"label":"Term","value":"6 months","icon":"📅"},{"label":"Max Amount","value":"500K RWF","icon":"💰"}]',
      'Apply via USSD *525#',
      'ussd:*525#',
      'RW',
      2
    ),
    (
      'urwego',
      'Agri-Business Loan',
      '10% APR · 18 months · Up to 3M',
      '🌾',
      'loan',
      '[{"label":"APR","value":"10%","icon":"📊"},{"label":"Term","value":"18 months","icon":"📅"},{"label":"Max Amount","value":"3M RWF","icon":"💰"}]',
      'Apply via USSD *525#',
      'ussd:*525#',
      'RW',
      3
    ),
    (
      'urwego',
      'Open a Bank Account',
      'Link your savings group to a real bank account',
      '🏧',
      'account',
      '[{"label":"Minimum Deposit","value":"5,000 RWF","icon":"💵"},{"label":"Monthly Fee","value":"Free","icon":"✨"},{"label":"Debit Card","value":"Included","icon":"💳"}]',
      'Open via USSD *525#',
      'ussd:*525#',
      'RW',
      4
    ),
    (
      'akarusho-sacco',
      'Circle Wallet',
      'Shared wallet for savings groups and treasury committees',
      '👛',
      'savings',
      '[{"label":"Active Groups","value":"96","icon":"👥"},{"label":"Float Protected","value":"8.4M RWF","icon":"🪙"},{"label":"Instant Statements","value":"Weekly","icon":"🧾"}]',
      'Open Group Wallet',
      'route:/groups',
      'RW',
      0
    ),
    (
      'akarusho-sacco',
      'Harvest Advance',
      '11% APR · 9 months · Up to 2M',
      '🌽',
      'loan',
      '[{"label":"APR","value":"11%","icon":"📊"},{"label":"Term","value":"9 months","icon":"📅"},{"label":"Disbursement","value":"48 hours","icon":"⚡"}]',
      'Request Callback',
      'ussd:*610#',
      'RW',
      1
    ),
    (
      'akarusho-sacco',
      'Payroll Bridge Loan',
      'Fast salary-backed top-up for verified members',
      '💼',
      'loan',
      '[{"label":"Ticket Size","value":"Up to 750K RWF","icon":"💰"},{"label":"Repayment","value":"3 months","icon":"📆"},{"label":"Collateral","value":"Salary checkoff","icon":"✅"}]',
      'Dial *610#',
      'ussd:*610#',
      'RW',
      2
    ),
    (
      'akarusho-sacco',
      'Agent Collection Till',
      'Receive kiosk and branchless collections into one ledger',
      '🏪',
      'account',
      '[{"label":"Settlement","value":"Same day","icon":"⏱️"},{"label":"Branches","value":"14 pickup points","icon":"📍"},{"label":"Alerts","value":"SMS + App","icon":"🔔"}]',
      'Talk to Collections',
      'ussd:*610#',
      'RW',
      3
    ),
    (
      'kivu-capital',
      'Merchant Float Manager',
      'Daily reconciliation for merchants and field teams',
      '📲',
      'account',
      '[{"label":"Settlements","value":"2x daily","icon":"🔄"},{"label":"Collectors","value":"54 active teams","icon":"🚚"},{"label":"Alerting","value":"Live balance SMS","icon":"📡"}]',
      'See Collections',
      'route:/momo',
      'RW',
      0
    ),
    (
      'kivu-capital',
      'SME Growth Line',
      '13% APR · 18 months · Up to 12M',
      '🏗️',
      'loan',
      '[{"label":"APR","value":"13%","icon":"📊"},{"label":"Ticket Size","value":"12M RWF","icon":"💼"},{"label":"Use Case","value":"Stock + equipment","icon":"📦"}]',
      'Request Assessment',
      'ussd:*772#',
      'RW',
      1
    ),
    (
      'kivu-capital',
      'School Fees Advance',
      'Short-tenor top-up for households and staff groups',
      '🎒',
      'loan',
      '[{"label":"Approval","value":"Same day","icon":"⚡"},{"label":"Term","value":"4 months","icon":"📅"},{"label":"Max Amount","value":"900K RWF","icon":"💰"}]',
      'Dial *772#',
      'ussd:*772#',
      'RW',
      2
    ),
    (
      'kivu-capital',
      'Branchless Business Account',
      'Digital account with SMS statements and merchant support',
      '💼',
      'account',
      '[{"label":"Opening Balance","value":"10,000 RWF","icon":"💵"},{"label":"Statement","value":"Monthly PDF","icon":"📄"},{"label":"Merchant Till","value":"Included","icon":"🏧"}]',
      'Open Account',
      'ussd:*772#',
      'RW',
      3
    ),
    (
      'radiant',
      'Group Savings Insurance',
      'Protect your group''s pooled funds',
      '👥',
      'insurance',
      '[{"label":"Coverage","value":"Up to 10M RWF","icon":"💎"},{"label":"Premium","value":"0.5% / month","icon":"📊"},{"label":"Claims","value":"48h turnaround","icon":"⚡"}]',
      'Chat about this cover',
      'whatsapp',
      'RW',
      0
    ),
    (
      'radiant',
      'Member Protection Plan',
      'Individual coverage for group members',
      '🫶',
      'insurance',
      '[{"label":"Life Cover","value":"5M RWF","icon":"❤️"},{"label":"Health","value":"Inpatient + Outpatient","icon":"🏥"},{"label":"Premium","value":"2,500 RWF / month","icon":"💰"}]',
      'Chat about this cover',
      'whatsapp',
      'RW',
      1
    ),
    (
      'radiant',
      'Agri-Insurance',
      'Crop and livestock coverage for farming groups',
      '🌾',
      'insurance',
      '[{"label":"Crop Cover","value":"Seasonal","icon":"🌱"},{"label":"Livestock","value":"Per animal","icon":"🐄"},{"label":"Weather Index","value":"Included","icon":"🌤️"}]',
      'Chat about this cover',
      'whatsapp',
      'RW',
      2
    ),
    (
      'safecover-rwanda',
      'Fleet Cover',
      'Vehicles, riders, and delivery fleets under one policy',
      '🚗',
      'insurance',
      '[{"label":"Cover Type","value":"Comprehensive","icon":"🛡️"},{"label":"Claims SLA","value":"72 hours","icon":"⏱️"},{"label":"Incident Hotline","value":"24/7","icon":"📞"}]',
      'Request a Quote',
      'whatsapp',
      'RW',
      0
    ),
    (
      'safecover-rwanda',
      'SME Asset Protection',
      'Shops, stock, and working equipment cover',
      '🏬',
      'insurance',
      '[{"label":"Property","value":"Fire + theft","icon":"🔥"},{"label":"Stock Cover","value":"Included","icon":"📦"},{"label":"Premium Billing","value":"Monthly","icon":"🗓️"}]',
      'Request a Quote',
      'whatsapp',
      'RW',
      1
    ),
    (
      'safecover-rwanda',
      'Team Health Bundle',
      'Outpatient and inpatient options for small teams',
      '🏥',
      'insurance',
      '[{"label":"Network","value":"Nationwide clinics","icon":"🩺"},{"label":"Family Add-ons","value":"Available","icon":"👨‍👩‍👧‍👦"},{"label":"Claims","value":"Digital submission","icon":"📱"}]',
      'Talk to an Advisor',
      'whatsapp',
      'RW',
      2
    ),
    (
      'prisma',
      'Accounting',
      'Bookkeeping, financial statements, payroll',
      '📒',
      'service',
      '[{"label":"Deliverable","value":"Monthly books","icon":"📚"},{"label":"Payroll","value":"Integrated","icon":"💼"},{"label":"Reporting","value":"Board-ready packs","icon":"📊"}]',
      'Chat about this service',
      'whatsapp',
      'RW',
      0
    ),
    (
      'prisma',
      'Tax',
      'RRA compliance, VAT, income tax, tax planning',
      '🧾',
      'service',
      '[{"label":"Filings","value":"VAT + PAYE","icon":"🗂️"},{"label":"Planning","value":"Quarterly reviews","icon":"📅"},{"label":"Support","value":"Audit defense","icon":"🛡️"}]',
      'Chat about this service',
      'whatsapp',
      'RW',
      1
    ),
    (
      'prisma',
      'Audit',
      'Statutory audit, internal audit, due diligence',
      '🔍',
      'service',
      '[{"label":"Scope","value":"Statutory + internal","icon":"📘"},{"label":"Readout","value":"Management letter","icon":"📝"},{"label":"Timeline","value":"4-6 weeks","icon":"⏳"}]',
      'Chat about this service',
      'whatsapp',
      'RW',
      2
    ),
    (
      'prisma',
      'Legal',
      'Corporate law, contracts, regulatory compliance',
      '⚖️',
      'service',
      '[{"label":"Contracts","value":"Drafting + review","icon":"📄"},{"label":"Company Secretarial","value":"Included","icon":"🏢"},{"label":"Compliance","value":"Regulatory filings","icon":"✅"}]',
      'Chat about this service',
      'whatsapp',
      'RW',
      3
    ),
    (
      'prisma',
      'Advisory',
      'Business strategy, M&A, restructuring',
      '💡',
      'service',
      '[{"label":"Board Advisory","value":"Monthly","icon":"🧠"},{"label":"Fundraising Prep","value":"Investor-ready","icon":"💼"},{"label":"Restructuring","value":"Operating model support","icon":"🛠️"}]',
      'Chat about this service',
      'whatsapp',
      'RW',
      4
    ),
    (
      'inkingi-advisory',
      'Finance Ops Setup',
      'Design controls, approvals, and month-end workflows',
      '🧮',
      'service',
      '[{"label":"Close Pack","value":"5-day target","icon":"📅"},{"label":"Approvals","value":"Multi-level matrix","icon":"🔐"},{"label":"Tooling","value":"Spreadsheet + ERP ready","icon":"🧰"}]',
      'Book a Consultation',
      'whatsapp',
      'RW',
      0
    ),
    (
      'inkingi-advisory',
      'Board Reporting',
      'Monthly KPI packs and management dashboards',
      '📈',
      'service',
      '[{"label":"Pack","value":"Board + ops views","icon":"📊"},{"label":"Cadence","value":"Monthly","icon":"🗓️"},{"label":"Narrative","value":"CEO-ready summary","icon":"🗣️"}]',
      'Book a Consultation',
      'whatsapp',
      'RW',
      1
    ),
    (
      'inkingi-advisory',
      'Compliance Retainer',
      'Recurring support for filings, policy upkeep, and reviews',
      '🛡️',
      'service',
      '[{"label":"Policy Reviews","value":"Quarterly","icon":"📘"},{"label":"Filings","value":"Tracked centrally","icon":"🗂️"},{"label":"Escalations","value":"Same-week response","icon":"⚡"}]',
      'Talk to Advisory',
      'whatsapp',
      'RW',
      2
    )
),
updated_services as (
  update public.partner_services ps
  set
    subtitle = s.subtitle,
    emoji = s.emoji,
    category = s.category,
    details = s.details::jsonb,
    cta_label = s.cta_label,
    cta_action = s.cta_action,
    country = s.country,
    sort_order = s.sort_order,
    is_active = true,
    is_mock = true,
    mock_batch = 'partners_mock_seed_20260311',
    updated_at = now()
  from service_seed s
  join public.partners p
    on p.slug = s.partner_slug
  where ps.partner_id = p.id
    and ps.title = s.title
  returning ps.id
)
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
  is_active,
  is_mock,
  mock_batch
)
select
  p.id,
  s.title,
  s.subtitle,
  s.emoji,
  s.category,
  s.details::jsonb,
  s.cta_label,
  s.cta_action,
  s.country,
  s.sort_order,
  true,
  true,
  'partners_mock_seed_20260311'
from service_seed s
join public.partners p
  on p.slug = s.partner_slug
where not exists (
  select 1
  from public.partner_services ps
  where ps.partner_id = p.id
    and ps.title = s.title
);
