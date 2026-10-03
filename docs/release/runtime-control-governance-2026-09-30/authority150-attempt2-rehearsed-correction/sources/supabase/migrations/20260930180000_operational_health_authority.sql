begin;
--150: prevent an established Repeatable Read snapshot retaining revoked health access.
--Uses149's private authority-row lock helper; no public authority API is added.
create or replace function public.admin_system_health(p_id text default 'system')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare authority_session uuid; t timestamptz:=clock_timestamp(); window_start timestamptz:=t-interval '24 hours';
 metrics jsonb:='{}'; alerts jsonb; samples jsonb; scheduler_count integer;
 scheduler_active integer; last_scheduler timestamptz; overall text;
begin
 -- Session/Auth locks precede the roster lock consistently with other RPCs.
 begin authority_session:=public._lock_notification_registration_session();
 exception when sqlstate '42501' then raise exception 'operational_health_session_required' using errcode='42501';end;
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 -- Lock the actual grant, approval and permission rows. A stale snapshot
 -- receives40001 after revocation rather than reading an obsolete EXISTS.
 begin
  perform collect_hybrid.require_roster_actor_authority(auth.uid(),authority_session,
    'platform_owner',array['system_health.read']);
 exception when sqlstate '42501' then
  raise exception 'operational_health_permission_required' using errcode='42501';end;
 if not public.has_admin_permission('system_health.read',auth.uid()) then
  raise exception 'operational_health_permission_required' using errcode='42501';end if;
 if p_id is not null and p_id<>'system' then
  raise exception 'operational_health_invalid' using errcode='22023';end if;

 select jsonb_build_object('durable_receipts_24h',count(*) filter(where ingested_at>=window_start),
  'sms_pending',count(*) filter(where parse_status='pending'),
  'sms_pending_age_seconds',floor(extract(epoch from t-min(ingested_at) filter(where parse_status='pending')))::bigint,
  'sms_failed_24h',count(*) filter(where parse_status='failed' and ingested_at>=window_start),
  'sms_parsed_24h',count(*) filter(where parse_status='parsed' and ingested_at>=window_start),
  'sms_expired_parse_leases',count(*) filter(where parse_status='pending' and parse_lease_id is not null and parse_started_at<t-interval '5 minutes'))
 into samples from public.raw_payment_sms where parse_status='pending' or ingested_at>=window_start;
 metrics:=metrics||samples;
 select jsonb_build_object('unallocated_events',count(*)) into samples
 from public.parsed_payment_events where allocation_status in ('unallocated','ambiguous','needs_review');metrics:=metrics||samples;
 select jsonb_build_object('payments_review',count(*) filter(where status='review'),
  'payment_review_age_seconds',floor(extract(epoch from t-min(created_at) filter(where status='review')))::bigint,
  'payments_posted_24h',count(*) filter(where status='posted' and posted_at>=window_start))
 into samples from public.payments where status='review' or posted_at>=window_start;metrics:=metrics||samples;
 select jsonb_build_object('reconciliation_open',count(*)) into samples
 from collect_hybrid.momo_reconciliation_exceptions where status='open';metrics:=metrics||samples;
 select jsonb_build_object('reversals_24h',count(*)) into samples
 from collect_hybrid.momo_journal_entries where entry_type='reversal' and posted_at>=window_start;metrics:=metrics||samples;
 select jsonb_build_object('finality_processing',count(*) filter(where status='processing'),
  'finality_processed_24h',count(*) filter(where status='processed' and processed_at>=window_start))
 into samples from public.provider_finality_requests where status='processing' or processed_at>=window_start;metrics:=metrics||samples;
 select jsonb_build_object('push_queued',count(*) filter(where status='queued'),
  'push_due',count(*) filter(where status='queued' and next_attempt_at<=t),
  'push_due_age_seconds',floor(extract(epoch from t-min(next_attempt_at) filter(where status='queued' and next_attempt_at<=t)))::bigint,
  'push_processing',count(*) filter(where status='processing'),
  'push_expired_leases',count(*) filter(where status='processing' and claim_expires_at<=t),
  'push_missing_leases',count(*) filter(where status='processing' and claim_expires_at is null),
  'push_failed',count(*) filter(where status='failed'))
 into samples from public.notification_deliveries where status in ('queued','processing','failed');metrics:=metrics||samples;
 select jsonb_build_object('push_attempts_24h',count(*),'push_failed_24h',count(*) filter(where outcome='failed'),
  'push_provider_accepts_24h',count(*) filter(where outcome='sent'),'push_retry_24h',count(*) filter(where outcome='retry'),
  'push_latency_p95_ms',ceil(percentile_cont(0.95) within group(order by latency_ms))::bigint)
 into samples from public.notification_delivery_attempts where attempted_at>=window_start;metrics:=metrics||samples;
 select jsonb_build_object('receipt_ack_generated_24h',coalesce(sum(event_count) filter(where event_code='receipt_ack_generated'),0),
  'receipt_rejected_24h',coalesce(sum(event_count) filter(where event_code='receipt_rejected'),0),
  'receipt_telemetry_age_seconds',floor(extract(epoch from t-max(bucket_at)))::bigint,
  'receipt_ack_latency_mean_ms',ceil(sum(duration_total_ms) filter(where event_code='receipt_ack_generated')::numeric /
    nullif(sum(measured_count) filter(where event_code='receipt_ack_generated'),0))::bigint)
 into samples from collect_security.operational_metric_buckets where bucket_at>=window_start;metrics:=metrics||samples;
 select count(*),count(*) filter(where active) into scheduler_count,scheduler_active from cron.job
 where jobname='collect-dispatch-notifications';
 select max(d.end_time) into last_scheduler from cron.job_run_details d join cron.job j on j.jobid=d.jobid
 where j.jobname='collect-dispatch-notifications' and d.status='succeeded';
 metrics:=metrics||jsonb_build_object('push_scheduler_age_seconds',floor(extract(epoch from t-last_scheduler))::bigint);
 alerts:=collect_security.operational_health_alerts(metrics);
 overall:=case when exists(select 1 from jsonb_array_elements(alerts) a where a->>'state'='attention') then 'attention'
  when exists(select 1 from jsonb_array_elements(alerts) a where a->>'state'='unknown') then 'unknown' else 'ok' end;
 return jsonb_build_object('id','system','contract_version',1,'database','reachable','auth','authenticated',
  'parser_pending_sms',metrics->'sms_pending','failed_sms_parse',metrics->'sms_failed_24h',
  'unallocated_events',metrics->'unallocated_events','queued_notifications',metrics->'push_queued',
  'processing_notifications',metrics->'push_processing','failed_notifications',metrics->'push_failed',
  'checked_at',t,'metrics',metrics,'alerts',alerts,'health_status',overall,
  'sample_valid_until',t+interval '60 seconds','window_seconds',86400,'threshold_version',1,
  'scheduler',jsonb_build_object('state',case when scheduler_count<>1 then 'unknown'
    when scheduler_active=1 then 'enabled' else 'disabled' end,'configuration_verified',false),
  'evidence_limits',jsonb_build_array('ACK generation does not prove device receipt.',
   'Provider acceptance does not prove user delivery.','Scheduler activation does not prove provider configuration.'));
end $$;
revoke all on function public.admin_system_health(text) from public,anon,service_role;
grant execute on function public.admin_system_health(text) to authenticated;

commit;
