begin;

-- Lock current Auth/approval/grant/permission evidence for sensitive RPCs.
-- Default public reads use POST with writable transactions when these proof
-- locks are required. Bodies and ACLs of existing RPC consumers remain
-- unchanged; only their volatility is changed below.
create or replace function public.assert_admin_permission(permission text)
returns void language plpgsql volatile security definer set search_path='' as $$
declare sid uuid;
begin
 begin
  sid:=public._lock_notification_registration_session();
  perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',array[permission]);
 exception when sqlstate '42501' then
  raise exception 'Admin permission % required',permission using errcode='42501';
 end;
end$$;
create or replace function public.has_admin_permission(permission text,user_uuid uuid default auth.uid())
returns boolean language plpgsql stable set search_path='' as $$
begin
 -- RLS reads remain read-only. The normal API uses Read Committed; an old
 -- caller-created snapshot cannot be used to preserve revoked Admin rights.
 if current_setting('transaction_isolation')<>'read committed' then
  raise exception 'admin_snapshot_retry' using errcode='40001';end if;
 return collect_admin_access.permission_allowed(permission,user_uuid);
end$$;

CREATE OR REPLACE FUNCTION public.admin_reveal_raw_sms(p_sms_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  raw_body text;
begin
  perform assert_admin_permission('sms.raw.reveal');
  if char_length(btrim(coalesce(p_reason,''))) not between 1 and 1000 then
    raise exception 'Reason is required';
  end if;
  select s.raw_body into raw_body from raw_payment_sms s where s.id = p_sms_id;
  if raw_body is null then
    raise exception 'Raw SMS not found';
  end if;
  insert into admin_sensitive_access_logs (actor_user_id, entity_type, entity_id, reason)
  values (auth.uid(), 'raw_payment_sms', p_sms_id, p_reason);
  perform create_audit_log('sms.raw.revealed', 'raw_payment_sms', p_sms_id, jsonb_build_object('reason', p_reason));
  return jsonb_build_object('ok', true, 'message', raw_body);
end;
$function$;
CREATE OR REPLACE FUNCTION public.admin_retry_notification(p_event_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  reason text := trim(coalesce(p_reason, ''));
  device_ids uuid[];
  session_ids uuid[];
  retried integer;
begin
  perform public._lock_notification_session_gate();
  perform public.assert_admin_permission('notifications.manage');
  if char_length(reason) not between 1 and 1000 then raise exception 'Reason is required'; end if;
  select array_agg(locked.id) into session_ids from (
    select s.id from auth.sessions s where exists(select 1 from public.notification_device_tokens device
      join public.notification_deliveries d on d.device_id=device.id
      where device.registration_session_id=s.id and d.event_id=p_event_id and d.status='failed')
    order by s.id for share of s
  ) locked;
  select array_agg(locked.id) into device_ids from (
    select device.id from public.notification_device_tokens device
    join public.notification_events event on event.user_id = device.user_id and event.id = p_event_id
    where device.registration_session_id=any(session_ids)
      and public._notification_session_is_live(device.registration_session_id,device.user_id)
      and device.enabled and device.provider in ('apns', 'fcm') and device.token is not null
      and exists (select 1 from public.notification_deliveries d where d.device_id = device.id
        and d.event_id = p_event_id and d.status = 'failed'
        and (d.claim_expires_at is null or d.claim_expires_at <= clock_timestamp()))
    order by device.id for update of device
  ) locked;
  update public.notification_deliveries d set status = 'queued',
    prior_attempt_count = d.prior_attempt_count + d.attempt_count, attempt_count = 0,
    next_attempt_at = clock_timestamp(), last_attempt_at = null, sent_at = null,
    provider_message_id = null, last_error_code = null,
    claim_token = null, claim_expires_at = null, claim_user_id = null, updated_at = clock_timestamp()
  where d.event_id = p_event_id and d.device_id = any(device_ids) and d.status = 'failed'
    and (d.claim_expires_at is null or d.claim_expires_at <= clock_timestamp());
  get diagnostics retried = row_count;
  if retried = 0 then raise exception 'No retryable failed deliveries'; end if;
  perform public._refresh_notification_event(p_event_id);
  perform public.create_audit_log('notification.delivery.retried', 'notification_event', p_event_id,
    jsonb_build_object('reason', reason, 'delivery_count', retried));
  return jsonb_build_object('ok', true, 'status', 'queued', 'delivery_count', retried);
end $function$;
alter function public._admin_list_people_by_membership(boolean, text, text, integer, integer, text) volatile;
alter function public.admin_get_bank_allocation_request(uuid) volatile;
alter function public.admin_get_bank_destination_change_request(uuid) volatile;
alter function public.admin_get_bank_destination(uuid) volatile;
alter function public.admin_get_bank_evidence(uuid) volatile;
alter function public.admin_get_bank_transaction(uuid) volatile;
alter function public.admin_get_bank_transfer_intent(uuid) volatile;
alter function public.admin_get_collect_transaction(text) volatile;
alter function public.admin_get_collection(uuid) volatile;
alter function public.admin_get_hybrid_sms_receipt(uuid) volatile;
alter function public.admin_get_journal_entry(uuid) volatile;
alter function public.admin_get_member_record(uuid) volatile;
alter function public.admin_get_payment_event(uuid) volatile;
alter function public.admin_get_payment_intent(uuid) volatile;
alter function public.admin_get_payment(uuid) volatile;
alter function public.admin_get_queue_sla(text) volatile;
alter function public.admin_get_receiver(uuid) volatile;
alter function public.admin_get_reconciliation_exception(uuid) volatile;
alter function public.admin_get_reconciliation_run(uuid) volatile;
alter function public.admin_get_sms_metadata(uuid) volatile;
alter function public.admin_get_user(uuid) volatile;
alter function public.admin_list_allocations(text, text, integer, integer, text) volatile;
alter function public.admin_list_audit_logs(text, text) volatile;
alter function public.admin_list_bank_allocation_requests(text, text, integer, integer, text) volatile;
alter function public.admin_list_bank_destination_change_requests(text, text, integer, integer, text) volatile;
alter function public.admin_list_bank_destinations(text, text, integer, integer, text) volatile;
alter function public.admin_list_bank_evidence(text, text, integer, integer, text) volatile;
alter function public.admin_list_bank_transactions(text, text, integer, integer, text) volatile;
alter function public.admin_list_bank_transfer_intents(text, text, integer, integer, text) volatile;
alter function public.admin_list_collect_ledgers(text, text, integer, integer, text) volatile;
alter function public.admin_list_collect_payees(text, text, integer, integer, text) volatile;
alter function public.admin_list_collect_reconciliations(text, text, integer, integer, text) volatile;
alter function public.admin_list_collect_transactions(text, text, integer, integer, text) volatile;
alter function public.admin_list_collections(text, text, integer, integer, text) volatile;
alter function public.admin_list_hybrid_sms_receipts(text, text, integer, integer, text) volatile;
alter function public.admin_list_journal_entries(text, text, integer, integer, text) volatile;
alter function public.admin_list_ledger(text, text) volatile;
alter function public.admin_list_members(text, text, integer, integer, text) volatile;
alter function public.admin_list_notifications(text, text, integer, integer, text) volatile;
alter function public.admin_list_payment_events(text, text, integer, integer, text) volatile;
alter function public.admin_list_payment_intents(text, text, integer, integer, text) volatile;
alter function public.admin_list_payments(text, text, integer, integer, text) volatile;
alter function public.admin_list_payments(text, text) volatile;
alter function public.admin_list_platform_payee_candidates(text, text, integer, integer, text) volatile;
alter function public.admin_list_receivers(text, text) volatile;
alter function public.admin_list_reconciliation_exceptions(text, text, integer, integer, text) volatile;
alter function public.admin_list_reconciliation_runs(text, text, integer, integer, text) volatile;
alter function public.admin_list_settings(text, text) volatile;
alter function public.admin_list_sms_metadata(text, text) volatile;
alter function public.admin_list_unallocated(text, text, integer, integer, text) volatile;
alter function public.admin_list_users(text, text, integer, integer, text) volatile;
alter function public.admin_overview() volatile;

-- These existing helpers and outer RPC wrappers also execute the permission
-- proof. Keeping an outer wrapper STABLE would run it in a read-only API
-- transaction even though the underlying function now requires row locks.
alter function collect_admin_access.approval_status(uuid) volatile;
alter function collect_admin_access.get_admin_user(uuid) volatile;
alter function collect_admin_access.list_admin_users(text,text,integer,integer,text) volatile;
alter function public.admin_get_admin_user(uuid) volatile;
alter function public.admin_get_whatsapp_approval(uuid) volatile;
alter function public.admin_list_admin_users(text,text,integer,integer,text) volatile;
alter function public.admin_list_collections(text,text) volatile;
alter function public.admin_list_country_scoped(text,text,text,text,integer,integer,text) volatile;
alter function public.admin_list_non_member_users(text,text,integer,integer,text) volatile;
alter function public.admin_list_users(text,text) volatile;

notify pgrst,'reload schema';
commit;
