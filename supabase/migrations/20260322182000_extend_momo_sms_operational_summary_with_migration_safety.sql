-- ============================================================================
-- Cool App - Extend MoMo SMS operational summary with migration safety
-- ============================================================================

create or replace function public.get_momo_sms_operational_summary()
returns table (
  metric_key text,
  label text,
  health_status text,
  summary text,
  primary_label text,
  primary_value integer,
  secondary_label text,
  secondary_value integer,
  tertiary_label text,
  tertiary_value integer,
  last_signal_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, auth
as $function$
begin
  if not public.is_admin() then
    raise exception 'Admin privileges required';
  end if;

  return query
  select *
    from (
      with sync_metrics as (
        select
          count(*) filter (
            where status = 'succeeded'
              and created_at >= now() - interval '24 hours'
          )::integer as success_24h,
          count(*) filter (
            where status = 'failed'
              and created_at >= now() - interval '24 hours'
          )::integer as failed_24h,
          coalesce(
            sum(duplicate_messages) filter (
              where created_at >= now() - interval '24 hours'
            ),
            0
          )::integer as duplicates_24h,
          max(created_at) as last_signal_at
        from public.momo_sms_sync_runs
      ),
      raw_summary as (
        select
          count(*) filter (
            where parse_status in ('pending', 'processing')
          )::integer as pending_now,
          count(*) filter (
            where parse_status = 'parsed'
              and created_at >= now() - interval '24 hours'
          )::integer as parsed_24h,
          count(*) filter (
            where parse_status = 'failed'
              and created_at >= now() - interval '24 hours'
          )::integer as failed_24h,
          max(coalesce(updated_at, created_at)) as last_signal_at
        from public.momo_sms_raw
      ),
      parsed_summary as (
        select
          count(*) filter (
            where parse_status = 'needs_review'
              and coalesce(updated_at, created_at) >= now() - interval '24 hours'
          )::integer as needs_review_24h,
          max(coalesce(updated_at, created_at)) as last_signal_at
        from public.momo_sms_parsed
      ),
      parsing_metrics as (
        select
          raw.pending_now,
          raw.parsed_24h,
          raw.failed_24h,
          parsed.needs_review_24h,
          (
            select max(ts)
            from (
              values (raw.last_signal_at), (parsed.last_signal_at)
            ) as timestamps(ts)
          ) as last_signal_at
        from raw_summary raw
        cross join parsed_summary parsed
      ),
      reconciliation_metrics as (
        select
          count(*) filter (
            where match_status = 'matched'
              and coalesce(reconciled_at, updated_at, created_at) >=
                  now() - interval '24 hours'
          )::integer as matched_24h,
          count(*) filter (
            where match_status in ('pending_review', 'manual_review')
          )::integer as open_reviews,
          count(*) filter (
            where match_status = 'rejected'
              and coalesce(updated_at, created_at) >= now() - interval '24 hours'
          )::integer as rejected_24h,
          min(coalesce(updated_at, created_at)) filter (
            where match_status in ('pending_review', 'manual_review')
          ) as oldest_open_at,
          max(coalesce(reconciled_at, updated_at, created_at)) as last_signal_at
        from public.momo_reconciliations
      ),
      sender_inventory_rows as (
        select *
        from public.get_momo_sms_sender_inventory(2147483647, false)
      ),
      sender_inventory_metrics as (
        select
          count(*) filter (
            where resolution_status is null
          )::integer as unresolved_senders,
          count(*) filter (
            where resolution_status is not null
          )::integer as acknowledged_senders,
          coalesce(
            sum(raw_count) filter (
              where resolution_status is null
            ),
            0
          )::integer as unresolved_raw_rows,
          coalesce(sum(raw_count), 0)::integer as total_raw_rows,
          max(
            case
              when resolution_status is null then last_seen_at
              when resolved_at is null then last_seen_at
              when last_seen_at is null then resolved_at
              when resolved_at > last_seen_at then resolved_at
              else last_seen_at
            end
          ) as last_signal_at
        from sender_inventory_rows
      ),
      migration_safety_metrics as (
        select
          count(*) filter (
            where status = 'completed'
          )::integer as legacy_completed_rows,
          count(distinct status)::integer as distinct_statuses,
          max(created_at) filter (
            where status = 'completed'
          ) as last_signal_at
        from public.group_contributions
      ),
      sync_audit_inventory as (
        select count(*)::integer as total_sync_runs
        from public.momo_sms_sync_runs
      ),
      raw_retention_backlog as (
        select count(*)::integer as backlog
        from public.momo_sms_raw raw
        join public.momo_sms_parsed parsed
          on parsed.raw_sms_id = raw.id
         and parsed.parse_status = 'parsed'
        join public.momo_reconciliations reconciliation
          on reconciliation.parsed_sms_id = parsed.id
         and reconciliation.match_status = 'matched'
        where raw.sms_body_redacted_at is null
          and raw.parse_status = 'parsed'
          and raw.created_at <= now() - interval '14 days'
      ),
      attempt_retention_backlog as (
        select count(*)::integer as backlog
        from public.momo_parse_attempts attempt
        join public.momo_sms_raw raw
          on raw.id = attempt.raw_sms_id
        where attempt.payloads_redacted_at is null
          and raw.created_at <= now() - interval '14 days'
          and raw.parse_status in ('parsed', 'failed', 'ignored')
      ),
      raw_redactions as (
        select
          count(*) filter (
            where sms_body_redacted_at >= now() - interval '24 hours'
          )::integer as redacted_24h,
          max(sms_body_redacted_at) as last_signal_at
        from public.momo_sms_raw
      ),
      attempt_redactions as (
        select
          count(*) filter (
            where payloads_redacted_at >= now() - interval '24 hours'
          )::integer as redacted_24h,
          max(payloads_redacted_at) as last_signal_at
        from public.momo_parse_attempts
      ),
      retention_metrics as (
        select
          raw_backlog.backlog as raw_backlog,
          attempt_backlog.backlog as attempt_backlog,
          raw_redactions.redacted_24h as raw_redacted_24h,
          attempt_redactions.redacted_24h as attempt_redacted_24h,
          (
            select max(ts)
            from (
              values (raw_redactions.last_signal_at), (attempt_redactions.last_signal_at)
            ) as timestamps(ts)
          ) as last_signal_at
        from raw_retention_backlog raw_backlog
        cross join attempt_retention_backlog attempt_backlog
        cross join raw_redactions
        cross join attempt_redactions
      ),
      sender_drift_metrics as (
        select
          count(*)::integer as drift_events_24h,
          count(distinct coalesce(
            nullif(metadata ->> 'sender_token', ''),
            nullif(metadata ->> 'sender_display', ''),
            'unknown'
          ))::integer as distinct_senders_24h,
          max(occurred_at) as last_signal_at
        from public.operational_health_events
        where service = 'sms_ingest'
          and component = 'android_sms_autoread'
          and ingest_origin = 'mobile_app'
          and issue_code = 'approved_sender_drift'
          and occurred_at >= now() - interval '24 hours'
      ),
      retry_queue_metrics as (
        select
          count(*) filter (
            where issue_code = 'retry_queue_backlog'
          )::integer as backlog_events_24h,
          count(*) filter (
            where issue_code = 'retry_queue_full'
          )::integer as full_events_24h,
          count(*) filter (
            where issue_code = 'retry_queue_drain_failed'
          )::integer as drain_failures_24h,
          coalesce(
            max(
              greatest(
                coalesce((metadata ->> 'queued_after')::integer, 0),
                coalesce((metadata ->> 'queued_before')::integer, 0)
              )
            ),
            0
          )::integer as max_queue_24h,
          max(occurred_at) as last_signal_at
        from public.operational_health_events
        where service = 'sms_ingest'
          and component = 'android_sms_autoread'
          and ingest_origin = 'mobile_app'
          and issue_code in (
            'retry_queue_backlog',
            'retry_queue_full',
            'retry_queue_drain_failed',
            'retry_queue_drained'
          )
          and occurred_at >= now() - interval '24 hours'
      )
      select
        'device_sync'::text as metric_key,
        'Device Sync'::text as label,
        case
          when sync.last_signal_at is null then 'unknown'
          when sync.failed_24h > 0 and sync.success_24h = 0 then 'failing'
          when sync.failed_24h > 0 then 'degraded'
          when sync.success_24h > 0 then 'healthy'
          else 'unknown'
        end as health_status,
        case
          when sync.last_signal_at is null then
            'No device sync audits have been reported yet.'
          when sync.failed_24h > 0 then
            format(
              '%s successful syncs and %s failed syncs were reported in the last 24 hours.',
              sync.success_24h,
              sync.failed_24h
            )
          else
            format(
              '%s successful syncs were reported in the last 24 hours.',
              sync.success_24h
            )
        end as summary,
        '24h Success'::text as primary_label,
        sync.success_24h as primary_value,
        '24h Fail'::text as secondary_label,
        sync.failed_24h as secondary_value,
        'Duplicates'::text as tertiary_label,
        sync.duplicates_24h as tertiary_value,
        sync.last_signal_at
      from sync_metrics sync

      union all

      select
        'parsing'::text as metric_key,
        'Parsing'::text as label,
        case
          when parsing.pending_now >= 50 or parsing.failed_24h >= 10 then 'failing'
          when parsing.pending_now > 0
            or parsing.failed_24h > 0
            or parsing.needs_review_24h > 0 then 'degraded'
          when parsing.parsed_24h > 0 then 'healthy'
          else 'unknown'
        end as health_status,
        case
          when parsing.last_signal_at is null then
            'No raw SMS parsing activity has been recorded yet.'
          else
            format(
              '%s SMS are waiting for parse, %s parsed successfully, %s failed, and %s required parser review in the last 24 hours.',
              parsing.pending_now,
              parsing.parsed_24h,
              parsing.failed_24h,
              parsing.needs_review_24h
            )
        end as summary,
        'Pending'::text as primary_label,
        parsing.pending_now as primary_value,
        'Parsed 24h'::text as secondary_label,
        parsing.parsed_24h as secondary_value,
        'Failed 24h'::text as tertiary_label,
        parsing.failed_24h as tertiary_value,
        parsing.last_signal_at
      from parsing_metrics parsing

      union all

      select
        'reconciliation'::text as metric_key,
        'Reconciliation'::text as label,
        case
          when reconciliation.open_reviews > 0
            and reconciliation.oldest_open_at <= now() - interval '24 hours' then
            'failing'
          when reconciliation.open_reviews > 0 then 'degraded'
          when reconciliation.matched_24h > 0
            or reconciliation.rejected_24h > 0 then
            'healthy'
          else 'unknown'
        end as health_status,
        case
          when reconciliation.last_signal_at is null then
            'No reconciliation activity has been recorded yet.'
          when reconciliation.open_reviews > 0 then
            format(
              '%s reconciliations still need review, %s matched automatically, and %s were closed in the last 24 hours.',
              reconciliation.open_reviews,
              reconciliation.matched_24h,
              reconciliation.rejected_24h
            )
          when reconciliation.matched_24h > 0
            or reconciliation.rejected_24h > 0 then
            format(
              '%s reconciliations matched automatically and %s were closed in the last 24 hours.',
              reconciliation.matched_24h,
              reconciliation.rejected_24h
            )
          else
            'No open reconciliation work remains in the current 24-hour window.'
        end as summary,
        'Open Review'::text as primary_label,
        reconciliation.open_reviews as primary_value,
        'Matched 24h'::text as secondary_label,
        reconciliation.matched_24h as secondary_value,
        'Closed 24h'::text as tertiary_label,
        reconciliation.rejected_24h as tertiary_value,
        reconciliation.last_signal_at
      from reconciliation_metrics reconciliation

      union all

      select
        'sender_inventory'::text as metric_key,
        'Sender Inventory'::text as label,
        case
          when sender_inventory.unresolved_senders >= 3
            or sender_inventory.unresolved_raw_rows >= 10 then
            'failing'
          when sender_inventory.unresolved_senders > 0 then 'degraded'
          else 'healthy'
        end as health_status,
        case
          when sender_inventory.unresolved_senders > 0 then
            format(
              '%s unsupported senders remain unresolved across %s raw SMS rows. %s sender backlogs were already acknowledged.',
              sender_inventory.unresolved_senders,
              sender_inventory.unresolved_raw_rows,
              sender_inventory.acknowledged_senders
            )
          when sender_inventory.acknowledged_senders > 0 then
            format(
              'All %s unsupported sender backlogs have been acknowledged. %s raw SMS rows remain preserved as historical evidence.',
              sender_inventory.acknowledged_senders,
              sender_inventory.total_raw_rows
            )
          else
            'No unsupported sender backlog is currently stored in raw SMS history.'
        end as summary,
        'Unresolved'::text as primary_label,
        sender_inventory.unresolved_senders as primary_value,
        'Acknowledged'::text as secondary_label,
        sender_inventory.acknowledged_senders as secondary_value,
        'Raw Rows'::text as tertiary_label,
        sender_inventory.total_raw_rows as tertiary_value,
        sender_inventory.last_signal_at
      from sender_inventory_metrics sender_inventory

      union all

      select
        'migration_safety'::text as metric_key,
        'Migration Safety'::text as label,
        case
          when migration_safety.legacy_completed_rows > 0 then 'failing'
          else 'healthy'
        end as health_status,
        case
          when migration_safety.legacy_completed_rows > 0 then
            format(
              '%s legacy group contribution rows still use completed instead of confirmed. Backfill verification failed.',
              migration_safety.legacy_completed_rows
            )
          else
            format(
              'No legacy completed contribution rows remain. %s sync audit runs are currently stored, and canonical statuses stay limited to pending, confirmed, and failed.',
              sync_audit.total_sync_runs
            )
        end as summary,
        'Legacy Rows'::text as primary_label,
        migration_safety.legacy_completed_rows as primary_value,
        'Distinct Statuses'::text as secondary_label,
        migration_safety.distinct_statuses as secondary_value,
        'Sync Audit Rows'::text as tertiary_label,
        sync_audit.total_sync_runs as tertiary_value,
        migration_safety.last_signal_at
      from migration_safety_metrics migration_safety
      cross join sync_audit_inventory sync_audit

      union all

      select
        'retention'::text as metric_key,
        'Retention'::text as label,
        case
          when retention.raw_backlog + retention.attempt_backlog >= 100 then
            'failing'
          when retention.raw_backlog + retention.attempt_backlog > 0 then
            'degraded'
          when retention.last_signal_at is not null then 'healthy'
          else 'unknown'
        end as health_status,
        case
          when retention.last_signal_at is null
            and retention.raw_backlog = 0
            and retention.attempt_backlog = 0 then
            'No eligible retention workload has accumulated yet.'
          else
            format(
              '%s raw SMS rows and %s parse-attempt payload rows are currently eligible for redaction cleanup.',
              retention.raw_backlog,
              retention.attempt_backlog
            )
        end as summary,
        'Raw Backlog'::text as primary_label,
        retention.raw_backlog as primary_value,
        'Attempt Backlog'::text as secondary_label,
        retention.attempt_backlog as secondary_value,
        'Redacted 24h'::text as tertiary_label,
        retention.raw_redacted_24h + retention.attempt_redacted_24h as tertiary_value,
        retention.last_signal_at
      from retention_metrics retention

      union all

      select
        'sender_drift'::text as metric_key,
        'Sender Drift'::text as label,
        case
          when sender_drift.drift_events_24h >= 10
            or sender_drift.distinct_senders_24h >= 3 then 'failing'
          when sender_drift.drift_events_24h > 0 then 'degraded'
          else 'unknown'
        end as health_status,
        case
          when sender_drift.last_signal_at is null then
            'No unapproved sender drift has been reported in the last 24 hours.'
          else
            format(
              '%s possible MoMo messages came from %s unapproved sender IDs in the last 24 hours.',
              sender_drift.drift_events_24h,
              sender_drift.distinct_senders_24h
            )
        end as summary,
        'Drift 24h'::text as primary_label,
        sender_drift.drift_events_24h as primary_value,
        'Distinct Senders'::text as secondary_label,
        sender_drift.distinct_senders_24h as secondary_value,
        'Expected Senders'::text as tertiary_label,
        11::integer as tertiary_value,
        sender_drift.last_signal_at
      from sender_drift_metrics sender_drift

      union all

      select
        'retry_queue'::text as metric_key,
        'Retry Queue'::text as label,
        case
          when retry_queue.full_events_24h > 0
            or retry_queue.drain_failures_24h > 0
            or retry_queue.max_queue_24h >= 50 then 'failing'
          when retry_queue.backlog_events_24h > 0
            or retry_queue.max_queue_24h > 0 then 'degraded'
          when retry_queue.last_signal_at is not null then 'healthy'
          else 'unknown'
        end as health_status,
        case
          when retry_queue.last_signal_at is null then
            'No retry queue pressure has been reported in the last 24 hours.'
          else
            format(
              'Retry queue backlog was reported %s times, the largest observed queue was %s, and full-queue incidents occurred %s times in the last 24 hours.',
              retry_queue.backlog_events_24h,
              retry_queue.max_queue_24h,
              retry_queue.full_events_24h
            )
        end as summary,
        'Backlog Events'::text as primary_label,
        retry_queue.backlog_events_24h as primary_value,
        'Max Queue'::text as secondary_label,
        retry_queue.max_queue_24h as secondary_value,
        'Full Events'::text as tertiary_label,
        retry_queue.full_events_24h as tertiary_value,
        retry_queue.last_signal_at
      from retry_queue_metrics retry_queue
    ) summary_rows
   order by
    case summary_rows.metric_key
      when 'device_sync' then 0
      when 'parsing' then 1
      when 'reconciliation' then 2
      when 'sender_inventory' then 3
      when 'migration_safety' then 4
      when 'retention' then 5
      when 'sender_drift' then 6
      when 'retry_queue' then 7
      else 8
    end;
end;
$function$;
