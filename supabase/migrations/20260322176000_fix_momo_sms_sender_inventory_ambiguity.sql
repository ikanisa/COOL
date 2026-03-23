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
      max(raw_parse_status) filter (
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
*** Add File: /Volumes/PRO-G40/COOL/supabase/migrations/20260322177000_fix_momo_sms_sender_inventory_grouping_aliases.sql
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
    count(*) over() as total_count
  from grouped g
  order by
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
  'Admin-only sender inventory for M-Money SMS raw history, including unsupported legacy senders and their parse or reconciliation outcomes.';

revoke all on function public.get_momo_sms_sender_inventory(integer, boolean) from public;
grant execute on function public.get_momo_sms_sender_inventory(integer, boolean)
  to authenticated, service_role;
  select
    grouped.sender,
    grouped.sender_token,
    grouped.sender_kind,
    grouped.approval_status,
    grouped.raw_count,
    grouped.user_count,
    grouped.pending_raw_count,
    grouped.parsed_count,
    grouped.open_review_count,
    grouped.rejected_count,
    grouped.matched_count,
    grouped.latest_parse_status,
    grouped.latest_match_status,
    grouped.last_ingestion_source,
    grouped.first_seen_at,
    grouped.last_seen_at,
    count(*) over() as total_count
  from grouped
  order by
    case grouped.approval_status
      when 'unsupported' then 0
      else 1
    end,
    grouped.raw_count desc,
    grouped.last_seen_at desc,
    grouped.sender asc
  limit greatest(coalesce(p_limit, 20), 1);
end;
$$;

comment on function public.get_momo_sms_sender_inventory(integer, boolean) is
  'Admin-only sender inventory for M-Money SMS raw history, including unsupported legacy senders and their parse or reconciliation outcomes.';

revoke all on function public.get_momo_sms_sender_inventory(integer, boolean) from public;
grant execute on function public.get_momo_sms_sender_inventory(integer, boolean)
  to authenticated, service_role;
