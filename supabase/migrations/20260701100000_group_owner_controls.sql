create or replace function archive_group(collection uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update collections
  set
    visibility = 'archived'::collection_visibility,
    public_status = 'archived'::collection_visibility,
    archived_at = now()
  where id = collection
    and creator_user_id = auth.uid();

  if not found then
    raise exception 'Only the group owner can archive this group';
  end if;
end;
$$;

create or replace function transfer_group_ownership(
  collection uuid,
  new_owner_public_id text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_owner uuid := auth.uid();
  new_owner uuid;
begin
  if current_owner is null then
    raise exception 'Authentication required';
  end if;

  select id
  into new_owner
  from profiles
  where public_id = regexp_replace(coalesce(new_owner_public_id, ''), '\D', '', 'g')
  limit 1;

  if new_owner is null then
    raise exception 'Collect ID not found';
  end if;

  update collections
  set creator_user_id = new_owner
  where id = collection
    and creator_user_id = current_owner;

  if not found then
    raise exception 'Only the group owner can transfer ownership';
  end if;

  insert into collection_members (collection_id, user_id, role, status)
  values (collection, new_owner, 'owner'::member_role, 'active'::member_status)
  on conflict (collection_id, user_id, role)
  do update set status = 'active'::member_status;

  if new_owner <> current_owner then
    delete from collection_members
    where collection_id = collection
      and user_id = current_owner
      and role = 'owner'::member_role;

    insert into collection_members (collection_id, user_id, role, status)
    values (
      collection,
      current_owner,
      'admin'::member_role,
      'active'::member_status
    )
    on conflict (collection_id, user_id, role)
    do update set status = 'active'::member_status;
  end if;
end;
$$;

revoke execute on function archive_group(uuid) from public, anon, authenticated;
grant execute on function archive_group(uuid) to authenticated;

revoke execute on function transfer_group_ownership(uuid, text)
from public, anon, authenticated;
grant execute on function transfer_group_ownership(uuid, text) to authenticated;
