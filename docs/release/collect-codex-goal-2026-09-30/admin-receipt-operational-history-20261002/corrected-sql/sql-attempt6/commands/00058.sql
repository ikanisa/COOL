set search_path=public,extensions,auth;set timezone='UTC';
begin;
-- Read-only redacted operational evidence. No producer, policy, financial,
-- receipt, signing, dispatch or scanner function is replaced.
create schema collect_receipt_history;
revoke all on schema collect_receipt_history from public,anon,authenticated,service_role;
create function collect_receipt_history.run_scope(p_run uuid)returns boolean
language sql stable security definer set search_path=''as $$
 select exists(select 1 from collect_receipt_operations.runs r where r.id=p_run and cardinality(r.collection_ids)>0
  and not exists(select 1 from unnest(r.collection_ids) x(id)left join public.collections c on c.id=x.id
   where c.id is null or c.currency<>'RWF'or c.diaspora_enabled))
$$;
create function collect_receipt_history.input(p_limit integer,p_at timestamptz,p_id text,p_section text)returns void
language plpgsql immutable set search_path=''as $$begin
 if p_limit is null or p_limit not between 1 and 25
 or(p_at is null)is distinct from(p_id is null)
 or(p_at is not null and(not isfinite(p_at)or p_at<'0001-01-01T00:00:00Z'::timestamptz or p_at>='10000-01-01T00:00:00Z'::timestamptz))
 or(p_id is not null and case when p_section='budget_refusals'then p_id!~'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}:[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
 else p_id!~'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'end)then
 raise exception 'receipt_history_input_invalid'using errcode='22023';end if;end$$;
create index receipt_history_starts on collect_receipt_operations.requests(recorded_at desc,request_id desc)where action='begin_run';
create index receipt_history_run_assignments on collect_receipt_operations.run_batch_events(run_id,assigned_at desc,event_id desc);
create index receipt_history_run_outcomes on collect_receipt_operations.run_events(run_id,recorded_at desc,event_id desc);
create index receipt_history_backlog_outcomes on collect_receipt_operations.backlog_results(run_id,recorded_at desc,snapshot_id desc);
create index receipt_history_budget_refusals on collect_ops.receipt_backlog_budget_deferrals(run_id,recorded_at desc,((request_id::text||':'||snapshot_id::text)collate "C")desc);
create index receipt_history_run_reservations on collect_receipt_operations.reservations(run_id,recorded_at desc,id desc);
create index receipt_history_configurations on collect_receipt_operations.owner_requests(((result->>'revision')::bigint))where action='configure';

create function public.admin_list_receipt_operation_starts_v1(p_limit integer default 20,
 p_before_at timestamptz default null,p_before_request_id uuid default null)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare at timestamptz;result jsonb;begin
 perform collect_ops.actor(false);perform collect_receipt_history.input(p_limit,p_before_at,p_before_request_id::text,'starts');at:=clock_timestamp();
 with page as materialized(select q.* from collect_receipt_operations.requests q
  where q.action='begin_run'and q.recorded_at<=at 
   and(p_before_at is null or(q.recorded_at,q.request_id)<(p_before_at,p_before_request_id))
  order by q.recorded_at desc,q.request_id desc limit p_limit+1),
 shown as materialized(select *from page order by recorded_at desc,request_id desc limit p_limit)
 select jsonb_build_object('contract_version',1,'scope','rw_receipt_operational_history','section','starts',
  'checked_at',collect_ops.utc(at),'sample_valid_until',collect_ops.utc(at+interval '60 seconds'),'limit',p_limit,
  'history_complete',false,'financial_action',false,'send_action',false,
  'rows',coalesce((select jsonb_agg(jsonb_build_object('request_id',q.request_id,'principal_id',q.principal_id,
   'recorded_at',collect_ops.utc(q.recorded_at),'code',q.result->>'code','mode',q.result->>'mode',
   'run_id',case when collect_receipt_history.run_scope(r.id)then r.id end,
   'run_state',case when r.id is null then 'no_run'when not collect_receipt_history.run_scope(r.id)then 'unavailable'
    when r.completed_at is not null then 'closed'when r.expires_at<=at then 'expired'else 'leased'end)
   order by q.recorded_at desc,q.request_id desc)from shown q left join collect_receipt_operations.runs r
    on r.request_id=q.request_id and r.principal_id=q.principal_id and r.id=collect_operator_audit.safe_uuid(q.result->>'run_id')),'[]'::jsonb),
  'next_cursor',case when(select count(*)from page)>p_limit then(select jsonb_build_object('recorded_at',collect_ops.utc(recorded_at),'evidence_id',request_id::text)
   from shown order by recorded_at,request_id limit 1)end)into result;
 perform collect_ops.actor(false);return result;
 exception when lock_not_available then raise exception 'receipt_history_authority_busy'using errcode='55P03';end$$;

create function public.admin_get_receipt_operation_run_v1(p_run_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare at timestamptz;r collect_receipt_operations.runs;config collect_receipt_operations.owner_requests;completion collect_receipt_operations.requests;
 result jsonb;caps jsonb;summary jsonb;day_start timestamptz;window_end timestamptz;n integer;begin
 perform collect_ops.actor(false);if p_run_id is null then raise exception 'receipt_history_input_invalid'using errcode='22023';end if;at:=clock_timestamp();
 select *into r from collect_receipt_operations.runs where id=p_run_id and collect_receipt_history.run_scope(id);
 if r.id is not null then
  -- Historical budgets belong only to the exact immutable configure revision.
  select count(*)into n from(select 1 from collect_receipt_operations.owner_requests q where q.action='configure'and(q.result->>'revision')::bigint=r.policy_revision
   and q.recorded_at<=r.started_at and jsonb_typeof(q.input)='array'and collect_receipt_operations.caps_valid(q.input->6)limit 2)matching_config;
  if n=1 then select *into config from collect_receipt_operations.owner_requests q where q.action='configure'
   and(q.result->>'revision')::bigint=r.policy_revision and q.recorded_at<=r.started_at and jsonb_typeof(q.input)='array'and collect_receipt_operations.caps_valid(q.input->6)limit 1;caps:=config.input->6;end if;
  -- Exact original complete_run evidence, never a latest request/configuration.
  select count(*)into n from(select 1 from collect_receipt_operations.requests q where q.action='complete_run'and q.principal_id=r.principal_id
   and collect_operator_audit.safe_uuid(q.input->>'run_id')=r.id
   and q.input->>'run_id'=r.id::text and q.input->>'fence_version'=r.fence_version::text
   and q.result->>'run_id'=r.id::text and q.result->>'fence_version'=r.fence_version::text
   and q.result->>'status'='completed'and r.completed_at is not null and q.recorded_at>=r.completed_at and q.recorded_at<=at limit 2)matching_completion;
  if n=1 then select *into completion from collect_receipt_operations.requests q where q.action='complete_run'and q.principal_id=r.principal_id
   and collect_operator_audit.safe_uuid(q.input->>'run_id')=r.id
   and q.input->>'run_id'=r.id::text and q.input->>'fence_version'=r.fence_version::text
   and q.result->>'run_id'=r.id::text and q.result->>'fence_version'=r.fence_version::text
   and q.result->>'status'='completed'and r.completed_at is not null and q.recorded_at>=r.completed_at and q.recorded_at<=at limit 1;
   summary:=jsonb_build_object('request_id',completion.request_id,'recorded_at',collect_ops.utc(completion.recorded_at),
    'handled_count',(completion.result->>'handled_count')::bigint,'deferred_count',(completion.result->>'deferred_count')::bigint,
    'action_count',(completion.result->>'action_count')::bigint,'sms_segments',(completion.result->>'sms_segments')::bigint,
    'business_handled',(completion.result->>'business_handled')::boolean);end if;
  day_start:=date_trunc('day',r.started_at at time zone 'UTC')at time zone 'UTC';window_end:=least(r.expires_at,at);
 end if;
 result:=jsonb_build_object('contract_version',1,'scope','rw_receipt_operational_history','run_id',p_run_id,
  'status',case when r.id is null then 'unavailable'else 'partial'end,'checked_at',collect_ops.utc(at),
  'sample_valid_until',collect_ops.utc(at+interval '60 seconds'),'history_complete',false,'financial_action',false,'send_action',false,
  'run',case when r.id is not null then jsonb_build_object('request_id',r.request_id,'principal_id',r.principal_id,
   'fence_version',r.fence_version,'policy_revision',r.policy_revision,'mode',r.mode,'collection_ids',r.collection_ids,'device_id',r.device_id,
   'started_at',collect_ops.utc(r.started_at),'expires_at',collect_ops.utc(r.expires_at),'completed_at',case when r.completed_at is not null then collect_ops.utc(r.completed_at)end,
   'scan_performed',r.scan_performed,'state',case when r.completed_at is not null then 'closed'when r.expires_at<=at then 'expired'else 'leased'end)end,
  'historical_config',case when caps is not null then jsonb_build_object('request_id',config.request_id,'revision',r.policy_revision,
   'recorded_at',collect_ops.utc(config.recorded_at),'caps',caps)end,'completion',summary,
  'quota_usage',case when r.id is not null then jsonb_build_object('window_start',collect_ops.utc(day_start),'window_end',collect_ops.utc(window_end),
   'scope','immutable_reservations_through_lease_window','run_actions',(select coalesce(sum(actions),0)from collect_receipt_operations.reservations where run_id=r.id and recorded_at<=at),
   'run_sms_segments',(select coalesce(sum(sms_segments),0)from collect_receipt_operations.reservations where run_id=r.id and recorded_at<=at),
   'global_actions',(select coalesce(sum(actions),0)from collect_receipt_operations.reservations where recorded_at>=day_start and recorded_at<=window_end),
   'global_sms_segments',(select coalesce(sum(sms_segments),0)from collect_receipt_operations.reservations where recorded_at>=day_start and recorded_at<=window_end),
   'device_actions',case when r.device_id is not null then(select coalesce(sum(actions),0)from collect_receipt_operations.reservations where device_id=r.device_id and recorded_at>=day_start and recorded_at<=window_end)end,
   'device_sms_segments',case when r.device_id is not null then(select coalesce(sum(sms_segments),0)from collect_receipt_operations.reservations where device_id=r.device_id and recorded_at>=day_start and recorded_at<=window_end)end,
   'groups',(select coalesce(jsonb_agg(jsonb_build_object('collection_id',x.id,'actions',x.actions,'sms_segments',x.segments)order by x.id),'[]'::jsonb)
    from(select g.id,coalesce(sum(q.actions),0)actions,coalesce(sum(q.sms_segments),0)segments from unnest(r.collection_ids)g(id)
     left join collect_receipt_operations.reservations q on q.collection_id=g.id and q.recorded_at>=day_start and q.recorded_at<=window_end group by g.id)x))end);
 perform collect_ops.actor(false);return result;
 exception when lock_not_available then raise exception 'receipt_history_authority_busy'using errcode='55P03';end$$;

create function public.admin_list_receipt_operation_evidence_v1(p_run_id uuid,p_section text,p_limit integer default 20,
 p_before_at timestamptz default null,p_before_id text default null)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare at timestamptz;result jsonb;available boolean;rows jsonb;cursor jsonb;begin
 perform collect_ops.actor(false);
 if p_run_id is null or p_section is null or p_section not in('events','backlog_results','budget_refusals','reservations')then raise exception 'receipt_history_input_invalid'using errcode='22023';end if;
 perform collect_receipt_history.input(p_limit,p_before_at,p_before_id,p_section);at:=clock_timestamp();available:=collect_receipt_history.run_scope(p_run_id);
 if p_section='events'then
  -- Bound both indexed assignment/outcome branches before deduplication/joins.
  with candidates as materialized(
   (select b.event_id,b.assigned_at recorded_at from collect_receipt_operations.run_batch_events b
    where available and b.run_id=p_run_id and b.assigned_at<=at
     and(p_before_at is null or(b.assigned_at,b.event_id)<(p_before_at,p_before_id::uuid))
    order by b.assigned_at desc,b.event_id desc limit p_limit+1)
   union all
   (select o.event_id,o.recorded_at from collect_receipt_operations.run_events o where available and o.run_id=p_run_id and o.recorded_at<=at
    and not exists(select 1 from collect_receipt_operations.run_batch_events b where b.run_id=o.run_id and b.event_id=o.event_id)
    and(p_before_at is null or(o.recorded_at,o.event_id)<(p_before_at,p_before_id::uuid))order by o.recorded_at desc,o.event_id desc limit p_limit+1)),
  page as materialized(select distinct event_id,recorded_at from candidates order by recorded_at desc,event_id desc limit p_limit+1),
  shown as materialized(select *from page order by recorded_at desc,event_id desc limit p_limit)
  select coalesce((select jsonb_agg(jsonb_build_object('evidence_id',s.event_id::text,'recorded_at',collect_ops.utc(s.recorded_at),
   'event_id',s.event_id,'source_status',case when collect_operator_audit.exception_scope_v2('receipt_event',s.event_id)then 'available'else 'unavailable'end,
   'payment_id',case when collect_operator_audit.exception_scope_v2('receipt_event',s.event_id)then e.payment_id end,
   'transaction_sms_id',case when collect_operator_audit.exception_scope_v2('receipt_event',s.event_id)then collect_ops.transaction_sms_id(e.source_kind,e.source_id)end,
   'receipt_id',case when collect_operator_audit.exception_scope_v2('receipt_event',s.event_id)and exists(select 1 from collect_hybrid.sms_notification_outbox j where j.id=coalesce(o.receipt_id,e.outbox_id)and collect_operator_audit.payment_scope(j.payment_id))then coalesce(o.receipt_id,e.outbox_id)end,
   'exception_ids',case when collect_operator_audit.exception_scope_v2('receipt_event',s.event_id)then(select coalesce(jsonb_agg(x.id order by x.id),'[]'::jsonb)from collect_ops.exceptions x where x.source_kind='receipt_event'and x.source_id=s.event_id)else '[]'::jsonb end,
   'assigned_at',case when b.event_id is not null then collect_ops.utc(b.assigned_at)end,
   'outcome',case when o.event_id is not null then jsonb_build_object('source_version',o.source_version,'code',o.code,'business_handled',o.business_handled,'recorded_at',collect_ops.utc(o.recorded_at))end,
   'first_handled',case when h.event_id is not null and h.handled_at<=at then jsonb_build_object('run_id',h.run_id,'source_version',h.source_version,'code',h.code,
    'receipt_id',case when exists(select 1 from collect_hybrid.sms_notification_outbox j where j.id=h.receipt_id and collect_operator_audit.payment_scope(j.payment_id))then h.receipt_id end,'handled_at',collect_ops.utc(h.handled_at))end,
   'current_deferral',case when d.event_id is not null then jsonb_build_object('code',d.code,'next_check_at',collect_ops.utc(d.next_check_at))end)
   order by s.recorded_at desc,s.event_id desc)from shown s join collect_hybrid.receipt_business_events e on e.id=s.event_id
   left join collect_receipt_operations.run_batch_events b on b.run_id=p_run_id and b.event_id=s.event_id
   left join collect_receipt_operations.run_events o on o.run_id=p_run_id and o.event_id=s.event_id
   left join collect_receipt_operations.handled_events h on h.event_id=s.event_id left join collect_receipt_operations.event_deferrals d on d.event_id=s.event_id),'[]'::jsonb),
  case when(select count(*)from page)>p_limit then(select jsonb_build_object('recorded_at',collect_ops.utc(recorded_at),'evidence_id',event_id::text)from shown order by recorded_at,event_id limit 1)end into rows,cursor;
 elsif p_section in('backlog_results','budget_refusals')then
  with candidates as materialized(
   (select b.snapshot_id,b.snapshot_id::text collate "C" evidence_id,b.recorded_at,null::uuid request_id,b.code,b.business_handled,b.receipt_id
    from collect_receipt_operations.backlog_results b where available and p_section='backlog_results'and b.run_id=p_run_id and b.recorded_at<=at
    and(p_before_at is null or(b.recorded_at,b.snapshot_id::text collate "C")<(p_before_at,p_before_id collate "C"))order by b.recorded_at desc,b.snapshot_id::text collate "C" desc limit p_limit+1)
   union all
   (select b.snapshot_id,(b.request_id::text||':'||b.snapshot_id::text)collate "C",b.recorded_at,b.request_id,'QUOTA_EXHAUSTED',false,null::uuid
    from collect_ops.receipt_backlog_budget_deferrals b where available and p_section='budget_refusals'and b.run_id=p_run_id and b.recorded_at<=at
    and(p_before_at is null or(b.recorded_at,(b.request_id::text||':'||b.snapshot_id::text)collate "C")<(p_before_at,p_before_id collate "C"))
    order by b.recorded_at desc,(b.request_id::text||':'||b.snapshot_id::text)collate "C" desc limit p_limit+1)),
  page as materialized(select *from candidates order by recorded_at desc,evidence_id collate "C"desc limit p_limit+1),
  shown as materialized(select *from page order by recorded_at desc,evidence_id collate "C"desc limit p_limit)
  select coalesce((select jsonb_agg(jsonb_build_object('evidence_id',b.evidence_id,'recorded_at',collect_ops.utc(b.recorded_at),
   'snapshot_id',b.snapshot_id,'request_id',b.request_id,'code',b.code,'business_handled',b.business_handled,
   'source_status',case when collect_operator_audit.exception_scope_v2('receipt_backlog',b.snapshot_id)then 'available'else 'unavailable'end,
   'payment_id',case when collect_operator_audit.exception_scope_v2('receipt_backlog',b.snapshot_id)then s.payment_id end,
   'transaction_sms_id',case when collect_operator_audit.exception_scope_v2('receipt_backlog',b.snapshot_id)then collect_ops.transaction_sms_id('payment',s.payment_id)end,
   'receipt_id',case when collect_operator_audit.exception_scope_v2('receipt_backlog',b.snapshot_id)and exists(select 1 from collect_hybrid.sms_notification_outbox j where j.id=b.receipt_id and collect_operator_audit.payment_scope(j.payment_id))then b.receipt_id end,
   'exception_ids',case when collect_operator_audit.exception_scope_v2('receipt_backlog',b.snapshot_id)then(select coalesce(jsonb_agg(x.id order by x.id),'[]'::jsonb)from collect_ops.exceptions x where x.source_kind='receipt_backlog'and x.source_id=b.snapshot_id)else '[]'::jsonb end)
   order by b.recorded_at desc,b.evidence_id collate "C"desc)from shown b join collect_hybrid.momo_balance_snapshots s on s.id=b.snapshot_id),'[]'::jsonb),
   case when(select count(*)from page)>p_limit then(select jsonb_build_object('recorded_at',collect_ops.utc(recorded_at),'evidence_id',evidence_id)from shown order by recorded_at,evidence_id collate "C"limit 1)end into rows,cursor;
 else
  with page as materialized(select q.* from collect_receipt_operations.reservations q where available and q.run_id=p_run_id and q.recorded_at<=at
   and(p_before_at is null or(q.recorded_at,q.id)<(p_before_at,p_before_id::uuid))order by q.recorded_at desc,q.id desc limit p_limit+1),
  shown as materialized(select *from page order by recorded_at desc,id desc limit p_limit)
  select coalesce((select jsonb_agg(jsonb_build_object('evidence_id',id::text,'recorded_at',collect_ops.utc(recorded_at),'collection_id',collection_id,
   'device_id',device_id,'fence_version',fence_version,'actions',actions,'sms_segments',sms_segments,
   'snapshot_id',case when exists(select 1 from collect_hybrid.momo_balance_snapshots s where s.id=shown.id and collect_operator_audit.exception_scope_v2('receipt_backlog',s.id))then shown.id end)order by recorded_at desc,id desc)from shown),'[]'::jsonb),
  case when(select count(*)from page)>p_limit then(select jsonb_build_object('recorded_at',collect_ops.utc(recorded_at),'evidence_id',id::text)from shown order by recorded_at,id limit 1)end into rows,cursor;
 end if;
 result:=jsonb_build_object('contract_version',1,'scope','rw_receipt_operational_history','run_id',p_run_id,'section',p_section,
  'status',case when available then 'partial'else 'unavailable'end,'checked_at',collect_ops.utc(at),'sample_valid_until',collect_ops.utc(at+interval '60 seconds'),
  'limit',p_limit,'history_complete',false,'financial_action',false,'send_action',false,'rows',rows,'next_cursor',cursor);
 perform collect_ops.actor(false);return result;
 exception when lock_not_available then raise exception 'receipt_history_authority_busy'using errcode='55P03';end$$;

create function collect_operator_audit.operational_event_id(p_source text,p_request uuid)returns uuid
language sql immutable set search_path=''as $$select md5(p_source||':'||p_request::text)::uuid$$;
create index receipt_history_operations_audit_order on collect_receipt_operations.owner_requests(recorded_at desc,
 (collect_operator_audit.operational_event_id('receipt_operations_owner_request',request_id))desc)where action in('configure','stop');
create index receipt_history_workflow_audit_order on collect_receipt_operations.enrollment_workflow_requests
 (collect_operator_audit.safe_uuid(result->>'principal_id'),recorded_at desc,(collect_operator_audit.operational_event_id('receipt_operations_enrollment_workflow',request_id))desc);
create index receipt_history_completions on collect_receipt_operations.requests
 (collect_operator_audit.safe_uuid(input->>'run_id'),principal_id,recorded_at desc,
 (collect_operator_audit.operational_event_id('receipt_operations_service_request',request_id))desc)where action='complete_run';
create index receipt_history_service_run_audit on collect_receipt_operations.requests
 (collect_operator_audit.safe_uuid(input->>'run_id'),principal_id,action,recorded_at desc,
 (collect_operator_audit.operational_event_id('receipt_operations_service_request',request_id))desc)
 where action in('list_events','ensure_receipt','reconcile_backlog','complete_run');
create index receipt_history_owner_identity_audit on collect_receipt_operations.owner_requests
 (collect_operator_audit.safe_uuid(result->>'principal_id'),recorded_at desc,
 (collect_operator_audit.operational_event_id('receipt_operations_owner_request',request_id))desc);
create index receipt_history_workflow_identity_audit on collect_receipt_operations.enrollment_workflow_requests
 (collect_operator_audit.safe_uuid(result->>'principal_id'),recorded_at desc,request_id desc);
create or replace function public.admin_get_operator_entity_audit_v1(p_entity_kind text,p_entity_id uuid,
 p_limit integer default 20,p_before_at timestamptz default null,p_before_event_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare available boolean;result jsonb;sample timestamptz;begin
 perform collect_operator_audit.actor(p_entity_kind);
 if p_entity_kind in('receipt_operation_run','receipt_operations_policy')then perform collect_ops.actor(false);end if;
 if p_entity_kind is null or p_entity_kind not in('shadow_run','gateway_device','exception','supervisor_identity','receipt','receipt_operations_policy','receipt_operation_run')
  or p_entity_id is null or p_limit is null or p_limit not between 1 and 50
  or(p_before_at is null)is distinct from(p_before_event_id is null)
  or(p_before_at is not null and not isfinite(p_before_at))then
  raise exception 'operator_audit_input_invalid'using errcode='22023';end if;
 available:=case p_entity_kind
  when 'shadow_run'then exists(select 1 from collect_security.shadow_supervisor_runs where id=p_entity_id)
  when 'gateway_device'then exists(select 1 from collect_gateway.devices where id=p_entity_id)
  when 'receipt_operation_run'then collect_receipt_history.run_scope(p_entity_id)
  when 'receipt_operations_policy'then p_entity_id='00000000-0000-4000-8000-000000000001'::uuid and exists(select 1 from collect_receipt_operations.policy where singleton)
  when 'supervisor_identity'then exists(select 1 from collect_supervisor.identities where id=p_entity_id)
  when 'receipt'then exists(select 1 from collect_hybrid.sms_notification_outbox j
   where j.id=p_entity_id and collect_operator_audit.payment_scope(j.payment_id))
  when 'exception'then exists(select 1 from collect_ops.exceptions e where e.id=p_entity_id and
   case e.source_kind
    when 'gateway'then exists(select 1 from collect_gateway.devices d where d.id=e.source_id)
    when 'receipt'then exists(select 1 from collect_hybrid.sms_notification_outbox j
     where j.id=e.source_id and collect_operator_audit.payment_scope(j.payment_id))
    when 'payment'then collect_operator_audit.payment_scope(e.source_id)
    when 'raw_sms'then collect_ops.transaction_sms_id('raw_sms',e.source_id) is not null
    when 'allocation'then collect_ops.transaction_sms_id('allocation',e.source_id) is not null
    else false end)
  else false end;
 sample:=clock_timestamp();
 -- Permit cursor predicates to reach the entity/order indexes rather than
 -- materializing an entity's entire retained history before selecting a page.
 with events as not materialized(
  (select *from(
  select e.event_id,'shadow_audit_event'::text source,e.action,e.recorded_at,e.actor_id,e.request_id,
   null::bigint revision,e.fence_version,null::text reason_code
   from collect_operator_audit.shadow_events e where p_entity_kind='shadow_run'and e.run_id=p_entity_id
  )branch(event_id,source,action,recorded_at,actor_id,request_id,revision,fence_version,reason_code) where isfinite(recorded_at)and recorded_at<=sample
   and(p_before_at is null or(recorded_at,event_id)<(p_before_at,p_before_event_id))
   order by recorded_at desc,event_id desc limit p_limit+1)
  union all
  (select *from(  select e.request_id,'gateway_admin_request','gateway.'||e.action,e.recorded_at,e.actor_id,e.request_id,
   null::bigint,null::bigint,null::text from collect_gateway.admin_requests e
   where p_entity_kind='gateway_device'and collect_operator_audit.safe_uuid(e.result->>'device_id')=p_entity_id
  )branch(event_id,source,action,recorded_at,actor_id,request_id,revision,fence_version,reason_code) where isfinite(recorded_at)and recorded_at<=sample
   and(p_before_at is null or(recorded_at,event_id)<(p_before_at,p_before_event_id))
   order by recorded_at desc,event_id desc limit p_limit+1)
  union all
  (select *from(  select e.request_id,'supervisor_owner_request','supervisor.'||e.action,e.recorded_at,e.actor_id,e.request_id,
   null::bigint,null::bigint,null::text from collect_supervisor.owner_requests e
   where p_entity_kind='supervisor_identity'and collect_operator_audit.safe_uuid(e.result->>'principal_id')=p_entity_id
  )branch(event_id,source,action,recorded_at,actor_id,request_id,revision,fence_version,reason_code) where isfinite(recorded_at)and recorded_at<=sample
   and(p_before_at is null or(recorded_at,event_id)<(p_before_at,p_before_event_id))
   order by recorded_at desc,event_id desc limit p_limit+1)
  union all
  (select *from(  select collect_operator_audit.operational_event_id('receipt_operations_owner_request',e.request_id),'receipt_operations_owner_request',
   'supervisor.operations.'||e.action,e.recorded_at,e.actor_id,e.request_id,
   case when p_entity_kind='receipt_operations_policy'then(e.result->>'revision')::bigint end,null::bigint,null::text
   from collect_receipt_operations.owner_requests e where p_entity_kind='supervisor_identity'and e.action in('enroll','activate','revoke')and collect_operator_audit.safe_uuid(e.result->>'principal_id')=p_entity_id
  )branch(event_id,source,action,recorded_at,actor_id,request_id,revision,fence_version,reason_code) where isfinite(recorded_at)and recorded_at<=sample
   and(recorded_at,event_id)<(coalesce(p_before_at,'infinity'::timestamptz),coalesce(p_before_event_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
   order by recorded_at desc,event_id desc limit p_limit+1)
  union all
  (select *from(  select collect_operator_audit.operational_event_id('receipt_operations_owner_request',e.request_id),'receipt_operations_owner_request',
   'supervisor.operations.'||e.action,e.recorded_at,e.actor_id,e.request_id,
   case when p_entity_kind='receipt_operations_policy'then(e.result->>'revision')::bigint end,null::bigint,null::text
   from collect_receipt_operations.owner_requests e where p_entity_kind='receipt_operations_policy'and e.action in('configure','stop')
  )branch(event_id,source,action,recorded_at,actor_id,request_id,revision,fence_version,reason_code) where isfinite(recorded_at)and recorded_at<=sample
   and(recorded_at,event_id)<(coalesce(p_before_at,'infinity'::timestamptz),coalesce(p_before_event_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
   order by recorded_at desc,event_id desc limit p_limit+1)
  union all
  (select *from(  select collect_operator_audit.operational_event_id('receipt_operations_enrollment_workflow',e.request_id),'receipt_operations_enrollment_workflow',
   'supervisor.operations.'||e.action,e.recorded_at,e.actor_id,e.request_id,null::bigint,null::bigint,null::text
   from collect_receipt_operations.enrollment_workflow_requests e where p_entity_kind='supervisor_identity'
    and collect_operator_audit.safe_uuid(e.result->>'principal_id')=p_entity_id
  )branch(event_id,source,action,recorded_at,actor_id,request_id,revision,fence_version,reason_code) where isfinite(recorded_at)and recorded_at<=sample
   and(p_before_at is null or(recorded_at,event_id)<(p_before_at,p_before_event_id))
   order by recorded_at desc,event_id desc limit p_limit+1)
  union all
  (select collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id),'receipt_operations_service_request',
   'operations.'||e.action,e.recorded_at,null::uuid,e.request_id,null::bigint,r.fence_version,null::text
   from collect_receipt_operations.runs r cross join lateral(
    -- Lookup the original begin request before action/time filters: a retained
    -- principal's lifetime begin history never becomes this branch's input.
    select q.*from collect_receipt_operations.requests q where q.request_id=r.request_id limit 1
   )e where p_entity_kind='receipt_operation_run'and r.id=p_entity_id and e.principal_id=r.principal_id
    and e.action='begin_run'and e.result->>'run_id'=r.id::text and isfinite(e.recorded_at)and e.recorded_at<=sample
    and(e.recorded_at,collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id))<(coalesce(p_before_at,'infinity'::timestamptz),coalesce(p_before_event_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
  union all
  (select collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id),'receipt_operations_service_request',
   'operations.'||e.action,e.recorded_at,null::uuid,e.request_id,null::bigint,r.fence_version,null::text
   from collect_receipt_operations.runs r cross join lateral(
    select e.*from collect_receipt_operations.requests e where e.principal_id=r.principal_id and e.action='list_events'
     and collect_operator_audit.safe_uuid(e.input->>'run_id')=r.id and e.input->>'run_id'=r.id::text
     and e.input->>'fence_version'=r.fence_version::text and e.result->>'run_id'=r.id::text and e.result->>'fence_version'=r.fence_version::text
     and isfinite(e.recorded_at)and e.recorded_at<=sample
     and(e.recorded_at,collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id))<(coalesce(p_before_at,'infinity'::timestamptz),coalesce(p_before_event_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
    order by e.recorded_at desc,collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id)desc limit p_limit+1
   )e where p_entity_kind='receipt_operation_run'and r.id=p_entity_id)
  union all
  (select collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id),'receipt_operations_service_request',
   'operations.'||e.action,e.recorded_at,null::uuid,e.request_id,null::bigint,r.fence_version,null::text
   from collect_receipt_operations.runs r cross join lateral(
    select e.*from collect_receipt_operations.requests e where e.principal_id=r.principal_id and e.action='ensure_receipt'
     and collect_operator_audit.safe_uuid(e.input->>'run_id')=r.id and e.input->>'run_id'=r.id::text
     and e.input->>'fence_version'=r.fence_version::text and e.result->>'run_id'=r.id::text and e.result->>'fence_version'=r.fence_version::text
     and isfinite(e.recorded_at)and e.recorded_at<=sample
     and(e.recorded_at,collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id))<(coalesce(p_before_at,'infinity'::timestamptz),coalesce(p_before_event_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
    order by e.recorded_at desc,collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id)desc limit p_limit+1
   )e where p_entity_kind='receipt_operation_run'and r.id=p_entity_id)
  union all
  (select collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id),'receipt_operations_service_request',
   'operations.'||e.action,e.recorded_at,null::uuid,e.request_id,null::bigint,r.fence_version,null::text
   from collect_receipt_operations.runs r cross join lateral(
    select e.*from collect_receipt_operations.requests e where e.principal_id=r.principal_id and e.action='reconcile_backlog'
     and collect_operator_audit.safe_uuid(e.input->>'run_id')=r.id and e.input->>'run_id'=r.id::text
     and e.input->>'fence_version'=r.fence_version::text and e.result->>'run_id'=r.id::text and e.result->>'fence_version'=r.fence_version::text
     and isfinite(e.recorded_at)and e.recorded_at<=sample
     and(e.recorded_at,collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id))<(coalesce(p_before_at,'infinity'::timestamptz),coalesce(p_before_event_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
    order by e.recorded_at desc,collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id)desc limit p_limit+1
   )e where p_entity_kind='receipt_operation_run'and r.id=p_entity_id)
  union all
  (select collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id),'receipt_operations_service_request',
   'operations.'||e.action,e.recorded_at,null::uuid,e.request_id,null::bigint,r.fence_version,null::text
   from collect_receipt_operations.runs r cross join lateral(
    select e.*from collect_receipt_operations.requests e where e.principal_id=r.principal_id and e.action='complete_run'
     and collect_operator_audit.safe_uuid(e.input->>'run_id')=r.id and e.input->>'run_id'=r.id::text
     and e.input->>'fence_version'=r.fence_version::text and e.result->>'run_id'=r.id::text and e.result->>'fence_version'=r.fence_version::text
     and isfinite(e.recorded_at)and e.recorded_at<=sample
     and(e.recorded_at,collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id))<(coalesce(p_before_at,'infinity'::timestamptz),coalesce(p_before_event_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid))
    order by e.recorded_at desc,collect_operator_audit.operational_event_id('receipt_operations_service_request',e.request_id)desc limit p_limit+1
   )e where p_entity_kind='receipt_operation_run'and r.id=p_entity_id)
  union all
  (select *from(  select e.request_id,'exception_action','exception.'||e.action,e.recorded_at,e.actor_id,e.request_id,
   e.expected_revision,null::bigint,e.reason_code from collect_ops.exception_actions e
   where p_entity_kind='exception'and e.exception_id=p_entity_id
  )branch(event_id,source,action,recorded_at,actor_id,request_id,revision,fence_version,reason_code) where isfinite(recorded_at)and recorded_at<=sample
   and(p_before_at is null or(recorded_at,event_id)<(p_before_at,p_before_event_id))
   order by recorded_at desc,event_id desc limit p_limit+1)
  union all
  (select *from(  select e.request_id,'receipt_cancellation','receipt.cancel_unstarted',e.recorded_at,e.actor_id,e.request_id,
   e.revision,null::bigint,e.reason_code from collect_receipt_actions.cancellations e
   where p_entity_kind='receipt'and e.outbox_id=p_entity_id

  )branch(event_id,source,action,recorded_at,actor_id,request_id,revision,fence_version,reason_code) where isfinite(recorded_at)and recorded_at<=sample
   and(p_before_at is null or(recorded_at,event_id)<(p_before_at,p_before_event_id))
   order by recorded_at desc,event_id desc limit p_limit+1) ), page as materialized(
  select * from events where available and isfinite(recorded_at)and recorded_at<=sample
   and(p_before_at is null or(recorded_at,event_id)<(p_before_at,p_before_event_id))
   order by recorded_at desc,event_id desc limit p_limit+1
 ), shown as materialized(select * from page order by recorded_at desc,event_id desc limit p_limit)
 select jsonb_build_object('contract_version',1,'scope','rw_operator_entity_audit',
  'entity_kind',p_entity_kind,'entity_id',p_entity_id,'status',case when available then 'available'else 'unavailable'end,
  'checked_at',collect_ops.utc(sample),'sample_valid_until',collect_ops.utc(sample+interval '60 seconds'),
  'limit',p_limit,'history_complete',false,'historical_shadow_audit_backfilled',false,
  'financial_action',false,'send_action',false,
  'rows',coalesce((select jsonb_agg(jsonb_build_object('event_id',event_id,'source',source,'action',action,
   'recorded_at',collect_ops.utc(recorded_at),'actor_id',actor_id,'request_id',request_id,
   'revision',revision,'fence_version',fence_version,'reason_code',reason_code)
   order by recorded_at desc,event_id desc)from shown),'[]'::jsonb),
  'next_cursor',case when(select count(*)from page)>p_limit then
   (select jsonb_build_object('recorded_at',collect_ops.utc(recorded_at),'event_id',event_id)
    from shown order by recorded_at,event_id limit 1)else null end)into result;
 -- Natural expiry remains relevant even while row locks prevent revocation.
 perform collect_operator_audit.actor(p_entity_kind);
 if p_entity_kind in('receipt_operation_run','receipt_operations_policy')then perform collect_ops.actor(false);end if;
 return result;
exception when lock_not_available then raise exception 'operator_audit_authority_busy'using errcode='55P03';end$$;

revoke all on all functions in schema collect_receipt_history from public,anon,authenticated,service_role;
revoke all on function collect_operator_audit.operational_event_id(text,uuid)from public,anon,authenticated,service_role;
revoke all on function public.admin_list_receipt_operation_starts_v1(integer,timestamptz,uuid),
 public.admin_get_receipt_operation_run_v1(uuid),public.admin_list_receipt_operation_evidence_v1(uuid,text,integer,timestamptz,text)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_list_receipt_operation_starts_v1(integer,timestamptz,uuid),
 public.admin_get_receipt_operation_run_v1(uuid),public.admin_list_receipt_operation_evidence_v1(uuid,text,integer,timestamptz,text)to authenticated;
commit;
