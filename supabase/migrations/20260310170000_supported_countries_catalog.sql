-- ==========================================================================
-- Cool App — Supported countries catalog and country normalization
-- ==========================================================================

create table if not exists public.supported_countries (
  iso_code            text primary key,
  dial_code           text not null unique,
  country_name        text not null,
  flag_emoji          text not null,
  currency_code       text not null,
  currency_name       text not null,
  momo_provider_id    text not null,
  momo_ussd_template  text not null,
  is_active           boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
insert into public.supported_countries (
  iso_code,
  dial_code,
  country_name,
  flag_emoji,
  currency_code,
  currency_name,
  momo_provider_id,
  momo_ussd_template
)
values
  ('BJ', '+229', 'Benin', '🇧🇯', 'XOF', 'West African CFA franc', 'momo_bj', '*400*1*{recipient}*{amount}#'),
  ('BW', '+267', 'Botswana', '🇧🇼', 'BWP', 'Botswana pula', 'momo_bw', '*167*1*{recipient}*{amount}#'),
  ('CM', '+237', 'Cameroon', '🇨🇲', 'XAF', 'Central African CFA franc', 'momo_cm', '*126*1*{recipient}*{amount}#'),
  ('CG', '+242', 'Congo Brazzaville', '🇨🇬', 'XAF', 'Central African CFA franc', 'momo_cg', '*124*1*{recipient}*{amount}#'),
  ('CI', '+225', 'Cote d''Ivoire', '🇨🇮', 'XOF', 'West African CFA franc', 'momo_ci', '*133*1*{recipient}*{amount}#'),
  ('GH', '+233', 'Ghana', '🇬🇭', 'GHS', 'Ghanaian cedi', 'momo_gh', '*170*1*{recipient}*{amount}#'),
  ('GN', '+224', 'Guinea', '🇬🇳', 'GNF', 'Guinean franc', 'momo_gn', '*155*1*{recipient}*{amount}#'),
  ('GW', '+245', 'Guinea-Bissau', '🇬🇼', 'XOF', 'West African CFA franc', 'momo_gw', '*124*1*{recipient}*{amount}#'),
  ('KE', '+254', 'Kenya', '🇰🇪', 'KES', 'Kenyan shilling', 'momo_ke', '*334*1*{recipient}*{amount}#'),
  ('LR', '+231', 'Liberia', '🇱🇷', 'LRD', 'Liberian dollar', 'momo_lr', '*156*1*{recipient}*{amount}#'),
  ('MW', '+265', 'Malawi', '🇲🇼', 'MWK', 'Malawian kwacha', 'momo_mw', '*444*1*{recipient}*{amount}#'),
  ('MZ', '+258', 'Mozambique', '🇲🇿', 'MZN', 'Mozambican metical', 'momo_mz', '*197*1*{recipient}*{amount}#'),
  ('NG', '+234', 'Nigeria', '🇳🇬', 'NGN', 'Nigerian naira', 'momo_ng', '*223*1*{recipient}*{amount}#'),
  ('RW', '+250', 'Rwanda', '🇷🇼', 'RWF', 'Rwandan franc', 'momo_rw', '*182*1*1*{recipient}*{amount}#'),
  ('ZA', '+27', 'South Africa', '🇿🇦', 'ZAR', 'South African rand', 'momo_za', '*120*668*1*{recipient}*{amount}#'),
  ('SZ', '+268', 'Eswatini', '🇸🇿', 'SZL', 'Swazi lilangeni', 'momo_sz', '*468*1*{recipient}*{amount}#'),
  ('UG', '+256', 'Uganda', '🇺🇬', 'UGX', 'Ugandan shilling', 'momo_ug', '*165*1*{recipient}*{amount}#'),
  ('ZM', '+260', 'Zambia', '🇿🇲', 'ZMW', 'Zambian kwacha', 'momo_zm', '*303*1*{recipient}*{amount}#'),
  ('ZW', '+263', 'Zimbabwe', '🇿🇼', 'ZWL', 'Zimbabwean dollar', 'momo_zw', '*151*1*{recipient}*{amount}#'),
  ('CD', '+243', 'Democratic Republic of the Congo', '🇨🇩', 'CDF', 'Congolese franc', 'momo_cd', '*099*1*{recipient}*{amount}#'),
  ('ET', '+251', 'Ethiopia', '🇪🇹', 'ETB', 'Ethiopian birr', 'momo_et', '*806*1*{recipient}*{amount}#'),
  ('GA', '+241', 'Gabon', '🇬🇦', 'XAF', 'Central African CFA franc', 'momo_ga', '*222*1*{recipient}*{amount}#'),
  ('MG', '+261', 'Madagascar', '🇲🇬', 'MGA', 'Malagasy ariary', 'momo_mg', '*162*1*{recipient}*{amount}#'),
  ('SN', '+221', 'Senegal', '🇸🇳', 'XOF', 'West African CFA franc', 'momo_sn', '*140*1*{recipient}*{amount}#'),
  ('SL', '+232', 'Sierra Leone', '🇸🇱', 'SLL', 'Sierra Leonean leone', 'momo_sl', '*277*1*{recipient}*{amount}#'),
  ('TZ', '+255', 'Tanzania', '🇹🇿', 'TZS', 'Tanzanian shilling', 'momo_tz', '*150*00*1*{recipient}*{amount}#')
on conflict (iso_code) do update
set
  dial_code = excluded.dial_code,
  country_name = excluded.country_name,
  flag_emoji = excluded.flag_emoji,
  currency_code = excluded.currency_code,
  currency_name = excluded.currency_name,
  momo_provider_id = excluded.momo_provider_id,
  momo_ussd_template = excluded.momo_ussd_template,
  is_active = true,
  updated_at = now();
create or replace function public.normalize_country_code(raw_value text)
returns text
language sql
immutable
as $$
  select case lower(trim(coalesce(raw_value, '')))
    when '' then 'RW'
    when 'rw' then 'RW'
    when 'rwanda' then 'RW'
    when 'bj' then 'BJ'
    when 'benin' then 'BJ'
    when 'bw' then 'BW'
    when 'botswana' then 'BW'
    when 'cm' then 'CM'
    when 'cameroon' then 'CM'
    when 'cg' then 'CG'
    when 'congo brazzaville' then 'CG'
    when 'republic of congo' then 'CG'
    when 'republic of the congo' then 'CG'
    when 'congo' then 'CG'
    when 'ci' then 'CI'
    when 'cote d''ivoire' then 'CI'
    when 'côte d''ivoire' then 'CI'
    when 'ivory coast' then 'CI'
    when 'gh' then 'GH'
    when 'ghana' then 'GH'
    when 'gn' then 'GN'
    when 'guinea' then 'GN'
    when 'gw' then 'GW'
    when 'guinea-bissau' then 'GW'
    when 'guinea bissau' then 'GW'
    when 'ke' then 'KE'
    when 'kenya' then 'KE'
    when 'lr' then 'LR'
    when 'liberia' then 'LR'
    when 'mw' then 'MW'
    when 'malawi' then 'MW'
    when 'mz' then 'MZ'
    when 'mozambique' then 'MZ'
    when 'ng' then 'NG'
    when 'nigeria' then 'NG'
    when 'za' then 'ZA'
    when 'south africa' then 'ZA'
    when 'sz' then 'SZ'
    when 'eswatini' then 'SZ'
    when 'swaziland' then 'SZ'
    when 'eswatini (swaziland)' then 'SZ'
    when 'ug' then 'UG'
    when 'uganda' then 'UG'
    when 'zm' then 'ZM'
    when 'zambia' then 'ZM'
    when 'zw' then 'ZW'
    when 'zimbabwe' then 'ZW'
    when 'cd' then 'CD'
    when 'drc' then 'CD'
    when 'democratic republic of congo' then 'CD'
    when 'democratic republic of the congo' then 'CD'
    when 'democratic republic of congo (drc)' then 'CD'
    when 'congo kinshasa' then 'CD'
    when 'et' then 'ET'
    when 'ethiopia' then 'ET'
    when 'ga' then 'GA'
    when 'gabon' then 'GA'
    when 'mg' then 'MG'
    when 'madagascar' then 'MG'
    when 'sn' then 'SN'
    when 'senegal' then 'SN'
    when 'sl' then 'SL'
    when 'sierra leone' then 'SL'
    when 'tz' then 'TZ'
    when 'tanzania' then 'TZ'
    else upper(trim(coalesce(raw_value, 'RW')))
  end
$$;
update public.users
set country = public.normalize_country_code(country)
where country is not null;
update public.groups
set country = public.normalize_country_code(country)
where country is not null;
update public.partners
set country = public.normalize_country_code(country)
where country is not null;
alter table public.users alter column country drop default;
alter table public.groups alter column country drop default;
alter table public.partners alter column country drop default;
