-- ==========================================================================
-- Preserve explicit user wallet route preferences
-- ==========================================================================

create or replace function public.enforce_user_momo_fields()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_country public.supported_countries;
begin
  new.country := public.normalize_country_code(
    coalesce(nullif(btrim(coalesce(new.country, '')), ''), 'RW')
  );
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
