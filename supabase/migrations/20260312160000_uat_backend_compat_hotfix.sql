-- ==========================================================================
-- Cool App — UAT backend compatibility hotfix
-- ==========================================================================
-- Purpose:
--   1. Restore the Countries admin surfaces expected by the current APK.
--   2. Add the legacy mobility/subscription columns that older hosted schemas
--      are missing, so Vehicle / Subscription screens do not fail on raw
--      schema mismatches.
--
-- This is intentionally narrow and safe against partially-upgraded projects.
-- It does not try to replay every mobile-contract migration on production.
-- ==========================================================================

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.supported_countries (
  iso_code text primary key,
  dial_code text not null,
  country_name text not null,
  flag_emoji text not null default '🏳️',
  currency_code text not null,
  currency_name text not null,
  momo_provider_id text not null default '',
  momo_ussd_template text not null,
  momo_number_ussd_template text,
  momo_code_ussd_template text,
  country_aliases jsonb not null default '[]'::jsonb,
  momo_provider_aliases jsonb not null default '[]'::jsonb,
  mobile_national_number_pattern text,
  mobile_possible_lengths integer[] not null default '{}'::integer[],
  mobile_example_national text,
  mobile_example_e164 text,
  momo_number_local_pattern text,
  momo_number_e164_pattern text,
  momo_number_ussd_regex text,
  momo_number_ussd_example text,
  momo_code_kind text,
  momo_code_pattern text,
  momo_code_min_length integer,
  momo_code_max_length integer,
  momo_code_example text,
  momo_code_ussd_regex text,
  momo_code_ussd_example text,
  phone_validation_source text,
  momo_ussd_source text,
  validation_notes text,
  default_lat double precision,
  default_lng double precision,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.supported_countries
  add column if not exists momo_number_ussd_template text,
  add column if not exists momo_code_ussd_template text,
  add column if not exists country_aliases jsonb not null default '[]'::jsonb,
  add column if not exists momo_provider_aliases jsonb not null default '[]'::jsonb,
  add column if not exists mobile_national_number_pattern text,
  add column if not exists mobile_possible_lengths integer[] not null default '{}'::integer[],
  add column if not exists mobile_example_national text,
  add column if not exists mobile_example_e164 text,
  add column if not exists momo_number_local_pattern text,
  add column if not exists momo_number_e164_pattern text,
  add column if not exists momo_number_ussd_regex text,
  add column if not exists momo_number_ussd_example text,
  add column if not exists momo_code_kind text,
  add column if not exists momo_code_pattern text,
  add column if not exists momo_code_min_length integer,
  add column if not exists momo_code_max_length integer,
  add column if not exists momo_code_example text,
  add column if not exists momo_code_ussd_regex text,
  add column if not exists momo_code_ussd_example text,
  add column if not exists phone_validation_source text,
  add column if not exists momo_ussd_source text,
  add column if not exists validation_notes text,
  add column if not exists default_lat double precision,
  add column if not exists default_lng double precision,
  add column if not exists sort_order integer not null default 0,
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
  momo_code_ussd_template,
  country_aliases,
  mobile_possible_lengths,
  mobile_example_national,
  mobile_example_e164,
  momo_number_local_pattern,
  momo_number_e164_pattern,
  momo_number_ussd_regex,
  momo_number_ussd_example,
  momo_code_kind,
  momo_code_pattern,
  momo_code_min_length,
  momo_code_max_length,
  momo_code_example,
  momo_code_ussd_regex,
  momo_code_ussd_example,
  phone_validation_source,
  momo_ussd_source,
  validation_notes,
  default_lat,
  default_lng,
  sort_order,
  is_active
)
values
  (
    'RW',
    '+250',
    'Rwanda',
    '🇷🇼',
    'RWF',
    'Rwandan franc',
    'momo_rw',
    '*182*1*1*{recipient}*{amount}#',
    '*182*1*1*{recipient}*{amount}#',
    '*182*8*1*{recipient}*{amount}#',
    '["Rwanda"]'::jsonb,
    array[9]::integer[],
    '0788 123 456',
    '+250788123456',
    '^(?:0)?7[2389]\\d{7}$',
    '^\\+2507[2389]\\d{7}$',
    '^\\*182\\*1\\*1\\*[0-9]{9,12}\\*[1-9][0-9]{0,11}\\#$',
    '*182*1*1*788123456*5000#',
    'merchant_code',
    '^[0-9]{5,6}$',
    5,
    6,
    '12345',
    '^\\*182\\*8\\*1\\*[0-9]{5,6}\\*[1-9][0-9]{0,11}\\#$',
    '*182*8*1*12345*5000#',
    'cool_app local catalog',
    'cool_app local catalog',
    'Compatibility seed row for the mobile countries admin surface.',
    -1.9441,
    30.0619,
    0,
    true
  )
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
  country_aliases = excluded.country_aliases,
  mobile_possible_lengths = excluded.mobile_possible_lengths,
  mobile_example_national = excluded.mobile_example_national,
  mobile_example_e164 = excluded.mobile_example_e164,
  momo_number_local_pattern = excluded.momo_number_local_pattern,
  momo_number_e164_pattern = excluded.momo_number_e164_pattern,
  momo_number_ussd_regex = excluded.momo_number_ussd_regex,
  momo_number_ussd_example = excluded.momo_number_ussd_example,
  momo_code_kind = excluded.momo_code_kind,
  momo_code_pattern = excluded.momo_code_pattern,
  momo_code_min_length = excluded.momo_code_min_length,
  momo_code_max_length = excluded.momo_code_max_length,
  momo_code_example = excluded.momo_code_example,
  momo_code_ussd_regex = excluded.momo_code_ussd_regex,
  momo_code_ussd_example = excluded.momo_code_ussd_example,
  phone_validation_source = excluded.phone_validation_source,
  momo_ussd_source = excluded.momo_ussd_source,
  validation_notes = excluded.validation_notes,
  default_lat = excluded.default_lat,
  default_lng = excluded.default_lng,
  sort_order = excluded.sort_order,
  is_active = excluded.is_active,
  updated_at = now();

create or replace view public.supported_country_momo_reference as
select
  sc.iso_code,
  sc.country_name,
  sc.flag_emoji,
  sc.dial_code,
  sc.currency_code,
  sc.currency_name,
  sc.momo_provider_id,
  sc.country_aliases,
  sc.momo_provider_aliases,
  sc.mobile_national_number_pattern,
  sc.mobile_possible_lengths,
  sc.mobile_example_national,
  sc.mobile_example_e164,
  sc.momo_number_local_pattern,
  sc.momo_number_e164_pattern,
  sc.momo_number_ussd_template,
  sc.momo_number_ussd_regex,
  sc.momo_number_ussd_example,
  sc.momo_code_kind,
  sc.momo_code_pattern,
  sc.momo_code_min_length,
  sc.momo_code_max_length,
  sc.momo_code_example,
  sc.momo_code_ussd_template,
  sc.momo_code_ussd_regex,
  sc.momo_code_ussd_example,
  (coalesce(nullif(sc.momo_code_ussd_template, ''), '') <> '') as supports_momo_code,
  sc.phone_validation_source,
  sc.momo_ussd_source,
  sc.validation_notes,
  sc.default_lat,
  sc.default_lng,
  sc.sort_order,
  sc.is_active,
  sc.updated_at
from public.supported_countries sc;

grant select on public.supported_countries to anon, authenticated;
grant select on public.supported_country_momo_reference to anon, authenticated;

create or replace view public.momo_validation_issues as
select
  null::text as record_type,
  null::uuid as record_id,
  null::text as country,
  null::text as country_name,
  null::text as route_type,
  null::text as issue_code,
  'Compatibility placeholder. Apply the full country-validation migration set to enable real audit rows.'::text as issue_message,
  null::text as momo_number,
  null::text as momo_code,
  null::text as expected_phone_example,
  null::text as expected_code_example,
  null::text as phone_ussd_example,
  null::text as code_ussd_example,
  false as repair_supported
where false;

drop function if exists public.get_momo_validation_issues();

create or replace function public.get_momo_validation_issues()
returns table (
  record_type text,
  record_id uuid,
  country text,
  country_name text,
  route_type text,
  issue_code text,
  issue_message text,
  momo_number text,
  momo_code text,
  expected_phone_example text,
  expected_code_example text,
  phone_ussd_example text,
  code_ussd_example text,
  repair_supported boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    mvi.record_type,
    mvi.record_id,
    mvi.country,
    mvi.country_name,
    mvi.route_type,
    mvi.issue_code,
    mvi.issue_message,
    mvi.momo_number,
    mvi.momo_code,
    mvi.expected_phone_example,
    mvi.expected_code_example,
    mvi.phone_ussd_example,
    mvi.code_ussd_example,
    mvi.repair_supported
  from public.momo_validation_issues mvi
$$;

revoke all on function public.get_momo_validation_issues() from public;
grant execute on function public.get_momo_validation_issues() to authenticated;

create or replace function public.repair_momo_validation_issue(
  p_record_type text,
  p_record_id uuid,
  p_issue_code text
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'status', 'unavailable',
    'record_type', p_record_type,
    'record_id', p_record_id,
    'issue_code', p_issue_code,
    'message', 'Repair automation is unavailable until the full validation migration set is applied.'
  )
$$;

revoke all on function public.repair_momo_validation_issue(text, uuid, text) from public;
grant execute on function public.repair_momo_validation_issue(text, uuid, text) to authenticated;

alter table public.driver_profiles
  add column if not exists country text not null default 'RW',
  add column if not exists trips_used_this_month integer not null default 0,
  add column if not exists plate_number text not null default '',
  add column if not exists base_location text not null default '',
  add column if not exists vehicle_status text not null default 'pending_review',
  add column if not exists rating double precision not null default 0,
  add column if not exists trips_done integer not null default 0,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

do $$
declare
  has_vehicle_description boolean;
  has_last_location_lat boolean;
  has_last_location_lng boolean;
begin
  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'driver_profiles'
      and column_name = 'vehicle_description'
  ) into has_vehicle_description;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'driver_profiles'
      and column_name = 'last_location_lat'
  ) into has_last_location_lat;

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'driver_profiles'
      and column_name = 'last_location_lng'
  ) into has_last_location_lng;

  execute format(
    $sql$
      update public.driver_profiles
      set
        country = coalesce(nullif(country, ''), 'RW'),
        plate_number = %s,
        latitude = %s,
        longitude = %s
      where true
    $sql$,
    case
      when has_vehicle_description
        then 'coalesce(nullif(plate_number, ''''), vehicle_description, '''')'
      else 'coalesce(nullif(plate_number, ''''), '''')'
    end,
    case
      when has_last_location_lat
        then 'coalesce(latitude, last_location_lat)'
      else 'latitude'
    end,
    case
      when has_last_location_lng
        then 'coalesce(longitude, last_location_lng)'
      else 'longitude'
    end
  );
end;
$$;

create index if not exists idx_driver_profiles_country
  on public.driver_profiles (country);

create table if not exists public.driver_subscriptions (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null,
  plan text,
  plan_id text,
  plan_name text,
  amount integer not null default 0,
  amount_rwf integer,
  status text not null default 'pending',
  started_at timestamptz,
  expires_at timestamptz,
  cancelled_at timestamptz,
  momo_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_driver_subscriptions_driver
  on public.driver_subscriptions (driver_id);

create index if not exists idx_driver_subscriptions_status
  on public.driver_subscriptions (status);

alter table public.mobility_trips
  add column if not exists country text not null default 'RW',
  add column if not exists contact_phone text,
  add column if not exists contact_name text;

update public.mobility_trips
set country = coalesce(nullif(country, ''), 'RW')
where true;

create index if not exists idx_mobility_trips_country
  on public.mobility_trips (country);
