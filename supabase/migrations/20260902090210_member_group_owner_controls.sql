begin;

-- Keep table DML revoked. These two reviewed member operations have a small,
-- non-exposed implementation schema; they do not inherit platform Admin powers.
-- Do not grant USAGE on the existing private schema, whose helpers have a
-- different trust boundary.
create schema if not exists collect_member_actions;
revoke all on schema collect_member_actions from public, anon, authenticated;
grant usage on schema collect_member_actions to authenticated;

create or replace function collect_member_actions.archive_owned_group(p_collection uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  group_row public.collections%rowtype;
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  select * into group_row from public.collections where id = p_collection for update;
  if group_row.id is null or group_row.creator_user_id is distinct from actor
     or group_row.is_platform_sponsored
     or group_row.public_status not in ('private', 'archived') then
    raise exception 'Only the current owner can archive a private group' using errcode = '42501';
  end if;
  -- A lost response can be retried by the same owner without a second event.
  if group_row.archived_at is not null then return; end if;
  update public.collections
  set visibility = 'archived', public_status = 'archived', archived_at = now(), updated_at = now()
  where id = p_collection;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(actor,'collection.archived','collection',p_collection,
    jsonb_build_object('previous_status',group_row.public_status::text));
end;
$$;

create or replace function collect_member_actions.transfer_owned_group(p_collection uuid, p_public_id text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  group_row public.collections%rowtype;
  target_user uuid;
  clean_id text := btrim(coalesce(p_public_id,''));
begin
  if actor is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  -- Serialize transfers/archives and re-check authority after taking the lock.
  select * into group_row from public.collections where id = p_collection for update;
  if group_row.id is null or group_row.creator_user_id is distinct from actor
     or group_row.is_platform_sponsored
     or group_row.public_status not in ('private', 'archived') then
    raise exception 'Only the current owner can transfer a private group' using errcode = '42501';
  end if;
  if group_row.archived_at is not null or group_row.public_status = 'archived' then
    raise exception 'Archived groups cannot be transferred' using errcode = '22023';
  end if;
  if clean_id !~ '^[0-9]{6}$' then
    raise exception 'Enter a 6 digit Collect ID.' using errcode = '22023';
  end if;
  -- Preserve the existing contract: a registered Collect ID may receive
  -- ownership. This endpoint never looks up or returns a personal name.
  select id into target_user from public.profiles where public_id = clean_id for key share;
  if target_user is null or target_user = actor then
    raise exception 'Choose another registered Collect ID' using errcode = '22023';
  end if;

  update public.collections set creator_user_id = target_user, updated_at = now()
  where id = p_collection;
  -- Preserve historical memberships, but never leave a stale active owner.
  update public.collection_members set status = 'removed'
  where collection_id = p_collection and role = 'owner' and user_id is distinct from target_user;
  insert into public.collection_members(collection_id,user_id,role,status)
  values(p_collection,target_user,'owner','active')
  on conflict(collection_id,user_id,role) do update set status = 'active';
  insert into public.collection_members(collection_id,user_id,role,status)
  values(p_collection,actor,'admin','active')
  on conflict(collection_id,user_id,role) do update set status = 'active';
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(actor,'collection.ownership_transferred','collection',p_collection,
    jsonb_build_object('previous_owner_id',actor,'new_owner_id',target_user));
  -- Receiver, SMS consent, ledger and platform Admin roles are intentionally
  -- unchanged. Transferring a group is not approval to redirect its funds.
end;
$$;

revoke all on function collect_member_actions.archive_owned_group(uuid) from public,anon,authenticated;
revoke all on function collect_member_actions.transfer_owned_group(uuid,text) from public,anon,authenticated;
grant execute on function collect_member_actions.archive_owned_group(uuid) to authenticated;
grant execute on function collect_member_actions.transfer_owned_group(uuid,text) to authenticated;

-- Keep the installed member clients' API signatures; no direct table grants.
create or replace function public.archive_group(collection uuid)
returns void language sql security invoker set search_path = ''
as $$ select collect_member_actions.archive_owned_group(collection); $$;
create or replace function public.transfer_group_ownership(collection uuid, new_owner_public_id text)
returns void language sql security invoker set search_path = ''
as $$ select collect_member_actions.transfer_owned_group(collection,new_owner_public_id); $$;
revoke all on function public.archive_group(uuid) from public,anon,authenticated;
revoke all on function public.transfer_group_ownership(uuid,text) from public,anon,authenticated;
grant execute on function public.archive_group(uuid) to authenticated;
grant execute on function public.transfer_group_ownership(uuid,text) to authenticated;

commit;
