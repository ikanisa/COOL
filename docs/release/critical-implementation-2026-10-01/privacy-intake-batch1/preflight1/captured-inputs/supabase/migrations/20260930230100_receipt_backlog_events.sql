begin;

-- Foundation only: committed UUID events and human monitoring acknowledgements.
-- No model payment authority, scheduler, carrier sender or historical enqueue.
create table collect_hybrid.receipt_business_event_heads (
  source_kind text not null check (source_kind in ('payment','allocation','receipt')),
  source_id uuid not null,
  version bigint not null check (version between 1 and 1000000000),
  signature jsonb not null,
  primary key(source_kind,source_id)
);
create table collect_hybrid.receipt_business_events (
  id uuid primary key default gen_random_uuid(),
  source_kind text not null check (source_kind in ('payment','allocation','receipt')),
  source_id uuid not null,
  source_version bigint not null check (source_version between 1 and 1000000000),
  event_kind text not null check (event_kind in ('payment_posted','payment_reversed',
    'allocation_changed','receipt_created','receipt_failed_no_send','receipt_uncertain','receipt_suppressed')),
  collection_id uuid,
  payment_id uuid,
  member_record_id uuid,
  snapshot_id uuid,
  outbox_id uuid,
  source_state text not null check (source_state in ('posted','reversed','unallocated',
    'allocated','ambiguous','needs_review','ignored','queued','awaiting_confirmation',
    'send_started','observed_sent','failed_no_send','uncertain','suppressed')),
  created_at timestamptz not null default clock_timestamp() check (isfinite(created_at)),
  unique(source_kind,source_id,source_version)
);
create index receipt_business_events_scan_idx
  on collect_hybrid.receipt_business_events(created_at,id);
create table collect_hybrid.receipt_monitor_consumers (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null unique,
  scope text not null default 'collect_platform' check (scope='collect_platform'),
  purpose text not null default 'manual_receipt_monitor' check (purpose='manual_receipt_monitor'),
  created_session_id uuid not null,
  created_at timestamptz not null default clock_timestamp()
);
create table collect_hybrid.receipt_monitor_acknowledgements (
  request_id uuid primary key,
  consumer_id uuid not null references collect_hybrid.receipt_monitor_consumers(id),
  event_id uuid not null references collect_hybrid.receipt_business_events(id),
  actor_id uuid not null,
  session_id uuid not null,
  outcome text not null check (outcome in ('observed','deferred')),
  reason_code text not null check (reason_code in ('monitoring_only','review_required',
    'policy_pending','dispatch_paused','source_changed')),
  acknowledged_at timestamptz not null default clock_timestamp()
);
create table collect_hybrid.receipt_monitor_observed_events (
  consumer_id uuid not null references collect_hybrid.receipt_monitor_consumers(id),
  event_id uuid not null references collect_hybrid.receipt_business_events(id),
  acknowledgement_id uuid not null unique references collect_hybrid.receipt_monitor_acknowledgements(request_id),
  primary key(consumer_id,event_id)
);
create index receipt_monitor_ack_event_idx
  on collect_hybrid.receipt_monitor_acknowledgements(consumer_id,event_id,acknowledged_at desc);
alter table collect_hybrid.receipt_business_event_heads enable row level security;
alter table collect_hybrid.receipt_business_events enable row level security;
alter table collect_hybrid.receipt_monitor_consumers enable row level security;
alter table collect_hybrid.receipt_monitor_acknowledgements enable row level security;
alter table collect_hybrid.receipt_monitor_observed_events enable row level security;
revoke all on collect_hybrid.receipt_business_event_heads,collect_hybrid.receipt_business_events,
  collect_hybrid.receipt_monitor_consumers,collect_hybrid.receipt_monitor_acknowledgements,
  collect_hybrid.receipt_monitor_observed_events from public,anon,authenticated,service_role;

create function collect_hybrid.guard_receipt_event_evidence() returns trigger
language plpgsql security definer set search_path='' as $$
begin raise exception 'receipt_event_evidence_immutable' using errcode='55000';end $$;
create trigger receipt_event_immutable before update or delete on collect_hybrid.receipt_business_events
  for each row execute function collect_hybrid.guard_receipt_event_evidence();
create trigger receipt_consumer_immutable before update or delete on collect_hybrid.receipt_monitor_consumers
  for each row execute function collect_hybrid.guard_receipt_event_evidence();
create trigger receipt_ack_immutable before update or delete on collect_hybrid.receipt_monitor_acknowledgements
  for each row execute function collect_hybrid.guard_receipt_event_evidence();
create trigger receipt_observed_immutable before update or delete on collect_hybrid.receipt_monitor_observed_events
  for each row execute function collect_hybrid.guard_receipt_event_evidence();

create function collect_hybrid.emit_receipt_business_event(p_source_kind text,p_source_id uuid,
  p_kind text,p_collection uuid,p_payment uuid,p_member uuid,p_snapshot uuid,p_outbox uuid,p_state text)
returns void language plpgsql security definer set search_path='' as $$
declare v bigint; signature jsonb;
begin
  signature:=jsonb_build_array(p_kind,p_collection,p_payment,p_member,p_snapshot,p_outbox,p_state);
  -- A physical row update serializes concurrent transitions. Its version is
  -- source-local identity only, never a commit-order watermark.
  insert into collect_hybrid.receipt_business_event_heads(source_kind,source_id,version,signature)
    values(p_source_kind,p_source_id,1,signature)
  on conflict(source_kind,source_id) do update
    set version=receipt_business_event_heads.version+1,signature=excluded.signature
    where receipt_business_event_heads.signature is distinct from excluded.signature
  returning version into v;
  if v is null then return;end if;
  insert into collect_hybrid.receipt_business_events(source_kind,source_id,source_version,event_kind,
    collection_id,payment_id,member_record_id,snapshot_id,outbox_id,source_state)
    values(p_source_kind,p_source_id,v,p_kind,p_collection,p_payment,p_member,p_snapshot,p_outbox,p_state);
end $$;

create function collect_hybrid.capture_receipt_payment_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.status in ('posted','reversed') and (tg_op='INSERT' or new.status is distinct from old.status) then
    perform collect_hybrid.emit_receipt_business_event('payment',new.id,
      case when new.status='posted' then 'payment_posted' else 'payment_reversed' end,
      new.collection_id,new.id,new.member_record_id,null,null,new.status);
  end if;
  return new;
end $$;
create trigger zzz_receipt_payment_event after insert or update of status on public.payments
  for each row execute function collect_hybrid.capture_receipt_payment_event();

create function collect_hybrid.capture_receipt_allocation_event() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_op='INSERT' or new.allocation_status is distinct from old.allocation_status
    or new.collection_id is distinct from old.collection_id then
    perform collect_hybrid.emit_receipt_business_event('allocation',new.id,'allocation_changed',
      new.collection_id,null,null,null,null,new.allocation_status::text);
  end if;
  return new;
end $$;
create trigger receipt_allocation_event after insert or update of allocation_status,collection_id
  on public.parsed_payment_events for each row execute function collect_hybrid.capture_receipt_allocation_event();

create function collect_hybrid.capture_receipt_outbox_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare kind text;
begin
  if tg_op='INSERT' then kind:='receipt_created';
  elsif new.state is distinct from old.state and new.state in ('failed_no_send','uncertain','suppressed') then
    kind:='receipt_'||new.state;
  else return new;end if;
  perform collect_hybrid.emit_receipt_business_event('receipt',new.id,kind,new.collection_id,
    new.payment_id,new.member_record_id,new.snapshot_id,new.id,new.state);
  return new;
end $$;
create trigger receipt_outbox_event after insert or update of state on collect_hybrid.sms_notification_outbox
  for each row execute function collect_hybrid.capture_receipt_outbox_event();

-- Pause is dispatch authority, not permanent suppression. Lock the real flag
-- through the durable claim/send boundary; a pause cannot recall carrier work.
create function collect_hybrid.require_receipt_dispatch_enabled() returns void
language plpgsql security definer set search_path='' as $$
declare enabled boolean;
begin
  select f.enabled into enabled from public.feature_flags f
    where f.key='hybrid_sms_notifications' for share;
  if enabled is distinct from true then
    raise exception 'receipt_dispatch_paused' using errcode='55000';end if;
end $$;
create function collect_hybrid.guard_receipt_dispatch_transition() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name='sms_notification_attempts' then
    perform collect_hybrid.require_receipt_dispatch_enabled();
  elsif new.state in ('awaiting_confirmation','send_started')
    and (tg_op='INSERT' or new.state is distinct from old.state) then
    perform collect_hybrid.require_receipt_dispatch_enabled();
  end if;
  return new;
end $$;
create trigger receipt_dispatch_state_gate before insert or update of state
  on collect_hybrid.sms_notification_outbox for each row
  execute function collect_hybrid.guard_receipt_dispatch_transition();
create trigger receipt_dispatch_attempt_gate before insert on collect_hybrid.sms_notification_attempts
  for each row execute function collect_hybrid.guard_receipt_dispatch_transition();

create function collect_hybrid.require_receipt_monitor_actor() returns uuid
language plpgsql security definer set search_path='' as $$
declare sid uuid;
begin
  sid:=public._lock_notification_registration_session();
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',
    array['system_health.read','notifications.read']);
  return sid;
end $$;
create function collect_hybrid.require_receipt_monitor_consumer(p_consumer_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  if p_consumer_id is null or not exists(select 1 from collect_hybrid.receipt_monitor_consumers
    where id=p_consumer_id and actor_id=auth.uid() and scope='collect_platform') then
    raise exception 'receipt_consumer_scope_denied' using errcode='42501';end if;
end $$;

create function public.register_receipt_monitor_consumer_v1() returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare sid uuid; c collect_hybrid.receipt_monitor_consumers;
begin
  sid:=collect_hybrid.require_receipt_monitor_actor();
  insert into collect_hybrid.receipt_monitor_consumers(actor_id,created_session_id)
    values(auth.uid(),sid) on conflict(actor_id) do nothing;
  select * into c from collect_hybrid.receipt_monitor_consumers where actor_id=auth.uid();
  return jsonb_build_object('contract_version',1,'consumer_id',c.id,'scope',c.scope,
    'purpose',c.purpose,'created_at',c.created_at);
end $$;

create function public.list_receipt_monitor_events_v1(p_consumer_id uuid,p_limit integer default 20,
  p_skip_event_ids uuid[] default '{}'::uuid[]) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare rows jsonb;
begin
  perform collect_hybrid.require_receipt_monitor_actor();
  perform collect_hybrid.require_receipt_monitor_consumer(p_consumer_id);
  if p_limit is null or p_limit not between 1 and 50 or p_skip_event_ids is null
    or cardinality(p_skip_event_ids)>50 or array_position(p_skip_event_ids,null) is not null then
    raise exception 'receipt_monitor_request_invalid' using errcode='22023';end if;
  -- Every invocation rescans committed unobserved UUIDs. Skip IDs are an
  -- ephemeral bounded batch aid, never persisted progress or an ACK.
  select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at,e.id),'[]'::jsonb) into rows from (
    select event.* from collect_hybrid.receipt_business_events event
    where not(event.id=any(p_skip_event_ids)) and not exists(
      select 1 from collect_hybrid.receipt_monitor_observed_events observed
      where observed.consumer_id=p_consumer_id and observed.event_id=event.id)
    order by event.created_at,event.id limit p_limit
  ) e;
  return jsonb_build_object('contract_version',1,'consumer_id',p_consumer_id,
    'scope','collect_platform','checked_at',clock_timestamp(),'rows',rows,
    'limit',p_limit,'progress','per_event_observation','delivery_evidence',false);
end $$;

create function public.ack_receipt_monitor_event_v1(p_consumer_id uuid,p_event_id uuid,
  p_request_id uuid,p_outcome text,p_reason_code text) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare sid uuid; a collect_hybrid.receipt_monitor_acknowledgements; terminal boolean;
begin
  sid:=collect_hybrid.require_receipt_monitor_actor();
  perform collect_hybrid.require_receipt_monitor_consumer(p_consumer_id);
  if p_request_id is null or p_event_id is null or p_outcome is null
    or p_outcome not in ('observed','deferred') or p_reason_code is null
    or p_reason_code not in ('monitoring_only','review_required','policy_pending','dispatch_paused','source_changed') then
    raise exception 'receipt_monitor_request_invalid' using errcode='22023';end if;
  perform pg_advisory_xact_lock(hashtextextended('receipt-monitor-ack:'||p_request_id::text,0));
  select * into a from collect_hybrid.receipt_monitor_acknowledgements where request_id=p_request_id;
  if a.request_id is not null then
    if a.actor_id<>auth.uid() or a.consumer_id<>p_consumer_id or a.event_id<>p_event_id
      or a.outcome<>p_outcome or a.reason_code<>p_reason_code then
      raise exception 'receipt_monitor_request_conflict' using errcode='22023';end if;
  else
    if not exists(select 1 from collect_hybrid.receipt_business_events where id=p_event_id) then
      raise exception 'receipt_event_not_found' using errcode='22023';end if;
    insert into collect_hybrid.receipt_monitor_acknowledgements(request_id,consumer_id,event_id,
      actor_id,session_id,outcome,reason_code)
      values(p_request_id,p_consumer_id,p_event_id,auth.uid(),sid,p_outcome,p_reason_code) returning * into a;
    if p_outcome='observed' then
      insert into collect_hybrid.receipt_monitor_observed_events(consumer_id,event_id,acknowledgement_id)
        values(p_consumer_id,p_event_id,p_request_id) on conflict(consumer_id,event_id) do nothing;
    end if;
  end if;
  terminal:=exists(select 1 from collect_hybrid.receipt_monitor_observed_events
    where consumer_id=p_consumer_id and event_id=p_event_id);
  return jsonb_build_object('contract_version',1,'consumer_id',p_consumer_id,'event_id',p_event_id,
    'request_id',p_request_id,'outcome',a.outcome,'reason_code',a.reason_code,
    'acknowledged_at',a.acknowledged_at,'pending',not terminal,'business_handled',false,'delivery_evidence',false);
end $$;

create function collect_hybrid.receipt_backlog_preview_row(p_snapshot uuid) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare s collect_hybrid.momo_balance_snapshots; p public.payments; m collect_hybrid.member_records;
  i collect_hybrid.member_momo_identities; policy collect_hybrid.sms_receipt_policies;
  consent collect_hybrid.sms_receipt_member_consents; code text; body jsonb;
begin
  select * into s from collect_hybrid.momo_balance_snapshots where id=p_snapshot and event_type='receipt';
  if s.id is null then return null;end if;
  select * into p from public.payments where id=s.payment_id;
  select * into m from collect_hybrid.member_records where id=s.member_record_id;
  select * into i from collect_hybrid.member_momo_identities where member_id=s.member_record_id;
  select * into policy from collect_hybrid.sms_receipt_policies where collection_id=s.collection_id;
  select * into consent from collect_hybrid.sms_receipt_member_consents where member_record_id=s.member_record_id;
  code:=case when s.member_record_id is null or s.member_balance_after_rwf is null then 'MEMBER_SNAPSHOT_MISSING'
    when p.status is distinct from 'posted' then 'PAYMENT_NOT_POSTED'
    when m.lifecycle is distinct from 'active' then 'MEMBER_INACTIVE'
    when m.linked_user_id is not null then 'APP_LINKED_MEMBER'
    when policy.enabled is distinct from true then 'POLICY_DISABLED'
    when i.member_id is null then 'IDENTITY_MISSING'
    when consent.enabled is distinct from true then 'CONSENT_DISABLED'
    when coalesce(btrim(p.transaction_id),'') !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$' then 'UNSAFE_REFERENCE'
    else 'CURRENTLY_ELIGIBLE_HISTORY_UNPROVEN' end;
  body:=jsonb_build_object('snapshot_id',s.id,'payment_id',s.payment_id,'collection_id',s.collection_id,
    'member_record_id',s.member_record_id,'captured_at',s.captured_at,'payment_status',p.status,
    'eligibility_code',code,'policy_revision',policy.revision,'consent_revision',consent.revision,
    'destination_revision',i.revision,'catch_up','policy_pending');
  return body||jsonb_build_object('review_version',encode(extensions.digest(convert_to(body::text,'UTF8'),'sha256'),'hex'));
end $$;

create function public.admin_preview_receipt_backlog_v1(p_limit integer default 20,
  p_before_captured_at timestamptz default null,p_before_snapshot_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' set timezone='UTC' as $$
declare rows jsonb; last_row jsonb; more boolean;
begin
  perform collect_hybrid.require_receipt_monitor_actor();
  if p_limit is null or p_limit not between 1 and 50
    or ((p_before_captured_at is null)<>(p_before_snapshot_id is null))
    or (p_before_captured_at is not null and not isfinite(p_before_captured_at)) then
    raise exception 'receipt_monitor_request_invalid' using errcode='22023';end if;
  select coalesce(jsonb_agg(collect_hybrid.receipt_backlog_preview_row(s.id) order by s.captured_at desc,s.id desc),'[]'::jsonb)
    into rows from (select snapshot.* from collect_hybrid.momo_balance_snapshots snapshot
      where snapshot.event_type='receipt' and not exists(select 1 from collect_hybrid.sms_notification_outbox o
        where o.payment_id=snapshot.payment_id and o.template_key='buri_munsi.payment_received')
      and (p_before_captured_at is null or (snapshot.captured_at,snapshot.id)<(p_before_captured_at,p_before_snapshot_id))
      order by snapshot.captured_at desc,snapshot.id desc limit p_limit+1) s;
  more:=jsonb_array_length(rows)>p_limit;
  if more then rows:=rows-(jsonb_array_length(rows)-1);end if;
  last_row:=rows->(jsonb_array_length(rows)-1);
  return jsonb_build_object('contract_version',1,'checked_at',clock_timestamp(),'scope','collect_platform',
    'catch_up','policy_pending','historical_enqueue_enabled',false,'rows',rows,'limit',p_limit,
    'next_cursor',case when more then jsonb_build_object('captured_at',last_row->'captured_at','snapshot_id',last_row->'snapshot_id') else null end);
end $$;

create function public.admin_reconcile_receipt_backlog_v1(p_request_id uuid,p_snapshot_ids uuid[],
  p_review_versions text[]) returns jsonb
language plpgsql security definer set search_path='' as $$
begin
  perform collect_hybrid.require_receipt_monitor_actor();
  if p_request_id is null or p_snapshot_ids is null or p_review_versions is null
    or cardinality(p_snapshot_ids) not between 1 and 25
    or cardinality(p_review_versions)<>cardinality(p_snapshot_ids)
    or array_position(p_snapshot_ids,null) is not null
    or exists(select 1 from unnest(p_review_versions) v where v is null or v !~ '^[a-f0-9]{64}$') then
    raise exception 'receipt_monitor_request_invalid' using errcode='22023';end if;
  -- Historical consent/contact snapshots cannot be reconstructed from current
  -- revisions. No approved policy exists: refuse without enqueue or mutation.
  return jsonb_build_object('contract_version',1,'ok',false,'code','CATCHUP_POLICY_PENDING',
    'request_id',p_request_id,'queued',0,'historical_enqueue_enabled',false);
end $$;

revoke all on function collect_hybrid.guard_receipt_event_evidence(),
  collect_hybrid.emit_receipt_business_event(text,uuid,text,uuid,uuid,uuid,uuid,uuid,text),
  collect_hybrid.capture_receipt_payment_event(),collect_hybrid.capture_receipt_allocation_event(),
  collect_hybrid.capture_receipt_outbox_event(),collect_hybrid.require_receipt_dispatch_enabled(),
  collect_hybrid.guard_receipt_dispatch_transition(),collect_hybrid.require_receipt_monitor_actor(),
  collect_hybrid.require_receipt_monitor_consumer(uuid),collect_hybrid.receipt_backlog_preview_row(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.register_receipt_monitor_consumer_v1(),
  public.list_receipt_monitor_events_v1(uuid,integer,uuid[]),
  public.ack_receipt_monitor_event_v1(uuid,uuid,uuid,text,text),
  public.admin_preview_receipt_backlog_v1(integer,timestamptz,uuid),
  public.admin_reconcile_receipt_backlog_v1(uuid,uuid[],text[]) from public,anon,authenticated,service_role;
grant execute on function public.register_receipt_monitor_consumer_v1(),
  public.list_receipt_monitor_events_v1(uuid,integer,uuid[]),
  public.ack_receipt_monitor_event_v1(uuid,uuid,uuid,text,text),
  public.admin_preview_receipt_backlog_v1(integer,timestamptz,uuid),
  public.admin_reconcile_receipt_backlog_v1(uuid,uuid[],text[]) to authenticated;

-- The existing enqueue and assisted authority definitions follow. Their
-- signatures/ACLs are preserved. Only pause capture/dispatch boundaries change.
create or replace function collect_hybrid.enqueue_sms_receipt_from_snapshot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payment public.payments;
  member collect_hybrid.member_records;
  identity collect_hybrid.member_momo_identities;
  policy collect_hybrid.sms_receipt_policies;
  consent collect_hybrid.sms_receipt_member_consents;
  message text;
  reference_value text;
begin
  if new.event_type <> 'receipt' or new.member_record_id is null
     or new.member_balance_after_rwf is null then
    return new;
  end if;
  -- Dispatch pause retains newly eligible immutable work.
  select item.* into policy
  from collect_hybrid.sms_receipt_policies item
  where item.collection_id = new.collection_id and item.enabled;
  if policy.collection_id is null then return new; end if;
  select item.* into payment from public.payments item where item.id = new.payment_id;
  select item.* into member
  from collect_hybrid.member_records item
  where item.id = new.member_record_id and item.lifecycle = 'active';
  if payment.id is null or payment.status <> 'posted' or member.id is null then
    return new;
  end if;
  -- App-linked members already use the existing contribution-confirmed push
  -- pipeline. SMS is reserved for account-independent members.
  if member.linked_user_id is not null then return new; end if;
  select item.* into identity
  from collect_hybrid.member_momo_identities item
  where item.member_id = member.id;
  if identity.member_id is null then return new; end if;
  select item.* into consent
  from collect_hybrid.sms_receipt_member_consents item
  where item.member_record_id = member.id and item.enabled;
  if consent.member_record_id is null then return new; end if;
  reference_value := btrim(coalesce(payment.transaction_id, ''));
  if reference_value !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,63}$' then
    insert into collect_hybrid.sms_notification_outbox(
      payment_id, snapshot_id, collection_id, member_record_id,
      destination_e164, destination_sha256, destination_revision,
      policy_revision, consent_revision, template_key, template_version, amount_rwf,
      member_balance_rwf, group_balance_rwf, reference, state,
      suppression_reason
    ) values (
      payment.id, new.id, new.collection_id, member.id,
      identity.momo_number,
      encode(extensions.digest(identity.momo_number, 'sha256'), 'hex'),
      identity.revision, policy.revision, consent.revision, policy.template_key,
      policy.template_version, payment.amount_rwf,
      new.member_balance_after_rwf, new.group_balance_after_rwf,
      coalesce(nullif(reference_value, ''), 'invalid'), 'suppressed',
      'Provider reference is not safe for the canonical receipt template'
    ) on conflict (payment_id, template_key) do nothing;
    return new;
  end if;
  message := collect_hybrid.render_buri_munsi_receipt(
    payment.amount_rwf, new.member_balance_after_rwf,
    new.group_balance_after_rwf, reference_value
  );
  insert into collect_hybrid.sms_notification_outbox(
    payment_id, snapshot_id, collection_id, member_record_id,
    destination_e164, destination_sha256, destination_revision,
    policy_revision, consent_revision, template_key, template_version, amount_rwf,
    member_balance_rwf, group_balance_rwf, reference,
    message_body, body_sha256
  ) values (
    payment.id, new.id, new.collection_id, member.id,
    identity.momo_number,
    encode(extensions.digest(identity.momo_number, 'sha256'), 'hex'),
    identity.revision, policy.revision, consent.revision, policy.template_key,
    policy.template_version, payment.amount_rwf,
    new.member_balance_after_rwf, new.group_balance_after_rwf,
    reference_value, message,
    encode(extensions.digest(message, 'sha256'), 'hex')
  ) on conflict (payment_id, template_key) do nothing;
  return new;
end;
$$;

create or replace function public.collect_claim_receipt(
  p_operator_user_id uuid,
  p_job_id uuid,
  p_worker_id text,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  clean_worker text := btrim(coalesce(p_worker_id, ''));
  job collect_hybrid.sms_notification_outbox;
  prior collect_hybrid.sms_notification_claim_requests;
  token uuid;
  result jsonb;
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.manage'
  ) then raise exception 'Notification operator manage permission required'; end if;
  perform collect_hybrid.require_receipt_dispatch_enabled();
  if p_job_id is null or p_request_id is null
     or clean_worker !~ '^[A-Za-z0-9._:-]{3,80}$' then
    raise exception 'Valid job, worker and request IDs are required';
  end if;
  select item.* into prior
  from collect_hybrid.sms_notification_claim_requests item
  where item.request_id = p_request_id;
  if prior.request_id is not null then
    if prior.operator_user_id <> p_operator_user_id
       or prior.outbox_id <> p_job_id or prior.worker_id <> clean_worker then
      raise exception 'Notification claim idempotency key conflict';
    end if;
    return prior.result || jsonb_build_object('replay', true);
  end if;
  select item.* into job
  from collect_hybrid.sms_notification_outbox item
  where item.id = p_job_id
  for update;
  if job.id is null then raise exception 'Notification job not found'; end if;
  if job.state = 'awaiting_confirmation'
     and job.claim_expires_at <= clock_timestamp()
     and not exists (
       select 1 from collect_hybrid.sms_notification_attempts attempt
       where attempt.outbox_id = job.id
     ) then
    update collect_hybrid.sms_notification_outbox
    set state = 'queued', claim_token = null, claimed_by = null,
        claim_expires_at = null
    where id = job.id;
    job.state := 'queued';
  end if;
  if job.state = 'queued'
     and not collect_hybrid.sms_receipt_job_is_current(job.id) then
    update collect_hybrid.sms_notification_outbox
    set state = 'suppressed',
        suppression_reason = 'Consent, collection policy, destination or payment state changed before claim',
        claim_token = null,
        claimed_by = null,
        claim_expires_at = null
    where id = job.id
    returning * into job;
    result := jsonb_build_object(
      'ok', false,
      'job_id', job.id,
      'state', 'suppressed',
      'replay', false
    );
    insert into collect_hybrid.sms_notification_claim_requests(
      request_id, operator_user_id, outbox_id, worker_id, result
    ) values (p_request_id, p_operator_user_id, job.id, clean_worker, result);
    perform public.create_audit_log(
      'notification.sms.suppressed', 'sms_notification_outbox', job.id,
      jsonb_build_object(
        'reason', job.suppression_reason,
        'fence_version', job.fence_version
      ),
      p_operator_user_id
    );
    return result;
  end if;
  if job.state <> 'queued' then
    raise exception 'Notification job is not available to claim';
  end if;
  token := gen_random_uuid();
  update collect_hybrid.sms_notification_outbox
  set state = 'awaiting_confirmation', claim_token = token,
      claimed_by = clean_worker, claim_expires_at = clock_timestamp() + interval '5 minutes',
      fence_version = fence_version + 1
  where id = job.id
  returning * into job;
  result := jsonb_build_object(
    'ok', true, 'job_id', job.id, 'claim_token', token,
    'fence_version', job.fence_version,
    'claim_expires_at', job.claim_expires_at,
    'destination_masked', left(job.destination_e164, 4) || '•••' || right(job.destination_e164, 3),
    'replay', false
  );
  insert into collect_hybrid.sms_notification_claim_requests(
    request_id, operator_user_id, outbox_id, worker_id, result
  ) values (p_request_id, p_operator_user_id, job.id, clean_worker, result);
  return result;
end;
$$;

create or replace function public.collect_get_claimed_receipt(
  p_operator_user_id uuid,
  p_job_id uuid,
  p_claim_token uuid,
  p_fence_version integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare job collect_hybrid.sms_notification_outbox;
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.manage'
  ) then raise exception 'Notification operator manage permission required'; end if;
  perform collect_hybrid.require_receipt_dispatch_enabled();
  select item.* into job
  from collect_hybrid.sms_notification_outbox item
  where item.id = p_job_id;
  if job.id is null or job.state <> 'awaiting_confirmation'
     or job.claim_token is distinct from p_claim_token
     or job.fence_version <> p_fence_version
     or job.claim_expires_at <= clock_timestamp()
     or not collect_hybrid.sms_receipt_job_is_current(job.id) then
    raise exception 'Current notification claim required';
  end if;
  return jsonb_build_object(
    'job_id', job.id,
    'destination_e164', job.destination_e164,
    'destination_revision', job.destination_revision,
    'message_body', job.message_body,
    'body_sha256', job.body_sha256,
    'template_key', job.template_key,
    'template_version', job.template_version,
    'amount_rwf', job.amount_rwf,
    'member_balance_rwf', job.member_balance_rwf,
    'group_balance_rwf', job.group_balance_rwf,
    'reference', job.reference,
    'fence_version', job.fence_version,
    'claim_expires_at', job.claim_expires_at
  );
end;
$$;

create or replace function public.collect_confirm_receipt(
  p_operator_user_id uuid,
  p_job_id uuid,
  p_claim_token uuid,
  p_fence_version integer,
  p_destination_revision integer,
  p_body_sha256 text,
  p_confirmation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  job collect_hybrid.sms_notification_outbox;
  confirmation collect_hybrid.sms_notification_confirmations;
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.manage'
  ) then raise exception 'Notification operator manage permission required'; end if;
  perform collect_hybrid.require_receipt_dispatch_enabled();
  if p_confirmation_id is null then raise exception 'Confirmation ID required'; end if;
  select item.* into confirmation
  from collect_hybrid.sms_notification_confirmations item
  where item.id = p_confirmation_id;
  if confirmation.id is not null then
    if confirmation.outbox_id <> p_job_id
       or confirmation.operator_user_id <> p_operator_user_id
       or confirmation.claim_token <> p_claim_token
       or confirmation.fence_version <> p_fence_version
       or confirmation.destination_revision <> p_destination_revision
       or confirmation.body_sha256 is distinct from lower(btrim(coalesce(p_body_sha256, ''))) then
      raise exception 'Notification confirmation idempotency key conflict';
    end if;
    return jsonb_build_object(
      'ok', true, 'confirmation_id', confirmation.id,
      'expires_at', confirmation.expires_at, 'replay', true
    );
  end if;
  select item.* into job
  from collect_hybrid.sms_notification_outbox item
  where item.id = p_job_id
  for update;
  if job.id is null or job.state <> 'awaiting_confirmation'
     or job.claim_token is distinct from p_claim_token
     or job.fence_version <> p_fence_version
     or job.claim_expires_at <= clock_timestamp()
     or job.destination_revision <> p_destination_revision
     or job.body_sha256 is distinct from lower(btrim(coalesce(p_body_sha256, '')))
     or not collect_hybrid.sms_receipt_job_is_current(job.id) then
    raise exception 'Exact current notification confirmation required';
  end if;
  insert into collect_hybrid.sms_notification_confirmations(
    id, outbox_id, operator_user_id, claim_token, fence_version,
    destination_revision, body_sha256, expires_at
  ) values (
    p_confirmation_id, job.id, p_operator_user_id, p_claim_token,
    p_fence_version, p_destination_revision, job.body_sha256,
    least(job.claim_expires_at, clock_timestamp() + interval '2 minutes')
  ) returning * into confirmation;
  return jsonb_build_object(
    'ok', true, 'confirmation_id', confirmation.id,
    'expires_at', confirmation.expires_at, 'replay', false
  );
end;
$$;

create or replace function public.collect_record_send_start(
  p_operator_user_id uuid,
  p_job_id uuid,
  p_claim_token uuid,
  p_fence_version integer,
  p_confirmation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  job collect_hybrid.sms_notification_outbox;
  confirmation collect_hybrid.sms_notification_confirmations;
  attempt collect_hybrid.sms_notification_attempts;
begin
  if not collect_hybrid.operator_authorized(
    p_operator_user_id, 'notifications.manage'
  ) then raise exception 'Notification operator manage permission required'; end if;
  perform collect_hybrid.require_receipt_dispatch_enabled();
  select item.* into attempt
  from collect_hybrid.sms_notification_attempts item
  where item.confirmation_id = p_confirmation_id;
  if attempt.id is not null then
    if attempt.outbox_id <> p_job_id
       or attempt.operator_user_id <> p_operator_user_id
       or attempt.claim_token <> p_claim_token
       or attempt.fence_version <> p_fence_version
       or attempt.confirmation_id <> p_confirmation_id then
      raise exception 'Send-start confirmation conflict';
    end if;
    return jsonb_build_object(
      'ok', true, 'attempt_id', attempt.id,
      'state', attempt.state, 'replay', true
    );
  end if;
  select item.* into job
  from collect_hybrid.sms_notification_outbox item
  where item.id = p_job_id
  for update;
  select item.* into confirmation
  from collect_hybrid.sms_notification_confirmations item
  where item.id = p_confirmation_id
  for update;
  -- Freeze the current authorization rows across the durable pre-send
  -- transition. Revocation or payment reversal must complete before or after
  -- this boundary, never race invisibly through it.
  perform 1 from public.payments item
  where item.id = job.payment_id
  for share;
  perform 1 from collect_hybrid.member_records item
  where item.id = job.member_record_id
  for share;
  perform 1 from collect_hybrid.member_momo_identities item
  where item.member_id = job.member_record_id
  for share;
  perform 1 from collect_hybrid.sms_receipt_policies item
  where item.collection_id = job.collection_id
  for share;
  perform 1 from collect_hybrid.sms_receipt_member_consents item
  where item.member_record_id = job.member_record_id
  for share;
  if job.id is null or confirmation.id is null
     or job.state <> 'awaiting_confirmation'
     or job.claim_token is distinct from p_claim_token
     or job.fence_version <> p_fence_version
     or job.claim_expires_at <= clock_timestamp()
     or confirmation.outbox_id <> job.id
     or confirmation.operator_user_id <> p_operator_user_id
     or confirmation.claim_token <> p_claim_token
     or confirmation.fence_version <> p_fence_version
     or confirmation.destination_revision <> job.destination_revision
     or confirmation.body_sha256 <> job.body_sha256
     or confirmation.expires_at <= clock_timestamp()
     or confirmation.consumed_at is not null
     or not collect_hybrid.sms_receipt_job_is_current(job.id) then
    raise exception 'Fresh exact receipt confirmation required before send start';
  end if;
  insert into collect_hybrid.sms_notification_attempts(
    outbox_id, confirmation_id, operator_user_id, worker_id,
    claim_token, fence_version, attempt_number, destination_sha256,
    destination_revision, body_sha256
  ) values (
    job.id, confirmation.id, p_operator_user_id, job.claimed_by,
    p_claim_token, p_fence_version, job.attempt_count + 1,
    job.destination_sha256, job.destination_revision, job.body_sha256
  ) returning * into attempt;
  update collect_hybrid.sms_notification_confirmations
  set consumed_at = clock_timestamp()
  where id = confirmation.id;
  update collect_hybrid.sms_notification_outbox
  set state = 'send_started', attempt_count = attempt.attempt_number
  where id = job.id;
  return jsonb_build_object(
    'ok', true, 'attempt_id', attempt.id,
    'job_id', job.id, 'state', 'send_started', 'replay', false
  );
end;
$$;

commit;
