begin;

-- Derived operational evidence only. No payment, allocation, receipt, sender
-- or policy action is authorized by acknowledging/escalating an exception.
create schema collect_ops;
revoke all on schema collect_ops from public,anon,authenticated,service_role;
create table collect_ops.exceptions(
 id uuid primary key default gen_random_uuid(),
 source_kind text not null check(source_kind in('raw_sms','allocation','payment','receipt','gateway')),
 source_id uuid not null,
 reason_code text not null check(reason_code in('PARSING_FAILED','ALLOCATION_REVIEW',
  'VERIFICATION_PENDING','VERIFICATION_REJECTED','VERIFICATION_CONFLICT','CONTACT_MISSING',
  'SEND_UNCERTAIN','SEND_FAILED_NO_SEND','RECEIPT_SUPPRESSED','GATEWAY_UNOBSERVED',
  'GATEWAY_STALE','GATEWAY_SMS_PERMISSION','GATEWAY_NETWORK','GATEWAY_TELEPHONY','GATEWAY_SIM')),
 active boolean not null,
 source_sha256 text not null check(source_sha256 ~ '^[a-f0-9]{64}$'),
 revision bigint not null check(revision between 1 and 1000000000),
 first_observed_at timestamptz not null default clock_timestamp(),
 last_changed_at timestamptz not null default clock_timestamp(),
 unique(source_kind,source_id,reason_code)
);
create index operational_exception_inbox_order on collect_ops.exceptions(active,last_changed_at desc,id desc);
create table collect_ops.exception_observations(
 exception_id uuid not null references collect_ops.exceptions(id) on delete restrict,
 revision bigint not null,
 active boolean not null,
 source_sha256 text not null check(source_sha256 ~ '^[a-f0-9]{64}$'),
 observed_at timestamptz not null,
 primary key(exception_id,revision)
);
create table collect_ops.exception_actions(
 request_id uuid primary key,
 exception_id uuid not null references collect_ops.exceptions(id) on delete restrict,
 expected_revision bigint not null,
 action text not null check(action in('acknowledge','escalate')),
 reason_code text not null check(reason_code in('review_started','owner_review_required',
  'uncertain_send_review','contact_review')),
 actor_id uuid not null,
 session_id uuid not null,
 recorded_at timestamptz not null default clock_timestamp(),
 result jsonb not null
);
do $$declare t text;begin
 foreach t in array array['exceptions','exception_observations','exception_actions'] loop
  execute format('alter table collect_ops.%I enable row level security',t);
  execute format('revoke all on collect_ops.%I from public,anon,authenticated,service_role',t);
 end loop;
end$$;
create function collect_ops.immutable_evidence() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'operational_exception_evidence_immutable' using errcode='55000';end$$;
create trigger immutable_exception_observation before update or delete on collect_ops.exception_observations
 for each row execute function collect_ops.immutable_evidence();
create trigger immutable_exception_action before update or delete on collect_ops.exception_actions
 for each row execute function collect_ops.immutable_evidence();
create trigger retain_exception before delete on collect_ops.exceptions
 for each row execute function collect_ops.immutable_evidence();
create function collect_ops.protect_identity() returns trigger language plpgsql set search_path='' as $$
begin
 if(to_jsonb(new)-array['active','source_sha256','revision','last_changed_at'])is distinct from
   (to_jsonb(old)-array['active','source_sha256','revision','last_changed_at'])
  or new.revision<>old.revision+1 or new.last_changed_at<old.last_changed_at
  or(new.active=old.active and new.source_sha256=old.source_sha256) then
  raise exception 'operational_exception_identity_immutable' using errcode='55000';end if;
 return new;
end$$;
create trigger protect_exception_identity before update on collect_ops.exceptions
 for each row execute function collect_ops.protect_identity();

create function collect_ops.observe(p_kind text,p_source uuid,p_codes text[],p_signature jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare code text;digest text;item collect_ops.exceptions;at timestamptz;
begin
 if p_kind is null or p_kind not in('raw_sms','allocation','payment','receipt','gateway')
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

create function collect_ops.payment_scope(p_payment uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.payments p where p.id=p_payment and p.currency='RWF'
  and p.provider_network in('mtn_momo','airtel_money') and
  (exists(select 1 from public.parsed_payment_events e join public.raw_payment_sms sms on sms.id=e.raw_sms_id
    where e.id=p.parsed_event_id and e.network=p.provider_network and e.receiver_user_id=p.receiver_user_id
    and sms.receiver_momo_number_hash=p.receiver_momo_number_hash and collect_security.rwanda_sms_scope(e.raw_sms_id))
   or exists(select 1 from public.collection_receivers r where r.collection_id=p.collection_id
    and r.receiver_user_id=p.receiver_user_id and r.momo_number_hash=p.receiver_momo_number_hash
    and r.network=p.provider_network and
    ((r.network='mtn_momo' and r.momo_number ~ '^(\+250|0)7[89][0-9]{7}$')
     or(r.network='airtel_money' and r.momo_number ~ '^(\+250|0)7[23][0-9]{7}$')))
   or exists(select 1 from public.profiles r where r.id=p.receiver_user_id
    and r.country_code='RW' and r.currency_code='RWF' and r.momo_number_verified_at is not null
    and r.momo_number_hash=p.receiver_momo_number_hash and r.momo_provider=p.provider_network and
    ((r.momo_provider='mtn_momo' and r.momo_number ~ '^(\+250|0)7[89][0-9]{7}$')
     or(r.momo_provider='airtel_money' and r.momo_number ~ '^(\+250|0)7[23][0-9]{7}$')))))
$$;

create function collect_ops.refresh_source(p_kind text,p_source uuid) returns void
language plpgsql security definer set search_path='' as $$
declare sms public.raw_payment_sms;event public.parsed_payment_events;payment public.payments;
 receipt collect_hybrid.sms_notification_outbox;device collect_gateway.devices;
 health collect_gateway.health_observations;codes text[]:='{}';signature jsonb;
 confirmation public.payment_provider_confirmations;rejected boolean;fresh boolean;
begin
 if p_source is null then raise exception 'operational_exception_source_invalid' using errcode='22023';end if;
 -- Acquire the source lock before taking its current predicate snapshot.
 -- A refresh queued behind a committed change must not reopen old evidence.
 perform pg_advisory_xact_lock(hashtextextended('collect-ops-source:'||p_kind||':'||p_source::text,0));
 if p_kind='raw_sms' then
  select * into sms from public.raw_payment_sms where id=p_source;
  if sms.id is null then raise exception 'operational_exception_source_unavailable' using errcode='22023';end if;
  if sms.parse_status='failed' and collect_security.rwanda_sms_scope(sms.id) then codes:=array['PARSING_FAILED'];end if;
  signature:=jsonb_build_array(sms.parse_status,collect_security.rwanda_sms_scope(sms.id));
 elsif p_kind='allocation' then
  select * into event from public.parsed_payment_events where id=p_source;
  if event.id is null then raise exception 'operational_exception_source_unavailable' using errcode='22023';end if;
  if event.allocation_status in('unallocated','ambiguous','needs_review') and collect_security.rwanda_sms_scope(event.raw_sms_id) then
   codes:=array['ALLOCATION_REVIEW'];end if;
  signature:=jsonb_build_array(event.allocation_status,event.collection_id,collect_security.rwanda_sms_scope(event.raw_sms_id));
 elsif p_kind='payment' then
  select * into payment from public.payments where id=p_source;
  if payment.id is null then raise exception 'operational_exception_source_unavailable' using errcode='22023';end if;
  select * into confirmation from public.payment_provider_confirmations where payment_id=payment.id;
  rejected:=exists(select 1 from collect_hybrid.payment_provider_rejections where payment_id=payment.id);
  if collect_ops.payment_scope(payment.id) then
   if rejected then codes:=array_append(codes,'VERIFICATION_REJECTED');end if;
   if confirmation.id is not null and(rejected or confirmation.amount_rwf<>payment.amount_rwf
    or confirmation.provider_network is distinct from payment.provider_network
    or confirmation.receiver_momo_number_hash is distinct from payment.receiver_momo_number_hash
    or upper(btrim(confirmation.transaction_id)) is distinct from upper(btrim(payment.transaction_id))) then
    codes:=array_append(codes,'VERIFICATION_CONFLICT');
   elsif payment.status='review' and not rejected then codes:=array_append(codes,'VERIFICATION_PENDING');end if;
   if payment.status='posted' and not exists(select 1 from collect_hybrid.sms_notification_outbox where payment_id=payment.id)
    and exists(select 1 from collect_hybrid.member_records m
     join collect_hybrid.sms_receipt_policies policy on policy.collection_id=payment.collection_id and policy.enabled
     join collect_hybrid.sms_receipt_member_consents consent on consent.member_record_id=m.id and consent.enabled
     where m.id=payment.member_record_id and m.lifecycle='active' and m.linked_user_id is null
      and not exists(select 1 from collect_hybrid.member_momo_identities i where i.member_id=m.id)) then
    codes:=array_append(codes,'CONTACT_MISSING');end if;
  end if;
  signature:=jsonb_build_array(payment.status,confirmation.id,rejected,codes,collect_ops.payment_scope(payment.id));
 elsif p_kind='receipt' then
  select * into receipt from collect_hybrid.sms_notification_outbox where id=p_source;
  if receipt.id is null then raise exception 'operational_exception_source_unavailable' using errcode='22023';end if;
  if collect_ops.payment_scope(receipt.payment_id) then
   codes:=case receipt.state when 'uncertain' then array['SEND_UNCERTAIN']
    when 'failed_no_send' then array['SEND_FAILED_NO_SEND'] when 'suppressed' then array['RECEIPT_SUPPRESSED'] else '{}'::text[] end;
  end if;
  signature:=jsonb_build_array(receipt.state,receipt.fence_version,receipt.attempt_count,codes,collect_ops.payment_scope(receipt.payment_id));
 elsif p_kind='gateway' then
  select * into device from collect_gateway.devices where id=p_source;
  if device.id is null then raise exception 'operational_exception_source_unavailable' using errcode='22023';end if;
  select * into health from collect_gateway.health_observations where device_id=device.id order by ingested_at desc,id desc limit 1;
  fresh:=health.id is not null and clock_timestamp()<least(health.reported_at,health.ingested_at)+interval '120 seconds';
  if device.state='active' then
   if health.id is null then codes:=array['GATEWAY_UNOBSERVED'];
   elsif not fresh then codes:=array['GATEWAY_STALE'];
   else
    if not health.sms_permission then codes:=array_append(codes,'GATEWAY_SMS_PERMISSION');end if;
    if health.network<>'validated' then codes:=array_append(codes,'GATEWAY_NETWORK');end if;
    if health.telephony<>'ready' then codes:=array_append(codes,'GATEWAY_TELEPHONY');end if;
    if not health.sim_selected then codes:=array_append(codes,'GATEWAY_SIM');end if;
   end if;
  end if;
  signature:=jsonb_build_array(device.state,health.id,fresh,codes);
 else raise exception 'operational_exception_source_invalid' using errcode='22023';end if;
 perform collect_ops.observe(p_kind,p_source,codes,signature);
end$$;

create function collect_ops.capture_source() returns trigger
language plpgsql security definer set search_path='' as $$
declare kind text;source uuid;
begin
 kind:=case tg_table_name when 'raw_payment_sms' then 'raw_sms' when 'parsed_payment_events' then 'allocation'
  when 'payments' then 'payment' when 'sms_notification_outbox' then 'receipt' when 'devices' then 'gateway'
  when 'health_observations' then 'gateway' when 'payment_provider_confirmations' then 'payment'
  when 'payment_provider_rejections' then 'payment' end;
 if tg_table_name='health_observations' then source:=new.device_id;
 elsif tg_table_name in('payment_provider_confirmations','payment_provider_rejections') then source:=new.payment_id;
 else source:=new.id;end if;
 perform collect_ops.refresh_source(kind,source);return new;
end$$;
create trigger zzzz_operational_raw after insert or update of parse_status on public.raw_payment_sms
 for each row execute function collect_ops.capture_source();
create trigger zzzz_operational_allocation after insert or update of allocation_status,collection_id on public.parsed_payment_events
 for each row execute function collect_ops.capture_source();
create trigger zzzz_operational_payment after insert or update of status on public.payments
 for each row execute function collect_ops.capture_source();
create trigger zzzz_operational_receipt after insert or update of state on collect_hybrid.sms_notification_outbox
 for each row execute function collect_ops.capture_source();
create trigger zzzz_operational_device after insert or update of state on collect_gateway.devices
 for each row execute function collect_ops.capture_source();
create trigger zzzz_operational_health after insert on collect_gateway.health_observations
 for each row execute function collect_ops.capture_source();
create trigger zzzz_operational_confirmation after insert on public.payment_provider_confirmations
 for each row execute function collect_ops.capture_source();
create trigger zzzz_operational_rejection after insert on collect_hybrid.payment_provider_rejections
 for each row execute function collect_ops.capture_source();

create function collect_ops.actor(p_mutation boolean) returns uuid
language plpgsql volatile security definer set search_path='' as $$
declare sid uuid;permissions text[]:=array['payments.read','notifications.read','system_health.read'];
begin
 if current_setting('transaction_isolation')<>'read committed' then
  raise exception 'operational_exception_snapshot_retry' using errcode='40001';end if;
 sid:=public._lock_notification_registration_session();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 if p_mutation then permissions:=array_append(permissions,'notifications.manage');end if;
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',permissions);
 return sid;
end$$;
create function collect_ops.utc(p_time timestamptz) returns text language sql immutable set search_path='' as $$
 select to_char(p_time at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')$$;

create function public.refresh_operational_exception_sources_v1(p_source_kind text,p_source_ids uuid[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare source uuid;
begin
 if auth.role() is distinct from 'service_role' then raise exception 'operational_exception_service_required' using errcode='42501';end if;
 if current_setting('transaction_isolation')<>'read committed' then
  raise exception 'operational_exception_snapshot_retry' using errcode='40001';end if;
 if p_source_kind is null or p_source_kind not in('raw_sms','allocation','payment','receipt','gateway')
  or p_source_ids is null or cardinality(p_source_ids) not between 1 and 25
  or array_position(p_source_ids,null) is not null
  or(select count(distinct id) from unnest(p_source_ids) id)<>cardinality(p_source_ids) then
  raise exception 'operational_exception_source_invalid' using errcode='22023';end if;
 foreach source in array p_source_ids loop perform collect_ops.refresh_source(p_source_kind,source);end loop;
 return jsonb_build_object('contract_version',1,'source_kind',p_source_kind,'checked',cardinality(p_source_ids),
  'financial_action',false,'send_action',false);
end$$;

create function public.admin_list_operational_exceptions_v1(p_active boolean default true,p_limit integer default 20,
 p_before_changed_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare rows jsonb;last jsonb;more boolean;
begin
 perform collect_ops.actor(false);
 if p_active is null or p_limit is null or p_limit not between 1 and 50
  or((p_before_changed_at is null)<>(p_before_id is null))
  or(p_before_changed_at is not null and not isfinite(p_before_changed_at)) then
  raise exception 'operational_exception_query_invalid' using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'source_kind',e.source_kind,'source_id',e.source_id,
  'reason_code',e.reason_code,'active',e.active,'revision',e.revision,'source_sha256',e.source_sha256,
  'first_observed_at',collect_ops.utc(e.first_observed_at),'last_changed_at',collect_ops.utc(e.last_changed_at),
  'acknowledged',exists(select 1 from collect_ops.exception_actions a where a.exception_id=e.id and a.expected_revision=e.revision and a.action='acknowledge'),
  'escalation_requested',exists(select 1 from collect_ops.exception_actions a where a.exception_id=e.id and a.expected_revision=e.revision and a.action='escalate'))
  order by e.last_changed_at desc,e.id desc),'[]'::jsonb) into rows
 from(select * from collect_ops.exceptions where active=p_active and
  (p_before_changed_at is null or(last_changed_at,id)<(p_before_changed_at,p_before_id))
  order by last_changed_at desc,id desc limit p_limit+1)e;
 more:=jsonb_array_length(rows)>p_limit;if more then rows:=rows-(jsonb_array_length(rows)-1);end if;
 last:=rows->(jsonb_array_length(rows)-1);
 return jsonb_build_object('contract_version',1,'checked_at',collect_ops.utc(clock_timestamp()),
  'rows',rows,'active',p_active,'limit',p_limit,
  'next_cursor',case when more then jsonb_build_object('changed_at',last->'last_changed_at','id',last->'id')else null end,
  'escalation_delivery_verified',false,'source_scan_complete',false);
end$$;

create function public.admin_act_operational_exception_v1(p_request_id uuid,p_exception_id uuid,
 p_expected_revision bigint,p_action text,p_reason_code text) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare sid uuid;prior collect_ops.exception_actions;item collect_ops.exceptions;at timestamptz;result jsonb;
begin
 sid:=collect_ops.actor(true);
 if p_request_id is null or p_exception_id is null or p_expected_revision is null or p_expected_revision not between 1 and 1000000000
  or p_action is null or p_action not in('acknowledge','escalate') or p_reason_code is null
  or p_reason_code not in('review_started','owner_review_required','uncertain_send_review','contact_review') then
  raise exception 'operational_exception_action_invalid' using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-ops-action:'||p_request_id::text,0));
 select * into prior from collect_ops.exception_actions where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid() or prior.exception_id<>p_exception_id or prior.expected_revision<>p_expected_revision
   or prior.action<>p_action or prior.reason_code<>p_reason_code then
   raise exception 'operational_exception_request_conflict' using errcode='22023';end if;
  return prior.result;
 end if;
 select * into item from collect_ops.exceptions where id=p_exception_id;
 if item.id is null then raise exception 'operational_exception_unavailable' using errcode='22023';end if;
 -- Re-check the actual source before recording review. This may update only
 -- derived operational evidence; it cannot clear or retry a financial/send source.
 perform collect_ops.refresh_source(item.source_kind,item.source_id);
 select * into item from collect_ops.exceptions where id=p_exception_id for share;
 if not item.active or item.revision<>p_expected_revision then raise exception 'operational_exception_source_changed' using errcode='55000';end if;
 at:=clock_timestamp();result:=jsonb_build_object('contract_version',1,'request_id',p_request_id,'exception_id',item.id,
  'revision',item.revision,'action',p_action,'recorded_at',collect_ops.utc(at),'source_resolved',false,
  'financial_action',false,'send_action',false,'escalation_delivery_verified',false);
 insert into collect_ops.exception_actions(request_id,exception_id,expected_revision,action,reason_code,actor_id,session_id,recorded_at,result)
  values(p_request_id,item.id,item.revision,p_action,p_reason_code,auth.uid(),sid,at,result);
 perform public.create_audit_log('operations.exception.'||p_action,'operational_exception',item.id,
  jsonb_build_object('request_id',p_request_id,'revision',item.revision,'reason_code',p_reason_code,
   'financial_action',false,'send_action',false),null);
 return result;
end$$;
create function public.admin_get_operational_exception_action_v1(p_request_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare prior collect_ops.exception_actions;
begin
 perform collect_ops.actor(false);
 if p_request_id is null then raise exception 'operational_exception_action_invalid' using errcode='22023';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('collect-ops-action:'||p_request_id::text,0))then
  return jsonb_build_object('contract_version',1,'request_id',p_request_id,'status','in_progress','receipt',null);end if;
 select * into prior from collect_ops.exception_actions where request_id=p_request_id and actor_id=auth.uid();
 return jsonb_build_object('contract_version',1,'request_id',p_request_id,
  'status',case when prior.request_id is null then 'not_recorded' else 'recorded' end,'receipt',prior.result);
end$$;
revoke all on all functions in schema collect_ops from public,anon,authenticated,service_role;
revoke all on function public.refresh_operational_exception_sources_v1(text,uuid[]),
 public.admin_list_operational_exceptions_v1(boolean,integer,timestamptz,uuid),
 public.admin_act_operational_exception_v1(uuid,uuid,bigint,text,text),
 public.admin_get_operational_exception_action_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.refresh_operational_exception_sources_v1(text,uuid[]) to service_role;
grant execute on function public.admin_list_operational_exceptions_v1(boolean,integer,timestamptz,uuid),
 public.admin_act_operational_exception_v1(uuid,uuid,bigint,text,text),
 public.admin_get_operational_exception_action_v1(uuid) to authenticated;
commit;
