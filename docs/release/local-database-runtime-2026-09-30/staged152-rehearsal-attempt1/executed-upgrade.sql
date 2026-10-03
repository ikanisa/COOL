begin isolation level serializable;
    do $$begin if current_user<>'postgres' or current_database()<>'postgres'
      or (select rolsuper from pg_roles where rolname=current_user)
      or current_setting('cron.launch_active_jobs')<>'off' or current_setting('pg_net.batch_size')<>'0'
      or (select count(*) from supabase_migrations.schema_migrations)<>151
      or (select max(version) from supabase_migrations.schema_migrations)<>'20260930200000' then
      raise exception 'Exact offline sequential upgrade required';end if;end$$;
    create temp table collect_upgrade_rows(table_name text,rowdata jsonb,n bigint) on commit drop;
    create temp table collect_upgrade_counts(table_name text,n bigint) on commit drop;
    create temp table collect_upgrade_catalog on commit drop as with objects(family,object_name,identity,body) as (
      select 'schema',n.nspname::text,n.nspname::text,to_jsonb(n)-array['oid'] from pg_namespace n where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'relation',coalesce(tn.nspname||'.'||tc.relname,n.nspname||'.'||c.relname),n.nspname||'.'||c.relname,
        jsonb_build_object('owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'kind',c.relkind)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_index ix on ix.indexrelid=c.oid
        left join pg_class tc on tc.oid=ix.indrelid left join pg_namespace tn on tn.oid=tc.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'column',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||a.attname,
        jsonb_build_object('type',a.atttypid,'mod',a.atttypmod,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))
        from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
        where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations') and a.attnum>0 and not a.attisdropped
      union all select 'routine',n.nspname||'.'||p.proname,n.nspname||'.'||p.proname||':'||pg_get_function_identity_arguments(p.oid),
        jsonb_build_object('owner',p.proowner,'acl',p.proacl,'source',p.prosrc,'config',p.proconfig,'definer',p.prosecdef,'volatile',p.provolatile,'result',p.prorettype)
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'trigger',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||t.tgname,
        jsonb_build_object('enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))
        from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'constraint',n.nspname||'.'||cl.relname,n.nspname||'.'||cl.relname||':'||c.conname,to_jsonb(pg_get_constraintdef(c.oid))
        from pg_constraint c join pg_class cl on cl.oid=c.conrelid join pg_namespace n on n.oid=c.connamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'policy',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||p.polname,
        jsonb_build_object('roles',p.polroles,'command',p.polcmd,'permissive',p.polpermissive,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
        from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
    ) select * from objects;
    do $$begin if exists(select 1 from pg_temp.collect_upgrade_catalog group by family,identity having count(*)<>1)
      or exists(select 1 from pg_temp.collect_upgrade_catalog where identity is null or object_name is null) then
      raise exception 'Catalog identity collision';end if;end$$;
    do $$declare t record;begin
      for t in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations') and c.relkind in ('r','p') loop
        execute format('insert into pg_temp.collect_upgrade_rows select %L,to_jsonb(t),count(*) from %I.%I t group by to_jsonb(t)',t.nspname||'.'||t.relname,t.nspname,t.relname);
        execute format('insert into pg_temp.collect_upgrade_counts select %L,count(*) from %I.%I',t.nspname||'.'||t.relname,t.nspname,t.relname);
      end loop;
    end$$;
    

-- Manual operational telemetry only. No scheduler, provider action, receipt
-- claim, heartbeat, payment, ledger or notification-outbox mutation is added.
create table collect_security.shadow_supervisor_runs (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  actor_id uuid not null,
  session_id uuid not null,
  fence_version bigint not null unique check (fence_version between 1 and 1000000000),
  scope text not null default 'collect_platform' check (scope = 'collect_platform'),
  mode text not null default 'shadow' check (mode = 'shadow'),
  status text not null default 'running' check (status in ('running','completed','expired')),
  started_at timestamptz not null,
  lease_expires_at timestamptz not null,
  completed_at timestamptz,
  check (isfinite(started_at) and lease_expires_at = started_at + interval '120 seconds'),
  check ((status = 'completed' and completed_at is not null and isfinite(completed_at)
      and completed_at >= started_at and completed_at < lease_expires_at)
    or (status <> 'completed' and completed_at is null))
);
-- Actor/session identifiers deliberately have no cascading Auth foreign key.
create index shadow_supervisor_runs_history_idx
  on collect_security.shadow_supervisor_runs(started_at desc,id desc);

create table collect_security.shadow_supervisor_lease (
  id boolean primary key default true check (id),
  fence_version bigint not null default 0 check (fence_version between 0 and 1000000000),
  active_run_id uuid references collect_security.shadow_supervisor_runs(id) on delete restrict,
  lease_expires_at timestamptz,
  check ((active_run_id is null and lease_expires_at is null)
    or (active_run_id is not null and lease_expires_at is not null and isfinite(lease_expires_at)))
);
insert into collect_security.shadow_supervisor_lease(id) values(true);

create table collect_security.shadow_supervisor_samples (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null unique references collect_security.shadow_supervisor_runs(id) on delete restrict,
  checked_at timestamptz not null check (isfinite(checked_at)),
  body jsonb not null check (jsonb_typeof(body) = 'object' and octet_length(body::text) <= 65536),
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$')
);

alter table collect_security.shadow_supervisor_runs enable row level security;
alter table collect_security.shadow_supervisor_lease enable row level security;
alter table collect_security.shadow_supervisor_samples enable row level security;
revoke all on collect_security.shadow_supervisor_runs,
  collect_security.shadow_supervisor_lease,collect_security.shadow_supervisor_samples
  from public,anon,authenticated,service_role;

create function collect_security.require_shadow_actor() returns uuid
language plpgsql security definer set search_path='' as $$
declare sid uuid;
begin
  begin sid:=public._lock_notification_registration_session();
  exception when sqlstate '42501' then
    raise exception 'shadow_session_required' using errcode='42501';end;
  -- Match150: Auth/session -> roster serialization -> authority rows -> lease.
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  begin
    perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,
      'platform_owner',array['system_health.read','notifications.read']);
  exception when sqlstate '42501' then
    raise exception 'shadow_permission_required' using errcode='42501';end;
  return sid;
end $$;

create function collect_security.guard_shadow_sample() returns trigger
language plpgsql security definer set search_path='' as $$
begin raise exception 'shadow_history_immutable' using errcode='55000';end $$;
create trigger shadow_sample_immutable before update or delete
  on collect_security.shadow_supervisor_samples
  for each row execute function collect_security.guard_shadow_sample();

create function collect_security.guard_shadow_run() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_op='DELETE' or old.status<>'running'
    or new.status not in ('completed','expired')
    or (to_jsonb(new)-array['status','completed_at']) is distinct from
       (to_jsonb(old)-array['status','completed_at']) then
    raise exception 'shadow_history_immutable' using errcode='55000';end if;
  return new;
end $$;
create trigger shadow_run_transition before update or delete
  on collect_security.shadow_supervisor_runs
  for each row execute function collect_security.guard_shadow_run();

create function collect_security.shadow_run_json(p_run_id uuid,
  p_observed_at timestamptz default clock_timestamp()) returns jsonb
language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare r collect_security.shadow_supervisor_runs;
  s collect_security.shadow_supervisor_samples;
begin
  select * into r from collect_security.shadow_supervisor_runs where id=p_run_id;
  if r.id is null then return null;end if;
  select * into s from collect_security.shadow_supervisor_samples where run_id=r.id;
  if s.id is not null and s.content_sha256 is distinct from
    encode(extensions.digest(convert_to(s.body::text,'UTF8'),'sha256'),'hex') then
    raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  return jsonb_build_object('run_id',r.id,'request_id',r.request_id,
    'fence_version',r.fence_version,'status',case when r.status='running'
      and r.lease_expires_at<=p_observed_at then 'expired' else r.status end,
    'started_at',r.started_at,'lease_expires_at',r.lease_expires_at,
    'sampled_at',s.checked_at,'completed_at',r.completed_at,'summary',s.body->'summary');
end $$;

create function collect_security.require_shadow_health(p_health jsonb,
  p_started_at timestamptz,p_observed_at timestamptz) returns void
language plpgsql security definer set search_path='' as $$
declare checked timestamptz; expires timestamptz; canonical_alerts jsonb;
  allowed_keys text[]:=array['id','contract_version','database','auth','parser_pending_sms',
    'failed_sms_parse','unallocated_events','queued_notifications','processing_notifications',
    'failed_notifications','checked_at','metrics','alerts','health_status','sample_valid_until',
    'window_seconds','threshold_version','scheduler','evidence_limits'];
  metric_keys text[]:=array['push_due','push_failed','push_queued','sms_pending','reversals_24h',
    'push_retry_24h','sms_failed_24h','sms_parsed_24h','payments_review','push_failed_24h',
    'push_processing','push_attempts_24h','unallocated_events','finality_processing',
    'payments_posted_24h','push_expired_leases','push_latency_p95_ms','push_missing_leases',
    'reconciliation_open','durable_receipts_24h','push_due_age_seconds','receipt_rejected_24h',
    'finality_processed_24h','sms_pending_age_seconds','sms_expired_parse_leases',
    'push_provider_accepts_24h','receipt_ack_generated_24h','payment_review_age_seconds',
    'push_scheduler_age_seconds','receipt_ack_latency_mean_ms','receipt_telemetry_age_seconds'];
  nullable_metric_keys text[]:=array['push_latency_p95_ms','push_due_age_seconds',
    'sms_pending_age_seconds','payment_review_age_seconds','push_scheduler_age_seconds',
    'receipt_ack_latency_mean_ms','receipt_telemetry_age_seconds'];
  metric record;
begin
  if p_health is null or jsonb_typeof(p_health) is distinct from 'object'
    or p_health->'contract_version' is distinct from '1'::jsonb
    or jsonb_typeof(p_health->'alerts') is distinct from 'array'
    or jsonb_typeof(p_health->'metrics') is distinct from 'object'
    or jsonb_typeof(p_health->'checked_at') is distinct from 'string'
    or jsonb_typeof(p_health->'sample_valid_until') is distinct from 'string'
    or p_health->>'health_status' is null
    or p_health->>'health_status' not in ('ok','unknown','attention') then
    raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  if not (p_health->'metrics' ?& metric_keys)
    or (p_health->'metrics')-metric_keys<>'{}'::jsonb then
    raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  for metric in select key,value from jsonb_each(p_health->'metrics') loop
    if metric.value='null'::jsonb and metric.key=any(nullable_metric_keys) then continue;end if;
    if jsonb_typeof(metric.value) is distinct from 'number' then
      raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
    if metric.value::text !~ '^[0-9]+$' or metric.value::text::numeric>9007199254740991 then
      raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  end loop;
  if p_health->'parser_pending_sms' is distinct from p_health->'metrics'->'sms_pending'
    or p_health->'failed_sms_parse' is distinct from p_health->'metrics'->'sms_failed_24h'
    or p_health->'unallocated_events' is distinct from p_health->'metrics'->'unallocated_events'
    or p_health->'queued_notifications' is distinct from p_health->'metrics'->'push_queued'
    or p_health->'processing_notifications' is distinct from p_health->'metrics'->'push_processing'
    or p_health->'failed_notifications' is distinct from p_health->'metrics'->'push_failed' then
    raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  -- Enforce the existing redacted v1 surface before making durable evidence.
  -- Future accidental source fields must not become a receipt-data export.
  if not (p_health ?& allowed_keys) or p_health-allowed_keys<>'{}'::jsonb
    or p_health->>'id' is distinct from 'system'
    or p_health->>'database' is distinct from 'reachable'
    or p_health->>'auth' is distinct from 'authenticated'
    or p_health->'window_seconds' is distinct from '86400'::jsonb
    or p_health->'threshold_version' is distinct from '1'::jsonb
    or jsonb_typeof(p_health->'metrics') is distinct from 'object'
    or jsonb_typeof(p_health->'scheduler') is distinct from 'object'
    or (p_health->'scheduler')-array['state','configuration_verified']<>'{}'::jsonb
    or p_health->'scheduler'->'configuration_verified' is distinct from 'false'::jsonb
    or p_health->'scheduler'->>'state' is null
    or p_health->'scheduler'->>'state' not in ('unknown','enabled','disabled')
    or p_health->'evidence_limits' is distinct from jsonb_build_array(
      'ACK generation does not prove device receipt.',
      'Provider acceptance does not prove user delivery.',
      'Scheduler activation does not prove provider configuration.') then
    raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  if jsonb_array_length(p_health->'alerts')<>13 or exists(
    select 1 from jsonb_array_elements(p_health->'alerts') a
    where jsonb_typeof(a) is distinct from 'object' or a->>'state' is null
      or a->>'state' not in ('ok','unknown','attention','not_applicable')) then
    raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  begin canonical_alerts:=collect_security.operational_health_alerts(p_health->'metrics');
  exception when others then
    raise exception 'shadow_integrity_unavailable' using errcode='55000';end;
  if p_health->'alerts' is distinct from canonical_alerts
    or p_health->>'health_status' is distinct from (case
      when exists(select 1 from jsonb_array_elements(canonical_alerts) a where a->>'state'='attention') then 'attention'
      when exists(select 1 from jsonb_array_elements(canonical_alerts) a where a->>'state'='unknown') then 'unknown'
      else 'ok' end) then
    raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  begin
    checked:=(p_health->>'checked_at')::timestamptz;
    expires:=(p_health->>'sample_valid_until')::timestamptz;
  exception when others then
    raise exception 'shadow_integrity_unavailable' using errcode='55000';end;
  if checked is null or expires is null or not isfinite(checked) or not isfinite(expires)
    or expires<>checked+interval '60 seconds' or checked<p_started_at or checked>p_observed_at then
    raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  if expires<=p_observed_at then
    raise exception 'shadow_health_stale' using errcode='55000';end if;
end $$;

create function public.begin_collect_shadow_run_v1(p_request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare sid uuid; l collect_security.shadow_supervisor_lease;
  r collect_security.shadow_supervisor_runs; t timestamptz;
begin
  sid:=collect_security.require_shadow_actor();
  if p_request_id is null then raise exception 'shadow_request_invalid' using errcode='22023';end if;
  -- A physical same-value write serializes quota/idempotency decisions, including
  -- established Repeatable Read snapshots, which receive40001 after a writer.
  update collect_security.shadow_supervisor_lease set fence_version=fence_version
    where id returning * into l;
  if l.id is null then raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  t:=clock_timestamp();
  select * into r from collect_security.shadow_supervisor_runs where request_id=p_request_id;
  if r.id is not null then
    if r.actor_id is distinct from auth.uid() or r.session_id is distinct from sid then
      raise exception 'shadow_request_conflict' using errcode='40001';end if;
    return jsonb_build_object('contract_version',1,'mode','shadow','scope','collect_platform',
      'ok',true,'outcome','replayed','replayed',true,'run',collect_security.shadow_run_json(r.id));
  end if;
  if l.active_run_id is not null and l.lease_expires_at>t then
    return jsonb_build_object('contract_version',1,'mode','shadow','scope','collect_platform',
      'ok',false,'outcome','busy','reason_code','shadow_run_busy','request_id',p_request_id,
      'retry_after_seconds',greatest(1,least(120,ceil(extract(epoch from l.lease_expires_at-t))::integer)));
  end if;
  if (select count(*) from collect_security.shadow_supervisor_runs
      where started_at>t-interval '1 hour')>=60 then
    raise exception 'shadow_limit_reached' using errcode='55000';end if;
  if l.fence_version>=1000000000 then raise exception 'shadow_limit_reached' using errcode='55000';end if;
  if l.active_run_id is not null then
    update collect_security.shadow_supervisor_runs set status='expired'
      where id=l.active_run_id and status='running';
  end if;
  insert into collect_security.shadow_supervisor_runs(request_id,actor_id,session_id,
    fence_version,started_at,lease_expires_at)
  values(p_request_id,auth.uid(),sid,l.fence_version+1,t,t+interval '120 seconds')
  returning * into r;
  update collect_security.shadow_supervisor_lease set fence_version=r.fence_version,
    active_run_id=r.id,lease_expires_at=r.lease_expires_at where id;
  return jsonb_build_object('contract_version',1,'mode','shadow','scope','collect_platform',
    'ok',true,'outcome','started','replayed',false,'run',collect_security.shadow_run_json(r.id));
end $$;

create function public.sample_collect_shadow_run_v1(p_run_id uuid,p_fence_version bigint) returns jsonb
language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare sid uuid; l collect_security.shadow_supervisor_lease;
  r collect_security.shadow_supervisor_runs; s collect_security.shadow_supervisor_samples;
  t timestamptz; health jsonb; sms jsonb; counts jsonb; summary jsonb; body jsonb;
begin
  sid:=collect_security.require_shadow_actor();
  if p_run_id is null or p_fence_version is null or p_fence_version not between 1 and 1000000000 then
    raise exception 'shadow_request_invalid' using errcode='22023';end if;
  -- A manual health sample must use current statement snapshots, not an older
  -- caller-created Repeatable Read view presented with a fresh checked_at.
  if current_setting('transaction_isolation')<>'read committed' then
    raise exception 'shadow_snapshot_retry' using errcode='40001';end if;
  select * into l from collect_security.shadow_supervisor_lease where id for update;
  select * into r from collect_security.shadow_supervisor_runs where id=p_run_id for update;
  if r.id is null or r.actor_id is distinct from auth.uid() or r.session_id is distinct from sid then
    raise exception 'shadow_run_unavailable' using errcode='42501';end if;
  if r.fence_version<>p_fence_version or l.active_run_id is distinct from r.id
    or l.fence_version<>p_fence_version or r.status<>'running' then
    raise exception 'shadow_fence_lost' using errcode='40001';end if;
  if r.lease_expires_at<=clock_timestamp() or l.lease_expires_at<=clock_timestamp() then
    raise exception 'shadow_lease_expired' using errcode='55000';end if;
  select * into s from collect_security.shadow_supervisor_samples where run_id=r.id;
  if s.id is not null then
    perform collect_security.shadow_run_json(r.id);
    perform collect_security.require_shadow_health(s.body->'system_health',r.started_at,clock_timestamp());
    return jsonb_build_object('contract_version',1,'mode','shadow','scope','collect_platform',
      'ok',true,'outcome','sampled','replayed',true,'run_id',r.id,'fence_version',r.fence_version,
      'sample',s.body||jsonb_build_object('sample_id',s.id,'content_sha256',s.content_sha256));
  end if;
  health:=public.admin_system_health('system');
  t:=clock_timestamp();
  perform collect_security.require_shadow_health(health,r.started_at,t);
  -- Same aggregate semantics as the assisted operator's health, without its
  -- service-only identity wrapper, full destinations, bodies or receipt IDs.
  select jsonb_build_object('enabled',coalesce((select enabled from public.feature_flags
    where key='hybrid_sms_notifications'),false),
    'queued',count(*) filter(where state='queued'),
    'awaiting_confirmation',count(*) filter(where state='awaiting_confirmation'),
    'send_started',count(*) filter(where state='send_started'),
    'uncertain',count(*) filter(where state='uncertain'),
    'suppressed',count(*) filter(where state='suppressed'),
    'oldest_queued_at',min(created_at) filter(where state='queued'),
    'active_workers',(select count(*) from collect_hybrid.sms_operator_heartbeats
      where observed_at>t-interval '3 minutes'),'observed_at',t)
  into sms from collect_hybrid.sms_notification_outbox;
  select jsonb_build_object('ok',count(*) filter(where a->>'state'='ok'),
    'unknown',count(*) filter(where a->>'state'='unknown'),
    'attention',count(*) filter(where a->>'state'='attention'),
    'not_applicable',count(*) filter(where a->>'state'='not_applicable'))
  into counts from jsonb_array_elements(health->'alerts') a;
  summary:=jsonb_build_object('health_status',case when health->>'health_status'='attention'
    or (sms->>'uncertain')::bigint>0 or (sms->>'send_started')::bigint>0 then 'attention'
    else health->>'health_status' end,'alert_counts',counts,
    'sms_queue',sms-array['oldest_queued_at','observed_at'],
    'checks_recorded',13,'samples_recorded',1,'business_mutations',0,'provider_sends',0);
  t:=clock_timestamp();
  if r.lease_expires_at<=t or l.lease_expires_at<=t then
    raise exception 'shadow_lease_expired' using errcode='55000';end if;
  perform collect_security.require_shadow_health(health,r.started_at,t);
  body:=jsonb_build_object('checked_at',t,'system_health',health,'sms_queue',sms,'summary',summary);
  insert into collect_security.shadow_supervisor_samples(run_id,checked_at,body,content_sha256)
  values(r.id,t,body,encode(extensions.digest(convert_to(body::text,'UTF8'),'sha256'),'hex'))
  returning * into s;
  return jsonb_build_object('contract_version',1,'mode','shadow','scope','collect_platform',
    'ok',true,'outcome','sampled','replayed',false,'run_id',r.id,'fence_version',r.fence_version,
    'sample',s.body||jsonb_build_object('sample_id',s.id,'content_sha256',s.content_sha256));
end $$;

create function public.finish_collect_shadow_run_v1(p_run_id uuid,p_fence_version bigint) returns jsonb
language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare sid uuid; l collect_security.shadow_supervisor_lease;
  r collect_security.shadow_supervisor_runs; s collect_security.shadow_supervisor_samples; t timestamptz;
begin
  sid:=collect_security.require_shadow_actor();
  if p_run_id is null or p_fence_version is null or p_fence_version not between 1 and 1000000000 then
    raise exception 'shadow_request_invalid' using errcode='22023';end if;
  select * into l from collect_security.shadow_supervisor_lease where id for update;
  select * into r from collect_security.shadow_supervisor_runs where id=p_run_id for update;
  if r.id is null or r.actor_id is distinct from auth.uid() or r.session_id is distinct from sid then
    raise exception 'shadow_run_unavailable' using errcode='42501';end if;
  if r.fence_version<>p_fence_version then raise exception 'shadow_fence_lost' using errcode='40001';end if;
  if r.status='completed' then
    return jsonb_build_object('contract_version',1,'mode','shadow','scope','collect_platform',
      'ok',true,'outcome','completed','replayed',true,'run',collect_security.shadow_run_json(r.id));
  end if;
  if l.active_run_id is distinct from r.id or l.fence_version<>p_fence_version or r.status<>'running' then
    raise exception 'shadow_fence_lost' using errcode='40001';end if;
  t:=clock_timestamp();
  if r.lease_expires_at<=t or l.lease_expires_at<=t then
    raise exception 'shadow_lease_expired' using errcode='55000';end if;
  select * into s from collect_security.shadow_supervisor_samples where run_id=r.id;
  if s.id is null then
    raise exception 'shadow_sample_required' using errcode='55000';end if;
  perform collect_security.shadow_run_json(r.id);
  perform collect_security.require_shadow_health(s.body->'system_health',r.started_at,t);
  update collect_security.shadow_supervisor_runs set status='completed',completed_at=t where id=r.id;
  update collect_security.shadow_supervisor_lease set active_run_id=null,lease_expires_at=null where id;
  return jsonb_build_object('contract_version',1,'mode','shadow','scope','collect_platform',
    'ok',true,'outcome','completed','replayed',false,'run',collect_security.shadow_run_json(r.id));
end $$;

create function public.get_collect_shadow_run_v1(p_request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare r collect_security.shadow_supervisor_runs;
begin
  perform collect_security.require_shadow_actor();
  if p_request_id is null then raise exception 'shadow_request_invalid' using errcode='22023';end if;
  -- Read-only reconciliation after normal reauthentication never resumes the
  -- previous session's lease. Only the original actor sees this request lookup.
  select * into r from collect_security.shadow_supervisor_runs
    where request_id=p_request_id and actor_id=auth.uid();
  return jsonb_build_object('contract_version',1,'mode','shadow','scope','collect_platform',
    'found',r.id is not null,'run',collect_security.shadow_run_json(r.id));
end $$;

create function public.list_collect_shadow_runs_v1(p_limit integer default 20,
  p_before_started_at timestamptz default null,p_before_run_id uuid default null) returns jsonb
language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare l collect_security.shadow_supervisor_lease; t timestamptz;
  rows jsonb; cursor jsonb; more boolean; total bigint;
begin
  perform collect_security.require_shadow_actor();
  if p_limit is null or p_limit not between 1 and 50
    or (p_before_started_at is null)<>(p_before_run_id is null)
    or p_before_started_at is not null and not isfinite(p_before_started_at) then
    raise exception 'shadow_request_invalid' using errcode='22023';end if;
  select * into l from collect_security.shadow_supervisor_lease where id for share;
  if l.id is null then raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  t:=clock_timestamp();
  select count(*) into total from collect_security.shadow_supervisor_runs;
  with candidates as materialized (
    select id,started_at from collect_security.shadow_supervisor_runs
    where p_before_started_at is null or (started_at,id)<(p_before_started_at,p_before_run_id)
    order by started_at desc,id desc limit p_limit+1
  ), page as materialized (
    select * from candidates order by started_at desc,id desc limit p_limit
  ) select coalesce((select jsonb_agg(collect_security.shadow_run_json(id,t)
      order by started_at desc,id desc) from page),'[]'::jsonb),
    (select count(*)>p_limit from candidates),
    (select jsonb_build_object('started_at',started_at,'run_id',id)
      from page order by started_at,id limit 1)
  into rows,more,cursor;
  return jsonb_build_object('contract_version',1,'mode','shadow','scope','collect_platform',
    'checked_at',t,'lease',jsonb_build_object('state',case when l.active_run_id is null
      then 'idle' when l.lease_expires_at<=t then 'expired' else 'active' end,
      'fence_version',l.fence_version,'active_run_id',l.active_run_id,'lease_expires_at',l.lease_expires_at),
    'rows',rows,'total',total,'next_cursor',case when more then cursor else null end);
end $$;

revoke all on function collect_security.require_shadow_actor(),
  collect_security.guard_shadow_sample(),collect_security.guard_shadow_run(),
  collect_security.shadow_run_json(uuid,timestamptz),
  collect_security.require_shadow_health(jsonb,timestamptz,timestamptz)
  from public,anon,authenticated,service_role;
revoke all on function public.begin_collect_shadow_run_v1(uuid),
  public.sample_collect_shadow_run_v1(uuid,bigint),public.finish_collect_shadow_run_v1(uuid,bigint),
  public.get_collect_shadow_run_v1(uuid),public.list_collect_shadow_runs_v1(integer,timestamptz,uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.begin_collect_shadow_run_v1(uuid),
  public.sample_collect_shadow_run_v1(uuid,bigint),public.finish_collect_shadow_run_v1(uuid,bigint),
  public.get_collect_shadow_run_v1(uuid),public.list_collect_shadow_runs_v1(integer,timestamptz,uuid)
  to authenticated;

comment on table collect_security.shadow_supervisor_runs is
  'Manual platform-scoped shadow monitoring telemetry; completion does not attest Codex execution or SMS delivery.';
comment on function public.sample_collect_shadow_run_v1(uuid,bigint) is
  'Stores one immutable server-derived redacted health and assisted-SMS aggregate sample; never mutates business or sending state.';
notify pgrst,'reload schema';

    insert into supabase_migrations.schema_migrations(version,name,statements)
      values('20260930210000','shadow_supervisor_runs',array['begin;

-- Manual operational telemetry only. No scheduler, provider action, receipt
-- claim, heartbeat, payment, ledger or notification-outbox mutation is added.
create table collect_security.shadow_supervisor_runs (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  actor_id uuid not null,
  session_id uuid not null,
  fence_version bigint not null unique check (fence_version between 1 and 1000000000),
  scope text not null default ''collect_platform'' check (scope = ''collect_platform''),
  mode text not null default ''shadow'' check (mode = ''shadow''),
  status text not null default ''running'' check (status in (''running'',''completed'',''expired'')),
  started_at timestamptz not null,
  lease_expires_at timestamptz not null,
  completed_at timestamptz,
  check (isfinite(started_at) and lease_expires_at = started_at + interval ''120 seconds''),
  check ((status = ''completed'' and completed_at is not null and isfinite(completed_at)
      and completed_at >= started_at and completed_at < lease_expires_at)
    or (status <> ''completed'' and completed_at is null))
);
-- Actor/session identifiers deliberately have no cascading Auth foreign key.
create index shadow_supervisor_runs_history_idx
  on collect_security.shadow_supervisor_runs(started_at desc,id desc);

create table collect_security.shadow_supervisor_lease (
  id boolean primary key default true check (id),
  fence_version bigint not null default 0 check (fence_version between 0 and 1000000000),
  active_run_id uuid references collect_security.shadow_supervisor_runs(id) on delete restrict,
  lease_expires_at timestamptz,
  check ((active_run_id is null and lease_expires_at is null)
    or (active_run_id is not null and lease_expires_at is not null and isfinite(lease_expires_at)))
);
insert into collect_security.shadow_supervisor_lease(id) values(true);

create table collect_security.shadow_supervisor_samples (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null unique references collect_security.shadow_supervisor_runs(id) on delete restrict,
  checked_at timestamptz not null check (isfinite(checked_at)),
  body jsonb not null check (jsonb_typeof(body) = ''object'' and octet_length(body::text) <= 65536),
  content_sha256 text not null check (content_sha256 ~ ''^[a-f0-9]{64}$'')
);

alter table collect_security.shadow_supervisor_runs enable row level security;
alter table collect_security.shadow_supervisor_lease enable row level security;
alter table collect_security.shadow_supervisor_samples enable row level security;
revoke all on collect_security.shadow_supervisor_runs,
  collect_security.shadow_supervisor_lease,collect_security.shadow_supervisor_samples
  from public,anon,authenticated,service_role;

create function collect_security.require_shadow_actor() returns uuid
language plpgsql security definer set search_path='''' as $$
declare sid uuid;
begin
  begin sid:=public._lock_notification_registration_session();
  exception when sqlstate ''42501'' then
    raise exception ''shadow_session_required'' using errcode=''42501'';end;
  -- Match150: Auth/session -> roster serialization -> authority rows -> lease.
  perform pg_advisory_xact_lock(hashtext(''collect_admin_combined_roster''));
  begin
    perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,
      ''platform_owner'',array[''system_health.read'',''notifications.read'']);
  exception when sqlstate ''42501'' then
    raise exception ''shadow_permission_required'' using errcode=''42501'';end;
  return sid;
end $$;

create function collect_security.guard_shadow_sample() returns trigger
language plpgsql security definer set search_path='''' as $$
begin raise exception ''shadow_history_immutable'' using errcode=''55000'';end $$;
create trigger shadow_sample_immutable before update or delete
  on collect_security.shadow_supervisor_samples
  for each row execute function collect_security.guard_shadow_sample();

create function collect_security.guard_shadow_run() returns trigger
language plpgsql security definer set search_path='''' as $$
begin
  if tg_op=''DELETE'' or old.status<>''running''
    or new.status not in (''completed'',''expired'')
    or (to_jsonb(new)-array[''status'',''completed_at'']) is distinct from
       (to_jsonb(old)-array[''status'',''completed_at'']) then
    raise exception ''shadow_history_immutable'' using errcode=''55000'';end if;
  return new;
end $$;
create trigger shadow_run_transition before update or delete
  on collect_security.shadow_supervisor_runs
  for each row execute function collect_security.guard_shadow_run();

create function collect_security.shadow_run_json(p_run_id uuid,
  p_observed_at timestamptz default clock_timestamp()) returns jsonb
language plpgsql volatile security definer set search_path='''' set timezone=''UTC'' as $$
declare r collect_security.shadow_supervisor_runs;
  s collect_security.shadow_supervisor_samples;
begin
  select * into r from collect_security.shadow_supervisor_runs where id=p_run_id;
  if r.id is null then return null;end if;
  select * into s from collect_security.shadow_supervisor_samples where run_id=r.id;
  if s.id is not null and s.content_sha256 is distinct from
    encode(extensions.digest(convert_to(s.body::text,''UTF8''),''sha256''),''hex'') then
    raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
  return jsonb_build_object(''run_id'',r.id,''request_id'',r.request_id,
    ''fence_version'',r.fence_version,''status'',case when r.status=''running''
      and r.lease_expires_at<=p_observed_at then ''expired'' else r.status end,
    ''started_at'',r.started_at,''lease_expires_at'',r.lease_expires_at,
    ''sampled_at'',s.checked_at,''completed_at'',r.completed_at,''summary'',s.body->''summary'');
end $$;

create function collect_security.require_shadow_health(p_health jsonb,
  p_started_at timestamptz,p_observed_at timestamptz) returns void
language plpgsql security definer set search_path='''' as $$
declare checked timestamptz; expires timestamptz; canonical_alerts jsonb;
  allowed_keys text[]:=array[''id'',''contract_version'',''database'',''auth'',''parser_pending_sms'',
    ''failed_sms_parse'',''unallocated_events'',''queued_notifications'',''processing_notifications'',
    ''failed_notifications'',''checked_at'',''metrics'',''alerts'',''health_status'',''sample_valid_until'',
    ''window_seconds'',''threshold_version'',''scheduler'',''evidence_limits''];
  metric_keys text[]:=array[''push_due'',''push_failed'',''push_queued'',''sms_pending'',''reversals_24h'',
    ''push_retry_24h'',''sms_failed_24h'',''sms_parsed_24h'',''payments_review'',''push_failed_24h'',
    ''push_processing'',''push_attempts_24h'',''unallocated_events'',''finality_processing'',
    ''payments_posted_24h'',''push_expired_leases'',''push_latency_p95_ms'',''push_missing_leases'',
    ''reconciliation_open'',''durable_receipts_24h'',''push_due_age_seconds'',''receipt_rejected_24h'',
    ''finality_processed_24h'',''sms_pending_age_seconds'',''sms_expired_parse_leases'',
    ''push_provider_accepts_24h'',''receipt_ack_generated_24h'',''payment_review_age_seconds'',
    ''push_scheduler_age_seconds'',''receipt_ack_latency_mean_ms'',''receipt_telemetry_age_seconds''];
  nullable_metric_keys text[]:=array[''push_latency_p95_ms'',''push_due_age_seconds'',
    ''sms_pending_age_seconds'',''payment_review_age_seconds'',''push_scheduler_age_seconds'',
    ''receipt_ack_latency_mean_ms'',''receipt_telemetry_age_seconds''];
  metric record;
begin
  if p_health is null or jsonb_typeof(p_health) is distinct from ''object''
    or p_health->''contract_version'' is distinct from ''1''::jsonb
    or jsonb_typeof(p_health->''alerts'') is distinct from ''array''
    or jsonb_typeof(p_health->''metrics'') is distinct from ''object''
    or jsonb_typeof(p_health->''checked_at'') is distinct from ''string''
    or jsonb_typeof(p_health->''sample_valid_until'') is distinct from ''string''
    or p_health->>''health_status'' is null
    or p_health->>''health_status'' not in (''ok'',''unknown'',''attention'') then
    raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
  if not (p_health->''metrics'' ?& metric_keys)
    or (p_health->''metrics'')-metric_keys<>''{}''::jsonb then
    raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
  for metric in select key,value from jsonb_each(p_health->''metrics'') loop
    if metric.value=''null''::jsonb and metric.key=any(nullable_metric_keys) then continue;end if;
    if jsonb_typeof(metric.value) is distinct from ''number'' then
      raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
    if metric.value::text !~ ''^[0-9]+$'' or metric.value::text::numeric>9007199254740991 then
      raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
  end loop;
  if p_health->''parser_pending_sms'' is distinct from p_health->''metrics''->''sms_pending''
    or p_health->''failed_sms_parse'' is distinct from p_health->''metrics''->''sms_failed_24h''
    or p_health->''unallocated_events'' is distinct from p_health->''metrics''->''unallocated_events''
    or p_health->''queued_notifications'' is distinct from p_health->''metrics''->''push_queued''
    or p_health->''processing_notifications'' is distinct from p_health->''metrics''->''push_processing''
    or p_health->''failed_notifications'' is distinct from p_health->''metrics''->''push_failed'' then
    raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
  -- Enforce the existing redacted v1 surface before making durable evidence.
  -- Future accidental source fields must not become a receipt-data export.
  if not (p_health ?& allowed_keys) or p_health-allowed_keys<>''{}''::jsonb
    or p_health->>''id'' is distinct from ''system''
    or p_health->>''database'' is distinct from ''reachable''
    or p_health->>''auth'' is distinct from ''authenticated''
    or p_health->''window_seconds'' is distinct from ''86400''::jsonb
    or p_health->''threshold_version'' is distinct from ''1''::jsonb
    or jsonb_typeof(p_health->''metrics'') is distinct from ''object''
    or jsonb_typeof(p_health->''scheduler'') is distinct from ''object''
    or (p_health->''scheduler'')-array[''state'',''configuration_verified'']<>''{}''::jsonb
    or p_health->''scheduler''->''configuration_verified'' is distinct from ''false''::jsonb
    or p_health->''scheduler''->>''state'' is null
    or p_health->''scheduler''->>''state'' not in (''unknown'',''enabled'',''disabled'')
    or p_health->''evidence_limits'' is distinct from jsonb_build_array(
      ''ACK generation does not prove device receipt.'',
      ''Provider acceptance does not prove user delivery.'',
      ''Scheduler activation does not prove provider configuration.'') then
    raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
  if jsonb_array_length(p_health->''alerts'')<>13 or exists(
    select 1 from jsonb_array_elements(p_health->''alerts'') a
    where jsonb_typeof(a) is distinct from ''object'' or a->>''state'' is null
      or a->>''state'' not in (''ok'',''unknown'',''attention'',''not_applicable'')) then
    raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
  begin canonical_alerts:=collect_security.operational_health_alerts(p_health->''metrics'');
  exception when others then
    raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end;
  if p_health->''alerts'' is distinct from canonical_alerts
    or p_health->>''health_status'' is distinct from (case
      when exists(select 1 from jsonb_array_elements(canonical_alerts) a where a->>''state''=''attention'') then ''attention''
      when exists(select 1 from jsonb_array_elements(canonical_alerts) a where a->>''state''=''unknown'') then ''unknown''
      else ''ok'' end) then
    raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
  begin
    checked:=(p_health->>''checked_at'')::timestamptz;
    expires:=(p_health->>''sample_valid_until'')::timestamptz;
  exception when others then
    raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end;
  if checked is null or expires is null or not isfinite(checked) or not isfinite(expires)
    or expires<>checked+interval ''60 seconds'' or checked<p_started_at or checked>p_observed_at then
    raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
  if expires<=p_observed_at then
    raise exception ''shadow_health_stale'' using errcode=''55000'';end if;
end $$;

create function public.begin_collect_shadow_run_v1(p_request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='''' set timezone=''UTC'' as $$
declare sid uuid; l collect_security.shadow_supervisor_lease;
  r collect_security.shadow_supervisor_runs; t timestamptz;
begin
  sid:=collect_security.require_shadow_actor();
  if p_request_id is null then raise exception ''shadow_request_invalid'' using errcode=''22023'';end if;
  -- A physical same-value write serializes quota/idempotency decisions, including
  -- established Repeatable Read snapshots, which receive40001 after a writer.
  update collect_security.shadow_supervisor_lease set fence_version=fence_version
    where id returning * into l;
  if l.id is null then raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
  t:=clock_timestamp();
  select * into r from collect_security.shadow_supervisor_runs where request_id=p_request_id;
  if r.id is not null then
    if r.actor_id is distinct from auth.uid() or r.session_id is distinct from sid then
      raise exception ''shadow_request_conflict'' using errcode=''40001'';end if;
    return jsonb_build_object(''contract_version'',1,''mode'',''shadow'',''scope'',''collect_platform'',
      ''ok'',true,''outcome'',''replayed'',''replayed'',true,''run'',collect_security.shadow_run_json(r.id));
  end if;
  if l.active_run_id is not null and l.lease_expires_at>t then
    return jsonb_build_object(''contract_version'',1,''mode'',''shadow'',''scope'',''collect_platform'',
      ''ok'',false,''outcome'',''busy'',''reason_code'',''shadow_run_busy'',''request_id'',p_request_id,
      ''retry_after_seconds'',greatest(1,least(120,ceil(extract(epoch from l.lease_expires_at-t))::integer)));
  end if;
  if (select count(*) from collect_security.shadow_supervisor_runs
      where started_at>t-interval ''1 hour'')>=60 then
    raise exception ''shadow_limit_reached'' using errcode=''55000'';end if;
  if l.fence_version>=1000000000 then raise exception ''shadow_limit_reached'' using errcode=''55000'';end if;
  if l.active_run_id is not null then
    update collect_security.shadow_supervisor_runs set status=''expired''
      where id=l.active_run_id and status=''running'';
  end if;
  insert into collect_security.shadow_supervisor_runs(request_id,actor_id,session_id,
    fence_version,started_at,lease_expires_at)
  values(p_request_id,auth.uid(),sid,l.fence_version+1,t,t+interval ''120 seconds'')
  returning * into r;
  update collect_security.shadow_supervisor_lease set fence_version=r.fence_version,
    active_run_id=r.id,lease_expires_at=r.lease_expires_at where id;
  return jsonb_build_object(''contract_version'',1,''mode'',''shadow'',''scope'',''collect_platform'',
    ''ok'',true,''outcome'',''started'',''replayed'',false,''run'',collect_security.shadow_run_json(r.id));
end $$;

create function public.sample_collect_shadow_run_v1(p_run_id uuid,p_fence_version bigint) returns jsonb
language plpgsql volatile security definer set search_path='''' set timezone=''UTC'' as $$
declare sid uuid; l collect_security.shadow_supervisor_lease;
  r collect_security.shadow_supervisor_runs; s collect_security.shadow_supervisor_samples;
  t timestamptz; health jsonb; sms jsonb; counts jsonb; summary jsonb; body jsonb;
begin
  sid:=collect_security.require_shadow_actor();
  if p_run_id is null or p_fence_version is null or p_fence_version not between 1 and 1000000000 then
    raise exception ''shadow_request_invalid'' using errcode=''22023'';end if;
  -- A manual health sample must use current statement snapshots, not an older
  -- caller-created Repeatable Read view presented with a fresh checked_at.
  if current_setting(''transaction_isolation'')<>''read committed'' then
    raise exception ''shadow_snapshot_retry'' using errcode=''40001'';end if;
  select * into l from collect_security.shadow_supervisor_lease where id for update;
  select * into r from collect_security.shadow_supervisor_runs where id=p_run_id for update;
  if r.id is null or r.actor_id is distinct from auth.uid() or r.session_id is distinct from sid then
    raise exception ''shadow_run_unavailable'' using errcode=''42501'';end if;
  if r.fence_version<>p_fence_version or l.active_run_id is distinct from r.id
    or l.fence_version<>p_fence_version or r.status<>''running'' then
    raise exception ''shadow_fence_lost'' using errcode=''40001'';end if;
  if r.lease_expires_at<=clock_timestamp() or l.lease_expires_at<=clock_timestamp() then
    raise exception ''shadow_lease_expired'' using errcode=''55000'';end if;
  select * into s from collect_security.shadow_supervisor_samples where run_id=r.id;
  if s.id is not null then
    perform collect_security.shadow_run_json(r.id);
    perform collect_security.require_shadow_health(s.body->''system_health'',r.started_at,clock_timestamp());
    return jsonb_build_object(''contract_version'',1,''mode'',''shadow'',''scope'',''collect_platform'',
      ''ok'',true,''outcome'',''sampled'',''replayed'',true,''run_id'',r.id,''fence_version'',r.fence_version,
      ''sample'',s.body||jsonb_build_object(''sample_id'',s.id,''content_sha256'',s.content_sha256));
  end if;
  health:=public.admin_system_health(''system'');
  t:=clock_timestamp();
  perform collect_security.require_shadow_health(health,r.started_at,t);
  -- Same aggregate semantics as the assisted operator''s health, without its
  -- service-only identity wrapper, full destinations, bodies or receipt IDs.
  select jsonb_build_object(''enabled'',coalesce((select enabled from public.feature_flags
    where key=''hybrid_sms_notifications''),false),
    ''queued'',count(*) filter(where state=''queued''),
    ''awaiting_confirmation'',count(*) filter(where state=''awaiting_confirmation''),
    ''send_started'',count(*) filter(where state=''send_started''),
    ''uncertain'',count(*) filter(where state=''uncertain''),
    ''suppressed'',count(*) filter(where state=''suppressed''),
    ''oldest_queued_at'',min(created_at) filter(where state=''queued''),
    ''active_workers'',(select count(*) from collect_hybrid.sms_operator_heartbeats
      where observed_at>t-interval ''3 minutes''),''observed_at'',t)
  into sms from collect_hybrid.sms_notification_outbox;
  select jsonb_build_object(''ok'',count(*) filter(where a->>''state''=''ok''),
    ''unknown'',count(*) filter(where a->>''state''=''unknown''),
    ''attention'',count(*) filter(where a->>''state''=''attention''),
    ''not_applicable'',count(*) filter(where a->>''state''=''not_applicable''))
  into counts from jsonb_array_elements(health->''alerts'') a;
  summary:=jsonb_build_object(''health_status'',case when health->>''health_status''=''attention''
    or (sms->>''uncertain'')::bigint>0 or (sms->>''send_started'')::bigint>0 then ''attention''
    else health->>''health_status'' end,''alert_counts'',counts,
    ''sms_queue'',sms-array[''oldest_queued_at'',''observed_at''],
    ''checks_recorded'',13,''samples_recorded'',1,''business_mutations'',0,''provider_sends'',0);
  t:=clock_timestamp();
  if r.lease_expires_at<=t or l.lease_expires_at<=t then
    raise exception ''shadow_lease_expired'' using errcode=''55000'';end if;
  perform collect_security.require_shadow_health(health,r.started_at,t);
  body:=jsonb_build_object(''checked_at'',t,''system_health'',health,''sms_queue'',sms,''summary'',summary);
  insert into collect_security.shadow_supervisor_samples(run_id,checked_at,body,content_sha256)
  values(r.id,t,body,encode(extensions.digest(convert_to(body::text,''UTF8''),''sha256''),''hex''))
  returning * into s;
  return jsonb_build_object(''contract_version'',1,''mode'',''shadow'',''scope'',''collect_platform'',
    ''ok'',true,''outcome'',''sampled'',''replayed'',false,''run_id'',r.id,''fence_version'',r.fence_version,
    ''sample'',s.body||jsonb_build_object(''sample_id'',s.id,''content_sha256'',s.content_sha256));
end $$;

create function public.finish_collect_shadow_run_v1(p_run_id uuid,p_fence_version bigint) returns jsonb
language plpgsql volatile security definer set search_path='''' set timezone=''UTC'' as $$
declare sid uuid; l collect_security.shadow_supervisor_lease;
  r collect_security.shadow_supervisor_runs; s collect_security.shadow_supervisor_samples; t timestamptz;
begin
  sid:=collect_security.require_shadow_actor();
  if p_run_id is null or p_fence_version is null or p_fence_version not between 1 and 1000000000 then
    raise exception ''shadow_request_invalid'' using errcode=''22023'';end if;
  select * into l from collect_security.shadow_supervisor_lease where id for update;
  select * into r from collect_security.shadow_supervisor_runs where id=p_run_id for update;
  if r.id is null or r.actor_id is distinct from auth.uid() or r.session_id is distinct from sid then
    raise exception ''shadow_run_unavailable'' using errcode=''42501'';end if;
  if r.fence_version<>p_fence_version then raise exception ''shadow_fence_lost'' using errcode=''40001'';end if;
  if r.status=''completed'' then
    return jsonb_build_object(''contract_version'',1,''mode'',''shadow'',''scope'',''collect_platform'',
      ''ok'',true,''outcome'',''completed'',''replayed'',true,''run'',collect_security.shadow_run_json(r.id));
  end if;
  if l.active_run_id is distinct from r.id or l.fence_version<>p_fence_version or r.status<>''running'' then
    raise exception ''shadow_fence_lost'' using errcode=''40001'';end if;
  t:=clock_timestamp();
  if r.lease_expires_at<=t or l.lease_expires_at<=t then
    raise exception ''shadow_lease_expired'' using errcode=''55000'';end if;
  select * into s from collect_security.shadow_supervisor_samples where run_id=r.id;
  if s.id is null then
    raise exception ''shadow_sample_required'' using errcode=''55000'';end if;
  perform collect_security.shadow_run_json(r.id);
  perform collect_security.require_shadow_health(s.body->''system_health'',r.started_at,t);
  update collect_security.shadow_supervisor_runs set status=''completed'',completed_at=t where id=r.id;
  update collect_security.shadow_supervisor_lease set active_run_id=null,lease_expires_at=null where id;
  return jsonb_build_object(''contract_version'',1,''mode'',''shadow'',''scope'',''collect_platform'',
    ''ok'',true,''outcome'',''completed'',''replayed'',false,''run'',collect_security.shadow_run_json(r.id));
end $$;

create function public.get_collect_shadow_run_v1(p_request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='''' set timezone=''UTC'' as $$
declare r collect_security.shadow_supervisor_runs;
begin
  perform collect_security.require_shadow_actor();
  if p_request_id is null then raise exception ''shadow_request_invalid'' using errcode=''22023'';end if;
  -- Read-only reconciliation after normal reauthentication never resumes the
  -- previous session''s lease. Only the original actor sees this request lookup.
  select * into r from collect_security.shadow_supervisor_runs
    where request_id=p_request_id and actor_id=auth.uid();
  return jsonb_build_object(''contract_version'',1,''mode'',''shadow'',''scope'',''collect_platform'',
    ''found'',r.id is not null,''run'',collect_security.shadow_run_json(r.id));
end $$;

create function public.list_collect_shadow_runs_v1(p_limit integer default 20,
  p_before_started_at timestamptz default null,p_before_run_id uuid default null) returns jsonb
language plpgsql volatile security definer set search_path='''' set timezone=''UTC'' as $$
declare l collect_security.shadow_supervisor_lease; t timestamptz;
  rows jsonb; cursor jsonb; more boolean; total bigint;
begin
  perform collect_security.require_shadow_actor();
  if p_limit is null or p_limit not between 1 and 50
    or (p_before_started_at is null)<>(p_before_run_id is null)
    or p_before_started_at is not null and not isfinite(p_before_started_at) then
    raise exception ''shadow_request_invalid'' using errcode=''22023'';end if;
  select * into l from collect_security.shadow_supervisor_lease where id for share;
  if l.id is null then raise exception ''shadow_integrity_unavailable'' using errcode=''55000'';end if;
  t:=clock_timestamp();
  select count(*) into total from collect_security.shadow_supervisor_runs;
  with candidates as materialized (
    select id,started_at from collect_security.shadow_supervisor_runs
    where p_before_started_at is null or (started_at,id)<(p_before_started_at,p_before_run_id)
    order by started_at desc,id desc limit p_limit+1
  ), page as materialized (
    select * from candidates order by started_at desc,id desc limit p_limit
  ) select coalesce((select jsonb_agg(collect_security.shadow_run_json(id,t)
      order by started_at desc,id desc) from page),''[]''::jsonb),
    (select count(*)>p_limit from candidates),
    (select jsonb_build_object(''started_at'',started_at,''run_id'',id)
      from page order by started_at,id limit 1)
  into rows,more,cursor;
  return jsonb_build_object(''contract_version'',1,''mode'',''shadow'',''scope'',''collect_platform'',
    ''checked_at'',t,''lease'',jsonb_build_object(''state'',case when l.active_run_id is null
      then ''idle'' when l.lease_expires_at<=t then ''expired'' else ''active'' end,
      ''fence_version'',l.fence_version,''active_run_id'',l.active_run_id,''lease_expires_at'',l.lease_expires_at),
    ''rows'',rows,''total'',total,''next_cursor'',case when more then cursor else null end);
end $$;

revoke all on function collect_security.require_shadow_actor(),
  collect_security.guard_shadow_sample(),collect_security.guard_shadow_run(),
  collect_security.shadow_run_json(uuid,timestamptz),
  collect_security.require_shadow_health(jsonb,timestamptz,timestamptz)
  from public,anon,authenticated,service_role;
revoke all on function public.begin_collect_shadow_run_v1(uuid),
  public.sample_collect_shadow_run_v1(uuid,bigint),public.finish_collect_shadow_run_v1(uuid,bigint),
  public.get_collect_shadow_run_v1(uuid),public.list_collect_shadow_runs_v1(integer,timestamptz,uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.begin_collect_shadow_run_v1(uuid),
  public.sample_collect_shadow_run_v1(uuid,bigint),public.finish_collect_shadow_run_v1(uuid,bigint),
  public.get_collect_shadow_run_v1(uuid),public.list_collect_shadow_runs_v1(integer,timestamptz,uuid)
  to authenticated;

comment on table collect_security.shadow_supervisor_runs is
  ''Manual platform-scoped shadow monitoring telemetry; completion does not attest Codex execution or SMS delivery.'';
comment on function public.sample_collect_shadow_run_v1(uuid,bigint) is
  ''Stores one immutable server-derived redacted health and assisted-SMS aggregate sample; never mutates business or sending state.'';
notify pgrst,''reload schema'';
commit;
']);
    create temp table collect_upgrade_catalog_after on commit drop as with objects(family,object_name,identity,body) as (
      select 'schema',n.nspname::text,n.nspname::text,to_jsonb(n)-array['oid'] from pg_namespace n where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'relation',coalesce(tn.nspname||'.'||tc.relname,n.nspname||'.'||c.relname),n.nspname||'.'||c.relname,
        jsonb_build_object('owner',c.relowner,'acl',c.relacl,'rls',c.relrowsecurity,'force',c.relforcerowsecurity,'kind',c.relkind)
        from pg_class c join pg_namespace n on n.oid=c.relnamespace left join pg_index ix on ix.indexrelid=c.oid
        left join pg_class tc on tc.oid=ix.indrelid left join pg_namespace tn on tn.oid=tc.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'column',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||a.attname,
        jsonb_build_object('type',a.atttypid,'mod',a.atttypmod,'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid))
        from pg_attribute a join pg_class c on c.oid=a.attrelid join pg_namespace n on n.oid=c.relnamespace left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum
        where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations') and a.attnum>0 and not a.attisdropped
      union all select 'routine',n.nspname||'.'||p.proname,n.nspname||'.'||p.proname||':'||pg_get_function_identity_arguments(p.oid),
        jsonb_build_object('owner',p.proowner,'acl',p.proacl,'source',p.prosrc,'config',p.proconfig,'definer',p.prosecdef,'volatile',p.provolatile,'result',p.prorettype)
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'trigger',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||t.tgname,
        jsonb_build_object('enabled',t.tgenabled,'definition',pg_get_triggerdef(t.oid))
        from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'constraint',n.nspname||'.'||cl.relname,n.nspname||'.'||cl.relname||':'||c.conname,to_jsonb(pg_get_constraintdef(c.oid))
        from pg_constraint c join pg_class cl on cl.oid=c.conrelid join pg_namespace n on n.oid=c.connamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
      union all select 'policy',n.nspname||'.'||c.relname,n.nspname||'.'||c.relname||':'||p.polname,
        jsonb_build_object('roles',p.polroles,'command',p.polcmd,'permissive',p.polpermissive,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid))
        from pg_policy p join pg_class c on c.oid=p.polrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private','collect_hybrid','collect_security','collect_admin_access','collect_auth_security','collect_member_actions','collect_profile_access','auth','realtime','supabase_migrations')
    ) select * from objects;
    do $$declare t record;missing boolean;delta bigint;new_xid bigint;append_count bigint:=0;begin
      for t in select * from pg_temp.collect_upgrade_counts loop
        execute format('select exists(select 1 from pg_temp.collect_upgrade_rows b where b.table_name=%L and b.n>(select count(*) from %s t where to_jsonb(t)=b.rowdata))',t.table_name,t.table_name) into missing;
        if missing then raise exception 'Original row removed or changed in %',t.table_name;end if;
        execute format('select count(*)-%s from %s',t.n,t.table_name) into delta;
        if t.table_name='supabase_migrations.schema_migrations' then
          if delta<>1 then raise exception 'Migration registry delta invalid';end if;
        elsif t.table_name=any(array[]::text[]) then
          if delta not in (0,1) then raise exception 'Append delta invalid in %',t.table_name;end if;
          execute format('select count(*) from %s where xmin::text::bigint=pg_current_xact_id()::text::bigint',t.table_name) into new_xid;
          if new_xid<>delta then raise exception 'Unattributed append in %',t.table_name;end if;
          append_count:=append_count+delta;
        elsif delta<>0 then raise exception 'Unexpected row insertion in %',t.table_name;end if;
      end loop;
      if append_count not in (0,4) then raise exception 'Navigation governance append incomplete';end if;
      missing:=false;
      for t in select b.family,b.identity,encode(extensions.digest(b.body::text,'sha256'),'hex') old_hash,
        encode(extensions.digest(a.body::text,'sha256'),'hex') new_hash
        from pg_temp.collect_upgrade_catalog b left join pg_temp.collect_upgrade_catalog_after a using(family,identity)
        where a.identity is null or a.body is distinct from b.body and not (b.family='routine' and b.object_name=any(array[]::text[])) loop
        raise notice 'CATALOG_DIFF|%|%|%|%',t.family,t.identity,t.old_hash,t.new_hash;
        missing:=true;
      end loop;
      if missing then raise exception 'Unexpected original catalog mutation';end if;
      if exists(select 1 from pg_temp.collect_upgrade_catalog_after a left join pg_temp.collect_upgrade_catalog b using(family,identity)
        where b.identity is null and not(a.object_name=any(array['collect_security.shadow_supervisor_runs','collect_security.shadow_supervisor_lease','collect_security.shadow_supervisor_samples','collect_security.require_shadow_actor','collect_security.guard_shadow_sample','collect_security.guard_shadow_run','collect_security.shadow_run_json','collect_security.require_shadow_health','public.begin_collect_shadow_run_v1','public.sample_collect_shadow_run_v1','public.finish_collect_shadow_run_v1','public.get_collect_shadow_run_v1','public.list_collect_shadow_runs_v1']::text[]))) then
        raise exception 'Unexpected new catalog object';end if;
      if (select count(*) from supabase_migrations.schema_migrations)<>152 then raise exception 'Wrong installed count';end if;
      raise notice 'STAGED_UPGRADE_ROWS_PRESERVED|%|%',(select count(*) from pg_temp.collect_upgrade_counts),append_count;
    end$$;
    do $$begin
          if (select count(*) from collect_security.shadow_supervisor_lease)<>1
            or exists(select 1 from collect_security.shadow_supervisor_lease where not id or fence_version<>0 or active_run_id is not null or lease_expires_at is not null)
            or exists(select 1 from collect_security.shadow_supervisor_runs) or exists(select 1 from collect_security.shadow_supervisor_samples) then
            raise exception 'Shadow initial state invalid';end if;
          if (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
            where n.nspname||'.'||c.relname=any(array['collect_security.shadow_supervisor_runs','collect_security.shadow_supervisor_lease','collect_security.shadow_supervisor_samples']::text[]) and c.relkind='r' and c.relrowsecurity)=3 is not true then
            raise exception 'Shadow RLS missing';end if;
          if exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace cross join unnest(array['anon','authenticated','service_role']) r
            where n.nspname||'.'||c.relname=any(array['collect_security.shadow_supervisor_runs','collect_security.shadow_supervisor_lease','collect_security.shadow_supervisor_samples']::text[]) and has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')) then
            raise exception 'Shadow API table privilege';end if;
          if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname||'.'||p.proname=any(array['collect_security.require_shadow_actor','collect_security.guard_shadow_sample','collect_security.guard_shadow_run','collect_security.shadow_run_json','collect_security.require_shadow_health','public.begin_collect_shadow_run_v1','public.sample_collect_shadow_run_v1','public.finish_collect_shadow_run_v1','public.get_collect_shadow_run_v1','public.list_collect_shadow_runs_v1']::text[]))<>10 then
            raise exception 'Shadow function set incomplete';end if;
          if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace cross join unnest(array['anon','authenticated','service_role']) r
            where n.nspname||'.'||p.proname=any(array['collect_security.require_shadow_actor','collect_security.guard_shadow_sample','collect_security.guard_shadow_run','collect_security.shadow_run_json','collect_security.require_shadow_health','public.begin_collect_shadow_run_v1','public.sample_collect_shadow_run_v1','public.finish_collect_shadow_run_v1','public.get_collect_shadow_run_v1','public.list_collect_shadow_runs_v1']::text[]) and has_function_privilege(r,p.oid,'EXECUTE') is distinct from (n.nspname='public' and r='authenticated')) then
            raise exception 'Shadow API function privilege';end if;
        end$$;
rollback;
