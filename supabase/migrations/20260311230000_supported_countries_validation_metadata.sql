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
  ('BJ', '+229', 'Benin', '🇧🇯', 'XOF', 'West African CFA franc', 'momo_bj', '*400*1*{recipient}*{amount}#', '*400*1*{recipient}*{amount}#', null, '["Benin"]'::jsonb, '[]'::jsonb, '^(?:01(?:2[5-9]|[4-69]\d)\d{6})$', ARRAY[10]::integer[], '01 95 12 34 56', '+2290195123456', '^(?:01(?:2[5-9]|[4-69]\d)\d{6})$', '^\+229(?:01(?:2[5-9]|[4-69]\d)\d{6})$', '^\*400\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*400*1*195123456*10000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('BW', '+267', 'Botswana', '🇧🇼', 'BWP', 'Botswana pula', 'momo_bw', '*167*1*{recipient}*{amount}#', '*167*1*{recipient}*{amount}#', null, '["Botswana"]'::jsonb, '[]'::jsonb, '^(?:(?:321|7[1-8]\d)\d{5})$', ARRAY[8]::integer[], '71 123 456', '+26771123456', '^(?:(?:321|7[1-8]\d)\d{5})$', '^\+267(?:(?:321|7[1-8]\d)\d{5})$', '^\*167\*1\*[0-9]{8}\*[1-9][0-9]{0,11}\#$', '*167*1*71123456*1000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('CM', '+237', 'Cameroon', '🇨🇲', 'XAF', 'Central African CFA franc', 'momo_cm', '*126*1*{recipient}*{amount}#', '*126*1*{recipient}*{amount}#', null, '["Cameroon"]'::jsonb, '[]'::jsonb, '^(?:(?:24[23]|6(?:[25-9]\d|40))\d{6})$', ARRAY[9]::integer[], '6 71 23 45 67', '+237671234567', '^(?:(?:24[23]|6(?:[25-9]\d|40))\d{6})$', '^\+237(?:(?:24[23]|6(?:[25-9]\d|40))\d{6})$', '^\*126\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*126*1*671234567*5000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('CG', '+242', 'Congo Brazzaville', '🇨🇬', 'XAF', 'Central African CFA franc', 'momo_cg', '*124*1*{recipient}*{amount}#', '*124*1*{recipient}*{amount}#', null, '["Congo Brazzaville", "Republic of the Congo", "Republic of Congo", "Congo"]'::jsonb, '[]'::jsonb, '^(?:026(?:1[0-5]|6[6-9])\d{4}|0(?:[14-6]\d\d|2(?:40|5[5-8]|6[07-9]))\d{5})$', ARRAY[9]::integer[], '06 123 4567', '+242061234567', '^(?:026(?:1[0-5]|6[6-9])\d{4}|0(?:[14-6]\d\d|2(?:40|5[5-8]|6[07-9]))\d{5})$', '^\+242(?:026(?:1[0-5]|6[6-9])\d{4}|0(?:[14-6]\d\d|2(?:40|5[5-8]|6[07-9]))\d{5})$', '^\*124\*1\*[0-9]{8}\*[1-9][0-9]{0,11}\#$', '*124*1*61234567*2500#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('CI', '+225', 'Côte d''Ivoire', '🇨🇮', 'XOF', 'West African CFA franc', 'momo_ci', '*133*1*{recipient}*{amount}#', '*133*1*{recipient}*{amount}#', null, '["Côte d''Ivoire", "Cote d''Ivoire", "Ivory Coast"]'::jsonb, '[]'::jsonb, '^(?:0[157]\d{8})$', ARRAY[10]::integer[], '01 23 45 6789', '+2250123456789', '^(?:0[157]\d{8})$', '^\+225(?:0[157]\d{8})$', '^\*133\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*133*1*123456789*3000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('GH', '+233', 'Ghana', '🇬🇭', 'GHS', 'Ghanaian cedi', 'momo_gh', '*170*1*{recipient}*{amount}#', '*170*1*{recipient}*{amount}#', null, '["Ghana"]'::jsonb, '[]'::jsonb, '^(?:(?:2(?:[0346-9]\d|5[67])|5(?:[03-7]\d|9[1-9]))\d{6})$', ARRAY[9]::integer[], '023 123 4567', '+233231234567', '^(?:0)?(?:(?:2(?:[0346-9]\d|5[67])|5(?:[03-7]\d|9[1-9]))\d{6})$', '^\+233(?:(?:2(?:[0346-9]\d|5[67])|5(?:[03-7]\d|9[1-9]))\d{6})$', '^\*170\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*170*1*231234567*15000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('GN', '+224', 'Guinea', '🇬🇳', 'GNF', 'Guinean franc', 'momo_gn', '*155*1*{recipient}*{amount}#', '*155*1*{recipient}*{amount}#', null, '["Guinea"]'::jsonb, '[]'::jsonb, '^(?:6[0-356]\d{7})$', ARRAY[9]::integer[], '601 12 34 56', '+224601123456', '^(?:6[0-356]\d{7})$', '^\+224(?:6[0-356]\d{7})$', '^\*155\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*155*1*601123456*2000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('GW', '+245', 'Guinea-Bissau', '🇬🇼', 'XOF', 'West African CFA franc', 'momo_gw', '*124*1*{recipient}*{amount}#', '*124*1*{recipient}*{amount}#', null, '["Guinea-Bissau", "Guinea Bissau"]'::jsonb, '[]'::jsonb, '^(?:9(?:5\d|6[569]|77)\d{6})$', ARRAY[9]::integer[], '955 012 345', '+245955012345', '^(?:9(?:5\d|6[569]|77)\d{6})$', '^\+245(?:9(?:5\d|6[569]|77)\d{6})$', '^\*124\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*124*1*955012345*1000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('KE', '+254', 'Kenya', '🇰🇪', 'KES', 'Kenyan shilling', 'momo_ke', '*334*1*{recipient}*{amount}#', '*334*1*{recipient}*{amount}#', null, '["Kenya"]'::jsonb, '["mpesa", "m-pesa", "safaricom"]'::jsonb, '^(?:(?:1(?:0[0-8]|1\d|2[014]|[34]0)|7\d\d)\d{6})$', ARRAY[9]::integer[], '0712 123456', '+254712123456', '^(?:0)?(?:(?:1(?:0[0-8]|1\d|2[014]|[34]0)|7\d\d)\d{6})$', '^\+254(?:(?:1(?:0[0-8]|1\d|2[014]|[34]0)|7\d\d)\d{6})$', '^\*334\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*334*1*712123456*500#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('LR', '+231', 'Liberia', '🇱🇷', 'LRD', 'Liberian dollar', 'momo_lr', '*156*1*{recipient}*{amount}#', '*156*1*{recipient}*{amount}#', null, '["Liberia"]'::jsonb, '[]'::jsonb, '^(?:(?:(?:(?:22|33)0|555|7(?:6[01]|7\d)|88\d)\d|4(?:240|[67]))\d{5}|[56]\d{6})$', ARRAY[7, 9]::integer[], '077 012 3456', '+231770123456', '^(?:0)?(?:(?:(?:(?:22|33)0|555|7(?:6[01]|7\d)|88\d)\d|4(?:240|[67]))\d{5}|[56]\d{6})$', '^\+231(?:(?:(?:(?:22|33)0|555|7(?:6[01]|7\d)|88\d)\d|4(?:240|[67]))\d{5}|[56]\d{6})$', '^\*156\*1\*[0-9]{7,9}\*[1-9][0-9]{0,11}\#$', '*156*1*770123456*7000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('MW', '+265', 'Malawi', '🇲🇼', 'MWK', 'Malawian kwacha', 'momo_mw', '*444*1*{recipient}*{amount}#', '*444*1*{recipient}*{amount}#', null, '["Malawi"]'::jsonb, '[]'::jsonb, '^(?:111\d{6}|(?:31|77|[89][89])\d{7})$', ARRAY[9]::integer[], '0991 23 45 67', '+265991234567', '^(?:0)?(?:111\d{6}|(?:31|77|[89][89])\d{7})$', '^\+265(?:111\d{6}|(?:31|77|[89][89])\d{7})$', '^\*444\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*444*1*991234567*8000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('MZ', '+258', 'Mozambique', '🇲🇿', 'MZN', 'Mozambican metical', 'momo_mz', '*197*1*{recipient}*{amount}#', '*197*1*{recipient}*{amount}#', null, '["Mozambique"]'::jsonb, '[]'::jsonb, '^(?:8[2-79]\d{7})$', ARRAY[9]::integer[], '82 123 4567', '+258821234567', '^(?:8[2-79]\d{7})$', '^\+258(?:8[2-79]\d{7})$', '^\*197\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*197*1*821234567*6000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('NG', '+234', 'Nigeria', '🇳🇬', 'NGN', 'Nigerian naira', 'momo_ng', '*223*1*{recipient}*{amount}#', '*223*1*{recipient}*{amount}#', null, '["Nigeria"]'::jsonb, '[]'::jsonb, '^(?:(?:702[0-24-9]|819[01])\d{6}|(?:7(?:0[13-9]|[12]\d)|8(?:0[1-9]|1[0-8])|9(?:0[1-9]|1[1-6]))\d{7})$', ARRAY[10]::integer[], '0802 123 4567', '+2348021234567', '^(?:0)?(?:(?:702[0-24-9]|819[01])\d{6}|(?:7(?:0[13-9]|[12]\d)|8(?:0[1-9]|1[0-8])|9(?:0[1-9]|1[1-6]))\d{7})$', '^\+234(?:(?:702[0-24-9]|819[01])\d{6}|(?:7(?:0[13-9]|[12]\d)|8(?:0[1-9]|1[0-8])|9(?:0[1-9]|1[1-6]))\d{7})$', '^\*223\*1\*[0-9]{10}\*[1-9][0-9]{0,11}\#$', '*223*1*8021234567*12000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('RW', '+250', 'Rwanda', '🇷🇼', 'RWF', 'Rwandan franc', 'momo_rw', '*182*1*1*{recipient}*{amount}#', '*182*1*1*{recipient}*{amount}#', '*182*8*1*{recipient}*{amount}#', '["Rwanda"]'::jsonb, '["mtn_rwanda", "mtn", "mtn rwanda"]'::jsonb, '^(?:7[237-9]\d{7})$', ARRAY[9]::integer[], '0720 123 456', '+250720123456', '^(?:0)?(?:7[237-9]\d{7})$', '^\+250(?:7[237-9]\d{7})$', '^\*182\*1\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*182*1*1*720123456*5000#', 'merchant_code', '^[0-9]{6}$', 6, 6, '123456', '^\*182\*8\*1\*[0-9]{6}\*[1-9][0-9]{0,11}\#$', '*182*8*1*123456*5000#', 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is a mobile MSISDN routed via *182*1*1*. Merchant code is a separate MTN MoMo Pay merchant identifier routed via *182*8*1* and validated separately from phone numbers.'),
  ('ZA', '+27', 'South Africa', '🇿🇦', 'ZAR', 'South African rand', 'momo_za', '*120*668*1*{recipient}*{amount}#', '*120*668*1*{recipient}*{amount}#', null, '["South Africa"]'::jsonb, '[]'::jsonb, '^(?:(?:1(?:3492[0-25]|4495[0235]|549(?:20|5[01]))|4[34]492[01])\d{3}|8[1-4]\d{3,7}|(?:2[27]|47|54)4950\d{3}|(?:1(?:049[2-4]|9[12]\d\d)|(?:50[0-2]|[67]\d\d)\d\d|8(?:5\d{3}|7(?:08[67]|158|28[5-9]|310)))\d{4}|(?:1[6-8]|28|3[2-69]|4[025689]|5[36-8])4920\d{3}|(?:12|[2-5]1)492\d{4})$', ARRAY[5, 6, 7, 8, 9]::integer[], '071 123 4567', '+27711234567', '^(?:0)?(?:(?:1(?:3492[0-25]|4495[0235]|549(?:20|5[01]))|4[34]492[01])\d{3}|8[1-4]\d{3,7}|(?:2[27]|47|54)4950\d{3}|(?:1(?:049[2-4]|9[12]\d\d)|(?:50[0-2]|[67]\d\d)\d\d|8(?:5\d{3}|7(?:08[67]|158|28[5-9]|310)))\d{4}|(?:1[6-8]|28|3[2-69]|4[025689]|5[36-8])4920\d{3}|(?:12|[2-5]1)492\d{4})$', '^\+27(?:(?:1(?:3492[0-25]|4495[0235]|549(?:20|5[01]))|4[34]492[01])\d{3}|8[1-4]\d{3,7}|(?:2[27]|47|54)4950\d{3}|(?:1(?:049[2-4]|9[12]\d\d)|(?:50[0-2]|[67]\d\d)\d\d|8(?:5\d{3}|7(?:08[67]|158|28[5-9]|310)))\d{4}|(?:1[6-8]|28|3[2-69]|4[025689]|5[36-8])4920\d{3}|(?:12|[2-5]1)492\d{4})$', '^\*120\*668\*1\*[0-9]{5,9}\*[1-9][0-9]{0,11}\#$', '*120*668*1*711234567*10000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('SZ', '+268', 'Eswatini', '🇸🇿', 'SZL', 'Swazi lilangeni', 'momo_sz', '*468*1*{recipient}*{amount}#', '*468*1*{recipient}*{amount}#', null, '["Eswatini", "Swaziland", "Eswatini (Swaziland)"]'::jsonb, '[]'::jsonb, '^(?:7[5-9]\d{6})$', ARRAY[8]::integer[], '7612 3456', '+26876123456', '^(?:7[5-9]\d{6})$', '^\+268(?:7[5-9]\d{6})$', '^\*468\*1\*[0-9]{8}\*[1-9][0-9]{0,11}\#$', '*468*1*76123456*2000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('UG', '+256', 'Uganda', '🇺🇬', 'UGX', 'Ugandan shilling', 'momo_ug', '*165*1*{recipient}*{amount}#', '*165*1*{recipient}*{amount}#', null, '["Uganda"]'::jsonb, '["airtel"]'::jsonb, '^(?:72[48]0\d{5}|7(?:[014-8]\d|2[0167]|3[06]|9[0-3589])\d{6})$', ARRAY[9]::integer[], '0712 345678', '+256712345678', '^(?:0)?(?:72[48]0\d{5}|7(?:[014-8]\d|2[0167]|3[06]|9[0-3589])\d{6})$', '^\+256(?:72[48]0\d{5}|7(?:[014-8]\d|2[0167]|3[06]|9[0-3589])\d{6})$', '^\*165\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*165*1*712345678*4000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('ZM', '+260', 'Zambia', '🇿🇲', 'ZMW', 'Zambian kwacha', 'momo_zm', '*303*1*{recipient}*{amount}#', '*303*1*{recipient}*{amount}#', null, '["Zambia"]'::jsonb, '[]'::jsonb, '^(?:(?:[59][5-8]|7[5-9])\d{7})$', ARRAY[9]::integer[], '095 5123456', '+260955123456', '^(?:0)?(?:(?:[59][5-8]|7[5-9])\d{7})$', '^\+260(?:(?:[59][5-8]|7[5-9])\d{7})$', '^\*303\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*303*1*955123456*3000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('ZW', '+263', 'Zimbabwe', '🇿🇼', 'ZWL', 'Zimbabwean dollar', 'momo_zw', '*151*1*{recipient}*{amount}#', '*151*1*{recipient}*{amount}#', null, '["Zimbabwe"]'::jsonb, '[]'::jsonb, '^(?:7(?:[1278]\d|3[1-9])\d{6})$', ARRAY[9]::integer[], '071 234 5678', '+263712345678', '^(?:0)?(?:7(?:[1278]\d|3[1-9])\d{6})$', '^\+263(?:7(?:[1278]\d|3[1-9])\d{6})$', '^\*151\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*151*1*712345678*7000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('CD', '+243', 'Democratic Republic of the Congo', '🇨🇩', 'CDF', 'Congolese franc', 'momo_cd', '*099*1*{recipient}*{amount}#', '*099*1*{recipient}*{amount}#', null, '["Democratic Republic of the Congo", "DRC", "Democratic Republic of Congo (DRC)", "Congo Kinshasa"]'::jsonb, '[]'::jsonb, '^(?:88\d{5}|(?:8[0-69]|9[016-9])\d{7})$', ARRAY[7, 9]::integer[], '0991 234 567', '+243991234567', '^(?:0)?(?:88\d{5}|(?:8[0-69]|9[016-9])\d{7})$', '^\+243(?:88\d{5}|(?:8[0-69]|9[016-9])\d{7})$', '^\*099\*1\*[0-9]{7,9}\*[1-9][0-9]{0,11}\#$', '*099*1*991234567*4500#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('ET', '+251', 'Ethiopia', '🇪🇹', 'ETB', 'Ethiopian birr', 'momo_et', '*806*1*{recipient}*{amount}#', '*806*1*{recipient}*{amount}#', null, '["Ethiopia"]'::jsonb, '[]'::jsonb, '^(?:700[1-9]\d{5}|(?:7(?:0[1-9]|1[0-8]|2[1-35-79]|3\d|77|86|99)|9\d\d)\d{6})$', ARRAY[9]::integer[], '091 123 4567', '+251911234567', '^(?:0)?(?:700[1-9]\d{5}|(?:7(?:0[1-9]|1[0-8]|2[1-35-79]|3\d|77|86|99)|9\d\d)\d{6})$', '^\+251(?:700[1-9]\d{5}|(?:7(?:0[1-9]|1[0-8]|2[1-35-79]|3\d|77|86|99)|9\d\d)\d{6})$', '^\*806\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*806*1*911234567*5000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('GA', '+241', 'Gabon', '🇬🇦', 'XAF', 'Central African CFA franc', 'momo_ga', '*222*1*{recipient}*{amount}#', '*222*1*{recipient}*{amount}#', null, '["Gabon"]'::jsonb, '[]'::jsonb, '^(?:(?:(?:0[2-7]|7[467])\d|6(?:0[0-4]|10|[256]\d))\d{5}|[2-7]\d{6})$', ARRAY[7, 8]::integer[], '06 03 12 34', '+24106031234', '^(?:(?:(?:0[2-7]|7[467])\d|6(?:0[0-4]|10|[256]\d))\d{5}|[2-7]\d{6})$', '^\+241(?:(?:(?:0[2-7]|7[467])\d|6(?:0[0-4]|10|[256]\d))\d{5}|[2-7]\d{6})$', '^\*222\*1\*[0-9]{6,7}\*[1-9][0-9]{0,11}\#$', '*222*1*6031234*3500#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('MG', '+261', 'Madagascar', '🇲🇬', 'MGA', 'Malagasy ariary', 'momo_mg', '*162*1*{recipient}*{amount}#', '*162*1*{recipient}*{amount}#', null, '["Madagascar"]'::jsonb, '[]'::jsonb, '^(?:3[2-9]\d{7})$', ARRAY[9]::integer[], '032 12 345 67', '+261321234567', '^(?:0)?(?:3[2-9]\d{7})$', '^\+261(?:3[2-9]\d{7})$', '^\*162\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*162*1*321234567*4000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('SN', '+221', 'Senegal', '🇸🇳', 'XOF', 'West African CFA franc', 'momo_sn', '*140*1*{recipient}*{amount}#', '*140*1*{recipient}*{amount}#', null, '["Senegal"]'::jsonb, '[]'::jsonb, '^(?:7(?:[015-8]\d|21|90)\d{6})$', ARRAY[9]::integer[], '70 123 45 67', '+221701234567', '^(?:7(?:[015-8]\d|21|90)\d{6})$', '^\+221(?:7(?:[015-8]\d|21|90)\d{6})$', '^\*140\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*140*1*701234567*6000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('SL', '+232', 'Sierra Leone', '🇸🇱', 'SLL', 'Sierra Leonean leone', 'momo_sl', '*277*1*{recipient}*{amount}#', '*277*1*{recipient}*{amount}#', null, '["Sierra Leone"]'::jsonb, '[]'::jsonb, '^(?:(?:25|3[0-5]|66|7\d|8[08]|9[09])\d{6})$', ARRAY[8]::integer[], '(025) 123456', '+23225123456', '^(?:0)?(?:(?:25|3[0-5]|66|7\d|8[08]|9[09])\d{6})$', '^\+232(?:(?:25|3[0-5]|66|7\d|8[08]|9[09])\d{6})$', '^\*277\*1\*[0-9]{8}\*[1-9][0-9]{0,11}\#$', '*277*1*25123456*2000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.'),
  ('TZ', '+255', 'Tanzania', '🇹🇿', 'TZS', 'Tanzanian shilling', 'momo_tz', '*150*00*1*{recipient}*{amount}#', '*150*00*1*{recipient}*{amount}#', null, '["Tanzania"]'::jsonb, '[]'::jsonb, '^(?:(?:6[1-35-9]|7[013-9])\d{7})$', ARRAY[9]::integer[], '0621 234 567', '+255621234567', '^(?:0)?(?:(?:6[1-35-9]|7[013-9])\d{7})$', '^\+255(?:(?:6[1-35-9]|7[013-9])\d{7})$', '^\*150\*00\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$', '*150*00*1*621234567*5000#', null, null, null, null, null, null, null, 'google/libphonenumber mobile metadata', 'business-configured operator USSD matrix', 'MoMo number is validated as a country-specific mobile MSISDN. Merchant code is a separate recipient type and is only enabled where a dedicated code route is configured.')
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
