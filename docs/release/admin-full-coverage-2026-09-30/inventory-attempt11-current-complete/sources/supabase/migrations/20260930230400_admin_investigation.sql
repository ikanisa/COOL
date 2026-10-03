begin;

-- A redacted investigation projection. Original SMS/receipt bodies, hashes,
-- destinations, claim credentials and operator identities remain private.
create function public.admin_get_collect_investigation_v1(p_kind text,p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=''
set timezone='UTC' as $$
declare payment_access boolean; receipt_access boolean; result jsonb; checked timestamptz;
begin
 if p_kind is null or p_kind not in ('transaction','receipt') or p_id is null then
  raise exception 'investigation_target_invalid' using errcode='22023';end if;
 payment_access:=collect_security.transaction_read_authority('payments.read');
 receipt_access:=collect_security.transaction_read_authority('notifications.read');
 if (p_kind='transaction' and not payment_access) or (p_kind='receipt' and not receipt_access) then
  raise exception 'investigation_permission_required' using errcode='42501';end if;

 -- Every section shares one statement snapshot. checked_at is captured after
 -- this read; it is measurement time, never a substituted business timestamp.
 with target as (
  select sms.id sms_id,e.id event_id,p.id payment_id,
   coalesce(p.collection_id,e.collection_id,sms.collection_id) collection_id,
   p.member_record_id,o.id outbox_id,
   collect_security.rwanda_sms_scope(sms.id) supported
  from public.raw_payment_sms sms
  left join public.parsed_payment_events e on e.raw_sms_id=sms.id
  left join public.payments p on p.parsed_event_id=e.id
  left join collect_hybrid.sms_notification_outbox o on o.payment_id=p.id
   and o.template_key='buri_munsi.payment_received'
  where p_kind='transaction' and sms.id=p_id
  union all
  select sms.id,e.id,p.id,o.collection_id,o.member_record_id,o.id,
   coalesce(collect_security.rwanda_sms_scope(sms.id),false)
  from collect_hybrid.sms_notification_outbox o
  join public.payments p on p.id=o.payment_id
  left join public.parsed_payment_events e on e.id=p.parsed_event_id
  left join public.raw_payment_sms sms on sms.id=e.raw_sms_id
  where p_kind='receipt' and o.id=p_id
 ), payment_section as (
  select jsonb_build_object(
   'payment_id',t.payment_id,'raw_sms_id',t.sms_id,'event_id',t.event_id,
   'collection_id',t.collection_id,'member_record_id',t.member_record_id,
   'lifecycle',case when t.sms_id is not null then
    collect_security.transaction_lifecycle(t.sms_id,receipt_access) else null end,
   'times',jsonb_build_object('received_at_device',sms.received_at_device,
    'ingested_at',sms.ingested_at,'parsed_recorded_at',e.created_at,
    'allocation_recorded_at',a.created_at,'provider_confirmed_at',pc.confirmed_at,
    'confirmation_recorded_at',pc.created_at,'rejection_occurred_at',pr.occurred_at,
    'rejection_recorded_at',pr.recorded_at,
    'payment_posted_at',case when p.status in ('posted','reversed') then p.posted_at else null end),
   'journals',coalesce((select jsonb_agg(jsonb_build_object(
    'id',j.id,'entry_type',j.entry_type,'amount_rwf',j.amount_rwf::text,'posted_at',j.posted_at,
    'snapshot',case when s.id is null then null else jsonb_build_object(
     'id',s.id,'captured_at',s.captured_at,'delta_rwf',s.delta_rwf::text,
     'member_balance_rwf',s.member_balance_after_rwf::text,
     'group_balance_rwf',s.group_balance_after_rwf::text) end)
    order by j.posted_at,j.id) from collect_hybrid.momo_journal_entries j
    left join collect_hybrid.momo_balance_snapshots s on s.journal_entry_id=j.id
    where j.payment_id=t.payment_id),'[]'::jsonb),
   'current_balances',jsonb_build_object(
    'member_rwf',mb.confirmed_rwf::text,'member_updated_at',mb.updated_at,
    'group_rwf',gb.confirmed_rwf::text,'group_updated_at',gb.updated_at)) value
  from target t left join public.raw_payment_sms sms on sms.id=t.sms_id
  left join public.parsed_payment_events e on e.id=t.event_id
  left join public.payments p on p.id=t.payment_id
  left join public.payment_allocations a on a.payment_id=t.payment_id
   and a.parsed_event_id=t.event_id
  left join public.payment_provider_confirmations pc on pc.payment_id=t.payment_id
  left join collect_hybrid.payment_provider_rejections pr on pr.payment_id=t.payment_id
  left join collect_hybrid.member_balances mb on mb.collection_id=t.collection_id
   and mb.member_record_id=t.member_record_id
  left join collect_hybrid.collection_balances gb on gb.collection_id=t.collection_id
  where payment_access and t.supported
 ), receipt_section as (
  select jsonb_build_object('id',o.id,'payment_id',o.payment_id,'snapshot_id',o.snapshot_id,
   'collection_id',o.collection_id,'member_record_id',o.member_record_id,'state',o.state,
   'template_key',o.template_key,'template_version',o.template_version,
   'created_at',o.created_at,'updated_at',o.updated_at,'observed_sent_at',o.observed_sent_at,
   'masked_destination','+250•••'||right(o.destination_e164,3),
   'amount_rwf',o.amount_rwf::text,'member_balance_rwf',o.member_balance_rwf::text,
   'group_balance_rwf',o.group_balance_rwf::text,
   'snapshot_captured_at',s.captured_at,
   'preview_source',case when s.id is not null then 'immutable_posting_snapshot' else 'snapshot_unavailable' end,
   'masked_snapshot_preview',case when s.id is not null then
    collect_hybrid.render_buri_munsi_receipt(s.delta_rwf,s.member_balance_after_rwf,
     s.group_balance_after_rwf,'snapshot-'||right(s.id::text,8)) else null end,
   'approvals',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,
    'approved_at',c.approved_at,'expires_at',c.expires_at,'consumed_at',c.consumed_at)
    order by c.approved_at desc,c.id desc) from (select *
     from collect_hybrid.sms_notification_confirmations where outbox_id=o.id
     order by approved_at desc,id desc limit 50)c),'[]'::jsonb),
   'approval_total',(select count(*) from collect_hybrid.sms_notification_confirmations where outbox_id=o.id),
   'attempts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,
    'attempt_number',a.attempt_number,'state',a.state,'send_started_at',a.send_started_at,
    'outcome_at',a.outcome_at) order by a.attempt_number desc) from
     (select * from collect_hybrid.sms_notification_attempts where outbox_id=o.id
      order by attempt_number desc limit 50)a),'[]'::jsonb),
   'attempt_total',(select count(*) from collect_hybrid.sms_notification_attempts where outbox_id=o.id)) value
  from target t join collect_hybrid.sms_notification_outbox o on o.id=t.outbox_id
  -- Reconstruction is allowed only from the matching immutable receipt snapshot.
  left join collect_hybrid.momo_balance_snapshots s on s.id=o.snapshot_id
   and s.payment_id=o.payment_id and s.collection_id=o.collection_id
   and s.member_record_id=o.member_record_id and s.event_type='receipt'
   and s.delta_rwf=o.amount_rwf and s.member_balance_after_rwf=o.member_balance_rwf
   and s.group_balance_after_rwf=o.group_balance_rwf
   and exists(select 1 from collect_hybrid.momo_journal_entries j
    where j.id=s.journal_entry_id and j.payment_id=o.payment_id
     and j.collection_id=o.collection_id and j.member_record_id=o.member_record_id
     and j.entry_type='receipt' and j.amount_rwf=o.amount_rwf)
  where receipt_access and t.supported
 ) select jsonb_build_object(
  'contract_version',1,'scope',case when exists(select 1 from target where supported)
   then 'rwanda_momo' else 'unclassified' end,'kind',p_kind,'target_id',p_id,'history_limit',50,
  'payment_state',case when not payment_access then 'denied'
   when not exists(select 1 from target) then 'missing'
   when not exists(select 1 from target where supported) then 'unsupported' else 'available' end,
  'payment',(select value from payment_section limit 1),
  'receipt_state',case when not receipt_access then 'denied'
   when exists(select 1 from target) and not exists(select 1 from target where supported) then 'unsupported'
   when exists(select 1 from receipt_section) then 'available' else 'missing' end,
  'receipt',(select value from receipt_section limit 1)) into result;
 checked:=clock_timestamp();
 return result||jsonb_build_object('checked_at',checked,'sample_valid_until',checked+interval '60 seconds');
end $$;

revoke all on function public.admin_get_collect_investigation_v1(text,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_get_collect_investigation_v1(text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
