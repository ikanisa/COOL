-- Add Equity Bank Rwanda as a second banking partner and seed official
-- product, channel, and support content from equitygroupholdings.com/rw.

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
  sort_order
)
values (
  'Equity Bank Rwanda',
  'equity',
  'bank',
  'RW',
  '🏦',
  'Accounts, digital banking, payments, savings, and borrowing',
  'Equity Bank Rwanda offers personal, SME, corporate, group, and diaspora banking, alongside digital channels, payments, savings, and borrowing services in Rwanda.',
  null,
  0,
  0,
  0,
  true,
  5
)
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
  updated_at = now();

delete from public.partner_services
where partner_id in (
  select id
  from public.partners
  where slug = 'equity'
);

with equity_partner as (
  select id
  from public.partners
  where slug = 'equity'
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
      'Equity Mobile App',
      'Official mobile banking channel listed on Equity Rwanda''s home page.',
      '📱',
      'digital',
      $$[
        {"label":"Channel","value":"Official Equity Mobile App","icon":"📲"},
        {"label":"Published with","value":"Equity Online Banking and Eazzy Biz","icon":"🔗"},
        {"label":"Use case","value":"Access your bank account from home or office","icon":"🏠"}
      ]$$::jsonb,
      'Open Equity Rwanda',
      'web:https://equitygroupholdings.com/rw/home/',
      0
    ),
    (
      'Equity Online, Eazzy Biz & EazzyFX',
      'Digital banking and business-payment rails highlighted by Equity Rwanda.',
      '💻',
      'digital',
      $$[
        {"label":"Digital family","value":"Equity Online Banking, Eazzy Biz, EazzyFX","icon":"🧩"},
        {"label":"Audience","value":"Individual and business banking users","icon":"👥"},
        {"label":"Positioning","value":"Self-service banking and payments from the official Rwanda site","icon":"✅"}
      ]$$::jsonb,
      'View digital banking',
      'web:https://equitygroupholdings.com/rw/home/',
      1
    ),
    (
      'Pay & Send Money',
      'Official payments page covering transfers and self-service transaction channels.',
      '💸',
      'payments',
      $$[
        {"label":"Includes","value":"Agency, cardless withdrawal, cards, EazzyPay, EazzyFX","icon":"📤"},
        {"label":"Transfers","value":"Local and international transfer services","icon":"🌍"},
        {"label":"Use case","value":"Move money and make payments conveniently","icon":"⚡"}
      ]$$::jsonb,
      'Open payments page',
      'web:https://equitygroupholdings.com/rw/pay-and-send-money/',
      2
    ),
    (
      'Open an Account',
      'Official account-opening surface for multiple customer segments.',
      '🏦',
      'current_account',
      $$[
        {"label":"Personal","value":"Individual account opening options","icon":"🧑"},
        {"label":"Business","value":"SME and corporate banking entry points","icon":"🏢"},
        {"label":"Also listed","value":"Chama & youth groups plus diaspora banking","icon":"🌍"}
      ]$$::jsonb,
      'Open account options',
      'web:https://equitygroupholdings.com/rw/open-an-account/',
      3
    ),
    (
      'Group, Youth & Diaspora Banking',
      'Community and diaspora banking paths published under Equity Rwanda account opening.',
      '👥',
      'group_account',
      $$[
        {"label":"Community","value":"Chama and youth-group banking options","icon":"🤝"},
        {"label":"Diaspora","value":"Dedicated diaspora banking pathway","icon":"✈️"},
        {"label":"Source","value":"Official Rwanda account-opening page","icon":"📄"}
      ]$$::jsonb,
      'View account categories',
      'web:https://equitygroupholdings.com/rw/open-an-account/',
      4
    ),
    (
      'Save & Invest',
      'Official savings catalogue highlighted by Equity Rwanda.',
      '💰',
      'savings',
      $$[
        {"label":"Products listed","value":"Super Junior, Call & Fixed Deposit, Impamba","icon":"📚"},
        {"label":"Use case","value":"Personal, goal-based, and deposit savings options","icon":"🎯"},
        {"label":"Source","value":"Official Save & Invest page","icon":"✅"}
      ]$$::jsonb,
      'Open savings page',
      'web:https://equitygroupholdings.com/rw/save-and-invest/',
      5
    ),
    (
      'Borrow',
      'Official borrowing surface for personal, SME, and diaspora customers.',
      '📈',
      'business_loan',
      $$[
        {"label":"Products listed","value":"Personal loans, asset finance, mortgage, biashara","icon":"💳"},
        {"label":"Diaspora","value":"Diaspora mortgages are explicitly listed","icon":"🏠"},
        {"label":"Source","value":"Official Borrow page","icon":"📄"}
      ]$$::jsonb,
      'Open borrowing page',
      'web:https://equitygroupholdings.com/rw/borrow/',
      6
    ),
    (
      'Talk to Us & Service Hours',
      'Official support channels published by Equity Bank Rwanda.',
      '☎️',
      'support',
      $$[
        {"label":"Customer care","value":"4555 / +250 737 360 000","icon":"📞"},
        {"label":"Email","value":"talktous@equitybank.co.rw","icon":"✉️"},
        {"label":"Hours","value":"Weekdays 8:00-18:00 · Weekends 9:00-13:00","icon":"🕒"}
      ]$$::jsonb,
      'Open contact page',
      'web:https://equitygroupholdings.com/rw/talk-to-us/',
      7
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
  equity_partner.id,
  service_seed.title,
  service_seed.subtitle,
  service_seed.emoji,
  service_seed.category,
  service_seed.details,
  service_seed.cta_label,
  service_seed.cta_action,
  service_seed.sort_order
from equity_partner
cross join service_seed;
