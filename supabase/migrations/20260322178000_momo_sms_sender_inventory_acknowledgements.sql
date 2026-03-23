create table if not exists public.momo_sms_sender_inventory_resolutions (
  sender_token text primary key,
  sender_display text,
  resolution_status text not null default 'acknowledged_legacy',
  resolution_note text not null,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint momo_sms_sender_inventory_resolutions_status_check
    check (resolution_status in ('acknowledged_legacy'))
);

create index if not exists idx_momo_sms_sender_inventory_resolutions_resolved_at
  on public.momo_sms_sender_inventory_resolutions (resolved_at desc);

alter table public.momo_sms_sender_inventory_resolutions enable row level security;

drop policy if exists momo_sms_sender_inventory_resolutions_select_admin
  on public.momo_sms_sender_inventory_resolutions;
create policy momo_sms_sender_inventory_resolutions_select_admin
  on public.momo_sms_sender_inventory_resolutions for select
  using (public.is_admin());

drop trigger if exists trg_momo_sms_sender_inventory_resolutions_set_updated_at
  on public.momo_sms_sender_inventory_resolutions;
create trigger trg_momo_sms_sender_inventory_resolutions_set_updated_at
  before update on public.momo_sms_sender_inventory_resolutions
  for each row
  execute function public.set_updated_at();

drop function if exists public.get_momo_sms_sender_inventory(integer, boolean);
create or replace function public.get_momo_sms_sender_inventory(
  p_limit integer default 20,
  p_include_approved boolean default false
)
returns table (
  sender text,
  sender_token text,
  sender_kind text,
  approval_status text,
  raw_count integer,
  user_count integer,
  pending_raw_count integer,
  parsed_count integer,
  open_review_count integer,
  rejected_count integer,
  matched_count integer,
  latest_parse_status text,
  latest_match_status text,
  last_ingestion_source text,
  first_seen_at timestamptz,
  last_seen_at timestamptz,
  resolution_status text,
  resolution_note text,
  resolved_at timestamptz,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
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

  return query
  with raw_enriched as (
    select
      raw.id,
      raw.user_id,
      btrim(raw.sender) as sender,
      regexp_replace(
        lower(coalesce(raw.sender, '')),
        '[^a-z0-9]+',
        '',
        'g'
      ) as sender_token,
      case
        when btrim(coalesce(raw.sender, '')) ~ '^\+?[0-9]+$' then 'msisdn'
        else 'alias'
      end as sender_kind,
      case
        when regexp_replace(
          lower(coalesce(raw.sender, '')),
          '[^a-z0-9]+',
          '',
          'g'
        ) = any(v_approved_sender_tokens) then 'approved'
        else 'unsupported'
      end as approval_status,
      raw.parse_status as raw_parse_status,
      raw.ingestion_source,
      raw.sms_received_at,
      parsed.parse_status as parsed_parse_status,
      reconciliation.match_status,
      row_number() over (
        partition by btrim(raw.sender)
        order by raw.sms_received_at desc, raw.created_at desc, raw.id desc
      ) as sender_recency_rank
    from public.momo_sms_raw raw
    left join public.momo_sms_parsed parsed
      on parsed.raw_sms_id = raw.id
    left join public.momo_reconciliations reconciliation
      on reconciliation.parsed_sms_id = parsed.id
  ),
  filtered as (
    select *
    from raw_enriched
    where p_include_approved or raw_enriched.approval_status = 'unsupported'
  ),
  grouped as (
    select
      f.sender as sender,
      f.sender_token as sender_token,
      f.sender_kind as sender_kind,
      f.approval_status as approval_status,
      count(*)::integer as raw_count,
      count(distinct f.user_id)::integer as user_count,
      count(*) filter (
        where f.raw_parse_status in ('pending', 'processing')
      )::integer as pending_raw_count,
      count(*) filter (
        where f.parsed_parse_status = 'parsed'
      )::integer as parsed_count,
      count(*) filter (
        where f.match_status in ('pending_review', 'manual_review')
      )::integer as open_review_count,
      count(*) filter (
        where f.match_status = 'rejected'
      )::integer as rejected_count,
      count(*) filter (
        where f.match_status = 'matched'
      )::integer as matched_count,
      max(f.raw_parse_status) filter (
        where f.sender_recency_rank = 1
      ) as latest_parse_status,
      coalesce(
        max(f.match_status) filter (
          where f.sender_recency_rank = 1
        ),
        'not_reconciled'
      ) as latest_match_status,
      max(f.ingestion_source) filter (
        where f.sender_recency_rank = 1
      ) as last_ingestion_source,
      min(f.sms_received_at) as first_seen_at,
      max(f.sms_received_at) as last_seen_at
    from filtered f
    group by f.sender, f.sender_token, f.sender_kind, f.approval_status
  )
  select
    g.sender,
    g.sender_token,
    g.sender_kind,
    g.approval_status,
    g.raw_count,
    g.user_count,
    g.pending_raw_count,
    g.parsed_count,
    g.open_review_count,
    g.rejected_count,
    g.matched_count,
    g.latest_parse_status,
    g.latest_match_status,
    g.last_ingestion_source,
    g.first_seen_at,
    g.last_seen_at,
    resolution.resolution_status,
    resolution.resolution_note,
    resolution.resolved_at,
    count(*) over() as total_count
  from grouped g
  left join public.momo_sms_sender_inventory_resolutions resolution
    on resolution.sender_token = g.sender_token
  order by
    case
      when resolution.resolution_status is null then 0
      else 1
    end,
    case g.approval_status
      when 'unsupported' then 0
      else 1
    end,
    g.raw_count desc,
    g.last_seen_at desc,
    g.sender asc
  limit greatest(coalesce(p_limit, 20), 1);
end;
$$;

comment on function public.get_momo_sms_sender_inventory(integer, boolean) is
  'Admin-only sender inventory for M-Money SMS raw history, including unsupported legacy senders, their parse or reconciliation outcomes, and admin acknowledgements.';

revoke all on function public.get_momo_sms_sender_inventory(integer, boolean) from public;
grant execute on function public.get_momo_sms_sender_inventory(integer, boolean)
  to authenticated, service_role;

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
