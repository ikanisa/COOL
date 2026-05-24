set search_path = public;

revoke execute on all functions in schema public from public;
alter default privileges in schema public revoke execute on functions from public;

grant execute on all functions in schema public to service_role;

grant execute on function public.current_user_is_platform_admin() to anon, authenticated;
grant execute on function public.user_is_collection_admin(uuid, uuid) to anon, authenticated;
grant execute on function public.user_can_read_collection(uuid, uuid) to anon, authenticated;
grant execute on function public.user_can_ingest_receiver_sms(text, uuid, uuid) to authenticated;

grant execute on function public.get_current_profile() to authenticated;
grant execute on function public.create_collection_with_owner(text, text, text, bigint, text, text, text, text, boolean, jsonb) to authenticated;
grant execute on function public.create_collection_invite(uuid, text, text, member_role) to authenticated;
grant execute on function public.create_payment_intent(uuid, bigint, text, text) to authenticated;
grant execute on function public.create_payment_intent_with_instructions(uuid, bigint, text, text) to authenticated;
grant execute on function public.report_payment_intent_paid(uuid, text) to authenticated;
grant execute on function public.request_public_collection(uuid) to authenticated;
grant execute on function public.review_public_collection(uuid, boolean, text) to authenticated;
grant execute on function public.manual_allocate_parsed_payment_event(uuid, uuid, uuid, text) to authenticated;
