begin;

-- ISO country/currency defaults are a 2026-08-28 snapshot of Unicode CLDR
-- supplemental currency data. European flags follow Revolut's supported EEA,
-- Switzerland, UK, and crown-dependency signup footprint on the same date.
-- They describe profile localization only; Collect bank-transfer settlement
-- remains the separately governed EUR rail.
create table if not exists public.profile_country_rules (
  country_code text primary key check (country_code ~ '^[A-Z]{2}$'),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  is_europe boolean not null default false,
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.profile_country_rules enable row level security;
drop policy if exists "profile country rules enabled read"
  on public.profile_country_rules;
create policy "profile country rules enabled read"
on public.profile_country_rules for select to anon, authenticated
using (enabled);

revoke all on public.profile_country_rules from anon, authenticated;
grant select on public.profile_country_rules to anon, authenticated;

insert into public.profile_country_rules (
  country_code, currency_code, is_europe, enabled, updated_at
)
select
  entry.country_code,
  entry.currency_code,
  entry.country_code = any(array['AT', 'BE', 'BG', 'CH', 'CY', 'CZ', 'DE', 'DK', 'EE', 'ES', 'FI', 'FR', 'GB', 'GG', 'GR', 'HR', 'HU', 'IE', 'IM', 'IS', 'IT', 'JE', 'LI', 'LT', 'LU', 'LV', 'MT', 'NL', 'NO', 'PL', 'PT', 'RO', 'SE', 'SI', 'SK']::text[]),
  true,
  now()
from jsonb_each_text(
  $country_currency${"AC":"SHP","AD":"EUR","AE":"AED","AF":"AFN","AG":"XCD","AI":"XCD","AL":"ALL","AM":"AMD","AO":"AOA","AR":"ARS","AS":"USD","AT":"EUR","AU":"AUD","AW":"AWG","AX":"EUR","AZ":"AZN","BA":"BAM","BB":"BBD","BD":"BDT","BE":"EUR","BF":"XOF","BG":"EUR","BH":"BHD","BI":"BIF","BJ":"XOF","BL":"EUR","BM":"BMD","BN":"BND","BO":"BOB","BQ":"USD","BR":"BRL","BS":"BSD","BT":"BTN","BW":"BWP","BY":"BYN","BZ":"BZD","CA":"CAD","CC":"AUD","CD":"CDF","CF":"XAF","CG":"XAF","CH":"CHF","CI":"XOF","CK":"NZD","CL":"CLP","CM":"XAF","CN":"CNY","CO":"COP","CR":"CRC","CU":"CUP","CV":"CVE","CW":"XCG","CX":"AUD","CY":"EUR","CZ":"CZK","DE":"EUR","DJ":"DJF","DK":"DKK","DM":"XCD","DO":"DOP","DZ":"DZD","EC":"USD","EE":"EUR","EG":"EGP","EH":"MAD","ER":"ERN","ES":"EUR","ET":"ETB","FI":"EUR","FJ":"FJD","FK":"FKP","FM":"USD","FO":"DKK","FR":"EUR","GA":"XAF","GB":"GBP","GD":"XCD","GE":"GEL","GF":"EUR","GG":"GBP","GH":"GHS","GI":"GIP","GL":"DKK","GM":"GMD","GN":"GNF","GP":"EUR","GQ":"XAF","GR":"EUR","GS":"GBP","GT":"GTQ","GU":"USD","GW":"XOF","GY":"GYD","HK":"HKD","HM":"AUD","HN":"HNL","HR":"EUR","HT":"HTG","HU":"HUF","ID":"IDR","IE":"EUR","IL":"ILS","IM":"GBP","IN":"INR","IO":"USD","IQ":"IQD","IR":"IRR","IS":"ISK","IT":"EUR","JE":"GBP","JM":"JMD","JO":"JOD","JP":"JPY","KE":"KES","KG":"KGS","KH":"KHR","KI":"AUD","KM":"KMF","KN":"XCD","KP":"KPW","KR":"KRW","KW":"KWD","KY":"KYD","KZ":"KZT","LA":"LAK","LB":"LBP","LC":"XCD","LI":"CHF","LK":"LKR","LR":"LRD","LS":"LSL","LT":"EUR","LU":"EUR","LV":"EUR","LY":"LYD","MA":"MAD","MC":"EUR","MD":"MDL","ME":"EUR","MF":"EUR","MG":"MGA","MH":"USD","MK":"MKD","ML":"XOF","MM":"MMK","MN":"MNT","MO":"MOP","MP":"USD","MQ":"EUR","MR":"MRU","MS":"XCD","MT":"EUR","MU":"MUR","MV":"MVR","MW":"MWK","MX":"MXN","MY":"MYR","MZ":"MZN","NA":"NAD","NC":"XPF","NE":"XOF","NF":"AUD","NG":"NGN","NI":"NIO","NL":"EUR","NO":"NOK","NP":"NPR","NR":"AUD","NU":"NZD","NZ":"NZD","OM":"OMR","PA":"PAB","PE":"PEN","PF":"XPF","PG":"PGK","PH":"PHP","PK":"PKR","PL":"PLN","PM":"EUR","PR":"USD","PS":"ILS","PT":"EUR","PW":"USD","PY":"PYG","QA":"QAR","RE":"EUR","RO":"RON","RS":"RSD","RU":"RUB","RW":"RWF","SA":"SAR","SB":"SBD","SC":"SCR","SD":"SDG","SE":"SEK","SG":"SGD","SH":"SHP","SI":"EUR","SJ":"NOK","SK":"EUR","SL":"SLE","SM":"EUR","SN":"XOF","SO":"SOS","SR":"SRD","SS":"SSP","ST":"STN","SV":"USD","SX":"XCG","SY":"SYP","SZ":"SZL","TC":"USD","TD":"XAF","TG":"XOF","TH":"THB","TJ":"TJS","TK":"NZD","TL":"USD","TM":"TMT","TN":"TND","TO":"TOP","TR":"TRY","TT":"TTD","TV":"AUD","TW":"TWD","TZ":"TZS","UA":"UAH","UG":"UGX","US":"USD","UY":"UYU","UZ":"UZS","VA":"EUR","VC":"XCD","VE":"VES","VG":"USD","VI":"USD","VN":"VND","VU":"VUV","WF":"XPF","WS":"WST","XK":"EUR","YE":"YER","YT":"EUR","ZA":"ZAR","ZM":"ZMW","ZW":"ZWG"}$country_currency$::jsonb
) as entry(country_code, currency_code)
on conflict (country_code) do update
set currency_code = excluded.currency_code,
    is_europe = excluded.is_europe,
    enabled = excluded.enabled,
    updated_at = now();

alter table public.profiles
  add column if not exists country_code text,
  add column if not exists currency_code text,
  add column if not exists revolut_name text;

alter table public.profiles
  drop constraint if exists profiles_country_code_format,
  drop constraint if exists profiles_currency_code_format,
  drop constraint if exists profiles_revolut_name_length;

alter table public.profiles
  add constraint profiles_country_code_format
    check (country_code is null or country_code ~ '^[A-Z]{2}$') not valid,
  add constraint profiles_currency_code_format
    check (currency_code is null or currency_code ~ '^[A-Z]{3}$') not valid,
  add constraint profiles_revolut_name_length
    check (
      revolut_name is null
      or char_length(trim(revolut_name)) between 2 and 100
    ) not valid;

alter table public.profiles
  validate constraint profiles_country_code_format,
  validate constraint profiles_currency_code_format,
  validate constraint profiles_revolut_name_length;

comment on column public.profiles.country_code is 'User-editable profile country, independent from WhatsApp sign-in calling code';
comment on column public.profiles.currency_code is 'Country-derived local profile currency; not the Collect settlement currency';
comment on column public.profiles.revolut_name is 'Regional profile identifier required in Revolut-supported Europe; never payment authorization';

-- Preserve the verified WhatsApp identity for older profiles that predate the
-- mobile bootstrap RPC. Never replace an existing profile number.
update public.profiles profile
set whatsapp_phone = nullif(trim(auth_user.phone), ''),
    updated_at = now()
from auth.users auth_user
where profile.id = auth_user.id
  and coalesce(trim(profile.whatsapp_phone), '') = ''
  and nullif(trim(auth_user.phone), '') is not null
  and not exists (
    select 1
    from public.profiles existing_profile
    where existing_profile.id <> profile.id
      and existing_profile.whatsapp_phone = trim(auth_user.phone)
  );

drop function if exists public.ensure_current_profile(text);

create or replace function public.ensure_current_profile(
  p_whatsapp_phone text default null,
  p_country_code text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  profile_row public.profiles%rowtype;
  country_rule public.profile_country_rules%rowtype;
  requested_phone text := nullif(trim(coalesce(p_whatsapp_phone, '')), '');
  verified_phone text;
  clean_phone text;
  clean_country text := upper(nullif(trim(coalesce(p_country_code, '')), ''));
  resolved_country text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select nullif(trim(phone), '') into verified_phone
  from auth.users
  where id = auth.uid();
  clean_phone := coalesce(verified_phone, requested_phone);

  if clean_country is not null then
    select * into country_rule
    from public.profile_country_rules
    where country_code = clean_country and enabled;
    if country_rule.country_code is null then
      raise exception 'Unsupported profile country';
    end if;
  end if;

  select * into profile_row
  from public.profiles
  where id = auth.uid();

  if profile_row.id is null then
    resolved_country := clean_country;
    insert into public.profiles (
      id, public_id, whatsapp_phone, country_code, currency_code
    )
    values (
      auth.uid(),
      public.generate_public_id(),
      clean_phone,
      resolved_country,
      country_rule.currency_code
    )
    returning * into profile_row;
  else
    resolved_country := coalesce(profile_row.country_code, clean_country);
    if resolved_country is not null
       and country_rule.country_code is distinct from resolved_country then
      select * into country_rule
      from public.profile_country_rules
      where country_code = resolved_country and enabled;
    end if;

    update public.profiles
    set whatsapp_phone = case
          when verified_phone is not null then verified_phone
          when coalesce(profile_row.whatsapp_phone, '') = '' then clean_phone
          else profile_row.whatsapp_phone
        end,
        country_code = resolved_country,
        currency_code = coalesce(
          profile_row.currency_code,
          country_rule.currency_code
        )
    where id = auth.uid()
    returning * into profile_row;
  end if;

  return profile_row;
end;
$$;

revoke execute on function public.ensure_current_profile(text, text)
  from public, anon, authenticated;
grant execute on function public.ensure_current_profile(text, text)
  to authenticated;

create or replace function public.update_current_profile(
  p_display_name text,
  p_country_code text,
  p_revolut_name text default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  profile_row public.profiles%rowtype;
  country_rule public.profile_country_rules%rowtype;
  clean_display_name text := trim(coalesce(p_display_name, ''));
  clean_country text := upper(trim(coalesce(p_country_code, '')));
  clean_revolut_name text := nullif(trim(coalesce(p_revolut_name, '')), '');
  previous_country text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if char_length(clean_display_name) not between 2 and 80 then
    raise exception 'Display name must be between 2 and 80 characters';
  end if;

  select * into country_rule
  from public.profile_country_rules
  where country_code = clean_country and enabled;
  if country_rule.country_code is null then
    raise exception 'Unsupported profile country';
  end if;
  if country_rule.is_europe
     and (clean_revolut_name is null
       or char_length(clean_revolut_name) not between 2 and 100) then
    raise exception 'Revolut name is required in supported European profiles';
  end if;

  select country_code into previous_country
  from public.profiles
  where id = auth.uid();

  update public.profiles
  set display_name = clean_display_name,
      country_code = country_rule.country_code,
      currency_code = country_rule.currency_code,
      revolut_name = case
        when country_rule.is_europe then clean_revolut_name
        else null
      end,
      updated_at = now()
  where id = auth.uid()
  returning * into profile_row;

  if profile_row.id is null then
    raise exception 'Collect profile not found';
  end if;

  insert into public.audit_logs (
    actor_user_id, action, entity_type, entity_id, metadata
  )
  values (
    auth.uid(),
    'profile.updated',
    'profile',
    auth.uid(),
    jsonb_build_object(
      'previous_country_code', previous_country,
      'country_code', profile_row.country_code,
      'currency_code', profile_row.currency_code,
      'revolut_name_required', country_rule.is_europe,
      'profile_complete', true
    )
  );

  return profile_row;
end;
$$;

revoke execute on function public.update_current_profile(text, text, text)
  from public, anon, authenticated;
grant execute on function public.update_current_profile(text, text, text)
  to authenticated;

update public.policy_document_sections section
set body =
      'Collect stores your Collect ID, display name, independently selected profile country and local currency, WhatsApp sign-in phone, conditional Revolut name in its supported European region, group memberships, group profile details, bank transfer requests, contribution records, notification preferences, and audit status. Controlled operations channels process beneficiary-bank SMS, email, and statement evidence.',
    updated_at = now(),
    updated_reason = 'Add independent country, local currency, and regional profile identity fields'
from public.policy_documents document
where section.policy_document_id = document.id
  and document.kind = 'privacy'
  and document.status = 'published'
  and section.section_key = 'data_we_collect';

commit;
