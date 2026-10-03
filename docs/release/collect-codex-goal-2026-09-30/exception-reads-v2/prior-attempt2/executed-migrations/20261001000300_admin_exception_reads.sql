begin;

-- Additive redacted reads. Captured v1 mutations and receipts remain unchanged.
create function collect_ops.transaction_sms_id(p_kind text,p_source uuid)
returns uuid language sql stable security definer set search_path='' as $$
 select case p_kind
  when 'raw_sms' then(select sms.id from public.raw_payment_sms sms
   where sms.id=p_source and collect_security.rwanda_sms_scope(sms.id))
  when 'allocation' then(select sms.id from public.parsed_payment_events e
   join public.raw_payment_sms sms on sms.id=e.raw_sms_id
   where e.id=p_source and collect_security.rwanda_sms_scope(sms.id))
  when 'payment' then(select sms.id from public.payments p
   join public.parsed_payment_events e on e.id=p.parsed_event_id
   join public.raw_payment_sms sms on sms.id=e.raw_sms_id
   where p.id=p_source and p.currency='RWF'
    and e.receiver_user_id=p.receiver_user_id and e.network=p.provider_network
    and sms.receiver_momo_number_hash=p.receiver_momo_number_hash
    and collect_security.rwanda_sms_scope(sms.id))
  else null::uuid end
$$;

create function collect_ops.public_action_receipt(p_action collect_ops.exception_actions)
returns jsonb language sql immutable set search_path='' as $$
 select jsonb_build_object('contract_version',1,'request_id',p_action.request_id,
  'exception_id',p_action.exception_id,'revision',p_action.expected_revision,
  'action',p_action.action,'recorded_at',collect_ops.utc(p_action.recorded_at),
  'source_resolved',false,'financial_action',false,'send_action',false,
  'escalation_delivery_verified',false)
$$;

create function public.admin_list_operational_exceptions_v2(p_active boolean default true,
 p_limit integer default 20,p_before_changed_at timestamptz default null,
 p_before_id uuid default null,p_source_kind text default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_ops.actor(false);
 if p_active is null or p_limit is null or p_limit not between 1 and 50
  or((p_before_changed_at is null)<>(p_before_id is null))
  or(p_before_changed_at is not null and not isfinite(p_before_changed_at))
  or(p_source_kind is not null and p_source_kind not in('raw_sms','allocation','payment','receipt','gateway')) then
  raise exception 'operational_exception_query_invalid' using errcode='22023';end if;
 -- One committed statement supplies time, category, page and review flags.
 -- Read freshness is independent of the retained source observation's age.
 with sample as materialized(select clock_timestamp() at),
 candidates as materialized(select e.* from collect_ops.exceptions e
  where e.active=p_active and(p_source_kind is null or e.source_kind=p_source_kind)
   and(p_before_changed_at is null or(e.last_changed_at,e.id)<(p_before_changed_at,p_before_id))
  order by e.last_changed_at desc,e.id desc limit p_limit+1),
 page as materialized(select * from candidates order by last_changed_at desc,id desc limit p_limit),
 projected as(select e.last_changed_at,e.id,jsonb_build_object('id',e.id,
  'source_kind',e.source_kind,'source_id',e.source_id,'reason_code',e.reason_code,
  'active',e.active,'revision',e.revision,'source_sha256',e.source_sha256,
  'first_observed_at',collect_ops.utc(e.first_observed_at),
  'last_changed_at',collect_ops.utc(e.last_changed_at),
  'transaction_sms_id',collect_ops.transaction_sms_id(e.source_kind,e.source_id),
  'acknowledged',exists(select 1 from collect_ops.exception_actions a
   where a.exception_id=e.id and a.expected_revision=e.revision and a.action='acknowledge'),
  'escalation_requested',exists(select 1 from collect_ops.exception_actions a
   where a.exception_id=e.id and a.expected_revision=e.revision and a.action='escalate'))value from page e)
 select jsonb_build_object('contract_version',2,'scope','platform_global',
  'checked_at',collect_ops.utc(sample.at),'sample_valid_until',collect_ops.utc(sample.at+interval '60 seconds'),
  'active',p_active,'source_kind',p_source_kind,'limit',p_limit,
  'rows',coalesce((select jsonb_agg(value order by last_changed_at desc,id desc)from projected),'[]'::jsonb),
  'next_cursor',case when(select count(*)from candidates)>p_limit then
   (select jsonb_build_object('changed_at',collect_ops.utc(last_changed_at),'id',id)
    from page order by last_changed_at,id limit 1)else null end,
  'escalation_delivery_verified',false,'source_scan_complete',false)
 into result from sample;
 return result;
end$$;

create function public.admin_get_operational_exception_action_v2(p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' set lock_timeout='100ms' as $$
declare result jsonb;acquired boolean;
begin
 -- The original action holds the roster authority lock until commit. Timeout
 -- means current authority could not be established, without outcome leakage.
 begin perform collect_ops.actor(false);
 exception when lock_not_available then
  raise exception 'operational_exception_authority_busy' using errcode='55P03';end;
 if p_request_id is null then raise exception 'operational_exception_action_invalid' using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-ops-action:'||p_request_id::text,0));
 with sample as materialized(select clock_timestamp() at),
 prior as materialized(select a.* from collect_ops.exception_actions a
  where acquired and a.request_id=p_request_id and a.actor_id=auth.uid())
 select jsonb_build_object('contract_version',2,'scope','platform_global',
  'checked_at',collect_ops.utc(sample.at),'sample_valid_until',collect_ops.utc(sample.at+interval '60 seconds'),
  'request_id',p_request_id,'status',case when not acquired then 'in_progress'
   when exists(select 1 from prior)then 'recorded'else 'not_recorded'end,
  'receipt',(select collect_ops.public_action_receipt(p)from prior p))
 into result from sample;
 return result;
end$$;

revoke all on function collect_ops.transaction_sms_id(text,uuid),
 collect_ops.public_action_receipt(collect_ops.exception_actions) from public,anon,authenticated,service_role;
revoke all on function public.admin_list_operational_exceptions_v2(boolean,integer,timestamptz,uuid,text),
 public.admin_get_operational_exception_action_v2(uuid) from public,anon,authenticated,service_role;
grant execute on function public.admin_list_operational_exceptions_v2(boolean,integer,timestamptz,uuid,text),
 public.admin_get_operational_exception_action_v2(uuid) to authenticated;

-- Preserve custom/disabled entries, including another key using this route.
lock table public.admin_navigation_items in share row exclusive mode;
insert into public.admin_navigation_items(key,label,icon_key,route_path,required_permission,
 display_order,enabled,metadata,updated_reason)
select 'exceptions','Exceptions','warning_amber','/admin/exceptions','payments.read',147,true,
 '{}'::jsonb,'Derived operational source conditions and human review evidence'
where not exists(select 1 from public.admin_navigation_items
 where key='exceptions' or route_path='/admin/exceptions')
on conflict do nothing;
notify pgrst,'reload schema';
commit;
