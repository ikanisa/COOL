begin;
-- Read-only finite inspection. Existing producers and v1/v2/v3 wires are retained.
create function collect_receipt_successors.investigation_root(p_approval uuid)returns uuid
language plpgsql volatile set search_path=''as $$declare root uuid;ids uuid[];begin
 perform collect_receipt_actions.actor(false);
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'receipt_successor_snapshot_retry'using errcode='40001';end if;
 if p_approval is null then raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 select root_outbox_id into root from collect_receipt_successors.approvals where id=p_approval;
 perform 1 from collect_hybrid.sms_notification_outbox where id=root for share;
 perform collect_receipt_actions.actor(false);
 select a.root_outbox_id into root from collect_receipt_successors.approvals a
 join collect_hybrid.sms_notification_outbox o on o.id=a.root_outbox_id
 where a.id=p_approval and collect_receipt_actions.rwanda_source(o);
 if root is null then return null;end if;
 select array_agg(id)into ids from(select id from collect_receipt_successors.jobs where root_outbox_id=root limit 2)bounded;
 if coalesce(cardinality(ids),0)>1 then raise exception 'receipt_successor_execution_topology_unsupported'using errcode='55000';end if;
 return root;end$$;

create function collect_receipt_successors.investigation_observation(p_root uuid,p_attempt uuid,p_request uuid)returns jsonb
language plpgsql volatile set search_path=''as $$declare
 a collect_receipt_successors.attempts;arm collect_receipt_successors.arms;
 e collect_receipt_successors.observation_events;c collect_receipt_successors.callbacks;
 r collect_receipt_successors.gateway_requests;route jsonb;occurred timestamptz;begin
 select *into a from collect_receipt_successors.attempts where id=p_attempt;
 select *into arm from collect_receipt_successors.arms where attempt_id=p_attempt;
 select *into e from collect_receipt_successors.observation_events where request_id=p_request;
 select *into c from collect_receipt_successors.callbacks where request_id=p_request;
 select *into r from collect_receipt_successors.gateway_requests where request_id=p_request;
 route:=collect_receipt_successors.route(a.job_id);
 if a.id is null or arm.attempt_id is null or e.request_id is null or c.request_id is null or r.request_id is null
  or route->>'primary_receipt_id' is distinct from p_root::text
  or e.root_outbox_id is distinct from p_root or e.attempt_id is distinct from a.id
  or c.attempt_id is distinct from a.id or c.recorded_at is distinct from e.recorded_at
  or c.segment_index<0 or c.segment_index>=a.segment_count
  or e.lineage_after is distinct from e.lineage_before+1 or e.observed_state not in('armed_unknown','observed_sent','uncertain')
  or r.action is distinct from 'callback'or r.device_id is distinct from a.device_id
  or r.route is distinct from route or r.recorded_at<c.recorded_at then
  raise exception 'receipt_successor_execution_binding_invalid'using errcode='55000';end if;
 perform collect_gateway.payload_keys(r.payload,array['route','callback_id','attempt_id','fence_version','segment_index','segment_count','body_sha256','destination_sha256','callback_kind','result_code','tp_status','occurred_at']);
 perform collect_gateway.payload_keys(r.result,array['contract_version','protocol_family','route','callback_id','attempt_id','recorded_at','replay','state','sent_observations','delivery_observations','conflicting_observations','failed_observations','send_authority','carrier_proof','delivery_proven']);
 occurred:=collect_gateway.payload_time(r.payload,'occurred_at');
 if r.payload->'route' is distinct from route or r.payload->>'callback_id' is distinct from c.callback_id::text
  or r.payload->>'attempt_id' is distinct from a.id::text
  or r.payload->>'fence_version' is distinct from a.fence_version::text
  or r.payload->>'segment_count' is distinct from a.segment_count::text
  or r.payload->>'segment_index' is distinct from c.segment_index::text
  or r.payload->>'body_sha256' is distinct from a.body_sha256
  or r.payload->>'destination_sha256' is distinct from a.destination_sha256
  or r.payload->>'callback_kind' is distinct from c.callback_kind
  or r.payload->>'result_code' is distinct from c.result_code::text
  or(r.payload->>'tp_status')is distinct from c.tp_status::text or occurred is distinct from c.occurred_at
  or c.callback_id is distinct from((arm.callback_plan->c.segment_index)->>case c.callback_kind when'sent'then'sent_callback_id'else'delivery_callback_id'end)::uuid
  or r.result->'contract_version' is distinct from '1'::jsonb or r.result->>'protocol_family' is distinct from 'receipt_successor'
  or r.result->'route' is distinct from route or r.result->>'callback_id' is distinct from c.callback_id::text
  or r.result->>'attempt_id' is distinct from a.id::text or r.result->>'state' is distinct from e.observed_state
  or r.result->>'recorded_at' is distinct from collect_gateway.utc(c.recorded_at)
  or r.result->'replay' is distinct from 'false'::jsonb
  or r.result->'send_authority' is distinct from 'false'::jsonb
  or r.result->'carrier_proof' is distinct from 'false'::jsonb or r.result->'delivery_proven' is distinct from 'false'::jsonb then
  raise exception 'receipt_successor_execution_binding_invalid'using errcode='55000';end if;
 return jsonb_build_object('request_id',c.request_id,'callback_id',c.callback_id,'attempt_id',a.id,
  'segment_index',c.segment_index,'callback_kind',c.callback_kind,'result_code',c.result_code,'tp_status',c.tp_status,
  'occurred_at',collect_gateway.utc(c.occurred_at),'recorded_at',collect_gateway.utc(c.recorded_at),
  'lineage_before',e.lineage_before,'lineage_after',e.lineage_after,'observed_state',e.observed_state);
 exception when data_exception then raise exception 'receipt_successor_execution_binding_invalid'using errcode='55000';end$$;

create function public.admin_get_receipt_successor_execution_v4(p_approval_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare root uuid;head bigint;t timestamptz;
 j collect_receipt_successors.jobs;a collect_receipt_successors.attempts;arm collect_receipt_successors.arms;
 revoked collect_receipt_successors.attempt_revocations;ack collect_receipt_successors.archive_acknowledgements;
 latest uuid;fact jsonb;events jsonb;value jsonb;state text;begin
 root:=collect_receipt_successors.investigation_root(p_approval_id);t:=clock_timestamp();
 if root is not null then
  select revision into head from collect_receipt_successors.lineage_heads where root_outbox_id=root;
  if head is null then raise exception 'receipt_successor_execution_binding_invalid'using errcode='55000';end if;
  select *into j from collect_receipt_successors.jobs where approval_id=p_approval_id;
  select *into a from collect_receipt_successors.attempts where job_id=j.id;
  select *into arm from collect_receipt_successors.arms where attempt_id=a.id;
  select *into revoked from collect_receipt_successors.attempt_revocations where attempt_id=a.id;
  select *into ack from collect_receipt_successors.archive_acknowledgements where attempt_id=a.id;
  if j.id is not null and(a.id is null or j.root_outbox_id is distinct from root)then raise exception 'receipt_successor_execution_binding_invalid'using errcode='55000';end if;
  select request_id into latest from collect_receipt_successors.observation_events
  where root_outbox_id=root and attempt_id=a.id order by lineage_after desc limit 1;
  if latest is not null then fact:=collect_receipt_successors.investigation_observation(root,a.id,latest);end if;
  select coalesce(jsonb_agg(jsonb_build_object('event_id',e.id,'event_kind',e.event_kind,'request_id',e.request_id,
   'approved_event_id',e.approved_event_id,'approval_request_id',e.approval_request_id,
   'lineage_before',e.lineage_before,'lineage_after',e.lineage_after,'recorded_at',collect_gateway.utc(e.recorded_at))order by e.lineage_after),'[]'::jsonb)
  into events from(select *from collect_receipt_successors.execution_events where attempt_id=a.id order by lineage_after limit 3)e;
  if jsonb_array_length(events)>2 or a.id is not null and(jsonb_array_length(events)<1 or events->0->>'event_kind'<>'grant')
   or arm.attempt_id is not null and(jsonb_array_length(events)<>2 or events->1->>'event_kind'<>'arm')
   or arm.attempt_id is null and jsonb_array_length(events)>1
   or ack.id is not null and(arm.attempt_id is null or ack.route is distinct from collect_receipt_successors.route(j.id)
    or jsonb_array_length(ack.callback_requests)<>2*a.segment_count)then raise exception 'receipt_successor_execution_binding_invalid'using errcode='55000';end if;
  state:=case when j.id is null then'not_materialized'when arm.attempt_id is null then
   case when revoked.attempt_id is not null then'unarmed_revoked'when a.expires_at<=t then'unarmed_expired'else'unarmed_granted'end
   else coalesce(fact->>'observed_state','armed_unknown')end;
  value:=jsonb_build_object('route',collect_receipt_successors.route(j.id),'state',state,
   'attempt',case when a.id is null then null else jsonb_build_object('attempt_id',a.id,'device_id',a.device_id,'run_id',a.run_id,'fence_version',a.fence_version,
    'grant_request_id',a.grant_request_id,'reservation_id',a.reservation_id,'segment_count',a.segment_count,'body_sha256',a.body_sha256,
    'destination_sha256',a.destination_sha256,'issued_at',collect_gateway.utc(a.issued_at),'expires_at',collect_gateway.utc(a.expires_at))end,
   'arm',case when arm.attempt_id is null then null else jsonb_build_object('request_id',arm.request_id,'reservation_sha256',arm.reservation_sha256,'armed_at',collect_gateway.utc(arm.armed_at))end,
   'revocation',case when revoked.attempt_id is null then null else jsonb_build_object('approval_event_id',revoked.approval_event_id,'recorded_at',collect_gateway.utc(revoked.recorded_at))end,
   'execution_events',events,'observation_count',null,
   'latest_projection',case when fact is null then null else jsonb_build_object('request_id',fact->'request_id','lineage_revision',fact->'lineage_after','recorded_at',fact->'recorded_at','state',fact->'observed_state')end,
   'archive',case when ack.id is null then null else jsonb_build_object('archive_ack_id',ack.id,'request_id',ack.request_id,'route',ack.route,
    'callback_requests',ack.callback_requests,'evidence_sha256',ack.evidence_sha256,'recorded_at',collect_gateway.utc(ack.recorded_at),
    'journal_ack',true,'send_authority',false,'carrier_proof',false,'delivery_proven',false)end);
 end if;
 perform collect_receipt_actions.actor(false);
 return jsonb_build_object('contract_version',4,'scope','rw_receipt_successor_execution','approval_id',p_approval_id,'checked_at',collect_gateway.utc(t),
  'sample_valid_until',collect_gateway.utc(t+interval'60 seconds'),'status',case when root is null then'unavailable'else'available'end,
  'primary_receipt_id',root,'cutoff_revision',head,'execution',value,'financial_action',false,'send_action',false,'carrier_proof',false,'delivery_proven',false,'retained_primary',true);end$$;

create function public.admin_list_receipt_successor_observations_v4(p_approval_id uuid,p_cutoff_revision bigint,p_after_revision bigint default null,p_limit integer default 20)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare root uuid;job uuid;attempt uuid;head bigint;t timestamptz;ids uuid[];id uuid;
 items jsonb:='[]'::jsonb;value jsonb;next_revision bigint;begin
 root:=collect_receipt_successors.investigation_root(p_approval_id);t:=clock_timestamp();
 if p_cutoff_revision is null or p_cutoff_revision not between 1 and 1000000000 or p_limit is null or p_limit not between 1 and 50
  or p_after_revision is not null and(p_after_revision not between 1 and p_cutoff_revision)then raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 if root is not null then
  select revision into head from collect_receipt_successors.lineage_heads where root_outbox_id=root;
  if head is null then raise exception 'receipt_successor_execution_binding_invalid'using errcode='55000';end if;
  if p_cutoff_revision>head then raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
  select j.id into job from collect_receipt_successors.jobs j where j.approval_id=p_approval_id and j.root_outbox_id=root;
  select a.id into attempt from collect_receipt_successors.attempts a where a.job_id=job;
  if job is not null and attempt is null then raise exception 'receipt_successor_execution_binding_invalid'using errcode='55000';end if;
  select array_agg(request_id order by lineage_after)into ids from(select request_id,lineage_after from collect_receipt_successors.observation_events
   where root_outbox_id=root and attempt_id=attempt and lineage_after>coalesce(p_after_revision,0)and lineage_after<=p_cutoff_revision
   order by lineage_after limit p_limit+1)bounded;
  foreach id in array coalesce(ids,array[]::uuid[])loop
   value:=collect_receipt_successors.investigation_observation(root,attempt,id);
   if jsonb_array_length(items)<p_limit then items:=items||jsonb_build_array(value);
   else next_revision:=(items->(p_limit-1)->>'lineage_after')::bigint;end if;
  end loop;
 end if;
 perform collect_receipt_actions.actor(false);
 return jsonb_build_object('contract_version',4,'scope','rw_receipt_successor_observations','approval_id',p_approval_id,'primary_receipt_id',root,
  'cutoff_revision',p_cutoff_revision,'after_revision',p_after_revision,'limit',p_limit,'checked_at',collect_gateway.utc(t),
  'sample_valid_until',collect_gateway.utc(t+interval'60 seconds'),'status',case when root is null then'unavailable'else'available'end,
  'items',items,'next_after_revision',next_revision,'financial_action',false,'send_action',false,'carrier_proof',false,'delivery_proven',false);end$$;

revoke all on function collect_receipt_successors.investigation_root(uuid),collect_receipt_successors.investigation_observation(uuid,uuid,uuid)from public,anon,authenticated,service_role;
revoke all on function public.admin_get_receipt_successor_execution_v4(uuid),public.admin_list_receipt_successor_observations_v4(uuid,bigint,bigint,integer)from public,anon,authenticated,service_role;
grant execute on function public.admin_get_receipt_successor_execution_v4(uuid),public.admin_list_receipt_successor_observations_v4(uuid,bigint,bigint,integer)to authenticated;
commit;
