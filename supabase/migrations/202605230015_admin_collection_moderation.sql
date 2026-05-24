create or replace function admin_moderate_collection(
  p_collection_id uuid,
  p_status text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform assert_admin_permission('collections.moderate');
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Reason is required';
  end if;
  if p_status not in ('private', 'public_rejected', 'archived') then
    raise exception 'Unsupported moderation status';
  end if;
  update collections
    set public_status = p_status::collection_visibility,
        visibility = case
          when p_status = 'archived' then 'archived'::collection_visibility
          else 'private'::collection_visibility
        end,
        archived_at = case
          when p_status = 'archived' then now()
          else archived_at
        end
    where id = p_collection_id;
  perform create_audit_log(
    'collection.moderated',
    'collection',
    p_collection_id,
    jsonb_build_object('status', p_status, 'reason', p_reason)
  );
  return jsonb_build_object('ok', true, 'message', 'Collection moderated');
end;
$$;

revoke execute on function admin_moderate_collection(uuid, text, text) from public, anon, authenticated;
grant execute on function admin_moderate_collection(uuid, text, text) to authenticated;
