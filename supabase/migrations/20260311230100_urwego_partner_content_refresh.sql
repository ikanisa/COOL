-- Refresh Urwego Finance partner content using official products, channels,
-- support, and locations published on urwegofinance.com.

with urwego_partner as (
  select id
  from public.partners
  where slug = 'urwego'
)
update public.partners
set
  subtitle = 'Digital banking, savings, group, SME, and agricultural finance',
  description = 'Urwego Finance CBC offers current and savings accounts, group lending, SME credit, agricultural finance, mobile and internet banking, transfers, and remittance services in Rwanda.',
  whatsapp_number = '+250785083323',
  fan_count = 0,
  club_count = 0,
  game_count = 0,
  updated_at = now()
where id in (select id from urwego_partner);
delete from public.partner_services
where partner_id in (
  select id
  from public.partners
  where slug = 'urwego'
);
with urwego_partner as (
  select id
  from public.partners
  where slug = 'urwego'
),
service_seed (
  title,
  subtitle,
  emoji,
  category,
  details,
  cta_label,
  cta_action,
  sort_order
) as (
  values
    (
      'mHose Mobile Banking',
      'Self-register, access account services, and transact through the official *501# channel and mHose agents.',
      '📱',
      'digital',
      $$[
        {"label":"Channel","value":"*501# + mHose agents","icon":"📲"},
        {"label":"Includes","value":"cash-in, cash-out, bill payments, transfers, account info","icon":"💸"},
        {"label":"Linked rails","value":"MTN MoMo and Airtel Money","icon":"🔗"}
      ]$$::jsonb,
      'Dial *501#',
      'ussd:*501#',
      0
    ),
    (
      'Internet Banking',
      'Online banking for corporate clients, MSMEs, and individual consumers.',
      '💻',
      'digital',
      $$[
        {"label":"Users","value":"corporates, MSMEs, individual consumers","icon":"👥"},
        {"label":"Do online","value":"bill payment, bulk transfer, statements, standing orders","icon":"🧾"},
        {"label":"Manage","value":"account activity, cheque book requests, transfer history","icon":"📊"}
      ]$$::jsonb,
      'Open Internet Banking',
      'web:https://internetbanking.urwegofinance.com/',
      1
    ),
    (
      'Money Transfers & Remittances',
      'Local transfers, RIPPS, SWIFT, and international remittance services.',
      '🌍',
      'payments',
      $$[
        {"label":"Local","value":"internal transfer and RIPPS","icon":"🏦"},
        {"label":"International","value":"SWIFT inward and outward transfers","icon":"✈️"},
        {"label":"Remittance partners","value":"Western Union, Ria, MoneyGram","icon":"💵"}
      ]$$::jsonb,
      'View official service page',
      'web:https://www.urwegofinance.com/productsandservices/',
      2
    ),
    (
      'IKAZE Current Account',
      'Current account for individuals, companies, NGOs, cooperatives, churches, and associations.',
      '🏦',
      'current_account',
      $$[
        {"label":"Currencies","value":"RWF, USD, EUR","icon":"💱"},
        {"label":"Opening balance","value":"No minimum","icon":"✨"},
        {"label":"Use it for","value":"deposits, withdrawals, transfers, cheque-book access","icon":"🧾"}
      ]$$::jsonb,
      'Contact Urwego',
      'whatsapp',
      3
    ),
    (
      'GWIZA Savings Account',
      'Flexible savings product with no minimum balance and interest up to 5% per year.',
      '💰',
      'savings',
      $$[
        {"label":"Minimum balance","value":"None","icon":"🪙"},
        {"label":"Interest","value":"Up to 5% p.a.","icon":"📈"},
        {"label":"Charges","value":"No monthly maintenance charge","icon":"✅"}
      ]$$::jsonb,
      'Ask about GWIZA',
      'whatsapp',
      4
    ),
    (
      'NZIGAMIRA Savings Account',
      'Children''s savings product with an opening deposit and interest up to 8% per year.',
      '🧒',
      'savings',
      $$[
        {"label":"Opening deposit","value":"5,000 RWF","icon":"💵"},
        {"label":"Interest","value":"Up to 8% p.a.","icon":"📈"},
        {"label":"Use case","value":"children''s school and future savings goals","icon":"🎓"}
      ]$$::jsonb,
      'Ask about NZIGAMIRA',
      'whatsapp',
      5
    ),
    (
      'TUZA Savings Account',
      'Term savings from 2 to 12 months with tiered returns.',
      '🪺',
      'savings',
      $$[
        {"label":"Term","value":"2 to 12 months","icon":"🗓️"},
        {"label":"Minimum amount","value":"20,000 RWF","icon":"💵"},
        {"label":"Interest band","value":"3.2% to 6% p.a.","icon":"📈"}
      ]$$::jsonb,
      'Ask about TUZA',
      'whatsapp',
      6
    ),
    (
      'TEGANYA Group Current Account',
      'Current account tailored to beneficiaries of Urwego group-loan products.',
      '👥',
      'group_account',
      $$[
        {"label":"Currency","value":"RWF","icon":"💱"},
        {"label":"Opening balance","value":"No minimum","icon":"✨"},
        {"label":"Supports","value":"cash deposits, cheque deposits, withdrawals, transfers","icon":"📋"}
      ]$$::jsonb,
      'Talk to Urwego',
      'whatsapp',
      7
    ),
    (
      'Traditional Community Banking (TCB)',
      'Group-loan product for organized solidarity groups under the TCB model.',
      '🤝',
      'group_loan',
      $$[
        {"label":"Group size","value":"15 to 60 members","icon":"👥"},
        {"label":"Loan size","value":"30,000 to 1,200,000 RWF per member","icon":"💰"},
        {"label":"Repayment","value":"weekly or bi-weekly over 4 to 6 months","icon":"🗓️"}
      ]$$::jsonb,
      'Discuss group eligibility',
      'whatsapp',
      8
    ),
    (
      'ZAMUKA Group Loan',
      'Group loan designed for women-led solidarity groups with limited prior credit access.',
      '🌱',
      'group_loan',
      $$[
        {"label":"Group size","value":"15 to 30 women","icon":"👭"},
        {"label":"Loan size","value":"10,000 to 50,000 RWF per member","icon":"💰"},
        {"label":"Repayment","value":"weekly over 4 to 6 months","icon":"🗓️"}
      ]$$::jsonb,
      'Talk to Urwego',
      'whatsapp',
      9
    ),
    (
      'Village Savings Group Loan',
      'External finance for village savings groups with prior savings history.',
      '🏘️',
      'group_loan',
      $$[
        {"label":"Group size","value":"15 to 30 members","icon":"👥"},
        {"label":"Loan size","value":"100,000 to 300,000 RWF per member","icon":"💰"},
        {"label":"Prerequisite","value":"3 to 6 months savings history and 20% equity","icon":"📚"}
      ]$$::jsonb,
      'Ask about VSLA finance',
      'whatsapp',
      10
    ),
    (
      'SME Working Capital Loan',
      'Working-capital facility for existing small and medium businesses.',
      '🏪',
      'business_loan',
      $$[
        {"label":"Minimum amount","value":"1,000,000 RWF","icon":"💵"},
        {"label":"Term","value":"12 to 36 months","icon":"🗓️"},
        {"label":"Requirements","value":"1+ year in business and 20% equity","icon":"📌"}
      ]$$::jsonb,
      'Ask about SME working capital',
      'whatsapp',
      11
    ),
    (
      'SME Asset Loan',
      'Asset-finance facility for equipment, expansion, or related business investment.',
      '🏗️',
      'business_loan',
      $$[
        {"label":"Minimum amount","value":"1,000,000 RWF","icon":"💵"},
        {"label":"Term","value":"12 to 48 months","icon":"🗓️"},
        {"label":"Requirements","value":"1+ year in business, 20% equity, collateral","icon":"📌"}
      ]$$::jsonb,
      'Ask about SME asset finance',
      'whatsapp',
      12
    ),
    (
      'Agricultural Finance',
      'Seasonal and value-chain finance across coffee, maize, rice, and Irish potato products.',
      '🚜',
      'agri',
      $$[
        {"label":"Crops","value":"coffee, maize, rice, Irish potato","icon":"🌾"},
        {"label":"Models","value":"group-based and selected individual farmer loans","icon":"👩🏾‍🌾"},
        {"label":"Use","value":"input financing and production-cycle support","icon":"📦"}
      ]$$::jsonb,
      'Find a branch or agent',
      'web:https://www.urwegofinance.com/our-locations/',
      13
    ),
    (
      'Support & Locations',
      'Official channels for onboarding, service questions, and finding the nearest branch or mHose agent.',
      '☎️',
      'support',
      $$[
        {"label":"Phone","value":"5151 / +250 788 173 100","icon":"📞"},
        {"label":"WhatsApp","value":"+250 785 083 323","icon":"💬"},
        {"label":"Email","value":"info@urwegofinance.com","icon":"✉️"},
        {"label":"Head office","value":"CHIC Building, Kicukiro, Kigali","icon":"📍"}
      ]$$::jsonb,
      'View locations',
      'web:https://www.urwegofinance.com/our-locations/',
      14
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
  sort_order
)
select
  urwego_partner.id,
  service_seed.title,
  service_seed.subtitle,
  service_seed.emoji,
  service_seed.category,
  service_seed.details,
  service_seed.cta_label,
  service_seed.cta_action,
  service_seed.sort_order
from urwego_partner
cross join service_seed;
