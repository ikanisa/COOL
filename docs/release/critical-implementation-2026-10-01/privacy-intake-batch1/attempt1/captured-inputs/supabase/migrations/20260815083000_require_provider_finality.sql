begin;

-- A provider transaction is globally single-use within its provider network.
-- Receiver identity is routing evidence, not an idempotency namespace.
do $$
begin
  if exists (
    select 1
    from public.payments payment
    where payment.transaction_id is not null
      and payment.status <> 'reversed'
    group by payment.provider_network, upper(btrim(payment.transaction_id))
    having count(*) > 1
  ) then
    raise exception 'Provider transaction duplicates require reconciliation before this migration can continue';
  end if;
end;
$$;

drop index if exists public.payments_receiver_network_transaction_unique;
create unique index if not exists payments_provider_transaction_unique
  on public.payments (
    provider_network,
    upper(btrim(transaction_id))
  )
  where transaction_id is not null and status <> 'reversed';

-- SMS is candidate evidence only. A payment in review reserves the canonical
-- provider transaction but does not affect a member or group balance.
alter table public.payments
  alter column posted_at drop not null;

create table if not exists public.payment_provider_confirmations (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null unique
    references public.payments(id) on delete restrict,
  provider_network text not null,
  provider_confirmation_id text not null,
  transaction_id text not null,
  receiver_momo_number_hash text not null,
  amount_rwf bigint not null check (amount_rwf > 0),
  currency text not null default 'RWF' check (currency = 'RWF'),
  confirmed_at timestamptz not null,
  evidence_sha256 text
    check (evidence_sha256 is null or evidence_sha256 ~ '^[0-9a-f]{64}$'),
  recorded_at timestamptz not null default now()
);

create unique index if not exists payment_provider_confirmation_reference_unique
  on public.payment_provider_confirmations (
    provider_network,
    upper(btrim(provider_confirmation_id))
  );
create unique index if not exists payment_provider_confirmation_transaction_unique
  on public.payment_provider_confirmations (
    provider_network,
    upper(btrim(transaction_id))
  );

alter table public.payment_provider_confirmations enable row level security;
revoke all on public.payment_provider_confirmations
  from public, anon, authenticated;

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
  event_row public.parsed_payment_events;
  intent_row public.payment_intents;
  raw_row public.raw_payment_sms;
  receiver_id uuid;
  payment_id uuid;
begin
  select *
  into event_row
  from public.parsed_payment_events event
  where event.id = event_id
  for update;
  if not found then
    raise exception 'Parsed event not found';
  end if;

  select payment.id
  into payment_id
  from public.payments payment
  where payment.parsed_event_id = event_id;
  if payment_id is not null then
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
    raise exception 'SMS payment evidence is incomplete or below the review threshold';
  end if;

  select *
  into intent_row
  from public.payment_intents intent
  where intent.id = intent_id
  for update;
  if not found then
    raise exception 'Payment intent not found';
  end if;
  if intent_row.status <> 'pending' or intent_row.expires_at <= now() then
    raise exception 'Payment intent is not active';
  end if;
  if intent_row.collection_id <> target_collection_id
     or intent_row.receiver_momo_number_hash <> event_row.receiver_phone_hash
     or intent_row.expected_amount_rwf <> event_row.amount_rwf then
    raise exception 'Payment intent does not match the SMS evidence';
  end if;
  if not (
    (
      event_row.sender_phone_hash is not null
      and intent_row.sender_phone_hash = event_row.sender_phone_hash
    )
    or (
      event_row.detected_user_public_id is not null
      and intent_row.contributor_public_id = event_row.detected_user_public_id
    )
  ) then
    raise exception 'Payer identity does not match the payment intent';
  end if;

  select *
  into raw_row
  from public.raw_payment_sms raw
  where raw.id = event_row.raw_sms_id;
  if coalesce(raw_row.received_at_device, raw_row.ingested_at)
     not between intent_row.created_at - interval '15 minutes'
       and intent_row.expires_at + interval '2 hours' then
    raise exception 'SMS evidence timestamp is outside the payment intent window';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      event_row.network || ':' || upper(btrim(event_row.transaction_id)),
      0
    )
  );

  select payment.id
  into payment_id
  from public.payments payment
  where payment.provider_network = event_row.network
    and upper(btrim(payment.transaction_id)) = upper(btrim(event_row.transaction_id))
    and payment.status <> 'reversed'
  order by payment.created_at
  limit 1;
  if payment_id is not null then
    update public.parsed_payment_events
    set allocation_status = 'ignored',
        review_reason = 'Duplicate provider transaction evidence'
    where id = event_id;
    return payment_id;
  end if;

  select receiver.receiver_user_id
  into receiver_id
  from public.collection_receivers receiver
  where receiver.collection_id = target_collection_id
    and receiver.momo_number_hash = event_row.receiver_phone_hash
    and receiver.is_active
  order by receiver.created_at desc
  limit 1;
  if receiver_id is null or receiver_id <> event_row.receiver_user_id then
    raise exception 'SMS receiver is not configured for the target group';
  end if;

  insert into public.payments (
    parsed_event_id,
    payment_intent_id,
    collection_id,
    contributor_user_id,
    contributor_public_id,
    receiver_user_id,
    receiver_momo_number_hash,
    amount_rwf,
    transaction_id,
    provider_network,
    source,
    status,
    anonymity_choice,
    posted_at
  ) values (
    event_id,
    intent_id,
    target_collection_id,
    intent_row.contributor_user_id,
    intent_row.contributor_public_id,
    receiver_id,
    event_row.receiver_phone_hash,
    event_row.amount_rwf,
    event_row.transaction_id,
    event_row.network,
    'sms_auto',
    'review',
    intent_row.anonymity_choice,
    null
  ) returning id into payment_id;

  insert into public.payment_allocations (
    payment_id,
    parsed_event_id,
    collection_id,
    payment_intent_id,
    allocated_by,
    allocation_method,
    confidence,
    reason
  ) values (
    payment_id,
    event_id,
    target_collection_id,
    intent_id,
    null,
    'auto_native_sms',
    event_row.confidence,
    allocation_reason || '; awaiting independent provider confirmation'
  );

  update public.parsed_payment_events
  set allocation_status = 'needs_review',
      review_reason = 'Matched to one payer-verified intent; awaiting independent provider confirmation'
  where id = event_id;
  update public.payment_intents
  set status = 'matched'
  where id = intent_id;

  insert into public.audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    metadata
  ) values (
    null,
    'payment.awaiting_provider_confirmation',
    'payment',
    payment_id,
    jsonb_build_object(
      'parsed_event_id', event_id,
      'payment_intent_id', intent_id,
      'method', 'native_sms_candidate',
      'ledger_posted', false
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
  event_row public.parsed_payment_events;
  evidence_time timestamptz;
  match_intent_id uuid;
  match_collection_id uuid;
  match_receiver_hash text;
  possible_count integer;
  result_status text;
  existing_payment_status text;
begin
  select *
  into event_row
  from public.parsed_payment_events event
  where event.id = event_id
  for update;
  if not found then
    raise exception 'Parsed event not found';
  end if;

  select payment.status
  into existing_payment_status
  from public.payments payment
  where payment.parsed_event_id = event_id;
  if existing_payment_status = 'posted' then
    return 'already_allocated';
  elsif existing_payment_status = 'review' then
    return 'awaiting_provider_confirmation';
  elsif event_row.allocation_status = 'allocated' then
    return 'already_allocated';
  end if;

  select coalesce(raw.received_at_device, raw.ingested_at)
  into evidence_time
  from public.raw_payment_sms raw
  where raw.id = event_row.raw_sms_id;

  if not event_row.is_mobile_money_payment
     or event_row.direction <> 'incoming'
     or event_row.currency <> 'RWF'
     or event_row.amount_rwf is null
     or event_row.amount_rwf <= 0
     or event_row.transaction_id is null
     or event_row.confidence < 0.90 then
    update public.parsed_payment_events
    set allocation_status = 'needs_review',
        review_reason = 'SMS evidence is incomplete or not reliable enough for candidate matching'
    where id = event_id;
    return 'needs_review';
  end if;

  update public.payment_intents
  set status = 'expired'
  where status = 'pending'
    and expires_at <= now();

  with candidates as (
    select distinct
      intent.id,
      intent.collection_id,
      intent.receiver_momo_number_hash,
      intent.created_at
    from public.payment_intents intent
    join public.collection_receivers route
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
        (
          event_row.sender_phone_hash is not null
          and intent.sender_phone_hash = event_row.sender_phone_hash
        )
        or (
          event_row.detected_user_public_id is not null
          and intent.contributor_public_id = event_row.detected_user_public_id
        )
      )
  )
  select
    count(*),
    (array_agg(candidate.id order by candidate.created_at))[1],
    (array_agg(candidate.collection_id order by candidate.created_at))[1],
    (array_agg(candidate.receiver_momo_number_hash order by candidate.created_at))[1]
  into possible_count, match_intent_id, match_collection_id, match_receiver_hash
  from candidates candidate;

  if possible_count = 1 then
    if event_row.receiver_phone_hash is null then
      update public.parsed_payment_events
      set receiver_phone_hash = match_receiver_hash,
          collection_id = coalesce(collection_id, match_collection_id)
      where id = event_id;
    end if;

    perform public.post_payment_from_event(
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

    select allocation_status::text
    into result_status
    from public.parsed_payment_events
    where id = event_id;
    if result_status = 'allocated' then
      return 'allocated';
    elsif result_status = 'needs_review' then
      return 'awaiting_provider_confirmation';
    end if;
    return 'ignored';
  elsif possible_count > 1 then
    update public.parsed_payment_events
    set allocation_status = 'ambiguous',
        review_reason = 'Multiple payer-verified payment intents matched this SMS evidence'
    where id = event_id;
    return 'ambiguous';
  end if;

  update public.parsed_payment_events
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

create or replace function public.confirm_provider_payment(
  p_payment_id uuid,
  p_provider_network text,
  p_transaction_id text,
  p_provider_confirmation_id text,
  p_receiver_momo_number_hash text,
  p_amount_rwf bigint,
  p_confirmed_at timestamptz,
  p_evidence_sha256 text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  payment_row public.payments;
  clean_network text := lower(trim(coalesce(p_provider_network, '')));
  clean_transaction_id text := upper(trim(coalesce(p_transaction_id, '')));
  clean_confirmation_id text := upper(trim(coalesce(p_provider_confirmation_id, '')));
  clean_receiver_hash text := lower(trim(coalesce(p_receiver_momo_number_hash, '')));
  clean_evidence_hash text := lower(trim(coalesce(p_evidence_sha256, '')));
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_payment_id is null
     or char_length(clean_network) not between 2 and 32
     or char_length(clean_transaction_id) not between 3 and 128
     or char_length(clean_confirmation_id) not between 3 and 128
     or clean_receiver_hash !~ '^[0-9a-f]{64}$'
     or p_amount_rwf is null
     or p_amount_rwf <= 0
     or p_confirmed_at is null
     or p_confirmed_at > now() + interval '5 minutes'
     or (clean_evidence_hash <> '' and clean_evidence_hash !~ '^[0-9a-f]{64}$') then
    raise exception 'Invalid provider confirmation';
  end if;

  select *
  into payment_row
  from public.payments payment
  where payment.id = p_payment_id
  for update;
  if not found then
    raise exception 'Payment not found';
  end if;

  if payment_row.status = 'posted' then
    if exists (
      select 1
      from public.payment_provider_confirmations confirmation
      where confirmation.payment_id = payment_row.id
        and confirmation.provider_network = clean_network
        and upper(btrim(confirmation.provider_confirmation_id)) = clean_confirmation_id
    ) then
      return payment_row.id;
    end if;
    raise exception 'Payment was already finalized by a different confirmation';
  end if;
  if payment_row.status <> 'review' then
    raise exception 'Payment is not awaiting provider confirmation';
  end if;
  if lower(payment_row.provider_network) <> clean_network
     or upper(btrim(payment_row.transaction_id)) <> clean_transaction_id
     or payment_row.receiver_momo_number_hash <> clean_receiver_hash
     or payment_row.amount_rwf <> p_amount_rwf then
    raise exception 'Provider confirmation does not match the payment candidate';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(clean_network || ':' || clean_transaction_id, 0)
  );

  insert into public.payment_provider_confirmations (
    payment_id,
    provider_network,
    provider_confirmation_id,
    transaction_id,
    receiver_momo_number_hash,
    amount_rwf,
    confirmed_at,
    evidence_sha256
  ) values (
    payment_row.id,
    clean_network,
    clean_confirmation_id,
    clean_transaction_id,
    clean_receiver_hash,
    p_amount_rwf,
    p_confirmed_at,
    nullif(clean_evidence_hash, '')
  );

  insert into public.ledger_entries (
    payment_id,
    collection_id,
    user_id,
    entry_type,
    amount_rwf,
    visibility,
    metadata
  ) values
    (
      payment_row.id,
      payment_row.collection_id,
      payment_row.contributor_user_id,
      'collection_credit',
      payment_row.amount_rwf,
      'public_safe',
      jsonb_build_object(
        'allocation_method', 'provider_confirmed',
        'provider_confirmation_id', clean_confirmation_id
      )
    ),
    (
      payment_row.id,
      payment_row.collection_id,
      payment_row.contributor_user_id,
      'member_credit',
      payment_row.amount_rwf,
      'private',
      jsonb_build_object(
        'allocation_method', 'provider_confirmed',
        'provider_confirmation_id', clean_confirmation_id
      )
    );

  update public.payments
  set status = 'posted',
      posted_at = p_confirmed_at
  where id = payment_row.id;

  update public.parsed_payment_events
  set allocation_status = 'allocated',
      review_reason = 'Posted after independent provider confirmation'
  where id = payment_row.parsed_event_id;

  insert into public.audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    metadata
  ) values (
    null,
    'payment.provider_confirmed',
    'payment',
    payment_row.id,
    jsonb_build_object(
      'provider_network', clean_network,
      'provider_confirmation_id', clean_confirmation_id,
      'confirmed_at', p_confirmed_at,
      'ledger_posted', true
    )
  );

  return payment_row.id;
end;
$$;

revoke all on function public.confirm_provider_payment(
  uuid, text, text, text, text, bigint, timestamptz, text
) from public, anon, authenticated;
grant execute on function public.confirm_provider_payment(
  uuid, text, text, text, text, bigint, timestamptz, text
) to service_role;

create or replace function public.reject_provider_payment(
  p_payment_id uuid,
  p_reason text,
  p_provider_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  payment_row public.payments;
  clean_reason text := trim(coalesce(p_reason, ''));
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if char_length(clean_reason) not between 3 and 500 then
    raise exception 'A bounded rejection reason is required';
  end if;

  select *
  into payment_row
  from public.payments payment
  where payment.id = p_payment_id
  for update;
  if not found then
    raise exception 'Payment not found';
  end if;
  if payment_row.status = 'reversed' then
    return payment_row.id;
  end if;
  if payment_row.status <> 'review' then
    raise exception 'Only a review payment can be rejected';
  end if;

  update public.payments
  set status = 'reversed',
      posted_at = null
  where id = payment_row.id;
  update public.parsed_payment_events
  set allocation_status = 'needs_review',
      review_reason = 'Provider rejected payment candidate: ' || clean_reason
  where id = payment_row.parsed_event_id;
  update public.payment_intents
  set status = 'cancelled'
  where id = payment_row.payment_intent_id;

  insert into public.audit_logs (
    actor_user_id,
    action,
    entity_type,
    entity_id,
    metadata
  ) values (
    null,
    'payment.provider_rejected',
    'payment',
    payment_row.id,
    jsonb_build_object(
      'reason', clean_reason,
      'provider_reference', nullif(trim(coalesce(p_provider_reference, '')), ''),
      'ledger_posted', false
    )
  );

  return payment_row.id;
end;
$$;

revoke all on function public.reject_provider_payment(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.reject_provider_payment(uuid, text, text)
  to service_role;

-- Confirmation notifications fire only on the first transition to posted.
create or replace function public.enqueue_contribution_confirmation_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  group_title text;
begin
  if new.status <> 'posted'
     or new.contributor_user_id is null
     or (tg_op = 'UPDATE' and old.status = 'posted') then
    return new;
  end if;
  select title
  into group_title
  from public.collections
  where id = new.collection_id;
  perform public.enqueue_notification_template_event(
    new.contributor_user_id,
    'contribution.confirmed.default',
    jsonb_build_object(
      'amount', 'RWF ' || new.amount_rwf::text,
      'group', coalesce(group_title, 'your group')
    ),
    new.collection_id,
    '/groups/' || new.collection_id::text || '/ledger',
    'en'
  );
  return new;
end;
$$;

drop trigger if exists enqueue_contribution_confirmation_notification_trigger
  on public.payments;
create trigger enqueue_contribution_confirmation_notification_trigger
after insert or update of status on public.payments
for each row execute function public.enqueue_contribution_confirmation_notification();

revoke execute on function public.enqueue_contribution_confirmation_notification()
  from public, anon, authenticated;

commit;
