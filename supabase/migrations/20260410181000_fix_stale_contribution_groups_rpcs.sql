-- ============================================================================
-- Cool App - Fix RPCs still referencing contribution_groups after rename
-- ============================================================================
-- After renaming contribution_groups → groups, several RPCs stored on the
-- remote DB still have 'contribution_groups' in their function bodies.
-- This migration drops the stale overloads and re-creates the canonical
-- versions that reference public.groups.
-- ============================================================================

-- 1. Drop stale create_group_atomic overloads from the remote branch
--    (the one with p_privacy, p_group_type, p_currency, p_country_code args)
drop function if exists public.create_group_atomic(
  text, text, text, text, integer, text, integer, text
);

-- 2. Re-create canonical create_group_atomic (latest local version)
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
  p_institution_id text default null,
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
  p_country := nullif(btrim(coalesce(p_country, '')), '');

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
    institution_id,
    momo_number,
    receiving_momo_code,
    receiving_momo_route_type,
    invite_code
  )
  values (
    auth.uid(),
    nullif(btrim(p_name), ''),
    nullif(btrim(coalesce(p_description, '')), ''),
    'RW',
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
    nullif(btrim(coalesce(p_institution_id, '')), ''),
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
    coalesce(nullif(btrim(v_user.public_user_id), ''), '000000'),
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

-- 3. Re-create join_group_via_invite (uses public.groups)
create or replace function public.join_group_via_invite(
  p_invite_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user public.users;
  v_group public.groups;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select *
  into v_user
  from public.users
  where id = auth.uid();

  if v_user.id is null then
    raise exception 'Complete your profile first.';
  end if;

  select *
  into v_group
  from public.groups
  where invite_code = btrim(upper(p_invite_code));

  if v_group.id is null then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Invalid invite code.'
    );
  end if;

  if exists (
    select 1 from public.group_members
    where group_id = v_group.id and user_id = auth.uid()
  ) then
    return jsonb_build_object(
      'status', 'already_member',
      'group_id', v_group.id,
      'group_name', v_group.name
    );
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
    coalesce(nullif(btrim(v_user.public_user_id), ''), '000000'),
    false,
    false,
    0,
    now()
  )
  on conflict (group_id, user_id) do nothing;

  return jsonb_build_object(
    'status', 'success',
    'group_id', v_group.id,
    'group_name', v_group.name,
    'invite_code', v_group.invite_code
  );
exception
  when others then
    return jsonb_build_object(
      'status', 'error',
      'message', sqlerrm
    );
end;
$$;

-- 4. Re-create preview_invite (uses public.groups)
create or replace function public.preview_invite(
  p_invite_code text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_group public.groups;
  v_member_count bigint;
begin
  select *
  into v_group
  from public.groups
  where invite_code = btrim(upper(p_invite_code));

  if v_group.id is null then
    return jsonb_build_object(
      'status', 'not_found',
      'message', 'No group found for this invite code.'
    );
  end if;

  select count(*)
  into v_member_count
  from public.group_members
  where group_id = v_group.id;

  return jsonb_build_object(
    'status', 'success',
    'group_id', v_group.id,
    'group_name', v_group.name,
    'description', v_group.description,
    'visibility', v_group.visibility,
    'type', v_group.type,
    'target_amount', v_group.target_amount,
    'country', v_group.country,
    'member_count', v_member_count,
    'invite_code', v_group.invite_code,
    'already_member', exists (
      select 1 from public.group_members
      where group_id = v_group.id and user_id = auth.uid()
    )
  );
end;
$$;

-- 5. Re-create update_group_totals trigger function
create or replace function public.update_group_totals()
returns trigger
language plpgsql
as $$
begin
  update public.groups
  set
    current_total = coalesce((
      select sum(gc.amount)
      from public.group_contributions gc
      where gc.group_id = coalesce(new.group_id, old.group_id)
        and gc.status = 'confirmed'
    ), 0),
    updated_at = now()
  where id = coalesce(new.group_id, old.group_id);

  return coalesce(new, old);
end;
$$;

-- 6. Re-create update_group_member_count trigger function
create or replace function public.update_group_member_count()
returns trigger
language plpgsql
as $$
begin
  update public.groups
  set
    member_count = (
      select count(*)
      from public.group_members gm
      where gm.group_id = coalesce(new.group_id, old.group_id)
    ),
    updated_at = now()
  where id = coalesce(new.group_id, old.group_id);

  return coalesce(new, old);
end;
$$;

-- 7. Re-create populate_group_message_defaults trigger function
create or replace function public.populate_group_message_defaults()
returns trigger
language plpgsql
as $$
begin
  if new.alias is null then
    new.alias := substr(md5(new.sender_id::text || new.group_id::text), 1, 6);
  end if;
  return new;
end;
$$;

-- 8. Re-create generate_invite_code (idempotent helper)
create or replace function public.generate_invite_code()
returns text
language plpgsql
as $$
declare
  v_code text;
  v_attempts int := 0;
begin
  loop
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    if not exists (
      select 1 from public.groups where invite_code = v_code
    ) then
      return v_code;
    end if;
    v_attempts := v_attempts + 1;
    if v_attempts > 100 then
      raise exception 'Could not generate unique invite code after 100 attempts';
    end if;
  end loop;
end;
$$;

-- 9. get_admin_groups_summary was just re-applied in 20260409225000
--    Let's verify it uses public.groups (it was written locally, should be fine)
--    Re-apply it from that migration to override the remote version.
