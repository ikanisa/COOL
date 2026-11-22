BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced') THEN
  RAISE EXCEPTION 'burimunsi_admin_sms_health_fence_required' USING ERRCODE='55000';
 END IF;
END;$preflight$;

CREATE FUNCTION private.burimunsi_admin_sms_health() RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE
 actor record;
 groups text[];
 result jsonb;
 old_observation text:=current_setting('burimunsi.observation_frame',true);
 old_pin text:=current_setting('burimunsi.pin_frame',true);
 old_native text:=current_setting('burimunsi.native_receipt_frame',true);
 old_payment_sms text:=current_setting('burimunsi.payment_sms_frame',true);
BEGIN
 PERFORM private._collect_fence_require_runtime();
 SELECT * INTO actor FROM private.burimunsi_managed_admin_snapshot();
 IF NOT FOUND OR actor.surface<>'admin' OR
  private.assert_actor('system_health.read',NULL,NULL,1,NULL) IS DISTINCT FROM actor.principal_user_id THEN
  RAISE EXCEPTION 'burimunsi_admin_sms_health_denied' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(
  SELECT 1 FROM app.admin_grants g JOIN app.admin_account_role_capabilities c ON c.permission=g.permission
  WHERE g.user_id=actor.principal_user_id AND c.role=actor.shared_role AND g.permission='sms.read'
  FOR SHARE OF g,c
 ) THEN RETURN NULL; END IF;

 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT array_agg(a.collection_id) INTO groups
 FROM private.burimunsi_operator_approvals a
 WHERE a.admin_user_id=actor.admin_id AND a.principal_user_id=actor.principal_user_id AND a.active
 AND ARRAY['records.read','sms.read']::text[] <@ a.capabilities
 AND private.burimunsi_pin_root_snapshot(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities) IS NOT NULL;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 IF groups IS NULL THEN RETURN NULL; END IF;

 PERFORM set_config('burimunsi.observation_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 PERFORM set_config('burimunsi.payment_sms_frame','1',true);
 WITH classified AS (
  SELECT j.created_at, CASE
   WHEN j.state='failed' OR j.state='completed' AND (j.relation='conflict' OR t.has_conflict<>0) THEN 'blocked'
   WHEN j.state='retry' OR j.state='processing' AND j.attempt_count>1 THEN 'retrying'
   WHEN j.state='processing' THEN 'pending'
   WHEN j.state='completed' AND j.relation='accepted' AND t.event_kind='incoming_receipt' THEN
    CASE WHEN l.id IS NOT NULL AND p.status IN ('confirmed','reconciled') AND s.payment_id IS NOT NULL
          AND NOT EXISTS(SELECT 1 FROM app.ledger_entries r WHERE r.reverses_entry_id=l.id) THEN 'posted'
         WHEN f.payment_id IS NOT NULL THEN NULL
         WHEN j.posting_failure_count>0 THEN 'retrying'
         WHEN j.posting_next_attempt_at>0 THEN 'unmatched'
         WHEN t.allocation_state IN ('unallocated','not_applicable') THEN 'pending' END
  END AS lane
  FROM private.burimunsi_auto_sms_jobs j
  LEFT JOIN app.momo_transactions t ON t.id=j.transaction_id
  LEFT JOIN app.momo_financial_links f ON f.transaction_id=t.id
  LEFT JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=j.collection_id AND p.member_id=f.beneficiary_member_id
  LEFT JOIN app.ledger_entries l ON l.payment_id=p.id AND l.collection_id=p.collection_id AND l.member_id=p.member_id
   AND l.kind='contribution' AND l.amount_minor=p.amount_minor AND l.currency=p.currency AND l.evidence_id=p.evidence_id
  LEFT JOIN app.contribution_posting_snapshots s ON s.payment_id=p.id AND s.ledger_entry_id=l.id AND s.posted_at=l.posted_at
  WHERE j.collection_id=ANY(groups)
  UNION ALL
  SELECT o.created_at,'pending'
  FROM private.burimunsi_unresolved_observations o
  WHERE o.collection_id=ANY(groups) AND NOT EXISTS(
   SELECT 1 FROM private.burimunsi_auto_sms_jobs j WHERE j.source_id=o.source_id)
 ), provider AS (
  SELECT CASE
   WHEN d.state='suppressed' THEN 'suppressed'
   WHEN d.state='sending' AND d.lease_until>statement_timestamp() THEN 'pending'
   WHEN d.state IN ('unknown','sending') THEN 'unknown'
   WHEN d.provider_state IN ('accepted','assigned','phone_accepted','queued','handoff_started') THEN 'gateway_accepted'
   WHEN d.provider_state IN ('sent','delivered') THEN d.provider_state
   WHEN d.provider_state IN ('failed','expired','cancelled') THEN 'failed'
   ELSE 'unknown'
  END AS lane
  FROM private.burimunsi_payment_sms_deliveries d WHERE d.collection_id=ANY(groups)
 )
 SELECT jsonb_build_object(
  'burimunsi_sms',(SELECT jsonb_build_object(
   'pending',count(*) FILTER(WHERE lane='pending'),'retrying',count(*) FILTER(WHERE lane='retrying'),
   'blocked',count(*) FILTER(WHERE lane='blocked'),'unmatched',count(*) FILTER(WHERE lane='unmatched'),
   'posted',count(*) FILTER(WHERE lane='posted'),
   'oldest_pending_seconds',CASE WHEN min(created_at) FILTER(WHERE lane IN ('pending','retrying','unmatched')) IS NOT NULL
    THEN greatest(0,floor(extract(epoch FROM statement_timestamp()))::bigint-
     min(created_at/1000) FILTER(WHERE lane IN ('pending','retrying','unmatched'))) END)
   FROM classified),
  'burimunsi_payer_sms',(SELECT jsonb_build_object(
   'pending',count(*) FILTER(WHERE lane='pending'),'gateway_accepted',count(*) FILTER(WHERE lane='gateway_accepted'),
   'sent',count(*) FILTER(WHERE lane='sent'),'delivered',count(*) FILTER(WHERE lane='delivered'),
   'failed',count(*) FILTER(WHERE lane='failed'),'unknown',count(*) FILTER(WHERE lane='unknown'),
   'suppressed',count(*) FILTER(WHERE lane='suppressed')) FROM provider))
 INTO result;

 PERFORM set_config('burimunsi.observation_frame',coalesce(old_observation,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);
 PERFORM set_config('burimunsi.payment_sms_frame',coalesce(old_payment_sms,''),true);
 RETURN result;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_observation,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);
 PERFORM set_config('burimunsi.payment_sms_frame',coalesce(old_payment_sms,''),true);
 RAISE;
END;$fn$;

REVOKE ALL ON FUNCTION private.burimunsi_admin_sms_health()
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_admin_sms_health() TO collect_runtime;
COMMIT;
