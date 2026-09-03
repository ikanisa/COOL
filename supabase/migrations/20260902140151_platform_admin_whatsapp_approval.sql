begin;

-- Platform operators only. Nothing in this schema changes group creation,
-- group membership/roles, payees, settlement rails or member authentication.
-- No existing account is silently pre-approved by this migration. A reviewed
-- service-only bootstrap and fresh operator sign-in are rollout prerequisites.
create schema if not exists collect_admin_access;
revoke all on schema collect_admin_access from public,anon,authenticated,service_role;
grant usage on schema collect_admin_access to authenticated,service_role;

create table collect_admin_access.whatsapp_approvals (
  user_id uuid primary key references auth.users(id) on delete cascade,
  phone_e164 text not null check (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  approved_at timestamptz not null default clock_timestamp(),
  approved_by uuid references auth.users(id) on delete set null,
  reason text not null check (length(btrim(reason)) between 1 and 1000),
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete set null,
  revoke_reason text,
  check (expires_at is null or expires_at > approved_at)
);
create unique index whatsapp_approvals_active_phone_key
  on collect_admin_access.whatsapp_approvals(phone_e164) where revoked_at is null;
alter table collect_admin_access.whatsapp_approvals enable row level security;
revoke all on collect_admin_access.whatsapp_approvals from public,anon,authenticated,service_role;

-- Private, ungranted predicates use Auth's server-owned verified identity,
-- never profiles, user_metadata or editable country/MoMo details.
create function collect_admin_access.verified_phone(p_user uuid)
returns text language sql stable security invoker set search_path = ''
as $$
  select '+' || ltrim(u.phone, '+') from auth.users u
  where u.id = p_user and u.phone ~ '^\+?[1-9][0-9]{7,14}$'
    and u.phone_confirmed_at is not null and u.deleted_at is null
    and not coalesce(u.is_anonymous,false)
    and (u.banned_until is null or u.banned_until <= statement_timestamp());
$$;
create function collect_admin_access.approved_identity(p_user uuid)
returns boolean language sql stable security invoker set search_path = ''
as $$
  select exists(select 1 from collect_admin_access.whatsapp_approvals a
    where a.user_id=p_user and a.revoked_at is null
      and (a.expires_at is null or a.expires_at > statement_timestamp())
      and a.phone_e164=collect_admin_access.verified_phone(p_user));
$$;
create function collect_admin_access.caller_eligible(p_user uuid)
returns boolean language plpgsql stable security invoker set search_path = ''
as $$
declare session_key text := auth.jwt()->>'session_id';
begin
  if not collect_admin_access.approved_identity(p_user) then return false; end if;
  if auth.jwt()->>'role' = 'service_role' then return true; end if;
  if p_user is distinct from auth.uid() or session_key is null
    or session_key !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
    return false;
  end if;
  return exists(select 1 from auth.sessions s
    join collect_admin_access.whatsapp_approvals a on a.user_id=s.user_id
    where s.id=session_key::uuid and s.user_id=p_user
      and s.created_at >= a.approved_at
      and exists(select 1 from public.admin_user_roles ur join public.admin_roles r on r.id=ur.role_id
        where ur.user_id=p_user and r.name='platform_owner' and ur.revoked_at is null
          and s.created_at >= ur.created_at)
      and (s.not_after is null or s.not_after > statement_timestamp()));
end;
$$;

create function collect_admin_access.platform_admin(p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select (auth.jwt()->>'role'='service_role' or p_user=auth.uid())
    and collect_admin_access.caller_eligible(p_user)
    and exists(select 1 from public.admin_user_roles ur join public.admin_roles r on r.id=ur.role_id
      where ur.user_id=p_user and ur.revoked_at is null and r.name='platform_owner');
$$;
create function collect_admin_access.permission_allowed(p_permission text,p_user uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce((auth.jwt()->>'role'='service_role' or p_user=auth.uid())
    and collect_admin_access.caller_eligible(p_user)
    and exists(select 1 from public.admin_user_roles ur
      join public.admin_roles r on r.id=ur.role_id and r.name='platform_owner'
      join public.admin_role_permissions rp on rp.role_id=ur.role_id
      where ur.user_id=p_user and ur.revoked_at is null and rp.permission_name=p_permission),false);
$$;

create or replace function public.is_platform_admin(user_uuid uuid default auth.uid())
returns boolean language sql stable security invoker set search_path = ''
as $$ select coalesce(collect_admin_access.platform_admin(user_uuid),false); $$;
create or replace function public.has_admin_permission(permission text,user_uuid uuid default auth.uid())
returns boolean language sql stable security invoker set search_path = ''
as $$ select collect_admin_access.permission_allowed(permission,user_uuid); $$;

create function collect_admin_access.current_identity()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  if not collect_admin_access.permission_allowed('overview.read',auth.uid()) then return '{}'::jsonb; end if;
  return coalesce((select jsonb_build_object('user_id',p.id,'display_name','Collect ID '||p.public_id,
    'phone_masked',public.mask_phone(collect_admin_access.verified_phone(p.id)),
    'roles','["admin"]'::jsonb,'permissions',(select coalesce(jsonb_agg(rp.permission_name order by rp.permission_name),'[]'::jsonb)
      from public.admin_role_permissions rp join public.admin_roles r on r.id=rp.role_id where r.name='platform_owner'))
    from public.profiles p where p.id=auth.uid()),'{}'::jsonb);
end;
$$;
create or replace function public.admin_current_user()
returns jsonb language sql stable security invoker set search_path = ''
as $$ select collect_admin_access.current_identity(); $$;

create function collect_admin_access.approve_whatsapp(
  p_user uuid,p_phone text,p_reason text,p_expires_at timestamptz,p_bootstrap boolean
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  phone text := btrim(coalesce(p_phone,''));
  reason_text text := btrim(coalesce(p_reason,''));
  prior collect_admin_access.whatsapp_approvals%rowtype;
begin
  -- All access/approval mutations serialize, and caller authority is checked
  -- AFTER waiting so a revoked operator cannot finish a queued grant.
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  if p_bootstrap then
    if auth.jwt()->>'role' is distinct from 'service_role' then
      raise exception 'Service role required' using errcode='42501';
    end if;
    if exists(select 1 from public.admin_user_roles ur join public.admin_roles r on r.id=ur.role_id
      where ur.revoked_at is null and r.name='platform_owner'
        and collect_admin_access.approved_identity(ur.user_id)) then
      raise exception 'An approved Admin already exists' using errcode='42501';
    end if;
  else
    perform public.assert_admin_permission('admin_users.manage');
    if p_user=auth.uid() then
      raise exception 'Another Admin must approve your identity' using errcode='42501';
    end if;
  end if;
  if length(reason_text) not between 1 and 1000
    or phone !~ '^\+[1-9][0-9]{7,14}$'
    or (p_expires_at is not null and p_expires_at <= clock_timestamp()) then
    raise exception 'Verified international WhatsApp number and reason required' using errcode='22023';
  end if;
  perform 1 from auth.users where id=p_user for update;
  if phone is distinct from collect_admin_access.verified_phone(p_user) then
    raise exception 'WhatsApp identity could not be verified' using errcode='22023';
  end if;
  select * into prior from collect_admin_access.whatsapp_approvals where user_id=p_user;
  if prior.user_id is not null and prior.revoked_at is null and prior.phone_e164=phone
    and prior.expires_at is not distinct from p_expires_at
    and (prior.expires_at is null or prior.expires_at > statement_timestamp()) then
    return jsonb_build_object('ok',true,'status','approved','user_id',p_user);
  end if;
  insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_by,reason,expires_at)
  values(p_user,phone,auth.uid(),reason_text,p_expires_at)
  on conflict(user_id) do update set phone_e164=excluded.phone_e164,
    approved_at=clock_timestamp(),approved_by=excluded.approved_by,reason=excluded.reason,
    expires_at=excluded.expires_at,revoked_at=null,revoked_by=null,revoke_reason=null;
  insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'admin.whatsapp.approved','profile',p_user,
    jsonb_build_object('phone_masked',public.mask_phone(phone),'reason',reason_text,
      'expires_at',p_expires_at,'service_bootstrap',p_bootstrap));
  -- Approval alone never creates or reactivates an Admin role.
  return jsonb_build_object('ok',true,'status','approved','user_id',p_user);
end;
$$;

create function collect_admin_access.set_user_access(p_user uuid,p_active boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_role_id uuid; reason_text text := btrim(coalesce(p_reason,''));
begin
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  perform public.assert_admin_permission('admin_users.manage');
  if p_active is null or length(reason_text) not between 1 and 1000 then
    raise exception 'Active state and reason are required' using errcode='22023';
  end if;
  select id into v_role_id from public.admin_roles where name='platform_owner';
  if v_role_id is null or not exists(select 1 from public.profiles where id=p_user) then
    raise exception 'Admin account unavailable' using errcode='22023';
  end if;
  if p_active then
    perform 1 from auth.users where id=p_user for update;
    if not collect_admin_access.approved_identity(p_user) then
      raise exception 'Pre-approved verified WhatsApp identity required' using errcode='42501';
    end if;
    if not exists(select 1 from public.admin_user_roles ur
      where ur.user_id=p_user and ur.role_id=v_role_id and ur.revoked_at is null) then
      insert into public.admin_user_roles(user_id,role_id,granted_by,reason,created_at)
      values(p_user,v_role_id,auth.uid(),reason_text,clock_timestamp());
      insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
      values(auth.uid(),'admin.access.activated','profile',p_user,jsonb_build_object('reason',reason_text));
    end if;
    return jsonb_build_object('ok',true,'status','active');
  end if;
  if p_user=auth.uid() then
    raise exception 'You cannot deactivate your own Admin access' using errcode='42501';
  end if;
  -- The caller is an approved active Admin, so deactivating a different account
  -- cannot remove the last approved Admin. This remains true under the lock.
  update public.admin_user_roles ur set revoked_at=clock_timestamp(),revoked_by=auth.uid(),revoke_reason=reason_text
    where ur.user_id=p_user and ur.revoked_at is null;
  if found then
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'admin.access.deactivated','profile',p_user,jsonb_build_object('reason',reason_text));
  end if;
  return jsonb_build_object('ok',true,'status','revoked');
end;
$$;

create function collect_admin_access.revoke_whatsapp(p_user uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare reason_text text := btrim(coalesce(p_reason,''));
begin
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  perform public.assert_admin_permission('admin_users.manage');
  if p_user=auth.uid() then
    raise exception 'You cannot revoke your own WhatsApp approval' using errcode='42501';
  end if;
  if length(reason_text) not between 1 and 1000 then
    raise exception 'Reason required' using errcode='22023';
  end if;
  update collect_admin_access.whatsapp_approvals set revoked_at=clock_timestamp(),revoked_by=auth.uid(),revoke_reason=reason_text
    where user_id=p_user and revoked_at is null;
  if found then
    perform collect_admin_access.set_user_access(p_user,false,reason_text);
    insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
    values(auth.uid(),'admin.whatsapp.revoked','profile',p_user,jsonb_build_object('reason',reason_text));
  end if;
  return jsonb_build_object('ok',true,'status','revoked','user_id',p_user);
end;
$$;

-- Internal durable account state, separate from a particular login session.
-- A role without a valid approved identity must never be displayed as active.
create function collect_admin_access.account_state(p_user uuid)
returns jsonb language plpgsql stable security invoker set search_path = ''
as $$
declare a collect_admin_access.whatsapp_approvals%rowtype; approved boolean; granted boolean;
begin
  select * into a from collect_admin_access.whatsapp_approvals where user_id=p_user;
  approved := collect_admin_access.approved_identity(p_user);
  granted := exists(select 1 from public.admin_user_roles ur join public.admin_roles r on r.id=ur.role_id
    where ur.user_id=p_user and ur.revoked_at is null and r.name='platform_owner');
  return jsonb_build_object('user_id',p_user,
    'phone_masked',public.mask_phone(coalesce(a.phone_e164,collect_admin_access.verified_phone(p_user))),
    'approved_at',a.approved_at,'expires_at',a.expires_at,
    'status',case when a.user_id is null then 'not_approved' when a.revoked_at is not null then 'revoked'
      when a.expires_at <= statement_timestamp() then 'expired'
      when not approved then 'identity_changed' else 'approved' end,
    'approved',approved,'role_granted',granted,'admin_access',approved and granted,
    'access_status',case when approved and granted then 'active' when granted then 'approval_required'
      when approved then 'approved' else 'revoked' end);
end;
$$;
create function collect_admin_access.approval_status(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.assert_admin_permission('admin_users.read');
  if not exists(select 1 from public.profiles where id=p_user) then
    raise exception 'Account unavailable' using errcode='22023';
  end if;
  return collect_admin_access.account_state(p_user);
end;
$$;

create function collect_admin_access.get_admin_user(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.assert_admin_permission('admin_users.read');
  return coalesce((select s.state || jsonb_build_object(
    'id',p.id,'public_id',p.public_id,'created_at',p.created_at,
    'status',s.state->>'access_status','whatsapp_approval',s.state->>'status',
    'active_roles',case when (s.state->>'admin_access')::boolean then '["admin"]'::jsonb else '[]'::jsonb end)
    from public.profiles p cross join lateral (select collect_admin_access.account_state(p.id) state) s
    where p.id=p_user and (exists(select 1 from public.admin_user_roles where user_id=p.id)
      or exists(select 1 from collect_admin_access.whatsapp_approvals where user_id=p.id))), '{}'::jsonb);
end;
$$;
create function collect_admin_access.list_admin_users(p_search text,p_status text,p_limit integer,p_offset integer,p_sort text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb;
begin
  perform public.assert_admin_permission('admin_users.read');
  with accounts as (
    select p.id,p.public_id,p.created_at,collect_admin_access.account_state(p.id) state
    from public.profiles p where exists(select 1 from public.admin_user_roles where user_id=p.id)
      or exists(select 1 from collect_admin_access.whatsapp_approvals where user_id=p.id)
  ), filtered as (
    select * from accounts where (p_search is null or public_id=p_search
      or state->>'phone_masked' ilike '%'||p_search||'%')
      and (p_status is null or state->>'access_status'=p_status
        or (p_status='admin' and state->>'access_status'='active'))
  ), ordered as (
    select *,row_number() over(order by
      case when p_sort='created_at_asc' then created_at end asc nulls last,created_at desc,id) rank
    from filtered order by rank limit least(greatest(coalesce(p_limit,25),1),100) offset greatest(coalesce(p_offset,0),0)
  )
  select jsonb_build_object('total',(select count(*) from filtered),'rows',coalesce(jsonb_agg(
    public._admin_row(id,'Collect ID '||public_id,'',state->>'access_status','Admin',created_at,
      state || jsonb_build_object('public_id',public_id)) order by rank),'[]'::jsonb)) into result from ordered;
  return result;
end;
$$;

-- Controlled service-only bootstrap cannot bypass number approval. No browser
-- bootstrap is reinstated, and no seed approves real users automatically.
create function collect_admin_access.bootstrap_owner(p_user uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_role_id uuid;
begin
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  if auth.jwt()->>'role' is distinct from 'service_role' then
    raise exception 'Service role required' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_reason,''))) not between 1 and 1000
    or not collect_admin_access.approved_identity(p_user) then
    raise exception 'Pre-approved verified identity and reason required' using errcode='42501';
  end if;
  select id into v_role_id from public.admin_roles where name='platform_owner';
  if not exists(select 1 from public.admin_user_roles ur where ur.user_id=p_user
    and ur.role_id=v_role_id and ur.revoked_at is null) then
    insert into public.admin_user_roles(user_id,role_id,reason,created_at)
    values(p_user,v_role_id,p_reason,clock_timestamp());
    insert into public.audit_logs(action,entity_type,entity_id,metadata)
    values('admin.bootstrap.platform_owner','profile',p_user,jsonb_build_object('reason',p_reason));
  end if;
  return jsonb_build_object('ok',true);
end;
$$;

create function public.admin_approve_whatsapp(p_user_id uuid,p_whatsapp_phone text,p_reason text,p_expires_at timestamptz default null)
returns jsonb language sql security invoker set search_path = ''
as $$ select collect_admin_access.approve_whatsapp(p_user_id,p_whatsapp_phone,p_reason,p_expires_at,false); $$;
create function public.admin_bootstrap_whatsapp_approval(p_user_id uuid,p_whatsapp_phone text,p_reason text)
returns jsonb language sql security invoker set search_path = ''
as $$ select collect_admin_access.approve_whatsapp(p_user_id,p_whatsapp_phone,p_reason,null,true); $$;
create function public.admin_revoke_whatsapp_approval(p_user_id uuid,p_reason text)
returns jsonb language sql security invoker set search_path = ''
as $$ select collect_admin_access.revoke_whatsapp(p_user_id,p_reason); $$;
create function public.admin_get_whatsapp_approval(p_user_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select collect_admin_access.approval_status(p_user_id); $$;
create or replace function public.admin_set_user_access(p_user_id uuid,p_active boolean,p_reason text)
returns jsonb language sql security invoker set search_path = ''
as $$ select collect_admin_access.set_user_access(p_user_id,p_active,p_reason); $$;
create or replace function public.admin_bootstrap_platform_owner(p_user_id uuid,p_reason text)
returns jsonb language sql security invoker set search_path = ''
as $$ select collect_admin_access.bootstrap_owner(p_user_id,p_reason); $$;
create or replace function public.admin_get_admin_user(p_id uuid)
returns jsonb language sql stable security invoker set search_path = ''
as $$ select collect_admin_access.get_admin_user(p_id); $$;
create or replace function public.admin_list_admin_users(p_search text default null,p_status text default null,
  p_limit integer default 25,p_offset integer default 0,p_sort text default 'created_at_desc')
returns jsonb language sql stable security invoker set search_path = ''
as $$ select collect_admin_access.list_admin_users(p_search,p_status,p_limit,p_offset,p_sort); $$;
-- The five-argument signature has defaults and supports old two-argument
-- callers. Keeping both signatures makes PostgREST return HTTP 300/PGRST203.
-- No CASCADE: an unexpected database dependency must stop this migration.
drop function if exists public.admin_list_admin_users(text,text);

revoke all on all functions in schema collect_admin_access from public,anon,authenticated,service_role;
grant execute on function collect_admin_access.platform_admin(uuid),collect_admin_access.permission_allowed(text,uuid)
  to authenticated,service_role;
grant execute on function collect_admin_access.current_identity() to authenticated;
grant execute on function collect_admin_access.approve_whatsapp(uuid,text,text,timestamptz,boolean)
  to authenticated,service_role;
grant execute on function collect_admin_access.set_user_access(uuid,boolean,text),collect_admin_access.revoke_whatsapp(uuid,text),
  collect_admin_access.approval_status(uuid),collect_admin_access.get_admin_user(uuid),
  collect_admin_access.list_admin_users(text,text,integer,integer,text) to authenticated;
grant execute on function collect_admin_access.bootstrap_owner(uuid,text) to service_role;
revoke all on function public.admin_approve_whatsapp(uuid,text,text,timestamptz),public.admin_revoke_whatsapp_approval(uuid,text),
  public.admin_get_whatsapp_approval(uuid),public.admin_set_user_access(uuid,boolean,text),
  public.admin_bootstrap_whatsapp_approval(uuid,text,text),public.admin_bootstrap_platform_owner(uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function public.admin_approve_whatsapp(uuid,text,text,timestamptz),public.admin_revoke_whatsapp_approval(uuid,text),
  public.admin_get_whatsapp_approval(uuid),public.admin_set_user_access(uuid,boolean,text) to authenticated;
grant execute on function public.admin_bootstrap_whatsapp_approval(uuid,text,text),public.admin_bootstrap_platform_owner(uuid,text) to service_role;
-- Retired role-grant APIs must not create a parallel platform access path.
revoke all on function public.admin_grant_user_role(uuid,text,text),public.admin_revoke_user_role(uuid,text,text)
  from public,anon,authenticated,service_role;

-- Keep the server-driven Admin filters aligned with the effective access state.
update public.admin_queue_filter_options set enabled=false,updated_at=clock_timestamp()
where rpc_name='admin_list_admin_users' and filter_kind='status'
  and value not in ('','active','approval_required','approved','revoked');
insert into public.admin_queue_filter_options(rpc_name,filter_kind,value,label,display_order,enabled)
select q.rpc_name,'status',v.value,v.label,v.display_order,true
from public.admin_queue_specs q cross join (values
  ('','All',0),('active','Active',10),('approval_required','Approval required',20),
  ('approved','Awaiting activation',30),('revoked','Revoked',40)
) v(value,label,display_order) where q.rpc_name='admin_list_admin_users'
on conflict(rpc_name,filter_kind,value) do update set label=excluded.label,
  display_order=excluded.display_order,enabled=true,updated_at=clock_timestamp();

notify pgrst,'reload schema';
commit;
