begin;
-- Point-in-time archive authority for complete signed framework observations.
-- Never a delivery conclusion, send permit, retention horizon or retry policy.
create schema collect_gateway_archive;
revoke all on schema collect_gateway_archive from public,anon,authenticated,service_role;
create table collect_gateway_archive.requests(
 request_id uuid primary key,device_id uuid not null references collect_gateway.devices(id)on delete restrict,
 request_sha256 text not null check(request_sha256~'^[0-9a-f]{64}$'),payload jsonb not null,
 result jsonb not null,recorded_at timestamptz not null);
create table collect_gateway_archive.acknowledgements(
 id uuid primary key default gen_random_uuid(),attempt_id uuid not null unique references collect_gateway_dispatch.arms(attempt_id)on delete restrict,
 request_id uuid not null unique references collect_gateway_archive.requests(request_id)on delete restrict deferrable initially deferred,
 device_id uuid not null references collect_gateway.devices(id)on delete restrict,
 callback_requests jsonb not null check(jsonb_typeof(callback_requests)='array'),recorded_at timestamptz not null);
do $$declare t text;begin foreach t in array array['requests','acknowledgements']loop
 execute format('alter table collect_gateway_archive.%I enable row level security',t);
 execute format('revoke all on collect_gateway_archive.%I from public,anon,authenticated,service_role',t);
 execute format('create trigger immutable_archive_evidence before update or delete on collect_gateway_archive.%I for each row execute function collect_gateway_dispatch.immutable()',t);
end loop;end$$;
create function collect_gateway_archive.cross_request()returns trigger language plpgsql set search_path=''as $$begin
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'gateway_archive_snapshot_retry'using errcode='40001';end if;
 if not pg_try_advisory_xact_lock(hashtextextended('gateway-dispatch-request:'||new.request_id::text,0))then raise exception 'gateway_archive_request_busy'using errcode='55000';end if;
 if tg_table_schema='collect_gateway_archive'then
  if exists(select 1 from collect_gateway.requests where request_id=new.request_id)or exists(select 1 from collect_gateway_dispatch.requests where request_id=new.request_id)then raise exception 'gateway_archive_request_conflict'using errcode='22023';end if;
 elsif exists(select 1 from collect_gateway_archive.requests where request_id=new.request_id)then raise exception 'gateway_archive_request_conflict'using errcode='22023';end if;
 return new;end$$;
create trigger archive_uuid_namespace before insert on collect_gateway.requests for each row execute function collect_gateway_archive.cross_request();
create trigger archive_uuid_namespace before insert on collect_gateway_dispatch.requests for each row execute function collect_gateway_archive.cross_request();
create trigger archive_uuid_namespace before insert on collect_gateway_archive.requests for each row execute function collect_gateway_archive.cross_request();
create function collect_gateway_archive.require_request(p_device uuid,p_request uuid,p_hash text)returns void language plpgsql set search_path=''as $$begin
 perform collect_gateway.require_service(p_device,p_request,p_hash);
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'gateway_archive_snapshot_retry'using errcode='40001';end if;
 if not exists(select 1 from collect_gateway.devices where id=p_device)then raise exception 'gateway_device_not_found'using errcode='42501';end if;
end$$;
create function public.gateway_archive_attempt_v3(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path=''as $$
declare a collect_gateway_dispatch.attempts;arm collect_gateway_dispatch.arms;prior collect_gateway_archive.requests;
 refs jsonb;x jsonb;cb collect_gateway_dispatch.callbacks;r collect_gateway_dispatch.requests;
 t timestamptz;idx integer:=0;n integer;reason text;ack uuid;result jsonb;ref_callback uuid;ref_request uuid;digest text;begin
 perform collect_gateway_archive.require_request(p_device_id,p_request_id,p_request_sha256);
 perform collect_gateway.payload_keys(p_payload,array['attempt_id','fence_version','body_sha256','destination_sha256','callback_requests']);
 if not pg_try_advisory_xact_lock(hashtextextended('gateway-dispatch-request:'||p_request_id::text,0))then raise exception 'gateway_archive_request_busy'using errcode='55000';end if;
 if exists(select 1 from collect_gateway.requests where request_id=p_request_id)or exists(select 1 from collect_gateway_dispatch.requests where request_id=p_request_id)then raise exception 'gateway_archive_request_conflict'using errcode='22023';end if;
 refs:=p_payload->'callback_requests';
 if jsonb_typeof(refs)is distinct from 'array'or jsonb_array_length(refs)not between 2 and 20
  or jsonb_typeof(p_payload->'body_sha256')is distinct from 'string'or(p_payload->>'body_sha256')!~'^[0-9a-f]{64}$'
  or jsonb_typeof(p_payload->'destination_sha256')is distinct from 'string'or(p_payload->>'destination_sha256')!~'^[0-9a-f]{64}$'then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
 select * into a from collect_gateway_dispatch.attempts where id=collect_gateway.payload_uuid(p_payload,'attempt_id')and device_id=p_device_id;
 if a.id is null or a.fence_version<>collect_gateway.payload_int(p_payload,'fence_version',1,1000000000)then raise exception 'gateway_dispatch_attempt_unavailable'using errcode='42501';end if;
 -- Callback folds use this receipt -> attempt order. Pause/revocation never
 -- reopens dispatch, but must not discard already signed prior-arm evidence.
 perform 1 from collect_hybrid.sms_notification_outbox where id=a.outbox_id for update;
 select * into a from collect_gateway_dispatch.attempts where id=a.id for update;
 perform 1 from collect_gateway.devices where id=p_device_id for share;
 select * into prior from collect_gateway_archive.requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.device_id<>p_device_id or prior.request_sha256<>p_request_sha256 or prior.payload is distinct from p_payload then raise exception 'gateway_archive_request_conflict'using errcode='22023';end if;
  return prior.result||jsonb_build_object('replay',true);
 end if;
 select * into arm from collect_gateway_dispatch.arms where attempt_id=a.id;
 if arm.attempt_id is null or a.body_sha256 is distinct from(p_payload->>'body_sha256')or a.destination_sha256 is distinct from(p_payload->>'destination_sha256')
  or jsonb_array_length(refs)<>a.segment_count*2 then raise exception 'gateway_archive_binding_invalid'using errcode='22023';end if;
 for x in select value from jsonb_array_elements(refs)loop
  perform collect_gateway.payload_keys(x,array['callback_id','request_id','request_sha256']);
  ref_callback:=collect_gateway.payload_uuid(x,'callback_id');ref_request:=collect_gateway.payload_uuid(x,'request_id');digest:=x->>'request_sha256';
  if jsonb_typeof(x->'request_sha256')is distinct from 'string'or digest!~'^[0-9a-f]{64}$'or ref_request=p_request_id
   or ref_callback is distinct from((arm.callback_plan->(idx/2))->>case when idx%2=0 then 'sent_callback_id'else 'delivery_callback_id'end)::uuid then raise exception 'gateway_archive_binding_invalid'using errcode='22023';end if;
  select * into r from collect_gateway_dispatch.requests where request_id=ref_request and device_id=p_device_id and action='callback';
  select * into cb from collect_gateway_dispatch.callbacks where request_id=ref_request and attempt_id=a.id and callback_id=ref_callback;
  if r.request_id is null or cb.request_id is null then reason:=coalesce(reason,'CALLBACK_EVIDENCE_INCOMPLETE');
  elsif r.request_sha256<>digest or cb.segment_index<>idx/2 or cb.callback_kind<>(case when idx%2=0 then 'sent'else 'delivery'end) then raise exception 'gateway_archive_binding_invalid'using errcode='22023';
  end if;idx:=idx+1;
 end loop;
 if(select count(distinct value->>'request_id')from jsonb_array_elements(refs))<>jsonb_array_length(refs)then raise exception 'gateway_archive_binding_invalid'using errcode='22023';end if;
 select count(*)into n from collect_gateway_dispatch.callback_bindings b where b.attempt_id=a.id;
 if n<>a.segment_count*2 then reason:='CALLBACK_EVIDENCE_INCOMPLETE';end if;
 if a.state='uncertain'or exists(select 1 from collect_gateway_dispatch.callbacks where attempt_id=a.id and result_code<>-1)
  or exists(select 1 from collect_gateway_dispatch.callbacks where attempt_id=a.id group by callback_id having count(distinct jsonb_build_array(result_code,tp_status))>1)then reason:='CALLBACK_EVIDENCE_UNCERTAIN';
 elsif a.state<>'observed_sent'or(select count(distinct callback_id)from collect_gateway_dispatch.callbacks where attempt_id=a.id)<>a.segment_count*2 then reason:=coalesce(reason,'CALLBACK_EVIDENCE_INCOMPLETE');end if;
 if exists(select 1 from collect_gateway_archive.acknowledgements where attempt_id=a.id)then reason:='ATTEMPT_ALREADY_ACKNOWLEDGED';end if;
 t:=clock_timestamp();
 if reason is null then
  ack:=gen_random_uuid();insert into collect_gateway_archive.acknowledgements values(ack,a.id,p_request_id,p_device_id,refs,t);
 end if;
 result:=jsonb_build_object('request_id',p_request_id,'device_id',p_device_id,'attempt_id',a.id,'fence_version',a.fence_version,
  'ok',reason is null,'code',reason,'archive_ack_id',ack,'receipt_id',case when reason is null then a.outbox_id end,
  'body_sha256',a.body_sha256,'destination_sha256',a.destination_sha256,'segment_count',a.segment_count,
  'callback_requests',case when reason is null then refs end,'recorded_at',collect_gateway.utc(t),'replay',false,
  'evidence_kind',case when reason is null then 'complete_framework_callback_observations'end,
  'carrier_proof',false,'delivery_proven',false,'send_authority',false);
 insert into collect_gateway_archive.requests values(p_request_id,p_device_id,p_request_sha256,p_payload,result,t);return result;
end$$;
create function public.gateway_archive_lookup_v3(p_device_id uuid,p_request_id uuid,p_request_sha256 text,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path=''as $$declare target uuid;r collect_gateway_archive.requests;begin
 perform collect_gateway_archive.require_request(p_device_id,p_request_id,p_request_sha256);
 perform collect_gateway.payload_keys(p_payload,array['target_request_id']);target:=collect_gateway.payload_uuid(p_payload,'target_request_id');
 if target=p_request_id then raise exception 'gateway_payload_invalid'using errcode='22023';end if;
 select * into r from collect_gateway_archive.requests where request_id=target and device_id=p_device_id;
 return jsonb_build_object('target_request_id',target,'outcome',case when r.request_id is null then 'unknown'else 'recorded'end,'recorded_result',r.result);
end$$;
revoke all on all functions in schema collect_gateway_archive from public,anon,authenticated,service_role;
revoke all on function public.gateway_archive_attempt_v3(uuid,uuid,text,jsonb),public.gateway_archive_lookup_v3(uuid,uuid,text,jsonb)from public,anon,authenticated;
grant execute on function public.gateway_archive_attempt_v3(uuid,uuid,text,jsonb),public.gateway_archive_lookup_v3(uuid,uuid,text,jsonb)to service_role;
commit;
