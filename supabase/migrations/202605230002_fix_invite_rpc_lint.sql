create or replace function create_collection_invite(
  collection uuid,
  target_phone_hash text default null,
  target_public_id text default null,
  invite_role member_role default 'member'
)
returns table (
  id uuid,
  invite_token text,
  invite_token_hash text,
  expires_at timestamptz,
  role member_role
)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  plain_token text;
  hashed_token text;
  invite_id uuid;
  target_user_id uuid;
  invite_expires_at timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if not public.user_is_collection_admin(collection, auth.uid()) then
    raise exception 'Only collection admins can invite members';
  end if;

  if invite_role = 'owner' then
    raise exception 'Owner role cannot be granted by invite';
  end if;

  if target_phone_hash is null and target_public_id is null then
    raise exception 'Invite requires a phone number or Collect public ID';
  end if;

  if target_public_id is not null then
    if target_public_id !~ '^[0-9]{6}$' then
      raise exception 'Collect public ID must be 6 digits';
    end if;

    select p.id into target_user_id
    from profiles p
    where p.public_id::text = target_public_id;
  end if;

  plain_token := encode(gen_random_bytes(18), 'hex');
  hashed_token := encode(digest(plain_token, 'sha256'), 'hex');

  insert into collection_invites (
    collection_id,
    invite_token_hash,
    invited_by,
    invited_phone_hash,
    role
  )
  values (
    collection,
    hashed_token,
    auth.uid(),
    target_phone_hash,
    invite_role
  )
  returning collection_invites.id, collection_invites.expires_at
    into invite_id, invite_expires_at;

  if target_user_id is not null then
    insert into collection_members (collection_id, user_id, role, status)
    values (collection, target_user_id, invite_role, 'invited')
    on conflict on constraint collection_members_collection_id_user_id_role_key do update
      set status = 'invited';
  end if;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    auth.uid(),
    'collection.invite_created',
    'collection',
    collection,
    jsonb_build_object(
      'role', invite_role,
      'target_public_id_present', target_public_id is not null,
      'target_phone_hash_present', target_phone_hash is not null
    )
  );

  return query select
    invite_id,
    plain_token,
    hashed_token,
    invite_expires_at,
    invite_role;
end;
$$;
