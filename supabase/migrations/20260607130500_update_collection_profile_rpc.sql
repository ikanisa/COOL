create or replace function update_collection_profile(
  collection uuid,
  group_name text,
  group_description text,
  group_image_url text default null,
  group_accent_color_hex text default null,
  group_is_public boolean default false,
  group_recurring_cadence text default 'monthly'
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not user_is_collection_admin(collection, auth.uid()) then
    raise exception 'Only collection admins can update the group profile';
  end if;
  if nullif(trim(group_name), '') is null then
    raise exception 'Group name is required';
  end if;

  update collections
  set
    title = trim(group_name),
    description = trim(coalesce(group_description, '')),
    cover_image_url = nullif(trim(group_image_url), ''),
    accent_color_hex = nullif(trim(group_accent_color_hex), ''),
    is_public = coalesce(group_is_public, false),
    recurring_cadence = coalesce(nullif(trim(group_recurring_cadence), ''), 'monthly'),
    updated_at = now()
  where id = collection;

  if not found then
    raise exception 'Group not found';
  end if;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'collection.profile_updated',
    'collection',
    collection,
    jsonb_build_object(
      'is_public', coalesce(group_is_public, false),
      'recurring_cadence', coalesce(nullif(trim(group_recurring_cadence), ''), 'monthly')
    )
  );
end;
$$;

revoke execute on function update_collection_profile(uuid, text, text, text, text, boolean, text)
  from public, anon, authenticated;
grant execute on function update_collection_profile(uuid, text, text, text, text, boolean, text)
  to authenticated;
