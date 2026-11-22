-- Owner operator artifact. Creates no extension, secret, provider call or active schedule.
BEGIN;
DO $$BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'email_owner_install_required';END IF;
 PERFORM private.collect_assert_deployment('__PROFILE_SHA256__');
END$$;
CREATE SCHEMA IF NOT EXISTS collect_ops;
REVOKE ALL ON SCHEMA collect_ops FROM PUBLIC;
CREATE TABLE collect_ops.email_config(
 singleton boolean PRIMARY KEY CHECK(singleton),profile_sha256 text NOT NULL CHECK(profile_sha256='__PROFILE_SHA256__'),
 endpoint text NOT NULL CHECK(endpoint='__ENDPOINT__'),vault_name text NOT NULL CHECK(vault_name='collect_email_job_token_v1'),
 config_sha256 text NOT NULL CHECK(config_sha256='__CONFIG_SHA256__'),template_sha256 text NOT NULL CHECK(template_sha256='__TEMPLATE_SHA256__'),
 enabled boolean NOT NULL DEFAULT false,cron_job_id bigint,readiness jsonb,last_probe_id uuid,created_at timestamptz NOT NULL DEFAULT clock_timestamp());
CREATE FUNCTION collect_ops.email_native_epoch() RETURNS text LANGUAGE plpgsql STABLE SET search_path=pg_catalog AS $$
DECLARE q regclass:=to_regclass('net.http_request_queue');r regclass:=to_regclass('net._http_response');s regclass;
BEGIN IF q IS NULL OR r IS NULL THEN RETURN NULL;END IF;s:=to_regclass(pg_get_serial_sequence('net.http_request_queue','id'));IF s IS NULL THEN RETURN NULL;END IF;
 RETURN encode(sha256(convert_to(jsonb_build_array(pg_postmaster_start_time(),q::oid,r::oid,s::oid)::text,'UTF8')),'hex');END$$;
CREATE TABLE collect_ops.email_dispatches(
 id uuid PRIMARY KEY,kind text NOT NULL CHECK(kind IN('probe','scheduled')),slot timestamptz UNIQUE,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 native_epoch text NOT NULL CHECK(native_epoch ~ '^[a-f0-9]{64}$'),net_request_id bigint,readiness_sha256 text NOT NULL,
 vault_secret_id uuid NOT NULL,vault_updated_at timestamptz NOT NULL,email_admission jsonb NOT NULL,
 state text NOT NULL CHECK(state IN('awaiting','confirmed','unconfirmed','reviewed_unknown','rejected')),reason text NOT NULL DEFAULT 'awaiting_reply',
 http_status integer,response_sha256 text,observed_at timestamptz,review_evidence_sha256 text,
 UNIQUE(native_epoch,net_request_id),CHECK((kind='probe' AND slot IS NULL)OR(kind='scheduled' AND slot IS NOT NULL)));
CREATE INDEX email_dispatches_pending ON collect_ops.email_dispatches(state,created_at);
ALTER TABLE collect_ops.email_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE collect_ops.email_dispatches ENABLE ROW LEVEL SECURITY;
INSERT INTO collect_ops.email_config(singleton,profile_sha256,endpoint,vault_name,config_sha256,template_sha256)
 VALUES(true,'__PROFILE_SHA256__','__ENDPOINT__','collect_email_job_token_v1','__CONFIG_SHA256__','__TEMPLATE_SHA256__');
CREATE FUNCTION collect_ops.email_state() RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('enabled',c.enabled,'cron_active',(SELECT active FROM cron.job WHERE jobid=c.cron_job_id),
 'profile_sha256',c.profile_sha256,'config_sha256',c.config_sha256,'template_sha256',c.template_sha256,'endpoint',c.endpoint,
 'last_probe_id',c.last_probe_id,'readiness_sha256',c.readiness->>'evidence_file_sha256','native_epoch',collect_ops.email_native_epoch(),
 'awaiting',(SELECT count(*) FROM collect_ops.email_dispatches WHERE state='awaiting'),
 'unconfirmed',(SELECT count(*) FROM collect_ops.email_dispatches WHERE state='unconfirmed'),
 'month_dispatches',(SELECT count(*) FROM collect_ops.email_dispatches WHERE created_at>=date_trunc('month',now() AT TIME ZONE 'UTC')AT TIME ZONE 'UTC'))
 FROM collect_ops.email_config c WHERE singleton$$;
CREATE FUNCTION collect_ops.pause_email() RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c collect_ops.email_config%ROWTYPE;BEGIN
 PERFORM private.collect_assert_deployment('__PROFILE_SHA256__');
 SELECT * INTO c FROM collect_ops.email_config WHERE singleton FOR UPDATE;UPDATE collect_ops.email_config SET enabled=false WHERE singleton;
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobid=c.cron_job_id AND jobname='collect-email-delivery-v1')THEN PERFORM cron.alter_job(c.cron_job_id,active:=false);END IF;
 RETURN collect_ops.email_state();END$$;
CREATE FUNCTION collect_ops.record_email_readiness(p jsonb) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE k text;a jsonb;BEGIN
 PERFORM private.collect_assert_deployment('__PROFILE_SHA256__');
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 IF jsonb_typeof(p)IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'email_readiness_shape';END IF;
 IF jsonb_typeof(p)IS DISTINCT FROM 'object' OR p->>'format' IS DISTINCT FROM 'collect.email.readiness.v1' OR p->>'profile_sha256' IS DISTINCT FROM '__PROFILE_SHA256__'
 OR p->>'endpoint' IS DISTINCT FROM '__ENDPOINT__' OR (SELECT count(*)FROM jsonb_object_keys(p))<>14
 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p)AS keys(name) WHERE name NOT IN('format','profile_sha256','endpoint','source_sha256','deployment_sha256','runtime_evidence_sha256','provider_evidence_sha256','token_custody_evidence_sha256','copy_inventory_evidence_sha256','quota_evidence_sha256','verified_at','email_admission','monthly_budget','evidence_file_sha256'))THEN RAISE EXCEPTION 'email_readiness_shape';END IF;
 FOREACH k IN ARRAY ARRAY['profile_sha256','source_sha256','deployment_sha256','runtime_evidence_sha256','provider_evidence_sha256','token_custody_evidence_sha256','copy_inventory_evidence_sha256','quota_evidence_sha256','evidence_file_sha256']LOOP
  IF jsonb_typeof(p->k)IS DISTINCT FROM 'string' OR NOT coalesce(p->>k ~ '^[a-f0-9]{64}$',false)THEN RAISE EXCEPTION 'email_evidence_required';END IF;
 END LOOP;
 IF p->>'verified_at' IS NULL OR(p->>'verified_at')::timestamptz<clock_timestamp()-interval '1 hour' OR(p->>'verified_at')::timestamptz>clock_timestamp()+interval '30 seconds'
 OR p->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256'
 OR jsonb_typeof(p->'monthly_budget')IS DISTINCT FROM 'number' OR NOT coalesce(p->>'monthly_budget'~'^[1-9][0-9]{0,4}$',false) OR(p->>'monthly_budget')::integer>10000 THEN RAISE EXCEPTION 'email_source_quota_or_freshness';END IF;
 a:=p->'email_admission';
 IF jsonb_typeof(a)IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'email_admission_required';END IF;
 IF jsonb_typeof(a)IS DISTINCT FROM 'object' OR(SELECT count(*)FROM jsonb_object_keys(a))<>5 OR EXISTS(SELECT 1 FROM jsonb_object_keys(a)AS keys(name) WHERE name NOT IN('contract','source_sha256','approval_sha256','admitted_from','batch_limit'))
 OR a->>'contract' IS DISTINCT FROM 'collect.contribution-email.v1' OR a->'batch_limit' IS DISTINCT FROM '1'::jsonb OR a->>'source_sha256' IS DISTINCT FROM p->>'source_sha256'
 OR jsonb_typeof(a->'approval_sha256')IS DISTINCT FROM 'string' OR NOT coalesce(a->>'approval_sha256'~'^[a-f0-9]{64}$',false)
 OR jsonb_typeof(a->'admitted_from')IS DISTINCT FROM 'number' OR NOT coalesce(a->>'admitted_from'~'^[1-9][0-9]{0,9}$',false) OR(a->>'admitted_from')::bigint>=4102444800 THEN RAISE EXCEPTION 'email_admission_required';END IF;
 PERFORM collect_ops.pause_email();UPDATE collect_ops.email_config SET readiness=p,last_probe_id=CASE WHEN readiness IS NOT DISTINCT FROM p THEN last_probe_id ELSE NULL END WHERE singleton;
END$$;
CREATE FUNCTION collect_ops.reconcile_email() RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE d collect_ops.email_dispatches%ROWTYPE;r record;p jsonb;ok boolean;v_reason text;observed integer:=0;BEGIN
 PERFORM private.collect_assert_deployment('__PROFILE_SHA256__');
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);PERFORM pg_advisory_xact_lock(hashtextextended('collect.email.__PROFILE_SHA256__',0));
 PERFORM 1 FROM collect_ops.email_config WHERE singleton FOR UPDATE;
 FOR d IN SELECT * FROM collect_ops.email_dispatches WHERE state='awaiting' ORDER BY created_at,id LIMIT 20 FOR UPDATE LOOP
  p:=NULL;ok:=false;v_reason:='reply_unconfirmed';SELECT NULL::integer AS status_code,NULL::text AS content INTO r;
  IF d.native_epoch IS DISTINCT FROM collect_ops.email_native_epoch()THEN v_reason:='native_transport_instance_changed';
  ELSE
   SELECT status_code,timed_out,error_msg IS NOT NULL AS failed,CASE WHEN octet_length(content)<=16384 THEN content ELSE NULL END AS content INTO r FROM net._http_response WHERE id=d.net_request_id ORDER BY created DESC LIMIT 1;
   IF NOT FOUND AND d.created_at>clock_timestamp()-interval '180 seconds'THEN CONTINUE;END IF;
   IF r.content IS NOT NULL THEN BEGIN p:=r.content::jsonb;EXCEPTION WHEN OTHERS THEN p:=NULL;END;END IF;
   IF r.status_code=200 AND NOT coalesce(r.timed_out,true) AND NOT r.failed AND jsonb_typeof(p)='object' THEN
    IF (SELECT count(*)FROM jsonb_object_keys(p))=3
    AND p->>'dispatch_id'=d.id::text AND p->'email_admission'=d.email_admission AND jsonb_typeof(p->'emails')='object'
    THEN
    IF (SELECT count(*)FROM jsonb_object_keys(p->'emails'))=3 AND p->'emails'->>'status'='complete'
    AND p->'emails'->'processed' IN('0'::jsonb,'1'::jsonb) AND jsonb_typeof(p->'emails'->'results')='array'THEN
    ok:=to_jsonb(jsonb_array_length(p->'emails'->'results'))=p->'emails'->'processed';
    IF ok THEN ok:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(p->'emails'->'results')item WHERE item IS DISTINCT FROM jsonb_build_object('state',item->>'state','delivery_confirmed',false)OR item->>'state' IS NULL OR item->>'state' NOT IN('accepted','suppressed'));END IF;
    IF ok THEN v_reason:='reply_confirmed';ELSIF EXISTS(SELECT 1 FROM jsonb_array_elements(p->'emails'->'results')item WHERE item->>'state'='unknown')THEN v_reason:='email_outcome_unknown';END IF;
    END IF;
    END IF;
   END IF;
  END IF;
  UPDATE collect_ops.email_dispatches SET state=CASE WHEN ok THEN 'confirmed' ELSE 'unconfirmed'END,reason=v_reason,
   http_status=CASE WHEN r.status_code BETWEEN 100 AND 599 THEN r.status_code ELSE NULL END,
   response_sha256=CASE WHEN r.content IS NOT NULL THEN encode(sha256(convert_to(r.content,'UTF8')),'hex')ELSE NULL END,observed_at=clock_timestamp()WHERE id=d.id;
  observed:=observed+1;IF NOT ok THEN PERFORM collect_ops.pause_email();END IF;
 END LOOP;RETURN jsonb_build_object('observed',observed);
END$$;
CREATE FUNCTION collect_ops.dispatch_email(p_kind text,p_id uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c collect_ops.email_config%ROWTYPE;d collect_ops.email_dispatches%ROWTYPE;credential text;secret_id uuid;secret_updated timestamptz;epoch text;slot_at timestamptz;request_id bigint;BEGIN
 PERFORM private.collect_assert_deployment('__PROFILE_SHA256__');
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);IF p_kind NOT IN('probe','scheduled')OR p_id IS NULL THEN RAISE EXCEPTION 'email_dispatch_identity';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.email.__PROFILE_SHA256__',0));
 SELECT * INTO d FROM collect_ops.email_dispatches WHERE id=p_id;IF FOUND THEN RETURN jsonb_build_object('dispatch_id',d.id,'state',d.state,'replayed',true);END IF;
 PERFORM collect_ops.reconcile_email();SELECT * INTO c FROM collect_ops.email_config WHERE singleton FOR UPDATE;
 IF EXISTS(SELECT 1 FROM collect_ops.email_dispatches WHERE state IN('awaiting','unconfirmed'))THEN RETURN jsonb_build_object('state','blocked_pending_reconciliation');END IF;
 IF p_kind='scheduled'AND NOT c.enabled THEN RETURN jsonb_build_object('state','disabled');END IF;
 IF c.readiness IS NULL OR(p_kind='probe'AND(c.enabled OR(c.readiness->>'verified_at')::timestamptz<clock_timestamp()-interval '1 hour'))THEN RAISE EXCEPTION 'email_fresh_disabled_probe_required';END IF;
 IF c.readiness->>'source_sha256' IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256'THEN PERFORM collect_ops.pause_email();RETURN jsonb_build_object('state','source_requires_review');END IF;
 IF(SELECT count(*)FROM collect_ops.email_dispatches WHERE created_at>=date_trunc('month',clock_timestamp()AT TIME ZONE 'UTC')AT TIME ZONE 'UTC')>=(c.readiness->>'monthly_budget')::integer THEN PERFORM collect_ops.pause_email();RETURN jsonb_build_object('state','monthly_budget_exhausted');END IF;
 IF p_kind='scheduled'THEN slot_at:=to_timestamp(floor(extract(epoch FROM clock_timestamp())/300)*300);SELECT * INTO d FROM collect_ops.email_dispatches WHERE slot=slot_at;IF FOUND THEN RETURN jsonb_build_object('dispatch_id',d.id,'state',d.state,'replayed',true);END IF;END IF;
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer','collect_sms_runtime')AND(has_schema_privilege(rolname,'vault','USAGE')OR has_schema_privilege(rolname,'net','USAGE')OR has_table_privilege(rolname,'net.http_request_queue','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')OR has_table_privilege(rolname,'net._http_response','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')))THEN PERFORM collect_ops.pause_email();RETURN jsonb_build_object('state','credential_dependency_acl_changed');END IF;
 SELECT decrypted_secret,id,updated_at INTO credential,secret_id,secret_updated FROM vault.decrypted_secrets WHERE name=c.vault_name;
 IF credential IS NULL OR length(credential)<32 OR length(credential)>4096 OR credential~'[[:space:]]'THEN PERFORM collect_ops.pause_email();RETURN jsonb_build_object('state','private_credential_unavailable');END IF;
 epoch:=collect_ops.email_native_epoch();IF epoch IS NULL THEN PERFORM collect_ops.pause_email();RETURN jsonb_build_object('state','native_transport_unavailable');END IF;
 IF p_kind='scheduled'AND NOT EXISTS(SELECT 1 FROM collect_ops.email_dispatches p WHERE p.id=c.last_probe_id AND p.state='confirmed'AND p.native_epoch=epoch AND p.vault_secret_id=secret_id AND p.vault_updated_at=secret_updated AND p.readiness_sha256=c.readiness->>'evidence_file_sha256'AND p.email_admission=c.readiness->'email_admission')THEN PERFORM collect_ops.pause_email();RETURN jsonb_build_object('state','new_probe_required');END IF;
 INSERT INTO collect_ops.email_dispatches(id,kind,slot,native_epoch,readiness_sha256,vault_secret_id,vault_updated_at,email_admission,state)VALUES(p_id,p_kind,slot_at,epoch,c.readiness->>'evidence_file_sha256',secret_id,secret_updated,c.readiness->'email_admission','awaiting');
 BEGIN
  request_id:=net.http_post(url:=c.endpoint,headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||credential),body:=jsonb_build_object('dispatch_id',p_id,'email_admission',c.readiness->'email_admission'),timeout_milliseconds:=120000);
  IF request_id IS NULL THEN RAISE EXCEPTION 'email_enqueue_unknown';END IF;UPDATE collect_ops.email_dispatches SET net_request_id=request_id WHERE id=p_id;
 EXCEPTION WHEN OTHERS THEN UPDATE collect_ops.email_dispatches SET state='rejected',reason='enqueue_rejected',observed_at=clock_timestamp()WHERE id=p_id;PERFORM collect_ops.pause_email();END;
 IF p_kind='probe'THEN UPDATE collect_ops.email_config SET last_probe_id=p_id WHERE singleton;END IF;
 SELECT * INTO d FROM collect_ops.email_dispatches WHERE id=p_id;RETURN jsonb_build_object('dispatch_id',d.id,'state',d.state);
END$$;
CREATE FUNCTION collect_ops.activate_email(p_evidence text) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE c collect_ops.email_config%ROWTYPE;BEGIN
 PERFORM private.collect_assert_deployment('__PROFILE_SHA256__');
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);PERFORM pg_advisory_xact_lock(hashtextextended('collect.email.__PROFILE_SHA256__',0));PERFORM collect_ops.reconcile_email();
 SELECT * INTO c FROM collect_ops.email_config WHERE singleton FOR UPDATE;
 IF c.readiness->>'evidence_file_sha256'IS DISTINCT FROM p_evidence OR c.readiness IS NULL OR(c.readiness->>'verified_at')::timestamptz<clock_timestamp()-interval '1 hour'
 OR c.readiness->>'source_sha256'IS DISTINCT FROM private.collect_fence_owner_status()->>'sourceSha256'
 OR EXISTS(SELECT 1 FROM collect_ops.email_dispatches WHERE state IN('awaiting','unconfirmed'))
 OR NOT EXISTS(SELECT 1 FROM collect_ops.email_dispatches p JOIN vault.decrypted_secrets v ON v.id=p.vault_secret_id AND v.updated_at=p.vault_updated_at
 WHERE p.id=c.last_probe_id AND p.kind='probe'AND p.state='confirmed'AND p.readiness_sha256=p_evidence AND p.email_admission=c.readiness->'email_admission'AND p.native_epoch=collect_ops.email_native_epoch()AND p.created_at>clock_timestamp()-interval '15 minutes'AND v.name=c.vault_name)
 THEN RAISE EXCEPTION 'email_fresh_confirmed_probe_required';END IF;
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=c.cron_job_id AND jobname='collect-email-delivery-v1'AND schedule='*/5 * * * *'AND command='SELECT collect_ops.tick_email();'AND database=current_database()AND username=current_user)THEN RAISE EXCEPTION 'email_cron_identity_changed';END IF;
 UPDATE collect_ops.email_config SET enabled=true WHERE singleton;PERFORM cron.alter_job(c.cron_job_id,active:=true);RETURN collect_ops.email_state();END$$;
CREATE FUNCTION collect_ops.review_email_unknown(p_id uuid,p_evidence text) RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN PERFORM private.collect_assert_deployment('__PROFILE_SHA256__');PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);IF NOT coalesce(p_evidence~'^[a-f0-9]{64}$',false)THEN RAISE EXCEPTION 'email_review_evidence_required';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.email.__PROFILE_SHA256__',0));PERFORM collect_ops.pause_email();
 UPDATE collect_ops.email_dispatches SET state='reviewed_unknown',review_evidence_sha256=p_evidence WHERE id=p_id AND state='unconfirmed'AND created_at<clock_timestamp()-interval '5 minutes';
 IF NOT FOUND THEN RAISE EXCEPTION 'email_settled_unknown_required';END IF;UPDATE collect_ops.email_config SET last_probe_id=NULL WHERE singleton;
 RETURN jsonb_build_object('dispatch_id',p_id,'state','reviewed_unknown','enabled',false);END$$;
CREATE FUNCTION collect_ops.tick_email() RETURNS jsonb LANGUAGE sql SET search_path=pg_catalog AS $$SELECT collect_ops.dispatch_email('scheduled',gen_random_uuid())$$;
DO $$DECLARE id bigint;BEGIN IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='collect-email-delivery-v1')THEN RAISE EXCEPTION 'email_named_cron_exists';END IF;
 id:=cron.schedule('collect-email-delivery-v1','*/5 * * * *','SELECT collect_ops.tick_email();');PERFORM cron.alter_job(id,active:=false);UPDATE collect_ops.email_config SET cron_job_id=id WHERE singleton;END$$;
REVOKE ALL ON ALL TABLES IN SCHEMA collect_ops FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA collect_ops FROM PUBLIC;
DO $$DECLARE r text;BEGIN FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_runtime','collect_importer','collect_sms_runtime']LOOP
 IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r)THEN EXECUTE format('REVOKE ALL ON SCHEMA collect_ops FROM %I',r);EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA collect_ops FROM %I',r);EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA collect_ops FROM %I',r);END IF;END LOOP;END$$;

-- Extend the existing closed scheduler inventory in the same owner transaction.
-- The renderer binds exact email routine bodies and metadata, not a name prefix.
-- Existing job guards, stopped proofs and retained lifecycle rows are preserved.
CREATE OR REPLACE FUNCTION private._collect_fence_scheduler_status() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fence$
DECLARE active_jobs bigint:=0;queued bigint:=0;awaiting bigint:=0;unconfirmed bigint:=0;reviewed bigint:=0;unproven bigint:=0;
 extra_awaiting bigint:=0;extra_unconfirmed bigint:=0;extra_reviewed bigint:=0;extra_unproven bigint:=0;orphan_unproven bigint:=0;
 missing_guards bigint:=0;guard_count bigint:=0;unexpected_functions bigint:=0;email_function_count bigint:=0;main_function_count bigint:=0;
 ops_exists boolean:=to_regnamespace('collect_ops')IS NOT NULL;has_config boolean:=to_regclass('collect_ops.jobs_config')IS NOT NULL;
 has_dispatch boolean:=to_regclass('collect_ops.jobs_dispatches')IS NOT NULL;has_email_config boolean:=to_regclass('collect_ops.email_config')IS NOT NULL;
 has_email_dispatch boolean:=to_regclass('collect_ops.email_dispatches')IS NOT NULL;coverage boolean:=true;owner_oid oid;google_present boolean;
 email_routines jsonb:='__EMAIL_ROUTINE_MANIFEST__'::jsonb;main_routines jsonb:='__MAIN_ROUTINE_MANIFEST__'::jsonb;
 expected_columns text[];observed_columns text[];relation_name text;
BEGIN
 SELECT relowner INTO owner_oid FROM pg_class WHERE oid='private.collect_fence_control'::regclass;
 -- Counts only: Vault plaintext and native HTTP headers/bodies are never read.
 IF to_regclass('cron.job')IS NOT NULL THEN
  EXECUTE $q$SELECT count(*)FROM cron.job WHERE jobname IN('collect-jobs-maintenance-v1','collect-google-ciphertext-expiry-v1','collect-email-delivery-v1')AND active$q$ INTO active_jobs;
 END IF;
 IF to_regclass('net.http_request_queue')IS NOT NULL THEN EXECUTE 'SELECT count(*)FROM net.http_request_queue' INTO queued;END IF;
 IF has_config IS DISTINCT FROM has_dispatch OR has_email_config IS DISTINCT FROM has_email_dispatch THEN coverage:=false;END IF;
 IF has_dispatch THEN
  EXECUTE $q$SELECT count(*)FILTER(WHERE state='awaiting'),count(*)FILTER(WHERE state='unconfirmed'),count(*)FILTER(WHERE state='reviewed_unknown'),
   count(*)FILTER(WHERE state IN('awaiting','unconfirmed','reviewed_unknown')AND NOT EXISTS(
    SELECT 1 FROM private.collect_fence_scheduler_lifecycle p WHERE p.dispatch_id=d.id AND p.native_epoch=d.native_epoch))
   FROM collect_ops.jobs_dispatches d$q$ INTO awaiting,unconfirmed,reviewed,unproven;
 END IF;
 SELECT count(*),count(*)FILTER(WHERE strpos(p.prosrc,E'BEGIN\n -- collect_fence_sql2_write_guard_v1\n PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);')=0
  OR p.prosecdef OR p.proowner<>owner_oid)
 INTO guard_count,missing_guards FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='collect_ops'AND(p.proname,p.proargtypes::text)IN(('cleanup_google_expired',''),('record_jobs_readiness','3802'),('reconcile_jobs',''),('dispatch_jobs','25 2950'),('activate_jobs','25'),('review_unknown_jobs','2950 25'),('tick_jobs',''));
 SELECT count(*)INTO unexpected_functions FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='collect_ops'AND(p.prokind<>'f'OR p.proowner<>owner_oid OR
  ((p.proname,p.proargtypes::text)NOT IN(('cleanup_google_expired',''),('record_jobs_readiness','3802'),('reconcile_jobs',''),('dispatch_jobs','25 2950'),('activate_jobs','25'),('review_unknown_jobs','2950 25'),('tick_jobs',''),('native_jobs_epoch',''),('jobs_state',''),('pause_jobs',''))
   AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(email_routines)m WHERE m->>'name'=p.proname AND m->>'arguments'=p.proargtypes::text))
  OR EXISTS(SELECT 1 FROM aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a WHERE a.grantee<>p.proowner AND a.privilege_type='EXECUTE')
  OR EXISTS(SELECT 1 FROM pg_roles r WHERE r.rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer','collect_sms_runtime')AND has_function_privilege(r.oid,p.oid,'EXECUTE')));
 IF has_dispatch AND guard_count NOT IN(6,7)THEN coverage:=false;END IF;
 IF NOT has_dispatch AND ops_exists AND guard_count<>1 AND NOT(has_email_dispatch AND guard_count=0)THEN coverage:=false;END IF;
 -- The legacy prefix still proves the original fence guard is retained.
 -- It is not a complete source identity: attest every main routine/helper
 -- body, signature and execution property as well as the closed ACL above.
 SELECT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='collect_ops'AND p.proname='cleanup_google_expired')INTO google_present;
 SELECT count(*)INTO main_function_count FROM jsonb_array_elements(main_routines)m
  JOIN pg_namespace n ON n.nspname='collect_ops'
  JOIN pg_proc p ON p.pronamespace=n.oid AND p.proname=m->>'name'AND p.proargtypes::text=m->>'arguments'
  JOIN pg_language l ON l.oid=p.prolang
  WHERE p.prokind='f'AND NOT p.prosecdef AND NOT p.proretset AND NOT p.proleakproof AND NOT p.proisstrict AND p.provariadic=0
   AND p.pronargdefaults=0 AND p.proargdefaults IS NULL AND p.proallargtypes IS NULL AND p.proargmodes IS NULL
   AND p.proparallel='u'AND p.prosupport=0
   AND p.proowner=owner_oid AND l.lanname=m->>'language'AND p.provolatile::text=m->>'volatility'
   AND p.prorettype::text=m->>'return_type'AND coalesce(to_jsonb(p.proargnames),'[]'::jsonb)=m->'argument_names'
   AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=m->>'body_sha256';
 IF jsonb_array_length(main_routines)<>10 OR main_function_count<>
   (CASE WHEN has_dispatch THEN 9 ELSE 0 END+CASE WHEN google_present THEN 1 ELSE 0 END)THEN coverage:=false;END IF;
 IF has_email_dispatch THEN
  PERFORM private.collect_assert_deployment('__PROFILE_SHA256__');
  SELECT count(*)INTO email_function_count FROM jsonb_array_elements(email_routines)m
   JOIN pg_namespace n ON n.nspname='collect_ops'
   JOIN pg_proc p ON p.pronamespace=n.oid AND p.proname=m->>'name'AND p.proargtypes::text=m->>'arguments'
   JOIN pg_language l ON l.oid=p.prolang
   WHERE p.prokind='f'AND NOT p.prosecdef AND NOT p.proretset AND NOT p.proleakproof AND NOT p.proisstrict AND p.provariadic=0
    AND p.pronargdefaults=0 AND p.proargdefaults IS NULL AND p.proallargtypes IS NULL AND p.proargmodes IS NULL
    AND p.proparallel='u'AND p.prosupport=0
    AND p.proowner=owner_oid AND l.lanname=m->>'language'AND p.provolatile::text=m->>'volatility'
    AND p.prorettype::text=m->>'return_type'AND coalesce(to_jsonb(p.proargnames),'[]'::jsonb)=m->'argument_names'
    AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=m->>'body_sha256';
  IF email_function_count<>9 OR jsonb_array_length(email_routines)<>9 THEN coverage:=false;END IF;
  FOREACH relation_name IN ARRAY ARRAY['email_config','email_dispatches']LOOP
   expected_columns:=CASE relation_name WHEN 'email_config'THEN ARRAY['singleton','profile_sha256','endpoint','vault_name','config_sha256','template_sha256','enabled','cron_job_id','readiness','last_probe_id','created_at']
    ELSE ARRAY['id','kind','slot','created_at','native_epoch','net_request_id','readiness_sha256','vault_secret_id','vault_updated_at','email_admission','state','reason','http_status','response_sha256','observed_at','review_evidence_sha256']END;
   SELECT array_agg(a.attname::text ORDER BY a.attnum)INTO observed_columns FROM pg_attribute a
    WHERE a.attrelid=to_regclass('collect_ops.'||relation_name)AND a.attnum>0 AND NOT a.attisdropped;
   IF observed_columns IS DISTINCT FROM expected_columns OR NOT EXISTS(SELECT 1 FROM pg_class c
     WHERE c.oid=to_regclass('collect_ops.'||relation_name)AND c.relkind='r'AND c.relpersistence='p'AND c.relowner=owner_oid AND c.relrowsecurity)
    OR EXISTS(SELECT 1 FROM pg_class c CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('r',c.relowner)))a
     WHERE c.oid=to_regclass('collect_ops.'||relation_name)AND a.grantee<>c.relowner)
    OR EXISTS(SELECT 1 FROM pg_roles r WHERE r.rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer','collect_sms_runtime')
     AND has_table_privilege(r.oid,to_regclass('collect_ops.'||relation_name),'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))THEN coverage:=false;END IF;
  END LOOP;
  IF NOT EXISTS(SELECT 1 FROM collect_ops.email_config c JOIN cron.job j ON j.jobid=c.cron_job_id
    WHERE c.singleton AND c.profile_sha256='__PROFILE_SHA256__'AND c.endpoint='__ENDPOINT__'AND c.vault_name='collect_email_job_token_v1'
    AND c.config_sha256='__CONFIG_SHA256__'AND c.template_sha256='__TEMPLATE_SHA256__'
    AND j.jobname='collect-email-delivery-v1'AND j.schedule='*/5 * * * *'AND j.command='SELECT collect_ops.tick_email();'
    AND j.database=current_database()AND j.username=pg_get_userbyid(owner_oid)AND j.active=c.enabled
    AND(NOT c.enabled OR c.readiness->>'source_sha256'=(SELECT source_sha256 FROM private.collect_fence_control WHERE singleton)))
   OR EXISTS(SELECT 1 FROM pg_roles r WHERE r.rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer','collect_sms_runtime')
    AND has_schema_privilege(r.oid,'collect_ops','USAGE'))THEN coverage:=false;END IF;
  SELECT count(*)FILTER(WHERE state='awaiting'),count(*)FILTER(WHERE state='unconfirmed'),count(*)FILTER(WHERE state='reviewed_unknown'),
   count(*)FILTER(WHERE state IN('awaiting','unconfirmed','reviewed_unknown')AND NOT EXISTS(
    SELECT 1 FROM private.collect_fence_scheduler_lifecycle p WHERE p.dispatch_id=d.id AND p.native_epoch=d.native_epoch))
   INTO extra_awaiting,extra_unconfirmed,extra_reviewed,extra_unproven FROM collect_ops.email_dispatches d;
  -- The application journal also retains lost outer-claim/finish replies.
  -- A reviewed-unknown label alone never proves the local request lifecycle.
  IF to_regclass('app.notification_email_job_dispatches')IS NULL THEN coverage:=false;
  ELSE
   SELECT count(*)INTO orphan_unproven FROM app.notification_email_job_dispatches a
   WHERE(a.state IN('claimed','unknown')OR(a.state='completed'AND a.result_json::jsonb->'results'@>'[{"state":"unknown"}]'::jsonb))
    AND NOT EXISTS(SELECT 1 FROM collect_ops.email_dispatches d WHERE d.id::text=a.id AND d.email_admission=a.admission_json::jsonb AND d.state IN('awaiting','unconfirmed','reviewed_unknown'))
    AND NOT EXISTS(SELECT 1 FROM collect_ops.email_dispatches d JOIN private.collect_fence_scheduler_lifecycle p ON p.dispatch_id=d.id AND p.native_epoch=d.native_epoch
     WHERE d.id::text=a.id AND d.email_admission=a.admission_json::jsonb);
  END IF;
  awaiting:=awaiting+extra_awaiting;unconfirmed:=unconfirmed+extra_unconfirmed;reviewed:=reviewed+extra_reviewed;unproven:=unproven+extra_unproven+orphan_unproven;
 ELSIF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='collect_ops'AND EXISTS(
  SELECT 1 FROM jsonb_array_elements(email_routines)m WHERE m->>'name'=p.proname))THEN coverage:=false;
 END IF;
 coverage:=coverage AND missing_guards=0 AND unexpected_functions=0;
 RETURN jsonb_build_object('checked',true,'coverageVerified',coverage,'namedActiveJobs',active_jobs,'pendingNativeRequests',queued,
  'awaitingDispatches',awaiting,'unconfirmedDispatches',unconfirmed,'reviewedUnknownDispatches',reviewed,'lifecycleUnproven',unproven,
  'blocking',NOT coverage OR active_jobs>0 OR queued>0 OR unproven>0);
EXCEPTION WHEN OTHERS THEN
 RETURN jsonb_build_object('checked',false,'coverageVerified',false,'namedActiveJobs',0,'pendingNativeRequests',0,
  'awaitingDispatches',0,'unconfirmedDispatches',0,'reviewedUnknownDispatches',0,'lifecycleUnproven',0,'blocking',true);
END;$fence$;
REVOKE ALL ON FUNCTION private._collect_fence_scheduler_status() FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer,collect_sms_runtime;
COMMIT;
