-- Installs a fenced, journalled policy transition. Installation never enables
-- the feature, enrolls a factor, rotates credentials or changes the policy.
-- Root must qualify actual Owner setup/recovery and browser behavior first.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE expected record;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM app.runtime_config WHERE key='security:admin_mfa_required:v1')
  OR to_regprocedure('private.collect_admin_mfa_activation_readiness_v1(text,text,uuid)') IS NOT NULL THEN
  RAISE EXCEPTION 'admin_mfa_activation_precondition' USING ERRCODE='55000';END IF;
 FOR expected IN SELECT * FROM(VALUES
  ('private.collect_admin_mfa_policy_guard_v1()','7d52c774f8d772dcb9df7db40a37684583035b4ff3547393b325748815ffd49b'),
  ('private.collect_admin_mfa_policy_enabled_v1()','71202e754d95fc43ec3d3da17d45c18e229a51b469ae16439505f17fba188c84'),
  ('private._collect_fence_statement()','0b886c44b329012c91e5eb85fce1a160a60e4172e016a284f2c280121b0a217d'),
  ('private._collect_fence_require_rc(boolean)','f29634a277e50d7e4751357550a4f8eed0bd5717178703ef92d95ce30bd1b552'),
  ('private.collect_fence_assert_write(uuid,bigint,text)','c29a20edd15233a50c7d561be8f038f6d0fbc125d6f57a85f6d1b11fd6a50949'),
  ('private.collect_fence_release(uuid,bigint,text)','000419dfb85b7ba81416ccf6bff9017121d7876c24003db13ede0bf4ff6e7ba0'),
  ('private.collect_fence_upgrade_source_v3(uuid,uuid,bigint,text,text,text,text,text)','a05450f947be791a28534acdd29939d67c47167fd242f8add08c6d66ad470184')
 ) e(signature,sha256) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(expected.signature)
   AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=expected.sha256) THEN
   RAISE EXCEPTION 'admin_mfa_activation_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
 IF (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='app' AND c.relname IN('runtime_config','audit_log') AND t.tgname='collect_fence_statement_v1'
   AND t.tgenabled='A' AND t.tgfoid='private._collect_fence_statement()'::regprocedure)<>2 THEN
  RAISE EXCEPTION 'admin_mfa_activation_statement_guard_changed' USING ERRCODE='55000';END IF;
END;$preflight$;

-- Only these two tables receive a policy-specific statement trigger. Its
-- fallback is copied byte-for-byte from the pinned generic predecessor, which
-- remains unchanged for every other table. Row guards below restrict the
-- exceptional fenced statement to the exact policy key/reserved audit action.
DO $statement_guard$
DECLARE body text;anchor text:=E'\nBEGIN\n';extra text;table_name text;
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._collect_fence_statement()'::regprocedure;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'admin_mfa_activation_statement_anchor_changed' USING ERRCODE='55000';END IF;
 extra:=$branch$
BEGIN
 IF TG_TABLE_SCHEMA='app' AND((TG_TABLE_NAME='runtime_config' AND TG_OP IN('INSERT','UPDATE')) OR(TG_TABLE_NAME='audit_log' AND TG_OP='INSERT'))
  AND session_user='postgres' AND current_setting('role',true) IN('none','postgres')
  AND current_setting('collect.admin_mfa_policy_write_frame',true)='1'
  AND current_setting('collect.admin_mfa_policy_commitment',true)~'^[a-f0-9]{64}$' THEN
  PERFORM private._collect_fence_require_rc(true);
  PERFORM private._collect_fence_require_operator();
  PERFORM pg_advisory_xact_lock_shared(7346371,1);
  PERFORM pg_advisory_xact_lock_shared(7346371,2);
  IF EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced'
    AND source_sha256=current_setting('collect.admin_mfa_policy_source',true)
    AND epoch::text=current_setting('collect.admin_mfa_policy_epoch',true)) THEN
   IF private._collect_fence_resources()->'capacityBlocked'='true'::jsonb THEN
    RAISE EXCEPTION 'collect_fence_capacity' USING ERRCODE='55000';END IF;
   RETURN NULL;
  END IF;
 END IF;
$branch$;
 EXECUTE 'CREATE FUNCTION private.collect_admin_mfa_fence_statement_v1() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(replace(body,anchor,extra));
 REVOKE ALL ON FUNCTION private.collect_admin_mfa_fence_statement_v1() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
 FOREACH table_name IN ARRAY ARRAY['runtime_config','audit_log'] LOOP
  EXECUTE format('DROP TRIGGER collect_fence_statement_v1 ON app.%I',table_name);
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON app.%I FOR EACH STATEMENT EXECUTE FUNCTION private.collect_admin_mfa_fence_statement_v1()',table_name);
  EXECUTE format('ALTER TABLE app.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',table_name);
 END LOOP;
END;$statement_guard$;

CREATE FUNCTION private.collect_admin_mfa_activation_readiness_v1(p_source text,p_owner text,p_factor uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE at bigint:=app.unixepoch();active_count bigint;missing_count bigint;pending_count bigint;owner_ready boolean;source_exact boolean;revision bigint;
BEGIN
 IF session_user<>'postgres' OR current_setting('role',true) NOT IN('none','postgres') THEN
  RAISE EXCEPTION 'admin_mfa_activation_operator_required' USING ERRCODE='42501';END IF;
 IF p_source IS NULL OR p_source!~'^[a-f0-9]{64}$' OR p_owner IS NULL OR length(p_owner) NOT BETWEEN 1 AND 200 OR p_factor IS NULL THEN
  RAISE EXCEPTION 'admin_mfa_activation_input_invalid' USING ERRCODE='22023';END IF;
 SELECT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND source_sha256=p_source) INTO source_exact;
 SELECT coalesce(max(c.revision),0) INTO revision FROM app.runtime_config c WHERE c.key='security:admin_mfa_required:v1';
 SELECT count(*),count(*) FILTER(WHERE NOT EXISTS(
  SELECT 1 FROM app.admin_principal_links l JOIN app.users principal ON principal.id=l.user_id AND principal.access_status='active'
  JOIN private.auth_principal_links link ON link.user_id=l.user_id
  JOIN auth.users u ON u.id=link.auth_user_id
  JOIN auth.mfa_factors f ON f.user_id=u.id AND f.factor_type::text='totp' AND f.status::text='verified'
  JOIN app.auth_mfa_factors marker ON marker.id=f.id::text AND marker.user_id=l.user_id
   AND marker.status='verified' AND marker.revoked_at IS NULL
   AND marker.secret_ciphertext::jsonb='{"managed_by":"supabase","version":1}'::jsonb
  WHERE l.admin_user_id=a.id AND lower(u.email)=a.email AND u.email_confirmed_at IS NOT NULL AND NOT coalesce(u.is_anonymous,false)
   AND u.deleted_at IS NULL AND(u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
 )) INTO active_count,missing_count FROM app.admin_users a WHERE a.status='active';
 SELECT count(*) INTO pending_count FROM private.bff_sessions b JOIN app.admin_sessions c ON c.token_hash=b.token_hash
  JOIN app.admin_users a ON a.id=c.user_id WHERE a.status='active' AND c.expires_at>at
   AND(b.refresh_lease IS NOT NULL OR b.mfa_pending_hash IS NOT NULL OR b.mfa_intent_hash IS NOT NULL);
 SELECT EXISTS(
  SELECT 1 FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id
  JOIN app.users principal ON principal.id=l.user_id AND principal.access_status='active'
  JOIN private.auth_principal_links link ON link.user_id=l.user_id
  JOIN auth.users u ON u.id=link.auth_user_id AND lower(u.email)=a.email AND u.email_confirmed_at IS NOT NULL AND NOT coalesce(u.is_anonymous,false)
   AND u.deleted_at IS NULL AND(u.banned_until IS NULL OR u.banned_until<=clock_timestamp())
  JOIN auth.mfa_factors f ON f.user_id=u.id AND f.id=p_factor AND f.factor_type::text='totp' AND f.status::text='verified'
  JOIN app.auth_mfa_factors marker ON marker.id=f.id::text AND marker.user_id=l.user_id AND marker.status='verified'
   AND marker.revoked_at IS NULL AND marker.secret_ciphertext::jsonb='{"managed_by":"supabase","version":1}'::jsonb
  JOIN private.managed_mfa_proofs m ON m.user_id=u.id AND m.factor_id=f.id
  JOIN auth.sessions managed ON managed.id=m.session_id AND managed.user_id=u.id AND managed.factor_id=f.id
   AND to_jsonb(managed)->>'aal'='aal2' AND(managed.not_after IS NULL OR managed.not_after>clock_timestamp())
  JOIN app.auth_sessions s ON s.id=m.session_id::text AND s.user_id=l.user_id AND s.revoked_at IS NULL
   AND s.assurance_level=2 AND s.mfa_factor_id=f.id::text AND s.mfa_at=m.verified_at_epoch AND s.expires_at>at
  JOIN app.admin_sessions c ON c.auth_session_id=s.id AND c.user_id=a.id AND c.auth_version=a.auth_version
   AND c.issued_assurance_level=2 AND c.issued_mfa_factor_id=f.id::text AND c.issued_mfa_at=m.verified_at_epoch AND c.expires_at>at
  JOIN private.bff_sessions b ON b.token_hash=c.token_hash AND b.auth_user_id=u.id AND b.auth_session_id=m.session_id
  WHERE a.id=p_owner AND a.role='owner' AND a.status='active' AND m.verified_at_epoch BETWEEN at-300 AND at
   AND b.refresh_lease IS NULL AND b.mfa_pending_hash IS NULL AND b.mfa_intent_hash IS NULL
 ) INTO owner_ready;
 RETURN jsonb_build_object('version',1,'scope','operator_metadata_only','source_exact',source_exact,
  'active_admin_count',active_count,'enrollment_missing_count',missing_count,'pending_session_transition_count',pending_count,
  'owner_current_factor_and_fresh_aal2',owner_ready,'policy_revision',revision,'required',private.collect_admin_mfa_policy_enabled_v1(),
  'ready',source_exact AND active_count>0 AND missing_count=0 AND pending_count=0 AND owner_ready,
  'owner_recovery_and_browser_qualification','external_evidence_required','activation_performed',false);
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_activation_readiness_v1(text,text,uuid)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

-- The session-local commitment is usable only by a fenced postgres operator.
-- Runtime callers cannot gain authority by setting an arbitrary custom GUC.
CREATE OR REPLACE FUNCTION private.collect_admin_mfa_policy_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE expected text;
BEGIN
 IF current_setting('collect.admin_mfa_policy_write_frame',true)='1'
  AND(TG_OP='DELETE' OR NEW.key<>'security:admin_mfa_required:v1' OR(TG_OP='UPDATE' AND OLD.key<>'security:admin_mfa_required:v1')) THEN
  RAISE EXCEPTION 'admin_mfa_policy_write_scope_changed' USING ERRCODE='42501';END IF;
 IF TG_OP='DELETE' THEN
  IF OLD.key='security:admin_mfa_required:v1' THEN RAISE EXCEPTION 'admin_mfa_policy_retained' USING ERRCODE='42501';END IF;
  RETURN OLD;
 END IF;
 IF NEW.key='security:admin_mfa_required:v1' OR(TG_OP='UPDATE' AND OLD.key='security:admin_mfa_required:v1') THEN
  IF session_user<>'postgres' OR current_setting('role',true) NOT IN('none','postgres') THEN
   RAISE EXCEPTION 'admin_mfa_policy_activation_unavailable' USING ERRCODE='42501';END IF;
  PERFORM private._collect_fence_require_operator();
  expected:=encode(sha256(convert_to(jsonb_build_object('key',NEW.key,'value',NEW.value_json,
   'revision',NEW.revision,'by',NEW.updated_by,'at',NEW.updated_at)::text,'UTF8')),'hex');
  IF NEW.key<>'security:admin_mfa_required:v1' OR NEW.value_json::jsonb NOT IN('{"version":1,"required":true}'::jsonb,'{"version":1,"required":false}'::jsonb)
   OR NEW.revision<>(CASE WHEN TG_OP='INSERT' THEN 1 ELSE OLD.revision+1 END)
   OR current_setting('collect.admin_mfa_policy_commitment',true) IS DISTINCT FROM expected THEN
   RAISE EXCEPTION 'admin_mfa_policy_activation_unavailable' USING ERRCODE='42501';END IF;
 END IF;
 RETURN NEW;
END;$fn$;

-- Reserve this audit action for the same fenced operator boundary. A runtime
-- audit writer must never forge a policy receipt used for reconciliation.
CREATE FUNCTION private.collect_admin_mfa_transition_audit_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF current_setting('collect.admin_mfa_policy_write_frame',true)='1'
  AND(TG_OP<>'INSERT' OR NEW.action<>'admin.mfa.policy.transition') THEN
  RAISE EXCEPTION 'admin_mfa_policy_audit_scope_changed' USING ERRCODE='42501';END IF;
 IF TG_OP='DELETE' THEN
  IF OLD.action='admin.mfa.policy.transition' THEN RAISE EXCEPTION 'admin_mfa_policy_receipt_immutable' USING ERRCODE='42501';END IF;
  RETURN OLD;
 END IF;
 IF TG_OP='UPDATE' AND OLD.action='admin.mfa.policy.transition' THEN
  RAISE EXCEPTION 'admin_mfa_policy_receipt_immutable' USING ERRCODE='42501';END IF;
 IF NEW.action='admin.mfa.policy.transition' THEN
  IF session_user<>'postgres' OR current_setting('role',true) NOT IN('none','postgres') THEN
   RAISE EXCEPTION 'admin_mfa_policy_receipt_operator_required' USING ERRCODE='42501';END IF;
  PERFORM private._collect_fence_require_operator();
  IF NOT coalesce(NEW.request_id~'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$',false)
   OR NEW.entity_type<>'runtime_config' OR NEW.entity_id<>'security:admin_mfa_required:v1'
   OR NEW.details_json::jsonb->'version' IS DISTINCT FROM '1'::jsonb
   OR NOT EXISTS(SELECT 1 FROM app.runtime_config c WHERE c.key=NEW.entity_id
    AND c.revision::text=NEW.details_json::jsonb->>'after_revision'
    AND c.value_json::jsonb->'required'=NEW.details_json::jsonb->'required') THEN
   RAISE EXCEPTION 'admin_mfa_policy_receipt_changed' USING ERRCODE='42501';END IF;
 END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_transition_audit_guard_v1()
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER collect_admin_mfa_transition_audit_guard_v1 BEFORE INSERT OR UPDATE OR DELETE ON app.audit_log
 FOR EACH ROW EXECUTE FUNCTION private.collect_admin_mfa_transition_audit_guard_v1();
ALTER TABLE app.audit_log ENABLE ALWAYS TRIGGER collect_admin_mfa_transition_audit_guard_v1;

CREATE FUNCTION private.collect_admin_mfa_policy_transition_v1(
 p_operation uuid,p_source text,p_expected_revision bigint,p_owner text,p_factor uuid,p_qualification jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE readiness jsonb;keys text[];input_sha text;prior app.audit_log%ROWTYPE;prior_details jsonb;
 current_revision bigint;required boolean;target boolean;principal text;owner_session text;updated text;value text;
 old_commitment text:=current_setting('collect.admin_mfa_policy_commitment',true);details jsonb;source_exact boolean;source_epoch bigint;
 old_write_frame text:=current_setting('collect.admin_mfa_policy_write_frame',true);
 old_source text:=current_setting('collect.admin_mfa_policy_source',true);old_epoch text:=current_setting('collect.admin_mfa_policy_epoch',true);
BEGIN
 PERFORM private._collect_fence_require_rc(true);
 -- Match controller WORK→WRITE lock order and retain both locks to commit.
 -- Release/source replacement cannot pass us while policy/audit are in flight.
 PERFORM pg_advisory_xact_lock_shared(7346371,1);
 PERFORM pg_advisory_xact_lock_shared(7346371,2);
 PERFORM private._collect_fence_require_operator();
 IF session_user<>'postgres' OR current_setting('role',true) NOT IN('none','postgres')
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced') THEN
  RAISE EXCEPTION 'admin_mfa_activation_operator_required' USING ERRCODE='42501';END IF;
 IF p_operation IS NULL OR p_source IS NULL OR p_source!~'^[a-f0-9]{64}$' OR p_expected_revision IS NULL OR p_expected_revision<0
  OR p_owner IS NULL OR length(p_owner) NOT BETWEEN 1 AND 200 OR p_factor IS NULL OR jsonb_typeof(p_qualification) IS DISTINCT FROM 'object' THEN
  RAISE EXCEPTION 'admin_mfa_activation_input_invalid' USING ERRCODE='22023';END IF;
 SELECT array_agg(k ORDER BY k) INTO keys FROM jsonb_object_keys(p_qualification) k;
 IF keys IS DISTINCT FROM ARRAY['action','browser_qualification_sha256','configuration_sha256','owner_recovery_sha256','owner_setup_sha256','previous_operation','version']::text[]
  OR p_qualification->'version' IS DISTINCT FROM '1'::jsonb OR jsonb_typeof(p_qualification->'action') IS DISTINCT FROM 'string'
  OR p_qualification->>'action' NOT IN('activate','rollback')
  OR EXISTS(SELECT 1 FROM jsonb_each(p_qualification) e WHERE e.key LIKE '%sha256' AND(jsonb_typeof(e.value)<>'string' OR e.value#>>'{}'!~'^[a-f0-9]{64}$'))
  OR(p_qualification->>'action'='activate' AND p_qualification->'previous_operation'<>'null'::jsonb)
  OR(p_qualification->>'action'='rollback' AND NOT coalesce(p_qualification->>'previous_operation'~'^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$',false)) THEN
  RAISE EXCEPTION 'admin_mfa_activation_qualification_required' USING ERRCODE='22023';END IF;
 SELECT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND source_sha256=p_source) INTO source_exact;
 IF NOT source_exact THEN RAISE EXCEPTION 'admin_mfa_activation_source_changed' USING ERRCODE='42501';END IF;
 SELECT epoch INTO STRICT source_epoch FROM private.collect_fence_control WHERE singleton AND source_sha256=p_source AND mode='fenced';
 IF private._collect_fence_resources()->'capacityBlocked'='true'::jsonb THEN
  RAISE EXCEPTION 'collect_fence_capacity' USING ERRCODE='55000';END IF;
 target:=p_qualification->>'action'='activate';
 input_sha:=encode(sha256(convert_to(jsonb_build_object('operation',p_operation,'source',p_source,'expected_revision',p_expected_revision,
  'owner',p_owner,'factor',p_factor,'qualification',p_qualification)::text,'UTF8')),'hex');
 PERFORM pg_advisory_xact_lock(hashtextextended('collect-admin-mfa-policy-transition-v1',0));
 SELECT * INTO prior FROM app.audit_log WHERE request_id=p_operation::text AND action='admin.mfa.policy.transition';
 SELECT coalesce(max(revision),0) INTO current_revision FROM app.runtime_config WHERE key='security:admin_mfa_required:v1';
 required:=private.collect_admin_mfa_policy_enabled_v1();
 IF FOUND AND prior.id IS NOT NULL THEN
  prior_details:=prior.details_json::jsonb;
  IF prior_details->>'input_sha256' IS DISTINCT FROM input_sha THEN
   RAISE EXCEPTION 'admin_mfa_activation_operation_conflict' USING ERRCODE='42501';END IF;
  RETURN jsonb_build_object('version',1,'state','recorded','operation_id',p_operation,'required',required,'policy_revision',current_revision,
   'current_policy_matches',current_revision=(prior_details->>'after_revision')::bigint AND required=(prior_details->>'required')::boolean,
   'replayed_effect',false);
 END IF;
 IF current_revision<>p_expected_revision OR target=required THEN
  RAISE EXCEPTION 'admin_mfa_activation_revision_changed' USING ERRCODE='42501';END IF;
 SELECT l.user_id INTO principal FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id
  JOIN app.users product ON product.id=l.user_id AND product.access_status='active'
  JOIN private.auth_principal_links link ON link.user_id=l.user_id
  JOIN auth.users managed ON managed.id=link.auth_user_id AND managed.deleted_at IS NULL
   AND(managed.banned_until IS NULL OR managed.banned_until<=clock_timestamp())
  WHERE a.id=p_owner AND a.role='owner' AND a.status='active';
 IF principal IS NULL THEN RAISE EXCEPTION 'admin_mfa_activation_owner_required' USING ERRCODE='42501';END IF;
 IF target THEN
  readiness:=private.collect_admin_mfa_activation_readiness_v1(p_source,p_owner,p_factor);
  IF readiness->'ready' IS DISTINCT FROM 'true'::jsonb THEN
   RAISE EXCEPTION 'admin_mfa_activation_not_ready' USING ERRCODE='42501';END IF;
 ELSE
  IF NOT EXISTS(SELECT 1 FROM app.audit_log a WHERE a.request_id=p_qualification->>'previous_operation'
   AND a.action='admin.mfa.policy.transition' AND a.details_json::jsonb->'required'='true'::jsonb
   AND a.details_json::jsonb->>'after_revision'=current_revision::text) THEN
   RAISE EXCEPTION 'admin_mfa_activation_rollback_binding_changed' USING ERRCODE='42501';END IF;
 END IF;
 SELECT c.auth_session_id INTO owner_session FROM app.admin_sessions c JOIN app.admin_users a ON a.id=c.user_id
  WHERE a.id=p_owner AND c.expires_at>app.unixepoch() AND c.auth_version=a.auth_version
  ORDER BY c.created_at DESC,c.public_id LIMIT 1;
 value:=jsonb_build_object('version',1,'required',target)::text;
 updated:=to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
 PERFORM set_config('collect.admin_mfa_policy_commitment',encode(sha256(convert_to(jsonb_build_object('key','security:admin_mfa_required:v1',
  'value',value,'revision',current_revision+1,'by',principal,'at',updated)::text,'UTF8')),'hex'),true);
 PERFORM set_config('collect.admin_mfa_policy_source',p_source,true);
 PERFORM set_config('collect.admin_mfa_policy_epoch',source_epoch::text,true);
 PERFORM set_config('collect.admin_mfa_policy_write_frame','1',true);
 IF current_revision=0 THEN
  INSERT INTO app.runtime_config(key,value_json,revision,updated_by,updated_at)
  VALUES('security:admin_mfa_required:v1',value,1,principal,updated);
 ELSE
  UPDATE app.runtime_config SET value_json=value,revision=current_revision+1,updated_by=principal,updated_at=updated
   WHERE key='security:admin_mfa_required:v1' AND revision=current_revision;
  IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_activation_revision_changed' USING ERRCODE='42501';END IF;
 END IF;
 details:=jsonb_build_object('version',1,'input_sha256',input_sha,'source_sha256',p_source,'before_revision',current_revision,
  'after_revision',current_revision+1,'required',target,'qualification',p_qualification,
  'owner_id_sha256',encode(sha256(convert_to(p_owner,'UTF8')),'hex'),'factor_id_sha256',encode(sha256(convert_to(p_factor::text,'UTF8')),'hex'));
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
 VALUES(principal,owner_session,'admin.mfa.policy.transition','runtime_config','security:admin_mfa_required:v1',p_operation::text,details::text,updated);
 PERFORM set_config('collect.admin_mfa_policy_write_frame',coalesce(old_write_frame,''),true);
 PERFORM set_config('collect.admin_mfa_policy_source',coalesce(old_source,''),true);
 PERFORM set_config('collect.admin_mfa_policy_epoch',coalesce(old_epoch,''),true);
 PERFORM set_config('collect.admin_mfa_policy_commitment',coalesce(old_commitment,''),true);
 RETURN jsonb_build_object('version',1,'state','applied','operation_id',p_operation,'required',target,'policy_revision',current_revision+1,
  'replayed_effect',false,'qualification_evidence_supplied_by_operator',true);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('collect.admin_mfa_policy_write_frame',coalesce(old_write_frame,''),true);
 PERFORM set_config('collect.admin_mfa_policy_source',coalesce(old_source,''),true);
 PERFORM set_config('collect.admin_mfa_policy_epoch',coalesce(old_epoch,''),true);
 PERFORM set_config('collect.admin_mfa_policy_commitment',coalesce(old_commitment,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_policy_transition_v1(uuid,text,bigint,text,uuid,jsonb)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
COMMIT;
