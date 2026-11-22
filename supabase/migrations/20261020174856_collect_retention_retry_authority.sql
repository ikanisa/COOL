-- Preserve immutable original erasure evidence; require independently current
-- fenced authority and a deduplicated append-only attempt for each resumed send.
CREATE OR REPLACE FUNCTION private.assert_storage_delete_authorized(p_key text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE actor text;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key,7346369));
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);
 IF EXISTS(SELECT 1 FROM app.payment_evidence WHERE object_key=p_key) OR EXISTS(SELECT 1 FROM app.sms_receipts WHERE object_key=p_key) OR EXISTS(SELECT 1 FROM app.roster_imports WHERE source_object_key=p_key) THEN RAISE EXCEPTION 'storage_retention_class_not_erasable' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM private.storage_put_intents i
  JOIN app.upload_objects o ON o.object_key=i.object_key AND o.sha256=i.sha256 AND o.user_id=i.scope->>'ownerId' AND o.id=i.scope->>'entityId'
  JOIN app.privacy_retention_effects e ON e.object_key=i.object_key AND e.source_sha256=i.sha256
  -- Original admission remains immutable evidence. It is never the authority
  -- for a resumed request: the independently current task claim below is.
  JOIN app.privacy_retention_claims original_claim ON original_claim.id=e.claim_id AND original_claim.task_id=e.task_id AND original_claim.fence=e.fence AND e.started_seconds>=original_claim.claimed_seconds AND e.started_seconds<original_claim.expires_seconds
  JOIN app.privacy_retention_tasks t ON t.id=e.task_id AND t.class_name='r2:upload_objects' AND t.action='erase' AND t.state='claimed' AND t.fence>=e.fence
  JOIN app.privacy_retention_claims c ON c.id=t.claim_id AND c.task_id=t.id AND c.fence=t.fence AND c.actor_id=actor AND c.session_id=api.current_session_id() AND c.claimed_seconds<=app.unixepoch() AND c.expires_seconds>app.unixepoch()
  JOIN app.privacy_retention_plans p ON p.id=t.plan_id AND p.subject_id=o.user_id
  JOIN app.privacy_retention_barriers b ON b.subject_id=p.subject_id AND (b.plan_id=p.id OR b.plan_id=app.json_extract(p.policy_json,'$.quarantine_continuation.previous_plan_id'))
  JOIN app.runtime_config cfg ON cfg.key='privacy:retention:approved:v1' AND cfg.revision=p.policy_config_revision AND cfg.value_json=p.policy_json
  WHERE i.object_key=p_key AND i.active_attempt IS NULL AND NOT i.upload_unresolved
   AND app.json_numeric(p.policy_json,'$.writer_fence.generic_upload_catalog_only')=1 AND app.json_numeric(p.policy_json,'$.writer_fence.unknown_in_flight')=0
   AND app.julianday(app.json_extract(p.policy_json,'$.expires_at'))>app.julianday('now')
   AND encode(sha256(convert_to(p.policy_json,'UTF8')),'hex')=p.policy_sha256
   AND coalesce((SELECT revision FROM app.privacy_review_heads WHERE request_id=p.request_id),0)=p.review_revision
   AND EXISTS(SELECT 1 FROM app.mutation_guards g WHERE g.user_id=actor AND g.session_id=api.current_session_id() AND g.permission='privacy.review' AND g.minimum_assurance=2 AND g.fresh_seconds<=300)
   AND EXISTS(SELECT 1 FROM app.privacy_retention_guards g WHERE g.plan_id=p.id AND g.class_name=t.class_name AND g.passed=1)
   -- One append-only marker for this exact current lease/object must precede
   -- any Storage transition. A timeout or the older effect cannot grant a send.
   AND (SELECT count(*) FROM app.privacy_retention_outcomes attempt
    WHERE attempt.task_id=t.id AND attempt.claim_id=c.id AND attempt.fence=c.fence
     AND app.json_extract(attempt.outcome_json,'$.disposition')='catalog_object_send_started'
     AND app.json_numeric(attempt.outcome_json,'$.contract_version')=1
     AND app.json_numeric(attempt.outcome_json,'$.verified')=0
     AND app.json_numeric(attempt.outcome_json,'$.erasure_completed')=0
     AND app.json_numeric(attempt.outcome_json,'$.all_data_erased')=0
     AND app.json_extract(attempt.outcome_json,'$.original_effect_operation_id')=e.operation_id
     AND app.json_extract(attempt.outcome_json,'$.object_key_sha256')=encode(sha256(convert_to(i.object_key,'UTF8')),'hex')
     AND app.json_extract(attempt.outcome_json,'$.source_sha256')=e.source_sha256
     AND app.json_extract(attempt.outcome_json,'$.source_id')=p.source_id
     AND app.json_extract(attempt.outcome_json,'$.policy_sha256')=p.policy_sha256
     AND attempt.observed_seconds>=c.claimed_seconds AND attempt.observed_seconds<c.expires_seconds)=1
   AND NOT EXISTS(SELECT 1 FROM app.privacy_holds h WHERE h.user_id=p.subject_id AND h.active=1)
   AND NOT EXISTS(SELECT 1 FROM app.native_reservations n WHERE n.user_id=p.subject_id AND n.state NOT IN('completed','rejected'))
   AND NOT EXISTS(SELECT 1 FROM app.roster_imports r WHERE r.user_id=p.subject_id AND r.state IN('processing','ambiguous'))
   AND NOT EXISTS(SELECT 1 FROM app.auth_otp_challenges x WHERE x.identity_value IN(SELECT phone FROM app.users WHERE id=p.subject_id UNION SELECT email FROM app.users WHERE id=p.subject_id) AND x.status IN('dispatching','delivery_unknown'))
 ) THEN RAISE EXCEPTION 'storage_retention_admission_required' USING ERRCODE='42501'; END IF;
END$$;
