create extension if not exists pgcrypto;
create extension if not exists vector;

create table if not exists public.biopay_profiles (
  id uuid primary key default gen_random_uuid(),
  public_id text not null unique,
  user_id uuid not null references public.users(id) on delete cascade,
  display_name text not null,
  route_type text not null check (route_type in ('phone_number', 'code')),
  recipient_value text not null,
  country_code text not null default 'RW',
  active boolean not null default true,
  consent_version text not null default 'biopay-v1',
  consent_at timestamptz not null default timezone('utc', now()),
  revoked_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.biopay_embeddings (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.biopay_profiles(id) on delete cascade,
  embedding vector(128) not null,
  model_version text not null default 'mobilefacenet_int8_v1',
  quality_score double precision,
  active boolean not null default true,
  enrolled_at timestamptz not null default timezone('utc', now()),
  retired_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  check (quality_score is null or (quality_score >= 0 and quality_score <= 1))
);

create table if not exists public.biopay_match_events (
  id uuid primary key default gen_random_uuid(),
  requester_user_id uuid not null references public.users(id) on delete cascade,
  matched_profile_id uuid references public.biopay_profiles(id) on delete set null,
  matched boolean not null default false,
  score double precision not null default 0,
  threshold_used double precision not null default 0.72,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.biopay_enrollment_audits (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.biopay_profiles(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  event_type text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.biopay_revocations (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.biopay_profiles(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists biopay_profiles_user_id_active_idx
  on public.biopay_profiles(user_id)
  where deleted_at is null;

create index if not exists biopay_profiles_public_id_idx
  on public.biopay_profiles(public_id);

create index if not exists biopay_embeddings_profile_id_idx
  on public.biopay_embeddings(profile_id, active);

create index if not exists biopay_match_events_requester_user_idx
  on public.biopay_match_events(requester_user_id, created_at desc);

create index if not exists biopay_enrollment_audits_user_idx
  on public.biopay_enrollment_audits(user_id, created_at desc);

create index if not exists biopay_revocations_user_idx
  on public.biopay_revocations(user_id, created_at desc);

create index if not exists biopay_embeddings_embedding_cosine_idx
  on public.biopay_embeddings
  using ivfflat (embedding vector_cosine_ops)
  with (lists = 64);

drop trigger if exists trg_biopay_profiles_updated on public.biopay_profiles;
create trigger trg_biopay_profiles_updated
before update on public.biopay_profiles
for each row execute function public.set_updated_at();

create or replace function public.generate_biopay_public_id()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_candidate text;
begin
  loop
    v_candidate := lpad(floor(random() * 1000000)::int::text, 6, '0');
    exit when not exists (
      select 1
      from public.biopay_profiles
      where public_id = v_candidate
    );
  end loop;

  return v_candidate;
end;
$$;

alter table public.biopay_profiles
alter column public_id set default public.generate_biopay_public_id();

create or replace function public.biopay_array_to_vector(p_embedding double precision[])
returns vector(128)
language plpgsql
immutable
set search_path = public
as $$
begin
  if coalesce(array_length(p_embedding, 1), 0) != 128 then
    raise exception 'BioPay embedding must contain exactly 128 values.';
  end if;

  return ('[' || array_to_string(p_embedding, ',') || ']')::vector(128);
end;
$$;

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
  v_user record;
  v_profile public.biopay_profiles%rowtype;
  v_embedding vector(128);
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

  select
    id,
    full_name,
    momo_number,
    momo_code,
    momo_route_type,
    country
  into v_user
  from public.users
  where id = v_user_id;

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
    nullif(p_route_type, ''),
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
    nullif(p_recipient_value, ''),
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
    nullif(p_country_code, ''),
    nullif(v_user.country, ''),
    'RW'
  )));
  v_consent_version := coalesce(nullif(trim(p_consent_version), ''), 'biopay-v1');
  v_embedding := public.biopay_array_to_vector(p_embedding);

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
      'model_version', coalesce(nullif(trim(p_model_version), ''), 'mobilefacenet_int8_v1')
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

create or replace function public.match_biopay_profile(
  p_embedding double precision[]
)
returns table (
  profile_id uuid,
  public_id text,
  user_id uuid,
  display_name text,
  route_type text,
  recipient_value text,
  country_code text,
  consent_version text,
  consent_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  score double precision
)
language sql
security definer
set search_path = public
as $$
  with query_vector as (
    select public.biopay_array_to_vector(p_embedding) as embedding
  )
  select
    p.id as profile_id,
    p.public_id,
    p.user_id,
    p.display_name,
    p.route_type,
    p.recipient_value,
    p.country_code,
    p.consent_version,
    p.consent_at,
    p.created_at,
    p.updated_at,
    1 - (e.embedding <=> q.embedding) as score
  from public.biopay_embeddings e
  join public.biopay_profiles p on p.id = e.profile_id
  cross join query_vector q
  where e.active = true
    and p.active = true
    and p.deleted_at is null
  order by e.embedding <=> q.embedding asc
  limit 1;
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

  select *
  into v_profile
  from public.biopay_profiles
  where user_id = v_user_id
    and active = true
    and deleted_at is null
  limit 1;

  if not found then
    raise exception 'No active BioPay enrollment was found.';
  end if;

  update public.biopay_profiles
  set
    active = false,
    revoked_at = v_revoked_at
  where id = v_profile.id
  returning * into v_profile;

  update public.biopay_embeddings
  set
    active = false,
    retired_at = v_revoked_at
  where profile_id = v_profile.id
    and active = true;

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

grant select, insert, update on public.biopay_profiles to authenticated;
grant select on public.biopay_match_events to authenticated;
grant select on public.biopay_enrollment_audits to authenticated;
grant select on public.biopay_revocations to authenticated;

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

grant execute on function public.match_biopay_profile(double precision[])
to authenticated;

grant execute on function public.biopay_revoke_profile(text)
to authenticated;

alter table public.biopay_profiles enable row level security;
alter table public.biopay_embeddings enable row level security;
alter table public.biopay_match_events enable row level security;
alter table public.biopay_enrollment_audits enable row level security;
alter table public.biopay_revocations enable row level security;

drop policy if exists biopay_profiles_select_own on public.biopay_profiles;
create policy biopay_profiles_select_own
  on public.biopay_profiles
  for select
  using (auth.uid() = user_id);

drop policy if exists biopay_profiles_insert_own on public.biopay_profiles;
create policy biopay_profiles_insert_own
  on public.biopay_profiles
  for insert
  with check (auth.uid() = user_id);

drop policy if exists biopay_profiles_update_own on public.biopay_profiles;
create policy biopay_profiles_update_own
  on public.biopay_profiles
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists biopay_match_events_select_own on public.biopay_match_events;
create policy biopay_match_events_select_own
  on public.biopay_match_events
  for select
  using (auth.uid() = requester_user_id);

drop policy if exists biopay_enrollment_audits_select_own on public.biopay_enrollment_audits;
create policy biopay_enrollment_audits_select_own
  on public.biopay_enrollment_audits
  for select
  using (auth.uid() = user_id);

drop policy if exists biopay_revocations_select_own on public.biopay_revocations;
create policy biopay_revocations_select_own
  on public.biopay_revocations
  for select
  using (auth.uid() = user_id);

insert into public.app_config (key, value, description) values
  ('feature_biopay_enabled', 'false', 'Enable the BioPay feature module inside the MoMo hub'),
  ('biopay_match_threshold', '0.72', 'Minimum cosine similarity score for a BioPay match'),
  ('biopay_cache_ttl_hours', '24', 'Hours before a cached BioPay match expires on device'),
  ('biopay_stable_frames', '3', 'Stable face frames required before BioPay capture proceeds')
on conflict (key) do update
set
  value = excluded.value,
  description = excluded.description;
