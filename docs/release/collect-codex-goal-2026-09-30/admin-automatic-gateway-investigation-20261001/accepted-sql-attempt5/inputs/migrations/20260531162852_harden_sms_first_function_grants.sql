-- Remove implicit PUBLIC execution from SMS-first security-definer RPCs.
-- Keep only the explicit roles required by the mobile app, admin PWA, and
-- service-role allocation pipeline.

revoke execute on function admin_list_payment_events(text, text)
  from public, anon;
revoke execute on function admin_list_allocations(text, text)
  from public, anon;
revoke execute on function admin_list_unallocated(text, text)
  from public, anon;
revoke execute on function admin_get_payment_event(uuid)
  from public, anon;

revoke execute on function create_group_with_owner(text, text, text, text, text)
  from public, anon;
revoke execute on function join_group_by_slug(text)
  from public, anon;
revoke execute on function create_payment_intent(uuid, bigint, text)
  from public, anon;
revoke execute on function create_contribution_intent(uuid, bigint, text)
  from public, anon;
revoke execute on function record_sms_access_consent(boolean, text, text, text)
  from public, anon;
revoke execute on function allocate_parsed_payment_event(uuid)
  from public, anon, authenticated;

grant execute on function admin_list_payment_events(text, text)
  to authenticated;
grant execute on function admin_list_allocations(text, text)
  to authenticated;
grant execute on function admin_list_unallocated(text, text)
  to authenticated;
grant execute on function admin_get_payment_event(uuid)
  to authenticated;

grant execute on function create_group_with_owner(text, text, text, text, text)
  to authenticated;
grant execute on function join_group_by_slug(text)
  to authenticated;
grant execute on function create_payment_intent(uuid, bigint, text)
  to authenticated;
grant execute on function create_contribution_intent(uuid, bigint, text)
  to authenticated;
grant execute on function record_sms_access_consent(boolean, text, text, text)
  to authenticated;
grant execute on function allocate_parsed_payment_event(uuid)
  to service_role;
