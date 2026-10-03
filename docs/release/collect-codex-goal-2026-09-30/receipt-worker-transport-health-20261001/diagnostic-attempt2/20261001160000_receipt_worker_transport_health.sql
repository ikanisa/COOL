begin;

-- pg_net0.20.0 indexes response creation time only. A bounded response-ID
-- lookup needs this index when unrelated functions have many responses.
create index if not exists collect_receipt_http_response_id on net._http_response(id);

-- Evidence only: no HTTP enqueue, worker execution, financial or send action.
-- pg_net response rows are ephemeral and are not worker acknowledgements.
create table collect_ops.receipt_transport_configuration(
 singleton boolean primary key check(singleton),revision bigint not null check(revision between 1 and 1000000000),
 batch_limit integer not null check(batch_limit between 1 and 25),day_inspections integer not null check(day_inspections between 1 and 72000));
insert into collect_ops.receipt_transport_configuration values(true,1,25,36000);
create table collect_ops.receipt_transport_progress(
 singleton boolean primary key check(singleton),epoch bigint not null check(epoch between 1 and 1000000000),
 last_dispatched_at timestamptz,last_http_request_id bigint,last_request_id uuid,last_recorded_at timestamptz,
 check((last_dispatched_at is null)=(last_http_request_id is null)));
insert into collect_ops.receipt_transport_progress(singleton,epoch)values(true,1);
create table collect_ops.receipt_transport_requests(
 request_id uuid primary key,request_limit integer not null check(request_limit between 1 and 25),expires_at timestamptz not null,
 recorded_at timestamptz not null,result jsonb not null,check(isfinite(expires_at)and isfinite(recorded_at)and expires_at>recorded_at));
create table collect_ops.receipt_transport_inspections(
 request_id uuid not null references collect_ops.receipt_transport_requests deferrable initially deferred,
 http_request_id bigint not null references collect_ops.receipt_worker_dispatches(http_request_id),
 inspected_at timestamptz not null,quota_day date not null,primary key(request_id,http_request_id));
create index receipt_transport_inspections_day on collect_ops.receipt_transport_inspections(quota_day);
create table collect_ops.receipt_transport_observations(
 http_request_id bigint not null references collect_ops.receipt_worker_dispatches(http_request_id),revision bigint not null check(revision between 1 and 1000000000),
 outcome text not null check(outcome in('QUEUED_UNOBSERVED','RESPONSE_UNOBSERVED','HTTP_ACCEPTED','HTTP_PENDING','AUTH_REFUSED','ENDPOINT_UNAVAILABLE',
  'REQUEST_REFUSED','ORIGINAL_CONFLICT','WORKER_CONFIG_REFUSED','RATE_LIMITED','HTTP_SERVER_FAILURE','HTTP_REFUSED','HTTP_UNEXPECTED',
  'NETWORK_TIMEOUT','NETWORK_FAILURE','RESPONSE_INVALID','RESPONSE_CONFLICT')),
 transport_terminal boolean not null,http_status integer check(http_status between 100 and 599),
 worker_error_code text check(worker_error_code in('WORKER_UNCONFIGURED','WORKER_AUTH_REQUIRED','WORKER_REQUEST_INVALID','WORKER_AUTHORITY_REFUSED',
  'WORKER_ORIGINAL_CONFLICT','WORKER_LOOKUP_UNAVAILABLE','WORKER_OUTCOME_UNKNOWN','METHOD_NOT_ALLOWED')),
 response_rows_observed integer not null check(response_rows_observed between 0 and 2),response_at timestamptz,
 observed_at timestamptz not null,evidence_sha256 text not null check(evidence_sha256~'^[a-f0-9]{64}$'),
 reconciliation_request_id uuid not null references collect_ops.receipt_transport_requests deferrable initially deferred,
 primary key(http_request_id,revision),check(isfinite(observed_at)and(response_at is null or isfinite(response_at))),
 check(transport_terminal=(outcome not in('QUEUED_UNOBSERVED','RESPONSE_UNOBSERVED'))));
create table collect_ops.receipt_transport_heads(
 http_request_id bigint primary key references collect_ops.receipt_worker_dispatches(http_request_id),revision bigint not null,
 foreign key(http_request_id,revision)references collect_ops.receipt_transport_observations);
create table collect_ops.receipt_transport_request_observations(
 request_id uuid not null references collect_ops.receipt_transport_requests deferrable initially deferred,
 http_request_id bigint not null,revision bigint not null,
 foreign key(http_request_id,revision)references collect_ops.receipt_transport_observations,
 primary key(request_id,http_request_id,revision));
do $$declare t text;begin
 foreach t in array array['receipt_transport_configuration','receipt_transport_progress','receipt_transport_requests','receipt_transport_inspections',
  'receipt_transport_observations','receipt_transport_heads','receipt_transport_request_observations']loop
  execute format('alter table collect_ops.%I enable row level security',t);
  execute format('revoke all on collect_ops.%I from public,anon,authenticated,service_role',t);
  if t in('receipt_transport_requests','receipt_transport_inspections','receipt_transport_observations','receipt_transport_request_observations')then
   execute format('create trigger retain_transport_evidence before update or delete on collect_ops.%I for each row execute function collect_ops.immutable_evidence()',t);end if;
 end loop;
end$$;

create function collect_ops.receipt_transport_schema_valid()returns boolean
language sql stable security definer set search_path=''as $$
 select to_regclass('net._http_response')is not null and to_regclass('net.http_request_queue')is not null and not exists(
  select 1 from(values('net._http_response','id','bigint'),('net._http_response','status_code','integer'),
   ('net._http_response','content','text'),('net._http_response','timed_out','boolean'),('net._http_response','error_msg','text'),
   ('net._http_response','created','timestamp with time zone'),('net.http_request_queue','id','bigint'))required(relation,name,type)
  where not exists(select 1 from pg_attribute a where a.attrelid=to_regclass(required.relation)and a.attname=required.name
   and a.attnum>0 and not a.attisdropped and format_type(a.atttypid,a.atttypmod)=required.type));
$$;
create function collect_ops.receipt_transport_sample(p_http_request_id bigint,p_worker_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare response_rows integer;r record;body jsonb;code text;outcome text;status integer;response_at timestamptz;begin
 -- Never select/store headers, URLs or raw errors. Read at most two matching
 -- response rows; pg_net0.20.0 does not make its response ID unique.
 select count(*)into response_rows from(select 1 from net._http_response where id=p_http_request_id limit 2)x;
 if response_rows=0 then
  outcome:=case when exists(select 1 from net.http_request_queue where id=p_http_request_id)then 'QUEUED_UNOBSERVED'else 'RESPONSE_UNOBSERVED'end;
 elsif response_rows=2 then outcome:='RESPONSE_CONFLICT';
 else
  select status_code,timed_out,nullif(error_msg,'')is not null as error_present,
   case when octet_length(content)<=1024 then content else null end as bounded_content,created into r
   from net._http_response where id=p_http_request_id limit 1;
  if isfinite(r.created)then response_at:=r.created;end if;
  if r.status_code between 100 and 599 then status:=r.status_code;end if;
  if r.bounded_content is not null then
   begin
    body:=r.bounded_content::jsonb;
    if jsonb_typeof(body)='object'and(body-'error'-'request_id')='{}'::jsonb
     and jsonb_typeof(body->'error')='string'and(body->>'error')in('WORKER_UNCONFIGURED','WORKER_AUTH_REQUIRED','WORKER_REQUEST_INVALID',
      'WORKER_AUTHORITY_REFUSED','WORKER_ORIGINAL_CONFLICT','WORKER_LOOKUP_UNAVAILABLE','WORKER_OUTCOME_UNKNOWN','METHOD_NOT_ALLOWED')
     and((body->>'error')in('WORKER_UNCONFIGURED','WORKER_AUTH_REQUIRED','WORKER_REQUEST_INVALID','METHOD_NOT_ALLOWED')and not body?'request_id'
      or body->>'request_id'=p_worker_request_id::text)then code:=body->>'error';end if;
   exception when data_exception then code:=null;end;
  end if;
  if response_at is null or(r.timed_out is true and status is not null)or(r.error_present and status is not null)then outcome:='RESPONSE_INVALID';code:=null;
  elsif r.timed_out is true then outcome:='NETWORK_TIMEOUT';code:=null;
  elsif r.error_present then outcome:='NETWORK_FAILURE';code:=null;
  elsif status is null then outcome:='RESPONSE_INVALID';code:=null;
  elsif status=503 and code='WORKER_UNCONFIGURED'then outcome:='WORKER_CONFIG_REFUSED';
  elsif status=409 and code='WORKER_ORIGINAL_CONFLICT'then outcome:='ORIGINAL_CONFLICT';
  elsif status in(401,403)then outcome:='AUTH_REFUSED';
  elsif status in(404,405)then outcome:='ENDPOINT_UNAVAILABLE';
  elsif status in(400,409,413,415,422)then outcome:='REQUEST_REFUSED';
  elsif status=429 then outcome:='RATE_LIMITED';
  elsif status between 500 and 599 then outcome:='HTTP_SERVER_FAILURE';
  elsif status between 400 and 499 then outcome:='HTTP_REFUSED';
  elsif status=202 then outcome:='HTTP_PENDING';
  elsif status between 200 and 299 then outcome:='HTTP_ACCEPTED';
  else outcome:='HTTP_UNEXPECTED';end if;
 end if;
 return jsonb_build_object('outcome',outcome,'transport_terminal',outcome not in('QUEUED_UNOBSERVED','RESPONSE_UNOBSERVED'),
  'http_status',status,'worker_error_code',code,'response_rows_observed',response_rows,'response_at',collect_ops.utc(response_at));
end$$;

create function collect_ops.reconcile_receipt_transport(p_request_id uuid,p_limit integer,p_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare prior collect_ops.receipt_transport_requests;c collect_ops.receipt_transport_configuration;p collect_ops.receipt_transport_progress;
 d collect_ops.receipt_worker_dispatches;old collect_ops.receipt_transport_observations;sample jsonb;signature text;rev bigint;
 t timestamptz;result jsonb;state text;inspected integer:=0;added integer:=0;terminal integer:=0;unobserved integer:=0;units integer;begin
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'receipt_transport_snapshot_retry'using errcode='40001';end if;
 if p_request_id is null or p_limit is null or p_limit not between 1 and 25 or p_expires_at is null or not isfinite(p_expires_at)
  or p_expires_at>clock_timestamp()+interval '120 seconds'then raise exception 'receipt_transport_request_invalid'using errcode='22023';end if;
 if p_expires_at<=clock_timestamp()then raise exception 'receipt_transport_expired'using errcode='55000';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-transport-request:'||p_request_id::text,0));
 select * into prior from collect_ops.receipt_transport_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.request_limit<>p_limit or prior.expires_at<>p_expires_at then raise exception 'receipt_transport_original_conflict'using errcode='22023';end if;return prior.result;end if;
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-transport-reconcile'))then state:='busy';
 else
  select * into c from collect_ops.receipt_transport_configuration where singleton for share;
  select * into p from collect_ops.receipt_transport_progress where singleton for update;
  if not collect_ops.receipt_transport_schema_valid()then state:='runtime_unavailable';
  else
   t:=clock_timestamp();select count(*)into units from collect_ops.receipt_transport_inspections where quota_day=(t at time zone 'UTC')::date;
   if units>=c.day_inspections then state:='quota_exhausted';
   else
    for d in select x.* from collect_ops.receipt_worker_dispatches x
     left join collect_ops.receipt_transport_heads h on h.http_request_id=x.http_request_id
     left join collect_ops.receipt_transport_observations o on o.http_request_id=h.http_request_id and o.revision=h.revision
     where o.transport_terminal is distinct from true and(p.last_dispatched_at is null or(x.dispatched_at,x.http_request_id)>(p.last_dispatched_at,p.last_http_request_id))
     order by x.dispatched_at,x.http_request_id limit least(p_limit,c.batch_limit,c.day_inspections-units)loop
     if p_expires_at<=clock_timestamp()then raise exception 'receipt_transport_expired'using errcode='55000';end if;
     sample:=collect_ops.receipt_transport_sample(d.http_request_id,d.request_id);
     signature:=encode(extensions.digest(convert_to(sample::text,'UTF8'),'sha256'),'hex');
     select o.* into old from collect_ops.receipt_transport_heads h join collect_ops.receipt_transport_observations o
      on o.http_request_id=h.http_request_id and o.revision=h.revision where h.http_request_id=d.http_request_id;
     if old.http_request_id is null or old.evidence_sha256<>signature then
      rev:=coalesce(old.revision,0)+1;if rev>1000000000 then raise exception 'receipt_transport_revision_exhausted'using errcode='55000';end if;
      insert into collect_ops.receipt_transport_observations values(d.http_request_id,rev,sample->>'outcome',(sample->>'transport_terminal')::boolean,
       (sample->>'http_status')::integer,sample->>'worker_error_code',(sample->>'response_rows_observed')::integer,
       (sample->>'response_at')::timestamptz,clock_timestamp(),signature,p_request_id);
      insert into collect_ops.receipt_transport_heads values(d.http_request_id,rev)on conflict(http_request_id)do update set revision=excluded.revision;
      insert into collect_ops.receipt_transport_request_observations values(p_request_id,d.http_request_id,rev);added:=added+1;
     end if;
     insert into collect_ops.receipt_transport_inspections values(p_request_id,d.http_request_id,clock_timestamp(),(t at time zone 'UTC')::date);
     inspected:=inspected+1;if(sample->>'transport_terminal')::boolean then terminal:=terminal+1;else unobserved:=unobserved+1;end if;
     p.last_dispatched_at:=d.dispatched_at;p.last_http_request_id:=d.http_request_id;
    end loop;
    if inspected=0 then
     if p.epoch=1000000000 then raise exception 'receipt_transport_epoch_exhausted'using errcode='55000';end if;
     p.last_dispatched_at:=null;p.last_http_request_id:=null;p.epoch:=p.epoch+1;
    end if;
    state:='processed';
   end if;
  end if;
 end if;
 t:=clock_timestamp();if p_expires_at<=t then raise exception 'receipt_transport_expired'using errcode='55000';end if;
 if p.singleton is not null then update collect_ops.receipt_transport_progress set epoch=p.epoch,last_dispatched_at=p.last_dispatched_at,
  last_http_request_id=p.last_http_request_id,last_request_id=p_request_id,last_recorded_at=t where singleton;end if;
 result:=jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),'expires_at',collect_ops.utc(p_expires_at),
  'status',state,'inspected',inspected,'observations_added',added,'terminal_observed',terminal,'unobserved',unobserved,
  'source_scan_complete',false,'financial_action',false,'send_action',false,'resend_action',false);
 insert into collect_ops.receipt_transport_requests values(p_request_id,p_limit,p_expires_at,t,result);return result;
end$$;
create function public.reconcile_receipt_worker_transport_v1(p_request_id uuid,p_limit integer,p_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''as $$begin
 perform collect_ops.receipt_exception_service();return collect_ops.reconcile_receipt_transport(p_request_id,p_limit,p_expires_at);end$$;
create function public.get_receipt_worker_transport_request_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare r collect_ops.receipt_transport_requests;t timestamptz;acquired boolean;begin
 perform collect_ops.receipt_exception_service();if p_request_id is null then raise exception 'receipt_transport_request_invalid'using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-receipt-transport-request:'||p_request_id::text,0));
 select * into r from collect_ops.receipt_transport_requests where acquired and request_id=p_request_id;t:=clock_timestamp();
 return jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),
  'status',case when not acquired then 'in_progress'when r.request_id is null then 'not_recorded'else 'recorded'end,
  'expires_at',case when r.request_id is null then null else collect_ops.utc(r.expires_at)end,'receipt',r.result);end$$;

-- Preserve the original scheduler OID, command, return contract and inactive
-- default. Telemetry collection happens before a configured original wake.
do $$declare definition text;begin
 select pg_get_functiondef('collect_ops.run_receipt_exception_schedule()'::regprocedure)into definition;
 definition:=replace(definition,'collect_ops.run_receipt_exception_schedule','collect_ops.receipt_transport_base_schedule');execute definition;
end$$;
create or replace function collect_ops.run_receipt_exception_schedule()returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare n integer;begin
 if exists(select 1 from collect_ops.receipt_worker_configuration where singleton and enabled)then
  select batch_limit into n from collect_ops.receipt_transport_configuration where singleton;
  begin
   perform collect_ops.reconcile_receipt_transport(gen_random_uuid(),n,clock_timestamp()+interval '60 seconds');
  exception when lock_not_available or query_canceled or insufficient_privilege or undefined_table or undefined_column then
   -- Observation failure rolls back only telemetry. It cannot prevent the
   -- existing bounded worker from progressing. Separate telemetry read
   -- reports absent/stale collector evidence; no success is fabricated.
   null;
  end;
 end if;
 return collect_ops.receipt_transport_base_schedule();
end$$;

create function public.admin_get_receipt_worker_transport_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare j collect_ops.receipt_worker_jobs;r collect_ops.receipt_worker_receipts;c collect_ops.receipt_transport_configuration;
 p collect_ops.receipt_transport_progress;t timestamptz;state text;rows jsonb;alerts jsonb:='[]'::jsonb;last_outcome text;units bigint;acquired boolean;begin
 perform collect_ops.actor(false);if p_request_id is null then raise exception 'receipt_transport_request_invalid'using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-receipt-worker-job:'||p_request_id::text,0));
 select * into j from collect_ops.receipt_worker_jobs where request_id=p_request_id;
 if j.request_id is null then raise exception 'receipt_transport_job_unavailable'using errcode='22023';end if;
 select * into r from collect_ops.receipt_worker_receipts where request_id=p_request_id;
 select * into c from collect_ops.receipt_transport_configuration where singleton;select * into p from collect_ops.receipt_transport_progress where singleton;
 t:=clock_timestamp();state:=case when not acquired then 'in_progress'when r.request_id is not null then 'recorded'
  when exists(select 1 from collect_ops.receipt_worker_expirations where request_id=j.request_id)then 'expired_without_receipt'
  when j.expires_at<=t then 'unknown'else 'pending'end;
 select coalesce(jsonb_agg(jsonb_build_object('attempt',d.attempt,'http_request_id',d.http_request_id::text,'dispatched_at',collect_ops.utc(d.dispatched_at),
  'evidence_revision',o.revision,'outcome',coalesce(o.outcome,'NOT_COLLECTED'),'transport_terminal',coalesce(o.transport_terminal,false),
  'http_status',o.http_status,'worker_error_code',o.worker_error_code,'response_rows_observed',o.response_rows_observed,
  'response_at',collect_ops.utc(o.response_at),'observed_at',collect_ops.utc(o.observed_at),'evidence_sha256',o.evidence_sha256)order by d.attempt),'[]'::jsonb)into rows
 from collect_ops.receipt_worker_dispatches d left join collect_ops.receipt_transport_heads h on h.http_request_id=d.http_request_id
 left join collect_ops.receipt_transport_observations o on o.http_request_id=h.http_request_id and o.revision=h.revision where d.request_id=p_request_id;
 select coalesce(o.outcome,'NOT_COLLECTED')into last_outcome from collect_ops.receipt_worker_dispatches d
 left join collect_ops.receipt_transport_heads h on h.http_request_id=d.http_request_id
 left join collect_ops.receipt_transport_observations o on o.http_request_id=h.http_request_id and o.revision=h.revision
 where d.request_id=p_request_id order by d.attempt desc limit 1;
 if last_outcome not in('HTTP_ACCEPTED','HTTP_PENDING')then alerts:=alerts||jsonb_build_array(last_outcome);end if;
 select count(*)into units from collect_ops.receipt_transport_inspections where quota_day=(t at time zone 'UTC')::date;
 if p.last_recorded_at is null then alerts:=alerts||jsonb_build_array('COLLECTOR_UNOBSERVED');
 elsif p.last_recorded_at<t-interval '180 seconds'then alerts:=alerts||jsonb_build_array('COLLECTOR_STALE');end if;
 if units>=c.day_inspections then alerts:=alerts||jsonb_build_array('COLLECTOR_QUOTA_EXHAUSTED');end if;
 if not collect_ops.receipt_transport_schema_valid()then alerts:=alerts||jsonb_build_array('SOURCE_SCHEMA_UNAVAILABLE');end if;
 perform collect_ops.actor(false);
 return jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),
  'original_status',state,'original_expires_at',collect_ops.utc(j.expires_at),'original_receipt_status',r.result->'status','scan_request_id',r.scan_request_id,
  'rows',rows,'alerts',alerts,'collector',jsonb_build_object('configuration_revision',c.revision,'last_request_id',p.last_request_id,
   'last_recorded_at',collect_ops.utc(p.last_recorded_at),'day_inspections',units,'day_cap',c.day_inspections,'quota_exhausted',units>=c.day_inspections,
   'source_schema_valid',collect_ops.receipt_transport_schema_valid()),'source_scan_complete',false,'financial_action',false,'send_action',false,'resend_action',false);
end$$;

revoke all on function collect_ops.receipt_transport_schema_valid(),collect_ops.receipt_transport_sample(bigint,uuid),
 collect_ops.reconcile_receipt_transport(uuid,integer,timestamptz),collect_ops.receipt_transport_base_schedule(),collect_ops.run_receipt_exception_schedule(),
 public.reconcile_receipt_worker_transport_v1(uuid,integer,timestamptz),public.get_receipt_worker_transport_request_v1(uuid),
 public.admin_get_receipt_worker_transport_v1(uuid)from public,anon,authenticated,service_role;
grant execute on function public.reconcile_receipt_worker_transport_v1(uuid,integer,timestamptz),public.get_receipt_worker_transport_request_v1(uuid)to service_role;
grant execute on function public.admin_get_receipt_worker_transport_v1(uuid)to authenticated;
commit;
