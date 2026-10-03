begin;
create schema collect_integrity;
revoke all on schema collect_integrity from public,anon,authenticated,service_role;
-- Engineering defaults only: no production traffic, Google quota grant or
-- human policy approval is claimed. Counts reserve both Google phases, not
-- prices. All admitted attempts, including rejected/unknown ones, spend quota.
create table collect_integrity.policy(
 id boolean primary key default true check(id),version integer not null check(version>0),
 actor_action_minute integer not null check(actor_action_minute between 1 and 100),
 actor_daily integer not null check(actor_daily between 1 and 10000),
 actor_active integer not null check(actor_active between 1 and 10),
 global_minute integer not null check(global_minute between 1 and 10000),
 global_daily integer not null check(global_daily between 1 and 100000),
 global_active integer not null check(global_active between 1 and 100),
 lease_seconds integer not null check(lease_seconds between 30 and 300));
insert into collect_integrity.policy values(true,1,10,500,2,100,5000,20,180);
create table collect_integrity.reservations(
 id uuid primary key default gen_random_uuid(),actor_id uuid not null,session_id uuid not null,nonce uuid not null,
 action text not null check(action in('sms.ingest','group.create')),request_hash text not null check(request_hash~'^[a-f0-9]{64}$'),
 token_sha256 text not null unique check(token_sha256~'^[a-f0-9]{64}$'),receiver_hash text not null check(receiver_hash~'^[a-f0-9]{64}$'),
 payload_sha256 text not null check(payload_sha256~'^[a-f0-9]{64}$'),binding_sha256 text not null check(binding_sha256~'^[a-f0-9]{64}$'),
 policy_version integer not null,reserved_at timestamptz not null default clock_timestamp(),expires_at timestamptz not null,
 unique(actor_id,nonce),check(isfinite(reserved_at)and isfinite(expires_at)and expires_at>reserved_at));
create index integrity_actor_action_time on collect_integrity.reservations(actor_id,action,reserved_at);
create index integrity_global_time on collect_integrity.reservations(reserved_at);
create index integrity_active_expiry on collect_integrity.reservations(expires_at);
create table collect_integrity.phases(
 reservation_id uuid not null references collect_integrity.reservations(id),phase text not null check(phase in('oauth','decode')),
 started_at timestamptz not null default clock_timestamp(),primary key(reservation_id,phase));
create table collect_integrity.completions(
 reservation_id uuid primary key references collect_integrity.reservations(id),
 outcome text not null check(outcome in('completed','rejected','failed','ambiguous')),
 capability_id uuid,result jsonb,decode_duration_ms integer check(decode_duration_ms between 0 and 120000),
 provider_status integer check(provider_status between 100 and 599),completed_at timestamptz not null default clock_timestamp(),
 check((outcome='completed'and capability_id is not null and result is not null)or(outcome<>'completed'and capability_id is null and result is null)));
create function collect_integrity.immutable_evidence()returns trigger language plpgsql set search_path=''as $$begin
 raise exception 'integrity_evidence_immutable'using errcode='55000';end$$;
do $$declare t text;begin foreach t in array array['policy','reservations','phases','completions']loop
 execute format('alter table collect_integrity.%I enable row level security',t);
 execute format('revoke all on collect_integrity.%I from public,anon,authenticated,service_role',t);
 if t<>'policy'then
  execute format('create trigger integrity_evidence_immutable before update or delete on collect_integrity.%I for each row execute function collect_integrity.immutable_evidence()',t);
  execute format('create trigger integrity_evidence_immutable_truncate before truncate on collect_integrity.%I for each statement execute function collect_integrity.immutable_evidence()',t);
 end if;
end loop;end$$;

create function collect_integrity.service_required()returns void language plpgsql volatile security definer set search_path=''as $$begin
 if current_setting('role',true)is distinct from 'service_role'or auth.jwt()->>'role'is distinct from 'service_role'then
  raise exception 'integrity_service_required'using errcode='42501';end if;
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'integrity_snapshot_retry'using errcode='40001';end if;
end$$;
create function collect_integrity.require_actor(p_actor uuid,p_session uuid,p_receiver text,p_action text)
returns void language plpgsql volatile security definer set search_path=''as $$
declare profile public.profiles;consent public.receiver_mode_consents;begin
 perform collect_integrity.service_required();
 perform public._lock_notification_session_gate();
 perform 1 from auth.users where id=p_actor for share;
 perform 1 from auth.sessions where id=p_session and user_id=p_actor for share;
 if not public._notification_session_is_live(p_session,p_actor)
  or not exists(select 1 from auth.sessions where id=p_session and user_id=p_actor and created_at<=clock_timestamp())then
  raise exception 'integrity_actor_unavailable'using errcode='42501';end if;
 select * into profile from public.profiles where id=p_actor for share;
 if profile.id is null or profile.country_code is distinct from 'RW'or profile.currency_code is distinct from 'RWF'
  or profile.momo_number_hash is distinct from p_receiver or profile.momo_number_verified_at is null then
  raise exception 'integrity_receiver_unavailable'using errcode='42501';end if;
 select * into consent from public.receiver_mode_consents where user_id=p_actor order by created_at desc,id desc limit 1 for share;
 if consent.id is null or consent.enabled is distinct from true or consent.momo_number_hash is distinct from p_receiver
  or consent.created_at>clock_timestamp()or(p_action='sms.ingest'and consent.created_at<clock_timestamp()-interval '10 minutes')then
  raise exception 'integrity_consent_unavailable'using errcode='42501';end if;
end$$;
create function collect_integrity.receipt(p_id uuid,p_state text,p_result jsonb default null)returns jsonb
language sql stable security definer set search_path=''as $$
 select jsonb_build_object('contract_version',1,'reservation_id',r.id,'actor_id',r.actor_id,'session_id',r.session_id,
  'nonce',r.nonce,'action',r.action,'request_hash',r.request_hash,'token_sha256',r.token_sha256,'state',p_state,
  'can_call',p_state<>'completed','expires_at',case when p_state='completed'then p_result->>'capability_expires_at'else to_char(r.expires_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')end,
  'result',p_result)from collect_integrity.reservations r where id=p_id;
$$;

create function public.reserve_play_integrity_admission_v1(p_actor_id uuid,p_session_id uuid,p_nonce uuid,p_action text,
 p_request_hash text,p_token_sha256 text,p_receiver_hash text,p_request_payload jsonb)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare r collect_integrity.reservations;p collect_integrity.policy;c collect_integrity.completions;fingerprint text;
begin
 perform collect_integrity.require_actor(p_actor_id,p_session_id,p_receiver_hash,p_action);
 if p_nonce is null or p_action is null or p_action not in('group.create','sms.ingest')
  or p_request_hash is null or p_request_hash!~'^[a-f0-9]{64}$'or p_token_sha256 is null or p_token_sha256!~'^[a-f0-9]{64}$'
  or p_request_payload is null or jsonb_typeof(p_request_payload)<>'object'or octet_length(p_request_payload::text)>16384
  or p_request_payload->>'receiver_momo_number_hash'is distinct from p_receiver_hash
  or(p_action='group.create'and(p_request_payload->'group_is_public'is distinct from 'false'::jsonb
   or coalesce(char_length(p_request_payload->>'group_name'),0)not between 1 and 120))
  or(p_action='sms.ingest'and(p_request_payload->>'client_envelope_id'is null
   or p_request_payload->>'client_envelope_id'!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
   or p_request_payload->>'raw_body_sha256'is null or p_request_payload->>'raw_body_sha256'!~'^[a-f0-9]{64}$'
   or coalesce(char_length(p_request_payload->>'raw_sender'),0)not between 1 and 96))then
  raise exception 'integrity_input_invalid'using errcode='22023';end if;
 update collect_integrity.policy set version=version where id returning * into strict p;
 -- The row-version fence makes quota decisions atomic and refuses old
 -- transaction snapshots. Repeat admissions never refund spent capacity.
 fingerprint:=encode(extensions.digest(jsonb_build_array(p_actor_id,p_session_id,p_nonce,p_action,p_request_hash,p_token_sha256,p_receiver_hash,p_request_payload)::text,'sha256'),'hex');
 select * into r from collect_integrity.reservations where actor_id=p_actor_id and nonce=p_nonce;
 if r.id is not null then
  if r.binding_sha256<>fingerprint then raise exception 'integrity_request_conflict'using errcode='55000';end if;
  select * into c from collect_integrity.completions where reservation_id=r.id;
  if c.outcome='completed'and exists(select 1 from public.native_action_capabilities where id=c.capability_id and consumed_at is null and expires_at>clock_timestamp())then
   return collect_integrity.receipt(r.id,'completed',c.result);
  end if;
  if c.reservation_id is not null or r.expires_at<=clock_timestamp()or exists(select 1 from collect_integrity.phases where reservation_id=r.id)then
   raise exception 'integrity_reconciliation_required'using errcode='55000';end if;
  return collect_integrity.receipt(r.id,'reserved');
 end if;
 if exists(select 1 from collect_integrity.reservations where token_sha256=p_token_sha256)then
  raise exception 'integrity_token_replay'using errcode='55000';end if;
 if(select count(*)from collect_integrity.reservations where actor_id=p_actor_id and action=p_action and reserved_at>clock_timestamp()-interval '1 minute')>=p.actor_action_minute
  or(select count(*)from collect_integrity.reservations where actor_id=p_actor_id and reserved_at>clock_timestamp()-interval '24 hours')>=p.actor_daily
  or(select count(*)from collect_integrity.reservations where reserved_at>clock_timestamp()-interval '1 minute')>=p.global_minute
  or(select count(*)from collect_integrity.reservations where reserved_at>clock_timestamp()-interval '24 hours')>=p.global_daily
  or(select count(*)from collect_integrity.reservations a where actor_id=p_actor_id and expires_at>clock_timestamp()
   and not exists(select 1 from collect_integrity.completions where reservation_id=a.id and outcome in('completed','rejected','failed')))>=p.actor_active
  or(select count(*)from collect_integrity.reservations a where expires_at>clock_timestamp()
   and not exists(select 1 from collect_integrity.completions where reservation_id=a.id and outcome in('completed','rejected','failed')))>=p.global_active then
  raise exception 'integrity_resource_limit'using errcode='53300';end if;
 insert into collect_integrity.reservations(actor_id,session_id,nonce,action,request_hash,token_sha256,receiver_hash,payload_sha256,
  binding_sha256,policy_version,expires_at)values(p_actor_id,p_session_id,p_nonce,p_action,p_request_hash,p_token_sha256,p_receiver_hash,
  encode(extensions.digest(p_request_payload::text,'sha256'),'hex'),fingerprint,p.version,clock_timestamp()+make_interval(secs=>p.lease_seconds))returning * into r;
 perform collect_integrity.require_actor(p_actor_id,p_session_id,p_receiver_hash,p_action);
 return collect_integrity.receipt(r.id,'reserved');
end$$;

create function public.begin_play_integrity_admission_v1(p_actor_id uuid,p_session_id uuid,p_reservation_id uuid,p_phase text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare r collect_integrity.reservations;begin
 perform collect_integrity.service_required();
 select * into r from collect_integrity.reservations where id=p_reservation_id;
 if r.id is null or r.actor_id is distinct from p_actor_id or r.session_id is distinct from p_session_id then
  raise exception 'integrity_reservation_unavailable'using errcode='42501';end if;
 perform collect_integrity.require_actor(p_actor_id,p_session_id,r.receiver_hash,r.action);
 perform 1 from collect_integrity.policy where id for update;
 if p_phase is null or p_phase not in('oauth','decode')then raise exception 'integrity_phase_invalid'using errcode='22023';end if;
 if r.expires_at<=clock_timestamp()or exists(select 1 from collect_integrity.completions where reservation_id=r.id)
  or exists(select 1 from collect_integrity.phases where reservation_id=r.id and phase=p_phase)
  or(p_phase='decode'and not exists(select 1 from collect_integrity.phases where reservation_id=r.id and phase='oauth'))then
  raise exception 'integrity_reconciliation_required'using errcode='55000';end if;
 insert into collect_integrity.phases(reservation_id,phase)values(r.id,p_phase);
 perform collect_integrity.require_actor(p_actor_id,p_session_id,r.receiver_hash,r.action);
 return collect_integrity.receipt(r.id,p_phase||'_started');
end$$;

create function public.complete_play_integrity_admission_v1(p_actor_id uuid,p_session_id uuid,p_reservation_id uuid,p_request_payload jsonb,
 p_package_name text,p_app_verdict text,p_device_verdicts text[],p_verified_at timestamptz,p_decode_duration_ms integer,p_provider_status integer)
returns jsonb language plpgsql volatile security definer set search_path=''as $$
declare r collect_integrity.reservations;c collect_integrity.completions;cap public.native_action_capabilities;identifier uuid;result jsonb;
begin
 perform collect_integrity.service_required();
 select * into r from collect_integrity.reservations where id=p_reservation_id;
 if r.id is null or r.actor_id is distinct from p_actor_id or r.session_id is distinct from p_session_id then
  raise exception 'integrity_reservation_unavailable'using errcode='42501';end if;
 perform collect_integrity.require_actor(p_actor_id,p_session_id,r.receiver_hash,r.action);
 perform 1 from collect_integrity.policy where id for update;
 if p_request_payload is null or encode(extensions.digest(p_request_payload::text,'sha256'),'hex')<>r.payload_sha256 then
  raise exception 'integrity_completion_invalid'using errcode='22023';end if;
 select * into c from collect_integrity.completions where reservation_id=r.id;
 if c.reservation_id is not null then
  if c.outcome='completed'and exists(select 1 from public.native_action_capabilities where id=c.capability_id and consumed_at is null and expires_at>clock_timestamp())then return c.result;end if;
  raise exception 'integrity_reconciliation_required'using errcode='55000';end if;
 if r.expires_at<=clock_timestamp()or not exists(select 1 from collect_integrity.phases where reservation_id=r.id and phase='decode')then
  raise exception 'integrity_reconciliation_required'using errcode='55000';end if;
 if p_request_payload is null or encode(extensions.digest(p_request_payload::text,'sha256'),'hex')<>r.payload_sha256
  or p_decode_duration_ms is null or p_decode_duration_ms not between 0 and 120000
  or p_provider_status is null or p_provider_status not between 200 and 299
  or p_device_verdicts is null or cardinality(p_device_verdicts)not between 1 and 10
  or exists(select 1 from unnest(p_device_verdicts)v where v is null or char_length(v)>80)then
  raise exception 'integrity_completion_invalid'using errcode='22023';end if;
 identifier:=public.mint_native_action_capability(r.actor_id,r.action,r.request_hash,p_request_payload,r.receiver_hash,
  p_package_name,p_app_verdict,p_device_verdicts,p_verified_at);
 select * into strict cap from public.native_action_capabilities where id=identifier;
 result:=jsonb_build_object('status','pass','action',r.action,'request_hash',r.request_hash,'package_name',cap.package_name,
  'app_verdict',cap.app_verdict,'device_verdicts',cap.device_verdicts,'native_capability',cap.id,'capability_expires_at',cap.expires_at);
 insert into collect_integrity.completions(reservation_id,outcome,capability_id,result,decode_duration_ms,provider_status)
 values(r.id,'completed',cap.id,result,p_decode_duration_ms,p_provider_status);
 perform collect_integrity.require_actor(p_actor_id,p_session_id,r.receiver_hash,r.action);
 return result;
end$$;

create function public.finish_play_integrity_admission_v1(p_actor_id uuid,p_session_id uuid,p_reservation_id uuid,p_outcome text,
 p_decode_duration_ms integer default null,p_provider_status integer default null)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare r collect_integrity.reservations;c collect_integrity.completions;begin
 -- Cleanup cannot start provider work or mint entitlement. Exact immutable
 -- provenance permits bounded service cleanup even after logout/expiry.
 perform collect_integrity.service_required();
 select * into r from collect_integrity.reservations where id=p_reservation_id;
 if r.id is null or r.actor_id is distinct from p_actor_id or r.session_id is distinct from p_session_id then
  raise exception 'integrity_reservation_unavailable'using errcode='42501';end if;
 if p_outcome is null or p_outcome not in('rejected','failed','ambiguous')
  or(p_decode_duration_ms is not null and p_decode_duration_ms not between 0 and 120000)
  or(p_provider_status is not null and p_provider_status not between 100 and 599)then
  raise exception 'integrity_completion_invalid'using errcode='22023';end if;
 perform 1 from collect_integrity.policy where id for update;
 select * into c from collect_integrity.completions where reservation_id=r.id;
 if c.reservation_id is null then
  insert into collect_integrity.completions(reservation_id,outcome,decode_duration_ms,provider_status)
  values(r.id,p_outcome,p_decode_duration_ms,p_provider_status)returning * into c;
 end if;
 return jsonb_build_object('ok',true,'state',c.outcome);
end$$;
revoke all on all functions in schema collect_integrity from public,anon,authenticated,service_role;
revoke all on function public.reserve_play_integrity_admission_v1(uuid,uuid,uuid,text,text,text,text,jsonb),
 public.begin_play_integrity_admission_v1(uuid,uuid,uuid,text),
 public.complete_play_integrity_admission_v1(uuid,uuid,uuid,jsonb,text,text,text[],timestamptz,integer,integer),
 public.finish_play_integrity_admission_v1(uuid,uuid,uuid,text,integer,integer)from public,anon,authenticated,service_role;
grant execute on function public.reserve_play_integrity_admission_v1(uuid,uuid,uuid,text,text,text,text,jsonb),
 public.begin_play_integrity_admission_v1(uuid,uuid,uuid,text),
 public.complete_play_integrity_admission_v1(uuid,uuid,uuid,jsonb,text,text,text[],timestamptz,integer,integer),
 public.finish_play_integrity_admission_v1(uuid,uuid,uuid,text,integer,integer)to service_role;
-- New Edge admission must be rolled out first (it denies if RPCs are absent),
-- then this migration. The owner retains the existing mint implementation.
revoke execute on function public.mint_native_action_capability(uuid,text,text,jsonb,text,text,text,text[],timestamptz)
 from public,anon,authenticated,service_role;
commit;
