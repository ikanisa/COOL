begin;

alter table public.raw_payment_sms
  add column if not exists parse_started_at timestamptz,
  add column if not exists parse_lease_id uuid;

alter table public.raw_payment_sms
  drop constraint if exists raw_payment_sms_parse_status_check;
alter table public.raw_payment_sms
  add constraint raw_payment_sms_parse_status_check
  check (parse_status in ('pending', 'processing', 'parsed', 'failed', 'ignored'));

create index if not exists raw_payment_sms_processing_lease_idx
  on public.raw_payment_sms (parse_started_at)
  where parse_status = 'processing';

create or replace function public.claim_raw_payment_sms_for_parse(
  p_raw_sms_id uuid,
  p_lease_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed_row public.raw_payment_sms;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_raw_sms_id is null or p_lease_id is null then
    raise exception 'Raw SMS and lease identifiers are required';
  end if;

  update public.raw_payment_sms raw
  set parse_status = 'processing',
      parse_started_at = now(),
      parse_lease_id = p_lease_id
  where raw.id = p_raw_sms_id
    and not exists (
      select 1
      from public.parsed_payment_events event
      where event.raw_sms_id = raw.id
    )
    and (
      raw.parse_status in ('pending', 'failed')
      or (
        raw.parse_status = 'processing'
        and raw.parse_started_at < now() - interval '60 seconds'
      )
    )
  returning raw.* into claimed_row;

  if claimed_row.id is null then
    return null;
  end if;
  return to_jsonb(claimed_row);
end;
$$;

revoke all on function public.claim_raw_payment_sms_for_parse(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.claim_raw_payment_sms_for_parse(uuid, uuid)
  to service_role;

commit;
