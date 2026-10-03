begin;

-- Exact legacy approval contract with a current email-mode guard.
create or replace function collect_admin_access.approve_whatsapp(
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
  perform public._lock_notification_session_gate();
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  -- A request opened before cutover cannot create a legacy approval after
  -- waiting for the authority/mode lock. Private/bootstrap callers share it.
  perform 1 from collect_admin_access.operator_auth_policy where id and mode='transition' for share;
  if not found or exists(select 1 from collect_admin_access.email_approvals where user_id=p_user) then
    raise exception 'operator_legacy_approval_disabled' using errcode='42501';
  end if;
  if not p_bootstrap then
    perform collect_hybrid.require_roster_actor_authority(auth.uid(),
      public._lock_notification_registration_session(),'platform_owner',array['admin_users.manage']);
  end if;

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

notify pgrst,'reload schema';
commit;
