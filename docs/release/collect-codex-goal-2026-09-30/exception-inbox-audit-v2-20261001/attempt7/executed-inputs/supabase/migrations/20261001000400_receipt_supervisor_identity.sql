begin;

-- Dedicated signed machine identity. Initial authority is Rwanda receipt
-- shadow health only; owner activation does not grant business or send actions.
create schema collect_supervisor;
revoke all on schema collect_supervisor from public,anon,authenticated,service_role;
create table collect_supervisor.identities(
 id uuid primary key default gen_random_uuid(),
 enrollment_request_id uuid not null unique,
 owner_actor_id uuid not null,
 owner_session_id uuid not null,
 public_key_spki_base64 text not null,
 key_sha256 text not null unique check(key_sha256 ~ '^[0-9a-f]{64}$'),
 scope text not null default 'rw_receipt_shadow' check(scope='rw_receipt_shadow'),
 state text not null default 'pending' check(state in('pending','active','revoked')),
 created_at timestamptz not null,
 expires_at timestamptz not null,
 activated_at timestamptz,
 revoked_at timestamptz,
 check(isfinite(created_at) and isfinite(expires_at) and expires_at>created_at
  and expires_at<=created_at+interval '30 days'),
 check((state='pending'and activated_at is null and revoked_at is null)
  or(state='active'and activated_at is not null and revoked_at is null)
  or(state='revoked'and revoked_at is not null))
);
create table collect_supervisor.owner_requests(
 request_id uuid primary key,actor_id uuid not null,session_id uuid not null,
 action text not null check(action in('enroll','activate','revoke')),
 input jsonb not null,result jsonb not null,recorded_at timestamptz not null
);
create table collect_supervisor.requests(
 request_id uuid primary key,
 principal_id uuid not null references collect_supervisor.identities(id)on delete restrict,
 action text not null check(action in('prove_key','shadow_health')),
 key_sha256 text not null check(key_sha256 ~ '^[0-9a-f]{64}$'),
 request_sha256 text not null check(request_sha256 ~ '^[0-9a-f]{64}$'),
 issued_at timestamptz not null,recorded_at timestamptz not null,result jsonb not null,
 check(isfinite(issued_at)and isfinite(recorded_at))
);
create index supervisor_proofs on collect_supervisor.requests(principal_id,recorded_at desc)
 where action='prove_key';
do $$declare t text;begin
 foreach t in array array['identities','owner_requests','requests']loop
  execute format('alter table collect_supervisor.%I enable row level security',t);
  execute format('revoke all on collect_supervisor.%I from public,anon,authenticated,service_role',t);
 end loop;
end$$;
create function collect_supervisor.immutable_evidence()returns trigger language plpgsql set search_path=''as $$
begin raise exception 'supervisor_evidence_immutable'using errcode='55000';end$$;
create trigger supervisor_owner_request_immutable before update or delete on collect_supervisor.owner_requests
 for each row execute function collect_supervisor.immutable_evidence();
create trigger supervisor_request_immutable before update or delete on collect_supervisor.requests
 for each row execute function collect_supervisor.immutable_evidence();
create function collect_supervisor.guard_identity()returns trigger language plpgsql set search_path=''as $$
begin
 if tg_op='DELETE'then raise exception 'supervisor_identity_retained'using errcode='55000';end if;
 if (to_jsonb(new)-array['state','activated_at','revoked_at'])is distinct from
  (to_jsonb(old)-array['state','activated_at','revoked_at'])or old.state='revoked'
  or(old.state='active'and new.state not in('active','revoked'))
  or(old.activated_at is not null and new.activated_at is distinct from old.activated_at)then
  raise exception 'supervisor_identity_immutable'using errcode='55000';end if;
 return new;
end$$;
create trigger retained_supervisor_identity before update or delete on collect_supervisor.identities
 for each row execute function collect_supervisor.guard_identity();

-- The two identities must never share a signing key, regardless of enrollment
-- order. Both insert paths take the same transaction key fence before checking
-- the other retained namespace; revocation does not release the key for reuse.
create function collect_supervisor.distinct_identity_key()returns trigger
language plpgsql volatile security definer set search_path=''as $$
begin
 if current_setting('transaction_isolation')<>'read committed'then
  raise exception 'supervisor_snapshot_retry'using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-dedicated-key:'||new.key_sha256,0));
 if (tg_table_schema='collect_gateway'and exists(
  select 1 from collect_supervisor.identities where key_sha256=new.key_sha256))
  or(tg_table_schema='collect_supervisor'and exists(
  select 1 from collect_gateway.devices where key_sha256=new.key_sha256))then
  raise exception 'supervisor_key_scope_conflict'using errcode='22023';end if;
 return new;
end$$;
create trigger distinct_supervisor_signing_key before insert on collect_supervisor.identities
 for each row execute function collect_supervisor.distinct_identity_key();
create trigger distinct_gateway_signing_key before insert on collect_gateway.devices
 for each row execute function collect_supervisor.distinct_identity_key();

create function collect_supervisor.owner_actor()returns uuid
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;begin
 if current_setting('transaction_isolation')<>'read committed'then
  raise exception 'supervisor_snapshot_retry'using errcode='40001';end if;
 sid:=public._lock_notification_registration_session();
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',
  array['admin_users.manage','notifications.manage','system_health.read']);
 if not collect_admin_access.email_identity(auth.uid())then
  raise exception 'supervisor_current_email_owner_required'using errcode='42501';end if;
 return sid;
end$$;
create function collect_supervisor.validate_key(p_spki text,p_hash text)returns void
language plpgsql set search_path=''as $$
declare der bytea;x numeric:=0;y numeric:=0;i integer;
 prime numeric:=115792089210356248762697446949407573530086143415290314195533631308867097853951;
 curve_b numeric:=41058363725152142129326129780047268409114441015993725554835256314039467401291;
begin
 if p_spki is null or p_spki !~ '^[A-Za-z0-9+/]{122}==$'
  or p_hash is null or p_hash !~ '^[0-9a-f]{64}$'then
  raise exception 'supervisor_key_invalid'using errcode='22023';end if;
 der:=decode(p_spki,'base64');
 if octet_length(der)<>91 or encode(substring(der from 1 for 27),'hex')<>
  '3059301306072a8648ce3d020106082a8648ce3d03010703420004'
  or replace(encode(der,'base64'),E'\n','')<>p_spki
  or encode(extensions.digest(der,'sha256'),'hex')<>p_hash then
  raise exception 'supervisor_key_invalid'using errcode='22023';end if;
 for i in 27..58 loop x:=x*256+get_byte(der,i);end loop;
 for i in 59..90 loop y:=y*256+get_byte(der,i);end loop;
 if x>=prime or y>=prime or mod(y*y-x*x*x+3*x-curve_b,prime)<>0 then
  raise exception 'supervisor_key_invalid'using errcode='22023';end if;
end$$;
create function collect_supervisor.owner_replay(p_request uuid,p_actor uuid,p_action text,p_input jsonb)
returns jsonb language plpgsql set search_path=''as $$
declare prior collect_supervisor.owner_requests;begin
 select * into prior from collect_supervisor.owner_requests where request_id=p_request;
 if prior.request_id is null then return null;end if;
 if prior.actor_id<>p_actor or prior.action<>p_action or prior.input is distinct from p_input then
  raise exception 'supervisor_owner_request_conflict'using errcode='22023';end if;
 return prior.result;
end$$;
create function public.admin_enroll_receipt_supervisor_v1(p_request_id uuid,p_public_key_spki_base64 text,
 p_key_sha256 text,p_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;prior jsonb;input jsonb;result jsonb;principal uuid;t timestamptz;begin
 sid:=collect_supervisor.owner_actor();
 if p_request_id is null or p_expires_at is null or not isfinite(p_expires_at)then
  raise exception 'supervisor_enrollment_invalid'using errcode='22023';end if;
 perform collect_supervisor.validate_key(p_public_key_spki_base64,p_key_sha256);
 input:=jsonb_build_array(p_public_key_spki_base64,p_key_sha256,p_expires_at);
 perform pg_advisory_xact_lock(hashtextextended('collect-supervisor-owner:'||p_request_id::text,0));
 prior:=collect_supervisor.owner_replay(p_request_id,auth.uid(),'enroll',input);
 if prior is not null then return prior;end if;
 t:=clock_timestamp();
 if p_expires_at<t+interval '10 minutes'or p_expires_at>t+interval '30 days'
  or exists(select 1 from collect_gateway.devices where key_sha256=p_key_sha256)then
  raise exception 'supervisor_enrollment_invalid'using errcode='22023';end if;
 insert into collect_supervisor.identities(enrollment_request_id,owner_actor_id,owner_session_id,
  public_key_spki_base64,key_sha256,created_at,expires_at)
 values(p_request_id,auth.uid(),sid,p_public_key_spki_base64,p_key_sha256,t,p_expires_at)returning identities.id into principal;
 result:=jsonb_build_object('contract_version',1,'principal_id',principal,'request_id',p_request_id,
  'state_at_action','pending','scope','rw_receipt_shadow','key_sha256',p_key_sha256,
  'expires_at',collect_gateway.utc(p_expires_at),'recorded_at',collect_gateway.utc(t));
 insert into collect_supervisor.owner_requests values(p_request_id,auth.uid(),sid,'enroll',input,result,t);
 perform public.create_audit_log('supervisor.identity.enroll','receipt_supervisor',principal,
  jsonb_build_object('request_id',p_request_id,'scope','rw_receipt_shadow','expires_at',p_expires_at),null);
 return result;
end$$;
create function collect_supervisor.change_identity(p_principal uuid,p_request uuid,p_expected_key text,p_action text)
returns jsonb language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;item collect_supervisor.identities;prior jsonb;input jsonb;result jsonb;t timestamptz;begin
 sid:=collect_supervisor.owner_actor();
 if p_principal is null or p_request is null or p_expected_key is null
  or p_expected_key !~ '^[0-9a-f]{64}$'or p_action not in('activate','revoke')then
  raise exception 'supervisor_action_invalid'using errcode='22023';end if;
 input:=jsonb_build_array(p_principal,p_expected_key);
 perform pg_advisory_xact_lock(hashtextextended('collect-supervisor-owner:'||p_request::text,0));
 prior:=collect_supervisor.owner_replay(p_request,auth.uid(),p_action,input);
 if prior is not null then return prior;end if;
 select * into item from collect_supervisor.identities where id=p_principal for update;
 if item.id is null or item.key_sha256<>p_expected_key then
  raise exception 'supervisor_identity_unavailable'using errcode='42501';end if;
 t:=clock_timestamp();
 if p_action='activate'then
  if item.state<>'pending'or item.expires_at<=t then
   raise exception 'supervisor_activation_unavailable'using errcode='55000';end if;
  if not exists(select 1 from collect_supervisor.requests where principal_id=item.id and action='prove_key'
   and recorded_at>=t-interval '120 seconds'and issued_at>=t-interval '120 seconds'
   and issued_at<=t+interval '30 seconds')then
   raise exception 'supervisor_key_possession_required'using errcode='55000';end if;
  update collect_supervisor.identities set state='active',activated_at=t where id=item.id;
 else
  if item.state='revoked'then raise exception 'supervisor_already_revoked'using errcode='55000';end if;
  update collect_supervisor.identities set state='revoked',revoked_at=t where id=item.id;
 end if;
 result:=jsonb_build_object('contract_version',1,'principal_id',item.id,'request_id',p_request,
  'state_at_action',case p_action when 'activate'then 'active'else 'revoked'end,
  'scope',item.scope,'key_sha256',item.key_sha256,'expires_at',collect_gateway.utc(item.expires_at),
  'recorded_at',collect_gateway.utc(t));
 insert into collect_supervisor.owner_requests values(p_request,auth.uid(),sid,p_action,input,result,t);
 perform public.create_audit_log('supervisor.identity.'||p_action,'receipt_supervisor',item.id,
  jsonb_build_object('request_id',p_request,'scope',item.scope),null);
 return result;
end$$;
create function public.admin_activate_receipt_supervisor_v1(p_principal_id uuid,p_request_id uuid,p_expected_key_sha256 text)
returns jsonb language sql volatile security definer set search_path=''as $$
 select collect_supervisor.change_identity(p_principal_id,p_request_id,p_expected_key_sha256,'activate')$$;
create function public.admin_revoke_receipt_supervisor_v1(p_principal_id uuid,p_request_id uuid,p_expected_key_sha256 text)
returns jsonb language sql volatile security definer set search_path=''as $$
 select collect_supervisor.change_identity(p_principal_id,p_request_id,p_expected_key_sha256,'revoke')$$;
create function public.admin_get_receipt_supervisor_owner_request_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare prior collect_supervisor.owner_requests;begin
 perform collect_supervisor.owner_actor();
 if p_request_id is null then raise exception 'supervisor_action_invalid'using errcode='22023';end if;
 select * into prior from collect_supervisor.owner_requests where request_id=p_request_id and actor_id=auth.uid();
 return jsonb_build_object('contract_version',1,'request_id',p_request_id,
  'status',case when prior.request_id is null then 'not_recorded'else 'recorded'end,'receipt',prior.result);
exception when lock_not_available then raise exception 'supervisor_authority_busy'using errcode='55P03';
end$$;

create function collect_supervisor.require_service_identity(p_principal uuid,p_key text,p_request uuid,
 p_request_sha text,p_issued timestamptz,p_action text)returns collect_supervisor.identities
language plpgsql set search_path=''as $$
declare item collect_supervisor.identities;t timestamptz;begin
 if auth.role()is distinct from 'service_role'then raise exception 'supervisor_service_required'using errcode='42501';end if;
 if current_setting('transaction_isolation')<>'read committed'then
  raise exception 'supervisor_snapshot_retry'using errcode='40001';end if;
 if p_principal is null or p_request is null or p_key is null or p_key !~ '^[0-9a-f]{64}$'
  or p_request_sha is null or p_request_sha !~ '^[0-9a-f]{64}$'or p_issued is null or not isfinite(p_issued)
  or p_action is null or p_action not in('prove_key','shadow_health','reconcile')then
  raise exception 'supervisor_request_invalid'using errcode='22023';end if;
 select * into item from collect_supervisor.identities where id=p_principal for share;
 t:=clock_timestamp();
 if item.id is null or item.state='revoked'or item.key_sha256<>p_key or item.expires_at<=t
  or(p_action<>'prove_key'and item.state<>'active')then
  raise exception 'supervisor_credential_unavailable'using errcode='42501';end if;
 if p_issued<t-interval '30 seconds'or p_issued>t+interval '10 seconds'then
  raise exception 'supervisor_request_expired'using errcode='42501';end if;
 return item;
end$$;
create function public.receipt_supervisor_key_v1(p_principal_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare item collect_supervisor.identities;begin
 if auth.role()is distinct from 'service_role'then raise exception 'supervisor_service_required'using errcode='42501';end if;
 if current_setting('transaction_isolation')<>'read committed'then
  raise exception 'supervisor_snapshot_retry'using errcode='40001';end if;
 select * into item from collect_supervisor.identities where id=p_principal_id for share;
 if item.id is null or item.state='revoked'or item.expires_at<=clock_timestamp()then
  raise exception 'supervisor_credential_unavailable'using errcode='42501';end if;
 return jsonb_build_object('contract_version',1,'principal_id',item.id,'state',item.state,'scope',item.scope,
  'public_key_spki_base64',item.public_key_spki_base64,'key_sha256',item.key_sha256,
  'expires_at',collect_gateway.utc(item.expires_at));
end$$;
create function public.receipt_supervisor_observe_v1(p_principal_id uuid,p_request_id uuid,p_key_sha256 text,
 p_request_sha256 text,p_issued_at timestamptz,p_action text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare item collect_supervisor.identities;prior collect_supervisor.requests;result jsonb;t timestamptz;
 queue bigint;unknowns bigint;failures bigint;begin
 item:=collect_supervisor.require_service_identity(p_principal_id,p_key_sha256,p_request_id,p_request_sha256,p_issued_at,p_action);
 if p_action not in('prove_key','shadow_health')then raise exception 'supervisor_request_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-supervisor-request:'||p_request_id::text,0));
 -- Authority and the signed-request window are checked again after a lock wait.
 item:=collect_supervisor.require_service_identity(p_principal_id,p_key_sha256,p_request_id,p_request_sha256,p_issued_at,p_action);
 select * into prior from collect_supervisor.requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.principal_id<>p_principal_id or prior.key_sha256<>p_key_sha256 or prior.action<>p_action
   or prior.request_sha256<>p_request_sha256 or prior.issued_at<>p_issued_at then
   raise exception 'supervisor_request_conflict'using errcode='22023';end if;
  return prior.result;
 end if;
 t:=clock_timestamp();
 if p_action='prove_key'then
  result:=jsonb_build_object('contract_version',1,'principal_id',item.id,'request_id',p_request_id,
   'action',p_action,'observed_at',collect_gateway.utc(t),'expires_at',collect_gateway.utc(item.expires_at),
   'scope',item.scope,'mode','Shadow','business_handled',false,'financial_action',false,'send_action',false);
 else
  select count(*)filter(where o.state in('queued','awaiting_confirmation')),
   count(*)filter(where o.state in('uncertain','send_started')),
   count(*)filter(where o.state='failed_no_send')into queue,unknowns,failures
   from collect_hybrid.sms_notification_outbox o where collect_ops.payment_scope(o.payment_id);
  if greatest(queue,unknowns,failures)>1000000000 then
   raise exception 'supervisor_snapshot_unavailable'using errcode='55000';end if;
  result:=jsonb_build_object('contract_version',1,'principal_id',item.id,'request_id',p_request_id,
   'action',p_action,'observed_at',collect_gateway.utc(t),'sample_valid_until',collect_gateway.utc(least(t+interval '60 seconds',item.expires_at)),
   'expires_at',collect_gateway.utc(item.expires_at),'scope',item.scope,'mode','Shadow',
   'queued_count',queue,'unknown_count',unknowns,'failed_no_send_count',failures,
   'dispatch_enabled',coalesce((select enabled from public.feature_flags where key='hybrid_sms_notifications'),false),
   'business_handled',false,'financial_action',false,'send_action',false);
 end if;
 insert into collect_supervisor.requests values(p_request_id,item.id,p_action,p_key_sha256,p_request_sha256,p_issued_at,t,result);
 return result;
end$$;
create function public.receipt_supervisor_reconcile_v1(p_principal_id uuid,p_request_id uuid,p_key_sha256 text,
 p_request_sha256 text,p_issued_at timestamptz,p_target_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare item collect_supervisor.identities;prior collect_supervisor.requests;begin
 item:=collect_supervisor.require_service_identity(p_principal_id,p_key_sha256,p_request_id,p_request_sha256,p_issued_at,'reconcile');
 if p_target_request_id is null then raise exception 'supervisor_request_invalid'using errcode='22023';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('collect-supervisor-request:'||p_target_request_id::text,0))then
  return jsonb_build_object('contract_version',1,'target_request_id',p_target_request_id,'status','in_progress','receipt',null);end if;
 select * into prior from collect_supervisor.requests where request_id=p_target_request_id and principal_id=item.id;
 return jsonb_build_object('contract_version',1,'target_request_id',p_target_request_id,
  'status',case when prior.request_id is null then 'not_recorded'else 'recorded'end,'receipt',prior.result);
exception when lock_not_available then raise exception 'supervisor_authority_busy'using errcode='55P03';
end$$;
revoke all on all functions in schema collect_supervisor from public,anon,authenticated,service_role;
revoke all on function public.admin_enroll_receipt_supervisor_v1(uuid,text,text,timestamptz),
 public.admin_activate_receipt_supervisor_v1(uuid,uuid,text),public.admin_revoke_receipt_supervisor_v1(uuid,uuid,text),
 public.admin_get_receipt_supervisor_owner_request_v1(uuid),public.receipt_supervisor_key_v1(uuid),
 public.receipt_supervisor_observe_v1(uuid,uuid,text,text,timestamptz,text),
 public.receipt_supervisor_reconcile_v1(uuid,uuid,text,text,timestamptz,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_enroll_receipt_supervisor_v1(uuid,text,text,timestamptz),
 public.admin_activate_receipt_supervisor_v1(uuid,uuid,text),public.admin_revoke_receipt_supervisor_v1(uuid,uuid,text),
 public.admin_get_receipt_supervisor_owner_request_v1(uuid)to authenticated;
grant execute on function public.receipt_supervisor_key_v1(uuid),
 public.receipt_supervisor_observe_v1(uuid,uuid,text,text,timestamptz,text),
 public.receipt_supervisor_reconcile_v1(uuid,uuid,text,text,timestamptz,uuid)to service_role;
commit;
