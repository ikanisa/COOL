-- ============================================================================
-- Cool App - repair group RPC drift and Rwanda MoMo validation
-- ============================================================================
-- Production was carrying:
--   1. stale create_group_atomic overloads, including one that references
--      public.users.display_name even though that column no longer exists.
--   2. supported_countries regex metadata stored in mixed libphonenumber and
--      hosted-hotfix formats (\d shorthand and doubled escapes), which breaks
--      Postgres-side Rwanda MoMo validation for valid numbers.
--
-- This migration collapses create_group_atomic back to a single safe signature
-- and normalizes regex use at runtime so existing rows become usable again.
-- ============================================================================

alter table public.groups
  add column if not exists bank_partner_id uuid references public.partners(id);

create or replace function public.normalize_momo_validation_pattern(
  p_pattern text
)
returns text
language sql
immutable
set search_path = public
as $$
  select case
    when nullif(p_pattern, '') is null then null
    else replace(
      replace(
        replace(
          replace(
            replace(
              replace(
                replace(
                  replace(p_pattern, E'\\\\d', '[0-9]'),
                  E'\\d', '[0-9]'
                ),
                E'\\\\D', '[^0-9]'
              ),
              E'\\D', '[^0-9]'
            ),
            E'\\\\+', E'\\+'
          ),
          E'\\\\*', E'\\*'
        ),
        E'\\\\#', '#'
      ),
      E'\\\\ ', E'\\s'
    )
  end
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
  v_e164_pattern text;
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
    nullif(
      public.normalize_momo_validation_pattern(
        v_country.momo_number_local_pattern
      ),
      ''
    ),
    nullif(
      public.normalize_momo_validation_pattern(
        v_country.mobile_national_number_pattern
      ),
      ''
    )
  );
  v_e164_pattern := nullif(
    public.normalize_momo_validation_pattern(v_country.momo_number_e164_pattern),
    ''
  );
  v_keep_nsn_leading_zero := regexp_replace(
    coalesce(v_country.mobile_example_e164, ''),
    '[^0-9]',
    '',
    'g'
  ) like v_dial_digits || '0%';

  if v_e164_pattern is not null
     and v_plus_candidate ~ v_e164_pattern then
    return v_plus_candidate;
  end if;

  if v_local_pattern is not null
     and v_digits ~ v_local_pattern then
    v_local_digits := v_digits;
    if not v_keep_nsn_leading_zero and left(v_local_digits, 1) = '0' then
      v_local_digits := regexp_replace(v_local_digits, '^0', '');
    end if;
    return v_country.dial_code || v_local_digits;
  end if;

  if left(v_digits, length(v_dial_digits)) = v_dial_digits then
    if v_e164_pattern is not null
       and v_plus_candidate ~ v_e164_pattern then
      return v_plus_candidate;
    end if;

    v_local_digits := substr(v_digits, length(v_dial_digits) + 1);
    if v_local_pattern is not null
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

update public.supported_countries
set
  mobile_national_number_pattern = '^(?:7[237-9][0-9]{7})$',
  mobile_example_national = '0788 123 456',
  mobile_example_e164 = '+250788123456',
  momo_number_local_pattern = '^(?:0)?(?:7[237-9][0-9]{7})$',
  momo_number_e164_pattern = '^\+250(?:7[237-9][0-9]{7})$',
  momo_number_ussd_regex = '^\*182\*1\*1\*[0-9]{9}\*[1-9][0-9]{0,11}\#$',
  momo_number_ussd_example = '*182*1*1*788123456*5000#',
  momo_code_kind = 'merchant_code',
  momo_code_pattern = '^[0-9]{6}$',
  momo_code_min_length = 6,
  momo_code_max_length = 6,
  momo_code_example = '123456',
  momo_code_ussd_regex = '^\*182\*8\*1\*[0-9]{6}\*[1-9][0-9]{0,11}\#$',
  momo_code_ussd_example = '*182*8*1*123456*5000#',
  updated_at = now()
where iso_code = 'RW';

create or replace function public.is_whatsapp_otp_verified_user(
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
      from auth.users au
     where au.id = p_user_id
       and (
         coalesce(nullif(btrim(au.raw_user_meta_data->>'auth_strategy'), ''), '') =
           'custom_whatsapp_otp'
         or nullif(btrim(coalesce(au.raw_user_meta_data->>'phone', '')), '') is not null
         or nullif(btrim(coalesce(au.phone, '')), '') is not null
       )
  );
$$;

drop function if exists public.create_group_atomic(
  text, text, text, text, integer, text, integer, text
);
drop function if exists public.create_group_atomic(
  text, text, text, text, text, integer, integer, integer, text, text, text, text
);
drop function if exists public.create_group_atomic(
  text, text, text, text, text, integer, integer, integer, text, text, text, text, text
);
drop function if exists public.create_group_atomic(
  text, text, text, text, text, bigint, bigint, integer, text, text, text, uuid
);

create or replace function public.create_group_atomic(
  p_name text,
  p_visibility text,
  p_type text,
  p_description text default null,
  p_country text default null,
  p_target_amount integer default 0,
  p_monthly_contribution integer default null,
  p_cycle_days integer default 30,
  p_bank_partner text default null,
  p_momo_number text default null,
  p_receiving_momo_code text default null,
  p_receiving_momo_route_type text default null,
  p_bank_partner_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user public.users;
  v_group public.groups;
  v_invite_code text;
  v_default_country text;
  v_visibility text;
  v_type text;
  v_cycle_days integer;
  v_frequency text;
  v_member_display_name text;
begin
  p_country := nullif(btrim(coalesce(p_country, '')), '');

  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  if not public.is_whatsapp_otp_verified_user(auth.uid()) then
    raise exception 'Verify your WhatsApp number before creating a group.';
  end if;

  select *
    into v_user
    from public.users
   where id = auth.uid();

  if v_user.id is null then
    raise exception 'Complete profile before creating a group.';
  end if;

  v_visibility := coalesce(
    nullif(lower(btrim(coalesce(p_visibility, ''))), ''),
    'private'
  );
  if v_visibility not in ('public', 'private') then
    raise exception 'Invalid group visibility.';
  end if;

  v_type := coalesce(
    nullif(lower(btrim(coalesce(p_type, ''))), ''),
    'saving'
  );
  if v_type not in ('saving', 'community') then
    raise exception 'Invalid group type.';
  end if;

  if v_type = 'community' and v_visibility = 'private' then
    v_cycle_days := 0;
    v_frequency := 'one_off';
  else
    v_cycle_days := greatest(coalesce(p_cycle_days, 30), 1);
    v_frequency := case
      when v_cycle_days <= 1 then 'daily'
      when v_cycle_days <= 7 then 'weekly'
      else 'monthly'
    end;
  end if;

  select value
    into v_default_country
    from public.app_config
   where key = 'default_country';

  v_invite_code := public.generate_group_invite_code();
  v_member_display_name := coalesce(
    nullif(btrim(v_user.public_user_id), ''),
    nullif(btrim(v_user.phone), ''),
    '000000'
  );

  insert into public.groups (
    creator_id,
    name,
    description,
    country,
    visibility,
    type,
    amount,
    target_amount,
    monthly_contribution,
    contribution_amount,
    cycle_days,
    frequency,
    bank_partner,
    bank_partner_id,
    momo_number,
    receiving_momo_code,
    receiving_momo_route_type,
    invite_code
  )
  values (
    auth.uid(),
    nullif(btrim(p_name), ''),
    nullif(btrim(coalesce(p_description, '')), ''),
    coalesce(p_country, v_user.country, v_default_country, 'RW'),
    v_visibility,
    v_type,
    0,
    coalesce(p_target_amount, 0),
    p_monthly_contribution,
    coalesce(p_monthly_contribution, p_target_amount, 0),
    v_cycle_days,
    v_frequency,
    nullif(btrim(coalesce(p_bank_partner, '')), ''),
    p_bank_partner_id,
    nullif(btrim(coalesce(p_momo_number, '')), ''),
    nullif(btrim(coalesce(p_receiving_momo_code, '')), ''),
    nullif(btrim(coalesce(p_receiving_momo_route_type, '')), ''),
    v_invite_code
  )
  returning *
    into v_group;

  insert into public.group_members (
    group_id,
    user_id,
    display_name,
    is_admin,
    is_anonymous,
    contribution_amount,
    joined_at
  )
  values (
    v_group.id,
    auth.uid(),
    v_member_display_name,
    true,
    false,
    0,
    now()
  )
  on conflict (group_id, user_id) do update
    set is_admin = true,
        display_name = excluded.display_name;

  return jsonb_build_object(
    'status', 'success',
    'group_id', v_group.id,
    'invite_code', v_invite_code
  );
exception
  when others then
    return jsonb_build_object(
      'status', 'error',
      'message', sqlerrm
    );
end;
$$;

grant execute on function public.create_group_atomic(
  text,
  text,
  text,
  text,
  text,
  integer,
  integer,
  integer,
  text,
  text,
  text,
  text,
  uuid
) to authenticated;
