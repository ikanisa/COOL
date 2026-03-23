create or replace function public.admin_acknowledge_momo_sms_sender_inventory_batch(
  p_sender_tokens text[],
  p_note text default null
)
returns table (
  acknowledged_count integer
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
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

  if coalesce(array_length(p_sender_tokens, 1), 0) = 0 then
    return query
    select 0::integer;
    return;
  end if;

  v_note := coalesce(
    nullif(btrim(p_note), ''),
    'Admin acknowledged this unsupported sender as legacy raw SMS history. The sender remains unapproved and stays excluded from active intake policies.'
  );

  return query
  with normalized_tokens as (
    select distinct regexp_replace(
      lower(coalesce(raw_token, '')),
      '[^a-z0-9]+',
      '',
      'g'
    ) as sender_token
    from unnest(p_sender_tokens) as raw_token
  ),
  eligible_tokens as (
    select nt.sender_token
    from normalized_tokens nt
    where nt.sender_token <> ''
      and not (nt.sender_token = any(v_approved_sender_tokens))
  ),
  source_rows as (
    select
      et.sender_token,
      (
        select btrim(raw.sender)
        from public.momo_sms_raw raw
        where regexp_replace(
          lower(coalesce(raw.sender, '')),
          '[^a-z0-9]+',
          '',
          'g'
        ) = et.sender_token
        order by raw.sms_received_at desc, raw.created_at desc, raw.id desc
        limit 1
      ) as sender_display
    from eligible_tokens et
  ),
  resolved_rows as (
    select
      sr.sender_token,
      sr.sender_display
    from source_rows sr
    where sr.sender_display is not null
  ),
  upserted as (
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
    select
      rr.sender_token,
      rr.sender_display,
      'acknowledged_legacy',
      v_note,
      auth.uid(),
      v_now,
      v_now,
      v_now
    from resolved_rows rr
    on conflict on constraint momo_sms_sender_inventory_resolutions_pkey do update
    set
      sender_display = excluded.sender_display,
      resolution_status = excluded.resolution_status,
      resolution_note = excluded.resolution_note,
      resolved_by = excluded.resolved_by,
      resolved_at = excluded.resolved_at,
      updated_at = excluded.updated_at
    returning resolution.sender_token
  )
  select count(*)::integer
  from upserted;
end;
$$;

comment on function public.admin_acknowledge_momo_sms_sender_inventory_batch(text[], text) is
  'Admin-only batch operation that marks unsupported M-Money SMS senders as acknowledged legacy history without altering raw SMS records.';

revoke all on function public.admin_acknowledge_momo_sms_sender_inventory_batch(text[], text) from public;
grant execute on function public.admin_acknowledge_momo_sms_sender_inventory_batch(text[], text)
  to authenticated, service_role;
