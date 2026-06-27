begin;

create or replace function is_platform_admin(user_uuid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.role() = 'service_role' or user_uuid = auth.uid() then
      coalesce((select p.is_platform_admin from profiles p where p.id = user_uuid), false)
      or exists (
        select 1
        from admin_user_roles aur
        join admin_roles ar on ar.id = aur.role_id
        where aur.user_id = user_uuid
          and aur.revoked_at is null
          and ar.name = 'platform_owner'
      )
    else false
  end;
$$;

create or replace function has_admin_permission(permission text, user_uuid uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case
    when auth.role() = 'service_role' or user_uuid = auth.uid() then
      public.is_platform_admin(user_uuid)
      or exists (
        select 1
        from admin_user_roles aur
        join admin_role_permissions arp on arp.role_id = aur.role_id
        where aur.user_id = user_uuid
          and aur.revoked_at is null
          and arp.permission_name = permission
      )
    else false
  end;
$$;

create or replace function current_user_has_admin_permission(permission text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_admin_permission(permission, auth.uid());
$$;

revoke execute on function is_platform_admin(uuid) from public, anon;
revoke execute on function has_admin_permission(text, uuid) from public, anon;
revoke execute on function current_user_has_admin_permission(text) from public, anon;
grant execute on function is_platform_admin(uuid) to authenticated, service_role;
grant execute on function has_admin_permission(text, uuid) to authenticated, service_role;
grant execute on function current_user_has_admin_permission(text) to authenticated, service_role;

comment on function is_platform_admin(uuid) is
  'Authenticated callers may evaluate only auth.uid(); service_role may evaluate arbitrary users for operator administration.';
comment on function has_admin_permission(text, uuid) is
  'Authenticated callers may evaluate only auth.uid(); service_role may evaluate arbitrary users for operator administration.';
comment on function current_user_has_admin_permission(text) is
  'Browser-safe current-user admin permission helper.';

commit;
