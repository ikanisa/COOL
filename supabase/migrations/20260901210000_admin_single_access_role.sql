begin;

-- Collect exposes one combined Admin access level. The existing
-- platform_owner row remains the internal permission carrier so deployed
-- permission checks stay compatible, but all other role assignments are
-- retired and are never exposed to the product UI.
update public.admin_roles
set description = 'Combined Collect Admin access'
where name = 'platform_owner';

insert into public.admin_role_permissions (role_id, permission_name)
select role.id, permission.name
from public.admin_roles role
cross join public.admin_permissions permission
where role.name = 'platform_owner'
on conflict do nothing;

with combined_role as (
  select id from public.admin_roles where name = 'platform_owner'
), existing_admins as (
  select distinct profile.id
  from public.profiles profile
  where coalesce(profile.is_platform_admin, false)
     or exists (
       select 1
       from public.admin_user_roles user_role
       where user_role.user_id = profile.id
         and user_role.revoked_at is null
     )
)
insert into public.admin_user_roles (user_id, role_id, granted_by, reason)
select existing_admin.id, combined_role.id, null,
       'Consolidated into combined Admin access'
from existing_admins existing_admin
cross join combined_role
where not exists (
  select 1
  from public.admin_user_roles active_role
  where active_role.user_id = existing_admin.id
    and active_role.role_id = combined_role.id
    and active_role.revoked_at is null
);

update public.admin_user_roles user_role
set revoked_at = now(),
    revoke_reason = 'Replaced by combined Admin access'
from public.admin_roles role
where role.id = user_role.role_id
  and role.name <> 'platform_owner'
  and user_role.revoked_at is null;

-- Remove the legacy boolean bypass after every legacy owner has a durable
-- combined-role assignment.
update public.profiles
set is_platform_admin = false
where coalesce(is_platform_admin, false);

create or replace function public.admin_list_admin_users(
  p_search text default null,
  p_status text default null,
  p_limit integer default 25,
  p_offset integer default 0,
  p_sort text default 'created_at_desc'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  perform public.assert_admin_permission('admin_users.read');

  with admin_profiles as (
    select
      profile.id,
      profile.public_id,
      profile.whatsapp_phone,
      profile.created_at,
      exists (
        select 1
        from public.admin_user_roles user_role
        join public.admin_roles role on role.id = user_role.role_id
        where user_role.user_id = profile.id
          and user_role.revoked_at is null
          and role.name = 'platform_owner'
      ) as admin_active
    from public.profiles profile
    where exists (
      select 1
      from public.admin_user_roles historical_role
      where historical_role.user_id = profile.id
    )
  ), filtered as (
    select *
    from admin_profiles
    where (
      p_search is null
      or public_id = p_search
      or public.mask_phone(whatsapp_phone) ilike '%' || p_search || '%'
    )
      and (
        p_status is null
        or (p_status in ('admin', 'active') and admin_active)
        or (p_status = 'revoked' and not admin_active)
      )
  ), ordered as (
    select filtered.*,
      row_number() over (
        order by
          case when coalesce(p_sort, 'created_at_desc') = 'created_at_asc'
            then filtered.created_at end asc nulls last,
          filtered.created_at desc,
          filtered.id
      ) as admin_rank
    from filtered
    order by
      case when coalesce(p_sort, 'created_at_desc') = 'created_at_asc'
        then filtered.created_at end asc nulls last,
      filtered.created_at desc,
      filtered.id
    limit v_limit offset v_offset
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(
      public._admin_row(
        ordered.id,
        coalesce(public.mask_phone(ordered.whatsapp_phone), ordered.public_id),
        '',
        case when ordered.admin_active then 'active' else 'revoked' end,
        'Admin',
        ordered.created_at,
        jsonb_build_object(
          'public_id', ordered.public_id,
          'phone_masked', public.mask_phone(ordered.whatsapp_phone),
          'admin_access', ordered.admin_active
        )
      ) order by ordered.admin_rank
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result
  from ordered;

  return coalesce(
    v_result,
    jsonb_build_object('rows', '[]'::jsonb, 'total', 0)
  );
end;
$$;

create or replace function public.admin_get_admin_user(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin_permission('admin_users.read');
  return coalesce((
    select jsonb_build_object(
      'id', profile.id,
      'public_id', profile.public_id,
      'phone_masked', public.mask_phone(profile.whatsapp_phone),
      'status', case when access.admin_active then 'active' else 'revoked' end,
      'admin_access', access.admin_active,
      'active_roles', case when access.admin_active
        then '["admin"]'::jsonb else '[]'::jsonb end,
      'created_at', profile.created_at
    )
    from public.profiles profile
    cross join lateral (
      select exists (
        select 1
        from public.admin_user_roles user_role
        join public.admin_roles role on role.id = user_role.role_id
        where user_role.user_id = profile.id
          and user_role.revoked_at is null
          and role.name = 'platform_owner'
      ) as admin_active
    ) access
    where profile.id = p_id
      and exists (
        select 1
        from public.admin_user_roles historical_role
        where historical_role.user_id = profile.id
      )
  ), '{}'::jsonb);
end;
$$;

create or replace function public.admin_set_user_access(
  p_user_id uuid,
  p_active boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role_id uuid;
  v_reason text := trim(coalesce(p_reason, ''));
  v_active_count integer;
begin
  perform public.assert_admin_permission('admin_users.manage');
  if v_reason = '' then raise exception 'Reason is required'; end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'Admin user profile not found';
  end if;

  select id into v_role_id
  from public.admin_roles
  where name = 'platform_owner';
  if v_role_id is null then raise exception 'Combined Admin role not found'; end if;

  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));

  if p_active then
    if exists (
      select 1 from public.admin_user_roles
      where user_id = p_user_id
        and role_id = v_role_id
        and revoked_at is null
    ) then
      raise exception 'Admin access is already active';
    end if;

    insert into public.admin_user_roles (user_id, role_id, granted_by, reason)
    values (p_user_id, v_role_id, auth.uid(), v_reason);

    perform public.create_audit_log(
      'admin.access.activated',
      'profile',
      p_user_id,
      jsonb_build_object('access', 'admin', 'reason', v_reason)
    );
    return jsonb_build_object('ok', true, 'status', 'active');
  end if;

  if p_user_id = auth.uid() then
    raise exception 'You cannot deactivate your own Admin access';
  end if;

  select count(*) into v_active_count
  from public.admin_user_roles active_role
  where active_role.role_id = v_role_id
    and active_role.revoked_at is null;
  if v_active_count <= 1 then
    raise exception 'The last Admin cannot be deactivated';
  end if;

  update public.admin_user_roles
  set revoked_at = now(),
      revoked_by = auth.uid(),
      revoke_reason = v_reason
  where user_id = p_user_id
    and role_id = v_role_id
    and revoked_at is null;
  if not found then raise exception 'Active Admin access not found'; end if;

  perform public.create_audit_log(
    'admin.access.deactivated',
    'profile',
    p_user_id,
    jsonb_build_object('access', 'admin', 'reason', v_reason)
  );
  return jsonb_build_object('ok', true, 'status', 'revoked');
end;
$$;

revoke execute on function public.admin_grant_user_role(uuid, text, text)
from authenticated;
revoke execute on function public.admin_revoke_user_role(uuid, text, text)
from authenticated;
revoke execute on function public.admin_set_user_access(uuid, boolean, text)
from public, anon;
grant execute on function public.admin_set_user_access(uuid, boolean, text)
to authenticated;

comment on function public.admin_set_user_access(uuid, boolean, text) is
  'Activates or deactivates the single combined Collect Admin access level with an audited reason.';

commit;
