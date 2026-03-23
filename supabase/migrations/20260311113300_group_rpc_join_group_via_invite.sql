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
    coalesce(nullif(btrim(v_user.full_name), ''), 'Member'),
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
grant execute on function public.join_group_via_invite(text) to authenticated;
