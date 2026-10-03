begin;

-- Preparation only: current-owner governance of future unattended preferences.
-- No executable unattended sender, schedule, approval or cap authority exists.
create schema collect_automation;
revoke all on schema collect_automation from public,anon,authenticated,service_role;
create table collect_automation.operating_policy(
 id uuid primary key default gen_random_uuid(),
 singleton boolean not null unique default true check(singleton),
 revision bigint not null default 1 check(revision between 1 and 1000000000),
 configured_mode text not null default 'Paused' check(configured_mode in('Shadow','Dry-run','Paused')),
 emergency_stop boolean not null default true,
 initialized_at timestamptz not null default clock_timestamp() check(isfinite(initialized_at)),
 updated_at timestamptz not null default clock_timestamp() check(isfinite(updated_at)),
 last_change_request_id uuid,
 check(configured_mode<>'Paused'or emergency_stop),
 check(updated_at>=initialized_at)
);
create table collect_automation.policy_requests(
 request_id uuid primary key,
 policy_id uuid not null references collect_automation.operating_policy(id)on delete restrict,
 actor_id uuid not null,
 session_id uuid not null,
 expected_revision bigint not null check(expected_revision between 1 and 1000000000),
 revision bigint not null check(revision between 1 and 1000000000),
 mode_before text not null check(mode_before in('Shadow','Dry-run','Paused')),
 mode_after text not null check(mode_after in('Shadow','Dry-run','Paused')),
 stop_before boolean not null,
 stop_after boolean not null,
 changed boolean not null,
 reason_code text not null check(reason_code in('operator_reviewed_configuration','operator_emergency_stop','operator_clear_future_stop')),
 recorded_at timestamptz not null check(isfinite(recorded_at)),
 check(changed=(mode_before<>mode_after or stop_before<>stop_after)),
 check(revision=expected_revision+case when changed then 1 else 0 end),
 check(mode_after<>'Paused'or stop_after),
 check(reason_code<>'operator_emergency_stop'or stop_after),
 check(reason_code<>'operator_clear_future_stop'or not stop_after)
);
alter table collect_automation.operating_policy add foreign key(last_change_request_id)
 references collect_automation.policy_requests(request_id)deferrable initially deferred;
alter table collect_automation.operating_policy enable row level security;
alter table collect_automation.policy_requests enable row level security;
revoke all on collect_automation.operating_policy,collect_automation.policy_requests
 from public,anon,authenticated,service_role;
-- A server default, with no fabricated owner, approval, schedule or cap.
insert into collect_automation.operating_policy(initialized_at,updated_at)
 select at,at from(select clock_timestamp()at)s;

create function collect_automation.protect_policy()returns trigger
language plpgsql set search_path=''as $$begin
 if tg_op='DELETE'or new.id is distinct from old.id or new.singleton is distinct from old.singleton
  or new.initialized_at is distinct from old.initialized_at or new.revision is distinct from old.revision+1
  or new.updated_at<old.updated_at or new.last_change_request_id is null
  or(new.configured_mode=old.configured_mode and new.emergency_stop=old.emergency_stop)then
  raise exception 'operating_policy_revision_invalid'using errcode='55000';end if;
 return new;end$$;
create trigger protect_operating_policy before update or delete on collect_automation.operating_policy
 for each row execute function collect_automation.protect_policy();
create function collect_automation.immutable_request()returns trigger
language plpgsql set search_path=''as $$begin
 raise exception 'operating_policy_evidence_retained'using errcode='55000';end$$;
create trigger immutable_operating_policy_request before update or delete on collect_automation.policy_requests
 for each row execute function collect_automation.immutable_request();

create function collect_automation.actor(p_mutation boolean)returns uuid
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;permissions text[]:=array['notifications.read','system_health.read'];begin
 if current_setting('transaction_isolation')<>'read committed'then
  raise exception 'operating_policy_snapshot_retry'using errcode='40001';end if;
 sid:=public._lock_notification_registration_session();
 perform pg_advisory_xact_lock(hashtext('collect_admin_combined_roster'));
 if p_mutation then permissions:=array_append(permissions,'notifications.manage');end if;
 perform collect_hybrid.require_roster_actor_authority(auth.uid(),sid,'platform_owner',permissions);
 if not collect_admin_access.email_identity(auth.uid())then
  raise exception 'operating_policy_current_email_owner_required'using errcode='42501';end if;
 return sid;end$$;

create function collect_automation.receipt(p collect_automation.policy_requests)returns jsonb
language sql immutable set search_path=''as $$
 select jsonb_build_object('contract_version',1,'scope','platform_global',
  'request_id',p.request_id,'policy_id',p.policy_id,'action','configure_unattended_policy',
  'expected_revision',p.expected_revision,'revision',p.revision,'changed',p.changed,
  'mode_before',p.mode_before,'mode_after',p.mode_after,'emergency_stop_before',p.stop_before,
  'emergency_stop_after',p.stop_after,'reason_code',p.reason_code,'recorded_at',collect_ops.utc(p.recorded_at),
  'unattended_dispatch_available',false,'financial_action',false,'send_action',false,
  'approval_granted',false,'schedule_changed',false,'assisted_dispatch_changed',false,
  'signed_shadow_observation_changed',false,'carrier_work_changed',false)
$$;

create function public.admin_get_unattended_operating_policy_v1()returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare p collect_automation.operating_policy;result jsonb;begin
 perform collect_automation.actor(false);
 select * into p from collect_automation.operating_policy where singleton for share;
 perform collect_automation.actor(false);
 if p.id is null then raise exception 'operating_policy_unavailable'using errcode='55000';end if;
 with sample as materialized(select clock_timestamp()at),
 assisted as materialized(select enabled from public.feature_flags where key='hybrid_sms_notifications')
 select jsonb_build_object('contract_version',1,'scope','platform_global','purpose','unattended_policy_preparation',
  'checked_at',collect_ops.utc(sample.at),'sample_valid_until',collect_ops.utc(sample.at+interval '60 seconds'),
  'policy_id',p.id,'revision',p.revision,'configured_mode',p.configured_mode,
  'effective_mode',case when p.emergency_stop then 'Paused'else p.configured_mode end,
  'emergency_stop',p.emergency_stop,'initialized_at',collect_ops.utc(p.initialized_at),
  'updated_at',collect_ops.utc(p.updated_at),'last_change_request_id',p.last_change_request_id,
  'modes',jsonb_build_array(
   jsonb_build_object('mode','Shadow','selectable',true,'unavailable_reason',null),
   jsonb_build_object('mode','Dry-run','selectable',true,'unavailable_reason',null),
   jsonb_build_object('mode','Live-limited','selectable',false,'unavailable_reason','OPERATING_POLICY_LIVE_AUTHORITY_PENDING'),
   jsonb_build_object('mode','Live','selectable',false,'unavailable_reason','OPERATING_POLICY_LIVE_AUTHORITY_PENDING'),
   jsonb_build_object('mode','Paused','selectable',true,'unavailable_reason',null)),
  'limits',jsonb_build_object('run_actions',null,'group_actions',null,'device_actions',null,'global_actions',null,
   'run_sms',null,'group_sms',null,'device_sms',null,'global_sms',null,'enforcement',false,
   'unavailable_reason','OPERATING_POLICY_LIMIT_AUTHORITY_PENDING'),
  'schedule',jsonb_build_object('owner',null,'kind',null,'cadence_seconds',null,'next_run_at',null,
   'configuration_available',false,'unavailable_reason','OPERATING_POLICY_SCHEDULE_AUTHORITY_UNAVAILABLE'),
  'approvals',jsonb_build_object('financial',null,'recipient',null,'template',null,'pilot',null),
  'execution',jsonb_build_object('unattended_dispatch_available',false,'grant_authority_pending',true,
   'unavailable_reason','OPERATING_POLICY_DISPATCH_AUTHORITY_PENDING'),
  'boundaries',jsonb_build_object('assisted_dispatch',case when not exists(select 1 from assisted)then 'unavailable'
    when(select enabled from assisted)then 'enabled'else 'paused'end,
   'policy_changes_assisted_dispatch',false,'policy_changes_signed_shadow_observation',false,
   'policy_changes_carrier_work',false))into result from sample;
 return result;
exception when lock_not_available then raise exception 'operating_policy_authority_busy'using errcode='55P03';end$$;

create function public.admin_configure_unattended_operating_policy_v1(p_request_id uuid,p_expected_revision bigint,
 p_mode text,p_emergency_stop boolean,p_reason_code text)returns jsonb
language plpgsql volatile security definer set search_path=''as $$
declare sid uuid;p collect_automation.operating_policy;prior collect_automation.policy_requests;
 changed boolean;at timestamptz;next_revision bigint;begin
 sid:=collect_automation.actor(true);
 if p_request_id is null or p_expected_revision is null or p_expected_revision not between 1 and 1000000000
  or p_mode is null or p_mode not in('Shadow','Dry-run','Live-limited','Live','Paused')
  or p_emergency_stop is null or p_reason_code is null
  or p_reason_code not in('operator_reviewed_configuration','operator_emergency_stop','operator_clear_future_stop')
  or(p_mode='Paused'and not p_emergency_stop)
  or(p_reason_code='operator_emergency_stop'and not p_emergency_stop)
  or(p_reason_code='operator_clear_future_stop'and p_emergency_stop)then
  raise exception 'operating_policy_input_invalid'using errcode='22023';end if;
 if p_mode in('Live-limited','Live')then
  raise exception 'OPERATING_POLICY_LIVE_AUTHORITY_PENDING'using errcode='55000';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-operating-policy-request:'||p_request_id::text,0));
 select * into prior from collect_automation.policy_requests where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.expected_revision<>p_expected_revision or prior.mode_after<>p_mode
   or prior.stop_after<>p_emergency_stop or prior.reason_code<>p_reason_code then
   raise exception 'operating_policy_request_conflict'using errcode='22023';end if;
  perform collect_automation.actor(true);
  return collect_automation.receipt(prior);
 end if;
 select * into p from collect_automation.operating_policy where singleton for update;
 perform collect_automation.actor(true);
 if p.id is null then raise exception 'operating_policy_unavailable'using errcode='55000';end if;
 if p.revision<>p_expected_revision then raise exception 'operating_policy_source_changed'using errcode='55000';end if;
 changed:=p.configured_mode<>p_mode or p.emergency_stop<>p_emergency_stop;
 if changed and p.revision=1000000000 then raise exception 'operating_policy_revision_exhausted'using errcode='55000';end if;
 next_revision:=p.revision+case when changed then 1 else 0 end;
 at:=greatest(p.updated_at,clock_timestamp());
 if changed then update collect_automation.operating_policy set configured_mode=p_mode,emergency_stop=p_emergency_stop,
  revision=next_revision,updated_at=at,last_change_request_id=p_request_id where id=p.id;end if;
 insert into collect_automation.policy_requests(request_id,policy_id,actor_id,session_id,expected_revision,revision,
  mode_before,mode_after,stop_before,stop_after,changed,reason_code,recorded_at)
 values(p_request_id,p.id,auth.uid(),sid,p.revision,next_revision,p.configured_mode,p_mode,p.emergency_stop,
  p_emergency_stop,changed,p_reason_code,at)returning * into prior;
 perform public.create_audit_log('automation.operating_policy.configured','unattended_operating_policy',p.id,
  jsonb_build_object('request_id',p_request_id,'expected_revision',p_expected_revision,'revision',next_revision,
   'changed',changed,'mode',p_mode,'emergency_stop',p_emergency_stop,'reason_code',p_reason_code,
   'financial_action',false,'send_action',false,'approval_granted',false,'schedule_changed',false),null);
 return collect_automation.receipt(prior);
end$$;

create function public.admin_get_unattended_policy_request_v1(p_request_id uuid)returns jsonb
language plpgsql volatile security definer set search_path=''set lock_timeout='100ms'as $$
declare acquired boolean;result jsonb;begin
 perform collect_automation.actor(false);
 if p_request_id is null then raise exception 'operating_policy_input_invalid'using errcode='22023';end if;
 acquired:=pg_try_advisory_xact_lock(hashtextextended('collect-operating-policy-request:'||p_request_id::text,0));
 with sample as materialized(select clock_timestamp()at),
 prior as materialized(select * from collect_automation.policy_requests
  where acquired and request_id=p_request_id and actor_id=auth.uid())
 select jsonb_build_object('contract_version',1,'scope','platform_global',
  'checked_at',collect_ops.utc(sample.at),'sample_valid_until',collect_ops.utc(sample.at+interval '60 seconds'),
  'request_id',p_request_id,'status',case when not acquired then 'in_progress'
   when exists(select 1 from prior)then 'recorded'else 'not_recorded'end,
  'receipt',(select collect_automation.receipt(r)from prior r))into result from sample;
 return result;
exception when lock_not_available then raise exception 'operating_policy_authority_busy'using errcode='55P03';end$$;

revoke all on all functions in schema collect_automation from public,anon,authenticated,service_role;
revoke all on function public.admin_get_unattended_operating_policy_v1(),
 public.admin_configure_unattended_operating_policy_v1(uuid,bigint,text,boolean,text),
 public.admin_get_unattended_policy_request_v1(uuid)from public,anon,authenticated,service_role;
grant execute on function public.admin_get_unattended_operating_policy_v1(),
 public.admin_configure_unattended_operating_policy_v1(uuid,bigint,text,boolean,text),
 public.admin_get_unattended_policy_request_v1(uuid)to authenticated;
commit;
