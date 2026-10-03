begin;

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
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_row public.raw_payment_sms;
  inserted_row public.raw_payment_sms;
  hourly_count integer;
  daily_count integer;
  clean_body_hash text := lower(trim(coalesce(p_body_hash, '')));
  clean_receiver_hash text := nullif(
    lower(trim(coalesce(p_receiver_momo_number_hash, ''))),
    ''
  );
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_receiver_user_id is null
     or nullif(trim(coalesce(p_raw_sender, '')), '') is null
     or nullif(trim(coalesce(p_raw_body, '')), '') is null
     or octet_length(trim(p_raw_sender)) > 96
     or octet_length(trim(p_raw_body)) > 4096
     or clean_body_hash !~ '^[0-9a-f]{64}$'
     or (clean_receiver_hash is not null and clean_receiver_hash !~ '^[0-9a-f]{64}$') then
    raise exception 'Invalid raw SMS ingestion request';
  end if;
  if not public.user_can_ingest_receiver_sms(
    clean_receiver_hash,
    p_collection_id,
    p_receiver_user_id
  ) then
    raise exception 'Receiver or SMS consent is not authorized';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('sms-ingest:' || p_receiver_user_id::text, 0)
  );

  select raw.*
  into existing_row
  from public.raw_payment_sms raw
  where raw.receiver_user_id = p_receiver_user_id
    and (
      (
        p_client_envelope_id is not null
        and raw.client_envelope_id = p_client_envelope_id
      )
      or (
        p_client_envelope_id is null
        and raw.body_hash = clean_body_hash
      )
    )
  order by raw.ingested_at
  limit 1;
  if existing_row.id is not null then
    return jsonb_build_object(
      'id', existing_row.id,
      'parse_status', existing_row.parse_status,
      'replay', true
    );
  end if;

  select
    count(*) filter (where raw.ingested_at >= now() - interval '1 hour'),
    count(*) filter (where raw.ingested_at >= now() - interval '24 hours')
  into hourly_count, daily_count
  from public.raw_payment_sms raw
  where raw.receiver_user_id = p_receiver_user_id
    and raw.ingested_at >= now() - interval '24 hours';
  if hourly_count >= 60 or daily_count >= 250 then
    raise exception 'SMS ingestion rate limit exceeded';
  end if;

  insert into public.raw_payment_sms (
    collection_id,
    receiver_user_id,
    raw_sender,
    raw_body,
    body_hash,
    client_envelope_id,
    receiver_momo_number_hash,
    received_at_device,
    parse_status
  ) values (
    p_collection_id,
    p_receiver_user_id,
    trim(p_raw_sender),
    trim(p_raw_body),
    clean_body_hash,
    p_client_envelope_id,
    clean_receiver_hash,
    p_received_at_device,
    'pending'
  )
  returning * into inserted_row;

  return jsonb_build_object(
    'id', inserted_row.id,
    'parse_status', inserted_row.parse_status,
    'replay', false
  );
end;
$$;

revoke all on function public.ingest_raw_payment_sms(
  uuid, uuid, text, text, text, uuid, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.ingest_raw_payment_sms(
  uuid, uuid, text, text, text, uuid, text, timestamptz
) to service_role;

-- The non-atomic pre-check remains unavailable to clients and is no longer used
-- by the Edge path. Keep it for operational diagnostics only.
revoke execute on function public.check_sms_ingest_rate_limit(uuid)
  from service_role;

commit;
