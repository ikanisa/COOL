create or replace function admin_list_users(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('users.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(p.id, coalesce(p.display_name, 'User #' || p.public_id), mask_phone(p.whatsapp_phone), case when p.is_platform_admin then 'admin' else 'active' end, '', p.created_at) order by p.created_at desc)
    from profiles p
    where (
        p_search is null
        or p.display_name ilike '%' || p_search || '%'
        or p.public_id = p_search
      )
      and (
        p_status is null
        or (p_status = 'admin' and p.is_platform_admin)
        or (p_status = 'active' and not p.is_platform_admin)
      )
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_unallocated(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return admin_list_payment_events(p_search, coalesce(p_status, 'needs_review'));
end;
$$;

create or replace function admin_list_ledger(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('ledger.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(le.id, le.entry_type, le.collection_id::text, le.visibility, le.amount_rwf::text || ' RWF', le.created_at) order by le.created_at desc)
    from ledger_entries le
    where (
        p_search is null
        or le.entry_type ilike '%' || p_search || '%'
        or le.collection_id::text = p_search
      )
      and (
        p_status is null
        or le.visibility = p_status
        or le.entry_type = p_status
      )
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_receivers(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('receivers.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(cr.id, cr.label, mask_phone(cr.momo_number), case when cr.is_active then 'active' else 'inactive' end, cr.network, cr.created_at) order by cr.created_at desc)
    from collection_receivers cr
    where (
        p_search is null
        or cr.label ilike '%' || p_search || '%'
        or cr.network ilike '%' || p_search || '%'
      )
      and (
        p_status is null
        or (p_status = 'active' and cr.is_active)
        or (p_status = 'inactive' and not cr.is_active)
      )
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_audit_logs(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('audit.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(a.id, a.action, a.entity_type, 'logged', '', a.created_at) order by a.created_at desc)
    from audit_logs a
    where (
        p_search is null
        or a.action ilike '%' || p_search || '%'
        or a.entity_type ilike '%' || p_search || '%'
      )
      and (p_status is null or p_status = 'logged')
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_feature_flags(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('feature_flags.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(gen_random_uuid(), key, description, case when enabled then 'enabled' else 'disabled' end, '', updated_at) order by key)
    from feature_flags
    where (
        p_search is null
        or key ilike '%' || p_search || '%'
        or description ilike '%' || p_search || '%'
      )
      and (
        p_status is null
        or (p_status = 'enabled' and enabled)
        or (p_status = 'disabled' and not enabled)
      )
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_settings(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('settings.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(gen_random_uuid(), key, description, case when is_sensitive then 'sensitive' else 'normal' end, '', updated_at) order by key)
    from system_settings
    where (
        p_search is null
        or key ilike '%' || p_search || '%'
        or description ilike '%' || p_search || '%'
      )
      and (
        p_status is null
        or (p_status = 'sensitive' and is_sensitive)
        or (p_status = 'normal' and not is_sensitive)
      )
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_list_admin_users(p_search text default null, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('admin_users.read');
  return jsonb_build_object('rows', coalesce((
    select jsonb_agg(_admin_row(p.id, coalesce(p.display_name, 'User #' || p.public_id), ar.name, 'admin', '', aur.created_at) order by aur.created_at desc)
    from admin_user_roles aur
    join profiles p on p.id = aur.user_id
    join admin_roles ar on ar.id = aur.role_id
    where aur.revoked_at is null
      and (
        p_search is null
        or p.display_name ilike '%' || p_search || '%'
        or p.public_id = p_search
        or ar.name ilike '%' || p_search || '%'
      )
      and (
        p_status is null
        or p_status = 'admin'
        or ar.name = p_status
      )
  ), '[]'::jsonb));
end;
$$;

create or replace function admin_system_health(p_id text default 'system')
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('system_health.read');
  return jsonb_build_object(
    'id', coalesce(nullif(p_id, ''), 'system'),
    'database', 'healthy',
    'auth', 'configured',
    'parser_pending_sms', (select count(*) from raw_payment_sms where parse_status = 'pending'),
    'failed_sms_parse', (select count(*) from raw_payment_sms where parse_status = 'failed'),
    'unallocated_events', (select count(*) from parsed_payment_events where allocation_status in ('unallocated', 'ambiguous', 'needs_review')),
    'checked_at', now()
  );
end;
$$;
