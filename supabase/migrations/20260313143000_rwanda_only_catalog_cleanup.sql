-- Rwanda-only catalog cleanup for admin-managed content and partner surfaces.
-- This removes legacy multi-market config and normalizes remaining catalog rows
-- to the fixed Rwanda market contract.

delete from public.app_config
where key ~ '^feature_.*_allowed_[a-z_]+$';

delete from public.app_config
where country is not null
  and upper(btrim(country)) <> 'RW';

with non_rw_partners as (
  select id
  from public.partners
  where coalesce(nullif(upper(btrim(country)), ''), 'RW') <> 'RW'
)
delete from public.partner_payment_routes
where partner_id in (select id from non_rw_partners);

with non_rw_partners as (
  select id
  from public.partners
  where coalesce(nullif(upper(btrim(country)), ''), 'RW') <> 'RW'
)
delete from public.partner_services
where partner_id in (select id from non_rw_partners);

delete from public.partner_payment_routes
where country is not null
  and upper(btrim(country)) <> 'RW';

delete from public.partner_services
where country is not null
  and upper(btrim(country)) <> 'RW';

delete from public.partners
where coalesce(nullif(upper(btrim(country)), ''), 'RW') <> 'RW';

update public.partners
set country = 'RW'
where country is null or btrim(country) = '';

update public.partner_services
set country = 'RW'
where country is null or btrim(country) = '';

update public.partner_payment_routes
set country = 'RW'
where country is null or btrim(country) = '';

delete from public.quick_actions
where country is not null
  and upper(btrim(country)) <> 'RW';

update public.quick_actions
set country = 'RW'
where country is null or btrim(country) = '';

delete from public.vehicle_types
where country is not null
  and upper(btrim(country)) <> 'RW';

update public.vehicle_types
set country = 'RW'
where country is null or btrim(country) = '';

update public.partners
set description =
      'Urwego Finance CBC offers current and savings accounts, group lending, SME credit, agricultural finance, mobile and internet banking, transfers, and payment services in Rwanda.',
    updated_at = now()
where slug = 'urwego';

with urwego_partner as (
  select id
  from public.partners
  where slug = 'urwego'
)
update public.partner_services
set title = 'Money Transfers & Payments',
    subtitle = 'Rwanda transfers, RIPPS, and official payment services.',
    details = $$[
      {"label":"Transfers","value":"Internal transfer and RIPPS","icon":"🏦"},
      {"label":"Payments","value":"Official bank payment services in Rwanda","icon":"💸"},
      {"label":"Channel","value":"Use the official Urwego service page","icon":"📄"}
    ]$$::jsonb,
    updated_at = now()
where partner_id in (select id from urwego_partner)
  and title = 'Money Transfers & Remittances';

update public.partners
set description =
      'Equity Bank Rwanda offers personal, SME, corporate, and community banking, alongside digital channels, payments, savings, and borrowing services in Rwanda.',
    updated_at = now()
where slug = 'equity';

with equity_partner as (
  select id
  from public.partners
  where slug = 'equity'
)
update public.partner_services
set details = $$[
      {"label":"Includes","value":"Agency, cardless withdrawal, cards, EazzyPay, EazzyFX","icon":"📤"},
      {"label":"Transfers","value":"Rwanda transfer and payment services","icon":"💸"},
      {"label":"Use case","value":"Move money and make payments conveniently","icon":"⚡"}
    ]$$::jsonb,
    updated_at = now()
where partner_id in (select id from equity_partner)
  and title = 'Pay & Send Money';

with equity_partner as (
  select id
  from public.partners
  where slug = 'equity'
)
update public.partner_services
set details = $$[
      {"label":"Personal","value":"Individual account opening options","icon":"🧑"},
      {"label":"Business","value":"SME and corporate banking entry points","icon":"🏢"},
      {"label":"Community","value":"Group and youth banking options in Rwanda","icon":"🤝"}
    ]$$::jsonb,
    updated_at = now()
where partner_id in (select id from equity_partner)
  and title = 'Open an Account';

with equity_partner as (
  select id
  from public.partners
  where slug = 'equity'
)
update public.partner_services
set title = 'Group & Youth Banking',
    subtitle = 'Community and youth banking paths published by Equity Rwanda.',
    details = $$[
      {"label":"Community","value":"Chama and youth-group banking options","icon":"🤝"},
      {"label":"Audience","value":"Community groups served in Rwanda","icon":"👥"},
      {"label":"Source","value":"Official Rwanda account-opening page","icon":"📄"}
    ]$$::jsonb,
    updated_at = now()
where partner_id in (select id from equity_partner)
  and title = 'Group, Youth & Diaspora Banking';

with equity_partner as (
  select id
  from public.partners
  where slug = 'equity'
)
update public.partner_services
set subtitle = 'Official borrowing surface for personal and SME customers.',
    details = $$[
      {"label":"Products listed","value":"Personal loans, asset finance, mortgage, biashara","icon":"💳"},
      {"label":"Audience","value":"Personal and business customers in Rwanda","icon":"🏠"},
      {"label":"Source","value":"Official Borrow page","icon":"📄"}
    ]$$::jsonb,
    updated_at = now()
where partner_id in (select id from equity_partner)
  and title = 'Borrow';
