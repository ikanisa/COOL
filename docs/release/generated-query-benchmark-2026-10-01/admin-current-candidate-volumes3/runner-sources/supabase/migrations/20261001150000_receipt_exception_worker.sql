begin;
create extension if not exists pg_net with schema extensions;

-- A separate trusted backend worker. It cannot enqueue receipts, mutate the
-- ledger or send SMS. Installation prepares an inactive cron job only.
create table collect_ops.receipt_worker_configuration(
 singleton boolean primary key check(singleton),revision bigint not null check(revision between 1 and 1000000000),
 enabled boolean not null,scan_limit integer not null check(scan_limit between 1 and 25),
 escalation_limit integer not null check(escalation_limit between 1 and 20),
 day_jobs integer not null check(day_jobs between 1 and 1440),
 day_scan_sources integer not null check(day_scan_sources between 1 and 36000),
 day_escalations integer not null check(day_escalations between 1 and 28800),updated_at timestamptz not null);
insert into collect_ops.receipt_worker_configuration values(true,1,false,25,20,1440,36000,28800,clock_timestamp());
create table collect_ops.receipt_worker_configuration_history(
 revision bigint primary key,configuration jsonb not null,recorded_at timestamptz not null);
insert into collect_ops.receipt_worker_configuration_history
 select revision,to_jsonb(c)-'singleton',clock_timestamp()from collect_ops.receipt_worker_configuration c;
create table collect_ops.receipt_worker_jobs(
 request_id uuid primary key,configuration_revision bigint not null references collect_ops.receipt_worker_configuration_history,
 scan_limit integer not null check(scan_limit between 1 and 25),escalation_limit integer not null check(escalation_limit between 1 and 20),
 reserved_day date not null,created_at timestamptz not null,expires_at timestamptz not null,
 check(isfinite(created_at)and isfinite(expires_at)and expires_at=created_at+interval '90 seconds'));
create index receipt_worker_jobs_day on collect_ops.receipt_worker_jobs(reserved_day,created_at desc);
create table collect_ops.receipt_worker_dispatches(
 request_id uuid not null references collect_ops.receipt_worker_jobs,attempt integer not null check(attempt between 1 and 3),
 http_request_id bigint not null unique,dispatched_at timestamptz not null,primary key(request_id,attempt));
create table collect_ops.receipt_worker_receipts(
 request_id uuid primary key references collect_ops.receipt_worker_jobs,recorded_at timestamptz not null,result jsonb not null,
 scan_request_id uuid not null unique references collect_ops.receipt_exception_scans);
create table collect_ops.receipt_worker_expirations(
 request_id uuid primary key references collect_ops.receipt_worker_jobs,checked_at timestamptz not null,
 outcome text not null check(outcome='expired_without_receipt'));
do $$declare t text;begin
 foreach t in array array['receipt_worker_configuration','receipt_worker_configuration_history','receipt_worker_jobs',
  'receipt_worker_dispatches','receipt_worker_receipts','receipt_worker_expirations']loop
  execute format('alter table collect_ops.%I enable row level security',t);
  execute format('revoke all on collect_ops.%I from public,anon,authenticated,service_role',t);
  if t<>'receipt_worker_configuration'then execute format('create trigger retain_worker_evidence before update or delete on collect_ops.%I for each row execute function collect_ops.immutable_evidence()',t);end if;
 end loop;
end$$;

create function collect_ops.receipt_worker_transport()returns jsonb
language plpgsql security definer set search_path=''as $$
declare project_url text;api_key text;secret text;begin
 if to_regclass('vault.decrypted_secrets')is null then raise exception 'receipt_worker_transport_unconfigured'using errcode='55000';end if;
 select decrypted_secret into project_url from vault.decrypted_secrets where name='collect_receipt_exception_project_url';
 select decrypted_secret into api_key from vault.decrypted_secrets where name='collect_receipt_exception_api_key';
 select decrypted_secret into secret from vault.decrypted_secrets where name='collect_receipt_exception_worker_secret';
 -- Deliberately pinned to Collect's existing project; no request-supplied URL.
 if project_url is distinct from 'https://lhbowpbcpwoiparwnwgt.supabase.co'
  or coalesce(length(api_key),0)<20 or coalesce(length(secret),0)<32 or length(secret)>256
  or api_key~'[\r\n]'or secret~'[\r\n]'then raise exception 'receipt_worker_transport_unconfigured'using errcode='55000';end if;
 return jsonb_build_object('url',project_url||'/functions/v1/collect-receipt-exception-worker',
  'headers',jsonb_build_object('Content-Type','application/json','apikey',api_key,'x-collect-receipt-worker',secret));
end$$;

create function public.execute_receipt_exception_worker_v1(p_request_id uuid,p_configuration_revision bigint,p_expires_at timestamptz)
returns jsonb language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare c collect_ops.receipt_worker_configuration;j collect_ops.receipt_worker_jobs;prior collect_ops.receipt_worker_receipts;
 scan jsonb;escalation jsonb;result jsonb;t timestamptz;begin
 perform collect_ops.receipt_exception_service();
 if p_request_id is null or p_configuration_revision is null or p_configuration_revision<1 or p_expires_at is null or not isfinite(p_expires_at)
  then raise exception 'receipt_worker_request_invalid'using errcode='22023';end if;
 -- Lock order is global authority, then original job, then scanner/workflow.
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-trusted-worker'))then
  return jsonb_build_object('contract_version',1,'request_id',p_request_id,'status','in_progress','receipt',null);end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-worker-job:'||p_request_id::text,0));
 select * into j from collect_ops.receipt_worker_jobs where request_id=p_request_id;
 if j.request_id is null then raise exception 'receipt_worker_job_unavailable'using errcode='42501';end if;
 if j.configuration_revision<>p_configuration_revision or j.expires_at<>p_expires_at then
  raise exception 'receipt_worker_original_conflict'using errcode='22023';end if;
 select * into prior from collect_ops.receipt_worker_receipts where request_id=p_request_id;
 if prior.request_id is not null then return jsonb_build_object('contract_version',1,'request_id',p_request_id,'status','recorded','receipt',prior.result);end if;
 select * into c from collect_ops.receipt_worker_configuration where singleton for share;
 if not c.enabled or c.revision<>j.configuration_revision then raise exception 'receipt_worker_authority_lost'using errcode='42501';end if;
 if j.expires_at<=clock_timestamp()or exists(select 1 from collect_ops.receipt_worker_expirations where request_id=j.request_id)
  then raise exception 'receipt_worker_expired'using errcode='55000';end if;
 -- The escalation pump takes roster before workflow. Acquire both before
 -- the scanner so the combined transaction preserves that same lock order.
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 perform pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
 if j.expires_at<=clock_timestamp()then raise exception 'receipt_worker_expired'using errcode='55000';end if;
 scan:=public.process_receipt_deferral_exceptions_v1(j.request_id,j.scan_limit,j.expires_at);
 if scan->>'status'='processed'then escalation:=public.process_exception_escalations_v1(j.escalation_limit);
 else escalation:=jsonb_build_object('contract_version',1,'channel','admin_inbox','delivered',0,'obsolete',0,'recipient_unavailable',0,'external_send',false);end if;
 t:=clock_timestamp();if j.expires_at<=t then raise exception 'receipt_worker_expired'using errcode='55000';end if;
 -- Scan, source observations, inbox delivery and this receipt commit together.
 result:=jsonb_build_object('contract_version',1,'request_id',j.request_id,'configuration_revision',j.configuration_revision,
  'recorded_at',collect_ops.utc(t),'expires_at',collect_ops.utc(j.expires_at),'status',case when scan->>'status'='busy'then 'busy'else 'completed'end,
  'scan',scan,'escalation',escalation,'financial_action',false,'send_action',false,'external_send',false);
 insert into collect_ops.receipt_worker_receipts values(j.request_id,t,result,j.request_id);
 return jsonb_build_object('contract_version',1,'request_id',p_request_id,'status','recorded','receipt',result);
end$$;
create function public.get_receipt_exception_worker_request_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare j collect_ops.receipt_worker_jobs;r collect_ops.receipt_worker_receipts;acquired boolean;t timestamptz;begin
 perform collect_ops.receipt_exception_service();if p_request_id is null then raise exception 'receipt_worker_request_invalid'using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-receipt-worker-job:'||p_request_id::text,0));
 if acquired then
  select * into j from collect_ops.receipt_worker_jobs where request_id=p_request_id;
  select * into r from collect_ops.receipt_worker_receipts where request_id=p_request_id;
 end if;
 t:=clock_timestamp();return jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),
  'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),'status',case when not acquired then 'in_progress'when r.request_id is not null then 'recorded'else 'not_recorded'end,
  'expires_at',case when j.request_id is null then null else collect_ops.utc(j.expires_at)end,'receipt',r.result);
end$$;

create function collect_ops.run_receipt_exception_schedule()returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare c collect_ops.receipt_worker_configuration;j collect_ops.receipt_worker_jobs;transport jsonb;t timestamptz;
 prior_count integer;http_id bigint;last_dispatch timestamptz;day_count integer;scan_reserved integer;escalation_reserved integer;state text;begin
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-trusted-worker'))then return jsonb_build_object('status','overlap');end if;
 select * into c from collect_ops.receipt_worker_configuration where singleton for share;
 if not c.enabled then return jsonb_build_object('status','inactive');end if;
 transport:=collect_ops.receipt_worker_transport();t:=clock_timestamp();
 select * into j from collect_ops.receipt_worker_jobs order by created_at desc,request_id desc limit 1;
 if j.request_id is not null then
  perform pg_advisory_xact_lock(hashtextextended('collect-receipt-worker-job:'||j.request_id::text,0));
  if not exists(select 1 from collect_ops.receipt_worker_receipts where request_id=j.request_id)then
   if j.expires_at<=t or j.configuration_revision<>c.revision then
    if j.expires_at>t then return jsonb_build_object('status','fenced_pending','request_id',j.request_id);end if;
    -- Fresh exact job lock makes absence conclusive after its immutable deadline.
    insert into collect_ops.receipt_worker_expirations values(j.request_id,t,'expired_without_receipt')on conflict do nothing;
   else
    select count(*),max(dispatched_at)into prior_count,last_dispatch from collect_ops.receipt_worker_dispatches where request_id=j.request_id;
    if prior_count>=3 or last_dispatch>t-interval '30 seconds'then return jsonb_build_object('status','pending','request_id',j.request_id);end if;
    state:='redispatched';
   end if;
  end if;
 end if;
 if state is null then
  if j.created_at>t-interval '60 seconds'then return jsonb_build_object('status','cadence');end if;
  select count(*),coalesce(sum(scan_limit),0),coalesce(sum(escalation_limit),0)into day_count,scan_reserved,escalation_reserved
   from collect_ops.receipt_worker_jobs where reserved_day=(t at time zone 'UTC')::date;
  if day_count>=c.day_jobs or scan_reserved+c.scan_limit>c.day_scan_sources or escalation_reserved+c.escalation_limit>c.day_escalations
   then return jsonb_build_object('status','quota_exhausted');end if;
  insert into collect_ops.receipt_worker_jobs values(gen_random_uuid(),c.revision,c.scan_limit,c.escalation_limit,
   (t at time zone 'UTC')::date,t,t+interval '90 seconds')returning * into j;prior_count:=0;state:='queued';
 end if;
 select net.http_post(url:=transport->>'url',headers:=transport->'headers',body:=jsonb_build_object('contract_version',1,
  'action','execute','request_id',j.request_id,'configuration_revision',j.configuration_revision,'expires_at',collect_ops.utc(j.expires_at)),
  timeout_milliseconds:=15000)into http_id;
 insert into collect_ops.receipt_worker_dispatches values(j.request_id,prior_count+1,http_id,t);
 return jsonb_build_object('status',state,'request_id',j.request_id,'http_request_id',http_id,'attempt',prior_count+1,'expires_at',collect_ops.utc(j.expires_at));
end$$;

-- Installer-only configuration, deliberately unavailable to all API roles.
-- Disabling/reconfiguring revision-fences every previously created job.
create function public.configure_receipt_exception_schedule_v1(p_expected_revision bigint,p_enabled boolean,p_scan_limit integer,
 p_escalation_limit integer,p_day_jobs integer,p_day_scan_sources integer,p_day_escalations integer)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='2s'as $$
declare c collect_ops.receipt_worker_configuration;job bigint;begin
 if p_expected_revision is null or p_enabled is null or p_scan_limit is null or p_scan_limit not between 1 and 25
  or p_escalation_limit is null or p_escalation_limit not between 1 and 20 or p_day_jobs is null or p_day_jobs not between 1 and 1440
  or p_day_scan_sources is null or p_day_scan_sources not between p_scan_limit and 36000
  or p_day_escalations is null or p_day_escalations not between p_escalation_limit and 28800 then
  raise exception 'receipt_worker_configuration_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtext('collect-receipt-trusted-worker'));
 select * into c from collect_ops.receipt_worker_configuration where singleton for update;
 if c.revision<>p_expected_revision or c.revision=1000000000 then raise exception 'receipt_worker_configuration_changed'using errcode='55000';end if;
 if p_enabled then perform collect_ops.receipt_worker_transport();end if;
 update collect_ops.receipt_worker_configuration set revision=revision+1,enabled=p_enabled,scan_limit=p_scan_limit,escalation_limit=p_escalation_limit,
  day_jobs=p_day_jobs,day_scan_sources=p_day_scan_sources,day_escalations=p_day_escalations,updated_at=clock_timestamp()where singleton returning * into c;
 insert into collect_ops.receipt_worker_configuration_history values(c.revision,to_jsonb(c)-'singleton',clock_timestamp());
 for job in select jobid from cron.job where jobname='collect-receipt-exceptions'loop perform cron.unschedule(job);end loop;
 job:=cron.schedule('collect-receipt-exceptions','* * * * *','select collect_ops.run_receipt_exception_schedule();');
 perform cron.alter_job(job,active:=p_enabled);
 return to_jsonb(c)-'singleton';
end$$;

create function public.admin_get_receipt_exception_worker_health_v1()returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare c collect_ops.receipt_worker_configuration;j collect_ops.receipt_worker_jobs;r collect_ops.receipt_worker_receipts;
 t timestamptz;state text;alerts jsonb:='[]'::jsonb;pending bigint;refused integer;transport_ready boolean:=false;
 day_count integer;scan_reserved integer;escalation_reserved integer;begin
 perform collect_ops.actor(false);t:=clock_timestamp();select * into c from collect_ops.receipt_worker_configuration where singleton;
 select * into j from collect_ops.receipt_worker_jobs order by created_at desc,request_id desc limit 1;
 select * into r from collect_ops.receipt_worker_receipts order by recorded_at desc,request_id desc limit 1;
 state:=case when not c.enabled then 'inactive'when j.request_id is null then 'unobserved'
  when exists(select 1 from collect_ops.receipt_worker_receipts where request_id=j.request_id)then 'observed'
  when exists(select 1 from collect_ops.receipt_worker_expirations where request_id=j.request_id)then 'expired_without_receipt'
  when j.expires_at<=t then 'unknown'else 'pending'end;
 select count(*)into pending from collect_ops.receipt_exception_work where processed_at is null;
 select count(*),coalesce(sum(scan_limit),0),coalesce(sum(escalation_limit),0)into day_count,scan_reserved,escalation_reserved
  from collect_ops.receipt_worker_jobs where reserved_day=(t at time zone 'UTC')::date;
 begin perform collect_ops.receipt_worker_transport();transport_ready:=true;
 exception when object_not_in_prerequisite_state then transport_ready:=false;end;
 refused:=coalesce((r.result->'scan'->>'refused')::integer,0);
 if c.enabled and(r.recorded_at is null or r.recorded_at<t-interval '180 seconds')then alerts:=alerts||jsonb_build_array('WORKER_STALE');end if;
 if state='unknown'then alerts:=alerts||jsonb_build_array('ORIGINAL_OUTCOME_UNKNOWN');end if;
 if state='expired_without_receipt'then alerts:=alerts||jsonb_build_array('ORIGINAL_EXPIRED_UNHANDLED');end if;
 if pending>c.scan_limit*10 then alerts:=alerts||jsonb_build_array('DEFERRAL_BACKLOG');end if;
 if refused>0 then alerts:=alerts||jsonb_build_array('SOURCE_REFUSALS');end if;
 if c.enabled and not transport_ready then alerts:=alerts||jsonb_build_array('TRANSPORT_UNCONFIGURED');end if;
 if c.enabled and(day_count>=c.day_jobs or scan_reserved+c.scan_limit>c.day_scan_sources or escalation_reserved+c.escalation_limit>c.day_escalations)
  then alerts:=alerts||jsonb_build_array('WORKER_QUOTA_EXHAUSTED');end if;
 return jsonb_build_object('contract_version',1,'checked_at',collect_ops.utc(t),'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),
  'configuration_revision',c.revision,'enabled',c.enabled,'state',state,'last_request_id',j.request_id,'last_created_at',collect_ops.utc(j.created_at),
  'last_expires_at',collect_ops.utc(j.expires_at),'last_recorded_at',collect_ops.utc(r.recorded_at),'last_outcome',r.result->'status',
  'pending_sources',pending,'alerts',alerts,'transport_configured',transport_ready,
  'day_jobs_reserved',day_count,'day_scan_sources_reserved',scan_reserved,'day_escalations_reserved',escalation_reserved,
  'day_jobs_cap',c.day_jobs,'day_scan_sources_cap',c.day_scan_sources,'day_escalations_cap',c.day_escalations,
  'source_scan_complete',false,'financial_action',false,'send_action',false,'external_send',false);
end$$;

revoke all on function collect_ops.receipt_worker_transport(),collect_ops.run_receipt_exception_schedule(),
 public.configure_receipt_exception_schedule_v1(bigint,boolean,integer,integer,integer,integer,integer),
 public.execute_receipt_exception_worker_v1(uuid,bigint,timestamptz),public.get_receipt_exception_worker_request_v1(uuid),
 public.admin_get_receipt_exception_worker_health_v1()from public,anon,authenticated,service_role;
grant execute on function public.execute_receipt_exception_worker_v1(uuid,bigint,timestamptz),
 public.get_receipt_exception_worker_request_v1(uuid)to service_role;
grant execute on function public.admin_get_receipt_exception_worker_health_v1()to authenticated;
-- Keep other existing schedules untouched. Applying this source has no HTTP wake.
do $$declare job bigint;begin
 for job in select jobid from cron.job where jobname='collect-receipt-exceptions'loop perform cron.unschedule(job);end loop;
 job:=cron.schedule('collect-receipt-exceptions','* * * * *','select collect_ops.run_receipt_exception_schedule();');
 perform cron.alter_job(job,active:=false);
end$$;
commit;
