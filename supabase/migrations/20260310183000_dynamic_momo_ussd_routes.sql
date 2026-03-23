-- ==========================================================================
-- Cool App — Dynamic MoMo USSD routes and merchant-code support
-- ==========================================================================
-- Ensures a DB-driven countries catalog exists, supports two USSD route types
-- (phone number and merchant code), and adds recipient-route metadata to
-- groups plus merchant-code storage to profile tables.
-- ==========================================================================

create table if not exists public.supported_countries (
  iso_code text primary key,
  dial_code text not null unique,
  country_name text not null,
  flag_emoji text not null,
  currency_code text not null,
  currency_name text not null,
  momo_provider_id text not null,
  momo_ussd_template text not null,
  momo_number_ussd_template text not null,
  momo_code_ussd_template text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.supported_countries
  add column if not exists momo_ussd_template text,
  add column if not exists momo_number_ussd_template text,
  add column if not exists momo_code_ussd_template text,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();
insert into public.supported_countries (
  iso_code,
  dial_code,
  country_name,
  flag_emoji,
  currency_code,
  currency_name,
  momo_provider_id,
  momo_ussd_template,
  momo_number_ussd_template,
  momo_code_ussd_template
)
values
  ('BJ', '+229', 'Benin', '🇧🇯', 'XOF', 'West African CFA franc', 'momo_bj', '*400*1*{recipient}*{amount}#', '*400*1*{recipient}*{amount}#', null),
  ('BW', '+267', 'Botswana', '🇧🇼', 'BWP', 'Botswana pula', 'momo_bw', '*167*1*{recipient}*{amount}#', '*167*1*{recipient}*{amount}#', null),
  ('CM', '+237', 'Cameroon', '🇨🇲', 'XAF', 'Central African CFA franc', 'momo_cm', '*126*1*{recipient}*{amount}#', '*126*1*{recipient}*{amount}#', null),
  ('CG', '+242', 'Congo Brazzaville', '🇨🇬', 'XAF', 'Central African CFA franc', 'momo_cg', '*124*1*{recipient}*{amount}#', '*124*1*{recipient}*{amount}#', null),
  ('CI', '+225', 'Côte d''Ivoire', '🇨🇮', 'XOF', 'West African CFA franc', 'momo_ci', '*133*1*{recipient}*{amount}#', '*133*1*{recipient}*{amount}#', null),
  ('GH', '+233', 'Ghana', '🇬🇭', 'GHS', 'Ghanaian cedi', 'momo_gh', '*170*1*{recipient}*{amount}#', '*170*1*{recipient}*{amount}#', null),
  ('GN', '+224', 'Guinea', '🇬🇳', 'GNF', 'Guinean franc', 'momo_gn', '*155*1*{recipient}*{amount}#', '*155*1*{recipient}*{amount}#', null),
  ('GW', '+245', 'Guinea-Bissau', '🇬🇼', 'XOF', 'West African CFA franc', 'momo_gw', '*124*1*{recipient}*{amount}#', '*124*1*{recipient}*{amount}#', null),
  ('KE', '+254', 'Kenya', '🇰🇪', 'KES', 'Kenyan shilling', 'momo_ke', '*334*1*{recipient}*{amount}#', '*334*1*{recipient}*{amount}#', null),
  ('LR', '+231', 'Liberia', '🇱🇷', 'LRD', 'Liberian dollar', 'momo_lr', '*156*1*{recipient}*{amount}#', '*156*1*{recipient}*{amount}#', null),
  ('MW', '+265', 'Malawi', '🇲🇼', 'MWK', 'Malawian kwacha', 'momo_mw', '*444*1*{recipient}*{amount}#', '*444*1*{recipient}*{amount}#', null),
  ('MZ', '+258', 'Mozambique', '🇲🇿', 'MZN', 'Mozambican metical', 'momo_mz', '*197*1*{recipient}*{amount}#', '*197*1*{recipient}*{amount}#', null),
  ('NG', '+234', 'Nigeria', '🇳🇬', 'NGN', 'Nigerian naira', 'momo_ng', '*223*1*{recipient}*{amount}#', '*223*1*{recipient}*{amount}#', null),
  ('RW', '+250', 'Rwanda', '🇷🇼', 'RWF', 'Rwandan franc', 'momo_rw', '*182*1*1*{recipient}*{amount}#', '*182*1*1*{recipient}*{amount}#', '*182*8*1*{recipient}*{amount}#'),
  ('ZA', '+27', 'South Africa', '🇿🇦', 'ZAR', 'South African rand', 'momo_za', '*120*668*1*{recipient}*{amount}#', '*120*668*1*{recipient}*{amount}#', null),
  ('SZ', '+268', 'Eswatini (Swaziland)', '🇸🇿', 'SZL', 'Swazi lilangeni', 'momo_sz', '*468*1*{recipient}*{amount}#', '*468*1*{recipient}*{amount}#', null),
  ('UG', '+256', 'Uganda', '🇺🇬', 'UGX', 'Ugandan shilling', 'momo_ug', '*165*1*{recipient}*{amount}#', '*165*1*{recipient}*{amount}#', null),
  ('ZM', '+260', 'Zambia', '🇿🇲', 'ZMW', 'Zambian kwacha', 'momo_zm', '*303*1*{recipient}*{amount}#', '*303*1*{recipient}*{amount}#', null),
  ('ZW', '+263', 'Zimbabwe', '🇿🇼', 'ZWL', 'Zimbabwean dollar', 'momo_zw', '*151*1*{recipient}*{amount}#', '*151*1*{recipient}*{amount}#', null),
  ('CD', '+243', 'Democratic Republic of Congo (DRC)', '🇨🇩', 'CDF', 'Congolese franc', 'momo_cd', '*099*1*{recipient}*{amount}#', '*099*1*{recipient}*{amount}#', null),
  ('ET', '+251', 'Ethiopia', '🇪🇹', 'ETB', 'Ethiopian birr', 'momo_et', '*806*1*{recipient}*{amount}#', '*806*1*{recipient}*{amount}#', null),
  ('GA', '+241', 'Gabon', '🇬🇦', 'XAF', 'Central African CFA franc', 'momo_ga', '*222*1*{recipient}*{amount}#', '*222*1*{recipient}*{amount}#', null),
  ('MG', '+261', 'Madagascar', '🇲🇬', 'MGA', 'Malagasy ariary', 'momo_mg', '*162*1*{recipient}*{amount}#', '*162*1*{recipient}*{amount}#', null),
  ('SN', '+221', 'Senegal', '🇸🇳', 'XOF', 'West African CFA franc', 'momo_sn', '*140*1*{recipient}*{amount}#', '*140*1*{recipient}*{amount}#', null),
  ('SL', '+232', 'Sierra Leone', '🇸🇱', 'SLL', 'Sierra Leonean leone', 'momo_sl', '*277*1*{recipient}*{amount}#', '*277*1*{recipient}*{amount}#', null),
  ('TZ', '+255', 'Tanzania', '🇹🇿', 'TZS', 'Tanzanian shilling', 'momo_tz', '*150*00*1*{recipient}*{amount}#', '*150*00*1*{recipient}*{amount}#', null)
on conflict (iso_code) do update
set
  dial_code = excluded.dial_code,
  country_name = excluded.country_name,
  flag_emoji = excluded.flag_emoji,
  currency_code = excluded.currency_code,
  currency_name = excluded.currency_name,
  momo_provider_id = excluded.momo_provider_id,
  momo_ussd_template = excluded.momo_ussd_template,
  momo_number_ussd_template = excluded.momo_number_ussd_template,
  momo_code_ussd_template = excluded.momo_code_ussd_template,
  is_active = true,
  updated_at = now();
update public.supported_countries
set momo_number_ussd_template = coalesce(
    nullif(momo_number_ussd_template, ''),
    nullif(momo_ussd_template, '')
  ),
  momo_ussd_template = coalesce(
    nullif(momo_ussd_template, ''),
    nullif(momo_number_ussd_template, '')
  )
where coalesce(momo_number_ussd_template, '') = ''
   or coalesce(momo_ussd_template, '') = '';
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'momo_code'
  ) then
    update public.users
    set momo_code = nullif(
      regexp_replace(coalesce(momo_code, ''), '[^0-9]', '', 'g'),
      ''
    )
    where momo_code is not null;
  elsif exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'users'
  ) then
    alter table public.users add column momo_code text;
    update public.users
    set momo_code = nullif(
      regexp_replace(coalesce(momo_number, ''), '[^0-9]', '', 'g'),
      ''
    )
    where coalesce(momo_number, '') <> '';
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'momo_code'
  ) then
    update public.profiles
    set momo_code = nullif(
      regexp_replace(coalesce(momo_code, ''), '[^0-9]', '', 'g'),
      ''
    )
    where momo_code is not null;
  elsif exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'profiles'
  ) then
    alter table public.profiles add column momo_code text;
  end if;
end $$;
alter table public.groups
  add column if not exists momo_number text,
  add column if not exists receiving_momo_code text,
  add column if not exists receiving_momo_route_type text
    check (receiving_momo_route_type in ('phone_number', 'code'));
update public.groups
set receiving_momo_code = coalesce(
    nullif(receiving_momo_code, ''),
    nullif(momo_number, '')
  )
where coalesce(receiving_momo_code, '') = ''
  and coalesce(momo_number, '') <> '';
update public.groups
set receiving_momo_route_type = case
  when coalesce(receiving_momo_route_type, '') <> '' then receiving_momo_route_type
  when coalesce(receiving_momo_code, '') = '' then null
  when receiving_momo_code like '+%' then 'phone_number'
  when receiving_momo_code ~ '^[0-9]{9,}$' then 'phone_number'
  else 'code'
end
where true;
