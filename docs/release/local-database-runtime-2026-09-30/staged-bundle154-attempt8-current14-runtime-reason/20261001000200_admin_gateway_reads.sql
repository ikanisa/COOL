begin;

-- Redacted current observations and retained owner receipts only. Identity
-- activation is never dispatch authority or independent carrier attestation.
create function collect_gateway.read_actor() returns uuid
language plpgsql volatile security definer set search_path='' as $$
declare sid uuid;actor uuid;
begin
 if current_setting('transaction_isolation')<>'read committed' then
  raise exception 'gateway_read_snapshot_retry' using errcode='40001';end if;
 sid:=public._lock_notification_registration_session();actor:=auth.uid();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 perform collect_hybrid.require_roster_actor_authority(actor,sid,'platform_owner',
  array['notifications.read','system_health.read']);
 return actor;
end$$;

create function collect_gateway.read_count(p_count bigint) returns bigint
language plpgsql immutable set search_path='' as $$
begin
 if p_count is null or p_count not between 0 and 1000000000 then
  raise exception 'gateway_read_count_unavailable' using errcode='55000';end if;
 return p_count;
end$$;

create function collect_gateway.public_identity(p_device collect_gateway.devices)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('device_id',p_device.id,'installation_id',p_device.installation_id,
  'key_sha256',p_device.key_sha256,'signing_certificate_sha256',p_device.signing_certificate_sha256)
$$;

create function collect_gateway.public_owner_receipt(p_result jsonb)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('device_id',p_result->'device_id','request_id',p_result->'request_id',
  'state_at_action',p_result->'state_at_action','recorded_at',p_result->'recorded_at',
  'replay',p_result->'replay')
$$;

create index gateway_devices_read_page on collect_gateway.devices(created_at desc,id desc);
create index gateway_owner_receipts_device on collect_gateway.admin_requests
 ((result->>'device_id'),recorded_at desc,request_id desc);
create index gateway_callback_device_kind on collect_gateway.segment_callbacks(device_id,callback_kind);

create function public.admin_list_gateway_devices_v1(p_limit integer default 20,
 p_before_enrolled_at timestamptz default null,p_before_device_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_gateway.read_actor();
 if p_limit is null or p_limit not between 1 and 50
  or ((p_before_enrolled_at is null)<>(p_before_device_id is null))
  or (p_before_enrolled_at is not null and not isfinite(p_before_enrolled_at)) then
  raise exception 'gateway_read_query_invalid' using errcode='22023';end if;
 -- One Read Committed statement sees a coherent committed source snapshot.
 -- Capture its clock inside that statement, after its snapshot is acquired;
 -- a concurrently committed heartbeat/action cannot be newer than this clock
 -- yet visible in only one of the separate projections.
 with read_time as materialized(select clock_timestamp() checked_at),
 candidates as materialized(
  select d.* from collect_gateway.devices d
  where p_before_enrolled_at is null or (d.created_at,d.id)<(p_before_enrolled_at,p_before_device_id)
  order by d.created_at desc,d.id desc limit p_limit+1
 ),page as materialized(select * from candidates order by created_at desc,id desc limit p_limit),
 projected as (
  select d.created_at,d.id,
   collect_gateway.public_identity(d::collect_gateway.devices)||jsonb_build_object(
    'state',d.state,'enrolled_at',collect_gateway.utc(d.created_at),
    'activated_at',collect_gateway.utc(d.activated_at),'revoked_at',collect_gateway.utc(d.revoked_at),
    'dispatch_authority','pending','dispatch_available',false,
    'health',case when h.id is null then null else jsonb_build_object(
     'observation_id',h.id,'reported_at',collect_gateway.utc(h.reported_at),
     'ingested_at',collect_gateway.utc(h.ingested_at),
     'observation_valid_until',collect_gateway.utc(least(h.reported_at,h.ingested_at)+interval '120 seconds'),
     'freshness',case when t.checked_at<least(h.reported_at,h.ingested_at)+interval '120 seconds'
       then 'fresh' else 'stale' end,
     'sms_permission',h.sms_permission,'network',h.network,'telephony',h.telephony,
     'sim_selected',h.sim_selected,'local_pause',h.local_pause,'carrier_proof',false) end,
    'callback_observations',jsonb_build_object('total',collect_gateway.read_count(cb.total),
     'sent',collect_gateway.read_count(cb.sent),'delivery',collect_gateway.read_count(cb.delivery)),
    'last_owner_action',case when a.request_id is null then null else
     jsonb_build_object('action',a.action,'receipt',collect_gateway.public_owner_receipt(a.result)) end) value
  from page d cross join read_time t
  left join lateral(select o.* from collect_gateway.health_observations o where o.device_id=d.id
    order by o.ingested_at desc,o.id desc limit 1)h on true
  left join lateral(select r.action,r.request_id,r.result from collect_gateway.admin_requests r
    where r.result->>'device_id'=d.id::text order by r.recorded_at desc,r.request_id desc limit 1)a on true
  cross join lateral(select count(*) total,count(*) filter(where c.callback_kind='sent')sent,
    count(*) filter(where c.callback_kind='delivery')delivery
    from collect_gateway.segment_callbacks c where c.device_id=d.id)cb
 )
 select jsonb_build_object('contract_version',1,'scope','platform_global',
  'checked_at',collect_gateway.utc(t.checked_at),
  'sample_valid_until',collect_gateway.utc(t.checked_at+interval '60 seconds'),
  'limit',p_limit,'total',collect_gateway.read_count((select count(*) from collect_gateway.devices)),
  'next_cursor',case when (select count(*) from candidates)>p_limit then
   (select jsonb_build_object('enrolled_at',collect_gateway.utc(p.created_at),'device_id',p.id)
    from page p order by p.created_at,p.id limit 1) else null end,
  'rows',coalesce((select jsonb_agg(p.value order by p.created_at desc,p.id desc)from projected p),'[]'::jsonb))
 into result from read_time t;
 return result;
end$$;

create function public.admin_get_gateway_owner_request_v1(p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid;result jsonb;
begin
 actor:=collect_gateway.read_actor();
 if p_request_id is null then raise exception 'gateway_owner_request_invalid' using errcode='22023';end if;
 -- Original-actor reconciliation only. An absent or other-actor request is
 -- unknown, never an instruction to retry an uncertain mutation. Identity
 -- fields are public immutable pairing data; original key bytes stay private.
 with read_time as materialized(select clock_timestamp() checked_at),
 evidence as materialized(
  select r.action,r.result,d.* from collect_gateway.admin_requests r
  join collect_gateway.devices d on r.result->>'device_id'=d.id::text
  where r.request_id=p_request_id and r.actor_id=actor
 )
 select jsonb_build_object('contract_version',1,'scope','platform_global',
  'checked_at',collect_gateway.utc(t.checked_at),
  'sample_valid_until',collect_gateway.utc(t.checked_at+interval '60 seconds'),
  'request_id',p_request_id,'outcome',case when e.id is null then 'unknown' else 'recorded' end,
  'action',e.action,'receipt',case when e.id is null then null else collect_gateway.public_owner_receipt(e.result) end,
  'identity',case when e.id is null then null else
   jsonb_build_object('device_id',e.id,'installation_id',e.installation_id,
    'key_sha256',e.key_sha256,'signing_certificate_sha256',e.signing_certificate_sha256) end)
 into result from read_time t left join evidence e on true;
 return result;
end$$;

revoke all on function collect_gateway.read_actor(),collect_gateway.read_count(bigint),
 collect_gateway.public_identity(collect_gateway.devices),collect_gateway.public_owner_receipt(jsonb)
 from public,anon,authenticated,service_role;
revoke all on function public.admin_list_gateway_devices_v1(integer,timestamptz,uuid),
 public.admin_get_gateway_owner_request_v1(uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_list_gateway_devices_v1(integer,timestamptz,uuid),
 public.admin_get_gateway_owner_request_v1(uuid) to authenticated;

-- Provision via the database owner and preserve customized or disabled rows.
-- Serialize the absence check to avoid firing audit guards for skipped rows.
lock table public.admin_navigation_items in share row exclusive mode;
insert into public.admin_navigation_items(key,label,icon_key,route_path,required_permission,
 display_order,enabled,metadata,updated_reason)
select 'sms_gateway','SMS Gateway','router','/admin/sms-gateway','notifications.read',146,true,
 '{}'::jsonb,'Redacted device observations and owner action evidence; dispatch authority pending'
where not exists(select 1 from public.admin_navigation_items
 where key='sms_gateway' or route_path='/admin/sms-gateway')
on conflict do nothing;

notify pgrst,'reload schema';
commit;
