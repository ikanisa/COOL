begin;

-- Keep historical requests unchanged. Their old payload hash cannot prove the
-- RPC arguments that were accepted; a legacy replay requires reconciliation.
alter table public.provider_finality_requests
  add column input_sha256 text check (input_sha256 ~ '^[0-9a-f]{64}$');

-- A rejection is an immutable provider decision, distinct from compensating a
-- posted payment. API roles can only reach this record through the gateway.
create table collect_hybrid.payment_provider_rejections (
  payment_id uuid primary key references public.payments(id) on delete restrict,
  provider_network text not null,
  transaction_id text not null,
  receiver_momo_number_hash text not null check (receiver_momo_number_hash ~ '^[0-9a-f]{64}$'),
  amount_rwf bigint not null check (amount_rwf > 0),
  occurred_at timestamptz not null,
  evidence_sha256 text check (evidence_sha256 ~ '^[0-9a-f]{64}$'),
  reason text not null check (char_length(reason) between 3 and 500),
  provider_reference text not null check (char_length(provider_reference) between 1 and 128),
  recorded_at timestamptz not null default now()
);
alter table collect_hybrid.payment_provider_rejections enable row level security;
revoke all on collect_hybrid.payment_provider_rejections from public, anon, authenticated, service_role;

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
set search_path = ''
as $$
declare
  payment_row public.payments;
  clean_network text := lower(btrim(coalesce(p_provider_network, '')));
  clean_transaction_id text := upper(btrim(coalesce(p_transaction_id, '')));
  clean_confirmation_id text := upper(btrim(coalesce(p_provider_confirmation_id, '')));
  clean_receiver_hash text := lower(btrim(coalesce(p_receiver_momo_number_hash, '')));
  clean_evidence_hash text := lower(btrim(coalesce(p_evidence_sha256, '')));
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Service role required'; end if;
  if p_payment_id is null
     or char_length(clean_network) not between 2 and 32
     or char_length(clean_transaction_id) not between 3 and 128
     or char_length(clean_confirmation_id) not between 3 and 128
     or clean_receiver_hash !~ '^[0-9a-f]{64}$'
     or p_amount_rwf is null or p_amount_rwf <= 0
     or p_confirmed_at is null or not isfinite(p_confirmed_at) or p_confirmed_at > now() + interval '5 minutes'
     or (clean_evidence_hash <> '' and clean_evidence_hash !~ '^[0-9a-f]{64}$') then
    raise exception 'Invalid provider confirmation';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('provider-finality-payment:' || p_payment_id::text, 0));

  select payment.* into payment_row
  from public.payments payment
  where payment.id = p_payment_id
  for update;
  if payment_row.id is null then raise exception 'Payment not found'; end if;
  if payment_row.status = 'posted' then
    if exists (
      select 1 from public.payment_provider_confirmations confirmation
      where confirmation.payment_id = payment_row.id
        and confirmation.provider_network = clean_network
        and upper(btrim(confirmation.provider_confirmation_id)) = clean_confirmation_id
        and upper(btrim(confirmation.transaction_id)) = clean_transaction_id
        and confirmation.receiver_momo_number_hash = clean_receiver_hash
        and confirmation.amount_rwf = p_amount_rwf
        and confirmation.confirmed_at = p_confirmed_at
        and confirmation.evidence_sha256 is not distinct from nullif(clean_evidence_hash, '')
    ) then return payment_row.id; end if;
    raise exception 'Payment was already finalized by a different confirmation';
  end if;
  if payment_row.status <> 'review' then
    raise exception 'Payment is not awaiting provider confirmation';
  end if;
  if lower(btrim(payment_row.provider_network)) is distinct from clean_network
     or upper(btrim(payment_row.transaction_id)) is distinct from clean_transaction_id
     or payment_row.receiver_momo_number_hash is distinct from clean_receiver_hash
     or payment_row.amount_rwf is distinct from p_amount_rwf then
    raise exception 'Provider confirmation does not match the payment candidate';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(clean_network || ':' || clean_transaction_id, 0));
  insert into public.payment_provider_confirmations(
    payment_id, provider_network, provider_confirmation_id, transaction_id,
    receiver_momo_number_hash, amount_rwf, confirmed_at, evidence_sha256
  ) values (
    payment_row.id, clean_network, clean_confirmation_id, clean_transaction_id,
    clean_receiver_hash, p_amount_rwf, p_confirmed_at, nullif(clean_evidence_hash, '')
  );
  insert into public.ledger_entries(
    payment_id, collection_id, user_id, member_record_id,
    entry_type, amount_rwf, visibility, metadata
  ) values
    (
      payment_row.id, payment_row.collection_id, payment_row.contributor_user_id,
      payment_row.member_record_id, 'collection_credit', payment_row.amount_rwf,
      'public_safe', jsonb_build_object(
        'allocation_method', 'provider_confirmed',
        'provider_confirmation_id', clean_confirmation_id
      )
    ),
    (
      payment_row.id, payment_row.collection_id, payment_row.contributor_user_id,
      payment_row.member_record_id, 'member_credit', payment_row.amount_rwf,
      'private', jsonb_build_object(
        'allocation_method', 'provider_confirmed',
        'provider_confirmation_id', clean_confirmation_id
      )
    );
  update public.payments
  set status = 'posted', posted_at = p_confirmed_at
  where id = payment_row.id;
  update public.parsed_payment_events
  set allocation_status = 'allocated',
      review_reason = 'Posted after independent provider confirmation'
  where id = payment_row.parsed_event_id;
  perform public.create_audit_log(
    'payment.provider_confirmed', 'payment', payment_row.id,
    jsonb_build_object(
      'provider_network', clean_network,
      'provider_confirmation_id', clean_confirmation_id,
      'confirmed_at', p_confirmed_at,
      'ledger_posted', true
    ),
    null
  );
  return payment_row.id;
end;
$$;

-- The old three-field entrypoint cannot bind an independent rejection to its
-- provider identity. Keep the signature for dependency discovery, fail closed.
create or replace function public.reject_provider_payment(
  p_payment_id uuid, p_reason text, p_provider_reference text default null
)
returns uuid language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'Use provider finality gateway with complete rejection identity' using errcode = '42501';
end;
$$;
revoke all on function public.reject_provider_payment(uuid,text,text)
  from public, anon, authenticated, service_role;

create function collect_hybrid.reject_bound_provider_payment(
  p_payment_id uuid, p_provider_network text, p_transaction_id text,
  p_receiver_momo_number_hash text, p_amount_rwf bigint,
  p_occurred_at timestamptz, p_evidence_sha256 text,
  p_reason text, p_provider_reference text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  payment_row public.payments;
  prior collect_hybrid.payment_provider_rejections;
  clean_network text := lower(btrim(coalesce(p_provider_network, '')));
  clean_transaction text := upper(btrim(coalesce(p_transaction_id, '')));
  clean_receiver text := lower(btrim(coalesce(p_receiver_momo_number_hash, '')));
  clean_evidence text := nullif(lower(btrim(coalesce(p_evidence_sha256, ''))), '');
  clean_reason text := btrim(coalesce(p_reason, ''));
  clean_reference text := btrim(coalesce(p_provider_reference, ''));
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Service role required'; end if;
  if p_payment_id is null or char_length(clean_network) not between 2 and 32
     or clean_network !~ '^[a-z0-9_]+$'
     or char_length(clean_transaction) not between 3 and 128
     or clean_receiver !~ '^[0-9a-f]{64}$'
     or p_amount_rwf is null or p_amount_rwf <= 0
     or p_occurred_at is null or not isfinite(p_occurred_at)
     or p_occurred_at > now() + interval '5 minutes'
     or (clean_evidence is not null and clean_evidence !~ '^[0-9a-f]{64}$')
     or char_length(clean_reason) not between 3 and 500
     or char_length(clean_reference) not between 1 and 128 then
    raise exception 'Invalid provider rejection';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('provider-finality-payment:' || p_payment_id::text, 0));
  select payment.* into payment_row from public.payments payment
    where payment.id = p_payment_id for update;
  if payment_row.id is null then raise exception 'Payment not found'; end if;
  if lower(btrim(payment_row.provider_network)) is distinct from clean_network
     or upper(btrim(payment_row.transaction_id)) is distinct from clean_transaction
     or payment_row.receiver_momo_number_hash is distinct from clean_receiver
     or payment_row.amount_rwf is distinct from p_amount_rwf then
    raise exception 'Provider rejection does not match the payment candidate';
  end if;
  if payment_row.status = 'reversed' then
    select rejection.* into prior from collect_hybrid.payment_provider_rejections rejection
      where rejection.payment_id = payment_row.id;
    if prior.payment_id is not null
       and prior.provider_network = clean_network
       and prior.transaction_id = clean_transaction
       and prior.receiver_momo_number_hash = clean_receiver
       and prior.amount_rwf = p_amount_rwf
       and prior.occurred_at = p_occurred_at
       and prior.evidence_sha256 is not distinct from clean_evidence
       and prior.reason = clean_reason and prior.provider_reference = clean_reference then
      return payment_row.id;
    end if;
    raise exception 'Payment was reversed without this provider rejection';
  end if;
  if payment_row.status <> 'review' then raise exception 'Only a review payment can be rejected'; end if;
  if exists(select 1 from public.payment_provider_confirmations where payment_id = payment_row.id)
     or exists(select 1 from public.ledger_entries where payment_id = payment_row.id) then
    raise exception 'Provider rejection cannot compensate posted financial evidence';
  end if;
  insert into collect_hybrid.payment_provider_rejections(
    payment_id, provider_network, transaction_id, receiver_momo_number_hash,
    amount_rwf, occurred_at, evidence_sha256, reason, provider_reference
  ) values (payment_row.id, clean_network, clean_transaction, clean_receiver,
    p_amount_rwf, p_occurred_at, clean_evidence, clean_reason, clean_reference);
  update public.payments set status = 'reversed', posted_at = null where id = payment_row.id;
  update public.parsed_payment_events set allocation_status = 'needs_review',
    review_reason = 'Provider rejected payment candidate: ' || clean_reason
    where id = payment_row.parsed_event_id;
  update public.payment_intents set status = 'cancelled' where id = payment_row.payment_intent_id;
  update collect_hybrid.momo_reconciliation_exceptions set status = 'resolved', resolved_at = now()
    where parsed_event_id = payment_row.parsed_event_id and status = 'open';
  perform public.create_audit_log('payment.provider_rejected', 'payment', payment_row.id,
    jsonb_build_object('reason', clean_reason, 'provider_reference', clean_reference,
      'provider_network', clean_network, 'transaction_id', clean_transaction,
      'occurred_at', p_occurred_at, 'evidence_sha256', clean_evidence, 'ledger_posted', false), null);
  return payment_row.id;
end;
$$;
revoke all on function collect_hybrid.reject_bound_provider_payment(uuid,text,text,text,bigint,timestamptz,text,text,text)
  from public, anon, authenticated, service_role;

create or replace function public.process_provider_finality_event(
  p_request_id uuid,
  p_event_type text,
  p_payload_sha256 text,
  p_payment_id uuid,
  p_provider_network text default null,
  p_transaction_id text default null,
  p_provider_confirmation_id text default null,
  p_receiver_momo_number_hash text default null,
  p_amount_rwf bigint default null,
  p_occurred_at timestamptz default null,
  p_evidence_sha256 text default null,
  p_rejection_reason text default null,
  p_provider_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_event_type text := btrim(coalesce(p_event_type, ''));
  clean_payload_sha256 text := lower(btrim(coalesce(p_payload_sha256, '')));
  existing_request public.provider_finality_requests;
  inserted_request_id uuid;
  finalized_payment_id uuid;
  stored_reference text;
  bound_input_sha256 text;
  clean_network text := nullif(lower(btrim(coalesce(p_provider_network, ''))), '');
  clean_transaction text := nullif(upper(btrim(coalesce(p_transaction_id, ''))), '');
  clean_confirmation text := nullif(upper(btrim(coalesce(p_provider_confirmation_id, ''))), '');
  clean_receiver text := nullif(lower(btrim(coalesce(p_receiver_momo_number_hash, ''))), '');
  clean_evidence text := nullif(lower(btrim(coalesce(p_evidence_sha256, ''))), '');
  clean_reason text := nullif(btrim(coalesce(p_rejection_reason, '')), '');
  clean_reference text := nullif(btrim(coalesce(p_provider_reference, '')), '');
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Service role required'; end if;
  if p_request_id is null or p_payment_id is null
     or clean_event_type not in ('payment.confirmed', 'payment.rejected')
     or clean_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider finality request';
  end if;
  stored_reference := case
    when clean_event_type = 'payment.confirmed'
      then clean_confirmation
    else clean_reference
  end;

  -- Epoch binds the instant independently of the caller's session TimeZone.
  bound_input_sha256 := encode(extensions.digest(jsonb_build_object(
    'contract', 1, 'event_type', clean_event_type, 'payment_id', p_payment_id,
    'network', clean_network, 'transaction_id', clean_transaction,
    'confirmation_id', clean_confirmation, 'receiver_hash', clean_receiver,
    'amount_rwf', p_amount_rwf, 'occurred_at_epoch', extract(epoch from p_occurred_at),
    'evidence_sha256', clean_evidence, 'rejection_reason', clean_reason,
    'provider_reference', clean_reference
  )::text, 'sha256'), 'hex');

  perform pg_advisory_xact_lock(
    hashtextextended('provider-finality-payment:' || p_payment_id::text, 0)
  );

  insert into public.provider_finality_requests(
    request_id, event_type, payload_sha256, payment_id, provider_network, provider_reference, input_sha256
  ) values (
    p_request_id, clean_event_type, clean_payload_sha256, p_payment_id,
    clean_network, stored_reference, bound_input_sha256
  )
  on conflict (request_id) do nothing
  returning request_id into inserted_request_id;
  if inserted_request_id is null then
    select request.* into existing_request
    from public.provider_finality_requests request
    where request.request_id = p_request_id
    for update;
    if existing_request.input_sha256 is null then
      raise exception 'Legacy provider finality request requires reconciliation';
    end if;
    if existing_request.event_type <> clean_event_type
       or existing_request.payload_sha256 <> clean_payload_sha256
       or existing_request.payment_id <> p_payment_id
       or existing_request.input_sha256 is distinct from bound_input_sha256 then
      raise exception 'Provider finality request id was reused with different content';
    end if;
    if existing_request.status <> 'processed' or existing_request.result_payment_id is null then
      raise exception 'Provider finality request is not complete';
    end if;
    return jsonb_build_object('payment_id', existing_request.result_payment_id, 'replayed', true);
  end if;
  if clean_event_type = 'payment.confirmed' then
    finalized_payment_id := public.confirm_provider_payment(
      p_payment_id, p_provider_network, p_transaction_id,
      p_provider_confirmation_id, p_receiver_momo_number_hash,
      p_amount_rwf, p_occurred_at, p_evidence_sha256
    );
  else
    finalized_payment_id := collect_hybrid.reject_bound_provider_payment(
      p_payment_id, p_provider_network, p_transaction_id, p_receiver_momo_number_hash,
      p_amount_rwf, p_occurred_at, p_evidence_sha256, p_rejection_reason, p_provider_reference
    );
  end if;
  update public.provider_finality_requests
  set status = 'processed', result_payment_id = finalized_payment_id, processed_at = now()
  where request_id = p_request_id;
  return jsonb_build_object('payment_id', finalized_payment_id, 'replayed', false);
end;
$$;

-- CREATE OR REPLACE preserves existing EXECUTE ACLs. Do not regrant service
-- access if an approved reconciliation rollout has already revoked it.
revoke all on function public.confirm_provider_payment(uuid,text,text,text,text,bigint,timestamptz,text),
  public.process_provider_finality_event(uuid,text,text,uuid,text,text,text,text,bigint,timestamptz,text,text,text)
  from public, anon, authenticated;
comment on column public.provider_finality_requests.input_sha256 is
  'Server-computed normalized RPC-input digest. NULL marks legacy requests whose full input identity is unverified; replay requires reconciliation.';
comment on function public.process_provider_finality_event(uuid,text,text,uuid,text,text,text,text,bigint,timestamptz,text,text,text) is
  'Provider finality gateway with payment lock ordering, exact normalized request binding and immutable confirmation/rejection identity.';
commit;
