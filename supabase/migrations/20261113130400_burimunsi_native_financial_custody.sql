-- Native receipt evidence only. Requires the separately reviewed native worker
-- lease; never creates financial authority, a gateway binding, or a payment.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR to_regprocedure('private.burimunsi_native_work_assert(uuid,uuid,bigint)') IS NULL
  OR to_regprocedure('private.burimunsi_auto_plan(text)') IS NULL
  OR to_regprocedure('private.burimunsi_native_custody_snapshot(uuid,uuid,bigint)') IS NOT NULL
 THEN RAISE EXCEPTION 'burimunsi_native_custody_precondition' USING ERRCODE='55000'; END IF;
END;$preflight$;

CREATE FUNCTION private.burimunsi_native_custody_snapshot(p_job uuid,p_token uuid,p_version bigint) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE work jsonb;captured jsonb;result jsonb;
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 -- Both calls are server-scoped and verify the current admitted jobs fence.
 -- The lease guard additionally locks the scoped worker grant and financial
 -- policy. The native auto plan rechecks the original account, capture grant,
 -- consent, observation, detection snapshot and committed storage identity.
 work:=private.burimunsi_native_work_assert(p_job,p_token,p_version);
 IF work IS NULL OR work->>'kind' IS DISTINCT FROM 'native_receipt' THEN
  RAISE EXCEPTION 'burimunsi_native_custody_changed' USING ERRCODE='40001';END IF;
 captured:=private.burimunsi_auto_plan(work->>'sourceId');
 IF captured->>'kind' IS DISTINCT FROM 'jobs' OR captured->'proof'->>'sourceId' IS DISTINCT FROM work->>'sourceId'
  OR captured->'actor'->>'collectionId' IS DISTINCT FROM work->>'groupId'
  OR captured->'proof'->>'bodySha256' IS DISTINCT FROM work->>'bodySha256'
  OR captured->'proof'->>'object_sha256' IS DISTINCT FROM work->>'objectSha256'
  OR captured->'proof'->>'fingerprint' IS DISTINCT FROM work->>'sourceFingerprint'
  OR captured->'proof'->>'principalUserId' IS DISTINCT FROM work->>'ownerUserId'
  OR captured->'proof'->>'size_bytes' IS DISTINCT FROM work->>'objectSizeBytes' THEN
  RAISE EXCEPTION 'burimunsi_native_custody_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT jsonb_build_object(
  'sourceId',o.source_id,'groupId',o.collection_id,'ownerUserId',o.principal_user_id,
  'bodySha256',o.body_sha256,'objectSha256',o.object_sha256,'objectSizeBytes',r.size_bytes,
  'sourceFingerprint',o.fingerprint,'evidenceLevel',r.evidence_level,
  'transaction',jsonb_build_object('id',t.id,'groupId',x.collection_id,'sourceId',o.source_id,
   'receivingAccountId',t.receiving_account_id,'provider',t.provider,'providerTransactionId',t.provider_transaction_id,
   'eventKind',t.event_kind,'paymentOutcome',j.payment_outcome,'amountMinor',t.amount_minor,'currency',t.currency,
   'mode',t.mode,'allocationState',t.allocation_state,'hasConflict',t.has_conflict,
   'parseAttemptId',a.id,'parseOutput',a.output_json::jsonb,'payerIdentifier',t.payer_identifier),
  'account',jsonb_build_object('id',w.id,'provider',w.provider,'public_code',w.public_code,'receiver_hash',w.receiver_hash,
   'status',w.status,'profile_status',w.profile_status,'profile_version',w.profile_version,
   'profile_json',w.profile_json,'currency',w.currency,'timezone',w.timezone)) INTO result
 FROM private.burimunsi_native_receipt_origins o
 JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=o.source_id AND j.collection_id=o.collection_id
  AND j.source_fingerprint=o.fingerprint AND j.state='completed' AND j.phase='finished' AND j.relation='accepted'
 JOIN app.sms_receipts r ON r.id=o.source_id AND r.owner_user_id=o.principal_user_id
  AND r.body_sha256=o.body_sha256 AND r.object_sha256=o.object_sha256 AND r.object_key='sms/'||o.source_id
  AND r.evidence_level='client_received' AND r.originating_session_id IS NULL
 JOIN private.burimunsi_transaction_scopes x ON x.transaction_id=j.transaction_id AND x.collection_id=o.collection_id
  AND x.native_source_id=o.source_id AND x.source_binding_id IS NULL AND x.source_binding_version IS NULL
 JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
  AND t.receiving_account_id=j.receiving_account_id AND t.parse_attempt_id=j.attempt_id::text
 JOIN app.momo_transaction_sources s ON s.transaction_id=t.id AND s.raw_sms_id=o.source_id
  AND s.parse_attempt_id=t.parse_attempt_id AND s.relation='accepted'
 JOIN app.momo_parse_attempts a ON a.id=s.parse_attempt_id AND a.raw_sms_id=o.source_id
  AND a.source_body_sha256=o.body_sha256 AND a.outcome='accepted'
 JOIN private.burimunsi_scopes scope ON scope.collection_id=o.collection_id AND scope.receiving_account_id=t.receiving_account_id
 JOIN app.momo_receiving_accounts w ON w.id=t.receiving_account_id AND w.provider=t.provider
 WHERE o.source_id=work->>'sourceId' AND o.collection_id=work->>'groupId' AND t.id=work->>'transactionId'
  AND t.mode=work->>'transactionMode' AND t.event_kind='incoming_receipt' AND j.payment_outcome='successful'
  AND t.provider_transaction_id IS NOT NULL AND t.amount_minor>0 AND t.currency='RWF' AND t.has_conflict=0
  AND t.allocation_state='unallocated' AND a.output_json IS NOT NULL
  AND w.status='active' AND w.profile_status='approved' AND w.profile_version<>'unverified'
  AND NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources bad WHERE bad.transaction_id=t.id AND bad.relation='conflict')
 FOR SHARE OF o,j,r,x,t,s,a,scope,w;
 IF result IS NULL OR result->>'bodySha256' IS DISTINCT FROM work->>'bodySha256'
  OR result->>'objectSha256' IS DISTINCT FROM work->>'objectSha256'
  OR result->>'sourceFingerprint' IS DISTINCT FROM work->>'sourceFingerprint'
  OR result->>'ownerUserId' IS DISTINCT FROM work->>'ownerUserId'
  OR result->>'objectSizeBytes' IS DISTINCT FROM work->>'objectSizeBytes'
  OR private.burimunsi_native_work_assert(p_job,p_token,p_version) IS DISTINCT FROM work
  OR private.burimunsi_auto_plan(work->>'sourceId') IS DISTINCT FROM captured THEN
  RAISE EXCEPTION 'burimunsi_native_custody_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('work',work,'capture',captured,'receipt',result);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_custody_snapshot(uuid,uuid,bigint)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_custody_snapshot(uuid,uuid,bigint) TO collect_runtime;
COMMIT;
