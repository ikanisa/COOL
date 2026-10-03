begin;
select pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
select pg_advisory_xact_lock(hashtext('collect-receipt-exception-worker'));
lock table collect_ops.exceptions in share row exclusive mode;
do $guard$declare expected record;oid_value oid;begin
 for expected in select * from(values
 ('collect_receipt_operations.ensure_snapshot(uuid,boolean,boolean)','12912903ceedef3bfe389a0398d69c7e19a109b70cf4f72a57b4e839e2c4bd94'),
 ('collect_ops.receipt_exception_source(text,uuid)','405824c850f281a553361288a8ea846d0d64fe210d2818bd0ed76ffba89ad0ab'),
 ('collect_ops.observe(text,uuid,text[],jsonb)','f674207951a3fa0b545993425f9e805b545a93232e75059c56a7f40b0640a9b0'),
 ('collect_ops.refresh_source(text,uuid)','82b7cdce56bf7d3f44ec0a30daffce7ea5c839eb2804180fee79f768962553f0'),
 ('collect_ops.transaction_sms_id(text,uuid)','8eb31fb089aef24b5248e9a3b469c57851a8ce0405edef6c81d58cc330413679'),
 ('public.admin_list_operational_exceptions_v2(boolean,integer,timestamptz,uuid,text)','8e94687c361bad799b1f4fa6b3f16e83eeb95961bcf1fa4e4910fd4386a5bb3c'),
 ('collect_ops.workflow_projection(uuid)','84eee23dabb536076dfda7b4a20fb2558dd8d1209e1c2f00597c01f8a97a2d51'),
 ('public.admin_act_exception_workflow_v1(uuid,uuid,bigint,bigint,text,uuid,timestamptz,text,timestamptz)','bda39ff588f8e0ff360be1f71a5892afa900ebef738d5df51f322a094f568c52'),
 ('public.refresh_operational_exception_sources_v1(text,uuid[])','4bf30c4129eebaaa24829d9b0be951f4dfdef4f575d29fefd7c78370b9c20a3c'),
 ('collect_operator_audit.exception_scope_v2(text,uuid)','b94a1ede58c6b1153330534d2414fab0c48d2a9a7dbd814d7e68c91a93e089e9')
 )v(signature,body_sha256)loop
  oid_value:=to_regprocedure(expected.signature);
  if oid_value is null or(select encode(extensions.digest(prosrc,'sha256'),'hex')from pg_proc where oid=oid_value)is distinct from expected.body_sha256 then
   raise exception 'receipt_telemetry_predecessor_drift:%',expected.signature using errcode='55000';end if;
 end loop;
 if(select pg_get_constraintdef(oid)from pg_constraint where conrelid='collect_ops.exceptions'::regclass and conname='exceptions_source_kind_check'and contype='c'and convalidated and not connoinherit)is distinct from $expected$CHECK ((source_kind = ANY (ARRAY['raw_sms'::text, 'allocation'::text, 'payment'::text, 'receipt'::text, 'gateway'::text, 'receipt_event'::text, 'receipt_backlog'::text])))$expected$then raise exception 'receipt_telemetry_constraint_drift:exceptions_source_kind_check'using errcode='55000';end if;
 if(select pg_get_constraintdef(oid)from pg_constraint where conrelid='collect_ops.exceptions'::regclass and conname='exceptions_reason_code_check'and contype='c'and convalidated and not connoinherit)is distinct from $expected$CHECK ((reason_code = ANY (ARRAY['PARSING_FAILED'::text, 'ALLOCATION_REVIEW'::text, 'VERIFICATION_PENDING'::text, 'VERIFICATION_REJECTED'::text, 'VERIFICATION_CONFLICT'::text, 'CONTACT_MISSING'::text, 'SEND_UNCERTAIN'::text, 'SEND_FAILED_NO_SEND'::text, 'RECEIPT_SUPPRESSED'::text, 'GATEWAY_UNOBSERVED'::text, 'GATEWAY_STALE'::text, 'GATEWAY_SMS_PERMISSION'::text, 'GATEWAY_NETWORK'::text, 'GATEWAY_TELEPHONY'::text, 'GATEWAY_SIM'::text, 'RECEIPT_OPERATION_SOURCE_CHANGED'::text, 'RECEIPT_OPERATION_PAYMENT_NOT_POSTED'::text, 'RECEIPT_OPERATION_SNAPSHOT_MISSING'::text, 'RECEIPT_OPERATION_RECIPIENT_INELIGIBLE'::text, 'RECEIPT_OPERATION_POLICY_DISABLED'::text, 'RECEIPT_OPERATION_CONSENT_MISSING'::text, 'RECEIPT_OPERATION_CONTACT_MISSING'::text, 'RECEIPT_OPERATION_CONTACT_HISTORY_UNPROVEN'::text, 'RECEIPT_OPERATION_POLICY_HISTORY_UNPROVEN'::text, 'RECEIPT_OPERATION_CONSENT_HISTORY_UNPROVEN'::text, 'RECEIPT_OPERATION_CATCHUP_DISABLED'::text, 'RECEIPT_OPERATION_CATCHUP_WINDOW_EXCEEDED'::text, 'RECEIPT_OPERATION_CONTENT_REFUSED'::text, 'RECEIPT_OPERATION_LEGACY_CONTENT_REVIEW_REQUIRED'::text, 'RECEIPT_OPERATION_QUOTA_EXHAUSTED'::text, 'RECEIPT_OPERATION_SOURCE_BUSY'::text])))$expected$then raise exception 'receipt_telemetry_constraint_drift:exceptions_reason_code_check'using errcode='55000';end if;
end $guard$;
-- New private evidence, inactive at installation. No automatic send authority.
create schema collect_receipt_telemetry;
revoke all on schema collect_receipt_telemetry from public,anon,authenticated,service_role;
create table collect_receipt_telemetry.configuration(
 singleton boolean primary key check(singleton),revision bigint not null default 1 check(revision between 1 and 1000000000),
 enabled boolean not null default false,updated_at timestamptz not null default clock_timestamp(),updated_by uuid);
insert into collect_receipt_telemetry.configuration(singleton)values(true);
create table collect_receipt_telemetry.pending_events(
 event_id uuid primary key references collect_hybrid.receipt_business_events(id)on delete restrict,
 collection_id uuid references public.collections(id)on delete restrict,created_at timestamptz not null check(isfinite(created_at)));
create index receipt_telemetry_pending_scope_age on collect_receipt_telemetry.pending_events(collection_id,created_at,event_id);
create index receipt_telemetry_handled_window on collect_receipt_operations.handled_events(handled_at,event_id);
create index receipt_telemetry_arm_window on collect_gateway_dispatch.arms(armed_at,attempt_id);
create index receipt_telemetry_attempt_state on collect_gateway_dispatch.attempts(state,id)where state<>'granted';
create table collect_receipt_telemetry.open_armed_attempts(
 attempt_id uuid primary key references collect_gateway_dispatch.arms(attempt_id)on delete restrict,
 collection_id uuid not null references public.collections(id)on delete restrict,armed_at timestamptz not null);
create index receipt_telemetry_open_arm_scope on collect_receipt_telemetry.open_armed_attempts(collection_id,armed_at,attempt_id);
create table collect_receipt_telemetry.alert_heads(
 id uuid primary key default gen_random_uuid(),scope_sha256 text not null check(scope_sha256~'^[0-9a-f]{64}$'),
 policy_revision bigint not null,collection_ids uuid[] not null,rule_code text not null
 check(rule_code in('BACKLOG_AGED','HANDLING_LATENCY_HIGH','ACTION_BUDGET_EXHAUSTED','SMS_BUDGET_EXHAUSTED','DELIVERY_CALLBACK_GAP','SEND_OUTCOME_UNKNOWN')),
 status text not null check(status in('active','clear','superseded')),episode bigint not null check(episode between 1 and 1000000000),
 revision bigint not null check(revision between 1 and 1000000000),evidence_sha256 text not null check(evidence_sha256~'^[0-9a-f]{64}$'),
 source_kind text not null check(source_kind in('business_event','handled_event','policy','attempt')),source_id uuid,
 response_code text not null check(response_code in('investigate_backlog','investigate_handling','review_limits','investigate_attempt','reconcile_unknown')),
 exception_id uuid references collect_ops.exceptions(id)on delete restrict,observed_at timestamptz not null check(isfinite(observed_at)),
 check((source_kind='policy')or source_id is not null),unique(scope_sha256,rule_code));
create index receipt_telemetry_active_scope on collect_receipt_telemetry.alert_heads(scope_sha256,rule_code)where status<>'superseded';
create table collect_receipt_telemetry.alert_observations(
 alert_id uuid not null references collect_receipt_telemetry.alert_heads(id)on delete restrict,revision bigint not null,
 status text not null check(status in('active','clear','superseded')),episode bigint not null,measurement jsonb not null,
 source_kind text not null,source_id uuid,observed_at timestamptz not null,primary key(alert_id,revision));
create table collect_receipt_telemetry.requests(
 request_id uuid primary key,expires_at timestamptz not null check(isfinite(expires_at)),configuration_revision bigint not null,
 policy_revision bigint not null,result jsonb not null,recorded_at timestamptz not null check(isfinite(recorded_at)));
create table collect_receipt_telemetry.configuration_requests(
 request_id uuid primary key,actor_id uuid not null,session_id uuid not null,expected_revision bigint not null,
 enabled boolean not null,expires_at timestamptz not null,result jsonb not null,recorded_at timestamptz not null);
do $$declare t text;begin
 foreach t in array array['configuration','pending_events','open_armed_attempts','alert_heads','alert_observations','requests','configuration_requests']loop
  execute format('alter table collect_receipt_telemetry.%I enable row level security',t);
  execute format('revoke all on collect_receipt_telemetry.%I from public,anon,authenticated,service_role',t);
 end loop;
end$$;
create trigger receipt_telemetry_observations_immutable before update or delete on collect_receipt_telemetry.alert_observations
 for each row execute function collect_ops.immutable_evidence();
create trigger receipt_telemetry_requests_immutable before update or delete on collect_receipt_telemetry.requests
 for each row execute function collect_ops.immutable_evidence();
create trigger receipt_telemetry_configuration_requests_immutable before update or delete on collect_receipt_telemetry.configuration_requests
 for each row execute function collect_ops.immutable_evidence();
create function collect_receipt_telemetry.pending_event_projection()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if tg_table_name='receipt_business_events'then
  insert into collect_receipt_telemetry.pending_events(event_id,collection_id,created_at)
   values(new.id,new.collection_id,new.created_at);
 else delete from collect_receipt_telemetry.pending_events where event_id=new.event_id;
 end if;return new;
end$$;
-- Protect trigger publication and exact backfill against both concurrent
-- producers; later financial transactions lock only their own event identity.
lock table collect_hybrid.receipt_business_events,collect_receipt_operations.handled_events in share row exclusive mode;
create trigger receipt_telemetry_event_insert after insert on collect_hybrid.receipt_business_events
 for each row execute function collect_receipt_telemetry.pending_event_projection();
create trigger receipt_telemetry_event_handled after insert on collect_receipt_operations.handled_events
 for each row execute function collect_receipt_telemetry.pending_event_projection();
insert into collect_receipt_telemetry.pending_events(event_id,collection_id,created_at)
 select e.id,e.collection_id,e.created_at from collect_hybrid.receipt_business_events e
 where not exists(select 1 from collect_receipt_operations.handled_events h where h.event_id=e.id);

create function collect_receipt_telemetry.arm_is_open(p_attempt uuid)returns boolean
language sql stable security definer set search_path=''as $$
 with bindings as(select b.callback_kind,
  f.request_id is not null and(f.result_code,coalesce(f.tp_status,-1))=(l.result_code,coalesce(l.tp_status,-1))consistent
  from collect_gateway_dispatch.callback_bindings b
  left join lateral(select c.request_id,c.result_code,c.tp_status from collect_gateway_dispatch.callbacks c
   where c.attempt_id=b.attempt_id and c.callback_id=b.callback_id
   order by c.result_code,coalesce(c.tp_status,-1)limit 1)f on true
  left join lateral(select c.result_code,c.tp_status from collect_gateway_dispatch.callbacks c
   where c.attempt_id=b.attempt_id and c.callback_id=b.callback_id
   order by c.result_code desc,coalesce(c.tp_status,-1)desc limit 1)l on true
  where b.attempt_id=p_attempt)
 select a.state='uncertain'or
  (select count(*)filter(where consistent and callback_kind='sent')from bindings)<>a.segment_count or
  (select count(*)filter(where consistent and callback_kind='delivery')from bindings)<>a.segment_count
 from collect_gateway_dispatch.attempts a join collect_gateway_dispatch.arms r on r.attempt_id=a.id where a.id=p_attempt
$$;
create function collect_receipt_telemetry.open_arm_projection()returns trigger
language plpgsql volatile security definer set search_path=''as $$
declare attempt uuid;begin
 if tg_table_name='attempts'then attempt:=new.id;else attempt:=new.attempt_id;end if;
 -- Public authenticated callback/arm producers already own this attempt row.
 -- The same per-attempt fence also makes direct ordinary-owner synthetic
 -- concurrent inserts exact without introducing any global producer lock.
 perform 1 from collect_gateway_dispatch.attempts where id=attempt for update;
 if collect_receipt_telemetry.arm_is_open(attempt)is true then
  insert into collect_receipt_telemetry.open_armed_attempts(attempt_id,collection_id,armed_at)
   select a.id,o.collection_id,r.armed_at from collect_gateway_dispatch.attempts a
   join collect_gateway_dispatch.arms r on r.attempt_id=a.id join collect_hybrid.sms_notification_outbox o on o.id=a.outbox_id
   where a.id=attempt on conflict(attempt_id)do nothing;
 else delete from collect_receipt_telemetry.open_armed_attempts where attempt_id=attempt;end if;
 return new;
end$$;
lock table collect_gateway_dispatch.attempts,collect_gateway_dispatch.arms,collect_gateway_dispatch.callbacks in share row exclusive mode;
create trigger receipt_telemetry_arm_insert after insert on collect_gateway_dispatch.arms
 for each row execute function collect_receipt_telemetry.open_arm_projection();
create trigger receipt_telemetry_callback_insert after insert on collect_gateway_dispatch.callbacks
 for each row execute function collect_receipt_telemetry.open_arm_projection();
create trigger receipt_telemetry_attempt_state after update of state on collect_gateway_dispatch.attempts
 for each row execute function collect_receipt_telemetry.open_arm_projection();
insert into collect_receipt_telemetry.open_armed_attempts(attempt_id,collection_id,armed_at)
 select a.id,o.collection_id,r.armed_at from collect_gateway_dispatch.arms r join collect_gateway_dispatch.attempts a on a.id=r.attempt_id
 join collect_hybrid.sms_notification_outbox o on o.id=a.outbox_id where collect_receipt_telemetry.arm_is_open(a.id)is true;

create function collect_receipt_telemetry.scope_hash(p collect_receipt_operations.policy)returns text
language sql immutable security definer set search_path=''as $$
 select encode(extensions.digest(convert_to(jsonb_build_array(p.revision,
  (select coalesce(jsonb_agg(x order by x),'[]'::jsonb)from unnest(p.collection_ids)x))::text,'UTF8'),'sha256'),'hex')
$$;
create function collect_receipt_telemetry.alerts(p_scope text)returns jsonb
language sql stable security definer set search_path=''as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'rule_code',a.rule_code,'status',a.status,
  'episode',a.episode,'revision',a.revision,'source_kind',a.source_kind,'source_id',a.source_id,
  'exception_id',a.exception_id,'response_code',a.response_code,'observed_at',collect_ops.utc(a.observed_at))order by a.rule_code),'[]'::jsonb)
 from collect_receipt_telemetry.alert_heads a where a.scope_sha256=p_scope
$$;
create function collect_receipt_telemetry.unavailable(p collect_receipt_operations.policy,p_at timestamptz,p_limit text)returns jsonb
language sql stable security definer set search_path=''as $$
 select jsonb_build_object('contract_version',1,'scope','receipt_operations_configured_collections',
  'checked_at',collect_ops.utc(p_at),'sample_valid_until',collect_ops.utc(p_at+interval '60 seconds'),
  'window_start',collect_ops.utc(p_at-interval '24 hours'),'window_end',collect_ops.utc(p_at),'window_seconds',86400,
  'policy_revision',p.revision,'mode',p.mode,'emergency_stop',p.emergency_stop,'configured_collection_count',cardinality(p.collection_ids),
  'backlog',null,'handling',null,'budgets',null,'callbacks',null,'unknown',null,
  'alerts',collect_receipt_telemetry.alerts(collect_receipt_telemetry.scope_hash(p)),
  'evidence_limit_codes',jsonb_build_array('durable_handling_not_delivery','framework_callbacks_not_carrier_proof',
   'callback_coverage_not_delivery_success','budget_caps_not_measured_capacity','costs_unmeasured','configured_scope_only',p_limit),
  'financial_action',false,'send_action',false)
$$;
-- One statement snapshot. A time window bounds handled throughput; lifetime
-- pending work uses its exact transactional mirror. Callback consistency uses
-- indexed first/last variants, never raw-row counts or assumed success codes.
create function collect_receipt_telemetry.measure(p collect_receipt_operations.policy,p_at timestamptz)returns jsonb
language sql stable security definer set search_path=''as $$
 with pending as materialized(select e.* from collect_receipt_telemetry.pending_events e where e.collection_id=any(p.collection_ids)),
 recent_created as materialized(select e.id from collect_hybrid.receipt_business_events e
  where e.collection_id=any(p.collection_ids)and e.created_at>=p_at-interval '24 hours'and e.created_at<=p_at),
 recent_handled as materialized(select h.event_id,h.handled_at,e.created_at,
  floor(extract(epoch from(h.handled_at-e.created_at))*1000)::bigint latency
  from collect_receipt_operations.handled_events h join collect_hybrid.receipt_business_events e on e.id=h.event_id
  where h.handled_at>=p_at-interval '24 hours'and h.handled_at<=p_at and e.collection_id=any(p.collection_ids)),
 candidate_arms as materialized(select r.attempt_id from collect_gateway_dispatch.arms r
  where r.armed_at>=p_at-interval '24 hours'and r.armed_at<=p_at
  union select r.attempt_id from collect_receipt_telemetry.open_armed_attempts r where r.collection_id=any(p.collection_ids)and r.armed_at<=p_at),
 scoped_attempts as materialized(select a.id,a.state,a.segment_count,r.armed_at from candidate_arms candidate
  join collect_gateway_dispatch.attempts a on a.id=candidate.attempt_id
  join collect_hybrid.sms_notification_outbox o on o.id=a.outbox_id join collect_gateway_dispatch.arms r on r.attempt_id=a.id
  where o.collection_id=any(p.collection_ids)and r.armed_at<=p_at),
 bindings as materialized(select b.attempt_id,b.callback_kind,
  f.request_id is not null has_observation,
  f.request_id is not null and(f.result_code,coalesce(f.tp_status,-1))=(l.result_code,coalesce(l.tp_status,-1))consistent
  from scoped_attempts a join collect_gateway_dispatch.callback_bindings b on b.attempt_id=a.id
  left join lateral(select c.request_id,c.result_code,c.tp_status from collect_gateway_dispatch.callbacks c
   where c.attempt_id=b.attempt_id and c.callback_id=b.callback_id
   order by c.result_code,coalesce(c.tp_status,-1)limit 1)f on true
  left join lateral(select c.result_code,c.tp_status from collect_gateway_dispatch.callbacks c
   where c.attempt_id=b.attempt_id and c.callback_id=b.callback_id
   order by c.result_code desc,coalesce(c.tp_status,-1)desc limit 1)l on true),
 folded as materialized(select a.*,count(*)filter(where b.callback_kind='sent'and b.consistent)sent_covered,
  count(*)filter(where b.callback_kind='delivery'and b.consistent)delivery_covered,
  count(*)filter(where b.has_observation and not b.consistent)>0 conflict
  from scoped_attempts a left join bindings b on b.attempt_id=a.id group by a.id,a.state,a.segment_count,a.armed_at),
 recent_arms as materialized(select * from folded where armed_at>=p_at-interval '24 hours'),
 day_budget as materialized(select coalesce(sum(actions),0)actions,coalesce(sum(sms_segments),0)segments
  from collect_receipt_operations.reservations where recorded_at>=date_trunc('day',p_at at time zone 'UTC')at time zone 'UTC'and recorded_at<=p_at),
 metrics as materialized(select
  (select count(*)from pending)pending_count,
  (select case when min(created_at)is null then null else greatest(0,floor(extract(epoch from(p_at-min(created_at))))::bigint)end from pending)oldest,
  (select count(*)from pending e join collect_receipt_operations.event_deferrals d on d.event_id=e.event_id where d.next_check_at<=p_at)due,
  (select count(*)from pending e join collect_receipt_operations.event_deferrals d on d.event_id=e.event_id where d.code='SOURCE_BUSY')busy,
  (select count(*)from recent_created)created_count,(select count(*)from recent_handled)handled_count,
  (select percentile_disc(.5)within group(order by latency)from recent_handled)p50,
  (select percentile_disc(.95)within group(order by latency)from recent_handled)p95,(select max(latency)from recent_handled)max_latency,
  (select count(*)from recent_arms)arms_count,(select coalesce(sum(segment_count),0)from recent_arms)expected_segments,
  (select coalesce(sum(sent_covered),0)from recent_arms)sent_count,(select coalesce(sum(delivery_covered),0)from recent_arms)delivery_count,
  (select count(*)from recent_arms where delivery_covered=segment_count and not conflict)complete_delivery,
  (select count(*)from recent_arms where conflict)conflicting,
  (select count(*)from folded where state='uncertain')uncertain,
  (select count(*)from folded where state in('send_started','uncertain')and sent_covered<segment_count)missing_sent,
  (select count(*)from folded where state='observed_sent'and delivery_covered<segment_count)missing_delivery,
  (select count(*)from folded where conflict)all_conflicting,
  (select id from folded where armed_at<=p_at-interval '300 seconds'and delivery_covered<segment_count order by armed_at,id limit 1)gap_source,
  (select id from folded where state='uncertain'or conflict or(armed_at<=p_at-interval '120 seconds'and sent_covered<segment_count)order by armed_at,id limit 1)unknown_source,
  exists(select 1 from recent_handled where latency<0)or exists(select 1 from pending where created_at>p_at)invalid),
 dto as(select jsonb_build_object('contract_version',1,'scope','receipt_operations_configured_collections',
  'checked_at',collect_ops.utc(p_at),'sample_valid_until',collect_ops.utc(p_at+interval '60 seconds'),
  'window_start',collect_ops.utc(p_at-interval '24 hours'),'window_end',collect_ops.utc(p_at),'window_seconds',86400,
  'policy_revision',p.revision,'mode',p.mode,'emergency_stop',p.emergency_stop,'configured_collection_count',cardinality(p.collection_ids),
  'backlog',jsonb_build_object('unhandled_events',v.pending_count,'oldest_unhandled_age_seconds',v.oldest,'due_deferrals',v.due,'source_busy_deferrals',v.busy),
  'handling',jsonb_build_object('events_created_24h',v.created_count,'events_handled_24h',v.handled_count,'latency_p50_ms',v.p50,'latency_p95_ms',v.p95,'latency_max_ms',v.max_latency),
  'budgets',jsonb_build_object('scope','global_utc_day','utc_day_start',collect_ops.utc(date_trunc('day',p_at at time zone 'UTC')at time zone 'UTC'),
   'actions_reserved',d.actions,'actions_cap',(p.caps->>'global_actions')::bigint,'sms_segments_reserved',d.segments,'sms_segments_cap',(p.caps->>'global_sms_segments')::bigint),
  'callbacks',jsonb_build_object('armed_attempts_24h',v.arms_count,'expected_segments',v.expected_segments,'covered_sent_segments',v.sent_count,
   'covered_delivery_segments',v.delivery_count,'complete_delivery_callback_attempts',v.complete_delivery,'conflicting_attempts',v.conflicting),
  'unknown',jsonb_build_object('uncertain_attempts',v.uncertain,'started_without_all_sent_callbacks',v.missing_sent,
   'observed_sent_without_all_delivery_callbacks',v.missing_delivery,'callback_conflict_attempts',v.all_conflicting),
  'alerts',collect_receipt_telemetry.alerts(collect_receipt_telemetry.scope_hash(p)),
  'evidence_limit_codes',jsonb_build_array('durable_handling_not_delivery','framework_callbacks_not_carrier_proof',
   'callback_coverage_not_delivery_success','budget_caps_not_measured_capacity','costs_unmeasured','configured_scope_only'),
  'financial_action',false,'send_action',false)value,v.* from metrics v cross join day_budget d)
 select jsonb_build_object('dto',case when invalid or exists(select 1
  from unnest(array['backlog','handling','budgets','callbacks','unknown'])section
  cross join lateral jsonb_each(value->section)entry where jsonb_typeof(entry.value)='number'
   and(entry.value::text)::numeric not between 0 and 1000000000)
  then collect_receipt_telemetry.unavailable(p,p_at,'measurement_unavailable')else value end,
  'rules',jsonb_build_array(
   jsonb_build_object('rule','BACKLOG_AGED','active',pending_count>0 and oldest>=300,'value',jsonb_build_array(pending_count,oldest),
    'source_kind','business_event','source_id',(select event_id from pending order by created_at,event_id limit 1),'response','investigate_backlog'),
   jsonb_build_object('rule','HANDLING_LATENCY_HIGH','active',coalesce(p95>=120000,false),'value',jsonb_build_array(handled_count,p95),
    'source_kind','handled_event','source_id',(select event_id from recent_handled order by latency desc,event_id limit 1),'response','investigate_handling'),
   jsonb_build_object('rule','ACTION_BUDGET_EXHAUSTED','active',(value->'budgets'->>'actions_reserved')::bigint>=(p.caps->>'global_actions')::bigint,
    'value',jsonb_build_array(value->'budgets'->'actions_reserved',p.caps->'global_actions'),'source_kind','policy','source_id',null,'response','review_limits'),
   jsonb_build_object('rule','SMS_BUDGET_EXHAUSTED','active',(value->'budgets'->>'sms_segments_reserved')::bigint>=(p.caps->>'global_sms_segments')::bigint,
    'value',jsonb_build_array(value->'budgets'->'sms_segments_reserved',p.caps->'global_sms_segments'),'source_kind','policy','source_id',null,'response','review_limits'),
   jsonb_build_object('rule','DELIVERY_CALLBACK_GAP','active',gap_source is not null,'value',jsonb_build_array(missing_delivery,gap_source),
    'source_kind','attempt','source_id',gap_source,'response','investigate_attempt'),
   jsonb_build_object('rule','SEND_OUTCOME_UNKNOWN','active',unknown_source is not null,'value',jsonb_build_array(uncertain,missing_sent,all_conflicting,unknown_source),
    'source_kind','attempt','source_id',unknown_source,'response','reconcile_unknown')))
 from dto
$$;

create function public.admin_get_receipt_operational_telemetry_v1()returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare p collect_receipt_operations.policy;latest_revision bigint;at timestamptz;value jsonb;begin
 perform collect_ops.actor(false);select * into p from collect_receipt_operations.policy where singleton;at:=clock_timestamp();
 if cardinality(p.collection_ids)=0 then value:=collect_receipt_telemetry.unavailable(p,at,'no_configured_scope');
 else
  begin value:=collect_receipt_telemetry.measure(p,at)->'dto';
  exception when query_canceled then value:=collect_receipt_telemetry.unavailable(p,clock_timestamp(),'measurement_timeout');
  when numeric_value_out_of_range or data_exception or lock_not_available then value:=collect_receipt_telemetry.unavailable(p,clock_timestamp(),'measurement_unavailable');end;
 end if;
 perform collect_ops.actor(false);select revision into latest_revision from collect_receipt_operations.policy where singleton;
 if latest_revision is distinct from p.revision then value:=collect_receipt_telemetry.unavailable(p,clock_timestamp(),'policy_changed');end if;
 return value;
end$$;

create function collect_receipt_telemetry.publish(p collect_receipt_operations.policy,p_at timestamptz,p_measurement jsonb)returns void
language plpgsql volatile security definer set search_path=''as $$
declare scope_value text:=collect_receipt_telemetry.scope_hash(p);item collect_receipt_telemetry.alert_heads;
 rule jsonb;state text;digest text;source uuid;codes text[];observed collect_ops.exceptions;begin
 if p_measurement->'dto'->'backlog'='null'::jsonb then return;end if;
 -- Caller holds the separate sampler lock. Supersession is explicit evidence,
 -- never a predicate clear or operator resolution of the previous scope.
 for item in select * from collect_receipt_telemetry.alert_heads where scope_sha256<>scope_value and status<>'superseded'for update loop
  update collect_receipt_telemetry.alert_heads set status='superseded',revision=revision+1,observed_at=p_at where id=item.id returning * into item;
  insert into collect_receipt_telemetry.alert_observations values(item.id,item.revision,'superseded',item.episode,
   jsonb_build_object('superseded_by_scope',scope_value,'policy_revision',p.revision),item.source_kind,item.source_id,p_at);
  perform collect_ops.observe('receipt_telemetry',item.id,'{}',jsonb_build_object('episode',item.episode,'status','superseded'));
 end loop;
 for rule in select value from jsonb_array_elements(p_measurement->'rules')loop
  state:=case when(rule->>'active')::boolean then 'active'else 'clear'end;
  source:=nullif(rule->>'source_id','')::uuid;
  -- Empty clear cohorts have no individual source; policy is still real.
  if source is null then rule:=rule||jsonb_build_object('source_kind','policy');end if;
  digest:=encode(extensions.digest(convert_to(jsonb_build_array(state,rule->'value',rule->'source_kind',source)::text,'UTF8'),'sha256'),'hex');
  select * into item from collect_receipt_telemetry.alert_heads where scope_sha256=scope_value and rule_code=rule->>'rule'for update;
  if item.id is null then
   insert into collect_receipt_telemetry.alert_heads(scope_sha256,policy_revision,collection_ids,rule_code,status,episode,revision,
    evidence_sha256,source_kind,source_id,response_code,observed_at)
   values(scope_value,p.revision,p.collection_ids,rule->>'rule',state,1,1,digest,rule->>'source_kind',source,rule->>'response',p_at)returning * into item;
  elsif item.evidence_sha256 is distinct from digest then
   update collect_receipt_telemetry.alert_heads set status=state,episode=case when state='active'and status<>'active'then episode+1 else episode end,
    revision=revision+1,evidence_sha256=digest,source_kind=rule->>'source_kind',source_id=source,observed_at=p_at where id=item.id returning * into item;
  else continue;end if;
  insert into collect_receipt_telemetry.alert_observations values(item.id,item.revision,state,item.episode,rule->'value',item.source_kind,item.source_id,p_at);
  codes:=case when state='active'then array['TELEMETRY_'||item.rule_code]else '{}'::text[]end;
  -- Only episode/status changes the exception source revision. Numeric ageing
  -- and 24h rollover cannot create repeat deadline escalations while active.
  perform collect_ops.observe('receipt_telemetry',item.id,codes,jsonb_build_object('episode',item.episode,'status',state));
  select * into observed from collect_ops.exceptions where source_kind='receipt_telemetry'and source_id=item.id and reason_code='TELEMETRY_'||item.rule_code;
  update collect_receipt_telemetry.alert_heads set exception_id=observed.id where id=item.id;
 end loop;
end$$;

create function collect_receipt_telemetry.refresh(p_source uuid)returns void
language plpgsql volatile security definer set search_path=''as $$
declare h collect_receipt_telemetry.alert_heads;p collect_receipt_operations.policy;m jsonb;at timestamptz;begin
 -- Shared workflow lock is acquired by existing action/deadline callers before
 -- this helper. Use the same order in the sampler and never hold source locks
 -- before policy locks. Trigger producers do not enter these operational locks.
 perform pg_advisory_xact_lock(hashtext('collect-receipt-telemetry-sampler'));
 select * into h from collect_receipt_telemetry.alert_heads where id=p_source;
 if h.id is null then raise exception 'receipt_telemetry_source_unavailable'using errcode='22023';end if;
 if h.status='superseded'then return;end if;
 select * into p from collect_receipt_operations.policy where singleton for share nowait;
 if cardinality(p.collection_ids)=0 then raise exception 'receipt_telemetry_measurement_unavailable'using errcode='55000';end if;
 at:=clock_timestamp();m:=collect_receipt_telemetry.measure(p,at);
 if m->'dto'->'backlog'='null'::jsonb then raise exception 'receipt_telemetry_measurement_unavailable'using errcode='55000';end if;
 -- READ COMMITTED current policy row remains held through publication.
 if(select revision from collect_receipt_operations.policy where singleton)is distinct from p.revision then
  raise exception 'receipt_telemetry_policy_changed'using errcode='55000';end if;
 if auth.role()='authenticated'then perform collect_ops.actor(false);
 elsif auth.role()is distinct from 'service_role'then raise exception 'receipt_telemetry_source_authority_required'using errcode='42501';end if;
 perform collect_receipt_telemetry.publish(p,at,m);
end$$;
create function public.process_receipt_operational_telemetry_v1(p_request_id uuid,p_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare c collect_receipt_telemetry.configuration;p collect_receipt_operations.policy;prior collect_receipt_telemetry.requests;
 at timestamptz;m jsonb;value jsonb;result jsonb;begin
 if auth.role()is distinct from 'service_role'then raise exception 'receipt_telemetry_sampler_required'using errcode='42501';end if;
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'receipt_telemetry_snapshot_retry'using errcode='40001';end if;
 if p_request_id is null or p_expires_at is null or not isfinite(p_expires_at)then raise exception 'receipt_telemetry_input_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-telemetry-request:'||p_request_id::text,0));
 select * into prior from collect_receipt_telemetry.requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.expires_at is distinct from p_expires_at then raise exception 'receipt_telemetry_request_conflict'using errcode='22023';end if;return prior.result;end if;
 perform pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
 perform pg_advisory_xact_lock(hashtext('collect-receipt-telemetry-sampler'));
 select * into c from collect_receipt_telemetry.configuration where singleton for share nowait;
 select * into p from collect_receipt_operations.policy where singleton for share nowait;at:=clock_timestamp();
 if p_expires_at<=at or p_expires_at>at+interval '120 seconds'then raise exception 'receipt_telemetry_request_expired'using errcode='22023';end if;
 if not c.enabled then value:=collect_receipt_telemetry.unavailable(p,at,'measurement_unavailable');
 elsif cardinality(p.collection_ids)=0 then value:=collect_receipt_telemetry.unavailable(p,at,'no_configured_scope');
 else
  begin m:=collect_receipt_telemetry.measure(p,at);value:=m->'dto';
  exception when query_canceled then value:=collect_receipt_telemetry.unavailable(p,clock_timestamp(),'measurement_timeout');
  when numeric_value_out_of_range or data_exception or lock_not_available then value:=collect_receipt_telemetry.unavailable(p,clock_timestamp(),'measurement_unavailable');end;
 end if;
 -- Recheck final authority, revisions and wall-clock expiry after measurement.
 if auth.role()is distinct from 'service_role'then raise exception 'receipt_telemetry_sampler_required'using errcode='42501';end if;
 if clock_timestamp()>=p_expires_at then raise exception 'receipt_telemetry_request_expired'using errcode='22023';end if;
 if(select revision from collect_receipt_operations.policy where singleton)is distinct from p.revision
  or(select revision from collect_receipt_telemetry.configuration where singleton)is distinct from c.revision then
  value:=collect_receipt_telemetry.unavailable(p,clock_timestamp(),'policy_changed');
 end if;
 if value->'backlog'<>'null'::jsonb then
  perform collect_receipt_telemetry.publish(p,at,m);
  value:=value||jsonb_build_object('alerts',collect_receipt_telemetry.alerts(collect_receipt_telemetry.scope_hash(p)));
 end if;
 result:=jsonb_build_object('contract_version',1,'request_id',p_request_id,'status',case when value->'backlog'='null'::jsonb then 'unavailable'else 'recorded'end,
  'sample',value,'financial_action',false,'send_action',false);
 insert into collect_receipt_telemetry.requests values(p_request_id,p_expires_at,c.revision,p.revision,result,clock_timestamp());
 return result;
end$$;

create function public.admin_configure_receipt_telemetry_v1(p_request_id uuid,p_expected_revision bigint,p_enabled boolean,p_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare sid uuid;c collect_receipt_telemetry.configuration;prior collect_receipt_telemetry.configuration_requests;at timestamptz;result jsonb;begin
 sid:=collect_ops.actor(true);
 if p_request_id is null or p_expected_revision is null or p_expected_revision not between 1 and 999999999
  or p_enabled is null or p_expires_at is null or not isfinite(p_expires_at)then raise exception 'receipt_telemetry_configuration_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-telemetry-configuration:'||p_request_id::text,0));
 select * into prior from collect_receipt_telemetry.configuration_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.expected_revision<>p_expected_revision or prior.enabled<>p_enabled or prior.expires_at<>p_expires_at then
   raise exception 'receipt_telemetry_configuration_conflict'using errcode='22023';end if;return prior.result;end if;
 select * into c from collect_receipt_telemetry.configuration where singleton for update nowait;
 if c.revision<>p_expected_revision then raise exception 'receipt_telemetry_configuration_changed'using errcode='55000';end if;
 perform collect_ops.actor(true);at:=clock_timestamp();
 if p_expires_at<=at or p_expires_at>at+interval '120 seconds'then raise exception 'receipt_telemetry_request_expired'using errcode='22023';end if;
 update collect_receipt_telemetry.configuration set enabled=p_enabled,revision=revision+1,updated_at=at,updated_by=auth.uid()where singleton returning * into c;
 result:=jsonb_build_object('contract_version',1,'request_id',p_request_id,'revision',c.revision,'enabled',c.enabled,'recorded_at',collect_ops.utc(at),'financial_action',false,'send_action',false);
 insert into collect_receipt_telemetry.configuration_requests values(p_request_id,auth.uid(),sid,p_expected_revision,p_enabled,p_expires_at,result,at);
 perform public.create_audit_log('operations.receipt.telemetry.configure','receipt_telemetry_configuration',p_request_id,
  jsonb_build_object('request_id',p_request_id,'revision',c.revision,'enabled',c.enabled,'financial_action',false,'send_action',false),auth.uid());return result;
end$$;
-- Private sources stay API inaccessible. The sampler has a separate service
-- privilege; it neither accepts an unattended identity nor modifies any run.
revoke all on all functions in schema collect_receipt_telemetry from public,anon,authenticated,service_role;
revoke all on function public.admin_get_receipt_operational_telemetry_v1(),public.process_receipt_operational_telemetry_v1(uuid,timestamptz),
 public.admin_configure_receipt_telemetry_v1(uuid,bigint,boolean,timestamptz)from public,anon,authenticated,service_role;
grant execute on function public.admin_get_receipt_operational_telemetry_v1(),public.admin_configure_receipt_telemetry_v1(uuid,bigint,boolean,timestamptz)to authenticated;
grant execute on function public.process_receipt_operational_telemetry_v1(uuid,timestamptz)to service_role;

alter table collect_ops.exceptions drop constraint exceptions_source_kind_check;
alter table collect_ops.exceptions add constraint exceptions_source_kind_check check(source_kind in('raw_sms','allocation','payment','receipt','gateway','receipt_event','receipt_backlog','receipt_telemetry'));
alter table collect_ops.exceptions drop constraint exceptions_reason_code_check;
alter table collect_ops.exceptions add constraint exceptions_reason_code_check check(reason_code in('PARSING_FAILED','ALLOCATION_REVIEW','VERIFICATION_PENDING','VERIFICATION_REJECTED','VERIFICATION_CONFLICT','CONTACT_MISSING','SEND_UNCERTAIN','SEND_FAILED_NO_SEND','RECEIPT_SUPPRESSED','GATEWAY_UNOBSERVED','GATEWAY_STALE','GATEWAY_SMS_PERMISSION','GATEWAY_NETWORK','GATEWAY_TELEPHONY','GATEWAY_SIM','RECEIPT_OPERATION_SOURCE_CHANGED','RECEIPT_OPERATION_PAYMENT_NOT_POSTED','RECEIPT_OPERATION_SNAPSHOT_MISSING','RECEIPT_OPERATION_RECIPIENT_INELIGIBLE','RECEIPT_OPERATION_POLICY_DISABLED','RECEIPT_OPERATION_CONSENT_MISSING','RECEIPT_OPERATION_CONTACT_MISSING','RECEIPT_OPERATION_CONTACT_HISTORY_UNPROVEN','RECEIPT_OPERATION_POLICY_HISTORY_UNPROVEN','RECEIPT_OPERATION_CONSENT_HISTORY_UNPROVEN','RECEIPT_OPERATION_CATCHUP_DISABLED','RECEIPT_OPERATION_CATCHUP_WINDOW_EXCEEDED','RECEIPT_OPERATION_CONTENT_REFUSED','RECEIPT_OPERATION_LEGACY_CONTENT_REVIEW_REQUIRED','RECEIPT_OPERATION_QUOTA_EXHAUSTED','RECEIPT_OPERATION_SOURCE_BUSY','TELEMETRY_BACKLOG_AGED','TELEMETRY_HANDLING_LATENCY_HIGH','TELEMETRY_ACTION_BUDGET_EXHAUSTED','TELEMETRY_SMS_BUDGET_EXHAUSTED','TELEMETRY_DELIVERY_CALLBACK_GAP','TELEMETRY_SEND_OUTCOME_UNKNOWN'));
create or replace function collect_ops.observe(p_kind text,p_source uuid,p_codes text[],p_signature jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare code text;digest text;item collect_ops.exceptions;at timestamptz;
begin
 if p_kind is null or p_kind not in('raw_sms','allocation','payment','receipt','gateway','receipt_event','receipt_backlog','receipt_telemetry')
  or p_source is null or p_codes is null or array_position(p_codes,null) is not null
  or cardinality(p_codes)>15 or p_signature is null then
  raise exception 'operational_exception_source_invalid' using errcode='22023';end if;
 digest:=encode(extensions.digest(convert_to(p_signature::text,'UTF8'),'sha256'),'hex');
 -- Source-local lock, not a global commit-order watermark. Triggers never
 -- invoke an external service or depend on Codex availability.
 perform pg_advisory_xact_lock(hashtextextended('collect-ops-source:'||p_kind||':'||p_source::text,0));
 foreach code in array p_codes loop
  at:=clock_timestamp();
  insert into collect_ops.exceptions(source_kind,source_id,reason_code,active,source_sha256,revision,
   first_observed_at,last_changed_at) values(p_kind,p_source,code,true,digest,1,at,at)
  on conflict(source_kind,source_id,reason_code) do update
   set active=true,source_sha256=excluded.source_sha256,revision=exceptions.revision+1,
    last_changed_at=greatest(exceptions.last_changed_at,excluded.last_changed_at)
   where not exceptions.active or exceptions.source_sha256 is distinct from excluded.source_sha256
  returning * into item;
  if item.id is not null then
   insert into collect_ops.exception_observations(exception_id,revision,active,source_sha256,observed_at)
    values(item.id,item.revision,item.active,item.source_sha256,item.last_changed_at);
  end if;
 end loop;
 for item in update collect_ops.exceptions set active=false,source_sha256=digest,
  revision=revision+1,last_changed_at=greatest(last_changed_at,clock_timestamp())
  where source_kind=p_kind and source_id=p_source and active and not(reason_code=any(p_codes)) returning * loop
  insert into collect_ops.exception_observations(exception_id,revision,active,source_sha256,observed_at)
   values(item.id,item.revision,item.active,item.source_sha256,item.last_changed_at);
 end loop;
end$$;

create or replace function collect_ops.refresh_source(p_kind text,p_source uuid)returns void
language plpgsql security definer set search_path=''as $$declare current jsonb;codes text[];begin
 if p_kind='receipt_telemetry'then perform collect_receipt_telemetry.refresh(p_source);
 elsif p_kind in('receipt_event','receipt_backlog')then
  perform pg_advisory_xact_lock(hashtextextended('collect-ops-source:'||p_kind||':'||p_source::text,0));
  current:=collect_ops.receipt_exception_source(p_kind,p_source);
  codes:=case when current->>'disposition'='deferred'then array['RECEIPT_OPERATION_'||(current->>'current_code')]else '{}'::text[]end;
  perform collect_ops.observe(p_kind,p_source,codes,current->'signature');
 else perform collect_ops.receipt_exception_base_refresh_source(p_kind,p_source);end if;end$$;

create or replace function collect_ops.transaction_sms_id(p_kind text,p_source uuid)returns uuid
language sql stable security definer set search_path=''as $$
 select case when p_kind='receipt_telemetry'then null::uuid when p_kind in('receipt_event','receipt_backlog')then
  (select sms.id from public.parsed_payment_events parsed join public.raw_payment_sms sms on sms.id=parsed.raw_sms_id
   where parsed.id=case when p_kind='receipt_event'then
    (select coalesce(p.parsed_event_id,case when e.source_kind='allocation'then e.source_id end)
     from collect_hybrid.receipt_business_events e left join public.payments p on p.id=e.payment_id
     where e.id=p_source)
    else(select p.parsed_event_id from collect_hybrid.momo_balance_snapshots s join public.payments p on p.id=s.payment_id where s.id=p_source)end
   and collect_security.rwanda_sms_scope(sms.id))
 else collect_ops.receipt_exception_base_transaction_sms_id(p_kind,p_source)end
$$;

create or replace function public.admin_list_operational_exceptions_v2(p_active boolean default true,
 p_limit integer default 20,p_before_changed_at timestamptz default null,
 p_before_id uuid default null,p_source_kind text default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_ops.actor(false);
 if p_active is null or p_limit is null or p_limit not between 1 and 50
  or((p_before_changed_at is null)<>(p_before_id is null))
  or(p_before_changed_at is not null and not isfinite(p_before_changed_at))
  or(p_source_kind is not null and p_source_kind not in('raw_sms','allocation','payment','receipt','gateway','receipt_event','receipt_backlog','receipt_telemetry')) then
  raise exception 'operational_exception_query_invalid' using errcode='22023';end if;
 -- One committed statement supplies time, category, page and review flags.
 -- Read freshness is independent of the retained source observation's age.
 with sample as materialized(select clock_timestamp() at),
 candidates as materialized(select e.* from collect_ops.exceptions e
  where e.active=p_active and(p_source_kind is null or e.source_kind=p_source_kind)
   and(p_before_changed_at is null or(e.last_changed_at,e.id)<(p_before_changed_at,p_before_id))
  order by e.last_changed_at desc,e.id desc limit p_limit+1),
 page as materialized(select * from candidates order by last_changed_at desc,id desc limit p_limit),
 projected as(select e.last_changed_at,e.id,jsonb_build_object('id',e.id,
  'source_kind',e.source_kind,'source_id',e.source_id,'reason_code',e.reason_code,
  'active',e.active,'revision',e.revision,'source_sha256',e.source_sha256,
  'first_observed_at',collect_ops.utc(e.first_observed_at),
  'last_changed_at',collect_ops.utc(e.last_changed_at),
  'transaction_sms_id',collect_ops.transaction_sms_id(e.source_kind,e.source_id),
  'acknowledged',exists(select 1 from collect_ops.exception_actions a
   where a.exception_id=e.id and a.expected_revision=e.revision and a.action='acknowledge'),
  'escalation_requested',exists(select 1 from collect_ops.exception_actions a
   where a.exception_id=e.id and a.expected_revision=e.revision and a.action='escalate'))value from page e)
 select jsonb_build_object('contract_version',2,'scope','platform_global',
  'checked_at',collect_ops.utc(sample.at),'sample_valid_until',collect_ops.utc(sample.at+interval '60 seconds'),
  'active',p_active,'source_kind',p_source_kind,'limit',p_limit,
  'rows',coalesce((select jsonb_agg(value order by last_changed_at desc,id desc)from projected),'[]'::jsonb),
  'next_cursor',case when(select count(*)from candidates)>p_limit then
   (select jsonb_build_object('changed_at',collect_ops.utc(last_changed_at),'id',id)
    from page order by last_changed_at,id limit 1)else null end,
  'escalation_delivery_verified',false,'source_scan_complete',false)
 into result from sample;
 return result;
end$$;

create or replace function collect_ops.workflow_projection(p_exception uuid)returns jsonb
language sql stable security definer set search_path=''as $$
 select jsonb_build_object('contract_version',1,'exception_id',e.id,'source_revision',e.revision,
  'source_active',e.active,'workflow_revision',coalesce(w.revision,0),
  'assignee_id',w.assignee_id,'recipient_available',case when w.assignee_id is null then false
   else collect_ops.recipient_available(w.assignee_id)end,'due_at',collect_ops.utc(w.due_at),
  'overdue',coalesce(e.active and w.due_at<clock_timestamp(),false),
  'status',case when e.source_kind='receipt_telemetry'and exists(select 1 from collect_receipt_telemetry.alert_heads h where h.id=e.source_id and h.status='superseded')then 'superseded'
   when not e.active and w.resolved_source_revision=e.revision then 'resolved'
   when not e.active then 'source_cleared' when w.assignee_id is null then 'unassigned'else 'assigned'end,
  'escalations',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'source_revision',s.source_revision,
   'recipient_id',s.recipient_id,'state',s.state,'queued_at',collect_ops.utc(s.queued_at),
   'delivered_at',(select collect_ops.utc(d.delivered_at)from collect_ops.exception_inbox_deliveries d where d.escalation_id=s.id),
   'read_at',(select collect_ops.utc(d.read_at)from collect_ops.exception_inbox_reads d where d.escalation_id=s.id))order by s.queued_at desc,s.id desc)
   from(select * from collect_ops.exception_escalations where exception_id=e.id order by queued_at desc,id desc limit 10)s),'[]'::jsonb))
 from collect_ops.exceptions e left join collect_ops.exception_workflows w on w.exception_id=e.id where e.id=p_exception
$$;

create or replace function public.admin_act_exception_workflow_v1(p_request_id uuid,p_exception_id uuid,
 p_expected_source_revision bigint,p_expected_workflow_revision bigint,p_action text,
 p_assignee_id uuid,p_due_at timestamptz,p_reason_code text,p_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;item collect_ops.exceptions;w collect_ops.exception_workflows;
 prior collect_ops.exception_workflow_requests;at timestamptz;next_revision bigint;escalation uuid;result jsonb;begin
 sid:=collect_ops.actor(true);
 if p_request_id is null or p_exception_id is null or p_expected_source_revision is null
  or p_expected_source_revision not between 1 and 1000000000 or p_expected_workflow_revision is null
  or p_expected_workflow_revision not between 0 and 999999999 or p_action is null
  or p_action not in('assign','escalate','resolve')or p_reason_code is null
  or p_reason_code not in('review_started','owner_review_required','uncertain_send_review','contact_review','source_rechecked')
  or(p_action='assign'and(p_assignee_id is null or p_due_at is null or not isfinite(p_due_at)))
  or(p_action<>'assign'and(p_assignee_id is not null or p_due_at is not null))
  or(p_action='resolve'and p_reason_code<>'source_rechecked')or p_expires_at is null or not isfinite(p_expires_at)then
  raise exception 'exception_workflow_input_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-ops-workflow-request:'||p_request_id::text,0));
 select * into prior from collect_ops.exception_workflow_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.exception_id<>p_exception_id
   or prior.expected_source_revision<>p_expected_source_revision or prior.expected_workflow_revision<>p_expected_workflow_revision
   or prior.action<>p_action or prior.assignee_id is distinct from p_assignee_id
   or prior.due_at is distinct from p_due_at or prior.reason_code<>p_reason_code or prior.expires_at<>p_expires_at then
   raise exception 'exception_workflow_request_conflict'using errcode='22023';end if;
  return prior.result;
 end if;
 -- The pump and workflow use this lock before acquiring any source-local lock.
 perform pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
 select * into item from collect_ops.exceptions where id=p_exception_id;
 if item.id is null then raise exception 'exception_workflow_unavailable'using errcode='22023';end if;
 perform collect_ops.refresh_source(item.source_kind,item.source_id);
 select * into item from collect_ops.exceptions where id=p_exception_id for share;
 select * into w from collect_ops.exception_workflows where exception_id=item.id for update;
 if item.revision<>p_expected_source_revision or coalesce(w.revision,0)<>p_expected_workflow_revision then
  raise exception 'exception_workflow_source_changed'using errcode='55000';end if;
 if item.source_kind='receipt_telemetry'and exists(select 1 from collect_receipt_telemetry.alert_heads h where h.id=item.source_id and h.status='superseded')then
  raise exception 'exception_workflow_source_state_invalid'using errcode='55000';end if;
 if(p_action='resolve'and item.active)or(p_action<>'resolve'and not item.active)then
  raise exception 'exception_workflow_source_state_invalid'using errcode='55000';end if;
 at:=clock_timestamp();next_revision:=coalesce(w.revision,0)+1;
 if p_expires_at<=at or p_expires_at>at+interval '120 seconds'then
  raise exception 'exception_workflow_request_expired'using errcode='22023';end if;
 if p_action='assign'then
  if not collect_ops.recipient_available(p_assignee_id)then raise exception 'exception_workflow_recipient_unavailable'using errcode='42501';end if;
  if p_due_at<=at or p_due_at>at+interval '30 days'then raise exception 'exception_workflow_deadline_invalid'using errcode='22023';end if;
 else
  if p_action='escalate'and(w.exception_id is null or w.assignee_id is null)then
   raise exception 'exception_workflow_assignment_required'using errcode='55000';end if;
 end if;
 if p_action='escalate'then
  if not collect_ops.recipient_available(w.assignee_id)then raise exception 'exception_workflow_recipient_unavailable'using errcode='42501';end if;
  insert into collect_ops.exception_escalations(exception_id,source_revision,recipient_id,reason_code)
   values(item.id,item.revision,w.assignee_id,'operator_escalation')on conflict do nothing;
  select id into escalation from collect_ops.exception_escalations
   where exception_id=item.id and source_revision=item.revision and recipient_id=w.assignee_id;
 end if;
 insert into collect_ops.exception_workflows(exception_id,revision,source_revision,assignee_id,due_at,
  resolved_source_revision,last_request_id,updated_at)
 values(item.id,next_revision,item.revision,coalesce(p_assignee_id,w.assignee_id),coalesce(p_due_at,w.due_at),
  case when p_action='resolve'then item.revision else null end,p_request_id,at)
 on conflict(exception_id)do update set revision=excluded.revision,source_revision=excluded.source_revision,
  assignee_id=excluded.assignee_id,due_at=excluded.due_at,resolved_source_revision=excluded.resolved_source_revision,
  last_request_id=excluded.last_request_id,updated_at=greatest(exception_workflows.updated_at,excluded.updated_at);
 result:=jsonb_build_object('contract_version',1,'request_id',p_request_id,'exception_id',item.id,
  'source_revision',item.revision,'workflow_revision',next_revision,'action',p_action,'escalation_id',escalation,
  'source_resolved',p_action='resolve','financial_action',false,'send_action',false,'recorded_at',collect_ops.utc(at));
 insert into collect_ops.exception_workflow_requests values(p_request_id,item.id,auth.uid(),sid,item.revision,
  p_expected_workflow_revision,p_action,p_assignee_id,p_due_at,p_reason_code,p_expires_at,result,at);
 perform public.create_audit_log('operations.exception.workflow.'||p_action,'operational_exception',item.id,
  jsonb_build_object('request_id',p_request_id,'source_revision',item.revision,'workflow_revision',next_revision,
   'reason_code',p_reason_code,'escalation_id',escalation,'financial_action',false,'send_action',false),auth.uid());
 return result;
end$$;

create or replace function public.refresh_operational_exception_sources_v1(p_source_kind text,p_source_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare source uuid;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'operational_exception_service_required' using errcode='42501';end if;
 if current_setting('transaction_isolation')<>'read committed' then
  raise exception 'operational_exception_snapshot_retry' using errcode='40001';end if;
 if p_source_kind is null or p_source_kind not in('raw_sms','allocation','payment','receipt','gateway','receipt_telemetry')
  or p_source_ids is null or cardinality(p_source_ids) not between 1 and 25
  or array_position(p_source_ids,null) is not null
  or(select count(distinct id) from unnest(p_source_ids) id)<>cardinality(p_source_ids) then
  raise exception 'operational_exception_source_invalid' using errcode='22023';end if;
 for source in select ids.id from unnest(p_source_ids)as ids(id)order by ids.id loop
  perform collect_ops.refresh_source(p_source_kind,source);end loop;
 return jsonb_build_object('contract_version',1,'source_kind',p_source_kind,'checked',cardinality(p_source_ids),
  'financial_action',false,'send_action',false);
end$$;

create or replace function collect_operator_audit.exception_scope_v2(p_kind text,p_source uuid)returns boolean
language sql stable security definer set search_path=''as $$
 select case p_kind
 when 'receipt_telemetry'then exists(select 1 from collect_receipt_telemetry.alert_heads h where h.id=p_source
  and not exists(select 1 from unnest(h.collection_ids)scoped(collection_id)left join public.collections c on c.id=scoped.collection_id
   where c.id is null or c.currency<>'RWF'or c.diaspora_enabled))
 when 'gateway'then exists(select 1 from collect_gateway.devices where id=p_source)
 when 'raw_sms'then collect_ops.transaction_sms_id('raw_sms',p_source)is not null
 when 'allocation'then collect_ops.transaction_sms_id('allocation',p_source)is not null
 when 'payment'then collect_operator_audit.payment_scope(p_source)
 when 'receipt'then exists(select 1 from collect_hybrid.sms_notification_outbox j
  where j.id=p_source and collect_operator_audit.payment_scope(j.payment_id))
 when 'receipt_backlog'then exists(select 1 from collect_hybrid.momo_balance_snapshots s
  join public.payments p on p.id=s.payment_id where s.id=p_source and s.event_type='receipt'
   and s.collection_id=p.collection_id and s.member_record_id=p.member_record_id
   and collect_operator_audit.payment_scope(p.id))
 when 'receipt_event'then exists(select 1 from collect_hybrid.receipt_business_events e
  join public.collections c on c.id=e.collection_id
  where e.id=p_source and c.currency='RWF'and not c.diaspora_enabled and case
   when e.source_kind='payment'then e.source_id=e.payment_id and exists(select 1 from public.payments p
    where p.id=e.payment_id and p.collection_id=e.collection_id and collect_operator_audit.payment_scope(p.id))
   when e.source_kind='receipt'then exists(select 1 from collect_hybrid.sms_notification_outbox j
    join public.payments p on p.id=j.payment_id where j.id=e.source_id and j.payment_id=e.payment_id
     and j.collection_id=e.collection_id and p.collection_id=e.collection_id
     and collect_operator_audit.payment_scope(p.id))
   when e.source_kind='allocation'then exists(select 1 from public.parsed_payment_events x
    join public.raw_payment_sms sms on sms.id=x.raw_sms_id
    where x.id=e.source_id and x.collection_id=e.collection_id
     and x.is_mobile_money_payment and x.currency='RWF'and x.direction='incoming'
     and x.network in('mtn_momo','airtel_money')and x.receiver_user_id=sms.receiver_user_id
     and(x.receiver_phone_hash is null or x.receiver_phone_hash=sms.receiver_momo_number_hash)
     and collect_security.rwanda_sms_scope(x.raw_sms_id)
     and(e.payment_id is null or exists(select 1 from public.payments p where p.id=e.payment_id
      and p.parsed_event_id=x.id and p.collection_id=e.collection_id and collect_operator_audit.payment_scope(p.id))))
   else false end)
 else false end
$$;
notify pgrst,'reload schema';
commit;
