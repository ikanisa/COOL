-- A device-attested SMS is evidence that a message was stored. It is not an
-- independent provider confirmation and must never post a payment or ledger.
-- This replaces the historical self-finalizer without altering existing rows.
begin;

create or replace function public.finalize_attested_payment_sms(p_raw_sms_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required' using errcode = '42501';
  end if;
  if p_raw_sms_id is null or not exists (
    select 1 from public.raw_payment_sms where id = p_raw_sms_id
  ) then
    raise exception 'Receipt not found' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'status', 'awaiting_reconciliation',
    'evidence_level', 'sms_observed',
    'payment_id', null
  );
end;
$$;

revoke all on function public.finalize_attested_payment_sms(uuid)
  from public, anon, authenticated;
grant execute on function public.finalize_attested_payment_sms(uuid)
  to service_role;
comment on function public.finalize_attested_payment_sms(uuid) is
  'Records SMS-only observation; never confirms provider settlement or posts money. Independent reconciliation is required.';

commit;
