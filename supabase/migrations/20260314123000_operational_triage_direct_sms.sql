-- ============================================================================
-- Cool App — Align operational triage with direct SMS reconciliation
-- ============================================================================

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
select * from edge_function_failures
union all
select * from config_issues;

comment on view public.operational_triage_issues is
  'Admin-only triage queue for direct SMS reconciliation reviews, failed function invocation, and stale configuration.';
