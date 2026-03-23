-- ==========================================================================
-- Cool App — MoMo validation reference and audit views
-- ==========================================================================
-- supported_country_momo_reference:
--   Public, read-only country metadata for admin panels and client reference.
-- momo_validation_issues:
--   Admin/service-side audit surface for legacy or imported records that do
--   not satisfy the country-aware MoMo validation rules.
-- ==========================================================================

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
comment on view public.supported_country_momo_reference is
  'Read-only country reference for MoMo number validation, merchant-code support, and country-specific USSD examples.';
grant select on table public.supported_country_momo_reference
  to anon, authenticated;
create or replace view public.momo_validation_issues as
with country_reference as (
  select *
  from public.supported_countries
  where is_active = true
),
user_candidates as (
  select
    u.id as record_id,
    u.country as raw_country,
    public.normalize_country_code(u.country) as normalized_country,
    nullif(btrim(coalesce(u.momo_number, '')), '') as momo_number,
    nullif(btrim(coalesce(u.momo_code, '')), '') as momo_code,
    sc.country_name,
    sc.mobile_example_e164,
    sc.momo_code_example,
    sc.momo_number_ussd_example,
    sc.momo_code_ussd_example
  from public.users u
  left join country_reference sc
    on sc.iso_code = public.normalize_country_code(u.country)
),
group_candidates as (
  select
    g.id as record_id,
    g.type as group_type,
    g.country as raw_country,
    public.normalize_country_code(g.country) as normalized_country,
    nullif(lower(btrim(coalesce(g.receiving_momo_route_type, ''))), '') as route_type,
    nullif(btrim(coalesce(g.momo_number, '')), '') as momo_number,
    nullif(btrim(coalesce(g.receiving_momo_code, '')), '') as receiving_momo_code,
    coalesce(
      nullif(btrim(coalesce(g.receiving_momo_code, '')), ''),
      nullif(btrim(coalesce(g.momo_number, '')), '')
    ) as effective_recipient,
    case
      when nullif(lower(btrim(coalesce(g.receiving_momo_route_type, ''))), '') in ('phone_number', 'code') then
        nullif(lower(btrim(coalesce(g.receiving_momo_route_type, ''))), '')
      when coalesce(
        nullif(btrim(coalesce(g.receiving_momo_code, '')), ''),
        nullif(btrim(coalesce(g.momo_number, '')), '')
      ) is not null then
        public.infer_momo_route_type_for_country(
          g.country,
          coalesce(
            nullif(btrim(coalesce(g.receiving_momo_code, '')), ''),
            nullif(btrim(coalesce(g.momo_number, '')), '')
          )
        )
      else null
    end as effective_route_type,
    sc.country_name,
    sc.mobile_example_e164,
    sc.momo_code_example,
    sc.momo_number_ussd_example,
    sc.momo_code_ussd_example
  from public.groups g
  left join country_reference sc
    on sc.iso_code = public.normalize_country_code(g.country)
)
select
  'user'::text as record_type,
  uc.record_id,
  uc.raw_country as country,
  uc.country_name,
  null::text as route_type,
  'unsupported_country'::text as issue_code,
  format(
    'User country %s is not configured in supported_countries.',
    coalesce(nullif(uc.raw_country, ''), '(blank)')
  ) as issue_message,
  uc.momo_number,
  uc.momo_code,
  uc.mobile_example_e164 as expected_phone_example,
  uc.momo_code_example as expected_code_example,
  uc.momo_number_ussd_example as phone_ussd_example,
  uc.momo_code_ussd_example as code_ussd_example
from user_candidates uc
where uc.country_name is null

union all

select
  'user'::text as record_type,
  uc.record_id,
  uc.raw_country as country,
  uc.country_name,
  null::text as route_type,
  'invalid_momo_number'::text as issue_code,
  format('User MoMo number is invalid for %s.', uc.country_name) as issue_message,
  uc.momo_number,
  uc.momo_code,
  uc.mobile_example_e164 as expected_phone_example,
  uc.momo_code_example as expected_code_example,
  uc.momo_number_ussd_example as phone_ussd_example,
  uc.momo_code_ussd_example as code_ussd_example
from user_candidates uc
where uc.country_name is not null
  and uc.momo_number is not null
  and not public.is_valid_momo_phone_for_country(
    uc.normalized_country,
    uc.momo_number
  )

union all

select
  'user'::text as record_type,
  uc.record_id,
  uc.raw_country as country,
  uc.country_name,
  null::text as route_type,
  'invalid_momo_code'::text as issue_code,
  format('User merchant code is invalid or unsupported for %s.', uc.country_name) as issue_message,
  uc.momo_number,
  uc.momo_code,
  uc.mobile_example_e164 as expected_phone_example,
  uc.momo_code_example as expected_code_example,
  uc.momo_number_ussd_example as phone_ussd_example,
  uc.momo_code_ussd_example as code_ussd_example
from user_candidates uc
where uc.country_name is not null
  and uc.momo_code is not null
  and not public.is_valid_momo_code_for_country(
    uc.normalized_country,
    uc.momo_code
  )

union all

select
  'group'::text as record_type,
  gc.record_id,
  gc.raw_country as country,
  gc.country_name,
  gc.route_type,
  'unsupported_country'::text as issue_code,
  format(
    'Group country %s is not configured in supported_countries.',
    coalesce(nullif(gc.raw_country, ''), '(blank)')
  ) as issue_message,
  gc.momo_number,
  gc.receiving_momo_code as momo_code,
  gc.mobile_example_e164 as expected_phone_example,
  gc.momo_code_example as expected_code_example,
  gc.momo_number_ussd_example as phone_ussd_example,
  gc.momo_code_ussd_example as code_ussd_example
from group_candidates gc
where gc.country_name is null

union all

select
  'group'::text as record_type,
  gc.record_id,
  gc.raw_country as country,
  gc.country_name,
  gc.route_type,
  'missing_community_recipient'::text as issue_code,
  'Community group is missing both MoMo number and merchant-code recipient.' as issue_message,
  gc.momo_number,
  gc.receiving_momo_code as momo_code,
  gc.mobile_example_e164 as expected_phone_example,
  gc.momo_code_example as expected_code_example,
  gc.momo_number_ussd_example as phone_ussd_example,
  gc.momo_code_ussd_example as code_ussd_example
from group_candidates gc
where gc.country_name is not null
  and lower(coalesce(gc.group_type, '')) = 'community'
  and gc.effective_recipient is null

union all

select
  'group'::text as record_type,
  gc.record_id,
  gc.raw_country as country,
  gc.country_name,
  gc.route_type,
  'unsupported_route_type'::text as issue_code,
  format(
    'Group route type %s must be phone_number or code.',
    gc.route_type
  ) as issue_message,
  gc.momo_number,
  gc.receiving_momo_code as momo_code,
  gc.mobile_example_e164 as expected_phone_example,
  gc.momo_code_example as expected_code_example,
  gc.momo_number_ussd_example as phone_ussd_example,
  gc.momo_code_ussd_example as code_ussd_example
from group_candidates gc
where gc.country_name is not null
  and gc.route_type is not null
  and gc.route_type not in ('phone_number', 'code')

union all

select
  'group'::text as record_type,
  gc.record_id,
  gc.raw_country as country,
  gc.country_name,
  gc.effective_route_type as route_type,
  'invalid_phone_recipient'::text as issue_code,
  format('Group phone-number recipient is invalid for %s.', gc.country_name) as issue_message,
  gc.momo_number,
  gc.receiving_momo_code as momo_code,
  gc.mobile_example_e164 as expected_phone_example,
  gc.momo_code_example as expected_code_example,
  gc.momo_number_ussd_example as phone_ussd_example,
  gc.momo_code_ussd_example as code_ussd_example
from group_candidates gc
where gc.country_name is not null
  and gc.effective_route_type = 'phone_number'
  and gc.effective_recipient is not null
  and not public.is_valid_momo_phone_for_country(
    gc.normalized_country,
    gc.effective_recipient
  )

union all

select
  'group'::text as record_type,
  gc.record_id,
  gc.raw_country as country,
  gc.country_name,
  gc.effective_route_type as route_type,
  'invalid_momo_code'::text as issue_code,
  format('Group merchant-code recipient is invalid or unsupported for %s.', gc.country_name) as issue_message,
  gc.momo_number,
  gc.receiving_momo_code as momo_code,
  gc.mobile_example_e164 as expected_phone_example,
  gc.momo_code_example as expected_code_example,
  gc.momo_number_ussd_example as phone_ussd_example,
  gc.momo_code_ussd_example as code_ussd_example
from group_candidates gc
where gc.country_name is not null
  and gc.effective_route_type = 'code'
  and gc.effective_recipient is not null
  and not public.is_valid_momo_code_for_country(
    gc.normalized_country,
    gc.effective_recipient
  );
comment on view public.momo_validation_issues is
  'Admin/service audit view for users and groups whose MoMo country or recipient data does not satisfy the current validation rules.';
revoke all on table public.momo_validation_issues
  from anon, authenticated;
