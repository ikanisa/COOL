CREATE OR REPLACE FUNCTION public.admin_reveal_raw_sms(p_sms_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  raw_body text;
  reason text := btrim(coalesce(p_reason,''));
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
