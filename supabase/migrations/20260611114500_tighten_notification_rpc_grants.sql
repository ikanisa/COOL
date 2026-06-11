revoke execute on function register_notification_device(text, text, text)
  from public, anon, authenticated;
grant execute on function register_notification_device(text, text, text)
  to authenticated;

revoke execute on function mark_notification_event_read(uuid)
  from public, anon, authenticated;
grant execute on function mark_notification_event_read(uuid)
  to authenticated;

revoke execute on function enqueue_notification_event(uuid, text, text, text, uuid, text)
  from public, anon, authenticated;
grant execute on function enqueue_notification_event(uuid, text, text, text, uuid, text)
  to service_role;
