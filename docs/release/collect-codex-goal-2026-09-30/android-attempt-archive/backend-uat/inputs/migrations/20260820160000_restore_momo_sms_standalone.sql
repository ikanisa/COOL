begin;

-- These objects were deployed by two migrations on 2026-08-15. Keep those
-- history files immutable, then remove their runtime effects in this forward
-- migration so production and fresh databases converge on the standalone
-- OpenAI SMS allocation design.
do $$
begin
  if exists (
    select 1
    from public.payments payment
    where payment.source = 'sms_auto'
      and payment.status = 'review'
  ) then
    raise exception 'Standalone SMS restoration requires zero unposted SMS review payments';
  end if;
  if exists (select 1 from public.payment_provider_confirmations) then
    raise exception 'Standalone SMS restoration requires reviewed export of legacy confirmation rows';
  end if;
  if exists (select 1 from public.provider_finality_requests) then
    raise exception 'Standalone SMS restoration requires reviewed export of legacy request rows';
  end if;
end;
$$;

drop function if exists public.process_provider_finality_event(
  uuid, text, text, uuid, text, text, text, text, bigint, timestamptz, text,
  text, text
);
drop function if exists public.confirm_provider_payment(
  uuid, text, text, text, text, bigint, timestamptz, text
);
drop function if exists public.reject_provider_payment(uuid, text, text);

drop table if exists public.provider_finality_requests;
drop table if exists public.payment_provider_confirmations;

drop index if exists public.payments_provider_transaction_unique;
create unique index if not exists payments_receiver_network_transaction_unique
  on public.payments (
    receiver_momo_number_hash,
    provider_network,
    upper(btrim(transaction_id))
  )
  where transaction_id is not null and status <> 'reversed';

update public.payments
set posted_at = coalesce(posted_at, created_at, now())
where posted_at is null;
alter table public.payments
  alter column posted_at set not null;

drop function if exists public.post_payment_from_event(uuid, uuid, uuid, text, text, uuid);
create or replace function public.post_payment_from_event(
  event_id uuid,
  intent_id uuid,
  target_collection_id uuid,
  allocation_reason text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  event_row parsed_payment_events;
  intent_row payment_intents;
  raw_row raw_payment_sms;
  receiver_id uuid;
  payment_id uuid;
begin
  select * into event_row from parsed_payment_events where id = event_id for update;
  if not found then raise exception 'Parsed event not found'; end if;
  if event_row.allocation_status = 'allocated' then
    select payment.id into payment_id from payments payment
    where payment.parsed_event_id = event_id;
    return payment_id;
  end if;
  if not event_row.is_mobile_money_payment
     or event_row.direction <> 'incoming'
     or event_row.currency <> 'RWF'
     or event_row.amount_rwf is null
     or event_row.amount_rwf <= 0
     or event_row.transaction_id is null
     or event_row.receiver_phone_hash is null
     or event_row.confidence < 0.90 then
    raise exception 'SMS payment evidence is incomplete or below the posting threshold';
  end if;

  select * into intent_row from payment_intents where id = intent_id for update;
  if not found then raise exception 'Payment intent not found'; end if;
  if intent_row.status <> 'pending' or intent_row.expires_at <= now() then
    raise exception 'Payment intent is not active';
  end if;
  if intent_row.collection_id <> target_collection_id
     or intent_row.receiver_momo_number_hash <> event_row.receiver_phone_hash
     or intent_row.expected_amount_rwf <> event_row.amount_rwf then
    raise exception 'Payment intent does not match the SMS evidence';
  end if;
  if not (
    (event_row.sender_phone_hash is not null
      and intent_row.sender_phone_hash = event_row.sender_phone_hash)
    or (event_row.detected_user_public_id is not null
      and intent_row.contributor_public_id = event_row.detected_user_public_id)
  ) then
    raise exception 'Payer identity does not match the payment intent';
  end if;

  select * into raw_row from raw_payment_sms where id = event_row.raw_sms_id;
  if coalesce(raw_row.received_at_device, raw_row.ingested_at)
     not between intent_row.created_at - interval '15 minutes'
       and intent_row.expires_at + interval '2 hours' then
    raise exception 'SMS evidence timestamp is outside the payment intent window';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      event_row.receiver_phone_hash || ':' || event_row.network || ':' ||
      upper(btrim(event_row.transaction_id)),
      0
    )
  );

  if exists (
    select 1 from payments payment
    where payment.receiver_momo_number_hash = event_row.receiver_phone_hash
      and payment.provider_network = event_row.network
      and upper(btrim(payment.transaction_id)) = upper(btrim(event_row.transaction_id))
      and payment.status <> 'reversed'
  ) then
    select payment.id into payment_id
    from payments payment
    where payment.receiver_momo_number_hash = event_row.receiver_phone_hash
      and payment.provider_network = event_row.network
      and upper(btrim(payment.transaction_id)) = upper(btrim(event_row.transaction_id))
      and payment.status <> 'reversed'
    order by payment.created_at
    limit 1;
    update parsed_payment_events
    set allocation_status = 'ignored',
        review_reason = 'Duplicate SMS transaction evidence'
    where id = event_id;
    return payment_id;
  end if;

  select receiver.receiver_user_id into receiver_id
  from collection_receivers receiver
  where receiver.collection_id = target_collection_id
    and receiver.momo_number_hash = event_row.receiver_phone_hash
  order by receiver.created_at desc
  limit 1;
  if receiver_id is null or receiver_id <> event_row.receiver_user_id then
    raise exception 'SMS receiver is not configured for the target group';
  end if;

  insert into payments (
    parsed_event_id, payment_intent_id, collection_id,
    contributor_user_id, contributor_public_id, receiver_user_id,
    receiver_momo_number_hash, amount_rwf, transaction_id,
    provider_network, source, anonymity_choice
  ) values (
    event_id, intent_id, target_collection_id,
    intent_row.contributor_user_id, intent_row.contributor_public_id, receiver_id,
    event_row.receiver_phone_hash, event_row.amount_rwf, event_row.transaction_id,
    event_row.network,
    'sms_auto',
    intent_row.anonymity_choice
  ) returning id into payment_id;

  insert into payment_allocations (
    payment_id, parsed_event_id, collection_id, payment_intent_id,
    allocated_by, allocation_method, confidence, reason
  ) values (
    payment_id, event_id, target_collection_id, intent_id,
    null, 'auto_native_sms', event_row.confidence, allocation_reason
  );

  insert into ledger_entries (
    payment_id, collection_id, user_id, entry_type,
    amount_rwf, visibility, metadata
  ) values
    (
      payment_id, target_collection_id, intent_row.contributor_user_id,
      'collection_credit', event_row.amount_rwf, 'public_safe',
      jsonb_build_object('allocation_method', 'auto_native_sms', 'parsed_event_id', event_id)
    ),
    (
      payment_id, target_collection_id, intent_row.contributor_user_id,
      'member_credit', event_row.amount_rwf, 'private',
      jsonb_build_object('allocation_method', 'auto_native_sms', 'parsed_event_id', event_id)
    );

  update parsed_payment_events
  set allocation_status = 'allocated', review_reason = allocation_reason
  where id = event_id;
  update payment_intents set status = 'matched' where id = intent_id;

  insert into audit_logs (actor_user_id, action, entity_type, entity_id, metadata)
  values (
    null,
    'payment.allocated.auto',
    'payment', payment_id,
    jsonb_build_object(
      'parsed_event_id', event_id,
      'payment_intent_id', intent_id,
      'method', 'auto_native_sms',
      'reason', allocation_reason
    )
  );
  return payment_id;
end;
$$;
revoke execute on function public.post_payment_from_event(uuid, uuid, uuid, text)
  from public, anon, authenticated;

create or replace function public.allocate_parsed_payment_event(event_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  event_row parsed_payment_events;
  evidence_time timestamptz;
  match_intent_id uuid;
  match_collection_id uuid;
  match_receiver_hash text;
  possible_count integer;
  result_status text;
begin
  select * into event_row
  from parsed_payment_events event
  where event.id = event_id
  for update;
  if not found then raise exception 'Parsed event not found'; end if;
  select coalesce(raw.received_at_device, raw.ingested_at)
  into evidence_time
  from raw_payment_sms raw
  where raw.id = event_row.raw_sms_id;
  if event_row.allocation_status = 'allocated' then return 'already_allocated'; end if;

  if not event_row.is_mobile_money_payment
     or event_row.direction <> 'incoming'
     or event_row.currency <> 'RWF'
     or event_row.amount_rwf is null
     or event_row.amount_rwf <= 0
     or event_row.transaction_id is null
     or event_row.confidence < 0.90 then
    update parsed_payment_events
    set allocation_status = 'needs_review',
        review_reason = 'SMS evidence is incomplete or not reliable enough for candidate matching'
    where id = event_id;
    return 'needs_review';
  end if;

  update payment_intents set status = 'expired'
  where status = 'pending' and expires_at <= now();

  with candidates as (
    select distinct
      intent.id,
      intent.collection_id,
      intent.receiver_momo_number_hash,
      intent.created_at
    from payment_intents intent
    join collection_receivers route
      on route.collection_id = intent.collection_id
     and route.momo_number_hash = intent.receiver_momo_number_hash
     and route.is_active
     and route.receiver_user_id = event_row.receiver_user_id
    where intent.status = 'pending'
      and (
        event_row.collection_id is null
        or intent.collection_id = event_row.collection_id
      )
      and (
        event_row.receiver_phone_hash is null
        or intent.receiver_momo_number_hash = event_row.receiver_phone_hash
      )
      and intent.expected_amount_rwf = event_row.amount_rwf
      and evidence_time between intent.created_at - interval '15 minutes'
        and intent.expires_at + interval '2 hours'
      and (
        (event_row.sender_phone_hash is not null
          and intent.sender_phone_hash = event_row.sender_phone_hash)
        or (event_row.detected_user_public_id is not null
          and intent.contributor_public_id = event_row.detected_user_public_id)
      )
  )
  select count(*),
    (array_agg(candidate.id order by candidate.created_at))[1],
    (array_agg(candidate.collection_id order by candidate.created_at))[1],
    (array_agg(candidate.receiver_momo_number_hash order by candidate.created_at))[1]
  into possible_count, match_intent_id, match_collection_id, match_receiver_hash
  from candidates candidate;

  if possible_count = 1 then
    if event_row.receiver_phone_hash is null then
      update parsed_payment_events
      set receiver_phone_hash = match_receiver_hash,
          collection_id = coalesce(collection_id, match_collection_id)
      where id = event_id;
    end if;
    perform post_payment_from_event(
      event_id,
      match_intent_id,
      match_collection_id,
      case
        when event_row.receiver_phone_hash is null then
          'Matched by native SMS transaction ID plus one unique owned receiver, amount, payer, and time window'
        else
          'Matched by native SMS transaction ID, receiver, amount, payer, and time window'
      end
    );
    select allocation_status::text into result_status
    from parsed_payment_events where id = event_id;
    if result_status = 'allocated' then
      return 'allocated';
    end if;
    return 'ignored';
  elsif possible_count > 1 then
    update parsed_payment_events
    set allocation_status = 'ambiguous',
        review_reason = 'Multiple payer-verified payment intents matched this SMS evidence'
    where id = event_id;
    return 'ambiguous';
  end if;

  update parsed_payment_events
  set allocation_status = 'needs_review',
      review_reason = 'No payer-verified pending payment intent matched this SMS evidence'
  where id = event_id;
  return 'needs_review';
end;
$$;
revoke execute on function public.allocate_parsed_payment_event(uuid)
  from public, anon, authenticated;
grant execute on function public.allocate_parsed_payment_event(uuid)
  to service_role;

comment on function public.allocate_parsed_payment_event(uuid) is
  'Matches one complete OpenAI-parsed receipt to one pending payer intent and posts the balanced ledger atomically.';
comment on function public.post_payment_from_event(uuid, uuid, uuid, text) is
  'Locked standalone SMS posting transition; unavailable to client roles.';

commit;
