begin;

-- Every authenticated gateway delivery is registered in the same transaction
-- as payment finalization. A failed finalization rolls back the reservation;
-- an identical retry returns the original result; a request-id collision with
-- different bytes is rejected.
create table if not exists public.provider_finality_requests (
  request_id uuid primary key,
  event_type text not null
    check (event_type in ('payment.confirmed', 'payment.rejected')),
  payload_sha256 text not null
    check (payload_sha256 ~ '^[0-9a-f]{64}$'),
  payment_id uuid not null references public.payments(id) on delete restrict,
  provider_network text
    check (
      provider_network is null
      or (
        char_length(provider_network) between 2 and 32
        and provider_network ~ '^[a-z0-9_]+$'
      )
    ),
  provider_reference text
    check (
      provider_reference is null
      or char_length(provider_reference) between 1 and 128
    ),
  status text not null default 'processing'
    check (status in ('processing', 'processed')),
  result_payment_id uuid references public.payments(id) on delete restrict,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  check (result_payment_id is null or result_payment_id = payment_id),
  check (
    (status = 'processing' and result_payment_id is null and processed_at is null)
    or
    (status = 'processed' and result_payment_id is not null and processed_at is not null)
  )
);

alter table public.provider_finality_requests enable row level security;
revoke all on public.provider_finality_requests
  from public, anon, authenticated;

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
set search_path = public
as $$
declare
  clean_event_type text := trim(coalesce(p_event_type, ''));
  clean_payload_sha256 text := lower(trim(coalesce(p_payload_sha256, '')));
  existing_request public.provider_finality_requests;
  inserted_request_id uuid;
  finalized_payment_id uuid;
  stored_reference text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_request_id is null
     or p_payment_id is null
     or clean_event_type not in ('payment.confirmed', 'payment.rejected')
     or clean_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider finality request';
  end if;

  stored_reference := case
    when clean_event_type = 'payment.confirmed'
      then nullif(trim(coalesce(p_provider_confirmation_id, '')), '')
    else nullif(trim(coalesce(p_provider_reference, '')), '')
  end;

  insert into public.provider_finality_requests (
    request_id,
    event_type,
    payload_sha256,
    payment_id,
    provider_network,
    provider_reference
  ) values (
    p_request_id,
    clean_event_type,
    clean_payload_sha256,
    p_payment_id,
    nullif(lower(trim(coalesce(p_provider_network, ''))), ''),
    stored_reference
  )
  on conflict (request_id) do nothing
  returning request_id into inserted_request_id;

  if inserted_request_id is null then
    select *
    into existing_request
    from public.provider_finality_requests request
    where request.request_id = p_request_id
    for update;

    if existing_request.event_type <> clean_event_type
       or existing_request.payload_sha256 <> clean_payload_sha256
       or existing_request.payment_id <> p_payment_id then
      raise exception 'Provider finality request id was reused with different content';
    end if;
    if existing_request.status <> 'processed'
       or existing_request.result_payment_id is null then
      raise exception 'Provider finality request is not complete';
    end if;
    return jsonb_build_object(
      'payment_id', existing_request.result_payment_id,
      'replayed', true
    );
  end if;

  if clean_event_type = 'payment.confirmed' then
    finalized_payment_id := public.confirm_provider_payment(
      p_payment_id,
      p_provider_network,
      p_transaction_id,
      p_provider_confirmation_id,
      p_receiver_momo_number_hash,
      p_amount_rwf,
      p_occurred_at,
      p_evidence_sha256
    );
  else
    finalized_payment_id := public.reject_provider_payment(
      p_payment_id,
      p_rejection_reason,
      p_provider_reference
    );
  end if;

  update public.provider_finality_requests
  set status = 'processed',
      result_payment_id = finalized_payment_id,
      processed_at = now()
  where request_id = p_request_id;

  return jsonb_build_object(
    'payment_id', finalized_payment_id,
    'replayed', false
  );
end;
$$;

revoke all on function public.process_provider_finality_event(
  uuid, text, text, uuid, text, text, text, text, bigint, timestamptz, text,
  text, text
) from public, anon, authenticated;
grant execute on function public.process_provider_finality_event(
  uuid, text, text, uuid, text, text, text, text, bigint, timestamptz, text,
  text, text
) to service_role;

comment on table public.provider_finality_requests is
  'Replay-safe audit register for authenticated provider finality gateway deliveries.';

commit;
