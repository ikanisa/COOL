begin;
select pg_advisory_xact_lock(193517,141);

-- Local engineering ceilings. Money units are conservatively reserved cost
-- units, not a provider invoice/price. Spent/ambiguous attempts are never refunded.
create table collect_hybrid.roster_resource_policy (
 id boolean primary key default true check(id),
 actor_daily_requests integer not null check(actor_daily_requests between 1 and 100),
 actor_daily_bytes bigint not null check(actor_daily_bytes between 5242880 and 524288000),
 actor_active integer not null check(actor_active between 1 and 10),
 global_daily_requests integer not null check(global_daily_requests between 1 and 10000),
 global_daily_bytes bigint not null check(global_daily_bytes between 5242880 and 52428800000),
 global_active integer not null check(global_active between 1 and 100),
 actor_daily_cost_units bigint not null check(actor_daily_cost_units between 1 and 1000000),
 global_daily_cost_units bigint not null check(global_daily_cost_units between 1 and 100000000),
 ai_attempt_cost_units bigint not null check(ai_attempt_cost_units between 1 and 100000),
 version integer not null check(version>0)
);
insert into collect_hybrid.roster_resource_policy values(true,100,104857600,2,1000,1073741824,20,100000,1000000,10000,1);
create table collect_hybrid.roster_resource_reservations (
 id uuid primary key default gen_random_uuid(), request_id uuid not null unique,
 actor_id uuid not null,session_id uuid not null,source_sha256 text not null check(source_sha256 ~ '^[a-f0-9]{64}$'),
 source_kind text not null check(source_kind in ('text','csv','txt','xlsx','pdf','image')),
 source_bytes bigint not null check(source_bytes between 1 and 5242880),
 derived_sha256 text, input_sha256 text not null check(input_sha256 ~ '^[a-f0-9]{64}$'),
 cost_units bigint not null check(cost_units>=0),policy_version integer not null,
 reserved_at timestamptz not null default clock_timestamp(), expires_at timestamptz not null,
 check(isfinite(reserved_at) and isfinite(expires_at) and expires_at>reserved_at),
 check((source_kind='xlsx' and derived_sha256 ~ '^[a-f0-9]{64}$') or (source_kind<>'xlsx' and derived_sha256 is null))
);
create index roster_resource_actor_time_idx on collect_hybrid.roster_resource_reservations(actor_id,reserved_at);
create index roster_resource_time_idx on collect_hybrid.roster_resource_reservations(reserved_at);
create index roster_resource_expiry_idx on collect_hybrid.roster_resource_reservations(expires_at);
create table collect_hybrid.roster_resource_completions (
 reservation_id uuid primary key references collect_hybrid.roster_resource_reservations(id),
 outcome text not null check(outcome in ('preview_ready','failed','ambiguous')),
 completed_at timestamptz not null default clock_timestamp() check(isfinite(completed_at))
);
create table collect_hybrid.roster_source_verifications (
 reservation_id uuid primary key references collect_hybrid.roster_resource_reservations(id),
 source_sha256 text not null check(source_sha256 ~ '^[a-f0-9]{64}$'), derived_sha256 text,
 decoder_receipt_sha256 text not null check(decoder_receipt_sha256 ~ '^[a-f0-9]{64}$'),
 decoder_build_sha256 text not null check(decoder_build_sha256 ~ '^[a-f0-9]{64}$'),
 policy_version text not null check(policy_version='collect-roster-decoder-v1'),
 toolchain jsonb not null, summary jsonb not null, recorded_at timestamptz not null default clock_timestamp(),
 check(isfinite(recorded_at))
);
do $$ declare t text; begin
 foreach t in array array['roster_resource_policy','roster_resource_reservations','roster_resource_completions','roster_source_verifications'] loop
  execute format('alter table collect_hybrid.%I enable row level security',t);
  execute format('revoke all on collect_hybrid.%I from public,anon,authenticated,service_role',t);
  if t<>'roster_resource_policy' then
   execute format('create trigger roster_resource_immutable before update or delete on collect_hybrid.%I for each row execute function collect_hybrid.guard_roster_provenance()',t);
  end if;
 end loop;
end $$;

create function public.reserve_roster_resources(p_actor_id uuid,p_session_id uuid,p_request_id uuid,p_source_sha256 text,
 p_source_kind text,p_source_bytes bigint,p_derived_sha256 text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r collect_hybrid.roster_resource_reservations; policy collect_hybrid.roster_resource_policy;
 fingerprint text; replayed boolean:=false; finished boolean; cost bigint; boundary timestamptz:=clock_timestamp()-interval '24 hours';
begin
 perform public._lock_notification_session_gate();
 if auth.role() is distinct from 'service_role' then raise exception 'roster_service_required' using errcode='42501'; end if;
 perform collect_hybrid.require_roster_actor(p_actor_id,p_session_id);
 if p_request_id is null or p_source_sha256 is null or p_source_sha256 !~ '^[a-f0-9]{64}$' or p_source_kind is null
  or p_source_kind not in ('text','csv','txt','xlsx','pdf','image') or p_source_bytes is null or p_source_bytes not between 1 and
  (case when p_source_kind in ('text','csv','txt') then 512000 else 5242880 end)
  or (p_source_kind='xlsx' and (p_derived_sha256 is null or p_derived_sha256 !~ '^[a-f0-9]{64}$'))
  or (p_source_kind<>'xlsx' and p_derived_sha256 is not null) then raise exception 'roster_input_invalid' using errcode='22023'; end if;
 -- Serialize the entire quota decision, not a SELECT followed by a racy insert.
 -- Same Auth-first order as all roster operations. A singleton policy row makes
 -- concurrent actor/global changes atomic and auditable at policy_version.
 -- Same-value UPDATE creates a row-version fence. Under REPEATABLE READ
 -- an old waiter receives40001 instead of counting quota from a stale snapshot.
 update collect_hybrid.roster_resource_policy set version=version where id returning * into strict policy;
 fingerprint:=collect_hybrid.roster_digest(jsonb_build_array(p_actor_id,p_session_id,p_source_sha256,p_source_kind,p_source_bytes,p_derived_sha256));
 select * into r from collect_hybrid.roster_resource_reservations where request_id=p_request_id;
 if r.id is not null then
  if r.input_sha256<>fingerprint then raise exception 'roster_request_conflict' using errcode='55000'; end if;
  select exists(select 1 from collect_hybrid.roster_resource_completions where reservation_id=r.id) into finished;
  if not finished then
   -- Repair a lost cleanup ACK from an already durable preview/failure; never
   -- reacquire or redispatch an unknown decoder/provider attempt.
   insert into collect_hybrid.roster_resource_completions(reservation_id,outcome)
   select r.id,result.state from collect_hybrid.roster_import_sources source
    join collect_hybrid.roster_import_results result on result.import_id=source.id
    where source.request_id=r.request_id and source.actor_id=r.actor_id and source.session_id=r.session_id;
   select exists(select 1 from collect_hybrid.roster_resource_completions where reservation_id=r.id) into finished;
  end if;
  if not finished then
   raise exception 'roster_resource_in_progress' using errcode='55000';
  end if;
  replayed:=true;
 else
  cost:=case when p_source_kind in ('image','pdf') then policy.ai_attempt_cost_units else 0 end;
  if (select count(*) from collect_hybrid.roster_resource_reservations where actor_id=p_actor_id and reserved_at>boundary)>=policy.actor_daily_requests
   or (select coalesce(sum(source_bytes),0) from collect_hybrid.roster_resource_reservations where actor_id=p_actor_id and reserved_at>boundary)+p_source_bytes>policy.actor_daily_bytes
   or (select coalesce(sum(cost_units),0) from collect_hybrid.roster_resource_reservations where actor_id=p_actor_id and reserved_at>boundary)+cost>policy.actor_daily_cost_units
   or (select count(*) from collect_hybrid.roster_resource_reservations where reserved_at>boundary)>=policy.global_daily_requests
   or (select coalesce(sum(source_bytes),0) from collect_hybrid.roster_resource_reservations where reserved_at>boundary)+p_source_bytes>policy.global_daily_bytes
   or (select coalesce(sum(cost_units),0) from collect_hybrid.roster_resource_reservations where reserved_at>boundary)+cost>policy.global_daily_cost_units then
   raise exception 'roster_resource_limit' using errcode='55000'; end if;
  if (select count(*) from collect_hybrid.roster_resource_reservations a where a.actor_id=p_actor_id and a.expires_at>clock_timestamp()
   and not exists(select 1 from collect_hybrid.roster_resource_completions c where c.reservation_id=a.id and c.outcome<>'ambiguous'))>=policy.actor_active
   or (select count(*) from collect_hybrid.roster_resource_reservations a where a.expires_at>clock_timestamp()
   and not exists(select 1 from collect_hybrid.roster_resource_completions c where c.reservation_id=a.id and c.outcome<>'ambiguous'))>=policy.global_active then
   raise exception 'roster_resource_limit' using errcode='55000'; end if;
  insert into collect_hybrid.roster_resource_reservations(request_id,actor_id,session_id,source_sha256,source_kind,source_bytes,
   derived_sha256,input_sha256,cost_units,policy_version,expires_at)
  values(p_request_id,p_actor_id,p_session_id,p_source_sha256,p_source_kind,p_source_bytes,p_derived_sha256,fingerprint,cost,policy.version,
   clock_timestamp()+interval '180 seconds') returning * into r;
  finished:=false;
 end if;
 return jsonb_build_object('contract_version',1,'ok',true,'reservation_id',r.id,'request_id',r.request_id,'actor_id',r.actor_id,
  'session_id',r.session_id,'source_sha256',r.source_sha256,'state',case when finished then 'finished' else 'reserved' end,
  'replayed',replayed,'expires_at',r.expires_at);
end $$;

create function public.verify_roster_source_integrity(p_reservation_id uuid,p_actor_id uuid,p_session_id uuid,
 p_decoder_receipt_sha256 text,p_decoder_build_sha256 text,p_policy_version text,p_toolchain jsonb,p_summary jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r collect_hybrid.roster_resource_reservations; v collect_hybrid.roster_source_verifications;
begin
 perform public._lock_notification_session_gate();
 if auth.role() is distinct from 'service_role' then raise exception 'roster_service_required' using errcode='42501'; end if;
 perform collect_hybrid.require_roster_actor(p_actor_id,p_session_id);
 select * into r from collect_hybrid.roster_resource_reservations where id=p_reservation_id for update;
 if r.id is null or r.actor_id<>p_actor_id or r.session_id<>p_session_id or r.source_kind not in ('xlsx','image','pdf') then
  raise exception 'roster_resource_unavailable' using errcode='42501'; end if;
 if p_decoder_receipt_sha256 is null or p_decoder_receipt_sha256 !~ '^[a-f0-9]{64}$'
  or p_decoder_build_sha256 is null or p_decoder_build_sha256 !~ '^[a-f0-9]{64}$'
  or p_policy_version is distinct from 'collect-roster-decoder-v1' or p_toolchain is distinct from
   '{"python":"3.12","pillow":"12.0.0","pypdfium2":"5.2.0","pypdf":"6.7.0","openpyxl":"3.1.5","defusedxml":"0.7.1"}'::jsonb
  or p_summary is null or jsonb_typeof(p_summary)<>'object' or not (p_summary ?& array['frames','pages','pixels','expanded_bytes'])
  or (select count(*) from jsonb_object_keys(p_summary))<>4
  or exists(select 1 from jsonb_each(p_summary) where jsonb_typeof(value)<>'number' or value::text !~ '^[0-9]+$'
    or value::text::numeric>160000000)
  or (p_summary->>'frames')::numeric>20 or (p_summary->>'pages')::numeric>20 or (p_summary->>'pixels')::numeric>40000000
  or (r.source_kind='image' and ((p_summary->>'frames')::numeric<1 or (p_summary->>'pages')::numeric<>0 or (p_summary->>'pixels')::numeric<1))
  or (r.source_kind='pdf' and ((p_summary->>'pages')::numeric<1 or (p_summary->>'frames')::numeric<>0 or (p_summary->>'pixels')::numeric<1))
  or (r.source_kind='xlsx' and ((p_summary->>'frames')::numeric<>0 or (p_summary->>'pages')::numeric<>0 or (p_summary->>'pixels')::numeric<>0
    or (p_summary->>'expanded_bytes')::numeric>8388608)) then raise exception 'roster_input_invalid' using errcode='22023'; end if;
 select * into v from collect_hybrid.roster_source_verifications where reservation_id=r.id;
 if v.reservation_id is not null then
  if v.decoder_receipt_sha256<>p_decoder_receipt_sha256 or v.decoder_build_sha256<>p_decoder_build_sha256 or v.toolchain<>p_toolchain or v.summary<>p_summary then
   raise exception 'roster_request_conflict' using errcode='55000'; end if;
 else
  if r.expires_at<=clock_timestamp() or exists(select 1 from collect_hybrid.roster_resource_completions where reservation_id=r.id) then
   raise exception 'roster_resource_expired' using errcode='55000'; end if;
  insert into collect_hybrid.roster_source_verifications values(r.id,r.source_sha256,r.derived_sha256,p_decoder_receipt_sha256,p_decoder_build_sha256,
   p_policy_version,p_toolchain,p_summary,clock_timestamp());
 end if;
 return jsonb_build_object('contract_version',1,'ok',true,'reservation_id',r.id,'source_sha256',r.source_sha256,
  'derived_sha256',r.derived_sha256,'decoder_receipt_sha256',p_decoder_receipt_sha256,'verified',true);
end $$;

create function public.finish_roster_resources(p_reservation_id uuid,p_actor_id uuid,p_session_id uuid,p_outcome text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r collect_hybrid.roster_resource_reservations; c collect_hybrid.roster_resource_completions;
begin
 perform public._lock_notification_session_gate();
 if auth.role() is distinct from 'service_role' then raise exception 'roster_service_required' using errcode='42501'; end if;
 perform collect_hybrid.require_roster_actor(p_actor_id,p_session_id);
 select * into r from collect_hybrid.roster_resource_reservations where id=p_reservation_id for update;
 if r.id is null or r.actor_id<>p_actor_id or r.session_id<>p_session_id then raise exception 'roster_resource_unavailable' using errcode='42501'; end if;
 if p_outcome is null or p_outcome not in ('preview_ready','failed','ambiguous') then raise exception 'roster_input_invalid' using errcode='22023'; end if;
 select * into c from collect_hybrid.roster_resource_completions where reservation_id=r.id;
 if c.reservation_id is not null then
  if c.outcome<>p_outcome then raise exception 'roster_request_conflict' using errcode='55000'; end if;
 else
  insert into collect_hybrid.roster_resource_completions values(r.id,p_outcome,clock_timestamp());
 end if;
 return jsonb_build_object('contract_version',1,'ok',true,'reservation_id',r.id,'outcome',p_outcome,'charged',true);
end $$;

-- Integrity is a prerequisite to creating new image/PDF/workbook provenance.
-- Existing rows remain unchanged and replayable. Clients keep the exact142
-- receipt shape; its conservative client-derived label is not upgraded silently.
alter function public.create_roster_import_source(uuid,uuid,uuid,text,text,bigint,text,text,text,text,bigint,boolean,text,jsonb)
 rename to _create_roster_import_source_v142;
revoke all on function public._create_roster_import_source_v142(uuid,uuid,uuid,text,text,bigint,text,text,text,text,bigint,boolean,text,jsonb)
 from public,anon,authenticated,service_role;
create function public.create_roster_import_source(p_actor_id uuid,p_session_id uuid,p_request_id uuid,p_source_kind text,
 p_original_sha256 text,p_original_size bigint,p_client_filename text,p_declared_mime text,p_detected_type text,
 p_derived_sha256 text,p_derived_size bigint,p_ai_consent boolean,p_consent_version text,p_ai_metadata jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r collect_hybrid.roster_resource_reservations;
begin
 perform public._lock_notification_session_gate();
 if auth.role() is distinct from 'service_role' then raise exception 'roster_service_required' using errcode='42501'; end if;
 perform collect_hybrid.require_roster_actor(p_actor_id,p_session_id);
 if not exists(select 1 from collect_hybrid.roster_import_sources where request_id=p_request_id) then
  select * into r from collect_hybrid.roster_resource_reservations where request_id=p_request_id for update;
  if r.id is null or r.actor_id<>p_actor_id or r.session_id<>p_session_id or r.source_sha256<>p_original_sha256
   or r.source_kind<>p_source_kind or r.source_bytes<>p_original_size or r.derived_sha256 is distinct from p_derived_sha256
   or r.expires_at<=clock_timestamp() or exists(select 1 from collect_hybrid.roster_resource_completions where reservation_id=r.id) then
   raise exception 'roster_resource_unavailable' using errcode='42501'; end if;
  if p_source_kind in ('xlsx','image','pdf') and not exists(select 1 from collect_hybrid.roster_source_verifications where reservation_id=r.id) then
   raise exception 'roster_source_unverified' using errcode='42501'; end if;
 end if;
 return public._create_roster_import_source_v142(p_actor_id,p_session_id,p_request_id,p_source_kind,p_original_sha256,p_original_size,
  p_client_filename,p_declared_mime,p_detected_type,p_derived_sha256,p_derived_size,p_ai_consent,p_consent_version,p_ai_metadata);
end $$;
revoke all on function public.reserve_roster_resources(uuid,uuid,uuid,text,text,bigint,text),
 public.verify_roster_source_integrity(uuid,uuid,uuid,text,text,text,jsonb,jsonb),public.finish_roster_resources(uuid,uuid,uuid,text),
 public.create_roster_import_source(uuid,uuid,uuid,text,text,bigint,text,text,text,text,bigint,boolean,text,jsonb)
 from public,anon,authenticated,service_role;
grant execute on function public.reserve_roster_resources(uuid,uuid,uuid,text,text,bigint,text),
 public.verify_roster_source_integrity(uuid,uuid,uuid,text,text,text,jsonb,jsonb),public.finish_roster_resources(uuid,uuid,uuid,text),
 public.create_roster_import_source(uuid,uuid,uuid,text,text,bigint,text,text,text,text,bigint,boolean,text,jsonb) to service_role;
commit;
