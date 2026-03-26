-- ==========================================================================
-- Cool App — Operational health, release dashboard, and triage surfaces
-- ==========================================================================

create table if not exists public.operational_health_events (
  id uuid primary key default gen_random_uuid(),
  service text not null,
  component text not null default 'general',
  status text not null default 'ok'
    check (status in ('ok', 'warn', 'error')),
  severity text not null default 'info'
    check (severity in ('info', 'warning', 'critical')),
  issue_code text,
  message text not null,
  function_name text,
  user_id uuid references auth.users(id) on delete set null,
  subject_type text,
  subject_id text,
  metadata jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists idx_operational_health_events_service_time
  on public.operational_health_events (service, occurred_at desc);
create index if not exists idx_operational_health_events_status_time
  on public.operational_health_events (status, occurred_at desc);
create index if not exists idx_operational_health_events_function_time
  on public.operational_health_events (function_name, occurred_at desc);
create index if not exists idx_operational_health_events_subject
  on public.operational_health_events (subject_type, subject_id, occurred_at desc);
alter table public.operational_health_events enable row level security;
drop policy if exists operational_health_events_insert_authenticated
  on public.operational_health_events;
create policy operational_health_events_insert_authenticated
  on public.operational_health_events for insert
  to authenticated
  with check (user_id is null or auth.uid() = user_id);
drop policy if exists operational_health_events_select_admin
  on public.operational_health_events;
create policy operational_health_events_select_admin
  on public.operational_health_events for select
  to authenticated
  using (public.is_admin());
comment on table public.operational_health_events is
  'Append-only operational health feed for SMS ingest, MoMo parsing, wallet sync, partner checkout, and Edge Function failures.';
create or replace view public.operational_config_issues as
with required_configs(config_key, scope_mode, stale_after_days, description) as (
  values
    ('support_whatsapp', 'global', 45, 'Global support escalation contact.'),
    ('supported_languages', 'global', 90, 'Languages exposed by the app shell.')
),
matching_configs as (
  select
    rc.config_key,
    rc.scope_mode,
    rc.stale_after_days,
    rc.description,
    ac.key,
    ac.country,
    nullif(btrim(coalesce(ac.value, '')), '') as config_value,
    coalesce(ac.updated_at, ac.created_at) as last_updated_at
  from required_configs rc
  left join lateral (
    select *
    from public.app_config ac
    where ac.key = rc.config_key
      and (
        rc.scope_mode = 'any'
        or (rc.scope_mode = 'global' and ac.country is null)
      )
    order by coalesce(ac.updated_at, ac.created_at) desc nulls last
    limit 1
  ) ac on true
)
select
  format('config:%s', config_key) as issue_id,
  case
    when config_value is null then 'missing_required_config'
    else 'stale_config_review'
  end as issue_type,
  case
    when config_value is null then 'critical'
    else 'warning'
  end as severity,
  'config_hygiene'::text as service,
  case
    when config_value is null then 'Required config is missing'
    else 'Config review window expired'
  end as title,
  case
    when config_value is null then
      format('%s is missing. %s', config_key, description)
    else
      format(
        '%s has not been reviewed in %s days. %s',
        config_key,
        greatest(
          1,
          floor(extract(epoch from (now() - last_updated_at)) / 86400)::int
        ),
        description
      )
  end as detail,
  'app_config'::text as subject_table,
  config_key as subject_id,
  null::uuid as user_id,
  config_key as reference,
  last_updated_at as first_seen_at,
  last_updated_at as last_seen_at,
  jsonb_build_object(
    'config_key', config_key,
    'scope_mode', scope_mode,
    'country', country,
    'last_updated_at', last_updated_at,
    'stale_after_days', stale_after_days
  ) as metadata
from matching_configs
where config_value is null
   or last_updated_at <= now() - make_interval(days => stale_after_days);
comment on view public.operational_config_issues is
  'Admin-only release hygiene issues for required app_config entries that are missing or stale.';
create or replace view public.operational_triage_issues as
with stale_pending_transactions as (
  select
    format('payment-sync:%s', pt.id) as issue_id,
    'failed_payment_sync'::text as issue_type,
    case
      when pt.created_at <= now() - interval '2 hours' then 'critical'
      else 'warning'
    end as severity,
    'payment_sync'::text as service,
    'Payment sync is still pending'::text as title,
    format(
      'Payment reference %s has been pending for %s minutes and has not reconciled.',
      pt.reference,
      greatest(
        1,
        floor(extract(epoch from (now() - pt.created_at)) / 60)::int
      )
    ) as detail,
    'pending_transactions'::text as subject_table,
    pt.id::text as subject_id,
    pt.user_id,
    pt.reference,
    pt.created_at as first_seen_at,
    coalesce(pt.updated_at, pt.created_at) as last_seen_at,
    jsonb_build_object(
      'amount', pt.amount,
      'provider', pt.provider,
      'status', pt.status,
      'recipient_momo', pt.recipient_momo
    ) as metadata
  from public.pending_transactions pt
  where pt.status = 'pending'
    and pt.created_at <= now() - interval '20 minutes'
),
manual_review_reconciliations as (
  select
    format('payment-review:%s', mr.id) as issue_id,
    'failed_payment_sync'::text as issue_type,
    case
      when coalesce(mr.updated_at, mr.created_at) <= now() - interval '2 hours'
        then 'critical'
      else 'warning'
    end as severity,
    'payment_sync'::text as service,
    'Payment sync requires manual review'::text as title,
    format(
      'Reconciliation %s is in %s for reference %s.',
      mr.id,
      mr.match_status,
      coalesce(
        nullif(mr.metadata ->> 'matched_reference', ''),
        'unknown'
      )
    ) as detail,
    coalesce(mr.target_table, 'momo_reconciliations') as subject_table,
    coalesce(mr.target_record_id::text, mr.id::text) as subject_id,
    mr.user_id,
    nullif(mr.metadata ->> 'matched_reference', '') as reference,
    mr.created_at as first_seen_at,
    coalesce(mr.updated_at, mr.created_at) as last_seen_at,
    coalesce(mr.metadata, '{}'::jsonb) || jsonb_build_object(
      'match_status', mr.match_status,
      'notes', mr.notes
    ) as metadata
  from public.momo_reconciliations mr
  where mr.match_status in ('pending_review', 'manual_review')
    and (
      nullif(mr.metadata ->> 'pending_transaction_id', '') is not null
      or nullif(mr.metadata ->> 'matched_reference', '') is not null
    )
),
edge_function_failures as (
  select
    format('edge-function:%s', ohe.id) as issue_id,
    'failed_function_invocation'::text as issue_type,
    'critical'::text as severity,
    'edge_function'::text as service,
    format(
      '%s failed',
      coalesce(nullif(ohe.function_name, ''), ohe.component, 'Edge Function')
    ) as title,
    ohe.message as detail,
    'operational_health_events'::text as subject_table,
    ohe.id::text as subject_id,
    ohe.user_id,
    coalesce(ohe.function_name, ohe.component) as reference,
    ohe.occurred_at as first_seen_at,
    ohe.occurred_at as last_seen_at,
    coalesce(ohe.metadata, '{}'::jsonb) || jsonb_build_object(
      'function_name', ohe.function_name,
      'issue_code', ohe.issue_code
    ) as metadata
  from public.operational_health_events ohe
  where ohe.service = 'edge_function'
    and ohe.status = 'error'
    and ohe.occurred_at >= now() - interval '7 days'
),
config_issues as (
  select *
  from public.operational_config_issues
)
select * from stale_pending_transactions
union all
select * from manual_review_reconciliations
union all
select * from edge_function_failures
union all
select * from config_issues;
comment on view public.operational_triage_issues is
  'Admin-only triage queue for failed payment sync, failed function invocation, and stale configuration.';
create or replace view public.operational_release_dashboard as
with targets(service_key, label) as (
  values
    ('sms_ingest', 'SMS Ingest'),
    ('momo_parsing', 'MoMo Parsing'),
    ('payment_sync', 'Payment Sync'),
    ('wallet_sync', 'Wallet Sync'),
    ('partner_checkout', 'Partner Checkout'),
    ('edge_function', 'Edge Functions'),
    ('config_hygiene', 'Config Hygiene')
),
recent_events as (
  select
    service,
    count(*) filter (where status = 'ok')::int as ok_count_24h,
    count(*) filter (where status = 'warn')::int as warn_count_24h,
    count(*) filter (where status = 'error')::int as error_count_24h,
    max(occurred_at) as last_event_at
  from public.operational_health_events
  where occurred_at >= now() - interval '24 hours'
  group by service
),
issue_counts as (
  select
    service,
    count(*)::int as issue_count,
    count(*) filter (where severity = 'critical')::int as critical_issue_count,
    max(last_seen_at) as last_issue_at
  from public.operational_triage_issues
  group by service
)
select
  t.service_key,
  t.label,
  case
    when t.service_key in ('payment_sync', 'config_hygiene', 'edge_function') then
      case
        when coalesce(ic.critical_issue_count, 0) > 0 then 'failing'
        when coalesce(ic.issue_count, 0) > 0 then 'degraded'
        else 'healthy'
      end
    when coalesce(re.error_count_24h, 0) > 0 then 'failing'
    when coalesce(re.warn_count_24h, 0) > 0 or coalesce(ic.issue_count, 0) > 0
      then 'degraded'
    when coalesce(re.ok_count_24h, 0) > 0 then 'healthy'
    else 'unknown'
  end as health_status,
  coalesce(re.ok_count_24h, 0) as ok_count_24h,
  coalesce(re.warn_count_24h, 0) as warn_count_24h,
  coalesce(re.error_count_24h, 0) as error_count_24h,
  coalesce(ic.issue_count, 0) as issue_count,
  greatest(
    coalesce(re.last_event_at, '-infinity'::timestamptz),
    coalesce(ic.last_issue_at, '-infinity'::timestamptz)
  ) as last_signal_at,
  case
    when t.service_key = 'payment_sync' then
      format(
        '%s payment-sync issues currently need triage.',
        coalesce(ic.issue_count, 0)
      )
    when t.service_key = 'config_hygiene' then
      format(
        '%s config issues are blocking or degrading release readiness.',
        coalesce(ic.issue_count, 0)
      )
    when t.service_key = 'edge_function' then
      case
        when coalesce(ic.issue_count, 0) = 0 then
          'No Edge Function failures were recorded in the last 7 days.'
        else
          format(
            '%s Edge Function failures were recorded in the last 7 days.',
            coalesce(ic.issue_count, 0)
          )
      end
    when coalesce(re.last_event_at, null) is null then
      format('No %s health events were recorded in the last 24 hours.', lower(t.label))
    else
      format(
        '%s ok, %s warn, %s error events in the last 24 hours.',
        coalesce(re.ok_count_24h, 0),
        coalesce(re.warn_count_24h, 0),
        coalesce(re.error_count_24h, 0)
      )
  end as summary
from targets t
left join recent_events re
  on re.service = t.service_key
left join issue_counts ic
  on ic.service = t.service_key;
comment on view public.operational_release_dashboard is
  'Admin-only release dashboard summarising operational health by monitored payment and function surface.';
create or replace function public.get_operational_release_dashboard()
returns table (
  service_key text,
  label text,
  health_status text,
  ok_count_24h int,
  warn_count_24h int,
  error_count_24h int,
  issue_count int,
  last_signal_at timestamptz,
  summary text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin privileges required';
  end if;

  return query
  select
    ord.service_key,
    ord.label,
    ord.health_status,
    ord.ok_count_24h,
    ord.warn_count_24h,
    ord.error_count_24h,
    ord.issue_count,
    ord.last_signal_at,
    ord.summary
  from public.operational_release_dashboard ord
  order by
    case ord.health_status
      when 'failing' then 0
      when 'degraded' then 1
      when 'unknown' then 2
      else 3
    end,
    ord.label asc;
end;
$$;
revoke all on function public.get_operational_release_dashboard() from public;
grant execute on function public.get_operational_release_dashboard() to authenticated;
create or replace function public.get_operational_triage_issues()
returns table (
  issue_id text,
  issue_type text,
  severity text,
  service text,
  title text,
  detail text,
  subject_table text,
  subject_id text,
  user_id uuid,
  reference text,
  first_seen_at timestamptz,
  last_seen_at timestamptz,
  metadata jsonb
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_admin() then
    raise exception 'Admin privileges required';
  end if;

  return query
  select
    oti.issue_id,
    oti.issue_type,
    oti.severity,
    oti.service,
    oti.title,
    oti.detail,
    oti.subject_table,
    oti.subject_id,
    oti.user_id,
    oti.reference,
    oti.first_seen_at,
    oti.last_seen_at,
    oti.metadata
  from public.operational_triage_issues oti
  order by
    case oti.severity
      when 'critical' then 0
      else 1
    end,
    oti.last_seen_at desc;
end;
$$;
revoke all on function public.get_operational_triage_issues() from public;
grant execute on function public.get_operational_triage_issues() to authenticated;
create or replace function public.get_recent_operational_health_events(
  p_limit integer default 40
)
returns table (
  id uuid,
  service text,
  component text,
  status text,
  severity text,
  issue_code text,
  message text,
  function_name text,
  user_id uuid,
  subject_type text,
  subject_id text,
  metadata jsonb,
  occurred_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 40), 1), 200);
begin
  if not public.is_admin() then
    raise exception 'Admin privileges required';
  end if;

  return query
  select
    ohe.id,
    ohe.service,
    ohe.component,
    ohe.status,
    ohe.severity,
    ohe.issue_code,
    ohe.message,
    ohe.function_name,
    ohe.user_id,
    ohe.subject_type,
    ohe.subject_id,
    ohe.metadata,
    ohe.occurred_at
  from public.operational_health_events ohe
  order by ohe.occurred_at desc
  limit v_limit;
end;
$$;
revoke all on function public.get_recent_operational_health_events(integer)
  from public;
grant execute on function public.get_recent_operational_health_events(integer)
  to authenticated;
