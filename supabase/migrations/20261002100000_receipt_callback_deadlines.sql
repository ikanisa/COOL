begin;
select pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
select pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
do $guard$declare v record;begin for v in select *from(values
('collect_operator_audit.exception_scope_v2(text,uuid)','1160b049b40f384bc205c51bfffe1a3cdc1af44c881c38dac350147e5d7403f1'),('collect_receipt_telemetry.refresh(uuid)','c068046b004375b15dbc42a86e047db687b14c6b7fb42efceef74aad336b448d'),('public.execute_receipt_exception_worker_v1(uuid,bigint,timestamptz)','32aaa90685ee143f46ff615cf8d7ce08319c5fdcea10bc9167e14b7353574bcc'))x(signature,sha)loop if to_regprocedure(v.signature)is null or(select encode(extensions.digest(prosrc,'sha256'),'hex')from pg_proc where oid=to_regprocedure(v.signature))is distinct from v.sha then raise exception 'callback_deadline_predecessor_drift:%',v.signature using errcode='55000';end if;end loop;end $guard$;
-- Private derived evidence. Original signed producers and identities remain intact.
create schema collect_receipt_callback_deadlines;
revoke all on schema collect_receipt_callback_deadlines from public,anon,authenticated,service_role;
create table collect_receipt_callback_deadlines.attempt_bindings(
 protocol_family text not null check(protocol_family in('primary_v2','receipt_successor')),
 attempt_id uuid not null,primary_attempt_id uuid references collect_gateway_dispatch.arms(attempt_id)on delete restrict,
 successor_attempt_id uuid references collect_receipt_successors.arms(attempt_id)on delete restrict,
 root_receipt_id uuid not null references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 collection_id uuid not null references public.collections(id)on delete restrict,
 run_id uuid not null references collect_receipt_operations.runs(id)on delete restrict,
 principal_id uuid not null references collect_supervisor.identities(id)on delete restrict,
 policy_revision bigint not null,arm_request_id uuid not null,armed_at timestamptz not null check(isfinite(armed_at)),
 callback_plan_sha256 text not null check(callback_plan_sha256~'^[0-9a-f]{64}$'),
 job_id uuid references collect_receipt_successors.jobs(id)on delete restrict,
 approval_id uuid references collect_receipt_successors.approvals(id)on delete restrict,
 primary key(protocol_family,attempt_id),
 check((protocol_family='primary_v2'and primary_attempt_id=attempt_id and successor_attempt_id is null and job_id is null and approval_id is null)
 or(protocol_family='receipt_successor'and successor_attempt_id=attempt_id and primary_attempt_id is null and job_id is not null and approval_id is not null)));
create table collect_receipt_callback_deadlines.pending(
 protocol_family text not null check(protocol_family in('primary_v2','receipt_successor')),attempt_id uuid not null,
 dirty_generation bigint not null check(dirty_generation between 1 and 1000000000),next_check_at timestamptz not null check(isfinite(next_check_at)),
 primary key(protocol_family,attempt_id));
create index callback_deadline_due on collect_receipt_callback_deadlines.pending(next_check_at,protocol_family,attempt_id);
create table collect_receipt_callback_deadlines.cases(
 id uuid primary key default gen_random_uuid(),protocol_family text not null,attempt_id uuid not null,
 rule_code text not null check(rule_code in('SEND_OUTCOME_UNKNOWN','DELIVERY_CALLBACK_GAP')),
 armed_at timestamptz not null,revision bigint not null check(revision between 1 and 1000000000),
 episode bigint not null check(episode between 1 and 1000000000),active boolean not null,
 source_sha256 text not null check(source_sha256~'^[0-9a-f]{64}$'),observed_at timestamptz not null,
 exception_id uuid references collect_ops.exceptions(id)on delete restrict,
 foreign key(protocol_family,attempt_id)references collect_receipt_callback_deadlines.attempt_bindings on delete restrict,
 unique(protocol_family,attempt_id,rule_code));
create index callback_deadline_family_order on collect_receipt_callback_deadlines.cases(protocol_family,armed_at desc,id desc);
create index callback_deadline_family_active_order on collect_receipt_callback_deadlines.cases(protocol_family,active,armed_at desc,id desc);
create table collect_receipt_callback_deadlines.observations(
 case_id uuid not null references collect_receipt_callback_deadlines.cases(id)on delete restrict,
 revision bigint not null,active boolean not null,episode bigint not null,source_sha256 text not null,
 source jsonb not null,observed_at timestamptz not null,primary key(case_id,revision));
create table collect_receipt_callback_deadlines.worker_results(
 request_id uuid primary key references collect_ops.receipt_worker_jobs(request_id)on delete restrict,
 configuration_revision bigint not null,expires_at timestamptz not null,telemetry_revision bigint not null,
 policy_revision bigint not null,recorded_at timestamptz not null,result jsonb not null);
-- Transaction-local admission receipt; no caller-controlled context or public helper.
create table collect_receipt_callback_deadlines.worker_invocations(
 request_id uuid primary key references collect_ops.receipt_worker_jobs(request_id)on delete restrict,
 backend_pid integer not null,transaction_id xid8 not null);
create table collect_receipt_callback_deadlines.seed_state(
 protocol_family text primary key check(protocol_family in('primary_v2','receipt_successor')),
 after_at timestamptz,after_attempt_id uuid,exhausted boolean not null default false,
 check((after_at is null)=(after_attempt_id is null)));
insert into collect_receipt_callback_deadlines.seed_state(protocol_family)values('primary_v2'),('receipt_successor');
create table collect_receipt_callback_deadlines.phase(singleton boolean primary key check(singleton),next_phase integer not null check(next_phase between 0 and 2));
insert into collect_receipt_callback_deadlines.phase values(true,0);
create index callback_deadline_primary_arm_order on collect_gateway_dispatch.arms(armed_at,attempt_id);
create index callback_deadline_successor_arm_order on collect_receipt_successors.arms(armed_at,attempt_id);
create index callback_deadline_primary_variants on collect_gateway_dispatch.callbacks(attempt_id,callback_id,result_code,(coalesce(tp_status,-1)),request_id);
create index callback_deadline_primary_causal on collect_gateway_dispatch.callbacks(attempt_id,recorded_at desc,request_id desc);
create index callback_deadline_successor_variants on collect_receipt_successors.callbacks(attempt_id,callback_id,result_code,(coalesce(tp_status,-1)),request_id);
create index callback_deadline_successor_causal on collect_receipt_successors.observation_events(attempt_id,lineage_after desc);

create function collect_receipt_callback_deadlines.identity_guard()returns trigger language plpgsql set search_path=''as $$begin
 if tg_op='DELETE'or(to_jsonb(new)-array['revision','episode','active','source_sha256','observed_at','exception_id'])is distinct from(to_jsonb(old)-array['revision','episode','active','source_sha256','observed_at','exception_id'])then
 raise exception 'callback_deadline_identity_immutable'using errcode='55000';end if;return new;end$$;
create trigger callback_deadline_identity before update or delete on collect_receipt_callback_deadlines.cases for each row execute function collect_receipt_callback_deadlines.identity_guard();
create function collect_receipt_callback_deadlines.collision_guard()returns trigger language plpgsql security definer set search_path=''as $$begin
 perform pg_advisory_xact_lock(hashtextextended('receipt-telemetry-source-identity:'||new.id::text,0));
 if(tg_table_schema='collect_receipt_telemetry'and exists(select 1 from collect_receipt_callback_deadlines.cases where id=new.id))
 or(tg_table_schema='collect_receipt_callback_deadlines'and exists(select 1 from collect_receipt_telemetry.alert_heads where id=new.id))then
 raise exception 'callback_deadline_source_collision'using errcode='55000';end if;return new;end$$;
create trigger callback_deadline_case_collision before insert on collect_receipt_callback_deadlines.cases for each row execute function collect_receipt_callback_deadlines.collision_guard();
create trigger callback_deadline_aggregate_collision before insert on collect_receipt_telemetry.alert_heads for each row execute function collect_receipt_callback_deadlines.collision_guard();
create function collect_receipt_callback_deadlines.enqueue()returns trigger language plpgsql security definer set search_path=''as $$
declare a uuid;f text;begin
 f:=case tg_table_schema when'collect_gateway_dispatch'then'primary_v2'else'receipt_successor'end;
 if tg_table_name='attempts'then a:=new.id;else a:=new.attempt_id;end if;
 if f='primary_v2'and not exists(select 1 from collect_gateway_dispatch.arms where attempt_id=a)then return new;end if;
 insert into collect_receipt_callback_deadlines.pending values(f,a,1,clock_timestamp())
 on conflict(protocol_family,attempt_id)do update set dirty_generation=collect_receipt_callback_deadlines.pending.dirty_generation+1,next_check_at=least(collect_receipt_callback_deadlines.pending.next_check_at,excluded.next_check_at);
 return new;end$$;
lock table collect_gateway_dispatch.arms,collect_gateway_dispatch.callbacks,collect_gateway_dispatch.attempts,collect_receipt_successors.arms,collect_receipt_successors.callbacks in share row exclusive mode;
create trigger callback_deadline_primary_arm after insert on collect_gateway_dispatch.arms for each row execute function collect_receipt_callback_deadlines.enqueue();
create trigger callback_deadline_primary_callback after insert on collect_gateway_dispatch.callbacks for each row execute function collect_receipt_callback_deadlines.enqueue();
create trigger callback_deadline_primary_state after update of state on collect_gateway_dispatch.attempts for each row execute function collect_receipt_callback_deadlines.enqueue();
create trigger callback_deadline_successor_arm after insert on collect_receipt_successors.arms for each row execute function collect_receipt_callback_deadlines.enqueue();
create trigger callback_deadline_successor_callback after insert on collect_receipt_successors.callbacks for each row execute function collect_receipt_callback_deadlines.enqueue();

create function collect_receipt_callback_deadlines.admit(p_family text,p_attempt uuid)returns collect_receipt_callback_deadlines.attempt_bindings
language plpgsql volatile security definer set search_path=''as $$declare b collect_receipt_callback_deadlines.attempt_bindings;begin
 if p_family='primary_v2'then
  insert into collect_receipt_callback_deadlines.attempt_bindings
  select 'primary_v2',a.id,a.id,null,o.id,o.collection_id,a.run_id,a.principal_id,a.policy_revision,r.request_id,r.armed_at,
   encode(extensions.digest(r.callback_plan::text,'sha256'),'hex'),null,null
  from collect_gateway_dispatch.attempts a join collect_gateway_dispatch.arms r on r.attempt_id=a.id
  join collect_hybrid.sms_notification_outbox o on o.id=a.outbox_id where a.id=p_attempt on conflict do nothing;
 elsif p_family='receipt_successor'then
  insert into collect_receipt_callback_deadlines.attempt_bindings
  select 'receipt_successor',a.id,null,a.id,j.root_outbox_id,o.collection_id,a.run_id,a.principal_id,a.policy_revision,r.request_id,r.armed_at,
   encode(extensions.digest(r.callback_plan::text,'sha256'),'hex'),j.id,j.approval_id
  from collect_receipt_successors.attempts a join collect_receipt_successors.arms r on r.attempt_id=a.id
  join collect_receipt_successors.jobs j on j.id=a.job_id join collect_hybrid.sms_notification_outbox o on o.id=j.root_outbox_id where a.id=p_attempt on conflict do nothing;
 else raise exception 'callback_deadline_family_invalid'using errcode='22023';end if;
 select *into b from collect_receipt_callback_deadlines.attempt_bindings where protocol_family=p_family and attempt_id=p_attempt;
 if b.attempt_id is null then raise exception 'callback_deadline_source_unavailable'using errcode='55000';end if;return b;end$$;

-- Exactly two indexed variant extrema per original slot, plus one causal endpoint.
create function collect_receipt_callback_deadlines.source(p_family text,p_attempt uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare
 b collect_receipt_callback_deadlines.attempt_bindings;plan jsonb;n integer;sticky boolean:=false;
 slot record;f record;l record;sent integer:=0;delivery integer:=0;conflict boolean:=false;failure boolean:=false;
 cb uuid;causal jsonb;latest record;idx integer;k text;begin
 select *into b from collect_receipt_callback_deadlines.attempt_bindings where protocol_family=p_family and attempt_id=p_attempt;
 if b.attempt_id is null then raise exception 'callback_deadline_source_unavailable'using errcode='55000';end if;
 if p_family='primary_v2'then
  select r.callback_plan,a.segment_count,a.state='uncertain'into plan,n,sticky from collect_gateway_dispatch.arms r join collect_gateway_dispatch.attempts a on a.id=r.attempt_id where a.id=p_attempt and a.outbox_id=b.root_receipt_id and r.request_id=b.arm_request_id and r.armed_at=b.armed_at;
 else
  select r.callback_plan,a.segment_count into plan,n from collect_receipt_successors.arms r join collect_receipt_successors.attempts a on a.id=r.attempt_id
  where a.id=p_attempt and a.job_id=b.job_id and r.request_id=b.arm_request_id and r.armed_at=b.armed_at and r.route is not distinct from collect_receipt_successors.route(b.job_id);
 end if;
 if n is null or jsonb_array_length(plan)<>n or encode(extensions.digest(plan::text,'sha256'),'hex')<>b.callback_plan_sha256 then raise exception 'callback_deadline_binding_invalid'using errcode='55000';end if;
 for idx in 0..n-1 loop
  for k in select unnest(array['sent','delivery'])loop
   cb:=((plan->idx)->>case k when'sent'then'sent_callback_id'else'delivery_callback_id'end)::uuid;
   if cb is null then raise exception 'callback_deadline_binding_invalid'using errcode='55000';end if;
   if p_family='primary_v2'then
    perform 1 from collect_gateway_dispatch.callback_bindings where callback_id=cb and attempt_id=p_attempt and segment_index=idx and callback_kind=k;
    if not found then raise exception 'callback_deadline_binding_invalid'using errcode='55000';end if;
    select request_id,result_code,coalesce(tp_status,-1)tp into f from collect_gateway_dispatch.callbacks where attempt_id=p_attempt and callback_id=cb order by result_code,coalesce(tp_status,-1),request_id limit 1;
    select request_id,result_code,coalesce(tp_status,-1)tp into l from collect_gateway_dispatch.callbacks where attempt_id=p_attempt and callback_id=cb order by result_code desc,coalesce(tp_status,-1)desc,request_id desc limit 1;
   else
    select request_id,result_code,coalesce(tp_status,-1)tp into f from collect_receipt_successors.callbacks where attempt_id=p_attempt and callback_id=cb order by result_code,coalesce(tp_status,-1),request_id limit 1;
    select request_id,result_code,coalesce(tp_status,-1)tp into l from collect_receipt_successors.callbacks where attempt_id=p_attempt and callback_id=cb order by result_code desc,coalesce(tp_status,-1)desc,request_id desc limit 1;
    if f.request_id is not null then perform collect_receipt_successors.investigation_observation(b.root_receipt_id,p_attempt,f.request_id);end if;
    if l.request_id is not null and l.request_id is distinct from f.request_id then perform collect_receipt_successors.investigation_observation(b.root_receipt_id,p_attempt,l.request_id);end if;
   end if;
   if f.request_id is not null then
    if(f.result_code,f.tp)is distinct from(l.result_code,l.tp)then conflict:=true;
    elsif k='sent'then sent:=sent+1;else delivery:=delivery+1;end if;
    failure:=failure or(k='sent'and(f.result_code<>-1 or l.result_code<>-1))or(k='delivery'and(f.result_code<>-1 or l.result_code<>-1 or f.tp>=64 or l.tp>=64));
   end if;
  end loop;
 end loop;
 if p_family='primary_v2'then
  select request_id,recorded_at into latest from collect_gateway_dispatch.callbacks where attempt_id=p_attempt order by recorded_at desc,request_id desc limit 1;
  causal:=jsonb_build_object('request_id',latest.request_id,'recorded_at',collect_ops.utc(latest.recorded_at),'lineage_revision',null);
 else
  select request_id,lineage_after,recorded_at into latest from collect_receipt_successors.observation_events where attempt_id=p_attempt order by lineage_after desc limit 1;
  if latest.request_id is not null then perform collect_receipt_successors.investigation_observation(b.root_receipt_id,p_attempt,latest.request_id);end if;
  causal:=jsonb_build_object('request_id',latest.request_id,'recorded_at',collect_ops.utc(latest.recorded_at),'lineage_revision',latest.lineage_after);
 end if;
 return jsonb_build_object('expected_segments',n,'sent_covered',sent,'delivery_covered',delivery,'conflict',conflict,'failure',failure,'sticky_uncertainty',sticky,'causal',causal);
end$$;

create function collect_receipt_callback_deadlines.refresh_attempt(p_family text,p_attempt uuid)returns void
language plpgsql volatile security definer set search_path=''as $$declare b collect_receipt_callback_deadlines.attempt_bindings;
 c collect_receipt_callback_deadlines.cases;facts jsonb;sig text;rule text;active_value boolean;t timestamptz;generation bigint;reason text;root uuid;begin
 if p_family='primary_v2'then select outbox_id into root from collect_gateway_dispatch.attempts where id=p_attempt;
 elsif p_family='receipt_successor'then select j.root_outbox_id into root from collect_receipt_successors.attempts a join collect_receipt_successors.jobs j on j.id=a.job_id where a.id=p_attempt;end if;
 if root is null then raise exception 'callback_deadline_source_unavailable'using errcode='55000';end if;
 perform 1 from collect_hybrid.sms_notification_outbox where id=root for update nowait;
 b:=collect_receipt_callback_deadlines.admit(p_family,p_attempt);
 if p_family='primary_v2'then perform 1 from collect_gateway_dispatch.attempts where id=p_attempt for update nowait;end if;
 select dirty_generation into generation from collect_receipt_callback_deadlines.pending where protocol_family=p_family and attempt_id=p_attempt;
 facts:=collect_receipt_callback_deadlines.source(p_family,p_attempt);t:=clock_timestamp();
 for rule in select unnest(array['SEND_OUTCOME_UNKNOWN','DELIVERY_CALLBACK_GAP'])loop
  active_value:=case rule when'SEND_OUTCOME_UNKNOWN'then(facts->>'sticky_uncertainty')::boolean or(facts->>'conflict')::boolean
   or(p_family='receipt_successor'and(facts->>'failure')::boolean)or(t>=b.armed_at+interval '120 seconds'and(facts->>'sent_covered')::integer<(facts->>'expected_segments')::integer)
   else t>=b.armed_at+interval '300 seconds'and(facts->>'delivery_covered')::integer<(facts->>'expected_segments')::integer end;
  sig:=encode(extensions.digest(jsonb_build_array(active_value,facts)::text,'sha256'),'hex');
  select *into c from collect_receipt_callback_deadlines.cases where protocol_family=p_family and attempt_id=p_attempt and rule_code=rule;
  if c.id is null then
   insert into collect_receipt_callback_deadlines.cases(protocol_family,attempt_id,rule_code,armed_at,revision,episode,active,source_sha256,observed_at)
   values(p_family,p_attempt,rule,b.armed_at,1,1,active_value,sig,t)returning *into c;
  elsif c.source_sha256<>sig then
   update collect_receipt_callback_deadlines.cases set revision=revision+1,episode=episode+case when not active and active_value then 1 else 0 end,active=active_value,source_sha256=sig,observed_at=t where id=c.id returning *into c;
  else continue;end if;
  insert into collect_receipt_callback_deadlines.observations values(c.id,c.revision,c.active,c.episode,sig,facts,t);
  reason:=case rule when'SEND_OUTCOME_UNKNOWN'then'TELEMETRY_SEND_OUTCOME_UNKNOWN'else'TELEMETRY_DELIVERY_CALLBACK_GAP'end;
  perform collect_ops.observe('receipt_telemetry',c.id,case when active_value then array[reason]else array[]::text[]end,
   jsonb_build_object('episode',c.episode,'status',case when active_value then'active'else'clear'end));
  update collect_receipt_callback_deadlines.cases set exception_id=(select id from collect_ops.exceptions where source_kind='receipt_telemetry'and source_id=c.id and reason_code=reason)where id=c.id;
 end loop;
 -- Compare the inspected generation under the same root/attempt producer fences.
 delete from collect_receipt_callback_deadlines.pending where protocol_family=p_family and attempt_id=p_attempt and dirty_generation=generation;
 if t<b.armed_at+interval '300 seconds'then
  insert into collect_receipt_callback_deadlines.pending values(p_family,p_attempt,1,case when t<b.armed_at+interval '120 seconds'then b.armed_at+interval '120 seconds'else b.armed_at+interval '300 seconds'end)on conflict do nothing;
 end if;
end$$;

create function collect_receipt_callback_deadlines.process_job(p_job uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare j collect_ops.receipt_worker_jobs;cfg collect_receipt_telemetry.configuration;
 s collect_receipt_callback_deadlines.seed_state;key record;phase_value integer;family text;lim integer;used integer:=0;busy integer:=0;unavailable integer:=0;
 keys uuid[];more boolean:=false;result jsonb;begin
 perform collect_ops.receipt_exception_service();select *into j from collect_ops.receipt_worker_jobs where request_id=p_job;
 if not exists(select 1 from collect_receipt_callback_deadlines.worker_invocations i where i.request_id=p_job and i.backend_pid=pg_backend_pid()and i.transaction_id=pg_current_xact_id())or j.expires_at<=clock_timestamp()then raise exception 'callback_deadline_worker_admission_required'using errcode='42501';end if;
 select *into cfg from collect_receipt_telemetry.configuration where singleton for share;
 if not cfg.enabled then return jsonb_build_object('status','inactive','processed',0,'busy',0,'unavailable',0,'partial',true);end if;
 lim:=least(j.scan_limit,25);select next_phase into phase_value from collect_receipt_callback_deadlines.phase where singleton for update;
 -- Persistent phase gives seeding and due work turns even with continuous arrivals.
 for offset_value in 0..2 loop
  exit when used>=lim;
  if(phase_value+offset_value)%3<2 then
   family:=case(phase_value+offset_value)%3 when 0 then'primary_v2'else'receipt_successor'end;
   select *into s from collect_receipt_callback_deadlines.seed_state where protocol_family=family for update;
   if s.exhausted then continue;end if;
   if family='primary_v2'then
    if s.after_at is null then select array_agg(attempt_id order by armed_at,attempt_id)into keys from(select attempt_id,armed_at from collect_gateway_dispatch.arms order by armed_at,attempt_id limit lim-used+1)b;
    else select array_agg(attempt_id order by armed_at,attempt_id)into keys from(select attempt_id,armed_at from collect_gateway_dispatch.arms where(armed_at,attempt_id)>(s.after_at,s.after_attempt_id)order by armed_at,attempt_id limit lim-used+1)b;end if;
   else
    if s.after_at is null then select array_agg(attempt_id order by armed_at,attempt_id)into keys from(select attempt_id,armed_at from collect_receipt_successors.arms order by armed_at,attempt_id limit lim-used+1)b;
    else select array_agg(attempt_id order by armed_at,attempt_id)into keys from(select attempt_id,armed_at from collect_receipt_successors.arms where(armed_at,attempt_id)>(s.after_at,s.after_attempt_id)order by armed_at,attempt_id limit lim-used+1)b;end if;
   end if;
   more:=more or coalesce(cardinality(keys),0)>lim-used;
   for idx in 1..least(coalesce(cardinality(keys),0),lim-used)loop
    used:=used+1;
    insert into collect_receipt_callback_deadlines.pending values(family,keys[idx],1,clock_timestamp())on conflict do nothing;
    begin perform collect_receipt_callback_deadlines.refresh_attempt(family,keys[idx]);exception when lock_not_available then busy:=busy+1;when sqlstate '55000'then
     if sqlerrm not in('callback_deadline_source_unavailable','callback_deadline_binding_invalid','receipt_successor_execution_binding_invalid')then raise;end if;unavailable:=unavailable+1;end;
    if family='primary_v2'then select armed_at,attempt_id into key from collect_gateway_dispatch.arms where attempt_id=keys[idx];else select armed_at,attempt_id into key from collect_receipt_successors.arms where attempt_id=keys[idx];end if;
    update collect_receipt_callback_deadlines.seed_state set after_at=key.armed_at,after_attempt_id=key.attempt_id where protocol_family=family;
   end loop;
   if coalesce(cardinality(keys),0)=0 then update collect_receipt_callback_deadlines.seed_state set exhausted=true where protocol_family=family;end if;
  else
   for key in select *from(select protocol_family,attempt_id from collect_receipt_callback_deadlines.pending where next_check_at<=clock_timestamp()order by next_check_at,protocol_family,attempt_id limit lim-used+1)b loop
    if used>=lim then more:=true;exit;end if;used:=used+1;
    begin perform collect_receipt_callback_deadlines.refresh_attempt(key.protocol_family,key.attempt_id);exception when lock_not_available then busy:=busy+1;when sqlstate '55000'then
     if sqlerrm not in('callback_deadline_source_unavailable','callback_deadline_binding_invalid','receipt_successor_execution_binding_invalid')then raise;end if;unavailable:=unavailable+1;end;
   end loop;
  end if;
 end loop;
 update collect_receipt_callback_deadlines.phase set next_phase=(phase_value+1)%3 where singleton;
 return jsonb_build_object('status',case when busy+unavailable>0 or more then'partial'else'processed'end,'processed',used-busy-unavailable,'busy',busy,'unavailable',unavailable,'partial',busy+unavailable>0 or more
  or exists(select 1 from collect_receipt_callback_deadlines.seed_state where not exhausted)
  or exists(select 1 from collect_receipt_callback_deadlines.pending where next_check_at<=clock_timestamp()));
end$$;

create function collect_receipt_callback_deadlines.row(p_case uuid)returns jsonb language sql stable security definer set search_path=''as $$
 select jsonb_build_object('case_id',c.id,'rule_code',c.rule_code,'protocol_family',c.protocol_family,'root_receipt_id',b.root_receipt_id,'attempt_id',b.attempt_id,'approval_id',b.approval_id,
  'arm_request_id',b.arm_request_id,'armed_at',collect_ops.utc(b.armed_at),'due_at',collect_ops.utc(b.armed_at+case c.rule_code when'SEND_OUTCOME_UNKNOWN'then interval '120 seconds'else interval '300 seconds'end),
  'revision',c.revision,'episode',c.episode,'active',c.active,'observed_at',collect_ops.utc(c.observed_at),'source',o.source,'exception_id',c.exception_id,
  'refresh_pending',exists(select 1 from collect_receipt_callback_deadlines.pending p where p.protocol_family=c.protocol_family and p.attempt_id=c.attempt_id))
 from collect_receipt_callback_deadlines.cases c join collect_receipt_callback_deadlines.attempt_bindings b using(protocol_family,attempt_id)
 join collect_receipt_callback_deadlines.observations o on o.case_id=c.id and o.revision=c.revision where c.id=p_case
$$;
create function public.admin_list_receipt_callback_deadlines_v1(p_protocol_family text,p_active boolean default true,p_limit integer default 20,p_before_at timestamptz default null,p_before_case_id uuid default null,p_cursor_query_sha256 text default null)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare ids uuid[];rows jsonb:='[]';at timestamptz;qh text;last_case collect_receipt_callback_deadlines.cases;cfg collect_receipt_telemetry.configuration;side jsonb;begin
 perform collect_ops.actor(false);
 if p_protocol_family not in('primary_v2','receipt_successor')or p_protocol_family is null or p_limit is null or p_limit not between 1 and 25
 or(p_before_at is null)<>(p_before_case_id is null)or(p_before_at is null)<>(p_cursor_query_sha256 is null)or(p_before_at is not null and not isfinite(p_before_at))then raise exception 'callback_deadline_query_invalid'using errcode='22023';end if;
 if p_protocol_family='receipt_successor'then perform collect_receipt_actions.actor(false);end if;
 qh:=encode(extensions.digest(jsonb_build_array(p_protocol_family,p_active,p_limit)::text,'sha256'),'hex');
 if p_cursor_query_sha256 is not null and p_cursor_query_sha256<>qh then raise exception 'callback_deadline_cursor_query_changed'using errcode='22023';end if;
 -- Four finite query identities keep generic-plan cursor predicates indexable.
 if p_active is null then
  if p_before_at is null then select array_agg(id order by armed_at desc,id desc)into ids from(select id,armed_at from collect_receipt_callback_deadlines.cases where protocol_family=p_protocol_family order by armed_at desc,id desc limit p_limit+1)b;
  else select array_agg(id order by armed_at desc,id desc)into ids from(select id,armed_at from collect_receipt_callback_deadlines.cases where protocol_family=p_protocol_family and(armed_at,id)<(p_before_at,p_before_case_id)order by armed_at desc,id desc limit p_limit+1)b;end if;
 else
  if p_before_at is null then select array_agg(id order by armed_at desc,id desc)into ids from(select id,armed_at from collect_receipt_callback_deadlines.cases where protocol_family=p_protocol_family and active=p_active order by armed_at desc,id desc limit p_limit+1)b;
  else select array_agg(id order by armed_at desc,id desc)into ids from(select id,armed_at from collect_receipt_callback_deadlines.cases where protocol_family=p_protocol_family and active=p_active and(armed_at,id)<(p_before_at,p_before_case_id)order by armed_at desc,id desc limit p_limit+1)b;end if;
 end if;
 for idx in 1..least(coalesce(cardinality(ids),0),p_limit)loop rows:=rows||jsonb_build_array(collect_receipt_callback_deadlines.row(ids[idx]));end loop;
 if cardinality(ids)>p_limit then select *into last_case from collect_receipt_callback_deadlines.cases where id=ids[p_limit];end if;
 select *into cfg from collect_receipt_telemetry.configuration where singleton;
 select result into side from collect_receipt_callback_deadlines.worker_results order by recorded_at desc,request_id desc limit 1;
 perform collect_ops.actor(false);if p_protocol_family='receipt_successor'then perform collect_receipt_actions.actor(false);end if;at:=clock_timestamp();
 return jsonb_build_object('contract_version',1,'scope','receipt_callback_deadlines','protocol_family',p_protocol_family,'active_filter',p_active,'limit',p_limit,'query_sha256',qh,'checked_at',collect_ops.utc(at),'sample_valid_until',collect_ops.utc(at+interval '60 seconds'),'status','available',
 'rows',rows,'scanned_count',least(coalesce(cardinality(ids),0),p_limit),'next_cursor',case when last_case.id is null then null else jsonb_build_object('before_at',collect_ops.utc(last_case.armed_at),'before_case_id',last_case.id,'query_sha256',qh)end,
 'seed_progress',(select jsonb_agg(jsonb_build_object('protocol_family',protocol_family,'after_at',collect_ops.utc(after_at),'after_attempt_id',after_attempt_id,'exhausted',exhausted)order by protocol_family)from collect_receipt_callback_deadlines.seed_state),
 'publication_enabled',cfg.enabled,'last_worker',side,'financial_action',false,'send_action',false,'carrier_proof',false,'delivery_proven',false);end$$;
create index callback_deadline_worker_order on collect_receipt_callback_deadlines.worker_results(recorded_at desc,request_id desc);
create function public.admin_get_receipt_callback_deadline_v1(p_case_id uuid,p_cutoff_revision bigint default null,p_after_revision bigint default null,p_limit integer default 20)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare c collect_receipt_callback_deadlines.cases;cutoff bigint;items jsonb;ids bigint[];at timestamptz;begin
 perform collect_ops.actor(false);
 if p_case_id is null or p_limit is null or p_limit not between 1 and 25 or(p_cutoff_revision is null)<>(p_after_revision is null)then raise exception 'callback_deadline_query_invalid'using errcode='22023';end if;
 select *into c from collect_receipt_callback_deadlines.cases where id=p_case_id;
 if c.protocol_family='receipt_successor'then perform collect_receipt_actions.actor(false);end if;
 cutoff:=coalesce(p_cutoff_revision,c.revision);
 if p_cutoff_revision is not null and(p_after_revision<1 or p_cutoff_revision<1 or p_after_revision>=p_cutoff_revision or p_cutoff_revision>c.revision)then raise exception 'callback_deadline_cutoff_invalid'using errcode='22023';end if;
 select array_agg(revision order by revision)into ids from(select revision from collect_receipt_callback_deadlines.observations where case_id=p_case_id and revision>coalesce(p_after_revision,0)and revision<=cutoff order by revision limit p_limit+1)b;
 select coalesce(jsonb_agg(jsonb_build_object('revision',revision,'active',active,'episode',episode,'source_sha256',source_sha256,'source',source,'observed_at',collect_ops.utc(observed_at))order by revision),'[]')into items from collect_receipt_callback_deadlines.observations where case_id=p_case_id and revision=any(ids[1:p_limit]);
 perform collect_ops.actor(false);if c.protocol_family='receipt_successor'then perform collect_receipt_actions.actor(false);end if;at:=clock_timestamp();
 return jsonb_build_object('contract_version',1,'scope','receipt_callback_deadline_detail','case_id',p_case_id,'cutoff_revision',cutoff,'after_revision',p_after_revision,'limit',p_limit,'checked_at',collect_ops.utc(at),'sample_valid_until',collect_ops.utc(at+interval '60 seconds'),'status',case when c.id is null then'unavailable'else'available'end,
 'head',collect_receipt_callback_deadlines.row(p_case_id),'items',items,'scanned_count',least(coalesce(cardinality(ids),0),p_limit),'next_revision',case when cardinality(ids)>p_limit then ids[p_limit]else null end,'financial_action',false,'send_action',false,'carrier_proof',false,'delivery_proven',false);end$$;

create function collect_receipt_callback_deadlines.audit_scope(p_source uuid)returns boolean
language plpgsql volatile security definer set search_path=''as $$declare c collect_receipt_callback_deadlines.cases;b collect_receipt_callback_deadlines.attempt_bindings;ok boolean;begin
 perform collect_ops.actor(false);
 select *into c from collect_receipt_callback_deadlines.cases where id=p_source;
 if c.id is null then return false;end if;
 if exists(select 1 from collect_receipt_telemetry.alert_heads where id=p_source)then raise exception 'callback_deadline_source_collision'using errcode='55000';end if;
 select *into b from collect_receipt_callback_deadlines.attempt_bindings where protocol_family=c.protocol_family and attempt_id=c.attempt_id;
 if c.protocol_family='receipt_successor'then perform collect_receipt_actions.actor(false);end if;
 select exists(select 1 from collect_hybrid.sms_notification_outbox o join public.payments p on p.id=o.payment_id join public.collections col on col.id=p.collection_id
  where o.id=b.root_receipt_id and o.collection_id=b.collection_id and p.collection_id=b.collection_id and col.currency='RWF'and not col.diaspora_enabled
  and collect_operator_audit.payment_scope(p.id)and collect_receipt_actions.rwanda_source(o)
  and case b.protocol_family when'primary_v2'then exists(select 1 from collect_gateway_dispatch.attempts a join collect_gateway_dispatch.arms arm on arm.attempt_id=a.id
   where a.id=b.attempt_id and a.outbox_id=o.id and a.run_id=b.run_id and a.principal_id=b.principal_id and a.policy_revision=b.policy_revision
   and arm.request_id=b.arm_request_id and arm.armed_at=b.armed_at and encode(extensions.digest(arm.callback_plan::text,'sha256'),'hex')=b.callback_plan_sha256)
  else exists(select 1 from collect_receipt_successors.attempts a join collect_receipt_successors.arms arm on arm.attempt_id=a.id join collect_receipt_successors.jobs j on j.id=a.job_id join collect_receipt_successors.approvals approval on approval.id=j.approval_id
   where a.id=b.attempt_id and j.id=b.job_id and j.root_outbox_id=o.id and j.approval_id=b.approval_id and approval.root_outbox_id=o.id
   and a.run_id=b.run_id and a.principal_id=b.principal_id and a.policy_revision=b.policy_revision and arm.request_id=b.arm_request_id and arm.armed_at=b.armed_at
   and arm.route is not distinct from collect_receipt_successors.route(j.id)and encode(extensions.digest(arm.callback_plan::text,'sha256'),'hex')=b.callback_plan_sha256)end)into ok;
 perform collect_ops.actor(false);if c.protocol_family='receipt_successor'then perform collect_receipt_actions.actor(false);end if;return ok;end$$;

do $$declare n text;begin foreach n in array array['attempt_bindings','pending','cases','observations','worker_results','worker_invocations','seed_state','phase']loop
 execute format('alter table collect_receipt_callback_deadlines.%I enable row level security',n);
 execute format('revoke all on collect_receipt_callback_deadlines.%I from public,anon,authenticated,service_role',n);
 if n in('attempt_bindings','observations','worker_results')then execute format('create trigger callback_deadline_immutable before update or delete on collect_receipt_callback_deadlines.%I for each row execute function collect_ops.immutable_evidence()',n);end if;
 execute format('create trigger callback_deadline_no_truncate before truncate on collect_receipt_callback_deadlines.%I for each statement execute function collect_ops.immutable_evidence()',n);
 end loop;end$$;
revoke all on all functions in schema collect_receipt_callback_deadlines from public,anon,authenticated,service_role;
revoke all on function public.admin_list_receipt_callback_deadlines_v1(text,boolean,integer,timestamptz,uuid,text),public.admin_get_receipt_callback_deadline_v1(uuid,bigint,bigint,integer)from public,anon,authenticated,service_role;
grant execute on function public.admin_list_receipt_callback_deadlines_v1(text,boolean,integer,timestamptz,uuid,text),public.admin_get_receipt_callback_deadline_v1(uuid,bigint,bigint,integer)to authenticated;

create or replace function collect_operator_audit.exception_scope_v2(p_kind text,p_source uuid)returns boolean
language sql stable security definer set search_path=''as $$
 select case p_kind
 when 'receipt_telemetry'then case when exists(select 1 from collect_receipt_callback_deadlines.cases where id=p_source)then collect_receipt_callback_deadlines.audit_scope(p_source)else exists(select 1 from collect_receipt_telemetry.alert_heads h where h.id=p_source
  and not exists(select 1 from unnest(h.collection_ids)scoped(collection_id)left join public.collections c on c.id=scoped.collection_id
   where c.id is null or c.currency<>'RWF'or c.diaspora_enabled))end
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
create or replace function collect_receipt_telemetry.refresh(p_source uuid)returns void
language plpgsql volatile security definer set search_path=''as $$
declare h collect_receipt_telemetry.alert_heads;p collect_receipt_operations.policy;m jsonb;at timestamptz;deadline collect_receipt_callback_deadlines.cases;begin
 -- Shared workflow lock is acquired by existing action/deadline callers before
 -- this helper. Use the same order in the sampler and never hold source locks
 -- before policy locks. Trigger producers do not enter these operational locks.
 if auth.role()='authenticated'then perform collect_ops.actor(false);
 elsif auth.role()='service_role'then perform collect_ops.receipt_exception_service();
 else raise exception 'receipt_telemetry_source_authority_required'using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
 perform pg_advisory_xact_lock(hashtext('collect-receipt-telemetry-sampler'));
 select *into deadline from collect_receipt_callback_deadlines.cases where id=p_source;
 if deadline.id is not null then
  if exists(select 1 from collect_receipt_telemetry.alert_heads where id=p_source)then raise exception 'callback_deadline_source_collision'using errcode='55000';end if;
  if auth.role()='authenticated'and deadline.protocol_family='receipt_successor'then perform collect_receipt_actions.actor(false);end if;
  perform collect_receipt_callback_deadlines.refresh_attempt(deadline.protocol_family,deadline.attempt_id);return;
 end if;
 -- Checked private job context, never a caller-controlled GUC/claim. An
 -- aggregate refresh reached by this pump remains stopped until its whole
 -- same-snapshot source/plan admission closure is separately accepted.
 if auth.role()='service_role'and exists(select 1 from collect_receipt_callback_deadlines.worker_invocations i
  join collect_ops.receipt_worker_jobs j on j.request_id=i.request_id
  join collect_ops.receipt_worker_configuration c on c.singleton and c.enabled and c.revision=j.configuration_revision
  where i.backend_pid=pg_backend_pid()and i.transaction_id=pg_current_xact_id()and j.expires_at>clock_timestamp()
  and not exists(select 1 from collect_ops.receipt_worker_receipts r where r.request_id=j.request_id))then
  raise exception 'callback_deadline_aggregate_not_admitted'using errcode='55000';end if;
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
create or replace function public.execute_receipt_exception_worker_v1(p_request_id uuid,p_configuration_revision bigint,p_expires_at timestamptz)
returns jsonb language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare c collect_ops.receipt_worker_configuration;j collect_ops.receipt_worker_jobs;prior collect_ops.receipt_worker_receipts;
 scan jsonb;escalation jsonb;result jsonb;t timestamptz;deadline jsonb;telemetry collect_receipt_telemetry.configuration;policy_revision bigint;escalation_status text:='processed';begin
 perform collect_ops.receipt_exception_service();
 if p_request_id is null or p_configuration_revision is null or p_configuration_revision<1 or p_expires_at is null or not isfinite(p_expires_at)
  then raise exception 'receipt_worker_request_invalid'using errcode='22023';end if;
 -- Lock order is global authority, then original job, then scanner/workflow.
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-trusted-worker'))then
  return jsonb_build_object('contract_version',1,'request_id',p_request_id,'status','in_progress','receipt',null);end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-worker-job:'||p_request_id::text,0));
 select * into j from collect_ops.receipt_worker_jobs where request_id=p_request_id;
 if j.request_id is null then raise exception 'receipt_worker_job_unavailable'using errcode='42501';end if;
 if j.configuration_revision<>p_configuration_revision or j.expires_at<>p_expires_at then
  raise exception 'receipt_worker_original_conflict'using errcode='22023';end if;
 select * into prior from collect_ops.receipt_worker_receipts where request_id=p_request_id;
 if prior.request_id is not null then return jsonb_build_object('contract_version',1,'request_id',p_request_id,'status','recorded','receipt',collect_receipt_worker_history.read_payload('worker_receipt',prior.request_id::text));end if;
 select * into c from collect_ops.receipt_worker_configuration where singleton for share;
 if not c.enabled or c.revision<>j.configuration_revision then raise exception 'receipt_worker_authority_lost'using errcode='42501';end if;
 if j.expires_at<=clock_timestamp()or exists(select 1 from collect_ops.receipt_worker_expirations where request_id=j.request_id)
  then raise exception 'receipt_worker_expired'using errcode='55000';end if;
 -- The escalation pump takes roster before workflow. Acquire both before
 -- the scanner so the combined transaction preserves that same lock order.
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 perform pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
 if j.expires_at<=clock_timestamp()then raise exception 'receipt_worker_expired'using errcode='55000';end if;
 scan:=public.process_receipt_deferral_exceptions_v1(j.request_id,j.scan_limit,j.expires_at);
 select *into telemetry from collect_receipt_telemetry.configuration where singleton for share;
 select revision into policy_revision from collect_receipt_operations.policy where singleton for share nowait;
 insert into collect_receipt_callback_deadlines.worker_invocations values(j.request_id,pg_backend_pid(),pg_current_xact_id());
 if scan->>'status'='processed'then
  deadline:=collect_receipt_callback_deadlines.process_job(j.request_id);
  begin escalation:=public.process_exception_escalations_v1(j.escalation_limit);
  exception when sqlstate '55000'then
   if sqlerrm<>'callback_deadline_aggregate_not_admitted'then raise;end if;
   escalation_status:='deferred_aggregate_not_admitted';
   escalation:=jsonb_build_object('contract_version',1,'channel','admin_inbox','delivered',0,'obsolete',0,'recipient_unavailable',0,'external_send',false);
  end;
 else escalation:=jsonb_build_object('contract_version',1,'channel','admin_inbox','delivered',0,'obsolete',0,'recipient_unavailable',0,'external_send',false);end if;
 t:=clock_timestamp();if j.expires_at<=t then raise exception 'receipt_worker_expired'using errcode='55000';end if;
 perform collect_ops.receipt_exception_service();
 if(select revision from collect_receipt_telemetry.configuration where singleton)is distinct from telemetry.revision then raise exception 'callback_deadline_configuration_changed'using errcode='55000';end if;
 if(select revision from collect_ops.receipt_worker_configuration where singleton)is distinct from j.configuration_revision then raise exception 'receipt_worker_authority_lost'using errcode='42501';end if;
 deadline:=jsonb_build_object('contract_version',1,'request_id',j.request_id,'configuration_revision',j.configuration_revision,'expires_at',collect_ops.utc(j.expires_at),'telemetry_revision',telemetry.revision,'policy_revision',policy_revision,'recorded_at',collect_ops.utc(t),
  'deadlines',coalesce(deadline,jsonb_build_object('status','unavailable','processed',0,'busy',0,'unavailable',0,'partial',true)),
  'aggregate_status','not_admitted','aggregate_reason','complete_input_plan_closure_unproved','escalation_status',escalation_status,'financial_action',false,'send_action',false);
 insert into collect_receipt_callback_deadlines.worker_results values(j.request_id,j.configuration_revision,j.expires_at,telemetry.revision,policy_revision,t,deadline);
 delete from collect_receipt_callback_deadlines.worker_invocations where request_id=j.request_id;
 -- Scan, source observations, inbox delivery and this receipt commit together.
 result:=jsonb_build_object('contract_version',1,'request_id',j.request_id,'configuration_revision',j.configuration_revision,
  'recorded_at',collect_ops.utc(t),'expires_at',collect_ops.utc(j.expires_at),'status',case when scan->>'status'='busy'then 'busy'else 'completed'end,
  'scan',scan,'escalation',escalation,'financial_action',false,'send_action',false,'external_send',false);
 insert into collect_ops.receipt_worker_receipts values(j.request_id,t,result,j.request_id);
 return jsonb_build_object('contract_version',1,'request_id',p_request_id,'status','recorded','receipt',result);
end$$;
commit;
