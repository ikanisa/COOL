begin;

-- A finality request references its payment. Inserting two distinct requests
-- first gives both transactions a foreign-key KEY SHARE lock on that payment.
-- Their later FOR UPDATE calls can then deadlock. Serialize by payment before
-- either request row takes its foreign-key lock.
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
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'Service role required'; end if;
  if p_request_id is null or p_payment_id is null
     or clean_event_type not in ('payment.confirmed', 'payment.rejected')
     or clean_payload_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid provider finality request';
  end if;
  stored_reference := case
    when clean_event_type = 'payment.confirmed'
      then nullif(btrim(coalesce(p_provider_confirmation_id, '')), '')
    else nullif(btrim(coalesce(p_provider_reference, '')), '')
  end;

  perform pg_advisory_xact_lock(
    hashtextextended('provider-finality-payment:' || p_payment_id::text, 0)
  );

  insert into public.provider_finality_requests(
    request_id, event_type, payload_sha256, payment_id, provider_network, provider_reference
  ) values (
    p_request_id, clean_event_type, clean_payload_sha256, p_payment_id,
    nullif(lower(btrim(coalesce(p_provider_network, ''))), ''), stored_reference
  )
  on conflict (request_id) do nothing
  returning request_id into inserted_request_id;
  if inserted_request_id is null then
    select request.* into existing_request
    from public.provider_finality_requests request
    where request.request_id = p_request_id
    for update;
    if existing_request.event_type <> clean_event_type
       or existing_request.payload_sha256 <> clean_payload_sha256
       or existing_request.payment_id <> p_payment_id then
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
    finalized_payment_id := public.reject_provider_payment(
      p_payment_id, p_rejection_reason, p_provider_reference
    );
  end if;
  update public.provider_finality_requests
  set status = 'processed', result_payment_id = finalized_payment_id, processed_at = now()
  where request_id = p_request_id;
  return jsonb_build_object('payment_id', finalized_payment_id, 'replayed', false);
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

comment on function public.process_provider_finality_event(
  uuid, text, text, uuid, text, text, text, text, bigint, timestamptz, text,
  text, text
) is 'Replay-safe service-only provider finality gateway; acquires the payment advisory lock before the request foreign-key lock.';

commit;
