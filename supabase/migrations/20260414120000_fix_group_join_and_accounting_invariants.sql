-- ============================================================================
-- Cool App - fix group join invariants and contribution accounting drift
-- ============================================================================

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

create or replace function public.confirm_contribution(p_contribution_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_contribution record;
begin
  select id, group_id, amount, status
    into v_contribution
    from public.group_contributions
   where id = p_contribution_id
   for update;

  if v_contribution is null then
    return jsonb_build_object(
      'status',
      'error',
      'message',
      'Contribution not found.'
    );
  end if;

  if v_contribution.status in ('confirmed', 'completed') then
    return jsonb_build_object('status', 'already_confirmed');
  end if;

  if v_contribution.status <> 'pending' then
    return jsonb_build_object(
      'status',
      'error',
      'message',
      format(
        'Cannot confirm contribution with status: %s',
        v_contribution.status
      )
    );
  end if;

  update public.group_contributions
     set status = 'confirmed',
         updated_at = now()
   where id = p_contribution_id;

  return jsonb_build_object(
    'status',
    'success',
    'amount',
    v_contribution.amount
  );
end;
$function$;

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
  v_default_country text;
  v_visibility text;
  v_type text;
  v_cycle_days integer;
  v_frequency text;
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

create or replace function public.join_public_group(
  p_group_id uuid
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

  if not public.is_whatsapp_otp_verified_user(auth.uid()) then
    raise exception 'Verify your WhatsApp number before joining a group.';
  end if;

  select *
    into v_user
    from public.users
   where id = auth.uid();

  if v_user.id is null then
    raise exception 'Complete your profile before joining a group.';
  end if;

  if coalesce(
    nullif(btrim(coalesce(v_user.momo_code, '')), ''),
    nullif(btrim(coalesce(v_user.momo_number, '')), '')
  ) is null then
    raise exception 'Add your MoMo number before joining a group.';
  end if;

  select *
    into v_group
    from public.groups
   where id = p_group_id
     and visibility = 'public';

  if v_group.id is null then
    return jsonb_build_object(
      'status', 'error',
      'message', 'Public group not found.'
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
    'status', 'joined',
    'group_id', v_group.id
  );
exception
  when others then
    return jsonb_build_object(
      'status', 'error',
      'message', sqlerrm
    );
end;
$$;

revoke all on function public.join_public_group(uuid) from public;
grant execute on function public.join_public_group(uuid)
  to authenticated, service_role;

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

  if not public.is_whatsapp_otp_verified_user(auth.uid()) then
    raise exception 'Verify your WhatsApp number before joining a group.';
  end if;

  select *
    into v_user
    from public.users
   where id = auth.uid();

  if v_user.id is null then
    raise exception 'Complete your profile first.';
  end if;

  if coalesce(
    nullif(btrim(coalesce(v_user.momo_code, '')), ''),
    nullif(btrim(coalesce(v_user.momo_number, '')), '')
  ) is null then
    raise exception 'Add your MoMo number before joining a group.';
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
     where group_id = v_group.id
       and user_id = auth.uid()
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
    'status', 'joined',
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
