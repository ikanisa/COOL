-- ==========================================================================
-- Cool App — Server-side MoMo validation and normalization
-- ==========================================================================
-- Enforces country-aware MoMo normalization in SQL so invalid writes cannot
-- bypass the Flutter client. This migration targets the tables that exist in
-- this repo today:
--   - public.users
--   - public.groups
--
-- Distinction enforced here:
--   - MoMo number: a mobile MSISDN validated and normalized to E.164.
--   - MoMo code: a merchant/payment code validated separately and only where
--     a dedicated code route is configured for the country.
-- ==========================================================================

create or replace function public.get_supported_country_momo_config(
  p_country text
)
returns public.supported_countries
language sql
stable
set search_path = public
as $$
  select sc.*
  from public.supported_countries sc
  where sc.iso_code = public.normalize_country_code(p_country)
    and sc.is_active = true
  limit 1
$$;

create or replace function public.normalize_momo_phone_for_country(
  p_country text,
  p_value text
)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_country public.supported_countries;
  v_trimmed text := btrim(coalesce(p_value, ''));
  v_digits text;
  v_plus_candidate text;
  v_dial_digits text;
  v_local_pattern text;
  v_keep_nsn_leading_zero boolean := false;
  v_local_digits text;
begin
  if v_trimmed = '' then
    return null;
  end if;

  select *
  into v_country
  from public.get_supported_country_momo_config(p_country);

  if v_country.iso_code is null then
    raise exception 'Unsupported country code for MoMo validation: %',
      coalesce(nullif(btrim(coalesce(p_country, '')), ''), '(blank)');
  end if;

  v_digits := regexp_replace(v_trimmed, '[^0-9]', '', 'g');
  if v_digits = '' then
    raise exception 'Phone number is required.';
  end if;

  v_plus_candidate := '+' || v_digits;
  v_dial_digits := replace(v_country.dial_code, '+', '');
  v_local_pattern := coalesce(
    nullif(v_country.momo_number_local_pattern, ''),
    nullif(v_country.mobile_national_number_pattern, '')
  );
  v_keep_nsn_leading_zero := regexp_replace(
    coalesce(v_country.mobile_example_e164, ''),
    '[^0-9]',
    '',
    'g'
  ) like v_dial_digits || '0%';

  if coalesce(v_country.momo_number_e164_pattern, '') <> ''
     and v_plus_candidate ~ v_country.momo_number_e164_pattern then
    return v_plus_candidate;
  end if;

  if coalesce(v_local_pattern, '') <> ''
     and v_digits ~ v_local_pattern then
    v_local_digits := v_digits;
    if not v_keep_nsn_leading_zero and left(v_local_digits, 1) = '0' then
      v_local_digits := regexp_replace(v_local_digits, '^0', '');
    end if;
    return v_country.dial_code || v_local_digits;
  end if;

  if left(v_digits, length(v_dial_digits)) = v_dial_digits then
    if coalesce(v_country.momo_number_e164_pattern, '') <> ''
       and v_plus_candidate ~ v_country.momo_number_e164_pattern then
      return v_plus_candidate;
    end if;

    v_local_digits := substr(v_digits, length(v_dial_digits) + 1);
    if coalesce(v_local_pattern, '') <> ''
       and v_local_digits ~ v_local_pattern then
      if not v_keep_nsn_leading_zero and left(v_local_digits, 1) = '0' then
        v_local_digits := regexp_replace(v_local_digits, '^0', '');
      end if;
      return v_country.dial_code || v_local_digits;
    end if;
  end if;

  if coalesce(array_length(v_country.mobile_possible_lengths, 1), 0) > 0
     and not (char_length(v_digits) = any(v_country.mobile_possible_lengths)) then
    raise exception 'Enter a valid % mobile money number.', v_country.country_name;
  end if;

  raise exception 'Enter a valid % mobile money number.', v_country.country_name;
end;
$$;

create or replace function public.is_valid_momo_phone_for_country(
  p_country text,
  p_value text
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
begin
  if nullif(btrim(coalesce(p_value, '')), '') is null then
    return false;
  end if;

  perform public.normalize_momo_phone_for_country(p_country, p_value);
  return true;
exception
  when others then
    return false;
end;
$$;

create or replace function public.normalize_momo_code_for_country(
  p_country text,
  p_value text
)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_country public.supported_countries;
  v_trimmed text := btrim(coalesce(p_value, ''));
  v_digits text;
begin
  if v_trimmed = '' then
    return null;
  end if;

  select *
  into v_country
  from public.get_supported_country_momo_config(p_country);

  if v_country.iso_code is null then
    raise exception 'Unsupported country code for MoMo validation: %',
      coalesce(nullif(btrim(coalesce(p_country, '')), ''), '(blank)');
  end if;

  if coalesce(nullif(v_country.momo_code_ussd_template, ''), '') = '' then
    raise exception 'Merchant-code payments are not configured for %.',
      v_country.country_name;
  end if;

  v_digits := regexp_replace(v_trimmed, '[^0-9]', '', 'g');
  if v_digits = '' then
    raise exception 'Merchant code is required.';
  end if;

  if coalesce(v_country.momo_code_pattern, '') <> ''
     and not (v_digits ~ v_country.momo_code_pattern) then
    raise exception 'Enter a valid merchant code for %.', v_country.country_name;
  end if;

  if v_country.momo_code_min_length is not null
     and char_length(v_digits) < v_country.momo_code_min_length then
    raise exception 'Merchant code is too short for %.', v_country.country_name;
  end if;

  if v_country.momo_code_max_length is not null
     and char_length(v_digits) > v_country.momo_code_max_length then
    raise exception 'Merchant code is too long for %.', v_country.country_name;
  end if;

  return v_digits;
end;
$$;

create or replace function public.is_valid_momo_code_for_country(
  p_country text,
  p_value text
)
returns boolean
language plpgsql
stable
set search_path = public
as $$
begin
  if nullif(btrim(coalesce(p_value, '')), '') is null then
    return false;
  end if;

  perform public.normalize_momo_code_for_country(p_country, p_value);
  return true;
exception
  when others then
    return false;
end;
$$;

create or replace function public.infer_momo_route_type_for_country(
  p_country text,
  p_value text
)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_country public.supported_countries;
  v_trimmed text := btrim(coalesce(p_value, ''));
  v_digits text;
  v_dial_digits text;
begin
  if v_trimmed = '' then
    return null;
  end if;

  if public.is_valid_momo_phone_for_country(p_country, v_trimmed) then
    return 'phone_number';
  end if;

  if public.is_valid_momo_code_for_country(p_country, v_trimmed) then
    return 'code';
  end if;

  select *
  into v_country
  from public.get_supported_country_momo_config(p_country);

  if v_country.iso_code is null then
    return null;
  end if;

  v_digits := regexp_replace(v_trimmed, '[^0-9]', '', 'g');
  v_dial_digits := replace(v_country.dial_code, '+', '');

  if left(v_trimmed, 1) = '+'
     or left(v_trimmed, 1) = '0'
     or left(v_digits, length(v_dial_digits)) = v_dial_digits
     or char_length(v_digits) >= 9 then
    return 'phone_number';
  end if;

  return 'code';
end;
$$;

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

  return new;
end;
$$;

drop trigger if exists trg_enforce_user_momo_fields on public.users;
create trigger trg_enforce_user_momo_fields
  before insert or update on public.users
  for each row
  execute function public.enforce_user_momo_fields();

create or replace function public.enforce_group_momo_fields()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_route_type text;
  v_recipient text;
begin
  new.country := public.normalize_country_code(
    coalesce(nullif(btrim(coalesce(new.country, '')), ''), 'RW')
  );
  new.type := coalesce(nullif(lower(btrim(coalesce(new.type, ''))), ''), 'saving');
  new.momo_number := nullif(btrim(coalesce(new.momo_number, '')), '');
  new.receiving_momo_code := nullif(
    btrim(coalesce(new.receiving_momo_code, '')),
    ''
  );
  new.receiving_momo_route_type := nullif(
    lower(btrim(coalesce(new.receiving_momo_route_type, ''))),
    ''
  );

  if new.receiving_momo_code is null and new.momo_number is not null then
    new.receiving_momo_code := new.momo_number;
  end if;

  if new.receiving_momo_route_type is null
     and new.receiving_momo_code is not null then
    new.receiving_momo_route_type := public.infer_momo_route_type_for_country(
      new.country,
      new.receiving_momo_code
    );
  end if;

  if new.type = 'community'
     and new.receiving_momo_code is null
     and new.momo_number is null then
    raise exception 'Community groups require a MoMo number or merchant code.';
  end if;

  v_route_type := new.receiving_momo_route_type;
  if v_route_type is null and new.momo_number is not null then
    v_route_type := 'phone_number';
  end if;

  if v_route_type is null then
    return new;
  end if;

  if v_route_type not in ('phone_number', 'code') then
    raise exception 'Unsupported receiving_momo_route_type: %', v_route_type;
  end if;

  v_recipient := coalesce(new.receiving_momo_code, new.momo_number);
  if v_recipient is null then
    raise exception 'A MoMo recipient is required for route type %.', v_route_type;
  end if;

  if v_route_type = 'phone_number' then
    v_recipient := public.normalize_momo_phone_for_country(
      new.country,
      v_recipient
    );
    new.momo_number := v_recipient;
    new.receiving_momo_code := v_recipient;
    new.receiving_momo_route_type := 'phone_number';
  else
    v_recipient := public.normalize_momo_code_for_country(
      new.country,
      v_recipient
    );
    new.momo_number := null;
    new.receiving_momo_code := v_recipient;
    new.receiving_momo_route_type := 'code';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_group_momo_fields on public.groups;
create trigger trg_enforce_group_momo_fields
  before insert or update on public.groups
  for each row
  execute function public.enforce_group_momo_fields();

-- Best-effort cleanup for existing rows. Values are only rewritten when they
-- can be normalized safely under the new country rules.
-- Temporarily disable the trigger so it doesn't reject invalid existing data.
alter table public.users disable trigger trg_enforce_user_momo_fields;

update public.users u
set
  country = public.normalize_country_code(u.country),
  momo_number = case
    when nullif(btrim(coalesce(u.momo_number, '')), '') is null then null
    when public.is_valid_momo_phone_for_country(u.country, u.momo_number) then
      public.normalize_momo_phone_for_country(u.country, u.momo_number)
    else u.momo_number
  end,
  momo_code = case
    when nullif(btrim(coalesce(u.momo_code, '')), '') is null then null
    when public.is_valid_momo_code_for_country(u.country, u.momo_code) then
      public.normalize_momo_code_for_country(u.country, u.momo_code)
    else u.momo_code
  end,
  momo_provider = case
    when nullif(btrim(coalesce(u.momo_provider, '')), '') is not null then
      u.momo_provider
    else coalesce(
      (
        select sc.momo_provider_id
        from public.supported_countries sc
        where sc.iso_code = public.normalize_country_code(u.country)
          and sc.is_active = true
      ),
      u.momo_provider
    )
  end
where true;

alter table public.users enable trigger trg_enforce_user_momo_fields;

alter table public.groups disable trigger trg_enforce_group_momo_fields;

update public.groups g
set
  country = public.normalize_country_code(g.country),
  receiving_momo_route_type = case
    when public.is_valid_momo_phone_for_country(
      g.country,
      coalesce(g.receiving_momo_code, g.momo_number)
    ) then
      'phone_number'
    when public.is_valid_momo_code_for_country(
      g.country,
      coalesce(g.receiving_momo_code, g.momo_number)
    ) then
      'code'
    when nullif(btrim(coalesce(g.receiving_momo_route_type, '')), '') is not null then
      lower(btrim(g.receiving_momo_route_type))
    when nullif(btrim(coalesce(g.receiving_momo_code, '')), '') is not null then
      public.infer_momo_route_type_for_country(g.country, g.receiving_momo_code)
    when nullif(btrim(coalesce(g.momo_number, '')), '') is not null then
      'phone_number'
    else null
  end,
  receiving_momo_code = case
    when (
      case
        when public.is_valid_momo_phone_for_country(
          g.country,
          coalesce(g.receiving_momo_code, g.momo_number)
        ) then
          'phone_number'
        when public.is_valid_momo_code_for_country(
          g.country,
          coalesce(g.receiving_momo_code, g.momo_number)
        ) then
          'code'
        when nullif(btrim(coalesce(g.receiving_momo_route_type, '')), '') is not null then
          lower(btrim(g.receiving_momo_route_type))
        else public.infer_momo_route_type_for_country(
          g.country,
          coalesce(g.receiving_momo_code, g.momo_number)
        )
      end
    ) = 'code'
      and public.is_valid_momo_code_for_country(
        g.country,
        coalesce(g.receiving_momo_code, g.momo_number)
      ) then
        public.normalize_momo_code_for_country(
          g.country,
          coalesce(g.receiving_momo_code, g.momo_number)
        )
    when public.is_valid_momo_phone_for_country(
      g.country,
      coalesce(g.receiving_momo_code, g.momo_number)
    ) then
      public.normalize_momo_phone_for_country(
        g.country,
        coalesce(g.receiving_momo_code, g.momo_number)
      )
    else g.receiving_momo_code
  end,
  momo_number = case
    when (
      case
        when public.is_valid_momo_phone_for_country(
          g.country,
          coalesce(g.receiving_momo_code, g.momo_number)
        ) then
          'phone_number'
        when public.is_valid_momo_code_for_country(
          g.country,
          coalesce(g.receiving_momo_code, g.momo_number)
        ) then
          'code'
        when nullif(btrim(coalesce(g.receiving_momo_route_type, '')), '') is not null then
          lower(btrim(g.receiving_momo_route_type))
        else public.infer_momo_route_type_for_country(
          g.country,
          coalesce(g.receiving_momo_code, g.momo_number)
        )
      end
    ) = 'code' then
      null
    when public.is_valid_momo_phone_for_country(
      g.country,
      coalesce(g.momo_number, g.receiving_momo_code)
    ) then
      public.normalize_momo_phone_for_country(
        g.country,
        coalesce(g.momo_number, g.receiving_momo_code)
      )
    else g.momo_number
  end
where true;

alter table public.groups enable trigger trg_enforce_group_momo_fields;
