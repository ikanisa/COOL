begin;
-- Additive retry prerequisite only. No successor enqueue, grant, final arm,
-- resend, correction or live configuration is enabled by this migration.
create schema collect_receipt_successors;
revoke all on schema collect_receipt_successors from public,anon,authenticated,service_role;
create table collect_receipt_successors.configuration(
 singleton boolean primary key default true check(singleton),
 enabled boolean not null default false,
 revision bigint not null default 1 check(revision between 1 and 1000000000));
insert into collect_receipt_successors.configuration(singleton)values(true);
create table collect_receipt_successors.content_policies(
 version integer primary key check(version=1),
 choices jsonb not null check(jsonb_typeof(choices)='object'),
 owner_message text not null,
 recorded_at timestamptz not null default clock_timestamp());
insert into collect_receipt_successors.content_policies(version,choices,owner_message)values(1,
 '{"original_primary_retained":true,"definitely_not_invoked_requires_irreversible_unarmed_closure":true,"unknown_outcome_no_blind_retry":true,"financial_mutation":false,"dispatch_enabled":false}'::jsonb,
 'User requested goal 7 safe retry, cancellation, correction and approved resend; root accepted additive successor contract for staged implementation. This slice implements unarmed closure only.');
create table collect_receipt_successors.lineage_heads(
 root_outbox_id uuid primary key references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 revision bigint not null check(revision between 1 and 1000000000));
create table collect_receipt_successors.owner_requests(
 request_id uuid primary key,actor_id uuid not null,session_id uuid not null,
 action text not null check(action='close_unarmed'),
 input_sha256 text not null check(input_sha256~'^[0-9a-f]{64}$'),
 result jsonb not null check(jsonb_typeof(result)='object'),
 recorded_at timestamptz not null);
create table collect_receipt_successors.original_closures(
 id uuid primary key default gen_random_uuid(),
 root_outbox_id uuid not null unique references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 original_attempt_id uuid unique references collect_gateway_dispatch.attempts(id)on delete restrict,
 request_id uuid not null unique references collect_receipt_successors.owner_requests(request_id)on delete restrict deferrable initially deferred,
 actor_id uuid not null,session_id uuid not null,
 expected_root_revision bigint not null check(expected_root_revision between 1 and 999999999),
 root_revision bigint not null check(root_revision=expected_root_revision+1),
 expected_lineage_revision bigint not null check(expected_lineage_revision between 1 and 999999999),
 lineage_revision bigint not null check(lineage_revision=expected_lineage_revision+1),
 reason_code text not null check(reason_code='definitely_not_invoked'),
 reason text not null check(char_length(reason)between 8 and 500),
 proof_sha256 text not null check(proof_sha256~'^[0-9a-f]{64}$'),
 closed_at timestamptz not null);

create function collect_receipt_successors.immutable()returns trigger
language plpgsql set search_path=''as $$begin
 raise exception 'receipt_successor_evidence_immutable'using errcode='55000';end$$;
do $$declare t text;begin
 foreach t in array array['configuration','content_policies','lineage_heads','owner_requests','original_closures']loop
  execute format('alter table collect_receipt_successors.%I enable row level security',t);
  execute format('revoke all on collect_receipt_successors.%I from public,anon,authenticated,service_role',t);
  if t in('content_policies','owner_requests','original_closures')then
   execute format('create trigger retained_successor_evidence before update or delete on collect_receipt_successors.%I for each row execute function collect_receipt_successors.immutable()',t);
   execute format('create trigger retained_successor_evidence_truncate before truncate on collect_receipt_successors.%I for each statement execute function collect_receipt_successors.immutable()',t);
  end if;
 end loop;end$$;
create function collect_receipt_successors.protect_head()returns trigger
language plpgsql set search_path=''as $$begin
 if tg_op='DELETE'or new.root_outbox_id is distinct from old.root_outbox_id
  or new.revision is distinct from old.revision+1 or new.revision>1000000000 then
  raise exception 'receipt_successor_revision_invalid'using errcode='55000';end if;return new;end$$;
create trigger monotonic_successor_head before update or delete on collect_receipt_successors.lineage_heads
 for each row execute function collect_receipt_successors.protect_head();
create trigger retained_successor_head_truncate before truncate on collect_receipt_successors.lineage_heads
 for each statement execute function collect_receipt_successors.immutable();
create function collect_receipt_successors.advance(p_root uuid)returns bigint
language plpgsql set search_path=''as $$declare value bigint;begin
 -- Existing roots have implicit revision1. The first observation becomes2.
 insert into collect_receipt_successors.lineage_heads(root_outbox_id,revision)values(p_root,2)
 on conflict(root_outbox_id)do update set revision=lineage_heads.revision+1
  where lineage_heads.revision<1000000000 returning revision into value;
 if value is null then raise exception 'receipt_successor_revision_exhausted'using errcode='55000';end if;
 return value;end$$;
create function collect_receipt_successors.observe_root()returns trigger
language plpgsql security definer set search_path=''as $$declare root uuid;begin
 if tg_table_schema='collect_hybrid'and tg_table_name='sms_notification_outbox'then root:=new.id;
 elsif tg_table_schema='collect_gateway_dispatch'and tg_table_name='attempts'then root:=new.outbox_id;
 else select outbox_id into root from collect_gateway_dispatch.attempts where id=new.attempt_id;end if;
 if root is not null then perform collect_receipt_successors.advance(root);end if;return null;end$$;
create trigger zzzzzz_successor_root_observation after update on collect_hybrid.sms_notification_outbox
 for each row execute function collect_receipt_successors.observe_root();
create trigger successor_callback_observation after insert on collect_gateway_dispatch.callbacks
 for each row execute function collect_receipt_successors.observe_root();
create trigger successor_ordinary_grant_observation after insert on collect_gateway_dispatch.attempts
 for each row execute function collect_receipt_successors.observe_root();

create function collect_receipt_successors.protect_closed_root()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if exists(select 1 from collect_receipt_successors.original_closures where root_outbox_id=old.id)
  and to_jsonb(new)is distinct from to_jsonb(old)then
  raise exception 'receipt_original_irreversibly_closed'using errcode='55000';end if;
 return new;end$$;
create trigger successor_closed_original_guard before update on collect_hybrid.sms_notification_outbox
 for each row execute function collect_receipt_successors.protect_closed_root();

create function collect_receipt_successors.fence_transport_insert()returns trigger
language plpgsql security definer set search_path=''as $$declare root uuid;begin
 if tg_table_name='dispatch_arms'then
  select outbox_id into root from collect_hybrid.sms_notification_attempts where id=new.attempt_id;
 elsif tg_table_schema='collect_gateway_dispatch'and tg_table_name='arms'then
  select outbox_id into root from collect_gateway_dispatch.attempts where id=new.attempt_id;
 else root:=new.outbox_id;end if;
 -- All actual claim/grant/arm paths serialize on the retained root. Inverse
 -- direct INSERT paths refuse contention instead of creating a lock cycle.
 perform 1 from collect_hybrid.sms_notification_outbox where id=root for update nowait;
 if exists(select 1 from collect_receipt_successors.original_closures where root_outbox_id=root)then
  raise exception 'receipt_original_irreversibly_closed'using errcode='55000';end if;return new;
 exception when lock_not_available then raise exception 'receipt_successor_source_busy'using errcode='55P03';end$$;
create trigger successor_claim_exclusion before insert on collect_hybrid.sms_notification_claim_requests
 for each row execute function collect_receipt_successors.fence_transport_insert();
create trigger successor_confirmation_exclusion before insert on collect_hybrid.sms_notification_confirmations
 for each row execute function collect_receipt_successors.fence_transport_insert();
create trigger successor_assisted_attempt_exclusion before insert on collect_hybrid.sms_notification_attempts
 for each row execute function collect_receipt_successors.fence_transport_insert();
create trigger successor_assisted_arm_exclusion before insert on collect_gateway.dispatch_arms
 for each row execute function collect_receipt_successors.fence_transport_insert();
create trigger successor_automatic_grant_exclusion before insert on collect_gateway_dispatch.attempts
 for each row execute function collect_receipt_successors.fence_transport_insert();
create trigger successor_automatic_arm_exclusion before insert on collect_gateway_dispatch.arms
 for each row execute function collect_receipt_successors.fence_transport_insert();

create function collect_receipt_successors.closure_reason(p_job collect_hybrid.sms_notification_outbox)
returns text language sql stable security definer set search_path=''as $$
 select case
 when p_job.id is null or not collect_receipt_actions.rwanda_source(p_job)then 'unavailable'
 when exists(select 1 from collect_receipt_successors.original_closures where root_outbox_id=p_job.id)then 'already_closed'
 when p_job.state is distinct from 'queued'then 'state_not_queued'
 when p_job.fence_version<>0 or p_job.attempt_count<>0 or p_job.claim_token is not null
  or p_job.claimed_by is not null or p_job.claim_expires_at is not null or p_job.observed_sent_at is not null
  or p_job.suppression_reason is not null
  or exists(select 1 from collect_hybrid.sms_notification_claim_requests where outbox_id=p_job.id)
  or exists(select 1 from collect_hybrid.sms_notification_confirmations where outbox_id=p_job.id)
  or exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id=p_job.id)
  or exists(select 1 from collect_security.assisted_sms_session_evidence where outbox_id=p_job.id)then 'assisted_transport_present'
 when exists(select 1 from collect_gateway_dispatch.attempts a where a.outbox_id=p_job.id
  and(a.state<>'granted'or exists(select 1 from collect_gateway_dispatch.arms where attempt_id=a.id)
   or exists(select 1 from collect_gateway_dispatch.callbacks where attempt_id=a.id)))then 'original_already_armed'
 when not collect_receipt_policy.content_is_current(p_job)then 'source_evidence_invalid'
 else 'unarmed_eligible'end
$$;
create function collect_receipt_successors.closure_inspection(p_job collect_hybrid.sms_notification_outbox)
returns jsonb language plpgsql set search_path=''as $$declare rr bigint;lr bigint;reason text;t timestamptz;begin
 t:=clock_timestamp();reason:=collect_receipt_successors.closure_reason(p_job);
 select coalesce((select revision from collect_receipt_actions.revisions where outbox_id=p_job.id),1)into rr;
 select coalesce((select revision from collect_receipt_successors.lineage_heads where root_outbox_id=p_job.id),1)into lr;
 if rr=1000000000 or lr=1000000000 then reason:='revision_exhausted';end if;
 return jsonb_build_object('contract_version',1,'scope','rw_receipt_successors','action','close_unarmed',
  'outbox_id',p_job.id,'checked_at',collect_ops.utc(t),'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),
  'status',case when reason='unavailable'then 'unavailable'else 'available'end,
  'root_revision',case when reason<>'unavailable'then rr end,'lineage_revision',case when reason<>'unavailable'then lr end,
  'can_close',reason='unarmed_eligible','reason_code',reason,
  'automatic_grant_present',case when reason<>'unavailable'then exists(select 1 from collect_gateway_dispatch.attempts where outbox_id=p_job.id)end,
  'financial_action',false,'send_action',false,'carrier_proof',false,'delivery_proven',false);
end$$;
create function public.admin_inspect_unarmed_receipt_closure_v1(p_outbox_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$declare o collect_hybrid.sms_notification_outbox;begin
 perform collect_receipt_actions.actor(false);
 if p_outbox_id is null then raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 select * into o from collect_hybrid.sms_notification_outbox where id=p_outbox_id for share;
 perform collect_receipt_actions.actor(false);
 return collect_receipt_successors.closure_inspection(o)||jsonb_build_object('outbox_id',p_outbox_id);
 exception when lock_not_available then raise exception 'receipt_successor_source_busy'using errcode='55P03';end$$;

create function public.admin_close_unarmed_receipt_v1(p_request_id uuid,p_outbox_id uuid,
 p_expected_root_revision bigint,p_expected_lineage_revision bigint,p_reason_code text,p_reason text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;o collect_hybrid.sms_notification_outbox;a collect_gateway_dispatch.attempts;
 prior collect_receipt_successors.owner_requests;row collect_receipt_successors.original_closures;
 rr bigint;lr bigint;input_hash text;proof text;reason text:=btrim(coalesce(p_reason,''));t timestamptz;result jsonb;begin
 sid:=collect_receipt_actions.actor(true);
 if p_request_id is null or p_outbox_id is null or p_expected_root_revision is null or p_expected_lineage_revision is null
  or p_expected_root_revision not between 1 and 999999999 or p_expected_lineage_revision not between 1 and 999999999
  or p_reason_code is distinct from 'definitely_not_invoked'or char_length(reason)not between 8 and 500 then
  raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 input_hash:=encode(extensions.digest(jsonb_build_array(p_outbox_id,p_expected_root_revision,p_expected_lineage_revision,p_reason_code,reason)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-successor-owner:'||p_request_id::text,0));
 select * into prior from collect_receipt_successors.owner_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.input_sha256<>input_hash or prior.action<>'close_unarmed'then
   raise exception 'receipt_successor_request_conflict'using errcode='22023';end if;
  perform collect_receipt_actions.actor(true);return prior.result;end if;
 -- Ordinary automatic grant/arm locks policy before the root. Owner close
 -- follows that order; callback facts need no policy and cannot exist unarmed.
 perform 1 from collect_receipt_operations.policy where singleton for update;
 select * into o from collect_hybrid.sms_notification_outbox where id=p_outbox_id for update;
 select * into a from collect_gateway_dispatch.attempts where outbox_id=o.id for update;
 perform collect_receipt_actions.actor(true);
 select coalesce((select revision from collect_receipt_actions.revisions where outbox_id=o.id),1)into rr;
 select coalesce((select revision from collect_receipt_successors.lineage_heads where root_outbox_id=o.id),1)into lr;
 if rr<>p_expected_root_revision or lr<>p_expected_lineage_revision then
  raise exception 'receipt_successor_source_changed'using errcode='55000';end if;
 if collect_receipt_successors.closure_reason(o)is distinct from 'unarmed_eligible'then
  raise exception 'receipt_successor_original_not_closable'using errcode='55000';end if;
 -- Source wait never creates payment/outbox inversion. Closure proof binds
 -- immutable financial/content evidence; paused/disabled sends can be closed.
 perform 1 from public.payments where id=o.payment_id for share nowait;
 perform 1 from public.collections where id=o.collection_id for share nowait;
 perform 1 from collect_hybrid.member_records where id=o.member_record_id for share nowait;
 perform 1 from public.collection_members where collection_id=o.collection_id and member_record_id=o.member_record_id for share nowait;
 if collect_receipt_successors.closure_reason(o)is distinct from 'unarmed_eligible'then
  raise exception 'receipt_successor_original_not_closable'using errcode='55000';end if;
 proof:=encode(extensions.digest(jsonb_build_object('original',to_jsonb(o),'automatic_grant',to_jsonb(a),
  'root_revision',rr,'lineage_revision',lr,'financial_content_valid',true,'no_assisted_transport',true,'no_automatic_arm',true)::text,'sha256'),'hex');
 update collect_hybrid.sms_notification_outbox set state='suppressed',suppression_reason='successor_unarmed_closed'where id=o.id;
 select revision into rr from collect_receipt_actions.revisions where outbox_id=o.id;
 select revision into lr from collect_receipt_successors.lineage_heads where root_outbox_id=o.id;
 if rr<>p_expected_root_revision+1 or lr<>p_expected_lineage_revision+1 then
  raise exception 'receipt_successor_revision_invalid'using errcode='55000';end if;
 perform collect_receipt_actions.actor(true);t:=clock_timestamp();
 insert into collect_receipt_successors.original_closures(root_outbox_id,original_attempt_id,request_id,actor_id,session_id,
 expected_root_revision,root_revision,expected_lineage_revision,lineage_revision,reason_code,reason,proof_sha256,closed_at)
 values(o.id,a.id,p_request_id,auth.uid(),sid,p_expected_root_revision,rr,p_expected_lineage_revision,lr,p_reason_code,reason,proof,t)returning *into row;
 result:=jsonb_build_object('contract_version',1,'scope','rw_receipt_successors','action','close_unarmed','request_id',p_request_id,
  'outbox_id',o.id,'closure_id',row.id,'expected_root_revision',p_expected_root_revision,'root_revision',rr,
  'expected_lineage_revision',p_expected_lineage_revision,'lineage_revision',lr,'proof_class','never_armed_closed',
  'proof_sha256',proof,'reason_code',p_reason_code,'recorded_at',collect_ops.utc(t),
  'financial_action',false,'send_action',false,'primary_receipt_retained',true,'carrier_proof',false,'delivery_proven',false);
 insert into collect_receipt_successors.owner_requests values(p_request_id,auth.uid(),sid,'close_unarmed',input_hash,result,t);
 perform public.create_audit_log('notification.successor.original_closed','sms_notification_outbox',o.id,
  jsonb_build_object('request_id',p_request_id,'closure_id',row.id,'root_revision',rr,'lineage_revision',lr,'reason_code',p_reason_code,'proof_sha256',proof),auth.uid());
 return result;
 exception when lock_not_available then raise exception 'receipt_successor_source_busy'using errcode='55P03';end$$;
create function public.admin_get_receipt_successor_request_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare r collect_receipt_successors.owner_requests;busy boolean;begin
 perform collect_receipt_actions.actor(false);
 if p_request_id is null then raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 busy:=not pg_try_advisory_xact_lock(hashtextextended('collect-receipt-successor-owner:'||p_request_id::text,0));
 select *into r from collect_receipt_successors.owner_requests where request_id=p_request_id;
 if r.request_id is not null and r.actor_id<>auth.uid()then raise exception 'receipt_successor_request_unavailable'using errcode='42501';end if;
 perform collect_receipt_actions.actor(false);
 return jsonb_build_object('contract_version',1,'scope','rw_receipt_successors','request_id',p_request_id,
  'status',case when r.request_id is not null then 'recorded'when busy then 'in_progress'else 'not_recorded'end,'receipt',r.result);
end$$;
revoke all on all functions in schema collect_receipt_successors from public,anon,authenticated,service_role;
revoke all on function public.admin_inspect_unarmed_receipt_closure_v1(uuid),
 public.admin_close_unarmed_receipt_v1(uuid,uuid,bigint,bigint,text,text),
 public.admin_get_receipt_successor_request_v1(uuid)from public,anon,authenticated,service_role;
grant execute on function public.admin_inspect_unarmed_receipt_closure_v1(uuid),
 public.admin_close_unarmed_receipt_v1(uuid,uuid,bigint,bigint,text,text),
 public.admin_get_receipt_successor_request_v1(uuid)to authenticated;
commit;
