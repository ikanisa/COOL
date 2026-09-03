begin;

-- Additive parser facts. Name and suffix are private payment evidence, not
-- profile names or account-authentication credentials.
alter table public.parsed_payment_events
  add column payer_last3 text check (payer_last3 ~ '^[0-9]{3}$'),
  add column payer_match_key text check (payer_match_key ~ '^[0-9a-f]{64}$'),
  add column wallet_balance_rwf bigint check (wallet_balance_rwf >= 0);

-- Distinct original observation times must not collapse solely by body text.
-- Existing rows/evidence remain untouched. Untimed legacy evidence retains its
-- old deduplication scope; new native capture always includes device time.
drop index public.raw_payment_sms_receiver_body_unique;
create unique index raw_payment_sms_observed_source_unique
  on public.raw_payment_sms (
    receiver_user_id, coalesce(receiver_momo_number_hash, ''), raw_sender,
    body_hash, received_at_device
  ) where received_at_device is not null;
create unique index raw_payment_sms_untimed_body_unique
  on public.raw_payment_sms (receiver_user_id, body_hash)
  where received_at_device is null;

create or replace function public.ingest_raw_payment_sms(
  p_receiver_user_id uuid,
  p_collection_id uuid,
  p_raw_sender text,
  p_raw_body text,
  p_body_hash text,
  p_client_envelope_id uuid,
  p_receiver_momo_number_hash text,
  p_received_at_device timestamptz
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  existing_row public.raw_payment_sms;
  inserted_row public.raw_payment_sms;
  hourly_count integer;
  daily_count integer;
  clean_body_hash text := lower(btrim(coalesce(p_body_hash, '')));
  clean_receiver_hash text := nullif(lower(btrim(coalesce(p_receiver_momo_number_hash, ''))), '');
begin
  -- The only API grant is service_role; the Edge Function verifies the receiver.
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_receiver_user_id is null
     or nullif(btrim(p_raw_sender), '') is null
     or nullif(btrim(p_raw_body), '') is null
     or octet_length(p_raw_sender) > 96
     or octet_length(p_raw_body) > 4096
     or clean_body_hash !~ '^[0-9a-f]{64}$'
     or clean_body_hash <> encode(extensions.digest(p_raw_body, 'sha256'), 'hex')
     or (clean_receiver_hash is not null and clean_receiver_hash !~ '^[0-9a-f]{64}$') then
    raise exception 'Invalid raw SMS ingestion request';
  end if;
  if not public.user_can_ingest_receiver_sms(clean_receiver_hash, p_collection_id, p_receiver_user_id) then
    raise exception 'Receiver or SMS consent is not authorized';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('sms-ingest:' || p_receiver_user_id::text, 0));

  select raw.* into existing_row from public.raw_payment_sms raw
  where raw.receiver_user_id = p_receiver_user_id
    and raw.client_envelope_id = p_client_envelope_id;
  if existing_row.id is not null then
    if existing_row.body_hash is distinct from clean_body_hash
       or existing_row.raw_sender is distinct from p_raw_sender
       or existing_row.receiver_momo_number_hash is distinct from clean_receiver_hash
       or existing_row.collection_id is distinct from p_collection_id
       or existing_row.received_at_device is distinct from p_received_at_device then
      raise exception 'Invalid replay: SMS envelope evidence changed';
    end if;
    return jsonb_build_object('id', existing_row.id, 'parse_status', existing_row.parse_status, 'replay', true);
  end if;

  select raw.* into existing_row from public.raw_payment_sms raw
  where raw.receiver_user_id = p_receiver_user_id
    and raw.body_hash = clean_body_hash
    and raw.receiver_momo_number_hash is not distinct from clean_receiver_hash
    and raw.raw_sender = p_raw_sender
    and raw.received_at_device is not distinct from p_received_at_device
  order by raw.ingested_at limit 1;
  if existing_row.id is not null then
    if existing_row.collection_id is distinct from p_collection_id then
      raise exception 'Invalid replay: SMS collection binding changed';
    end if;
    return jsonb_build_object('id', existing_row.id, 'parse_status', existing_row.parse_status, 'replay', true);
  end if;

  select count(*) filter (where raw.ingested_at >= now() - interval '1 hour'), count(*)
  into hourly_count, daily_count from public.raw_payment_sms raw
  where raw.receiver_user_id = p_receiver_user_id and raw.ingested_at >= now() - interval '24 hours';
  if hourly_count >= 60 or daily_count >= 250 then
    raise exception 'SMS ingestion rate limit exceeded';
  end if;
  insert into public.raw_payment_sms (
    collection_id, receiver_user_id, raw_sender, raw_body, body_hash,
    client_envelope_id, receiver_momo_number_hash, received_at_device, parse_status
  ) values (
    p_collection_id, p_receiver_user_id, p_raw_sender, p_raw_body, clean_body_hash,
    p_client_envelope_id, clean_receiver_hash, p_received_at_device, 'pending'
  ) returning * into inserted_row;
  return jsonb_build_object('id', inserted_row.id, 'parse_status', inserted_row.parse_status, 'replay', false);
end;
$$;
revoke all on function public.ingest_raw_payment_sms(uuid, uuid, text, text, text, uuid, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.ingest_raw_payment_sms(uuid, uuid, text, text, text, uuid, text, timestamptz)
  to service_role;

comment on column public.parsed_payment_events.wallet_balance_rwf is
  'Receiving wallet balance from this exact receipt, not the member or group balance.';

commit;
