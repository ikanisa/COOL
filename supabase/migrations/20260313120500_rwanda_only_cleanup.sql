-- Rwanda-only cleanup for databases that were already seeded before the
-- product was locked to Rwanda.

delete from public.supported_countries
where iso_code != 'RW';

-- Disable triggers that validate MoMo fields against the user's country,
-- because non-RW users may have phone numbers that don't match RW patterns.
-- Users can login/OTP with any international phone number; MoMo fields are
-- Rwanda-specific and get cleared for users whose numbers aren't valid for RW.
alter table public.users disable trigger trg_enforce_user_momo_fields;

update public.users
set
  country = 'RW',
  -- Clear MoMo fields that aren't valid for Rwanda
  momo_number = case
    when momo_number is not null
      and public.is_valid_momo_phone_for_country('RW', momo_number) then momo_number
    else null
  end,
  momo_code = case
    when momo_code is not null
      and public.is_valid_momo_code_for_country('RW', momo_code) then momo_code
    else null
  end,
  momo_route_type = case
    when momo_number is not null
      and public.is_valid_momo_phone_for_country('RW', momo_number) then momo_route_type
    when momo_code is not null
      and public.is_valid_momo_code_for_country('RW', momo_code) then momo_route_type
    else null
  end
where country is not null
  and country != 'RW';

alter table public.users enable trigger trg_enforce_user_momo_fields;

-- Same pattern for groups
alter table public.groups disable trigger trg_enforce_group_momo_fields;

update public.groups
set country = 'RW'
where country is not null
  and country != 'RW';

alter table public.groups enable trigger trg_enforce_group_momo_fields;

update public.partners
set country = 'RW'
where country is not null
  and country != 'RW';

with prisma_partner as (
  select id
  from public.partners
  where slug = 'prisma'
)
update public.partners
set
  subtitle = 'IKANISA AI professional services · Rwanda',
  description = 'AI-powered professional services across legal, tax, accounting, audit, insurance, corporate, NGO, and marketplace operations in Rwanda.',
  whatsapp_number = '+250795588248',
  updated_at = now()
where id in (select id from prisma_partner);

delete from public.partner_services
where partner_id in (
  select id
  from public.partners
  where slug = 'prisma'
);

with prisma_partner as (
  select id
  from public.partners
  where slug = 'prisma'
),
service_seed (
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
      'Chantal',
      'Private Notary & Advocate',
      '⚖️',
      'rwanda_agent',
      $$[
        {"label":"Jurisdiction","value":"Rwanda","icon":"🇷🇼"},
        {"label":"Grounded in","value":"9,000+ indexed Rwanda legal documents","icon":"📚"},
        {"label":"Covers","value":"contracts, litigation, notarial services, compliance, advisory","icon":"📝"}
      ]$$::jsonb,
      'Open Chantal',
      'web:https://chantal.ikanisa.com',
      'RW',
      0
    ),
    (
      'Emmanuel',
      'Rwanda Tax Partner',
      '🧾',
      'rwanda_agent',
      $$[
        {"label":"Jurisdiction","value":"Rwanda / RRA","icon":"🇷🇼"},
        {"label":"Tax stack","value":"CIT, PIT, VAT, PAYE, WHT, EFRIS","icon":"📊"},
        {"label":"Covers","value":"compliance, audit defense, objections, appeals, tax research","icon":"✅"}
      ]$$::jsonb,
      'Open Emmanuel',
      'web:https://emmanuel.ikanisa.com',
      'RW',
      1
    ),
    (
      'MEAL',
      'M&E, Accountability & Learning',
      '📈',
      'rwanda_agent',
      $$[
        {"label":"Jurisdiction","value":"Rwanda NGO and development context","icon":"🇷🇼"},
        {"label":"Tools","value":"KoboToolbox, ODK Central, DHIS2","icon":"🧰"},
        {"label":"Covers","value":"logframes, donor reporting, accountability systems, evaluation design","icon":"🧭"}
      ]$$::jsonb,
      'Open MEAL',
      'web:https://meal.ikanisa.com',
      'RW',
      2
    ),
    (
      'SAKA',
      'AI Marketplace Broker',
      '🛍️',
      'rwanda_agent',
      $$[
        {"label":"Jurisdiction","value":"Kigali, Rwanda","icon":"📍"},
        {"label":"Model","value":"WhatsApp-first marketplace concierge","icon":"💬"},
        {"label":"Covers","value":"vendor verification, stock checks, price confirmation, buyer-seller matching","icon":"🔎"}
      ]$$::jsonb,
      'Open SAKA',
      'web:https://saka.ikanisa.com',
      'RW',
      3
    ),
    (
      'Claire',
      'Rwanda Corporate Services Partner',
      '🏛️',
      'rwanda_agent',
      $$[
        {"label":"Jurisdiction","value":"Rwanda","icon":"🇷🇼"},
        {"label":"Grounded in","value":"Rwanda company law and governance practice","icon":"📚"},
        {"label":"Covers","value":"company formation, annual filings, governance, KYC/AML coordination","icon":"📄"}
      ]$$::jsonb,
      'Open Claire',
      'web:https://claire.ikanisa.com',
      'RW',
      4
    ),
    (
      'Matthew',
      'Rwanda Finance Controller',
      '📒',
      'rwanda_agent',
      $$[
        {"label":"Jurisdiction","value":"Rwanda","icon":"🇷🇼"},
        {"label":"Frameworks","value":"IFRS, IFRS for SMEs, GAPSME","icon":"📚"},
        {"label":"Covers","value":"bookkeeping, payroll, treasury, close management, statutory financial statements","icon":"📑"}
      ]$$::jsonb,
      'Open Matthew',
      'web:https://matthew.ikanisa.com',
      'RW',
      5
    ),
    (
      'Emma',
      'Insurance & Regulatory Partner',
      '🛡️',
      'rwanda_agent',
      $$[
        {"label":"Jurisdiction","value":"Rwanda","icon":"🇷🇼"},
        {"label":"Grounded in","value":"Rwanda insurance, compliance, governance, and risk practice","icon":"📚"},
        {"label":"Covers","value":"insurance regulation, prudential reporting, policy drafting, governance review","icon":"🔐"}
      ]$$::jsonb,
      'Open Emma',
      'web:https://emma.ikanisa.com',
      'RW',
      6
    ),
    (
      'Sofia',
      'Rwanda Audit & Assurance Partner',
      '🔍',
      'rwanda_agent',
      $$[
        {"label":"Jurisdiction","value":"Rwanda","icon":"🇷🇼"},
        {"label":"Grounded in","value":"ISA audit, internal audit, AML/CFT, quality control","icon":"📚"},
        {"label":"Covers","value":"external audit, internal audit, risk reviews, controls testing, evidence packs","icon":"🧮"}
      ]$$::jsonb,
      'Open Sofia',
      'web:https://sofia.ikanisa.com',
      'RW',
      7
    ),
    (
      'Patrick',
      'Rwanda Internal Controls Partner',
      '✅',
      'rwanda_agent',
      $$[
        {"label":"Jurisdiction","value":"Rwanda","icon":"🇷🇼"},
        {"label":"Grounded in","value":"internal controls, SOP design, audit readiness, compliance operations","icon":"📚"},
        {"label":"Scale","value":"14 sectors and 9,500+ audit and controls documents referenced on the official site","icon":"📊"}
      ]$$::jsonb,
      'Open Patrick',
      'web:https://patrick.ikanisa.com',
      'RW',
      8
    ),
    (
      'Legal & Regulatory Coverage',
      'Jurisdiction-locked legal and regulatory services for Rwanda.',
      '⚖️',
      'capability',
      $$[
        {"label":"Includes","value":"contract drafting, litigation support, notarial services, compliance advisory","icon":"📝"},
        {"label":"Rwanda legal focus","value":"private notary, judicial procedures, regulatory frameworks","icon":"🇷🇼"},
        {"label":"Source","value":"official IKANISA services and Chantal agent coverage","icon":"✅"}
      ]$$::jsonb,
      'View service coverage',
      'web:https://ikanisa.com/#services',
      'RW',
      9
    ),
    (
      'Tax, Finance & Accounting',
      'End-to-end tax intelligence and finance operations for Rwanda organizations.',
      '🧮',
      'capability',
      $$[
        {"label":"Tax","value":"RRA compliance, audit defence, disputes, planning","icon":"🧾"},
        {"label":"Finance","value":"bookkeeping, AP/AR, payroll, treasury, period close","icon":"📒"},
        {"label":"Reporting","value":"IFRS, IFRS for SMEs, GAPSME financial statement packs","icon":"📊"}
      ]$$::jsonb,
      'Browse capabilities',
      'web:https://ikanisa.com/#services',
      'RW',
      10
    ),
    (
      'Audit, Risk & Assurance',
      'External audit, internal audit, AML/CFT, and evidence-ready assurance workflows.',
      '✅',
      'capability',
      $$[
        {"label":"Audit","value":"ISA external audit and internal audit across multiple sectors","icon":"🔍"},
        {"label":"Risk","value":"AML/CFT, controls testing, fraud response, evidence gating","icon":"🔐"},
        {"label":"Insurance","value":"Rwanda insurance governance, reporting, and policy review","icon":"🛡️"}
      ]$$::jsonb,
      'Browse capabilities',
      'web:https://ikanisa.com/#services',
      'RW',
      11
    ),
    (
      'Corporate, NGO & Marketplace Ops',
      'Company operations, donor reporting, and marketplace execution support for Rwanda teams.',
      '🌐',
      'capability',
      $$[
        {"label":"Corporate","value":"formation, statutory records, governance, compliance calendars","icon":"🏢"},
        {"label":"NGO","value":"donor reporting, data pipelines, theory of change, grant intelligence","icon":"📈"},
        {"label":"Marketplace","value":"vendor verification, stock and price checks, WhatsApp-first handoff","icon":"🛍️"}
      ]$$::jsonb,
      'Browse capabilities',
      'web:https://ikanisa.com/#services',
      'RW',
      12
    ),
    (
      'Support & Onboarding',
      'Official contact channels published on ikanisa.com.',
      '☎️',
      'support',
      $$[
        {"label":"Rwanda desk","value":"+250 795 588 248","icon":"🇷🇼"},
        {"label":"Email","value":"info@ikanisa.com","icon":"✉️"},
        {"label":"Coverage","value":"Kigali, Rwanda","icon":"📍"}
      ]$$::jsonb,
      'Email IKANISA',
      'mailto:info@ikanisa.com',
      'RW',
      13
    )
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
  sort_order
)
select
  prisma_partner.id,
  service_seed.title,
  service_seed.subtitle,
  service_seed.emoji,
  service_seed.category,
  service_seed.details,
  service_seed.cta_label,
  service_seed.cta_action,
  service_seed.country,
  service_seed.sort_order
from prisma_partner
cross join service_seed;

update public.partners
set description = 'Urwego Finance CBC offers current and savings accounts, group lending, SME credit, agricultural finance, mobile and internet banking, and local payment services in Rwanda.'
where slug = 'urwego';

update public.partner_services
set
  title = 'Transfers & Payments',
  subtitle = 'Local transfers and Rwanda payment services.',
  details = $$[
    {"label":"Local","value":"internal transfer and RIPPS","icon":"🏦"},
    {"label":"Payments","value":"cash-in, cash-out, bill payments, account-to-account transfers","icon":"💸"},
    {"label":"Use case","value":"day-to-day local movement of money in Rwanda","icon":"📍"}
  ]$$::jsonb
where title = 'Money Transfers & Remittances'
  and partner_id in (select id from public.partners where slug = 'urwego');

update public.partner_services
set details = $$[
  {"label":"Currency","value":"RWF","icon":"💱"},
  {"label":"Opening balance","value":"No minimum","icon":"✨"},
  {"label":"Use it for","value":"deposits, withdrawals, transfers, cheque-book access","icon":"🧾"}
]$$::jsonb
where title = 'IKAZE Current Account'
  and partner_id in (select id from public.partners where slug = 'urwego');

update public.partners
set description = 'Equity Bank Rwanda offers personal, SME, corporate, and group banking, alongside digital channels, payments, savings, and borrowing services in Rwanda.'
where slug = 'equity';

update public.partner_services
set details = $$[
  {"label":"Includes","value":"Agency, cardless withdrawal, cards, EazzyPay, EazzyFX","icon":"📤"},
  {"label":"Transfers","value":"Local transfer and self-service payment services","icon":"📍"},
  {"label":"Use case","value":"Move money and make payments conveniently","icon":"⚡"}
]$$::jsonb
where title = 'Pay & Send Money'
  and partner_id in (select id from public.partners where slug = 'equity');

update public.partner_services
set details = $$[
  {"label":"Personal","value":"Individual account opening options","icon":"🧑"},
  {"label":"Business","value":"SME and corporate banking entry points","icon":"🏢"},
  {"label":"Also listed","value":"Chama and youth-group banking options","icon":"🤝"}
]$$::jsonb
where title = 'Open an Account'
  and partner_id in (select id from public.partners where slug = 'equity');

update public.partner_services
set
  title = 'Group & Youth Banking',
  subtitle = 'Community and youth banking paths published under Equity Rwanda account opening.',
  details = $$[
    {"label":"Community","value":"Chama and youth-group banking options","icon":"🤝"},
    {"label":"Use case","value":"Shared group and youth savings workflows","icon":"📘"},
    {"label":"Source","value":"Official Rwanda account-opening page","icon":"📄"}
  ]$$::jsonb
where title = 'Group, Youth & Diaspora Banking'
  and partner_id in (select id from public.partners where slug = 'equity');

update public.partner_services
set
  subtitle = 'Official borrowing surface for personal and SME customers.',
  details = $$[
    {"label":"Products listed","value":"Personal loans, asset finance, mortgage, biashara","icon":"💳"},
    {"label":"Coverage","value":"Local borrowing options for Rwanda households and businesses","icon":"🏠"},
    {"label":"Source","value":"Official Borrow page","icon":"📄"}
  ]$$::jsonb
where title = 'Borrow'
  and partner_id in (select id from public.partners where slug = 'equity');
