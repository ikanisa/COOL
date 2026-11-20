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
