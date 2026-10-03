begin;
-- Local implementation only: default operating policy remains Paused. Device
-- grants are separate from assisted confirmations and are not carrier proof.
create schema collect_gateway_dispatch;
revoke all on schema collect_gateway_dispatch from public,anon,authenticated,service_role;
create table collect_gateway_dispatch.attempts(
 id uuid primary key default gen_random_uuid(),outbox_id uuid not null unique references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 device_id uuid not null references collect_gateway.devices(id)on delete restrict,
 run_id uuid not null references collect_receipt_operations.runs(id)on delete restrict,
 principal_id uuid not null references collect_supervisor.identities(id)on delete restrict,
 fence_version bigint not null check(fence_version between 1 and 1000000000),policy_revision bigint not null,
 grant_request_id uuid not null unique,reservation_id uuid not null unique references collect_receipt_operations.reservations(id)on delete restrict,
 body_sha256 text not null check(body_sha256~'^[0-9a-f]{64}$'),destination_sha256 text not null check(destination_sha256~'^[0-9a-f]{64}$'),
 segment_count integer not null check(segment_count between 1 and 10),health_observation_id uuid not null references collect_gateway.health_observations(id)on delete restrict,
 sim_revision_sha256 text not null check(sim_revision_sha256~'^[0-9a-f]{64}$'),issued_at timestamptz not null,expires_at timestamptz not null,
 state text not null default 'granted'check(state in('granted','send_started','observed_sent','uncertain')),
 updated_at timestamptz not null,check(expires_at>issued_at and expires_at<=issued_at+interval '30 seconds'));
create table collect_gateway_dispatch.arms(
 attempt_id uuid primary key references collect_gateway_dispatch.attempts(id)on delete restrict,
 request_id uuid not null unique,reservation_sha256 text not null check(reservation_sha256~'^[0-9a-f]{64}$'),
 callback_plan jsonb not null check(jsonb_typeof(callback_plan)='array'),
 health_observation_id uuid not null references collect_gateway.health_observations(id)on delete restrict,
 armed_at timestamptz not null,expires_at timestamptz not null,check(expires_at>armed_at and expires_at<=armed_at+interval '30 seconds'));
create table collect_gateway_dispatch.requests(
 request_id uuid primary key,device_id uuid not null references collect_gateway.devices(id)on delete restrict,
 action text not null check(action in('dispatch_grant','arm_dispatch','callback')),
 request_sha256 text not null check(request_sha256~'^[0-9a-f]{64}$'),payload jsonb not null,result jsonb not null,recorded_at timestamptz not null);
create table collect_gateway_dispatch.callbacks(
 request_id uuid primary key references collect_gateway_dispatch.requests(request_id)on delete restrict deferrable initially deferred,
 callback_id uuid not null,attempt_id uuid not null references collect_gateway_dispatch.arms(attempt_id)on delete restrict,
 segment_index integer not null check(segment_index between 0 and 9),callback_kind text not null check(callback_kind in('sent','delivery')),
 result_code integer not null check(result_code between -1 and 200),tp_status integer check(tp_status between 0 and 255),
 occurred_at timestamptz not null,recorded_at timestamptz not null);
create index automatic_callback_fold on collect_gateway_dispatch.callbacks(attempt_id,segment_index,callback_kind);
create function collect_gateway_dispatch.immutable()returns trigger language plpgsql set search_path=''as $$begin
 raise exception 'gateway_dispatch_evidence_immutable'using errcode='55000';end$$;
create function collect_gateway_dispatch.attempt_guard()returns trigger language plpgsql set search_path=''as $$begin
 if tg_op='DELETE'then raise exception 'gateway_dispatch_evidence_immutable'using errcode='55000';end if;
 if(to_jsonb(new)-array['state','updated_at'])is distinct from(to_jsonb(old)-array['state','updated_at'])
  or old.state='uncertain'and new.state<>'uncertain'or old.state='observed_sent'and new.state not in('observed_sent','uncertain')
  or old.state='send_started'and new.state='granted'then raise exception 'gateway_dispatch_evidence_immutable'using errcode='55000';end if;return new;end$$;
do $$declare t text;begin
 foreach t in array array['attempts','arms','requests','callbacks']loop
  execute format('alter table collect_gateway_dispatch.%I enable row level security',t);
  execute format('revoke all on collect_gateway_dispatch.%I from public,anon,authenticated,service_role',t);
  if t<>'attempts'then execute format('create trigger immutable_dispatch_evidence before update or delete on collect_gateway_dispatch.%I for each row execute function collect_gateway_dispatch.immutable()',t);end if;
 end loop;end$$;
create trigger immutable_automatic_attempt before update or delete on collect_gateway_dispatch.attempts for each row execute function collect_gateway_dispatch.attempt_guard();
create function collect_gateway_dispatch.request_lock(p_device uuid,p_request uuid,p_hash text)returns void language plpgsql set search_path=''as $$begin
 perform collect_gateway.require_service(p_device,p_request,p_hash);
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'gateway_dispatch_snapshot_retry'using errcode='40001';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('gateway-dispatch-request:'||p_request::text,0))then raise exception 'gateway_dispatch_request_busy'using errcode='55000';end if;
 -- Cross-version UUID reuse cannot acquire a second authority.
 if exists(select 1 from collect_gateway.requests where request_id=p_request)then raise exception 'gateway_dispatch_request_conflict'using errcode='22023';end if;
end$$;
create function collect_gateway_dispatch.refusal(p_device uuid,p_request uuid,p_code text,p_replay boolean default false)
returns jsonb language sql immutable set search_path=''as $$select jsonb_build_object('ok',false,'code',p_code,'device_id',p_device,'request_id',p_request,'replay',p_replay)$$;
create function collect_gateway_dispatch.replay(p_device uuid,p_request uuid,p_action text,p_hash text,p_payload jsonb)returns jsonb
language plpgsql set search_path=''as $$declare r collect_gateway_dispatch.requests;begin
 select * into r from collect_gateway_dispatch.requests where request_id=p_request;
 if r.request_id is null then return null;end if;
 if r.device_id<>p_device or r.action<>p_action or r.request_sha256<>p_hash or r.payload is distinct from p_payload then raise exception 'gateway_dispatch_request_conflict'using errcode='22023';end if;
 if p_action in('dispatch_grant','arm_dispatch')then return collect_gateway_dispatch.refusal(p_device,p_request,'ORIGINAL_REQUEST_RECORDED',true);end if;
 return r.result||jsonb_build_object('replay',true);end$$;
create function collect_gateway_dispatch.store(p_device uuid,p_request uuid,p_action text,p_hash text,p_payload jsonb,p_result jsonb)returns jsonb
language plpgsql set search_path=''as $$begin
 insert into collect_gateway_dispatch.requests values(p_request,p_device,p_action,p_hash,p_payload,p_result,clock_timestamp());return p_result;end$$;
create function collect_gateway_dispatch.ready_health(p_device uuid)returns collect_gateway.health_observations
language plpgsql set search_path=''as $$declare d collect_gateway.devices;h collect_gateway.health_observations;t timestamptz;begin
 select * into d from collect_gateway.devices where id=p_device for share;t:=clock_timestamp();
 if d.id is null or d.state<>'active'then raise exception 'gateway_device_not_active'using errcode='42501';end if;
 select * into h from collect_gateway.health_observations where device_id=p_device order by ingested_at desc,id desc limit 1;
 if h.id is null or not h.sms_permission or h.network<>'validated'or h.telephony<>'ready'or not h.sim_selected
  or h.sim_revision_sha256 is null or h.local_pause or h.ingested_at>t or h.reported_at>h.ingested_at+interval '30 seconds'
  or least(h.reported_at,h.ingested_at)+interval '120 seconds'<=t then return null;end if;return h;end$$;
create function collect_gateway_dispatch.lock_source(p_outbox uuid)returns void language plpgsql set search_path=''as $$declare o collect_hybrid.sms_notification_outbox;begin
 select * into o from collect_hybrid.sms_notification_outbox where id=p_outbox;
 -- Existing claim/enqueue orders differ. Never wait on their source rows after
 -- the outbox lock; contention aborts before a carrier permit is issued.
 perform 1 from public.feature_flags where key='hybrid_sms_notifications'for share nowait;
 perform 1 from public.payments where id=o.payment_id for share nowait;
 perform 1 from public.collections where id=o.collection_id for share nowait;
 perform 1 from public.parsed_payment_events where id=(select parsed_event_id from public.payments where id=o.payment_id)for share nowait;
 perform 1 from public.raw_payment_sms where id=(select raw_sms_id from public.parsed_payment_events where id=(select parsed_event_id from public.payments where id=o.payment_id))for share nowait;
 perform 1 from public.collection_receivers where collection_id=o.collection_id for share nowait;
 perform 1 from public.profiles where id=(select receiver_user_id from public.payments where id=o.payment_id)for share nowait;
 perform 1 from collect_hybrid.member_records where id=o.member_record_id for share nowait;
 perform 1 from public.collection_members where collection_id=o.collection_id and member_record_id=o.member_record_id for share nowait;
 perform 1 from collect_hybrid.sms_receipt_policies where collection_id=o.collection_id for share nowait;
 perform 1 from collect_hybrid.sms_receipt_member_consents where member_record_id=o.member_record_id for share nowait;
 perform 1 from collect_hybrid.member_momo_identities where member_id=o.member_record_id for share nowait;
 perform collect_hybrid.require_receipt_dispatch_enabled();
 if not collect_hybrid.sms_receipt_job_is_current(o.id)or not collect_receipt_actions.rwanda_source(o)then raise exception 'gateway_dispatch_source_invalid'using errcode='55000';end if;
 exception when lock_not_available then raise exception 'gateway_dispatch_source_busy'using errcode='55000';end$$;
-- Approved rw V2 copy and references contain only this GSM basic subset; refuse
-- other encodings rather than guess carrier-dependent national tables. Native
-- SmsManager must also divide and exactly match count/body before reserving.
create function collect_gateway_dispatch.segment_count(p_body text)returns integer language plpgsql immutable set search_path=''as $$declare n integer;begin
 if p_body is null or p_body!~'^[A-Za-z0-9 .,/:_-]+$'or octet_length(p_body)>1000 then raise exception 'gateway_dispatch_encoding_unsupported'using errcode='55000';end if;
 n:=char_length(p_body);return case when n<=160 then 1 else ceil(n::numeric/153)::integer end;end$$;
create function public.gateway_dispatch_grant_v2(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path=''as $$
declare p collect_receipt_operations.policy;r collect_receipt_operations.runs;o collect_hybrid.sms_notification_outbox;
 h collect_gateway.health_observations;a collect_gateway_dispatch.attempts;prior jsonb;result jsonb;reservation uuid;t timestamptz;expiry timestamptz;n integer;begin
 perform collect_gateway_dispatch.request_lock(p_device_id,p_request_id,p_request_sha256);perform collect_gateway.payload_keys(p_payload,array[]::text[]);
 -- Lock current policy before any run/outbox/device authority, matching quota.
 select * into p from collect_receipt_operations.policy where singleton for update;
 if not exists(select 1 from collect_gateway.devices where id=p_device_id and state='active')then raise exception 'gateway_device_not_active'using errcode='42501';end if;
 prior:=collect_gateway_dispatch.replay(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload);if prior is not null then return prior;end if;
 if p.emergency_stop or p.mode not in('Live-limited','Live')then return collect_gateway_dispatch.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,collect_gateway_dispatch.refusal(p_device_id,p_request_id,'OPERATIONS_PAUSED'));end if;
 select * into r from collect_receipt_operations.runs where device_id=p_device_id and completed_at is null and expires_at>clock_timestamp()
  and policy_revision=p.revision and mode in('Live-limited','Live')order by fence_version desc limit 1;
 if r.id is null then return collect_gateway_dispatch.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,collect_gateway_dispatch.refusal(p_device_id,p_request_id,'NO_CURRENT_RUN'));end if;
 r:=collect_receipt_operations.require_run(r.id,r.fence_version,r.principal_id);
 select * into o from collect_hybrid.sms_notification_outbox j where state='queued'and template_version=2 and collection_id=any(r.collection_ids)
  and fence_version=0 and attempt_count=0 and claim_token is null and claimed_by is null and claim_expires_at is null
  and suppression_reason is null and observed_sent_at is null
  and not exists(select 1 from collect_gateway_dispatch.attempts automatic where automatic.outbox_id=j.id)
  and not exists(select 1 from collect_hybrid.sms_notification_attempts assisted where assisted.outbox_id=j.id)
  and not exists(select 1 from collect_hybrid.sms_notification_claim_requests c where c.outbox_id=j.id)
  and not exists(select 1 from collect_hybrid.sms_notification_confirmations c where c.outbox_id=j.id)
  order by created_at,id limit 1 for update skip locked;
 if o.id is null then return collect_gateway_dispatch.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,collect_gateway_dispatch.refusal(p_device_id,p_request_id,'NO_ELIGIBLE_RECEIPT'));end if;
 perform collect_gateway_dispatch.lock_source(o.id);h:=collect_gateway_dispatch.ready_health(p_device_id);
 if h.id is null then return collect_gateway_dispatch.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,collect_gateway_dispatch.refusal(p_device_id,p_request_id,'DEVICE_NOT_READY'));end if;
 n:=collect_gateway_dispatch.segment_count(o.message_body);reservation:=gen_random_uuid();
 result:=collect_receipt_operations.reserve_dispatch(r.id,r.fence_version,reservation,o.id,p_device_id,n);
 if not(result->>'ok')::boolean then return collect_gateway_dispatch.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,collect_gateway_dispatch.refusal(p_device_id,p_request_id,'QUOTA_EXHAUSTED'));end if;
 t:=clock_timestamp();expiry:=least(r.expires_at,t+interval '30 seconds',least(h.reported_at,h.ingested_at)+interval '120 seconds',(date_trunc('day',t at time zone 'UTC')at time zone 'UTC')+interval '1 day');
 if expiry<=t then raise exception 'gateway_dispatch_expired'using errcode='55000';end if;
 insert into collect_gateway_dispatch.attempts(outbox_id,device_id,run_id,principal_id,fence_version,policy_revision,grant_request_id,reservation_id,body_sha256,destination_sha256,segment_count,health_observation_id,sim_revision_sha256,issued_at,expires_at,updated_at)
 values(o.id,p_device_id,r.id,r.principal_id,r.fence_version,r.policy_revision,p_request_id,reservation,o.body_sha256,o.destination_sha256,n,h.id,h.sim_revision_sha256,t,expiry,t) returning * into a;
 result:=jsonb_build_object('ok',true,'code','DISPATCH_GRANTED','device_id',p_device_id,'request_id',p_request_id,'attempt_id',a.id,'receipt_id',o.id,'run_id',r.id,
  'fence_version',r.fence_version,'policy_revision',r.policy_revision,'issued_at',collect_gateway.utc(t),'expires_at',collect_gateway.utc(expiry),'segment_count',n,
  'body',o.message_body,'destination_e164',o.destination_e164,'body_sha256',o.body_sha256,'destination_sha256',o.destination_sha256,'sim_revision_sha256',h.sim_revision_sha256,'replay',false);
 -- Durable request result is redacted; lost initial response never releases a
 -- reusable body/grant. Request lookup only reconciles recording, not sending.
 perform collect_gateway_dispatch.store(p_device_id,p_request_id,'dispatch_grant',p_request_sha256,p_payload,collect_gateway_dispatch.refusal(p_device_id,p_request_id,'ORIGINAL_REQUEST_RECORDED',true));return result;
end$$;
create function public.gateway_arm_dispatch_v2(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path=''as $$
declare a collect_gateway_dispatch.attempts;r collect_receipt_operations.runs;o collect_hybrid.sms_notification_outbox;h collect_gateway.health_observations;
 prior jsonb;cb jsonb;idx integer;seen uuid[]:='{}';sid uuid;did uuid;t timestamptz;result jsonb;attempt uuid;fence integer;begin
 perform collect_gateway_dispatch.request_lock(p_device_id,p_request_id,p_request_sha256);
 perform collect_gateway.payload_keys(p_payload,array['attempt_id','fence_version','body_sha256','destination_sha256','callbacks','reservation_sha256']);
 attempt:=collect_gateway.payload_uuid(p_payload,'attempt_id');fence:=collect_gateway.payload_int(p_payload,'fence_version',1,1000000000);
 if jsonb_typeof(p_payload->'callbacks')is distinct from 'array'or jsonb_array_length(p_payload->'callbacks')not between 1 and 10 then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
 foreach did in array array[attempt,p_request_id]loop seen:=array_append(seen,did);end loop;
 idx:=0;for cb in select value from jsonb_array_elements(p_payload->'callbacks')loop
  perform collect_gateway.payload_keys(cb,array['segment_index','sent_callback_id','delivery_callback_id']);
  if collect_gateway.payload_int(cb,'segment_index',0,9)<>idx then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
  sid:=collect_gateway.payload_uuid(cb,'sent_callback_id');did:=collect_gateway.payload_uuid(cb,'delivery_callback_id');
  if sid=any(seen)or did=any(seen)or sid=did then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
  seen:=seen||array[sid,did];idx:=idx+1;
 end loop;
 if jsonb_typeof(p_payload->'reservation_sha256')is distinct from 'string'or(p_payload->>'reservation_sha256')!~'^[0-9a-f]{64}$'
  or jsonb_typeof(p_payload->'body_sha256')is distinct from 'string'or jsonb_typeof(p_payload->'destination_sha256')is distinct from 'string'then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
 select * into a from collect_gateway_dispatch.attempts where id=attempt;
 if a.id is null or a.device_id<>p_device_id or a.fence_version<>fence then raise exception 'gateway_dispatch_attempt_unavailable'using errcode='42501';end if;
 r:=collect_receipt_operations.require_run(a.run_id,a.fence_version,a.principal_id);
 select * into o from collect_hybrid.sms_notification_outbox where id=a.outbox_id for update;
 select * into a from collect_gateway_dispatch.attempts where id=attempt for update;
 h:=collect_gateway_dispatch.ready_health(p_device_id);prior:=collect_gateway_dispatch.replay(p_device_id,p_request_id,'arm_dispatch',p_request_sha256,p_payload);
 if prior is not null then return prior;end if;
 if a.state<>'granted'or a.expires_at<=clock_timestamp()or o.state<>'queued'or a.policy_revision<>r.policy_revision
  or a.body_sha256 is distinct from(p_payload->>'body_sha256')or a.destination_sha256 is distinct from(p_payload->>'destination_sha256')
  or idx<>a.segment_count or h.id is null or h.sim_revision_sha256 is distinct from a.sim_revision_sha256
  or exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id=o.id)
  or exists(select 1 from collect_hybrid.sms_notification_claim_requests where outbox_id=o.id)
  or exists(select 1 from collect_hybrid.sms_notification_confirmations where outbox_id=o.id)
  then raise exception 'gateway_dispatch_arm_fenced'using errcode='55000';end if;
 perform collect_gateway_dispatch.lock_source(o.id);t:=clock_timestamp();
 if t>=a.expires_at or t>=r.expires_at then raise exception 'gateway_dispatch_expired'using errcode='55000';end if;
 insert into collect_gateway_dispatch.arms values(a.id,p_request_id,p_payload->>'reservation_sha256',p_payload->'callbacks',h.id,t,a.expires_at);
 update collect_gateway_dispatch.attempts set state='send_started',updated_at=t where id=a.id;
 update collect_hybrid.sms_notification_outbox set state='send_started',fence_version=a.fence_version,attempt_count=1,updated_at=t where id=o.id;
 result:=jsonb_build_object('ok',true,'code','DISPATCH_ARMED','device_id',p_device_id,'request_id',p_request_id,'attempt_id',a.id,'fence_version',a.fence_version,
  'reservation_sha256',p_payload->>'reservation_sha256','armed_at',collect_gateway.utc(t),'expires_at',collect_gateway.utc(a.expires_at),'replay',false,'carrier_proof',false);
 perform collect_gateway_dispatch.store(p_device_id,p_request_id,'arm_dispatch',p_request_sha256,p_payload,collect_gateway_dispatch.refusal(p_device_id,p_request_id,'ORIGINAL_REQUEST_RECORDED',true));return result;
end$$;
create function collect_gateway_dispatch.status(p_attempt uuid)returns jsonb language plpgsql set search_path=''as $$
declare a collect_gateway_dispatch.attempts;arm collect_gateway_dispatch.arms;s integer;d integer;conflict boolean;begin
 select * into a from collect_gateway_dispatch.attempts where id=p_attempt;select * into arm from collect_gateway_dispatch.arms where attempt_id=p_attempt;
 select count(distinct segment_index)filter(where callback_kind='sent'),count(distinct segment_index)filter(where callback_kind='delivery')into s,d
 from collect_gateway_dispatch.callbacks where attempt_id=p_attempt;
 select exists(select 1 from collect_gateway_dispatch.callbacks where attempt_id=p_attempt group by segment_index,callback_kind
  having count(distinct jsonb_build_array(result_code,tp_status))>1)into conflict;
 return jsonb_build_object('attempt_id',a.id,'fence_version',a.fence_version,'state',a.state,'segment_count',a.segment_count,'armed_at',collect_gateway.utc(arm.armed_at),
  'sent_observations',s,'delivery_observations',d,'conflicting_observations',conflict,'terminal_archive_ack',false,'carrier_proof',false);
end$$;
create function public.gateway_callback_v2(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path=''as $$
declare a collect_gateway_dispatch.attempts;arm collect_gateway_dispatch.arms;o collect_hybrid.sms_notification_outbox;
 cb uuid;idx integer;n integer;code integer;tp integer;occurred timestamptz;t timestamptz;prior jsonb;fold jsonb;newstate text;result jsonb;begin
 perform collect_gateway_dispatch.request_lock(p_device_id,p_request_id,p_request_sha256);
 perform collect_gateway.payload_keys(p_payload,array['callback_id','attempt_id','fence_version','segment_index','segment_count','body_sha256','destination_sha256','callback_kind','result_code','tp_status','occurred_at']);
 cb:=collect_gateway.payload_uuid(p_payload,'callback_id');if cb=p_request_id then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
 idx:=collect_gateway.payload_int(p_payload,'segment_index',0,9);n:=collect_gateway.payload_int(p_payload,'segment_count',1,10);
 code:=collect_gateway.payload_int(p_payload,'result_code',-1,200);occurred:=collect_gateway.payload_time(p_payload,'occurred_at');
 if jsonb_typeof(p_payload->'tp_status')is distinct from 'null'then tp:=collect_gateway.payload_int(p_payload,'tp_status',0,255);end if;
 if jsonb_typeof(p_payload->'callback_kind')is distinct from 'string'or coalesce(p_payload->>'callback_kind','')not in('sent','delivery')or jsonb_typeof(p_payload->'body_sha256')is distinct from 'string'
  or jsonb_typeof(p_payload->'destination_sha256')is distinct from 'string'then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
 select * into a from collect_gateway_dispatch.attempts where id=collect_gateway.payload_uuid(p_payload,'attempt_id');
 if a.id is null or a.device_id<>p_device_id then raise exception 'gateway_dispatch_attempt_unavailable'using errcode='42501';end if;
 -- Same receipt lock as arm, without reopening current mode/run authority.
 select * into o from collect_hybrid.sms_notification_outbox where id=a.outbox_id for update;
 select * into a from collect_gateway_dispatch.attempts where id=a.id for update;
 perform 1 from collect_gateway.devices where id=p_device_id for share;
 prior:=collect_gateway_dispatch.replay(p_device_id,p_request_id,'callback',p_request_sha256,p_payload);if prior is not null then return prior;end if;
 select * into arm from collect_gateway_dispatch.arms where attempt_id=a.id;t:=clock_timestamp();
 if arm.attempt_id is null or a.fence_version<>collect_gateway.payload_int(p_payload,'fence_version',1,1000000000)
  or a.body_sha256 is distinct from(p_payload->>'body_sha256')or a.destination_sha256 is distinct from(p_payload->>'destination_sha256')
  or n<>a.segment_count or idx>=n or cb is distinct from((arm.callback_plan->idx)->>case p_payload->>'callback_kind'when 'sent'then 'sent_callback_id'else 'delivery_callback_id'end)::uuid
  or occurred<arm.armed_at-interval '120 seconds'or occurred>t+interval '30 seconds'then raise exception 'gateway_dispatch_callback_binding_invalid'using errcode='22023';end if;
 -- Changed signed observations are retained under a new request UUID and fold
 -- to uncertainty; original callback identities remain fixed by the arm plan.
 insert into collect_gateway_dispatch.callbacks values(p_request_id,cb,a.id,idx,p_payload->>'callback_kind',code,tp,occurred,t);
 fold:=collect_gateway_dispatch.status(a.id);
 newstate:=case when a.state='uncertain'or(fold->>'conflicting_observations')::boolean
   or exists(select 1 from collect_gateway_dispatch.callbacks where attempt_id=a.id and callback_kind='sent'and result_code<>-1)then 'uncertain'
  when(fold->>'sent_observations')::integer=a.segment_count then 'observed_sent'else 'send_started'end;
 update collect_gateway_dispatch.attempts set state=newstate,updated_at=t where id=a.id;
 update collect_hybrid.sms_notification_outbox set state=newstate,observed_sent_at=case when newstate='observed_sent'then coalesce(observed_sent_at,t)else observed_sent_at end,updated_at=t where id=o.id;
 result:=jsonb_build_object('callback_id',cb,'recorded_at',collect_gateway.utc(t),'replay',false,'carrier_proof',false,'state',newstate,
  'sent_observations',fold->'sent_observations','delivery_observations',fold->'delivery_observations','conflicting_observations',fold->'conflicting_observations');
 perform collect_gateway_dispatch.store(p_device_id,p_request_id,'callback',p_request_sha256,p_payload,result);return result;
end$$;

create function public.gateway_reconcile_v2(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path=''as $$declare target uuid;r collect_gateway_dispatch.requests;begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'gateway_dispatch_snapshot_retry'using errcode='40001';end if;
 perform collect_gateway.payload_keys(p_payload,array['target_request_id']);target:=collect_gateway.payload_uuid(p_payload,'target_request_id');
 if not exists(select 1 from collect_gateway.devices where id=p_device_id)then raise exception 'gateway_device_not_found'using errcode='22023';end if;
 select * into r from collect_gateway_dispatch.requests where request_id=target and device_id=p_device_id;
 return jsonb_build_object('target_request_id',target,'outcome',case when r.request_id is null then 'unknown'else 'recorded'end,'recorded_action',r.action,'recorded_result',r.result);
end$$;
create function public.gateway_attempt_status_v2(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path=''as $$declare a collect_gateway_dispatch.attempts;begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'gateway_dispatch_snapshot_retry'using errcode='40001';end if;
 perform collect_gateway.payload_keys(p_payload,array['attempt_id','fence_version']);
 select * into a from collect_gateway_dispatch.attempts where id=collect_gateway.payload_uuid(p_payload,'attempt_id')and device_id=p_device_id;
 if a.id is null or a.fence_version<>collect_gateway.payload_int(p_payload,'fence_version',1,1000000000)then raise exception 'gateway_dispatch_attempt_unavailable'using errcode='42501';end if;
 -- Serialize against arm/callback; revoked devices may read their prior facts.
 perform 1 from collect_hybrid.sms_notification_outbox where id=a.outbox_id for share;
 return collect_gateway_dispatch.status(a.id);
end$$;
create function collect_gateway_dispatch.cross_version_request()returns trigger language plpgsql set search_path=''as $$begin
 if not pg_try_advisory_xact_lock(hashtextextended('gateway-dispatch-request:'||new.request_id::text,0))then raise exception 'gateway_dispatch_request_busy'using errcode='55000';end if;
 if(tg_table_schema='collect_gateway'and exists(select 1 from collect_gateway_dispatch.requests where request_id=new.request_id))
  or(tg_table_schema='collect_gateway_dispatch'and exists(select 1 from collect_gateway.requests where request_id=new.request_id))then
  raise exception 'gateway_dispatch_request_conflict'using errcode='22023';end if;return new;end$$;
create trigger gateway_uuid_namespace before insert on collect_gateway.requests for each row execute function collect_gateway_dispatch.cross_version_request();
create trigger gateway_uuid_namespace before insert on collect_gateway_dispatch.requests for each row execute function collect_gateway_dispatch.cross_version_request();
create function collect_gateway_dispatch.outbox_guard()returns trigger language plpgsql security definer set search_path=''as $$declare a collect_gateway_dispatch.attempts;begin
 if tg_table_name='sms_notification_attempts'then
  if exists(select 1 from collect_gateway_dispatch.attempts where outbox_id=new.outbox_id)then raise exception 'gateway_automatic_attempt_reserved'using errcode='55000';end if;return new;end if;
 select * into a from collect_gateway_dispatch.attempts where outbox_id=old.id;
 if a.id is not null then
  if new.id is distinct from old.id then raise exception 'gateway_dispatch_source_identity_immutable'using errcode='55000';end if;
  if a.state='granted'and new.state not in('queued','suppressed')then
   raise exception 'gateway_dispatch_arm_required'using errcode='55000';end if;
  if a.state<>'granted'and(new.state<>a.state or new.fence_version<>a.fence_version or new.attempt_count<>1)then
   raise exception 'gateway_dispatch_state_proof_invalid'using errcode='55000';end if;
 end if;return new;end$$;
create trigger automatic_receipt_transition_guard before update on collect_hybrid.sms_notification_outbox for each row execute function collect_gateway_dispatch.outbox_guard();
create trigger automatic_receipt_assisted_exclusion before insert on collect_hybrid.sms_notification_attempts for each row execute function collect_gateway_dispatch.outbox_guard();
create function collect_gateway_dispatch.verify_attempt()returns trigger language plpgsql security definer set search_path=''as $$
declare a collect_gateway_dispatch.attempts;arm collect_gateway_dispatch.arms;o collect_hybrid.sms_notification_outbox;r collect_receipt_operations.reservations;fold jsonb;begin
 if tg_table_name='attempts'then select * into a from collect_gateway_dispatch.attempts where id=new.id;else select * into a from collect_gateway_dispatch.attempts where id=new.attempt_id;end if;
 select * into o from collect_hybrid.sms_notification_outbox where id=a.outbox_id;
 select * into arm from collect_gateway_dispatch.arms where attempt_id=a.id;
 select * into r from collect_receipt_operations.reservations where id=a.reservation_id;
 if a.id is null or a.body_sha256 is distinct from o.body_sha256 or a.destination_sha256 is distinct from o.destination_sha256
  or r.run_id is distinct from a.run_id or r.device_id is distinct from a.device_id or r.fence_version is distinct from a.fence_version
  or r.collection_id is distinct from o.collection_id or r.actions is distinct from 1 or r.sms_segments is distinct from a.segment_count
  or exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id=a.outbox_id)
  or(a.state='granted'and(arm.attempt_id is not null or o.state not in('queued','suppressed')))
  or(a.state<>'granted'and(arm.attempt_id is null or o.state is distinct from a.state or o.fence_version<>a.fence_version or o.attempt_count<>1))then
  raise exception 'gateway_dispatch_state_proof_invalid'using errcode='55000';end if;
 if arm.attempt_id is not null then
  if jsonb_array_length(arm.callback_plan)<>a.segment_count or arm.expires_at is distinct from a.expires_at
   or arm.armed_at<a.issued_at then raise exception 'gateway_dispatch_arm_proof_invalid'using errcode='55000';end if;
  fold:=collect_gateway_dispatch.status(a.id);
  if a.state='observed_sent'and((fold->>'sent_observations')::integer<>a.segment_count or(fold->>'conflicting_observations')::boolean
   or exists(select 1 from collect_gateway_dispatch.callbacks where attempt_id=a.id and callback_kind='sent'and result_code<>-1))then
   raise exception 'gateway_dispatch_outcome_proof_invalid'using errcode='55000';end if;
 end if;return null;end$$;
create constraint trigger automatic_attempt_proof after insert or update on collect_gateway_dispatch.attempts deferrable initially deferred for each row execute function collect_gateway_dispatch.verify_attempt();
create constraint trigger automatic_arm_proof after insert on collect_gateway_dispatch.arms deferrable initially deferred for each row execute function collect_gateway_dispatch.verify_attempt();
-- Protect cancellation and assisted authority without rewriting their evidence.
create or replace function collect_receipt_actions.ineligible_reason(p_job collect_hybrid.sms_notification_outbox)
returns text language sql stable security definer set search_path=''as $$
 select case
  when exists(select 1 from collect_receipt_actions.cancellations where outbox_id=p_job.id)then 'already_cancelled'
  when exists(select 1 from collect_gateway_dispatch.attempts where outbox_id=p_job.id)then 'prior_transport_evidence'
  when p_job.state is distinct from 'queued'then 'state_not_queued'
  when p_job.fence_version is distinct from 0 or p_job.attempt_count is distinct from 0
   or p_job.claim_token is not null or p_job.claimed_by is not null or p_job.claim_expires_at is not null
   or p_job.observed_sent_at is not null or p_job.suppression_reason is not null
   or exists(select 1 from collect_hybrid.sms_notification_claim_requests where outbox_id=p_job.id)
   or exists(select 1 from collect_hybrid.sms_notification_confirmations where outbox_id=p_job.id)
   or exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id=p_job.id)
   or exists(select 1 from collect_gateway.dispatch_arms g join collect_hybrid.sms_notification_attempts a
    on a.id=g.attempt_id where a.outbox_id=p_job.id)then 'prior_transport_evidence'
  when not exists(select 1 from public.payments p
   join collect_hybrid.momo_balance_snapshots s on s.id=p_job.snapshot_id
   join collect_hybrid.momo_journal_entries j on j.id=s.journal_entry_id
   where p.id=p_job.payment_id and p.status='posted'and p.currency='RWF'
    and collect_receipt_actions.rwanda_source(p_job)
    and p.collection_id=p_job.collection_id and p.member_record_id=p_job.member_record_id
    and p.amount_rwf=p_job.amount_rwf
    and p_job.reference=coalesce(nullif(btrim(p.transaction_id),''),p.id::text)
    and s.payment_id=p.id and s.collection_id=p_job.collection_id and s.member_record_id=p_job.member_record_id
    and s.event_type='receipt'and s.delta_rwf=p_job.amount_rwf
    and s.member_balance_after_rwf=p_job.member_balance_rwf and s.group_balance_after_rwf=p_job.group_balance_rwf
    and j.payment_id=p.id and j.collection_id=p_job.collection_id and j.member_record_id=p_job.member_record_id
    and j.entry_type='receipt'and j.amount_rwf=p_job.amount_rwf
    and not exists(select 1 from collect_hybrid.momo_journal_entries r where r.payment_id=p.id and r.entry_type='reversal')
    and(select count(*)=2 and count(*)filter(where l.account_code='momo_receiving_asset:RWF'and l.direction='debit')=1
     and count(*)filter(where l.account_code='member_savings_liability:RWF'and l.direction='credit')=1
     and min(l.amount_rwf)=p_job.amount_rwf and max(l.amount_rwf)=p_job.amount_rwf
     from collect_hybrid.momo_journal_lines l where l.journal_entry_id=j.id)
    and p_job.destination_sha256=encode(extensions.digest(p_job.destination_e164,'sha256'),'hex')
    and p_job.message_body=case when btrim(p_job.reference)~'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'then
      collect_receipt_policy.body_for_job(p_job)else null end
    and p_job.body_sha256=encode(extensions.digest(p_job.message_body,'sha256'),'hex'))then 'source_evidence_invalid'
  else 'eligible'end
$$;

-- Automatic history is deliberately separate from human confirmations.
create function public.admin_get_gateway_receipt_attempt_v2(p_receipt_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare sid uuid;a collect_gateway_dispatch.attempts;o collect_hybrid.sms_notification_outbox;t timestamptz;data jsonb;begin
 sid:=collect_gateway.owner_actor();
 if p_receipt_id is null then raise exception 'gateway_receipt_id_invalid'using errcode='22023';end if;
 select * into o from collect_hybrid.sms_notification_outbox where id=p_receipt_id for share;
 if o.id is null or not collect_receipt_actions.rwanda_source(o)then raise exception 'gateway_receipt_unavailable'using errcode='42501';end if;
 select * into a from collect_gateway_dispatch.attempts where outbox_id=o.id;t:=clock_timestamp();
 if a.id is not null then data:=collect_gateway_dispatch.status(a.id)||jsonb_build_object('device_id',a.device_id,'run_id',a.run_id,'policy_revision',a.policy_revision,'issued_at',collect_gateway.utc(a.issued_at),'expires_at',collect_gateway.utc(a.expires_at));end if;
 return jsonb_build_object('contract_version',2,'receipt_id',p_receipt_id,'checked_at',collect_gateway.utc(t),'sample_valid_until',collect_gateway.utc(t+interval '60 seconds'),'automatic_attempt',data);
end$$;
revoke all on all functions in schema collect_gateway_dispatch from public,anon,authenticated,service_role;
revoke all on function public.gateway_dispatch_grant_v2(uuid,uuid,text,jsonb),public.gateway_arm_dispatch_v2(uuid,uuid,text,jsonb),public.gateway_callback_v2(uuid,uuid,text,jsonb),public.gateway_reconcile_v2(uuid,uuid,text,jsonb),public.gateway_attempt_status_v2(uuid,uuid,text,jsonb)from public,anon,authenticated;
grant execute on function public.gateway_dispatch_grant_v2(uuid,uuid,text,jsonb),public.gateway_arm_dispatch_v2(uuid,uuid,text,jsonb),public.gateway_callback_v2(uuid,uuid,text,jsonb),public.gateway_reconcile_v2(uuid,uuid,text,jsonb),public.gateway_attempt_status_v2(uuid,uuid,text,jsonb)to service_role;
revoke all on function public.admin_get_gateway_receipt_attempt_v2(uuid)from public,anon,service_role;
grant execute on function public.admin_get_gateway_receipt_attempt_v2(uuid)to authenticated;
commit;
