alter table public.biopay_profiles
  drop constraint if exists biopay_profiles_user_id_fkey;

alter table public.biopay_match_events
  drop constraint if exists biopay_match_events_requester_user_id_fkey;

alter table public.biopay_enrollment_audits
  drop constraint if exists biopay_enrollment_audits_user_id_fkey;

alter table public.biopay_revocations
  drop constraint if exists biopay_revocations_user_id_fkey;

alter table public.biopay_profiles
  add constraint biopay_profiles_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.biopay_match_events
  add constraint biopay_match_events_requester_user_id_fkey
  foreign key (requester_user_id) references auth.users(id) on delete cascade;

alter table public.biopay_enrollment_audits
  add constraint biopay_enrollment_audits_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

alter table public.biopay_revocations
  add constraint biopay_revocations_user_id_fkey
  foreign key (user_id) references auth.users(id) on delete cascade;

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
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_profile public.biopay_profiles%rowtype;
  v_embedding vector(192);
  v_display_name text;
  v_route_type text;
  v_recipient_value text;
  v_country_code text;
  v_consent_version text;
  v_enrolled_at timestamptz := timezone('utc', now());
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if p_embedding is null then
    raise exception 'Embedding is required for BioPay enrollment.';
  end if;

  v_display_name := nullif(trim(coalesce(p_display_name, '')), '');
  if v_display_name is null then
    v_display_name := 'BioPay User';
  end if;

  v_country_code := upper(trim(coalesce(
    nullif(p_country_code, ''),
    'RW'
  )));
  v_route_type := lower(trim(coalesce(nullif(p_route_type, ''), '')));

  if v_route_type not in ('phone_number', 'code') then
    raise exception 'A valid MoMo receive route is required before BioPay enrollment.';
  end if;

  v_recipient_value := case
    when v_route_type = 'code' then public.normalize_momo_code_for_country(
      v_country_code,
      coalesce(p_recipient_value, '')
    )
    else public.normalize_momo_phone_for_country(
      v_country_code,
      coalesce(p_recipient_value, '')
    )
  end;

  if trim(coalesce(v_recipient_value, '')) = '' then
    raise exception 'A valid payout recipient is required before BioPay enrollment.';
  end if;

  v_consent_version := coalesce(nullif(trim(p_consent_version), ''), 'biopay-v1');
  v_embedding := public.biopay_array_to_vector_192(p_embedding);

  select *
  into v_profile
  from public.biopay_profiles
  where user_id = v_user_id
    and deleted_at is null
  limit 1;

  if found then
    update public.biopay_profiles
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
    where id = v_profile.id
    returning * into v_profile;
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

  update public.biopay_embeddings
  set
    active = false,
    retired_at = timezone('utc', now())
  where profile_id = v_profile.id
    and active = true;

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
      'route_source', 'client_payload'
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
