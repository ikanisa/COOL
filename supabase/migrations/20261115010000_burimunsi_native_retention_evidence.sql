-- Bounded positive-link evidence for the existing privacy inventory. This
-- migration grants no erasure/retention authority and changes no source,
-- payment, ledger, object, policy or UNKNOWN outcome.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE expected record;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR to_regprocedure('private._burimunsi_retention_evidence_v2(text,text)') IS NOT NULL THEN
  RAISE EXCEPTION 'native_retention_evidence_precondition' USING ERRCODE='55000';END IF;
 FOR expected IN SELECT * FROM(VALUES
  ('private._burimunsi_retention_positive_links_v1(text,text)','3124613986def2fde264d20fc75c3b5974ad9e093dc6b623175c5b03cbbab583'),
  ('private._retention_manifest_rows_v2(text)','79ca2b3459164c66c8ba52670f59f9e9fe31b91d34c20f80fabf9cc58a617f3d')
 ) e(signature,sha256) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(expected.signature)
    AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND p.provolatile='s'
    AND p.proacl::text='{postgres=X/postgres}'
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=expected.sha256) THEN
   RAISE EXCEPTION 'native_retention_evidence_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
END;$preflight$;

CREATE FUNCTION private._burimunsi_retention_evidence_v2(p_subject text,p_class text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
 old_observation_frame text:=current_setting('burimunsi.observation_frame',true);answer jsonb;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 IF p_subject IS NULL OR p_subject !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'
  OR p_class IS NULL OR p_class NOT IN('private:burimunsi_native_receipt_origins','private:burimunsi_auto_sms_jobs') THEN
  RAISE EXCEPTION 'native_retention_evidence_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 PERFORM set_config('burimunsi.observation_frame','1',true);
 WITH financial AS MATERIALIZED(
  SELECT DISTINCT o.source_id,p.member_id,p.evidence_id
  FROM app.payments p
  JOIN app.momo_financial_links f ON f.payment_id=p.id AND f.beneficiary_member_id=p.member_id
  JOIN app.momo_transactions t ON t.id=f.transaction_id
  JOIN app.momo_transaction_sources ts ON ts.transaction_id=t.id
   AND ts.parse_attempt_id=t.parse_attempt_id AND ts.relation='accepted'
  JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=ts.raw_sms_id AND j.transaction_id=t.id
   AND j.attempt_id::text=ts.parse_attempt_id AND j.receiving_account_id=t.receiving_account_id
   AND j.state='completed' AND j.relation='accepted'
  JOIN private.burimunsi_native_receipt_origins o ON o.source_id=j.source_id
   AND o.collection_id=j.collection_id AND o.collection_id=p.collection_id
 ), links AS(
  SELECT o.source_id,'capture_principal'::text AS relationship
  FROM private.burimunsi_native_receipt_origins o WHERE o.principal_user_id=p_subject
   AND(p_class='private:burimunsi_native_receipt_origins' OR EXISTS(
    SELECT 1 FROM private.burimunsi_auto_sms_jobs j WHERE j.source_id=o.source_id AND j.collection_id=o.collection_id))
  UNION ALL SELECT f.source_id,'canonical_beneficiary' FROM financial f WHERE f.member_id=p_subject
 ), bounded AS MATERIALIZED(
  SELECT DISTINCT source_id,relationship FROM links ORDER BY source_id,relationship LIMIT 101
 ), described AS(
  SELECT b.source_id,b.relationship,
   jsonb_build_object('relationship',b.relationship,
    'record_key_sha256',encode(sha256(convert_to(p_class||':'||b.source_id,'UTF8')),'hex'),
    'source_row_sha256',encode(sha256(convert_to(to_jsonb(o)::text,'UTF8')),'hex'),
    'payer_identity_asserted',false,'all_subjects_mapped',false,
    'holds',jsonb_build_object(
     'request_subject_active',EXISTS(SELECT 1 FROM app.privacy_holds h WHERE h.user_id=p_subject AND h.active=1),
     'capture_principal_active',EXISTS(SELECT 1 FROM app.privacy_holds h WHERE h.user_id=o.principal_user_id AND h.active=1),
     'canonical_beneficiary_active',EXISTS(SELECT 1 FROM financial f JOIN app.privacy_holds h ON h.user_id=f.member_id AND h.active=1 WHERE f.source_id=b.source_id),
     'financial_evidence_active',EXISTS(SELECT 1 FROM financial f JOIN app.payment_evidence e ON e.id=f.evidence_id WHERE f.source_id=b.source_id AND e.legal_hold=1)),
    'retention',jsonb_build_object('disposition','blocked','policy_assessed',false,
     'existing_financial_deadline_recorded',EXISTS(SELECT 1 FROM financial f JOIN app.payment_evidence e ON e.id=f.evidence_id WHERE f.source_id=b.source_id AND e.retained_until IS NOT NULL)),
    'custody',jsonb_build_object('object_key_sha256',CASE WHEN ob.object_key IS NULL THEN NULL ELSE encode(sha256(convert_to(ob.object_key,'UTF8')),'hex') END,
     'source_receipt_binding_matches',coalesce(ob.object_key='sms/'||o.source_id AND ob.collection_id=o.collection_id
      AND ob.principal_user_id=o.principal_user_id AND ob.body_sha256=o.body_sha256 AND ob.object_sha256=o.object_sha256 AND raw.object_key=ob.object_key
      AND raw.owner_user_id=o.principal_user_id AND raw.body_sha256=o.body_sha256 AND raw.object_sha256=o.object_sha256,false),
     'intent_present',i.object_key IS NOT NULL,'catalog_present',m.object_key IS NOT NULL,
     'catalog_commit_matches',coalesce(i.state='committed' AND m.operation_id=i.operation_id AND m.fingerprint=i.fingerprint
      AND m.sha256=i.sha256 AND m.size=i.size AND m.scope=i.scope AND m.http_metadata=i.http_metadata AND m.custom_metadata=i.custom_metadata,false),
     'scope_matches_capture_principal',coalesce(i.scope=jsonb_build_object('ownerId',o.principal_user_id,'purpose','sms_receipt','entityId',o.source_id),false),
     'reservation_present',reservation.object_key IS NOT NULL,
     'reservation_plaintext_matches',coalesce(reservation.plaintext_sha256=o.object_sha256 AND reservation.scope=i.scope
      AND reservation.aad='sms:'||o.source_id||':'||o.object_sha256,false),
     'reservation_sealed',coalesce(reservation.sealed_body IS NOT NULL AND reservation.cleared_at IS NULL,false),
     'upload_unresolved',coalesce(i.upload_unresolved,true),'upload_active',coalesce(i.active_attempt IS NOT NULL,false),
     'delete_pending_or_tombstoned',coalesce(i.delete_tombstone,false) OR deletion.object_key IS NOT NULL,
     'physical_object_verified',false,'external_copies_verified',false),
    'processing',jsonb_build_object('job_present',j.source_id IS NOT NULL,'state',j.state,'phase',j.phase,
     'active',coalesce(j.state='processing',false),'unresolved',coalesce(j.state IN('retry','failed') OR j.relation='conflict' OR j.payment_outcome='unknown',true),
     'observation_sha256',CASE WHEN j.source_id IS NULL THEN NULL ELSE encode(sha256(convert_to(to_jsonb(j)::text,'UTF8')),'hex') END,
     'observation_includes_mutable_job_metadata',true,'control_plane_unknowns','not_assessed_by_this_projection')) AS descriptor
  FROM bounded b JOIN private.burimunsi_native_receipt_origins o ON o.source_id=b.source_id
  LEFT JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=o.source_id AND j.collection_id=o.collection_id
  LEFT JOIN private.burimunsi_unresolved_observations ob ON ob.source_id=o.source_id
  LEFT JOIN app.sms_receipts raw ON raw.id=o.source_id
  LEFT JOIN private.storage_put_intents i ON i.object_key=ob.object_key
  LEFT JOIN private.storage_objects m ON m.object_key=i.object_key
  LEFT JOIN private.storage_payload_reservations reservation ON reservation.object_key=i.object_key
  LEFT JOIN private.storage_delete_intents deletion ON deletion.object_key=i.object_key
 ), numbered AS(SELECT descriptor,row_number() OVER(ORDER BY source_id,relationship) AS n FROM described)
 SELECT jsonb_build_object('contract_version',2,'complete',false,'erasure','blocked','limit',100,
  'truncated',count(*)>100,'missing_matches_prove_absence',false,'payer_identity','unresolved',
  'physical_objects_verified',false,'retention_approval_granted',false,
  'matches',coalesce(jsonb_agg(descriptor ORDER BY n) FILTER(WHERE n<=100),'[]'::jsonb)) INTO answer FROM numbered;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_observation_frame,''),true);
 RETURN answer;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_observation_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private._burimunsi_retention_evidence_v2(text,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

DO $integrate$
DECLARE body text;anchor text:='private._burimunsi_retention_positive_links_v1(p_subject,c->>''name'')';
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_rows_v2(text)'::regprocedure;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'native_retention_evidence_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_rows_v2(p_subject text) RETURNS TABLE(class_name text,descriptor jsonb) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=app,pg_catalog,pg_temp AS '||
  quote_literal(replace(body,anchor,'private._burimunsi_retention_evidence_v2(p_subject,c->>''name'')'));
END;$integrate$;
COMMIT;
