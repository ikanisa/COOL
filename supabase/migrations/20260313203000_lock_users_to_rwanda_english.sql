-- ==========================================================================
-- Lock user profiles to the Rwanda market and English UI
-- ==========================================================================

update public.users
set
  country = 'RW',
  language_code = 'en'
where
  country is distinct from 'RW'
  or language_code is distinct from 'en';

update auth.users
set raw_user_meta_data =
  coalesce(raw_user_meta_data, '{}'::jsonb) ||
  jsonb_build_object(
    'country', 'RW',
    'language_code', 'en',
    'market', 'RW',
    'ui_language', 'en'
  )
where
  coalesce(raw_user_meta_data->>'country', '') is distinct from 'RW'
  or coalesce(raw_user_meta_data->>'language_code', '') is distinct from 'en'
  or coalesce(raw_user_meta_data->>'market', '') is distinct from 'RW'
  or coalesce(raw_user_meta_data->>'ui_language', '') is distinct from 'en';

create or replace function public.enforce_user_momo_fields()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_country public.supported_countries;
begin
  new.country := 'RW';
  new.language_code := 'en';
  new.momo_number := nullif(btrim(coalesce(new.momo_number, '')), '');
  new.momo_code := nullif(btrim(coalesce(new.momo_code, '')), '');
  new.momo_route_type := nullif(
    lower(btrim(coalesce(new.momo_route_type, ''))),
    ''
  );
  new.momo_provider := coalesce(new.momo_provider, '');

  if new.momo_number is not null then
    new.momo_number := public.normalize_momo_phone_for_country(
      new.country,
      new.momo_number
    );
  end if;

  if new.momo_code is not null then
    new.momo_code := public.normalize_momo_code_for_country(
      new.country,
      new.momo_code
    );
  end if;

  if btrim(new.momo_provider) = '' then
    select *
    into v_country
    from public.get_supported_country_momo_config(new.country);

    if v_country.iso_code is not null then
      new.momo_provider := coalesce(v_country.momo_provider_id, '');
    end if;
  end if;

  if new.momo_route_type = 'phone_number' then
    if new.momo_number is null then
      raise exception using
        errcode = '23514',
        message = 'momo_route_type phone_number requires momo_number';
    end if;
  elsif new.momo_route_type = 'code' then
    if new.momo_code is null then
      raise exception using
        errcode = '23514',
        message = 'momo_route_type code requires momo_code';
    end if;
  elsif new.momo_number is not null then
    new.momo_route_type := 'phone_number';
  elsif new.momo_code is not null then
    new.momo_route_type := 'code';
  else
    new.momo_route_type := null;
  end if;

  return new;
end;
$$;
