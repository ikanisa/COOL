create or replace function public.admin_get_exception_entity_audit_v2(p_exception_id uuid,p_limit integer default 20,
 p_before_at timestamptz default null,p_before_event_id uuid default null)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare sample timestamptz;result jsonb;begin
 perform collect_operator_audit.exception_actor_v2(true);
 if p_exception_id is null or p_limit is null or p_limit not between 1 and 25
  or(p_before_at is null)is distinct from(p_before_event_id is null)
  or(p_before_at is not null and(not isfinite(p_before_at)
   or p_before_at<'0001-01-01T00:00:00Z'::timestamptz
   or p_before_at>='10000-01-01T00:00:00Z'::timestamptz))then
  raise exception 'exception_audit_input_invalid'using errcode='22023';end if;
 sample:=clock_timestamp();
 with scope as materialized(select exists(select 1 from collect_ops.exceptions e where e.id=p_exception_id
  and collect_operator_audit.exception_scope_v2(e.source_kind,e.source_id))available),
 events as not materialized(
  (select collect_operator_audit.exception_event_id('exception_action',r.request_id)event_id,
   'exception_action'::text source,r.request_id source_record_id,'exception.'||r.action action,r.recorded_at,
   'operator'::text actor_kind,r.actor_id,r.request_id,r.expected_revision revision,null::bigint workflow_revision,
   null::uuid escalation_id,r.reason_code,'immutable_request'::text origin,null::uuid assignee_id,null::timestamptz due_at
   from collect_ops.exception_actions r where r.exception_id=p_exception_id
    and r.recorded_at>='0001-01-01T00:00:00Z'::timestamptz and r.recorded_at<=sample
    and(p_before_at is null or(r.recorded_at,collect_operator_audit.exception_event_id('exception_action',r.request_id))<(p_before_at,p_before_event_id))
   order by r.recorded_at desc,collect_operator_audit.exception_event_id('exception_action',r.request_id)desc limit p_limit+1)
  union all (select collect_operator_audit.exception_event_id('exception_workflow_request',r.request_id),
   'exception_workflow_request',r.request_id,'exception.workflow.'||r.action,r.recorded_at,'operator',r.actor_id,r.request_id,
   r.expected_source_revision,(r.result->>'workflow_revision')::bigint,
   case when r.action='escalate'then collect_operator_audit.safe_uuid(r.result->>'escalation_id')end,r.reason_code,
   'immutable_request',case when r.action='assign'then r.assignee_id end,case when r.action='assign'then r.due_at end
   from collect_ops.exception_workflow_requests r where r.exception_id=p_exception_id
    and r.recorded_at>='0001-01-01T00:00:00Z'::timestamptz and r.recorded_at<=sample
    and(p_before_at is null or(r.recorded_at,collect_operator_audit.exception_event_id('exception_workflow_request',r.request_id))<(p_before_at,p_before_event_id))
   order by r.recorded_at desc,collect_operator_audit.exception_event_id('exception_workflow_request',r.request_id)desc limit p_limit+1)
  union all (select collect_operator_audit.exception_event_id('exception_escalation_event',r.id),
   'exception_escalation_event',r.id,'exception.escalation.'||r.action,r.recorded_at,r.actor_kind,r.actor_id,null::uuid,
   r.source_revision,null::bigint,r.escalation_id,e.reason_code,r.origin,null::uuid,null::timestamptz
   from collect_ops.exception_escalation_events r join collect_ops.exception_escalations e on e.id=r.escalation_id
   where r.exception_id=p_exception_id
    and r.recorded_at>='0001-01-01T00:00:00Z'::timestamptz and r.recorded_at<=sample
    and(p_before_at is null or(r.recorded_at,collect_operator_audit.exception_event_id('exception_escalation_event',r.id))<(p_before_at,p_before_event_id))
   order by r.recorded_at desc,collect_operator_audit.exception_event_id('exception_escalation_event',r.id)desc limit p_limit+1)
 ),page as materialized(select * from events where(select available from scope)
  and recorded_at>='0001-01-01T00:00:00Z'::timestamptz and recorded_at<=sample
  and(p_before_at is null or(recorded_at,event_id)<(p_before_at,p_before_event_id))
  order by recorded_at desc,event_id desc limit p_limit+1),
 shown as materialized(select * from page order by recorded_at desc,event_id desc limit p_limit)
 select jsonb_build_object('contract_version',2,'scope','rw_operator_entity_audit','entity_kind','exception',
  'entity_id',p_exception_id,'status',case when(select available from scope)then 'available'else 'unavailable'end,
  'checked_at',collect_ops.utc(sample),'sample_valid_until',collect_ops.utc(sample+interval '60 seconds'),
  'limit',p_limit,'history_complete',false,'financial_action',false,'send_action',false,
  'rows',coalesce((select jsonb_agg(jsonb_build_object('event_id',event_id,'source',source,
   'source_record_id',source_record_id,'action',action,'recorded_at',collect_ops.utc(recorded_at),
   'actor_kind',actor_kind,'actor_id',actor_id,'request_id',request_id,'revision',revision,
   'workflow_revision',workflow_revision,'escalation_id',escalation_id,'reason_code',reason_code,
   'origin',origin,'assignee_id',assignee_id,'due_at',collect_ops.utc(due_at))order by recorded_at desc,event_id desc)from shown),'[]'::jsonb),
  'next_cursor',case when(select count(*)from page)>p_limit then
   (select jsonb_build_object('recorded_at',collect_ops.utc(recorded_at),'event_id',event_id)
    from shown order by recorded_at,event_id limit 1)else null end)into result;
 perform collect_operator_audit.exception_actor_v2(true);
 return result;
exception when lock_not_available then raise exception 'exception_audit_authority_busy'using errcode='55P03';end$$;
