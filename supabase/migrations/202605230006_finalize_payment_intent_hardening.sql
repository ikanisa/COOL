drop policy if exists "payment intents update contributor txn or admin" on payment_intents;

revoke update on payment_intents from anon, authenticated;
grant select on payment_intents to authenticated;

grant execute on function report_payment_intent_paid(uuid, text) to authenticated;
