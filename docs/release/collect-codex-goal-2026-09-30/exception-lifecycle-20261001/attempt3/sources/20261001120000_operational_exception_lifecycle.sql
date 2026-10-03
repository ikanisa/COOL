begin;

-- Escalations use a durable, private Admin inbox. Delivery means committed
-- availability in that inbox; read acknowledgement is separate. No SMS, push,
-- payment or external communication is performed by these functions.
create table collect_ops.exception_workflows(
 exception_id uuid primary key references collect_ops.exceptions(id) on delete restrict,
 revision bigint not null check(revision between 1 and 1000000000),
 source_revision bigint not null check(source_revision between 1 and 1000000000),
 assignee_id uuid not null references auth.users(id) on delete restrict,
 due_at timestamptz not null check(isfinite(due_at)),
 resolved_source_revision bigint check(resolved_source_revision between 1 and 1000000000),
 last_request_id uuid not null,
 updated_at timestamptz not null check(isfinite(updated_at))
);
create table collect_ops.exception_workflow_requests(
 request_id uuid primary key,
 exception_id uuid not null references collect_ops.exceptions(id) on delete restrict,
 actor_id uuid not null,
 session_id uuid not null,
 expected_source_revision bigint not null,
 expected_workflow_revision bigint not null,
 action text not null check(action in('assign','escalate','resolve')),
 assignee_id uuid,
 due_at timestamptz,
 reason_code text not null check(reason_code in('review_started','owner_review_required','uncertain_send_review','contact_review','source_rechecked')),
 result jsonb not null,
 recorded_at timestamptz not null check(isfinite(recorded_at))
);
create table collect_ops.exception_escalations(
 id uuid primary key default gen_random_uuid(),
 exception_id uuid not null references collect_ops.exceptions(id) on delete restrict,
 source_revision bigint not null check(source_revision between 1 and 1000000000),
 recipient_id uuid not null references auth.users(id) on delete restrict,
 reason_code text not null check(reason_code in('operator_escalation','deadline_exceeded')),
 queued_at timestamptz not null default clock_timestamp() check(isfinite(queued_at)),
 retry_at timestamptz not null default clock_timestamp() check(isfinite(retry_at)),
 state text not null default 'queued' check(state in('queued','delivered','obsolete','recipient_unavailable')),
 completed_at timestamptz check(isfinite(completed_at)),
 unique(exception_id,source_revision,recipient_id),
 check((state in('queued','recipient_unavailable'))=(completed_at is null))
);
create index exception_escalation_work on collect_ops.exception_escalations(state,queued_at,id);
create table collect_ops.exception_inbox_deliveries(
 escalation_id uuid primary key references collect_ops.exception_escalations(id) on delete restrict,
 recipient_id uuid not null references auth.users(id) on delete restrict,
 delivered_at timestamptz not null check(isfinite(delivered_at))
);
create table collect_ops.exception_inbox_reads(
 escalation_id uuid primary key references collect_ops.exception_inbox_deliveries(escalation_id) on delete restrict,
 recipient_id uuid not null references auth.users(id) on delete restrict,
 read_at timestamptz not null check(isfinite(read_at))
);
do $$declare t text;begin
 foreach t in array array['exception_workflows','exception_workflow_requests','exception_escalations',
  'exception_inbox_deliveries','exception_inbox_reads']loop
  execute format('alter table collect_ops.%I enable row level security',t);
  execute format('revoke all on collect_ops.%I from public,anon,authenticated,service_role',t);
 end loop;
 foreach t in array array['exception_workflow_requests','exception_inbox_deliveries','exception_inbox_reads']loop
  execute format('create trigger retain_%I before update or delete on collect_ops.%I for each row execute function collect_ops.immutable_evidence()',t,t);
 end loop;
end$$;
create function collect_ops.protect_workflow()returns trigger language plpgsql set search_path=''as $$begin
 if tg_op='DELETE' or new.exception_id<>old.exception_id or new.revision<>old.revision+1
  or new.updated_at<old.updated_at then
  raise exception 'exception_workflow_revision_invalid'using errcode='55000';end if;
 return new;end$$;
create trigger protect_exception_workflow before update or delete on collect_ops.exception_workflows
 for each row execute function collect_ops.protect_workflow();
create function collect_ops.protect_escalation()returns trigger language plpgsql set search_path=''as $$begin
 if tg_op='DELETE' or (to_jsonb(new)-array['state','completed_at','retry_at'])is distinct from
  (to_jsonb(old)-array['state','completed_at','retry_at']) or old.state in('delivered','obsolete')then
  raise exception 'exception_escalation_evidence_retained'using errcode='55000';end if;
 return new;end$$;
create trigger protect_exception_escalation before update or delete on collect_ops.exception_escalations
 for each row execute function collect_ops.protect_escalation();

create function collect_ops.recipient_available(p_user uuid)returns boolean
language sql stable security definer set search_path=''as $$
 select collect_admin_access.email_identity(p_user) and exists(
  select 1 from public.admin_user_roles u join public.admin_roles r on r.id=u.role_id
  where u.user_id=p_user and u.revoked_at is null and r.name='platform_owner'
   and not exists(select 1 from unnest(array['payments.read','notifications.read','system_health.read'])permission
    where not exists(select 1 from public.admin_role_permissions p where p.role_id=r.id and p.permission_name=permission)))
$$;
create function collect_ops.workflow_projection(p_exception uuid)returns jsonb
language sql stable security definer set search_path=''as $$
 select jsonb_build_object('contract_version',1,'exception_id',e.id,'source_revision',e.revision,
  'source_active',e.active,'workflow_revision',coalesce(w.revision,0),
  'assignee_id',w.assignee_id,'recipient_available',case when w.assignee_id is null then false
   else collect_ops.recipient_available(w.assignee_id)end,'due_at',collect_ops.utc(w.due_at),
  'overdue',e.active and w.due_at<clock_timestamp(),
  'status',case when not e.active and w.resolved_source_revision=e.revision then 'resolved'
   when not e.active then 'source_cleared' when w.exception_id is null then 'unassigned'else 'assigned'end,
  'escalations',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'source_revision',s.source_revision,
   'recipient_id',s.recipient_id,'state',s.state,'queued_at',collect_ops.utc(s.queued_at),
   'delivered_at',(select collect_ops.utc(d.delivered_at)from collect_ops.exception_inbox_deliveries d where d.escalation_id=s.id),
   'read_at',(select collect_ops.utc(d.read_at)from collect_ops.exception_inbox_reads d where d.escalation_id=s.id))order by s.queued_at desc,s.id desc)
   from(select * from collect_ops.exception_escalations where exception_id=e.id order by queued_at desc,id desc limit 10)s),'[]'::jsonb))
 from collect_ops.exceptions e left join collect_ops.exception_workflows w on w.exception_id=e.id where e.id=p_exception
$$;
create function public.admin_get_exception_workflow_v1(p_exception_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare at timestamptz;result jsonb;begin
 perform collect_ops.actor(false);
 if p_exception_id is null then raise exception 'exception_workflow_input_invalid'using errcode='22023';end if;
 at:=clock_timestamp();result:=collect_ops.workflow_projection(p_exception_id);
 if result is null then raise exception 'exception_workflow_unavailable'using errcode='22023';end if;
 return result||jsonb_build_object('checked_at',collect_ops.utc(at),'sample_valid_until',collect_ops.utc(at+interval '60 seconds'));
end$$;

create function public.admin_act_exception_workflow_v1(p_request_id uuid,p_exception_id uuid,
 p_expected_source_revision bigint,p_expected_workflow_revision bigint,p_action text,
 p_assignee_id uuid,p_due_at timestamptz,p_reason_code text)returns jsonb
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
  or(p_action='resolve'and p_reason_code<>'source_rechecked')then
  raise exception 'exception_workflow_input_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-ops-workflow-request:'||p_request_id::text,0));
 select * into prior from collect_ops.exception_workflow_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.exception_id<>p_exception_id
   or prior.expected_source_revision<>p_expected_source_revision or prior.expected_workflow_revision<>p_expected_workflow_revision
   or prior.action<>p_action or prior.assignee_id is distinct from p_assignee_id
   or prior.due_at is distinct from p_due_at or prior.reason_code<>p_reason_code then
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
 if(p_action='resolve'and item.active)or(p_action<>'resolve'and not item.active)then
  raise exception 'exception_workflow_source_state_invalid'using errcode='55000';end if;
 at:=clock_timestamp();next_revision:=coalesce(w.revision,0)+1;
 if p_action='assign'then
  if not collect_ops.recipient_available(p_assignee_id)then raise exception 'exception_workflow_recipient_unavailable'using errcode='42501';end if;
  if p_due_at<=at or p_due_at>at+interval '30 days'then raise exception 'exception_workflow_deadline_invalid'using errcode='22023';end if;
 else
  if w.exception_id is null then raise exception 'exception_workflow_assignment_required'using errcode='55000';end if;
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
  p_expected_workflow_revision,p_action,p_assignee_id,p_due_at,p_reason_code,result,at);
 perform public.create_audit_log('operations.exception.workflow.'||p_action,'operational_exception',item.id,
  jsonb_build_object('request_id',p_request_id,'source_revision',item.revision,'workflow_revision',next_revision,
   'reason_code',p_reason_code,'escalation_id',escalation,'financial_action',false,'send_action',false),auth.uid());
 return result;
end$$;
create function public.admin_get_exception_workflow_request_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare prior collect_ops.exception_workflow_requests;acquired boolean;at timestamptz;begin
 perform collect_ops.actor(false);
 if p_request_id is null then raise exception 'exception_workflow_input_invalid'using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-ops-workflow-request:'||p_request_id::text,0));
 select * into prior from collect_ops.exception_workflow_requests where acquired and request_id=p_request_id and actor_id=auth.uid();
 at:=clock_timestamp();return jsonb_build_object('contract_version',1,'request_id',p_request_id,
  'checked_at',collect_ops.utc(at),'sample_valid_until',collect_ops.utc(at+interval '60 seconds'),
  'status',case when not acquired then 'in_progress'when prior.request_id is null then 'not_recorded'else 'recorded'end,'receipt',prior.result);
end$$;

create function public.process_exception_escalations_v1(p_limit integer default 20)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare s collect_ops.exception_escalations;e collect_ops.exceptions;w collect_ops.exception_workflows;
 delivered integer:=0;obsolete integer:=0;unavailable integer:=0;at timestamptz;begin
 if auth.role()is distinct from 'service_role'then raise exception 'exception_escalation_service_required'using errcode='42501';end if;
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'exception_escalation_snapshot_retry'using errcode='40001';end if;
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'exception_escalation_limit_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 perform pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
 at:=clock_timestamp();
 -- Repeated deadline sweeps preserve one stable work identity per source revision/recipient.
 for w in select x.* from collect_ops.exception_workflows x join collect_ops.exceptions ex on ex.id=x.exception_id
  where ex.active and x.due_at<=at and not exists(select 1 from collect_ops.exception_escalations job
   where job.exception_id=ex.id and job.source_revision=ex.revision and job.recipient_id=x.assignee_id)
  order by x.due_at,x.exception_id limit p_limit loop
  select * into e from collect_ops.exceptions where id=w.exception_id;
  perform collect_ops.refresh_source(e.source_kind,e.source_id);
  select * into e from collect_ops.exceptions where id=w.exception_id;
  if e.active then insert into collect_ops.exception_escalations(exception_id,source_revision,recipient_id,reason_code)
   values(e.id,e.revision,w.assignee_id,'deadline_exceeded')on conflict do nothing;end if;
 end loop;
 at:=clock_timestamp();
 for s in select * from collect_ops.exception_escalations where state in('queued','recipient_unavailable')and retry_at<=at
  order by retry_at,queued_at,id limit p_limit for update skip locked loop
  select * into e from collect_ops.exceptions where id=s.exception_id;
  perform collect_ops.refresh_source(e.source_kind,e.source_id);
  select * into e from collect_ops.exceptions where id=s.exception_id;
  select * into w from collect_ops.exception_workflows where exception_id=e.id;
  if not e.active or e.revision<>s.source_revision or w.assignee_id is distinct from s.recipient_id then
   update collect_ops.exception_escalations set state='obsolete',completed_at=clock_timestamp()where id=s.id;obsolete:=obsolete+1;
  elsif not collect_ops.recipient_available(s.recipient_id)then
   update collect_ops.exception_escalations set state='recipient_unavailable',retry_at=clock_timestamp()+interval '60 seconds'where id=s.id;
   unavailable:=unavailable+1;
  else
   insert into collect_ops.exception_inbox_deliveries values(s.id,s.recipient_id,clock_timestamp());
   update collect_ops.exception_escalations set state='delivered',completed_at=clock_timestamp()where id=s.id;
   delivered:=delivered+1;
  end if;
 end loop;
 return jsonb_build_object('contract_version',1,'channel','admin_inbox','delivered',delivered,'obsolete',obsolete,
  'recipient_unavailable',unavailable,'external_send',false);
end$$;
create function public.admin_list_exception_escalation_inbox_v1(p_limit integer default 20)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare at timestamptz;rows jsonb;begin
 perform collect_ops.actor(false);
 if p_limit is null or p_limit not between 1 and 50 then raise exception 'exception_escalation_limit_invalid'using errcode='22023';end if;
 at:=clock_timestamp();
 select coalesce(jsonb_agg(jsonb_build_object('escalation_id',d.escalation_id,'exception_id',s.exception_id,
  'source_revision',s.source_revision,'reason_code',s.reason_code,'source_active',e.active,
  'current_source_revision',e.revision,'delivered_at',collect_ops.utc(d.delivered_at),'read_at',collect_ops.utc(r.read_at))
  order by d.delivered_at desc,d.escalation_id desc),'[]'::jsonb)into rows
 from(select * from collect_ops.exception_inbox_deliveries where recipient_id=auth.uid()
  order by delivered_at desc,escalation_id desc limit p_limit)d
 join collect_ops.exception_escalations s on s.id=d.escalation_id
 join collect_ops.exceptions e on e.id=s.exception_id
 left join collect_ops.exception_inbox_reads r on r.escalation_id=d.escalation_id;
 return jsonb_build_object('contract_version',1,'channel','admin_inbox','checked_at',collect_ops.utc(at),
  'sample_valid_until',collect_ops.utc(at+interval '60 seconds'),'rows',rows);
end$$;
create function public.admin_read_exception_escalation_v1(p_escalation_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare d collect_ops.exception_inbox_deliveries;r collect_ops.exception_inbox_reads;begin
 perform collect_ops.actor(false);
 select * into d from collect_ops.exception_inbox_deliveries where escalation_id=p_escalation_id and recipient_id=auth.uid();
 if d.escalation_id is null then raise exception 'exception_escalation_delivery_unavailable'using errcode='42501';end if;
 insert into collect_ops.exception_inbox_reads values(d.escalation_id,auth.uid(),clock_timestamp())on conflict do nothing;
 select * into r from collect_ops.exception_inbox_reads where escalation_id=d.escalation_id;
 return jsonb_build_object('contract_version',1,'escalation_id',r.escalation_id,'read_at',collect_ops.utc(r.read_at),'source_resolved',false);
end$$;
revoke all on function collect_ops.protect_workflow(),collect_ops.protect_escalation(),
 collect_ops.recipient_available(uuid),collect_ops.workflow_projection(uuid)from public,anon,authenticated,service_role;
revoke all on function public.admin_get_exception_workflow_v1(uuid),
 public.admin_act_exception_workflow_v1(uuid,uuid,bigint,bigint,text,uuid,timestamptz,text),
 public.admin_get_exception_workflow_request_v1(uuid),public.process_exception_escalations_v1(integer),
 public.admin_list_exception_escalation_inbox_v1(integer),public.admin_read_exception_escalation_v1(uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_get_exception_workflow_v1(uuid),
 public.admin_act_exception_workflow_v1(uuid,uuid,bigint,bigint,text,uuid,timestamptz,text),
 public.admin_get_exception_workflow_request_v1(uuid),public.admin_list_exception_escalation_inbox_v1(integer),
 public.admin_read_exception_escalation_v1(uuid)to authenticated;
grant execute on function public.process_exception_escalations_v1(integer)to service_role;
notify pgrst,'reload schema';
commit;
