begin;

-- Group roles are independent of pre-approved platform Admin operators.
-- Only the current private-group owner may promote an existing active member.
create or replace function collect_member_actions.add_owned_group_admin(
  p_collection uuid, p_public_id text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  group_row public.collections%rowtype;
  target_user uuid;
  clean_id text := btrim(coalesce(p_public_id, ''));
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  -- Share the owner-control lock: queued requests re-check current authority
  -- after a concurrent ownership transfer or archive, rather than trusting it.
  select * into group_row from public.collections where id = p_collection for update;
  if group_row.id is null or group_row.creator_user_id is distinct from actor
     or group_row.is_platform_sponsored
     or group_row.public_status not in ('private', 'archived') then
    raise exception 'Only the current owner can add a private group admin' using errcode = '42501';
  end if;
  if group_row.archived_at is not null or group_row.public_status = 'archived' then
    raise exception 'Archived groups cannot add admins' using errcode = '22023';
  end if;
  if clean_id !~ '^[0-9]{6}$' then
    raise exception 'Enter a 6 digit Collect ID.' using errcode = '22023';
  end if;
  -- Resolve the ID only within this group's active membership, never expose
  -- global account existence, phone numbers or names through this endpoint.
  select p.id into target_user from public.profiles p
  where p.public_id = clean_id and p.id <> actor
    and exists(select 1 from public.collection_members m
      where m.collection_id = p_collection and m.user_id = p.id and m.status = 'active');
  if target_user is null then
    raise exception 'Choose another active group member.' using errcode = '22023';
  end if;
  -- Lock and re-check membership too; a removed/left member must not be revived.
  perform 1 from public.collection_members
    where collection_id = p_collection and user_id = target_user for update;
  if not exists(select 1 from public.collection_members where collection_id = p_collection
    and user_id = target_user and status = 'active') then
    raise exception 'Choose another active group member.' using errcode = '22023';
  end if;
  if not exists(select 1 from public.collection_members where collection_id = p_collection
    and user_id = target_user and role = 'admin' and status = 'active') then
    insert into public.collection_members(collection_id, user_id, role, status)
    values(p_collection, target_user, 'admin', 'active')
    on conflict(collection_id, user_id, role) do update set status = 'active';
    insert into public.audit_logs(actor_user_id, action, entity_type, entity_id, metadata)
    values(actor, 'collection.admin_added', 'collection', p_collection,
      jsonb_build_object('member_public_id', clean_id));
  end if;
  -- Lost-response retries return the same minimal, verifiable result and do
  -- not create a second role or audit event. No ownership/payment/Admin writes.
  return jsonb_build_object('collection_id', p_collection, 'public_id', clean_id,
    'role', 'admin', 'status', 'active');
end;
$$;
revoke all on function collect_member_actions.add_owned_group_admin(uuid,text) from public,anon,authenticated;
grant execute on function collect_member_actions.add_owned_group_admin(uuid,text) to authenticated;

create or replace function public.add_group_admin(collection uuid, member_public_id text)
returns jsonb language sql security invoker set search_path = ''
as $$ select collect_member_actions.add_owned_group_admin(collection, member_public_id); $$;
revoke all on function public.add_group_admin(uuid,text) from public,anon,authenticated;
grant execute on function public.add_group_admin(uuid,text) to authenticated;

notify pgrst, 'reload schema';
commit;
