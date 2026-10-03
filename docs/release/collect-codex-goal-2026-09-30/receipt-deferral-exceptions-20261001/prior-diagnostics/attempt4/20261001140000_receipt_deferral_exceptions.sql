begin;

-- Derived operational sources only. Append-only producer work never waits on
-- a scanner-owned source queue row while holding a financial row lock.
alter table collect_ops.exceptions drop constraint exceptions_source_kind_check;
alter table collect_ops.exceptions add constraint exceptions_source_kind_check
 check(source_kind in('raw_sms','allocation','payment','receipt','gateway','receipt_event','receipt_backlog'));
alter table collect_ops.exceptions drop constraint exceptions_reason_code_check;
alter table collect_ops.exceptions add constraint exceptions_reason_code_check
 check(reason_code in('PARSING_FAILED','ALLOCATION_REVIEW','VERIFICATION_PENDING','VERIFICATION_REJECTED','VERIFICATION_CONFLICT','CONTACT_MISSING','SEND_UNCERTAIN','SEND_FAILED_NO_SEND','RECEIPT_SUPPRESSED','GATEWAY_UNOBSERVED','GATEWAY_STALE','GATEWAY_SMS_PERMISSION','GATEWAY_NETWORK','GATEWAY_TELEPHONY','GATEWAY_SIM','RECEIPT_OPERATION_SOURCE_CHANGED','RECEIPT_OPERATION_PAYMENT_NOT_POSTED','RECEIPT_OPERATION_SNAPSHOT_MISSING','RECEIPT_OPERATION_RECIPIENT_INELIGIBLE','RECEIPT_OPERATION_POLICY_DISABLED','RECEIPT_OPERATION_CONSENT_MISSING','RECEIPT_OPERATION_CONTACT_MISSING','RECEIPT_OPERATION_CONTACT_HISTORY_UNPROVEN','RECEIPT_OPERATION_POLICY_HISTORY_UNPROVEN','RECEIPT_OPERATION_CONSENT_HISTORY_UNPROVEN','RECEIPT_OPERATION_CATCHUP_DISABLED','RECEIPT_OPERATION_CATCHUP_WINDOW_EXCEEDED','RECEIPT_OPERATION_CONTENT_REFUSED','RECEIPT_OPERATION_LEGACY_CONTENT_REVIEW_REQUIRED','RECEIPT_OPERATION_QUOTA_EXHAUSTED'));
create table collect_ops.receipt_exception_work(
 id uuid primary key default gen_random_uuid(),source_kind text not null check(source_kind in('receipt_event','receipt_backlog')),
 source_id uuid not null,origin text not null check(origin in('deferral','handled','backlog','sweep')),
 queued_at timestamptz not null default clock_timestamp()check(isfinite(queued_at)),processed_at timestamptz check(isfinite(processed_at)),
 outcome text check(outcome in('refreshed','scope_refused','source_unavailable')),check((processed_at is null)=(outcome is null)),
 check(processed_at is null or processed_at>=queued_at));
create index receipt_exception_pending on collect_ops.receipt_exception_work(queued_at,id)where processed_at is null;
create table collect_ops.receipt_backlog_budget_deferrals(
 request_id uuid not null references collect_receipt_operations.requests(request_id)on delete restrict,
 run_id uuid not null references collect_receipt_operations.runs(id)on delete restrict,
 snapshot_id uuid not null references collect_hybrid.momo_balance_snapshots(id)on delete restrict,
 recorded_at timestamptz not null default clock_timestamp()check(isfinite(recorded_at)),primary key(request_id,snapshot_id));
create index receipt_backlog_budget_source on collect_ops.receipt_backlog_budget_deferrals(snapshot_id,recorded_at desc);
create index receipt_backlog_budget_run on collect_ops.receipt_backlog_budget_deferrals(run_id,snapshot_id);
create table collect_ops.receipt_exception_progress(
 singleton boolean primary key check(singleton),epoch bigint not null default 1 check(epoch between 1 and 1000000000),
 phase text not null default 'receipt_event'check(phase in('receipt_event','receipt_backlog')),last_id uuid,
 last_scan_at timestamptz,last_request_id uuid);
insert into collect_ops.receipt_exception_progress(singleton)values(true);
create table collect_ops.receipt_exception_scans(
 request_id uuid primary key,request_limit integer not null check(request_limit between 1 and 25),
 expires_at timestamptz not null check(isfinite(expires_at)),recorded_at timestamptz not null check(isfinite(recorded_at)),result jsonb not null,
 check(expires_at>recorded_at and expires_at<=recorded_at+interval '120 seconds'));
do $$declare t text;begin
 foreach t in array array['receipt_exception_work','receipt_exception_progress','receipt_exception_scans','receipt_backlog_budget_deferrals']loop
  execute format('alter table collect_ops.%I enable row level security',t);
  execute format('revoke all on collect_ops.%I from public,anon,authenticated,service_role',t);
 end loop;
end$$;
create trigger retain_receipt_backlog_budget before update or delete on collect_ops.receipt_backlog_budget_deferrals
 for each row execute function collect_ops.immutable_evidence();
create trigger retain_receipt_exception_scan before update or delete on collect_ops.receipt_exception_scans
 for each row execute function collect_ops.immutable_evidence();
create function collect_ops.protect_receipt_exception_work()returns trigger language plpgsql set search_path=''as $$begin
 if tg_op='DELETE'or(to_jsonb(new)-array['processed_at','outcome'])is distinct from(to_jsonb(old)-array['processed_at','outcome'])
  or old.processed_at is not null or new.processed_at is null then raise exception 'receipt_exception_work_immutable'using errcode='55000';end if;return new;end$$;
create trigger retain_receipt_exception_work before update or delete on collect_ops.receipt_exception_work
 for each row execute function collect_ops.protect_receipt_exception_work();
create function collect_ops.queue_receipt_exception_source()returns trigger
language plpgsql security definer set search_path=''as $$begin
 if tg_table_name in('backlog_results','receipt_backlog_budget_deferrals')then
  insert into collect_ops.receipt_exception_work(source_kind,source_id,origin)values('receipt_backlog',new.snapshot_id,'backlog');
 else
  insert into collect_ops.receipt_exception_work(source_kind,source_id,origin)values('receipt_event',new.event_id,
   case tg_table_name when 'event_deferrals'then 'deferral'else 'handled'end);
 end if;
 return new;end$$;
create trigger receipt_exception_deferral after insert or update on collect_receipt_operations.event_deferrals
 for each row execute function collect_ops.queue_receipt_exception_source();
create trigger receipt_exception_handled after insert on collect_receipt_operations.handled_events
 for each row execute function collect_ops.queue_receipt_exception_source();
create trigger receipt_exception_backlog after insert on collect_receipt_operations.backlog_results
 for each row execute function collect_ops.queue_receipt_exception_source();

-- Preserve original source implementations and function OIDs. Existing
-- callers route through the replaced wrappers; old raw-source rules stay exact.
do $$declare body text;begin
 body:=pg_get_functiondef('collect_ops.refresh_source(text,uuid)'::regprocedure);
 execute replace(body,'FUNCTION collect_ops.refresh_source(', 'FUNCTION collect_ops.receipt_exception_base_refresh_source(');
 body:=pg_get_functiondef('collect_ops.transaction_sms_id(text,uuid)'::regprocedure);
 execute replace(body,'FUNCTION collect_ops.transaction_sms_id(', 'FUNCTION collect_ops.receipt_exception_base_transaction_sms_id(');
end$$;

create or replace function collect_ops.observe(p_kind text,p_source uuid,p_codes text[],p_signature jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare code text;digest text;item collect_ops.exceptions;at timestamptz;
begin
 if p_kind is null or p_kind not in('raw_sms','allocation','payment','receipt','gateway','receipt_event','receipt_backlog')
  or p_source is null or p_codes is null or array_position(p_codes,null) is not null
  or cardinality(p_codes)>15 or p_signature is null then
  raise exception 'operational_exception_source_invalid' using errcode='22023';end if;
 digest:=encode(extensions.digest(convert_to(p_signature::text,'UTF8'),'sha256'),'hex');
 -- Source-local lock, not a global commit-order watermark. Triggers never
 -- invoke an external service or depend on Codex availability.
 perform pg_advisory_xact_lock(hashtextextended('collect-ops-source:'||p_kind||':'||p_source::text,0));
 foreach code in array p_codes loop
  at:=clock_timestamp();
  insert into collect_ops.exceptions(source_kind,source_id,reason_code,active,source_sha256,revision,
   first_observed_at,last_changed_at) values(p_kind,p_source,code,true,digest,1,at,at)
  on conflict(source_kind,source_id,reason_code) do update
   set active=true,source_sha256=excluded.source_sha256,revision=exceptions.revision+1,
    last_changed_at=greatest(exceptions.last_changed_at,excluded.last_changed_at)
   where not exceptions.active or exceptions.source_sha256 is distinct from excluded.source_sha256
  returning * into item;
  if item.id is not null then
   insert into collect_ops.exception_observations(exception_id,revision,active,source_sha256,observed_at)
    values(item.id,item.revision,item.active,item.source_sha256,item.last_changed_at);
  end if;
 end loop;
 for item in update collect_ops.exceptions set active=false,source_sha256=digest,
  revision=revision+1,last_changed_at=greatest(last_changed_at,clock_timestamp())
  where source_kind=p_kind and source_id=p_source and active and not(reason_code=any(p_codes)) returning * loop
  insert into collect_ops.exception_observations(exception_id,revision,active,source_sha256,observed_at)
   values(item.id,item.revision,item.active,item.source_sha256,item.last_changed_at);
 end loop;
end$$;


create index receipt_exception_run_quota on collect_receipt_operations.reservations(run_id)include(actions);
create function collect_ops.receipt_exception_run_budget_available(p_run uuid,collection uuid)returns boolean
language plpgsql volatile set search_path=''as $$
declare p collect_receipt_operations.policy;r collect_receipt_operations.runs;e collect_hybrid.receipt_business_events;
 device uuid;run_used bigint;group_used bigint;device_used bigint;global_used bigint;day_start timestamptz;begin
 select * into r from collect_receipt_operations.runs where id=p_run;
 select * into p from collect_receipt_operations.policy where singleton;
 if p.emergency_stop or p.mode not in('Live','Live-limited')or r.id is null or not coalesce(collection=any(p.collection_ids),false)
  or not exists(select 1 from collect_supervisor.identities i where i.id=any(p.principal_ids)and i.scope='rw_receipt_operations'and i.state='active'and i.expires_at>clock_timestamp())then return false;end if;
 device:=p.device_ids[1];if device is null or not exists(select 1 from collect_gateway.devices d where d.id=device and d.state='active')then return false;end if;
 day_start:=date_trunc('day',clock_timestamp()at time zone 'UTC')at time zone 'UTC';
 select coalesce(sum(actions)filter(where run_id=r.id and r.policy_revision=p.revision and r.completed_at is null and r.expires_at>clock_timestamp()),0),
  coalesce(sum(actions)filter(where collection_id=collection and recorded_at>=day_start),0),
  coalesce(sum(actions)filter(where device_id=device and recorded_at>=day_start),0),
  coalesce(sum(actions)filter(where recorded_at>=day_start),0)
 into run_used,group_used,device_used,global_used from collect_receipt_operations.reservations where run_id=r.id or recorded_at>=day_start;
 return run_used<(p.caps->>'run_actions')::bigint and group_used<(p.caps->>'group_actions')::bigint
  and device_used<(p.caps->>'device_actions')::bigint and global_used<(p.caps->>'global_actions')::bigint;end$$;

create function collect_ops.receipt_exception_quota_available(p_kind text,p_source uuid)returns boolean
language plpgsql volatile set search_path=''as $$declare run uuid;collection uuid;begin
 if p_kind='receipt_event'then
  select e.collection_id into collection from collect_hybrid.receipt_business_events e where id=p_source;
  select x.run_id into run from collect_receipt_operations.run_events x where x.event_id=p_source and x.code='QUOTA_EXHAUSTED'order by x.recorded_at desc,x.run_id desc limit 1;
 else
  select s.collection_id into collection from collect_hybrid.momo_balance_snapshots s where id=p_source;
  select x.run_id into run from(
   select b.run_id,b.recorded_at from collect_receipt_operations.backlog_results b where b.snapshot_id=p_source and b.code='QUOTA_EXHAUSTED'
   union all select b.run_id,b.recorded_at from collect_ops.receipt_backlog_budget_deferrals b where b.snapshot_id=p_source)x order by x.recorded_at desc,x.run_id desc limit 1;
 end if;return collect_ops.receipt_exception_run_budget_available(run,collection);end$$;

-- Reconciliation exits before inspecting a snapshot when quota is exhausted.
-- Capture that actual bounded first-candidate refusal under its existing run/
-- policy lock without changing examined counts, reserving quota or sending.
create function collect_ops.capture_receipt_backlog_budget_refusal()returns trigger
language plpgsql security definer set search_path=''as $$
declare r collect_receipt_operations.runs;p collect_receipt_operations.policy;s collect_hybrid.momo_balance_snapshots;begin
 if new.action<>'reconcile_backlog'then return new;end if;
 r:=collect_receipt_operations.require_run((new.input->>'run_id')::uuid,(new.input->>'fence_version')::bigint,new.principal_id);
 select * into p from collect_receipt_operations.policy where singleton;
 if p.catchup_enabled and r.mode in('Live','Live-limited')and(new.result->>'examined')::integer<(new.input->>'limit')::integer then
  select * into s from collect_hybrid.momo_balance_snapshots snapshot
   where snapshot.event_type='receipt'and snapshot.collection_id=any(r.collection_ids)
    and snapshot.captured_at>=clock_timestamp()-make_interval(hours=>p.catchup_hours)
    and not exists(select 1 from collect_hybrid.sms_notification_outbox o where o.payment_id=snapshot.payment_id and o.template_key='buri_munsi.payment_received')
    and not exists(select 1 from collect_receipt_operations.backlog_results b where b.run_id=r.id and b.snapshot_id=snapshot.id)
   order by snapshot.captured_at,snapshot.id limit 1;
  if s.id is not null and not collect_ops.receipt_exception_run_budget_available(r.id,s.collection_id)then
   insert into collect_ops.receipt_backlog_budget_deferrals(request_id,run_id,snapshot_id)values(new.request_id,r.id,s.id);
  end if;
 end if;return new;end$$;
create trigger receipt_backlog_budget_refusal after insert on collect_receipt_operations.requests
 for each row execute function collect_ops.capture_receipt_backlog_budget_refusal();
create trigger receipt_exception_budget after insert on collect_ops.receipt_backlog_budget_deferrals
 for each row execute function collect_ops.queue_receipt_exception_source();

-- Retain the public function OID/signature/grants and action allowlist, while
-- completion counts assigned-but-unexamined quota refusals as deferred work.
do $$declare body text;needle text;replacement text;begin
 body:=pg_get_functiondef('public.receipt_operations_execute_v2(uuid,uuid,text,text,timestamptz,text,jsonb)'::regprocedure);
 needle:='deferred:=deferred+(select count(*)from collect_receipt_operations.backlog_results where run_id=r.id and not business_handled);';
 replacement:=needle||E'\n   deferred:=deferred+(select count(distinct b.snapshot_id)from collect_ops.receipt_backlog_budget_deferrals b where b.run_id=r.id and not exists(select 1 from collect_receipt_operations.backlog_results x where x.run_id=r.id and x.snapshot_id=b.snapshot_id));';
 if strpos(body,needle)=0 then raise exception 'receipt_operations_completion_definition_unavailable'using errcode='55000';end if;
 execute replace(body,needle,replacement);end$$;

create function collect_ops.receipt_exception_source(p_kind text,p_source uuid)returns jsonb
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
   select b.code,b.recorded_at,b.run_id from collect_receipt_operations.backlog_results b where b.snapshot_id=s.id and not b.business_handled
   union all select 'QUOTA_EXHAUSTED',b.recorded_at,b.run_id from collect_ops.receipt_backlog_budget_deferrals b where b.snapshot_id=s.id)x order by x.recorded_at desc,x.run_id desc limit 1;
  select * into handled_backlog from collect_receipt_operations.backlog_results x where x.snapshot_id=s.id and x.business_handled order by x.recorded_at,x.run_id limit 1;
  if handled_backlog.snapshot_id is not null then code:=handled_backlog.code;receipt:=handled_backlog.receipt_id;business:=true;disposition:='durably_handled';
  elsif original is null then disposition:='current_blocker_cleared';
  elsif original='QUOTA_EXHAUSTED'and not collect_ops.receipt_exception_quota_available(p_kind,p_source)then code:=original;disposition:='deferred';
  else inspected:=collect_receipt_operations.ensure_snapshot(s.id,true,false);code:=inspected->>'code';receipt:=(inspected->>'receipt_id')::uuid;end if;
 else raise exception 'receipt_exception_source_invalid'using errcode='22023';end if;
 if disposition is null then disposition:=case when code in('RECEIPT_EXISTS','PAYMENT_REVERSED','DRY_RUN_ELIGIBLE')then 'current_blocker_cleared'else 'deferred'end;end if;
 if disposition='deferred'and code not in('SOURCE_CHANGED','PAYMENT_NOT_POSTED','SNAPSHOT_MISSING','RECIPIENT_INELIGIBLE','POLICY_DISABLED',
  'CONSENT_MISSING','CONTACT_MISSING','CONTACT_HISTORY_UNPROVEN','POLICY_HISTORY_UNPROVEN','CONSENT_HISTORY_UNPROVEN','CATCHUP_DISABLED',
  'CATCHUP_WINDOW_EXCEEDED','CONTENT_REFUSED','LEGACY_CONTENT_REVIEW_REQUIRED','QUOTA_EXHAUSTED')then
  raise exception 'receipt_exception_unknown_deferral'using errcode='55000';end if;
 signature:=jsonb_build_array(version,original,code,disposition,business,receipt,
  (select policy.revision from collect_hybrid.sms_receipt_policies policy where policy.collection_id=coalesce(e.collection_id,s.collection_id)),
  (select consent.revision from collect_hybrid.sms_receipt_member_consents consent where consent.member_record_id=coalesce(e.member_record_id,s.member_record_id)),
  (select identity.revision from collect_hybrid.member_momo_identities identity where identity.member_id=coalesce(e.member_record_id,s.member_record_id)),
  (select jsonb_build_array(p.catchup_enabled,p.catchup_hours)from collect_receipt_operations.policy p where singleton));
 return jsonb_build_object('source_version',version,'event_kind',kind,'original_code',original,'current_code',code,
  'disposition',disposition,'business_handled',business,'receipt_id',receipt,'signature',signature);end$$;

create or replace function collect_ops.refresh_source(p_kind text,p_source uuid)returns void
language plpgsql security definer set search_path=''as $$declare current jsonb;codes text[];begin
 if p_kind in('receipt_event','receipt_backlog')then
  perform pg_advisory_xact_lock(hashtextextended('collect-ops-source:'||p_kind||':'||p_source::text,0));
  current:=collect_ops.receipt_exception_source(p_kind,p_source);
  codes:=case when current->>'disposition'='deferred'then array['RECEIPT_OPERATION_'||(current->>'current_code')]else '{}'::text[]end;
  perform collect_ops.observe(p_kind,p_source,codes,current->'signature');
 else perform collect_ops.receipt_exception_base_refresh_source(p_kind,p_source);end if;end$$;
create or replace function collect_ops.transaction_sms_id(p_kind text,p_source uuid)returns uuid
language sql stable security definer set search_path=''as $$
 select case when p_kind in('receipt_event','receipt_backlog')then
  (select sms.id from public.parsed_payment_events parsed join public.raw_payment_sms sms on sms.id=parsed.raw_sms_id
   where parsed.id=case when p_kind='receipt_event'then
    (select coalesce(p.parsed_event_id,case when e.source_kind='allocation'then e.source_id end)
     from collect_hybrid.receipt_business_events e left join public.payments p on p.id=e.payment_id
     where e.id=p_source)
    else(select p.parsed_event_id from collect_hybrid.momo_balance_snapshots s join public.payments p on p.id=s.payment_id where s.id=p_source)end
   and collect_security.rwanda_sms_scope(sms.id))
 else collect_ops.receipt_exception_base_transaction_sms_id(p_kind,p_source)end
$$;

create function collect_ops.receipt_exception_service()returns void
language plpgsql set search_path=''as $$begin
 if auth.role()is distinct from 'service_role'then raise exception 'receipt_exception_service_required'using errcode='42501';end if;
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'receipt_exception_snapshot_retry'using errcode='40001';end if;end$$;
create function public.process_receipt_deferral_exceptions_v1(p_request_id uuid,p_limit integer,p_expires_at timestamptz)returns jsonb
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
   for source in select d.event_id from collect_receipt_operations.event_deferrals d
    where(p.last_id is null or d.event_id>p.last_id)order by d.event_id limit p_limit loop
    insert into collect_ops.receipt_exception_work(source_kind,source_id,origin)values('receipt_event',source,'sweep');seeded:=seeded+1;p.last_id:=source;
   end loop;
   if seeded=0 then p.phase:='receipt_backlog';p.last_id:=null;end if;
  else
   for source in select distinct x.snapshot_id from(
    select b.snapshot_id from collect_receipt_operations.backlog_results b where not b.business_handled
    union all select b.snapshot_id from collect_ops.receipt_backlog_budget_deferrals b)x
    where p.last_id is null or x.snapshot_id>p.last_id order by x.snapshot_id limit p_limit loop
    insert into collect_ops.receipt_exception_work(source_kind,source_id,origin)values('receipt_backlog',source,'sweep');seeded:=seeded+1;p.last_id:=source;
   end loop;
   if seeded=0 then
    if p.epoch=1000000000 then raise exception 'receipt_exception_epoch_exhausted'using errcode='55000';end if;
    p.phase:='receipt_event';p.last_id:=null;p.epoch:=p.epoch+1;
   end if;
  end if;
  for w in select * from collect_ops.receipt_exception_work where processed_at is null order by queued_at,id limit p_limit for update skip locked loop
   work_outcome:='refreshed';begin
    perform pg_advisory_xact_lock(hashtextextended('collect-ops-source:'||w.source_kind||':'||w.source_id::text,0));
    select coalesce(jsonb_object_agg(e.id::text,e.revision),'{}'::jsonb)into before_heads from collect_ops.exceptions e where e.source_kind=w.source_kind and e.source_id=w.source_id;
    perform collect_ops.refresh_source(w.source_kind,w.source_id);
    select count(*),count(*)filter(where o.active),count(*)filter(where not o.active)into changed,act,closed
     from collect_ops.exception_observations o join collect_ops.exceptions e on e.id=o.exception_id
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
   update collect_ops.receipt_exception_work set processed_at=clock_timestamp(),outcome=work_outcome where id=w.id;processed:=processed+1;
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
create function public.get_receipt_deferral_exception_scan_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare prior collect_ops.receipt_exception_scans;acquired boolean;t timestamptz;begin
 perform collect_ops.receipt_exception_service();if p_request_id is null then raise exception 'receipt_exception_scan_invalid'using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-receipt-exception-scan:'||p_request_id::text,0));
 select * into prior from collect_ops.receipt_exception_scans where acquired and request_id=p_request_id;
 t:=clock_timestamp();return jsonb_build_object('contract_version',1,'request_id',p_request_id,'checked_at',collect_ops.utc(t),
  'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),'status',case when not acquired then 'in_progress'when prior.request_id is null then 'not_recorded'else 'recorded'end,
  'expires_at',case when prior.request_id is null then null else collect_ops.utc(prior.expires_at)end,'receipt',prior.result);end$$;
create function public.admin_get_receipt_deferral_exception_v1(p_exception_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='200ms'as $$
declare e collect_ops.exceptions;current jsonb;t timestamptz;begin
 perform collect_ops.actor(false);perform pg_advisory_xact_lock(hashtext('collect-ops-workflow'));
 select * into e from collect_ops.exceptions where id=p_exception_id and source_kind in('receipt_event','receipt_backlog');
 if e.id is null then raise exception 'receipt_exception_unavailable'using errcode='22023';end if;
 perform collect_ops.refresh_source(e.source_kind,e.source_id);select * into e from collect_ops.exceptions where id=p_exception_id;
 current:=collect_ops.receipt_exception_source(e.source_kind,e.source_id);perform collect_ops.actor(false);t:=clock_timestamp();
 return jsonb_build_object('contract_version',1,'exception_id',e.id,'source_kind',e.source_kind,'source_id',e.source_id,
  'source_version',current->'source_version','event_kind',current->'event_kind','reason_code',e.reason_code,'revision',e.revision,'active',e.active,
  'disposition',current->'disposition','original_code',current->'original_code','current_code',current->'current_code',
  'business_handled',current->'business_handled','receipt_id',current->'receipt_id','checked_at',collect_ops.utc(t),
  'sample_valid_until',collect_ops.utc(t+interval '60 seconds'),'financial_action',false,'send_action',false);end$$;

create or replace function public.admin_list_operational_exceptions_v2(p_active boolean default true,
 p_limit integer default 20,p_before_changed_at timestamptz default null,
 p_before_id uuid default null,p_source_kind text default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_ops.actor(false);
 if p_active is null or p_limit is null or p_limit not between 1 and 50
  or((p_before_changed_at is null)<>(p_before_id is null))
  or(p_before_changed_at is not null and not isfinite(p_before_changed_at))
  or(p_source_kind is not null and p_source_kind not in('raw_sms','allocation','payment','receipt','gateway','receipt_event','receipt_backlog')) then
  raise exception 'operational_exception_query_invalid' using errcode='22023';end if;
 -- One committed statement supplies time, category, page and review flags.
 -- Read freshness is independent of the retained source observation's age.
 with sample as materialized(select clock_timestamp() at),
 candidates as materialized(select e.* from collect_ops.exceptions e
  where e.active=p_active and(p_source_kind is null or e.source_kind=p_source_kind)
   and(p_before_changed_at is null or(e.last_changed_at,e.id)<(p_before_changed_at,p_before_id))
  order by e.last_changed_at desc,e.id desc limit p_limit+1),
 page as materialized(select * from candidates order by last_changed_at desc,id desc limit p_limit),
 projected as(select e.last_changed_at,e.id,jsonb_build_object('id',e.id,
  'source_kind',e.source_kind,'source_id',e.source_id,'reason_code',e.reason_code,
  'active',e.active,'revision',e.revision,'source_sha256',e.source_sha256,
  'first_observed_at',collect_ops.utc(e.first_observed_at),
  'last_changed_at',collect_ops.utc(e.last_changed_at),
  'transaction_sms_id',collect_ops.transaction_sms_id(e.source_kind,e.source_id),
  'acknowledged',exists(select 1 from collect_ops.exception_actions a
   where a.exception_id=e.id and a.expected_revision=e.revision and a.action='acknowledge'),
  'escalation_requested',exists(select 1 from collect_ops.exception_actions a
   where a.exception_id=e.id and a.expected_revision=e.revision and a.action='escalate'))value from page e)
 select jsonb_build_object('contract_version',2,'scope','platform_global',
  'checked_at',collect_ops.utc(sample.at),'sample_valid_until',collect_ops.utc(sample.at+interval '60 seconds'),
  'active',p_active,'source_kind',p_source_kind,'limit',p_limit,
  'rows',coalesce((select jsonb_agg(value order by last_changed_at desc,id desc)from projected),'[]'::jsonb),
  'next_cursor',case when(select count(*)from candidates)>p_limit then
   (select jsonb_build_object('changed_at',collect_ops.utc(last_changed_at),'id',id)
    from page order by last_changed_at,id limit 1)else null end,
  'escalation_delivery_verified',false,'source_scan_complete',false)
 into result from sample;
 return result;
end$$;


-- New helpers remain private; replaced legacy function grants stay unchanged.
revoke all on function collect_ops.protect_receipt_exception_work(),collect_ops.queue_receipt_exception_source(),
 collect_ops.receipt_exception_base_refresh_source(text,uuid),collect_ops.receipt_exception_base_transaction_sms_id(text,uuid),
 collect_ops.receipt_exception_quota_available(text,uuid),collect_ops.receipt_exception_run_budget_available(uuid,uuid),collect_ops.capture_receipt_backlog_budget_refusal(),collect_ops.receipt_exception_source(text,uuid),collect_ops.receipt_exception_service()
 from public,anon,authenticated,service_role;
revoke all on function public.process_receipt_deferral_exceptions_v1(uuid,integer,timestamptz),public.get_receipt_deferral_exception_scan_v1(uuid),
 public.admin_get_receipt_deferral_exception_v1(uuid)from public,anon,authenticated,service_role;
grant execute on function public.process_receipt_deferral_exceptions_v1(uuid,integer,timestamptz),public.get_receipt_deferral_exception_scan_v1(uuid)to service_role;
grant execute on function public.admin_get_receipt_deferral_exception_v1(uuid)to authenticated;
commit;
