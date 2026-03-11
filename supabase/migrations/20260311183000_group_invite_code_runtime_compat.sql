create or replace function public.generate_group_invite_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (
      select 1
      from public.groups
      where invite_code = v_code
    );
  end loop;

  return v_code;
end;
$$;

do $$
declare
  v_group_id uuid;
begin
  for v_group_id in
    select id
    from public.groups
    where invite_code is null
       or btrim(invite_code) = ''
  loop
    update public.groups
    set invite_code = public.generate_group_invite_code()
    where id = v_group_id;
  end loop;
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
    coalesce(nullif(btrim(v_user.full_name), ''), 'Member'),
    true,
    false,
    0,
    now()
  )
  on conflict (group_id, user_id) do update
  set
    is_admin = true,
    display_name = coalesce(public.group_members.display_name, excluded.display_name);

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
