begin;
set local collect.operational_health_qa='isolated_clone';

-- Engineering health counters contain no recipient, token, body, amount,
-- transaction reference, provider response or arbitrary diagnostic text.
create table collect_security.operational_metric_buckets (
 bucket_at timestamptz not null,
 event_code text not null check(event_code in ('receipt_ack_generated','receipt_rejected',
   'receipt_processing_accepted','receipt_processing_deferred')),
 event_count bigint not null check(event_count between 1 and 9007199254740991),
 measured_count bigint not null check(measured_count between 0 and event_count),
 duration_total_ms bigint not null check(duration_total_ms>=0),
 duration_max_ms integer not null check(duration_max_ms between 0 and 120000),
 primary key(bucket_at,event_code),
 check(bucket_at=date_trunc('minute',bucket_at))
);
alter table collect_security.operational_metric_buckets enable row level security;
revoke all on collect_security.operational_metric_buckets from public,anon,authenticated,service_role;

create function public.record_operational_metric_v1(p_event_code text,p_duration_ms integer default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare bucket timestamptz:=date_trunc('minute',clock_timestamp());
begin
 if auth.role() is distinct from 'service_role' then
  raise exception 'operational_metric_service_required' using errcode='42501'; end if;
 if p_event_code is null or p_event_code not in ('receipt_ack_generated','receipt_rejected',
   'receipt_processing_accepted','receipt_processing_deferred')
   or p_duration_ms<0 or p_duration_ms>120000 then
  raise exception 'operational_metric_invalid' using errcode='22023';end if;
 insert into collect_security.operational_metric_buckets as b
   (bucket_at,event_code,event_count,measured_count,duration_total_ms,duration_max_ms)
 values(bucket,p_event_code,1,case when p_duration_ms is null then 0 else 1 end,
   coalesce(p_duration_ms,0),coalesce(p_duration_ms,0))
 on conflict(bucket_at,event_code) do update set event_count=b.event_count+1,
   measured_count=b.measured_count+excluded.measured_count,
   duration_total_ms=b.duration_total_ms+excluded.duration_total_ms,
   duration_max_ms=greatest(b.duration_max_ms,excluded.duration_max_ms);
 return true;
end $$;
revoke all on function public.record_operational_metric_v1(text,integer) from public,anon,authenticated;
grant execute on function public.record_operational_metric_v1(text,integer) to service_role;

-- Explicit bounded owner maintenance; installing the migration starts no job.
create function collect_security.purge_operational_metrics(p_limit integer default 1000)
returns integer language plpgsql security definer set search_path='' as $$
declare removed integer;
begin
 if p_limit is null or p_limit not between 1 and 10000 then
  raise exception 'operational_metric_limit_invalid' using errcode='22023';end if;
 with old as (select bucket_at,event_code from collect_security.operational_metric_buckets
   where bucket_at<clock_timestamp()-interval '90 days' order by bucket_at,event_code
   for update skip locked limit p_limit), gone as (
   delete from collect_security.operational_metric_buckets b using old
   where b.bucket_at=old.bucket_at and b.event_code=old.event_code returning 1)
 select count(*) into removed from gone;
 return removed;
end $$;
revoke all on function collect_security.purge_operational_metrics(integer) from public,anon,authenticated,service_role;

-- Versioned local engineering thresholds, not assertions of a contracted SLO.
-- Missing measurements are unknown; an empty queue has no queue-age sample.
create function collect_security.operational_health_alerts(p_metrics jsonb)
returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare rule record; value jsonb; number_value numeric; state text;
 alerts jsonb:='[]';
begin
 if p_metrics is null or jsonb_typeof(p_metrics)<>'object' then
  raise exception 'operational_health_invalid' using errcode='22023';end if;
 for rule in select * from (values
  ('receipt_parse_backlog','sms_pending',100::numeric,null::text),
  ('receipt_parse_age','sms_pending_age_seconds',300::numeric,'sms_pending'),
  ('receipt_parse_failure','sms_failed_24h',1::numeric,null::text),
  ('receipt_parser_lease_expired','sms_expired_parse_leases',1::numeric,null::text),
  ('payment_unmatched','unallocated_events',1::numeric,null::text),
  ('payment_review_age','payment_review_age_seconds',3600::numeric,'payments_review'),
  ('reconciliation_exception','reconciliation_open',1::numeric,null::text),
  ('push_queue_age','push_due_age_seconds',120::numeric,'push_due'),
  ('push_expired_lease','push_expired_leases',1::numeric,null::text),
  ('push_missing_lease','push_missing_leases',1::numeric,null::text),
  ('push_attempt_failure','push_failed_24h',5::numeric,null::text),
  ('receipt_telemetry_stale','receipt_telemetry_age_seconds',300::numeric,'durable_receipts_24h'),
  ('push_scheduler_stale','push_scheduler_age_seconds',180::numeric,'push_due')
 ) rules(code,metric,threshold,queue) loop
  value:=p_metrics->rule.metric;
  if rule.queue is not null and p_metrics->rule.queue='0'::jsonb then state:='not_applicable';
  elsif value is null or value='null'::jsonb then state:='unknown';
  elsif jsonb_typeof(value)<>'number' or (value#>>'{}') !~ '^[0-9]+$'
     or (value#>>'{}')::numeric>9007199254740991 then
   raise exception 'operational_health_invalid' using errcode='22023';
  else number_value:=(value#>>'{}')::numeric;
   state:=case when number_value>=rule.threshold then 'attention' else 'ok' end;
  end if;
  alerts:=alerts||jsonb_build_array(jsonb_build_object('code',rule.code,'metric',rule.metric,
   'threshold',rule.threshold,'state',state));
 end loop;
 return alerts;
end $$;
revoke all on function collect_security.operational_health_alerts(jsonb) from public,anon,authenticated,service_role;

create or replace function public.admin_system_health(p_id text default 'system')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare t timestamptz:=clock_timestamp(); window_start timestamptz:=t-interval '24 hours';
 metrics jsonb:='{}'; alerts jsonb; samples jsonb; scheduler_count integer;
 scheduler_active integer; last_scheduler timestamptz; overall text;
begin
 -- Session/Auth locks precede the roster lock consistently with other RPCs.
 begin perform public._lock_notification_registration_session();
 exception when sqlstate '42501' then raise exception 'operational_health_session_required' using errcode='42501';end;
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 if not public.has_admin_permission('system_health.read',auth.uid()) then
  raise exception 'operational_health_permission_required' using errcode='42501';end if;
 if p_id is not null and p_id<>'system' then
  raise exception 'operational_health_invalid' using errcode='22023';end if;

 select jsonb_build_object('durable_receipts_24h',count(*) filter(where ingested_at>=window_start),
  'sms_pending',count(*) filter(where parse_status='pending'),
  'sms_pending_age_seconds',floor(extract(epoch from t-min(ingested_at) filter(where parse_status='pending')))::bigint,
  'sms_failed_24h',count(*) filter(where parse_status='failed' and ingested_at>=window_start),
  'sms_parsed_24h',count(*) filter(where parse_status='parsed' and ingested_at>=window_start),
  'sms_expired_parse_leases',count(*) filter(where parse_status='pending' and parse_lease_id is not null and parse_started_at<t-interval '5 minutes')))
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


-- Root recorder must validate exact isolated Docker/55722 identity first.
-- Run in the same rollback transaction as reviewed148 migration body on146,
-- or inside a guarded rollback transaction after the final148 owner apply.
set local statement_timeout='30s';
set local lock_timeout='5s';
do $$ begin
 if current_database()<>'postgres' or current_user<>'postgres'
  or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
  or current_setting('collect.operational_health_qa',true) is distinct from 'isolated_clone'
  or exists(select 1 from auth.users where id::text like '99680000-%' or phone='250788968001') then
  raise exception 'Quiet isolated operational-health fixture required';end if;
end $$;
create temp table health_assertions(name text primary key);
create function pg_temp.health_assert(name text,ok boolean) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Health assertion failed: %',name;end if;
 insert into health_assertions values(name);end $$;
create function pg_temp.health_error(name text,statement text,expected text) returns void language plpgsql as $$
begin begin execute statement;exception when others then
 if sqlstate is distinct from expected then raise exception 'Unexpected health rejection SQLSTATE %',sqlstate;end if;
 perform pg_temp.health_assert(name,true);return;end;
 raise exception 'Expected health rejection: %',name;end $$;
grant all on health_assertions to authenticated,service_role,anon;
grant execute on function pg_temp.health_assert(text,boolean),pg_temp.health_error(text,text,text) to authenticated,service_role,anon;
do $$ begin execute format('grant usage on schema %I to authenticated,service_role,anon',pg_my_temp_schema()::regnamespace::text);end $$;

select pg_temp.health_assert('private metric table RLS', (select relrowsecurity from pg_class where oid='collect_security.operational_metric_buckets'::regclass));
select pg_temp.health_assert('no raw metric table API grant', not has_table_privilege('anon','collect_security.operational_metric_buckets','SELECT,INSERT,UPDATE,DELETE')
 and not has_table_privilege('authenticated','collect_security.operational_metric_buckets','SELECT,INSERT,UPDATE,DELETE')
 and not has_table_privilege('service_role','collect_security.operational_metric_buckets','SELECT,INSERT,UPDATE,DELETE'));
select pg_temp.health_assert('private purge denies service',not has_function_privilege('service_role','collect_security.purge_operational_metrics(integer)','EXECUTE'));
select pg_temp.health_assert('alert evaluator denies all API roles',not has_function_privilege('anon','collect_security.operational_health_alerts(jsonb)','EXECUTE')
 and not has_function_privilege('authenticated','collect_security.operational_health_alerts(jsonb)','EXECUTE')
 and not has_function_privilege('service_role','collect_security.operational_health_alerts(jsonb)','EXECUTE'));
select pg_temp.health_assert('absent health is unknown',(select bool_and(a->>'state'='unknown') from jsonb_array_elements(collect_security.operational_health_alerts('{}')) a));
select pg_temp.health_assert('empty queue age not applicable',(select a->>'state'='not_applicable' from jsonb_array_elements(collect_security.operational_health_alerts('{"push_due":0}')) a where a->>'code'='push_queue_age'));
select pg_temp.health_assert('pending without age unknown',(select a->>'state'='unknown' from jsonb_array_elements(collect_security.operational_health_alerts('{"push_due":1}')) a where a->>'code'='push_queue_age'));
select pg_temp.health_assert('age below threshold ok',(select a->>'state'='ok' from jsonb_array_elements(collect_security.operational_health_alerts('{"push_due":1,"push_due_age_seconds":119}')) a where a->>'code'='push_queue_age'));
select pg_temp.health_assert('exact age threshold alerts',(select a->>'state'='attention' from jsonb_array_elements(collect_security.operational_health_alerts('{"push_due":1,"push_due_age_seconds":120}')) a where a->>'code'='push_queue_age'));
select pg_temp.health_assert('expired lease alerts',(select a->>'state'='attention' from jsonb_array_elements(collect_security.operational_health_alerts('{"push_expired_leases":1}')) a where a->>'code'='push_expired_lease'));
select pg_temp.health_assert('stale telemetry alerts',(select a->>'state'='attention' from jsonb_array_elements(collect_security.operational_health_alerts('{"durable_receipts_24h":1,"receipt_telemetry_age_seconds":300}')) a where a->>'code'='receipt_telemetry_stale'));
select pg_temp.health_error('null metrics denied','select collect_security.operational_health_alerts(null)','22023');
select pg_temp.health_error('negative counters denied','select collect_security.operational_health_alerts(''{"sms_pending":-1}'')','22023');
select pg_temp.health_error('string counters denied','select collect_security.operational_health_alerts(''{"sms_pending":"100"}'')','22023');
select pg_temp.health_error('fraction counters denied','select collect_security.operational_health_alerts(''{"sms_pending":1.5}'')','22023');
select pg_temp.health_error('unsafe counters denied','select collect_security.operational_health_alerts(''{"sms_pending":9007199254740992}'')','22023');

set local role anon;
select set_config('request.jwt.claims','{"role":"anon"}',true);
select pg_temp.health_error('anonymous telemetry denied','select public.record_operational_metric_v1(''receipt_ack_generated'',5)','42501');
select pg_temp.health_error('anonymous health denied','select public.admin_system_health()','42501');
reset role;
set local role service_role;
select set_config('request.jwt.claims','{"role":"service_role"}',true);
select pg_temp.health_assert('service bounded sample', public.record_operational_metric_v1('receipt_ack_generated',12));
select pg_temp.health_assert('service unmeasured sample',public.record_operational_metric_v1('receipt_ack_generated',null));
select pg_temp.health_error('arbitrary diagnostic text denied','select public.record_operational_metric_v1(''secret-canary-phone-250788968001'',1)','22023');
select pg_temp.health_error('missing event denied','select public.record_operational_metric_v1(null,1)','22023');
select pg_temp.health_error('negative duration denied','select public.record_operational_metric_v1(''receipt_ack_generated'',-1)','22023');
select pg_temp.health_error('unbounded duration denied','select public.record_operational_metric_v1(''receipt_ack_generated'',120001)','22023');
select pg_temp.health_error('service health read denied','select public.admin_system_health()','42501');
reset role;
select pg_temp.health_assert('measured versus missing duration distinct',exists(select 1 from collect_security.operational_metric_buckets
 where event_code='receipt_ack_generated' and event_count=2 and measured_count=1 and duration_total_ms=12 and duration_max_ms=12));

insert into auth.users(id,aud,role,phone,phone_confirmed_at,raw_app_meta_data,raw_user_meta_data)
values('99680000-0000-4000-8000-000000000001','authenticated','authenticated','250788968001',now(),'{}','{}');
insert into collect_admin_access.whatsapp_approvals(user_id,phone_e164,approved_at,reason)
values('99680000-0000-4000-8000-000000000001','+250788968001',now()-interval '2 minutes','Synthetic health fixture identity');
insert into public.admin_user_roles(user_id,role_id,reason,created_at)
select '99680000-0000-4000-8000-000000000001',id,'Synthetic health fixture role',now()-interval '1 minute'
from public.admin_roles where name='platform_owner';
insert into auth.sessions(id,user_id,created_at,updated_at,not_after,aal)
values('99680000-0000-4000-8000-000000000011','99680000-0000-4000-8000-000000000001',now(),now(),now()+interval '1 hour','aal1');
insert into public.raw_payment_sms(id,receiver_user_id,raw_sender,raw_body,body_hash,ingested_at)
values('99680000-0000-4000-8000-000000000101','99680000-0000-4000-8000-000000000001',
 'secret-sender-canary','secret-body-canary',encode(extensions.digest('secret-body-canary','sha256'),'hex'),now()-interval '6 minutes');
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","aal":"aal1","sub":"99680000-0000-4000-8000-000000000001","session_id":"99680000-0000-4000-8000-000000000011"}',true);
create temp table health_receipt as select public.admin_system_health() receipt;
select pg_temp.health_assert('health read schema and freshness', (select receipt->>'id'='system' and receipt->>'contract_version'='1'
 and (receipt->>'sample_valid_until')::timestamptz=(receipt->>'checked_at')::timestamptz+interval '60 seconds' from health_receipt));
select pg_temp.health_assert('actual pending age alerts',(select exists(select 1 from jsonb_array_elements(receipt->'alerts') a
 where a->>'code'='receipt_parse_age' and a->>'state'='attention') from health_receipt));
select pg_temp.health_assert('actual ACK counts and latency',(select receipt->'metrics'->>'receipt_ack_generated_24h'='2'
 and receipt->'metrics'->>'receipt_ack_latency_mean_ms'='12' from health_receipt));
select pg_temp.health_assert('no private source facts',(select receipt::text !~ 'secret-|250788968001|99680000|raw_body|raw_sender|token_hash|provider_message_id' from health_receipt));
select pg_temp.health_assert('disabled scheduler explicit',(select receipt->'scheduler'->>'state'='disabled'
 and receipt->'scheduler'->>'configuration_verified'='false' from health_receipt));
select pg_temp.health_error('arbitrary caller ID not reflected','select public.admin_system_health(''secret-id-canary'')','22023');
reset role;
delete from public.admin_user_roles where user_id='99680000-0000-4000-8000-000000000001';
set local role authenticated;
select pg_temp.health_error('revoked role denied','select public.admin_system_health()','42501');
reset role;
delete from auth.sessions where id='99680000-0000-4000-8000-000000000011';
set local role authenticated;
select pg_temp.health_error('deleted Auth session denied','select public.admin_system_health()','42501');
reset role;
select pg_temp.health_error('unbounded purge denied','select collect_security.purge_operational_metrics(10001)','22023');
select pg_temp.health_assert('fresh metrics preserved',collect_security.purge_operational_metrics(1)=0);
select 'OPERATIONAL_HEALTH_ASSERTIONS|'||count(*) from health_assertions;
-- Recorder/parent controls rollback and checks all tables, catalog and cron.

rollback;
