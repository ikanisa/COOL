-- ============================================================================
-- Cool App - Schedule M-Money SMS migration safety verification
-- ============================================================================

create or replace function public.run_momo_sms_migration_safety_check()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_now timestamptz := now();
  v_legacy_completed_rows integer := 0;
  v_distinct_statuses integer := 0;
  v_sync_audit_rows integer := 0;
  v_status text := 'ok';
  v_severity text := 'info';
  v_issue_code text := 'migration_safety_verified';
  v_message text;
begin
  select
    count(*) filter (where status = 'completed')::integer,
    count(distinct status)::integer
    into v_legacy_completed_rows, v_distinct_statuses
  from public.group_contributions;

  select count(*)::integer
    into v_sync_audit_rows
  from public.momo_sms_sync_runs;

  if v_legacy_completed_rows > 0 then
    v_status := 'error';
    v_severity := 'critical';
    v_issue_code := 'legacy_completed_contribution_rows';
    v_message := format(
      '%s legacy group contribution rows still use completed instead of confirmed.',
      v_legacy_completed_rows
    );
  else
    v_message := format(
      'No legacy completed contribution rows remain. %s sync audit runs are currently stored.',
      v_sync_audit_rows
    );
  end if;

  insert into public.operational_health_events (
    service,
    component,
    status,
    severity,
    issue_code,
    message,
    subject_type,
    subject_id,
    metadata,
    occurred_at,
    ingest_origin
  )
  values (
    'sms_ingest',
    'momo_sms_migration_safety',
    v_status,
    v_severity,
    v_issue_code,
    v_message,
    'group_contributions',
    'completed_status_backfill',
    jsonb_build_object(
      'legacy_completed_rows',
      v_legacy_completed_rows,
      'distinct_statuses',
      v_distinct_statuses,
      'sync_audit_rows',
      v_sync_audit_rows
    ),
    v_now,
    'system'
  );

  return jsonb_build_object(
    'status',
    v_status,
    'issue_code',
    v_issue_code,
    'legacy_completed_rows',
    v_legacy_completed_rows,
    'distinct_statuses',
    v_distinct_statuses,
    'sync_audit_rows',
    v_sync_audit_rows,
    'executed_at',
    v_now
  );
end;
$function$;

revoke all on function public.run_momo_sms_migration_safety_check() from public;
grant execute on function public.run_momo_sms_migration_safety_check()
  to service_role;
grant execute on function public.run_momo_sms_migration_safety_check()
  to postgres;

do $$
declare
  v_existing_job_id bigint;
begin
  if exists (
    select 1
      from pg_namespace
     where nspname = 'cron'
  ) then
    select jobid
      into v_existing_job_id
      from cron.job
     where jobname = 'check-momo-sms-migration-safety-daily'
     limit 1;

    if v_existing_job_id is not null then
      perform cron.unschedule(v_existing_job_id);
    end if;

    perform cron.schedule(
      'check-momo-sms-migration-safety-daily',
      '29 2 * * *',
      $cron$
        select public.run_momo_sms_migration_safety_check();
      $cron$
    );
  end if;
end;
$$;

create or replace view public.operational_triage_issues as
with manual_review_reconciliations as (
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
      'Reconciliation %s is in %s for %s.',
      mr.id,
      mr.match_status,
      coalesce(
        nullif(mr.metadata ->> 'matched_reference', ''),
        nullif(mr.metadata ->> 'source_raw_sms_id', ''),
        'this SMS'
      )
    ) as detail,
    coalesce(mr.target_table, 'momo_reconciliations') as subject_table,
    coalesce(mr.target_record_id::text, mr.id::text) as subject_id,
    mr.user_id,
    coalesce(
      nullif(mr.metadata ->> 'matched_reference', ''),
      nullif(mr.metadata ->> 'source_raw_sms_id', '')
    ) as reference,
    mr.created_at as first_seen_at,
    coalesce(mr.updated_at, mr.created_at) as last_seen_at,
    coalesce(mr.metadata, '{}'::jsonb) || jsonb_build_object(
      'match_status', mr.match_status,
      'notes', mr.notes
    ) as metadata
  from public.momo_reconciliations mr
  where mr.match_status in ('pending_review', 'manual_review')
),
latest_sms_migration_safety as (
  select distinct on (coalesce(ohe.subject_id, 'completed_status_backfill'))
    format('sms-migration-safety:%s', ohe.id) as issue_id,
    'sms_migration_safety'::text as issue_type,
    'critical'::text as severity,
    'sms_ingest'::text as service,
    'M-Money SMS migration safety regression'::text as title,
    ohe.message as detail,
    'operational_health_events'::text as subject_table,
    ohe.id::text as subject_id,
    ohe.user_id,
    coalesce(ohe.issue_code, ohe.component) as reference,
    ohe.occurred_at as first_seen_at,
    ohe.occurred_at as last_seen_at,
    coalesce(ohe.metadata, '{}'::jsonb) || jsonb_build_object(
      'function_name', ohe.function_name,
      'issue_code', ohe.issue_code,
      'component', ohe.component
    ) as metadata,
    ohe.status
  from public.operational_health_events ohe
  where ohe.service = 'sms_ingest'
    and ohe.component = 'momo_sms_migration_safety'
    and ohe.ingest_origin = 'system'
    and ohe.occurred_at >= now() - interval '30 days'
  order by coalesce(ohe.subject_id, 'completed_status_backfill'), ohe.occurred_at desc
),
sms_migration_safety_issues as (
  select
    issue_id,
    issue_type,
    severity,
    service,
    title,
    detail,
    subject_table,
    subject_id,
    user_id,
    reference,
    first_seen_at,
    last_seen_at,
    metadata
  from latest_sms_migration_safety
  where status = 'error'
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
select * from manual_review_reconciliations
union all
select * from sms_migration_safety_issues
union all
select * from edge_function_failures
union all
select * from config_issues;

comment on view public.operational_triage_issues is
  'Admin-only triage queue for direct SMS reconciliation reviews, M-Money SMS migration regressions, failed function invocation, and stale configuration.';

create or replace view public.operational_release_dashboard as
with targets(service_key, label) as (
  values
    ('sms_ingest', 'SMS Ingest'),
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
    when t.service_key in (
      'sms_ingest',
      'payment_sync',
      'config_hygiene',
      'edge_function'
    ) then
      case
        when coalesce(ic.critical_issue_count, 0) > 0 then 'failing'
        when coalesce(ic.issue_count, 0) > 0 then 'degraded'
        when coalesce(re.error_count_24h, 0) > 0 then 'failing'
        when coalesce(re.warn_count_24h, 0) > 0 then 'degraded'
        when coalesce(re.ok_count_24h, 0) > 0 then 'healthy'
        else 'unknown'
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
    when t.service_key = 'sms_ingest' then
      case
        when coalesce(ic.issue_count, 0) > 0 then
          format(
            '%s trusted M-Money SMS migration safety issues currently need triage.',
            coalesce(ic.issue_count, 0)
          )
        when coalesce(re.last_event_at, null) is null then
          'No trusted SMS ingest checks were recorded in the last 24 hours.'
        else
          format(
            '%s ok, %s warn, %s error trusted SMS ingest checks in the last 24 hours.',
            coalesce(re.ok_count_24h, 0),
            coalesce(re.warn_count_24h, 0),
            coalesce(re.error_count_24h, 0)
          )
      end
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
  'Admin-only release dashboard summarising server-trusted operational health by monitored payment, SMS, and function surface.';
