begin;

-- Read contracts for the supported Rwanda MoMo workflow. No financial,
-- receipt, provider or allocation state is changed by these functions.
create function collect_security.transaction_read_authority(p_permission text)
returns boolean language plpgsql volatile security definer set search_path='' as $$
declare sid uuid;
begin
 if p_permission not in ('payments.read','notifications.read') or p_permission is null then
  raise exception 'transaction_permission_invalid' using errcode='22023';end if;
 sid:=public._lock_notification_registration_session();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 -- Match installed Admin authority: approved current platform_owner only.
 -- Lock Auth, approval, grant, role and permission proof rows against revoke.
 begin
  perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,
   'platform_owner',array[p_permission]);
  return true;
 exception when sqlstate '42501' then return false;end;
end $$;

-- Raw SMS has no country field. Bind geography to the receiving route/wallet.
create function collect_security.rwanda_sms_scope(p_sms_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(
  select 1 from public.raw_payment_sms sms
  left join public.parsed_payment_events e on e.raw_sms_id=sms.id
  where sms.id=p_sms_id
   and (e.id is null or (e.is_mobile_money_payment and e.currency='RWF'
    and e.network in ('mtn_momo','airtel_money') and e.direction='incoming'
    and e.receiver_user_id=sms.receiver_user_id))
   and (exists(select 1 from public.collection_receivers r
     where r.collection_id=sms.collection_id and r.receiver_user_id=sms.receiver_user_id
      and r.momo_number_hash=sms.receiver_momo_number_hash
      and ((r.network='mtn_momo' and r.momo_number ~ '^(\+250|0)7[89][0-9]{7}$')
       or (r.network='airtel_money' and r.momo_number ~ '^(\+250|0)7[23][0-9]{7}$')))
    or exists(select 1 from public.profiles profile where profile.id=sms.receiver_user_id
     and profile.country_code='RW' and profile.currency_code='RWF'
     and profile.momo_number_verified_at is not null
     and profile.momo_number_hash=sms.receiver_momo_number_hash
     and ((profile.momo_provider='mtn_momo' and profile.momo_number ~ '^(\+250|0)7[89][0-9]{7}$')
      or (profile.momo_provider='airtel_money' and profile.momo_number ~ '^(\+250|0)7[23][0-9]{7}$'))))
 )
$$;

create function collect_security.transaction_lifecycle(p_sms_id uuid,p_notifications boolean)
returns jsonb language sql stable security definer set search_path='' as $$
 with evidence as (
  select sms.id,sms.parse_status,e.allocation_status,p.id payment_id,p.status,
   p.amount_rwf,p.collection_id,p.member_record_id,
   pc.id confirmation_id,pr.payment_id rejection_id,
   pc.amount_rwf confirmation_amount,pc.provider_network confirmation_network,
   p.provider_network,pc.transaction_id confirmation_reference,p.transaction_id,
   exists(select 1 from collect_hybrid.momo_journal_entries j
    join collect_hybrid.momo_balance_snapshots s on s.journal_entry_id=j.id
    where j.payment_id=p.id and j.entry_type='receipt' and j.amount_rwf=p.amount_rwf
     and j.collection_id=p.collection_id and j.member_record_id is not distinct from p.member_record_id
     and s.payment_id=p.id and s.collection_id=p.collection_id
     and s.member_record_id is not distinct from p.member_record_id
     and s.event_type='receipt' and s.delta_rwf=p.amount_rwf
     and (select count(*)=2 and count(*) filter(where
      (l.account_code='momo_receiving_asset:RWF' and l.direction='debit') or
      (l.account_code='member_savings_liability:RWF' and l.direction='credit'))=2
      and min(l.amount_rwf)=p.amount_rwf and max(l.amount_rwf)=p.amount_rwf
      from collect_hybrid.momo_journal_lines l where l.journal_entry_id=j.id)) receipt_posted,
   exists(select 1 from collect_hybrid.momo_journal_entries j
    join collect_hybrid.momo_balance_snapshots s on s.journal_entry_id=j.id
    where j.payment_id=p.id and j.entry_type='reversal' and j.amount_rwf=p.amount_rwf
     and j.collection_id=p.collection_id and j.member_record_id is not distinct from p.member_record_id
     and s.payment_id=p.id and s.collection_id=p.collection_id
     and s.member_record_id is not distinct from p.member_record_id
     and s.event_type='reversal' and s.delta_rwf=-p.amount_rwf
     and (select count(*)=2 and count(*) filter(where
      (l.account_code='momo_receiving_asset:RWF' and l.direction='credit') or
      (l.account_code='member_savings_liability:RWF' and l.direction='debit'))=2
      and min(l.amount_rwf)=p.amount_rwf and max(l.amount_rwf)=p.amount_rwf
      from collect_hybrid.momo_journal_lines l where l.journal_entry_id=j.id)) reversal_posted,
   case when p_notifications then (select o.state from collect_hybrid.sms_notification_outbox o
    where o.payment_id=p.id and o.template_key='buri_munsi.payment_received') else null end notification
  from public.raw_payment_sms sms
  left join public.parsed_payment_events e on e.raw_sms_id=sms.id
  left join public.payments p on p.parsed_event_id=e.id
  left join public.payment_provider_confirmations pc on pc.payment_id=p.id
  left join collect_hybrid.payment_provider_rejections pr on pr.payment_id=p.id
  where sms.id=p_sms_id
 ) select jsonb_build_object('contract_version',1,
  'verification',case
   when confirmation_id is not null and (rejection_id is not null or confirmation_amount<>amount_rwf
    or confirmation_network is distinct from provider_network
    or upper(btrim(confirmation_reference)) is distinct from upper(btrim(transaction_id))) then 'evidence_conflict'
   when rejection_id is not null then 'rejection_recorded'
   when confirmation_id is not null then 'confirmation_recorded' else 'pending' end,
  'allocation',coalesce(allocation_status::text,case parse_status
   when 'pending' then 'pending_parse' when 'failed' then 'parse_failed' else 'unavailable' end),
  'ledger',case when status='reversed' and receipt_posted and reversal_posted then 'reversed'
   when status='posted' and receipt_posted and not reversal_posted then 'posted'
   when status in ('posted','reversed') or receipt_posted or reversal_posted then 'evidence_missing'
   else 'not_posted' end,
  'notification',case when not p_notifications then 'access_required'
   else coalesce(notification,'not_created') end,
  'evidence_limit','confirmation_record_is_not_external_settlement_proof') from evidence
$$;

create or replace function public.admin_list_collect_transactions(
 p_search text default null,p_status text default null,p_limit integer default 25,
 p_offset integer default 0,p_sort text default 'created_at_desc')
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb; notification_access boolean;
begin
 if not collect_security.transaction_read_authority('payments.read') then
  raise exception 'transaction_permission_required' using errcode='42501';end if;
 if p_limit is null or p_limit not between 1 and 100 or p_offset is null or p_offset not between 0 and 100000
  or p_sort is null or p_sort not in ('created_at_desc','created_at_asc','amount_desc','amount_asc')
  or char_length(coalesce(p_search,''))>128 or char_length(coalesce(p_status,''))>64 then
  raise exception 'transaction_query_invalid' using errcode='22023';end if;
 notification_access:=collect_security.transaction_read_authority('notifications.read');
 with source as (
  select sms.id sms_id,'momo:'||sms.id::text id,
   coalesce(e.transaction_id,'Receipt '||right(sms.body_hash,8)) title,
   'Rwanda · '||case e.network when 'mtn_momo' then 'MTN MoMo' when 'airtel_money' then 'Airtel Money' else 'MoMo SMS' end
    ||' · '||coalesce(c.title,'Payee not linked') subtitle,
   coalesce(e.allocation_status::text,sms.parse_status) status,
   case when e.amount_rwf is null then '' else 'RWF '||to_char(e.amount_rwf,'FM999G999G999G999') end amount,
   coalesce(sms.received_at_device,sms.ingested_at) created_at,e.amount_rwf sort_amount,
   jsonb_build_object('rail','rw_momo','country_code','RW',
    'source_label',case e.network when 'mtn_momo' then 'MTN MoMo receipt SMS' when 'airtel_money' then 'Airtel Money receipt SMS' else 'MoMo receipt SMS' end,
    'raw_sms_id',sms.id,'event_id',e.id,'payment_id',p.id,
    'collection_id',coalesce(p.collection_id,e.collection_id,sms.collection_id),'payment_intent_id',p.payment_intent_id,
    'reference',e.transaction_id,'sender_masked',public.collect_admin_mask_sender(sms.raw_sender),
    'payer_name_masked',public.collect_admin_mask_name(e.sender_name),
    'allocated_member_id',p.member_record_id,'group_name',c.title,'payee_label',receiver.label) extra
  from public.raw_payment_sms sms left join public.parsed_payment_events e on e.raw_sms_id=sms.id
  left join public.payments p on p.parsed_event_id=e.id
  left join public.collections c on c.id=coalesce(p.collection_id,e.collection_id,sms.collection_id)
  left join lateral(select r.label from public.collection_receivers r where r.collection_id=c.id and r.is_active
   order by r.created_at desc,r.id limit 1) receiver on true
  where collect_security.rwanda_sms_scope(sms.id)
 ), filtered as (
  select * from source where (nullif(btrim(coalesce(p_status,'')),'') is null or status=btrim(p_status)
   or p_status='parse_failed' and status='failed') and
   (nullif(btrim(coalesce(p_search,'')),'') is null or title ilike '%'||btrim(p_search)||'%'
    or subtitle ilike '%'||btrim(p_search)||'%' or extra->>'reference' ilike '%'||btrim(p_search)||'%')
 ), numbered as (
  select *,row_number() over(order by
   case when p_sort='created_at_asc' then created_at end asc nulls last,
   case when p_sort='amount_asc' then sort_amount end asc nulls last,
   case when p_sort='amount_desc' then sort_amount end desc nulls last,
   created_at desc,sms_id desc) position from filtered
 ), page as (select * from numbered order by position limit p_limit offset p_offset)
 select jsonb_build_object('rows',coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,
  'subtitle',subtitle,'status',status,'amount',amount,'created_at',created_at)||extra||
  jsonb_build_object('lifecycle',collect_security.transaction_lifecycle(sms_id,notification_access))
  order by position) from page),'[]'::jsonb),'total',(select count(*) from filtered)) into result;
 return result;
end $$;

revoke all on function collect_security.transaction_read_authority(text),
 collect_security.transaction_lifecycle(uuid,boolean),collect_security.rwanda_sms_scope(uuid)
 from public,anon,authenticated,service_role;
revoke all on function public.admin_list_collect_transactions(text,text,integer,integer,text)
 from public,anon,authenticated,service_role;
grant execute on function public.admin_list_collect_transactions(text,text,integer,integer,text) to authenticated;
notify pgrst,'reload schema';
commit;
