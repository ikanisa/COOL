begin;

-- Registered users and group members are separate operational populations.
-- A member has at least one active collection membership; a user has completed
-- sign-in/profile creation but has not yet joined a group.
create or replace function public._admin_list_people_by_membership(
  p_has_active_group boolean,
  p_search text,
  p_status text,
  p_limit integer,
  p_offset integer,
  p_sort text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('users.read');

  with base as (
    select
      profile.id,
      'Collect ID ' || profile.public_id as title,
      public.mask_phone(profile.whatsapp_phone) as subtitle,
      case
        when profile.is_platform_admin then 'admin'
        when p_has_active_group then 'active'
        else 'registered'
      end as status,
      profile.created_at,
      profile.updated_at,
      coalesce(member_count.active_groups, 0)::integer as active_groups,
      jsonb_build_object(
        'public_id', profile.public_id,
        'display_name', profile.display_name,
        'whatsapp_masked', public.mask_phone(profile.whatsapp_phone),
        'country_code', coalesce(profile.country_code, 'RW'),
        'currency_code', coalesce(profile.currency_code, 'RWF'),
        'momo_provider', profile.momo_provider,
        'momo_masked', public.mask_phone(profile.momo_number),
        'has_revolut_profile',
          profile.revolut_link is not null and profile.revolut_account is not null,
        'account_last4', case
          when profile.revolut_account is null then null
          else right(regexp_replace(profile.revolut_account, '[^A-Za-z0-9]', '', 'g'), 4)
        end,
        'active_groups', coalesce(member_count.active_groups, 0),
        'is_platform_admin', profile.is_platform_admin,
        'updated_at', profile.updated_at
      ) as extra
    from public.profiles profile
    left join lateral (
      select count(distinct member.collection_id) as active_groups
      from public.collection_members member
      join public.collections collection on collection.id = member.collection_id
      where member.user_id = profile.id
        and member.status = 'active'
        and collection.archived_at is null
    ) member_count on true
    where case
      when p_has_active_group then coalesce(member_count.active_groups, 0) > 0
      else coalesce(member_count.active_groups, 0) = 0
    end
  ), filtered as (
    select *
    from base
    where (
      nullif(btrim(coalesce(p_status, '')), '') is null
      or status = btrim(p_status)
    ) and (
      nullif(btrim(coalesce(p_search, '')), '') is null
      or title ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'display_name', '') ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'whatsapp_masked', '') ilike '%' || btrim(p_search) || '%'
      or coalesce(extra ->> 'country_code', '') ilike '%' || btrim(p_search) || '%'
    )
  ), counted as (
    select filtered.*, count(*) over () as total_count
    from filtered
    order by
      case when p_sort = 'created_at_asc' then created_at end asc nulls last,
      created_at desc
    limit least(greatest(coalesce(p_limit, 25), 1), 100)
    offset greatest(coalesce(p_offset, 0), 0)
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      jsonb_build_object(
        'id', id,
        'title', title,
        'subtitle', subtitle,
        'status', status,
        'amount', active_groups::text || ' groups',
        'created_at', created_at
      ) || extra order by created_at desc
    ), '[]'::jsonb),
    'total', coalesce(max(total_count), 0)
  ) into result
  from counted;

  return result;
end;
$$;

create or replace function public.admin_list_members(
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public._admin_list_people_by_membership(
    true, p_search, p_status, p_limit, p_offset, p_sort
  );
$$;

create or replace function public.admin_list_non_member_users(
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public._admin_list_people_by_membership(
    false, p_search, p_status, p_limit, p_offset, p_sort
  );
$$;

revoke all on function public._admin_list_people_by_membership(
  boolean, text, text, integer, integer, text
) from public, anon, authenticated;
revoke all on function public.admin_list_members(
  text, text, integer, integer, text
) from public, anon;
revoke all on function public.admin_list_non_member_users(
  text, text, integer, integer, text
) from public, anon;
grant execute on function public.admin_list_members(
  text, text, integer, integer, text
) to authenticated, service_role;
grant execute on function public.admin_list_non_member_users(
  text, text, integer, integer, text
) to authenticated, service_role;

insert into public.admin_navigation_items
  (key, label, icon_key, route_path, required_permission, display_order, enabled, metadata)
values
  ('users', 'Users', 'person', '/admin/users', 'users.read', 25, true,
    '{"population":"registered_without_active_group"}'::jsonb)
on conflict (key) do update set
  label = excluded.label,
  icon_key = excluded.icon_key,
  route_path = excluded.route_path,
  required_permission = excluded.required_permission,
  display_order = excluded.display_order,
  enabled = excluded.enabled,
  metadata = excluded.metadata,
  updated_at = now(),
  updated_reason = 'Separate registered users from active group members';

update public.admin_navigation_items
set label = 'Members',
    route_path = '/admin/members',
    display_order = 30,
    metadata = coalesce(metadata, '{}'::jsonb) ||
      '{"population":"active_group_members"}'::jsonb,
    updated_at = now(),
    updated_reason = 'Separate registered users from active group members'
where key = 'members';

update public.admin_queue_specs
set enabled = false,
    updated_at = now(),
    updated_reason = 'Split into registered users and active group members'
where rpc_name = 'admin_list_users';

insert into public.admin_queue_specs
  (rpc_name, title, subtitle, required_permission, display_order, enabled, metadata)
values
  ('admin_list_non_member_users', 'Users',
    'Registered users who have not joined any active group.',
    'users.read', 18, true, '{"population":"registered_without_active_group"}'::jsonb),
  ('admin_list_members', 'Members',
    'Users with at least one active group membership.',
    'users.read', 20, true, '{"population":"active_group_members"}'::jsonb)
on conflict (rpc_name) do update set
  title = excluded.title,
  subtitle = excluded.subtitle,
  required_permission = excluded.required_permission,
  display_order = excluded.display_order,
  enabled = excluded.enabled,
  metadata = excluded.metadata,
  updated_at = now(),
  updated_reason = 'Separate registered users from active group members';

insert into public.admin_queue_filter_options
  (rpc_name, filter_kind, value, label, display_order, enabled)
values
  ('admin_list_non_member_users', 'status', '', 'All', 10, true),
  ('admin_list_non_member_users', 'status', 'registered', 'Registered', 20, true),
  ('admin_list_non_member_users', 'status', 'admin', 'Admin', 30, true),
  ('admin_list_members', 'status', '', 'All', 10, true),
  ('admin_list_members', 'status', 'active', 'Active', 20, true),
  ('admin_list_members', 'status', 'admin', 'Admin', 30, true)
on conflict (rpc_name, filter_kind, value) do update set
  label = excluded.label,
  display_order = excluded.display_order,
  enabled = excluded.enabled;

commit;
