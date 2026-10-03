begin;

create or replace function admin_record_operator_note(
  p_entity_type text,
  p_entity_id uuid,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  note_id uuid;
  normalized_entity_type text := trim(coalesce(p_entity_type, ''));
  normalized_body text := trim(coalesce(p_body, ''));
begin
  if normalized_body = '' then
    raise exception 'Note body is required';
  end if;

  case normalized_entity_type
    when 'collection' then perform assert_admin_permission('collections.read');
    when 'profile' then perform assert_admin_permission('users.read');
    when 'payment_intent' then perform assert_admin_permission('payments.read');
    when 'parsed_payment_event' then perform assert_admin_permission('payment_events.read');
    when 'payment_receiver' then perform assert_admin_permission('collections.read');
    when 'raw_payment_sms' then perform assert_admin_permission('sms.metadata.read');
    else raise exception 'Unsupported admin note entity type: %', normalized_entity_type;
  end case;

  insert into admin_notes (entity_type, entity_id, body, created_by)
  values (normalized_entity_type, p_entity_id, normalized_body, auth.uid())
  returning id into note_id;

  perform create_audit_log(
    'admin.operator_note.recorded',
    normalized_entity_type,
    p_entity_id,
    jsonb_build_object('note_id', note_id)
  );

  return jsonb_build_object('ok', true, 'note_id', note_id);
end;
$$;

revoke execute on function admin_record_operator_note(text, uuid, text)
  from public, anon;
grant execute on function admin_record_operator_note(text, uuid, text)
  to authenticated;

commit;
