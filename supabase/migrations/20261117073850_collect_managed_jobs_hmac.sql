-- OPERATOR ARTIFACT, NOT AN APPLICATION MIGRATION. No extension/secret creation.
-- Render only through jobs_config.mjs; install transaction leaves Cron INACTIVE.
BEGIN;
DO $existing$ BEGIN
  IF to_regnamespace('collect_ops') IS NULL OR (SELECT nspowner::regrole::text FROM pg_namespace WHERE nspname='collect_ops')<>'postgres'
   OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='collect_ops')<>0
   OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='collect_ops')<>1
   OR NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('collect_ops.cleanup_google_expired()') AND p.proowner::regrole::text='postgres'
    AND encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex')='f70925051147096cfb72869b401fdb69c976b68034c87e8c3e98ee8b5f350ed0'
    AND p.proacl::text='{postgres=X/postgres}') THEN RAISE EXCEPTION 'unexpected_existing_collect_ops';END IF;
 END $existing$;
REVOKE ALL ON SCHEMA collect_ops FROM PUBLIC;
CREATE TABLE collect_ops.jobs_config(
 singleton boolean PRIMARY KEY CHECK(singleton),
 project_ref text NOT NULL CHECK(project_ref='rrlduytparvsjfmegalh'),
 endpoint text NOT NULL CHECK(endpoint='https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-jobs'),
 vault_name text NOT NULL CHECK(vault_name='collect_job_signing_key_v1'),
 config_sha256 text NOT NULL CHECK(config_sha256='9851fdcc5950910547706199c1bc3234ed09ac599237ac21af063fb19a395d3c'),
 template_sha256 text NOT NULL CHECK(template_sha256='cfd56f3f3d6d0a69f7a4909f3b2d482b600d2e681ba02734e15c838e1212d384'),
 enabled boolean NOT NULL DEFAULT false,cron_job_id bigint,
 readiness jsonb,last_probe_id uuid,created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- Numeric pg_net request IDs belong to this native transport instance. The
-- logged journal survives a crash; the unlogged queue, replies and its owned
-- sequence need not. Object OIDs additionally fence extension recreation.
CREATE FUNCTION collect_ops.native_jobs_epoch() RETURNS text LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE queue_oid regclass:=to_regclass('net.http_request_queue');response_oid regclass:=to_regclass('net._http_response');sequence_oid regclass;
BEGIN
 IF queue_oid IS NULL OR response_oid IS NULL THEN RETURN NULL;END IF;
 sequence_oid:=to_regclass(pg_get_serial_sequence('net.http_request_queue','id'));
 IF sequence_oid IS NULL THEN RETURN NULL;END IF;
 RETURN encode(sha256(convert_to(jsonb_build_object('postmaster_epoch',extract(epoch FROM pg_postmaster_start_time())::text,'queue_oid',queue_oid::oid,'response_oid',response_oid::oid,'sequence_oid',sequence_oid::oid)::text,'UTF8')),'hex');
END$$;
CREATE TABLE collect_ops.jobs_dispatches(
 id uuid PRIMARY KEY,kind text NOT NULL CHECK(kind IN('probe','scheduled')),
 slot timestamptz UNIQUE,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 native_epoch text NOT NULL DEFAULT collect_ops.native_jobs_epoch() CHECK(native_epoch ~ '^[a-f0-9]{64}$'),
 net_request_id bigint,readiness_sha256 text,vault_secret_id uuid,vault_updated_at timestamptz,
 runtime_contract jsonb CHECK(runtime_contract IS NULL OR jsonb_typeof(runtime_contract)='object'),
 notification_contract jsonb CHECK(notification_contract IS NULL OR jsonb_typeof(notification_contract)='object'),
 native_contract jsonb CHECK(native_contract IS NULL OR jsonb_typeof(native_contract)='object'),
 state text NOT NULL CHECK(state IN('awaiting','confirmed','unconfirmed','reviewed_unknown','rejected')),
 reason text NOT NULL DEFAULT 'awaiting_reply',http_status integer,maintenance_purged integer,
 response_sha256 text,observed_at timestamptz,resolution_evidence_sha256 text,
 UNIQUE(native_epoch,net_request_id),
 CHECK((kind='scheduled' AND slot IS NOT NULL) OR(kind='probe' AND slot IS NULL)),
 CHECK(maintenance_purged IS NULL OR maintenance_purged BETWEEN 0 AND 100),
 CHECK(response_sha256 IS NULL OR response_sha256 ~ '^[a-f0-9]{64}$'),
 CHECK(resolution_evidence_sha256 IS NULL OR resolution_evidence_sha256 ~ '^[a-f0-9]{64}$')
);
-- Isolated candidate: install inside the same transaction as the reviewed,
-- initially disabled scheduler. Must be owned by the non-superuser postgres
-- operator; never grant ticket mutation to the Edge runtime. Values in the
-- pg_net queue are short-lived per-dispatch MACs, not reusable credentials.
CREATE TABLE private.collect_managed_job_tickets(
 dispatch_id uuid PRIMARY KEY REFERENCES collect_ops.jobs_dispatches(id) ON DELETE CASCADE,
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 payload jsonb NOT NULL CHECK(jsonb_typeof(payload) IS NOT DISTINCT FROM 'object' AND jsonb_typeof(payload->'dispatch_id') IS NOT DISTINCT FROM 'string'
  AND payload->>'dispatch_id' IS NOT DISTINCT FROM dispatch_id::text AND jsonb_typeof(payload->'dispatch_expires_at') IS NOT DISTINCT FROM 'number'),
 created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
 expires_at timestamptz NOT NULL,
 claimed_at timestamptz,
 admission_id uuid,
 completed_at timestamptz,
 response_sha256 text CHECK(response_sha256 IS NULL OR response_sha256 ~ '^[a-f0-9]{64}$'),
 CHECK(expires_at>created_at AND expires_at<=created_at+interval '3 minutes'),
 CHECK((claimed_at IS NULL)=(admission_id IS NULL)),
 CHECK((completed_at IS NULL)=(response_sha256 IS NULL)),
 CHECK(completed_at IS NULL OR (claimed_at IS NOT NULL AND completed_at>=claimed_at))
);
ALTER TABLE private.collect_managed_job_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_managed_job_tickets FORCE ROW LEVEL SECURITY;
CREATE POLICY collect_managed_job_tickets_owner ON private.collect_managed_job_tickets TO postgres USING(true) WITH CHECK(true);
REVOKE ALL ON private.collect_managed_job_tickets FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.collect_managed_job_tickets
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.collect_managed_job_tickets ENABLE ALWAYS TRIGGER collect_fence_statement_v1;

CREATE FUNCTION private.collect_managed_job_claim(p_dispatch uuid,p_source text,p_payload jsonb,p_signature text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $claim$
DECLARE v_admission uuid;v_epoch bigint;v_source text;v_key text;v_expected text;v_claimed uuid;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 v_admission:=NULLIF(current_setting('collect.fence_admission_id',true),'')::uuid;
 v_epoch:=NULLIF(current_setting('collect.fence_epoch',true),'')::bigint;
 v_source:=NULLIF(current_setting('collect.fence_source_sha256',true),'');
 IF v_admission IS NULL OR v_epoch IS NULL OR v_source IS NULL OR p_dispatch IS NULL
  OR p_source IS DISTINCT FROM v_source OR NOT coalesce(p_source ~ '^[a-f0-9]{64}$',false)
  OR NOT coalesce(p_signature ~ '^[a-f0-9]{64}$',false)
  OR jsonb_typeof(p_payload) IS DISTINCT FROM 'object' OR p_payload->>'dispatch_id' IS DISTINCT FROM p_dispatch::text
 THEN RETURN false;END IF;
 PERFORM private.collect_fence_assert_write(v_admission,v_epoch,v_source);
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE a.admission_id=v_admission
  AND a.epoch=v_epoch AND a.source_sha256=v_source AND a.kind='jobs' AND a.state='active') THEN RETURN false;END IF;
 IF (SELECT count(*) FROM vault.decrypted_secrets WHERE name='collect_job_signing_key_v1')<>1 THEN RETURN false;END IF;
 SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='collect_job_signing_key_v1';
 IF NOT coalesce(v_key ~ '^[a-f0-9]{64}$',false) THEN RETURN false;END IF;
 IF jsonb_typeof(p_payload->'dispatch_expires_at') IS DISTINCT FROM 'number' OR NOT coalesce(p_payload->>'dispatch_expires_at' ~ '^[1-9][0-9]{0,10}$',false) THEN RETURN false;END IF;
 v_expected:=encode(extensions.hmac(convert_to('collect.jobs.dispatch.v1'||E'\n'||'rrlduytparvsjfmegalh'||E'\n'||v_source||E'\n'||p_dispatch::text||E'\n'||(p_payload->>'dispatch_expires_at'),'UTF8'),convert_to(v_key,'UTF8'),'sha256'),'hex');
 IF p_signature IS DISTINCT FROM v_expected THEN RETURN false;END IF;
 UPDATE private.collect_managed_job_tickets t SET claimed_at=clock_timestamp(),admission_id=v_admission
  WHERE t.dispatch_id=p_dispatch AND t.source_sha256=v_source AND t.payload=p_payload AND t.claimed_at IS NULL
   AND t.created_at<=clock_timestamp() AND t.expires_at>clock_timestamp() AND t.expires_at=to_timestamp((p_payload->>'dispatch_expires_at')::bigint)
   AND EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches d WHERE d.id=t.dispatch_id AND d.state='awaiting' AND d.net_request_id IS NOT NULL)
  RETURNING t.dispatch_id INTO v_claimed;
 RETURN v_claimed IS NOT NULL;
END
$claim$;
REVOKE ALL ON FUNCTION private.collect_managed_job_claim(uuid,text,jsonb,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.collect_managed_job_claim(uuid,text,jsonb,text) TO collect_runtime;

-- pg_net response rows are writable by database roles. The scheduler may
-- confirm only the exact response whose digest was committed by the same
-- active jobs admission after all work completed successfully.
CREATE FUNCTION private.collect_managed_job_complete(p_dispatch uuid,p_source text,p_response_sha256 text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $complete$
DECLARE v_admission uuid;v_epoch bigint;v_source text;v_completed uuid;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 v_admission:=NULLIF(current_setting('collect.fence_admission_id',true),'')::uuid;
 v_epoch:=NULLIF(current_setting('collect.fence_epoch',true),'')::bigint;
 v_source:=NULLIF(current_setting('collect.fence_source_sha256',true),'');
 IF v_admission IS NULL OR v_epoch IS NULL OR v_source IS NULL OR p_dispatch IS NULL
  OR p_source IS DISTINCT FROM v_source OR NOT coalesce(p_source ~ '^[a-f0-9]{64}$',false)
  OR NOT coalesce(p_response_sha256 ~ '^[a-f0-9]{64}$',false) THEN RETURN false;END IF;
 PERFORM private.collect_fence_assert_write(v_admission,v_epoch,v_source);
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE a.admission_id=v_admission
  AND a.epoch=v_epoch AND a.source_sha256=v_source AND a.kind='jobs' AND a.state='active') THEN RETURN false;END IF;
 UPDATE private.collect_managed_job_tickets SET completed_at=clock_timestamp(),response_sha256=p_response_sha256
  WHERE dispatch_id=p_dispatch AND source_sha256=v_source AND admission_id=v_admission AND claimed_at IS NOT NULL AND completed_at IS NULL
  RETURNING dispatch_id INTO v_completed;
 RETURN v_completed IS NOT NULL;
END
$complete$;
REVOKE ALL ON FUNCTION private.collect_managed_job_complete(uuid,text,text) FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.collect_managed_job_complete(uuid,text,text) TO collect_runtime;

CREATE INDEX jobs_dispatches_pending ON collect_ops.jobs_dispatches(state,created_at);
ALTER TABLE collect_ops.jobs_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE collect_ops.jobs_dispatches ENABLE ROW LEVEL SECURITY;
INSERT INTO collect_ops.jobs_config(singleton,project_ref,endpoint,vault_name,config_sha256,template_sha256) VALUES(true,'rrlduytparvsjfmegalh','https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-jobs','collect_job_signing_key_v1','9851fdcc5950910547706199c1bc3234ed09ac599237ac21af063fb19a395d3c','cfd56f3f3d6d0a69f7a4909f3b2d482b600d2e681ba02734e15c838e1212d384');

CREATE FUNCTION collect_ops.jobs_state() RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('contract_version',1,'config_sha256',c.config_sha256,'template_sha256',c.template_sha256,'project_ref',c.project_ref,'endpoint',c.endpoint,'enabled',c.enabled,'cron_job_id',c.cron_job_id,
 'cron_active',(SELECT active FROM cron.job WHERE jobid=c.cron_job_id),'readiness_sha256',c.readiness->>'evidence_file_sha256','last_probe_id',c.last_probe_id,
 'mode',coalesce(c.readiness->>'mode','maintenance_only'),'processing_admission',c.readiness->'processing_admission','notification_admission',c.readiness->'notification_admission',
 'awaiting',(SELECT count(*) FROM collect_ops.jobs_dispatches WHERE state='awaiting'),
 'unconfirmed',(SELECT count(*) FROM collect_ops.jobs_dispatches WHERE state='unconfirmed'),'native_epoch',collect_ops.native_jobs_epoch(),
 'month_dispatches',(SELECT count(*) FROM collect_ops.jobs_dispatches WHERE created_at>=date_trunc('month',now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'))
 FROM collect_ops.jobs_config c WHERE singleton
$$;
CREATE FUNCTION collect_ops.pause_jobs() RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c collect_ops.jobs_config%ROWTYPE;
BEGIN
 SELECT * INTO c FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 UPDATE collect_ops.jobs_config SET enabled=false WHERE singleton;
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobid=c.cron_job_id AND jobname='collect-jobs-maintenance-v1') THEN PERFORM cron.alter_job(c.cron_job_id,active:=false);END IF;
 RETURN collect_ops.jobs_state();
END$$;
CREATE FUNCTION collect_ops.record_jobs_readiness(p_readiness jsonb) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
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
   OR NOT coalesce(p_readiness->>'remaining_native_provider_requests' ~ '^[0-9]{1,9}$',false) OR (p_readiness->>'remaining_native_provider_requests')::bigint<10000
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
CREATE FUNCTION collect_ops.reconcile_jobs() RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE d collect_ops.jobs_dispatches%ROWTYPE;r record;payload jsonb;v_reason text;observed integer:=0;uncertain integer:=0;purged integer;confirmed boolean;processing_ok boolean;notifications_ok boolean;native_ok boolean;native_epoch_now text;
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.rrlduytparvsjfmegalh',0));
 PERFORM 1 FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 native_epoch_now:=collect_ops.native_jobs_epoch();
 FOR d IN SELECT * FROM collect_ops.jobs_dispatches WHERE state='awaiting' ORDER BY created_at,id LIMIT 20 FOR UPDATE LOOP
  IF native_epoch_now IS NULL OR d.native_epoch IS DISTINCT FROM native_epoch_now THEN
   -- Never match a surviving durable request to a recycled native numeric ID.
   UPDATE collect_ops.jobs_dispatches SET state='unconfirmed',reason='native_transport_instance_changed',http_status=NULL,maintenance_purged=NULL,response_sha256=NULL,observed_at=clock_timestamp() WHERE id=d.id;
   observed:=observed+1;uncertain:=uncertain+1;PERFORM collect_ops.pause_jobs();CONTINUE;
  END IF;
  SELECT status_code,timed_out,error_msg IS NOT NULL AS failed,CASE WHEN octet_length(content)<=16384 THEN content ELSE NULL END AS content INTO r FROM net._http_response WHERE id=d.net_request_id ORDER BY created DESC LIMIT 1;
  IF NOT FOUND THEN
   IF d.created_at>clock_timestamp()-interval '180 seconds' THEN CONTINUE;END IF;
   v_reason:='reply_missing';confirmed:=false;purged:=NULL;
  ELSE
   confirmed:=false;processing_ok:=false;notifications_ok:=false;purged:=NULL;payload:=NULL;v_reason:='reply_unconfirmed';
   IF r.content IS NOT NULL THEN BEGIN payload:=r.content::jsonb;EXCEPTION WHEN OTHERS THEN payload:=NULL;END;END IF;
   IF payload->'maintenance'->>'purged' ~ '^(0|[1-9][0-9]{0,2})$' THEN purged:=(payload->'maintenance'->>'purged')::integer;END IF;
   IF d.runtime_contract IS NULL THEN
    processing_ok:=NOT coalesce(payload?'processing_admission',false) AND payload->'processing'->>'status' IS DISTINCT FROM 'unconfirmed' AND payload->'processing'->'paused'='true'::jsonb
     AND payload->'processing'->'processed'='0'::jsonb AND payload->'processing'->'results'='[]'::jsonb;
   ELSIF payload->'processing_admission'=d.runtime_contract AND payload->'processing'->>'status'='complete'
    AND payload->'processing'->'paused'='false'::jsonb AND payload->'processing'->'processed' IN('0'::jsonb,'1'::jsonb)
    AND jsonb_typeof(payload->'processing'->'results')='array' THEN
    processing_ok:=to_jsonb(jsonb_array_length(payload->'processing'->'results'))=payload->'processing'->'processed';
    IF processing_ok THEN
     processing_ok:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'processing'->'results') item
      WHERE jsonb_typeof(item) IS DISTINCT FROM 'object' OR item->>'state' IS NULL OR item->>'state' NOT IN('completed','needs_review','retry','not_claimed','superseded')
       OR item IS DISTINCT FROM jsonb_build_object('state',item->>'state'));
    END IF;
   END IF;
   IF d.notification_contract IS NULL THEN
    notifications_ok:=NOT coalesce(payload?'notification_admission',false) AND(NOT coalesce(payload?'notifications',false) OR(
     payload->'notifications'->>'status'='disabled' AND payload->'notifications'->'paused'='true'::jsonb
     AND payload->'notifications'->'processed'='0'::jsonb AND payload->'notifications'->'results'='[]'::jsonb AND payload->'notifications'->'recovered_unknown'='0'::jsonb));
   ELSIF payload->'notification_admission'=d.notification_contract AND payload->'notifications'->>'status'='complete'
    AND payload->'notifications'->'paused'='false'::jsonb AND payload->'notifications'->'processed' IN('0'::jsonb,'1'::jsonb)
    AND jsonb_typeof(payload->'notifications'->'results')='array' AND jsonb_typeof(payload->'notifications'->'recovered_unknown')='number'
    AND (CASE WHEN payload->'notifications'->>'recovered_unknown' ~ '^(0|[1-9][0-9]{0,2})$' THEN(payload->'notifications'->>'recovered_unknown')::integer ELSE 101 END) BETWEEN 0 AND 100 THEN
    notifications_ok:=to_jsonb(jsonb_array_length(payload->'notifications'->'results'))=payload->'notifications'->'processed';
    IF notifications_ok THEN
     notifications_ok:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'notifications'->'results') item
      WHERE jsonb_typeof(item) IS DISTINCT FROM 'object' OR item->>'state' IS NULL OR item->>'state' NOT IN('accepted','retry','rejected','suppressed','unknown')
       OR item IS DISTINCT FROM jsonb_build_object('state',item->>'state'));
    END IF;
   END IF;
   native_ok:=false;
   IF d.native_contract IS NULL THEN
    native_ok:=NOT coalesce(payload?'native_sms_admission',false) AND NOT coalesce(payload?'native_auto_processing',false) AND NOT coalesce(payload?'native_sms_ledger',false);
   ELSIF payload->'native_sms_admission'=d.native_contract AND payload->'native_auto_processing'->>'status'='complete'
    AND payload->'native_sms_ledger'->>'status'='complete' AND payload->'native_auto_processing'->'processed' IN('0'::jsonb,'1'::jsonb)
    AND payload->'native_sms_ledger'->'processed' IN('0'::jsonb,'1'::jsonb)
    AND jsonb_typeof(payload->'native_auto_processing'->'results')='array' AND jsonb_typeof(payload->'native_sms_ledger'->'results')='array' THEN
    native_ok:=to_jsonb(jsonb_array_length(payload->'native_auto_processing'->'results'))=payload->'native_auto_processing'->'processed'
     AND to_jsonb(jsonb_array_length(payload->'native_sms_ledger'->'results'))=payload->'native_sms_ledger'->'processed'
     AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'native_auto_processing'->'results') item WHERE
      ((item->>'state'='completed' AND item->>'relation' IN('accepted','duplicate','conflict') AND item=jsonb_build_object('state',item->>'state','relation',item->>'relation'))
       OR (item->>'state' IN('security_message','not_claimed','retry') AND item=jsonb_build_object('state',item->>'state'))) IS NOT TRUE)
     AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'native_sms_ledger'->'results') item WHERE
      (item->>'state' IN('posted','unmatched','already_posted','not_financial') AND item=jsonb_build_object('state',item->>'state')) IS NOT TRUE);
   END IF;
   IF r.status_code=200 AND NOT coalesce(r.timed_out,true) AND NOT r.failed AND jsonb_typeof(payload->'dispatch_id')='string' AND payload->>'dispatch_id'=d.id::text AND payload->'maintenance'->>'status'='complete'
    AND payload->'maintenance'->>'examined_limit'='100' AND payload->'maintenance'->>'provider_calls'='0'
    AND jsonb_typeof(payload->'maintenance'->'purged')='number' AND payload->'maintenance'->>'purged' ~ '^(0|[1-9][0-9]{0,2})$'
    AND purged BETWEEN 0 AND 100 AND coalesce(processing_ok,false) AND coalesce(notifications_ok,false) AND coalesce(native_ok,false)
    AND EXISTS(SELECT 1 FROM private.collect_managed_job_tickets t WHERE t.dispatch_id=d.id AND t.source_sha256=private.collect_fence_owner_status()->>'sourceSha256'
     AND t.completed_at IS NOT NULL AND t.response_sha256=encode(sha256(convert_to(r.content,'UTF8')),'hex')) THEN
    confirmed:=true;v_reason:='reply_confirmed';purged:=(payload->'maintenance'->>'purged')::integer;
   ELSIF r.status_code=200 AND (jsonb_typeof(payload->'dispatch_id') IS DISTINCT FROM 'string' OR payload->>'dispatch_id' IS DISTINCT FROM d.id::text) THEN v_reason:='dispatch_identity_mismatch';
   ELSIF r.status_code=200 AND d.runtime_contract IS NOT NULL AND payload->'processing_admission' IS DISTINCT FROM d.runtime_contract THEN v_reason:='processing_admission_mismatch';
   ELSIF r.status_code=200 AND d.notification_contract IS NOT NULL AND payload->'notification_admission' IS DISTINCT FROM d.notification_contract THEN v_reason:='notification_admission_mismatch';
   ELSIF r.status_code=200 AND(NOT coalesce(processing_ok,false) OR NOT coalesce(notifications_ok,false) OR NOT coalesce(native_ok,false)) THEN v_reason:='runtime_gate_changed';
   ELSIF r.status_code BETWEEN 400 AND 499 THEN v_reason:='http_rejected';END IF;
  END IF;
  UPDATE collect_ops.jobs_dispatches SET state=CASE WHEN confirmed THEN 'confirmed' ELSE 'unconfirmed' END,reason=v_reason,http_status=CASE WHEN r.status_code BETWEEN 100 AND 599 THEN r.status_code ELSE NULL END,maintenance_purged=CASE WHEN confirmed THEN purged ELSE NULL END,
   response_sha256=CASE WHEN r.content IS NOT NULL THEN encode(sha256(convert_to(r.content,'UTF8')),'hex') ELSE NULL END,observed_at=clock_timestamp() WHERE id=d.id;
  observed:=observed+1;
  IF NOT confirmed THEN uncertain:=uncertain+1;PERFORM collect_ops.pause_jobs();END IF;
 END LOOP;
 RETURN jsonb_build_object('observed',observed,'unconfirmed',uncertain);
END$$;

CREATE FUNCTION collect_ops.dispatch_jobs(p_kind text,p_dispatch_id uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c collect_ops.jobs_config%ROWTYPE;d collect_ops.jobs_dispatches%ROWTYPE;slot_at timestamptz;request_id bigint;credential text;secret_id uuid;secret_updated_at timestamptz;native_epoch_now text;selected_contract jsonb;selected_notification jsonb;selected_native jsonb;request_body jsonb;
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 IF p_kind NOT IN('probe','scheduled') OR p_dispatch_id IS NULL THEN RAISE EXCEPTION 'invalid_dispatch_identity';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.rrlduytparvsjfmegalh',0));
 SELECT * INTO d FROM collect_ops.jobs_dispatches WHERE id=p_dispatch_id;
 IF FOUND THEN RETURN jsonb_build_object('dispatch_id',d.id,'state',d.state,'net_request_id',d.net_request_id,'replayed',true);END IF;
 PERFORM collect_ops.reconcile_jobs();
 SELECT * INTO c FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 IF EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed')) THEN RETURN jsonb_build_object('state','blocked_pending_reconciliation');END IF;
 IF p_kind='scheduled' AND NOT c.enabled THEN RETURN jsonb_build_object('state','disabled');END IF;
 IF c.readiness IS NULL OR (p_kind='probe' AND ((c.readiness->>'verified_at')::timestamptz<clock_timestamp()-interval '1 hour' OR c.enabled)) THEN RAISE EXCEPTION 'fresh_disabled_probe_readiness_required';END IF;
 selected_contract:=c.readiness->'processing_admission';
 selected_notification:=c.readiness->'notification_admission';
 selected_native:=c.readiness->'native_sms_admission';
 IF selected_native IS NOT NULL AND selected_native->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256' THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','native_source_requires_review');END IF;
 IF selected_contract IS NOT NULL AND selected_contract->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256' THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','processing_source_requires_review');END IF;
 IF selected_notification IS NOT NULL AND selected_notification->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256' THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','notification_source_requires_review');END IF;
 IF (SELECT count(*) FROM collect_ops.jobs_dispatches WHERE created_at>=date_trunc('month',clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC')>=10000 THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','monthly_budget_exhausted');END IF;
 IF p_kind='scheduled' THEN
  slot_at:=to_timestamp(floor(extract(epoch FROM clock_timestamp())/300)*300);
  SELECT * INTO d FROM collect_ops.jobs_dispatches WHERE slot=slot_at;
  IF FOUND THEN RETURN jsonb_build_object('dispatch_id',d.id,'state',d.state,'net_request_id',d.net_request_id,'replayed',true);END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('anon','authenticated','collect_runtime','collect_importer') AND has_schema_privilege(rolname,'vault','USAGE') AND has_table_privilege(rolname,'vault.decrypted_secrets','SELECT')) THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','signing_key_acl_changed');END IF;
 SELECT decrypted_secret,id,updated_at INTO credential,secret_id,secret_updated_at FROM vault.decrypted_secrets WHERE name=c.vault_name;
 IF (SELECT count(*) FROM vault.decrypted_secrets WHERE name=c.vault_name)<>1 OR credential IS NULL OR credential !~ '^[a-f0-9]{64}$' THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','private_job_credential_unavailable');END IF;
 native_epoch_now:=collect_ops.native_jobs_epoch();
 IF native_epoch_now IS NULL THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','native_transport_unavailable');END IF;
 IF p_kind='scheduled' AND NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches p WHERE p.id=c.last_probe_id AND p.state='confirmed' AND p.native_epoch=native_epoch_now) THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','native_transport_instance_requires_probe');END IF;
 IF p_kind='scheduled' AND NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches p WHERE p.id=c.last_probe_id AND p.state='confirmed' AND p.vault_secret_id=secret_id AND p.vault_updated_at=secret_updated_at) THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','credential_rotation_requires_probe');END IF;
 IF p_kind='scheduled' AND NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches p WHERE p.id=c.last_probe_id AND p.state='confirmed' AND p.readiness_sha256=c.readiness->>'evidence_file_sha256' AND p.runtime_contract IS NOT DISTINCT FROM selected_contract AND p.notification_contract IS NOT DISTINCT FROM selected_notification AND p.native_contract IS NOT DISTINCT FROM selected_native) THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','processing_admission_requires_probe');END IF;
 INSERT INTO collect_ops.jobs_dispatches(id,kind,slot,state,native_epoch,readiness_sha256,vault_secret_id,vault_updated_at,runtime_contract,notification_contract,native_contract) VALUES(p_dispatch_id,p_kind,slot_at,'awaiting',native_epoch_now,c.readiness->>'evidence_file_sha256',secret_id,secret_updated_at,selected_contract,selected_notification,selected_native);
 BEGIN
  request_body:=jsonb_build_object('dispatch_id',p_dispatch_id);
  IF selected_contract IS NOT NULL THEN request_body:=request_body||jsonb_build_object('processing_admission',selected_contract);END IF;
  IF selected_notification IS NOT NULL THEN request_body:=request_body||jsonb_build_object('notification_admission',selected_notification);END IF;
  IF selected_native IS NOT NULL THEN request_body:=request_body||jsonb_build_object('native_sms_admission',selected_native);END IF;
  request_body:=request_body||jsonb_build_object('dispatch_expires_at',floor(extract(epoch FROM statement_timestamp()))::bigint+180);
  INSERT INTO private.collect_managed_job_tickets(dispatch_id,source_sha256,payload,expires_at)
   VALUES(p_dispatch_id,private.collect_fence_owner_status()->>'sourceSha256',request_body,to_timestamp((request_body->>'dispatch_expires_at')::bigint));
  request_id:=net.http_post(url:=c.endpoint,headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||encode(extensions.hmac(convert_to('collect.jobs.dispatch.v1'||E'\n'||'rrlduytparvsjfmegalh'||E'\n'||(private.collect_fence_owner_status()->>'sourceSha256')||E'\n'||p_dispatch_id::text||E'\n'||(request_body->>'dispatch_expires_at'),'UTF8'),convert_to(credential,'UTF8'),'sha256'),'hex')),body:=request_body,timeout_milliseconds:=120000);
  IF request_id IS NULL THEN RAISE EXCEPTION 'net_request_unconfirmed';END IF;
  UPDATE collect_ops.jobs_dispatches SET net_request_id=request_id WHERE id=p_dispatch_id;
 EXCEPTION WHEN OTHERS THEN
  -- pg_net begins HTTP only after commit. This nested rollback discards any
  -- queue row from a rejected enqueue; no SQLERRM/credential enters a log row.
  UPDATE collect_ops.jobs_dispatches SET state='rejected',reason='enqueue_rejected',observed_at=clock_timestamp() WHERE id=p_dispatch_id;
  PERFORM collect_ops.pause_jobs();
 END;
 IF p_kind='probe' THEN UPDATE collect_ops.jobs_config SET last_probe_id=p_dispatch_id WHERE singleton;END IF;
 SELECT * INTO d FROM collect_ops.jobs_dispatches WHERE id=p_dispatch_id;
 RETURN jsonb_build_object('dispatch_id',d.id,'state',d.state,'net_request_id',d.net_request_id);
END$$;
CREATE FUNCTION collect_ops.activate_jobs(p_evidence_sha256 text) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c collect_ops.jobs_config%ROWTYPE;
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.rrlduytparvsjfmegalh',0));PERFORM collect_ops.reconcile_jobs();
 SELECT * INTO c FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 IF c.readiness IS NULL OR c.readiness->>'evidence_file_sha256' IS DISTINCT FROM p_evidence_sha256 OR (c.readiness->>'verified_at')::timestamptz<clock_timestamp()-interval '1 hour'
 OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches WHERE id=c.last_probe_id AND kind='probe' AND state='confirmed' AND readiness_sha256=p_evidence_sha256 AND runtime_contract IS NOT DISTINCT FROM c.readiness->'processing_admission' AND notification_contract IS NOT DISTINCT FROM c.readiness->'notification_admission' AND native_contract IS NOT DISTINCT FROM c.readiness->'native_sms_admission' AND native_epoch=collect_ops.native_jobs_epoch() AND created_at>clock_timestamp()-interval '15 minutes')
 OR (c.readiness->'processing_admission' IS NOT NULL AND c.readiness->'processing_admission'->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256')
 OR (c.readiness->'notification_admission' IS NOT NULL AND c.readiness->'notification_admission'->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256')
 OR (c.readiness->'native_sms_admission' IS NOT NULL AND c.readiness->'native_sms_admission'->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256')
 OR EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed'))
 OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches p JOIN vault.decrypted_secrets v ON v.id=p.vault_secret_id AND v.updated_at=p.vault_updated_at WHERE p.id=c.last_probe_id AND v.name=c.vault_name) THEN RAISE EXCEPTION 'fresh_confirmed_probe_and_review_required';END IF;
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=c.cron_job_id AND jobname='collect-jobs-maintenance-v1' AND schedule='*/5 * * * *' AND command='SELECT collect_ops.tick_jobs();' AND database=current_database() AND username=current_user) THEN RAISE EXCEPTION 'cron_identity_changed';END IF;
 UPDATE collect_ops.jobs_config SET enabled=true WHERE singleton;PERFORM cron.alter_job(c.cron_job_id,active:=true);
 RETURN collect_ops.jobs_state();
END$$;
CREATE FUNCTION collect_ops.review_unknown_jobs(p_dispatch_id uuid,p_evidence_sha256 text) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 IF NOT coalesce(p_evidence_sha256 ~ '^[a-f0-9]{64}$',false) THEN RAISE EXCEPTION 'review_evidence_required';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.rrlduytparvsjfmegalh',0));PERFORM collect_ops.pause_jobs();
 UPDATE collect_ops.jobs_dispatches SET state='reviewed_unknown',resolution_evidence_sha256=p_evidence_sha256 WHERE id=p_dispatch_id AND state='unconfirmed' AND created_at<=clock_timestamp()-interval '5 minutes';
 IF NOT FOUND THEN RAISE EXCEPTION 'settled_unknown_dispatch_required';END IF;
 -- This is reviewed ambiguity, NEVER a fabricated successful worker receipt.
 UPDATE collect_ops.jobs_config SET last_probe_id=NULL WHERE singleton;
 RETURN jsonb_build_object('dispatch_id',p_dispatch_id,'state','reviewed_unknown','enabled',false);
END$$;
CREATE FUNCTION collect_ops.tick_jobs() RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c collect_ops.jobs_config%ROWTYPE;
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.rrlduytparvsjfmegalh',0));
 SELECT * INTO c FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 -- Bound operational history only. Unknown work/evidence is never auto-pruned.
 DELETE FROM collect_ops.jobs_dispatches WHERE id IN(SELECT id FROM collect_ops.jobs_dispatches WHERE state IN('confirmed','reviewed_unknown','rejected') AND id IS DISTINCT FROM c.last_probe_id AND created_at<clock_timestamp()-interval '30 days' AND created_at<date_trunc('month',clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' ORDER BY created_at LIMIT 500);
 DELETE FROM cron.job_run_details WHERE runid IN(SELECT runid FROM cron.job_run_details WHERE jobid=c.cron_job_id AND end_time<clock_timestamp()-interval '7 days' ORDER BY end_time LIMIT 500);
 RETURN collect_ops.dispatch_jobs('scheduled',gen_random_uuid());
END$$;
DO $$DECLARE id bigint;BEGIN
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='collect-jobs-maintenance-v1') THEN RAISE EXCEPTION 'existing_named_cron_job_requires_review';END IF;
 id:=cron.schedule('collect-jobs-maintenance-v1','*/5 * * * *','SELECT collect_ops.tick_jobs();');
 PERFORM cron.alter_job(id,active:=false);
 UPDATE collect_ops.jobs_config SET cron_job_id=id WHERE singleton;
END$$;
REVOKE ALL ON ALL TABLES IN SCHEMA collect_ops FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA collect_ops FROM PUBLIC;
DO $$DECLARE r text;BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_runtime','collect_importer'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN
   EXECUTE format('REVOKE ALL ON SCHEMA collect_ops FROM %I',r);
   EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA collect_ops FROM %I',r);
   EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA collect_ops FROM %I',r);
  END IF;
 END LOOP;
END$$;
-- Add the opaque job ticket to shared blocked retention inventory. Existing
-- catalog bytes and the exact managed project/fence are prerequisites.
DO $managed_job_retention$
DECLARE old_body text;new_body text;classes jsonb;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced' AND project_ref='rrlduytparvsjfmegalh')
  OR to_regclass('private.collect_managed_job_tickets') IS NULL THEN
  RAISE EXCEPTION 'managed_job_retention_precondition' USING ERRCODE='55000';END IF;
 SELECT prosrc INTO STRICT old_body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure
  AND pg_get_userbyid(proowner)='postgres' AND NOT prosecdef AND provolatile='i'
  AND proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND proacl::text='{postgres=X/postgres}';
 IF encode(sha256(convert_to(old_body,'UTF8')),'hex')<>'09ecc11aca46af15d7f981b5d5c7c7d3775be6fc245c8ff73f48f61269e37671' THEN
  RAISE EXCEPTION 'managed_job_retention_preimage_changed' USING ERRCODE='55000';END IF;
 classes:='[{"name":"private:collect_managed_job_tickets","relation":"private.collect_managed_job_tickets","scope":"shared_fence","purpose":"One-use scheduled job identity and bounded source/payload with claim and completion digests; blocked shared operational copy","blocked":true}]'::jsonb;
 new_body:=format('SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||%L::jsonb) FROM (%s) prior(base)',classes::text,old_body);
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(new_body);
END;$managed_job_retention$;

COMMIT;
