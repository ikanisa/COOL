begin;
-- Ordinary-owner, additive source-contention maintenance. The receipt worker
-- records a bounded durable deferral and leaves business work unhandled.
select pg_advisory_xact_lock(hashtext('collect-receipt-exception-worker'));
lock table collect_ops.exceptions in share row exclusive mode;
do $guard$ declare expected record;oid_value oid;actual_constraint text;begin
 for expected in select * from(values
 ('collect_receipt_operations.ensure_snapshot(uuid,boolean,boolean)','e0caafdfd15bf90a5c91af49f6394432aacf4d48c083ee731e601dcc883021ea'),
 ('collect_ops.receipt_exception_source(text,uuid)','e5fa8846cd39550b3f5a4ef51a1e3409a149304a09abd84cb007fc543ec86c3a')
 )v(signature,body_sha256)loop
  oid_value:=to_regprocedure(expected.signature);
  if oid_value is null or (select encode(extensions.digest(prosrc,'sha256'),'hex')from pg_proc where oid=oid_value)
   is distinct from expected.body_sha256 then
   raise exception 'receipt_source_busy_predecessor_drift:%',expected.signature using errcode='55000';end if;
 end loop;
 select pg_get_constraintdef(oid)into actual_constraint from pg_constraint
 where conrelid='collect_ops.exceptions'::regclass and conname='exceptions_reason_code_check'
  and contype='c'and convalidated and not connoinherit;
 if actual_constraint is distinct from $expected$CHECK ((reason_code = ANY (ARRAY['PARSING_FAILED'::text, 'ALLOCATION_REVIEW'::text, 'VERIFICATION_PENDING'::text, 'VERIFICATION_REJECTED'::text, 'VERIFICATION_CONFLICT'::text, 'CONTACT_MISSING'::text, 'SEND_UNCERTAIN'::text, 'SEND_FAILED_NO_SEND'::text, 'RECEIPT_SUPPRESSED'::text, 'GATEWAY_UNOBSERVED'::text, 'GATEWAY_STALE'::text, 'GATEWAY_SMS_PERMISSION'::text, 'GATEWAY_NETWORK'::text, 'GATEWAY_TELEPHONY'::text, 'GATEWAY_SIM'::text, 'RECEIPT_OPERATION_SOURCE_CHANGED'::text, 'RECEIPT_OPERATION_PAYMENT_NOT_POSTED'::text, 'RECEIPT_OPERATION_SNAPSHOT_MISSING'::text, 'RECEIPT_OPERATION_RECIPIENT_INELIGIBLE'::text, 'RECEIPT_OPERATION_POLICY_DISABLED'::text, 'RECEIPT_OPERATION_CONSENT_MISSING'::text, 'RECEIPT_OPERATION_CONTACT_MISSING'::text, 'RECEIPT_OPERATION_CONTACT_HISTORY_UNPROVEN'::text, 'RECEIPT_OPERATION_POLICY_HISTORY_UNPROVEN'::text, 'RECEIPT_OPERATION_CONSENT_HISTORY_UNPROVEN'::text, 'RECEIPT_OPERATION_CATCHUP_DISABLED'::text, 'RECEIPT_OPERATION_CATCHUP_WINDOW_EXCEEDED'::text, 'RECEIPT_OPERATION_CONTENT_REFUSED'::text, 'RECEIPT_OPERATION_LEGACY_CONTENT_REVIEW_REQUIRED'::text, 'RECEIPT_OPERATION_QUOTA_EXHAUSTED'::text])))$expected$then
  raise exception 'receipt_source_busy_constraint_drift'using errcode='55000';end if;
end $guard$;
alter table collect_ops.exceptions drop constraint exceptions_reason_code_check;
alter table collect_ops.exceptions add constraint exceptions_reason_code_check
 check(reason_code in('PARSING_FAILED','ALLOCATION_REVIEW','VERIFICATION_PENDING','VERIFICATION_REJECTED','VERIFICATION_CONFLICT','CONTACT_MISSING','SEND_UNCERTAIN','SEND_FAILED_NO_SEND','RECEIPT_SUPPRESSED','GATEWAY_UNOBSERVED','GATEWAY_STALE','GATEWAY_SMS_PERMISSION','GATEWAY_NETWORK','GATEWAY_TELEPHONY','GATEWAY_SIM','RECEIPT_OPERATION_SOURCE_CHANGED','RECEIPT_OPERATION_PAYMENT_NOT_POSTED','RECEIPT_OPERATION_SNAPSHOT_MISSING','RECEIPT_OPERATION_RECIPIENT_INELIGIBLE','RECEIPT_OPERATION_POLICY_DISABLED','RECEIPT_OPERATION_CONSENT_MISSING','RECEIPT_OPERATION_CONTACT_MISSING','RECEIPT_OPERATION_CONTACT_HISTORY_UNPROVEN','RECEIPT_OPERATION_POLICY_HISTORY_UNPROVEN','RECEIPT_OPERATION_CONSENT_HISTORY_UNPROVEN','RECEIPT_OPERATION_CATCHUP_DISABLED','RECEIPT_OPERATION_CATCHUP_WINDOW_EXCEEDED','RECEIPT_OPERATION_CONTENT_REFUSED','RECEIPT_OPERATION_LEGACY_CONTENT_REVIEW_REQUIRED','RECEIPT_OPERATION_QUOTA_EXHAUSTED','RECEIPT_OPERATION_SOURCE_BUSY'));

create or replace function collect_receipt_operations.ensure_snapshot(p_snapshot uuid,p_catchup boolean,p_commit boolean default true)
returns jsonb language plpgsql set search_path=''as $$
declare s collect_hybrid.momo_balance_snapshots;p public.payments;o collect_hybrid.sms_notification_outbox;
 policy collect_hybrid.sms_receipt_policies;consent collect_hybrid.sms_receipt_member_consents;identity collect_hybrid.member_momo_identities;
 settings collect_receipt_operations.policy;message text;ref text;job_id uuid;code text;begin
 select * into s from collect_hybrid.momo_balance_snapshots where id=p_snapshot and event_type='receipt';
 if s.id is null then return jsonb_build_object('ok',false,'code','SNAPSHOT_MISSING','business_handled',false,'receipt_id',null);end if;
 -- A caught subtransaction releases any earlier row locks on contention.
 -- No receipt, proof or handling acknowledgement is written on SOURCE_BUSY.
 -- Successful locks still fence posting, reversal, membership and policy
 -- until the caller durably commits its immutable receipt and evidence.
 begin
 select * into p from public.payments where id=s.payment_id for update nowait;
 select * into o from collect_hybrid.sms_notification_outbox where payment_id=p.id and template_key='buri_munsi.payment_received'for update nowait;
 if o.id is not null then
  code:=case when o.template_version=2 and collect_receipt_policy.content_is_valid(o)then 'RECEIPT_EXISTS'else 'LEGACY_CONTENT_REVIEW_REQUIRED'end;
  return jsonb_build_object('ok',code='RECEIPT_EXISTS','code',code,'business_handled',code='RECEIPT_EXISTS','receipt_id',o.id);end if;
 if p.status='reversed'then return jsonb_build_object('ok',true,'code','PAYMENT_REVERSED','business_handled',true,'receipt_id',null);end if;
 if p.status is distinct from 'posted'then return jsonb_build_object('ok',false,'code','PAYMENT_NOT_POSTED','business_handled',false,'receipt_id',null);end if;
 perform 1 from public.collections where id=s.collection_id for share nowait;
 perform 1 from collect_hybrid.member_records where id=s.member_record_id for share nowait;
 perform 1 from public.collection_members where collection_id=s.collection_id and member_record_id=s.member_record_id for share nowait;
 if not collect_receipt_policy.snapshot_is_eligible(s)then return jsonb_build_object('ok',false,'code','RECIPIENT_INELIGIBLE','business_handled',false,'receipt_id',null);end if;
 select * into policy from collect_hybrid.sms_receipt_policies where collection_id=s.collection_id for share nowait;
 select * into consent from collect_hybrid.sms_receipt_member_consents where member_record_id=s.member_record_id for share nowait;
 select * into identity from collect_hybrid.member_momo_identities where member_id=s.member_record_id for share nowait;
 select * into settings from collect_receipt_operations.policy where singleton;
 exception when lock_not_available then
  return jsonb_build_object('ok',false,'code','SOURCE_BUSY','business_handled',false,'receipt_id',null);
 end;
 code:=case when policy.collection_id is null or not policy.enabled then 'POLICY_DISABLED'
  when consent.member_record_id is null or not consent.enabled then 'CONSENT_MISSING'
  when identity.member_id is null then 'CONTACT_MISSING'
  when p_catchup and not settings.catchup_enabled then 'CATCHUP_DISABLED'
  when s.captured_at<clock_timestamp()-make_interval(hours=>settings.catchup_hours)then 'CATCHUP_WINDOW_EXCEEDED'
  when p_catchup and(identity.revision<>1 or identity.created_at>s.captured_at)then 'CONTACT_HISTORY_UNPROVEN'
  when p_catchup and policy.updated_at>s.captured_at then 'POLICY_HISTORY_UNPROVEN'
  when p_catchup and consent.recorded_at>s.captured_at then 'CONSENT_HISTORY_UNPROVEN'else null end;
 if code is not null then return jsonb_build_object('ok',false,'code',code,'business_handled',false,'receipt_id',null);end if;
 ref:=btrim(coalesce(p.transaction_id,''));
 if ref!~'^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$'then return jsonb_build_object('ok',false,'code','CONTENT_REFUSED','business_handled',false,'receipt_id',null);end if;
 message:=collect_receipt_policy.render_v2(p.amount_rwf,s.member_balance_after_rwf,s.captured_at,ref,policy.receipt_language);
 if not p_commit then return jsonb_build_object('ok',false,'code','DRY_RUN_ELIGIBLE','business_handled',false,'receipt_id',null);end if;
 insert into collect_hybrid.sms_notification_outbox(payment_id,snapshot_id,collection_id,member_record_id,destination_e164,destination_sha256,destination_revision,policy_revision,consent_revision,
 template_key,template_version,amount_rwf,member_balance_rwf,group_balance_rwf,reference,message_body,body_sha256,state)
 values(p.id,s.id,s.collection_id,s.member_record_id,identity.momo_number,encode(extensions.digest(identity.momo_number,'sha256'),'hex'),identity.revision,policy.revision,consent.revision,
 'buri_munsi.payment_received',2,p.amount_rwf,s.member_balance_after_rwf,s.group_balance_after_rwf,ref,message,encode(extensions.digest(message,'sha256'),'hex'),'queued')
 on conflict(payment_id,template_key)do nothing returning id into job_id;
 if job_id is null then select id into job_id from collect_hybrid.sms_notification_outbox where payment_id=p.id and template_key='buri_munsi.payment_received';end if;
 insert into collect_receipt_policy.content_evidence values(job_id,2,policy.receipt_language,s.captured_at,encode(extensions.digest(message,'sha256'),'hex'))on conflict(outbox_id)do nothing;
 return jsonb_build_object('ok',true,'code','RECEIPT_ENQUEUED','business_handled',true,'receipt_id',job_id);end$$;

create or replace function collect_ops.receipt_exception_source(p_kind text,p_source uuid)returns jsonb
language plpgsql volatile set search_path=''as $$
declare e collect_hybrid.receipt_business_events;s collect_hybrid.momo_balance_snapshots;
 h collect_receipt_operations.handled_events;handled_backlog collect_receipt_operations.backlog_results;
 original text;code text;disposition text;payment uuid;receipt uuid;version bigint;kind text;business boolean:=false;inspected jsonb;
 signature jsonb;begin
 if p_kind='receipt_event'then
  select * into e from collect_hybrid.receipt_business_events where id=p_source;
  if e.id is null or e.collection_id is null then raise exception 'receipt_exception_source_unavailable'using errcode='22023';end if;
  payment:=e.payment_id;
  if payment is null and e.source_kind='allocation'then select p.id into payment from public.payments p where p.parsed_event_id=e.source_id and p.collection_id=e.collection_id;end if;
  if payment is null and e.source_kind='receipt'then select o.payment_id into payment from collect_hybrid.sms_notification_outbox o where o.id=e.source_id;end if;
  if payment is null then
   if e.source_kind<>'allocation'or not exists(select 1 from public.parsed_payment_events x where x.id=e.source_id and x.collection_id=e.collection_id and collect_security.rwanda_sms_scope(x.raw_sms_id))then
    raise exception 'receipt_exception_source_scope_refused'using errcode='42501';end if;
  elsif not collect_ops.payment_scope(payment)then raise exception 'receipt_exception_source_scope_refused'using errcode='42501';end if;
  version:=e.source_version;kind:=e.event_kind;
  select d.code into original from collect_receipt_operations.event_deferrals d where d.event_id=e.id;
  select * into h from collect_receipt_operations.handled_events where event_id=e.id;
  if h.event_id is not null then code:=h.code;receipt:=h.receipt_id;business:=true;disposition:='durably_handled';
  elsif exists(select 1 from collect_hybrid.receipt_business_event_heads head join collect_hybrid.receipt_business_events newer
   on newer.source_kind=head.source_kind and newer.source_id=head.source_id and newer.source_version=head.version
   where head.source_kind=e.source_kind and head.source_id=e.source_id and head.version>e.source_version)then
   code:='SOURCE_SUPERSEDED';disposition:='source_superseded';
  elsif original is null then disposition:='current_blocker_cleared';
  elsif original='QUOTA_EXHAUSTED'and not collect_ops.receipt_exception_quota_available(p_kind,p_source)then code:=original;disposition:='deferred';
  else
   select * into s from collect_hybrid.momo_balance_snapshots where payment_id=payment and event_type='receipt'order by captured_at,id limit 1;
   inspected:=collect_receipt_operations.ensure_snapshot(s.id,true,false);code:=inspected->>'code';receipt:=(inspected->>'receipt_id')::uuid;
  end if;
 elsif p_kind='receipt_backlog'then
  select * into s from collect_hybrid.momo_balance_snapshots where id=p_source and event_type='receipt';
  if s.id is null then raise exception 'receipt_exception_source_unavailable'using errcode='22023';end if;
  if not collect_ops.payment_scope(s.payment_id)then raise exception 'receipt_exception_source_scope_refused'using errcode='42501';end if;
  select x.code into original from(
   (select b.code,b.recorded_at,b.run_id from collect_receipt_operations.backlog_results b where b.snapshot_id=s.id and not b.business_handled order by b.recorded_at desc,b.run_id desc limit 1)
   union all(select 'QUOTA_EXHAUSTED',b.recorded_at,b.run_id from collect_ops.receipt_backlog_budget_deferrals b where b.snapshot_id=s.id order by b.recorded_at desc,b.run_id desc limit 1))x order by x.recorded_at desc,x.run_id desc limit 1;
  select * into handled_backlog from collect_receipt_operations.backlog_results x where x.snapshot_id=s.id and x.business_handled order by x.recorded_at,x.run_id limit 1;
  if handled_backlog.snapshot_id is not null then code:=handled_backlog.code;receipt:=handled_backlog.receipt_id;business:=true;disposition:='durably_handled';
  elsif original is null then disposition:='current_blocker_cleared';
  elsif original='QUOTA_EXHAUSTED'and not collect_ops.receipt_exception_quota_available(p_kind,p_source)then code:=original;disposition:='deferred';
  else inspected:=collect_receipt_operations.ensure_snapshot(s.id,true,false);code:=inspected->>'code';receipt:=(inspected->>'receipt_id')::uuid;end if;
 else raise exception 'receipt_exception_source_invalid'using errcode='22023';end if;
 if disposition is null then disposition:=case when code in('RECEIPT_EXISTS','PAYMENT_REVERSED','DRY_RUN_ELIGIBLE')then 'current_blocker_cleared'else 'deferred'end;end if;
 if disposition='deferred'and code not in('SOURCE_CHANGED','PAYMENT_NOT_POSTED','SNAPSHOT_MISSING','RECIPIENT_INELIGIBLE','POLICY_DISABLED',
  'CONSENT_MISSING','CONTACT_MISSING','CONTACT_HISTORY_UNPROVEN','POLICY_HISTORY_UNPROVEN','CONSENT_HISTORY_UNPROVEN','CATCHUP_DISABLED',
  'CATCHUP_WINDOW_EXCEEDED','CONTENT_REFUSED','LEGACY_CONTENT_REVIEW_REQUIRED','QUOTA_EXHAUSTED','SOURCE_BUSY')then
  raise exception 'receipt_exception_unknown_deferral'using errcode='55000';end if;
 signature:=jsonb_build_array(version,original,code,disposition,business,receipt,
  (select policy.revision from collect_hybrid.sms_receipt_policies policy where policy.collection_id=coalesce(e.collection_id,s.collection_id)),
  (select consent.revision from collect_hybrid.sms_receipt_member_consents consent where consent.member_record_id=coalesce(e.member_record_id,s.member_record_id)),
  (select identity.revision from collect_hybrid.member_momo_identities identity where identity.member_id=coalesce(e.member_record_id,s.member_record_id)),
  (select jsonb_build_array(p.catchup_enabled,p.catchup_hours)from collect_receipt_operations.policy p where singleton));
 return jsonb_build_object('source_version',version,'event_kind',kind,'original_code',original,'current_code',code,
  'disposition',disposition,'business_handled',business,'receipt_id',receipt,'signature',signature);end$$;
commit;
