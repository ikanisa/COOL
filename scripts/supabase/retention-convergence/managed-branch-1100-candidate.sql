-- Positive subject evidence only. Unmapped classes, object custody and every
-- retention disposition remain blocked. Missing links never establish absence.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $preflight$
DECLARE r record;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR to_regprocedure('private._burimunsi_retention_positive_links_v1(text,text)') IS NOT NULL THEN
  RAISE EXCEPTION 'burimunsi_retention_positive_precondition' USING ERRCODE='55000';END IF;
 FOR r IN SELECT * FROM (VALUES
  ('private._retention_manifest_catalog_v2()','aa9aa0086b70ced2d8533946c98e53814c183891c9057c307b3d207a30650674',false,'i','sql','{postgres=X/postgres}',ARRAY['search_path=pg_catalog, pg_temp']::text[]),
  ('private._retention_manifest_rows_v2(text)','5aa6ca4011d0fa45e644066da4e90fd74fa55fe0c115a13c047e5399319a30a0',true,'s','plpgsql','{postgres=X/postgres}',ARRAY['search_path=app, pg_catalog, pg_temp']::text[]),
  ('private._retention_manifest_schema_v2()','afad38d443badf352c865abb5ca1f9fd939566da05c1c29f50f10ab8905a3feb',true,'s','plpgsql','{postgres=X/postgres}',ARRAY['search_path=pg_catalog, pg_temp']::text[]),
  ('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','9f89fad1121d4f33e25fb5b9a7f56ff67873bf101ab3d7da294ca3f141b713f5',true,'v','plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}',ARRAY['search_path=pg_catalog, pg_temp']::text[]),
  ('private._retention_row_policy_v2(uuid,text,text,text)','642f9f6545776e0ed6abca60007a9ea8c2d79faed0945d70ccbc8219eaa86228',true,'s','plpgsql','{postgres=X/postgres}',ARRAY['search_path=pg_catalog, pg_temp']::text[])
 ) e(sig,hash,definer,volatility,language,acl,config) LOOP
  IF to_regprocedure(r.sig) IS NULL OR NOT EXISTS(
   SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure(r.sig) AND pg_get_userbyid(p.proowner)='postgres'
    AND p.prosecdef=r.definer AND p.provolatile=r.volatility AND p.prokind='f'
    AND p.proparallel='u' AND NOT p.proleakproof AND l.lanname=r.language
    AND p.proacl::text=r.acl AND p.proconfig=r.config
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.hash) THEN
   RAISE EXCEPTION 'burimunsi_retention_positive_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
 IF (SELECT count(DISTINCT c->>'name') FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') c
     WHERE c->>'name' IN ('private:burimunsi_native_receipt_origins','private:burimunsi_auto_sms_jobs')
      AND c->>'scope'='unmapped_private' AND c->'blocked'='true'::jsonb)<>2 THEN
  RAISE EXCEPTION 'burimunsi_retention_positive_catalog_changed' USING ERRCODE='55000';END IF;
END;$preflight$;

-- This helper is called only by the existing owner-only inventory reader.
-- It returns at most 100 positive, source-bound links, identified by hashes.
-- A beneficiary is an existing canonical linked member, not an asserted payer.
CREATE FUNCTION private._burimunsi_retention_positive_links_v1(p_subject text,p_class text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.native_receipt_frame',true);answer jsonb;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 IF p_subject IS NULL OR p_subject !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'
  OR p_class IS NULL OR p_class NOT IN('private:burimunsi_native_receipt_origins','private:burimunsi_auto_sms_jobs') THEN
  RAISE EXCEPTION 'burimunsi_retention_positive_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 WITH links AS (
  SELECT o.source_id,'capture_principal'::text AS relationship
   FROM private.burimunsi_native_receipt_origins o
   WHERE o.principal_user_id=p_subject AND (p_class='private:burimunsi_native_receipt_origins'
    OR EXISTS(SELECT 1 FROM private.burimunsi_auto_sms_jobs j
     WHERE j.source_id=o.source_id AND j.collection_id=o.collection_id))
  UNION ALL
  SELECT o.source_id,'canonical_beneficiary'::text FROM app.payments p
   JOIN app.momo_financial_links f ON f.payment_id=p.id AND f.beneficiary_member_id=p.member_id
   JOIN app.momo_transactions t ON t.id=f.transaction_id
   JOIN app.momo_transaction_sources ts ON ts.transaction_id=t.id
    AND ts.parse_attempt_id=t.parse_attempt_id AND ts.relation='accepted'
   JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=ts.raw_sms_id AND j.transaction_id=t.id
    AND j.attempt_id::text=ts.parse_attempt_id AND j.receiving_account_id=t.receiving_account_id
    AND j.state='completed' AND j.relation='accepted'
   JOIN private.burimunsi_native_receipt_origins o ON o.source_id=j.source_id
    AND o.collection_id=j.collection_id AND o.collection_id=p.collection_id
   WHERE p.member_id=p_subject
 ), bounded AS MATERIALIZED (
  SELECT DISTINCT source_id,relationship FROM links ORDER BY source_id,relationship LIMIT 101
 ), numbered AS (
  SELECT source_id,relationship,row_number() OVER(ORDER BY source_id,relationship) AS n FROM bounded
 )
 SELECT jsonb_build_object('complete',false,'erasure','blocked','limit',100,
  'truncated',count(*)>100,
  'matches',coalesce(jsonb_agg(jsonb_build_object('relationship',relationship,
   'record_key_sha256',encode(sha256(convert_to(p_class||':'||source_id,'UTF8')),'hex'))
   ORDER BY n) FILTER(WHERE n<=100),'[]'::jsonb)) INTO answer FROM numbered;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 RETURN answer;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private._burimunsi_retention_positive_links_v1(text,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

DO $integrate$
DECLARE body text;anchor text;replacement text;
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_rows_v2(text)'::regprocedure;
 anchor:=$a$  IF c->>'scope'='unmapped_private' OR c->>'name'=ANY(ARRAY['private:storage_payload_reservations'$a$;
 replacement:=$b$  IF c->>'name' IN ('private:burimunsi_native_receipt_origins','private:burimunsi_auto_sms_jobs') THEN
   RETURN QUERY SELECT c->>'name',jsonb_build_object('kind','class','status','unmapped','subject_count',NULL,
    'erasure','blocked','present',to_regclass(c->>'relation') IS NOT NULL,'object_custody','unverified',
    'lifecycle',jsonb_build_object('unresolved',true),
    'positive_subject_links',private._burimunsi_retention_positive_links_v1(p_subject,c->>'name'));
   CONTINUE;
  END IF;
  IF c->>'scope'='unmapped_private' OR c->>'name'=ANY(ARRAY['private:storage_payload_reservations'$b$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'burimunsi_retention_positive_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_rows_v2(p_subject text) RETURNS TABLE(class_name text,descriptor jsonb) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=app,pg_catalog,pg_temp AS '||quote_literal(replace(body,anchor,replacement));
END;$integrate$;
COMMIT;
