--- canonical/scripts/sql/collect_inactive_restore_overlay.sql
+++ proposed/scripts/sql/collect_inactive_restore_overlay.sql
@@ -0,0 +1,229 @@
+-- Offline isolated restore only. Owner transaction; no public mutation API.
+BEGIN ISOLATION LEVEL READ COMMITTED;
+SET LOCAL search_path = pg_catalog;
+SET LOCAL timezone = 'UTC';
+SET LOCAL standard_conforming_strings = 'on';
+SET LOCAL lock_timeout = '200ms';
+SET LOCAL statement_timeout = '30s';
+CREATE TEMP TABLE collect_stop_input(document jsonb NOT NULL) ON COMMIT DROP;
+INSERT INTO collect_stop_input VALUES (__CONTEXT__::jsonb);
+DO $stop$
+DECLARE c jsonb; expected jsonb:=__CATALOG__::jsonb; actual jsonb; old_stop jsonb; gate_key text; item record;
+ at timestamptz:=clock_timestamp(); deadline timestamptz; created boolean:=false; n integer; v_prior jsonb; v_after jsonb;
+ relation text; predicate text; capsule_hash text; delta jsonb; result jsonb;
+BEGIN
+ SELECT document INTO STRICT c FROM pg_temp.collect_stop_input;
+ deadline:=(c->>'expires_at')::timestamptz;
+ IF session_user<>'postgres' OR current_user<>'postgres' OR current_setting('role') NOT IN('none','postgres')
+  OR NOT EXISTS(SELECT 1 FROM pg_roles r WHERE r.rolname=session_user AND NOT r.rolsuper)
+  OR current_setting('transaction_isolation')<>'read committed' OR current_database()<>'postgres'
+  OR current_setting('collect.recovery_drill',true) IS DISTINCT FROM 'production-archive-v1'
+  OR current_setting('cron.launch_active_jobs')<>'off' OR current_setting('listen_addresses')<>''
+  OR current_setting('pg_net.database_name')<>'template1' OR current_setting('pg_net.batch_size')<>'0'
+  OR nullif(current_setting('request.jwt.claims',true),'') IS NOT NULL
+  OR nullif(current_setting('request.jwt.claim.sub',true),'') IS NOT NULL
+  OR nullif(current_setting('request.jwt.claim.role',true),'') IS NOT NULL
+  OR nullif(current_setting('collect.runtime_control_context',true),'') IS NOT NULL THEN
+  RAISE EXCEPTION 'restore_stop_owner_isolation_required' USING ERRCODE='42501'; END IF;
+ IF deadline<=at OR deadline>at+interval '120 seconds' OR NOT isfinite(deadline)
+  OR (SELECT array_agg(k ORDER BY k)FROM jsonb_object_keys(c)k) IS DISTINCT FROM
+  ARRAY['archive_sha256','comparison_sha256','expires_at','format','reason','restore_id','source_catalog_sha256','source_contract_sha256','source_vector_sha256','sql_sha256','target','tools_sha256']::text[]
+  OR c->>'format'<>'collect-inactive-restore-input-v1' OR c->>'restore_id'!~'^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
+  OR c->>'target'!~'^collect-recovery-[a-z0-9-]{8,80}$' OR char_length(btrim(c->>'reason')) NOT BETWEEN 8 AND 500 THEN
+  RAISE EXCEPTION 'restore_stop_input_invalid' USING ERRCODE='22023'; END IF;
+ FOREACH gate_key IN ARRAY ARRAY['format','restore_id','target','reason','expires_at'] LOOP
+  IF jsonb_typeof(c->gate_key) IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'restore_stop_string_invalid' USING ERRCODE='22023'; END IF;
+ END LOOP;
+ IF c->>'reason' IS DISTINCT FROM btrim(c->>'reason') OR c->>'reason'~'[[:cntrl:]]' THEN RAISE EXCEPTION 'restore_stop_reason_invalid' USING ERRCODE='22023'; END IF;
+ FOREACH gate_key IN ARRAY ARRAY['archive_sha256','comparison_sha256','source_catalog_sha256','source_contract_sha256','source_vector_sha256','sql_sha256','tools_sha256'] LOOP
+  IF jsonb_typeof(c->gate_key)<>'string' OR c->>gate_key!~'^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'restore_stop_digest_invalid' USING ERRCODE='22023'; END IF;
+ END LOOP;
+ FOREACH gate_key IN ARRAY ARRAY['collect-recovery-stop:'||(c->>'restore_id'),'collect_admin_combined_roster','collect-receipt-trusted-worker',
+  'collect-receipt-history-maintenance','collect-ops-workflow','collect-receipt-telemetry-sampler'] LOOP
+  IF NOT pg_try_advisory_xact_lock(hashtext(gate_key)) THEN RAISE EXCEPTION 'restore_stop_busy' USING ERRCODE='55P03'; END IF;
+ END LOOP;
+ IF EXISTS(SELECT 1 FROM pg_class WHERE oid IN('collect_supervisor.identities'::regclass,'collect_gateway.devices'::regclass)
+  AND relowner<>(SELECT oid FROM pg_roles WHERE rolname='postgres')) THEN RAISE EXCEPTION 'restore_stop_table_owner_invalid' USING ERRCODE='42501'; END IF;
+ LOCK TABLE collect_supervisor.identities IN SHARE ROW EXCLUSIVE MODE NOWAIT;
+ LOCK TABLE collect_gateway.devices IN SHARE ROW EXCLUSIVE MODE NOWAIT;
+ PERFORM 1 FROM collect_receipt_operations.policy WHERE singleton FOR UPDATE NOWAIT;
+ PERFORM 1 FROM collect_receipt_operations.fence WHERE singleton FOR UPDATE NOWAIT;
+ PERFORM 1 FROM collect_receipt_successors.configuration WHERE singleton FOR UPDATE NOWAIT;
+ PERFORM 1 FROM collect_ops.receipt_worker_configuration WHERE singleton FOR UPDATE NOWAIT;
+ PERFORM 1 FROM collect_receipt_worker_history.configuration WHERE singleton FOR UPDATE NOWAIT;
+ PERFORM 1 FROM collect_receipt_telemetry.configuration WHERE singleton FOR UPDATE NOWAIT;
+ SELECT to_jsonb(f) INTO STRICT v_prior FROM public.feature_flags f WHERE key='hybrid_sms_notifications' FOR UPDATE NOWAIT;
+ PERFORM 1 FROM collect_security.runtime_control_heads h WHERE family='feature_flags'
+  AND identity=collect_security.runtime_control_identity('feature_flags',v_prior) FOR UPDATE NOWAIT;
+ IF NOT FOUND THEN RAISE EXCEPTION 'restore_stop_flag_head_missing' USING ERRCODE='55000'; END IF;
+ -- The unchanged original catalog is compared inside the owner transaction.
+ -- Only the separately verified target capsule is omitted on original-UUID replay.
+ SELECT (__SOURCE_QUERY__)::jsonb INTO actual;
+ IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'restore_stop_source_catalog_changed' USING ERRCODE='55000'; END IF;
+ IF NOT has_function_privilege(current_user,'cron.alter_job(bigint,text,text,text,text,boolean)','EXECUTE') THEN
+  RAISE EXCEPTION 'restore_stop_cron_execute_required' USING ERRCODE='42501'; END IF;
+ SELECT count(*)INTO n FROM(SELECT id FROM collect_supervisor.identities ORDER BY id LIMIT 1001)s;
+ IF n>1000 THEN RAISE EXCEPTION 'restore_stop_identity_cap' USING ERRCODE='54000'; END IF;
+ SELECT count(*)INTO n FROM(SELECT id FROM collect_gateway.devices ORDER BY id LIMIT 1001)s;
+ IF n>1000 THEN RAISE EXCEPTION 'restore_stop_device_cap' USING ERRCODE='54000'; END IF;
+ SELECT count(*)INTO n FROM(SELECT jobid FROM cron.job WHERE jobname IN('collect-receipt-exceptions','collect-receipt-history-maintenance')ORDER BY jobname,jobid LIMIT 3)s;
+ IF n>2 OR EXISTS(SELECT 1 FROM cron.job WHERE jobname IN('collect-receipt-exceptions','collect-receipt-history-maintenance')
+  AND(username<>'postgres' OR database<>'postgres' OR command IS DISTINCT FROM CASE jobname
+  WHEN'collect-receipt-exceptions'THEN'select collect_ops.run_receipt_exception_schedule();'
+  ELSE'select collect_receipt_worker_history.run_schedule();'END))
+  OR EXISTS(SELECT 1 FROM cron.job WHERE jobname IN('collect-receipt-exceptions','collect-receipt-history-maintenance')GROUP BY jobname HAVING count(*)>1) THEN
+  RAISE EXCEPTION 'restore_stop_cron_vector_invalid' USING ERRCODE='55000'; END IF;
+ IF NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname='collect_recovery_restore') THEN
+  created:=true;
+  CREATE SCHEMA collect_recovery_restore AUTHORIZATION postgres;
+  REVOKE ALL ON SCHEMA collect_recovery_restore FROM PUBLIC,anon,authenticated,service_role;
+  CREATE TABLE collect_recovery_restore.stops(
+   restore_id uuid PRIMARY KEY,input jsonb NOT NULL,recorded_at timestamptz NOT NULL CHECK(isfinite(recorded_at)),
+   capsule_catalog_sha256 text NOT NULL CHECK(capsule_catalog_sha256~'^[0-9a-f]{64}$'),
+   delta_sha256 text NOT NULL CHECK(delta_sha256~'^[0-9a-f]{64}$'),item_count integer NOT NULL CHECK(item_count BETWEEN 10 AND 2013),
+   reason_sha256 text NOT NULL CHECK(reason_sha256~'^[0-9a-f]{64}$'),session_owner text NOT NULL CHECK(session_owner='postgres'),
+   effective_owner text NOT NULL CHECK(effective_owner='postgres'),resume_required boolean NOT NULL CHECK(resume_required),
+   financial_action boolean NOT NULL CHECK(NOT financial_action),send_action boolean NOT NULL CHECK(NOT send_action));
+  CREATE TABLE collect_recovery_restore.stop_items(
+   restore_id uuid NOT NULL REFERENCES collect_recovery_restore.stops DEFERRABLE INITIALLY DEFERRED,
+   family text NOT NULL CHECK(family IN('policy','fence','successor_configuration','worker_configuration','history_configuration','telemetry_configuration',
+    'feature_flag','runtime_head','supervisor_identity','gateway_device','cron_job','new_worker_configuration_history','new_worker_configuration_binding','new_flag_realtime_event')),
+   original_key text NOT NULL,prior_sha256 text,after_sha256 text NOT NULL CHECK(after_sha256~'^[0-9a-f]{64}$'),
+   prior_metadata jsonb,after_metadata jsonb NOT NULL,PRIMARY KEY(restore_id,family,original_key),
+   CHECK(prior_sha256 IS NULL OR prior_sha256~'^[0-9a-f]{64}$'),CHECK(octet_length(after_metadata::text)<=65536));
+  EXECUTE $definition$
+   CREATE FUNCTION collect_recovery_restore.protect() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $guard$
+BEGIN
+ IF TG_OP<>'INSERT' OR session_user<>'postgres' OR current_user<>'postgres' OR current_setting('role') NOT IN('none','postgres')
+  OR current_setting('collect.recovery_drill',true) IS DISTINCT FROM 'production-archive-v1'
+  OR nullif(current_setting('request.jwt.claims',true),'') IS NOT NULL THEN
+  RAISE EXCEPTION 'restore_stop_evidence_immutable' USING ERRCODE='42501'; END IF;
+ RETURN NEW;
+END
+$guard$ $definition$;
+  CREATE TRIGGER stop_owner_insert BEFORE INSERT OR UPDATE OR DELETE ON collect_recovery_restore.stops FOR EACH ROW EXECUTE FUNCTION collect_recovery_restore.protect();
+  CREATE TRIGGER stop_owner_truncate BEFORE TRUNCATE ON collect_recovery_restore.stops FOR EACH STATEMENT EXECUTE FUNCTION collect_recovery_restore.protect();
+  CREATE TRIGGER stop_items_owner_insert BEFORE INSERT OR UPDATE OR DELETE ON collect_recovery_restore.stop_items FOR EACH ROW EXECUTE FUNCTION collect_recovery_restore.protect();
+  CREATE TRIGGER stop_items_owner_truncate BEFORE TRUNCATE ON collect_recovery_restore.stop_items FOR EACH STATEMENT EXECUTE FUNCTION collect_recovery_restore.protect();
+  ALTER TABLE collect_recovery_restore.stops ENABLE ROW LEVEL SECURITY;
+  ALTER TABLE collect_recovery_restore.stop_items ENABLE ROW LEVEL SECURITY;
+  REVOKE ALL ON ALL TABLES IN SCHEMA collect_recovery_restore FROM PUBLIC,anon,authenticated,service_role;
+  REVOKE ALL ON ALL FUNCTIONS IN SCHEMA collect_recovery_restore FROM PUBLIC,anon,authenticated,service_role;
+ END IF;
+ IF (SELECT count(*)FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='collect_recovery_restore'AND t.relkind='r')<>2
+  OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='collect_recovery_restore'AND p.proname='protect'
+   AND NOT p.prosecdef AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='__GUARD_HASH__')
+  OR EXISTS(SELECT 1 FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname='collect_recovery_restore'
+   AND(t.relowner<>(SELECT oid FROM pg_roles WHERE rolname='postgres')OR(t.relkind='r'AND NOT t.relrowsecurity)))
+  OR EXISTS(SELECT 1 FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner)))a WHERE n.nspname='collect_recovery_restore'AND a.grantee<>n.nspowner) THEN
+  RAISE EXCEPTION 'restore_stop_capsule_invalid' USING ERRCODE='55000'; END IF;
+ -- Exact private capsule definition, including namespace, type modifiers, collation and actual index metadata.
+ SELECT encode(sha256(convert_to(jsonb_build_object(
+  'namespace',(SELECT jsonb_build_array(nspname,pg_get_userbyid(nspowner),nspacl)FROM pg_namespace WHERE oid='collect_recovery_restore'::regnamespace),
+  'relations',(SELECT jsonb_agg(jsonb_build_array(t.relname,t.relkind,t.relpersistence,pg_get_userbyid(t.relowner),t.relacl,t.relrowsecurity,t.relforcerowsecurity)ORDER BY t.relname)FROM pg_class t WHERE relnamespace='collect_recovery_restore'::regnamespace),
+  'columns',(SELECT jsonb_agg(jsonb_build_array(c.relname,a.attname,a.atttypid::regtype::text,a.atttypmod,a.attcollation,CASE WHEN a.attcollation=0 THEN NULL ELSE a.attcollation::regcollation::text END,a.attnotnull,a.attnum,a.attidentity,a.attgenerated,a.attacl,a.atthasdef,pg_get_expr(d.adbin,d.adrelid))ORDER BY c.relname,a.attnum)FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum WHERE c.relnamespace='collect_recovery_restore'::regnamespace AND a.attnum>0 AND NOT a.attisdropped),
+  'constraints',(SELECT jsonb_agg(jsonb_build_array(conname,pg_get_constraintdef(oid))ORDER BY conname)FROM pg_constraint WHERE connamespace='collect_recovery_restore'::regnamespace),
+  'indexes',(SELECT jsonb_agg(jsonb_build_array(c.relname,pg_get_indexdef(c.oid),c.reloptions,c.reltablespace,am.amname,to_jsonb(i)-'indexrelid'-'indrelid')ORDER BY c.relname)FROM pg_class c JOIN pg_index i ON i.indexrelid=c.oid JOIN pg_am am ON am.oid=c.relam WHERE c.relnamespace='collect_recovery_restore'::regnamespace),
+  'triggers',(SELECT jsonb_agg(jsonb_build_array(c.relname,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid))ORDER BY c.relname,t.tgname)FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relnamespace='collect_recovery_restore'::regnamespace AND NOT t.tgisinternal),
+  'policies',(SELECT jsonb_agg(jsonb_build_array(c.relname,p.polname,p.polcmd,p.polpermissive,(SELECT array_agg(CASE WHEN u.role_id=0 THEN'PUBLIC'ELSE pg_get_userbyid(u.role_id)END ORDER BY u.role_id)FROM unnest(p.polroles)u(role_id)),pg_get_expr(p.polqual,p.polrelid),pg_get_expr(p.polwithcheck,p.polrelid))ORDER BY c.relname,p.polname)FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid WHERE c.relnamespace='collect_recovery_restore'::regnamespace),
+  'functions',(SELECT jsonb_agg(jsonb_build_array(p.proname,pg_get_userbyid(p.proowner),pg_get_functiondef(p.oid),p.proconfig,p.proacl)ORDER BY p.proname)FROM pg_proc p WHERE pronamespace='collect_recovery_restore'::regnamespace))::text,'UTF8')),'hex')INTO capsule_hash;
+ CREATE TEMP TABLE collect_stop_delta(family text,original_key text,prior jsonb,after_row jsonb)ON COMMIT DROP;
+ INSERT INTO collect_stop_delta SELECT'policy','singleton',to_jsonb(t),NULL FROM collect_receipt_operations.policy t WHERE singleton;
+ INSERT INTO collect_stop_delta SELECT'fence','singleton',to_jsonb(t),NULL FROM collect_receipt_operations.fence t WHERE singleton;
+ INSERT INTO collect_stop_delta SELECT'successor_configuration','singleton',to_jsonb(t),NULL FROM collect_receipt_successors.configuration t WHERE singleton;
+ INSERT INTO collect_stop_delta SELECT'worker_configuration','singleton',to_jsonb(t),NULL FROM collect_ops.receipt_worker_configuration t WHERE singleton;
+ INSERT INTO collect_stop_delta SELECT'history_configuration','singleton',to_jsonb(t),NULL FROM collect_receipt_worker_history.configuration t WHERE singleton;
+ INSERT INTO collect_stop_delta SELECT'telemetry_configuration','singleton',to_jsonb(t),NULL FROM collect_receipt_telemetry.configuration t WHERE singleton;
+ INSERT INTO collect_stop_delta SELECT'feature_flag','hybrid_sms_notifications',to_jsonb(t),NULL FROM public.feature_flags t WHERE key='hybrid_sms_notifications';
+ INSERT INTO collect_stop_delta SELECT'runtime_head','hybrid_sms_notifications',to_jsonb(t),NULL FROM collect_security.runtime_control_heads t WHERE family='feature_flags'AND identity=collect_security.runtime_control_identity('feature_flags',v_prior);
+ INSERT INTO collect_stop_delta SELECT'supervisor_identity',id::text,to_jsonb(t),NULL FROM collect_supervisor.identities t;
+ INSERT INTO collect_stop_delta SELECT'gateway_device',id::text,to_jsonb(t),NULL FROM collect_gateway.devices t;
+ INSERT INTO collect_stop_delta SELECT'cron_job',jobid::text,to_jsonb(t),NULL FROM cron.job t WHERE jobname IN('collect-receipt-exceptions','collect-receipt-history-maintenance');
+ IF (SELECT count(*)FROM collect_stop_delta WHERE family IN('policy','fence','successor_configuration','worker_configuration','history_configuration','telemetry_configuration','feature_flag','runtime_head'))<>8 THEN
+  RAISE EXCEPTION 'restore_stop_singleton_missing' USING ERRCODE='55000'; END IF;
+ SELECT to_jsonb(s)INTO old_stop FROM collect_recovery_restore.stops s WHERE restore_id=(c->>'restore_id')::uuid;
+ IF old_stop IS NOT NULL THEN
+  IF (old_stop->'input')-'expires_at' IS DISTINCT FROM c-'expires_at' OR old_stop->>'capsule_catalog_sha256'<>capsule_hash THEN
+   RAISE EXCEPTION 'restore_stop_replay_conflict' USING ERRCODE='55000'; END IF;
+  IF (SELECT count(*)FROM collect_stop_delta)<>(old_stop->>'item_count')::integer-(SELECT count(*)FROM collect_recovery_restore.stop_items WHERE restore_id=(c->>'restore_id')::uuid AND family IN('new_worker_configuration_history','new_worker_configuration_binding','new_flag_realtime_event'))
+   OR EXISTS(SELECT 1 FROM collect_stop_delta d LEFT JOIN collect_recovery_restore.stop_items i ON i.restore_id=(c->>'restore_id')::uuid AND i.family=d.family AND i.original_key=d.original_key
+    WHERE i.original_key IS NULL OR i.after_sha256<>encode(sha256(convert_to(d.prior::text,'UTF8')),'hex'))
+ THEN
+   RAISE EXCEPTION 'restore_stop_replay_state_changed' USING ERRCODE='55000'; END IF;
+  FOR item IN SELECT *FROM collect_recovery_restore.stop_items WHERE restore_id=(c->>'restore_id')::uuid AND family IN('new_worker_configuration_history','new_worker_configuration_binding','new_flag_realtime_event') LOOP
+   CASE item.family
+    WHEN 'new_worker_configuration_history' THEN SELECT to_jsonb(h)INTO v_after FROM collect_ops.receipt_worker_configuration_history h WHERE revision=item.original_key::bigint;
+    WHEN 'new_worker_configuration_binding' THEN SELECT to_jsonb(b)INTO v_after FROM collect_receipt_worker_history.bindings b WHERE family='worker_configuration'AND original_key=item.original_key;
+    WHEN 'new_flag_realtime_event' THEN SELECT to_jsonb(e)INTO v_after FROM public.app_realtime_events e WHERE id=item.original_key::uuid;
+   END CASE;
+   IF v_after IS NULL OR encode(sha256(convert_to(v_after::text,'UTF8')),'hex')IS DISTINCT FROM item.after_sha256 THEN RAISE EXCEPTION 'restore_stop_replay_derived_changed' USING ERRCODE='55000'; END IF;
+  END LOOP;
+  SELECT jsonb_agg(jsonb_build_array(family,original_key,prior_sha256,after_sha256)ORDER BY family,original_key)INTO delta FROM collect_recovery_restore.stop_items WHERE restore_id=(c->>'restore_id')::uuid;
+  IF encode(sha256(convert_to(delta::text,'UTF8')),'hex')IS DISTINCT FROM old_stop->>'delta_sha256'OR jsonb_array_length(delta)<>(old_stop->>'item_count')::integer THEN RAISE EXCEPTION 'restore_stop_replay_delta_changed' USING ERRCODE='55000'; END IF;
+ ELSE
+  IF NOT created OR EXISTS(SELECT 1 FROM collect_recovery_restore.stops)THEN RAISE EXCEPTION 'restore_stop_target_already_bound' USING ERRCODE='55000'; END IF;
+  IF EXISTS(SELECT 1 FROM collect_stop_delta WHERE family IN('policy','successor_configuration','worker_configuration','history_configuration','telemetry_configuration')AND(prior->>'revision')::bigint>=1000000000)
+   OR (SELECT value FROM collect_receipt_operations.fence WHERE singleton)>=1000000000 THEN RAISE EXCEPTION 'restore_stop_revision_exhausted' USING ERRCODE='55000'; END IF;
+  UPDATE collect_receipt_operations.policy SET revision=revision+1,mode='Paused',emergency_stop=true,catchup_enabled=false,updated_at=at,updated_by=NULL WHERE singleton;
+  UPDATE collect_receipt_operations.fence SET value=value+1 WHERE singleton;
+  UPDATE collect_receipt_successors.configuration SET revision=revision+1,enabled=false WHERE singleton;
+  UPDATE collect_ops.receipt_worker_configuration SET revision=revision+1,enabled=false,updated_at=at WHERE singleton;
+  INSERT INTO collect_ops.receipt_worker_configuration_history SELECT revision,to_jsonb(t)-'singleton',at FROM collect_ops.receipt_worker_configuration t WHERE singleton;
+  INSERT INTO collect_stop_delta SELECT'new_worker_configuration_history',revision::text,NULL,to_jsonb(h)FROM collect_ops.receipt_worker_configuration_history h WHERE revision=(SELECT revision FROM collect_ops.receipt_worker_configuration WHERE singleton);
+  INSERT INTO collect_stop_delta SELECT'new_worker_configuration_binding',b.original_key,NULL,to_jsonb(b)FROM collect_receipt_worker_history.bindings b WHERE family='worker_configuration'AND original_key=(SELECT revision::text FROM collect_ops.receipt_worker_configuration WHERE singleton);
+  UPDATE collect_receipt_worker_history.configuration SET revision=revision+1,enabled=false,updated_at=at WHERE singleton;
+  UPDATE collect_receipt_telemetry.configuration SET revision=revision+1,enabled=false,updated_at=at,updated_by=NULL WHERE singleton;
+  UPDATE public.feature_flags SET enabled=false WHERE key='hybrid_sms_notifications'AND enabled;
+  GET DIAGNOSTICS n=ROW_COUNT;
+  IF n=1 THEN
+   INSERT INTO collect_stop_delta SELECT'new_flag_realtime_event',id::text,NULL,to_jsonb(e)FROM public.app_realtime_events e
+    WHERE area='feature_flags'AND xmin=((pg_current_xact_id()::text::numeric%4294967296)::bigint::text)::xid LIMIT 2;
+   IF(SELECT count(*)FROM collect_stop_delta WHERE family='new_flag_realtime_event')<>1 THEN RAISE EXCEPTION 'restore_stop_invalidation_binding_invalid' USING ERRCODE='55000'; END IF;
+  END IF;
+  IF(SELECT count(*)FROM collect_stop_delta WHERE family='new_worker_configuration_binding')<>1 THEN RAISE EXCEPTION 'restore_stop_new_config_binding_invalid' USING ERRCODE='55000'; END IF;
+  UPDATE collect_supervisor.identities SET state='revoked',revoked_at=at WHERE state<>'revoked';
+  UPDATE collect_gateway.devices SET state='revoked',revoked_at=at WHERE state<>'revoked';
+  FOR item IN SELECT jobid FROM cron.job WHERE jobname IN('collect-receipt-exceptions','collect-receipt-history-maintenance')ORDER BY jobid LOOP
+   PERFORM cron.alter_job(item.jobid,active:=false);
+  END LOOP;
+  FOR item IN SELECT *FROM collect_stop_delta WHERE after_row IS NULL LOOP
+   CASE item.family
+    WHEN'policy'THEN relation:='collect_receipt_operations.policy';predicate:='singleton';
+    WHEN'fence'THEN relation:='collect_receipt_operations.fence';predicate:='singleton';
+    WHEN'successor_configuration'THEN relation:='collect_receipt_successors.configuration';predicate:='singleton';
+    WHEN'worker_configuration'THEN relation:='collect_ops.receipt_worker_configuration';predicate:='singleton';
+    WHEN'history_configuration'THEN relation:='collect_receipt_worker_history.configuration';predicate:='singleton';
+    WHEN'telemetry_configuration'THEN relation:='collect_receipt_telemetry.configuration';predicate:='singleton';
+    WHEN'feature_flag'THEN relation:='public.feature_flags';predicate:='key=$1';
+    WHEN'runtime_head'THEN relation:='collect_security.runtime_control_heads';predicate:='family=''feature_flags''AND identity=jsonb_build_object(''key'',$1)';
+    WHEN'supervisor_identity'THEN relation:='collect_supervisor.identities';predicate:='id=$1::uuid';
+    WHEN'gateway_device'THEN relation:='collect_gateway.devices';predicate:='id=$1::uuid';
+    WHEN'cron_job'THEN relation:='cron.job';predicate:='jobid=$1::bigint';
+    ELSE RAISE EXCEPTION 'restore_stop_family_invalid' USING ERRCODE='55000';
+   END CASE;
+   EXECUTE format('SELECT to_jsonb(t)FROM %s t WHERE %s',relation,predicate)INTO STRICT v_after USING item.original_key;
+   UPDATE collect_stop_delta SET after_row=v_after WHERE family=item.family AND original_key=item.original_key;
+  END LOOP;
+  SELECT jsonb_agg(jsonb_build_array(family,original_key,CASE WHEN prior IS NULL THEN NULL ELSE encode(sha256(convert_to(prior::text,'UTF8')),'hex')END,
+   encode(sha256(convert_to(after_row::text,'UTF8')),'hex'))ORDER BY family,original_key)INTO delta FROM collect_stop_delta;
+  INSERT INTO collect_recovery_restore.stop_items SELECT(c->>'restore_id')::uuid,family,original_key,
+   CASE WHEN prior IS NULL THEN NULL ELSE encode(sha256(convert_to(prior::text,'UTF8')),'hex')END,encode(sha256(convert_to(after_row::text,'UTF8')),'hex'),
+   prior-'public_key_spki_base64',after_row-'public_key_spki_base64'FROM collect_stop_delta;
+  INSERT INTO collect_recovery_restore.stops VALUES((c->>'restore_id')::uuid,c,at,capsule_hash,encode(sha256(convert_to(delta::text,'UTF8')),'hex'),
+   jsonb_array_length(delta),encode(sha256(convert_to(c->>'reason','UTF8')),'hex'),session_user,current_user,true,false,false);
+ END IF;
+ SELECT (__SOURCE_QUERY_FINAL__)::jsonb INTO actual;
+ IF actual IS DISTINCT FROM expected THEN RAISE EXCEPTION 'restore_stop_final_catalog_changed' USING ERRCODE='55000'; END IF;
+ IF clock_timestamp()>=deadline OR EXISTS(SELECT 1 FROM collect_receipt_operations.policy WHERE NOT(singleton AND mode='Paused'AND emergency_stop AND NOT catchup_enabled))
+  OR EXISTS(SELECT 1 FROM collect_supervisor.identities WHERE state<>'revoked')OR EXISTS(SELECT 1 FROM collect_gateway.devices WHERE state<>'revoked')
+  OR EXISTS(SELECT 1 FROM public.feature_flags WHERE key='hybrid_sms_notifications'AND enabled)
+  OR EXISTS(SELECT 1 FROM collect_receipt_successors.configuration WHERE enabled)OR EXISTS(SELECT 1 FROM collect_ops.receipt_worker_configuration WHERE enabled)
+  OR EXISTS(SELECT 1 FROM collect_receipt_worker_history.configuration WHERE enabled)OR EXISTS(SELECT 1 FROM collect_receipt_telemetry.configuration WHERE enabled)
+  OR EXISTS(SELECT 1 FROM cron.job WHERE jobname IN('collect-receipt-exceptions','collect-receipt-history-maintenance')AND active)THEN
+  RAISE EXCEPTION 'restore_stop_final_state_invalid' USING ERRCODE='55000'; END IF;
+END
+$stop$;
+SELECT jsonb_build_object('format','collect-inactive-restore-result-v1','restore_id',restore_id,'recorded_at',recorded_at,
+ 'delta_sha256',delta_sha256,'item_count',item_count,'resume_required',resume_required,'financial_action',financial_action,'send_action',send_action,
+ 'session_owner',session_owner,'effective_owner',effective_owner)FROM collect_recovery_restore.stops WHERE restore_id=(SELECT(document->>'restore_id')::uuid FROM pg_temp.collect_stop_input);
+COMMIT;
