-- ==========================================================================
-- Cool App — Supported countries validation metadata
-- ==========================================================================
-- Adds country aliases, libphonenumber-backed mobile validation metadata,
-- and explicit separation between:
--   1) MoMo phone numbers (mobile MSISDNs)
--   2) MoMo merchant/payment codes
--
-- Source strategy:
-- - Phone validation: libphonenumber mobile metadata.
-- - USSD route shapes: product/business-configured operator matrix.
-- ==========================================================================

alter table public.supported_countries
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
  add column if not exists validation_notes text;

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
  momo_provider_aliases,
  mobile_national_number_pattern,
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
  validation_notes
)
values
  ('RW', '+250', 'Rwanda', '🇷🇼', 'RWF', 'Rwandan franc', 'momo_rw', '*182*1*1*{recipient}*{amount}#', '*182*1*1*{recipient}*{amount}#', '*182*8*1*{recipient}*{amount}#', '["Rwanda"]'::jsonb, '["mtn_rwanda", "mtn", "mtn rwanda"]'::jsonb, '^(?:7[237-9]\d{7})$', ARRAY[9]::integer[], '0720 123 456', '+250720123456', '^(?:0)?(?:7[237-9]\d{7})$', '^\+250(?:7[237-9]\d{7})$', '^\*182\*1\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*182*1*1*720123456*5000#', 'merchant_code', '^[0-9]{6}$', 6, 6, '123456', '^\*182\*8\*1\*[0-9]{6}\*[1-9][0-9]{0,11}\#$', '*182*8*1*123456*5000#', 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is a mobile MSISDN routed via *182*1*1*. Merchant code is a separate MTN MoMo Pay merchant identifier routed via *182*8*1* and validated separately from phone numbers.')
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
  momo_provider_aliases = excluded.momo_provider_aliases,
  mobile_national_number_pattern = excluded.mobile_national_number_pattern,
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
  is_active = true,
  updated_at = now();

update public.supported_countries
set country_aliases = '[]'::jsonb
where country_aliases is null;

update public.supported_countries
set momo_provider_aliases = '[]'::jsonb
where momo_provider_aliases is null;

update public.supported_countries
set mobile_possible_lengths = '{}'::integer[]
where mobile_possible_lengths is null;
