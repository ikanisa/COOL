set search_path=public,extensions,auth;set timezone='UTC';
begin;
-- Reviewed retry intent only. No execution job, reservation, gateway protocol,
-- final arm, SMS, correction or resend is introduced by this slice.
alter table collect_receipt_successors.owner_requests drop constraint owner_requests_action_check;
alter table collect_receipt_successors.owner_requests add constraint owner_requests_action_check
 check(action in('close_unarmed','approve_successor','revoke_successor'));
alter table collect_receipt_successors.content_policies drop constraint content_policies_version_check;
alter table collect_receipt_successors.content_policies add constraint content_policies_version_check check(version between 1 and 10);
insert into collect_receipt_successors.content_policies(version,choices,owner_message)values(2,
 '{"action":"retry_uninvoked","requires_irreversible_unarmed_closure":true,"body_source":"current_v2_recorded_member_savings_snapshot","languages":["rw","en","fr"],"approval_expires_seconds":900,"inspection_expires_seconds":60,"financial_mutation":false,"send_authority":false,"dispatch_enabled":false}'::jsonb,
 'User requested safe retry and root accepted immutable backend-derived approvals. This stage retains reviewed retry intent only; unknown, resend and correction are refused.');
create table collect_receipt_successors.approvals(
 id uuid primary key default gen_random_uuid(),
 root_outbox_id uuid not null references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 closure_id uuid not null references collect_receipt_successors.original_closures(id)on delete restrict,
 sequence bigint not null check(sequence between 1 and 1000000000),
 action text not null check(action='retry_uninvoked'),
 actor_id uuid not null,session_id uuid not null,
 request_id uuid not null unique references collect_receipt_successors.owner_requests(request_id)on delete restrict deferrable initially deferred,
 expected_root_revision bigint not null check(expected_root_revision between 1 and 999999999),
 expected_lineage_revision bigint not null check(expected_lineage_revision between 1 and 999999998),
 lineage_revision bigint not null check(lineage_revision=expected_lineage_revision+1),
 content_policy_version integer not null references collect_receipt_successors.content_policies(version)on delete restrict check(content_policy_version=2),
 source_snapshot_id uuid not null references collect_hybrid.momo_balance_snapshots(id)on delete restrict,
 candidate jsonb not null check(jsonb_typeof(candidate)='object'),
 preview_sha256 text not null check(preview_sha256~'^[0-9a-f]{64}$'),
 sampled_valid_until timestamptz not null check(isfinite(sampled_valid_until)),
 reason_code text not null check(reason_code='definitely_not_invoked'),
 reason text not null check(char_length(reason)between 8 and 500),
 recorded_at timestamptz not null check(isfinite(recorded_at)),
 expires_at timestamptz not null check(isfinite(expires_at)and expires_at=recorded_at+interval '15 minutes'),
 unique(root_outbox_id,sequence));
create index successor_approval_queue on collect_receipt_successors.approvals(expires_at,recorded_at,id);
create table collect_receipt_successors.approval_events(
 id uuid primary key default gen_random_uuid(),
 approval_id uuid not null references collect_receipt_successors.approvals(id)on delete restrict,
 revision integer not null check(revision in(1,2)),
 event_kind text not null check(event_kind in('approved','revoked')),
 request_id uuid not null unique references collect_receipt_successors.owner_requests(request_id)on delete restrict deferrable initially deferred,
 actor_id uuid not null,session_id uuid not null,
 lineage_revision bigint not null check(lineage_revision between 2 and 1000000000),
 reason text not null check(char_length(reason)between 8 and 500),
 recorded_at timestamptz not null check(isfinite(recorded_at)),
 check((revision=1 and event_kind='approved')or(revision=2 and event_kind='revoked')),
 unique(approval_id,revision),unique(approval_id,event_kind));
do $$declare t text;begin
 foreach t in array array['approvals','approval_events']loop
  execute format('alter table collect_receipt_successors.%I enable row level security',t);
  execute format('revoke all on collect_receipt_successors.%I from public,anon,authenticated,service_role',t);
  execute format('create trigger retained_successor_evidence before update or delete on collect_receipt_successors.%I for each row execute function collect_receipt_successors.immutable()',t);
  execute format('create trigger retained_successor_evidence_truncate before truncate on collect_receipt_successors.%I for each statement execute function collect_receipt_successors.immutable()',t);
 end loop;end$$;

create function collect_receipt_successors.lock_preview_source(p_root uuid)returns void
language plpgsql set search_path=''as $$declare o collect_hybrid.sms_notification_outbox;begin
 select *into o from collect_hybrid.sms_notification_outbox where id=p_root;
 -- Never invert payment/receipt or member/receipt wait order. Every mutable
 -- source determining the candidate is locked NOWAIT until approval commits.
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
end$$;
create function collect_receipt_successors.retry_candidate(p_root uuid,p_source uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare o collect_hybrid.sms_notification_outbox;c collect_receipt_successors.original_closures;
 s collect_hybrid.momo_balance_snapshots;p public.payments;policy collect_hybrid.sms_receipt_policies;
 consent collect_hybrid.sms_receipt_member_consents;i collect_hybrid.member_momo_identities;
 a collect_gateway_dispatch.attempts;body text;ref text;rr bigint;lr bigint;proof text;begin
 select *into o from collect_hybrid.sms_notification_outbox where id=p_root;
 if o.id is null or not collect_receipt_actions.rwanda_source(o)then return jsonb_build_object('reason_code','unavailable');end if;
 if p_source is distinct from o.snapshot_id then return jsonb_build_object('reason_code','source_not_original');end if;
 select *into c from collect_receipt_successors.original_closures where root_outbox_id=o.id;
 if c.id is null or o.state<>'suppressed'or o.suppression_reason<>'successor_unarmed_closed'then
  return jsonb_build_object('reason_code','irreversible_closure_required');end if;
 -- Closure is immutable and insertion guards exclude future transports.
 -- Still fold actual transport facts, so corruption/late evidence never grants
 -- authority merely because a classification was once recorded.
 if exists(select 1 from collect_hybrid.sms_notification_claim_requests where outbox_id=o.id)
  or exists(select 1 from collect_hybrid.sms_notification_confirmations where outbox_id=o.id)
  or exists(select 1 from collect_hybrid.sms_notification_attempts where outbox_id=o.id)
  or exists(select 1 from collect_security.assisted_sms_session_evidence where outbox_id=o.id)
  or exists(select 1 from collect_gateway_dispatch.attempts x where x.outbox_id=o.id and(x.state<>'granted'
   or exists(select 1 from collect_gateway_dispatch.arms where attempt_id=x.id)
   or exists(select 1 from collect_gateway_dispatch.callbacks where attempt_id=x.id)))then
  return jsonb_build_object('reason_code','transport_proof_changed');end if;
 select *into s from collect_hybrid.momo_balance_snapshots where id=o.snapshot_id;
 select *into p from public.payments where id=o.payment_id;
 if not collect_receipt_policy.content_is_current(o)or not collect_receipt_policy.snapshot_is_eligible(s)then
  return jsonb_build_object('reason_code','source_evidence_invalid');end if;
 select *into policy from collect_hybrid.sms_receipt_policies where collection_id=o.collection_id;
 select *into consent from collect_hybrid.sms_receipt_member_consents where member_record_id=o.member_record_id;
 select *into i from collect_hybrid.member_momo_identities where member_id=o.member_record_id;
 if policy.collection_id is null or not policy.enabled or policy.template_key<>'buri_munsi.payment_received'
  or policy.template_version<>1 or policy.receipt_language not in('rw','en','fr')then
  return jsonb_build_object('reason_code','policy_disabled');end if;
 if consent.member_record_id is null or not consent.enabled then return jsonb_build_object('reason_code','consent_missing');end if;
 if i.member_id is null or i.momo_number!~'^\+2507[2389][0-9]{7}$'then return jsonb_build_object('reason_code','contact_missing');end if;
 ref:=btrim(coalesce(p.transaction_id,''));
 if ref!~'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'then return jsonb_build_object('reason_code','content_refused');end if;
 body:=collect_receipt_policy.render_v2(p.amount_rwf,s.member_balance_after_rwf,s.captured_at,ref,policy.receipt_language);
 perform collect_gateway_dispatch.segment_count(body);
 select coalesce((select revision from collect_receipt_actions.revisions where outbox_id=o.id),1)into rr;
 select coalesce((select revision from collect_receipt_successors.lineage_heads where root_outbox_id=o.id),1)into lr;
 if rr>=1000000000 or lr>=999999999 then return jsonb_build_object('reason_code','revision_exhausted');end if;
 select *into a from collect_gateway_dispatch.attempts where outbox_id=o.id;
 proof:=encode(extensions.digest(jsonb_build_object('original',to_jsonb(o),'closure',to_jsonb(c),'ordinary_grant',to_jsonb(a))::text,'sha256'),'hex');
 return jsonb_build_object('reason_code','retry_eligible','root_outbox_id',o.id,'closure_id',c.id,
  'action','retry_uninvoked','proof_class','never_armed_closed','transport_proof_sha256',proof,
  'root_revision',rr,'lineage_revision',lr,'source_snapshot_id',s.id,'journal_entry_id',s.journal_entry_id,
  'source_sha256',encode(extensions.digest(to_jsonb(s)::text,'sha256'),'hex'),
  'payment_id',p.id,'collection_id',o.collection_id,'member_record_id',o.member_record_id,
  'amount_rwf',s.delta_rwf,'member_balance_recorded_rwf',s.member_balance_after_rwf,
  'snapshot_recorded_at',collect_ops.utc(s.captured_at),'reference',ref,
  'destination_e164',i.momo_number,'destination_sha256',encode(extensions.digest(i.momo_number,'sha256'),'hex'),
  'destination_revision',i.revision,'policy_revision',policy.revision,'consent_revision',consent.revision,
  'language',policy.receipt_language,'content_policy_version',2,'body',body,
  'body_sha256',encode(extensions.digest(body,'sha256'),'hex'),'segment_count',collect_gateway_dispatch.segment_count(body));
end$$;
create function collect_receipt_successors.preview_hash(p_candidate jsonb,p_deadline timestamptz)returns text
language sql immutable set search_path=''as $$
 select encode(extensions.digest(jsonb_build_object('contract_version',1,'candidate',p_candidate,
  'sample_valid_until',collect_ops.utc(p_deadline))::text,'sha256'),'hex')
$$;
create function collect_receipt_successors.pending(p_root uuid)returns boolean
language sql stable set search_path=''as $$
 select exists(select 1 from collect_receipt_successors.approvals a where a.root_outbox_id=p_root
  and a.expires_at>clock_timestamp()and not exists(select 1 from collect_receipt_successors.approval_events e where e.approval_id=a.id and e.event_kind='revoked'))
$$;
create function public.admin_inspect_receipt_successor_v1(p_outbox_id uuid,p_action text,p_source_snapshot_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare o collect_hybrid.sms_notification_outbox;c jsonb;t timestamptz;deadline timestamptz;reason text;begin
 perform collect_receipt_actions.actor(false);
 if p_outbox_id is null or p_source_snapshot_id is null or p_action is null
  or p_action not in('retry_uninvoked','approved_resend','correction')then
  raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 select *into o from collect_hybrid.sms_notification_outbox where id=p_outbox_id for share;
 perform collect_receipt_successors.lock_preview_source(o.id);
 perform collect_receipt_actions.actor(false);t:=clock_timestamp();deadline:=t+interval '60 seconds';
 c:=collect_receipt_successors.retry_candidate(o.id,p_source_snapshot_id);reason:=c->>'reason_code';
 if reason<>'unavailable'and p_action<>'retry_uninvoked'then reason:='proof_class_unavailable';end if;
 if reason='retry_eligible'and collect_receipt_successors.pending(o.id)then reason:='approval_pending';end if;
 return jsonb_build_object('contract_version',1,'scope','rw_receipt_successors','action',p_action,
  'outbox_id',p_outbox_id,'source_snapshot_id',p_source_snapshot_id,'checked_at',collect_ops.utc(t),
  'sample_valid_until',collect_ops.utc(deadline),'status',case when reason='unavailable'then 'unavailable'else 'available'end,
  'can_approve',reason='retry_eligible','reason_code',reason,
  'preview',case when reason in('retry_eligible','approval_pending')then c-'destination_e164'||jsonb_build_object('recipient_masked','+250***'||right(c->>'destination_e164',3))end,
  'preview_sha256',case when reason='retry_eligible'then collect_receipt_successors.preview_hash(c,deadline)end,
  'configuration_enabled',(select enabled from collect_receipt_successors.configuration where singleton),
  'financial_action',false,'send_action',false,'primary_receipt_retained',true,'carrier_proof',false,'delivery_proven',false);
 exception when lock_not_available then raise exception 'receipt_successor_source_busy'using errcode='55P03';end$$;
create function public.admin_approve_receipt_successor_v1(p_request_id uuid,p_outbox_id uuid,p_action text,
 p_source_snapshot_id uuid,p_expected_root_revision bigint,p_expected_lineage_revision bigint,
 p_preview_sha256 text,p_sample_valid_until timestamptz,p_reason_code text,p_reason text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;c jsonb;o collect_hybrid.sms_notification_outbox;prior collect_receipt_successors.owner_requests;
 a collect_receipt_successors.approvals;ih text;reason text:=btrim(coalesce(p_reason,''));lr bigint;t timestamptz;result jsonb;begin
 sid:=collect_receipt_actions.actor(true);
 if p_request_id is null or p_outbox_id is null or p_source_snapshot_id is null
  or p_action is distinct from 'retry_uninvoked'or p_reason_code is distinct from 'definitely_not_invoked'
  or p_expected_root_revision is null or p_expected_root_revision not between 1 and 999999999
  or p_expected_lineage_revision is null or p_expected_lineage_revision not between 1 and 999999998
  or p_preview_sha256 is null or p_preview_sha256!~'^[0-9a-f]{64}$'
  or p_sample_valid_until is null or not isfinite(p_sample_valid_until)or char_length(reason)not between 8 and 500 then
  raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 ih:=encode(extensions.digest(jsonb_build_array(p_outbox_id,p_action,p_source_snapshot_id,p_expected_root_revision,
  p_expected_lineage_revision,p_preview_sha256,collect_ops.utc(p_sample_valid_until),p_reason_code,reason)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-successor-owner:'||p_request_id::text,0));
 select *into prior from collect_receipt_successors.owner_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.input_sha256<>ih or prior.action<>'approve_successor'then
   raise exception 'receipt_successor_request_conflict'using errcode='22023';end if;
  perform collect_receipt_actions.actor(true);return prior.result;end if;
 perform 1 from collect_receipt_operations.policy where singleton for update;
 select *into o from collect_hybrid.sms_notification_outbox where id=p_outbox_id for update;
 perform 1 from collect_gateway_dispatch.attempts where outbox_id=o.id for share;
 perform collect_receipt_successors.lock_preview_source(o.id);
 perform collect_receipt_actions.actor(true);t:=clock_timestamp();
 if p_sample_valid_until<=t or p_sample_valid_until>t+interval '60 seconds'then
  raise exception 'receipt_successor_preview_expired'using errcode='55000';end if;
 c:=collect_receipt_successors.retry_candidate(o.id,p_source_snapshot_id);
 if c->>'reason_code' is distinct from 'retry_eligible'then
  raise exception 'receipt_successor_candidate_refused'using errcode='55000';end if;
 if (c->>'root_revision')::bigint<>p_expected_root_revision
  or(c->>'lineage_revision')::bigint<>p_expected_lineage_revision
  or collect_receipt_successors.preview_hash(c,p_sample_valid_until)<>p_preview_sha256 then
  raise exception 'receipt_successor_source_changed'using errcode='55000';end if;
 if collect_receipt_successors.pending(o.id)then raise exception 'receipt_successor_approval_pending'using errcode='55000';end if;
 lr:=collect_receipt_successors.advance(o.id);
 if lr<>p_expected_lineage_revision+1 then raise exception 'receipt_successor_revision_invalid'using errcode='55000';end if;
 insert into collect_receipt_successors.approvals(root_outbox_id,closure_id,sequence,action,actor_id,session_id,request_id,
  expected_root_revision,expected_lineage_revision,lineage_revision,content_policy_version,source_snapshot_id,candidate,
  preview_sha256,sampled_valid_until,reason_code,reason,recorded_at,expires_at)
 values(o.id,(c->>'closure_id')::uuid,coalesce((select max(sequence)from collect_receipt_successors.approvals where root_outbox_id=o.id),0)+1,
  p_action,auth.uid(),sid,p_request_id,p_expected_root_revision,p_expected_lineage_revision,lr,2,p_source_snapshot_id,c,
  p_preview_sha256,p_sample_valid_until,p_reason_code,reason,t,t+interval '15 minutes')returning *into a;
 insert into collect_receipt_successors.approval_events(approval_id,revision,event_kind,request_id,actor_id,session_id,lineage_revision,reason,recorded_at)
 values(a.id,1,'approved',p_request_id,auth.uid(),sid,lr,reason,t);
 result:=jsonb_build_object('contract_version',1,'scope','rw_receipt_successors','action','approve_successor','request_id',p_request_id,
  'outbox_id',o.id,'approval_id',a.id,'sequence',a.sequence,'successor_action',p_action,'source_snapshot_id',p_source_snapshot_id,
  'expected_root_revision',p_expected_root_revision,'expected_lineage_revision',p_expected_lineage_revision,'lineage_revision',lr,
  'preview_sha256',p_preview_sha256,'reason_code',p_reason_code,'recorded_at',collect_ops.utc(t),'expires_at',collect_ops.utc(a.expires_at),
  'financial_action',false,'send_action',false,'primary_receipt_retained',true,'carrier_proof',false,'delivery_proven',false);
 insert into collect_receipt_successors.owner_requests values(p_request_id,auth.uid(),sid,'approve_successor',ih,result,t);
 perform public.create_audit_log('notification.successor.approved','sms_notification_outbox',o.id,
  jsonb_build_object('request_id',p_request_id,'approval_id',a.id,'sequence',a.sequence,'lineage_revision',lr,
   'preview_sha256',p_preview_sha256,'source_snapshot_id',p_source_snapshot_id,'reason_code',p_reason_code),auth.uid());
 return result;
 exception when lock_not_available then raise exception 'receipt_successor_source_busy'using errcode='55P03';end$$;
create function collect_receipt_successors.approval_read(p_approval uuid)returns jsonb
language sql stable set search_path=''as $$
 select jsonb_build_object('approval_id',a.id,'outbox_id',a.root_outbox_id,'sequence',a.sequence,'action',a.action,
  'status',case when exists(select 1 from collect_receipt_successors.approval_events e where e.approval_id=a.id and e.event_kind='revoked')then 'revoked'
   when a.expires_at<=clock_timestamp()then 'expired'else 'pending'end,
  'preview',a.candidate-'destination_e164'||jsonb_build_object('recipient_masked','+250***'||right(a.candidate->>'destination_e164',3)),
  'preview_sha256',a.preview_sha256,'reason_code',a.reason_code,'reason',a.reason,'recorded_at',collect_ops.utc(a.recorded_at),
  'expires_at',collect_ops.utc(a.expires_at),'lineage_revision',coalesce((select revision from collect_receipt_successors.lineage_heads where root_outbox_id=a.root_outbox_id),1),
  'events',(select jsonb_agg(jsonb_build_object('event_id',e.id,'revision',e.revision,'event_kind',e.event_kind,
   'request_id',e.request_id,'lineage_revision',e.lineage_revision,'reason',e.reason,'recorded_at',collect_ops.utc(e.recorded_at))order by e.revision)
   from collect_receipt_successors.approval_events e where e.approval_id=a.id))
 from collect_receipt_successors.approvals a where a.id=p_approval
$$;
create function public.admin_get_receipt_successor_v1(p_approval_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare value jsonb;begin
 perform collect_receipt_actions.actor(false);
 if p_approval_id is null then raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 value:=collect_receipt_successors.approval_read(p_approval_id);perform collect_receipt_actions.actor(false);
 return jsonb_build_object('contract_version',1,'scope','rw_receipt_successors','approval_id',p_approval_id,
  'status',case when value is null then 'unavailable'else 'available'end,'approval',value,
  'financial_action',false,'send_action',false,'carrier_proof',false,'delivery_proven',false);
end$$;
create function public.admin_list_receipt_successors_v1(p_outbox_id uuid,p_after bigint default null,p_limit integer default 20)returns jsonb
language plpgsql volatile security definer set search_path=''as $$declare value jsonb;cursor bigint;more boolean;begin
 perform collect_receipt_actions.actor(false);
 if p_outbox_id is null or p_after is not null and p_after not between 1 and 1000000000
  or p_limit is null or p_limit not between 1 and 50 then raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 select jsonb_agg(collect_receipt_successors.approval_read(a.id)order by a.sequence),max(a.sequence)into value,cursor
 from(select *from collect_receipt_successors.approvals where root_outbox_id=p_outbox_id
  and(p_after is null or sequence>p_after)order by sequence limit p_limit)a;
 more:=cursor is not null and exists(select 1 from collect_receipt_successors.approvals where root_outbox_id=p_outbox_id and sequence>cursor);
 perform collect_receipt_actions.actor(false);
 return jsonb_build_object('contract_version',1,'scope','rw_receipt_successors','outbox_id',p_outbox_id,'items',coalesce(value,'[]'::jsonb),
  'has_more',more,'next_after',case when more then cursor end,'financial_action',false,'send_action',false,'carrier_proof',false,'delivery_proven',false);
end$$;
create function public.admin_revoke_receipt_successor_v1(p_request_id uuid,p_approval_id uuid,p_expected_lineage_revision bigint,p_reason text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;a collect_receipt_successors.approvals;prior collect_receipt_successors.owner_requests;
 root uuid;lr bigint;ih text;reason text:=btrim(coalesce(p_reason,''));t timestamptz;result jsonb;begin
 sid:=collect_receipt_actions.actor(true);
 if p_request_id is null or p_approval_id is null or p_expected_lineage_revision is null
  or p_expected_lineage_revision not between 1 and 999999999 or char_length(reason)not between 8 and 500 then
  raise exception 'receipt_successor_input_invalid'using errcode='22023';end if;
 ih:=encode(extensions.digest(jsonb_build_array(p_approval_id,p_expected_lineage_revision,reason)::text,'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-successor-owner:'||p_request_id::text,0));
 select *into prior from collect_receipt_successors.owner_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.action<>'revoke_successor'or prior.input_sha256<>ih then
   raise exception 'receipt_successor_request_conflict'using errcode='22023';end if;
  perform collect_receipt_actions.actor(true);return prior.result;end if;
 select root_outbox_id into root from collect_receipt_successors.approvals where id=p_approval_id;
 perform 1 from collect_receipt_operations.policy where singleton for update;
 perform 1 from collect_hybrid.sms_notification_outbox where id=root for update;
 select *into a from collect_receipt_successors.approvals where id=p_approval_id for share;
 perform collect_receipt_actions.actor(true);
 if a.id is null then raise exception 'receipt_successor_approval_unavailable'using errcode='55000';end if;
 select revision into lr from collect_receipt_successors.lineage_heads where root_outbox_id=root;
 if lr<>p_expected_lineage_revision then raise exception 'receipt_successor_source_changed'using errcode='55000';end if;
 if exists(select 1 from collect_receipt_successors.approval_events where approval_id=a.id and event_kind='revoked')then
  raise exception 'receipt_successor_already_revoked'using errcode='55000';end if;
 -- There are no execution tables or arms in this slice. A later execution
 -- migration must add its grant/arm fence before this service can coexist.
 lr:=collect_receipt_successors.advance(root);perform collect_receipt_actions.actor(true);t:=clock_timestamp();
 insert into collect_receipt_successors.approval_events(approval_id,revision,event_kind,request_id,actor_id,session_id,lineage_revision,reason,recorded_at)
 values(a.id,2,'revoked',p_request_id,auth.uid(),sid,lr,reason,t);
 result:=jsonb_build_object('contract_version',1,'scope','rw_receipt_successors','action','revoke_successor','request_id',p_request_id,
  'outbox_id',root,'approval_id',a.id,'expected_lineage_revision',p_expected_lineage_revision,'lineage_revision',lr,'recorded_at',collect_ops.utc(t),
  'financial_action',false,'send_action',false,'primary_receipt_retained',true,'carrier_proof',false,'delivery_proven',false);
 insert into collect_receipt_successors.owner_requests values(p_request_id,auth.uid(),sid,'revoke_successor',ih,result,t);
 perform public.create_audit_log('notification.successor.revoked','sms_notification_outbox',root,
  jsonb_build_object('request_id',p_request_id,'approval_id',a.id,'lineage_revision',lr),auth.uid());return result;
 exception when lock_not_available then raise exception 'receipt_successor_source_busy'using errcode='55P03';end$$;
revoke all on all functions in schema collect_receipt_successors from public,anon,authenticated,service_role;
revoke all on function public.admin_inspect_receipt_successor_v1(uuid,text,uuid),
 public.admin_approve_receipt_successor_v1(uuid,uuid,text,uuid,bigint,bigint,text,timestamptz,text,text),
 public.admin_revoke_receipt_successor_v1(uuid,uuid,bigint,text),
 public.admin_get_receipt_successor_v1(uuid),public.admin_list_receipt_successors_v1(uuid,bigint,integer)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_inspect_receipt_successor_v1(uuid,text,uuid),
 public.admin_approve_receipt_successor_v1(uuid,uuid,text,uuid,bigint,bigint,text,timestamptz,text,text),
 public.admin_revoke_receipt_successor_v1(uuid,uuid,bigint,text),
 public.admin_get_receipt_successor_v1(uuid),public.admin_list_receipt_successors_v1(uuid,bigint,integer)to authenticated;
commit;
