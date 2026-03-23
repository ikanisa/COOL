-- ============================================================================
-- Cool App — Engagement foundation
-- ============================================================================

alter table public.cool_events
  add column if not exists dedupe_key text,
  add column if not exists campaign_id text,
  add column if not exists season_id uuid;
create unique index if not exists idx_cool_events_user_dedupe
  on public.cool_events (user_id, dedupe_key)
  where dedupe_key is not null;
create index if not exists idx_cool_events_campaign
  on public.cool_events (campaign_id)
  where campaign_id is not null;
create index if not exists idx_cool_events_season
  on public.cool_events (season_id)
  where season_id is not null;
create table if not exists public.season_definitions (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  description text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create table if not exists public.season_memberships (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.season_definitions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  season_points int not null default 0,
  rank_hint int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (season_id, user_id)
);
create table if not exists public.quest_definitions (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  description text,
  event_type text not null,
  target_count int not null default 1,
  reward_points int not null default 0,
  campaign_id text,
  start_at timestamptz,
  end_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (target_count > 0),
  check (reward_points >= 0),
  check (end_at is null or start_at is null or end_at > start_at)
);
create table if not exists public.quest_progress (
  id uuid primary key default gen_random_uuid(),
  quest_id uuid not null references public.quest_definitions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  progress_count int not null default 0,
  completed_at timestamptz,
  reward_dedupe_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (quest_id, user_id),
  unique (reward_dedupe_key),
  check (progress_count >= 0)
);
create table if not exists public.referral_invites (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null references auth.users(id) on delete cascade,
  invite_code text not null,
  share_channel text,
  deep_link text,
  campaign_id text,
  status text not null default 'pending'
    check (status in ('pending', 'opened', 'activated', 'expired')),
  opened_by_user_id uuid references auth.users(id) on delete set null,
  activated_by_user_id uuid references auth.users(id) on delete set null,
  opened_at timestamptz,
  activated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.referral_conversions (
  id uuid primary key default gen_random_uuid(),
  referral_invite_id uuid not null references public.referral_invites(id) on delete cascade,
  inviter_id uuid not null references auth.users(id) on delete cascade,
  invitee_id uuid not null references auth.users(id) on delete cascade,
  qualifying_event_type text not null,
  qualifying_event_id text,
  status text not null default 'pending'
    check (status in ('pending', 'rewarded')),
  inviter_points int not null default 0,
  invitee_points int not null default 0,
  dedupe_key text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (referral_invite_id, invitee_id)
);
create table if not exists public.share_artifacts (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null,
  target_id text,
  canonical_route text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_season_memberships_user
  on public.season_memberships (user_id, season_points desc);
create index if not exists idx_quest_progress_user
  on public.quest_progress (user_id, updated_at desc);
create index if not exists idx_referral_invites_inviter
  on public.referral_invites (inviter_id, created_at desc);
create index if not exists idx_referral_invites_invite_code
  on public.referral_invites (invite_code);
create index if not exists idx_referral_conversions_inviter
  on public.referral_conversions (inviter_id, created_at desc);
create index if not exists idx_referral_conversions_invitee
  on public.referral_conversions (invitee_id, created_at desc);
create index if not exists idx_share_artifacts_owner
  on public.share_artifacts (owner_user_id, created_at desc);
create or replace function public.cool_status_tier_for_points(p_points int)
returns text
language sql
immutable
as $$
  select case
    when greatest(coalesce(p_points, 0), 0) >= 5000 then 'platinum'
    when greatest(coalesce(p_points, 0), 0) >= 2000 then 'gold'
    when greatest(coalesce(p_points, 0), 0) >= 1000 then 'silver'
    else 'blue'
  end;
$$;
create or replace function public.sync_cool_status_fields()
returns trigger
language plpgsql
as $$
begin
  new.total_points := greatest(coalesce(new.total_points, 0), 0);
  new.season_points := greatest(coalesce(new.season_points, 0), 0);
  new.current_streak := greatest(coalesce(new.current_streak, 0), 0);
  new.longest_streak := greatest(coalesce(new.longest_streak, 0), 0);
  new.streak_grace_remaining := greatest(coalesce(new.streak_grace_remaining, 0), 0);
  new.tier := public.cool_status_tier_for_points(new.total_points);

  if tg_op = 'insert' then
    new.created_at := coalesce(new.created_at, now());
  end if;

  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_cool_status_sync_fields on public.cool_status;
create trigger trg_cool_status_sync_fields
  before insert or update on public.cool_status
  for each row
  execute function public.sync_cool_status_fields();
drop trigger if exists trg_season_definitions_set_updated_at on public.season_definitions;
create trigger trg_season_definitions_set_updated_at
  before update on public.season_definitions
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_season_memberships_set_updated_at on public.season_memberships;
create trigger trg_season_memberships_set_updated_at
  before update on public.season_memberships
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_quest_definitions_set_updated_at on public.quest_definitions;
create trigger trg_quest_definitions_set_updated_at
  before update on public.quest_definitions
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_quest_progress_set_updated_at on public.quest_progress;
create trigger trg_quest_progress_set_updated_at
  before update on public.quest_progress
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_referral_invites_set_updated_at on public.referral_invites;
create trigger trg_referral_invites_set_updated_at
  before update on public.referral_invites
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_referral_conversions_set_updated_at on public.referral_conversions;
create trigger trg_referral_conversions_set_updated_at
  before update on public.referral_conversions
  for each row
  execute function public.set_updated_at();
drop trigger if exists trg_share_artifacts_set_updated_at on public.share_artifacts;
create trigger trg_share_artifacts_set_updated_at
  before update on public.share_artifacts
  for each row
  execute function public.set_updated_at();
update public.cool_status
set
  total_points = greatest(coalesce(total_points, 0), 0),
  season_points = greatest(coalesce(season_points, 0), 0),
  tier = public.cool_status_tier_for_points(total_points),
  updated_at = now()
where true;
create or replace function public.apply_cool_event_internal(
  p_user_id uuid,
  p_event_type text,
  p_points int default 0,
  p_source_id text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_referrer_id uuid default null,
  p_dedupe_key text default null,
  p_campaign_id text default null,
  p_season_id uuid default null
)
returns public.cool_status
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status public.cool_status;
  v_existing_event_id uuid;
  v_effective_season_id uuid;
begin
  insert into public.cool_status (user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  if nullif(btrim(coalesce(p_dedupe_key, '')), '') is not null then
    select id
    into v_existing_event_id
    from public.cool_events
    where user_id = p_user_id
      and dedupe_key = p_dedupe_key
    limit 1;

    if v_existing_event_id is not null then
      select *
      into v_status
      from public.cool_status
      where user_id = p_user_id;

      return v_status;
    end if;
  end if;

  select active_season_id
  into v_effective_season_id
  from public.cool_status
  where user_id = p_user_id;

  v_effective_season_id := coalesce(p_season_id, v_effective_season_id);

  insert into public.cool_events (
    user_id,
    event_type,
    source_id,
    points_awarded,
    metadata,
    referrer_id,
    dedupe_key,
    campaign_id,
    season_id
  )
  values (
    p_user_id,
    p_event_type,
    p_source_id,
    coalesce(p_points, 0),
    coalesce(p_metadata, '{}'::jsonb),
    p_referrer_id,
    nullif(btrim(coalesce(p_dedupe_key, '')), ''),
    nullif(btrim(coalesce(p_campaign_id, '')), ''),
    v_effective_season_id
  );

  update public.cool_status
  set
    total_points = greatest(total_points + coalesce(p_points, 0), 0),
    season_points = case
      when v_effective_season_id is null then season_points
      when active_season_id is null or active_season_id = v_effective_season_id
        then greatest(season_points + coalesce(p_points, 0), 0)
      else season_points
    end,
    active_season_id = coalesce(v_effective_season_id, active_season_id),
    updated_at = now()
  where user_id = p_user_id
  returning *
  into v_status;

  if v_effective_season_id is not null then
    insert into public.season_memberships (
      season_id,
      user_id,
      season_points
    )
    values (
      v_effective_season_id,
      p_user_id,
      greatest(coalesce(p_points, 0), 0)
    )
    on conflict (season_id, user_id) do update
      set
        season_points = greatest(
          public.season_memberships.season_points + coalesce(p_points, 0),
          0
        ),
        updated_at = now();
  end if;

  return v_status;
end;
$$;
revoke all on function public.apply_cool_event_internal(
  uuid,
  text,
  int,
  text,
  jsonb,
  uuid,
  text,
  text,
  uuid
) from public, anon, authenticated;
create or replace function public.apply_cool_event(
  p_user_id uuid,
  p_event_type text,
  p_points int default 0,
  p_source_id text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_referrer_id uuid default null,
  p_dedupe_key text default null,
  p_campaign_id text default null,
  p_season_id uuid default null
)
returns public.cool_status
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null and auth.role() <> 'service_role' then
    raise exception 'Authentication is required.';
  end if;

  if auth.role() <> 'service_role' and auth.uid() <> p_user_id then
    raise exception 'You can only log your own status event.';
  end if;

  return public.apply_cool_event_internal(
    p_user_id,
    p_event_type,
    p_points,
    p_source_id,
    p_metadata,
    p_referrer_id,
    p_dedupe_key,
    p_campaign_id,
    p_season_id
  );
end;
$$;
create or replace function public.create_referral_invite(
  p_invite_code text,
  p_share_channel text default null,
  p_deep_link text default null,
  p_campaign_id text default null
)
returns public.referral_invites
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.referral_invites;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  insert into public.referral_invites (
    inviter_id,
    invite_code,
    share_channel,
    deep_link,
    campaign_id
  )
  values (
    auth.uid(),
    upper(btrim(p_invite_code)),
    nullif(btrim(coalesce(p_share_channel, '')), ''),
    nullif(btrim(coalesce(p_deep_link, '')), ''),
    nullif(btrim(coalesce(p_campaign_id, '')), '')
  )
  returning *
  into v_invite;

  return v_invite;
end;
$$;
create or replace function public.mark_referral_invite_opened(
  p_referral_invite_id uuid
)
returns public.referral_invites
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.referral_invites;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  update public.referral_invites
  set
    status = case
      when status = 'pending' then 'opened'
      else status
    end,
    opened_by_user_id = coalesce(opened_by_user_id, auth.uid()),
    opened_at = coalesce(opened_at, now()),
    updated_at = now()
  where id = p_referral_invite_id
  returning *
  into v_invite;

  if not found then
    raise exception 'Referral invite not found.';
  end if;

  return v_invite;
end;
$$;
create or replace function public.activate_referral_invite(
  p_referral_invite_id uuid,
  p_qualifying_event_type text,
  p_qualifying_event_id text default null,
  p_inviter_points int default 150,
  p_invitee_points int default 50
)
returns public.referral_conversions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.referral_invites;
  v_conversion public.referral_conversions;
  v_invitee_id uuid := auth.uid();
  v_dedupe_key text;
begin
  if v_invitee_id is null then
    raise exception 'Authentication is required.';
  end if;

  select *
  into v_invite
  from public.referral_invites
  where id = p_referral_invite_id;

  if not found then
    raise exception 'Referral invite not found.';
  end if;

  if v_invite.inviter_id = v_invitee_id then
    raise exception 'Inviter cannot activate their own invite.';
  end if;

  v_dedupe_key := 'referral:' || p_referral_invite_id::text || ':' || v_invitee_id::text;

  insert into public.referral_conversions (
    referral_invite_id,
    inviter_id,
    invitee_id,
    qualifying_event_type,
    qualifying_event_id,
    dedupe_key
  )
  values (
    p_referral_invite_id,
    v_invite.inviter_id,
    v_invitee_id,
    p_qualifying_event_type,
    p_qualifying_event_id,
    v_dedupe_key
  )
  on conflict (referral_invite_id, invitee_id) do update
    set
      qualifying_event_type = excluded.qualifying_event_type,
      qualifying_event_id = excluded.qualifying_event_id,
      updated_at = now()
  returning *
  into v_conversion;

  if v_conversion.status <> 'rewarded' then
    perform public.apply_cool_event_internal(
      v_invite.inviter_id,
      'inviteQualified',
      greatest(coalesce(p_inviter_points, 0), 0),
      p_qualifying_event_id,
      jsonb_build_object(
        'referral_invite_id', p_referral_invite_id,
        'invitee_id', v_invitee_id,
        'qualifying_event_type', p_qualifying_event_type
      ),
      v_invitee_id,
      'inviteQualified:inviter:' || p_referral_invite_id::text || ':' || v_invitee_id::text,
      v_invite.campaign_id,
      null
    );

    perform public.apply_cool_event_internal(
      v_invitee_id,
      'inviteQualified',
      greatest(coalesce(p_invitee_points, 0), 0),
      p_qualifying_event_id,
      jsonb_build_object(
        'referral_invite_id', p_referral_invite_id,
        'inviter_id', v_invite.inviter_id,
        'qualifying_event_type', p_qualifying_event_type
      ),
      v_invite.inviter_id,
      'inviteQualified:invitee:' || p_referral_invite_id::text || ':' || v_invitee_id::text,
      v_invite.campaign_id,
      null
    );

    update public.referral_conversions
    set
      inviter_points = greatest(coalesce(p_inviter_points, 0), 0),
      invitee_points = greatest(coalesce(p_invitee_points, 0), 0),
      status = 'rewarded',
      updated_at = now()
    where id = v_conversion.id
    returning *
    into v_conversion;
  end if;

  update public.referral_invites
  set
    status = 'activated',
    opened_by_user_id = coalesce(opened_by_user_id, v_invitee_id),
    activated_by_user_id = coalesce(activated_by_user_id, v_invitee_id),
    opened_at = coalesce(opened_at, now()),
    activated_at = coalesce(activated_at, now()),
    updated_at = now()
  where id = p_referral_invite_id;

  return v_conversion;
end;
$$;
alter table public.season_definitions enable row level security;
alter table public.season_memberships enable row level security;
alter table public.quest_definitions enable row level security;
alter table public.quest_progress enable row level security;
alter table public.referral_invites enable row level security;
alter table public.referral_conversions enable row level security;
alter table public.share_artifacts enable row level security;
drop policy if exists season_definitions_select_authenticated on public.season_definitions;
create policy season_definitions_select_authenticated
  on public.season_definitions for select
  using (auth.role() = 'authenticated');
drop policy if exists season_memberships_select_own on public.season_memberships;
create policy season_memberships_select_own
  on public.season_memberships for select
  using (auth.uid() = user_id);
drop policy if exists quest_definitions_select_authenticated on public.quest_definitions;
create policy quest_definitions_select_authenticated
  on public.quest_definitions for select
  using (auth.role() = 'authenticated');
drop policy if exists quest_progress_select_own on public.quest_progress;
create policy quest_progress_select_own
  on public.quest_progress for select
  using (auth.uid() = user_id);
drop policy if exists quest_progress_insert_own on public.quest_progress;
create policy quest_progress_insert_own
  on public.quest_progress for insert
  with check (auth.uid() = user_id);
drop policy if exists quest_progress_update_own on public.quest_progress;
create policy quest_progress_update_own
  on public.quest_progress for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop policy if exists referral_invites_select_visible on public.referral_invites;
create policy referral_invites_select_visible
  on public.referral_invites for select
  using (
    auth.uid() = inviter_id
    or auth.uid() = opened_by_user_id
    or auth.uid() = activated_by_user_id
  );
drop policy if exists referral_invites_insert_own on public.referral_invites;
create policy referral_invites_insert_own
  on public.referral_invites for insert
  with check (auth.uid() = inviter_id);
drop policy if exists referral_invites_update_own on public.referral_invites;
create policy referral_invites_update_own
  on public.referral_invites for update
  using (auth.uid() = inviter_id)
  with check (auth.uid() = inviter_id);
drop policy if exists referral_conversions_select_visible on public.referral_conversions;
create policy referral_conversions_select_visible
  on public.referral_conversions for select
  using (auth.uid() = inviter_id or auth.uid() = invitee_id);
drop policy if exists share_artifacts_select_own on public.share_artifacts;
create policy share_artifacts_select_own
  on public.share_artifacts for select
  using (auth.uid() = owner_user_id);
drop policy if exists share_artifacts_insert_own on public.share_artifacts;
create policy share_artifacts_insert_own
  on public.share_artifacts for insert
  with check (auth.uid() = owner_user_id);
drop policy if exists share_artifacts_update_own on public.share_artifacts;
create policy share_artifacts_update_own
  on public.share_artifacts for update
  using (auth.uid() = owner_user_id)
  with check (auth.uid() = owner_user_id);
