begin;

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

create function collect_security.shadow_run_json(p_run_id uuid) returns jsonb
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
      and r.lease_expires_at<=clock_timestamp() then 'expired' else r.status end,
    'started_at',r.started_at,'lease_expires_at',r.lease_expires_at,
    'sampled_at',s.checked_at,'completed_at',r.completed_at,'summary',s.body->'summary');
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
    return jsonb_build_object('contract_version',1,'mode','shadow','scope','collect_platform',
      'ok',true,'outcome','sampled','replayed',true,'run_id',r.id,'fence_version',r.fence_version,
      'sample',s.body||jsonb_build_object('sample_id',s.id,'content_sha256',s.content_sha256));
  end if;
  health:=public.admin_system_health('system');
  t:=clock_timestamp();
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
  if health->>'contract_version'<>'1' or jsonb_array_length(health->'alerts')<>13
    or health->>'health_status' not in ('ok','unknown','attention') then
    raise exception 'shadow_integrity_unavailable' using errcode='55000';end if;
  summary:=jsonb_build_object('health_status',case when health->>'health_status'='attention'
    or (sms->>'uncertain')::bigint>0 or (sms->>'send_started')::bigint>0 then 'attention'
    else health->>'health_status' end,'alert_counts',counts,
    'sms_queue',sms-array['oldest_queued_at','observed_at'],
    'checks_recorded',13,'samples_recorded',1,'business_mutations',0,'provider_sends',0);
  t:=clock_timestamp();
  if r.lease_expires_at<=t or l.lease_expires_at<=t then
    raise exception 'shadow_lease_expired' using errcode='55000';end if;
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
  r collect_security.shadow_supervisor_runs; t timestamptz;
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
  if not exists(select 1 from collect_security.shadow_supervisor_samples where run_id=r.id) then
    raise exception 'shadow_sample_required' using errcode='55000';end if;
  perform collect_security.shadow_run_json(r.id);
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
  t:=clock_timestamp();
  select * into l from collect_security.shadow_supervisor_lease where id;
  select count(*) into total from collect_security.shadow_supervisor_runs;
  with candidates as materialized (
    select id,started_at from collect_security.shadow_supervisor_runs
    where p_before_started_at is null or (started_at,id)<(p_before_started_at,p_before_run_id)
    order by started_at desc,id desc limit p_limit+1
  ), page as materialized (
    select * from candidates order by started_at desc,id desc limit p_limit
  ) select coalesce((select jsonb_agg(collect_security.shadow_run_json(id)
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
  collect_security.shadow_run_json(uuid) from public,anon,authenticated,service_role;
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
commit;
