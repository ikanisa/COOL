-- Disposable synthetic PostgreSQL fixture ONLY. Before running, the fixture
-- substitutes the placeholders with UUIDs belonging to the seeded capture
-- principal, its distinct canonical beneficiary, an unrelated subject, a
-- cross-group/wrong-attempt beneficiary decoy, and a synthetic subject with at
-- least 101 distinct positive source links.
-- The fixture supplies normal application roles, the 53-migration predecessor,
-- migration 20261114110000, and committed source/payment/link relationships.
-- Never run this file against a live database.
BEGIN;
CREATE FUNCTION pg_temp.test_native_retention_links(subject text,class_name text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp
AS $test$ SELECT private._burimunsi_retention_positive_links_v1(subject,class_name) $test$;
REVOKE ALL ON FUNCTION pg_temp.test_native_retention_links(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION pg_temp.test_native_retention_links(text,text) TO collect_runtime;
DO $privileges$
BEGIN
 IF has_function_privilege('collect_runtime','private._burimunsi_retention_positive_links_v1(text,text)','EXECUTE')
  OR has_function_privilege('anon','private._burimunsi_retention_positive_links_v1(text,text)','EXECUTE')
  OR has_function_privilege('authenticated','private._burimunsi_retention_positive_links_v1(text,text)','EXECUTE')
  OR has_function_privilege('service_role','private._burimunsi_retention_positive_links_v1(text,text)','EXECUTE') THEN
  RAISE EXCEPTION 'native_retention_helper_exposed';END IF;
END;$privileges$;
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true),set_config('burimunsi.native_receipt_frame','0',true);
DO $verify$
DECLARE actor jsonb;member jsonb;outsider jsonb;decoy jsonb;bulk jsonb;item jsonb;class_name text;
BEGIN
 FOREACH class_name IN ARRAY ARRAY['private:burimunsi_native_receipt_origins','private:burimunsi_auto_sms_jobs'] LOOP
  actor:=pg_temp.test_native_retention_links('__CAPTURE_PRINCIPAL__',class_name);
  member:=pg_temp.test_native_retention_links('__CANONICAL_BENEFICIARY__',class_name);
  outsider:=pg_temp.test_native_retention_links('__UNRELATED_SUBJECT__',class_name);
  decoy:=pg_temp.test_native_retention_links('__CROSS_SCOPE_DECOY__',class_name);
  bulk:=pg_temp.test_native_retention_links('__BULK_SUBJECT__',class_name);
  FOREACH item IN ARRAY ARRAY[actor,member,outsider,decoy,bulk] LOOP
   IF item->'complete' IS DISTINCT FROM 'false'::jsonb OR item->>'erasure'<>'blocked'
    OR item->'limit' IS DISTINCT FROM '100'::jsonb OR jsonb_typeof(item->'matches')<>'array'
    OR jsonb_typeof(item->'truncated')<>'boolean' THEN
    RAISE EXCEPTION 'native_retention_metadata_invalid';END IF;
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(actor->'matches') e
      WHERE e->>'relationship'='capture_principal' AND e->>'record_key_sha256' ~ '^[a-f0-9]{64}$')
   OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(member->'matches') e
      WHERE e->>'relationship'='canonical_beneficiary' AND e->>'record_key_sha256' ~ '^[a-f0-9]{64}$')
   OR jsonb_array_length(outsider->'matches')<>0 OR outsider->'complete' IS DISTINCT FROM 'false'::jsonb
   OR jsonb_array_length(decoy->'matches')<>0 OR decoy->'complete' IS DISTINCT FROM 'false'::jsonb
   OR jsonb_array_length(bulk->'matches')<>100 OR bulk->'truncated' IS DISTINCT FROM 'true'::jsonb THEN
   RAISE EXCEPTION 'native_retention_subject_mapping_failed';END IF;
  IF actor::text LIKE '%__CAPTURE_PRINCIPAL__%' OR member::text LIKE '%__CANONICAL_BENEFICIARY__%'
   OR current_setting('burimunsi.native_receipt_frame',true)<>'0' THEN
   RAISE EXCEPTION 'native_retention_raw_or_frame_leaked';END IF;
 END LOOP;
 BEGIN
  PERFORM pg_temp.test_native_retention_links('__CAPTURE_PRINCIPAL__','private:unrelated');
  RAISE EXCEPTION 'native_retention_unknown_class_accepted';
 EXCEPTION WHEN SQLSTATE '22023' THEN NULL;END;
 IF current_setting('burimunsi.native_receipt_frame',true)<>'0' THEN
  RAISE EXCEPTION 'native_retention_frame_not_restored';END IF;
END;$verify$;
ROLLBACK;
SELECT 'synthetic_native_retention_positive_links_pass';
