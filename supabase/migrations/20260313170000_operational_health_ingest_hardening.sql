-- ==========================================================================
-- Cool App — Harden operational health ingestion
-- ==========================================================================

alter table public.operational_health_events
  add column if not exists ingest_origin text not null default 'system'
    check (ingest_origin in ('system', 'mobile_app'));

comment on column public.operational_health_events.ingest_origin is
  'Source class for the event. system = service-role/server instrumentation, mobile_app = authenticated mobile telemetry relayed via Edge Function.';

drop policy if exists operational_health_events_insert_authenticated
  on public.operational_health_events;

create index if not exists idx_operational_health_events_origin_time
  on public.operational_health_events (ingest_origin, occurred_at desc);

create or replace view public.operational_release_dashboard as
with targets(service_key, label) as (
  values
    ('momo_parsing', 'MoMo Parsing'),
    ('payment_sync', 'Payment Sync'),
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
  where ingest_origin = 'system'
    and occurred_at >= now() - interval '24 hours'
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
      format(
        'No trusted %s health events were recorded in the last 24 hours.',
        lower(t.label)
      )
    else
      format(
        '%s ok, %s warn, %s error trusted events in the last 24 hours.',
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
  'Admin-only release dashboard summarising server-trusted operational health by monitored payment and function surface.';
