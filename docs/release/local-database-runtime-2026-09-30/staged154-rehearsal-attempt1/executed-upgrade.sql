begin isolation level serializable;
    do $$begin if current_user<>'postgres' or current_database()<>'postgres'
      or (select rolsuper from pg_roles where rolname=current_user)
      or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
      or (select count(*) from supabase_migrations.schema_migrations)<>153
      or (select max(version) from supabase_migrations.schema_migrations)<>'20260930220000' then
      raise exception 'Exact offline sequential upgrade required';end if;end$$;
    create temp table collect_upgrade_rows(table_name text,rowdata jsonb,n bigint) on commit drop;
    create temp table collect_upgrade_counts(table_name text,n bigint) on commit drop;
    create temp table collect_upgrade_catalog on commit drop as with objects(family,object_name,identity,body) as (
      select 'schema',n.nspname::text,n.nspname::text,to_jsonb(n)-array['oid'] from pg_namespace n where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'relation',coalesce(tn.nspname||'.'||tc.relname,n.nspname||'.'||c.relname),n.nspname||'.'||c.relname,
        jsonb_build_object('owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'kind',c.relkind)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_index ix on ix.indexrelid=c.oid
        left join pg_class tc on tc.oid=ix.indrelid left join pg_namespace tn on tn.oid=tc.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'column',coalesce(tn.nspname||'.'||tc.relname,n.nspname||'.'||c.relname),n.nspname||'.'||c.relname||':'||a.attname,
        jsonb_build_object('type',a.atttypid,'mod',a.atttypmod,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))
        from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
        left join pg_index ix on ix.indexrelid=c.oid left join pg_class tc on tc.oid=ix.indrelid left join pg_namespace tn on tn.oid=tc.relnamespace
        where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations') and a.attnum>0 and not a.attisdropped
      union all select 'routine',n.nspname||'.'||p.proname,n.nspname||'.'||p.proname||':'||pg_get_function_identity_arguments(p.oid),
        jsonb_build_object('owner',p.proowner,'acl',p.proacl,'source',p.prosrc,'config',p.proconfig,'definer',p.prosecdef,'volatile',p.provolatile,'result',p.prorettype)
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'trigger',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||t.tgname,
        jsonb_build_object('enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))
        from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'constraint',n.nspname||'.'||cl.relname,n.nspname||'.'||cl.relname||':'||c.conname,to_jsonb(pg_get_constraintdef(c.oid))
        from pg_constraint c join pg_class cl on cl.oid=c.conrelid join pg_namespace n on n.oid=c.connamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'policy',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||p.polname,
        jsonb_build_object('roles',p.polroles,'command',p.polcmd,'permissive',p.polpermissive,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
        from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
    ) select * from objects;
    do $$begin if exists(select 1 from pg_temp.collect_upgrade_catalog group by family,identity having count(*)<>1)
      or exists(select 1 from pg_temp.collect_upgrade_catalog where identity is null or object_name is null) then
      raise exception 'Catalog identity collision';end if;end$$;
    do $$declare t record;begin
      for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations') and c.relkind in ('r','p') loop
        execute format('insert into pg_temp.collect_upgrade_rows select %L,to_jsonb(t),count(*) from %I.%I t group by to_jsonb(t)',t.nspname||'.'||t.relname,t.nspname,t.relname);
        execute format('insert into pg_temp.collect_upgrade_counts select %L,count(*) from %I.%I',t.nspname||'.'||t.relname,t.nspname,t.relname);
      end loop;
    end$$;
    

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
  -- Rotation retains the existing platform-owner exception with current proof
  -- locks. Reading a private link still requires actual group authority.
  elsif p_rotate and public.is_platform_admin(auth.uid()) then
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

    insert into supabase_migrations.schema_migrations(version,name,statements)
      values('20260930230000','group_share_rotation_receipts',array['begin;

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
language plpgsql security definer set search_path='''' as $$
begin raise exception ''group_share_receipt_immutable'' using errcode=''55000'';end$$;
create trigger group_share_receipt_immutable before update or delete
  on collect_member_actions.group_share_rotations for each row
  execute function collect_member_actions.guard_group_share_rotation();

create function collect_member_actions.require_group_share_actor(p_collection_id uuid,p_rotate boolean)
returns uuid language plpgsql security definer set search_path='''' as $$
declare sid uuid; u auth.users; s auth.sessions; c public.collections; m record; jwt_exp text:=auth.jwt()->>''exp'';
  member collect_hybrid.member_records; claimed_user uuid; authorized boolean:=false;
begin
  if p_collection_id is null or p_rotate is null then
    raise exception ''group_share_request_invalid'' using errcode=''22023'';end if;
  begin sid:=public._lock_notification_registration_session();
  exception when sqlstate ''42501'' then
    raise exception ''group_share_session_required'' using errcode=''42501'';end;
  if jwt_exp is null or jwt_exp !~ ''^[0-9]{1,12}$''
    or jwt_exp::bigint<=extract(epoch from clock_timestamp()) then
    raise exception ''group_share_session_required'' using errcode=''42501'';end if;
  select * into s from auth.sessions where id=sid and user_id=auth.uid();
  if s.id is null or s.created_at is null or not isfinite(s.created_at) or s.created_at>clock_timestamp()
    or (s.not_after is not null and (not isfinite(s.not_after) or s.not_after<=clock_timestamp())) then
    raise exception ''group_share_session_required'' using errcode=''42501'';end if;
  select * into u from auth.users where id=auth.uid() for share;
  if u.id is null or u.deleted_at is not null or coalesce(u.is_anonymous,false)
    or (u.phone_confirmed_at is null and u.email_confirmed_at is null)
    or (u.banned_until is not null and u.banned_until>clock_timestamp()) then
    raise exception ''group_share_session_required'' using errcode=''42501'';end if;
  if p_rotate then
    select * into c from public.collections where id=p_collection_id for update;
  else
    select * into c from public.collections where id=p_collection_id for share;
  end if;
  if c.id is null or c.archived_at is not null then
    raise exception ''group_share_group_unavailable'' using errcode=''42501'';end if;
  if c.creator_user_id=auth.uid() then authorized:=true;
  -- Rotation retains the existing platform-owner exception with current proof
  -- locks. Reading a private link still requires actual group authority.
  elsif p_rotate and public.is_platform_admin(auth.uid()) then
    begin perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,
      ''platform_owner'',array[''collections.moderate'']);
    exception when sqlstate ''42501'' then
      raise exception ''group_share_permission_required'' using errcode=''42501'';end;
    authorized:=true;
  else
  for m in select cm.id,cm.user_id,cm.member_record_id from public.collection_members cm
    where cm.collection_id=p_collection_id and cm.status=''active''
      and (not p_rotate or cm.role in (''owner'',''admin'',''receiver''))
      and (cm.user_id=auth.uid() or collect_hybrid.member_record_belongs_to_user(cm.member_record_id,auth.uid()))
    order by cm.id for share of cm loop
    if m.user_id=auth.uid() then authorized:=true;exit;end if;
    -- Lock both possible account bindings. A lost claim/record in an established
    -- snapshot must serialize or refuse rather than authorize from old EXISTS.
    select * into member from collect_hybrid.member_records where id=m.member_record_id for share;
    claimed_user:=null;
    select claim.user_id into claimed_user from collect_hybrid.member_account_claims claim
      where claim.member_record_id=m.member_record_id for share;
    if member.id is not null and member.lifecycle=''active''
      and (member.linked_user_id=auth.uid() or claimed_user=auth.uid()) then authorized:=true;exit;end if;
  end loop;
  end if;
  if not authorized then raise exception ''group_share_permission_required'' using errcode=''42501'';end if;
  if jwt_exp::bigint<=extract(epoch from clock_timestamp()) then
    raise exception ''group_share_session_required'' using errcode=''42501'';end if;
  return sid;
end$$;

create or replace function public.get_group_share_code(p_collection_id uuid)
returns text language plpgsql volatile security definer set search_path='''' as $$
declare code uuid;
begin
  perform collect_member_actions.require_group_share_actor(p_collection_id,false);
  select share_code into code from public.collection_share_secrets
    where collection_id=p_collection_id for share;
  if code is null then raise exception ''group_share_group_unavailable'' using errcode=''42501'';end if;
  return code::text;
end$$;

create function public.rotate_group_share_code_v2(p_collection_id uuid,p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='''' as $$
declare sid uuid; receipt collect_member_actions.group_share_rotations; code uuid;
begin
  if p_request_id is null then raise exception ''group_share_request_invalid'' using errcode=''22023'';end if;
  sid:=collect_member_actions.require_group_share_actor(p_collection_id,true);
  select * into receipt from collect_member_actions.group_share_rotations where request_id=p_request_id;
  if receipt.request_id is not null then
    if receipt.actor_id is distinct from auth.uid() or receipt.collection_id is distinct from p_collection_id then
      raise exception ''group_share_request_conflict'' using errcode=''40001'';end if;
    select share_code into code from public.collection_share_secrets where collection_id=p_collection_id for share;
    if code is distinct from receipt.share_code then
      raise exception ''group_share_rotation_superseded'' using errcode=''55000'';end if;
    return jsonb_build_object(''contract_version'',1,''ok'',true,''collection_id'',receipt.collection_id,
      ''request_id'',receipt.request_id,''share_code'',receipt.share_code);
  end if;
  -- The locked parent serializes this count and its subsequent receipt insert.
  -- Established snapshots also lock the actual secret row before rotating it.
  perform 1 from public.collection_share_secrets where collection_id=p_collection_id for update;
  if (select count(*) from collect_member_actions.group_share_rotations
      where collection_id=p_collection_id and created_at>clock_timestamp()-interval ''1 hour'')>=60 then
    raise exception ''group_share_rate_limited'' using errcode=''55000'';end if;
  insert into public.collection_share_secrets(collection_id,share_code,rotated_at,rotated_by)
    values(p_collection_id,gen_random_uuid(),clock_timestamp(),auth.uid())
    on conflict(collection_id) do update set share_code=excluded.share_code,
      rotated_at=excluded.rotated_at,rotated_by=excluded.rotated_by
    returning share_code into code;
  begin
    insert into collect_member_actions.group_share_rotations(request_id,collection_id,actor_id,session_id,share_code)
      values(p_request_id,p_collection_id,auth.uid(),sid,code);
  exception when unique_violation then
    raise exception ''group_share_request_conflict'' using errcode=''40001'';end;
  perform public.create_audit_log(''group.share_link_rotated'',''collection'',p_collection_id,
    jsonb_build_object(''request_id'',p_request_id,''rotated_at'',clock_timestamp()));
  return jsonb_build_object(''contract_version'',1,''ok'',true,''collection_id'',p_collection_id,
    ''request_id'',p_request_id,''share_code'',code);
end$$;

-- Old clients must refresh/update instead of making an unidentifiable rotation.
create or replace function public.rotate_group_share_code(p_collection_id uuid)
returns text language plpgsql security definer set search_path='''' as $$
begin raise exception ''group_share_rotation_request_required'' using errcode=''22023'';end$$;

revoke all on function collect_member_actions.guard_group_share_rotation(),
  collect_member_actions.require_group_share_actor(uuid,boolean)
  from public,anon,authenticated,service_role;
revoke all on function public.get_group_share_code(uuid),public.rotate_group_share_code(uuid),
  public.rotate_group_share_code_v2(uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function public.get_group_share_code(uuid),public.rotate_group_share_code(uuid),
  public.rotate_group_share_code_v2(uuid,uuid) to authenticated;
notify pgrst,''reload schema'';
commit;
']);
    create temp table collect_upgrade_catalog_after on commit drop as with objects(family,object_name,identity,body) as (
      select 'schema',n.nspname::text,n.nspname::text,to_jsonb(n)-array['oid'] from pg_namespace n where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'relation',coalesce(tn.nspname||'.'||tc.relname,n.nspname||'.'||c.relname),n.nspname||'.'||c.relname,
        jsonb_build_object('owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'kind',c.relkind)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_index ix on ix.indexrelid=c.oid
        left join pg_class tc on tc.oid=ix.indrelid left join pg_namespace tn on tn.oid=tc.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'column',coalesce(tn.nspname||'.'||tc.relname,n.nspname||'.'||c.relname),n.nspname||'.'||c.relname||':'||a.attname,
        jsonb_build_object('type',a.atttypid,'mod',a.atttypmod,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))
        from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
        left join pg_index ix on ix.indexrelid=c.oid left join pg_class tc on tc.oid=ix.indrelid left join pg_namespace tn on tn.oid=tc.relnamespace
        where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations') and a.attnum>0 and not a.attisdropped
      union all select 'routine',n.nspname||'.'||p.proname,n.nspname||'.'||p.proname||':'||pg_get_function_identity_arguments(p.oid),
        jsonb_build_object('owner',p.proowner,'acl',p.proacl,'source',p.prosrc,'config',p.proconfig,'definer',p.prosecdef,'volatile',p.provolatile,'result',p.prorettype)
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'trigger',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||t.tgname,
        jsonb_build_object('enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))
        from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'constraint',n.nspname||'.'||cl.relname,n.nspname||'.'||cl.relname||':'||c.conname,to_jsonb(pg_get_constraintdef(c.oid))
        from pg_constraint c join pg_class cl on cl.oid=c.conrelid join pg_namespace n on n.oid=c.connamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'policy',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||p.polname,
        jsonb_build_object('roles',p.polroles,'command',p.polcmd,'permissive',p.polpermissive,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
        from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
    ) select * from objects;
    do $$declare t record;missing boolean;delta bigint;new_xid bigint;append_count bigint:=0;begin
      for t in select * from pg_temp.collect_upgrade_counts loop
        execute format('select exists(select 1 from pg_temp.collect_upgrade_rows b where b.table_name=%L and b.n>(select count(*) from %s t where to_jsonb(t)=b.rowdata))',t.table_name,t.table_name) into missing;
        if missing then raise exception 'Original row removed or changed in %',t.table_name;end if;
        execute format('select count(*)-%s from %s',t.n,t.table_name) into delta;
        if t.table_name='supabase_migrations.schema_migrations' then
          if delta<>1 then raise exception 'Migration registry delta invalid';end if;
        elsif t.table_name=any(array[]::text[]) then
          if delta not in (0,1) then raise exception 'Append delta invalid in %',t.table_name;end if;
          execute format('select count(*) from %s where xmin::text::bigint=pg_current_xact_id()::text::bigint',t.table_name) into new_xid;
          if new_xid<>delta then raise exception 'Unattributed append in %',t.table_name;end if;
          append_count:=append_count+delta;
        elsif delta<>0 then raise exception 'Unexpected row insertion in %',t.table_name;end if;
      end loop;
      if append_count not in (0,4) then raise exception 'Navigation governance append incomplete';end if;
      missing:=false;
      for t in select b.family,b.identity,encode(extensions.digest(b.body::text,'sha256'),'hex') old_hash,
        encode(extensions.digest(a.body::text,'sha256'),'hex') new_hash
        from pg_temp.collect_upgrade_catalog b left join pg_temp.collect_upgrade_catalog_after a using(family,identity)
        where a.identity is null or a.body is distinct from b.body and not (b.family='routine' and b.object_name=any(array['public.get_group_share_code','public.rotate_group_share_code']::text[])) loop
        raise notice 'CATALOG_DIFF|%|%|%|%',t.family,t.identity,t.old_hash,t.new_hash;
        missing:=true;
      end loop;
      if missing then raise exception 'Unexpected original catalog mutation';end if;
      missing:=false;
      for t in select a.family,a.object_name,a.identity from pg_temp.collect_upgrade_catalog_after a left join pg_temp.collect_upgrade_catalog b using(family,identity)
        where b.identity is null and not(a.object_name=any(array['collect_member_actions.group_share_rotations','collect_member_actions.guard_group_share_rotation','collect_member_actions.require_group_share_actor','public.rotate_group_share_code_v2']::text[])) loop
        raise notice 'UNEXPECTED_NEW_CATALOG|%|%|%',t.family,t.object_name,t.identity;missing:=true;
      end loop;
      if missing then raise exception 'Unexpected new catalog object';end if;
      if (select count(*) from supabase_migrations.schema_migrations)<>154 then raise exception 'Wrong installed count';end if;
      raise notice 'STAGED_UPGRADE_ROWS_PRESERVED|%|%',(select count(*) from pg_temp.collect_upgrade_counts),append_count;
    end$$;
    do $$begin
          if exists(select 1 from collect_member_actions.group_share_rotations) then
            raise exception 'Invitation receipts must start empty';end if;
          if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
            where n.nspname||'.'||c.relname=any(array['collect_member_actions.group_share_rotations']::text[]) and c.relkind='r' and c.relrowsecurity)<>1 then
            raise exception 'Invitation receipt RLS missing';end if;
          if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join unnest(array['anon','authenticated','service_role']) r
            where n.nspname||'.'||c.relname=any(array['collect_member_actions.group_share_rotations']::text[]) and has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')) then
            raise exception 'Invitation API table privilege';end if;
          if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
            where n.nspname||'.'||p.proname=any(array['collect_member_actions.guard_group_share_rotation','collect_member_actions.require_group_share_actor','public.rotate_group_share_code_v2','public.get_group_share_code','public.rotate_group_share_code']::text[]))<>5 then
            raise exception 'Invitation function set incomplete';end if;
          if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join unnest(array['anon','authenticated','service_role']) r
            where n.nspname||'.'||p.proname=any(array['collect_member_actions.guard_group_share_rotation','collect_member_actions.require_group_share_actor','public.rotate_group_share_code_v2','public.get_group_share_code','public.rotate_group_share_code']::text[])
            and has_function_privilege(r,p.oid,'EXECUTE') is distinct from (n.nspname='public' and r='authenticated')) then
            raise exception 'Invitation API function privilege';end if;
          if exists(select 1 from pg_temp.collect_upgrade_catalog b join pg_temp.collect_upgrade_catalog_after a using(family,identity)
            where b.family='routine' and b.object_name=any(array['public.get_group_share_code','public.rotate_group_share_code']::text[])
            and (b.body-array['source','config','volatile','acl','definer']) is distinct from
                (a.body-array['source','config','volatile','acl','definer'])) then
            raise exception 'Invitation original function owner/result changed';end if;
        end$$;
rollback;
