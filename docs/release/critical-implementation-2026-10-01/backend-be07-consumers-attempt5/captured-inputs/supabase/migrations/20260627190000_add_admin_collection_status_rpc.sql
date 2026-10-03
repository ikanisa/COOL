create or replace function admin_update_collection_support_status(
  p_collection_id uuid,
  p_status text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  new_visibility collection_visibility;
begin
  perform assert_admin_permission('collections.moderate');

  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Reason is required';
  end if;

  if p_status not in ('private', 'public_rejected', 'archived') then
    raise exception 'Unsupported collection support status';
  end if;

  new_visibility := p_status::collection_visibility;

  update collections
    set public_status = new_visibility,
        visibility = case
          when new_visibility = 'archived'::collection_visibility then 'archived'::collection_visibility
          else 'private'::collection_visibility
        end,
        archived_at = case
          when new_visibility = 'archived'::collection_visibility then now()
          else archived_at
        end,
        updated_at = now()
    where id = p_collection_id;

  if not found then
    raise exception 'Collection not found';
  end if;

  perform create_audit_log(
    'collection.support_status.updated',
    'collection',
    p_collection_id,
    jsonb_build_object('status', p_status, 'reason', p_reason)
  );

  return jsonb_build_object('ok', true, 'status', p_status);
end;
$$;

revoke execute on function admin_update_collection_support_status(uuid, text, text)
  from public, anon;
grant execute on function admin_update_collection_support_status(uuid, text, text)
  to authenticated;
