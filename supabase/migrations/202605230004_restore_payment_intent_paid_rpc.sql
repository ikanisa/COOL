create or replace function report_payment_intent_paid(
  intent uuid,
  transaction_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  intent_row payment_intents;
  cleaned_transaction_id text;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  select * into intent_row
  from payment_intents
  where id = intent
  for update;

  if not found then
    raise exception 'Payment intent not found';
  end if;

  if intent_row.contributor_user_id is distinct from (select auth.uid())
     and not public.user_is_collection_admin(intent_row.collection_id, (select auth.uid())) then
    raise exception 'Not authorized to report this payment intent';
  end if;

  if intent_row.status <> 'pending' then
    raise exception 'Only pending payment intents can be reported paid';
  end if;

  cleaned_transaction_id := nullif(upper(trim(coalesce(transaction_id, ''))), '');

  update payment_intents
    set reported_transaction_id = cleaned_transaction_id
    where id = intent;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    (select auth.uid()),
    'payment_intent.reported_paid',
    'payment_intent',
    intent,
    jsonb_build_object('transaction_id_present', cleaned_transaction_id is not null)
  );
end;
$$;

grant execute on function report_payment_intent_paid(uuid, text) to authenticated;
