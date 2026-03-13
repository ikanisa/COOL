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
  ('RW', '+250', 'Rwanda', '🇷🇼', 'RWF', 'Rwandan franc', 'momo_rw', '*182*1*1*{recipient}*{amount}#')
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
    else 'RW'
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
