create or replace function public.admin_acknowledge_momo_sms_sender_inventory(
  p_sender_token text,
  p_note text default null
)
returns table (
  sender_token text,
  resolution_status text
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_sender_token text;
  v_sender_display text;
  v_note text;
  v_now timestamptz := now();
  v_approved_sender_tokens constant text[] := array[
    'mmoney',
    'mmoneyalerts',
    'mobilemoney',
    'momo',
    'momoalerts',
    'mtnmomo',
    'mtnmomorwanda'
  ];
begin
  if not public.is_admin() then
    raise exception 'Admin privileges required';
  end if;

  v_sender_token := regexp_replace(
    lower(coalesce(p_sender_token, '')),
    '[^a-z0-9]+',
    '',
    'g'
  );

  if v_sender_token = '' then
    raise exception 'Sender token is required.';
  end if;

  if v_sender_token = any(v_approved_sender_tokens) then
    raise exception 'Approved sender tokens cannot be acknowledged as legacy unsupported senders.';
  end if;

  select btrim(raw.sender)
  into v_sender_display
  from public.momo_sms_raw raw
  where regexp_replace(
    lower(coalesce(raw.sender, '')),
    '[^a-z0-9]+',
    '',
    'g'
  ) = v_sender_token
  order by raw.sms_received_at desc, raw.created_at desc, raw.id desc
  limit 1;

  if not found then
    raise exception 'Unsupported sender backlog was not found.';
  end if;

  v_note := coalesce(
    nullif(btrim(p_note), ''),
    'Admin acknowledged this unsupported sender as legacy raw SMS history. The sender remains unapproved and stays excluded from active intake policies.'
  );

  insert into public.momo_sms_sender_inventory_resolutions as resolution (
    sender_token,
    sender_display,
    resolution_status,
    resolution_note,
    resolved_by,
    resolved_at,
    created_at,
    updated_at
  )
  values (
    v_sender_token,
    v_sender_display,
    'acknowledged_legacy',
    v_note,
    auth.uid(),
    v_now,
    v_now,
    v_now
  )
  on conflict on constraint momo_sms_sender_inventory_resolutions_pkey do update
  set
    sender_display = excluded.sender_display,
    resolution_status = excluded.resolution_status,
    resolution_note = excluded.resolution_note,
    resolved_by = excluded.resolved_by,
    resolved_at = excluded.resolved_at,
    updated_at = excluded.updated_at;

  return query
  select v_sender_token, 'acknowledged_legacy'::text;
end;
$$;

comment on function public.admin_acknowledge_momo_sms_sender_inventory(text, text) is
  'Admin-only operation that marks an unsupported M-Money SMS sender as acknowledged legacy history without altering the raw SMS records.';

revoke all on function public.admin_acknowledge_momo_sms_sender_inventory(text, text) from public;
grant execute on function public.admin_acknowledge_momo_sms_sender_inventory(text, text)
  to authenticated, service_role;
