begin;

-- Redacted, entity-scoped action evidence. This does not grant business,
-- financial, receipt dispatch or policy approval authority.
create schema collect_operator_audit;
revoke all on schema collect_operator_audit from public,anon,authenticated,service_role;
create table collect_operator_audit.shadow_events(
 event_id uuid primary key,
 run_id uuid not null references collect_security.shadow_supervisor_runs(id) on delete restrict,
 request_id uuid not null,
 actor_id uuid,
 fence_version bigint not null check(fence_version between 1 and 1000000000),
 action text not null check(action in('shadow.started','shadow.sampled','shadow.completed','shadow.expired')),
 recorded_at timestamptz not null check(isfinite(recorded_at)),
 unique(run_id,action)
);
alter table collect_operator_audit.shadow_events enable row level security;
revoke all on collect_operator_audit.shadow_events from public,anon,authenticated,service_role;
create function collect_operator_audit.immutable_shadow_event()returns trigger
language plpgsql set search_path=''as $$begin
 raise exception 'operator_audit_evidence_retained'using errcode='55000';end$$;
create trigger operator_shadow_audit_immutable before update or delete
 on collect_operator_audit.shadow_events for each row
 execute function collect_operator_audit.immutable_shadow_event();

create function collect_operator_audit.capture_shadow_event()returns trigger
language plpgsql security definer set search_path=''as $$
declare r collect_security.shadow_supervisor_runs;a text;t timestamptz;eid uuid;
begin
 if tg_table_name='shadow_supervisor_samples'then
  select * into strict r from collect_security.shadow_supervisor_runs where id=new.run_id;
  a:='shadow.sampled';t:=new.checked_at;
 else
  r:=new;
  if tg_op='INSERT'then a:='shadow.started';t:=r.started_at;
  elsif new.status is distinct from old.status and new.status='completed'then
   a:='shadow.completed';t:=r.completed_at;
  elsif new.status is distinct from old.status and new.status='expired'then
   a:='shadow.expired';t:=clock_timestamp();
  else return new;end if;
 end if;
 -- The executing actor is recorded, including the owner who expires a prior
 -- run. No original actor is substituted for a missing execution identity.
 insert into public.audit_logs(actor_user_id,action,entity_type,entity_id,metadata,created_at)
 values(auth.uid(),a,'collect_shadow_run',r.id,
  jsonb_build_object('request_id',r.request_id,'fence_version',r.fence_version,
   'mode','shadow','financial_action',false,'send_action',false),t)returning id into eid;
 insert into collect_operator_audit.shadow_events
 values(eid,r.id,r.request_id,auth.uid(),r.fence_version,a,t);
 return new;
end$$;
create trigger operator_shadow_run_audit after insert or update
 on collect_security.shadow_supervisor_runs for each row
 execute function collect_operator_audit.capture_shadow_event();
create trigger operator_shadow_sample_audit after insert
 on collect_security.shadow_supervisor_samples for each row
 execute function collect_operator_audit.capture_shadow_event();
-- No historical runs, public audit rows or financial records are backfilled.

create function collect_operator_audit.safe_uuid(p_text text)returns uuid
language sql immutable set search_path=''as $$
 select case when p_text~'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 then p_text::uuid else null end
$$;
create index operator_shadow_audit_order on collect_operator_audit.shadow_events(run_id,recorded_at desc,event_id desc);
create index operator_gateway_audit_order on collect_gateway.admin_requests
 (collect_operator_audit.safe_uuid(result->>'device_id'),recorded_at desc,request_id desc);
create index operator_supervisor_audit_order on collect_supervisor.owner_requests
 (collect_operator_audit.safe_uuid(result->>'principal_id'),recorded_at desc,request_id desc);
create index operator_exception_audit_order on collect_ops.exception_actions(exception_id,recorded_at desc,request_id desc);
create function collect_operator_audit.payment_scope(p_payment uuid)returns boolean
language sql stable security definer set search_path=''as $$
 select exists(select 1 from public.payments p where p.id=p_payment
  and collect_ops.payment_scope(p.id)
  and(p.parsed_event_id is null or collect_ops.transaction_sms_id('payment',p.id)is not null))
$$;
create function collect_operator_audit.actor(p_kind text)returns uuid
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;permissions text[]:=array['audit.read','system_health.read','notifications.read'];begin
 if current_setting('transaction_isolation')<>'read committed'then
  raise exception 'operator_audit_snapshot_retry'using errcode='40001';end if;
 sid:=public._lock_notification_registration_session();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 if p_kind in('exception','receipt')then permissions:=array_append(permissions,'payments.read');end if;
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',permissions);
 if not collect_admin_access.email_identity(auth.uid())then
  raise exception 'operator_audit_current_email_owner_required'using errcode='42501';end if;
 return sid;
end$$;

create function public.admin_get_operator_entity_audit_v1(p_entity_kind text,p_entity_id uuid,
 p_limit integer default 20,p_before_at timestamptz default null,p_before_event_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare available boolean;result jsonb;sample timestamptz;begin
 perform collect_operator_audit.actor(p_entity_kind);
 if p_entity_kind is null or p_entity_kind not in('shadow_run','gateway_device','exception','supervisor_identity','receipt')
  or p_entity_id is null or p_limit is null or p_limit not between 1 and 50
  or(p_before_at is null)is distinct from(p_before_event_id is null)
  or(p_before_at is not null and not isfinite(p_before_at))then
  raise exception 'operator_audit_input_invalid'using errcode='22023';end if;
 available:=case p_entity_kind
  when 'shadow_run'then exists(select 1 from collect_security.shadow_supervisor_runs where id=p_entity_id)
  when 'gateway_device'then exists(select 1 from collect_gateway.devices where id=p_entity_id)
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
  select e.event_id,'shadow_audit_event'::text source,e.action,e.recorded_at,e.actor_id,e.request_id,
   null::bigint revision,e.fence_version,null::text reason_code
   from collect_operator_audit.shadow_events e where p_entity_kind='shadow_run'and e.run_id=p_entity_id
  union all
  select e.request_id,'gateway_admin_request','gateway.'||e.action,e.recorded_at,e.actor_id,e.request_id,
   null::bigint,null::bigint,null::text from collect_gateway.admin_requests e
   where p_entity_kind='gateway_device'and collect_operator_audit.safe_uuid(e.result->>'device_id')=p_entity_id
  union all
  select e.request_id,'supervisor_owner_request','supervisor.'||e.action,e.recorded_at,e.actor_id,e.request_id,
   null::bigint,null::bigint,null::text from collect_supervisor.owner_requests e
   where p_entity_kind='supervisor_identity'and collect_operator_audit.safe_uuid(e.result->>'principal_id')=p_entity_id
  union all
  select e.request_id,'exception_action','exception.'||e.action,e.recorded_at,e.actor_id,e.request_id,
   e.expected_revision,null::bigint,e.reason_code from collect_ops.exception_actions e
   where p_entity_kind='exception'and e.exception_id=p_entity_id
  union all
  select e.request_id,'receipt_cancellation','receipt.cancel_unstarted',e.recorded_at,e.actor_id,e.request_id,
   e.revision,null::bigint,e.reason_code from collect_receipt_actions.cancellations e
   where p_entity_kind='receipt'and e.outbox_id=p_entity_id
 ), page as materialized(
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
 return result;
exception when lock_not_available then raise exception 'operator_audit_authority_busy'using errcode='55P03';end$$;

revoke all on all functions in schema collect_operator_audit from public,anon,authenticated,service_role;
revoke all on function public.admin_get_operator_entity_audit_v1(text,uuid,integer,timestamptz,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_get_operator_entity_audit_v1(text,uuid,integer,timestamptz,uuid)to authenticated;
commit;
