begin;

-- Operator migration only. Member phone identities/payment routes are unchanged.
create table collect_admin_access.email_approvals (
 user_id uuid primary key,
 email text not null unique check(email=lower(btrim(email)) and length(email) between 3 and 254
  and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
 approved_at timestamptz not null default clock_timestamp(),
 approved_by uuid,
 reason text not null check(length(btrim(reason)) between 8 and 500),
 expires_at timestamptz,
 revoked_at timestamptz,
 revoked_by uuid,
 check(expires_at is null or expires_at>approved_at)
);
create table collect_admin_access.operator_auth_policy (
 id boolean primary key default true check(id),
 mode text not null check(mode in ('transition','email')),
 revision integer not null check(revision>0),
 updated_at timestamptz not null default clock_timestamp()
);
insert into collect_admin_access.operator_auth_policy values(true,'transition',1,clock_timestamp());
alter table collect_admin_access.email_approvals enable row level security;
alter table collect_admin_access.operator_auth_policy enable row level security;
revoke all on collect_admin_access.email_approvals,collect_admin_access.operator_auth_policy
 from public,anon,authenticated,service_role;

create function collect_admin_access.email_identity(p_user uuid)
returns boolean language sql stable security invoker set search_path='' as $$
 select exists(select 1 from auth.users u join collect_admin_access.email_approvals a on a.user_id=u.id
  where u.id=p_user and u.deleted_at is null and not coalesce(u.is_anonymous,false)
   and (u.banned_until is null or u.banned_until<=statement_timestamp())
   and u.email_confirmed_at is not null and lower(btrim(u.email))=a.email
   and a.revoked_at is null and (a.expires_at is null or a.expires_at>statement_timestamp()))
$$;
create or replace function collect_admin_access.approved_identity(p_user uuid)
returns boolean language sql stable security invoker set search_path='' as $$
 select collect_admin_access.email_identity(p_user) or
  (not exists(select 1 from collect_admin_access.email_approvals where user_id=p_user)
   and exists(select 1 from collect_admin_access.operator_auth_policy where id and mode='transition')
   and exists(select 1 from collect_admin_access.whatsapp_approvals a
    where a.user_id=p_user and a.revoked_at is null
     and (a.expires_at is null or a.expires_at>statement_timestamp())
     and a.phone_e164=collect_admin_access.verified_phone(p_user)))
$$;
create or replace function collect_admin_access.caller_eligible(p_user uuid)
returns boolean language plpgsql stable security invoker set search_path='' as $$
declare session_key text:=auth.jwt()->>'session_id';begin
 if not collect_admin_access.approved_identity(p_user) then return false;end if;
 if auth.jwt()->>'role'='service_role' then return true;end if;
 if auth.role() is distinct from 'authenticated' then return false;end if;
 if p_user is distinct from auth.uid() or session_key is null
  or session_key !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' then return false;end if;
 return exists(select 1 from auth.sessions s join auth.users u on u.id=s.user_id
  join public.admin_user_roles ur on ur.user_id=u.id and ur.revoked_at is null
  join public.admin_roles r on r.id=ur.role_id and r.name='platform_owner'
  where s.id=session_key::uuid and s.user_id=p_user
   and public._notification_session_is_live(s.id,p_user) and s.created_at<=statement_timestamp()
   and s.created_at>=ur.created_at
   and (exists(select 1 from collect_admin_access.email_approvals a
     where a.user_id=p_user and collect_admin_access.email_identity(p_user) and s.created_at>=a.approved_at)
    or (exists(select 1 from collect_admin_access.operator_auth_policy where id and mode='transition')
     and exists(select 1 from collect_admin_access.whatsapp_approvals a where a.user_id=p_user
      and a.revoked_at is null and (a.expires_at is null or a.expires_at>statement_timestamp())
      and a.phone_e164=collect_admin_access.verified_phone(p_user) and s.created_at>=a.approved_at))));
end $$;

-- Preserve149's row locks, session age, explicit role and permission evidence.
create or replace function collect_hybrid.require_roster_actor_authority(
 p_actor uuid,p_session uuid,p_role_name text,p_permission_names text[])
returns void language plpgsql security definer set search_path='' as $$
declare u auth.users;s auth.sessions;role_uuid uuid;permission text;mode_value text;approval_time timestamptz;
begin
 perform public._lock_notification_session_gate();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 if p_actor is null or p_session is null or p_role_name is null or p_role_name !~ '^[a-z_]+$'
  or p_permission_names is null or cardinality(p_permission_names) not between 1 and 30
  or exists(select 1 from unnest(p_permission_names)n where n is null or n !~ '^[a-z_]+(\.[a-z_]+)+$') then
  raise exception 'roster_actor_unavailable' using errcode='42501';end if;
 select mode into mode_value from collect_admin_access.operator_auth_policy where id for share;
 select * into u from auth.users where id=p_actor for share;
 select * into s from auth.sessions where id=p_session and user_id=p_actor for share;
 if u.id is null or s.id is null or s.created_at is null or not isfinite(s.created_at)
  or s.created_at>clock_timestamp() or s.aal::text not in ('aal1','aal2') or s.aal is null
  or (s.not_after is not null and (not isfinite(s.not_after) or s.not_after<=clock_timestamp()))
  or u.deleted_at is not null or coalesce(u.is_anonymous,false)
  or (u.banned_until is not null and u.banned_until>clock_timestamp()) then
  raise exception 'roster_actor_unavailable' using errcode='42501';end if;
 if u.email_confirmed_at is not null then
  select approved_at into approval_time from collect_admin_access.email_approvals a
   where a.user_id=p_actor and a.email=lower(btrim(u.email)) and a.revoked_at is null
    and (a.expires_at is null or a.expires_at>clock_timestamp()) for share;
 end if;
 if approval_time is null and mode_value='transition' and u.phone_confirmed_at is not null
  and not exists(select 1 from collect_admin_access.email_approvals where user_id=p_actor) then
  select approved_at into approval_time from collect_admin_access.whatsapp_approvals a
   where a.user_id=p_actor and a.phone_e164='+'||ltrim(u.phone,'+') and a.revoked_at is null
    and (a.expires_at is null or a.expires_at>clock_timestamp()) for share;
 end if;
 select r.id into role_uuid from public.admin_user_roles ur
  join public.admin_roles r on r.id=ur.role_id and r.name=p_role_name
  where ur.user_id=p_actor and ur.revoked_at is null and s.created_at>=ur.created_at
   and approval_time is not null and s.created_at>=approval_time
  order by ur.created_at for share of ur,r;
 if role_uuid is null then raise exception 'roster_actor_unavailable' using errcode='42501';end if;
 for permission in select distinct n from unnest(p_permission_names)n order by n loop
  perform 1 from public.admin_role_permissions where role_id=role_uuid and permission_name=permission for share;
  if not found then raise exception 'roster_actor_unavailable' using errcode='42501';end if;
 end loop;
end $$;

create or replace function collect_security.reconciliation_actor_current(p_actor uuid,p_session uuid)
returns boolean language plpgsql security definer set search_path='' as $$
begin
 perform collect_hybrid.require_roster_actor_authority(p_actor,p_session,'platform_owner',array['payments.allocate']);
 return exists(select 1 from auth.sessions where id=p_session and user_id=p_actor and aal::text='aal2');
exception when sqlstate '42501' then return false;
end $$;

-- One service-managed reservation for the user-selected email. No email is
-- verified by this operation and no credential is created or returned.
create function public.bootstrap_collect_email_operator_v1(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare target auth.users;role_id_value uuid;begin
 if auth.role() is distinct from 'service_role' then
  raise exception 'email_enrollment_service_required' using errcode='42501';end if;
 perform public._lock_notification_session_gate();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 select * into target from auth.users where id=p_user_id for update;
 if target.id is null or lower(btrim(target.email)) is distinct from 'info@ikanisa.com'
  or target.deleted_at is not null or coalesce(target.is_anonymous,false)
  or (target.banned_until is not null and target.banned_until>clock_timestamp())
  or not exists(select 1 from public.profiles where id=p_user_id) then
  raise exception 'email_enrollment_target_invalid' using errcode='22023';end if;
 if exists(select 1 from collect_admin_access.email_approvals where user_id=p_user_id
  and (revoked_at is not null or email<>'info@ikanisa.com')) then
  raise exception 'email_enrollment_previously_revoked' using errcode='42501';end if;
 select id into role_id_value from public.admin_roles where name='platform_owner';
 if role_id_value is null then raise exception 'email_role_unavailable' using errcode='55000';end if;
 insert into collect_admin_access.email_approvals(user_id,email,reason)
  values(p_user_id,'info@ikanisa.com','Owner-directed operator email migration') on conflict(user_id) do nothing;
 if not exists(select 1 from public.admin_user_roles where user_id=p_user_id and role_id=role_id_value and revoked_at is null) then
  if exists(select 1 from public.admin_user_roles where user_id=p_user_id and revoked_at is not null) then
   raise exception 'email_enrollment_previously_revoked' using errcode='42501';end if;
  insert into public.admin_user_roles(user_id,role_id,reason)
   values(p_user_id,role_id_value,'Owner-directed operator email migration');
 end if;
 return jsonb_build_object('ok',true,'user_id',p_user_id,'email_verified',target.email_confirmed_at is not null,
  'fresh_email_sign_in_required',true,'auth_mode',(select mode from collect_admin_access.operator_auth_policy where id));
end $$;

create function public.admin_set_operator_email_mode_v1(p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;current_mode text;begin
 sid:=public._lock_notification_registration_session();
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',array['admin_users.manage']);
 if not collect_admin_access.email_identity(auth.uid()) or length(btrim(coalesce(p_reason,''))) not between 8 and 500 then
  raise exception 'current_email_operator_required' using errcode='42501';end if;
 select mode into current_mode from collect_admin_access.operator_auth_policy where id for update;
 if current_mode<>'email' then
  update collect_admin_access.operator_auth_policy set mode='email',revision=revision+1,updated_at=clock_timestamp() where id;
  insert into public.audit_logs(actor_user_id,action,entity_type,metadata)
   values(auth.uid(),'admin.auth.email_cutover','operator_auth_policy',jsonb_build_object('reason',btrim(p_reason)));
 end if;
 return jsonb_build_object('ok',true,'mode','email','replay',current_mode='email');
end $$;

create function public.admin_revoke_email_operator_v1(p_user_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;changed boolean;begin
 sid:=public._lock_notification_registration_session();
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',array['admin_users.manage']);
 if p_user_id is null or p_user_id=auth.uid() or length(btrim(coalesce(p_reason,''))) not between 8 and 500 then
  raise exception 'email_revoke_invalid' using errcode='22023';end if;
 perform 1 from collect_admin_access.email_approvals where user_id=p_user_id for update;
 if not found then raise exception 'operator_email_approval_unavailable' using errcode='22023';end if;
 update collect_admin_access.email_approvals set revoked_at=clock_timestamp(),revoked_by=auth.uid()
  where user_id=p_user_id and revoked_at is null;
 changed:=found;
 if changed then insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'admin.email.revoked','profile',p_user_id,jsonb_build_object('reason',btrim(p_reason)));end if;
 return jsonb_build_object('ok',true,'status','revoked','user_id',p_user_id);
end $$;

-- Keep the existing list/detail shape while giving email-approved accounts
-- the correct status. The phone field retains its literal meaning.
create or replace function collect_admin_access.account_state(p_user uuid)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare e collect_admin_access.email_approvals;w collect_admin_access.whatsapp_approvals;
 approved boolean;granted boolean;state text;approval_time timestamptz;expiry timestamptz;
begin
 select * into e from collect_admin_access.email_approvals where user_id=p_user;
 select * into w from collect_admin_access.whatsapp_approvals where user_id=p_user;
 approved:=collect_admin_access.approved_identity(p_user);
 granted:=exists(select 1 from public.admin_user_roles ur join public.admin_roles r on r.id=ur.role_id
  where ur.user_id=p_user and ur.revoked_at is null and r.name='platform_owner');
 if e.user_id is not null then
  approval_time:=e.approved_at;expiry:=e.expires_at;
  state:=case when e.revoked_at is not null then 'revoked'
   when e.expires_at<=statement_timestamp() then 'expired'
   when not approved then 'identity_changed' else 'approved' end;
 else
  approval_time:=w.approved_at;expiry:=w.expires_at;
  state:=case when w.user_id is null then 'not_approved' when w.revoked_at is not null then 'revoked'
   when w.expires_at<=statement_timestamp() then 'expired'
   when not approved then 'identity_changed' else 'approved' end;
 end if;
 return jsonb_build_object('user_id',p_user,'phone_masked',public.mask_phone(collect_admin_access.verified_phone(p_user)),
  'approved_at',approval_time,'expires_at',expiry,'status',state,'approved',approved,'role_granted',granted,
  'admin_access',approved and granted,'access_status',case when approved and granted then 'active'
   when granted then 'approval_required' when approved then 'approved' else 'revoked' end);
end $$;

create function public.admin_get_operator_approval_v1(p_user_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;target auth.users;e collect_admin_access.email_approvals;w collect_admin_access.whatsapp_approvals;
 state jsonb;provider text;status_value text;mode_value text;masked text;
begin
 sid:=public._lock_notification_registration_session();
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',array['admin_users.read']);
 select * into target from auth.users where id=p_user_id for share;
 if target.id is null or not exists(select 1 from public.profiles where id=p_user_id) then
  raise exception 'operator_account_unavailable' using errcode='22023';end if;
 select * into e from collect_admin_access.email_approvals where user_id=p_user_id for share;
 select * into w from collect_admin_access.whatsapp_approvals where user_id=p_user_id for share;
 select mode into mode_value from collect_admin_access.operator_auth_policy where id;
 state:=collect_admin_access.account_state(p_user_id);status_value:=state->>'status';
 if e.user_id is not null or (w.user_id is null and nullif(btrim(target.email),'') is not null) then
  provider:='email';
  masked:=case when nullif(btrim(target.email),'') is not null then left(lower(btrim(target.email)),1)||'***@***' end;
  if e.user_id is not null and e.revoked_at is null and (e.expires_at is null or e.expires_at>clock_timestamp())
   and target.email_confirmed_at is null and lower(btrim(target.email))=e.email then status_value:='pending_verification';end if;
 elsif w.user_id is not null then
  provider:='whatsapp';masked:=state->>'phone_masked';
  if mode_value='email' and status_value='identity_changed' then status_value:='legacy_disabled';end if;
 else provider:='unapproved';masked:=null;end if;
 return jsonb_build_object('contract_version',1,'user_id',p_user_id,'provider',provider,'mode',mode_value,
  'identity_masked',masked,'approved_at',state->'approved_at','expires_at',state->'expires_at',
  'status',status_value,'approved',state->'approved','role_granted',state->'role_granted',
  'admin_access',state->'admin_access','access_status',state->'access_status');
end $$;

create function public.admin_approve_email_operator_v1(p_user_id uuid,p_email text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;target auth.users;normalized text:=lower(btrim(p_email));
begin
 sid:=public._lock_notification_registration_session();
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',array['admin_users.manage']);
 if p_user_id is null or p_user_id=auth.uid() or length(btrim(coalesce(p_reason,''))) not between 8 and 500
  or normalized is null or length(normalized) not between 3 and 254
  or normalized !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
  raise exception 'operator_email_approval_invalid' using errcode='22023';end if;
 select * into target from auth.users where id=p_user_id for update;
 if target.id is null or target.deleted_at is not null or coalesce(target.is_anonymous,false)
  or (target.banned_until is not null and target.banned_until>clock_timestamp())
  or target.email_confirmed_at is null or lower(btrim(target.email)) is distinct from normalized
  or not exists(select 1 from public.profiles where id=p_user_id) then
  raise exception 'operator_verified_email_required' using errcode='42501';end if;
 if exists(select 1 from collect_admin_access.email_approvals where user_id=p_user_id
  and email=normalized and revoked_at is null and (expires_at is null or expires_at>clock_timestamp())) then
  return jsonb_build_object('ok',true,'status','approved','user_id',p_user_id);end if;
 insert into collect_admin_access.email_approvals(user_id,email,approved_by,reason)
  values(p_user_id,normalized,auth.uid(),btrim(p_reason)) on conflict(user_id) do update
  set email=excluded.email,approved_at=clock_timestamp(),approved_by=excluded.approved_by,reason=excluded.reason,
   revoked_at=null,revoked_by=null,expires_at=null;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'admin.email.approved','profile',p_user_id,jsonb_build_object('reason',btrim(p_reason)));
 return jsonb_build_object('ok',true,'status','approved','user_id',p_user_id);
end $$;

revoke all on function collect_admin_access.email_identity(uuid),collect_admin_access.approved_identity(uuid),
 collect_admin_access.caller_eligible(uuid),collect_hybrid.require_roster_actor_authority(uuid,uuid,text,text[]),
 collect_security.reconciliation_actor_current(uuid,uuid) from public,anon,authenticated,service_role;
revoke all on function collect_admin_access.account_state(uuid) from public,anon,authenticated,service_role;
revoke all on function public.bootstrap_collect_email_operator_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.bootstrap_collect_email_operator_v1(uuid) to service_role;
revoke all on function public.admin_set_operator_email_mode_v1(text),public.admin_revoke_email_operator_v1(uuid,text)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_set_operator_email_mode_v1(text),public.admin_revoke_email_operator_v1(uuid,text) to authenticated;
revoke all on function public.admin_get_operator_approval_v1(uuid),public.admin_approve_email_operator_v1(uuid,text,text)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_get_operator_approval_v1(uuid),public.admin_approve_email_operator_v1(uuid,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
