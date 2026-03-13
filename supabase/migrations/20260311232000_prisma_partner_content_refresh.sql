-- Refresh PRISMA partner content using official IKANISA website content.
-- The app partner slug remains "prisma", while the content is sourced from
-- ikanisa.com per product requirements.

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
  fan_count = 9,
  club_count = 28000,
  game_count = 14,
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
