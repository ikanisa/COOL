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
 result:=public.collect_claim_receipt(p_operator_user_id,p_job_id,p_worker_id,p_request_id);
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
 result:=public.collect_confirm_receipt(p_operator_user_id,p_job_id,p_claim_token,p_fence_version,p_destination_revision,p_body_sha256,p_confirmation_id);
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
 result:=public.collect_record_send_start(p_operator_user_id,p_job_id,p_claim_token,p_fence_version,p_confirmation_id);
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
