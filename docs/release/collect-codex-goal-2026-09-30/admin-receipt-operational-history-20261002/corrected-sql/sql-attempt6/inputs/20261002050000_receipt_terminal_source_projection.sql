begin;
select pg_advisory_xact_lock(hashtext('collect-receipt-exception-worker'));
select pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
do $guard$declare expected record;begin
 for expected in select * from(values
 ('public.process_receipt_deferral_exceptions_v1(uuid,integer,timestamp with time zone)','aaf9e9f058c3372281ecd078c864109917890fb80ac9ad0e0148c68b07459348'),
 ('collect_ops.queue_receipt_exception_source()','368e24280a4071f19e619f71438e4334b75d1b8bb534f13ffa0d9207004df8c5'),
 ('collect_receipt_operations.ensure_snapshot(uuid,boolean,boolean)','12912903ceedef3bfe389a0398d69c7e19a109b70cf4f72a57b4e839e2c4bd94'),
 ('collect_ops.receipt_exception_source(text,uuid)','405824c850f281a553361288a8ea846d0d64fe210d2818bd0ed76ffba89ad0ab'),
 ('collect_ops.refresh_source(text,uuid)','e20dbdfdd4774a7666d403206d179f897ee41e0a8fa277d989e59e1f4677fd9d'),
 ('collect_ops.observe(text,uuid,text[],jsonb)','24e2a9b5abbf94005ba802977ad032f75917205bb0e273007d256f369a6674d8'),
 ('collect_receipt_telemetry.publish(collect_receipt_operations.policy,timestamptz,jsonb)','4ffbc1d5f3a87006d96ccf823547b1820d60959d74ee00a807a1fd3a811bc6e0'),
 ('collect_receipt_policy.content_is_valid(collect_hybrid.sms_notification_outbox)','a4ac68e2c39d6c24cfa7e4933065248ff79a4a18a149b737825e19e35cfbb2c5'),
 ('collect_receipt_successors.fence_transport_insert()','c80f0f27f815c002af6ff22851c93d353d53979fff31922fa96ce64f3a18a278'),
 ('collect_receipt_successors.protect_closed_root()','e9574a4c5bfde554ed626a2fc1ddff8c0ed13fd60a000ed5eed51576ab08a8af'),
 ('public.process_exception_escalations_v1(integer)','8a1f53541b91895ea759719d9a1b07a9c17ea6359e5e591c76463540000bef45'),
 ('public.admin_read_exception_escalation_v1(uuid)','9229d7a2c09b292b92ef73cc1cd893731249d7029478790353d4fd48b51d134c'),
 ('collect_ops.protect_escalation()','e62dbf90cbd7105b8d1eb2e8318d14388c769e20153b5f8bc0e469ed94785ddb')
 )v(signature,body_sha256)loop
  if to_regprocedure(expected.signature)is null or(select encode(extensions.digest(prosrc,'sha256'),'hex')from pg_proc
   where oid=to_regprocedure(expected.signature))is distinct from expected.body_sha256 then
   raise exception 'receipt_source_projection_predecessor_drift:%',expected.signature using errcode='55000';end if;
 end loop;
 if(select pg_get_constraintdef(oid)from pg_constraint where conrelid='collect_ops.receipt_exception_work'::regclass and conname='receipt_exception_work_source_kind_check'and convalidated)is distinct from
  $expected$CHECK ((source_kind = ANY (ARRAY['receipt_event'::text, 'receipt_backlog'::text])))$expected$then
  raise exception 'receipt_source_projection_constraint_drift'using errcode='55000';end if;
 if not exists(select 1 from pg_constraint c where c.conrelid='collect_ops.exception_inbox_reads'::regclass and c.contype='f'
  and c.confrelid='collect_ops.exception_inbox_deliveries'::regclass and c.convalidated and c.confdeltype='r'
  and c.conkey=array[(select attnum from pg_attribute where attrelid=c.conrelid and attname='escalation_id')]::smallint[]
  and c.confkey=array[(select attnum from pg_attribute where attrelid=c.confrelid and attname='escalation_id')]::smallint[])
  or not exists(select 1 from pg_constraint c where c.conrelid='collect_ops.exception_inbox_deliveries'::regclass and c.contype='f'
   and c.confrelid='collect_ops.exception_escalations'::regclass and c.convalidated and c.confdeltype='r'
   and c.conkey=array[(select attnum from pg_attribute where attrelid=c.conrelid and attname='escalation_id')]::smallint[]
   and c.confkey=array[(select attnum from pg_attribute where attrelid=c.confrelid and attname='id')]::smallint[])then
  raise exception 'receipt_source_projection_inbox_fk_drift'using errcode='55000';end if;
 if exists(select 1 from pg_class c cross join(values('anon'),('authenticated'),('service_role'))r(name)
  where c.oid in('collect_ops.receipt_exception_work'::regclass,'collect_ops.exception_inbox_deliveries'::regclass,
   'collect_ops.exception_inbox_reads'::regclass,'collect_ops.exception_escalations'::regclass,'collect_ops.exception_workflows'::regclass)
   and(not c.relrowsecurity or has_table_privilege(r.name,c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER,MAINTAIN')
    or has_any_column_privilege(r.name,c.oid,'SELECT,INSERT,UPDATE,REFERENCES')))then
  raise exception 'receipt_source_projection_original_acl_drift'using errcode='55000';end if;
end $guard$;
-- Source-work maintenance only. Original journals, receipts and APIs stay put.
create schema collect_receipt_source_projection;
revoke all on schema collect_receipt_source_projection from public,anon,authenticated,service_role;
create table collect_receipt_source_projection.installations(
 id uuid primary key,contract_version integer not null check(contract_version=1),
 predecessor_sha256 text not null check(predecessor_sha256~'^[0-9a-f]{64}$'),
 recorded_at timestamptz not null check(isfinite(recorded_at)));
create table collect_receipt_source_projection.admissions(
 id uuid primary key,source_kind text not null check(source_kind in('receipt_event','receipt_backlog')),
 source_id uuid not null,work_id uuid references collect_ops.receipt_exception_work(id)on delete restrict,
 installation_id uuid references collect_receipt_source_projection.installations(id)on delete restrict,
 admitted_at timestamptz not null check(isfinite(admitted_at)),
 check((work_id is null)<>(installation_id is null)),unique(id,source_kind,source_id));
create table collect_receipt_source_projection.live(
 source_kind text not null check(source_kind in('receipt_event','receipt_backlog')),source_id uuid not null,
 admission_id uuid not null unique,primary key(source_kind,source_id),
 foreign key(admission_id,source_kind,source_id)references collect_receipt_source_projection.admissions(id,source_kind,source_id)
  on delete restrict deferrable initially deferred);
create table collect_receipt_source_projection.certificates(
 id uuid primary key,admission_id uuid not null unique,source_kind text not null,source_id uuid not null,
 scan_request_id uuid not null references collect_ops.receipt_exception_scans(request_id)on delete restrict deferrable initially deferred,
 work_id uuid not null references collect_ops.receipt_exception_work(id)on delete restrict,
 proof_kind text not null check(proof_kind in('handled_event','handled_backlog','immutable_supersession')),
 event_id uuid references collect_hybrid.receipt_business_events(id)on delete restrict,
 handled_event_id uuid references collect_receipt_operations.handled_events(event_id)on delete restrict,
 backlog_run_id uuid,snapshot_id uuid references collect_hybrid.momo_balance_snapshots(id)on delete restrict,
 superseding_event_id uuid references collect_hybrid.receipt_business_events(id)on delete restrict,
 receipt_id uuid references collect_hybrid.sms_notification_outbox(id)on delete restrict,
 terminal_code text not null check(terminal_code in('RECEIPT_ENQUEUED','RECEIPT_EXISTS','PAYMENT_REVERSED','SOURCE_SUPERSEDED')),
 source_sha256 text not null check(source_sha256~'^[0-9a-f]{64}$'),
 terminal_sha256 text not null check(terminal_sha256~'^[0-9a-f]{64}$'),
 graph_sha256 text not null check(graph_sha256~'^[0-9a-f]{64}$'),
 evidence_sha256 text not null check(evidence_sha256~'^[0-9a-f]{64}$'),
 certified_at timestamptz not null check(isfinite(certified_at)),
 financial_action boolean not null default false check(not financial_action),
 send_action boolean not null default false check(not send_action),
 source_scan_complete boolean not null default false check(not source_scan_complete),
 foreign key(admission_id,source_kind,source_id)references collect_receipt_source_projection.admissions(id,source_kind,source_id)on delete restrict,
 foreign key(backlog_run_id,snapshot_id)references collect_receipt_operations.backlog_results(run_id,snapshot_id)on delete restrict,
 check(((source_kind='receipt_event'and event_id=source_id and snapshot_id is null and backlog_run_id is null)
  or(source_kind='receipt_backlog'and snapshot_id=source_id and event_id is null and handled_event_id is null and superseding_event_id is null))is true),
 check(((proof_kind='handled_event'and handled_event_id=event_id and backlog_run_id is null)
  or(proof_kind='handled_backlog'and backlog_run_id is not null)
  or(proof_kind='immutable_supersession'and superseding_event_id is not null and handled_event_id is null))is true),
 check(terminal_code not in('RECEIPT_ENQUEUED','RECEIPT_EXISTS')or receipt_id is not null));
create index receipt_source_certificate_original on collect_receipt_source_projection.certificates(source_kind,source_id,scan_request_id);
create table collect_receipt_source_projection.certificate_observations(
 certificate_id uuid not null references collect_receipt_source_projection.certificates(id)on delete restrict,
 exception_id uuid not null,revision bigint not null,
 foreign key(exception_id,revision)references collect_ops.exception_observations(exception_id,revision)on delete restrict,
 primary key(certificate_id,exception_id,revision));
create table collect_receipt_source_projection.unread_inbox(
 escalation_id uuid primary key references collect_ops.exception_inbox_deliveries(escalation_id)on delete restrict,
 exception_id uuid not null references collect_ops.exceptions(id)on delete restrict,
 recipient_id uuid not null);
create index receipt_source_unread_exception on collect_receipt_source_projection.unread_inbox(exception_id,escalation_id);
create index receipt_source_open_escalation on collect_ops.exception_escalations(exception_id,state,id)where state in('queued','recipient_unavailable');
create index receipt_exception_pending_source on collect_ops.receipt_exception_work(source_kind,source_id,queued_at,id)where processed_at is null;
create index receipt_telemetry_head_source on collect_receipt_telemetry.alert_heads(source_kind,source_id,id);
create index receipt_telemetry_observation_source on collect_receipt_telemetry.alert_observations(source_kind,source_id,alert_id,revision);

create function collect_receipt_source_projection.immutable()returns trigger
language plpgsql set search_path=''as $$begin
 raise exception 'receipt_source_projection_evidence_immutable'using errcode='55000';end$$;
create function collect_receipt_source_projection.protect_live()returns trigger
language plpgsql set search_path=''as $$begin
 if tg_op='DELETE'and exists(select 1 from collect_receipt_source_projection.certificates c
  where c.admission_id=old.admission_id and c.source_kind=old.source_kind and c.source_id=old.source_id)
 then return old;end if;
 raise exception 'receipt_source_live_certificate_required'using errcode='55000';end$$;
do $$declare t text;begin
 foreach t in array array['installations','admissions','live','certificates','certificate_observations','unread_inbox']loop
  execute format('alter table collect_receipt_source_projection.%I enable row level security',t);
  execute format('revoke all on collect_receipt_source_projection.%I from public,anon,authenticated,service_role',t);
  if t not in('live','unread_inbox')then
   execute format('create trigger retained_projection_evidence before update or delete on collect_receipt_source_projection.%I for each row execute function collect_receipt_source_projection.immutable()',t);
  end if;
  execute format('create trigger retained_projection_truncate before truncate on collect_receipt_source_projection.%I for each statement execute function collect_receipt_source_projection.immutable()',t);
 end loop;end$$;
create trigger certified_live_removal before update or delete on collect_receipt_source_projection.live
 for each row execute function collect_receipt_source_projection.protect_live();
create function collect_receipt_source_projection.protect_unread()returns trigger
language plpgsql set search_path=''as $$begin
 if tg_op='DELETE'and exists(select 1 from collect_ops.exception_inbox_reads r
  where r.escalation_id=old.escalation_id and r.recipient_id=old.recipient_id)then return old;end if;
 raise exception 'receipt_source_original_inbox_read_required'using errcode='55000';end$$;
create trigger original_read_required before update or delete on collect_receipt_source_projection.unread_inbox
 for each row execute function collect_receipt_source_projection.protect_unread();
create function collect_receipt_source_projection.project_inbox()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if tg_table_name='exception_inbox_deliveries'then
  insert into collect_receipt_source_projection.unread_inbox(escalation_id,exception_id,recipient_id)
   select new.escalation_id,e.exception_id,new.recipient_id from collect_ops.exception_escalations e where e.id=new.escalation_id
    and not exists(select 1 from collect_ops.exception_inbox_reads r where r.escalation_id=new.escalation_id and r.recipient_id=new.recipient_id);
 else
  delete from collect_receipt_source_projection.unread_inbox u where u.escalation_id=new.escalation_id and u.recipient_id=new.recipient_id;
 end if;return null;end$$;

create function collect_receipt_source_projection.ensure_work_membership(p_work uuid)returns boolean
language plpgsql volatile security definer set search_path=''as $$
declare w collect_ops.receipt_exception_work;a uuid;begin
 select * into w from collect_ops.receipt_exception_work where id=p_work;
 if w.id is null then raise exception 'receipt_source_work_unavailable'using errcode='22023';end if;
 -- Producers always append original pending work. The existing-live fast path
 -- intentionally does not block financial production. A concurrent retirement
 -- may remove this sampled membership; consuming that exact pending work MUST
 -- call this helper again before refresh. Pending work is never lost.
 if exists(select 1 from collect_receipt_source_projection.live where source_kind=w.source_kind and source_id=w.source_id)then return true;end if;
 if not pg_try_advisory_xact_lock(hashtextextended('collect-receipt-source-admission:'||w.source_kind||':'||w.source_id::text,0))then return false;end if;
 if exists(select 1 from collect_receipt_source_projection.live where source_kind=w.source_kind and source_id=w.source_id)then return true;end if;
 a:=gen_random_uuid();
 insert into collect_receipt_source_projection.live(source_kind,source_id,admission_id)values(w.source_kind,w.source_id,a);
 insert into collect_receipt_source_projection.admissions(id,source_kind,source_id,work_id,admitted_at)
  values(a,w.source_kind,w.source_id,w.id,clock_timestamp());return true;end$$;
create function collect_receipt_source_projection.admit_work()returns trigger
language plpgsql security definer set search_path=''as $$begin
 perform collect_receipt_source_projection.ensure_work_membership(new.id);return null;end$$;

-- Closed, bounded source graph. Every missing/ambiguous required identity keeps
-- the original source live. No mutable policy/contact/cap is terminal evidence.
create function collect_receipt_source_projection.try_retire_source(p_kind text,p_source uuid,p_scan uuid,p_work uuid)returns boolean
language plpgsql volatile security definer set search_path=''as $$
declare e collect_hybrid.receipt_business_events;n collect_hybrid.receipt_business_events;
 h collect_receipt_operations.handled_events;b collect_receipt_operations.backlog_results;
 s collect_hybrid.momo_balance_snapshots;payment public.payments;root collect_hybrid.sms_notification_outbox;
 live collect_receipt_source_projection.live;w collect_ops.receipt_exception_work;
 original_kind text;terminal_code text;receipt uuid;parsed uuid;raw uuid;collection uuid;
 proof_kind text;source_digest text;terminal_digest text;graph_digest text;evidence_digest text;certificate uuid;
 roots uuid[]:='{}';attempts uuid[]:='{}';telemetry uuid[]:='{}';exceptions uuid[]:='{}';
 graph jsonb:='[]';facts jsonb;closures jsonb:='[]';point record;head record;count_value bigint;at timestamptz;
 last_alert uuid;next_alert uuid;seek_count integer;
begin
 if current_setting('transaction_isolation')<>'read committed'then return false;end if;
 -- Private helper is permitted only inside the original, not-yet-published
 -- scan transaction, after its exact original work transition.
 select * into w from collect_ops.receipt_exception_work where id=p_work;
 if w.source_kind is distinct from p_kind or w.source_id is distinct from p_source or w.outcome is distinct from 'refreshed'
  or w.processed_request_id is distinct from p_scan or exists(select 1 from collect_ops.receipt_exception_scans where request_id=p_scan)then return false;end if;
 begin
  if not pg_try_advisory_xact_lock(hashtextextended('collect-receipt-source-admission:'||p_kind||':'||p_source::text,0))
   or not pg_try_advisory_xact_lock(hashtext('collect-receipt-telemetry-sampler'))then raise exception 'receipt_source_held'using errcode='P0002';end if;
  select * into live from collect_receipt_source_projection.live where source_kind=p_kind and source_id=p_source for update nowait;
  if live.admission_id is null then raise exception 'receipt_source_held'using errcode='P0002';end if;
  if p_kind='receipt_event'then
   select * into e from collect_hybrid.receipt_business_events where id=p_source;
   select * into h from collect_receipt_operations.handled_events where event_id=p_source;
   if e.id is null or e.collection_id is null then raise exception 'receipt_source_held'using errcode='P0002';end if;
   collection:=e.collection_id;receipt:=h.receipt_id;terminal_code:=h.code;
   if h.event_id is not null then
    if h.source_version is distinct from e.source_version then raise exception 'receipt_source_held'using errcode='P0002';end if;
    proof_kind:='handled_event';terminal_digest:=encode(extensions.digest(to_jsonb(h)::text,'sha256'),'hex');
   else proof_kind:='immutable_supersession';terminal_code:='SOURCE_SUPERSEDED';end if;
   if terminal_code='SOURCE_SUPERSEDED'then
    select * into n from collect_hybrid.receipt_business_events x where x.source_kind=e.source_kind and x.source_id=e.source_id
     and x.source_version>e.source_version and x.collection_id=e.collection_id order by x.source_version,x.id limit 1;
    if n.id is null or not(exists(select 1 from collect_receipt_source_projection.live l where l.source_kind='receipt_event'and l.source_id=n.id)
     or exists(select 1 from collect_ops.receipt_exception_work x where x.source_kind='receipt_event'and x.source_id=n.id and x.processed_at is null)
     or exists(select 1 from collect_receipt_operations.handled_events x where x.event_id=n.id and x.source_version=n.source_version)
     or exists(select 1 from collect_receipt_source_projection.certificates x where x.source_kind='receipt_event'and x.source_id=n.id))then raise exception 'receipt_source_held'using errcode='P0002';end if;
    if proof_kind='immutable_supersession'then terminal_digest:=encode(extensions.digest(to_jsonb(n)::text,'sha256'),'hex');end if;
   end if;
   source_digest:=encode(extensions.digest(to_jsonb(e)::text,'sha256'),'hex');
   if e.source_kind='payment'then select * into payment from public.payments where id=e.source_id for update nowait;
   elsif e.source_kind='receipt'then
    select * into root from collect_hybrid.sms_notification_outbox where id=e.source_id for update nowait;
    select * into payment from public.payments where id=root.payment_id for update nowait;
   else
    select count(*)into count_value from(select p.id from public.payments p where p.parsed_event_id=e.source_id limit 2)bounded;
    if count_value<>1 then raise exception 'receipt_source_held'using errcode='P0002';end if;
    select * into payment from public.payments p where p.parsed_event_id=e.source_id for update nowait;
   end if;
   if e.payment_id is not null and e.payment_id is distinct from payment.id then raise exception 'receipt_source_held'using errcode='P0002';end if;
  elsif p_kind='receipt_backlog'then
   select * into s from collect_hybrid.momo_balance_snapshots where id=p_source and event_type='receipt';
   select * into b from collect_receipt_operations.backlog_results x where x.snapshot_id=p_source and x.business_handled order by x.recorded_at,x.run_id limit 1;
   if s.id is null or b.snapshot_id is null or b.code not in('RECEIPT_ENQUEUED','RECEIPT_EXISTS','PAYMENT_REVERSED','SOURCE_SUPERSEDED')
    or b.code='SOURCE_SUPERSEDED'then raise exception 'receipt_source_held'using errcode='P0002';end if;
   select * into payment from public.payments where id=s.payment_id for update nowait;
   collection:=s.collection_id;receipt:=b.receipt_id;terminal_code:=b.code;proof_kind:='handled_backlog';
   source_digest:=encode(extensions.digest(to_jsonb(s)::text,'sha256'),'hex');terminal_digest:=encode(extensions.digest(to_jsonb(b)::text,'sha256'),'hex');
  else raise exception 'receipt_source_held'using errcode='P0002';end if;
  if payment.id is null or payment.collection_id is distinct from collection or not collect_ops.payment_scope(payment.id)
   or terminal_code not in('RECEIPT_ENQUEUED','RECEIPT_EXISTS','PAYMENT_REVERSED','SOURCE_SUPERSEDED')then raise exception 'receipt_source_held'using errcode='P0002';end if;
  parsed:=payment.parsed_event_id;
  if parsed is not null then
   perform 1 from public.parsed_payment_events where id=parsed for share nowait;
   select raw_sms_id into raw from public.parsed_payment_events where id=parsed;
   if raw is null then raise exception 'receipt_source_held'using errcode='P0002';end if;
   perform 1 from public.raw_payment_sms where id=raw for share nowait;
  end if;
  graph:=jsonb_build_array(jsonb_build_object('kind',p_kind,'id',p_source),jsonb_build_object('kind','payment','id',payment.id));
  if parsed is not null then graph:=graph||jsonb_build_array(jsonb_build_object('kind','allocation','id',parsed),jsonb_build_object('kind','raw_sms','id',raw));end if;
  -- Payment FOR UPDATE also fences FK admission of a new original root.
  -- Each existing root is the exact shared grant/arm/callback/400 fence.
  select count(*)into count_value from(select o.id from collect_hybrid.sms_notification_outbox o where o.payment_id=payment.id limit 9)bounded;
  if count_value>8 then raise exception 'receipt_source_held'using errcode='P0002';end if;
  for root in select * from collect_hybrid.sms_notification_outbox o where o.payment_id=payment.id order by o.id for update nowait loop
   roots:=array_append(roots,root.id);graph:=graph||jsonb_build_array(jsonb_build_object('kind','receipt','id',root.id));
   if root.collection_id is distinct from collection or root.state in('awaiting_confirmation','send_started','uncertain')
    or exists(select 1 from collect_security.assisted_sms_session_evidence x where x.outbox_id=root.id)
    or exists(select 1 from collect_hybrid.sms_notification_claim_requests x where x.outbox_id=root.id)
    or exists(select 1 from collect_hybrid.sms_notification_confirmations x where x.outbox_id=root.id)
    or exists(select 1 from collect_hybrid.sms_notification_attempts x where x.outbox_id=root.id)then raise exception 'receipt_source_held'using errcode='P0002';end if;
   for point in select a.* from collect_gateway_dispatch.attempts a where a.outbox_id=root.id loop
    attempts:=array_append(attempts,point.id);graph:=graph||jsonb_build_array(jsonb_build_object('kind','gateway','id',point.device_id));
    if cardinality(attempts)>8 or point.state<>'granted'
     or exists(select 1 from collect_gateway_dispatch.arms x where x.attempt_id=point.id)
     or exists(select 1 from collect_gateway_dispatch.callbacks x where x.attempt_id=point.id)
     or not exists(select 1 from collect_receipt_successors.original_closures x where x.root_outbox_id=root.id
      and x.original_attempt_id=point.id and x.reason_code='definitely_not_invoked')then raise exception 'receipt_source_held'using errcode='P0002';end if;
   end loop;
   closures:=closures||coalesce((select jsonb_agg(jsonb_build_object('id',x.id,'sha256',encode(extensions.digest(to_jsonb(x)::text,'sha256'),'hex'))order by x.id)
    from collect_receipt_successors.original_closures x where x.root_outbox_id=root.id),'[]'::jsonb);
  end loop;
  if terminal_code in('RECEIPT_ENQUEUED','RECEIPT_EXISTS')then
   select * into root from collect_hybrid.sms_notification_outbox where id=receipt;
   select * into s from collect_hybrid.momo_balance_snapshots where id=root.snapshot_id;
   if root.id is null or not root.id=any(roots)or s.id is null or s.event_type<>'receipt'
    or root.payment_id is distinct from payment.id or s.payment_id is distinct from payment.id
    or root.collection_id is distinct from collection or s.collection_id is distinct from collection
    or root.member_record_id is distinct from s.member_record_id or root.amount_rwf is distinct from s.delta_rwf
    or root.member_balance_rwf is distinct from s.member_balance_after_rwf or root.group_balance_rwf is distinct from s.group_balance_after_rwf
    or(p_kind='receipt_backlog'and root.snapshot_id is distinct from p_source)
    or(e.snapshot_id is not null and e.snapshot_id is distinct from root.snapshot_id)
    or not collect_receipt_policy.content_is_valid(root)then raise exception 'receipt_source_held'using errcode='P0002';end if;
  elsif terminal_code='PAYMENT_REVERSED'and not exists(select 1 from collect_hybrid.momo_journal_entries j
   where j.payment_id=payment.id and j.entry_type='reversal')then raise exception 'receipt_source_held'using errcode='P0002';end if;
  -- The sampler lock fences new and moved telemetry heads, including history
  -- still referenced by unfinished workflows and escalation/inbox journals.
  -- At most10 source-local keys, each with at most33 alert-ID index seeks.
  -- Seeking beyond the prior alert_id skips arbitrary numeric-history repeats
  -- without DISTINCT/aggregation over that immutable lifetime journal.
  for point in select 'business_event'kind,p_source id where p_kind='receipt_event'
   union all select 'handled_event',p_source where p_kind='receipt_event'
   union all select 'attempt',a from unnest(attempts)a loop
   for next_alert in select a.id from collect_receipt_telemetry.alert_heads a
    where a.source_kind=point.kind and a.source_id=point.id order by a.id limit 33 loop
    if not next_alert=any(telemetry)then telemetry:=array_append(telemetry,next_alert);end if;
    if cardinality(telemetry)>32 then raise exception 'receipt_source_held'using errcode='P0002';end if;
   end loop;
   last_alert:=null;seek_count:=0;
   loop
    select a.alert_id into next_alert from collect_receipt_telemetry.alert_observations a
     where a.source_kind=point.kind and a.source_id=point.id
      and a.alert_id>=coalesce(last_alert,'00000000-0000-0000-0000-000000000000'::uuid)
      and(last_alert is null or a.alert_id>last_alert)order by a.alert_id limit 1;
    exit when next_alert is null;
    seek_count:=seek_count+1;
    if seek_count>33 then raise exception 'receipt_source_held'using errcode='P0002';end if;
    if not next_alert=any(telemetry)then telemetry:=array_append(telemetry,next_alert);end if;
    if cardinality(telemetry)>32 then raise exception 'receipt_source_held'using errcode='P0002';end if;
    last_alert:=next_alert;
   end loop;
  end loop;
  foreach certificate in array telemetry loop graph:=graph||jsonb_build_array(jsonb_build_object('kind','receipt_telemetry','id',certificate));end loop;
  -- Every observer takes this exact advisory source fence before admission of
  -- a new exception head. Locking existing heads alone would miss phantoms.
  for point in select distinct x->>'kind'kind,(x->>'id')::uuid id from jsonb_array_elements(graph)x order by 1,2 loop
   if not pg_try_advisory_xact_lock(hashtextextended('collect-ops-source:'||point.kind||':'||point.id::text,0))then raise exception 'receipt_source_held'using errcode='P0002';end if;
  end loop;
  for point in select distinct x->>'kind'kind,(x->>'id')::uuid id from jsonb_array_elements(graph)x order by 1,2 loop
   for head in select x.id from collect_ops.exceptions x where x.source_kind=point.kind and x.source_id=point.id order by x.reason_code limit 129 loop
    exceptions:=array_append(exceptions,head.id);
    if cardinality(exceptions)>128 then raise exception 'receipt_source_held'using errcode='P0002';end if;
   end loop;
  end loop;
  if exists(select 1 from collect_ops.exceptions x left join collect_ops.exception_workflows f on f.exception_id=x.id
   where x.id=any(exceptions)and(x.active or(f.exception_id is not null and f.resolved_source_revision is distinct from x.revision)))
   or exists(select 1 from collect_ops.exception_escalations x where x.exception_id=any(exceptions)and x.state in('queued','recipient_unavailable'))
   or exists(select 1 from collect_receipt_source_projection.unread_inbox x where x.exception_id=any(exceptions))
   or exists(select 1 from collect_ops.receipt_exception_work x where x.source_kind=p_kind and x.source_id=p_source and x.processed_at is null)
  then raise exception 'receipt_source_held'using errcode='P0002';end if;
  select coalesce(jsonb_agg(jsonb_build_array(x.id,x.revision,x.active,x.source_sha256)order by x.id),'[]')into facts
   from collect_ops.exceptions x where x.id=any(exceptions);
  graph_digest:=encode(extensions.digest(jsonb_build_object('graph',graph,'heads',facts,'roots',roots,'attempts',attempts,'closures',closures,
   'superseding_event',case when n.id is null then null else to_jsonb(n)end)::text,'sha256'),'hex');
  at:=clock_timestamp();certificate:=gen_random_uuid();
  evidence_digest:=encode(extensions.digest(jsonb_build_object('admission',live.admission_id,'source_kind',p_kind,'source_id',p_source,
   'scan',p_scan,'work',p_work,'proof_kind',proof_kind,'code',terminal_code,'source_sha256',source_digest,
   'terminal_sha256',terminal_digest,'graph_sha256',graph_digest,'certified_at',at)::text,'sha256'),'hex');
  insert into collect_receipt_source_projection.certificates(id,admission_id,source_kind,source_id,scan_request_id,work_id,proof_kind,
   event_id,handled_event_id,backlog_run_id,snapshot_id,superseding_event_id,receipt_id,terminal_code,source_sha256,terminal_sha256,graph_sha256,evidence_sha256,certified_at)
  values(certificate,live.admission_id,p_kind,p_source,p_scan,p_work,proof_kind,e.id,h.event_id,b.run_id,
   case when p_kind='receipt_backlog'then p_source end,n.id,receipt,terminal_code,source_digest,terminal_digest,graph_digest,evidence_digest,at);
  insert into collect_receipt_source_projection.certificate_observations(certificate_id,exception_id,revision)
   select certificate,x.id,x.revision from collect_ops.exceptions x where x.id=any(exceptions);
  -- Repeat the pending-work check after publication, while all source/graph
  -- fences are still held. A producer fast path can race this sample; its exact
  -- original pending row remains and MUST re-admit before the next refresh.
  if exists(select 1 from collect_ops.receipt_exception_work x where x.source_kind=p_kind and x.source_id=p_source and x.processed_at is null)
   then raise exception 'receipt_source_held'using errcode='P0002';end if;
  delete from collect_receipt_source_projection.live x where x.source_kind=p_kind and x.source_id=p_source and x.admission_id=live.admission_id;
  return true;
 exception when no_data_found or lock_not_available or invalid_parameter_value or insufficient_privilege then return false;end;
end$$;

-- Scanner before original producer publication locks; original source-table
-- locks precede work-table installation to retain producer source→work order.
lock table collect_receipt_operations.event_deferrals,collect_receipt_operations.handled_events,
 collect_receipt_operations.backlog_results,collect_ops.receipt_backlog_budget_deferrals in share row exclusive mode;
lock table collect_ops.receipt_exception_work in share row exclusive mode;
-- Reader INSERT takes the child reads table before its delivery FK check.
-- Installation follows that same order; SELECTs inside delivery producers do
-- not conflict with these publication locks. No original row is modified.
lock table collect_ops.exception_inbox_reads,collect_ops.exception_inbox_deliveries in share row exclusive mode;
create trigger receipt_source_inbox_delivery after insert on collect_ops.exception_inbox_deliveries
 for each row execute function collect_receipt_source_projection.project_inbox();
create trigger receipt_source_inbox_read after insert on collect_ops.exception_inbox_reads
 for each row execute function collect_receipt_source_projection.project_inbox();
insert into collect_receipt_source_projection.unread_inbox(escalation_id,exception_id,recipient_id)
 select d.escalation_id,e.exception_id,d.recipient_id from collect_ops.exception_inbox_deliveries d join collect_ops.exception_escalations e on e.id=d.escalation_id
  where not exists(select 1 from collect_ops.exception_inbox_reads r where r.escalation_id=d.escalation_id and r.recipient_id=d.recipient_id);
create trigger receipt_source_projection_admission after insert on collect_ops.receipt_exception_work
 for each row execute function collect_receipt_source_projection.admit_work();
do $$declare installation uuid:=gen_random_uuid();source record;a uuid;begin
 insert into collect_receipt_source_projection.installations values(installation,1,'aaf9e9f058c3372281ecd078c864109917890fb80ac9ad0e0148c68b07459348',clock_timestamp());
 for source in select 'receipt_event'kind,d.event_id id from collect_receipt_operations.event_deferrals d
  union select 'receipt_backlog',b.snapshot_id from collect_ops.receipt_backlog_sweep_sources b
  union select w.source_kind,w.source_id from collect_ops.receipt_exception_work w where w.processed_at is null loop
  a:=gen_random_uuid();insert into collect_receipt_source_projection.admissions(id,source_kind,source_id,installation_id,admitted_at)
   values(a,source.kind,source.id,installation,clock_timestamp());
  insert into collect_receipt_source_projection.live values(source.kind,source.id,a);
 end loop;end$$;
revoke all on all functions in schema collect_receipt_source_projection from public,anon,authenticated,service_role;

create or replace function public.process_receipt_deferral_exceptions_v1(p_request_id uuid,p_limit integer,p_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare prior collect_ops.receipt_exception_scans;p collect_ops.receipt_exception_progress;
 w collect_ops.receipt_exception_work;source uuid;before_heads jsonb;t timestamptz;result jsonb;
 seeded integer:=0;processed integer:=0;refused integer:=0;added integer:=0;activated integer:=0;cleared integer:=0;unchanged integer:=0;
 changed integer;act integer;closed integer;status text;work_outcome text;begin
 perform collect_ops.receipt_exception_service();
 if p_request_id is null or p_limit is null or p_limit not between 1 and 25 or p_expires_at is null or not isfinite(p_expires_at)
  or p_expires_at>clock_timestamp()+interval '120 seconds'then raise exception 'receipt_exception_scan_invalid'using errcode='22023';end if;
 if p_expires_at<=clock_timestamp()then raise exception 'receipt_exception_scan_expired'using errcode='55000';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-exception-scan:'||p_request_id::text,0));
 select * into prior from collect_ops.receipt_exception_scans where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.request_limit<>p_limit or prior.expires_at<>p_expires_at then raise exception 'receipt_exception_scan_conflict'using errcode='22023';end if;return prior.result;end if;
 if not pg_try_advisory_xact_lock(hashtext('collect-receipt-exception-worker'))then status:='busy';
 else
  -- Existing assignment/escalation takes this lock before any source lock.
  perform pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
  if p_expires_at<=clock_timestamp()then raise exception 'receipt_exception_scan_expired'using errcode='55000';end if;
  select * into p from collect_ops.receipt_exception_progress where singleton for update;
  -- This is a bounded, repeating source-local UUID sweep, never a commit-order
  -- watermark or a claim that all sources have been observed. New transitions
  -- also append independent work, including UUIDs behind the sweep cursor.
  if p.phase='receipt_event'then
   for source in select l.source_id from collect_receipt_source_projection.live l
    where l.source_kind='receipt_event'and l.source_id>=coalesce(p.last_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and(p.last_id is null or l.source_id>p.last_id)order by l.source_id limit p_limit loop
    insert into collect_ops.receipt_exception_work(source_kind,source_id,origin)values('receipt_event',source,'sweep');seeded:=seeded+1;p.last_id:=source;
   end loop;
   if seeded=0 then p.phase:='receipt_backlog';p.last_id:=null;end if;
  else
   for source in select l.source_id from collect_receipt_source_projection.live l
    where l.source_kind='receipt_backlog'and l.source_id>=coalesce(p.last_id,'00000000-0000-0000-0000-000000000000'::uuid)
     and(p.last_id is null or l.source_id>p.last_id)order by l.source_id limit p_limit loop
    insert into collect_ops.receipt_exception_work(source_kind,source_id,origin)values('receipt_backlog',source,'sweep');seeded:=seeded+1;p.last_id:=source;
   end loop;
   if seeded=0 then
    if p.epoch=1000000000 then raise exception 'receipt_exception_epoch_exhausted'using errcode='55000';end if;
    p.phase:='receipt_event';p.last_id:=null;p.epoch:=p.epoch+1;
   end if;
  end if;
  for w in select * from collect_ops.receipt_exception_work where processed_at is null order by queued_at,id limit p_limit for update skip locked loop
   -- Pending work is independent of the sweep cursor and re-establishes exact
   -- membership after any producer/retirement fast-path race. A contended
   -- publication leaves this original row pending for a later bounded scan.
   if not collect_receipt_source_projection.ensure_work_membership(w.id)then continue;end if;
   work_outcome:='refreshed';begin
    perform pg_advisory_xact_lock(hashtextextended('collect-ops-source:'||w.source_kind||':'||w.source_id::text,0));
    select coalesce(jsonb_object_agg(e.id::text,e.revision),'{}'::jsonb)into before_heads from collect_ops.exceptions e where e.source_kind=w.source_kind and e.source_id=w.source_id;
    perform collect_ops.refresh_source(w.source_kind,w.source_id);
    select count(*),count(*)filter(where o.active),count(*)filter(where not o.active)into changed,act,closed
     from collect_ops.exception_observations o join collect_ops.exceptions e on e.id=o.exception_id
     where e.source_kind=w.source_kind and e.source_id=w.source_id and o.revision>coalesce((before_heads->>e.id::text)::bigint,0);
    insert into collect_ops.receipt_exception_scan_observations(request_id,exception_id,revision)
     select p_request_id,o.exception_id,o.revision from collect_ops.exception_observations o join collect_ops.exceptions e on e.id=o.exception_id
      where e.source_kind=w.source_kind and e.source_id=w.source_id and o.revision>coalesce((before_heads->>e.id::text)::bigint,0);
    added:=added+changed;activated:=activated+act;cleared:=cleared+closed;if changed=0 then unchanged:=unchanged+1;end if;
   exception when insufficient_privilege then
    -- An unavailable or scope-refused source cannot create/clear evidence.
    -- Retain the failed refresh attempt and count it without starving other
    -- work or interpreting refusal as business/delivery acknowledgement.
    refused:=refused+1;work_outcome:='scope_refused';
   when invalid_parameter_value then refused:=refused+1;work_outcome:='source_unavailable';
   end;
   if p_expires_at<=clock_timestamp()then raise exception 'receipt_exception_scan_expired'using errcode='55000';end if;
   update collect_ops.receipt_exception_work set processed_at=clock_timestamp(),outcome=work_outcome,processed_request_id=p_request_id where id=w.id;processed:=processed+1;
   if work_outcome='refreshed'then
    perform collect_receipt_source_projection.try_retire_source(w.source_kind,w.source_id,p_request_id,w.id);
   end if;
  end loop;
  update collect_ops.receipt_exception_progress set epoch=p.epoch,phase=p.phase,last_id=p.last_id,last_scan_at=clock_timestamp(),last_request_id=p_request_id where singleton;
  status:='processed';
 end if;
 t:=clock_timestamp();if p_expires_at<=t then raise exception 'receipt_exception_scan_expired'using errcode='55000';end if;
 select * into p from collect_ops.receipt_exception_progress where singleton;
 result:=jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),'expires_at',collect_ops.utc(p_expires_at),
  'status',status,'seeded',seeded,'processed',processed,'refused',refused,'observations_added',added,'activated',activated,'cleared',cleared,'unchanged',unchanged,
  'pending',(select count(*)from collect_ops.receipt_exception_work where processed_at is null),'scan_epoch',p.epoch,'scan_phase',p.phase,
  'source_scan_complete',false,'financial_action',false,'send_action',false);
 insert into collect_ops.receipt_exception_scans values(p_request_id,p_limit,p_expires_at,t,result);return result;end$$;
notify pgrst,'reload schema';
commit;
