set search_path=public,extensions,auth;set timezone='UTC';
begin;
-- CLI-created 20261001183721, ordered after the current 20261001230000
-- predecessor. Add adapters only: retain every effective receipt, consent,
-- finality, Android dispatch and Settings implementation from earlier migrations.
-- Deploy this database fence before the matching Edge command update. The
-- previous Edge bridge then fails closed until it uses these session-bound RPCs.
create function collect_security.require_assisted_sms_actor_v2(
 p_actor uuid,p_session uuid,p_permission text)
returns void language plpgsql volatile security definer set search_path='' as $$
begin
 -- EXECUTE is service-only; also require the actual calling role and its JWT
 -- identity. SECURITY DEFINER changes current_user, not the caller's role GUC.
 if current_setting('role',true) is distinct from 'service_role'
  or auth.jwt()->>'role' is distinct from 'service_role'
  or p_permission not in ('notifications.read','notifications.manage')
  or p_permission is null then
  raise exception 'assisted_sms_service_required' using errcode='42501';
 end if;
 -- A pre-established snapshot must never retain revoked session/role evidence.
 if current_setting('transaction_isolation')<>'read committed' then
  raise exception 'assisted_sms_snapshot_retry' using errcode='40001';
 end if;
 -- Same authority and lock order as roster/reconciliation: shared Auth gate,
 -- combined-roster gate, policy, Auth user/session, approval, role/permissions.
 -- Locks last through the legacy operation and the transaction's commit.
 perform collect_hybrid.require_roster_actor_authority(
  p_actor,p_session,'platform_owner',array[p_permission]);
end $$;
revoke all on function collect_security.require_assisted_sms_actor_v2(uuid,uuid,text)
 from public,anon,authenticated,service_role;

-- Server-owned capability provenance must survive logout/user deletion.
-- No Auth FK/cascade or caller-write grant may erase/rebind this evidence.
-- Existing unbound claims/confirmations/attempts are not attributed to a new
-- session: they fail closed without rewriting retained receipt evidence.
create table collect_security.assisted_sms_session_evidence(
 capability_kind text not null check(capability_kind in('claim_request','claim','confirmation','attempt')),
 capability_id uuid not null,
 operator_user_id uuid not null,
 originating_session_id uuid not null,
 outbox_id uuid not null,
 claim_token uuid,
 fence_version integer check(fence_version>0),
 body_sha256 text check(body_sha256~'^[0-9a-f]{64}$'),
 recorded_at timestamptz not null default clock_timestamp(),
 primary key(capability_kind,capability_id),
 check(capability_kind='claim_request'or(claim_token is not null and fence_version is not null))
);
alter table collect_security.assisted_sms_session_evidence enable row level security;
revoke all on collect_security.assisted_sms_session_evidence from public,anon,authenticated,service_role;
create function collect_security.immutable_assisted_sms_session_evidence_v2()
returns trigger language plpgsql set search_path=''as $$begin
 raise exception 'assisted_sms_session_evidence_immutable'using errcode='55000';end$$;
create trigger assisted_sms_session_evidence_immutable_row before update or delete
 on collect_security.assisted_sms_session_evidence for each row
 execute function collect_security.immutable_assisted_sms_session_evidence_v2();
create trigger assisted_sms_session_evidence_immutable_truncate before truncate
 on collect_security.assisted_sms_session_evidence for each statement
 execute function collect_security.immutable_assisted_sms_session_evidence_v2();
revoke all on function collect_security.immutable_assisted_sms_session_evidence_v2()
 from public,anon,authenticated,service_role;

create function collect_security.require_assisted_sms_capability_v2(
 p_actor uuid,p_session uuid,p_kind text,p_capability uuid,p_outbox uuid default null)
returns void language plpgsql volatile security definer set search_path=''as $$
declare evidence collect_security.assisted_sms_session_evidence;
begin
 select item.* into evidence from collect_security.assisted_sms_session_evidence item
 where item.capability_kind=p_kind and item.capability_id=p_capability;
 if evidence.capability_id is null or evidence.operator_user_id is distinct from p_actor
  or evidence.originating_session_id is distinct from p_session
  or(p_outbox is not null and evidence.outbox_id is distinct from p_outbox)then
  raise exception 'assisted_sms_originating_capability_required'using errcode='42501';
 end if;
end$$;
revoke all on function collect_security.require_assisted_sms_capability_v2(uuid,uuid,text,uuid,uuid)
 from public,anon,authenticated,service_role;

create function collect_security.record_assisted_sms_capability_v2(
 p_actor uuid,p_session uuid,p_kind text,p_capability uuid,p_outbox uuid,
 p_claim uuid,p_fence integer,p_body text default null)
returns void language plpgsql volatile security definer set search_path=''as $$
declare evidence collect_security.assisted_sms_session_evidence;
begin
 insert into collect_security.assisted_sms_session_evidence(
  capability_kind,capability_id,operator_user_id,originating_session_id,outbox_id,claim_token,fence_version,body_sha256)
 values(p_kind,p_capability,p_actor,p_session,p_outbox,p_claim,p_fence,p_body)
 on conflict(capability_kind,capability_id)do nothing;
 perform collect_security.require_assisted_sms_capability_v2(p_actor,p_session,p_kind,p_capability,p_outbox);
 select item.* into evidence from collect_security.assisted_sms_session_evidence item
 where item.capability_kind=p_kind and item.capability_id=p_capability;
 if evidence.claim_token is distinct from p_claim or evidence.fence_version is distinct from p_fence
  or evidence.body_sha256 is distinct from p_body then
  raise exception 'assisted_sms_session_evidence_conflict'using errcode='42501';
 end if;
end$$;
revoke all on function collect_security.record_assisted_sms_capability_v2(uuid,uuid,text,uuid,uuid,uuid,integer,text)
 from public,anon,authenticated,service_role;

create function public.collect_notification_health_v2(
 p_operator_user_id uuid,
 p_operator_session_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.read');
 result:=public.collect_notification_health(p_operator_user_id);
 -- The legacy operation/audit can wait on its own rows. Recheck live
 -- expiry after those waits; refusal rolls back all writes in this call.
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.read');
 return result;
end $$;
revoke all on function public.collect_notification_health_v2(uuid,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.collect_notification_health_v2(uuid,uuid) to service_role;
-- The owner keeps the legacy function callable inside the fenced adapter.
-- Revoke the old service API so no sessionless bridge can bypass this check.
revoke all on function public.collect_notification_health(uuid)
 from public,anon,authenticated,service_role;

create function public.collect_list_pending_receipts_v2(
 p_operator_user_id uuid,
 p_operator_session_id uuid,
 p_limit integer default 20,
 p_after_created_at timestamptz default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.read');
 result:=public.collect_list_pending_receipts(p_operator_user_id,p_limit,p_after_created_at);
 -- The legacy operation/audit can wait on its own rows. Recheck live
 -- expiry after those waits; refusal rolls back all writes in this call.
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.read');
 return result;
end $$;
revoke all on function public.collect_list_pending_receipts_v2(uuid,uuid,integer,timestamptz)
 from public,anon,authenticated,service_role;
grant execute on function public.collect_list_pending_receipts_v2(uuid,uuid,integer,timestamptz) to service_role;
-- The owner keeps the legacy function callable inside the fenced adapter.
-- Revoke the old service API so no sessionless bridge can bypass this check.
revoke all on function public.collect_list_pending_receipts(uuid,integer,timestamptz)
 from public,anon,authenticated,service_role;

create function public.collect_claim_receipt_v2(
 p_operator_user_id uuid,
 p_operator_session_id uuid,
 p_job_id uuid,
 p_worker_id text,
 p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 if exists(select 1 from collect_hybrid.sms_notification_claim_requests where request_id=p_request_id)then
  perform collect_security.require_assisted_sms_capability_v2(
   p_operator_user_id,p_operator_session_id,'claim_request',p_request_id);
 end if;
 result:=public.collect_claim_receipt(p_operator_user_id,p_job_id,p_worker_id,p_request_id);
 perform collect_security.record_assisted_sms_capability_v2(
  p_operator_user_id,p_operator_session_id,'claim_request',p_request_id,p_job_id,
  (result->>'claim_token')::uuid,(result->>'fence_version')::integer);
 if result->>'claim_token'is not null then
  perform collect_security.record_assisted_sms_capability_v2(
   p_operator_user_id,p_operator_session_id,'claim',(result->>'claim_token')::uuid,p_job_id,
   (result->>'claim_token')::uuid,(result->>'fence_version')::integer);
 end if;
 -- Retain originating-session provenance without SMS content or destination.
 perform public.create_audit_log(
  'notification.sms.session_fenced','sms_notification_outbox',p_job_id,
  jsonb_build_object('originating_session_id',p_operator_session_id,
   'operation','collect_claim_receipt_v2'),p_operator_user_id);
 -- The legacy operation/audit can wait on its own rows. Recheck live
 -- expiry after those waits; refusal rolls back all writes in this call.
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 return result;
end $$;
revoke all on function public.collect_claim_receipt_v2(uuid,uuid,uuid,text,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.collect_claim_receipt_v2(uuid,uuid,uuid,text,uuid) to service_role;
-- The owner keeps the legacy function callable inside the fenced adapter.
-- Revoke the old service API so no sessionless bridge can bypass this check.
revoke all on function public.collect_claim_receipt(uuid,uuid,text,uuid)
 from public,anon,authenticated,service_role;

create function public.collect_get_claimed_receipt_v2(
 p_operator_user_id uuid,
 p_operator_session_id uuid,
 p_job_id uuid,
 p_claim_token uuid,
 p_fence_version integer)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 perform collect_security.require_assisted_sms_capability_v2(
  p_operator_user_id,p_operator_session_id,'claim',p_claim_token,p_job_id);
 result:=public.collect_get_claimed_receipt(p_operator_user_id,p_job_id,p_claim_token,p_fence_version);
 -- Retain originating-session provenance without SMS content or destination.
 perform public.create_audit_log(
  'notification.sms.session_fenced','sms_notification_outbox',p_job_id,
  jsonb_build_object('originating_session_id',p_operator_session_id,
   'operation','collect_get_claimed_receipt_v2'),p_operator_user_id);
 -- The legacy operation/audit can wait on its own rows. Recheck live
 -- expiry after those waits; refusal rolls back all writes in this call.
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 return result;
end $$;
revoke all on function public.collect_get_claimed_receipt_v2(uuid,uuid,uuid,uuid,integer)
 from public,anon,authenticated,service_role;
grant execute on function public.collect_get_claimed_receipt_v2(uuid,uuid,uuid,uuid,integer) to service_role;
-- The owner keeps the legacy function callable inside the fenced adapter.
-- Revoke the old service API so no sessionless bridge can bypass this check.
revoke all on function public.collect_get_claimed_receipt(uuid,uuid,uuid,integer)
 from public,anon,authenticated,service_role;

create function public.collect_confirm_receipt_v2(
 p_operator_user_id uuid,
 p_operator_session_id uuid,
 p_job_id uuid,
 p_claim_token uuid,
 p_fence_version integer,
 p_destination_revision integer,
 p_body_sha256 text,
 p_confirmation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 perform collect_security.require_assisted_sms_capability_v2(
  p_operator_user_id,p_operator_session_id,'claim',p_claim_token,p_job_id);
 result:=public.collect_confirm_receipt(p_operator_user_id,p_job_id,p_claim_token,p_fence_version,p_destination_revision,p_body_sha256,p_confirmation_id);
 perform collect_security.record_assisted_sms_capability_v2(
  p_operator_user_id,p_operator_session_id,'confirmation',p_confirmation_id,p_job_id,
  p_claim_token,p_fence_version,lower(btrim(p_body_sha256)));
 -- Retain originating-session provenance without SMS content or destination.
 perform public.create_audit_log(
  'notification.sms.session_fenced','sms_notification_outbox',p_job_id,
  jsonb_build_object('originating_session_id',p_operator_session_id,
   'operation','collect_confirm_receipt_v2'),p_operator_user_id);
 -- The legacy operation/audit can wait on its own rows. Recheck live
 -- expiry after those waits; refusal rolls back all writes in this call.
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 return result;
end $$;
revoke all on function public.collect_confirm_receipt_v2(uuid,uuid,uuid,uuid,integer,integer,text,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.collect_confirm_receipt_v2(uuid,uuid,uuid,uuid,integer,integer,text,uuid) to service_role;
-- The owner keeps the legacy function callable inside the fenced adapter.
-- Revoke the old service API so no sessionless bridge can bypass this check.
revoke all on function public.collect_confirm_receipt(uuid,uuid,uuid,integer,integer,text,uuid)
 from public,anon,authenticated,service_role;

create function public.collect_record_send_start_v2(
 p_operator_user_id uuid,
 p_operator_session_id uuid,
 p_job_id uuid,
 p_claim_token uuid,
 p_fence_version integer,
 p_confirmation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 perform collect_security.require_assisted_sms_capability_v2(
  p_operator_user_id,p_operator_session_id,'claim',p_claim_token,p_job_id);
 perform collect_security.require_assisted_sms_capability_v2(
  p_operator_user_id,p_operator_session_id,'confirmation',p_confirmation_id,p_job_id);
 result:=public.collect_record_send_start(p_operator_user_id,p_job_id,p_claim_token,p_fence_version,p_confirmation_id);
 perform collect_security.record_assisted_sms_capability_v2(
  p_operator_user_id,p_operator_session_id,'attempt',(result->>'attempt_id')::uuid,p_job_id,
  p_claim_token,p_fence_version,(select body_sha256 from collect_hybrid.sms_notification_attempts where id=(result->>'attempt_id')::uuid));
 -- Retain originating-session provenance without SMS content or destination.
 perform public.create_audit_log(
  'notification.sms.session_fenced','sms_notification_outbox',p_job_id,
  jsonb_build_object('originating_session_id',p_operator_session_id,
   'operation','collect_record_send_start_v2'),p_operator_user_id);
 -- The legacy operation/audit can wait on its own rows. Recheck live
 -- expiry after those waits; refusal rolls back all writes in this call.
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 return result;
end $$;
revoke all on function public.collect_record_send_start_v2(uuid,uuid,uuid,uuid,integer,uuid)
 from public,anon,authenticated,service_role;
grant execute on function public.collect_record_send_start_v2(uuid,uuid,uuid,uuid,integer,uuid) to service_role;
-- The owner keeps the legacy function callable inside the fenced adapter.
-- Revoke the old service API so no sessionless bridge can bypass this check.
revoke all on function public.collect_record_send_start(uuid,uuid,uuid,integer,uuid)
 from public,anon,authenticated,service_role;

create function public.collect_record_observed_outcome_v2(
 p_operator_user_id uuid,
 p_operator_session_id uuid,
 p_attempt_id uuid,
 p_outcome text,
 p_evidence_reference text,
 p_outcome_note text default null)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 perform collect_security.require_assisted_sms_capability_v2(
  p_operator_user_id,p_operator_session_id,'attempt',p_attempt_id);
 result:=public.collect_record_observed_outcome(p_operator_user_id,p_attempt_id,p_outcome,p_evidence_reference,p_outcome_note);
 -- Retain originating-session provenance without SMS content or destination.
 perform public.create_audit_log(
  'notification.sms.session_fenced','sms_notification_attempt',p_attempt_id,
  jsonb_build_object('originating_session_id',p_operator_session_id,
   'operation','collect_record_observed_outcome_v2'),p_operator_user_id);
 -- The legacy operation/audit can wait on its own rows. Recheck live
 -- expiry after those waits; refusal rolls back all writes in this call.
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 return result;
end $$;
revoke all on function public.collect_record_observed_outcome_v2(uuid,uuid,uuid,text,text,text)
 from public,anon,authenticated,service_role;
grant execute on function public.collect_record_observed_outcome_v2(uuid,uuid,uuid,text,text,text) to service_role;
-- The owner keeps the legacy function callable inside the fenced adapter.
-- Revoke the old service API so no sessionless bridge can bypass this check.
revoke all on function public.collect_record_observed_outcome(uuid,uuid,text,text,text)
 from public,anon,authenticated,service_role;

create function public.collect_release_unsent_claim_v2(
 p_operator_user_id uuid,
 p_operator_session_id uuid,
 p_job_id uuid,
 p_claim_token uuid,
 p_fence_version integer,
 p_reason text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 perform collect_security.require_assisted_sms_capability_v2(
  p_operator_user_id,p_operator_session_id,'claim',p_claim_token,p_job_id);
 result:=public.collect_release_unsent_claim(p_operator_user_id,p_job_id,p_claim_token,p_fence_version,p_reason);
 -- Retain originating-session provenance without SMS content or destination.
 perform public.create_audit_log(
  'notification.sms.session_fenced','sms_notification_outbox',p_job_id,
  jsonb_build_object('originating_session_id',p_operator_session_id,
   'operation','collect_release_unsent_claim_v2'),p_operator_user_id);
 -- The legacy operation/audit can wait on its own rows. Recheck live
 -- expiry after those waits; refusal rolls back all writes in this call.
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.manage');
 return result;
end $$;
revoke all on function public.collect_release_unsent_claim_v2(uuid,uuid,uuid,uuid,integer,text)
 from public,anon,authenticated,service_role;
grant execute on function public.collect_release_unsent_claim_v2(uuid,uuid,uuid,uuid,integer,text) to service_role;
-- The owner keeps the legacy function callable inside the fenced adapter.
-- Revoke the old service API so no sessionless bridge can bypass this check.
revoke all on function public.collect_release_unsent_claim(uuid,uuid,uuid,integer,text)
 from public,anon,authenticated,service_role;

create function public.collect_worker_heartbeat_v2(
 p_operator_user_id uuid,
 p_operator_session_id uuid,
 p_worker_id text,
 p_run_id uuid,
 p_mode text,
 p_safe_status jsonb default '{}'::jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.read');
 result:=public.collect_worker_heartbeat(p_operator_user_id,p_worker_id,p_run_id,p_mode,p_safe_status);
 -- The legacy operation/audit can wait on its own rows. Recheck live
 -- expiry after those waits; refusal rolls back all writes in this call.
 perform collect_security.require_assisted_sms_actor_v2(
  p_operator_user_id,p_operator_session_id,'notifications.read');
 return result;
end $$;
revoke all on function public.collect_worker_heartbeat_v2(uuid,uuid,text,uuid,text,jsonb)
 from public,anon,authenticated,service_role;
grant execute on function public.collect_worker_heartbeat_v2(uuid,uuid,text,uuid,text,jsonb) to service_role;
-- The owner keeps the legacy function callable inside the fenced adapter.
-- Revoke the old service API so no sessionless bridge can bypass this check.
revoke all on function public.collect_worker_heartbeat(uuid,text,uuid,text,jsonb)
 from public,anon,authenticated,service_role;

commit;
