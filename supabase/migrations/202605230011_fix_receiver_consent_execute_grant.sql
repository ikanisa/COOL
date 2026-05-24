set search_path = public;

revoke execute on function record_receiver_mode_consent(boolean, text, text, text) from public, anon;
grant execute on function record_receiver_mode_consent(boolean, text, text, text) to authenticated;
