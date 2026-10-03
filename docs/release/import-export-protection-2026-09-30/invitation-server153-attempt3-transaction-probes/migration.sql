begin;

-- Private operation receipts are not bearer credentials. Every read/replay
-- revalidates current Auth and actual group authority before returning a code.
create table collect_member_actions.group_share_rotations (
  request_id uuid primary key,
  collection_id uuid not null,
  actor_id uuid not null,
  session_id uuid not null,
  share_code uuid not null,
  created_at timestamptz not null default clock_timestamp() check(isfinite(created_at))
);
create index group_share_rotations_group_time_idx
  on collect_member_actions.group_share_rotations(collection_id,created_at desc);
alter table collect_member_actions.group_share_rotations enable row level security;
revoke all on collect_member_actions.group_share_rotations from public,anon,authenticated,service_role;

create function collect_member_actions.guard_group_share_rotation() returns trigger
language plpgsql security definer set search_path='' as $$
begin raise exception 'group_share_receipt_immutable' using errcode='55000';end$$;
create trigger group_share_receipt_immutable before update or delete
  on collect_member_actions.group_share_rotations for each row
  execute function collect_member_actions.guard_group_share_rotation();

create function collect_member_actions.require_group_share_actor(p_collection_id uuid,p_rotate boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare sid uuid; u auth.users; s auth.sessions; c public.collections; m record; jwt_exp text:=auth.jwt()->>'exp';
  member collect_hybrid.member_records; claimed_user uuid; authorized boolean:=false;
begin
  if p_collection_id is null or p_rotate is null then
    raise exception 'group_share_request_invalid' using errcode='22023';end if;
  begin sid:=public._lock_notification_registration_session();
  exception when sqlstate '42501' then
    raise exception 'group_share_session_required' using errcode='42501';end;
  if jwt_exp is null or jwt_exp !~ '^[0-9]{1,12}$'
    or jwt_exp::bigint<=extract(epoch from clock_timestamp()) then
    raise exception 'group_share_session_required' using errcode='42501';end if;
  select * into s from auth.sessions where id=sid and user_id=auth.uid();
  if s.id is null or s.created_at is null or not isfinite(s.created_at) or s.created_at>clock_timestamp()
    or (s.not_after is not null and (not isfinite(s.not_after) or s.not_after<=clock_timestamp())) then
    raise exception 'group_share_session_required' using errcode='42501';end if;
  select * into u from auth.users where id=auth.uid() for share;
  if u.id is null or u.deleted_at is not null or coalesce(u.is_anonymous,false)
    or (u.phone_confirmed_at is null and u.email_confirmed_at is null)
    or (u.banned_until is not null and u.banned_until>clock_timestamp()) then
    raise exception 'group_share_session_required' using errcode='42501';end if;
  if p_rotate then
    select * into c from public.collections where id=p_collection_id for update;
  else
    select * into c from public.collections where id=p_collection_id for share;
  end if;
  if c.id is null or c.archived_at is not null then
    raise exception 'group_share_group_unavailable' using errcode='42501';end if;
  if c.creator_user_id=auth.uid() then authorized:=true;
  -- The existing platform-owner exception is retained with current proof locks.
  elsif public.is_platform_admin(auth.uid()) then
    begin perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,
      'platform_owner',array['collections.moderate']);
    exception when sqlstate '42501' then
      raise exception 'group_share_permission_required' using errcode='42501';end;
    authorized:=true;
  else
  for m in select cm.id,cm.user_id,cm.member_record_id from public.collection_members cm
    where cm.collection_id=p_collection_id and cm.status='active'
      and (not p_rotate or cm.role in ('owner','admin','receiver'))
      and (cm.user_id=auth.uid() or collect_hybrid.member_record_belongs_to_user(cm.member_record_id,auth.uid()))
    order by cm.id for share of cm loop
    if m.user_id=auth.uid() then authorized:=true;exit;end if;
    -- Lock both possible account bindings. A lost claim/record in an established
    -- snapshot must serialize or refuse rather than authorize from old EXISTS.
    select * into member from collect_hybrid.member_records where id=m.member_record_id for share;
    claimed_user:=null;
    select claim.user_id into claimed_user from collect_hybrid.member_account_claims claim
      where claim.member_record_id=m.member_record_id for share;
    if member.id is not null and member.lifecycle='active'
      and (member.linked_user_id=auth.uid() or claimed_user=auth.uid()) then authorized:=true;exit;end if;
  end loop;
  end if;
  if not authorized then raise exception 'group_share_permission_required' using errcode='42501';end if;
  if jwt_exp::bigint<=extract(epoch from clock_timestamp()) then
    raise exception 'group_share_session_required' using errcode='42501';end if;
  return sid;
end$$;

create or replace function public.get_group_share_code(p_collection_id uuid)
returns text language plpgsql volatile security definer set search_path='' as $$
declare code uuid;
begin
  perform collect_member_actions.require_group_share_actor(p_collection_id,false);
  select share_code into code from public.collection_share_secrets
    where collection_id=p_collection_id for share;
  if code is null then raise exception 'group_share_group_unavailable' using errcode='42501';end if;
  return code::text;
end$$;

create function public.rotate_group_share_code_v2(p_collection_id uuid,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare sid uuid; receipt collect_member_actions.group_share_rotations; code uuid;
begin
  if p_request_id is null then raise exception 'group_share_request_invalid' using errcode='22023';end if;
  sid:=collect_member_actions.require_group_share_actor(p_collection_id,true);
  select * into receipt from collect_member_actions.group_share_rotations where request_id=p_request_id;
  if receipt.request_id is not null then
    if receipt.actor_id is distinct from auth.uid() or receipt.collection_id is distinct from p_collection_id then
      raise exception 'group_share_request_conflict' using errcode='40001';end if;
    select share_code into code from public.collection_share_secrets where collection_id=p_collection_id for share;
    if code is distinct from receipt.share_code then
      raise exception 'group_share_rotation_superseded' using errcode='55000';end if;
    return jsonb_build_object('contract_version',1,'ok',true,'collection_id',receipt.collection_id,
      'request_id',receipt.request_id,'share_code',receipt.share_code);
  end if;
  -- The locked parent serializes this count and its subsequent receipt insert.
  -- Established snapshots also lock the actual secret row before rotating it.
  perform 1 from public.collection_share_secrets where collection_id=p_collection_id for update;
  if (select count(*) from collect_member_actions.group_share_rotations
      where collection_id=p_collection_id and created_at>clock_timestamp()-interval '1 hour')>=60 then
    raise exception 'group_share_rate_limited' using errcode='55000';end if;
  insert into public.collection_share_secrets(collection_id,share_code,rotated_at,rotated_by)
    values(p_collection_id,gen_random_uuid(),clock_timestamp(),auth.uid())
    on conflict(collection_id) do update set share_code=excluded.share_code,
      rotated_at=excluded.rotated_at,rotated_by=excluded.rotated_by
    returning share_code into code;
  begin
    insert into collect_member_actions.group_share_rotations(request_id,collection_id,actor_id,session_id,share_code)
      values(p_request_id,p_collection_id,auth.uid(),sid,code);
  exception when unique_violation then
    raise exception 'group_share_request_conflict' using errcode='40001';end;
  perform public.create_audit_log('group.share_link_rotated','collection',p_collection_id,
    jsonb_build_object('request_id',p_request_id,'rotated_at',clock_timestamp()));
  return jsonb_build_object('contract_version',1,'ok',true,'collection_id',p_collection_id,
    'request_id',p_request_id,'share_code',code);
end$$;

-- Old clients must refresh/update instead of making an unidentifiable rotation.
create or replace function public.rotate_group_share_code(p_collection_id uuid)
returns text language plpgsql security definer set search_path='' as $$
begin raise exception 'group_share_rotation_request_required' using errcode='22023';end$$;

revoke all on function collect_member_actions.guard_group_share_rotation(),
  collect_member_actions.require_group_share_actor(uuid,boolean)
  from public,anon,authenticated,service_role;
revoke all on function public.get_group_share_code(uuid),public.rotate_group_share_code(uuid),
  public.rotate_group_share_code_v2(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_group_share_code(uuid),public.rotate_group_share_code(uuid),
  public.rotate_group_share_code_v2(uuid,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
