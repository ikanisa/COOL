-- ==========================================================================
-- Cool App — Group RLS repair
-- ==========================================================================
-- Fixes recursive/incorrect policies on groups, group_members, and
-- group_contributions by routing membership checks through a security-definer
-- helper instead of querying the protected tables directly from policy bodies.
-- ==========================================================================

create or replace function public.is_group_member(
  p_group_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (
      select exists (
        select 1
        from public.group_members
        where group_id = p_group_id
          and user_id = p_user_id
      )
    ),
    false
  );
$$;

grant execute on function public.is_group_member(uuid, uuid) to anon;
grant execute on function public.is_group_member(uuid, uuid) to authenticated;

drop policy if exists "groups_select_public" on public.groups;
create policy "groups_select_public"
  on public.groups for select
  using (
    visibility = 'public'
    or creator_id = auth.uid()
    or public.is_group_member(id)
  );

drop policy if exists "groups_update_creator" on public.groups;
create policy "groups_update_creator"
  on public.groups for update
  using (auth.uid() = creator_id)
  with check (auth.uid() = creator_id);

drop policy if exists "group_members_select" on public.group_members;
create policy "group_members_select"
  on public.group_members for select
  using (
    user_id = auth.uid()
    or public.is_group_member(group_id)
  );

drop policy if exists "group_members_insert" on public.group_members;
create policy "group_members_insert"
  on public.group_members for insert
  with check (
    user_id = auth.uid()
    and exists (
      select 1
      from public.groups g
      where g.id = group_id
        and (
          g.visibility = 'public'
          or g.creator_id = auth.uid()
          or public.is_group_member(g.id)
        )
    )
  );

drop policy if exists "contributions_select" on public.group_contributions;
create policy "contributions_select"
  on public.group_contributions for select
  using (public.is_group_member(group_id));

drop policy if exists "contributions_insert" on public.group_contributions;
create policy "contributions_insert"
  on public.group_contributions for insert
  with check (
    auth.uid() = user_id
    and public.is_group_member(group_id)
  );
