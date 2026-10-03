begin;
-- Publish reciprocal reservation and all three old request guards atomically.
-- Shipping grant writes reservation -> attempt -> request. Preserve that order
-- before any new FK relation lock can invert an in-flight writer.
lock table collect_receipt_operations.reservations in share row exclusive mode;
lock table collect_gateway_dispatch.attempts in share row exclusive mode;
lock table collect_gateway.requests,collect_gateway_dispatch.requests,collect_gateway_archive.requests in share row exclusive mode;
-- Private additive identity foundation. No RPC, grant, arm or sender authority.
-- Existing primary requests, attempts, reservations and ciphertext remain intact.
create schema collect_gateway_transport;
revoke all on schema collect_gateway_transport from public,anon,authenticated,service_role;

create table collect_receipt_successors.jobs(
 id uuid primary key default gen_random_uuid(),
 approval_id uuid not null unique references collect_receipt_successors.approvals(id)on delete restrict,
 root_outbox_id uuid not null references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 route_version integer not null default 1 check(route_version=1),
 route_kind text not null default 'receipt_successor'check(route_kind='receipt_successor'),
 candidate jsonb not null check(jsonb_typeof(candidate)='object'),
 candidate_sha256 text not null check(candidate_sha256~'^[0-9a-f]{64}$'),
 materialized_at timestamptz not null check(isfinite(materialized_at)),
 check(id<>root_outbox_id),unique(id,approval_id,root_outbox_id));
create index successor_jobs_root on collect_receipt_successors.jobs(root_outbox_id,materialized_at,id);

create table collect_receipt_successors.attempts(
 id uuid primary key default gen_random_uuid(),
 job_id uuid not null unique references collect_receipt_successors.jobs(id)on delete restrict,
 device_id uuid not null references collect_gateway.devices(id)on delete restrict,
 run_id uuid not null references collect_receipt_operations.runs(id)on delete restrict,
 principal_id uuid not null references collect_supervisor.identities(id)on delete restrict,
 fence_version bigint not null check(fence_version between 1 and 1000000000),
 policy_revision bigint not null check(policy_revision between 1 and 1000000000),
 grant_request_id uuid not null unique,
 reservation_id uuid not null unique references collect_receipt_operations.reservations(id)on delete restrict,
 body_sha256 text not null check(body_sha256~'^[0-9a-f]{64}$'),
 destination_sha256 text not null check(destination_sha256~'^[0-9a-f]{64}$'),
 segment_count integer not null check(segment_count between 1 and 10),
 health_observation_id uuid not null references collect_gateway.health_observations(id)on delete restrict,
 sim_revision_sha256 text not null check(sim_revision_sha256~'^[0-9a-f]{64}$'),
 issued_at timestamptz not null check(isfinite(issued_at)),
 expires_at timestamptz not null check(isfinite(expires_at)and expires_at>issued_at and expires_at<=issued_at+interval '30 seconds'));

create table collect_gateway_transport.request_registry(
 request_id uuid primary key,
 protocol_family text not null check(protocol_family in('primary_v1','primary_v2','primary_archive_v3','receipt_successor_v1')),
 device_id uuid not null,
 action text not null,
 request_sha256 text not null check(request_sha256~'^[0-9a-f]{64}$'),
 payload jsonb not null check(jsonb_typeof(payload)='object'),
 route jsonb check(route is null or jsonb_typeof(route)='object'),
 recorded_at timestamptz not null check(isfinite(recorded_at)));

create table collect_receipt_successors.gateway_requests(
 request_id uuid primary key,
 device_id uuid not null references collect_gateway.devices(id)on delete restrict,
 action text not null check(action in('dispatch_grant','arm_dispatch','callback','archive_attempt')),
 request_sha256 text not null check(request_sha256~'^[0-9a-f]{64}$'),
 payload jsonb not null check(jsonb_typeof(payload)='object'),
 route jsonb check(route is null or jsonb_typeof(route)='object'),
 result jsonb not null check(jsonb_typeof(result)='object'),
 recorded_at timestamptz not null check(isfinite(recorded_at)),
 check(action='dispatch_grant'or route is not null));
alter table collect_receipt_successors.attempts add constraint successor_grant_request
 foreign key(grant_request_id)references collect_receipt_successors.gateway_requests(request_id)on delete restrict deferrable initially deferred;

create table collect_gateway_transport.reservation_consumers(
 reservation_id uuid primary key,
 primary_attempt_id uuid unique,
 successor_attempt_id uuid unique,
 primary_receipt_id uuid not null,
 dispatch_job_id uuid references collect_receipt_successors.jobs(id)on delete restrict,
 approval_id uuid references collect_receipt_successors.approvals(id)on delete restrict,
 route_kind text not null check(route_kind in('primary','receipt_successor')),
 route_version integer not null,
 run_id uuid not null,
 fence_version bigint not null check(fence_version between 1 and 1000000000),
 collection_id uuid not null,
 device_id uuid not null,
 actions integer not null check(actions=1),
 sms_segments integer not null check(sms_segments between 1 and 10),
 body_sha256 text not null check(body_sha256~'^[0-9a-f]{64}$'),
 destination_sha256 text not null check(destination_sha256~'^[0-9a-f]{64}$'),
 source_sha256 text not null check(source_sha256~'^[0-9a-f]{64}$'),
 recorded_at timestamptz not null check(isfinite(recorded_at)),
 check((route_kind='primary'and route_version=2 and primary_attempt_id is not null and successor_attempt_id is null
  and dispatch_job_id is null and approval_id is null)
  or(route_kind='receipt_successor'and route_version=1 and successor_attempt_id is not null and primary_attempt_id is null
  and dispatch_job_id is not null and approval_id is not null and dispatch_job_id<>primary_receipt_id)));

create function collect_gateway_transport.immutable()returns trigger
language plpgsql set search_path=''as $$begin
 raise exception 'gateway_transport_identity_immutable'using errcode='55000';end$$;
do $$declare item record;begin
 for item in select *from(values('collect_gateway_transport','request_registry'),('collect_gateway_transport','reservation_consumers'),
  ('collect_receipt_successors','jobs'),('collect_receipt_successors','attempts'),('collect_receipt_successors','gateway_requests'))v(s,t)loop
  execute format('alter table %I.%I enable row level security',item.s,item.t);
  execute format('revoke all on %I.%I from public,anon,authenticated,service_role',item.s,item.t);
  execute format('create trigger retained_transport_identity before update or delete on %I.%I for each row execute function collect_gateway_transport.immutable()',item.s,item.t);
  execute format('create trigger retained_transport_identity_truncate before truncate on %I.%I for each statement execute function collect_gateway_transport.immutable()',item.s,item.t);
 end loop;end$$;

create function collect_receipt_successors.route(p_job uuid)returns jsonb
language sql stable set search_path=''as $$
 select jsonb_build_object('route_version',j.route_version,'route_kind',j.route_kind,
  'primary_receipt_id',j.root_outbox_id,'dispatch_job_id',j.id,'approval_id',j.approval_id)
 from collect_receipt_successors.jobs j where j.id=p_job
$$;
create function collect_receipt_successors.validate_route(p_route jsonb)returns uuid
language plpgsql stable set search_path=''as $$declare job uuid;begin
 perform collect_gateway.payload_keys(p_route,array['route_version','route_kind','primary_receipt_id','dispatch_job_id','approval_id']);
 if p_route->>'route_kind'<>'receipt_successor'or collect_gateway.payload_int(p_route,'route_version',1,1)<>1 then
  raise exception 'receipt_successor_route_invalid'using errcode='22023';end if;
 job:=collect_gateway.payload_uuid(p_route,'dispatch_job_id');
 if collect_gateway.payload_uuid(p_route,'primary_receipt_id')=job
  or collect_gateway.payload_uuid(p_route,'approval_id')is null
  or collect_receipt_successors.route(job)is distinct from p_route then
  raise exception 'receipt_successor_route_invalid'using errcode='22023';end if;return job;end$$;

create function collect_gateway_transport.claim_request()returns trigger
language plpgsql security definer set search_path=''as $$
declare family text;action text;route jsonb;prior collect_gateway_transport.request_registry;begin
 if current_setting('transaction_isolation')<>'read committed'then
  raise exception 'gateway_transport_snapshot_retry'using errcode='40001';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('gateway-dispatch-request:'||new.request_id::text,0))then
  raise exception 'gateway_transport_request_busy'using errcode='55000';end if;
 family:=case tg_table_schema when 'collect_gateway'then 'primary_v1'when 'collect_gateway_dispatch'then 'primary_v2'
  when 'collect_gateway_archive'then 'primary_archive_v3'when 'collect_receipt_successors'then 'receipt_successor_v1'end;
 if family is null then raise exception 'gateway_transport_family_invalid'using errcode='22023';end if;
 if tg_table_schema='collect_gateway_archive'then action:='archive_attempt';else action:=new.action;end if;
 if tg_table_schema='collect_receipt_successors'then route:=new.route;end if;
 if route is not null then perform collect_receipt_successors.validate_route(route);end if;
 select *into prior from collect_gateway_transport.request_registry where request_id=new.request_id;
 if prior.request_id is not null then
  if prior.protocol_family is distinct from family or prior.device_id is distinct from new.device_id
   or prior.action is distinct from action or prior.request_sha256 is distinct from new.request_sha256
   or prior.payload is distinct from new.payload or prior.route is distinct from route then
   raise exception 'gateway_transport_request_conflict'using errcode='22023';end if;
 else
  insert into collect_gateway_transport.request_registry values(new.request_id,family,new.device_id,action,new.request_sha256,new.payload,route,new.recorded_at);
 end if;return new;end$$;

-- Historical tables already have mutually exclusive UUIDs. A historical
-- collision stops this migration; it is never silently deduplicated.
insert into collect_gateway_transport.request_registry
 select request_id,'primary_v1',device_id,action,request_sha256,payload,null::jsonb,recorded_at from collect_gateway.requests
 union all select request_id,'primary_v2',device_id,action,request_sha256,payload,null::jsonb,recorded_at from collect_gateway_dispatch.requests
 union all select request_id,'primary_archive_v3',device_id,'archive_attempt',request_sha256,payload,null::jsonb,recorded_at from collect_gateway_archive.requests;
-- Bulk FK validation avoids acquiring device key-share rows during backfill.
-- Child publication locks keep writers outside these unexposed new tables.
alter table collect_gateway_transport.request_registry add constraint request_registry_device_id_fkey
 foreign key(device_id)references collect_gateway.devices(id)on delete restrict;
create trigger a_global_transport_request_claim before insert on collect_gateway.requests
 for each row execute function collect_gateway_transport.claim_request();
create trigger a_global_transport_request_claim before insert on collect_gateway_dispatch.requests
 for each row execute function collect_gateway_transport.claim_request();
create trigger a_global_transport_request_claim before insert on collect_gateway_archive.requests
 for each row execute function collect_gateway_transport.claim_request();
create trigger a_global_transport_request_claim before insert on collect_receipt_successors.gateway_requests
 for each row execute function collect_gateway_transport.claim_request();

create function collect_gateway_transport.primary_source(p_root uuid)returns text
language sql stable set search_path=''as $$
 select encode(extensions.digest(jsonb_build_object('receipt_id',o.id,'snapshot_id',o.snapshot_id,
  'payment_id',o.payment_id,'collection_id',o.collection_id,'member_record_id',o.member_record_id,
  'amount_rwf',o.amount_rwf,'member_balance_rwf',o.member_balance_rwf,'body_sha256',o.body_sha256,
  'destination_sha256',o.destination_sha256)::text,'sha256'),'hex')
 from collect_hybrid.sms_notification_outbox o where o.id=p_root
$$;
create function collect_gateway_transport.bind_consumer()returns trigger
language plpgsql security definer set search_path=''as $$
declare r collect_receipt_operations.reservations;o collect_hybrid.sms_notification_outbox;
 j collect_receipt_successors.jobs;source text;root uuid;collection uuid;begin
 select *into r from collect_receipt_operations.reservations where id=new.reservation_id for share;
 if tg_table_schema='collect_gateway_dispatch'then
  select *into o from collect_hybrid.sms_notification_outbox where id=new.outbox_id;
  root:=o.id;collection:=o.collection_id;source:=collect_gateway_transport.primary_source(root);
  if new.body_sha256 is distinct from o.body_sha256 or new.destination_sha256 is distinct from o.destination_sha256
   or new.segment_count is distinct from collect_gateway_dispatch.segment_count(o.message_body)then
   raise exception 'gateway_transport_content_proof_invalid'using errcode='55000';end if;
 else
  select *into j from collect_receipt_successors.jobs where id=new.job_id;
  root:=j.root_outbox_id;collection:=(j.candidate->>'collection_id')::uuid;source:=j.candidate_sha256;
  if new.body_sha256 is distinct from j.candidate->>'body_sha256'
   or new.destination_sha256 is distinct from j.candidate->>'destination_sha256'
   or new.segment_count is distinct from (j.candidate->>'segment_count')::integer then
   raise exception 'gateway_transport_content_proof_invalid'using errcode='55000';end if;
 end if;
 if r.id is null or root is null or source is null or r.run_id<>new.run_id or r.fence_version<>new.fence_version
  or r.collection_id is distinct from collection or r.device_id is distinct from new.device_id
  or r.actions<>1 or r.sms_segments<>new.segment_count then
  raise exception 'gateway_transport_reservation_proof_invalid'using errcode='55000';end if;
 if exists(select 1 from collect_gateway_transport.reservation_consumers where reservation_id=new.reservation_id)then
  raise exception 'gateway_transport_reservation_already_consumed'using errcode='55000';end if;
 insert into collect_gateway_transport.reservation_consumers values(new.reservation_id,
  case when tg_table_schema='collect_gateway_dispatch'then new.id end,
  case when tg_table_schema='collect_receipt_successors'then new.id end,
  root,j.id,j.approval_id,case when tg_table_schema='collect_gateway_dispatch'then 'primary'else 'receipt_successor'end,
  case when tg_table_schema='collect_gateway_dispatch'then 2 else 1 end,
  new.run_id,new.fence_version,collection,new.device_id,1,new.segment_count,new.body_sha256,new.destination_sha256,source,new.issued_at);
 return new;end$$;

insert into collect_gateway_transport.reservation_consumers
 select a.reservation_id,a.id,null,a.outbox_id,null,null,'primary',2,a.run_id,a.fence_version,o.collection_id,a.device_id,
  1,a.segment_count,a.body_sha256,a.destination_sha256,collect_gateway_transport.primary_source(o.id),a.issued_at
 from collect_gateway_dispatch.attempts a join collect_hybrid.sms_notification_outbox o on o.id=a.outbox_id;
-- Existing rows are verified explicitly because the deferred triggers below
-- cannot retroactively validate the backfill that preceded their creation.
do $$begin
 if exists(select 1 from collect_gateway_transport.reservation_consumers c
  left join collect_gateway_dispatch.attempts a on a.id=c.primary_attempt_id
  left join collect_receipt_operations.reservations r on r.id=c.reservation_id
  left join collect_hybrid.sms_notification_outbox o on o.id=c.primary_receipt_id
  where a.id is null or r.id is null or o.id is null
   or a.reservation_id is distinct from c.reservation_id or a.outbox_id is distinct from o.id
   or a.run_id is distinct from r.run_id or a.fence_version is distinct from r.fence_version
   or o.collection_id is distinct from r.collection_id or a.device_id is distinct from r.device_id
   or r.actions<>1 or a.segment_count is distinct from r.sms_segments
   or a.body_sha256 is distinct from o.body_sha256 or a.destination_sha256 is distinct from o.destination_sha256
   or a.segment_count is distinct from collect_gateway_dispatch.segment_count(o.message_body))then
  raise exception 'gateway_transport_historical_consumer_invalid'using errcode='55000';end if;
end$$;
-- Add exact validated old-parent FKs after the private primary-only backfill.
-- Final constraints remain restrictive; primary attempt links remain deferred.
alter table collect_gateway_transport.reservation_consumers
 add constraint reservation_consumers_reservation_id_fkey foreign key(reservation_id)references collect_receipt_operations.reservations(id)on delete restrict,
 add constraint reservation_consumers_primary_attempt_id_fkey foreign key(primary_attempt_id)references collect_gateway_dispatch.attempts(id)on delete restrict deferrable initially deferred,
 add constraint reservation_consumers_successor_attempt_id_fkey foreign key(successor_attempt_id)references collect_receipt_successors.attempts(id)on delete restrict deferrable initially deferred,
 add constraint reservation_consumers_primary_receipt_id_fkey foreign key(primary_receipt_id)references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 add constraint reservation_consumers_run_id_fkey foreign key(run_id)references collect_receipt_operations.runs(id)on delete restrict,
 add constraint reservation_consumers_collection_id_fkey foreign key(collection_id)references public.collections(id)on delete restrict,
 add constraint reservation_consumers_device_id_fkey foreign key(device_id)references collect_gateway.devices(id)on delete restrict;
create trigger a_exclusive_dispatch_reservation before insert on collect_gateway_dispatch.attempts
 for each row execute function collect_gateway_transport.bind_consumer();
create trigger a_exclusive_dispatch_reservation before insert on collect_receipt_successors.attempts
 for each row execute function collect_gateway_transport.bind_consumer();

create function collect_gateway_transport.verify_consumer()returns trigger
language plpgsql security definer set search_path=''as $$
declare c collect_gateway_transport.reservation_consumers;r collect_receipt_operations.reservations;
 a collect_gateway_dispatch.attempts;s collect_receipt_successors.attempts;j collect_receipt_successors.jobs;
 expected_root uuid;expected_collection uuid;expected_source text;begin
 select *into c from collect_gateway_transport.reservation_consumers where reservation_id=new.reservation_id;
 select *into r from collect_receipt_operations.reservations where id=c.reservation_id;
 if c.route_kind='primary'then
  select *into a from collect_gateway_dispatch.attempts where id=c.primary_attempt_id;
  select id,collection_id into expected_root,expected_collection from collect_hybrid.sms_notification_outbox where id=a.outbox_id;
  expected_source:=collect_gateway_transport.primary_source(expected_root);
  if a.id is null or a.reservation_id<>c.reservation_id or a.outbox_id<>c.primary_receipt_id or a.device_id<>c.device_id
   or a.run_id<>c.run_id or a.fence_version<>c.fence_version or a.segment_count<>c.sms_segments
   or a.body_sha256<>c.body_sha256 or a.destination_sha256<>c.destination_sha256 then
   raise exception 'gateway_transport_consumer_proof_invalid'using errcode='55000';end if;
  if not exists(select 1 from collect_hybrid.sms_notification_outbox o where o.id=expected_root
   and o.body_sha256=a.body_sha256 and o.destination_sha256=a.destination_sha256
   and collect_gateway_dispatch.segment_count(o.message_body)=a.segment_count)then
   raise exception 'gateway_transport_content_proof_invalid'using errcode='55000';end if;
 else
  select *into s from collect_receipt_successors.attempts where id=c.successor_attempt_id;
  select *into j from collect_receipt_successors.jobs where id=s.job_id;
  expected_root:=j.root_outbox_id;expected_collection:=(j.candidate->>'collection_id')::uuid;expected_source:=j.candidate_sha256;
  if s.id is null or s.reservation_id<>c.reservation_id or s.job_id<>c.dispatch_job_id or j.approval_id<>c.approval_id
   or s.device_id<>c.device_id or s.run_id<>c.run_id or s.fence_version<>c.fence_version
   or s.segment_count<>c.sms_segments or s.body_sha256<>c.body_sha256 or s.destination_sha256<>c.destination_sha256 then
   raise exception 'gateway_transport_consumer_proof_invalid'using errcode='55000';end if;
  if s.body_sha256 is distinct from j.candidate->>'body_sha256'
   or s.destination_sha256 is distinct from j.candidate->>'destination_sha256'
   or s.segment_count is distinct from (j.candidate->>'segment_count')::integer then
   raise exception 'gateway_transport_content_proof_invalid'using errcode='55000';end if;
 end if;
 if c.reservation_id is null or r.id is null or c.primary_receipt_id is distinct from expected_root
  or c.collection_id is distinct from expected_collection or c.source_sha256 is distinct from expected_source
  or r.run_id<>c.run_id or r.fence_version<>c.fence_version or r.collection_id<>c.collection_id
  or r.device_id is distinct from c.device_id or r.actions<>1 or r.sms_segments<>c.sms_segments then
  raise exception 'gateway_transport_consumer_proof_invalid'using errcode='55000';end if;
 return null;end$$;
create constraint trigger retained_exclusive_consumer_proof after insert on collect_gateway_transport.reservation_consumers
 deferrable initially deferred for each row execute function collect_gateway_transport.verify_consumer();
create constraint trigger primary_exclusive_consumer_proof after insert on collect_gateway_dispatch.attempts
 deferrable initially deferred for each row execute function collect_gateway_transport.verify_consumer();
create constraint trigger successor_exclusive_consumer_proof after insert on collect_receipt_successors.attempts
 deferrable initially deferred for each row execute function collect_gateway_transport.verify_consumer();

create function collect_receipt_successors.verify_job()returns trigger
language plpgsql security definer set search_path=''as $$declare a collect_receipt_successors.approvals;begin
 select *into a from collect_receipt_successors.approvals where id=new.approval_id;
 if a.id is null or a.root_outbox_id<>new.root_outbox_id or a.candidate is distinct from new.candidate
  or new.materialized_at<a.recorded_at or new.materialized_at>=a.expires_at
  or exists(select 1 from collect_receipt_successors.approval_events where approval_id=a.id and event_kind='revoked')
  or new.candidate_sha256 is distinct from encode(extensions.digest(new.candidate::text,'sha256'),'hex')then
  raise exception 'receipt_successor_job_proof_invalid'using errcode='55000';end if;return null;end$$;
create constraint trigger successor_immutable_job_proof after insert on collect_receipt_successors.jobs
 deferrable initially deferred for each row execute function collect_receipt_successors.verify_job();

revoke all on all functions in schema collect_gateway_transport from public,anon,authenticated,service_role;
revoke all on all functions in schema collect_receipt_successors from public,anon,authenticated,service_role;
do $guard$begin
 if(select prosrc from pg_proc where oid='collect_receipt_successors.retry_candidate(uuid,uuid)'::regprocedure)is distinct from $expected$
declare o collect_hybrid.sms_notification_outbox;c collect_receipt_successors.original_closures;
 s collect_hybrid.momo_balance_snapshots;p public.payments;policy collect_hybrid.sms_receipt_policies;
 consent collect_hybrid.sms_receipt_member_consents;i collect_hybrid.member_momo_identities;
 a collect_gateway_dispatch.attempts;body text;ref text;rr bigint;lr bigint;proof text;begin
 select *into o from collect_hybrid.sms_notification_outbox where id=p_root;
 if o.id is null or not collect_receipt_actions.rwanda_source(o)then return jsonb_build_object('reason_code','unavailable');end if;
 if p_source is distinct from o.snapshot_id then return jsonb_build_object('reason_code','source_not_original');end if;
 select *into c from collect_receipt_successors.original_closures where root_outbox_id=o.id;
 if c.id is null or o.state<>'suppressed'or o.suppression_reason<>'successor_unarmed_closed'then
  return jsonb_build_object('reason_code','irreversible_closure_required');end if;
 -- Closure is immutable and insertion guards exclude future transports.
 -- Still fold actual transport facts, so corruption/late evidence never grants
 -- authority merely because a classification was once recorded.
 if exists(select 1 from collect_hybrid.sms_notification_claim_requests where outbox_id=o.id)
  or exists(select 1 from collect_hybrid.sms_notification_confirmations where outbox_id=o.id)
  or exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id=o.id)
  or exists(select 1 from collect_security.assisted_sms_session_evidence where outbox_id=o.id)
  or exists(select 1 from collect_gateway_dispatch.attempts x where x.outbox_id=o.id and(x.state<>'granted'
   or exists(select 1 from collect_gateway_dispatch.arms where attempt_id=x.id)
   or exists(select 1 from collect_gateway_dispatch.callbacks where attempt_id=x.id)))then
  return jsonb_build_object('reason_code','transport_proof_changed');end if;
 select *into s from collect_hybrid.momo_balance_snapshots where id=o.snapshot_id;
 select *into p from public.payments where id=o.payment_id;
 if not collect_receipt_policy.content_is_current(o)or not collect_receipt_policy.snapshot_is_eligible(s)then
  return jsonb_build_object('reason_code','source_evidence_invalid');end if;
 select *into policy from collect_hybrid.sms_receipt_policies where collection_id=o.collection_id;
 select *into consent from collect_hybrid.sms_receipt_member_consents where member_record_id=o.member_record_id;
 select *into i from collect_hybrid.member_momo_identities where member_id=o.member_record_id;
 if policy.collection_id is null or not policy.enabled or policy.template_key<>'buri_munsi.payment_received'
  or policy.template_version<>1 or policy.receipt_language not in('rw','en','fr')then
  return jsonb_build_object('reason_code','policy_disabled');end if;
 if consent.member_record_id is null or not consent.enabled then return jsonb_build_object('reason_code','consent_missing');end if;
 if i.member_id is null or i.momo_number!~'^\+2507[2389][0-9]{7}$'then return jsonb_build_object('reason_code','contact_missing');end if;
 ref:=btrim(coalesce(p.transaction_id,''));
 if ref!~'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'then return jsonb_build_object('reason_code','content_refused');end if;
 body:=collect_receipt_policy.render_v2(p.amount_rwf,s.member_balance_after_rwf,s.captured_at,ref,policy.receipt_language);
 perform collect_gateway_dispatch.segment_count(body);
 select coalesce((select revision from collect_receipt_actions.revisions where outbox_id=o.id),1)into rr;
 select coalesce((select revision from collect_receipt_successors.lineage_heads where root_outbox_id=o.id),1)into lr;
 if rr>=1000000000 or lr>=999999999 then return jsonb_build_object('reason_code','revision_exhausted');end if;
 select *into a from collect_gateway_dispatch.attempts where outbox_id=o.id;
 proof:=encode(extensions.digest(jsonb_build_object('original',to_jsonb(o),'closure',to_jsonb(c),'ordinary_grant',to_jsonb(a))::text,'sha256'),'hex');
 return jsonb_build_object('reason_code','retry_eligible','root_outbox_id',o.id,'closure_id',c.id,
  'action','retry_uninvoked','proof_class','never_armed_closed','transport_proof_sha256',proof,
  'root_revision',rr,'lineage_revision',lr,'source_snapshot_id',s.id,'journal_entry_id',s.journal_entry_id,
  'source_sha256',encode(extensions.digest(to_jsonb(s)::text,'sha256'),'hex'),
  'payment_id',p.id,'collection_id',o.collection_id,'member_record_id',o.member_record_id,
  'amount_rwf',s.delta_rwf,'member_balance_recorded_rwf',s.member_balance_after_rwf,
  'snapshot_recorded_at',collect_ops.utc(s.captured_at),'reference',ref,
  'destination_e164',i.momo_number,'destination_sha256',encode(extensions.digest(i.momo_number,'sha256'),'hex'),
  'destination_revision',i.revision,'policy_revision',policy.revision,'consent_revision',consent.revision,
  'language',policy.receipt_language,'content_policy_version',2,'body',body,
  'body_sha256',encode(extensions.digest(body,'sha256'),'hex'),'segment_count',collect_gateway_dispatch.segment_count(body));
end$expected$then
  raise exception 'receipt_successor_predecessor_changed'using errcode='55000';end if;
 if(select proowner from pg_proc where oid='collect_receipt_successors.retry_candidate(uuid,uuid)'::regprocedure)<>current_user::regrole then
  raise exception 'receipt_successor_predecessor_owner_changed'using errcode='55000';end if;
end$guard$;
create function collect_receipt_successors.retry_financial_candidate(p_root uuid,p_source uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare o collect_hybrid.sms_notification_outbox;c collect_receipt_successors.original_closures;
 s collect_hybrid.momo_balance_snapshots;p public.payments;policy collect_hybrid.sms_receipt_policies;
 consent collect_hybrid.sms_receipt_member_consents;i collect_hybrid.member_momo_identities;
 a collect_gateway_dispatch.attempts;body text;ref text;rr bigint;lr bigint;proof text;begin
 select *into o from collect_hybrid.sms_notification_outbox where id=p_root;
 if o.id is null or not collect_receipt_actions.rwanda_source(o)then return jsonb_build_object('reason_code','unavailable');end if;
 if p_source is distinct from o.snapshot_id then return jsonb_build_object('reason_code','source_not_original');end if;
 select *into c from collect_receipt_successors.original_closures where root_outbox_id=o.id;
 if c.id is null or o.state<>'suppressed'or o.suppression_reason<>'successor_unarmed_closed'then
  return jsonb_build_object('reason_code','irreversible_closure_required');end if;
 -- Closure is immutable and insertion guards exclude future transports.
 -- Still fold actual transport facts, so corruption/late evidence never grants
 -- authority merely because a classification was once recorded.
 if exists(select 1 from collect_hybrid.sms_notification_claim_requests where outbox_id=o.id)
  or exists(select 1 from collect_hybrid.sms_notification_confirmations where outbox_id=o.id)
  or exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id=o.id)
  or exists(select 1 from collect_security.assisted_sms_session_evidence where outbox_id=o.id)
  or exists(select 1 from collect_gateway_dispatch.attempts x where x.outbox_id=o.id and(x.state<>'granted'
   or exists(select 1 from collect_gateway_dispatch.arms where attempt_id=x.id)
   or exists(select 1 from collect_gateway_dispatch.callbacks where attempt_id=x.id)))then
  return jsonb_build_object('reason_code','transport_proof_changed');end if;
 select *into s from collect_hybrid.momo_balance_snapshots where id=o.snapshot_id;
 select *into p from public.payments where id=o.payment_id;
 if not collect_receipt_policy.content_is_current(o)or not collect_receipt_policy.snapshot_is_eligible(s)then
  return jsonb_build_object('reason_code','source_evidence_invalid');end if;
 select *into policy from collect_hybrid.sms_receipt_policies where collection_id=o.collection_id;
 select *into consent from collect_hybrid.sms_receipt_member_consents where member_record_id=o.member_record_id;
 select *into i from collect_hybrid.member_momo_identities where member_id=o.member_record_id;
 if policy.collection_id is null or not policy.enabled or policy.template_key<>'buri_munsi.payment_received'
  or policy.template_version<>1 or policy.receipt_language not in('rw','en','fr')then
  return jsonb_build_object('reason_code','policy_disabled');end if;
 if consent.member_record_id is null or not consent.enabled then return jsonb_build_object('reason_code','consent_missing');end if;
 if i.member_id is null or i.momo_number!~'^\+2507[2389][0-9]{7}$'then return jsonb_build_object('reason_code','contact_missing');end if;
 ref:=btrim(coalesce(p.transaction_id,''));
 if ref!~'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'then return jsonb_build_object('reason_code','content_refused');end if;
 body:=collect_receipt_policy.render_v2(p.amount_rwf,s.member_balance_after_rwf,s.captured_at,ref,policy.receipt_language);
 perform collect_gateway_dispatch.segment_count(body);
 select coalesce((select revision from collect_receipt_actions.revisions where outbox_id=o.id),1)into rr;
 select coalesce((select revision from collect_receipt_successors.lineage_heads where root_outbox_id=o.id),1)into lr;
 if rr>=1000000000 or lr>=999999999 then return jsonb_build_object('reason_code','revision_exhausted');end if;
 select *into a from collect_gateway_dispatch.attempts where outbox_id=o.id;
 proof:=encode(extensions.digest(jsonb_build_object('original',to_jsonb(o),'closure',to_jsonb(c),'ordinary_grant',to_jsonb(a))::text,'sha256'),'hex');
 return jsonb_build_object('reason_code','retry_eligible','root_outbox_id',o.id,'closure_id',c.id,
  'action','retry_uninvoked','proof_class','never_armed_closed','transport_proof_sha256',proof,
  'root_revision',rr,'lineage_revision',lr,'source_snapshot_id',s.id,'journal_entry_id',s.journal_entry_id,
  'source_sha256',encode(extensions.digest(to_jsonb(s)::text,'sha256'),'hex'),
  'payment_id',p.id,'collection_id',o.collection_id,'member_record_id',o.member_record_id,
  'amount_rwf',s.delta_rwf,'member_balance_recorded_rwf',s.member_balance_after_rwf,
  'snapshot_recorded_at',collect_ops.utc(s.captured_at),'reference',ref,
  'destination_e164',i.momo_number,'destination_sha256',encode(extensions.digest(i.momo_number,'sha256'),'hex'),
  'destination_revision',i.revision,'policy_revision',policy.revision,'consent_revision',consent.revision,
  'language',policy.receipt_language,'content_policy_version',2,'body',body,
  'body_sha256',encode(extensions.digest(body,'sha256'),'hex'),'segment_count',collect_gateway_dispatch.segment_count(body));
end$$;
create or replace function collect_receipt_successors.retry_candidate(p_root uuid,p_source uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$begin
 if exists(select 1 from collect_receipt_successors.jobs where root_outbox_id=p_root)then
  return jsonb_build_object('reason_code','transport_proof_changed');end if;
 return collect_receipt_successors.retry_financial_candidate(p_root,p_source);
end$$;
revoke all on function collect_receipt_successors.retry_financial_candidate(uuid,uuid)from public,anon,authenticated,service_role;

-- Execution continuation in the same atomic migration.
-- Private continuation over exact sealed identity foundation. Inactive default.
insert into collect_receipt_successors.content_policies(version,choices,owner_message)values(3,
 '{"action":"first_job_retry_uninvoked","separate_dispatch_job":true,"route_version":1,"approval_causal_event_required":true,"grant_causal_event_required_at_arm":true,"current_exact_financial_contact_language_required":true,"single_physical_sender":true,"shared_quota":true,"dispatch_enabled_by_default":false,"resend":false,"correction":false}'::jsonb,
 'Additive first-job retry execution proof. Original primary lifetime identity and retained v2 financial decision remain unchanged. Successor configuration stays inactive.');

create table collect_receipt_successors.execution_events(
 id uuid primary key default gen_random_uuid(),
 job_id uuid not null references collect_receipt_successors.jobs(id)on delete restrict,
 attempt_id uuid not null references collect_receipt_successors.attempts(id)on delete restrict,
 root_outbox_id uuid not null references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 approval_id uuid not null references collect_receipt_successors.approvals(id)on delete restrict,
 approved_event_id uuid not null references collect_receipt_successors.approval_events(id)on delete restrict,
 approval_request_id uuid not null references collect_receipt_successors.owner_requests(request_id)on delete restrict,
 request_id uuid not null unique references collect_receipt_successors.gateway_requests(request_id)on delete restrict deferrable initially deferred,
 event_kind text not null check(event_kind in('grant','arm')),
 lineage_before bigint not null check(lineage_before between 1 and 999999999),
 lineage_after bigint not null check(lineage_after=lineage_before+1),
 candidate_sha256 text not null check(candidate_sha256~'^[0-9a-f]{64}$'),
 recorded_at timestamptz not null check(isfinite(recorded_at)),
 unique(attempt_id,event_kind),unique(root_outbox_id,lineage_after));
create table collect_receipt_successors.arms(
 attempt_id uuid primary key references collect_receipt_successors.attempts(id)on delete restrict,
 request_id uuid not null unique references collect_receipt_successors.gateway_requests(request_id)on delete restrict deferrable initially deferred,
 reservation_sha256 text not null check(reservation_sha256~'^[0-9a-f]{64}$'),
 route jsonb not null check(jsonb_typeof(route)='object'),
 callback_plan jsonb not null check(jsonb_typeof(callback_plan)='array'),
 health_observation_id uuid not null references collect_gateway.health_observations(id)on delete restrict,
 armed_at timestamptz not null check(isfinite(armed_at)),expires_at timestamptz not null check(isfinite(expires_at)and expires_at>armed_at and expires_at<=armed_at+interval '30 seconds'));
create table collect_receipt_successors.attempt_revocations(
 attempt_id uuid primary key references collect_receipt_successors.attempts(id)on delete restrict,
 approval_event_id uuid not null references collect_receipt_successors.approval_events(id)on delete restrict,
 recorded_at timestamptz not null check(isfinite(recorded_at)));
do $$declare name text;begin
 foreach name in array array['execution_events','arms','attempt_revocations']loop
  execute format('alter table collect_receipt_successors.%I enable row level security',name);
  execute format('revoke all on collect_receipt_successors.%I from public,anon,authenticated,service_role',name);
  execute format('create trigger retained_transport_identity before update or delete on collect_receipt_successors.%I for each row execute function collect_gateway_transport.immutable()',name);
  execute format('create trigger retained_transport_identity_truncate before truncate on collect_receipt_successors.%I for each statement execute function collect_gateway_transport.immutable()',name);
 end loop;end$$;

create function collect_receipt_successors.require_approval(p_approval uuid,p_lineage bigint)returns collect_receipt_successors.approvals
language plpgsql set search_path=''as $$
declare a collect_receipt_successors.approvals;e collect_receipt_successors.approval_events;
 r collect_receipt_successors.owner_requests;current_candidate jsonb;head bigint;begin
 select *into a from collect_receipt_successors.approvals where id=p_approval for share;
 select *into e from collect_receipt_successors.approval_events where approval_id=a.id and event_kind='approved'for share;
 select *into r from collect_receipt_successors.owner_requests where request_id=a.request_id for share;
 select revision into head from collect_receipt_successors.lineage_heads where root_outbox_id=a.root_outbox_id;
 if a.id is null or e.id is null or r.request_id is null or a.expires_at<=clock_timestamp()
  or exists(select 1 from collect_receipt_successors.approval_events where approval_id=a.id and event_kind='revoked')
  or e.request_id<>a.request_id or e.actor_id<>a.actor_id or e.session_id<>a.session_id
  or e.lineage_revision<>a.lineage_revision or r.action<>'approve_successor'
  or r.actor_id<>a.actor_id or r.session_id<>a.session_id
  or r.result->>'approval_id' is distinct from a.id::text
  or r.result->>'outbox_id' is distinct from a.root_outbox_id::text
  or r.result->>'preview_sha256' is distinct from a.preview_sha256
  or r.result->>'lineage_revision' is distinct from a.lineage_revision::text
  or collect_receipt_successors.preview_hash(a.candidate,a.sampled_valid_until)is distinct from a.preview_sha256
  or head is distinct from p_lineage then
  raise exception 'receipt_successor_approval_fenced'using errcode='55000';end if;
 current_candidate:=collect_receipt_successors.retry_financial_candidate(a.root_outbox_id,a.source_snapshot_id);
 if current_candidate->>'reason_code' is distinct from 'retry_eligible'
  or(current_candidate->>'root_revision')::bigint is distinct from a.expected_root_revision
  or(current_candidate-array['root_revision','lineage_revision'])is distinct from(a.candidate-array['root_revision','lineage_revision'])then
  raise exception 'receipt_successor_approved_source_changed'using errcode='55000';end if;
 return a;end$$;
create function collect_receipt_successors.request_lock(p_device uuid,p_request uuid,p_hash text)returns void
language plpgsql set search_path=''as $$begin
 perform collect_gateway.require_service(p_device,p_request,p_hash);
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'receipt_successor_snapshot_retry'using errcode='40001';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('gateway-dispatch-request:'||p_request::text,0))then
  raise exception 'receipt_successor_request_busy'using errcode='55000';end if;
 if exists(select 1 from collect_gateway_transport.request_registry where request_id=p_request and protocol_family<>'receipt_successor_v1')then
  raise exception 'receipt_successor_request_conflict'using errcode='22023';end if;end$$;
create function collect_receipt_successors.refusal(p_device uuid,p_request uuid,p_code text,p_replay boolean default false)returns jsonb
language sql immutable set search_path=''as $$
 select jsonb_build_object('contract_version',1,'protocol_family','receipt_successor','ok',false,'code',p_code,
  'device_id',p_device,'request_id',p_request,'replay',p_replay,'send_authority',false,'carrier_proof',false,'delivery_proven',false)
$$;
create function collect_receipt_successors.replay(p_device uuid,p_request uuid,p_action text,p_hash text,p_payload jsonb)returns jsonb
language plpgsql set search_path=''as $$declare r collect_receipt_successors.gateway_requests;begin
 select *into r from collect_receipt_successors.gateway_requests where request_id=p_request;
 if r.request_id is null then return null;end if;
 if r.device_id<>p_device or r.action<>p_action or r.request_sha256<>p_hash or r.payload is distinct from p_payload then
  raise exception 'receipt_successor_request_conflict'using errcode='22023';end if;
 if p_action in('dispatch_grant','arm_dispatch')then
  return collect_receipt_successors.refusal(p_device,p_request,'ORIGINAL_REQUEST_RECORDED',true);end if;
 return r.result||jsonb_build_object('replay',true);end$$;
create function collect_receipt_successors.store(p_device uuid,p_request uuid,p_action text,p_hash text,p_payload jsonb,p_route jsonb,p_result jsonb)returns jsonb
language plpgsql set search_path=''as $$begin
 insert into collect_receipt_successors.gateway_requests values(p_request,p_device,p_action,p_hash,p_payload,p_route,p_result,clock_timestamp());return p_result;end$$;

create function public.gateway_receipt_successor_grant_v1(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare p collect_receipt_operations.policy;r collect_receipt_operations.runs;a collect_receipt_successors.approvals;
 j collect_receipt_successors.jobs;s collect_receipt_successors.attempts;h collect_gateway.health_observations;
 prior jsonb;result jsonb;route jsonb;reservation uuid;before_revision bigint;after_revision bigint;t timestamptz;expiry timestamptz;approved_event uuid;begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);
 perform collect_receipt_successors.request_lock(p_device_id,p_request_id,p_request_sha256);perform collect_gateway.payload_keys(p_payload,array[]::text[]);
 select *into p from collect_receipt_operations.policy where singleton for update;
 if not exists(select 1 from collect_gateway.devices where id=p_device_id and state='active')then raise exception 'gateway_device_not_active'using errcode='42501';end if;
 prior:=collect_receipt_successors.replay(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload);if prior is not null then return prior;end if;
 if not(select enabled from collect_receipt_successors.configuration where singleton for share)then
  result:=collect_receipt_successors.refusal(p_device_id,p_request_id,'SUCCESSORS_DISABLED');
 elsif p.emergency_stop or p.mode not in('Live-limited','Live')then result:=collect_receipt_successors.refusal(p_device_id,p_request_id,'OPERATIONS_PAUSED');end if;
 if result is not null then return collect_receipt_successors.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,null,result);end if;
 select *into r from collect_receipt_operations.runs where device_id=p_device_id and completed_at is null and expires_at>clock_timestamp()
  and policy_revision=p.revision and mode in('Live-limited','Live')order by fence_version desc limit 1;
 if r.id is null then return collect_receipt_successors.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,null,collect_receipt_successors.refusal(p_device_id,p_request_id,'NO_CURRENT_RUN'));end if;
 r:=collect_receipt_operations.require_run(r.id,r.fence_version,r.principal_id);
 select *into a from collect_receipt_successors.approvals candidate where expires_at>clock_timestamp()
  and(candidate.candidate->>'collection_id')::uuid=any(r.collection_ids)
  and not exists(select 1 from collect_receipt_successors.approval_events where approval_id=candidate.id and event_kind='revoked')
  and not exists(select 1 from collect_receipt_successors.jobs where approval_id=candidate.id)
  order by recorded_at,id limit 1;
 if a.id is null then
  result:=collect_receipt_successors.refusal(p_device_id,p_request_id,case
   when exists(select 1 from collect_receipt_successors.jobs outstanding_job where(outstanding_job.candidate->>'collection_id')::uuid=any(r.collection_ids))then 'SUCCESSOR_EXECUTION_PRESENT'
   when exists(select 1 from collect_receipt_successors.approvals outstanding_intent where(outstanding_intent.candidate->>'collection_id')::uuid=any(r.collection_ids))then 'APPROVAL_REVIEW_REQUIRED'
   else 'NO_SUCCESSOR_INTENT'end);
  return collect_receipt_successors.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,null,result);end if;
 perform 1 from collect_hybrid.sms_notification_outbox where id=a.root_outbox_id for update;
 perform collect_receipt_successors.lock_preview_source(a.root_outbox_id);
 perform 1 from public.feature_flags where key='hybrid_sms_notifications'for share nowait;
 if not coalesce((select enabled from public.feature_flags where key='hybrid_sms_notifications'),false)then raise exception 'receipt_dispatch_paused'using errcode='55000';end if;
 before_revision:=a.lineage_revision;a:=collect_receipt_successors.require_approval(a.id,before_revision);
 h:=collect_gateway_dispatch.ready_health(p_device_id);
 if h.id is null then return collect_receipt_successors.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,null,collect_receipt_successors.refusal(p_device_id,p_request_id,'DEVICE_NOT_READY'));end if;
 reservation:=gen_random_uuid();
 if not collect_receipt_operations.reserve_budget(r.id,r.fence_version,reservation,(a.candidate->>'collection_id')::uuid,p_device_id,1,(a.candidate->>'segment_count')::integer)then
  return collect_receipt_successors.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,null,collect_receipt_successors.refusal(p_device_id,p_request_id,'QUOTA_EXHAUSTED'));end if;
 r:=collect_receipt_operations.require_run(r.id,r.fence_version,r.principal_id);a:=collect_receipt_successors.require_approval(a.id,before_revision);t:=clock_timestamp();
 expiry:=least(a.expires_at,r.expires_at,t+interval '30 seconds',least(h.reported_at,h.ingested_at)+interval '120 seconds',(date_trunc('day',t at time zone 'UTC')at time zone 'UTC')+interval '1 day');
 if expiry<=t then raise exception 'receipt_successor_expired'using errcode='55000';end if;
 insert into collect_receipt_successors.jobs(approval_id,root_outbox_id,candidate,candidate_sha256,materialized_at)
  values(a.id,a.root_outbox_id,a.candidate,encode(extensions.digest(a.candidate::text,'sha256'),'hex'),t)returning *into j;
 route:=collect_receipt_successors.route(j.id);
 insert into collect_receipt_successors.attempts(job_id,device_id,run_id,principal_id,fence_version,policy_revision,grant_request_id,reservation_id,body_sha256,destination_sha256,segment_count,health_observation_id,sim_revision_sha256,issued_at,expires_at)
  values(j.id,p_device_id,r.id,r.principal_id,r.fence_version,r.policy_revision,p_request_id,reservation,a.candidate->>'body_sha256',a.candidate->>'destination_sha256',(a.candidate->>'segment_count')::integer,h.id,h.sim_revision_sha256,t,expiry)returning *into s;
 select id into approved_event from collect_receipt_successors.approval_events where approval_id=a.id and event_kind='approved';after_revision:=collect_receipt_successors.advance(a.root_outbox_id);
 if after_revision<>before_revision+1 then raise exception 'receipt_successor_causal_event_invalid'using errcode='55000';end if;
 insert into collect_receipt_successors.execution_events(job_id,attempt_id,root_outbox_id,approval_id,approved_event_id,approval_request_id,request_id,event_kind,lineage_before,lineage_after,candidate_sha256,recorded_at)
  values(j.id,s.id,a.root_outbox_id,a.id,approved_event,a.request_id,p_request_id,'grant',before_revision,after_revision,j.candidate_sha256,t);
 result:=jsonb_build_object('contract_version',1,'protocol_family','receipt_successor','ok',true,'code','SUCCESSOR_GRANTED','device_id',p_device_id,'request_id',p_request_id,
  'route',route,'attempt_id',s.id,'run_id',r.id,'fence_version',r.fence_version,'policy_revision',r.policy_revision,'issued_at',collect_gateway.utc(t),'expires_at',collect_gateway.utc(expiry),
  'segment_count',s.segment_count,'body',a.candidate->>'body','destination_e164',a.candidate->>'destination_e164','body_sha256',s.body_sha256,'destination_sha256',s.destination_sha256,
  'sim_revision_sha256',s.sim_revision_sha256,'replay',false,'send_authority',false,'carrier_proof',false,'delivery_proven',false);
 perform collect_receipt_successors.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,route,collect_receipt_successors.refusal(p_device_id,p_request_id,'ORIGINAL_REQUEST_RECORDED',true));return result;
 exception when lock_not_available then raise exception 'receipt_successor_source_busy'using errcode='55000';end$$;

create function public.gateway_receipt_successor_arm_v1(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare s collect_receipt_successors.attempts;j collect_receipt_successors.jobs;a collect_receipt_successors.approvals;
 r collect_receipt_operations.runs;h collect_gateway.health_observations;g collect_receipt_successors.execution_events;
 prior jsonb;cb jsonb;seen uuid[];sid uuid;did uuid;idx integer:=0;t timestamptz;after_revision bigint;result jsonb;job uuid;begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);
 perform collect_receipt_successors.request_lock(p_device_id,p_request_id,p_request_sha256);
 perform collect_gateway.payload_keys(p_payload,array['route','attempt_id','fence_version','body_sha256','destination_sha256','reservation_sha256','callbacks']);
 job:=collect_receipt_successors.validate_route(p_payload->'route');
 select *into s from collect_receipt_successors.attempts where id=collect_gateway.payload_uuid(p_payload,'attempt_id')and job_id=job;
 if s.id is null or s.device_id<>p_device_id or s.fence_version<>collect_gateway.payload_int(p_payload,'fence_version',1,1000000000)then raise exception 'receipt_successor_attempt_unavailable'using errcode='42501';end if;
 if jsonb_typeof(p_payload->'callbacks')is distinct from 'array'or jsonb_array_length(p_payload->'callbacks')<>s.segment_count
  or jsonb_typeof(p_payload->'reservation_sha256')is distinct from 'string'or(p_payload->>'reservation_sha256')!~'^[0-9a-f]{64}$'then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
 seen:=array[s.id,p_request_id,job];
 for cb in select value from jsonb_array_elements(p_payload->'callbacks')loop
  perform collect_gateway.payload_keys(cb,array['segment_index','sent_callback_id','delivery_callback_id']);
  if collect_gateway.payload_int(cb,'segment_index',0,9)<>idx then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
  sid:=collect_gateway.payload_uuid(cb,'sent_callback_id');did:=collect_gateway.payload_uuid(cb,'delivery_callback_id');
  if sid=any(seen)or did=any(seen)or sid=did then raise exception 'gateway_payload_invalid'using errcode='22023';end if;seen:=seen||array[sid,did];idx:=idx+1;end loop;
 r:=collect_receipt_operations.require_run(s.run_id,s.fence_version,s.principal_id);
 if not(select enabled from collect_receipt_successors.configuration where singleton for share)then raise exception 'receipt_successor_dispatch_disabled'using errcode='55000';end if;
 select *into j from collect_receipt_successors.jobs where id=s.job_id;
 perform 1 from collect_hybrid.sms_notification_outbox where id=j.root_outbox_id for update;
 select *into s from collect_receipt_successors.attempts where id=s.id for share;
 prior:=collect_receipt_successors.replay(p_device_id,p_request_id,'arm_dispatch',p_request_sha256,p_payload);if prior is not null then return prior;end if;
 select *into g from collect_receipt_successors.execution_events where attempt_id=s.id and event_kind='grant';
 if g.id is null or g.job_id<>j.id or g.approval_id<>j.approval_id or g.candidate_sha256<>j.candidate_sha256
  or g.request_id<>s.grant_request_id or exists(select 1 from collect_receipt_successors.arms where attempt_id=s.id)
  or exists(select 1 from collect_receipt_successors.attempt_revocations where attempt_id=s.id)
  or s.expires_at<=clock_timestamp()or s.policy_revision<>r.policy_revision
  or s.body_sha256 is distinct from p_payload->>'body_sha256'or s.destination_sha256 is distinct from p_payload->>'destination_sha256'then
  raise exception 'receipt_successor_arm_fenced'using errcode='55000';end if;
 perform collect_receipt_successors.lock_preview_source(j.root_outbox_id);
 perform 1 from public.feature_flags where key='hybrid_sms_notifications'for share nowait;
 if not coalesce((select enabled from public.feature_flags where key='hybrid_sms_notifications'),false)then raise exception 'receipt_dispatch_paused'using errcode='55000';end if;
 a:=collect_receipt_successors.require_approval(j.approval_id,g.lineage_after);
 h:=collect_gateway_dispatch.ready_health(p_device_id);
 if h.id is null or h.sim_revision_sha256 is distinct from s.sim_revision_sha256 then raise exception 'receipt_successor_device_not_ready'using errcode='55000';end if;
 r:=collect_receipt_operations.require_run(s.run_id,s.fence_version,s.principal_id);a:=collect_receipt_successors.require_approval(j.approval_id,g.lineage_after);t:=clock_timestamp();
 if t>=s.expires_at or t>=r.expires_at or t>=a.expires_at then raise exception 'receipt_successor_expired'using errcode='55000';end if;
 insert into collect_receipt_successors.arms values(s.id,p_request_id,p_payload->>'reservation_sha256',p_payload->'route',p_payload->'callbacks',h.id,t,s.expires_at);
 after_revision:=collect_receipt_successors.advance(j.root_outbox_id);
 if after_revision<>g.lineage_after+1 then raise exception 'receipt_successor_causal_event_invalid'using errcode='55000';end if;
 insert into collect_receipt_successors.execution_events(job_id,attempt_id,root_outbox_id,approval_id,approved_event_id,approval_request_id,request_id,event_kind,lineage_before,lineage_after,candidate_sha256,recorded_at)
  values(j.id,s.id,j.root_outbox_id,a.id,g.approved_event_id,g.approval_request_id,p_request_id,'arm',g.lineage_after,after_revision,j.candidate_sha256,t);
 result:=jsonb_build_object('contract_version',1,'protocol_family','receipt_successor','ok',true,'code','SUCCESSOR_ARMED','device_id',p_device_id,'request_id',p_request_id,'route',p_payload->'route',
  'attempt_id',s.id,'fence_version',s.fence_version,'reservation_sha256',p_payload->>'reservation_sha256','armed_at',collect_gateway.utc(t),'expires_at',collect_gateway.utc(s.expires_at),
  'replay',false,'send_authority',true,'carrier_proof',false,'delivery_proven',false);
 perform collect_receipt_successors.store(p_device_id,p_request_id,'arm_dispatch',p_request_sha256,p_payload,p_payload->'route',collect_receipt_successors.refusal(p_device_id,p_request_id,'ORIGINAL_REQUEST_RECORDED',true));return result;
 exception when lock_not_available then raise exception 'receipt_successor_source_busy'using errcode='55000';end$$;

revoke all on all functions in schema collect_receipt_successors from public,anon,authenticated,service_role;
revoke all on function public.gateway_receipt_successor_grant_v1(uuid,uuid,text,jsonb),public.gateway_receipt_successor_arm_v1(uuid,uuid,text,jsonb)from public,anon,authenticated;
grant execute on function public.gateway_receipt_successor_grant_v1(uuid,uuid,text,jsonb),public.gateway_receipt_successor_arm_v1(uuid,uuid,text,jsonb)to service_role;
-- Exact retained public review body, and OID-preserving reviewed arm fence.
do $guard$begin
 if(select prosrc from pg_proc where oid='public.admin_revoke_receipt_successor_v1(uuid,uuid,bigint,text)'::regprocedure)is distinct from $prior_revoke$
declare sid uuid;a collect_receipt_successors.approvals;prior collect_receipt_successors.owner_requests;
 root uuid;lr bigint;ih text;reason text:=btrim(coalesce(p_reason,''));t timestamptz;result jsonb;begin
 sid:=collect_receipt_actions.actor(true);
 if p_request_id is null or p_approval_id is null or p_expected_lineage_revision is null
  or p_expected_lineage_revision not between 1 and 999999999 or char_length(reason)not between 8 and 500 then
  raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 ih:=encode(extensions.digest(jsonb_build_array(p_approval_id,p_expected_lineage_revision,reason)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-successor-owner:'||p_request_id::text,0));
 select *into prior from collect_receipt_successors.owner_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.action<>'revoke_successor'or prior.input_sha256<>ih then
   raise exception 'receipt_successor_request_conflict'using errcode='22023';end if;
  perform collect_receipt_actions.actor(true);return prior.result;end if;
 select root_outbox_id into root from collect_receipt_successors.approvals where id=p_approval_id;
 perform 1 from collect_receipt_operations.policy where singleton for update;
 perform 1 from collect_hybrid.sms_notification_outbox where id=root for update;
 select *into a from collect_receipt_successors.approvals where id=p_approval_id for share;
 perform collect_receipt_actions.actor(true);
 if a.id is null then raise exception 'receipt_successor_approval_unavailable'using errcode='55000';end if;
 select revision into lr from collect_receipt_successors.lineage_heads where root_outbox_id=root;
 if lr<>p_expected_lineage_revision then raise exception 'receipt_successor_source_changed'using errcode='55000';end if;
 if exists(select 1 from collect_receipt_successors.approval_events where approval_id=a.id and event_kind='revoked')then
  raise exception 'receipt_successor_already_revoked'using errcode='55000';end if;
 -- There are no execution tables or arms in this slice. A later execution
 -- migration must add its grant/arm fence before this service can coexist.
 lr:=collect_receipt_successors.advance(root);perform collect_receipt_actions.actor(true);t:=clock_timestamp();
 insert into collect_receipt_successors.approval_events(approval_id,revision,event_kind,request_id,actor_id,session_id,lineage_revision,reason,recorded_at)
 values(a.id,2,'revoked',p_request_id,auth.uid(),sid,lr,reason,t);
 result:=jsonb_build_object('contract_version',1,'scope','rw_receipt_successors','action','revoke_successor','request_id',p_request_id,
  'outbox_id',root,'approval_id',a.id,'expected_lineage_revision',p_expected_lineage_revision,'lineage_revision',lr,'recorded_at',collect_ops.utc(t),
  'financial_action',false,'send_action',false,'primary_receipt_retained',true,'carrier_proof',false,'delivery_proven',false);
 insert into collect_receipt_successors.owner_requests values(p_request_id,auth.uid(),sid,'revoke_successor',ih,result,t);
 perform public.create_audit_log('notification.successor.revoked','sms_notification_outbox',root,
  jsonb_build_object('request_id',p_request_id,'approval_id',a.id,'lineage_revision',lr),auth.uid());return result;
 exception when lock_not_available then raise exception 'receipt_successor_source_busy'using errcode='55P03';end$prior_revoke$then raise exception 'receipt_successor_revoke_predecessor_changed'using errcode='55000';end if;
 if(select proowner from pg_proc where oid='public.admin_revoke_receipt_successor_v1(uuid,uuid,bigint,text)'::regprocedure)<>current_user::regrole then raise exception 'receipt_successor_revoke_owner_changed'using errcode='55000';end if;
end$guard$;
create function collect_receipt_successors.retained_review_revocation(p_request_id uuid,p_approval_id uuid,p_expected_lineage_revision bigint,p_reason text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;a collect_receipt_successors.approvals;prior collect_receipt_successors.owner_requests;
 root uuid;lr bigint;ih text;reason text:=btrim(coalesce(p_reason,''));t timestamptz;result jsonb;begin
 sid:=collect_receipt_actions.actor(true);
 if p_request_id is null or p_approval_id is null or p_expected_lineage_revision is null
  or p_expected_lineage_revision not between 1 and 999999999 or char_length(reason)not between 8 and 500 then
  raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 ih:=encode(extensions.digest(jsonb_build_array(p_approval_id,p_expected_lineage_revision,reason)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-successor-owner:'||p_request_id::text,0));
 select *into prior from collect_receipt_successors.owner_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.action<>'revoke_successor'or prior.input_sha256<>ih then
   raise exception 'receipt_successor_request_conflict'using errcode='22023';end if;
  perform collect_receipt_actions.actor(true);return prior.result;end if;
 select root_outbox_id into root from collect_receipt_successors.approvals where id=p_approval_id;
 perform 1 from collect_receipt_operations.policy where singleton for update;
 perform 1 from collect_hybrid.sms_notification_outbox where id=root for update;
 select *into a from collect_receipt_successors.approvals where id=p_approval_id for share;
 perform collect_receipt_actions.actor(true);
 if a.id is null then raise exception 'receipt_successor_approval_unavailable'using errcode='55000';end if;
 select revision into lr from collect_receipt_successors.lineage_heads where root_outbox_id=root;
 if lr<>p_expected_lineage_revision then raise exception 'receipt_successor_source_changed'using errcode='55000';end if;
 if exists(select 1 from collect_receipt_successors.approval_events where approval_id=a.id and event_kind='revoked')then
  raise exception 'receipt_successor_already_revoked'using errcode='55000';end if;
 -- There are no execution tables or arms in this slice. A later execution
 -- migration must add its grant/arm fence before this service can coexist.
 lr:=collect_receipt_successors.advance(root);perform collect_receipt_actions.actor(true);t:=clock_timestamp();
 insert into collect_receipt_successors.approval_events(approval_id,revision,event_kind,request_id,actor_id,session_id,lineage_revision,reason,recorded_at)
 values(a.id,2,'revoked',p_request_id,auth.uid(),sid,lr,reason,t);
 result:=jsonb_build_object('contract_version',1,'scope','rw_receipt_successors','action','revoke_successor','request_id',p_request_id,
  'outbox_id',root,'approval_id',a.id,'expected_lineage_revision',p_expected_lineage_revision,'lineage_revision',lr,'recorded_at',collect_ops.utc(t),
  'financial_action',false,'send_action',false,'primary_receipt_retained',true,'carrier_proof',false,'delivery_proven',false);
 insert into collect_receipt_successors.owner_requests values(p_request_id,auth.uid(),sid,'revoke_successor',ih,result,t);
 perform public.create_audit_log('notification.successor.revoked','sms_notification_outbox',root,
  jsonb_build_object('request_id',p_request_id,'approval_id',a.id,'lineage_revision',lr),auth.uid());return result;
 exception when lock_not_available then raise exception 'receipt_successor_source_busy'using errcode='55P03';end$$;
create or replace function public.admin_revoke_receipt_successor_v1(p_request_id uuid,p_approval_id uuid,p_expected_lineage_revision bigint,p_reason text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;a collect_receipt_successors.approvals;prior collect_receipt_successors.owner_requests;
 root uuid;lr bigint;ih text;reason text:=btrim(coalesce(p_reason,''));t timestamptz;result jsonb;begin
 sid:=collect_receipt_actions.actor(true);
 if p_request_id is null or p_approval_id is null or p_expected_lineage_revision is null
  or p_expected_lineage_revision not between 1 and 999999999 or char_length(reason)not between 8 and 500 then
  raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 ih:=encode(extensions.digest(jsonb_build_array(p_approval_id,p_expected_lineage_revision,reason)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-successor-owner:'||p_request_id::text,0));
 select *into prior from collect_receipt_successors.owner_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.action<>'revoke_successor'or prior.input_sha256<>ih then
   raise exception 'receipt_successor_request_conflict'using errcode='22023';end if;
  perform collect_receipt_actions.actor(true);return prior.result;end if;
 select root_outbox_id into root from collect_receipt_successors.approvals where id=p_approval_id;
 perform 1 from collect_receipt_operations.policy where singleton for update;
 perform 1 from collect_hybrid.sms_notification_outbox where id=root for update;
 select *into a from collect_receipt_successors.approvals where id=p_approval_id for share;
 perform collect_receipt_actions.actor(true);
 if a.id is null then raise exception 'receipt_successor_approval_unavailable'using errcode='55000';end if;
 select revision into lr from collect_receipt_successors.lineage_heads where root_outbox_id=root;
 if exists(select 1 from collect_receipt_successors.jobs j join collect_receipt_successors.attempts s on s.job_id=j.id join collect_receipt_successors.arms arm on arm.attempt_id=s.id where j.approval_id=a.id)then
  raise exception 'receipt_successor_approval_already_armed'using errcode='55000';end if;
 if lr<>p_expected_lineage_revision then raise exception 'receipt_successor_source_changed'using errcode='55000';end if;
 if exists(select 1 from collect_receipt_successors.approval_events where approval_id=a.id and event_kind='revoked')then
  raise exception 'receipt_successor_already_revoked'using errcode='55000';end if;
 -- Policy/root locks serialize this revocation with the final successor arm.
 lr:=collect_receipt_successors.advance(root);perform collect_receipt_actions.actor(true);t:=clock_timestamp();
 insert into collect_receipt_successors.approval_events(approval_id,revision,event_kind,request_id,actor_id,session_id,lineage_revision,reason,recorded_at)
 values(a.id,2,'revoked',p_request_id,auth.uid(),sid,lr,reason,t);
 insert into collect_receipt_successors.attempt_revocations(attempt_id,approval_event_id,recorded_at)
 select s.id,e.id,t from collect_receipt_successors.attempts s join collect_receipt_successors.jobs j on j.id=s.job_id
 join collect_receipt_successors.approval_events e on e.approval_id=j.approval_id and e.event_kind='revoked'and e.request_id=p_request_id
 where j.approval_id=a.id;
 result:=jsonb_build_object('contract_version',1,'scope','rw_receipt_successors','action','revoke_successor','request_id',p_request_id,
  'outbox_id',root,'approval_id',a.id,'expected_lineage_revision',p_expected_lineage_revision,'lineage_revision',lr,'recorded_at',collect_ops.utc(t),
  'financial_action',false,'send_action',false,'primary_receipt_retained',true,'carrier_proof',false,'delivery_proven',false);
 insert into collect_receipt_successors.owner_requests values(p_request_id,auth.uid(),sid,'revoke_successor',ih,result,t);
 perform public.create_audit_log('notification.successor.revoked','sms_notification_outbox',root,
  jsonb_build_object('request_id',p_request_id,'approval_id',a.id,'lineage_revision',lr),auth.uid());return result;
 exception when lock_not_available then raise exception 'receipt_successor_source_busy'using errcode='55P03';end$$;
revoke all on function collect_receipt_successors.retained_review_revocation(uuid,uuid,bigint,text)from public,anon,authenticated,service_role;

create function collect_receipt_successors.verify_execution()returns trigger
language plpgsql security definer set search_path=''as $$
declare s collect_receipt_successors.attempts;j collect_receipt_successors.jobs;a collect_receipt_successors.approvals;
 e collect_receipt_successors.execution_events;g collect_receipt_successors.execution_events;
 approved collect_receipt_successors.approval_events;request collect_receipt_successors.gateway_requests;
 arm collect_receipt_successors.arms;kind text;begin
 if tg_table_name='attempts'then select *into s from collect_receipt_successors.attempts where id=new.id;kind:='grant';
 else
  select *into s from collect_receipt_successors.attempts where id=new.attempt_id;
  if tg_table_name='arms'then kind:='arm';else kind:=new.event_kind;end if;
 end if;
 select *into j from collect_receipt_successors.jobs where id=s.job_id;select *into a from collect_receipt_successors.approvals where id=j.approval_id;
 select *into e from collect_receipt_successors.execution_events where attempt_id=s.id and event_kind=kind;
 select *into approved from collect_receipt_successors.approval_events where id=e.approved_event_id;
 select *into request from collect_receipt_successors.gateway_requests where request_id=e.request_id;
 if e.id is null or e.job_id<>j.id or e.root_outbox_id<>j.root_outbox_id or e.approval_id<>a.id
  or e.approval_request_id<>a.request_id or e.candidate_sha256<>j.candidate_sha256
  or approved.approval_id<>a.id or approved.event_kind<>'approved'or approved.request_id<>a.request_id
  or request.request_id is null or request.device_id<>s.device_id
  or request.route is distinct from collect_receipt_successors.route(j.id)
  or request.result is distinct from collect_receipt_successors.refusal(s.device_id,e.request_id,'ORIGINAL_REQUEST_RECORDED',true)then
  raise exception 'receipt_successor_execution_proof_invalid'using errcode='55000';end if;
 if kind='grant'then
  if e.request_id<>s.grant_request_id or e.lineage_before<>approved.lineage_revision or request.action<>'dispatch_grant'
   or request.payload is distinct from '{}'::jsonb then raise exception 'receipt_successor_grant_proof_invalid'using errcode='55000';end if;
 else
  select *into g from collect_receipt_successors.execution_events where attempt_id=s.id and event_kind='grant';
  select *into arm from collect_receipt_successors.arms where attempt_id=s.id;
  if g.id is null or arm.attempt_id is null or e.lineage_before<>g.lineage_after or e.approved_event_id<>g.approved_event_id
   or arm.request_id<>e.request_id or request.action<>'arm_dispatch'
   or arm.route is distinct from request.route or request.payload->'route' is distinct from arm.route
   or request.payload->>'attempt_id' is distinct from s.id::text
   or request.payload->>'fence_version' is distinct from s.fence_version::text
   or request.payload->>'reservation_sha256' is distinct from arm.reservation_sha256
   or request.payload->'callbacks' is distinct from arm.callback_plan
   or request.payload->>'body_sha256' is distinct from s.body_sha256
   or request.payload->>'destination_sha256' is distinct from s.destination_sha256
   or exists(select 1 from collect_receipt_successors.attempt_revocations where attempt_id=s.id)then
   raise exception 'receipt_successor_arm_proof_invalid'using errcode='55000';end if;
 end if;return null;end$$;
create constraint trigger successor_attempt_execution_proof after insert on collect_receipt_successors.attempts
 deferrable initially deferred for each row execute function collect_receipt_successors.verify_execution();
create constraint trigger successor_event_execution_proof after insert on collect_receipt_successors.execution_events
 deferrable initially deferred for each row execute function collect_receipt_successors.verify_execution();
create constraint trigger successor_arm_execution_proof after insert on collect_receipt_successors.arms
 deferrable initially deferred for each row execute function collect_receipt_successors.verify_execution();
create function collect_receipt_successors.verify_revocation()returns trigger
language plpgsql security definer set search_path=''as $$
declare e collect_receipt_successors.approval_events;approval uuid;begin
 select j.approval_id into approval from collect_receipt_successors.attempts s join collect_receipt_successors.jobs j on j.id=s.job_id where s.id=new.attempt_id;
 select *into e from collect_receipt_successors.approval_events where id=new.approval_event_id;
 if e.id is null or e.approval_id is distinct from approval or e.event_kind<>'revoked'
  or new.recorded_at<>e.recorded_at or exists(select 1 from collect_receipt_successors.arms where attempt_id=new.attempt_id)then
  raise exception 'receipt_successor_revocation_proof_invalid'using errcode='55000';end if;return null;end$$;
create constraint trigger successor_revocation_execution_proof after insert on collect_receipt_successors.attempt_revocations
 deferrable initially deferred for each row execute function collect_receipt_successors.verify_revocation();

create function public.gateway_receipt_successor_reconcile_v1(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare target uuid;r collect_receipt_successors.gateway_requests;begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);perform collect_gateway.payload_keys(p_payload,array['target_request_id']);
 target:=collect_gateway.payload_uuid(p_payload,'target_request_id');if target=p_request_id then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
 if not exists(select 1 from collect_gateway.devices where id=p_device_id)then raise exception 'gateway_device_not_found'using errcode='42501';end if;
 select *into r from collect_receipt_successors.gateway_requests where request_id=target and device_id=p_device_id;
 return jsonb_build_object('contract_version',1,'protocol_family','receipt_successor','target_request_id',target,
  'outcome',case when r.request_id is null then 'unknown'else 'recorded'end,'recorded_action',r.action,'recorded_route',r.route,'recorded_result',r.result,
  'send_authority',false,'carrier_proof',false,'delivery_proven',false);end$$;
create function collect_receipt_successors.execution_read(p_approval uuid)returns jsonb
language sql volatile set search_path=''as $$
 select jsonb_build_object('approval_id',a.id,'primary_receipt_id',a.root_outbox_id,'route',collect_receipt_successors.route(j.id),
  'status',case when j.id is null then 'not_materialized'when arm.attempt_id is not null then 'armed_unknown'
   when revoked.attempt_id is not null then 'unarmed_revoked'when s.expires_at<=clock_timestamp()then 'unarmed_expired'else 'unarmed_granted'end,
  'attempt_id',s.id,'run_id',s.run_id,'fence_version',s.fence_version,'issued_at',collect_gateway.utc(s.issued_at),'expires_at',collect_gateway.utc(s.expires_at),
  'armed_at',collect_gateway.utc(arm.armed_at),'grant_request_id',s.grant_request_id,'arm_request_id',arm.request_id,
  'reservation_id',s.reservation_id,'segment_count',s.segment_count,'body_sha256',s.body_sha256,'destination_sha256',s.destination_sha256,
  'revocation_event_id',revoked.approval_event_id,
  'events',coalesce((select jsonb_agg(jsonb_build_object('event_id',e.id,'event_kind',e.event_kind,'request_id',e.request_id,
   'approved_event_id',e.approved_event_id,'approval_request_id',e.approval_request_id,'lineage_before',e.lineage_before,'lineage_after',e.lineage_after,'recorded_at',collect_gateway.utc(e.recorded_at))order by e.lineage_after)
   from collect_receipt_successors.execution_events e where e.job_id=j.id),'[]'::jsonb),
  'callback_evidence_supported',false,'callback_observations',0,'terminal_archive_ack',false,'send_authority',false,'carrier_proof',false,'delivery_proven',false)
 from collect_receipt_successors.approvals a left join collect_receipt_successors.jobs j on j.approval_id=a.id
 left join collect_receipt_successors.attempts s on s.job_id=j.id left join collect_receipt_successors.arms arm on arm.attempt_id=s.id
 left join collect_receipt_successors.attempt_revocations revoked on revoked.attempt_id=s.id where a.id=p_approval
$$;
create function public.admin_get_receipt_successor_execution_v2(p_approval_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare value jsonb;begin
 perform collect_receipt_actions.actor(false);if p_approval_id is null then raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 value:=collect_receipt_successors.execution_read(p_approval_id);perform collect_receipt_actions.actor(false);
 return jsonb_build_object('contract_version',2,'scope','rw_receipt_successor_execution','approval_id',p_approval_id,
  'status',case when value is null then 'unavailable'else 'available'end,'execution',value,'financial_action',false,'send_action',false,'carrier_proof',false,'delivery_proven',false);end$$;
revoke all on all functions in schema collect_receipt_successors from public,anon,authenticated,service_role;
revoke all on function public.gateway_receipt_successor_reconcile_v1(uuid,uuid,text,jsonb)from public,anon,authenticated;
grant execute on function public.gateway_receipt_successor_reconcile_v1(uuid,uuid,text,jsonb)to service_role;
revoke all on function public.admin_get_receipt_successor_execution_v2(uuid)from public,anon,authenticated,service_role;
grant execute on function public.admin_get_receipt_successor_execution_v2(uuid)to authenticated;

-- Successor observation and retention continuation, same atomic migration.
insert into collect_receipt_successors.content_policies(version,choices,owner_message)values(4,
 '{"protocol_family":"receipt_successor","callback_route_required":true,"late_evidence_after_stop_revocation_and_archive":true,"journal_ack_is_delivery_proof":false,"journal_ack_is_resend_authority":false,"immutable_archive_evidence":true,"configuration_enabled":false}'::jsonb,
 'Additive successor observation and journal retention contract. Framework facts and journal ACK confer neither carrier delivery proof nor resend authority. Existing v2 financial decision and inactive configuration are retained.');
-- Additive successor transport observations and journal retention only.
-- Framework observations and archive ACK do not prove carrier delivery.
create table collect_receipt_successors.callbacks(
 request_id uuid primary key references collect_receipt_successors.gateway_requests(request_id)on delete restrict deferrable initially deferred,
 callback_id uuid not null,attempt_id uuid not null references collect_receipt_successors.attempts(id)on delete restrict,
 segment_index integer not null check(segment_index between 0 and 9),callback_kind text not null check(callback_kind in('sent','delivery')),
 result_code integer not null check(result_code between -1 and 200),tp_status integer check(tp_status between 0 and 255),
 occurred_at timestamptz not null check(isfinite(occurred_at)),recorded_at timestamptz not null check(isfinite(recorded_at)));
create index successor_callbacks_attempt on collect_receipt_successors.callbacks(attempt_id,segment_index,callback_kind,recorded_at,request_id);
create table collect_receipt_successors.observation_events(
 request_id uuid primary key references collect_receipt_successors.callbacks(request_id)on delete restrict deferrable initially deferred,
 root_outbox_id uuid not null references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 attempt_id uuid not null references collect_receipt_successors.attempts(id)on delete restrict,
 lineage_before bigint not null check(lineage_before between 1 and 999999999),lineage_after bigint not null check(lineage_after=lineage_before+1),
 observed_state text not null check(observed_state in('armed_unknown','observed_sent','uncertain')),recorded_at timestamptz not null check(isfinite(recorded_at)),
 unique(root_outbox_id,lineage_after));
create table collect_receipt_successors.archive_acknowledgements(
 id uuid primary key default gen_random_uuid(),request_id uuid not null unique references collect_receipt_successors.gateway_requests(request_id)on delete restrict deferrable initially deferred,
 attempt_id uuid not null unique references collect_receipt_successors.attempts(id)on delete restrict,route jsonb not null,
 callback_requests jsonb not null check(jsonb_typeof(callback_requests)='array'),evidence jsonb not null check(jsonb_typeof(evidence)='object'),
 evidence_sha256 text not null check(evidence_sha256~'^[0-9a-f]{64}$'),recorded_at timestamptz not null check(isfinite(recorded_at)));
do $$declare name text;begin foreach name in array array['callbacks','observation_events','archive_acknowledgements']loop
 execute format('alter table collect_receipt_successors.%I enable row level security',name);
 execute format('revoke all on collect_receipt_successors.%I from public,anon,authenticated,service_role',name);
 execute format('create trigger retained_transport_identity before update or delete on collect_receipt_successors.%I for each row execute function collect_gateway_transport.immutable()',name);
 execute format('create trigger retained_transport_identity_truncate before truncate on collect_receipt_successors.%I for each statement execute function collect_gateway_transport.immutable()',name);
 end loop;end$$;
create function collect_receipt_successors.transport_status(p_attempt uuid)returns jsonb
language plpgsql volatile set search_path=''as $$declare a collect_receipt_successors.attempts;arm collect_receipt_successors.arms;
 s integer;d integer;conflict boolean;failure boolean;state text;begin
 select *into a from collect_receipt_successors.attempts where id=p_attempt;select *into arm from collect_receipt_successors.arms where attempt_id=p_attempt;
 if a.id is null then return null;end if;
 select count(distinct segment_index)filter(where callback_kind='sent'),count(distinct segment_index)filter(where callback_kind='delivery')into s,d from collect_receipt_successors.callbacks where attempt_id=a.id;
 select exists(select 1 from collect_receipt_successors.callbacks where attempt_id=a.id group by segment_index,callback_kind having count(distinct jsonb_build_array(result_code,tp_status))>1)into conflict;
 select exists(select 1 from collect_receipt_successors.callbacks where attempt_id=a.id and(callback_kind='sent'and result_code<>-1 or callback_kind='delivery'and(result_code<>-1 or coalesce(tp_status,0)>=64)))into failure;
 state:=case when arm.attempt_id is null then case when exists(select 1 from collect_receipt_successors.attempt_revocations where attempt_id=a.id)then'unarmed_revoked'when a.expires_at<=clock_timestamp()then'unarmed_expired'else'unarmed_granted'end
  when conflict or failure then'uncertain'when s=a.segment_count then'observed_sent'else'armed_unknown'end;
 return jsonb_build_object('contract_version',1,'protocol_family','receipt_successor','route',collect_receipt_successors.route(a.job_id),
  'attempt_id',a.id,'fence_version',a.fence_version,'state',state,'segment_count',a.segment_count,'armed_at',collect_gateway.utc(arm.armed_at),
  'sent_observations',s,'delivery_observations',d,'conflicting_observations',conflict,'failed_observations',failure,
  'terminal_archive_ack',exists(select 1 from collect_receipt_successors.archive_acknowledgements where attempt_id=a.id),
  'send_authority',false,'carrier_proof',false,'delivery_proven',false);end$$;
create function public.gateway_receipt_successor_callback_v1(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare a collect_receipt_successors.attempts;arm collect_receipt_successors.arms;
 cb uuid;job uuid;idx integer;n integer;code integer;tp integer;occurred timestamptz;t timestamptz;prior jsonb;fold jsonb;result jsonb;before_revision bigint;after_revision bigint;root uuid;begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);perform collect_receipt_successors.request_lock(p_device_id,p_request_id,p_request_sha256);
 perform collect_gateway.payload_keys(p_payload,array['route','callback_id','attempt_id','fence_version','segment_index','segment_count','body_sha256','destination_sha256','callback_kind','result_code','tp_status','occurred_at']);
 job:=collect_receipt_successors.validate_route(p_payload->'route');cb:=collect_gateway.payload_uuid(p_payload,'callback_id');if cb=p_request_id then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
 idx:=collect_gateway.payload_int(p_payload,'segment_index',0,9);n:=collect_gateway.payload_int(p_payload,'segment_count',1,10);code:=collect_gateway.payload_int(p_payload,'result_code',-1,200);occurred:=collect_gateway.payload_time(p_payload,'occurred_at');
 if jsonb_typeof(p_payload->'tp_status')is distinct from'null'then tp:=collect_gateway.payload_int(p_payload,'tp_status',0,255);end if;
 if jsonb_typeof(p_payload->'callback_kind')is distinct from'string'or coalesce(p_payload->>'callback_kind','')not in('sent','delivery')then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
 select *into a from collect_receipt_successors.attempts where id=collect_gateway.payload_uuid(p_payload,'attempt_id')and job_id=job;
 if a.id is null or a.device_id<>p_device_id then raise exception 'receipt_successor_attempt_unavailable'using errcode='42501';end if;
 select root_outbox_id into root from collect_receipt_successors.jobs where id=a.job_id;perform 1 from collect_hybrid.sms_notification_outbox where id=root for update;
 perform 1 from collect_gateway.devices where id=p_device_id for share;
 prior:=collect_receipt_successors.replay(p_device_id,p_request_id,'callback',p_request_sha256,p_payload);if prior is not null then return prior;end if;
 select *into arm from collect_receipt_successors.arms where attempt_id=a.id;t:=clock_timestamp();
 if arm.attempt_id is null or a.fence_version<>collect_gateway.payload_int(p_payload,'fence_version',1,1000000000)
  or a.body_sha256 is distinct from p_payload->>'body_sha256'or a.destination_sha256 is distinct from p_payload->>'destination_sha256'
  or n<>a.segment_count or idx>=n or cb is distinct from((arm.callback_plan->idx)->>case p_payload->>'callback_kind'when'sent'then'sent_callback_id'else'delivery_callback_id'end)::uuid
  or occurred<arm.armed_at-interval'120 seconds'or occurred>t+interval'30 seconds'then raise exception 'receipt_successor_callback_binding_invalid'using errcode='22023';end if;
 select revision into before_revision from collect_receipt_successors.lineage_heads where root_outbox_id=root;
 insert into collect_receipt_successors.callbacks values(p_request_id,cb,a.id,idx,p_payload->>'callback_kind',code,tp,occurred,t);
 fold:=collect_receipt_successors.transport_status(a.id);after_revision:=collect_receipt_successors.advance(root);
 insert into collect_receipt_successors.observation_events values(p_request_id,root,a.id,before_revision,after_revision,fold->>'state',t);
 result:=jsonb_build_object('contract_version',1,'protocol_family','receipt_successor','route',p_payload->'route','callback_id',cb,'attempt_id',a.id,
  'recorded_at',collect_gateway.utc(t),'replay',false,'state',fold->'state','sent_observations',fold->'sent_observations','delivery_observations',fold->'delivery_observations',
  'conflicting_observations',fold->'conflicting_observations','failed_observations',fold->'failed_observations','send_authority',false,'carrier_proof',false,'delivery_proven',false);
 perform collect_receipt_successors.store(p_device_id,p_request_id,'callback',p_request_sha256,p_payload,p_payload->'route',result);return result;end$$;
create function public.gateway_receipt_successor_attempt_status_v1(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare a collect_receipt_successors.attempts;job uuid;root uuid;begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);perform collect_gateway.payload_keys(p_payload,array['route','attempt_id','fence_version']);
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'receipt_successor_snapshot_retry'using errcode='40001';end if;
 job:=collect_receipt_successors.validate_route(p_payload->'route');select *into a from collect_receipt_successors.attempts where id=collect_gateway.payload_uuid(p_payload,'attempt_id')and device_id=p_device_id and job_id=job;
 if a.id is null or a.fence_version<>collect_gateway.payload_int(p_payload,'fence_version',1,1000000000)then raise exception 'receipt_successor_attempt_unavailable'using errcode='42501';end if;
 select root_outbox_id into root from collect_receipt_successors.jobs where id=a.job_id;perform 1 from collect_hybrid.sms_notification_outbox where id=root for share;
 return collect_receipt_successors.transport_status(a.id);end$$;
create function public.gateway_receipt_successor_archive_v1(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare a collect_receipt_successors.attempts;arm collect_receipt_successors.arms;ack collect_receipt_successors.archive_acknowledgements;
 job uuid;root uuid;ref jsonb;cb collect_receipt_successors.callbacks;r collect_receipt_successors.gateway_requests;
 prior jsonb;seen uuid[]:=array[]::uuid[];refs uuid[]:=array[]::uuid[];expected uuid[];evidence jsonb;result jsonb;t timestamptz;begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);perform collect_receipt_successors.request_lock(p_device_id,p_request_id,p_request_sha256);
 perform collect_gateway.payload_keys(p_payload,array['route','attempt_id','fence_version','body_sha256','destination_sha256','callback_requests']);job:=collect_receipt_successors.validate_route(p_payload->'route');
 select *into a from collect_receipt_successors.attempts where id=collect_gateway.payload_uuid(p_payload,'attempt_id')and job_id=job and device_id=p_device_id;
 if a.id is null then raise exception 'receipt_successor_attempt_unavailable'using errcode='42501';end if;
 select root_outbox_id into root from collect_receipt_successors.jobs where id=a.job_id;perform 1 from collect_hybrid.sms_notification_outbox where id=root for update;
 perform 1 from collect_gateway.devices where id=p_device_id for share;
 prior:=collect_receipt_successors.replay(p_device_id,p_request_id,'archive_attempt',p_request_sha256,p_payload);if prior is not null then return prior;end if;
 select *into arm from collect_receipt_successors.arms where attempt_id=a.id;
 if arm.attempt_id is null or a.fence_version<>collect_gateway.payload_int(p_payload,'fence_version',1,1000000000)
  or a.body_sha256 is distinct from p_payload->>'body_sha256'or a.destination_sha256 is distinct from p_payload->>'destination_sha256'
  or jsonb_typeof(p_payload->'callback_requests')is distinct from'array'or jsonb_array_length(p_payload->'callback_requests')<>2*a.segment_count then raise exception 'receipt_successor_archive_binding_invalid'using errcode='22023';end if;
 select array_agg(id order by id)into expected from(select(x->>'sent_callback_id')::uuid id from jsonb_array_elements(arm.callback_plan)x union all select(x->>'delivery_callback_id')::uuid from jsonb_array_elements(arm.callback_plan)x)ids;
 for ref in select value from jsonb_array_elements(p_payload->'callback_requests')loop
  perform collect_gateway.payload_keys(ref,array['callback_id','request_id','request_sha256']);
  if collect_gateway.payload_uuid(ref,'callback_id')=any(seen)or collect_gateway.payload_uuid(ref,'request_id')=any(refs)or jsonb_typeof(ref->'request_sha256')is distinct from'string'or ref->>'request_sha256'!~'^[0-9a-f]{64}$'then raise exception 'receipt_successor_archive_binding_invalid'using errcode='22023';end if;
  seen:=seen||collect_gateway.payload_uuid(ref,'callback_id');refs:=refs||collect_gateway.payload_uuid(ref,'request_id');
  select *into cb from collect_receipt_successors.callbacks where request_id=collect_gateway.payload_uuid(ref,'request_id');select *into r from collect_receipt_successors.gateway_requests where request_id=cb.request_id;
  if cb.request_id is null or cb.attempt_id<>a.id or cb.callback_id<>collect_gateway.payload_uuid(ref,'callback_id')or r.device_id<>p_device_id or r.action<>'callback'or r.request_sha256 is distinct from ref->>'request_sha256'or r.route is distinct from p_payload->'route'then
   result:=collect_receipt_successors.refusal(p_device_id,p_request_id,'CALLBACK_EVIDENCE_INCOMPLETE');return collect_receipt_successors.store(p_device_id,p_request_id,'archive_attempt',p_request_sha256,p_payload,p_payload->'route',result);end if;
 end loop;
 if(array(select unnest(seen)order by 1))is distinct from expected then raise exception 'receipt_successor_archive_binding_invalid'using errcode='22023';end if;
 select *into ack from collect_receipt_successors.archive_acknowledgements where attempt_id=a.id;
 if ack.id is not null then raise exception 'receipt_successor_archive_already_acknowledged'using errcode='55000';end if;
 t:=clock_timestamp();evidence:=jsonb_build_object('lineage_revision',(select revision from collect_receipt_successors.lineage_heads where root_outbox_id=root),'route',p_payload->'route','attempt',to_jsonb(a),'arm',to_jsonb(arm),'callback_requests',p_payload->'callback_requests',
  'all_observations',(select coalesce(jsonb_agg(to_jsonb(c)order by c.request_id),'[]'::jsonb)from collect_receipt_successors.callbacks c where c.attempt_id=a.id),'status',collect_receipt_successors.transport_status(a.id));
 insert into collect_receipt_successors.archive_acknowledgements(request_id,attempt_id,route,callback_requests,evidence,evidence_sha256,recorded_at)
 values(p_request_id,a.id,p_payload->'route',p_payload->'callback_requests',evidence,encode(extensions.digest(evidence::text,'sha256'),'hex'),t)returning *into ack;
 result:=jsonb_build_object('contract_version',1,'protocol_family','receipt_successor','ok',true,'code','SUCCESSOR_JOURNAL_ARCHIVE_ACKNOWLEDGED',
  'device_id',p_device_id,'request_id',p_request_id,'route',ack.route,'attempt_id',a.id,'fence_version',a.fence_version,'body_sha256',a.body_sha256,'destination_sha256',a.destination_sha256,
  'archive_ack_id',ack.id,'evidence_sha256',ack.evidence_sha256,'callback_requests',ack.callback_requests,'recorded_at',collect_gateway.utc(t),'replay',false,
  'journal_ack',true,'send_authority',false,'carrier_proof',false,'delivery_proven',false);
 perform collect_receipt_successors.store(p_device_id,p_request_id,'archive_attempt',p_request_sha256,p_payload,p_payload->'route',result);return result;end$$;
create function collect_receipt_successors.verify_callback_proof()returns trigger
language plpgsql security definer set search_path=''as $$declare c collect_receipt_successors.callbacks;e collect_receipt_successors.observation_events;
 a collect_receipt_successors.attempts;arm collect_receipt_successors.arms;j collect_receipt_successors.jobs;r collect_receipt_successors.gateway_requests;begin
 select *into c from collect_receipt_successors.callbacks where request_id=new.request_id;
 select *into e from collect_receipt_successors.observation_events where request_id=new.request_id;
 select *into a from collect_receipt_successors.attempts where id=c.attempt_id;select *into arm from collect_receipt_successors.arms where attempt_id=a.id;
 select *into j from collect_receipt_successors.jobs where id=a.job_id;select *into r from collect_receipt_successors.gateway_requests where request_id=c.request_id;
 if c.request_id is null or e.request_id is null or a.id is null or arm.attempt_id is null or j.id is null or r.request_id is null
  or e.attempt_id<>a.id or e.root_outbox_id<>j.root_outbox_id or e.recorded_at<>c.recorded_at
  or r.action<>'callback'or r.device_id<>a.device_id or r.recorded_at<c.recorded_at or r.route is distinct from collect_receipt_successors.route(j.id)
  or r.payload->'route' is distinct from r.route
  or r.payload->>'callback_id' is distinct from c.callback_id::text or r.payload->>'attempt_id' is distinct from a.id::text
  or r.payload->>'fence_version' is distinct from a.fence_version::text or r.payload->>'segment_count' is distinct from a.segment_count::text
  or r.payload->>'segment_index' is distinct from c.segment_index::text or r.payload->>'callback_kind' is distinct from c.callback_kind
  or r.payload->>'body_sha256' is distinct from a.body_sha256 or r.payload->>'destination_sha256' is distinct from a.destination_sha256
  or r.payload->>'result_code' is distinct from c.result_code::text or(r.payload->>'tp_status')is distinct from c.tp_status::text
  or(r.payload->>'occurred_at')::timestamptz is distinct from c.occurred_at
  or c.segment_index>=a.segment_count or c.callback_id is distinct from((arm.callback_plan->c.segment_index)->>case c.callback_kind when'sent'then'sent_callback_id'else'delivery_callback_id'end)::uuid
  or r.result->>'state' is distinct from e.observed_state or r.result->'route' is distinct from r.route
  or r.result->>'callback_id' is distinct from c.callback_id::text or r.result->>'attempt_id' is distinct from a.id::text
  or r.result->'send_authority' is distinct from 'false'::jsonb or r.result->'carrier_proof' is distinct from 'false'::jsonb or r.result->'delivery_proven' is distinct from 'false'::jsonb then
  raise exception 'receipt_successor_callback_proof_invalid'using errcode='55000';end if;return null;end$$;
create constraint trigger successor_callback_retained_proof after insert on collect_receipt_successors.callbacks deferrable initially deferred for each row execute function collect_receipt_successors.verify_callback_proof();
create constraint trigger successor_observation_retained_proof after insert on collect_receipt_successors.observation_events deferrable initially deferred for each row execute function collect_receipt_successors.verify_callback_proof();
create function collect_receipt_successors.verify_archive_proof()returns trigger
language plpgsql security definer set search_path=''as $$declare a collect_receipt_successors.attempts;arm collect_receipt_successors.arms;r collect_receipt_successors.gateway_requests;j collect_receipt_successors.jobs;vector jsonb;begin
 select *into a from collect_receipt_successors.attempts where id=new.attempt_id;select *into arm from collect_receipt_successors.arms where attempt_id=a.id;
 select *into j from collect_receipt_successors.jobs where id=a.job_id;select *into r from collect_receipt_successors.gateway_requests where request_id=new.request_id;
 select coalesce(jsonb_agg(to_jsonb(c)order by c.request_id),'[]'::jsonb)into vector from collect_receipt_successors.callbacks c join collect_receipt_successors.observation_events e on e.request_id=c.request_id
 where c.attempt_id=a.id and e.lineage_after<=(new.evidence->>'lineage_revision')::bigint;
 if a.id is null or arm.attempt_id is null or j.id is null or r.request_id is null or r.action<>'archive_attempt'or r.device_id<>a.device_id
  or new.route is distinct from collect_receipt_successors.route(j.id)or r.route is distinct from new.route
  or r.payload->'callback_requests' is distinct from new.callback_requests or r.payload->'route' is distinct from new.route
  or new.evidence->'route' is distinct from new.route or new.evidence->'attempt' is distinct from to_jsonb(a)
  or new.evidence->'arm' is distinct from to_jsonb(arm)or new.evidence->'all_observations' is distinct from vector
  or new.evidence->'callback_requests' is distinct from new.callback_requests
  or new.evidence_sha256 is distinct from encode(extensions.digest(new.evidence::text,'sha256'),'hex')
  or r.result->>'archive_ack_id' is distinct from new.id::text or r.result->>'evidence_sha256' is distinct from new.evidence_sha256
  or r.result->'route' is distinct from new.route or r.result->'journal_ack' is distinct from 'true'::jsonb
  or r.result->'send_authority' is distinct from 'false'::jsonb or r.result->'carrier_proof' is distinct from 'false'::jsonb or r.result->'delivery_proven' is distinct from 'false'::jsonb then
  raise exception 'receipt_successor_archive_proof_invalid'using errcode='55000';end if;return null;end$$;
create constraint trigger successor_archive_retained_proof after insert on collect_receipt_successors.archive_acknowledgements deferrable initially deferred for each row execute function collect_receipt_successors.verify_archive_proof();
create function public.admin_get_receipt_successor_execution_v3(p_approval_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare a collect_receipt_successors.approvals;job uuid;attempt uuid;value jsonb;begin
 perform collect_receipt_actions.actor(false);if p_approval_id is null then raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 select *into a from collect_receipt_successors.approvals where id=p_approval_id;
 if a.id is not null and not exists(select 1 from collect_hybrid.sms_notification_outbox o where o.id=a.root_outbox_id and collect_receipt_actions.rwanda_source(o))then a:=null;end if;
 select id into job from collect_receipt_successors.jobs where approval_id=a.id;select id into attempt from collect_receipt_successors.attempts where job_id=job;
 value:=case when a.id is null then null else jsonb_build_object('approval_id',a.id,'primary_receipt_id',a.root_outbox_id,'route',collect_receipt_successors.route(job),'transport',collect_receipt_successors.transport_status(attempt),
  'callbacks',coalesce((select jsonb_agg(to_jsonb(c)order by c.recorded_at,c.request_id)from collect_receipt_successors.callbacks c where c.attempt_id=attempt),'[]'::jsonb),
  'observation_events',coalesce((select jsonb_agg(to_jsonb(e)order by e.lineage_after)from collect_receipt_successors.observation_events e where e.attempt_id=attempt),'[]'::jsonb),
  'archive',coalesce((select jsonb_build_object('archive_ack_id',ack.id,'request_id',ack.request_id,'route',ack.route,'callback_requests',ack.callback_requests,'evidence_sha256',ack.evidence_sha256,'recorded_at',collect_gateway.utc(ack.recorded_at),'journal_ack',true,'send_authority',false,'carrier_proof',false,'delivery_proven',false)from collect_receipt_successors.archive_acknowledgements ack where ack.attempt_id=attempt),'null'::jsonb))end;
 perform collect_receipt_actions.actor(false);return jsonb_build_object('contract_version',3,'scope','rw_receipt_successor_execution','approval_id',p_approval_id,'status',case when value is null then'unavailable'else'available'end,'execution',value,'financial_action',false,'send_action',false,'carrier_proof',false,'delivery_proven',false);end$$;
revoke all on function public.admin_get_receipt_successor_execution_v3(uuid)from public,anon,authenticated,service_role;
grant execute on function public.admin_get_receipt_successor_execution_v3(uuid)to authenticated;
-- Producers above are the sole ACL-exposed mutation paths; private tables retain RLS.
revoke all on all functions in schema collect_receipt_successors from public,anon,authenticated,service_role;
revoke all on function public.gateway_receipt_successor_callback_v1(uuid,uuid,text,jsonb),public.gateway_receipt_successor_attempt_status_v1(uuid,uuid,text,jsonb),public.gateway_receipt_successor_archive_v1(uuid,uuid,text,jsonb)from public,anon,authenticated;
grant execute on function public.gateway_receipt_successor_callback_v1(uuid,uuid,text,jsonb),public.gateway_receipt_successor_attempt_status_v1(uuid,uuid,text,jsonb),public.gateway_receipt_successor_archive_v1(uuid,uuid,text,jsonb)to service_role;
commit;
