-- Keep public Collect ID as a consistency check only. It is not payer
-- ownership evidence and must not reserve a globally unique provider reference.
-- Both overrides are copied from the effective 20260903084000 functions.
-- The intent-payer predicates are tightened, and a conflicting public payer
-- identifier now holds a direct assignment for operator review.
begin;

alter table collect_hybrid.momo_reconciliation_exceptions
  drop constraint momo_reconciliation_exceptions_code_check;
alter table collect_hybrid.momo_reconciliation_exceptions
  add constraint momo_reconciliation_exceptions_code_check
  check (code in (
    'no_candidate', 'ambiguous_candidate', 'intent_direct_disagreement',
    'member_identity_missing', 'route_changed',
    'provider_confirmation_pending', 'payer_identity_conflict'
  ));

create or replace function public.post_payment_from_event(
  event_id uuid,
  intent_id uuid,
  target_collection_id uuid,
  allocation_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_row public.parsed_payment_events;
  intent_row public.payment_intents;
  raw_row public.raw_payment_sms;
  receiver_id uuid;
  candidate_payment_id uuid;
begin
  select event.* into event_row
  from public.parsed_payment_events event
  where event.id = event_id
  for update;
  if event_row.id is null then raise exception 'Parsed event not found'; end if;

  select payment.id into candidate_payment_id
  from public.payments payment
  where payment.parsed_event_id = event_id;
  if candidate_payment_id is not null then return candidate_payment_id; end if;

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

  select intent.* into intent_row
  from public.payment_intents intent
  where intent.id = intent_id
  for update;
  if intent_row.id is null then raise exception 'Payment intent not found'; end if;
  if intent_row.status <> 'pending' or intent_row.expires_at <= now() then
    raise exception 'Payment intent is not active';
  end if;
  if intent_row.collection_id <> target_collection_id
     or intent_row.receiver_momo_number_hash <> event_row.receiver_phone_hash
     or intent_row.expected_amount_rwf <> event_row.amount_rwf then
    raise exception 'Payment intent does not match the SMS evidence';
  end if;
  if event_row.sender_phone_hash is null
     or intent_row.sender_phone_hash is distinct from event_row.sender_phone_hash
     or intent_row.sender_phone_hash is distinct from
       public._authenticated_momo_phone_hash(intent_row.contributor_user_id)
     or (event_row.detected_user_public_id is not null
       and intent_row.contributor_public_id is distinct from
         event_row.detected_user_public_id) then
    raise exception 'Payer identity does not match the payment intent';
  end if;

  select raw.* into raw_row
  from public.raw_payment_sms raw
  where raw.id = event_row.raw_sms_id;
  if raw_row.id is null
     or raw_row.native_action_capability_id is null
     or raw_row.attestation_request_hash is null
     or raw_row.device_attested_at is null
     or coalesce(raw_row.received_at_device, raw_row.ingested_at)
       not between intent_row.created_at - interval '15 minutes'
         and intent_row.expires_at + interval '2 hours' then
    raise exception 'Device-attested SMS evidence is required within the payment intent window';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    event_row.network || ':' || upper(btrim(event_row.transaction_id)), 0
  ));
  select payment.id into candidate_payment_id
  from public.payments payment
  where payment.provider_network = event_row.network
    and upper(btrim(payment.transaction_id)) = upper(btrim(event_row.transaction_id))
  order by payment.created_at
  limit 1;
  if candidate_payment_id is not null then
    update public.parsed_payment_events
    set allocation_status = 'ignored',
        review_reason = 'Duplicate provider transaction evidence'
    where id = event_id;
    return candidate_payment_id;
  end if;

  select receiver.receiver_user_id into receiver_id
  from public.collection_receivers receiver
  where receiver.collection_id = target_collection_id
    and receiver.momo_number_hash = event_row.receiver_phone_hash
    and receiver.is_active
  order by receiver.created_at desc
  limit 1;
  if receiver_id is null or receiver_id <> event_row.receiver_user_id then
    raise exception 'SMS receiver is not configured for the target group';
  end if;

  insert into public.payments(
    parsed_event_id, payment_intent_id, collection_id,
    contributor_user_id, contributor_public_id, receiver_user_id,
    receiver_momo_number_hash, amount_rwf, transaction_id,
    provider_network, source, status, anonymity_choice, posted_at
  ) values (
    event_id, intent_id, target_collection_id,
    intent_row.contributor_user_id, intent_row.contributor_public_id, receiver_id,
    event_row.receiver_phone_hash, event_row.amount_rwf, event_row.transaction_id,
    event_row.network, 'sms_auto', 'review', intent_row.anonymity_choice, null
  ) returning id into candidate_payment_id;

  insert into public.payment_allocations(
    payment_id, parsed_event_id, collection_id, payment_intent_id,
    allocated_by, allocation_method, confidence, reason
  ) values (
    candidate_payment_id, event_id, target_collection_id, intent_id,
    null, 'auto_native_sms', event_row.confidence,
    allocation_reason || '; awaiting independent provider confirmation'
  );
  update public.parsed_payment_events
  set allocation_status = 'needs_review',
      review_reason = 'Matched to one payer-verified intent; awaiting independent provider confirmation'
  where id = event_id;
  update public.payment_intents set status = 'matched' where id = intent_id;
  perform collect_hybrid.record_momo_exception(
    event_id, 'provider_confirmation_pending',
    jsonb_build_object('payment_id', candidate_payment_id, 'payment_intent_id', intent_id)
  );
  perform public.create_audit_log(
    'payment.awaiting_provider_confirmation', 'payment', candidate_payment_id,
    jsonb_build_object(
      'parsed_event_id', event_id,
      'payment_intent_id', intent_id,
      'method', 'native_sms_candidate',
      'ledger_posted', false
    ),
    null
  );
  return candidate_payment_id;
end;
$$;

create or replace function public.allocate_parsed_payment_event(event_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_row public.parsed_payment_events;
  evidence_time timestamptz;
  intent_count integer := 0;
  intent_id uuid;
  intent_collection_id uuid;
  intent_receiver_hash text;
  intent_member_id uuid;
  direct_count integer := 0;
  direct_assignment_id uuid;
  direct_collection_id uuid;
  direct_member_id uuid;
  direct_enabled boolean;
  result_status text;
  existing_payment_status text;
begin
  select event.* into event_row
  from public.parsed_payment_events event
  where event.id = event_id
  for update;
  if event_row.id is null then raise exception 'Parsed event not found'; end if;
  select coalesce(raw.received_at_device, raw.ingested_at)
  into evidence_time
  from public.raw_payment_sms raw
  where raw.id = event_row.raw_sms_id;
  select payment.status into existing_payment_status
  from public.payments payment
  where payment.parsed_event_id = event_id;
  if existing_payment_status = 'posted'
     or event_row.allocation_status = 'allocated' then
    return 'already_allocated';
  elsif existing_payment_status = 'review' then
    return 'awaiting_provider_confirmation';
  elsif existing_payment_status = 'reversed'
     or event_row.allocation_status = 'ignored' then
    return 'ignored';
  end if;
  if not event_row.is_mobile_money_payment
     or event_row.direction <> 'incoming'
     or event_row.currency <> 'RWF'
     or event_row.amount_rwf is null
     or event_row.amount_rwf <= 0
     or event_row.transaction_id is null
     or event_row.confidence < 0.90
     or evidence_time is null then
    update public.parsed_payment_events
    set allocation_status = 'needs_review',
        review_reason = 'SMS evidence is incomplete or not reliable enough for candidate matching'
    where id = event_id;
    perform collect_hybrid.record_momo_exception(
      event_id, 'no_candidate', jsonb_build_object('stage', 'evidence_validation')
    );
    return 'needs_review';
  end if;

  -- Serialize every route on the same provider reference and treat the
  -- reference as consumed even after rejection or compensating reversal.
  perform pg_advisory_xact_lock(hashtextextended(
    event_row.network || ':' || upper(btrim(event_row.transaction_id)), 0
  ));
  if exists (
    select 1 from public.payments payment
    where payment.provider_network = event_row.network
      and upper(btrim(payment.transaction_id)) = upper(btrim(event_row.transaction_id))
  ) then
    update public.parsed_payment_events
    set allocation_status = 'ignored',
        review_reason = 'Provider transaction evidence was already consumed'
    where id = event_id;
    return 'ignored';
  end if;

  update public.payment_intents set status = 'expired'
  where status = 'pending' and expires_at <= now();
  if event_row.transaction_id is not null then
    with candidates as (
      select distinct
        intent.id,
        intent.collection_id,
        intent.receiver_momo_number_hash,
        intent.contributor_user_id,
        intent.contributor_public_id,
        intent.created_at
      from public.payment_intents intent
      join public.collection_receivers route
        on route.collection_id = intent.collection_id
       and route.momo_number_hash = intent.receiver_momo_number_hash
       and route.is_active
       and route.receiver_user_id = event_row.receiver_user_id
      where intent.status = 'pending'
        and (event_row.collection_id is null or intent.collection_id = event_row.collection_id)
        and (event_row.receiver_phone_hash is null
          or intent.receiver_momo_number_hash = event_row.receiver_phone_hash)
        and intent.expected_amount_rwf = event_row.amount_rwf
        and evidence_time between intent.created_at - interval '15 minutes'
          and intent.expires_at + interval '2 hours'
        and event_row.sender_phone_hash is not null
        and intent.sender_phone_hash = event_row.sender_phone_hash
        and intent.sender_phone_hash =
          public._authenticated_momo_phone_hash(intent.contributor_user_id)
        and (event_row.detected_user_public_id is null
          or intent.contributor_public_id = event_row.detected_user_public_id)
    )
    select count(*),
      (array_agg(candidate.id order by candidate.created_at))[1],
      (array_agg(candidate.collection_id order by candidate.created_at))[1],
      (array_agg(candidate.receiver_momo_number_hash order by candidate.created_at))[1],
      (array_agg(member.id order by candidate.created_at))[1]
    into intent_count, intent_id, intent_collection_id, intent_receiver_hash, intent_member_id
    from candidates candidate
    left join collect_hybrid.member_records member
      on member.linked_user_id = candidate.contributor_user_id
      or (
        candidate.contributor_user_id is null
        and candidate.contributor_public_id is not null
        and member.collect_id = candidate.contributor_public_id
      );
  end if;

  direct_enabled := coalesce((select flag.enabled from public.feature_flags flag
    where flag.key = 'hybrid_direct_ussd_allocation'), false);
  if direct_enabled and event_row.transaction_id is not null
     and event_row.receiver_phone_hash is not null
     and event_row.payer_match_key is not null then
    with candidates as (
      select distinct
        assignment.id,
        assignment.collection_id,
        assignment.member_record_id,
        assignment.created_at
      from collect_hybrid.member_receiving_assignments assignment
      join public.collection_receivers route
        on route.id = assignment.collection_receiver_id
       and route.collection_id = assignment.collection_id
       and route.is_active
       and route.receiver_user_id = event_row.receiver_user_id
       and route.momo_number_hash = event_row.receiver_phone_hash
       and route.network = event_row.network
       and assignment.route_key = encode(extensions.digest(
         route.receiver_user_id::text || '|' || route.momo_number_hash || '|' || route.network,
         'sha256'
       ), 'hex')
      join collect_hybrid.member_records member
        on member.id = assignment.member_record_id and member.lifecycle = 'active'
      join collect_hybrid.member_momo_identities identity
        on identity.member_id = member.id and identity.match_key = event_row.payer_match_key
      join public.collection_members membership
        on membership.member_record_id = member.id
       and membership.collection_id = assignment.collection_id
       and membership.status = 'active'
      where assignment.status = 'active'
        and evidence_time >= assignment.starts_at
        and (assignment.ended_at is null or evidence_time <= assignment.ended_at)
        and (event_row.collection_id is null or assignment.collection_id = event_row.collection_id)
    )
    select count(*),
      (array_agg(candidate.id order by candidate.created_at))[1],
      (array_agg(candidate.collection_id order by candidate.created_at))[1],
      (array_agg(candidate.member_record_id order by candidate.created_at))[1]
    into direct_count, direct_assignment_id, direct_collection_id, direct_member_id
    from candidates candidate;
  end if;

  if intent_count > 1 or direct_count > 1 then
    update public.parsed_payment_events
    set allocation_status = 'ambiguous',
        review_reason = 'Multiple payer-verified destinations matched this SMS evidence'
    where id = event_id;
    perform collect_hybrid.record_momo_exception(
      event_id, 'ambiguous_candidate',
      jsonb_build_object('intent_candidates', intent_count, 'direct_candidates', direct_count)
    );
    return 'ambiguous';
  end if;
  if intent_count = 1 and direct_count = 1
     and (intent_collection_id <> direct_collection_id
       or intent_member_id is distinct from direct_member_id) then
    update public.parsed_payment_events
    set allocation_status = 'ambiguous',
        review_reason = 'Payment intent and direct receiving assignment disagree'
    where id = event_id;
    perform collect_hybrid.record_momo_exception(
      event_id, 'intent_direct_disagreement',
      jsonb_build_object(
        'intent_collection_id', intent_collection_id,
        'direct_collection_id', direct_collection_id,
        'intent_member_record_id', intent_member_id,
        'direct_member_record_id', direct_member_id
      )
    );
    return 'ambiguous';
  end if;
  if direct_count = 1 and event_row.detected_user_public_id is not null
     and exists (
       select 1 from collect_hybrid.member_records member
       where member.id = direct_member_id
         and member.collect_id is distinct from event_row.detected_user_public_id
     ) then
    update public.parsed_payment_events
    set allocation_status = 'ambiguous',
        review_reason = 'SMS payer identifier conflicts with the direct receiving assignment'
    where id = event_id;
    perform collect_hybrid.record_momo_exception(
      event_id, 'payer_identity_conflict',
      jsonb_build_object(
        'direct_member_record_id', direct_member_id,
        'detected_user_public_id', event_row.detected_user_public_id
      )
    );
    return 'ambiguous';
  end if;
  if intent_count = 1 then
    if event_row.receiver_phone_hash is null then
      update public.parsed_payment_events
      set receiver_phone_hash = intent_receiver_hash,
          collection_id = coalesce(collection_id, intent_collection_id)
      where id = event_id;
    end if;
    perform public.post_payment_from_event(
      event_id, intent_id, intent_collection_id,
      case when direct_count = 1 then
        'Matched by one agreeing payment intent and direct receiving assignment'
      when event_row.receiver_phone_hash is null then
        'Matched by native SMS transaction ID plus one unique owned receiver, amount, payer, and time window'
      else
        'Matched by native SMS transaction ID, receiver, amount, payer, and time window'
      end
    );
    select event.allocation_status::text into result_status
    from public.parsed_payment_events event where event.id = event_id;
    if result_status = 'allocated' then
      update collect_hybrid.momo_reconciliation_exceptions
      set status = 'resolved', resolved_at = now()
      where parsed_event_id = event_id and status = 'open';
      return 'allocated';
    elsif result_status = 'needs_review' then
      return 'awaiting_provider_confirmation';
    end if;
    return 'ignored';
  end if;
  if direct_count = 1 then
    perform collect_hybrid.post_direct_ussd_payment(
      event_id, direct_assignment_id,
      'Matched by exact normalized MoMo name plus last three digits and one explicit active receiving assignment'
    );
    select event.allocation_status::text into result_status
    from public.parsed_payment_events event where event.id = event_id;
    if result_status = 'allocated' then
      return 'allocated';
    elsif result_status = 'needs_review' then
      return 'awaiting_provider_confirmation';
    end if;
    return 'ignored';
  end if;

  update public.parsed_payment_events
  set allocation_status = 'needs_review',
      review_reason = case when direct_enabled then
        'No payer-verified payment intent or direct receiving assignment matched this SMS evidence'
      else 'No payer-verified pending payment intent matched this SMS evidence' end
  where id = event_id;
  perform collect_hybrid.record_momo_exception(
    event_id, 'no_candidate',
    jsonb_build_object(
      'intent_candidates', intent_count,
      'direct_candidates', direct_count,
      'direct_allocation_enabled', direct_enabled
    )
  );
  return 'needs_review';
end;
$$;

commit;
