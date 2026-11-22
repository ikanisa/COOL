-- OPERATOR ARTIFACT, NOT AN APPLICATION MIGRATION. No extension/secret creation.
-- Render only through jobs_config.mjs; install transaction leaves Cron INACTIVE.
BEGIN;
CREATE SCHEMA collect_ops;
REVOKE ALL ON SCHEMA collect_ops FROM PUBLIC;
CREATE TABLE collect_ops.jobs_config(
 singleton boolean PRIMARY KEY CHECK(singleton),
 project_ref text NOT NULL CHECK(project_ref='__PROJECT_REF__'),
 endpoint text NOT NULL CHECK(endpoint='__ENDPOINT__'),
 vault_name text NOT NULL CHECK(vault_name='__VAULT_NAME__'),
 config_sha256 text NOT NULL CHECK(config_sha256='__CONFIG_SHA256__'),
 template_sha256 text NOT NULL CHECK(template_sha256='__TEMPLATE_SHA256__'),
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
 state text NOT NULL CHECK(state IN('awaiting','confirmed','unconfirmed','reviewed_unknown','rejected')),
 reason text NOT NULL DEFAULT 'awaiting_reply',http_status integer,maintenance_purged integer,
 response_sha256 text,observed_at timestamptz,resolution_evidence_sha256 text,
 UNIQUE(native_epoch,net_request_id),
 CHECK((kind='scheduled' AND slot IS NOT NULL) OR(kind='probe' AND slot IS NULL)),
 CHECK(maintenance_purged IS NULL OR maintenance_purged BETWEEN 0 AND 100),
 CHECK(response_sha256 IS NULL OR response_sha256 ~ '^[a-f0-9]{64}$'),
 CHECK(resolution_evidence_sha256 IS NULL OR resolution_evidence_sha256 ~ '^[a-f0-9]{64}$')
);
CREATE INDEX jobs_dispatches_pending ON collect_ops.jobs_dispatches(state,created_at);
ALTER TABLE collect_ops.jobs_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE collect_ops.jobs_dispatches ENABLE ROW LEVEL SECURITY;
INSERT INTO collect_ops.jobs_config(singleton,project_ref,endpoint,vault_name,config_sha256,template_sha256) VALUES(true,'__PROJECT_REF__','__ENDPOINT__','__VAULT_NAME__','__CONFIG_SHA256__','__TEMPLATE_SHA256__');

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
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobid=c.cron_job_id AND jobname='__JOB_NAME__') THEN PERFORM cron.alter_job(c.cron_job_id,active:=false);END IF;
 RETURN collect_ops.jobs_state();
END$$;
CREATE FUNCTION collect_ops.record_jobs_readiness(p_readiness jsonb) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE k text;processing boolean;notifications boolean;expected_keys text[];admission jsonb;
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 IF p_readiness IS NULL OR jsonb_typeof(p_readiness) IS DISTINCT FROM 'object' OR p_readiness->>'verified_at' IS NULL OR p_readiness->>'format' NOT IN('collect.jobs.readiness.v1','collect.jobs.readiness.v2','collect.jobs.readiness.v3') OR p_readiness->>'format' IS NULL OR p_readiness->>'project_ref' IS DISTINCT FROM '__PROJECT_REF__' OR p_readiness->>'endpoint' IS DISTINCT FROM '__ENDPOINT__' THEN RAISE EXCEPTION 'reviewed_job_readiness_required';END IF;
 notifications:=p_readiness->>'format'='collect.jobs.readiness.v3';
 processing:=p_readiness->>'format'='collect.jobs.readiness.v2' OR(notifications AND p_readiness->>'mode'='receipt_and_push_v1');
 IF notifications AND(p_readiness->>'mode' IS NULL OR p_readiness->>'mode' NOT IN('notification_delivery_v1','receipt_and_push_v1')) THEN RAISE EXCEPTION 'reviewed_notification_mode_required';END IF;
 expected_keys:=ARRAY['format','project_ref','endpoint','deployment_sha256','runtime_evidence_sha256','token_custody_evidence_sha256','copy_inventory_evidence_sha256','quota_evidence_sha256','verified_at','momo_processing_paused','remaining_invocations','evidence_file_sha256'];
 IF processing OR notifications THEN expected_keys:=expected_keys||ARRAY['mode'];END IF;
 IF processing THEN expected_keys:=expected_keys||ARRAY['processing_admission','provider_evidence_sha256','remaining_provider_requests'];END IF;
 IF notifications THEN expected_keys:=expected_keys||ARRAY['notification_admission','notification_provider_evidence_sha256','remaining_notification_attempts','remaining_notification_provider_requests'];END IF;
 IF (SELECT count(*) FROM jsonb_object_keys(p_readiness))<>cardinality(expected_keys) OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_readiness) key WHERE NOT key=ANY(expected_keys)) THEN RAISE EXCEPTION 'strict_evidence_fields_required';END IF;
 IF p_readiness->'momo_processing_paused' IS DISTINCT FROM to_jsonb(NOT processing) THEN RAISE EXCEPTION 'reviewed_job_readiness_required';END IF;
 FOREACH k IN ARRAY (ARRAY['deployment_sha256','runtime_evidence_sha256','token_custody_evidence_sha256','copy_inventory_evidence_sha256','quota_evidence_sha256','evidence_file_sha256']||CASE WHEN processing THEN ARRAY['provider_evidence_sha256'] ELSE ARRAY[]::text[] END||CASE WHEN notifications THEN ARRAY['notification_provider_evidence_sha256'] ELSE ARRAY[]::text[] END) LOOP
  IF jsonb_typeof(p_readiness->k) IS DISTINCT FROM 'string' OR NOT coalesce(p_readiness->>k ~ '^[a-f0-9]{64}$',false) THEN RAISE EXCEPTION 'readiness_evidence_digest_required';END IF;
 END LOOP;
 IF (p_readiness->>'verified_at')::timestamptz<clock_timestamp()-interval '1 hour' OR (p_readiness->>'verified_at')::timestamptz>clock_timestamp()+interval '30 seconds' OR jsonb_typeof(p_readiness->'remaining_invocations') IS DISTINCT FROM 'number' OR NOT coalesce(p_readiness->>'remaining_invocations' ~ '^[0-9]{1,9}$',false) OR (p_readiness->>'remaining_invocations')::bigint<10000 THEN RAISE EXCEPTION 'fresh_runtime_and_quota_review_required';END IF;
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
DECLARE d collect_ops.jobs_dispatches%ROWTYPE;r record;payload jsonb;v_reason text;observed integer:=0;uncertain integer:=0;purged integer;confirmed boolean;processing_ok boolean;notifications_ok boolean;native_epoch_now text;
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.__PROJECT_REF__',0));
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
   IF r.status_code=200 AND NOT coalesce(r.timed_out,true) AND NOT r.failed AND jsonb_typeof(payload->'dispatch_id')='string' AND payload->>'dispatch_id'=d.id::text AND payload->'maintenance'->>'status'='complete'
    AND payload->'maintenance'->>'examined_limit'='100' AND payload->'maintenance'->>'provider_calls'='0'
    AND jsonb_typeof(payload->'maintenance'->'purged')='number' AND payload->'maintenance'->>'purged' ~ '^(0|[1-9][0-9]{0,2})$'
    AND purged BETWEEN 0 AND 100 AND coalesce(processing_ok,false) AND coalesce(notifications_ok,false) THEN
    confirmed:=true;v_reason:='reply_confirmed';purged:=(payload->'maintenance'->>'purged')::integer;
   ELSIF r.status_code=200 AND (jsonb_typeof(payload->'dispatch_id') IS DISTINCT FROM 'string' OR payload->>'dispatch_id' IS DISTINCT FROM d.id::text) THEN v_reason:='dispatch_identity_mismatch';
   ELSIF r.status_code=200 AND d.runtime_contract IS NOT NULL AND payload->'processing_admission' IS DISTINCT FROM d.runtime_contract THEN v_reason:='processing_admission_mismatch';
   ELSIF r.status_code=200 AND d.notification_contract IS NOT NULL AND payload->'notification_admission' IS DISTINCT FROM d.notification_contract THEN v_reason:='notification_admission_mismatch';
   ELSIF r.status_code=200 AND(NOT coalesce(processing_ok,false) OR NOT coalesce(notifications_ok,false)) THEN v_reason:='runtime_gate_changed';
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
DECLARE c collect_ops.jobs_config%ROWTYPE;d collect_ops.jobs_dispatches%ROWTYPE;slot_at timestamptz;request_id bigint;credential text;secret_id uuid;secret_updated_at timestamptz;native_epoch_now text;selected_contract jsonb;selected_notification jsonb;request_body jsonb;
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 IF p_kind NOT IN('probe','scheduled') OR p_dispatch_id IS NULL THEN RAISE EXCEPTION 'invalid_dispatch_identity';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.__PROJECT_REF__',0));
 SELECT * INTO d FROM collect_ops.jobs_dispatches WHERE id=p_dispatch_id;
 IF FOUND THEN RETURN jsonb_build_object('dispatch_id',d.id,'state',d.state,'net_request_id',d.net_request_id,'replayed',true);END IF;
 PERFORM collect_ops.reconcile_jobs();
 SELECT * INTO c FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 IF EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed')) THEN RETURN jsonb_build_object('state','blocked_pending_reconciliation');END IF;
 IF p_kind='scheduled' AND NOT c.enabled THEN RETURN jsonb_build_object('state','disabled');END IF;
 IF c.readiness IS NULL OR (p_kind='probe' AND ((c.readiness->>'verified_at')::timestamptz<clock_timestamp()-interval '1 hour' OR c.enabled)) THEN RAISE EXCEPTION 'fresh_disabled_probe_readiness_required';END IF;
 selected_contract:=c.readiness->'processing_admission';
 selected_notification:=c.readiness->'notification_admission';
 IF selected_contract IS NOT NULL AND selected_contract->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256' THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','processing_source_requires_review');END IF;
 IF selected_notification IS NOT NULL AND selected_notification->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256' THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','notification_source_requires_review');END IF;
 IF (SELECT count(*) FROM collect_ops.jobs_dispatches WHERE created_at>=date_trunc('month',clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC')>=10000 THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','monthly_budget_exhausted');END IF;
 IF p_kind='scheduled' THEN
  slot_at:=to_timestamp(floor(extract(epoch FROM clock_timestamp())/300)*300);
  SELECT * INTO d FROM collect_ops.jobs_dispatches WHERE slot=slot_at;
  IF FOUND THEN RETURN jsonb_build_object('dispatch_id',d.id,'state',d.state,'net_request_id',d.net_request_id,'replayed',true);END IF;
 END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer') AND (has_schema_privilege(rolname,'vault','USAGE') OR has_schema_privilege(rolname,'net','USAGE') OR has_table_privilege(rolname,'net.http_request_queue','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') OR has_table_privilege(rolname,'net._http_response','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))) THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','credential_dependency_acl_changed');END IF;
 SELECT decrypted_secret,id,updated_at INTO credential,secret_id,secret_updated_at FROM vault.decrypted_secrets WHERE name=c.vault_name;
 IF credential IS NULL OR length(credential)<32 OR length(credential)>4096 OR credential ~ '[[:space:]]' THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','private_job_credential_unavailable');END IF;
 native_epoch_now:=collect_ops.native_jobs_epoch();
 IF native_epoch_now IS NULL THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','native_transport_unavailable');END IF;
 IF p_kind='scheduled' AND NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches p WHERE p.id=c.last_probe_id AND p.state='confirmed' AND p.native_epoch=native_epoch_now) THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','native_transport_instance_requires_probe');END IF;
 IF p_kind='scheduled' AND NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches p WHERE p.id=c.last_probe_id AND p.state='confirmed' AND p.vault_secret_id=secret_id AND p.vault_updated_at=secret_updated_at) THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','credential_rotation_requires_probe');END IF;
 IF p_kind='scheduled' AND NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches p WHERE p.id=c.last_probe_id AND p.state='confirmed' AND p.readiness_sha256=c.readiness->>'evidence_file_sha256' AND p.runtime_contract IS NOT DISTINCT FROM selected_contract AND p.notification_contract IS NOT DISTINCT FROM selected_notification) THEN PERFORM collect_ops.pause_jobs();RETURN jsonb_build_object('state','processing_admission_requires_probe');END IF;
 INSERT INTO collect_ops.jobs_dispatches(id,kind,slot,state,native_epoch,readiness_sha256,vault_secret_id,vault_updated_at,runtime_contract,notification_contract) VALUES(p_dispatch_id,p_kind,slot_at,'awaiting',native_epoch_now,c.readiness->>'evidence_file_sha256',secret_id,secret_updated_at,selected_contract,selected_notification);
 BEGIN
  -- Never inline or return the credential. pg_net's restricted unlogged queue
  -- necessarily holds the live header until dispatch; it is NOT durable proof.
  request_body:=jsonb_build_object('dispatch_id',p_dispatch_id);
  IF selected_contract IS NOT NULL THEN request_body:=request_body||jsonb_build_object('processing_admission',selected_contract);END IF;
  IF selected_notification IS NOT NULL THEN request_body:=request_body||jsonb_build_object('notification_admission',selected_notification);END IF;
  request_id:=net.http_post(url:=c.endpoint,headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||credential),body:=request_body,timeout_milliseconds:=120000);
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
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.__PROJECT_REF__',0));PERFORM collect_ops.reconcile_jobs();
 SELECT * INTO c FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 IF c.readiness IS NULL OR c.readiness->>'evidence_file_sha256' IS DISTINCT FROM p_evidence_sha256 OR (c.readiness->>'verified_at')::timestamptz<clock_timestamp()-interval '1 hour'
 OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches WHERE id=c.last_probe_id AND kind='probe' AND state='confirmed' AND readiness_sha256=p_evidence_sha256 AND runtime_contract IS NOT DISTINCT FROM c.readiness->'processing_admission' AND notification_contract IS NOT DISTINCT FROM c.readiness->'notification_admission' AND native_epoch=collect_ops.native_jobs_epoch() AND created_at>clock_timestamp()-interval '15 minutes')
 OR (c.readiness->'processing_admission' IS NOT NULL AND c.readiness->'processing_admission'->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256')
 OR (c.readiness->'notification_admission' IS NOT NULL AND c.readiness->'notification_admission'->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256')
 OR EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed'))
 OR NOT EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches p JOIN vault.decrypted_secrets v ON v.id=p.vault_secret_id AND v.updated_at=p.vault_updated_at WHERE p.id=c.last_probe_id AND v.name=c.vault_name) THEN RAISE EXCEPTION 'fresh_confirmed_probe_and_review_required';END IF;
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=c.cron_job_id AND jobname='__JOB_NAME__' AND schedule='__SCHEDULE__' AND command='SELECT collect_ops.tick_jobs();' AND database=current_database() AND username=current_user) THEN RAISE EXCEPTION 'cron_identity_changed';END IF;
 UPDATE collect_ops.jobs_config SET enabled=true WHERE singleton;PERFORM cron.alter_job(c.cron_job_id,active:=true);
 RETURN collect_ops.jobs_state();
END$$;
CREATE FUNCTION collect_ops.review_unknown_jobs(p_dispatch_id uuid,p_evidence_sha256 text) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 IF NOT coalesce(p_evidence_sha256 ~ '^[a-f0-9]{64}$',false) THEN RAISE EXCEPTION 'review_evidence_required';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.__PROJECT_REF__',0));PERFORM collect_ops.pause_jobs();
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
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.__PROJECT_REF__',0));
 SELECT * INTO c FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 -- Bound operational history only. Unknown work/evidence is never auto-pruned.
 DELETE FROM collect_ops.jobs_dispatches WHERE id IN(SELECT id FROM collect_ops.jobs_dispatches WHERE state IN('confirmed','reviewed_unknown','rejected') AND id IS DISTINCT FROM c.last_probe_id AND created_at<clock_timestamp()-interval '30 days' AND created_at<date_trunc('month',clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' ORDER BY created_at LIMIT 500);
 DELETE FROM cron.job_run_details WHERE runid IN(SELECT runid FROM cron.job_run_details WHERE jobid=c.cron_job_id AND end_time<clock_timestamp()-interval '7 days' ORDER BY end_time LIMIT 500);
 RETURN collect_ops.dispatch_jobs('scheduled',gen_random_uuid());
END$$;
DO $$DECLARE id bigint;BEGIN
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='__JOB_NAME__') THEN RAISE EXCEPTION 'existing_named_cron_job_requires_review';END IF;
 id:=cron.schedule('__JOB_NAME__','__SCHEDULE__','SELECT collect_ops.tick_jobs();');
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
COMMIT;
