begin;
select pg_advisory_xact_lock(193517, 230);

-- These indexes bound the Admin reader independently of lifetime duplicate
-- callback observations. Existing device protocols and grants are preserved.
create index automatic_callback_admin_history
 on collect_gateway_dispatch.callbacks(attempt_id,recorded_at desc,request_id desc);
create index automatic_callback_admin_variants
 on collect_gateway_dispatch.callbacks(attempt_id,callback_id,result_code,(coalesce(tp_status,-1)));
create index automatic_archive_admin_history
 on collect_gateway_archive.requests((payload->>'attempt_id'),recorded_at desc,request_id desc);
create index automatic_device_admin_history
 on collect_gateway_dispatch.attempts(device_id,issued_at desc,id desc);

create function collect_gateway_dispatch.admin_attempt_projection(p collect_gateway_dispatch.attempts)
returns jsonb language sql immutable security definer set search_path='' as $$
 select jsonb_build_object('attempt_id',p.id,'receipt_id',p.outbox_id,
  'device_id',p.device_id,'run_id',p.run_id,'principal_id',p.principal_id,
  'fence_version',p.fence_version,'policy_revision',p.policy_revision,
  'segment_count',p.segment_count,'grant_request_id',p.grant_request_id,
  'health_observation_id',p.health_observation_id,'state',p.state,
  'issued_at',collect_gateway.utc(p.issued_at),'expires_at',collect_gateway.utc(p.expires_at),
  'updated_at',collect_gateway.utc(p.updated_at))
$$;
revoke all on function collect_gateway_dispatch.admin_attempt_projection(collect_gateway_dispatch.attempts)
 from public,anon,authenticated,service_role;

create function public.admin_get_gateway_receipt_investigation_v3(
 p_receipt_id uuid,p_limit integer default 20,
 p_before_at timestamptz default null,p_before_request_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare t timestamptz;answer jsonb;
begin
 perform collect_gateway.read_actor();
 t:=clock_timestamp();
 if p_receipt_id is null or p_limit is null or p_limit not between 1 and 25
  or (p_before_at is null)<>(p_before_request_id is null)
  or p_before_at is not null and not isfinite(p_before_at) then
  raise exception 'gateway_investigation_input_invalid' using errcode='22023';end if;
 -- All evidence below is read in one statement snapshot. Framework callbacks
 -- and archival recording never establish carrier delivery or send authority.
 with source as materialized (
  select o.* from collect_hybrid.sms_notification_outbox o
  where o.id=p_receipt_id and collect_receipt_actions.rwanda_source(o)
 ), attempt as materialized (
  select a.* from collect_gateway_dispatch.attempts a join source o on o.id=a.outbox_id
 ), arm as materialized (
  select r.* from collect_gateway_dispatch.arms r join attempt a on a.id=r.attempt_id
 ), bindings as materialized (
  select b.callback_id,b.segment_index,b.callback_kind,
   first_value.request_id is not null as has_observation,
   first_value.request_id is not null and
    (first_value.result_code,coalesce(first_value.tp_status,-1))=
    (last_value.result_code,coalesce(last_value.tp_status,-1)) as consistent,
   first_value.result_code,first_value.tp_status
  from collect_gateway_dispatch.callback_bindings b join attempt a on a.id=b.attempt_id
  left join lateral (
   select c.request_id,c.result_code,c.tp_status from collect_gateway_dispatch.callbacks c
   where c.attempt_id=b.attempt_id and c.callback_id=b.callback_id
   order by c.result_code,coalesce(c.tp_status,-1) limit 1
  ) first_value on true
  left join lateral (
   select c.result_code,c.tp_status from collect_gateway_dispatch.callbacks c
   where c.attempt_id=b.attempt_id and c.callback_id=b.callback_id
   order by c.result_code desc,coalesce(c.tp_status,-1) desc limit 1
  ) last_value on true
 ), ack as materialized (
  select k.* from collect_gateway_archive.acknowledgements k join attempt a on a.id=k.attempt_id
 ), dispatch_history as materialized (
  select r.request_id,r.recorded_at,r.action,
   case when r.action='dispatch_grant' then 'grant' else 'arm' end as source,
   r.result->>'code' as code,null::uuid as callback_id,null::integer as segment_index,
   null::text as callback_kind,null::integer as result_code,null::integer as tp_status,
   null::timestamptz as occurred_at
  from collect_gateway_dispatch.requests r join attempt a on
   r.request_id=a.grant_request_id or r.request_id=(select request_id from arm)
  where p_before_at is null or (r.recorded_at,r.request_id)<(p_before_at,p_before_request_id)
  order by r.recorded_at desc,r.request_id desc limit p_limit+1
 ), callback_history as materialized (
  select c.request_id,c.recorded_at,'callback'::text as action,'callback'::text as source,
   null::text as code,c.callback_id,c.segment_index,c.callback_kind,c.result_code,c.tp_status,c.occurred_at
  from attempt a cross join lateral (
   select c.* from collect_gateway_dispatch.callbacks c where c.attempt_id=a.id
    and (p_before_at is null or (c.recorded_at,c.request_id)<(p_before_at,p_before_request_id))
   order by c.recorded_at desc,c.request_id desc limit p_limit+1
  ) c
 ), archive_history as materialized (
  select r.request_id,r.recorded_at,'archive_attempt'::text as action,'archive'::text as source,
   r.result->>'code' as code,null::uuid as callback_id,null::integer as segment_index,
   null::text as callback_kind,null::integer as result_code,null::integer as tp_status,
   null::timestamptz as occurred_at
  from attempt a cross join lateral (
   select r.* from collect_gateway_archive.requests r where r.payload->>'attempt_id'=a.id::text
    and (p_before_at is null or (r.recorded_at,r.request_id)<(p_before_at,p_before_request_id))
   order by r.recorded_at desc,r.request_id desc limit p_limit+1
  ) r
 ), bounded_history as materialized (
  select * from (
   select * from dispatch_history union all select * from callback_history union all select * from archive_history
  ) h order by recorded_at desc,request_id desc limit p_limit+1
 ), page as materialized (
  select * from bounded_history order by recorded_at desc,request_id desc limit p_limit
 )
 select jsonb_build_object('contract_version',3,'scope','rw_automatic_gateway_evidence',
  'receipt_id',p_receipt_id,
  'status',case when not exists(select 1 from source) then 'unavailable'
   when not exists(select 1 from attempt) then 'no_automatic_attempt' else 'available' end,
  'checked_at',collect_gateway.utc(t),'sample_valid_until',collect_gateway.utc(t+interval '60 seconds'),
  'limit',p_limit,'attempt',(select collect_gateway_dispatch.admin_attempt_projection(a) from attempt a),
  'arm',(select jsonb_build_object('request_id',r.request_id,'health_observation_id',r.health_observation_id,
   'armed_at',collect_gateway.utc(r.armed_at),'expires_at',collect_gateway.utc(r.expires_at)) from arm r),
  'expected_callbacks',coalesce((select jsonb_agg(jsonb_build_object('callback_id',b.callback_id,
   'segment_index',b.segment_index,'callback_kind',b.callback_kind,'has_observation',b.has_observation,
   'consistent',b.consistent,'result_code',b.result_code,'tp_status',b.tp_status)
   order by b.segment_index,b.callback_kind) from bindings b),'[]'::jsonb),
  'archive_ack',(select jsonb_build_object('acknowledgement_id',k.id,'request_id',k.request_id,
   'recorded_at',collect_gateway.utc(k.recorded_at),'evidence_kind','complete_framework_callback_observations') from ack k),
  'history_complete',false,
  'rows',coalesce((select jsonb_agg(jsonb_build_object('request_id',h.request_id,'source',h.source,
   'action',h.action,'recorded_at',collect_gateway.utc(h.recorded_at),'code',h.code,
   'callback_id',h.callback_id,'segment_index',h.segment_index,'callback_kind',h.callback_kind,
   'result_code',h.result_code,'tp_status',h.tp_status,
   'occurred_at',case when h.occurred_at is not null then collect_gateway.utc(h.occurred_at) end)
   order by h.recorded_at desc,h.request_id desc) from page h),'[]'::jsonb),
  'next_cursor',case when (select count(*) from bounded_history)>p_limit then
   (select jsonb_build_object('recorded_at',collect_gateway.utc(h.recorded_at),'request_id',h.request_id)
    from page h order by h.recorded_at,h.request_id limit 1) else null end,
  'carrier_proof',false,'delivery_proven',false,'send_authority',false) into answer;
 perform collect_gateway.read_actor();
 if clock_timestamp()>=t+interval '60 seconds' then
  raise exception 'gateway_investigation_sample_expired' using errcode='55000';end if;
 return answer;
end$$;

create function public.admin_list_gateway_device_attempts_v3(
 p_device_id uuid,p_limit integer default 20,
 p_before_at timestamptz default null,p_before_attempt_id uuid default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare t timestamptz;answer jsonb;
begin
 perform collect_gateway.read_actor();t:=clock_timestamp();
 if p_device_id is null or p_limit is null or p_limit not between 1 and 25
  or (p_before_at is null)<>(p_before_attempt_id is null)
  or p_before_at is not null and not isfinite(p_before_at) then
  raise exception 'gateway_investigation_input_invalid' using errcode='22023';end if;
 with device as materialized (
  select d.id from collect_gateway.devices d where d.id=p_device_id
 ), candidates as materialized (
  select a.* from device d cross join lateral (
   select a.* from collect_gateway_dispatch.attempts a where a.device_id=d.id
    and (p_before_at is null or (a.issued_at,a.id)<(p_before_at,p_before_attempt_id))
   order by a.issued_at desc,a.id desc limit p_limit+1
  ) a
 ), scanned_page as materialized (
  select * from candidates order by issued_at desc,id desc limit p_limit
 ), page as materialized (
  select a.* from scanned_page a join collect_hybrid.sms_notification_outbox o on o.id=a.outbox_id
  where collect_receipt_actions.rwanda_source(o)
 ) select jsonb_build_object('contract_version',3,'scope','rw_automatic_gateway_evidence',
  'device_id',p_device_id,'status',case when exists(select 1 from device) then 'available' else 'unavailable' end,
  'checked_at',collect_gateway.utc(t),'sample_valid_until',collect_gateway.utc(t+interval '60 seconds'),
  'limit',p_limit,'scanned_count',(select count(*) from scanned_page),
  'rows',coalesce((select jsonb_agg(collect_gateway_dispatch.admin_attempt_projection(a)
   order by a.issued_at desc,a.id desc) from page a),'[]'::jsonb),
  'next_cursor',case when (select count(*) from candidates)>p_limit then
   (select jsonb_build_object('issued_at',collect_gateway.utc(a.issued_at),'attempt_id',a.id)
    from scanned_page a order by a.issued_at,a.id limit 1) else null end,
  'carrier_proof',false,'delivery_proven',false,'send_authority',false) into answer;
 perform collect_gateway.read_actor();
 if clock_timestamp()>=t+interval '60 seconds' then
  raise exception 'gateway_investigation_sample_expired' using errcode='55000';end if;
 return answer;
end$$;
revoke all on function public.admin_get_gateway_receipt_investigation_v3(uuid,integer,timestamptz,uuid),
 public.admin_list_gateway_device_attempts_v3(uuid,integer,timestamptz,uuid)
 from public,anon,service_role;
grant execute on function public.admin_get_gateway_receipt_investigation_v3(uuid,integer,timestamptz,uuid),
 public.admin_list_gateway_device_attempts_v3(uuid,integer,timestamptz,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
