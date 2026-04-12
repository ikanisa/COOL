-- ============================================================================
-- Cool App - public group member preview
-- ============================================================================

create or replace function public.can_view_group_members_preview(
  p_group_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.groups g
    where g.id = p_group_id
      and (
        g.visibility = 'public'
        or g.creator_id = auth.uid()
        or public.is_group_member(g.id)
        or public.is_admin_user()
        or exists (
          select 1
          from public.partners p
          where public.bank_is_partner_admin(p.id)
            and public.group_belongs_to_bank_partner(g.id, p.id)
        )
      )
  );
$$;

revoke all on function public.can_view_group_members_preview(uuid) from public;
grant execute on function public.can_view_group_members_preview(uuid)
  to anon, authenticated, service_role;

create or replace function public.get_group_members_preview(
  p_group_id uuid,
  p_limit integer default 100
)
returns table (
  display_name text,
  is_admin boolean,
  is_anonymous boolean,
  joined_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_group_id is null then
    raise exception 'Group id is required.';
  end if;

  if not public.can_view_group_members_preview(p_group_id) then
    raise exception 'Not authorized to view this group member preview.';
  end if;

  return query
  with scoped_members as (
    select
      case
        when coalesce(gm.is_anonymous, false) then 'Anonymous member'
        else coalesce(
          nullif(btrim(gm.display_name), ''),
          nullif(btrim(u.public_user_id), ''),
          'Member'
        )
      end as display_name,
      coalesce(gm.is_admin, false) as is_admin,
      coalesce(gm.is_anonymous, false) as is_anonymous,
      gm.joined_at
    from public.group_members gm
    left join public.users u
      on u.id = gm.user_id
    where gm.group_id = p_group_id
  )
  select
    sm.display_name,
    sm.is_admin,
    sm.is_anonymous,
    sm.joined_at,
    count(*) over() as total_count
  from scoped_members sm
  order by sm.is_admin desc, sm.joined_at asc nulls last, sm.display_name asc
  limit greatest(coalesce(p_limit, 100), 1);
end;
$$;

revoke all on function public.get_group_members_preview(uuid, integer) from public;
grant execute on function public.get_group_members_preview(uuid, integer)
  to anon, authenticated, service_role;
