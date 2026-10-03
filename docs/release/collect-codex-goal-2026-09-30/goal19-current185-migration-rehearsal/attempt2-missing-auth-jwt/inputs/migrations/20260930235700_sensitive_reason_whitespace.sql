begin;

-- Actual current-bundle probes allowed BOM-only reasons and retained
-- invisible Unicode padding in reveal/retry audit reasons. Normalize
-- through235500's private helper before the original1..1000 bounds.
-- Keep authority, locks, API attributes, audit, retry and ACK semantics.
do $$begin
 if to_regprocedure('collect_admin_access.normalized_operator_reason(text)') is null then
  raise exception 'sensitive_reason_normalizer_required' using errcode='55000';
 end if;
end$$;

CREATE OR REPLACE FUNCTION public.admin_reveal_raw_sms(p_sms_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  raw_body text;
  reason text := collect_admin_access.normalized_operator_reason(p_reason);
begin
  perform assert_admin_permission('sms.raw.reveal');
  if char_length(reason) not between 1 and 1000 or reason ~ '^[[:space:]]*$' then
    raise exception 'Reason is required';
  end if;
  select s.raw_body into raw_body from raw_payment_sms s where s.id = p_sms_id;
  if raw_body is null then
    raise exception 'Raw SMS not found';
  end if;
  insert into admin_sensitive_access_logs (actor_user_id, entity_type, entity_id, reason)
  values (auth.uid(), 'raw_payment_sms', p_sms_id, reason);
  perform create_audit_log('sms.raw.revealed', 'raw_payment_sms', p_sms_id, jsonb_build_object('reason', reason));
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
  reason text := collect_admin_access.normalized_operator_reason(p_reason);
  device_ids uuid[];
  session_ids uuid[];
  retried integer;
begin
  perform public._lock_notification_session_gate();
  perform public.assert_admin_permission('notifications.manage');
  if char_length(reason) not between 1 and 1000 or reason ~ '^[[:space:]]*$' then raise exception 'Reason is required'; end if;
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

notify pgrst,'reload schema';
commit;
