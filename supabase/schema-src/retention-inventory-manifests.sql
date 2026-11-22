-- Sealed metadata inspection only. No personal-data erasure, provider request,
-- expiry/pruning or policy approval is introduced by this migration.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SET LOCAL search_path=pg_catalog,pg_temp;
DO $$BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR to_regclass('private.collect_fence_stopped_admissions') IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='retention_manifest_owner_install_required';END IF;
END$$;

-- COMPILED_CATALOG_FUNCTION

CREATE TABLE private.retention_inventory_manifests(
 id uuid PRIMARY KEY, request_id text NOT NULL, subject_id text NOT NULL,
 actor_id text NOT NULL, session_id text NOT NULL, input_sha256 text NOT NULL CHECK(input_sha256~'^[a-f0-9]{64}$'),
 source_sha256 text NOT NULL CHECK(source_sha256~'^[a-f0-9]{64}$'),
 schema_sha256 text NOT NULL CHECK(schema_sha256~'^[a-f0-9]{64}$'),
 schema_identity jsonb NOT NULL, control_identity jsonb NOT NULL,
 descriptor_count bigint NOT NULL CHECK(descriptor_count BETWEEN 1 AND 1000000),
 page_count integer NOT NULL CHECK(page_count BETWEEN 1 AND 10000),
 class_counts jsonb NOT NULL,
 pages_sha256 text NOT NULL CHECK(pages_sha256~'^[a-f0-9]{64}$'),
 manifest_sha256 text NOT NULL CHECK(manifest_sha256~'^[a-f0-9]{64}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.retention_inventory_pages(
 manifest_id uuid NOT NULL REFERENCES private.retention_inventory_manifests(id) DEFERRABLE INITIALLY DEFERRED,
 page_number integer NOT NULL CHECK(page_number BETWEEN 0 AND 9999),
 descriptors jsonb NOT NULL CHECK(octet_length(descriptors::text)<=131072 AND jsonb_typeof(descriptors)='array' AND jsonb_array_length(descriptors) BETWEEN 1 AND 100),
 descriptor_count integer GENERATED ALWAYS AS(jsonb_array_length(descriptors)) STORED,
 page_sha256 text NOT NULL CHECK(page_sha256~'^[a-f0-9]{64}$'),
 PRIMARY KEY(manifest_id,page_number) INCLUDE(page_sha256,descriptor_count),
 CHECK(encode(sha256(convert_to(descriptors::text,'UTF8')),'hex')=page_sha256)
);
CREATE INDEX retention_inventory_subject_created ON private.retention_inventory_manifests(subject_id,created_at DESC,id);
CREATE FUNCTION private._retention_manifest_immutable_v2() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $$BEGIN
 RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='retention_manifest_immutable';END$$;
DO $$DECLARE t text;BEGIN
 FOREACH t IN ARRAY ARRAY['retention_inventory_manifests','retention_inventory_pages'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer',t);
  EXECUTE format('CREATE TRIGGER retention_manifest_immutable BEFORE UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._retention_manifest_immutable_v2()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER retention_manifest_immutable',t);
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',t);
 END LOOP;
END$$;

CREATE FUNCTION private._retention_manifest_schema_v2() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE catalog jsonb:=private._retention_manifest_catalog_v2();r record;expected jsonb;actual jsonb;schema_rows jsonb;helpers jsonb;roles jsonb;memberships jsonb;
 known_auth text[]:=ARRAY['audit_log_entries','custom_oauth_providers','flow_state','identities','instances','mfa_amr_claims','mfa_challenges','mfa_factors','mfa_recovery_code_sets','mfa_recovery_codes','oauth_authorizations','oauth_client_states','oauth_clients','oauth_consents','one_time_tokens','refresh_tokens','saml_providers','saml_relay_states','schema_migrations','scim_tokens','scim_users','sessions','sso_domains','sso_providers','users','webauthn_challenges','webauthn_credentials'];
 known_storage text[]:=ARRAY['buckets','buckets_analytics','buckets_vectors','migrations','objects','s3_multipart_uploads','s3_multipart_uploads_parts','vector_indexes'];
BEGIN
 FOR r IN SELECT n.nspname,c.relname,c.relkind,c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN('app','private','auth','storage','collect_sms') AND c.relkind IN('r','p','v') LOOP
  IF r.nspname='app' AND r.relkind IN('r','p') THEN
   IF catalog->'engine_tables' ? r.relname THEN CONTINUE;END IF;
   expected:=catalog->'application'->r.relname->'columns';
   IF expected IS NULL THEN RAISE EXCEPTION 'retention_manifest_unknown_application_relation' USING ERRCODE='42501';END IF;
   SELECT jsonb_agg(a.attname ORDER BY a.attnum) INTO actual FROM pg_attribute a WHERE a.attrelid=r.oid AND a.attnum>0 AND NOT a.attisdropped;
   -- The entire SQL16 predecessor remains an explicit supported prefix.
   IF r.relname='notification_preferences' AND to_regclass('app.notification_email_deliveries') IS NULL THEN expected:=expected-ARRAY['email_enabled','payment_reminders','security_notices'];END IF;
   IF actual<>expected THEN RAISE EXCEPTION 'retention_manifest_application_columns_changed' USING ERRCODE='42501';END IF;
  ELSIF r.nspname='private' THEN
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(catalog->'private_classes') c WHERE c->>'relation'='private.'||r.relname) THEN
    RAISE EXCEPTION 'retention_manifest_unknown_private_relation' USING ERRCODE='42501';END IF;
  ELSIF r.nspname='auth' AND NOT r.relname=ANY(known_auth) OR r.nspname='storage' AND NOT r.relname=ANY(known_storage) THEN
   RAISE EXCEPTION 'retention_manifest_unknown_managed_relation' USING ERRCODE='42501';
  ELSIF r.nspname='collect_sms' AND NOT(catalog->'gateway_tables' ? r.relname) AND r.relname<>'attempt_evidence' THEN
   RAISE EXCEPTION 'retention_manifest_unknown_gateway_relation' USING ERRCODE='42501';
  END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(catalog->'application') k
   WHERE to_regclass('app.'||k) IS NULL AND k NOT IN('notification_email_deliveries','assisted_sms_dispatches','notification_email_job_dispatches'))
  OR(to_regclass('app.notification_email_deliveries') IS NULL)<>(to_regclass('app.assisted_sms_dispatches') IS NULL)
  OR(to_regclass('app.notification_email_deliveries') IS NULL)<>(to_regclass('app.notification_email_job_dispatches') IS NULL)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(catalog->'engine_tables') k WHERE to_regclass('app.'||k) IS NULL)
  OR(to_regclass('collect_sms.messages') IS NOT NULL AND EXISTS(SELECT 1 FROM jsonb_array_elements_text(catalog->'gateway_tables') k WHERE to_regclass('collect_sms.'||k) IS NULL)) THEN
  RAISE EXCEPTION 'retention_manifest_incomplete_schema' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('schema',n.nspname,'relation',c.relname,'kind',c.relkind,
  'owner',pg_get_userbyid(c.relowner),'acl',c.relacl::text,'schema_acl',n.nspacl::text,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,
  'columns',(SELECT jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'not_null',a.attnotnull,'generated',a.attgenerated,'identity',a.attidentity,'acl',a.attacl::text,'default',(SELECT pg_get_expr(d.adbin,d.adrelid) FROM pg_attrdef d WHERE d.adrelid=a.attrelid AND d.adnum=a.attnum)) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),
  'constraints',(SELECT jsonb_agg(pg_get_constraintdef(x.oid) ORDER BY x.conname) FROM pg_constraint x WHERE x.conrelid=c.oid),
  'triggers',(SELECT jsonb_agg(jsonb_build_object('definition',pg_get_triggerdef(t.oid),'enabled',t.tgenabled) ORDER BY t.tgname) FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal),
  'policies',(SELECT jsonb_agg(jsonb_build_object('name',p.polname,'command',p.polcmd,'permissive',p.polpermissive,'roles',p.polroles::text,'using',pg_get_expr(p.polqual,p.polrelid),'check',pg_get_expr(p.polwithcheck,p.polrelid)) ORDER BY p.polname) FROM pg_policy p WHERE p.polrelid=c.oid),
  'view',CASE WHEN c.relkind='v' THEN pg_get_viewdef(c.oid,true) END,
  'partition_bound',pg_get_expr(c.relpartbound,c.oid)) ORDER BY n.nspname,c.relname),'[]') INTO schema_rows
 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN('app','private','auth','storage','realtime','collect_sms','collect_ops','vault','net','cron','supabase_migrations') AND c.relkind IN('r','p','v');
 SELECT jsonb_agg(jsonb_build_object('name',p.oid::regprocedure::text,'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'sha256',encode(sha256(convert_to(pg_get_functiondef(p.oid),'UTF8')),'hex')) ORDER BY p.oid::regprocedure::text) INTO helpers
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname IN('app','private','api','auth','storage','realtime','collect_sms','collect_ops','vault','net','cron','supabase_migrations') AND p.prokind='f';
 SELECT jsonb_agg(jsonb_build_object('name',rolname,'super',rolsuper,'bypass',rolbypassrls,'inherit',rolinherit,'login',rolcanlogin,'create_role',rolcreaterole,'create_db',rolcreatedb,'replication',rolreplication) ORDER BY rolname) INTO roles
 FROM pg_roles WHERE rolname IN('postgres','anon','authenticated','service_role','collect_runtime','collect_importer','collect_edge','collect_sms_runtime','supabase_realtime_admin');
 SELECT coalesce(jsonb_agg(jsonb_build_object('role',pg_get_userbyid(roleid),'member',pg_get_userbyid(member),'grantor',pg_get_userbyid(grantor),'admin',admin_option,'inherit',inherit_option,'set',set_option) ORDER BY roleid,member,grantor),'[]') INTO memberships
 FROM pg_auth_members WHERE roleid IN(SELECT oid FROM pg_roles WHERE rolname IN('postgres','anon','authenticated','service_role','collect_runtime','collect_importer','collect_edge','collect_sms_runtime','supabase_realtime_admin'))
 OR member IN(SELECT oid FROM pg_roles WHERE rolname IN('postgres','anon','authenticated','service_role','collect_runtime','collect_importer','collect_edge','collect_sms_runtime','supabase_realtime_admin'));
 RETURN jsonb_build_object('contract','collect.retention.schema.v2','sha256',encode(sha256(convert_to(jsonb_build_object('relations',schema_rows,'helpers',helpers,'roles',roles,'memberships',memberships)::text,'UTF8')),'hex'),
  'catalog_sha256',encode(sha256(convert_to(catalog::text,'UTF8')),'hex'),'relation_count',jsonb_array_length(schema_rows),
  'gateway_relation_count',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='collect_sms' AND c.relkind IN('r','p','v')));
END$$;

CREATE FUNCTION private._retention_manifest_managed_rows_v2(p_subject text,p_limit integer DEFAULT 1000001)
RETURNS TABLE(class_name text,descriptor jsonb) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=app,pg_catalog,pg_temp AS $$
DECLARE relation record;managed_id uuid;bucket_name text;bucket_private boolean:=false;predicate text;sql_text text;produced bigint:=0;emitted bigint;
 owned_sql text:='SELECT object_key FROM private.storage_put_intents WHERE scope->>''ownerId''=$2 UNION SELECT object_key FROM private.storage_payload_reservations WHERE scope->>''ownerId''=$2 UNION SELECT object_key FROM app.payment_evidence WHERE owner_user_id=$2 UNION SELECT object_key FROM app.sms_receipts WHERE owner_user_id=$2 UNION SELECT source_object_key FROM app.roster_imports WHERE user_id=$2 UNION SELECT object_key FROM app.upload_objects WHERE user_id=$2';
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 3 AND 1000001 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 SELECT auth_user_id INTO managed_id FROM private.auth_principal_links WHERE user_id=p_subject;
 SELECT bucket INTO bucket_name FROM private.storage_namespace WHERE singleton;
 IF to_regclass('storage.buckets') IS NOT NULL AND bucket_name IS NOT NULL THEN EXECUTE 'SELECT NOT public FROM storage.buckets WHERE id=$1' INTO bucket_private USING bucket_name;END IF;
 RETURN QUERY SELECT 'managed:auth',jsonb_build_object('kind','class','status',CASE WHEN managed_id IS NULL THEN 'unmapped' ELSE 'observed' END,'provider_logs_backups','blocked');
 produced:=produced+1;
 FOR relation IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='auth' AND c.relkind IN('r','p') ORDER BY c.relname LOOP
  predicate:=CASE relation.relname
   WHEN 'users' THEN 'r.id=$1'
   WHEN 'refresh_tokens' THEN 'r.user_id=$1::text OR r.session_id IN(SELECT id FROM auth.sessions WHERE user_id=$1)'
   WHEN 'flow_state' THEN 'r.user_id=$1 OR to_jsonb(r)->>''linking_target_id''=$1::text'
   WHEN 'mfa_amr_claims' THEN 'r.session_id IN(SELECT id FROM auth.sessions WHERE user_id=$1)'
   WHEN 'mfa_challenges' THEN 'r.factor_id IN(SELECT id FROM auth.mfa_factors WHERE user_id=$1)'
   WHEN 'mfa_recovery_codes' THEN 'r.mfa_recovery_code_set_id IN(SELECT id FROM auth.mfa_recovery_code_sets WHERE user_id=$1)'
   WHEN 'oauth_client_states' THEN 'r.id IN(SELECT (to_jsonb(f)->>''oauth_client_state_id'')::uuid FROM auth.flow_state f WHERE f.user_id=$1 OR to_jsonb(f)->>''linking_target_id''=$1::text)'
   WHEN 'saml_relay_states' THEN 'r.flow_state_id IN(SELECT id FROM auth.flow_state WHERE user_id=$1)'
   WHEN 'audit_log_entries' THEN 'r.payload::jsonb->>''actor_id''=$1::text OR r.payload::jsonb->>''user_id''=$1::text'
   WHEN 'custom_oauth_providers' THEN NULL WHEN 'instances' THEN NULL WHEN 'oauth_clients' THEN NULL WHEN 'saml_providers' THEN NULL WHEN 'schema_migrations' THEN NULL WHEN 'scim_tokens' THEN NULL WHEN 'sso_domains' THEN NULL WHEN 'sso_providers' THEN NULL
   ELSE 'r.user_id=$1' END;
  IF predicate IS NULL OR managed_id IS NULL THEN CONTINUE;END IF;
  sql_text:=format('SELECT ''managed:auth''::text,jsonb_build_object(''kind'',''row'',''relation'',%L,''key_sha256'',encode(sha256(convert_to(%L||'':''||coalesce(to_jsonb(r)->>''id'',to_jsonb(r)->>''session_id'',to_jsonb(r)::text)||'':''||coalesce(to_jsonb(r)->>''authentication_method'',''''),''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''lifecycle'',''{}''::jsonb) FROM auth.%I r WHERE %s',relation.relname,relation.relname,relation.relname,predicate);
  RETURN QUERY EXECUTE sql_text||format(' LIMIT %s',greatest(p_limit-produced,1)) USING managed_id;
  GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
  IF produced>=p_limit THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 END LOOP;
 RETURN QUERY SELECT 'managed:storage',jsonb_build_object('kind','class','status',CASE WHEN bucket_name IS NOT NULL AND coalesce(bucket_private,false) AND to_regclass('storage.objects') IS NOT NULL THEN 'observed' ELSE 'unavailable' END,'scope','owned_catalog_and_principal_metadata','object_content_verification','not_performed');
 produced:=produced+1;
 IF bucket_name IS NOT NULL AND to_regclass('storage.objects') IS NOT NULL THEN
  FOR relation IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='storage' AND c.relkind IN('r','p') AND c.relname IN('objects','s3_multipart_uploads','s3_multipart_uploads_parts') ORDER BY c.relname LOOP
   predicate:=CASE relation.relname WHEN 'objects' THEN 'r.name IN('||owned_sql||') OR to_jsonb(r)->>''owner_id''=$1::text OR to_jsonb(r)->>''owner''=$1::text' ELSE 'r.key IN('||owned_sql||') OR to_jsonb(r)->>''owner_id''=$1::text' END;
   sql_text:=format('SELECT ''managed:storage''::text,jsonb_build_object(''kind'',''row'',''relation'',%L,''key_sha256'',encode(sha256(convert_to(%s,''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''lifecycle'',jsonb_build_object(''catalog_rows'',1,''erasure_verified'',false)) FROM storage.%I r WHERE r.bucket_id=$3 AND (%s)',relation.relname,CASE WHEN relation.relname='objects' THEN 'r.name' ELSE 'r.key' END,relation.relname,predicate);
   RETURN QUERY EXECUTE sql_text||format(' LIMIT %s',greatest(p_limit-produced,1)) USING managed_id,p_subject,bucket_name;
   GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
   IF produced>=p_limit THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
  END LOOP;
 END IF;
 RETURN QUERY SELECT 'managed:realtime_messages',jsonb_build_object('kind','class','status',CASE WHEN managed_id IS NULL OR to_regclass('realtime.messages') IS NULL THEN 'unavailable' ELSE 'observed' END,'scope','retained_member_topics_only','provider_logs_backups','blocked','erasure_verified',false);
 produced:=produced+1;
 IF managed_id IS NOT NULL AND to_regclass('realtime.messages') IS NOT NULL THEN
  IF EXISTS(SELECT 1 FROM app.auth_sessions WHERE user_id=p_subject AND surface='member' AND id !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$') THEN RAISE EXCEPTION 'retention_manifest_realtime_attribution_unavailable' USING ERRCODE='42501';END IF;
  RETURN QUERY SELECT 'managed:realtime_messages',jsonb_build_object('kind','row','key_sha256',encode(sha256(convert_to(r.topic||':'||r.id::text||':'||r.inserted_at::text,'UTF8')),'hex'),
   'row_sha256',encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),'identity_sha256',encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),'lifecycle',jsonb_build_object('managed_copy',true,'erasure_verified',false))
   FROM realtime.messages r WHERE r.topic IN(SELECT 'collect:member:'||managed_id::text||':'||s.id FROM app.auth_sessions s WHERE s.user_id=p_subject AND s.surface='member') LIMIT greatest(p_limit-produced,1);
  GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
 END IF;
 IF produced>=p_limit THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
END$$;

CREATE FUNCTION private._retention_manifest_rows_v2(p_subject text)
RETURNS TABLE(class_name text,descriptor jsonb) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=app,pg_catalog,pg_temp AS $$
DECLARE catalog jsonb:=private._retention_manifest_catalog_v2();entry record;c jsonb;predicate text;sql_text text;life text;engine text;produced bigint:=0;emitted bigint;
BEGIN
 FOR entry IN SELECT * FROM jsonb_each(catalog->'application') ORDER BY key LOOP
  produced:=produced+1;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
  IF to_regclass('app.'||entry.key) IS NULL THEN
   RETURN QUERY SELECT entry.key,jsonb_build_object('kind','class','status','absent_schema');CONTINUE;END IF;
  RETURN QUERY SELECT entry.key,jsonb_build_object('kind','class','status',CASE WHEN entry.key='client_diagnostic_reports' THEN 'unmapped' ELSE 'observed' END);
  predicate:=entry.value->>'where';
  -- Approved policy bytes bind separately; the approval cannot hash itself.
  IF entry.key='runtime_config' THEN predicate:='('||predicate||') AND key NOT IN(''privacy:retention:approved:v1'',''privacy:retention:approved:v2'')';END IF;
  life:=CASE entry.key
   WHEN 'privacy_holds' THEN 'jsonb_build_object(''hold'',r.active=1)'
   WHEN 'payment_evidence' THEN 'jsonb_build_object(''hold'',r.legal_hold=1,''physical_object_unverified'',true)'
   WHEN 'sms_receipts' THEN 'jsonb_build_object(''physical_object_unverified'',true)'
   WHEN 'upload_objects' THEN 'jsonb_build_object(''physical_object_unverified'',true)'
   WHEN 'roster_imports' THEN 'jsonb_build_object(''unresolved'',r.state IN(''processing'',''ambiguous''),''physical_object_unverified'',true)'
   WHEN 'native_reservations' THEN 'jsonb_build_object(''unresolved'',r.state NOT IN(''completed'',''rejected''))'
   WHEN 'auth_otp_challenges' THEN 'jsonb_build_object(''unresolved'',r.status IN(''dispatching'',''delivery_unknown''))'
   WHEN 'assisted_sms_jobs' THEN 'jsonb_build_object(''unresolved'',r.state NOT IN(''observed_sent'',''failed_no_send''))'
   WHEN 'momo_processing_jobs' THEN 'jsonb_build_object(''unresolved'',r.state<>''completed'')'
   WHEN 'momo_processing_guards' THEN 'jsonb_build_object(''unresolved'',true)'
   WHEN 'notification_deliveries' THEN 'jsonb_build_object(''unresolved'',r.state IN(''pending'',''claimed'',''sending'',''retry'',''unknown''))'
   WHEN 'notification_email_job_dispatches' THEN 'jsonb_build_object(''unresolved'',r.state IN(''claimed'',''unknown''),''shared'',true)'
   WHEN 'notification_email_deliveries' THEN 'jsonb_build_object(''unresolved'',r.state IN(''pending'',''sending'',''unknown''))'
   WHEN 'assisted_sms_dispatches' THEN 'jsonb_build_object(''unresolved'',r.state IN(''ready'',''sending'',''unknown''))'
   WHEN 'admin_email_otp_challenges' THEN 'jsonb_build_object(''unresolved'',r.used_at IS NULL AND r.delivery_status IN(''pending'',''accepted'',''unknown'') AND r.expires_at>app.unixepoch())'
   WHEN 'auth_google_flows' THEN 'jsonb_build_object(''unresolved'',r.status IN(''pending'',''exchanging'',''ready'') AND r.expires_at>app.unixepoch())'
   ELSE '''{}''::jsonb' END;
  sql_text:=format('SELECT %L::text,jsonb_build_object(''kind'',''row'',''key_sha256'',encode(sha256(convert_to(coalesce(to_jsonb(r)->>''id'',to_jsonb(r)->>''user_id'',to_jsonb(r)::text),''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''lifecycle'',%s) FROM app.%I r WHERE %s',entry.key,life,entry.key,predicate);
  RETURN QUERY EXECUTE sql_text||format(' LIMIT %s',1000001-produced) USING p_subject;
  GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 END LOOP;
 FOR engine IN SELECT jsonb_array_elements_text(catalog->'engine_tables') LOOP
  produced:=produced+1;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
  RETURN QUERY SELECT engine,jsonb_build_object('kind','class','status','observed','erasure','blocked');
  predicate:=CASE WHEN engine='privacy_retention_plans' THEN 'r.subject_id=$1'
   WHEN engine='privacy_retention_barriers' THEN 'r.subject_id=$1'
   WHEN engine IN('privacy_retention_claims','privacy_retention_outcomes','privacy_retention_effects') THEN 'r.task_id IN(SELECT t.id FROM app.privacy_retention_tasks t JOIN app.privacy_retention_plans p ON p.id=t.plan_id WHERE p.subject_id=$1)'
   ELSE 'r.plan_id IN(SELECT id FROM app.privacy_retention_plans WHERE subject_id=$1)' END;
  RETURN QUERY EXECUTE format('SELECT %L::text,jsonb_build_object(''kind'',''row'',''key_sha256'',encode(sha256(convert_to(coalesce(to_jsonb(r)->>''id'',to_jsonb(r)->>''subject_id'',to_jsonb(r)::text),''UTF8'')),''hex''),''row_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''identity_sha256'',encode(sha256(convert_to(to_jsonb(r)::text,''UTF8'')),''hex''),''lifecycle'',''{}''::jsonb) FROM app.%I r WHERE %s LIMIT %s',engine,engine,predicate,1000001-produced) USING p_subject;
  GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 END LOOP;
 FOR c IN SELECT value FROM jsonb_array_elements(catalog->'private_classes') LOOP
  produced:=produced+1;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
  IF coalesce((c->>'blocked')::boolean,false) THEN
   -- These two request-attributed protocol tables are the capture receipt
   -- itself. Hashing a receipt into its own source root would be recursive.
   -- Keep their custody explicit and blocked; do not claim no subject copies.
   RETURN QUERY SELECT c->>'name',jsonb_build_object('kind','class',
    'status',CASE WHEN c->>'relation' IN('private.retention_inventory_manifests','private.retention_inventory_pages','private.retention_row_plans','private.retention_row_claims','private.retention_row_effects','private.retention_row_operations') THEN 'retained_control' ELSE 'unmapped' END,
    'subject_count',NULL,'erasure','blocked','present',to_regclass(c->>'relation') IS NOT NULL)||
    CASE WHEN c->>'relation' IN('private.retention_inventory_manifests','private.retention_inventory_pages','private.retention_row_plans','private.retention_row_claims','private.retention_row_effects','private.retention_row_operations') THEN
     jsonb_build_object('subject_mapping','request_subject_id','source_root_exclusion','immutable_capture_protocol_custody') ELSE '{}'::jsonb END;
   CONTINUE;
  END IF;
  IF to_regclass(c->>'relation') IS NULL THEN RAISE EXCEPTION 'retention_manifest_private_relation_missing' USING ERRCODE='42501';END IF;
  RETURN QUERY SELECT c->>'name',jsonb_build_object('kind','class','status','observed');
  sql_text:=format('SELECT %L::text,jsonb_build_object(''kind'',''row'',''key_sha256'',%s,''row_sha256'',%s,''identity_sha256'',%s,''lifecycle'',%s) FROM %s r WHERE %s',c->>'name',c->>'keyHash',c->>'rowHash',c->>'identityHash',c->>'lifecycle',c->>'relation',c->>'where');
  RETURN QUERY EXECUTE sql_text||format(' LIMIT %s',1000001-produced) USING p_subject;
  GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 END LOOP;
 RETURN QUERY SELECT * FROM private._retention_manifest_managed_rows_v2(p_subject,(1000001-produced)::integer);
 GET DIAGNOSTICS emitted=ROW_COUNT;produced:=produced+emitted;
 FOR c IN SELECT value FROM jsonb_array_elements(catalog->'copy_classes') LOOP
  produced:=produced+1;
  IF produced>1000000 THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
  RETURN QUERY SELECT c#>>'{}',jsonb_build_object('kind','class','status','unverified','subject_count',NULL,'erasure','blocked','physical_object_verification','not_performed')||
   CASE WHEN c#>>'{}' IN('external:collect_sms','external:collect_ops','external:vault','external:net','external:cron','external:supabase_migrations') THEN
    jsonb_build_object('namespace_present',to_regnamespace(split_part(c#>>'{}',':',2)) IS NOT NULL,'relation_count',
     (SELECT count(*) FROM pg_class t JOIN pg_namespace n ON n.oid=t.relnamespace WHERE n.nspname=split_part(c#>>'{}',':',2) AND t.relkind IN('r','p','v')))
   ELSE '{}'::jsonb END;
 END LOOP;
END$$;

CREATE FUNCTION private._retention_manifest_control_v2(p_request text,p_review bigint,p_source text) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE r app.deletion_requests%ROWTYPE;head jsonb;holds jsonb;review bigint;managed uuid;
BEGIN
 SELECT * INTO r FROM app.deletion_requests WHERE id=p_request;
 IF NOT FOUND THEN RAISE EXCEPTION 'retention_manifest_request_unavailable' USING ERRCODE='42501';END IF;
 SELECT to_jsonb(h),h.revision INTO head,review FROM app.privacy_review_heads h WHERE request_id=p_request;
 IF coalesce(review,0)<>p_review THEN RAISE EXCEPTION 'retention_manifest_review_changed' USING ERRCODE='42501';END IF;
 IF p_source IS NULL OR p_source!~'^[a-f0-9]{64}$' OR p_source IS DISTINCT FROM current_setting('collect.fence_source_sha256',true)
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND source_sha256=p_source AND mode='open') THEN
  RAISE EXCEPTION 'retention_manifest_source_changed' USING ERRCODE='42501';END IF;
 SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY h.id),'[]') INTO holds FROM app.privacy_holds h WHERE h.user_id=r.user_id;
 SELECT auth_user_id INTO managed FROM private.auth_principal_links WHERE user_id=r.user_id;
 RETURN jsonb_build_object('request_id',r.id,'subject_id',r.user_id,'review_revision',p_review,'source_sha256',p_source,
  'request_sha256',encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex'),
  'review_sha256',encode(sha256(convert_to(coalesce(head,'null')::text,'UTF8')),'hex'),
  'holds_sha256',encode(sha256(convert_to(holds::text,'UTF8')),'hex'),
  'active_hold_count',(SELECT count(*) FROM app.privacy_holds WHERE user_id=r.user_id AND active=1),
  'principal_mapping_sha256',CASE WHEN managed IS NULL THEN NULL ELSE encode(sha256(convert_to(managed::text,'UTF8')),'hex') END);
END$$;

CREATE FUNCTION private._retention_manifest_commitment_v2(p_control jsonb,p_schema jsonb,p_count bigint,p_pages integer,p_classes jsonb,p_pages_sha text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $$
 SELECT encode(sha256(convert_to(jsonb_build_object('contract','collect.retention.manifest.v2','control',p_control,'schema',p_schema,
 'descriptor_count',p_count,'page_count',p_pages,'class_counts',p_classes,'pages_sha256',p_pages_sha)::text,'UTF8')),'hex')
$$;

CREATE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE actor text;session text;subject text;fingerprint text;prior private.retention_inventory_manifests%ROWTYPE;control jsonb;result jsonb;
BEGIN
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);session:=api.current_session_id();
 IF p_operation IS NULL OR p_request IS NULL OR p_review IS NULL OR p_review<0 OR p_max_rows IS NULL OR p_max_rows NOT BETWEEN 1 AND 1000000 THEN RAISE EXCEPTION 'retention_manifest_input_invalid' USING ERRCODE='22023';END IF;
 control:=private._retention_manifest_control_v2(p_request,p_review,p_source);subject:=control->>'subject_id';
 IF actor=subject THEN RAISE EXCEPTION 'retention_manifest_independent_review_required' USING ERRCODE='42501';END IF;
 fingerprint:=encode(sha256(convert_to(jsonb_build_object('operation',p_operation,'request',p_request,'review',p_review,'source',p_source,'actor',actor,'session',session,'max_rows',p_max_rows)::text,'UTF8')),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('retention-manifest:'||p_operation::text,0));
 SELECT * INTO prior FROM private.retention_inventory_manifests WHERE id=p_operation;
 IF FOUND THEN
  IF prior.input_sha256<>fingerprint THEN RAISE EXCEPTION 'retention_manifest_operation_conflict' USING ERRCODE='42501';END IF;
  RETURN private.retention_inventory_page_v2(p_operation,prior.manifest_sha256,0,false);
 END IF;
 -- Both STABLE enumerators use this one statement's MVCC snapshot. No page
 -- is assembled from a later transaction; any over-budget capture rolls back.
 WITH metadata AS MATERIALIZED(SELECT private._retention_manifest_schema_v2() AS schema,private._retention_manifest_control_v2(p_request,p_review,p_source) AS control),
 observed AS MATERIALIZED(SELECT class_name,descriptor FROM private._retention_manifest_rows_v2(subject) LIMIT p_max_rows+1),
 ordered AS(SELECT class_name,descriptor,(row_number() OVER(ORDER BY class_name,descriptor->>'kind',descriptor->>'key_sha256',descriptor->>'row_sha256',descriptor::text)-1)/100 AS page FROM observed),
 page_values AS(SELECT page::integer AS page_number,jsonb_agg(jsonb_build_object('class_name',class_name)||descriptor ORDER BY class_name,descriptor->>'kind',descriptor->>'key_sha256',descriptor->>'row_sha256',descriptor::text) AS items FROM ordered GROUP BY page),
 written AS(INSERT INTO private.retention_inventory_pages(manifest_id,page_number,descriptors,page_sha256) SELECT p_operation,page_number,items,encode(sha256(convert_to(items::text,'UTF8')),'hex') FROM page_values RETURNING page_number,page_sha256),
 classes AS(SELECT jsonb_object_agg(class_name,jsonb_build_object('descriptor_count',n,'rows',row_count,'status',status,'unresolved_count',unresolved,'hold_count',holds) ORDER BY class_name) AS value FROM(
  SELECT class_name,count(*) AS n,count(*) FILTER(WHERE descriptor->>'kind'='row') AS row_count,
  max(descriptor->>'status') FILTER(WHERE descriptor->>'kind'='class') AS status,
  count(*) FILTER(WHERE descriptor->'lifecycle' @> '{"unresolved":true}' OR descriptor->'lifecycle' @> '{"active":true}') AS unresolved,
  count(*) FILTER(WHERE descriptor->'lifecycle' @> '{"hold":true}') AS holds FROM observed GROUP BY class_name) q),
 totals AS(SELECT (SELECT count(*) FROM observed) AS n,count(*)::integer AS pages,encode(sha256(convert_to(jsonb_agg(jsonb_build_object('page',page_number,'sha256',page_sha256) ORDER BY page_number)::text,'UTF8')),'hex') AS pages_sha FROM written),
 inserted AS(INSERT INTO private.retention_inventory_manifests(id,request_id,subject_id,actor_id,session_id,input_sha256,source_sha256,schema_sha256,schema_identity,control_identity,descriptor_count,page_count,class_counts,pages_sha256,manifest_sha256)
 SELECT p_operation,p_request,subject,actor,session,fingerprint,p_source,m.schema->>'sha256',m.schema,m.control,t.n,t.pages,c.value,t.pages_sha,
  private._retention_manifest_commitment_v2(m.control,m.schema,t.n,t.pages,c.value,t.pages_sha) FROM metadata m CROSS JOIN totals t CROSS JOIN classes c
 WHERE t.n<=p_max_rows RETURNING *) SELECT to_jsonb(inserted) INTO result FROM inserted;
 IF result IS NULL THEN RAISE EXCEPTION 'retention_manifest_capacity_exceeded' USING ERRCODE='54000';END IF;
 IF private._retention_manifest_control_v2(p_request,p_review,p_source)<>result->'control_identity' OR private._retention_manifest_schema_v2()<>result->'schema_identity' THEN RAISE EXCEPTION 'retention_manifest_capture_changed' USING ERRCODE='42501';END IF;
 RETURN private.retention_inventory_page_v2(p_operation,result->>'manifest_sha256',0,false);
END$$;

CREATE FUNCTION private.retention_inventory_page_v2(p_manifest uuid,p_sha text,p_page integer,p_verify_current boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE actor text;m private.retention_inventory_manifests%ROWTYPE;p private.retention_inventory_pages%ROWTYPE;control jsonb;schema jsonb;pages_sha text;n bigint;page_count integer;current_sha text;currently_equal boolean:=NULL;
BEGIN
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);
 IF p_manifest IS NULL OR p_sha IS NULL OR p_sha!~'^[a-f0-9]{64}$' OR p_page IS NULL OR p_page<0 OR p_verify_current IS NULL THEN RAISE EXCEPTION 'retention_manifest_input_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO m FROM private.retention_inventory_manifests WHERE id=p_manifest;
 IF NOT FOUND OR m.manifest_sha256<>p_sha OR actor=m.subject_id OR p_page>=m.page_count THEN RAISE EXCEPTION 'retention_manifest_unavailable' USING ERRCODE='42501';END IF;
 control:=private._retention_manifest_control_v2(m.request_id,(m.control_identity->>'review_revision')::bigint,m.source_sha256);
 schema:=private._retention_manifest_schema_v2();
 IF control<>m.control_identity OR schema<>m.schema_identity THEN RAISE EXCEPTION 'retention_manifest_control_changed' USING ERRCODE='42501';END IF;
 -- Header integrity reads only small indexed hashes/counts. Resuming one page
 -- must not detoast every other descriptor page in a million-row capture.
 SELECT count(*),sum(descriptor_count),encode(sha256(convert_to(jsonb_agg(jsonb_build_object('page',page_number,'sha256',page_sha256) ORDER BY page_number)::text,'UTF8')),'hex') INTO page_count,n,pages_sha FROM private.retention_inventory_pages WHERE manifest_id=p_manifest;
 IF page_count<>m.page_count OR n<>m.descriptor_count OR pages_sha<>m.pages_sha256
  OR private._retention_manifest_commitment_v2(control,schema,n,page_count,m.class_counts,pages_sha)<>m.manifest_sha256 THEN RAISE EXCEPTION 'retention_manifest_integrity_failed' USING ERRCODE='42501';END IF;
 SELECT * INTO p FROM private.retention_inventory_pages WHERE manifest_id=p_manifest AND page_number=p_page;
 IF NOT FOUND OR encode(sha256(convert_to(p.descriptors::text,'UTF8')),'hex')<>p.page_sha256 THEN RAISE EXCEPTION 'retention_manifest_integrity_failed' USING ERRCODE='42501';END IF;
 IF p_verify_current THEN
  WITH observed AS MATERIALIZED(SELECT class_name,descriptor FROM private._retention_manifest_rows_v2(m.subject_id) LIMIT 1000001),
  ordered AS(SELECT class_name,descriptor,(row_number() OVER(ORDER BY class_name,descriptor->>'kind',descriptor->>'key_sha256',descriptor->>'row_sha256',descriptor::text)-1)/100 AS page FROM observed),
  pages AS(SELECT page,jsonb_agg(jsonb_build_object('class_name',class_name)||descriptor ORDER BY class_name,descriptor->>'kind',descriptor->>'key_sha256',descriptor->>'row_sha256',descriptor::text) AS items FROM ordered GROUP BY page)
  SELECT encode(sha256(convert_to(jsonb_agg(jsonb_build_object('page',page,'sha256',encode(sha256(convert_to(items::text,'UTF8')),'hex')) ORDER BY page)::text,'UTF8')),'hex') INTO current_sha FROM pages;
  currently_equal:=current_sha=m.pages_sha256;
 END IF;
 RETURN jsonb_build_object('contract_version',2,'scope','sealed_metadata_inventory','manifest_id',m.id,'manifest_sha256',m.manifest_sha256,
  'request_id',m.request_id,'subject_id',m.subject_id,'source_id',m.source_sha256,'schema_sha256',m.schema_sha256,
  'captured_at',m.created_at,'descriptor_count',m.descriptor_count,'page_count',m.page_count,'class_counts',m.class_counts,
  'active_hold_count',control->'active_hold_count','page_number',p_page,'page_sha256',p.page_sha256,'descriptors',p.descriptors,
  'next_page',CASE WHEN p_page+1<m.page_count THEN p_page+1 END,'complete_capture',true,'controls_current',true,
  'data_current',currently_equal,'currentness_checked',p_verify_current,'physical_objects_verified',false,'approval_granted',false,'erasure_completed',false);
END$$;

DO $$DECLARE routine record;BEGIN
 FOR routine IN SELECT p.oid::regprocedure AS signature FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND(p.proname LIKE '\_retention\_manifest\_%' ESCAPE '\' OR p.proname IN('retention_capture_inventory_v2','retention_inventory_page_v2')) LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer',routine.signature);
 END LOOP;
END$$;
GRANT EXECUTE ON FUNCTION private.retention_capture_inventory_v2(uuid,text,bigint,text,integer),private.retention_inventory_page_v2(uuid,text,integer,boolean) TO collect_runtime;
COMMIT;
