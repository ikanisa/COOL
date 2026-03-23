-- ==========================================================================
-- Public 6-digit user IDs for all in-app identity surfaces
-- ==========================================================================

create sequence if not exists public.public_user_id_seq
  as integer
  minvalue 1
  maxvalue 999999
  start with 1
  increment by 1
  no cycle;

create or replace function public.next_public_user_id()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_next integer;
begin
  v_next := nextval('public.public_user_id_seq');
  return lpad(v_next::text, 6, '0');
end;
$$;

revoke all on function public.next_public_user_id() from public;
grant execute on function public.next_public_user_id() to authenticated;

alter table public.users
  add column if not exists public_user_id text;

alter table public.users
  alter column public_user_id set default public.next_public_user_id();

create or replace function public.assign_public_user_id()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(btrim(new.public_user_id), '') = '' then
    new.public_user_id := public.next_public_user_id();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_assign_public_user_id on public.users;
create trigger trg_assign_public_user_id
  before insert or update of public_user_id
  on public.users
  for each row
  execute function public.assign_public_user_id();

do $$
declare
  has_momo_trigger boolean;
begin
  select exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.users'::regclass
      and tgname = 'trg_enforce_user_momo_fields'
      and not tgisinternal
  )
  into has_momo_trigger;

  if has_momo_trigger then
    execute 'alter table public.users disable trigger trg_enforce_user_momo_fields';
  end if;

  update public.users
  set public_user_id = null
  where coalesce(btrim(public_user_id), '') <> ''
    and public_user_id !~ '^[0-9]{6}$';

  update public.users
  set public_user_id = public.next_public_user_id()
  where coalesce(btrim(public_user_id), '') = '';

  if has_momo_trigger then
    execute 'alter table public.users enable trigger trg_enforce_user_momo_fields';
  end if;
exception
  when others then
    if has_momo_trigger then
      execute 'alter table public.users enable trigger trg_enforce_user_momo_fields';
    end if;
    raise;
end;
$$;

select setval(
  'public.public_user_id_seq',
  greatest(
    coalesce(
      (
        select max(public_user_id::integer) + 1
        from public.users
        where public_user_id ~ '^[0-9]{6}$'
      ),
      1
    ),
    1
  ),
  false
);

alter table public.users
  drop constraint if exists users_public_user_id_format_check;

alter table public.users
  add constraint users_public_user_id_format_check
    check (public_user_id ~ '^[0-9]{6}$');

create unique index if not exists idx_users_public_user_id
  on public.users (public_user_id);

alter table public.users
  alter column public_user_id set not null;

do $$
declare
  has_group_count_trigger boolean;
begin
  select exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.group_members'::regclass
      and tgname = 'trg_sync_group_member_count'
      and not tgisinternal
  )
  into has_group_count_trigger;

  if has_group_count_trigger then
    execute 'alter table public.group_members disable trigger trg_sync_group_member_count';
  end if;

  update public.group_members as membership
  set display_name = profile.public_user_id
  from public.users as profile
  where profile.id = membership.user_id
    and coalesce(membership.display_name, '') is distinct from profile.public_user_id;

  if has_group_count_trigger then
    execute 'alter table public.group_members enable trigger trg_sync_group_member_count';
  end if;
exception
  when others then
    if has_group_count_trigger then
      execute 'alter table public.group_members enable trigger trg_sync_group_member_count';
    end if;
    raise;
end;
$$;

update public.mobility_trips as trip
set contact_name = profile.public_user_id
from public.users as profile
where profile.id = trip.user_id
  and coalesce(trip.contact_name, '') is distinct from profile.public_user_id;

create or replace function public.sync_mobility_trip_contact()
returns trigger
language plpgsql
as $$
declare
  profile_phone text;
  profile_name text;
begin
  if new.user_id is null then
    return new;
  end if;

  select u.phone, u.public_user_id
  into profile_phone, profile_name
  from public.users u
  where u.id = new.user_id;

  new.contact_phone := coalesce(nullif(new.contact_phone, ''), profile_phone);
  new.contact_name := coalesce(profile_name, nullif(new.contact_name, ''));
  return new;
end;
$$;

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
  p_receiving_momo_route_type text default null
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
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select *
  into v_user
  from public.users
  where id = auth.uid();

  if v_user.id is null then
    raise exception 'Complete profile before creating a group.';
  end if;

  v_invite_code := public.generate_group_invite_code();

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
    momo_number,
    receiving_momo_code,
    receiving_momo_route_type,
    invite_code
  )
  values (
    auth.uid(),
    nullif(btrim(p_name), ''),
    nullif(btrim(coalesce(p_description, '')), ''),
    coalesce(nullif(btrim(coalesce(p_country, '')), ''), 'RW'),
    coalesce(nullif(btrim(coalesce(p_visibility, '')), ''), 'private'),
    coalesce(nullif(btrim(coalesce(p_type, '')), ''), 'saving'),
    0,
    coalesce(p_target_amount, 0),
    p_monthly_contribution,
    coalesce(p_monthly_contribution, p_target_amount, 0),
    greatest(coalesce(p_cycle_days, 30), 1),
    coalesce(
      nullif(
        btrim(
          case
            when p_cycle_days <= 1 then 'daily'
            when p_cycle_days <= 7 then 'weekly'
            else 'monthly'
          end
        ),
        ''
      ),
      'monthly'
    ),
    nullif(btrim(coalesce(p_bank_partner, '')), ''),
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
    v_user.public_user_id,
    true,
    false,
    0,
    now()
  )
  on conflict (group_id, user_id) do update
  set
    is_admin = true,
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

create or replace function public.join_group_via_invite(
  p_invite_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.groups;
  v_user public.users;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select *
  into v_group
  from public.groups
  where invite_code = upper(btrim(p_invite_code))
  limit 1;

  if v_group.id is null then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Invite code not found.'
    );
  end if;

  if exists (
    select 1
    from public.group_members
    where group_id = v_group.id
      and user_id = auth.uid()
  ) then
    return jsonb_build_object(
      'status', 'already_member',
      'group_id', v_group.id
    );
  end if;

  select *
  into v_user
  from public.users
  where id = auth.uid();

  if v_user.id is null then
    raise exception 'Complete profile before joining a group.';
  end if;

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
    v_user.public_user_id,
    false,
    false,
    0,
    now()
  );

  return jsonb_build_object(
    'status', 'joined',
    'group_id', v_group.id
  );
exception
  when unique_violation then
    return jsonb_build_object(
      'status', 'already_member',
      'group_id', v_group.id
    );
  when others then
    return jsonb_build_object(
      'status', 'error',
      'message', sqlerrm
    );
end;
$$;

create or replace function public.get_rayon_member_registry(
  p_partner_id uuid,
  p_search_query text default null,
  p_filter_tier text default null,
  p_region text default null,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  user_id uuid,
  display_name text,
  membership_number text,
  points integer,
  tier text,
  chapter text,
  joined_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_search text := nullif(btrim(coalesce(p_search_query, '')), '');
  v_tier text := lower(nullif(btrim(coalesce(p_filter_tier, '')), ''));
  v_region text := nullif(btrim(coalesce(p_region, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  if p_partner_id is null then
    raise exception 'Partner id is required.';
  end if;

  return query
  select
    membership.user_id,
    profile.public_user_id as display_name,
    membership.membership_number,
    membership.points,
    membership.tier,
    coalesce(nullif(btrim(membership.chapter), ''), 'Kigali Central') as chapter,
    membership.joined_at
  from public.rs_fan_memberships membership
  join public.users profile on profile.id = membership.user_id
  where membership.partner_id = p_partner_id
    and (v_tier is null or lower(membership.tier) = v_tier)
    and (
      v_region is null
      or coalesce(membership.chapter, '') ilike '%' || v_region || '%'
    )
    and (
      v_search is null
      or profile.public_user_id ilike '%' || v_search || '%'
      or membership.membership_number ilike '%' || v_search || '%'
    )
  order by
    membership.points desc,
    membership.joined_at asc,
    membership.membership_number asc
  limit greatest(coalesce(p_limit, 20), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;
;
