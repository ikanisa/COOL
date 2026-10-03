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
