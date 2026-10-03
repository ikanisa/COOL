CREATE OR REPLACE FUNCTION public.admin_cancel_unstarted_receipt_v1(p_request_id uuid, p_outbox_id uuid, p_expected_revision bigint, p_reason_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare sid uuid;job collect_hybrid.sms_notification_outbox;prior collect_receipt_actions.cancellations;
 before_revision bigint;after_revision bigint;at timestamptz;begin
 sid:=collect_receipt_actions.actor(true);
 if p_request_id is null or p_outbox_id is null or p_expected_revision is null
  or p_expected_revision not between 1 and 999999999 or p_reason_code is null
  or p_reason_code not in('operator_cancelled','recipient_review_required','content_review_required')then
  raise exception 'receipt_action_input_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended('collect-receipt-cancel-request:'||p_request_id::text,0));
 select * into prior from collect_receipt_actions.cancellations where request_id=p_request_id;
 if prior.request_id is not null then
  if prior.actor_id<>auth.uid()or prior.outbox_id<>p_outbox_id or prior.expected_revision<>p_expected_revision
   or prior.reason_code<>p_reason_code then raise exception 'receipt_action_request_conflict'using errcode='22023';end if;
  perform collect_receipt_actions.actor(true);
  return collect_receipt_actions.receipt(prior);
 end if;
 select * into job from collect_hybrid.sms_notification_outbox where id=p_outbox_id for update;
 -- Revalidate natural expiry after waiting, without changing the lock order:
 -- all authority proof locks were already held before the request/outbox lock.
 perform collect_receipt_actions.actor(true);
 select coalesce((select revision from collect_receipt_actions.revisions where outbox_id=job.id),1)into before_revision;
 if job.id is null or not collect_receipt_actions.rwanda_source(job)then
  raise exception 'receipt_action_unavailable'using errcode='55000';end if;
 if before_revision<>p_expected_revision then raise exception 'receipt_action_source_changed'using errcode='55000';end if;
 if collect_receipt_actions.ineligible_reason(job)is distinct from 'eligible'then
  raise exception 'receipt_not_cancellable'using errcode='55000';end if;
 update collect_hybrid.sms_notification_outbox set state='suppressed',suppression_reason='manual_pre_send_cancel'
  where id=job.id;
 select revision into after_revision from collect_receipt_actions.revisions where outbox_id=job.id;
 if after_revision is distinct from before_revision+1 then
  raise exception 'receipt_action_revision_invalid'using errcode='55000';end if;
 at:=clock_timestamp();
 insert into collect_receipt_actions.cancellations(request_id,outbox_id,expected_revision,revision,
  reason_code,actor_id,session_id,recorded_at)
 values(p_request_id,job.id,before_revision,after_revision,p_reason_code,auth.uid(),sid,at)returning * into prior;
 perform public.create_audit_log('notification.sms.cancelled_unstarted','sms_notification_outbox',job.id,
  jsonb_build_object('request_id',p_request_id,'expected_revision',before_revision,'revision',after_revision,
   'reason_code',p_reason_code,'financial_action',false,'send_action',false),null);
 return collect_receipt_actions.receipt(prior);
end$function$

