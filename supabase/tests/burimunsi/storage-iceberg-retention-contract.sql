-- Disposable networkless schema fixture. No production rows or provider calls.
BEGIN;
SELECT pg_advisory_xact_lock_shared(7346371,1);
-- The synthetic JWT must describe the seeded authentication event, which may
-- precede this test by several seconds when the full Edge suite is running.
SELECT set_config('collect.synthetic_otp_at',
 (SELECT floor(extract(epoch FROM updated_at))::bigint::text FROM auth.mfa_amr_claims
  WHERE id='60000000-0000-4000-8000-000000000004'
    AND session_id='60000000-0000-4000-8000-000000000002' AND authentication_method='otp'),true);
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id','__ADMIN_ADMISSION__',true),
 set_config('collect.fence_epoch','2',true),set_config('collect.fence_source_sha256','__SOURCE__',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','60000000-0000-4000-8000-000000000001',
 'session_id','60000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','exp',app.unixepoch()+3500,
 'amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',current_setting('collect.synthetic_otp_at')::bigint)))::text,true);
SELECT private.admin_email_record_initial('synthetic-admin',repeat('a',64),'https://admin.synthetic.invalid',
 '60000000-0000-4000-8000-000000000003','synthetic-email-challenge');
SELECT set_config('collect.admin_email_context',jsonb_build_object('admin_id','synthetic-admin','cookie_hash',repeat('a',64),
 'origin','https://admin.synthetic.invalid','public_session_id','60000000-0000-4000-8000-000000000003')::text,true);
CREATE TEMP TABLE capture_result(value jsonb) ON COMMIT DROP;
INSERT INTO capture_result SELECT private.retention_capture_inventory_v2('b0000000-0000-4000-8000-000000000003',
 'b0000000-0000-4000-8000-000000000002',0,'__SOURCE__',1000000);
DO $verify$
DECLARE v jsonb;
BEGIN
 SELECT value INTO STRICT v FROM capture_result;
 IF v->'class_counts'->'managed:storage_iceberg'->'rows' IS DISTINCT FROM 'null'::jsonb
  OR v->'class_counts'->'managed:storage_iceberg'->>'status'<>'unverified'
  OR v->'erasure_completed' IS DISTINCT FROM 'false'::jsonb
  OR v->'physical_objects_verified' IS DISTINCT FROM 'false'::jsonb
  OR v->'approval_granted' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION 'iceberg_capture_projection_failed';END IF;
END;$verify$;
DO $direct_erasure$
DECLARE relation text;
BEGIN
 FOREACH relation IN ARRAY ARRAY['storage.buckets_analytics','storage.iceberg_namespaces','storage.iceberg_tables'] LOOP
  BEGIN
   EXECUTE 'DELETE FROM '||relation;
   RAISE EXCEPTION 'storage_delete_unexpectedly_allowed';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  BEGIN
   EXECUTE 'TRUNCATE '||relation;
   RAISE EXCEPTION 'storage_truncate_unexpectedly_allowed';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
 END LOOP;
END;$direct_erasure$;
RESET ROLE;
DO $policy$
DECLARE m private.retention_inventory_manifests%ROWTYPE;p jsonb;rules jsonb;raw text;pin text;action text;
BEGIN
 SELECT * INTO STRICT m FROM private.retention_inventory_manifests WHERE id='b0000000-0000-4000-8000-000000000003';
 SELECT jsonb_object_agg(k,jsonb_build_object('action','blocked','basis_reference','synthetic-only','deadline','2026-01-01T00:00:00.000Z')) INTO rules
 FROM jsonb_object_keys(m.class_counts) k;
 rules:=rules||jsonb_build_object('access',jsonb_build_object('action','quarantine','basis_reference','synthetic-only','deadline','2026-01-01T00:00:00.000Z'));
 p:=jsonb_build_object('contract_version',2,'scope','sql_rows_only','policy_id','b0000000-0000-4000-8000-000000000004',
  'environment','test','synthetic_test_only',true,'approval_evidence_sha256',repeat('c',64),
  'approved_by','60000000-0000-4000-8000-000000000001','approved_at','2026-01-01T00:00:00.000Z','expires_at','2099-01-01T00:00:00.000Z',
  'source_id',m.source_sha256,'schema_sha256',m.schema_sha256,'manifest_id',m.id::text,'manifest_sha256',m.manifest_sha256,
  'request_id',m.request_id,'subject_id',m.subject_id,'review_revision',0,'rules',rules,
  'writer_fence',jsonb_build_object('source_id',m.source_sha256,'evidence_sha256',repeat('d',64),'unknown_in_flight',false),
  'copy_inventory',jsonb_build_object('unmapped_copies','blocked','physical_objects','blocked','providers','blocked','bff_access_revocation','block'),
  'quarantine_continuation',NULL);
 raw:=p::text;pin:=encode(sha256(convert_to(raw,'UTF8')),'hex');
 INSERT INTO app.runtime_config(key,value_json,revision,updated_by,updated_at)
 VALUES('privacy:retention:approved:v2',raw,1,'synthetic-owner','2026-01-01T00:00:00.000Z');
 PERFORM private._retention_row_policy_v2(m.id,pin,'test',m.source_sha256);
 FOREACH action IN ARRAY ARRAY['erase','retain'] LOOP
  raw:=jsonb_set(p,'{rules,managed:storage_iceberg,action}',to_jsonb(action))::text;
  pin:=encode(sha256(convert_to(raw,'UTF8')),'hex');
  UPDATE app.runtime_config SET value_json=raw WHERE key='privacy:retention:approved:v2';
  BEGIN
   PERFORM private._retention_row_policy_v2(m.id,pin,'test',m.source_sha256);
   RAISE EXCEPTION 'iceberg_disposition_unexpectedly_allowed';
  EXCEPTION WHEN SQLSTATE '42501' THEN
   IF SQLERRM<>'retention_row_unsupported_disposition' THEN RAISE;END IF;
  END;
 END LOOP;
 raw:=jsonb_set(p,'{rules}',(p->'rules')-'managed:storage_iceberg'::text)::text;
 pin:=encode(sha256(convert_to(raw,'UTF8')),'hex');
 UPDATE app.runtime_config SET value_json=raw WHERE key='privacy:retention:approved:v2';
 BEGIN
  PERFORM private._retention_row_policy_v2(m.id,pin,'test',m.source_sha256);
  RAISE EXCEPTION 'iceberg_policy_omission_unexpectedly_allowed';
 EXCEPTION WHEN SQLSTATE '42501' THEN
  IF SQLERRM<>'retention_row_policy_classes_changed' THEN RAISE;END IF;
 END;
 IF (SELECT count(*) FROM storage.buckets_analytics)<>1 OR (SELECT count(*) FROM storage.iceberg_namespaces)<>1
  OR (SELECT count(*) FROM storage.iceberg_tables)<>1 THEN RAISE EXCEPTION 'synthetic_shared_catalog_changed';END IF;
END;$policy$;
ROLLBACK;
SELECT 'synthetic_census_and_policy_pass';
