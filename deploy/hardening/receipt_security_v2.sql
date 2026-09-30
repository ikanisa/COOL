-- Staged SQL only. Generate a numbered migration with the pinned CLI and rehearse
-- against the complete schema before deployment. This file has NOT been applied.
begin;
create schema if not exists collect_security;
revoke all on schema collect_security from public,anon,authenticated;

create or replace function public.accept_attested_receipt_v2(
  p_native_capability_id uuid,p_receiver_user_id uuid,p_collection_id uuid,
  p_raw_sender text,p_raw_body text,p_body_hash text,p_client_envelope_id uuid,
  p_receiver_momo_number_hash text,p_received_at_device text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.raw_payment_sms; accepted jsonb; result_id uuid;
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  if p_native_capability_id is null or p_receiver_user_id is null or p_client_envelope_id is null
     or p_raw_body is null or length(btrim(p_raw_body))=0 or octet_length(p_raw_body)>4096
     or p_raw_sender is null or length(btrim(p_raw_sender))=0 or octet_length(p_raw_sender)>96
     or p_body_hash is null or p_body_hash !~ '^[a-f0-9]{64}$'
     or p_receiver_momo_number_hash is null or p_receiver_momo_number_hash !~ '^[a-f0-9]{64}$'
     or encode(extensions.digest(p_raw_body,'sha256'),'hex')<>p_body_hash then
    raise exception 'Invalid receipt binding' using errcode='22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_receiver_user_id::text||':'||p_client_envelope_id::text,0));
  select * into r from public.raw_payment_sms
    where receiver_user_id=p_receiver_user_id and client_envelope_id=p_client_envelope_id for update;
  if r.id is null then
    accepted:=public.ingest_attested_raw_payment_sms(p_native_capability_id,p_receiver_user_id,p_collection_id,
      p_raw_sender,p_raw_body,p_body_hash,p_client_envelope_id,p_receiver_momo_number_hash,p_received_at_device);
    result_id:=(accepted->>'id')::uuid;
    select * into r from public.raw_payment_sms where id=result_id for update;
  end if;
  -- A committed, exactly bound receipt may be acknowledged again after a timeout.
  -- A new capability is not needed to prove a second settlement: none is posted here.
  if r.id is null or r.receiver_user_id is distinct from p_receiver_user_id
     or r.client_envelope_id is distinct from p_client_envelope_id
     or r.body_hash is distinct from p_body_hash or r.raw_body is distinct from p_raw_body
     or btrim(r.raw_sender) is distinct from btrim(p_raw_sender)
     or r.receiver_momo_number_hash is distinct from p_receiver_momo_number_hash
     or r.received_at_device is distinct from nullif(btrim(p_received_at_device),'')::timestamptz
     or r.native_action_capability_id is null or r.attestation_request_hash is null or r.device_attested_at is null then
    raise exception 'Receipt binding conflict' using errcode='22023';
  end if;
  -- collection_id can be assigned later by allocation; it is not an ACK identity.
  return jsonb_build_object('contract_version',2,'stored',true,'raw_sms_id',r.id,
    'client_envelope_id',r.client_envelope_id,'owner_user_id',r.receiver_user_id,'body_sha256',r.body_hash);
end; $$;
revoke all on function public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text) from public,anon,authenticated;
grant execute on function public.accept_attested_receipt_v2(uuid,uuid,uuid,text,text,text,uuid,text,text) to service_role;

-- Conservative containment: previous parser deployments also stop self-confirming
-- SMS receipts. Existing posted journals are left unchanged for reconciliation.
create or replace function public.finalize_attested_payment_sms(p_raw_sms_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if coalesce(auth.role(),'')<>'service_role' then raise exception 'Service role required' using errcode='42501'; end if;
  if not exists(select 1 from public.raw_payment_sms where id=p_raw_sms_id) then raise exception 'Receipt not found'; end if;
  return jsonb_build_object('status','awaiting_reconciliation','evidence_level','sms_observed','payment_id',null);
end; $$;
revoke all on function public.finalize_attested_payment_sms(uuid) from public,anon,authenticated;
grant execute on function public.finalize_attested_payment_sms(uuid) to service_role;

create or replace function public.attested_sms_contract_version()
returns integer language sql stable security invoker set search_path='' as $$ select 2 $$;
revoke all on function public.attested_sms_contract_version() from public,anon,authenticated;
grant execute on function public.attested_sms_contract_version() to service_role;
commit;
