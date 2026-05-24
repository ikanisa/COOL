revoke all on raw_payment_sms from anon, authenticated;
grant select (
  id,
  collection_id,
  receiver_user_id,
  raw_sender,
  body_hash,
  receiver_momo_number_hash,
  received_at_device,
  ingested_at,
  parse_status,
  created_at
) on raw_payment_sms to authenticated;

revoke execute on function admin_reveal_raw_sms(uuid, text) from public, anon, authenticated;
grant execute on function admin_reveal_raw_sms(uuid, text) to authenticated;

revoke execute on function admin_manual_allocate_payment(uuid, uuid, uuid, text) from public, anon, authenticated;
grant execute on function admin_manual_allocate_payment(uuid, uuid, uuid, text) to authenticated;

revoke execute on function admin_reparse_payment_event(uuid, text) from public, anon, authenticated;
grant execute on function admin_reparse_payment_event(uuid, text) to authenticated;
