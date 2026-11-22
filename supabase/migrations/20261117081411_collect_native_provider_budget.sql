BEGIN;
DO $native_budget_scheduler_preimage$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('private._collect_fence_scheduler_status()')
  AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='5dc44f65fb52562bc6a0391a7f7b7d050c333c2276f98097943d9c1e340d926d'
  AND p.prosecdef AND p.proowner='postgres'::regrole AND p.prokind='f' AND p.prorettype='jsonb'::regtype
  AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND p.proacl::text='{postgres=X/postgres}')
 THEN RAISE EXCEPTION 'native_budget_scheduler_inventory_preimage_changed';END IF;
END
$native_budget_scheduler_preimage$;
-- Forward-only addition. No reset, runtime setter, replacement of imported
-- history guards, or table/trigger privilege relaxation is provided.
ALTER TABLE collect_ops.jobs_config
 ADD COLUMN native_provider_source_sha256 text,
 ADD COLUMN native_provider_model_id text,
 ADD COLUMN native_provider_approval_sha256 text,
 ADD COLUMN native_provider_expires_at timestamptz,
 ADD COLUMN native_provider_limit integer NOT NULL DEFAULT 400 CHECK(native_provider_limit=400),
 ADD COLUMN native_provider_used integer NOT NULL DEFAULT 0 CHECK(native_provider_used BETWEEN 0 AND 400),
 ADD CONSTRAINT native_provider_budget_binding CHECK(
  (native_provider_source_sha256 IS NULL AND native_provider_model_id IS NULL AND native_provider_approval_sha256 IS NULL AND native_provider_expires_at IS NULL AND native_provider_used=0)
  OR (native_provider_source_sha256 ~ '^[a-f0-9]{64}$' AND native_provider_model_id='gpt-5.4-mini-2026-03-17'
   AND native_provider_approval_sha256 ~ '^[a-f0-9]{64}$' AND native_provider_expires_at<='2026-11-30 23:59:59+00'::timestamptz
   AND native_provider_source_sha256 IS NOT NULL AND native_provider_model_id IS NOT NULL AND native_provider_approval_sha256 IS NOT NULL AND native_provider_expires_at IS NOT NULL));
ALTER TABLE private.collect_managed_job_tickets ADD COLUMN native_provider_calls integer NOT NULL DEFAULT 0 CHECK(native_provider_calls BETWEEN 0 AND 2);

CREATE FUNCTION collect_ops.configure_native_provider_budget(p_source text,p_model text,p_approval text,p_expires timestamptz)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $budget_setup$
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 PERFORM private._collect_fence_require_operator();
 IF NOT coalesce(p_source ~ '^[a-f0-9]{64}$',false) OR p_source IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256'
  OR p_model IS DISTINCT FROM 'gpt-5.4-mini-2026-03-17' OR NOT coalesce(p_approval ~ '^[a-f0-9]{64}$',false)
  OR p_expires IS NULL OR p_expires<=clock_timestamp() OR p_expires>'2026-11-30 23:59:59+00'::timestamptz
 THEN RAISE EXCEPTION 'native_provider_budget_setup_invalid';END IF;
 UPDATE collect_ops.jobs_config SET native_provider_source_sha256=p_source,native_provider_model_id=p_model,
  native_provider_approval_sha256=p_approval,native_provider_expires_at=p_expires
  WHERE singleton AND NOT enabled AND native_provider_source_sha256 IS NULL AND native_provider_used=0;
 IF NOT FOUND THEN RAISE EXCEPTION 'native_provider_budget_already_configured_or_active';END IF;
END
$budget_setup$;
REVOKE ALL ON FUNCTION collect_ops.configure_native_provider_budget(text,text,text,timestamptz) FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;

CREATE FUNCTION private.collect_native_provider_reserve(p_dispatch uuid,p_source text,p_model text,p_approval text)
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
  OR c.native_provider_approval_sha256 IS DISTINCT FROM p_approval OR c.native_provider_expires_at IS NULL
  OR c.native_provider_expires_at<=clock_timestamp() OR c.native_provider_used>=c.native_provider_limit THEN RETURN false;END IF;
 SELECT * INTO t FROM private.collect_managed_job_tickets WHERE dispatch_id=p_dispatch FOR UPDATE;
 IF NOT FOUND OR t.source_sha256 IS DISTINCT FROM src OR t.admission_id IS DISTINCT FROM aid OR t.claimed_at IS NULL
  OR t.completed_at IS NOT NULL OR t.expires_at<=clock_timestamp() OR t.native_provider_calls>=2
  OR t.payload->'native_sms_admission' IS DISTINCT FROM jsonb_build_object('contract','collect.native-sms-automation.v1','source_sha256',src,'approval_sha256',p_approval,'model_id',p_model,'batch_limit',1)
  OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches d WHERE d.id=p_dispatch AND d.state='awaiting' AND d.net_request_id IS NOT NULL) THEN RETURN false;END IF;
 UPDATE collect_ops.jobs_config SET native_provider_used=native_provider_used+1
  WHERE singleton AND native_provider_expires_at>clock_timestamp() AND native_provider_used<native_provider_limit;
 IF NOT FOUND THEN RETURN false;END IF;
 UPDATE private.collect_managed_job_tickets SET native_provider_calls=native_provider_calls+1 WHERE dispatch_id=p_dispatch;
 RETURN true;
END
$budget_reserve$;
REVOKE ALL ON FUNCTION private.collect_native_provider_reserve(uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.collect_native_provider_reserve(uuid,text,text,text) TO collect_runtime;

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
 IF (p_readiness->>'verified_at')::timestamptz<clock_timestamp()-interval '1 hour' OR (p_readiness->>'verified_at')::timestamptz>clock_timestamp()+interval '30 seconds' OR jsonb_typeof(p_readiness->'remaining_invocations') IS DISTINCT FROM 'number' OR NOT coalesce(p_readiness->>'remaining_invocations' ~ '^[0-9]{1,9}$',false) OR (p_readiness->>'remaining_invocations')::bigint<10000 THEN RAISE EXCEPTION 'fresh_runtime_and_quota_review_required';END IF;
 IF native_sms THEN
  admission:=p_readiness->'native_sms_admission';
  IF jsonb_typeof(admission) IS DISTINCT FROM 'object'
   OR (SELECT count(*) FROM jsonb_object_keys(admission))<>5 OR EXISTS(SELECT 1 FROM jsonb_object_keys(admission) key WHERE key NOT IN('contract','source_sha256','approval_sha256','model_id','batch_limit'))
   OR admission->>'contract' IS DISTINCT FROM 'collect.native-sms-automation.v1' OR admission->'batch_limit' IS DISTINCT FROM '1'::jsonb
   OR NOT coalesce(admission->>'source_sha256' ~ '^[a-f0-9]{64}$',false) OR admission->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256'
   OR NOT coalesce(admission->>'approval_sha256' ~ '^[a-f0-9]{64}$',false) OR NOT coalesce(admission->>'model_id' ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$',false)
   OR jsonb_typeof(p_readiness->'remaining_native_provider_requests') IS DISTINCT FROM 'number'
   OR NOT coalesce(p_readiness->>'remaining_native_provider_requests' ~ '^[0-9]{1,9}$',false) OR (p_readiness->>'remaining_native_provider_requests')::bigint<2
   OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_config c WHERE c.singleton
    AND c.native_provider_source_sha256=admission->>'source_sha256' AND c.native_provider_model_id=admission->>'model_id'
    AND c.native_provider_approval_sha256=admission->>'approval_sha256' AND c.native_provider_expires_at>clock_timestamp()
    AND c.native_provider_limit-c.native_provider_used>=2
    AND (p_readiness->>'remaining_native_provider_requests')::bigint<=c.native_provider_limit-c.native_provider_used)
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
CREATE OR REPLACE FUNCTION private._collect_fence_scheduler_status() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE active_jobs bigint:=0;queued bigint:=0;awaiting bigint:=0;unconfirmed bigint:=0;reviewed bigint:=0;unproven bigint:=0;
 missing_guards bigint:=0;guard_count bigint:=0;unexpected_functions bigint:=0;ops_exists boolean:=to_regnamespace('collect_ops') IS NOT NULL;has_config boolean:=to_regclass('collect_ops.jobs_config') IS NOT NULL;
 has_dispatch boolean:=to_regclass('collect_ops.jobs_dispatches') IS NOT NULL;coverage boolean:=true;
BEGIN
 -- Read counts only. Never select Vault/queue header/body/response content.
 IF to_regclass('cron.job') IS NOT NULL THEN
  EXECUTE $q$SELECT count(*) FROM cron.job WHERE jobname IN('collect-jobs-maintenance-v1','collect-google-ciphertext-expiry-v1') AND active$q$ INTO active_jobs;
 END IF;
 IF to_regclass('net.http_request_queue') IS NOT NULL THEN EXECUTE 'SELECT count(*) FROM net.http_request_queue' INTO queued;END IF;
 IF has_config IS DISTINCT FROM has_dispatch THEN coverage:=false;END IF;
 IF has_dispatch THEN
  EXECUTE $q$SELECT count(*) FILTER(WHERE state='awaiting'),count(*) FILTER(WHERE state='unconfirmed'),count(*) FILTER(WHERE state='reviewed_unknown'),
   count(*) FILTER(WHERE state IN('awaiting','unconfirmed','reviewed_unknown') AND NOT EXISTS(
    SELECT 1 FROM private.collect_fence_scheduler_lifecycle p WHERE p.dispatch_id=d.id AND p.native_epoch=d.native_epoch))
   FROM collect_ops.jobs_dispatches d$q$ INTO awaiting,unconfirmed,reviewed,unproven;
 END IF;
 SELECT count(*),count(*) FILTER(WHERE strpos(p.prosrc,E'BEGIN\n -- collect_fence_sql2_write_guard_v1\n PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);')=0
   OR p.prosecdef OR pg_get_userbyid(p.proowner)<>(SELECT pg_get_userbyid(c.relowner) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private' AND c.relname='collect_fence_control'))
 INTO guard_count,missing_guards FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='collect_ops' AND (p.proname,p.proargtypes::text) IN(('cleanup_google_expired',''),('record_jobs_readiness','3802'),('reconcile_jobs',''),('dispatch_jobs','25 2950'),('activate_jobs','25'),('review_unknown_jobs','2950 25'),('tick_jobs',''),('configure_native_provider_budget','25 25 25 1184'));
 SELECT count(*) INTO unexpected_functions FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='collect_ops' AND (p.prokind<>'f' OR
  (p.proname,p.proargtypes::text) NOT IN(('cleanup_google_expired',''),('record_jobs_readiness','3802'),('reconcile_jobs',''),('dispatch_jobs','25 2950'),('activate_jobs','25'),('review_unknown_jobs','2950 25'),('tick_jobs',''),('configure_native_provider_budget','25 25 25 1184'),('native_jobs_epoch',''),('jobs_state',''),('pause_jobs',''))
  OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE a.grantee=0 AND a.privilege_type='EXECUTE')
  OR EXISTS(SELECT 1 FROM pg_roles r WHERE r.rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer') AND has_function_privilege(r.oid,p.oid,'EXECUTE')));
 IF ops_exists AND guard_count=0 THEN coverage:=false;END IF;
 IF has_dispatch AND guard_count NOT IN(7,8) THEN coverage:=false;END IF;
 IF NOT has_dispatch AND ops_exists AND guard_count<>1 THEN coverage:=false;END IF;
 coverage:=coverage AND missing_guards=0 AND unexpected_functions=0;
 RETURN jsonb_build_object('checked',true,'coverageVerified',coverage,'namedActiveJobs',active_jobs,'pendingNativeRequests',queued,
  'awaitingDispatches',awaiting,'unconfirmedDispatches',unconfirmed,'reviewedUnknownDispatches',reviewed,'lifecycleUnproven',unproven,
  'blocking',NOT coverage OR active_jobs>0 OR queued>0 OR unproven>0);
EXCEPTION WHEN OTHERS THEN
 -- Counts are unobserved sentinels when checked=false, never evidence of absence.
 -- Returning this blocker rather than raising lets begin_quiesce COMMIT its
 -- admission closure even when a separate scheduler observation is unavailable.
 RETURN jsonb_build_object('checked',false,'coverageVerified',false,'namedActiveJobs',0,'pendingNativeRequests',0,
  'awaitingDispatches',0,'unconfirmedDispatches',0,'reviewedUnknownDispatches',0,'lifecycleUnproven',0,'blocking',true);
END;$fn$;
COMMIT;
