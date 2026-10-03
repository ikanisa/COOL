begin;

create or replace function admin_set_feature_flag(
  p_key text,
  p_enabled boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_key text := trim(coalesce(p_key, ''));
  normalized_reason text := trim(coalesce(p_reason, ''));
  flag_row feature_flags%rowtype;
begin
  perform assert_admin_permission('feature_flags.manage');

  if normalized_key = '' then
    raise exception 'Feature flag key is required';
  end if;

  if normalized_reason = '' then
    raise exception 'Feature flag change reason is required';
  end if;

  update feature_flags
  set enabled = p_enabled,
      updated_by = auth.uid(),
      updated_reason = normalized_reason,
      updated_at = now()
  where key = normalized_key
  returning * into flag_row;

  if not found then
    raise exception 'Feature flag not found: %', normalized_key;
  end if;

  perform create_audit_log(
    'admin.feature_flag.updated',
    'feature_flag',
    null,
    jsonb_build_object(
      'key', flag_row.key,
      'enabled', flag_row.enabled,
      'reason', normalized_reason
    )
  );

  return jsonb_build_object(
    'ok', true,
    'key', flag_row.key,
    'enabled', flag_row.enabled,
    'updated_at', flag_row.updated_at
  );
end;
$$;

revoke execute on function admin_set_feature_flag(text, boolean, text)
  from public, anon;
grant execute on function admin_set_feature_flag(text, boolean, text)
  to authenticated;

commit;
