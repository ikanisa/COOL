begin;

-- Identity/observation foundation only. No function issues dispatch authority,
-- credentials, receipt bodies, destinations or financial/send mutations.
create schema collect_gateway;
revoke all on schema collect_gateway from public,anon,authenticated,service_role;

create table collect_gateway.devices(
 id uuid primary key default gen_random_uuid(),
 enrollment_request_id uuid not null unique,
 owner_actor_id uuid not null,
 owner_session_id uuid not null,
 installation_id uuid not null unique,
 public_key_spki_base64 text not null,
 key_sha256 text not null unique check(key_sha256 ~ '^[0-9a-f]{64}$'),
 signing_certificate_sha256 text not null check(signing_certificate_sha256 ~ '^[0-9a-f]{64}$'),
 state text not null default 'pending' check(state in('pending','active','revoked')),
 created_at timestamptz not null default clock_timestamp(),
 activated_at timestamptz,
 revoked_at timestamptz,
 check((state='pending' and activated_at is null and revoked_at is null)
   or(state='active' and activated_at is not null and revoked_at is null)
   or(state='revoked' and revoked_at is not null))
);
-- No Auth FK: identity/evidence survives session/user deletion.
create table collect_gateway.admin_requests(
 request_id uuid primary key,
 actor_id uuid not null,
 action text not null check(action in('enroll','activate','revoke')),
 input jsonb not null,
 result jsonb not null,
 recorded_at timestamptz not null default clock_timestamp()
);
create table collect_gateway.requests(
 request_id uuid primary key,
 device_id uuid not null references collect_gateway.devices(id) on delete restrict,
 action text not null check(action in('heartbeat','callback','dispatch_grant')),
 request_sha256 text not null check(request_sha256 ~ '^[0-9a-f]{64}$'),
 payload jsonb not null,
 result jsonb not null,
 recorded_at timestamptz not null default clock_timestamp()
);
create table collect_gateway.health_observations(
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references collect_gateway.devices(id) on delete restrict,
 request_id uuid not null unique references collect_gateway.requests(request_id) on delete restrict,
 reported_at timestamptz not null,
 ingested_at timestamptz not null,
 sms_permission boolean not null,
 network text not null check(network in('validated','unvalidated','offline','unknown')),
 telephony text not null check(telephony in('ready','unavailable','unknown')),
 sim_selected boolean not null,
 sim_revision_sha256 text,
 local_pause boolean not null,
 check((sim_selected and sim_revision_sha256 is not null and sim_revision_sha256 ~ '^[0-9a-f]{64}$')
   or(not sim_selected and sim_revision_sha256 is null))
);
create index gateway_health_device_time on collect_gateway.health_observations(device_id,ingested_at desc,id);

-- Deliberately empty: no API can insert an arm or convert identity activation
-- into dispatch authority. Future governed run/policy/cap authority must own it.
create table collect_gateway.dispatch_arms(
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references collect_gateway.devices(id) on delete restrict,
 attempt_id uuid not null unique references collect_hybrid.sms_notification_attempts(id) on delete restrict,
 fence_version integer not null check(fence_version between 1 and 1000000000),
 body_sha256 text not null check(body_sha256 ~ '^[0-9a-f]{64}$'),
 destination_sha256 text not null check(destination_sha256 ~ '^[0-9a-f]{64}$'),
 segment_count integer not null check(segment_count between 1 and 10),
 armed_at timestamptz not null default clock_timestamp()
);
create table collect_gateway.segment_callbacks(
 callback_id uuid primary key,
 request_id uuid not null unique references collect_gateway.requests(request_id) on delete restrict,
 arm_id uuid not null references collect_gateway.dispatch_arms(id) on delete restrict,
 device_id uuid not null references collect_gateway.devices(id) on delete restrict,
 segment_index integer not null check(segment_index between 0 and 9),
 callback_kind text not null check(callback_kind in('sent','delivery')),
 result_code integer not null check(result_code between -1 and 200),
 tp_status integer check(tp_status between 0 and 255),
 occurred_at timestamptz not null,
 recorded_at timestamptz not null,
 unique(arm_id,segment_index,callback_kind)
);
do $$declare t text;begin
 foreach t in array array['devices','admin_requests','requests','health_observations','dispatch_arms','segment_callbacks'] loop
  execute format('alter table collect_gateway.%I enable row level security',t);
  execute format('revoke all on collect_gateway.%I from public,anon,authenticated,service_role',t);
 end loop;
end$$;

create function collect_gateway.immutable_evidence() returns trigger
language plpgsql set search_path='' as $$begin
 raise exception 'gateway_evidence_immutable' using errcode='55000';end$$;
do $$declare t text;begin
 foreach t in array array['admin_requests','requests','health_observations','dispatch_arms','segment_callbacks'] loop
  execute format('create trigger immutable_gateway_evidence before update or delete on collect_gateway.%I for each row execute function collect_gateway.immutable_evidence()',t);
 end loop;
end$$;
create function collect_gateway.protect_device_identity() returns trigger
language plpgsql set search_path='' as $$begin
 if tg_op='DELETE' then raise exception 'gateway_identity_retained' using errcode='55000';end if;
 if (to_jsonb(new)-array['state','activated_at','revoked_at']) is distinct from
    (to_jsonb(old)-array['state','activated_at','revoked_at'])
  or old.state='revoked' or (old.state='active' and new.state not in('active','revoked'))
  or (old.activated_at is not null and new.activated_at is distinct from old.activated_at)
  or (old.state='pending' and new.state='pending' and new.activated_at is not null) then
  raise exception 'gateway_identity_immutable' using errcode='55000';end if;
 return new;end$$;
create trigger retained_gateway_identity before update or delete on collect_gateway.devices
 for each row execute function collect_gateway.protect_device_identity();
create function collect_gateway.bind_arm() returns trigger language plpgsql set search_path='' as $$
declare a collect_hybrid.sms_notification_attempts;d collect_gateway.devices;
begin
 select * into d from collect_gateway.devices where id=new.device_id for share;
 select * into a from collect_hybrid.sms_notification_attempts where id=new.attempt_id for share;
 if d.state is distinct from 'active' or a.id is null or a.fence_version<>new.fence_version
  or a.body_sha256 is distinct from new.body_sha256 or a.destination_sha256 is distinct from new.destination_sha256 then
  raise exception 'gateway_arm_binding_invalid' using errcode='22023';end if;
 return new;end$$;
create trigger bind_gateway_arm before insert on collect_gateway.dispatch_arms
 for each row execute function collect_gateway.bind_arm();

create function collect_gateway.utc(p_time timestamptz) returns text language sql immutable set search_path='' as $$
 select to_char(p_time at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')$$;
create function collect_gateway.owner_actor() returns uuid language plpgsql volatile security definer set search_path='' as $$
declare s uuid;a uuid;
begin
 s:=public._lock_notification_registration_session();a:=auth.uid();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 perform collect_hybrid.require_roster_actor_authority(a,s,'platform_owner',array['notifications.manage','system_health.read']);
 return a;
end$$;
create function collect_gateway.require_service(p_device uuid,p_request uuid,p_hash text) returns void language plpgsql set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'gateway_service_required' using errcode='42501';end if;
 if p_device is null or p_request is null or p_hash is null or p_hash !~ '^[0-9a-f]{64}$' then
  raise exception 'gateway_request_invalid' using errcode='22023';end if;
end$$;
create function collect_gateway.payload_keys(p_payload jsonb,p_keys text[]) returns void language plpgsql set search_path='' as $$
begin
 if jsonb_typeof(p_payload) is distinct from 'object' or not(p_payload ?& p_keys)
  or (select count(*) from jsonb_object_keys(p_payload))<>cardinality(p_keys) then
  raise exception 'gateway_payload_invalid' using errcode='22023';end if;
end$$;
create function collect_gateway.payload_int(p_payload jsonb,p_key text,p_min integer,p_max integer)
 returns integer language plpgsql set search_path='' as $$declare n numeric;begin
 if jsonb_typeof(p_payload->p_key) is distinct from 'number' then raise exception 'gateway_payload_invalid' using errcode='22023';end if;
 n:=(p_payload->>p_key)::numeric;
 if n<p_min or n>p_max or n<>floor(n) then raise exception 'gateway_payload_invalid' using errcode='22023';end if;
 return n::integer;end$$;
create function collect_gateway.payload_uuid(p_payload jsonb,p_key text) returns uuid language plpgsql set search_path='' as $$begin
 if jsonb_typeof(p_payload->p_key) is distinct from 'string' or (p_payload->>p_key) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
  raise exception 'gateway_payload_invalid' using errcode='22023';end if;
 return (p_payload->>p_key)::uuid;end$$;
create function collect_gateway.payload_time(p_payload jsonb,p_key text) returns timestamptz language plpgsql set search_path='' as $$begin
 if jsonb_typeof(p_payload->p_key) is distinct from 'string' or (p_payload->>p_key) !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$' then
  raise exception 'gateway_payload_invalid' using errcode='22023';end if;
 begin return (p_payload->>p_key)::timestamptz;
 exception when others then raise exception 'gateway_payload_invalid' using errcode='22023';end;
end$$;
create function collect_gateway.replay(p_device uuid,p_request uuid,p_action text,p_hash text,p_payload jsonb)
 returns jsonb language plpgsql set search_path='' as $$declare r collect_gateway.requests;begin
 select * into r from collect_gateway.requests where request_id=p_request for share;
 if r.request_id is null then return null;end if;
 if r.device_id<>p_device or r.action<>p_action or r.request_sha256<>p_hash or r.payload is distinct from p_payload then
  raise exception 'gateway_request_conflict' using errcode='22023';end if;
 return r.result||jsonb_build_object('replay',true);end$$;
create function collect_gateway.owner_replay(p_actor uuid,p_request uuid,p_action text,p_input jsonb)
 returns jsonb language plpgsql set search_path='' as $$declare r collect_gateway.admin_requests;begin
 select * into r from collect_gateway.admin_requests where request_id=p_request for share;
 if r.request_id is null then return null;end if;
 if r.actor_id<>p_actor or r.action<>p_action or r.input is distinct from p_input then
  raise exception 'gateway_owner_request_conflict' using errcode='22023';end if;
 return r.result||jsonb_build_object('replay',true);end$$;

create function public.admin_enroll_gateway_device_v1(p_request_id uuid,p_installation_id uuid,
 p_public_key_spki_base64 text,p_key_sha256 text,p_signing_certificate_sha256 text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid;der bytea;i jsonb;r jsonb;d uuid;t timestamptz;
 x numeric:=0;y numeric:=0;point_byte integer;
 prime numeric:=115792089210356248762697446949407573530086143415290314195533631308867097853951;
 curve_b numeric:=41058363725152142129326129780047268409114441015993725554835256314039467401291;
begin
 actor:=collect_gateway.owner_actor();
 if p_request_id is null or p_installation_id is null or p_key_sha256 is null or p_key_sha256 !~ '^[0-9a-f]{64}$'
  or p_signing_certificate_sha256 is null or p_signing_certificate_sha256 !~ '^[0-9a-f]{64}$'
  or p_public_key_spki_base64 is null or p_public_key_spki_base64 !~ '^[A-Za-z0-9+/]{122}==$' then
  raise exception 'gateway_enrollment_invalid' using errcode='22023';end if;
 der:=decode(p_public_key_spki_base64,'base64');
 if octet_length(der)<>91 or encode(substring(der from 1 for 27),'hex')<>'3059301306072a8648ce3d020106082a8648ce3d03010703420004'
  or replace(encode(der,'base64'),E'\n','')<>p_public_key_spki_base64
  or encode(extensions.digest(der,'sha256'),'hex')<>p_key_sha256 then
  raise exception 'gateway_enrollment_invalid' using errcode='22023';end if;
 for point_byte in 0..31 loop
  x:=x*256+get_byte(der,27+point_byte);y:=y*256+get_byte(der,59+point_byte);
 end loop;
 if x>=prime or y>=prime or mod(y*y-(x*x*x-3*x+curve_b),prime)<>0 then
  raise exception 'gateway_enrollment_invalid' using errcode='22023';end if;
 -- DER, SHA and the actual P-256 curve point are checked here. Recent key
 -- possession still depends on the separately verified Edge signature.
 i:=jsonb_build_array(p_installation_id,p_public_key_spki_base64,p_key_sha256,p_signing_certificate_sha256);
 r:=collect_gateway.owner_replay(actor,p_request_id,'enroll',i);if r is not null then return r;end if;
 if exists(select 1 from collect_gateway.devices where installation_id=p_installation_id or key_sha256=p_key_sha256) then
  raise exception 'gateway_installation_already_enrolled' using errcode='22023';end if;
 t:=clock_timestamp();
 insert into collect_gateway.devices(enrollment_request_id,owner_actor_id,owner_session_id,installation_id,public_key_spki_base64,key_sha256,signing_certificate_sha256,created_at)
 values(p_request_id,actor,(auth.jwt()->>'session_id')::uuid,p_installation_id,p_public_key_spki_base64,p_key_sha256,p_signing_certificate_sha256,t) returning id into d;
 r:=jsonb_build_object('device_id',d,'request_id',p_request_id,'state_at_action','pending','recorded_at',collect_gateway.utc(t),'replay',false);
 insert into collect_gateway.admin_requests(request_id,actor_id,action,input,result,recorded_at) values(p_request_id,actor,'enroll',i,r,t);
 return r;
end$$;
create function collect_gateway.change_device(p_device uuid,p_request uuid,p_key text,p_cert text,p_action text)
 returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid;i jsonb;r jsonb;d collect_gateway.devices;t timestamptz;
begin
 actor:=collect_gateway.owner_actor();
 if p_device is null or p_request is null or p_key is null or p_key !~ '^[0-9a-f]{64}$'
  or p_cert is null or p_cert !~ '^[0-9a-f]{64}$' or p_action not in('activate','revoke') then
  raise exception 'gateway_enrollment_invalid' using errcode='22023';end if;
 i:=jsonb_build_array(p_device,p_key,p_cert);
 r:=collect_gateway.owner_replay(actor,p_request,p_action,i);if r is not null then return r;end if;
 select * into d from collect_gateway.devices where id=p_device for update;
 if d.id is null or d.key_sha256<>p_key or d.signing_certificate_sha256<>p_cert then
  raise exception 'gateway_identity_mismatch' using errcode='22023';end if;
 t:=clock_timestamp();
 if p_action='activate' then
  if d.state<>'pending' then raise exception 'gateway_activation_state_invalid' using errcode='55000';end if;
  if not exists(select 1 from collect_gateway.health_observations h where h.device_id=d.id
   and h.ingested_at>=t-interval '120 seconds' and h.ingested_at<=t
   and h.reported_at>=t-interval '120 seconds' and h.reported_at<=t+interval '30 seconds') then
   raise exception 'gateway_key_possession_required' using errcode='55000';end if;
  update collect_gateway.devices set state='active',activated_at=t where id=d.id;
 else
  if d.state='revoked' then raise exception 'gateway_already_revoked' using errcode='55000';end if;
  update collect_gateway.devices set state='revoked',revoked_at=t where id=d.id;
 end if;
 r:=jsonb_build_object('device_id',d.id,'request_id',p_request,'state_at_action',case p_action when 'activate' then 'active' else 'revoked' end,'recorded_at',collect_gateway.utc(t),'replay',false);
 insert into collect_gateway.admin_requests(request_id,actor_id,action,input,result,recorded_at) values(p_request,actor,p_action,i,r,t);
 return r;
end$$;
create function public.admin_activate_gateway_device_v1(p_device_id uuid,p_request_id uuid,p_expected_key_sha256 text,p_expected_signing_certificate_sha256 text)
returns jsonb language sql volatile security definer set search_path='' as $$
 select collect_gateway.change_device(p_device_id,p_request_id,p_expected_key_sha256,p_expected_signing_certificate_sha256,'activate')$$;
create function public.admin_revoke_gateway_device_v1(p_device_id uuid,p_request_id uuid,p_expected_key_sha256 text,p_expected_signing_certificate_sha256 text)
returns jsonb language sql volatile security definer set search_path='' as $$
 select collect_gateway.change_device(p_device_id,p_request_id,p_expected_key_sha256,p_expected_signing_certificate_sha256,'revoke')$$;

create function public.gateway_device_key_v1(p_device_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d collect_gateway.devices;begin
 if auth.role() is distinct from 'service_role' then raise exception 'gateway_service_required' using errcode='42501';end if;
 select * into d from collect_gateway.devices where id=p_device_id;
 if d.id is null then raise exception 'gateway_device_not_found' using errcode='22023';end if;
 return jsonb_build_object('device_id',d.id,'state',d.state,'public_key_spki_base64',d.public_key_spki_base64,'key_sha256',d.key_sha256,'installation_id',d.installation_id,'signing_certificate_sha256',d.signing_certificate_sha256);
end$$;
create function public.gateway_heartbeat_v1(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare d collect_gateway.devices;r jsonb;t timestamptz;observed timestamptz;h uuid;
begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);
 perform collect_gateway.payload_keys(p_payload,array['sms_permission','network','telephony','sim_selected','sim_revision_sha256','local_pause','reported_at']);
 if jsonb_typeof(p_payload->'sms_permission') is distinct from 'boolean'
  or jsonb_typeof(p_payload->'sim_selected') is distinct from 'boolean'
  or jsonb_typeof(p_payload->'local_pause') is distinct from 'boolean'
  or coalesce(p_payload->>'network','') not in('validated','unvalidated','offline','unknown')
  or coalesce(p_payload->>'telephony','') not in('ready','unavailable','unknown')
  or ((p_payload->>'sim_selected')::boolean and (jsonb_typeof(p_payload->'sim_revision_sha256') is distinct from 'string' or coalesce(p_payload->>'sim_revision_sha256','') !~ '^[0-9a-f]{64}$'))
  or (not(p_payload->>'sim_selected')::boolean and jsonb_typeof(p_payload->'sim_revision_sha256') is distinct from 'null') then
  raise exception 'gateway_payload_invalid' using errcode='22023';end if;
 observed:=collect_gateway.payload_time(p_payload,'reported_at');
 select * into d from collect_gateway.devices where id=p_device_id for update;
 if d.id is null then raise exception 'gateway_device_not_found' using errcode='22023';end if;
 if d.state='revoked' then raise exception 'gateway_device_revoked' using errcode='42501';end if;
 r:=collect_gateway.replay(d.id,p_request_id,'heartbeat',p_request_sha256,p_payload);if r is not null then return r;end if;
 t:=clock_timestamp();if observed<t-interval '120 seconds' or observed>t+interval '30 seconds' then
  raise exception 'gateway_report_time_invalid' using errcode='22023';end if;
 h:=gen_random_uuid();r:=jsonb_build_object('observation_id',h,'ingested_at',collect_gateway.utc(t),'replay',false,'carrier_proof',false);
 insert into collect_gateway.requests(request_id,device_id,action,request_sha256,payload,result,recorded_at) values(p_request_id,d.id,'heartbeat',p_request_sha256,p_payload,r,t);
 insert into collect_gateway.health_observations(id,device_id,request_id,reported_at,ingested_at,sms_permission,network,telephony,sim_selected,sim_revision_sha256,local_pause)
 values(h,d.id,p_request_id,observed,t,(p_payload->>'sms_permission')::boolean,p_payload->>'network',p_payload->>'telephony',(p_payload->>'sim_selected')::boolean,p_payload->>'sim_revision_sha256',(p_payload->>'local_pause')::boolean);
 return r;
end$$;
create function public.gateway_reconcile_v1(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare target uuid;r collect_gateway.requests;begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);
 perform collect_gateway.payload_keys(p_payload,array['target_request_id']);target:=collect_gateway.payload_uuid(p_payload,'target_request_id');
 if not exists(select 1 from collect_gateway.devices where id=p_device_id) then raise exception 'gateway_device_not_found' using errcode='22023';end if;
 select * into r from collect_gateway.requests where device_id=p_device_id and request_id=target;
 return jsonb_build_object('target_request_id',target,'outcome',case when r.request_id is null then 'unknown' else 'recorded' end,'recorded_action',r.action,'recorded_result',r.result);
end$$;
create function public.gateway_dispatch_grant_v1(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare d collect_gateway.devices;r jsonb;t timestamptz;begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);
 perform collect_gateway.payload_keys(p_payload,array[]::text[]);
 select * into d from collect_gateway.devices where id=p_device_id for update;
 if d.id is null then raise exception 'gateway_device_not_found' using errcode='22023';end if;
 if d.state='revoked' then raise exception 'gateway_device_revoked' using errcode='42501';end if;
 r:=collect_gateway.replay(d.id,p_request_id,'dispatch_grant',p_request_sha256,p_payload);if r is not null then return r;end if;
 t:=clock_timestamp();r:=jsonb_build_object('ok',false,'code','GATEWAY_DISPATCH_AUTHORITY_PENDING','device_id',d.id,'request_id',p_request_id,'replay',false);
 insert into collect_gateway.requests(request_id,device_id,action,request_sha256,payload,result,recorded_at) values(p_request_id,d.id,'dispatch_grant',p_request_sha256,p_payload,r,t);
 return r;
end$$;
create function public.gateway_callback_v1(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare d collect_gateway.devices;r jsonb;arm collect_gateway.dispatch_arms;cb uuid;attempt uuid;
 fence integer;idx integer;segments integer;rc integer;tp integer;t timestamptz;occurred timestamptz;
begin
 perform collect_gateway.require_service(p_device_id,p_request_id,p_request_sha256);
 perform collect_gateway.payload_keys(p_payload,array['callback_id','attempt_id','fence_version','segment_index','segment_count','body_sha256','destination_sha256','callback_kind','result_code','tp_status','occurred_at']);
 cb:=collect_gateway.payload_uuid(p_payload,'callback_id');attempt:=collect_gateway.payload_uuid(p_payload,'attempt_id');
 if cb=p_request_id then raise exception 'gateway_callback_id_invalid' using errcode='22023';end if;
 fence:=collect_gateway.payload_int(p_payload,'fence_version',1,1000000000);
 idx:=collect_gateway.payload_int(p_payload,'segment_index',0,9);segments:=collect_gateway.payload_int(p_payload,'segment_count',1,10);
 rc:=collect_gateway.payload_int(p_payload,'result_code',-1,200);
 if jsonb_typeof(p_payload->'tp_status') is distinct from 'null' then tp:=collect_gateway.payload_int(p_payload,'tp_status',0,255);end if;
 if jsonb_typeof(p_payload->'body_sha256') is distinct from 'string' or coalesce(p_payload->>'body_sha256','') !~ '^[0-9a-f]{64}$'
  or jsonb_typeof(p_payload->'destination_sha256') is distinct from 'string' or coalesce(p_payload->>'destination_sha256','') !~ '^[0-9a-f]{64}$'
  or coalesce(p_payload->>'callback_kind','') not in('sent','delivery') then raise exception 'gateway_payload_invalid' using errcode='22023';end if;
 occurred:=collect_gateway.payload_time(p_payload,'occurred_at');
 select * into d from collect_gateway.devices where id=p_device_id for update;
 if d.id is null then raise exception 'gateway_device_not_found' using errcode='22023';end if;
 r:=collect_gateway.replay(d.id,p_request_id,'callback',p_request_sha256,p_payload);if r is not null then return r;end if;
 select * into arm from collect_gateway.dispatch_arms where device_id=d.id and attempt_id=attempt for share;
 if arm.id is null or arm.fence_version<>fence or arm.body_sha256<>p_payload->>'body_sha256'
  or arm.destination_sha256<>p_payload->>'destination_sha256' or arm.segment_count<>segments or idx>=segments then
  raise exception 'gateway_prior_arm_required' using errcode='42501';end if;
 t:=clock_timestamp();if occurred<arm.armed_at-interval '120 seconds' or occurred>t+interval '30 seconds' then raise exception 'gateway_callback_time_invalid' using errcode='22023';end if;
 if exists(select 1 from collect_gateway.segment_callbacks where callback_id=cb or (arm_id=arm.id and segment_index=idx and callback_kind=p_payload->>'callback_kind')) then
  raise exception 'gateway_callback_conflict' using errcode='22023';end if;
 r:=jsonb_build_object('callback_id',cb,'recorded_at',collect_gateway.utc(t),'replay',false,'carrier_proof',false);
 insert into collect_gateway.requests(request_id,device_id,action,request_sha256,payload,result,recorded_at) values(p_request_id,d.id,'callback',p_request_sha256,p_payload,r,t);
 insert into collect_gateway.segment_callbacks(callback_id,request_id,arm_id,device_id,segment_index,callback_kind,result_code,tp_status,occurred_at,recorded_at)
 values(cb,p_request_id,arm.id,d.id,idx,p_payload->>'callback_kind',rc,tp,occurred,t);
 return r;
end$$;

revoke all on all functions in schema collect_gateway from public,anon,authenticated,service_role;
revoke all on function public.admin_enroll_gateway_device_v1(uuid,uuid,text,text,text),
 public.admin_activate_gateway_device_v1(uuid,uuid,text,text),public.admin_revoke_gateway_device_v1(uuid,uuid,text,text),
 public.gateway_device_key_v1(uuid),public.gateway_heartbeat_v1(uuid,uuid,text,jsonb),
 public.gateway_reconcile_v1(uuid,uuid,text,jsonb),public.gateway_callback_v1(uuid,uuid,text,jsonb),
 public.gateway_dispatch_grant_v1(uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.admin_enroll_gateway_device_v1(uuid,uuid,text,text,text),
 public.admin_activate_gateway_device_v1(uuid,uuid,text,text),public.admin_revoke_gateway_device_v1(uuid,uuid,text,text) to authenticated;
grant execute on function public.gateway_device_key_v1(uuid),public.gateway_heartbeat_v1(uuid,uuid,text,jsonb),
 public.gateway_reconcile_v1(uuid,uuid,text,jsonb),public.gateway_callback_v1(uuid,uuid,text,jsonb),
 public.gateway_dispatch_grant_v1(uuid,uuid,text,jsonb) to service_role;
notify pgrst,'reload schema';
commit;
