-- ============================================================================
-- Admin PWA RBAC + audit contract hardening
-- ============================================================================
-- 1) Materialize legacy users.is_admin rows into admin_role_assignments so the
--    browser can reason about a single role inventory.
-- 2) Expose explicit capabilities on get_admin_access_for_user so frontend and
--    edge middleware can converge on the same access contract.
-- 3) Extend get_admin_audit_log with notes, search filters, and total_count to
--    support pageable audit review in the admin PWA.

insert into public.admin_role_assignments (
  user_id,
  role,
  partner_scope_id,
  granted_by,
  granted_at,
  is_active,
  notes
)
select
  u.id,
  'admin',
  null,
  null,
  coalesce(u.created_at, now()),
  true,
  'Backfilled from legacy users.is_admin for admin PWA parity.'
from public.users u
where u.is_admin = true
  and not exists (
    select 1
    from public.admin_role_assignments ra
    where ra.user_id = u.id
      and ra.role = 'admin'
      and ra.is_active = true
  );

create or replace function public.get_admin_access_for_user(
  p_user_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_has_legacy_admin boolean := false;
  v_has_platform_role boolean := false;
  v_role_rows jsonb := '[]'::jsonb;
  v_bank_ids jsonb := '[]'::jsonb;
  v_has_bank_access boolean := false;
begin
  v_user_id := coalesce(p_user_id, auth.uid());

  if v_user_id is null then
    return jsonb_build_object(
      'has_platform_access', false,
      'has_bank_access', false,
      'has_partner_access', false,
      'has_legacy_admin_flag', false,
      'bank_partner_ids', '[]'::jsonb,
      'partner_admin_ids', '[]'::jsonb,
      'role_assignments', '[]'::jsonb,
      'capabilities', jsonb_build_object(
        'manage_platform', false,
        'manage_users', false,
        'manage_roles', false,
        'manage_config', false,
        'view_analytics', false,
        'view_audit_log', false,
        'view_groups', false,
        'view_savings', false
      )
    );
  end if;

  select coalesce(u.is_admin, false)
  into v_has_legacy_admin
  from public.users u
  where u.id = v_user_id;

  select exists(
    select 1
    from public.admin_role_assignments ra
    where ra.user_id = v_user_id
      and ra.is_active = true
      and ra.role = 'admin'
  )
  into v_has_platform_role;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', ra.id,
        'user_id', ra.user_id,
        'role', ra.role,
        'partner_scope_id', ra.partner_scope_id,
        'partner_name', p.name,
        'granted_by', ra.granted_by,
        'granted_at', ra.granted_at,
        'revoked_at', ra.revoked_at,
        'is_active', ra.is_active,
        'notes', ra.notes
      )
      order by ra.granted_at desc
    ),
    '[]'::jsonb
  )
  into v_role_rows
  from public.admin_role_assignments ra
  left join public.partners p on p.id = ra.partner_scope_id
  where ra.user_id = v_user_id
    and ra.is_active = true;

  select coalesce(jsonb_agg(ra.partner_scope_id), '[]'::jsonb)
  into v_bank_ids
  from public.admin_role_assignments ra
  where ra.user_id = v_user_id
    and ra.is_active = true
    and ra.role = 'bank'
    and ra.partner_scope_id is not null;

  v_has_bank_access := jsonb_array_length(v_bank_ids) > 0;

  return jsonb_build_object(
    'has_platform_access', v_has_legacy_admin or v_has_platform_role,
    'has_bank_access', (v_has_legacy_admin or v_has_platform_role) or v_has_bank_access,
    'has_partner_access', false,
    'has_legacy_admin_flag', v_has_legacy_admin,
    'bank_partner_ids', v_bank_ids,
    'partner_admin_ids', '[]'::jsonb,
    'role_assignments', v_role_rows,
    'capabilities', jsonb_build_object(
      'manage_platform', v_has_legacy_admin or v_has_platform_role,
      'manage_users', v_has_legacy_admin or v_has_platform_role,
      'manage_roles', v_has_legacy_admin or v_has_platform_role,
      'manage_config', v_has_legacy_admin or v_has_platform_role,
      'view_analytics', v_has_legacy_admin or v_has_platform_role,
      'view_audit_log', v_has_legacy_admin or v_has_platform_role,
      'view_groups', (v_has_legacy_admin or v_has_platform_role) or v_has_bank_access,
      'view_savings', (v_has_legacy_admin or v_has_platform_role) or v_has_bank_access
    )
  );
end;
$$;

grant execute on function public.get_admin_access_for_user(uuid) to authenticated;

drop function if exists public.get_admin_audit_log(integer, integer, text, uuid);
drop function if exists public.get_admin_audit_log(integer, integer, text, uuid, text, text);

create or replace function public.get_admin_audit_log(
  p_limit integer default 50,
  p_offset integer default 0,
  p_action text default null,
  p_actor_id uuid default null,
  p_query text default null,
  p_target_table text default null
)
returns table (
  id uuid,
  actor_id uuid,
  actor_name text,
  actor_phone text,
  action text,
  target_table text,
  target_id text,
  old_data jsonb,
  new_data jsonb,
  notes text,
  created_at timestamptz,
  total_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with filtered as (
    select
      a.id,
      a.actor_id,
      u.full_name as actor_name,
      u.phone as actor_phone,
      a.action,
      a.target_table,
      a.target_id,
      a.old_data,
      a.new_data,
      a.notes,
      a.created_at
    from public.admin_audit_log a
    left join public.users u on u.id = a.actor_id
    where (p_action is null or a.action = p_action)
      and (p_actor_id is null or a.actor_id = p_actor_id)
      and (p_target_table is null or a.target_table = p_target_table)
      and (
        p_query is null
        or coalesce(u.full_name, '') ilike '%' || p_query || '%'
        or coalesce(u.phone, '') ilike '%' || p_query || '%'
        or coalesce(a.target_table, '') ilike '%' || p_query || '%'
        or coalesce(a.target_id, '') ilike '%' || p_query || '%'
        or coalesce(a.notes, '') ilike '%' || p_query || '%'
      )
  )
  select
    filtered.id,
    filtered.actor_id,
    filtered.actor_name,
    filtered.actor_phone,
    filtered.action,
    filtered.target_table,
    filtered.target_id,
    filtered.old_data,
    filtered.new_data,
    filtered.notes,
    filtered.created_at,
    count(*) over () as total_count
  from filtered
  order by filtered.created_at desc
  limit greatest(p_limit, 1)
  offset greatest(p_offset, 0);
$$;

grant execute on function public.get_admin_audit_log(integer, integer, text, uuid, text, text)
  to authenticated;
