begin;

-- Add original-request evidence and bounded Admin reads without replacing v1.
do $$begin
 if to_regprocedure('public.admin_update_runtime_control_v1(text,jsonb,jsonb,bigint,text)') is null
  or to_regprocedure('collect_admin_access.normalized_operator_reason(text)') is null
  or to_regclass('collect_admin_access.email_approvals') is null then
  raise exception 'runtime_control_v2_prerequisite_required' using errcode='55000';end if;
end$$;

create table collect_security.runtime_control_requests (
 request_id uuid primary key,
 actor_id uuid not null, session_id uuid not null,
 family text not null, identity jsonb not null check(jsonb_typeof(identity)='object' and octet_length(identity::text)<=2048),
 expected_revision bigint not null check(expected_revision between 0 and 1000000000),
 patch_json text not null check(octet_length(patch_json) between 2 and 65536),
 reason_sha256 text not null check(reason_sha256 ~ '^[a-f0-9]{64}$'),
 reason_characters integer not null check(reason_characters between 8 and 500),
 request_fingerprint text not null check(request_fingerprint ~ '^[a-f0-9]{64}$'),
 expires_at timestamptz not null check(isfinite(expires_at)),
 recorded_at timestamptz not null check(isfinite(recorded_at) and recorded_at<expires_at),
 receipt jsonb not null check(jsonb_typeof(receipt)='object'),
 event_id uuid unique references collect_security.runtime_control_events(id)
);
alter table collect_security.runtime_control_requests enable row level security;
revoke all on collect_security.runtime_control_requests from public,anon,authenticated,service_role;
create function collect_security.guard_runtime_control_request_v2() returns trigger
language plpgsql set search_path='' as $$begin
 raise exception 'runtime_control_request_immutable' using errcode='55000';end$$;
create trigger runtime_control_request_immutable before update or delete on collect_security.runtime_control_requests
 for each row execute function collect_security.guard_runtime_control_request_v2();
create index runtime_control_event_identity_page_v2 on collect_security.runtime_control_events
 (family,identity_sha256,recorded_at desc,id desc);

create function collect_security.runtime_control_v2_spec(p_family text) returns jsonb
language plpgsql set search_path='' as $$declare spec jsonb:=collect_security.runtime_control_spec(p_family);begin
 if p_family is null or not p_family=any(array['account_request_reason_options','admin_navigation_items','admin_queue_filter_options','admin_queue_signals','admin_queue_sla_policies','admin_queue_specs','brand_entities','collection_category_subtypes','collection_purpose_templates','collection_type_catalog','collection_type_country_rules','feature_flags','notification_channels','notification_event_types','notification_template_versions','notification_templates','otp_policy','payment_entrypoints','policy_document_sections','policy_documents','roster_resource_policy','sms_receipt_member_consents','sms_receipt_policies','support_channels','system_settings'])
  or spec is null or coalesce((spec->>'user_owned')::boolean,false) then
  raise exception 'runtime_control_family_invalid' using errcode='22023';end if;
 return spec;
end$$;
create function collect_security.runtime_control_v2_utc(p_at timestamptz) returns text
language sql immutable strict set search_path='' as $$
 select to_char(p_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
$$;
create function collect_security.runtime_control_v2_deadline(p_expires_at timestamptz,p_initial boolean default false) returns void
language plpgsql set search_path='' as $$declare at_time timestamptz:=clock_timestamp();begin
 if p_expires_at is null or not isfinite(p_expires_at) or p_expires_at<=at_time
  or p_initial and p_expires_at>at_time+interval '120 seconds' then
  raise exception 'runtime_control_request_expired' using errcode='22023';end if;
 if current_setting('transaction_isolation')<>'read committed' then
  raise exception 'runtime_control_read_committed_required' using errcode='25001';end if;
end$$;

-- Same current email/transition authority and SHARE row locks as the current
-- roster helper. A read observation avoids its global exclusive roster writer
-- lock: an unrelated blocked mutation cannot hide original-request progress.
-- Missing manage grants are an ordinary capability=false only after successful
-- read/session/approval/role validation; malformed registry and sessions fail.
create function collect_security.runtime_control_v2_observe(p_family text,p_audit boolean default false) returns jsonb
language plpgsql security definer set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_v2_spec(p_family);sid uuid;u auth.users;s auth.sessions;
 role_uuid uuid;mode_value text;approval_time timestamptz;approval_expiry timestamptz;permission text;required text[];manage text[];can_manage boolean:=true;
begin
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'runtime_control_read_committed_required' using errcode='25001';end if;
 if not pg_try_advisory_xact_lock_shared(193517,141) then raise exception 'runtime_control_authority_unavailable' using errcode='42501';end if;
 begin
  lock table collect_admin_access.operator_auth_policy,collect_admin_access.email_approvals,collect_admin_access.whatsapp_approvals,
   public.admin_user_roles,public.admin_roles,public.admin_role_permissions,public.admin_permissions in share mode nowait;
 exception when lock_not_available then raise exception 'runtime_control_authority_unavailable' using errcode='42501';end;
 sid:=public._lock_notification_registration_session();
 required:=array[case when p_audit then 'audit.read' else spec->>'read_permission' end];
 manage:=array[spec->>'permission'];
 if spec ? 'additional_permission' then manage:=array_append(manage,spec->>'additional_permission');end if;
 if exists(select 1 from unnest(required||manage)n where n is null or n !~ '^[a-z_]+(\.[a-z_]+)+$')
  or exists(select 1 from unnest(required||manage)n where not exists(select 1 from public.admin_permissions p where p.name=n)) then
  raise exception 'runtime_control_registry_invalid' using errcode='55000';end if;
 select mode into mode_value from collect_admin_access.operator_auth_policy where id for share;
 if mode_value is null or mode_value not in('email','transition') then raise exception 'runtime_control_authority_invalid' using errcode='55000';end if;
 select * into u from auth.users where id=auth.uid() for share;
 select * into s from auth.sessions where id=sid and user_id=auth.uid() for share;
 if u.id is null or s.id is null or s.created_at is null or not isfinite(s.created_at)
  or s.created_at>clock_timestamp() or s.aal::text not in('aal1','aal2') or s.aal is null
  or s.not_after is not null and (not isfinite(s.not_after) or s.not_after<=clock_timestamp())
  or u.deleted_at is not null or coalesce(u.is_anonymous,false) or u.banned_until>clock_timestamp() then
  raise exception 'runtime_control_session_required' using errcode='42501';end if;
 if u.email_confirmed_at is not null then
  select approved_at,expires_at into approval_time,approval_expiry from collect_admin_access.email_approvals a
   where a.user_id=auth.uid() and a.email=lower(btrim(u.email)) and a.revoked_at is null
    and (a.expires_at is null or a.expires_at>clock_timestamp()) for share;
 end if;
 if approval_time is null and mode_value='transition' and u.phone_confirmed_at is not null
  and not exists(select 1 from collect_admin_access.email_approvals where user_id=auth.uid()) then
  select approved_at,expires_at into approval_time,approval_expiry from collect_admin_access.whatsapp_approvals a
   where a.user_id=auth.uid() and a.phone_e164='+'||ltrim(u.phone,'+') and a.revoked_at is null
    and (a.expires_at is null or a.expires_at>clock_timestamp()) for share;
 end if;
 select r.id into role_uuid from public.admin_user_roles ur join public.admin_roles r on r.id=ur.role_id and r.name='platform_owner'
  where ur.user_id=auth.uid() and ur.revoked_at is null and s.created_at>=ur.created_at
   and approval_time is not null and s.created_at>=approval_time order by ur.created_at for share of ur,r;
 if role_uuid is null then raise exception 'runtime_control_permission_required' using errcode='42501';end if;
 for permission in select distinct n from unnest(required||manage)n order by n loop
  perform 1 from public.admin_role_permissions where role_id=role_uuid and permission_name=permission for share;
  if not found then
   if permission=any(required) then raise exception 'runtime_control_permission_required' using errcode='42501';end if;
   can_manage:=false;
  end if;
 end loop;
 -- Authority times can elapse during a real row wait. Revalidate every clock
 -- predicate after the last permission lock, preserving the locked evidence.
 if approval_expiry is not null and approval_expiry<=clock_timestamp()
  or not public._notification_session_is_live(sid,auth.uid())
  or not collect_admin_access.approved_identity(auth.uid()) then raise exception 'runtime_control_session_required' using errcode='42501';end if;
 return jsonb_build_object('session_id',sid,'can_manage',can_manage);
end$$;

create function collect_security.runtime_control_v2_fingerprint(p_request_id uuid,p_family text,p_identity jsonb,p_patch_json text,p_expected_revision bigint,p_reason_sha256 text,p_expires_at timestamptz)
returns text language plpgsql set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_v2_spec(p_family);lines text[];field text;begin
 perform collect_security.runtime_control_check_identity(p_family,p_identity);
 lines:=array['collect-runtime-control-request-v2',p_request_id::text,p_family];
 for field in select jsonb_array_elements_text(spec->'identity') loop lines:=array_append(lines,field||'='||(p_identity->>field));end loop;
 lines:=lines||array[p_expected_revision::text,collect_security.runtime_control_v2_utc(p_expires_at),
  encode(extensions.digest(convert_to(p_patch_json,'UTF8'),'sha256'),'hex'),p_reason_sha256];
 return encode(extensions.digest(convert_to(array_to_string(lines,E'\n'),'UTF8'),'sha256'),'hex');
end$$;
create function collect_security.runtime_control_v2_project(p_family text,p_value jsonb) returns jsonb
language sql stable set search_path='' as $$
 select case when p_value is null or p_value='null'::jsonb then null else
 (select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) from jsonb_each(p_value)e(k,v)
  where (collect_security.runtime_control_spec(p_family)->'identity')?k or (collect_security.runtime_control_spec(p_family)->'writable')?k) end
$$;

create function public.admin_get_runtime_control_v2(p_family text,p_identity jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare observed jsonb;value jsonb;at_time timestamptz;begin
 perform collect_security.runtime_control_v2_spec(p_family);
 observed:=collect_security.runtime_control_v2_observe(p_family);
 value:=public.admin_get_runtime_control_v1(p_family,p_identity);
 perform collect_security.runtime_control_actor(p_family,true);
 observed:=collect_security.runtime_control_v2_observe(p_family);at_time:=clock_timestamp();
 return (value-'contract_version')||jsonb_build_object('contract_version',2,'scope','runtime_controls',
  'value',collect_security.runtime_control_v2_project(p_family,value->'value'),'checked_at',collect_security.runtime_control_v2_utc(at_time),
  'sample_valid_until',collect_security.runtime_control_v2_utc(at_time+interval '60 seconds'),'can_manage',observed->'can_manage');
end$$;

create function public.admin_list_runtime_controls_v2(p_family text,p_limit integer default 25,p_after_identity jsonb default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare spec jsonb:=collect_security.runtime_control_v2_spec(p_family);observed jsonb;head record;value jsonb;rows jsonb:='[]';cursor jsonb;counted integer:=0;at_time timestamptz;types jsonb;begin
 observed:=collect_security.runtime_control_v2_observe(p_family);
 if p_limit is null or p_limit not between 1 and 25 then raise exception 'runtime_control_query_invalid' using errcode='22023';end if;
 if p_after_identity is not null then perform collect_security.runtime_control_check_identity(p_family,p_after_identity);end if;
 for head in select h.identity from collect_security.runtime_control_heads h
  where h.family=p_family and (p_after_identity is null or h.identity>p_after_identity) order by h.identity limit p_limit+1 loop
  counted:=counted+1;if counted>p_limit then exit;end if;
  value:=public.admin_get_runtime_control_v1(p_family,head.identity);
  rows:=rows||jsonb_build_array((value-array['contract_version','ok','family'])||jsonb_build_object('value',collect_security.runtime_control_v2_project(p_family,value->'value')));
  cursor:=head.identity;
 end loop;
 if counted<=p_limit then cursor:=null;end if;
 perform collect_security.runtime_control_actor(p_family,true);
 observed:=collect_security.runtime_control_v2_observe(p_family);at_time:=clock_timestamp();
 select coalesce(jsonb_object_agg(k,v),'{}') into types from jsonb_each(spec->'types')e(k,v) where (spec->'identity')?k or (spec->'writable')?k;
 return jsonb_build_object('contract_version',2,'scope','runtime_controls','family',p_family,'checked_at',collect_security.runtime_control_v2_utc(at_time),
  'sample_valid_until',collect_security.runtime_control_v2_utc(at_time+interval '60 seconds'),'limit',p_limit,
  'descriptor',jsonb_build_object('identity_fields',spec->'identity','writable_fields',spec->'writable','immutable_fields',coalesce(spec->'immutable_after_create','[]'),
   'nullable_fields',(select coalesce(jsonb_agg(k),'[]') from jsonb_array_elements_text(spec->'nullable')k where (spec->'identity')?k or (spec->'writable')?k),'field_types',types,'create_allowed',(spec->>'create_allowed')::boolean,'can_manage',observed->'can_manage'),
  'rows',rows,'next_cursor',cursor);
end$$;

create function public.admin_update_runtime_control_v2(p_request_id uuid,p_family text,p_identity jsonb,p_patch_json text,p_expected_revision bigint,p_reason text,p_expires_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare sid uuid;reason_text text:=collect_admin_access.normalized_operator_reason(p_reason);reason_hash text;fingerprint text;
 prior collect_security.runtime_control_requests;patch jsonb;changed_receipt jsonb;receipt jsonb;at_time timestamptz;event_uuid uuid;begin
 perform collect_security.runtime_control_v2_spec(p_family);
 perform collect_security.runtime_control_v2_deadline(p_expires_at,true);
 sid:=collect_security.runtime_control_actor(p_family);
 perform collect_security.runtime_control_v2_deadline(p_expires_at);
 if p_request_id is null or p_expected_revision is null or p_expected_revision not between 0 and 1000000000
  or p_patch_json is null or octet_length(p_patch_json) not between 2 and 65536
  or char_length(reason_text) not between 8 and 500 or regexp_replace(reason_text,E'[\n\r\t]','','g') ~ '[[:cntrl:]]' then
  raise exception 'runtime_control_request_invalid' using errcode='22023';end if;
 perform collect_security.runtime_control_check_identity(p_family,p_identity);
 reason_hash:=encode(extensions.digest(convert_to(reason_text,'UTF8'),'sha256'),'hex');
 fingerprint:=collect_security.runtime_control_v2_fingerprint(p_request_id,p_family,p_identity,p_patch_json,p_expected_revision,reason_hash,p_expires_at);
 -- The actor marker distinguishes the original actor while its uncommitted
 -- request row is invisible. It never creates or extends mutation authority.
 perform pg_advisory_xact_lock(hashtextextended('collect-runtime-control-request-actor:'||p_request_id::text||':'||auth.uid()::text,0));
 perform pg_advisory_xact_lock(hashtextextended('collect-runtime-control-request:'||p_request_id::text,0));
 if sid is distinct from collect_security.runtime_control_actor(p_family) then raise exception 'runtime_control_session_required' using errcode='42501';end if;
 perform collect_security.runtime_control_v2_deadline(p_expires_at);
 select * into prior from collect_security.runtime_control_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id is distinct from auth.uid() or prior.session_id is distinct from sid then raise exception 'runtime_control_request_owner_required' using errcode='42501';end if;
  if prior.family is distinct from p_family or prior.identity is distinct from p_identity or prior.expected_revision is distinct from p_expected_revision
   or prior.patch_json is distinct from p_patch_json or prior.reason_sha256 is distinct from reason_hash or prior.reason_characters is distinct from char_length(reason_text)
   or prior.expires_at is distinct from p_expires_at or prior.request_fingerprint is distinct from fingerprint then raise exception 'runtime_control_request_conflict' using errcode='22023';end if;
  return prior.receipt;
 end if;
 begin patch:=p_patch_json::jsonb;exception when invalid_text_representation then raise exception 'runtime_control_patch_invalid' using errcode='22023';end;
 changed_receipt:=public.admin_update_runtime_control_v1(p_family,p_identity,patch,p_expected_revision,reason_text);
 if sid is distinct from collect_security.runtime_control_actor(p_family) then raise exception 'runtime_control_session_required' using errcode='42501';end if;
 perform collect_security.runtime_control_v2_deadline(p_expires_at);
 if (changed_receipt->>'changed')::boolean then
  select e.id into strict event_uuid from collect_security.runtime_control_events e where e.family=p_family
   and e.identity_sha256=collect_security.runtime_control_hash(p_identity) and e.revision=(changed_receipt->>'revision')::bigint
   and e.actor_id=auth.uid() and e.session_id=sid and e.authority='live_operator';
 end if;
 at_time:=clock_timestamp();
 receipt:=jsonb_build_object('contract_version',2,'scope','runtime_controls','request_id',p_request_id,'request_fingerprint',fingerprint,
  'family',p_family,'identity',p_identity,'previous_revision',changed_receipt->'previous_revision','revision',changed_receipt->'revision','changed',changed_receipt->'changed',
  'updated_at',collect_security.runtime_control_v2_utc((changed_receipt->>'updated_at')::timestamptz),'content_sha256',changed_receipt->'content_sha256',
  'recorded_at',collect_security.runtime_control_v2_utc(at_time),'expires_at',collect_security.runtime_control_v2_utc(p_expires_at));
 insert into collect_security.runtime_control_requests values(p_request_id,auth.uid(),sid,p_family,p_identity,p_expected_revision,p_patch_json,reason_hash,char_length(reason_text),fingerprint,p_expires_at,at_time,receipt,event_uuid);
 perform collect_security.runtime_control_actor(p_family);
 perform collect_security.runtime_control_v2_deadline(p_expires_at);
 return receipt;
end$$;

create function public.admin_get_runtime_control_request_v2(p_request_id uuid,p_family text,p_identity jsonb,p_request_fingerprint text,p_expires_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare prior collect_security.runtime_control_requests;status text;receipt jsonb;at_time timestamptz;begin
 perform collect_security.runtime_control_v2_spec(p_family);
 perform collect_security.runtime_control_check_identity(p_family,p_identity);
 if p_request_id is null or p_request_fingerprint is null or p_request_fingerprint !~ '^[a-f0-9]{64}$' or p_expires_at is null or not isfinite(p_expires_at) then
  raise exception 'runtime_control_request_invalid' using errcode='22023';end if;
 perform collect_security.runtime_control_v2_observe(p_family);
 if not pg_try_advisory_xact_lock(hashtextextended('collect-runtime-control-request:'||p_request_id::text,0)) then
  select * into prior from collect_security.runtime_control_requests where request_id=p_request_id;
  if prior.request_id is not null then
   if prior.actor_id is distinct from auth.uid() then raise exception 'runtime_control_request_owner_required' using errcode='42501';end if;
   if prior.family is distinct from p_family or prior.identity is distinct from p_identity or prior.request_fingerprint is distinct from p_request_fingerprint or prior.expires_at is distinct from p_expires_at then
    raise exception 'runtime_control_request_conflict' using errcode='22023';end if;
  elsif pg_try_advisory_xact_lock(hashtextextended('collect-runtime-control-request-actor:'||p_request_id::text||':'||auth.uid()::text,0)) then
   raise exception 'runtime_control_request_owner_required' using errcode='42501';
  end if;
  status:='in_progress';
 else
  select * into prior from collect_security.runtime_control_requests where request_id=p_request_id;
  if prior.request_id is null then status:='not_recorded';
  else
   if prior.actor_id is distinct from auth.uid() then raise exception 'runtime_control_request_owner_required' using errcode='42501';end if;
   if prior.family is distinct from p_family or prior.identity is distinct from p_identity or prior.request_fingerprint is distinct from p_request_fingerprint or prior.expires_at is distinct from p_expires_at then
    raise exception 'runtime_control_request_conflict' using errcode='22023';end if;
   status:='recorded';receipt:=prior.receipt;
  end if;
 end if;
 perform collect_security.runtime_control_v2_observe(p_family);at_time:=clock_timestamp();
 return jsonb_build_object('contract_version',2,'scope','runtime_controls','request_id',p_request_id,'request_fingerprint',p_request_fingerprint,
  'family',p_family,'identity',p_identity,'expires_at',collect_security.runtime_control_v2_utc(p_expires_at),'checked_at',collect_security.runtime_control_v2_utc(at_time),
  'sample_valid_until',collect_security.runtime_control_v2_utc(at_time+interval '60 seconds'),'status',status,'receipt',receipt);
end$$;

create function public.admin_list_runtime_control_history_v2(p_family text,p_identity jsonb,p_limit integer default 20,p_before_at timestamptz default null,p_before_event_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare event record;rows jsonb:='[]';cursor jsonb;counted integer:=0;at_time timestamptz;begin
 perform collect_security.runtime_control_v2_spec(p_family);
 perform collect_security.runtime_control_check_identity(p_family,p_identity);
 perform collect_security.runtime_control_v2_observe(p_family,true);at_time:=clock_timestamp();
 if p_limit is null or p_limit not between 1 and 25 or (p_before_at is null)<>(p_before_event_id is null)
  or p_before_at is not null and not isfinite(p_before_at) then raise exception 'runtime_control_query_invalid' using errcode='22023';end if;
 for event in select e.*,r.request_id from collect_security.runtime_control_events e left join collect_security.runtime_control_requests r on r.event_id=e.id
  where e.family=p_family and e.identity_sha256=collect_security.runtime_control_hash(p_identity) and e.recorded_at<=at_time
   and (p_before_at is null or (e.recorded_at,e.id)<(p_before_at,p_before_event_id)) order by e.recorded_at desc,e.id desc limit p_limit+1 loop
  counted:=counted+1;if counted>p_limit then exit;end if;
  rows:=rows||jsonb_build_array(jsonb_build_object('event_id',event.id,'request_id',event.request_id,'operation',event.operation,'previous_revision',event.previous_revision,
   'revision',event.revision,'recorded_at',collect_security.runtime_control_v2_utc(event.recorded_at),'actor_id',event.actor_id,'authority',event.authority,
   'changed_fields',event.changed_fields,'old_sha256',event.old_sha256,'new_sha256',event.new_sha256,'reason_sha256',event.reason_sha256,
   'reason_characters',event.reason_characters,'redacted',event.redacted));
  cursor:=jsonb_build_object('recorded_at',collect_security.runtime_control_v2_utc(event.recorded_at),'event_id',event.id);
 end loop;
 if counted<=p_limit then cursor:=null;end if;
 perform collect_security.runtime_control_v2_observe(p_family,true);
 return jsonb_build_object('contract_version',2,'scope','runtime_controls','family',p_family,'identity',p_identity,'checked_at',collect_security.runtime_control_v2_utc(at_time),
  'sample_valid_until',collect_security.runtime_control_v2_utc(at_time+interval '60 seconds'),'limit',p_limit,'history_complete',false,'changes_only',true,'rows',rows,'next_cursor',cursor);
end$$;

revoke all on function collect_security.guard_runtime_control_request_v2(),collect_security.runtime_control_v2_spec(text),
 collect_security.runtime_control_v2_utc(timestamptz),collect_security.runtime_control_v2_deadline(timestamptz,boolean),
 collect_security.runtime_control_v2_observe(text,boolean),collect_security.runtime_control_v2_fingerprint(uuid,text,jsonb,text,bigint,text,timestamptz),
 collect_security.runtime_control_v2_project(text,jsonb) from public,anon,authenticated,service_role;
revoke all on function public.admin_list_runtime_controls_v2(text,integer,jsonb),public.admin_get_runtime_control_v2(text,jsonb),
 public.admin_update_runtime_control_v2(uuid,text,jsonb,text,bigint,text,timestamptz),public.admin_get_runtime_control_request_v2(uuid,text,jsonb,text,timestamptz),
 public.admin_list_runtime_control_history_v2(text,jsonb,integer,timestamptz,uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_list_runtime_controls_v2(text,integer,jsonb),public.admin_get_runtime_control_v2(text,jsonb),
 public.admin_update_runtime_control_v2(uuid,text,jsonb,text,bigint,text,timestamptz),public.admin_get_runtime_control_request_v2(uuid,text,jsonb,text,timestamptz),
 public.admin_list_runtime_control_history_v2(text,jsonb,integer,timestamptz,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
