begin;

-- Preserve email identity, role/session locks, original reason bounds, exact
-- ACKs, audit and replay contracts from213000 SHA-256 7d2093a9470ece13ffebf4b5f9bc23e2ea5c563efc4993ea7dd774f5c2623a92.
-- Normalize the whitespace characters used by native/browser String.trim
-- before the existing8..500 character validation and stored audit reason.
create function collect_admin_access.normalized_operator_reason(p_reason text)
returns text language sql immutable security invoker set search_path='' as $$
 select btrim(coalesce(p_reason,''),chr(9)||chr(10)||chr(11)||chr(12)||chr(13)||chr(32)||chr(133)||chr(160)||chr(5760)||chr(8192)||chr(8193)||chr(8194)||chr(8195)||chr(8196)||chr(8197)||chr(8198)||chr(8199)||chr(8200)||chr(8201)||chr(8202)||chr(8232)||chr(8233)||chr(8239)||chr(8287)||chr(12288)||chr(65279));
$$;
revoke all on function collect_admin_access.normalized_operator_reason(text)
 from public,anon,authenticated,service_role;

create or replace function public.admin_set_operator_email_mode_v1(p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;current_mode text;begin
 sid:=public._lock_notification_registration_session();
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',array['admin_users.manage']);
 if not collect_admin_access.email_identity(auth.uid()) or length(collect_admin_access.normalized_operator_reason(p_reason)) not between 8 and 500 then
  raise exception 'current_email_operator_required' using errcode='42501';end if;
 select mode into current_mode from collect_admin_access.operator_auth_policy where id for update;
 if current_mode<>'email' then
  update collect_admin_access.operator_auth_policy set mode='email',revision=revision+1,updated_at=clock_timestamp() where id;
  insert into public.audit_logs(actor_user_id,action,entity_type,metadata)
   values(auth.uid(),'admin.auth.email_cutover','operator_auth_policy',jsonb_build_object('reason',collect_admin_access.normalized_operator_reason(p_reason)));
 end if;
 return jsonb_build_object('ok',true,'mode','email','replay',current_mode='email');
end $$;

create or replace function public.admin_revoke_email_operator_v1(p_user_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;changed boolean;begin
 sid:=public._lock_notification_registration_session();
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',array['admin_users.manage']);
 if p_user_id is null or p_user_id=auth.uid() or length(collect_admin_access.normalized_operator_reason(p_reason)) not between 8 and 500 then
  raise exception 'email_revoke_invalid' using errcode='22023';end if;
 perform 1 from collect_admin_access.email_approvals where user_id=p_user_id for update;
 if not found then raise exception 'operator_email_approval_unavailable' using errcode='22023';end if;
 update collect_admin_access.email_approvals set revoked_at=clock_timestamp(),revoked_by=auth.uid()
  where user_id=p_user_id and revoked_at is null;
 changed:=found;
 if changed then insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'admin.email.revoked','profile',p_user_id,jsonb_build_object('reason',collect_admin_access.normalized_operator_reason(p_reason)));end if;
 return jsonb_build_object('ok',true,'status','revoked','user_id',p_user_id);
end $$;

create or replace function public.admin_approve_email_operator_v1(p_user_id uuid,p_email text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare sid uuid;target auth.users;normalized text:=lower(btrim(p_email));
begin
 sid:=public._lock_notification_registration_session();
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',array['admin_users.manage']);
 if p_user_id is null or p_user_id=auth.uid() or length(collect_admin_access.normalized_operator_reason(p_reason)) not between 8 and 500
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
  values(p_user_id,normalized,auth.uid(),collect_admin_access.normalized_operator_reason(p_reason)) on conflict(user_id) do update
  set email=excluded.email,approved_at=clock_timestamp(),approved_by=excluded.approved_by,reason=excluded.reason,
   revoked_at=null,revoked_by=null,expires_at=null;
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata)
  values(auth.uid(),'admin.email.approved','profile',p_user_id,jsonb_build_object('reason',collect_admin_access.normalized_operator_reason(p_reason)));
 return jsonb_build_object('ok',true,'status','approved','user_id',p_user_id);
end $$;

notify pgrst,'reload schema';
commit;
