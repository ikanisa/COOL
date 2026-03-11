create or replace function public.get_group_invite_preview(
  p_invite_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group public.groups;
  v_member_count integer := 0;
  v_is_member boolean := false;
begin
  select *
  into v_group
  from public.groups
  where invite_code = upper(btrim(p_invite_code))
  limit 1;

  if v_group.id is null then
    return '{}'::jsonb;
  end if;

  select count(*)
  into v_member_count
  from public.group_members
  where group_id = v_group.id;

  if auth.uid() is not null then
    select exists (
      select 1
      from public.group_members
      where group_id = v_group.id
        and user_id = auth.uid()
    )
    into v_is_member;
  end if;

  return to_jsonb(v_group) || jsonb_build_object(
    'member_count', v_member_count,
    'is_member', v_is_member
  );
end;
$$;

grant execute on function public.get_group_invite_preview(text) to authenticated;
