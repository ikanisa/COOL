begin;
-- Dedicated business-event operations. Existing v1 Shadow observation and
-- immutable financial/content evidence retain their separate authority.
create schema collect_receipt_operations;
revoke all on schema collect_receipt_operations from public,anon,authenticated,service_role;
alter table collect_supervisor.identities drop constraint identities_scope_check;
alter table collect_supervisor.identities add constraint identities_scope_check
 check(scope in('rw_receipt_shadow','rw_receipt_operations'));
create or replace function collect_supervisor.require_service_identity(p_principal uuid,p_key text,p_request uuid,
 p_request_sha text,p_issued timestamptz,p_action text)returns collect_supervisor.identities
language plpgsql set search_path=''as $$
declare item collect_supervisor.identities;t timestamptz;begin
 if auth.role()is distinct from 'service_role'then raise exception 'supervisor_service_required'using errcode='42501';end if;
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'supervisor_snapshot_retry'using errcode='40001';end if;
 if p_principal is null or p_request is null or p_key is null or p_key!~'^[0-9a-f]{64}$'
  or p_request_sha is null or p_request_sha!~'^[0-9a-f]{64}$'or p_issued is null or not isfinite(p_issued)
  or p_action is null or p_action not in('prove_key','shadow_health','reconcile')then raise exception 'supervisor_request_invalid'using errcode='22023';end if;
 select * into item from collect_supervisor.identities where id=p_principal for share;t:=clock_timestamp();
 if item.id is null or item.scope<>'rw_receipt_shadow'or item.state='revoked'or item.key_sha256<>p_key or item.expires_at<=t
  or(p_action<>'prove_key'and item.state<>'active')then raise exception 'supervisor_credential_unavailable'using errcode='42501';end if;
 if p_issued<t-interval '30 seconds'or p_issued>t+interval '10 seconds'then raise exception 'supervisor_request_expired'using errcode='42501';end if;return item;end$$;
create table collect_receipt_operations.policy(
 singleton boolean primary key default true check(singleton),
 revision bigint not null default 1 check(revision between 1 and 1000000000),
 mode text not null default 'Paused' check(mode in('Shadow','Dry-run','Live-limited','Live','Paused')),
 emergency_stop boolean not null default true,
 principal_ids uuid[] not null default '{}',collection_ids uuid[] not null default '{}',device_ids uuid[] not null default '{}',
 caps jsonb not null default '{"run_actions":0,"group_actions":0,"device_actions":0,"global_actions":0,"run_sms_segments":0,"group_sms_segments":0,"device_sms_segments":0,"global_sms_segments":0}',
 catchup_enabled boolean not null default false,
 catchup_hours integer not null default 24 check(catchup_hours between 1 and 168),
 updated_at timestamptz not null default clock_timestamp(),updated_by uuid,
 check(mode<>'Paused'or emergency_stop),check(jsonb_typeof(caps)='object'));
insert into collect_receipt_operations.policy(singleton)values(true);
create table collect_receipt_operations.owner_requests(
 request_id uuid primary key,actor_id uuid not null,session_id uuid not null,
 action text not null,input jsonb not null,result jsonb not null,recorded_at timestamptz not null);
create table collect_receipt_operations.fence(singleton boolean primary key check(singleton),value bigint not null check(value between 0 and 1000000000));
insert into collect_receipt_operations.fence values(true,0);
create table collect_receipt_operations.runs(
 id uuid primary key default gen_random_uuid(),request_id uuid not null unique,
 principal_id uuid not null references collect_supervisor.identities(id)on delete restrict,
 fence_version bigint not null unique check(fence_version between 1 and 1000000000),
 policy_revision bigint not null,mode text not null check(mode in('Shadow','Dry-run','Live-limited','Live')),
 collection_ids uuid[] not null,device_id uuid references collect_gateway.devices(id)on delete restrict,
 started_at timestamptz not null,expires_at timestamptz not null,
 scan_performed boolean not null default false,
 completed_at timestamptz,
 check(expires_at>started_at and expires_at<=started_at+interval '120 seconds'));
create table collect_receipt_operations.requests(
 request_id uuid primary key,principal_id uuid not null references collect_supervisor.identities(id)on delete restrict,
 action text not null check(action in('prove_key','begin_run','list_events','ensure_receipt','reconcile_backlog','complete_run')),
 request_sha256 text not null check(request_sha256~'^[0-9a-f]{64}$'),
 input jsonb not null,issued_at timestamptz not null,recorded_at timestamptz not null,result jsonb not null);
create index operations_identity_proofs on collect_receipt_operations.requests(principal_id,recorded_at desc)where action='prove_key';
create table collect_receipt_operations.handled_events(
 event_id uuid primary key references collect_hybrid.receipt_business_events(id)on delete restrict,
 run_id uuid not null references collect_receipt_operations.runs(id)on delete restrict,
 principal_id uuid not null references collect_supervisor.identities(id)on delete restrict,
 source_version bigint not null,code text not null check(code in('RECEIPT_ENQUEUED','RECEIPT_EXISTS','PAYMENT_REVERSED')),
 receipt_id uuid references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 handled_at timestamptz not null,check((code='PAYMENT_REVERSED')or receipt_id is not null));
create table collect_receipt_operations.run_events(
 run_id uuid not null references collect_receipt_operations.runs(id)on delete restrict,
 event_id uuid not null references collect_hybrid.receipt_business_events(id)on delete restrict,
 source_version bigint not null,code text not null,business_handled boolean not null,
 receipt_id uuid references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 recorded_at timestamptz not null,primary key(run_id,event_id));
create table collect_receipt_operations.run_batch_events(
 run_id uuid not null references collect_receipt_operations.runs(id)on delete restrict,
 event_id uuid not null references collect_hybrid.receipt_business_events(id)on delete restrict,
 assigned_at timestamptz not null,primary key(run_id,event_id));
create table collect_receipt_operations.event_deferrals(
 event_id uuid primary key references collect_hybrid.receipt_business_events(id)on delete restrict,
 next_check_at timestamptz not null,code text not null);
create table collect_receipt_operations.reservations(
 id uuid primary key,run_id uuid not null references collect_receipt_operations.runs(id)on delete restrict,
 fence_version bigint not null,collection_id uuid not null references public.collections(id)on delete restrict,
 device_id uuid references collect_gateway.devices(id)on delete restrict,
 actions integer not null check(actions between 0 and 1),sms_segments integer not null check(sms_segments between 0 and 10),
 recorded_at timestamptz not null,check(actions>0 or sms_segments>0));
create index operations_daily_quota on collect_receipt_operations.reservations(recorded_at,collection_id,device_id);
create table collect_receipt_operations.backlog_results(
 run_id uuid not null references collect_receipt_operations.runs(id)on delete restrict,
 snapshot_id uuid not null references collect_hybrid.momo_balance_snapshots(id)on delete restrict,
 code text not null,business_handled boolean not null,receipt_id uuid references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 recorded_at timestamptz not null,primary key(run_id,snapshot_id));
do $$declare t text;begin
 foreach t in array array['policy','owner_requests','fence','runs','requests','handled_events','run_events','run_batch_events','event_deferrals','reservations','backlog_results']loop
  execute format('alter table collect_receipt_operations.%I enable row level security',t);
  execute format('revoke all on collect_receipt_operations.%I from public,anon,authenticated,service_role',t);
 end loop;
 foreach t in array array['owner_requests','requests','handled_events','run_events','run_batch_events','reservations','backlog_results']loop
  execute format('create trigger operations_evidence_immutable before update or delete on collect_receipt_operations.%I for each row execute function collect_supervisor.immutable_evidence()',t);
 end loop;
end$$;

create function collect_receipt_operations.base(p_principal uuid,p_request uuid,p_action text,p_at timestamptz)
returns jsonb language sql immutable set search_path=''as $$
 select jsonb_build_object('contract_version',2,'principal_id',p_principal,'request_id',p_request,'action',p_action,'observed_at',collect_gateway.utc(p_at))
$$;
create function collect_receipt_operations.owner_replay(p_request uuid,p_action text,p_input jsonb)
returns jsonb language plpgsql set search_path=''as $$declare r collect_receipt_operations.owner_requests;begin
 select * into r from collect_receipt_operations.owner_requests where request_id=p_request;
 if r.request_id is null then return null;end if;
 if r.actor_id<>auth.uid()or r.action<>p_action or r.input is distinct from p_input then
  raise exception 'operations_owner_request_conflict'using errcode='22023';end if;return r.result;end$$;
create function public.admin_enroll_receipt_operations_identity_v2(p_request_id uuid,p_public_key_spki_base64 text,
 p_key_sha256 text,p_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;prior jsonb;input jsonb;result jsonb;principal uuid;t timestamptz;begin
 sid:=collect_supervisor.owner_actor();
 if p_request_id is null or p_expires_at is null or not isfinite(p_expires_at)then raise exception 'operations_enrollment_invalid'using errcode='22023';end if;
 perform collect_supervisor.validate_key(p_public_key_spki_base64,p_key_sha256);
 input:=jsonb_build_array(p_public_key_spki_base64,p_key_sha256,p_expires_at);
 perform pg_advisory_xact_lock(hashtextextended('collect-operations-owner:'||p_request_id::text,0));
 prior:=collect_receipt_operations.owner_replay(p_request_id,'enroll',input);if prior is not null then return prior;end if;
 t:=clock_timestamp();if p_expires_at<t+interval '10 minutes'or p_expires_at>t+interval '30 days'then raise exception 'operations_enrollment_invalid'using errcode='22023';end if;
 insert into collect_supervisor.identities(enrollment_request_id,owner_actor_id,owner_session_id,public_key_spki_base64,key_sha256,scope,created_at,expires_at)
 values(p_request_id,auth.uid(),sid,p_public_key_spki_base64,p_key_sha256,'rw_receipt_operations',t,p_expires_at)returning id into principal;
 result:=jsonb_build_object('contract_version',2,'principal_id',principal,'request_id',p_request_id,'state_at_action','pending','scope','rw_receipt_operations','key_sha256',p_key_sha256,'expires_at',collect_gateway.utc(p_expires_at),'recorded_at',collect_gateway.utc(t));
 insert into collect_receipt_operations.owner_requests values(p_request_id,auth.uid(),sid,'enroll',input,result,t);
 perform public.create_audit_log('supervisor.operations.enroll','receipt_supervisor',principal,jsonb_build_object('request_id',p_request_id,'scope','rw_receipt_operations'),auth.uid());
 return result;end$$;
create function public.admin_activate_receipt_operations_identity_v2(p_principal_id uuid,p_request_id uuid,p_expected_key_sha256 text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;prior jsonb;input jsonb;r collect_supervisor.identities;result jsonb;t timestamptz;begin
 sid:=collect_supervisor.owner_actor();
 if p_principal_id is null or p_request_id is null or p_expected_key_sha256 is null or p_expected_key_sha256!~'^[0-9a-f]{64}$'then raise exception 'operations_identity_input_invalid'using errcode='22023';end if;
 input:=jsonb_build_array(p_principal_id,p_expected_key_sha256);perform pg_advisory_xact_lock(hashtextextended('collect-operations-owner:'||p_request_id::text,0));
 prior:=collect_receipt_operations.owner_replay(p_request_id,'activate',input);if prior is not null then return prior;end if;
 select * into r from collect_supervisor.identities where id=p_principal_id for update;t:=clock_timestamp();
 if r.id is null or r.scope<>'rw_receipt_operations'or r.key_sha256<>p_expected_key_sha256 or r.state<>'pending'or r.expires_at<=t then raise exception 'operations_identity_unavailable'using errcode='42501';end if;
 if not exists(select 1 from collect_receipt_operations.requests where principal_id=r.id and action='prove_key'and recorded_at>=t-interval '120 seconds')then raise exception 'operations_key_possession_required'using errcode='55000';end if;
 update collect_supervisor.identities set state='active',activated_at=t where id=r.id;
 result:=jsonb_build_object('contract_version',2,'principal_id',r.id,'request_id',p_request_id,'state_at_action','active','scope','rw_receipt_operations','recorded_at',collect_gateway.utc(t));
 insert into collect_receipt_operations.owner_requests values(p_request_id,auth.uid(),sid,'activate',input,result,t);
 perform public.create_audit_log('supervisor.operations.activate','receipt_supervisor',r.id,jsonb_build_object('request_id',p_request_id),auth.uid());return result;end$$;

create function collect_receipt_operations.caps_valid(p_caps jsonb)returns boolean language plpgsql immutable set search_path=''as $$
declare k text;begin
 if p_caps is null or jsonb_typeof(p_caps)<>'object'or(select count(*)from jsonb_object_keys(p_caps))<>8 then return false;end if;
 foreach k in array array['run_actions','group_actions','device_actions','global_actions','run_sms_segments','group_sms_segments','device_sms_segments','global_sms_segments']loop
  if not p_caps?k or jsonb_typeof(p_caps->k)<>'number'or p_caps->>k!~'^[0-9]+$'or(p_caps->>k)::numeric not between 1 and 1000000 then return false;end if;
 end loop;return true;end$$;
create function public.admin_configure_receipt_operations_v2(p_request_id uuid,p_expected_revision bigint,p_mode text,
 p_emergency_stop boolean,p_principal_ids uuid[],p_collection_ids uuid[],p_device_ids uuid[],p_caps jsonb,
 p_catchup_enabled boolean,p_catchup_hours integer,p_reason text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;r collect_receipt_operations.policy;input jsonb;prior jsonb;result jsonb;t timestamptz;begin
 sid:=collect_supervisor.owner_actor();
 if p_request_id is null or p_expected_revision is null or p_mode is null or p_mode not in('Shadow','Dry-run','Live-limited','Live','Paused')
  or p_emergency_stop is null or(p_mode='Paused'and not p_emergency_stop)or p_principal_ids is null or p_collection_ids is null or p_device_ids is null
  or cardinality(p_principal_ids)not between 1 and 10 or cardinality(p_collection_ids)not between 1 and 100 or cardinality(p_device_ids)>10
  or array_position(p_principal_ids,null)is not null or array_position(p_collection_ids,null)is not null or array_position(p_device_ids,null)is not null
  or cardinality(p_principal_ids)<>(select count(distinct x)from unnest(p_principal_ids)x)
  or cardinality(p_collection_ids)<>(select count(distinct x)from unnest(p_collection_ids)x)
  or cardinality(p_device_ids)<>(select count(distinct x)from unnest(p_device_ids)x)
  or not collect_receipt_operations.caps_valid(p_caps)or p_catchup_enabled is null or p_catchup_hours is null or p_catchup_hours not between 1 and 168
  or p_reason is null or char_length(btrim(p_reason))not between 8 and 500 then raise exception 'operations_policy_input_invalid'using errcode='22023';end if;
 if p_mode='Live-limited'and((p_caps->>'run_actions')::integer>10 or(p_caps->>'run_sms_segments')::integer>20)then raise exception 'operations_pilot_caps_exceeded'using errcode='22023';end if;
 input:=jsonb_build_array(p_expected_revision,p_mode,p_emergency_stop,p_principal_ids,p_collection_ids,p_device_ids,p_caps,p_catchup_enabled,p_catchup_hours,btrim(p_reason));
 perform pg_advisory_xact_lock(hashtextextended('collect-operations-owner:'||p_request_id::text,0));
 prior:=collect_receipt_operations.owner_replay(p_request_id,'configure',input);if prior is not null then return prior;end if;
 select * into r from collect_receipt_operations.policy where singleton for update;perform collect_supervisor.owner_actor();
 if r.revision<>p_expected_revision or r.revision=1000000000 then raise exception 'operations_policy_source_changed'using errcode='55000';end if;
 if exists(select 1 from unnest(p_principal_ids)x left join collect_supervisor.identities i on i.id=x where i.id is null or i.scope<>'rw_receipt_operations'or i.state<>'active'or i.expires_at<=clock_timestamp())
  or exists(select 1 from unnest(p_collection_ids)x left join public.collections c on c.id=x where c.id is null or c.collection_type<>'ikimina'or c.archived_at is not null)
  or exists(select 1 from unnest(p_device_ids)x left join collect_gateway.devices d on d.id=x where d.id is null or d.state<>'active')
  or(p_mode in('Live','Live-limited')and cardinality(p_device_ids)=0)then raise exception 'operations_scope_unavailable'using errcode='42501';end if;
 t:=clock_timestamp();update collect_receipt_operations.policy set revision=r.revision+1,mode=p_mode,emergency_stop=p_emergency_stop,
 principal_ids=p_principal_ids,collection_ids=p_collection_ids,device_ids=p_device_ids,caps=p_caps,catchup_enabled=p_catchup_enabled,catchup_hours=p_catchup_hours,updated_at=t,updated_by=auth.uid()where singleton;
 result:=jsonb_build_object('contract_version',2,'request_id',p_request_id,'revision',r.revision+1,'mode',p_mode,'emergency_stop',p_emergency_stop,'recorded_at',collect_gateway.utc(t));
 insert into collect_receipt_operations.owner_requests values(p_request_id,auth.uid(),sid,'configure',input,result,t);
 perform public.create_audit_log('supervisor.operations.configure','receipt_operations_policy',null,
  jsonb_build_object('request_id',p_request_id,'revision',r.revision+1,'mode',p_mode,'emergency_stop',p_emergency_stop,'collection_ids',p_collection_ids,'device_ids',p_device_ids,'caps',p_caps,'catchup_enabled',p_catchup_enabled,'catchup_hours',p_catchup_hours,'reason',btrim(p_reason)),auth.uid());return result;end$$;
create function public.admin_get_receipt_operations_policy_v2()returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare p collect_receipt_operations.policy;begin
 perform collect_supervisor.owner_actor();select * into p from collect_receipt_operations.policy where singleton;
 return jsonb_build_object('contract_version',2,'revision',p.revision,'mode',p.mode,'emergency_stop',p.emergency_stop,
 'principal_ids',p.principal_ids,'collection_ids',p.collection_ids,'device_ids',p.device_ids,'caps',p.caps,
 'catchup_enabled',p.catchup_enabled,'catchup_hours',p.catchup_hours,'updated_at',collect_gateway.utc(p.updated_at),'checked_at',collect_gateway.utc(clock_timestamp()));end$$;

create function collect_receipt_operations.require_identity(p_principal uuid,p_key text,p_request uuid,p_sha text,p_issued timestamptz,p_action text)
returns collect_supervisor.identities language plpgsql set search_path=''as $$declare i collect_supervisor.identities;t timestamptz;begin
 if auth.role()is distinct from 'service_role'then raise exception 'operations_service_required'using errcode='42501';end if;
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'operations_snapshot_retry'using errcode='40001';end if;
 if p_principal is null or p_request is null or p_key is null or p_key!~'^[0-9a-f]{64}$'or p_sha is null or p_sha!~'^[0-9a-f]{64}$'or p_issued is null or not isfinite(p_issued)
  or p_action is null or p_action not in('prove_key','begin_run','list_events','ensure_receipt','reconcile_backlog','complete_run','reconcile_request')then raise exception 'operations_request_invalid'using errcode='22023';end if;
 select * into i from collect_supervisor.identities where id=p_principal for share;t:=clock_timestamp();
 if i.id is null or i.scope<>'rw_receipt_operations'or i.state='revoked'or i.key_sha256<>p_key or i.expires_at<=t or(p_action<>'prove_key'and i.state<>'active')
  or p_issued<t-interval '30 seconds'or p_issued>t+interval '10 seconds'then raise exception 'operations_identity_unavailable'using errcode='42501';end if;return i;end$$;
create function collect_receipt_operations.require_run(p_run uuid,p_fence bigint,p_principal uuid)
returns collect_receipt_operations.runs language plpgsql set search_path=''as $$declare r collect_receipt_operations.runs;p collect_receipt_operations.policy;i collect_supervisor.identities;begin
 -- One global lock order also serializes daily quota reservations and stop.
 select * into p from collect_receipt_operations.policy where singleton for update;
 select * into r from collect_receipt_operations.runs where id=p_run for update;
 if r.id is null or r.principal_id is distinct from p_principal or r.fence_version is distinct from p_fence
  or r.completed_at is not null or r.expires_at<=clock_timestamp()or r.policy_revision<>p.revision
  or p.emergency_stop or p.mode='Paused'or not p_principal=any(p.principal_ids)then raise exception 'operations_run_fenced'using errcode='55000';end if;
 select * into i from collect_supervisor.identities where id=p_principal for share;
 if i.state<>'active'or i.scope<>'rw_receipt_operations'or i.expires_at<=clock_timestamp()then raise exception 'operations_identity_unavailable'using errcode='42501';end if;
 return r;end$$;
create function collect_receipt_operations.reserve_budget(p_run uuid,p_fence bigint,p_reservation uuid,p_collection uuid,p_device uuid,p_actions integer,p_sms_segments integer)
returns boolean language plpgsql set search_path=''as $$
declare r collect_receipt_operations.runs;p collect_receipt_operations.policy;prior collect_receipt_operations.reservations;t timestamptz;start_day timestamptz;k text;used bigint;delta integer;begin
 select * into r from collect_receipt_operations.runs where id=p_run;
 r:=collect_receipt_operations.require_run(p_run,p_fence,r.principal_id);select * into p from collect_receipt_operations.policy where singleton;
 if p_reservation is null or p_collection is null or not p_collection=any(r.collection_ids)or p_device is distinct from r.device_id
  or p_actions is null or p_sms_segments is null or p_actions not between 0 and 1 or p_sms_segments not between 0 and 10 or p_actions+p_sms_segments=0 then raise exception 'operations_budget_input_invalid'using errcode='22023';end if;
 if p_sms_segments>0 and(r.mode not in('Live','Live-limited')or p_device is null or not exists(select 1 from collect_gateway.devices where id=p_device and state='active')
  or not coalesce((select enabled from public.feature_flags where key='hybrid_sms_notifications'),false))then raise exception 'operations_dispatch_paused'using errcode='55000';end if;
 select * into prior from collect_receipt_operations.reservations where id=p_reservation;
 if prior.id is not null then
  if prior.run_id<>p_run or prior.fence_version<>p_fence or prior.collection_id<>p_collection or prior.device_id is distinct from p_device or prior.actions<>p_actions or prior.sms_segments<>p_sms_segments then raise exception 'operations_budget_conflict'using errcode='22023';end if;return true;end if;
 t:=clock_timestamp();start_day:=date_trunc('day',t at time zone 'UTC')at time zone 'UTC';
 foreach k in array array['run_actions','group_actions','device_actions','global_actions','run_sms_segments','group_sms_segments','device_sms_segments','global_sms_segments']loop
  delta:=case when k like '%sms_segments'then p_sms_segments else p_actions end;
  select coalesce(sum(case when k like '%sms_segments'then q.sms_segments else q.actions end),0)into used from collect_receipt_operations.reservations q
   where q.recorded_at>=start_day and(case when k like 'run_%'then q.run_id=p_run when k like 'group_%'then q.collection_id=p_collection when k like 'device_%'then q.device_id is not distinct from p_device else true end);
  if used+delta>(p.caps->>k)::bigint then return false;end if;
 end loop;
 insert into collect_receipt_operations.reservations values(p_reservation,p_run,p_fence,p_collection,p_device,p_actions,p_sms_segments,t);return true;end$$;

create function collect_receipt_operations.ensure_snapshot(p_snapshot uuid,p_catchup boolean,p_commit boolean default true)
returns jsonb language plpgsql set search_path=''as $$
declare s collect_hybrid.momo_balance_snapshots;p public.payments;o collect_hybrid.sms_notification_outbox;
 policy collect_hybrid.sms_receipt_policies;consent collect_hybrid.sms_receipt_member_consents;identity collect_hybrid.member_momo_identities;
 settings collect_receipt_operations.policy;message text;ref text;job_id uuid;code text;begin
 select * into s from collect_hybrid.momo_balance_snapshots where id=p_snapshot and event_type='receipt';
 if s.id is null then return jsonb_build_object('ok',false,'code','SNAPSHOT_MISSING','business_handled',false,'receipt_id',null);end if;
 -- Canonical payment lock fences posting/reversal; current contact, policy and
 -- consent locks fence changes until immutable enqueue and its proof commit.
 select * into p from public.payments where id=s.payment_id for update;
 select * into o from collect_hybrid.sms_notification_outbox where payment_id=p.id and template_key='buri_munsi.payment_received'for update;
 if o.id is not null then
  code:=case when o.template_version=2 and collect_receipt_policy.content_is_valid(o)then 'RECEIPT_EXISTS'else 'LEGACY_CONTENT_REVIEW_REQUIRED'end;
  return jsonb_build_object('ok',code='RECEIPT_EXISTS','code',code,'business_handled',code='RECEIPT_EXISTS','receipt_id',o.id);end if;
 if p.status='reversed'then return jsonb_build_object('ok',true,'code','PAYMENT_REVERSED','business_handled',true,'receipt_id',null);end if;
 if p.status is distinct from 'posted'then return jsonb_build_object('ok',false,'code','PAYMENT_NOT_POSTED','business_handled',false,'receipt_id',null);end if;
 perform 1 from public.collections where id=s.collection_id for share;
 perform 1 from collect_hybrid.member_records where id=s.member_record_id for share;
 perform 1 from public.collection_members where collection_id=s.collection_id and member_record_id=s.member_record_id for share;
 if not collect_receipt_policy.snapshot_is_eligible(s)then return jsonb_build_object('ok',false,'code','RECIPIENT_INELIGIBLE','business_handled',false,'receipt_id',null);end if;
 select * into policy from collect_hybrid.sms_receipt_policies where collection_id=s.collection_id for share;
 select * into consent from collect_hybrid.sms_receipt_member_consents where member_record_id=s.member_record_id for share;
 select * into identity from collect_hybrid.member_momo_identities where member_id=s.member_record_id for share;
 select * into settings from collect_receipt_operations.policy where singleton;
 code:=case when policy.collection_id is null or not policy.enabled then 'POLICY_DISABLED'
  when consent.member_record_id is null or not consent.enabled then 'CONSENT_MISSING'
  when identity.member_id is null then 'CONTACT_MISSING'
  when s.captured_at<clock_timestamp()-make_interval(hours=>settings.catchup_hours)then 'CATCHUP_WINDOW_EXCEEDED'
  when p_catchup and(identity.revision<>1 or identity.created_at>s.captured_at)then 'CONTACT_HISTORY_UNPROVEN'
  when p_catchup and policy.updated_at>s.captured_at then 'POLICY_HISTORY_UNPROVEN'
  when p_catchup and consent.recorded_at>s.captured_at then 'CONSENT_HISTORY_UNPROVEN'else null end;
 if code is not null then return jsonb_build_object('ok',false,'code',code,'business_handled',false,'receipt_id',null);end if;
 ref:=btrim(coalesce(p.transaction_id,''));
 if ref!~'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'then return jsonb_build_object('ok',false,'code','CONTENT_REFUSED','business_handled',false,'receipt_id',null);end if;
 message:=collect_receipt_policy.render_v2(p.amount_rwf,s.member_balance_after_rwf,s.captured_at,ref,'rw');
 if not p_commit then return jsonb_build_object('ok',false,'code','DRY_RUN_ELIGIBLE','business_handled',false,'receipt_id',null);end if;
 insert into collect_hybrid.sms_notification_outbox(payment_id,snapshot_id,collection_id,member_record_id,destination_e164,destination_sha256,destination_revision,policy_revision,consent_revision,
 template_key,template_version,amount_rwf,member_balance_rwf,group_balance_rwf,reference,message_body,body_sha256,state)
 values(p.id,s.id,s.collection_id,s.member_record_id,identity.momo_number,encode(extensions.digest(identity.momo_number,'sha256'),'hex'),identity.revision,policy.revision,consent.revision,
 'buri_munsi.payment_received',2,p.amount_rwf,s.member_balance_after_rwf,s.group_balance_after_rwf,ref,message,encode(extensions.digest(message,'sha256'),'hex'),'queued')
 on conflict(payment_id,template_key)do nothing returning id into job_id;
 if job_id is null then select id into job_id from collect_hybrid.sms_notification_outbox where payment_id=p.id and template_key='buri_munsi.payment_received';end if;
 insert into collect_receipt_policy.content_evidence values(job_id,2,'rw',s.captured_at,encode(extensions.digest(message,'sha256'),'hex'))on conflict(outbox_id)do nothing;
 return jsonb_build_object('ok',true,'code','RECEIPT_ENQUEUED','business_handled',true,'receipt_id',job_id);end$$;

create function public.receipt_operations_execute_v2(p_principal_id uuid,p_request_id uuid,p_key_sha256 text,p_request_sha256 text,
 p_issued_at timestamptz,p_action text,p_payload jsonb)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare identity collect_supervisor.identities;prior collect_receipt_operations.requests;r collect_receipt_operations.runs;p collect_receipt_operations.policy;
 event collect_hybrid.receipt_business_events;row jsonb;result jsonb;base jsonb;fence bigint;at timestamptz;rid uuid;fv bigint;lim integer;eid uuid;expected bigint;target uuid;
 snapshot collect_hybrid.momo_balance_snapshots;payment_id uuid;sid uuid;code text;handled boolean;receipt uuid;examined integer:=0;done integer:=0;deferred integer:=0;rows jsonb;more boolean;begin
 identity:=collect_receipt_operations.require_identity(p_principal_id,p_key_sha256,p_request_id,p_request_sha256,p_issued_at,p_action);
 if p_payload is null or jsonb_typeof(p_payload)<>'object'then raise exception 'operations_payload_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-operations-request:'||p_request_id::text,0));
 identity:=collect_receipt_operations.require_identity(p_principal_id,p_key_sha256,p_request_id,p_request_sha256,p_issued_at,p_action);
 if p_action='reconcile_request'then
  perform collect_gateway.payload_keys(p_payload,array['target_request_id']);target:=collect_gateway.payload_uuid(p_payload,'target_request_id');
  if target=p_request_id then raise exception 'operations_lookup_identity_invalid'using errcode='22023';end if;
  more:=pg_try_advisory_xact_lock(hashtextextended('collect-operations-request:'||target::text,0));
  select * into prior from collect_receipt_operations.requests where more and request_id=target and principal_id=p_principal_id;
  return jsonb_build_object('contract_version',2,'target_request_id',target,'status',case when not more then 'in_progress'when prior.request_id is null then 'not_recorded'else 'recorded'end,'receipt',prior.result);end if;
 select * into prior from collect_receipt_operations.requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.principal_id<>p_principal_id or prior.action<>p_action or prior.request_sha256<>p_request_sha256 or prior.input is distinct from p_payload then raise exception 'operations_request_conflict'using errcode='22023';end if;return prior.result;end if;
 at:=clock_timestamp();base:=collect_receipt_operations.base(p_principal_id,p_request_id,p_action,at);
 if p_action='prove_key'then
  perform collect_gateway.payload_keys(p_payload,array[]::text[]);
  result:=base||jsonb_build_object('expires_at',collect_gateway.utc(identity.expires_at),'scope','rw_receipt_operations','business_handled',false,'financial_action',false,'send_action',false);
 elsif p_action='begin_run'then
  perform collect_gateway.payload_keys(p_payload,array[]::text[]);select * into p from collect_receipt_operations.policy where singleton for update;
  identity:=collect_receipt_operations.require_identity(p_principal_id,p_key_sha256,p_request_id,p_request_sha256,p_issued_at,p_action);at:=clock_timestamp();
  code:=case when p.emergency_stop or p.mode='Paused'then 'OPERATIONS_PAUSED'when not p_principal_id=any(p.principal_ids)or cardinality(p.collection_ids)=0 then 'PRINCIPAL_SCOPE_UNCONFIGURED'
   when exists(select 1 from collect_receipt_operations.runs where completed_at is null and expires_at>at and policy_revision=p.revision)then 'RUN_BUSY'else 'RUN_STARTED'end;
  if code='RUN_STARTED'then
   update collect_receipt_operations.fence set value=value+1 where singleton and value<1000000000 returning value into fence;
   if fence is null then raise exception 'operations_fence_exhausted'using errcode='55000';end if;
   insert into collect_receipt_operations.runs(request_id,principal_id,fence_version,policy_revision,mode,collection_ids,device_id,started_at,expires_at)
   values(p_request_id,p_principal_id,fence,p.revision,p.mode,p.collection_ids,p.device_ids[1],at,least(at+interval '120 seconds',identity.expires_at))returning * into r;end if;
  result:=collect_receipt_operations.base(p_principal_id,p_request_id,p_action,at)||jsonb_build_object('ok',code='RUN_STARTED','code',code,'run_id',r.id,'fence_version',r.fence_version,'mode',p.mode,'expires_at',case when r.id is not null then collect_gateway.utc(r.expires_at)end);
 else
  rid:=collect_gateway.payload_uuid(p_payload,'run_id');fv:=collect_gateway.payload_int(p_payload,'fence_version',1,1000000000);
  r:=collect_receipt_operations.require_run(rid,fv,p_principal_id);select * into p from collect_receipt_operations.policy where singleton;
  base:=base||jsonb_build_object('run_id',r.id,'fence_version',r.fence_version);
  if p_action='list_events'then
   perform collect_gateway.payload_keys(p_payload,array['run_id','fence_version','limit']);lim:=collect_gateway.payload_int(p_payload,'limit',1,25);
   select coalesce(jsonb_agg(jsonb_build_object('event_id',e.id,'source_version',e.source_version,'event_kind',e.event_kind,'payment_id',e.payment_id,'collection_id',e.collection_id,'source_state',e.source_state)order by e.created_at,e.id),'[]'::jsonb),count(*)>lim into rows,more
   from(select e.* from collect_hybrid.receipt_business_events e
    where e.collection_id=any(r.collection_ids)and not exists(select 1 from collect_receipt_operations.handled_events h where h.event_id=e.id)
    and not exists(select 1 from collect_receipt_operations.run_events h where h.run_id=r.id and h.event_id=e.id)
    and not exists(select 1 from collect_receipt_operations.event_deferrals d where d.event_id=e.id and d.next_check_at>clock_timestamp())
    order by e.created_at,e.id limit lim+1)e;
   if more then rows:=rows-(jsonb_array_length(rows)-1);end if;
   insert into collect_receipt_operations.run_batch_events select r.id,(value->>'event_id')::uuid,clock_timestamp()from jsonb_array_elements(rows)on conflict(run_id,event_id)do nothing;
   update collect_receipt_operations.runs set scan_performed=true where id=r.id;
   result:=base||jsonb_build_object('events',rows,'more',more);
  elsif p_action='ensure_receipt'then
   perform collect_gateway.payload_keys(p_payload,array['run_id','fence_version','event_id','expected_source_version']);eid:=collect_gateway.payload_uuid(p_payload,'event_id');expected:=collect_gateway.payload_int(p_payload,'expected_source_version',1,1000000000);
   select * into event from collect_hybrid.receipt_business_events where id=eid;
   if event.id is null or not coalesce(event.collection_id=any(r.collection_ids),false)then raise exception 'operations_event_scope_refused'using errcode='42501';end if;
   code:='SOURCE_CHANGED';handled:=false;receipt:=null;
   if event.source_version=expected then
    select * into snapshot from collect_hybrid.momo_balance_snapshots where payment_id=event.payment_id and event_type='receipt'order by captured_at,id limit 1;
    select jsonb_build_object('code',h.code,'business_handled',h.business_handled,'receipt_id',h.receipt_id)into row from collect_receipt_operations.run_events h where h.run_id=r.id and h.event_id=event.id;
    if row is not null then code:=row->>'code';handled:=(row->>'business_handled')::boolean;receipt:=(row->>'receipt_id')::uuid;
    elsif r.mode='Shadow'then code:='SHADOW_OBSERVED';
    elsif r.mode='Dry-run'then row:=collect_receipt_operations.ensure_snapshot(snapshot.id,true,false);code:=case when(row->>'business_handled')::boolean then 'DRY_RUN_ELIGIBLE'else row->>'code'end;
    elsif not collect_receipt_operations.reserve_budget(r.id,r.fence_version,p_request_id,event.collection_id,r.device_id,1,0)then code:='QUOTA_EXHAUSTED';
    else
     if event.event_kind='payment_reversed'and exists(select 1 from public.payments p0 where p0.id=event.payment_id and p0.status='reversed')then row:=jsonb_build_object('code','PAYMENT_REVERSED','business_handled',true,'receipt_id',null);
     else row:=collect_receipt_operations.ensure_snapshot(snapshot.id,true);end if;
     code:=row->>'code';handled:=(row->>'business_handled')::boolean;receipt:=(row->>'receipt_id')::uuid;
    end if;
   end if;
   insert into collect_receipt_operations.run_events values(r.id,event.id,event.source_version,code,handled,receipt,clock_timestamp())on conflict(run_id,event_id)do nothing;
   if handled then insert into collect_receipt_operations.handled_events values(event.id,r.id,p_principal_id,event.source_version,code,receipt,clock_timestamp())on conflict(event_id)do nothing;
   elsif r.mode in('Live','Live-limited')then insert into collect_receipt_operations.event_deferrals values(event.id,clock_timestamp()+interval '60 seconds',code)on conflict(event_id)do update set next_check_at=excluded.next_check_at,code=excluded.code;end if;
   result:=base||jsonb_build_object('event_id',event.id,'source_version',case when code='SOURCE_CHANGED'then expected else event.source_version end,'ok',handled,'code',code,'business_handled',handled,'receipt_id',receipt);
  elsif p_action='reconcile_backlog'then
   perform collect_gateway.payload_keys(p_payload,array['run_id','fence_version','limit']);lim:=collect_gateway.payload_int(p_payload,'limit',1,25);
   if p.catchup_enabled and r.mode in('Live','Live-limited')then
    for snapshot in select s.* from collect_hybrid.momo_balance_snapshots s
     where s.event_type='receipt'and s.collection_id=any(r.collection_ids)and s.captured_at>=clock_timestamp()-make_interval(hours=>p.catchup_hours)
     and not exists(select 1 from collect_hybrid.sms_notification_outbox o where o.payment_id=s.payment_id and o.template_key='buri_munsi.payment_received')
     and not exists(select 1 from collect_receipt_operations.backlog_results b where b.run_id=r.id and b.snapshot_id=s.id)
     order by s.captured_at,s.id limit lim loop
     if not collect_receipt_operations.reserve_budget(r.id,r.fence_version,snapshot.id,snapshot.collection_id,r.device_id,1,0)then exit;end if;
     row:=collect_receipt_operations.ensure_snapshot(snapshot.id,true);examined:=examined+1;handled:=(row->>'business_handled')::boolean;
     if handled then done:=done+1;else deferred:=deferred+1;end if;
     insert into collect_receipt_operations.backlog_results values(r.id,snapshot.id,row->>'code',handled,(row->>'receipt_id')::uuid,clock_timestamp());
    end loop;
   end if;result:=base||jsonb_build_object('examined',examined,'handled',done,'deferred',deferred);
  elsif p_action='complete_run'then
   perform collect_gateway.payload_keys(p_payload,array['run_id','fence_version']);
   update collect_receipt_operations.runs set completed_at=clock_timestamp()where id=r.id;
   select count(*)filter(where business_handled),count(*)filter(where not business_handled)into done,deferred from collect_receipt_operations.run_events where run_id=r.id;
   deferred:=deferred+(select count(*)from collect_receipt_operations.run_batch_events b where b.run_id=r.id and not exists(select 1 from collect_receipt_operations.run_events e where e.run_id=r.id and e.event_id=b.event_id));
   done:=done+(select count(*)from collect_receipt_operations.backlog_results where run_id=r.id and business_handled);
   deferred:=deferred+(select count(*)from collect_receipt_operations.backlog_results where run_id=r.id and not business_handled);
   select coalesce(jsonb_build_object('action_count',sum(actions),'sms_segments',sum(sms_segments)),jsonb_build_object('action_count',0,'sms_segments',0))into row from collect_receipt_operations.reservations where run_id=r.id;
   result:=base||jsonb_build_object('status','completed','handled_count',done,'deferred_count',deferred,'action_count',coalesce((row->>'action_count')::bigint,0),'sms_segments',coalesce((row->>'sms_segments')::bigint,0),'business_handled',r.mode in('Live','Live-limited')and r.scan_performed and deferred=0);
  else raise exception 'operations_action_refused'using errcode='22023';end if;
 end if;
 insert into collect_receipt_operations.requests values(p_request_id,p_principal_id,p_action,p_request_sha256,p_payload,p_issued_at,clock_timestamp(),result);
 return result;
end$$;

-- A sender may reserve an exact v2 queued receipt only under the currently
-- executing run. Reservation grants no carrier attestation or blind retry.
create function collect_receipt_operations.reserve_dispatch(p_run uuid,p_fence bigint,p_reservation uuid,p_outbox uuid,p_device uuid,p_sms_segments integer)
returns jsonb language plpgsql set search_path=''as $$declare r collect_receipt_operations.runs;o collect_hybrid.sms_notification_outbox;begin
 select * into r from collect_receipt_operations.runs where id=p_run;r:=collect_receipt_operations.require_run(p_run,p_fence,r.principal_id);
 select * into o from collect_hybrid.sms_notification_outbox where id=p_outbox for update;
 if o.id is null or o.state<>'queued'or o.template_version<>2 or not coalesce(o.collection_id=any(r.collection_ids),false)
  or p_device is distinct from r.device_id or not collect_hybrid.sms_receipt_job_is_current(o.id)
  or exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id=o.id)then raise exception 'operations_receipt_dispatch_refused'using errcode='55000';end if;
 if not collect_receipt_operations.reserve_budget(p_run,p_fence,p_reservation,o.collection_id,p_device,1,p_sms_segments)then return jsonb_build_object('ok',false,'code','QUOTA_EXHAUSTED');end if;
 return jsonb_build_object('ok',true,'code','DISPATCH_RESERVED','run_id',r.id,'fence_version',r.fence_version,'policy_revision',r.policy_revision,'device_id',r.device_id,'receipt_id',o.id,'expires_at',collect_gateway.utc(least(r.expires_at,clock_timestamp()+interval '120 seconds')));end$$;

revoke all on all functions in schema collect_receipt_operations from public,anon,authenticated,service_role;
revoke all on function public.admin_enroll_receipt_operations_identity_v2(uuid,text,text,timestamptz),public.admin_activate_receipt_operations_identity_v2(uuid,uuid,text),
 public.admin_configure_receipt_operations_v2(uuid,bigint,text,boolean,uuid[],uuid[],uuid[],jsonb,boolean,integer,text),public.admin_get_receipt_operations_policy_v2(),
 public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)from public,anon,authenticated,service_role;
grant execute on function public.admin_enroll_receipt_operations_identity_v2(uuid,text,text,timestamptz),public.admin_activate_receipt_operations_identity_v2(uuid,uuid,text),
 public.admin_configure_receipt_operations_v2(uuid,bigint,text,boolean,uuid[],uuid[],uuid[],jsonb,boolean,integer,text),public.admin_get_receipt_operations_policy_v2()to authenticated;
grant execute on function public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)to service_role;
commit;
