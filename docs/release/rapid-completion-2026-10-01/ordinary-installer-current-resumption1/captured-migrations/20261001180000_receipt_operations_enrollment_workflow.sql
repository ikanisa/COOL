begin;
-- Bounded owner workflow around the retained v2 identity operations. This does
-- not enable operating policy, create a sender, or expose signing material.
create table collect_receipt_operations.enrollment_workflow_requests(
 request_id uuid primary key,actor_id uuid not null,session_id uuid not null,
 action text not null check(action in('enroll','activate','revoke')),input jsonb not null,
 request_expires_at timestamptz not null,result jsonb not null,recorded_at timestamptz not null,
 check(isfinite(recorded_at)and isfinite(request_expires_at)and request_expires_at>recorded_at
  and request_expires_at<=recorded_at+interval '120 seconds'));
alter table collect_receipt_operations.enrollment_workflow_requests enable row level security;
revoke all on collect_receipt_operations.enrollment_workflow_requests from public,anon,authenticated,service_role;
create trigger enrollment_workflow_evidence_immutable before update or delete
 on collect_receipt_operations.enrollment_workflow_requests for each row
 execute function collect_supervisor.immutable_evidence();

create function collect_receipt_operations.enrollment_identity_row(p_identity collect_supervisor.identities)
returns jsonb language sql immutable set search_path=''as $$
 select jsonb_build_object('principal_id',p_identity.id,'key_sha256',p_identity.key_sha256,
  'state',p_identity.state,'scope',p_identity.scope,'created_at',collect_gateway.utc(p_identity.created_at),
  'expires_at',collect_gateway.utc(p_identity.expires_at),
  'activated_at',case when p_identity.activated_at is null then null else collect_gateway.utc(p_identity.activated_at)end,
  'revoked_at',case when p_identity.revoked_at is null then null else collect_gateway.utc(p_identity.revoked_at)end)
$$;

create function public.admin_enroll_receipt_operations_identity_v3(p_request_id uuid,p_public_key_spki_base64 text,
 p_key_sha256 text,p_identity_expires_at timestamptz,p_request_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;prior collect_receipt_operations.enrollment_workflow_requests;input jsonb;
 legacy jsonb;item collect_supervisor.identities;result jsonb;t timestamptz;begin
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_id is null or p_identity_expires_at is null or not isfinite(p_identity_expires_at)
  or p_request_expires_at is null or not isfinite(p_request_expires_at)
  or p_request_expires_at>t+interval '120 seconds'then raise exception 'operations_enrollment_input_invalid'using errcode='22023';end if;
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 perform collect_supervisor.validate_key(p_public_key_spki_base64,p_key_sha256);
 input:=jsonb_build_array(p_public_key_spki_base64,p_key_sha256,p_identity_expires_at,p_request_expires_at);
 perform pg_advisory_xact_lock(hashtextextended('collect-operations-owner:'||p_request_id::text,0));
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-supervisor-owner:'||p_request_id::text,0));
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 select * into prior from collect_receipt_operations.enrollment_workflow_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.action<>'enroll'or prior.input is distinct from input
   or prior.request_expires_at<>p_request_expires_at then raise exception 'operations_enrollment_request_conflict'using errcode='22023';end if;
  return prior.result;
 end if;
 if exists(select 1 from collect_receipt_operations.owner_requests where request_id=p_request_id)
  or exists(select 1 from collect_supervisor.owner_requests where request_id=p_request_id)
  then raise exception 'operations_enrollment_legacy_request_conflict'using errcode='22023';end if;
 legacy:=public.admin_enroll_receipt_operations_identity_v2(p_request_id,p_public_key_spki_base64,p_key_sha256,p_identity_expires_at);
 select * into item from collect_supervisor.identities where id=(legacy->>'principal_id')::uuid for share;
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 if item.id is null or item.enrollment_request_id<>p_request_id or item.owner_actor_id<>auth.uid()
  or item.key_sha256<>p_key_sha256 or item.expires_at<>p_identity_expires_at or item.scope<>'rw_receipt_operations'
  or item.state<>'pending'or item.expires_at<=t then raise exception 'operations_enrollment_binding_invalid'using errcode='55000';end if;
 result:=jsonb_build_object('contract_version',3,'action','enroll','request_id',p_request_id,'principal_id',item.id,
  'state_at_action','pending','scope','rw_receipt_operations','key_sha256',item.key_sha256,
  'identity_expires_at',collect_gateway.utc(item.expires_at),'recorded_at',collect_gateway.utc(t),
  'request_expires_at',collect_gateway.utc(p_request_expires_at));
 insert into collect_receipt_operations.enrollment_workflow_requests values(p_request_id,auth.uid(),sid,'enroll',input,p_request_expires_at,result,t);
 return result;end$$;

create function public.admin_activate_receipt_operations_identity_v3(p_principal_id uuid,p_request_id uuid,
 p_expected_key_sha256 text,p_request_expires_at timestamptz)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;prior collect_receipt_operations.enrollment_workflow_requests;input jsonb;
 legacy jsonb;item collect_supervisor.identities;result jsonb;t timestamptz;begin
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_principal_id is null or p_request_id is null or p_expected_key_sha256 is null or p_expected_key_sha256!~'^[0-9a-f]{64}$'
  or p_request_expires_at is null or not isfinite(p_request_expires_at)
  or p_request_expires_at>t+interval '120 seconds'then raise exception 'operations_enrollment_input_invalid'using errcode='22023';end if;
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 input:=jsonb_build_array(p_principal_id,p_expected_key_sha256,p_request_expires_at);
 perform pg_advisory_xact_lock(hashtextextended('collect-operations-owner:'||p_request_id::text,0));
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-supervisor-owner:'||p_request_id::text,0));
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 select * into prior from collect_receipt_operations.enrollment_workflow_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.action<>'activate'or prior.input is distinct from input
   or prior.request_expires_at<>p_request_expires_at then raise exception 'operations_enrollment_request_conflict'using errcode='22023';end if;
  return prior.result;
 end if;
 if exists(select 1 from collect_receipt_operations.owner_requests where request_id=p_request_id)
  or exists(select 1 from collect_supervisor.owner_requests where request_id=p_request_id)
  then raise exception 'operations_enrollment_legacy_request_conflict'using errcode='22023';end if;
 select * into item from collect_supervisor.identities where id=p_principal_id for update;
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 if item.id is null or item.owner_actor_id<>auth.uid()or item.key_sha256<>p_expected_key_sha256
  or item.scope<>'rw_receipt_operations'or item.state<>'pending'or item.expires_at<=t
  then raise exception 'operations_identity_unavailable'using errcode='42501';end if;
 legacy:=public.admin_activate_receipt_operations_identity_v2(p_principal_id,p_request_id,p_expected_key_sha256);
 select * into item from collect_supervisor.identities where id=p_principal_id for share;
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 if item.id is null or item.owner_actor_id<>auth.uid()or item.key_sha256<>p_expected_key_sha256 or item.scope<>'rw_receipt_operations'
  or item.state<>'active'or item.expires_at<=t or legacy->>'principal_id'<>p_principal_id::text
  then raise exception 'operations_enrollment_binding_invalid'using errcode='55000';end if;
 result:=jsonb_build_object('contract_version',3,'action','activate','request_id',p_request_id,'principal_id',item.id,
  'state_at_action','active','scope','rw_receipt_operations','key_sha256',item.key_sha256,
  'identity_expires_at',collect_gateway.utc(item.expires_at),'recorded_at',collect_gateway.utc(t),
  'request_expires_at',collect_gateway.utc(p_request_expires_at));
 insert into collect_receipt_operations.enrollment_workflow_requests values(p_request_id,auth.uid(),sid,'activate',input,p_request_expires_at,result,t);
 return result;end$$;

create function public.admin_revoke_receipt_operations_identity_v3(p_principal_id uuid,p_request_id uuid,
 p_expected_key_sha256 text,p_request_expires_at timestamptz,p_reason text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;prior collect_receipt_operations.enrollment_workflow_requests;input jsonb;
 legacy jsonb;item collect_supervisor.identities;source_expiry timestamptz;result jsonb;t timestamptz;reason text;reason_hash text;begin
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();reason:=btrim(p_reason);
 if p_principal_id is null or p_request_id is null or p_expected_key_sha256 is null or p_expected_key_sha256!~'^[0-9a-f]{64}$'
  or p_request_expires_at is null or not isfinite(p_request_expires_at)or p_request_expires_at>t+interval '120 seconds'
  or reason is null or length(reason)not between 8 and 500
  then raise exception 'operations_enrollment_input_invalid'using errcode='22023';end if;
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 reason_hash:=encode(extensions.digest(convert_to(reason,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended('collect-operations-owner:'||p_request_id::text,0));
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-supervisor-owner:'||p_request_id::text,0));
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 select * into prior from collect_receipt_operations.enrollment_workflow_requests where request_id=p_request_id;
 if prior.request_id is not null and(prior.actor_id<>auth.uid()or prior.action<>'revoke')
  then raise exception 'operations_enrollment_request_conflict'using errcode='22023';end if;
 if prior.request_id is null and(exists(select 1 from collect_receipt_operations.owner_requests where request_id=p_request_id)
  or exists(select 1 from collect_supervisor.owner_requests where request_id=p_request_id))
  then raise exception 'operations_enrollment_legacy_request_conflict'using errcode='22023';end if;
 select * into item from collect_supervisor.identities where id=p_principal_id for update;
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 if item.id is null or item.owner_actor_id<>auth.uid()or item.key_sha256<>p_expected_key_sha256 or item.scope<>'rw_receipt_operations'
  then raise exception 'operations_identity_unavailable'using errcode='42501';end if;
 source_expiry:=item.expires_at;
 input:=jsonb_build_array(p_principal_id,p_expected_key_sha256,source_expiry,p_request_expires_at,reason_hash);
 if prior.request_id is not null then
  if prior.input is distinct from input or prior.request_expires_at<>p_request_expires_at
   then raise exception 'operations_enrollment_request_conflict'using errcode='22023';end if;
  return prior.result;
 end if;
 if item.state not in('pending','active')then raise exception 'operations_identity_unavailable'using errcode='55000';end if;
 legacy:=public.admin_revoke_receipt_supervisor_v1(p_principal_id,p_request_id,p_expected_key_sha256);
 select * into item from collect_supervisor.identities where id=p_principal_id for share;
 sid:=collect_supervisor.owner_actor();t:=clock_timestamp();
 if p_request_expires_at<=t then raise exception 'operations_enrollment_request_expired'using errcode='55000';end if;
 if item.id is null or item.owner_actor_id<>auth.uid()or item.key_sha256<>p_expected_key_sha256 or item.scope<>'rw_receipt_operations'
  or item.state<>'revoked'or item.expires_at<>source_expiry or legacy->>'principal_id'<>p_principal_id::text
  then raise exception 'operations_enrollment_binding_invalid'using errcode='55000';end if;
 result:=jsonb_build_object('contract_version',3,'action','revoke','request_id',p_request_id,'principal_id',item.id,
  'state_at_action','revoked','scope','rw_receipt_operations','key_sha256',item.key_sha256,
  'identity_expires_at',collect_gateway.utc(item.expires_at),'recorded_at',collect_gateway.utc(t),
  'request_expires_at',collect_gateway.utc(p_request_expires_at),'reason_sha256',reason_hash);
 insert into collect_receipt_operations.enrollment_workflow_requests values(p_request_id,auth.uid(),sid,'revoke',input,p_request_expires_at,result,t);
 return result;end$$;

create function public.admin_get_receipt_operations_enrollment_request_v3(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare r collect_receipt_operations.enrollment_workflow_requests;t timestamptz;status text;begin
 perform collect_supervisor.owner_actor();
 if p_request_id is null then raise exception 'operations_enrollment_input_invalid'using errcode='22023';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('collect-operations-owner:'||p_request_id::text,0))then status:='in_progress';
 else
  perform collect_supervisor.owner_actor();
  if not pg_try_advisory_xact_lock(hashtextextended('collect-supervisor-owner:'||p_request_id::text,0))then status:='in_progress';
  else
   perform collect_supervisor.owner_actor();
   select * into r from collect_receipt_operations.enrollment_workflow_requests where request_id=p_request_id and actor_id=auth.uid();
   if r.request_id is null and(exists(select 1 from collect_receipt_operations.owner_requests where request_id=p_request_id and actor_id=auth.uid())
    or exists(select 1 from collect_supervisor.owner_requests where request_id=p_request_id and actor_id=auth.uid()))
    then raise exception 'operations_enrollment_legacy_request_conflict'using errcode='22023';end if;
   status:=case when r.request_id is null then 'not_recorded'else 'recorded'end;
  end if;
 end if;
 perform collect_supervisor.owner_actor();t:=clock_timestamp();
 return jsonb_build_object('contract_version',3,'request_id',p_request_id,'action',r.action,'status',status,
  'checked_at',collect_gateway.utc(t),'sample_valid_until',collect_gateway.utc(t+interval '60 seconds'),
  'request_expires_at',case when r.request_id is null then null else collect_gateway.utc(r.request_expires_at)end,
  'receipt',case when status='recorded'then r.result else null end);end$$;

create function public.admin_get_receipt_operations_identity_v3(p_principal_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare r collect_supervisor.identities;t timestamptz;begin
 perform collect_supervisor.owner_actor();
 if p_principal_id is null then raise exception 'operations_enrollment_input_invalid'using errcode='22023';end if;
 select * into r from collect_supervisor.identities where id=p_principal_id and owner_actor_id=auth.uid()and scope='rw_receipt_operations'for share;
 perform collect_supervisor.owner_actor();t:=clock_timestamp();
 return jsonb_build_object('contract_version',3,'checked_at',collect_gateway.utc(t),
  'sample_valid_until',collect_gateway.utc(t+interval '60 seconds'),'found',r.id is not null,
  'identity',case when r.id is null then null else collect_receipt_operations.enrollment_identity_row(r)end);end$$;

create function public.admin_list_receipt_operations_identities_v3(p_limit integer default 25,
 p_before_created_at timestamptz default null,p_before_principal_id uuid default null)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare data jsonb;t timestamptz;begin
 perform collect_supervisor.owner_actor();
 if p_limit is null or p_limit not between 1 and 25 or(p_before_created_at is null)is distinct from(p_before_principal_id is null)
  or(p_before_created_at is not null and not isfinite(p_before_created_at))
  then raise exception 'operations_enrollment_input_invalid'using errcode='22023';end if;
 with page as materialized(
  select i as identity,i.created_at,i.id from collect_supervisor.identities i
  where i.owner_actor_id=auth.uid()and i.scope='rw_receipt_operations'
   and(p_before_created_at is null or(i.created_at,i.id)<(p_before_created_at,p_before_principal_id))
  order by i.created_at desc,i.id desc limit p_limit+1 for share
 ),shown as materialized(select * from page order by created_at desc,id desc limit p_limit)
 select jsonb_build_object('rows',coalesce((select jsonb_agg(collect_receipt_operations.enrollment_identity_row(s.identity)
   order by s.created_at desc,s.id desc)from shown s),'[]'::jsonb),
  'next_cursor',case when(select count(*)from page)>p_limit then
   (select jsonb_build_object('created_at',collect_gateway.utc(created_at),'principal_id',id)
    from shown order by created_at,id limit 1)else null end)into data;
 perform collect_supervisor.owner_actor();t:=clock_timestamp();
 return jsonb_build_object('contract_version',3,'checked_at',collect_gateway.utc(t),
  'sample_valid_until',collect_gateway.utc(t+interval '60 seconds'))||data;end$$;

revoke all on function collect_receipt_operations.enrollment_identity_row(collect_supervisor.identities)from public,anon,authenticated,service_role;
revoke all on function public.admin_enroll_receipt_operations_identity_v3(uuid,text,text,timestamptz,timestamptz),
 public.admin_activate_receipt_operations_identity_v3(uuid,uuid,text,timestamptz),
 public.admin_revoke_receipt_operations_identity_v3(uuid,uuid,text,timestamptz,text),
 public.admin_get_receipt_operations_enrollment_request_v3(uuid),public.admin_get_receipt_operations_identity_v3(uuid),
 public.admin_list_receipt_operations_identities_v3(integer,timestamptz,uuid)from public,anon,authenticated,service_role;
grant execute on function public.admin_enroll_receipt_operations_identity_v3(uuid,text,text,timestamptz,timestamptz),
 public.admin_activate_receipt_operations_identity_v3(uuid,uuid,text,timestamptz),
 public.admin_revoke_receipt_operations_identity_v3(uuid,uuid,text,timestamptz,text),
 public.admin_get_receipt_operations_enrollment_request_v3(uuid),public.admin_get_receipt_operations_identity_v3(uuid),
 public.admin_list_receipt_operations_identities_v3(integer,timestamptz,uuid)to authenticated;
commit;
