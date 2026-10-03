begin;
-- Additive private lifecycle evidence and bounded current-operator reads.
-- Delivery is committed availability in the Admin inbox, not carrier proof.
-- Serialize installation with existing owner/pump authority before capturing
-- retained facts; no financial, receipt, request or lifecycle source is changed.
select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
select pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
lock table collect_ops.exception_escalations,collect_ops.exception_inbox_deliveries,
 collect_ops.exception_inbox_reads in share row exclusive mode;

create table collect_ops.exception_escalation_events(
 id uuid primary key default gen_random_uuid(),
 escalation_id uuid not null references collect_ops.exception_escalations(id)on delete restrict,
 exception_id uuid not null references collect_ops.exceptions(id)on delete restrict,
 source_revision bigint not null check(source_revision between 1 and 1000000000),
 action text not null check(action in('queued','delivered','opened','obsolete','recipient_unavailable')),
 recorded_at timestamptz not null check(isfinite(recorded_at)),
 actor_kind text not null check(actor_kind in('operator','service','unknown')),
 actor_id uuid,
 origin text not null check(origin in('retained_source','captured_transition')),
 check((actor_kind='operator')=(actor_id is not null)),
 check(origin<>'retained_source'or actor_kind='unknown')
);
create unique index exception_escalation_single_phase on collect_ops.exception_escalation_events(escalation_id,action)
 where action<>'recipient_unavailable';
create index exception_escalation_event_order on collect_ops.exception_escalation_events(exception_id,recorded_at desc,id desc);
create index exception_workflow_audit_order on collect_ops.exception_workflow_requests(exception_id,recorded_at desc,request_id desc);
create index exception_inbox_recipient_order on collect_ops.exception_inbox_deliveries(recipient_id,delivered_at desc,escalation_id desc);
alter table collect_ops.exception_escalation_events enable row level security;
revoke all on collect_ops.exception_escalation_events from public,anon,authenticated,service_role;
create trigger retain_exception_escalation_events before update or delete on collect_ops.exception_escalation_events
 for each row execute function collect_ops.immutable_evidence();

create function collect_ops.capture_escalation_event()returns trigger
language plpgsql security definer set search_path=''as $$
declare e collect_ops.exception_escalations;phase text;at timestamptz;
 who text;actor uuid;begin
 if tg_table_name='exception_escalations'then
  e:=new;
  if tg_op='INSERT'then phase:='queued';at:=new.queued_at;
  elsif new.state='obsolete'and new.state is distinct from old.state then phase:='obsolete';at:=new.completed_at;
  elsif new.state='recipient_unavailable'and(new.state is distinct from old.state or new.retry_at is distinct from old.retry_at)then
   phase:='recipient_unavailable';at:=clock_timestamp();
  else return new;end if;
 else
  select * into strict e from collect_ops.exception_escalations where id=new.escalation_id;
  if tg_table_name='exception_inbox_deliveries'then phase:='delivered';at:=new.delivered_at;
  else phase:='opened';at:=new.read_at;end if;
 end if;
 who:=case when auth.role()='service_role'then 'service'
  when auth.role()='authenticated'and auth.uid()is not null then 'operator'else 'unknown'end;
 actor:=case when who='operator'then auth.uid()end;
 insert into collect_ops.exception_escalation_events(escalation_id,exception_id,source_revision,action,recorded_at,actor_kind,actor_id,origin)
 values(e.id,e.exception_id,e.source_revision,phase,at,who,actor,'captured_transition');
 return new;
end$$;
create trigger capture_exception_escalation_event after insert or update on collect_ops.exception_escalations
 for each row execute function collect_ops.capture_escalation_event();
create trigger capture_exception_inbox_delivery after insert on collect_ops.exception_inbox_deliveries
 for each row execute function collect_ops.capture_escalation_event();
create trigger capture_exception_inbox_opened after insert on collect_ops.exception_inbox_reads
 for each row execute function collect_ops.capture_escalation_event();

-- Known retained source timestamps are facts, not newly observed executions.
-- No unavailable-retry history is manufactured from a mutable current state.
insert into collect_ops.exception_escalation_events(escalation_id,exception_id,source_revision,action,recorded_at,actor_kind,origin)
 select e.id,e.exception_id,e.source_revision,'queued',e.queued_at,'unknown','retained_source'from collect_ops.exception_escalations e
 union all select e.id,e.exception_id,e.source_revision,'delivered',d.delivered_at,'unknown','retained_source'
 from collect_ops.exception_inbox_deliveries d join collect_ops.exception_escalations e on e.id=d.escalation_id
 union all select e.id,e.exception_id,e.source_revision,'opened',r.read_at,'unknown','retained_source'
 from collect_ops.exception_inbox_reads r join collect_ops.exception_escalations e on e.id=r.escalation_id
 union all select e.id,e.exception_id,e.source_revision,'obsolete',e.completed_at,'unknown','retained_source'
 from collect_ops.exception_escalations e where e.state='obsolete';

create function collect_operator_audit.exception_event_id(p_source text,p_record uuid)returns uuid
language sql immutable set search_path=''as $$
 select extensions.uuid_generate_v5('c5a97546-80ab-5b57-a267-754aac043bd0'::uuid,p_source||':'||p_record::text)
$$;
-- Pure scope derivation. This never invokes operational ensure/enqueue/refresh.
create function collect_operator_audit.exception_scope_v2(p_kind text,p_source uuid)returns boolean
language sql stable security definer set search_path=''as $$
 select case p_kind
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
create function collect_operator_audit.exception_actor_v2(p_audit boolean)returns uuid
language plpgsql volatile security definer set search_path=''as $$declare sid uuid;begin
 sid:=collect_ops.followup_v2_actor(false);
 if p_audit then perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',
  array['audit.read','payments.read','notifications.read','system_health.read']);end if;
 return sid;
end$$;

create function public.admin_get_exception_entity_audit_v2(p_exception_id uuid,p_limit integer default 20,
 p_before_at timestamptz default null,p_before_event_id uuid default null)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare available boolean;sample timestamptz;result jsonb;begin
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
  select collect_operator_audit.exception_event_id('exception_action',r.request_id)event_id,
   'exception_action'::text source,r.request_id source_record_id,'exception.'||r.action action,r.recorded_at,
   'operator'::text actor_kind,r.actor_id,r.request_id,r.expected_revision revision,null::bigint workflow_revision,
   null::uuid escalation_id,r.reason_code,'immutable_request'::text origin,null::uuid assignee_id,null::timestamptz due_at
   from collect_ops.exception_actions r where r.exception_id=p_exception_id
  union all select collect_operator_audit.exception_event_id('exception_workflow_request',r.request_id),
   'exception_workflow_request',r.request_id,'exception.workflow.'||r.action,r.recorded_at,'operator',r.actor_id,r.request_id,
   r.expected_source_revision,(r.result->>'workflow_revision')::bigint,
   case when r.action='escalate'then collect_operator_audit.safe_uuid(r.result->>'escalation_id')end,r.reason_code,
   'immutable_request',case when r.action='assign'then r.assignee_id end,case when r.action='assign'then r.due_at end
   from collect_ops.exception_workflow_requests r where r.exception_id=p_exception_id
  union all select collect_operator_audit.exception_event_id('exception_escalation_event',r.id),
   'exception_escalation_event',r.id,'exception.escalation.'||r.action,r.recorded_at,r.actor_kind,r.actor_id,null::uuid,
   r.source_revision,null::bigint,r.escalation_id,e.reason_code,r.origin,null::uuid,null::timestamptz
   from collect_ops.exception_escalation_events r join collect_ops.exception_escalations e on e.id=r.escalation_id
   where r.exception_id=p_exception_id
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

create function public.admin_list_exception_escalation_inbox_v2(p_limit integer default 20,
 p_before_delivered_at timestamptz default null,p_before_escalation_id uuid default null)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare sample timestamptz;result jsonb;begin
 perform collect_operator_audit.exception_actor_v2(false);
 if p_limit is null or p_limit not between 1 and 25
  or(p_before_delivered_at is null)is distinct from(p_before_escalation_id is null)
  or(p_before_delivered_at is not null and(not isfinite(p_before_delivered_at)
   or p_before_delivered_at<'0001-01-01T00:00:00Z'::timestamptz
   or p_before_delivered_at>='10000-01-01T00:00:00Z'::timestamptz))then
  raise exception 'exception_inbox_input_invalid'using errcode='22023';end if;
 sample:=clock_timestamp();
 with page as materialized(select d.escalation_id,e.id exception_id,s.source_revision,s.reason_code,
  e.active source_active,e.revision current_source_revision,d.delivered_at,r.read_at
  from collect_ops.exception_inbox_deliveries d join collect_ops.exception_escalations s on s.id=d.escalation_id
  join collect_ops.exceptions e on e.id=s.exception_id
  left join collect_ops.exception_inbox_reads r on r.escalation_id=d.escalation_id and r.recipient_id=auth.uid()
  where d.recipient_id=auth.uid()and s.recipient_id=d.recipient_id
   and d.delivered_at>='0001-01-01T00:00:00Z'::timestamptz and d.delivered_at<=sample
   and(p_before_delivered_at is null or(d.delivered_at,d.escalation_id)<(p_before_delivered_at,p_before_escalation_id))
  order by d.delivered_at desc,d.escalation_id desc limit p_limit+1),
 shown as materialized(select * from page order by delivered_at desc,escalation_id desc limit p_limit)
 select jsonb_build_object('contract_version',2,'channel','admin_inbox','scope','current_operator','recipient_id',auth.uid(),
  'checked_at',collect_ops.utc(sample),'sample_valid_until',collect_ops.utc(sample+interval '60 seconds'),'limit',p_limit,
  'rows',coalesce((select jsonb_agg(jsonb_build_object('escalation_id',escalation_id,'exception_id',exception_id,
   'source_revision',source_revision,'reason_code',reason_code,'source_active',source_active,
   'current_source_revision',current_source_revision,'delivered_at',collect_ops.utc(delivered_at),'read_at',collect_ops.utc(read_at))
   order by delivered_at desc,escalation_id desc)from shown),'[]'::jsonb),
  'next_cursor',case when(select count(*)from page)>p_limit then
   (select jsonb_build_object('delivered_at',collect_ops.utc(delivered_at),'escalation_id',escalation_id)
    from shown order by delivered_at,escalation_id limit 1)else null end)into result;
 perform collect_operator_audit.exception_actor_v2(false);
 return result;
exception when lock_not_available then raise exception 'exception_inbox_authority_busy'using errcode='55P03';end$$;

create function public.admin_read_exception_escalation_v2(p_escalation_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare result jsonb;begin
 perform collect_operator_audit.exception_actor_v2(false);
 result:=public.admin_read_exception_escalation_v1(p_escalation_id);
 perform collect_operator_audit.exception_actor_v2(false);
 return result||jsonb_build_object('contract_version',2);
exception when lock_not_available then raise exception 'exception_inbox_authority_busy'using errcode='55P03';end$$;

revoke all on function collect_ops.capture_escalation_event()from public,anon,authenticated,service_role;
revoke all on function collect_operator_audit.exception_event_id(text,uuid),
 collect_operator_audit.exception_scope_v2(text,uuid),collect_operator_audit.exception_actor_v2(boolean)
 from public,anon,authenticated,service_role;
revoke all on function public.admin_get_exception_entity_audit_v2(uuid,integer,timestamptz,uuid),
 public.admin_list_exception_escalation_inbox_v2(integer,timestamptz,uuid),
 public.admin_read_exception_escalation_v2(uuid)from public,anon,authenticated,service_role;
grant execute on function public.admin_get_exception_entity_audit_v2(uuid,integer,timestamptz,uuid),
 public.admin_list_exception_escalation_inbox_v2(integer,timestamptz,uuid),
 public.admin_read_exception_escalation_v2(uuid)to authenticated;
commit;
