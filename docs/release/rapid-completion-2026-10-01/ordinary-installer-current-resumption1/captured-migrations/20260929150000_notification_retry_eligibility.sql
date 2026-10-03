begin;

-- Match the notification retry action's ownership, transport and live-claim
-- restrictions so operators are not offered retries the action must reject.
create or replace function public.admin_get_notification(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.assert_admin_permission('notifications.read');
  return coalesce((
    select jsonb_build_object(
      'id', event.id,
      'type', event.type,
      'title', event.title,
      'status', event.status,
      'collect_id', profile.public_id,
      'collection_id', event.collection_id,
      'deep_link', event.deep_link,
      'delivery_statuses', coalesce((
        select string_agg(count_rows.status || ': ' || count_rows.delivery_count::text, ', ' order by count_rows.status)
        from (
          select status, count(*) as delivery_count
          from public.notification_deliveries
          where event_id = event.id
          group by status
        ) count_rows
      ), 'No registered delivery'),
      'retryable_count', (
        select count(*)
        from public.notification_deliveries delivery
        join public.notification_device_tokens device on device.id = delivery.device_id
        where delivery.event_id = event.id
          and delivery.status = 'failed'
          and device.enabled
          and device.user_id = event.user_id
          and device.provider in ('apns', 'fcm')
          and device.token is not null
          and (delivery.claim_expires_at is null
            or delivery.claim_expires_at <= clock_timestamp())
      ),
      'cumulative_attempt_count', coalesce((
        select sum(delivery.prior_attempt_count + delivery.attempt_count)
        from public.notification_deliveries delivery
        where delivery.event_id = event.id
      ), 0),
      'last_error_code', event.last_error_code,
      'created_at', event.created_at,
      'sent_at', event.sent_at,
      'read_at', event.read_at
    )
    from public.notification_events event
    join public.profiles profile on profile.id = event.user_id
    where event.id = p_id
  ), '{}'::jsonb);
end;
$$;

revoke execute on function public.admin_get_notification(uuid) from public, anon;
grant execute on function public.admin_get_notification(uuid) to authenticated;

commit;
