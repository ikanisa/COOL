create or replace function public.biopay_upsert_enrollment(
  p_display_name text default null,
  p_route_type text default null,
  p_recipient_value text default null,
  p_country_code text default 'RW',
  p_consent_version text default 'biopay-v1',
  p_embedding double precision[] default null,
  p_model_version text default 'mobilefacenet_int8_v1',
  p_quality_score double precision default null
)
returns table (
  id uuid,
  public_id text,
  user_id uuid,
  display_name text,
  route_type text,
  recipient_value text,
  country_code text,
  active boolean,
  consent_version text,
  consent_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  revoked_at timestamptz,
  enrolled_at timestamptz
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_user_id uuid := auth.uid();
  v_user record;
  v_profile public.biopay_profiles%rowtype;
  v_embedding vector(192);
  v_display_name text;
  v_route_type text;
  v_recipient_value text;
  v_country_code text;
  v_consent_version text;
  v_enrolled_at timestamptz := timezone('utc', now());
  v_client_route_type text;
  v_client_recipient_value text;
  v_client_country_code text;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  select
    u.id,
    u.full_name,
    u.momo_number,
    u.momo_code,
    u.momo_route_type,
    u.country
  into v_user
  from public.users u
  where u.id = v_user_id;

  if not found then
    raise exception 'Cool user profile not found.';
  end if;

  if p_embedding is null then
    raise exception 'Embedding is required for BioPay enrollment.';
  end if;

  v_display_name := nullif(trim(coalesce(p_display_name, v_user.full_name, '')), '');
  if v_display_name is null then
    raise exception 'Display name is required.';
  end if;

  v_route_type := lower(trim(coalesce(
    nullif(v_user.momo_route_type, ''),
    case
      when nullif(trim(coalesce(v_user.momo_code, '')), '') is not null then 'code'
      when nullif(trim(coalesce(v_user.momo_number, '')), '') is not null then 'phone_number'
      else ''
    end
  )));

  if v_route_type not in ('phone_number', 'code') then
    raise exception 'A valid MoMo receive route is required before BioPay enrollment.';
  end if;

  v_recipient_value := trim(coalesce(
    case
      when v_route_type = 'code' then v_user.momo_code
      else v_user.momo_number
    end,
    ''
  ));

  if v_recipient_value = '' then
    raise exception 'A valid payout recipient is required before BioPay enrollment.';
  end if;

  v_country_code := upper(trim(coalesce(
    nullif(v_user.country, ''),
    'RW'
  )));
  v_consent_version := coalesce(nullif(trim(p_consent_version), ''), 'biopay-v1');
  v_embedding := public.biopay_array_to_vector_192(p_embedding);

  v_client_route_type := nullif(lower(trim(coalesce(p_route_type, ''))), '');
  if v_client_route_type is not null and v_client_route_type <> v_route_type then
    raise exception 'BioPay enrollment route must match your verified wallet route.';
  end if;

  v_client_recipient_value := nullif(trim(coalesce(p_recipient_value, '')), '');
  if v_client_recipient_value is not null and v_client_recipient_value <> v_recipient_value then
    raise exception 'BioPay enrollment recipient must match your verified wallet route.';
  end if;

  v_client_country_code := nullif(upper(trim(coalesce(p_country_code, ''))), '');
  if v_client_country_code is not null and v_client_country_code <> v_country_code then
    raise exception 'BioPay enrollment country must match your verified profile country.';
  end if;

  select bp.*
  into v_profile
  from public.biopay_profiles bp
  where bp.user_id = v_user_id
    and bp.deleted_at is null
  limit 1;

  if found then
    update public.biopay_profiles bp
    set
      display_name = v_display_name,
      route_type = v_route_type,
      recipient_value = v_recipient_value,
      country_code = v_country_code,
      active = true,
      consent_version = v_consent_version,
      consent_at = timezone('utc', now()),
      revoked_at = null,
      deleted_at = null
    where bp.id = v_profile.id
    returning bp.* into v_profile;
  else
    insert into public.biopay_profiles (
      user_id,
      display_name,
      route_type,
      recipient_value,
      country_code,
      active,
      consent_version,
      consent_at
    )
    values (
      v_user_id,
      v_display_name,
      v_route_type,
      v_recipient_value,
      v_country_code,
      true,
      v_consent_version,
      timezone('utc', now())
    )
    returning * into v_profile;
  end if;

  update public.biopay_embeddings be
  set
    active = false,
    retired_at = timezone('utc', now())
  where be.profile_id = v_profile.id
    and be.active = true;

  insert into public.biopay_embeddings (
    profile_id,
    embedding,
    model_version,
    quality_score,
    active,
    enrolled_at
  )
  values (
    v_profile.id,
    v_embedding,
    coalesce(nullif(trim(p_model_version), ''), 'mobilefacenet_int8_v1'),
    p_quality_score,
    true,
    v_enrolled_at
  );

  insert into public.biopay_enrollment_audits (
    profile_id,
    user_id,
    event_type,
    metadata
  )
  values (
    v_profile.id,
    v_user_id,
    'enrolled',
    jsonb_build_object(
      'route_type', v_route_type,
      'country_code', v_country_code,
      'model_version', coalesce(nullif(trim(p_model_version), ''), 'mobilefacenet_int8_v1'),
      'route_source', 'user_profile'
    )
  );

  return query
  select
    v_profile.id,
    v_profile.public_id,
    v_profile.user_id,
    v_profile.display_name,
    v_profile.route_type,
    v_profile.recipient_value,
    v_profile.country_code,
    v_profile.active,
    v_profile.consent_version,
    v_profile.consent_at,
    v_profile.created_at,
    v_profile.updated_at,
    v_profile.revoked_at,
    v_enrolled_at;
end;
$$;

create or replace function public.biopay_revoke_profile(
  p_reason text default null
)
returns table (
  profile_id uuid,
  public_id text,
  revoked_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.biopay_profiles%rowtype;
  v_revoked_at timestamptz := timezone('utc', now());
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  select bp.*
  into v_profile
  from public.biopay_profiles bp
  where bp.user_id = v_user_id
    and bp.active = true
    and bp.deleted_at is null
  limit 1;

  if not found then
    raise exception 'No active BioPay enrollment was found.';
  end if;

  update public.biopay_profiles bp
  set
    active = false,
    revoked_at = v_revoked_at
  where bp.id = v_profile.id
  returning bp.* into v_profile;

  update public.biopay_embeddings be
  set
    active = false,
    retired_at = v_revoked_at
  where be.profile_id = v_profile.id
    and be.active = true;

  insert into public.biopay_revocations (
    profile_id,
    user_id,
    reason,
    metadata
  )
  values (
    v_profile.id,
    v_user_id,
    nullif(trim(coalesce(p_reason, '')), ''),
    jsonb_build_object('public_id', v_profile.public_id)
  );

  insert into public.biopay_enrollment_audits (
    profile_id,
    user_id,
    event_type,
    metadata
  )
  values (
    v_profile.id,
    v_user_id,
    'revoked',
    jsonb_build_object(
      'reason', nullif(trim(coalesce(p_reason, '')), ''),
      'public_id', v_profile.public_id
    )
  );

  return query
  select
    v_profile.id,
    v_profile.public_id,
    v_revoked_at;
end;
$$;

grant execute on function public.biopay_upsert_enrollment(
  text,
  text,
  text,
  text,
  text,
  double precision[],
  text,
  double precision
) to authenticated;

grant execute on function public.biopay_revoke_profile(text) to authenticated;

comment on function public.biopay_upsert_enrollment(
  text,
  text,
  text,
  text,
  text,
  double precision[],
  text,
  double precision
) is 'Upserts a BioPay enrollment using profile-owned MoMo route data with qualified references for lint-safe PL/pgSQL execution.';

comment on function public.biopay_revoke_profile(text) is
  'Revokes the caller BioPay profile and retires active embeddings with qualified references for lint-safe PL/pgSQL execution.';
