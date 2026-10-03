begin;

-- Private read authority preserves the installed approved platform-owner gate.
-- Permission/approval/Auth rows are locked by149 before aggregate data is read.
create function collect_hybrid.admin_overview_authorized(
  p_actor uuid, p_session uuid, p_permission text
) returns boolean language plpgsql security definer set search_path='' as $$
begin
  perform collect_hybrid.require_roster_actor_authority(
    p_actor,p_session,'platform_owner',array[p_permission]);
  return public.has_admin_permission(p_permission,p_actor);
exception when sqlstate '42501' then return false;
end $$;
revoke all on function collect_hybrid.admin_overview_authorized(uuid,uuid,text)
  from public,anon,authenticated,service_role;

create function public.admin_receipt_overview_v1(p_country text default 'RW')
returns jsonb language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare session_id uuid; t timestamptz; day_start timestamptz; day_end timestamptz;
  posted jsonb; receipts jsonb; receipt_access boolean;
begin
  session_id:=public._lock_notification_registration_session();
  perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
  if not collect_hybrid.admin_overview_authorized(auth.uid(),session_id,'overview.read') then
    raise exception 'overview_permission_required' using errcode='42501';
  end if;
  if coalesce(upper(btrim(p_country)),'RW')<>'RW' then
    raise exception 'overview_country_invalid' using errcode='22023';
  end if;
  receipt_access:=collect_hybrid.admin_overview_authorized(auth.uid(),session_id,'notifications.read');
  t:=clock_timestamp();
  day_start:=date_trunc('day',t at time zone 'Africa/Kigali') at time zone 'Africa/Kigali';
  day_end:=day_start+interval '24 hours';
  -- public.payments is the canonical Rwanda RWF posting source. Reversed
  -- payments are excluded; this is currently-posted value, not gross turnover,
  -- a wallet balance or bank/diaspora rail aggregation.
  -- Both subqueries use the same SQL statement snapshot. The read timestamp
  -- is captured after evaluation; crossing midnight fails closed for refresh.
  select
    (select jsonb_build_object('count',count(*),
      'value_rwf',coalesce(sum(p.amount_rwf),0)::text)
     from public.payments p where p.status='posted' and p.currency='RWF'
       and p.provider_network in ('mtn_momo','airtel_money')
       and p.posted_at>=day_start and p.posted_at<day_end and p.posted_at<=t),
    case when receipt_access then
      (select jsonb_build_object('queued',count(*) filter(where state='queued'),
        'awaiting_confirmation',count(*) filter(where state='awaiting_confirmation'),
        'oldest_pending_at',min(created_at) filter(where state in ('queued','awaiting_confirmation')),
        'failed_no_send',count(*) filter(where state='failed_no_send'),
        'uncertain',count(*) filter(where state='uncertain'),
        'send_started',count(*) filter(where state='send_started'))
       from collect_hybrid.sms_notification_outbox)
      else null end into posted,receipts;
  t:=clock_timestamp();
  if t>=day_end then
    raise exception 'overview_day_changed' using errcode='40001';
  end if;
  return jsonb_build_object('contract_version',1,'scope','rwanda_momo','country_code','RW',
    'timezone','Africa/Kigali','checked_at',t,'sample_valid_until',t+interval '60 seconds',
    'day_start',day_start,'day_end',day_end,'posted',posted,
    'receipts_state',case when receipt_access then 'available' else 'denied' end,
    'receipts',receipts);
end $$;
revoke all on function public.admin_receipt_overview_v1(text) from public,anon,service_role;
grant execute on function public.admin_receipt_overview_v1(text) to authenticated;

commit;
