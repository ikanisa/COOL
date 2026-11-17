BEGIN;
DO $provider_policy_preflight$
DECLARE item record;p pg_proc%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_config c JOIN cron.job j ON j.jobid=c.cron_job_id WHERE c.singleton AND NOT c.enabled AND NOT j.active)
  OR EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed'))
  OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='collect_ops.jobs_config'::regclass AND conname='native_provider_budget_binding')
 THEN RAISE EXCEPTION 'native_provider_policy_precondition';END IF;
 FOR item IN SELECT * FROM (VALUES
  ('collect_ops.record_jobs_readiness(jsonb)','64fd5a1cc2c3a96a86f8819f100c0d828238b3098389ee7cfee898753f02b8fd',false,'{postgres=X/postgres}'),
  ('collect_ops.configure_native_provider_budget(text,text,text,timestamp with time zone)','5cb722b0d11c52d626fe1462dbec4bbd17c9288640357ed5ccb201287b71f7b2',false,'{postgres=X/postgres}'),
  ('private.collect_native_provider_reserve(uuid,text,text,text)','7bf0e8e2412617ff3887f0998aeadc5657946a9807a1c5a93835838822889e59',true,'{postgres=X/postgres,collect_runtime=X/postgres}')
 ) AS x(signature,digest,security_definer,acl) LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(item.signature);
  IF NOT FOUND OR pg_get_userbyid(p.proowner)<>'postgres' OR p.prosecdef IS DISTINCT FROM item.security_definer OR p.proacl::text IS DISTINCT FROM item.acl
   OR encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') IS DISTINCT FROM item.digest THEN
   RAISE EXCEPTION 'native_provider_policy_preimage_changed: %',item.signature;END IF;
 END LOOP;
END
$provider_policy_preflight$;
ALTER TABLE collect_ops.jobs_config
 DROP CONSTRAINT jobs_config_native_provider_limit_check,
 DROP CONSTRAINT jobs_config_native_provider_used_check,
 DROP CONSTRAINT native_provider_budget_binding,
 ALTER COLUMN native_provider_limit DROP NOT NULL,
 ALTER COLUMN native_provider_limit DROP DEFAULT,
 ALTER COLUMN native_provider_limit TYPE bigint,
 ALTER COLUMN native_provider_used TYPE bigint;
 UPDATE collect_ops.jobs_config SET native_provider_limit=NULL,native_provider_expires_at=NULL WHERE singleton;
 ALTER TABLE collect_ops.jobs_config
 ADD CONSTRAINT native_provider_budget_bounds CHECK(native_provider_used BETWEEN 0 AND 9007199254740991
  AND (native_provider_limit IS NULL OR (native_provider_limit>=native_provider_used AND native_provider_limit<=9007199254740991))),
 ADD CONSTRAINT native_provider_budget_binding CHECK(
  (native_provider_source_sha256 IS NULL AND native_provider_model_id IS NULL AND native_provider_approval_sha256 IS NULL AND native_provider_expires_at IS NULL AND native_provider_used=0)
  OR (native_provider_source_sha256 IS NOT NULL AND native_provider_source_sha256 ~ '^[a-f0-9]{64}$'
   AND native_provider_model_id IS NOT NULL AND native_provider_model_id ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'
   AND native_provider_approval_sha256 IS NOT NULL AND native_provider_approval_sha256 ~ '^[a-f0-9]{64}$'));
CREATE OR REPLACE FUNCTION collect_ops.configure_native_provider_budget(p_source text,p_model text,p_approval text,p_expires timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $budget_setup$
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 PERFORM private._collect_fence_require_operator();
 IF NOT coalesce(p_source ~ '^[a-f0-9]{64}$',false) OR p_source IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256'
  OR NOT coalesce(p_model ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$',false) OR NOT coalesce(p_approval ~ '^[a-f0-9]{64}$',false)
  OR (p_expires IS NOT NULL AND p_expires<=clock_timestamp())
 THEN RAISE EXCEPTION 'native_provider_budget_setup_invalid';END IF;
 UPDATE collect_ops.jobs_config SET native_provider_source_sha256=p_source,native_provider_model_id=p_model,
  native_provider_approval_sha256=p_approval,native_provider_expires_at=p_expires
  WHERE singleton AND NOT enabled AND native_provider_source_sha256 IS NULL AND native_provider_used=0;
 IF NOT FOUND THEN RAISE EXCEPTION 'native_provider_budget_already_configured_or_active';END IF;
END
$budget_setup$;
CREATE OR REPLACE FUNCTION private.collect_native_provider_reserve(p_dispatch uuid,p_source text,p_model text,p_approval text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $budget_reserve$
DECLARE aid uuid;ep bigint;src text;c collect_ops.jobs_config%ROWTYPE;t private.collect_managed_job_tickets%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 aid:=NULLIF(current_setting('collect.fence_admission_id',true),'')::uuid;
 ep:=NULLIF(current_setting('collect.fence_epoch',true),'')::bigint;
 src:=NULLIF(current_setting('collect.fence_source_sha256',true),'');
 IF aid IS NULL OR ep IS NULL OR src IS NULL OR p_dispatch IS NULL OR p_source IS DISTINCT FROM src THEN RETURN false;END IF;
 PERFORM private.collect_fence_assert_write(aid,ep,src);
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE a.admission_id=aid AND a.epoch=ep AND a.source_sha256=src AND a.kind='jobs' AND a.state='active') THEN RETURN false;END IF;
 -- Same lock order as scheduler reconciliation. The lifetime row is never
 -- pruned or reset when a ticket expires, completes, or is deleted.
 SELECT * INTO c FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 IF NOT FOUND OR c.native_provider_source_sha256 IS DISTINCT FROM src OR c.native_provider_model_id IS DISTINCT FROM p_model
  OR c.native_provider_approval_sha256 IS DISTINCT FROM p_approval
  OR (c.native_provider_expires_at IS NOT NULL AND c.native_provider_expires_at<=clock_timestamp())
  OR (c.native_provider_limit IS NOT NULL AND c.native_provider_used>=c.native_provider_limit) THEN RETURN false;END IF;
 SELECT * INTO t FROM private.collect_managed_job_tickets WHERE dispatch_id=p_dispatch FOR UPDATE;
 IF NOT FOUND OR t.source_sha256 IS DISTINCT FROM src OR t.admission_id IS DISTINCT FROM aid OR t.claimed_at IS NULL
  OR t.completed_at IS NOT NULL OR t.expires_at<=clock_timestamp() OR t.native_provider_calls>=2
  OR t.payload->'native_sms_admission' IS DISTINCT FROM jsonb_build_object('contract','collect.native-sms-automation.v1','source_sha256',src,'approval_sha256',p_approval,'model_id',p_model,'batch_limit',1)
  OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches d WHERE d.id=p_dispatch AND d.state='awaiting' AND d.net_request_id IS NOT NULL) THEN RETURN false;END IF;
 UPDATE collect_ops.jobs_config SET native_provider_used=native_provider_used+1
  WHERE singleton AND native_provider_used<9007199254740991
   AND (native_provider_expires_at IS NULL OR native_provider_expires_at>clock_timestamp())
   AND (native_provider_limit IS NULL OR native_provider_used<native_provider_limit);
 IF NOT FOUND THEN RETURN false;END IF;
 UPDATE private.collect_managed_job_tickets SET native_provider_calls=native_provider_calls+1 WHERE dispatch_id=p_dispatch;
 RETURN true;
END
$budget_reserve$;
CREATE OR REPLACE FUNCTION collect_ops.record_jobs_readiness(p_readiness jsonb) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE k text;processing boolean;notifications boolean;native_sms boolean;expected_keys text[];admission jsonb;
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 IF p_readiness IS NULL OR jsonb_typeof(p_readiness) IS DISTINCT FROM 'object' OR p_readiness->>'verified_at' IS NULL OR p_readiness->>'format' NOT IN('collect.jobs.readiness.v1','collect.jobs.readiness.v2','collect.jobs.readiness.v3') OR p_readiness->>'format' IS NULL OR p_readiness->>'project_ref' IS DISTINCT FROM 'rrlduytparvsjfmegalh' OR p_readiness->>'endpoint' IS DISTINCT FROM 'https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-jobs' THEN RAISE EXCEPTION 'reviewed_job_readiness_required';END IF;
 native_sms:=p_readiness?'native_sms_admission';
 notifications:=p_readiness->>'format'='collect.jobs.readiness.v3';
 processing:=p_readiness->>'format'='collect.jobs.readiness.v2' OR(notifications AND p_readiness->>'mode'='receipt_and_push_v1');
 IF notifications AND(p_readiness->>'mode' IS NULL OR p_readiness->>'mode' NOT IN('notification_delivery_v1','receipt_and_push_v1')) THEN RAISE EXCEPTION 'reviewed_notification_mode_required';END IF;
 expected_keys:=ARRAY['format','project_ref','endpoint','deployment_sha256','runtime_evidence_sha256','token_custody_evidence_sha256','copy_inventory_evidence_sha256','quota_evidence_sha256','verified_at','momo_processing_paused','remaining_invocations','evidence_file_sha256'];
 IF native_sms THEN expected_keys:=expected_keys||ARRAY['native_sms_admission','native_provider_evidence_sha256','native_guard_evidence_sha256','remaining_native_provider_requests'];END IF;
 IF processing OR notifications THEN expected_keys:=expected_keys||ARRAY['mode'];END IF;
 IF processing THEN expected_keys:=expected_keys||ARRAY['processing_admission','provider_evidence_sha256','remaining_provider_requests'];END IF;
 IF notifications THEN expected_keys:=expected_keys||ARRAY['notification_admission','notification_provider_evidence_sha256','remaining_notification_attempts','remaining_notification_provider_requests'];END IF;
 IF (SELECT count(*) FROM jsonb_object_keys(p_readiness))<>cardinality(expected_keys) OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_readiness) key WHERE NOT key=ANY(expected_keys)) THEN RAISE EXCEPTION 'strict_evidence_fields_required';END IF;
 IF p_readiness->'momo_processing_paused' IS DISTINCT FROM to_jsonb(NOT processing) THEN RAISE EXCEPTION 'reviewed_job_readiness_required';END IF;
 FOREACH k IN ARRAY (ARRAY['deployment_sha256','runtime_evidence_sha256','token_custody_evidence_sha256','copy_inventory_evidence_sha256','quota_evidence_sha256','evidence_file_sha256']||CASE WHEN processing THEN ARRAY['provider_evidence_sha256'] ELSE ARRAY[]::text[] END||CASE WHEN notifications THEN ARRAY['notification_provider_evidence_sha256'] ELSE ARRAY[]::text[] END||CASE WHEN native_sms THEN ARRAY['native_provider_evidence_sha256','native_guard_evidence_sha256'] ELSE ARRAY[]::text[] END) LOOP
  IF jsonb_typeof(p_readiness->k) IS DISTINCT FROM 'string' OR NOT coalesce(p_readiness->>k ~ '^[a-f0-9]{64}$',false) THEN RAISE EXCEPTION 'readiness_evidence_digest_required';END IF;
 END LOOP;
 IF (p_readiness->>'verified_at')::timestamptz<clock_timestamp()-interval '1 hour' OR (p_readiness->>'verified_at')::timestamptz>clock_timestamp()+interval '30 seconds' OR jsonb_typeof(p_readiness->'remaining_invocations') IS DISTINCT FROM 'number' OR NOT coalesce(p_readiness->>'remaining_invocations' ~ '^[0-9]{1,9}$',false) OR (p_readiness->>'remaining_invocations')::bigint<50000 THEN RAISE EXCEPTION 'fresh_runtime_and_quota_review_required';END IF;
 IF native_sms THEN
  admission:=p_readiness->'native_sms_admission';
  IF jsonb_typeof(admission) IS DISTINCT FROM 'object'
   OR (SELECT count(*) FROM jsonb_object_keys(admission))<>5 OR EXISTS(SELECT 1 FROM jsonb_object_keys(admission) key WHERE key NOT IN('contract','source_sha256','approval_sha256','model_id','batch_limit'))
   OR admission->>'contract' IS DISTINCT FROM 'collect.native-sms-automation.v1' OR admission->'batch_limit' IS DISTINCT FROM '1'::jsonb
   OR NOT coalesce(admission->>'source_sha256' ~ '^[a-f0-9]{64}$',false) OR admission->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256'
   OR NOT coalesce(admission->>'approval_sha256' ~ '^[a-f0-9]{64}$',false) OR NOT coalesce(admission->>'model_id' ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$',false)
   OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_config c WHERE c.singleton
    AND c.native_provider_source_sha256=admission->>'source_sha256' AND c.native_provider_model_id=admission->>'model_id'
    AND c.native_provider_approval_sha256=admission->>'approval_sha256'
    AND (c.native_provider_expires_at IS NULL OR c.native_provider_expires_at>clock_timestamp())
    AND CASE WHEN c.native_provider_limit IS NULL THEN p_readiness->'remaining_native_provider_requests'='null'::jsonb
     WHEN jsonb_typeof(p_readiness->'remaining_native_provider_requests')='number'
      AND coalesce(p_readiness->>'remaining_native_provider_requests' ~ '^[0-9]{1,16}$',false)
     THEN (p_readiness->>'remaining_native_provider_requests')::bigint BETWEEN 2 AND c.native_provider_limit-c.native_provider_used
     ELSE false END)
  THEN RAISE EXCEPTION 'reviewed_native_source_model_guard_and_quota_required';END IF;
 END IF;
 IF processing THEN
  admission:=p_readiness->'processing_admission';
  IF p_readiness->>'mode' IS DISTINCT FROM (CASE WHEN notifications THEN 'receipt_and_push_v1' ELSE 'receipt_processing_v1' END) OR jsonb_typeof(admission) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'reviewed_processing_admission_required';END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(admission))<>5 OR EXISTS(SELECT 1 FROM jsonb_object_keys(admission) key WHERE key NOT IN('contract','source_sha256','approval_sha256','model_id','batch_limit'))
   OR admission->>'contract' IS DISTINCT FROM 'collect.receipt-processing.v1' OR admission->'batch_limit' IS DISTINCT FROM '1'::jsonb
   OR jsonb_typeof(admission->'source_sha256') IS DISTINCT FROM 'string' OR NOT coalesce(admission->>'source_sha256' ~ '^[a-f0-9]{64}$',false)
   OR jsonb_typeof(admission->'approval_sha256') IS DISTINCT FROM 'string' OR NOT coalesce(admission->>'approval_sha256' ~ '^[a-f0-9]{64}$',false)
   OR jsonb_typeof(admission->'model_id') IS DISTINCT FROM 'string' OR NOT coalesce(admission->>'model_id' ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$',false)
   OR admission->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256'
   OR jsonb_typeof(p_readiness->'remaining_provider_requests') IS DISTINCT FROM 'number' OR NOT coalesce(p_readiness->>'remaining_provider_requests' ~ '^[0-9]{1,9}$',false) OR (p_readiness->>'remaining_provider_requests')::bigint<10000
  THEN RAISE EXCEPTION 'reviewed_processing_source_model_approval_and_quota_required';END IF;
 END IF;
 IF notifications THEN
  admission:=p_readiness->'notification_admission';
  IF jsonb_typeof(admission) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'reviewed_notification_admission_required';END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(admission))<>7 OR EXISTS(SELECT 1 FROM jsonb_object_keys(admission) key WHERE key NOT IN('contract','source_sha256','approval_sha256','project_id','android_package','admitted_from','batch_limit'))
   OR admission->>'contract' IS DISTINCT FROM 'collect.android-push.v1' OR admission->'batch_limit' IS DISTINCT FROM '1'::jsonb
   OR jsonb_typeof(admission->'source_sha256') IS DISTINCT FROM 'string' OR NOT coalesce(admission->>'source_sha256' ~ '^[a-f0-9]{64}$',false)
   OR jsonb_typeof(admission->'approval_sha256') IS DISTINCT FROM 'string' OR NOT coalesce(admission->>'approval_sha256' ~ '^[a-f0-9]{64}$',false)
   OR admission->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256'
   OR jsonb_typeof(admission->'project_id') IS DISTINCT FROM 'string' OR NOT coalesce(admission->>'project_id' ~ '^[a-z][a-z0-9-]{4,28}[a-z0-9]$',false)
   OR admission->>'android_package' IS NULL OR admission->>'android_package' NOT IN('app.cool.mobile','app.cool.mobile.dev')
   OR jsonb_typeof(admission->'admitted_from') IS DISTINCT FROM 'number' OR NOT coalesce(admission->>'admitted_from' ~ '^[1-9][0-9]{0,9}$',false) OR(admission->>'admitted_from')::bigint>=4102444800
   OR jsonb_typeof(p_readiness->'remaining_notification_attempts') IS DISTINCT FROM 'number' OR NOT coalesce(p_readiness->>'remaining_notification_attempts' ~ '^[0-9]{1,9}$',false) OR(p_readiness->>'remaining_notification_attempts')::bigint<10000
   OR jsonb_typeof(p_readiness->'remaining_notification_provider_requests') IS DISTINCT FROM 'number' OR NOT coalesce(p_readiness->>'remaining_notification_provider_requests' ~ '^[0-9]{1,9}$',false) OR(p_readiness->>'remaining_notification_provider_requests')::bigint<20000
  THEN RAISE EXCEPTION 'reviewed_notification_source_project_approval_and_quota_required';END IF;
 END IF;
 PERFORM collect_ops.pause_jobs();
 UPDATE collect_ops.jobs_config SET readiness=p_readiness,last_probe_id=CASE WHEN readiness IS NOT DISTINCT FROM p_readiness THEN last_probe_id ELSE NULL END WHERE singleton;
END$$;
COMMIT;
