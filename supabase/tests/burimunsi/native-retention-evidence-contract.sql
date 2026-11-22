-- Disposable synthetic PostgreSQL fixture ONLY. Substitute the six identity
-- placeholders as in native-retention-positive-links-contract.sql, after both
-- new migrations. Current runtime work admission must be supplied by fixture.
BEGIN;
CREATE FUNCTION pg_temp.native_retention_evidence(subject text,class_name text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $fn$ SELECT private._burimunsi_retention_evidence_v2(subject,class_name) $fn$;
REVOKE ALL ON FUNCTION pg_temp.native_retention_evidence(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_temp.native_retention_evidence(text,text) TO collect_runtime;
CREATE FUNCTION pg_temp.synthetic_native_hold(subject text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 INSERT INTO app.privacy_holds(id,user_id,category,reason_code,active,created_at)
 VALUES('native-retention-evidence-fixture-hold',subject,'synthetic-only','synthetic-only',1,'2026-01-01');
END;$fn$;
REVOKE ALL ON FUNCTION pg_temp.synthetic_native_hold(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_temp.synthetic_native_hold(text) TO collect_runtime;
DO $acl$
DECLARE role_name text;
BEGIN
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer','collect_runtime'] LOOP
  IF has_function_privilege(role_name,'private._burimunsi_retention_evidence_v2(text,text)','EXECUTE') THEN
   RAISE EXCEPTION 'native_retention_evidence_exposed';END IF;
 END LOOP;
END;$acl$;
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true),set_config('burimunsi.native_receipt_frame','0',true),set_config('burimunsi.observation_frame','0',true);
DO $positive_negative$
DECLARE class_name text;actor jsonb;beneficiary jsonb;outsider jsonb;decoy jsonb;bulk jsonb;item jsonb;matched jsonb;
BEGIN
 FOREACH class_name IN ARRAY ARRAY['private:burimunsi_native_receipt_origins','private:burimunsi_auto_sms_jobs'] LOOP
  actor:=pg_temp.native_retention_evidence('__CAPTURE_PRINCIPAL__',class_name);
  beneficiary:=pg_temp.native_retention_evidence('__CANONICAL_BENEFICIARY__',class_name);
  outsider:=pg_temp.native_retention_evidence('__UNRELATED_SUBJECT__',class_name);
  decoy:=pg_temp.native_retention_evidence('__CROSS_SCOPE_DECOY__',class_name);
  bulk:=pg_temp.native_retention_evidence('__BULK_SUBJECT__',class_name);
  FOREACH item IN ARRAY ARRAY[actor,beneficiary,outsider,decoy,bulk] LOOP
   IF item->'contract_version' IS DISTINCT FROM '2'::jsonb OR item->'complete' IS DISTINCT FROM 'false'::jsonb
    OR item->>'erasure'<>'blocked' OR item->'physical_objects_verified' IS DISTINCT FROM 'false'::jsonb
    OR item->'retention_approval_granted' IS DISTINCT FROM 'false'::jsonb OR item->>'payer_identity'<>'unresolved'
    OR item->'missing_matches_prove_absence' IS DISTINCT FROM 'false'::jsonb THEN RAISE EXCEPTION 'native_retention_evidence_overclaimed';END IF;
   FOR matched IN SELECT value FROM jsonb_array_elements(item->'matches') LOOP
    IF matched->>'relationship' NOT IN('capture_principal','canonical_beneficiary')
     OR matched->>'record_key_sha256'!~'^[a-f0-9]{64}$' OR matched->>'source_row_sha256'!~'^[a-f0-9]{64}$'
     OR matched->'payer_identity_asserted' IS DISTINCT FROM 'false'::jsonb OR matched->'all_subjects_mapped' IS DISTINCT FROM 'false'::jsonb
     OR matched->'custody'->'physical_object_verified' IS DISTINCT FROM 'false'::jsonb
     OR matched->'custody'->'external_copies_verified' IS DISTINCT FROM 'false'::jsonb
     OR matched->'retention'->>'disposition'<>'blocked' OR matched->'retention'->'policy_assessed' IS DISTINCT FROM 'false'::jsonb
     OR matched->'processing'->>'control_plane_unknowns'<>'not_assessed_by_this_projection' THEN
     RAISE EXCEPTION 'native_retention_link_evidence_invalid';END IF;
   END LOOP;
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(actor->'matches') e WHERE e->>'relationship'='capture_principal')
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(beneficiary->'matches') e WHERE e->>'relationship'='canonical_beneficiary')
   OR jsonb_array_length(outsider->'matches')<>0 OR jsonb_array_length(decoy->'matches')<>0
   OR jsonb_array_length(bulk->'matches')<>100 OR bulk->'truncated' IS DISTINCT FROM 'true'::jsonb THEN
   RAISE EXCEPTION 'native_retention_positive_negative_mapping_failed';END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(beneficiary->'matches') e
   WHERE e->'custody'->'source_receipt_binding_matches'='true'::jsonb
    AND e->'custody'->'catalog_commit_matches'='true'::jsonb
    AND e->'custody'->'scope_matches_capture_principal'='true'::jsonb
    AND e->'custody'->'reservation_plaintext_matches'='true'::jsonb) THEN
   RAISE EXCEPTION 'native_retention_positive_custody_hidden';END IF;
  IF actor::text LIKE '%__CAPTURE_PRINCIPAL__%' OR beneficiary::text LIKE '%__CANONICAL_BENEFICIARY__%'
   OR current_setting('burimunsi.native_receipt_frame',true)<>'0'
   OR current_setting('burimunsi.observation_frame',true)<>'0' THEN RAISE EXCEPTION 'native_retention_identity_or_frame_leaked';END IF;
 END LOOP;
 PERFORM pg_temp.synthetic_native_hold('__CANONICAL_BENEFICIARY__');
 beneficiary:=pg_temp.native_retention_evidence('__CANONICAL_BENEFICIARY__','private:burimunsi_native_receipt_origins');
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(beneficiary->'matches') e WHERE e->'holds'->'request_subject_active'='true'::jsonb
  AND e->'holds'->'canonical_beneficiary_active'='true'::jsonb) THEN RAISE EXCEPTION 'native_retention_existing_hold_omitted';END IF;
 BEGIN
  PERFORM pg_temp.native_retention_evidence('__CAPTURE_PRINCIPAL__','private:unrelated');
  RAISE EXCEPTION 'native_retention_unknown_class_accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 IF current_setting('burimunsi.native_receipt_frame',true)<>'0' OR current_setting('burimunsi.observation_frame',true)<>'0' THEN RAISE EXCEPTION 'native_retention_exception_frame_leaked';END IF;
END;$positive_negative$;
ROLLBACK;
SELECT 'synthetic_native_retention_evidence_contract_pass';
