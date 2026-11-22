-- UNVERIFIED DESIGN DRAFT. Do not register or deploy until independently reviewed
-- and the full synthetic chain and affected permission paths have passed.
-- Observations are private, encrypted, unparsed, unassigned, nonfinancial evidence.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR to_regprocedure('private.burimunsi_pin_context()') IS NULL
  OR to_regprocedure('private.burimunsi_pin_assert_actor(text,text,text,bigint,bigint)') IS NULL
  OR to_regprocedure('private.assert_storage_ready(text,text,text,text,text)') IS NULL
  OR to_regclass('private.burimunsi_observation_consents') IS NOT NULL
  OR to_regclass('private.burimunsi_detection_profiles') IS NOT NULL
  OR to_regclass('private.burimunsi_observation_requests') IS NOT NULL
  OR to_regclass('private.burimunsi_unresolved_observations') IS NOT NULL
  OR to_regprocedure('private.trg_storage_identity()') IS NULL
  OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid='private.trg_storage_identity()'::regprocedure AND pg_get_userbyid(p.proowner)='postgres'
    AND l.lanname='plpgsql' AND p.prokind='f' AND p.pronargs=0 AND p.prorettype='pg_catalog.trigger'::regtype
    AND NOT p.prosecdef AND NOT p.proleakproof AND p.provolatile='v' AND p.proparallel='u'
    AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='ccd10219b573a5e605a2fd8f0ddebfe9b7ebe3b7e1bb7844dfbaa4b9a95d2224')
  OR (SELECT count(*) FROM pg_trigger t WHERE NOT t.tgisinternal AND t.tgfoid='private.trg_storage_identity()'::regprocedure)<>6
  OR EXISTS(SELECT 1 FROM (VALUES
    ('private.storage_namespace','storage_namespace_identity',27),
    ('private.storage_payload_reservations','storage_payload_identity',27),
    ('private.storage_put_intents','storage_put_identity',27),
    ('private.storage_upload_attempts','storage_upload_identity',27),
    ('private.storage_delete_intents','storage_delete_identity',27),
    ('private.storage_objects','storage_object_identity',19)) expected(relation,name,kind)
   WHERE NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid=to_regclass(expected.relation)
    AND t.tgname=expected.name AND t.tgfoid='private.trg_storage_identity()'::regprocedure
    AND t.tgenabled='O' AND t.tgtype=expected.kind AND t.tgqual IS NULL AND t.tgnargs=0
    AND t.tgconstraint=0 AND NOT t.tgdeferrable AND NOT t.tginitdeferred AND t.tgparentid=0
    AND cardinality(t.tgattr::smallint[])=0 AND NOT t.tgisinternal))
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_observation_install_precondition' USING ERRCODE='55000';
 END IF;
END;$preflight$;

-- An operator-maintained collection filter only. This configuration never
-- changes a receiving account's approval and does not establish SMS origin,
-- ownership, recipient, or authority to create any financial transaction.
CREATE TABLE private.burimunsi_detection_profiles(
 collection_id text PRIMARY KEY REFERENCES private.burimunsi_scopes(collection_id),
 expected_receiving_account_id text NOT NULL REFERENCES app.momo_receiving_accounts(id),
 revision bigint NOT NULL CHECK(revision>0), enabled boolean NOT NULL,
 profile_version text NOT NULL CHECK(length(profile_version) BETWEEN 1 AND 80 AND profile_version<>'unverified' AND profile_version !~ '[[:cntrl:]]'),
 profile_json text NOT NULL CHECK(octet_length(profile_json) BETWEEN 2 AND 65536 AND jsonb_typeof(profile_json::jsonb)='object'),
 evidence_sha256 text NOT NULL CHECK(evidence_sha256 ~ '^[a-f0-9]{64}$'),
 configured_at bigint NOT NULL CHECK(configured_at>=0)
);
ALTER TABLE private.burimunsi_detection_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_detection_profiles FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_detection_profiles FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE POLICY burimunsi_detection_operator ON private.burimunsi_detection_profiles TO postgres
 USING(private._collect_fence_operator()) WITH CHECK(private._collect_fence_operator());
-- The definer may lock/read only while an already authenticated observation
-- frame is active. Its direct table privileges remain revoked from runtime.
CREATE POLICY burimunsi_detection_read ON private.burimunsi_detection_profiles FOR SELECT TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.observation_frame',true)='1');
CREATE POLICY burimunsi_detection_lock ON private.burimunsi_detection_profiles FOR UPDATE TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.observation_frame',true)='1') WITH CHECK(false);
-- Lock the collection before PostgreSQL locks an UPDATE target row. This
-- matches observation_context's scope-then-profile order and also fences the
-- absence of a row against concurrent inserts. The statement trigger name is
-- ordered after the existing application-fence statement trigger.
CREATE FUNCTION private.burimunsi_detection_statement_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
DECLARE cid text:=nullif(current_setting('burimunsi.collection_id',true),'');
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF cid IS NULL THEN RAISE EXCEPTION 'burimunsi_detection_scope_required' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM private.burimunsi_scopes WHERE collection_id=cid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_detection_scope_changed' USING ERRCODE='40001';END IF;
 RETURN NULL;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_detection_statement_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE FUNCTION private.burimunsi_detection_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
DECLARE scoped_account text;old_group text:=current_setting('burimunsi.collection_id',true);
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NEW.collection_id IS DISTINCT FROM old_group THEN
  RAISE EXCEPTION 'burimunsi_detection_scope_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.collection_id',NEW.collection_id,true);
 SELECT receiving_account_id INTO scoped_account FROM private.burimunsi_scopes
  WHERE collection_id=NEW.collection_id FOR UPDATE;
 IF NOT FOUND OR scoped_account IS DISTINCT FROM NEW.expected_receiving_account_id THEN
  RAISE EXCEPTION 'burimunsi_detection_scope_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 IF TG_OP='UPDATE' AND (NEW.collection_id IS DISTINCT FROM OLD.collection_id OR NEW.revision<>OLD.revision+1
  OR NEW.configured_at<OLD.configured_at) THEN
  RAISE EXCEPTION 'burimunsi_detection_version_changed' USING ERRCODE='40001';END IF;
 RETURN NEW;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_detection_guard() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_detection_guard BEFORE INSERT OR UPDATE ON private.burimunsi_detection_profiles FOR EACH ROW EXECUTE FUNCTION private.burimunsi_detection_guard();
ALTER TABLE private.burimunsi_detection_profiles ENABLE ALWAYS TRIGGER burimunsi_detection_guard;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_detection_profiles FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.burimunsi_detection_profiles ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE TRIGGER z_burimunsi_detection_statement BEFORE INSERT OR UPDATE ON private.burimunsi_detection_profiles FOR EACH STATEMENT EXECUTE FUNCTION private.burimunsi_detection_statement_guard();
ALTER TABLE private.burimunsi_detection_profiles ENABLE ALWAYS TRIGGER z_burimunsi_detection_statement;
CREATE TRIGGER burimunsi_detection_retain BEFORE DELETE OR TRUNCATE ON private.burimunsi_detection_profiles FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_detection_profiles ENABLE ALWAYS TRIGGER burimunsi_detection_retain;

CREATE TABLE private.burimunsi_observation_consents(
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 account_id uuid NOT NULL,installation_id uuid NOT NULL,grant_id uuid NOT NULL,
 grant_version bigint NOT NULL CHECK(grant_version>0),generation bigint NOT NULL CHECK(generation BETWEEN 1 AND 9007199254740991),
 enabled boolean NOT NULL,updated_at bigint NOT NULL CHECK(updated_at>=0),
 PRIMARY KEY(collection_id,account_id,installation_id),
 FOREIGN KEY(account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id),
 FOREIGN KEY(grant_id,collection_id) REFERENCES private.burimunsi_device_grants(id,collection_id)
);
-- A request is charged before any protected-storage PUT. A pending intent is
-- immutable and stays visible until this same request obtains a durable source.
CREATE TABLE private.burimunsi_observation_requests(
 source_id text PRIMARY KEY CHECK(source_id ~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 account_id uuid NOT NULL,principal_user_id text NOT NULL REFERENCES app.users(id),
 installation_id uuid NOT NULL,grant_id uuid NOT NULL,grant_version bigint NOT NULL CHECK(grant_version>0),
 native_session_id uuid NOT NULL REFERENCES private.burimunsi_sessions(id),request_id uuid NOT NULL,
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 initial_profile_version text NOT NULL CHECK(length(initial_profile_version) BETWEEN 1 AND 128),
 initial_profile_sha256 text NOT NULL CHECK(initial_profile_sha256 ~ '^[a-f0-9]{64}$'),
 initial_profile_tuple_sha256 text NOT NULL CHECK(initial_profile_tuple_sha256 ~ '^[a-f0-9]{64}$'),
 initial_consent_generation bigint NOT NULL CHECK(initial_consent_generation>0),
 created_at bigint NOT NULL CHECK(created_at>=0),UNIQUE(collection_id,account_id,request_id),
 FOREIGN KEY(account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id),
 FOREIGN KEY(grant_id,collection_id) REFERENCES private.burimunsi_device_grants(id,collection_id)
);
CREATE INDEX burimunsi_observation_request_budget ON private.burimunsi_observation_requests(principal_user_id,created_at);
CREATE TABLE private.burimunsi_unresolved_observations(
 source_id text PRIMARY KEY REFERENCES private.burimunsi_observation_requests(source_id) CHECK(source_id ~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 account_id uuid NOT NULL,principal_user_id text NOT NULL REFERENCES app.users(id),
 installation_id uuid NOT NULL,grant_id uuid NOT NULL,grant_version bigint NOT NULL CHECK(grant_version>0),
 native_session_id uuid NOT NULL REFERENCES private.burimunsi_sessions(id),
 request_id uuid NOT NULL,fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 body_sha256 text NOT NULL CHECK(body_sha256 ~ '^[a-f0-9]{64}$'),
 object_key text NOT NULL UNIQUE CHECK(object_key='sms/'||source_id),
 object_sha256 text NOT NULL CHECK(object_sha256 ~ '^[a-f0-9]{64}$'),
 size_bytes bigint NOT NULL CHECK(size_bytes BETWEEN 1 AND 131072),
 profile_version text NOT NULL CHECK(length(profile_version) BETWEEN 1 AND 128),
 profile_sha256 text NOT NULL CHECK(profile_sha256 ~ '^[a-f0-9]{64}$'),
 profile_tuple_sha256 text NOT NULL CHECK(profile_tuple_sha256 ~ '^[a-f0-9]{64}$'),
 consent_generation bigint NOT NULL CHECK(consent_generation>0),
 created_at bigint NOT NULL CHECK(created_at>=0),UNIQUE(collection_id,account_id,request_id),
 FOREIGN KEY(account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id),
 FOREIGN KEY(grant_id,collection_id) REFERENCES private.burimunsi_device_grants(id,collection_id)
);
CREATE INDEX burimunsi_observation_own_page ON private.burimunsi_unresolved_observations
 (collection_id,account_id,installation_id,grant_id,created_at DESC,source_id);
CREATE INDEX burimunsi_observation_budget ON private.burimunsi_unresolved_observations(principal_user_id,created_at);
DO $policy$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['burimunsi_observation_consents','burimunsi_observation_requests','burimunsi_unresolved_observations'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE private.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime',t);
  EXECUTE format('CREATE POLICY burimunsi_observation_owner_frame ON private.%I TO postgres USING(current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''burimunsi.observation_frame'',true)=''1'') WITH CHECK(current_setting(''role'',true)=''collect_runtime'' AND current_setting(''collect.edge_verified'',true)=''true'' AND current_setting(''burimunsi.observation_frame'',true)=''1'')',t);
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',t);
  EXECUTE format('CREATE TRIGGER burimunsi_observation_retain BEFORE DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER burimunsi_observation_retain',t);
 END LOOP;
END;$policy$;
CREATE TRIGGER burimunsi_observation_request_immutable BEFORE UPDATE ON private.burimunsi_observation_requests
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_observation_requests ENABLE ALWAYS TRIGGER burimunsi_observation_request_immutable;
CREATE TRIGGER burimunsi_observation_immutable BEFORE UPDATE ON private.burimunsi_unresolved_observations
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_unresolved_observations ENABLE ALWAYS TRIGGER burimunsi_observation_immutable;
-- Internal preflight for the added storage-payload clear condition. Outside
-- the already fenced observation commit frame it is always false; no caller
-- receives access to observation rows or a generalized clearing capability.
CREATE FUNCTION private.burimunsi_observation_storage_matches(p_key text,p_scope jsonb,p_plain text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'collect_runtime'
  OR current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true'
  OR current_setting('burimunsi.observation_frame',true) IS DISTINCT FROM '1' THEN RETURN false;END IF;
 RETURN EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations r
  JOIN private.storage_put_intents i ON i.object_key=r.object_key
  JOIN private.storage_objects o ON o.object_key=i.object_key AND o.operation_id=i.operation_id
  WHERE r.object_key=p_key AND r.object_sha256=p_plain
   AND p_scope=jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id)
   AND i.scope=p_scope AND o.scope=p_scope AND i.state='committed' AND NOT i.delete_tombstone
   AND NOT i.upload_unresolved AND i.active_attempt IS NULL AND i.sha256=o.sha256 AND i.size=o.size
   AND i.http_metadata=o.http_metadata AND i.custom_metadata=o.custom_metadata
   AND o.custom_metadata->>'sha256'=r.object_sha256
   AND NOT EXISTS(SELECT 1 FROM private.storage_delete_intents d WHERE d.object_key=r.object_key));
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_storage_matches(text,jsonb,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_storage_matches(text,jsonb,text) TO collect_runtime;

-- The exact reviewed predecessor remains byte-for-byte intact except for the
-- additional private-observation clear predicate. Existing trigger objects and
-- their verified enabled modes are preserved.
CREATE OR REPLACE FUNCTION private.trg_storage_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $storage_identity$
DECLARE old_json jsonb;new_json jsonb;mutable text[];
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'retain_storage_control_identity' USING ERRCODE='42501'; END IF;
 mutable:=CASE TG_TABLE_NAME
  WHEN 'storage_put_intents' THEN ARRAY['state','attempts','active_attempt','upload_unresolved','delete_tombstone','last_outcome','updated_at']
  WHEN 'storage_upload_attempts' THEN ARRAY['outcome','completed_at']
  WHEN 'storage_delete_intents' THEN ARRAY['state','last_outcome','absence_proof','committed_at']
  WHEN 'storage_payload_reservations' THEN ARRAY['sealed_body','cleared_at']
  ELSE ARRAY[]::text[] END;
 old_json:=to_jsonb(OLD);new_json:=to_jsonb(NEW);
 IF old_json-mutable IS DISTINCT FROM new_json-mutable THEN RAISE EXCEPTION 'immutable_storage_identity' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='storage_namespace' THEN RAISE EXCEPTION 'immutable_storage_namespace' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='storage_payload_reservations' THEN
  IF OLD.sealed_body IS NULL OR NEW.sealed_body IS NOT NULL OR NEW.cleared_at IS NULL THEN RAISE EXCEPTION 'immutable_storage_payload' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM app.sms_receipts r WHERE r.object_key=OLD.object_key AND r.id=OLD.scope->>'entityId' AND r.owner_user_id=OLD.scope->>'ownerId' AND r.object_sha256=OLD.plaintext_sha256)
   AND NOT EXISTS(SELECT 1 FROM app.payment_evidence r WHERE r.object_key=OLD.object_key AND r.id=OLD.scope->>'entityId' AND r.owner_user_id=OLD.scope->>'ownerId' AND r.object_sha256=OLD.plaintext_sha256)
   AND NOT EXISTS(SELECT 1 FROM app.roster_imports r WHERE r.source_object_key=OLD.object_key AND r.id=OLD.scope->>'entityId' AND r.user_id=OLD.scope->>'ownerId' AND r.source_sha256=OLD.plaintext_sha256 AND r.state='retained')
   AND NOT private.burimunsi_observation_storage_matches(OLD.object_key,OLD.scope,OLD.plaintext_sha256)
   AND NOT EXISTS(SELECT 1 FROM private.storage_put_intents i JOIN private.storage_delete_intents d ON d.object_key=i.object_key WHERE i.object_key=OLD.object_key AND i.state='erased' AND i.delete_tombstone AND d.state='committed' AND d.absence_proof @> '{"headStatus":404,"getStatus":404,"bucketVerified":true}'::jsonb)
  THEN RAISE EXCEPTION 'storage_payload_clear_requires_application_or_erasure_commit' USING ERRCODE='42501'; END IF;
 ELSIF TG_TABLE_NAME='storage_put_intents' THEN
  IF (OLD.delete_tombstone AND NOT NEW.delete_tombstone) OR (OLD.upload_unresolved AND NOT NEW.upload_unresolved) OR NEW.attempts<OLD.attempts OR (OLD.state='erased' AND NEW.state<>'erased') OR (OLD.state='committed' AND NEW.state='pending') THEN RAISE EXCEPTION 'storage_state_regression' USING ERRCODE='42501'; END IF;
  IF (NEW.delete_tombstone AND NOT OLD.delete_tombstone) OR (NEW.state='erased' AND OLD.state<>'erased') THEN PERFORM private.assert_storage_delete_authorized(NEW.object_key); END IF;
 ELSIF TG_TABLE_NAME='storage_delete_intents' THEN
  IF OLD.state='committed' AND old_json IS DISTINCT FROM new_json THEN RAISE EXCEPTION 'immutable_storage_delete_result' USING ERRCODE='42501'; END IF;
 ELSIF TG_TABLE_NAME='storage_upload_attempts' THEN
  IF OLD.completed_at IS NOT NULL AND old_json IS DISTINCT FROM new_json THEN RAISE EXCEPTION 'immutable_storage_attempt_result' USING ERRCODE='42501'; END IF;
 END IF;
 RETURN NEW;
END$storage_identity$;

-- Existing generic erasure recognizes only canonical reference classes. This
-- private source gets an additional fail-closed erasure guard, without changing
-- how other storage objects are handled.
CREATE POLICY burimunsi_observation_storage_guard ON private.burimunsi_unresolved_observations TO postgres
 USING(current_setting('burimunsi.storage_guard',true)='1');
CREATE FUNCTION private.burimunsi_observation_retain_storage() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE k text;held boolean;old_guard text:=current_setting('burimunsi.storage_guard',true);
BEGIN
 IF TG_TABLE_NAME='storage_put_intents' THEN
  IF NOT(NEW.delete_tombstone OR NEW.state='erased') THEN RETURN NEW;END IF;
 END IF;
 k:=CASE WHEN TG_OP='DELETE' THEN OLD.object_key ELSE NEW.object_key END;
 PERFORM pg_advisory_xact_lock(hashtextextended(k,7346369));
 PERFORM set_config('burimunsi.storage_guard','1',true);
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations r WHERE r.object_key=k) INTO held;
 PERFORM set_config('burimunsi.storage_guard',coalesce(old_guard,''),true);
 IF held THEN RAISE EXCEPTION 'burimunsi_observation_retained' USING ERRCODE='42501';END IF;
 IF TG_OP='DELETE' THEN RETURN OLD;END IF;RETURN NEW;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.storage_guard',coalesce(old_guard,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_retain_storage()
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_observation_retained_put BEFORE UPDATE ON private.storage_put_intents
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_observation_retain_storage();
ALTER TABLE private.storage_put_intents ENABLE ALWAYS TRIGGER burimunsi_observation_retained_put;
CREATE TRIGGER burimunsi_observation_retained_delete BEFORE INSERT OR UPDATE ON private.storage_delete_intents
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_observation_retain_storage();
ALTER TABLE private.storage_delete_intents ENABLE ALWAYS TRIGGER burimunsi_observation_retained_delete;
CREATE TRIGGER burimunsi_observation_retained_object BEFORE DELETE ON private.storage_objects
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_observation_retain_storage();
ALTER TABLE private.storage_objects ENABLE ALWAYS TRIGGER burimunsi_observation_retained_object;

CREATE FUNCTION private.burimunsi_observation_storage_commit() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM private.assert_storage_ready(NEW.object_key,NEW.principal_user_id,NEW.source_id,NEW.object_sha256,'sms_receipt');
 UPDATE private.storage_payload_reservations SET sealed_body=NULL,cleared_at=clock_timestamp()
  WHERE object_key=NEW.object_key AND sealed_body IS NOT NULL;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER burimunsi_observation_storage_commit AFTER INSERT ON private.burimunsi_unresolved_observations
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_observation_storage_commit();

-- This NEW authority applies only to an account's own consenting installation.
-- It never changes or authorizes the existing paired-receiver reader or posting.
CREATE FUNCTION private.burimunsi_observation_actor(p_reveal boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a record;perm text;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 IF p_reveal IS NULL THEN RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 SELECT * INTO a FROM private.burimunsi_pin_context();
 IF NOT FOUND OR a.role<>'admin' OR a.profile<>'internal_receiver'
  OR NOT('sms.read'=ANY(a.capabilities)) OR NOT('gateway.manage'=ANY(a.capabilities)) THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 PERFORM private.burimunsi_pin_assert_actor(NULL,a.collection_id,'admin',1,NULL);
 SELECT * INTO a FROM private.burimunsi_pin_context();
 IF NOT FOUND OR a.role<>'admin' OR a.profile<>'internal_receiver'
  OR NOT('sms.read'=ANY(a.capabilities)) OR NOT('gateway.manage'=ANY(a.capabilities)) THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM private.burimunsi_scopes s JOIN app.collections c ON c.id=s.collection_id AND c.status='active'
   WHERE s.collection_id=a.collection_id AND (s.enabled OR s.active_binding_id IS NULL)) THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 FOREACH perm IN ARRAY CASE WHEN p_reveal THEN ARRAY['sms.read','sms.reveal'] ELSE ARRAY['sms.read'] END LOOP
  IF current_setting('transaction_read_only')='off' THEN
   PERFORM 1 FROM app.admin_grants WHERE user_id=a.principal_user_id AND permission=perm FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
   PERFORM 1 FROM app.admin_account_role_capabilities WHERE role=a.shared_role AND permission=perm FOR SHARE;
   IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
  ELSIF NOT EXISTS(SELECT 1 FROM app.admin_grants g JOIN app.admin_account_role_capabilities r ON r.permission=g.permission
       AND r.role=a.shared_role WHERE g.user_id=a.principal_user_id AND g.permission=perm) THEN
   RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';
  END IF;
 END LOOP;
 RETURN jsonb_build_object('collectionId',a.collection_id,'accountId',a.account_id,'principalUserId',a.principal_user_id,
  'sessionId',a.native_session_id,'installationId',a.installation_id,'grantId',a.grant_id,'grantVersion',a.grant_version);
END;$fn$;

CREATE FUNCTION private.burimunsi_observation_consent_current() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(false);c private.burimunsi_observation_consents%ROWTYPE;
 old_frame text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO c FROM private.burimunsi_observation_consents WHERE collection_id=a->>'collectionId'
  AND account_id=(a->>'accountId')::uuid AND installation_id=(a->>'installationId')::uuid;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('enabled',coalesce(c.enabled AND c.grant_id=(a->>'grantId')::uuid AND c.grant_version=(a->>'grantVersion')::bigint,false),
  'generation',coalesce(c.generation,0));
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

CREATE FUNCTION private.burimunsi_observation_set_consent(p_enabled boolean,p_generation bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;c private.burimunsi_observation_consents%ROWTYPE;has_row boolean;
 old_frame text:=current_setting('burimunsi.observation_frame',true);at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 PERFORM private.burimunsi_setup_fence();a:=private.burimunsi_observation_actor(false);
 IF p_enabled IS NULL OR p_generation IS NULL OR p_generation NOT BETWEEN 1 AND 9007199254740991 THEN
  RAISE EXCEPTION 'burimunsi_observation_consent_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO c FROM private.burimunsi_observation_consents WHERE collection_id=a->>'collectionId'
  AND account_id=(a->>'accountId')::uuid AND installation_id=(a->>'installationId')::uuid FOR UPDATE;
 has_row:=FOUND;
 IF has_row AND (p_generation<c.generation OR p_generation=c.generation AND
   (c.enabled IS DISTINCT FROM p_enabled OR c.grant_id IS DISTINCT FROM (a->>'grantId')::uuid OR c.grant_version IS DISTINCT FROM (a->>'grantVersion')::bigint)) THEN
  RAISE EXCEPTION 'burimunsi_observation_consent_changed' USING ERRCODE='40001';END IF;
 IF NOT has_row THEN
  INSERT INTO private.burimunsi_observation_consents(collection_id,account_id,installation_id,grant_id,grant_version,generation,enabled,updated_at)
   VALUES(a->>'collectionId',(a->>'accountId')::uuid,(a->>'installationId')::uuid,(a->>'grantId')::uuid,(a->>'grantVersion')::bigint,p_generation,p_enabled,at_ms);
 ELSIF p_generation>c.generation THEN
  UPDATE private.burimunsi_observation_consents SET grant_id=(a->>'grantId')::uuid,grant_version=(a->>'grantVersion')::bigint,
   generation=p_generation,enabled=p_enabled,updated_at=at_ms WHERE collection_id=c.collection_id AND account_id=c.account_id AND installation_id=c.installation_id;
 END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('enabled',p_enabled,'generation',p_generation);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Exactly one approved provider profile is only a candidate filter, never
-- evidence of a receiver or a reason to post.
CREATE FUNCTION private.burimunsi_observation_context() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(false);c jsonb:=private.burimunsi_observation_consent_current();w record;d record;
 old_frame text:=current_setting('burimunsi.observation_frame',true);snapshot jsonb;
BEGIN
 IF c->'enabled' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'burimunsi_observation_consent_required' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 IF current_setting('transaction_read_only')='off' THEN
  PERFORM 1 FROM private.burimunsi_scopes s JOIN app.momo_receiving_accounts r ON r.id=s.receiving_account_id
   WHERE s.collection_id=a->>'collectionId' AND (s.enabled OR s.active_binding_id IS NULL) FOR SHARE OF s,r;
 END IF;
 SELECT r.id,r.provider,r.status,r.profile_status,r.profile_version,r.profile_json,r.currency,r.timezone INTO w
 FROM private.burimunsi_scopes s JOIN app.momo_receiving_accounts r ON r.id=s.receiving_account_id
 WHERE s.collection_id=a->>'collectionId' AND (s.enabled OR s.active_binding_id IS NULL);
 IF NOT FOUND OR w.status<>'active' THEN RAISE EXCEPTION 'burimunsi_observation_profile_unavailable' USING ERRCODE='55000';END IF;
 IF current_setting('transaction_read_only')='off' THEN
  SELECT * INTO d FROM private.burimunsi_detection_profiles WHERE collection_id=a->>'collectionId' FOR SHARE;
 ELSE
  SELECT * INTO d FROM private.burimunsi_detection_profiles WHERE collection_id=a->>'collectionId';
 END IF;
 IF FOUND THEN
  IF NOT d.enabled OR d.expected_receiving_account_id IS DISTINCT FROM w.id THEN
   RAISE EXCEPTION 'burimunsi_observation_profile_unavailable' USING ERRCODE='55000';END IF;
  -- "approved" here means only that the operator supplied this separate
  -- detection profile; it is an input to the filter grammar validator and is
  -- never persisted on the receiving account or exposed as account approval.
  snapshot:=jsonb_build_object('profile_kind','detection_only','status',w.status,'profile_status','approved',
   'provider',w.provider,'profile_version',d.profile_version,'profile_json',d.profile_json,'currency',w.currency,'timezone',w.timezone,
   'profile_sha256',encode(sha256(convert_to(d.profile_json,'UTF8')),'hex'),
   'profile_tuple_sha256',encode(sha256(convert_to(jsonb_build_array('detection_only',w.id,w.provider,w.status,w.profile_status,
    w.profile_version,w.profile_json,w.currency,w.timezone,d.revision,d.enabled,d.profile_version,d.profile_json,d.evidence_sha256)::text,'UTF8')),'hex'));
 ELSE
  IF w.profile_status<>'approved' OR w.profile_version IS NULL OR w.profile_version='unverified' THEN
   RAISE EXCEPTION 'burimunsi_observation_profile_unavailable' USING ERRCODE='55000';END IF;
  snapshot:=jsonb_build_object('profile_kind','canonical','status',w.status,'profile_status',w.profile_status,
   'provider',w.provider,'profile_version',w.profile_version,'profile_json',w.profile_json,'currency',w.currency,'timezone',w.timezone,
   'profile_sha256',encode(sha256(convert_to(w.profile_json,'UTF8')),'hex'),
   'profile_tuple_sha256',encode(sha256(convert_to(jsonb_build_array(w.id,w.provider,w.status,w.profile_status,w.profile_version,w.profile_json,w.currency,w.timezone)::text,'UTF8')),'hex'));
 END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN a||jsonb_build_object('consentGeneration',(c->>'generation')::bigint)||snapshot;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- A globally serialized, durable, per-owner admission precedes every PUT.
-- Pending intents never expire or vanish merely because an outcome is unknown;
-- a retry must use exactly the same source/request fingerprint.
CREATE FUNCTION private.burimunsi_observation_prepare(p_request uuid,p_fingerprint text,p_source text,
 p_profile_version text,p_profile_sha text,p_consent_generation bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;ctx jsonb;prior private.burimunsi_observation_requests%ROWTYPE;h text;expected_id text;
 old_frame text:=current_setting('burimunsi.observation_frame',true);at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 PERFORM private.burimunsi_setup_fence();a:=private.burimunsi_observation_actor(false);ctx:=private.burimunsi_observation_context();
 IF p_request IS NULL OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$'
  OR p_profile_sha IS NULL OR p_profile_sha !~ '^[a-f0-9]{64}$' OR p_profile_version IS NULL
  OR length(p_profile_version) NOT BETWEEN 1 AND 128 OR p_consent_generation IS NULL OR p_consent_generation<1 THEN
  RAISE EXCEPTION 'burimunsi_observation_invalid' USING ERRCODE='22023';END IF;
 IF ctx->>'profile_version' IS DISTINCT FROM p_profile_version OR ctx->>'profile_sha256' IS DISTINCT FROM p_profile_sha
  OR (ctx->>'consentGeneration')::bigint IS DISTINCT FROM p_consent_generation THEN
  RAISE EXCEPTION 'burimunsi_observation_profile_changed' USING ERRCODE='40001';END IF;
 h:=encode(sha256(convert_to('collect.storage.entity.v1'||E'\n'||'burimunsi.native.observation.v1'||E'\n'||(a->>'principalUserId')||E'\n'||p_request::text,'UTF8')),'hex');
 expected_id:=substr(h,1,8)||'-'||substr(h,9,4)||'-5'||substr(h,14,3)||'-8'||substr(h,18,3)||'-'||substr(h,21,12);
 IF p_source IS DISTINCT FROM expected_id THEN RAISE EXCEPTION 'burimunsi_observation_invalid' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(a->>'principalUserId',7346370));
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO prior FROM private.burimunsi_observation_requests WHERE collection_id=a->>'collectionId'
  AND account_id=(a->>'accountId')::uuid AND request_id=p_request FOR UPDATE;
 IF FOUND THEN
  IF prior.source_id IS DISTINCT FROM p_source OR prior.fingerprint IS DISTINCT FROM p_fingerprint
   OR prior.principal_user_id IS DISTINCT FROM a->>'principalUserId' OR prior.installation_id IS DISTINCT FROM (a->>'installationId')::uuid
   OR prior.grant_id IS DISTINCT FROM (a->>'grantId')::uuid OR prior.grant_version IS DISTINCT FROM (a->>'grantVersion')::bigint THEN
   RAISE EXCEPTION 'burimunsi_observation_conflict' USING ERRCODE='23505';END IF;
  IF prior.initial_profile_tuple_sha256 IS DISTINCT FROM ctx->>'profile_tuple_sha256' THEN
   RAISE EXCEPTION 'burimunsi_observation_profile_changed' USING ERRCODE='40001';END IF;
 ELSE
  IF (SELECT count(*) FROM private.burimunsi_observation_requests r WHERE r.principal_user_id=a->>'principalUserId'
    AND NOT EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations o WHERE o.source_id=r.source_id))>=16
   OR (SELECT count(*) FROM private.burimunsi_observation_requests WHERE principal_user_id=a->>'principalUserId' AND created_at>=at_ms-60000)>=60
   OR (SELECT count(*) FROM private.burimunsi_observation_requests WHERE principal_user_id=a->>'principalUserId' AND created_at>=at_ms-86400000)>=1000 THEN
   RAISE EXCEPTION 'burimunsi_observation_budget' USING ERRCODE='54000';END IF;
  INSERT INTO private.burimunsi_observation_requests(source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,
   native_session_id,request_id,fingerprint,initial_profile_version,initial_profile_sha256,initial_profile_tuple_sha256,initial_consent_generation,created_at)
  VALUES(p_source,a->>'collectionId',(a->>'accountId')::uuid,a->>'principalUserId',(a->>'installationId')::uuid,
   (a->>'grantId')::uuid,(a->>'grantVersion')::bigint,(a->>'sessionId')::uuid,p_request,p_fingerprint,p_profile_version,
   p_profile_sha,ctx->>'profile_tuple_sha256',p_consent_generation,at_ms);
 END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN ctx||jsonb_build_object('sourceId',p_source,'requestId',p_request,'fingerprint',p_fingerprint);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- A proof for the active account and the same consented installation only.
CREATE FUNCTION private.burimunsi_observation_own(p_source text,p_reveal boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(p_reveal);c jsonb:=private.burimunsi_observation_consent_current();
 r private.burimunsi_unresolved_observations%ROWTYPE;old_frame text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 IF c->'enabled' IS DISTINCT FROM 'true'::jsonb OR p_source IS NULL THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO r FROM private.burimunsi_unresolved_observations WHERE source_id=p_source AND collection_id=a->>'collectionId'
  AND account_id=(a->>'accountId')::uuid AND principal_user_id=a->>'principalUserId' AND installation_id=(a->>'installationId')::uuid
  AND grant_id=(a->>'grantId')::uuid AND grant_version=(a->>'grantVersion')::bigint;
 IF NOT FOUND THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RETURN NULL;END IF;
 IF NOT EXISTS(SELECT 1 FROM private.storage_objects o JOIN private.storage_put_intents p ON p.object_key=o.object_key
    WHERE o.object_key=r.object_key AND o.operation_id=p.operation_id AND p.state='committed' AND NOT p.delete_tombstone
     AND NOT p.upload_unresolved AND p.active_attempt IS NULL AND o.sha256=p.sha256 AND o.size=p.size AND o.scope=p.scope
     AND o.scope=jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id)
     AND o.custom_metadata->>'sha256'=r.object_sha256
     AND NOT EXISTS(SELECT 1 FROM private.storage_delete_intents d WHERE d.object_key=r.object_key)) THEN
  RAISE EXCEPTION 'burimunsi_observation_storage_changed' USING ERRCODE='55000';END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('sourceId',r.source_id,'requestId',r.request_id,'bodySha256',r.body_sha256,
  'object_key',r.object_key,'object_sha256',r.object_sha256,'size_bytes',r.size_bytes,'id',r.source_id,
  'createdAt',r.created_at,'principalUserId',r.principal_user_id,'sessionId',a->>'sessionId',
  'consentGeneration',(c->>'generation')::bigint,'fingerprint',r.fingerprint);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Optional display hints use only the currently approved profile whose exact
-- JSON hash/version and full provider tuple match the immutable capture. The existing own-source
-- and consent/reveal checks remain the authority; no receiving wallet is sent.
CREATE FUNCTION private.burimunsi_observation_hint_profile(p_source text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(true);own jsonb;v jsonb;
 old_frame text:=current_setting('burimunsi.observation_frame',true);
 old_pin text:=current_setting('burimunsi.pin_frame',true);
BEGIN
 own:=private.burimunsi_observation_own(p_source,true);IF own IS NULL THEN RETURN NULL;END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);PERFORM set_config('burimunsi.pin_frame','1',true);
 -- Profile writers take the scope before the detection row. Acquire these
 -- locks explicitly in that order, including the no-profile insertion gap.
 PERFORM 1 FROM private.burimunsi_scopes s JOIN app.momo_receiving_accounts w ON w.id=s.receiving_account_id
  WHERE s.collection_id=a->>'collectionId' FOR SHARE OF s,w;
 PERFORM 1 FROM private.burimunsi_detection_profiles d WHERE d.collection_id=a->>'collectionId' FOR SHARE;
 SELECT jsonb_build_object('profileSha256',r.profile_sha256,'profile',jsonb_build_object(
  'provider',w.provider,'status',w.status,'profile_status',w.profile_status,'profile_version',w.profile_version,
  'profile_json',w.profile_json,'currency',w.currency,'timezone',w.timezone)) INTO v
 FROM private.burimunsi_unresolved_observations r
 JOIN private.burimunsi_scopes s ON s.collection_id=r.collection_id
 JOIN app.momo_receiving_accounts w ON w.id=s.receiving_account_id
 WHERE r.source_id=p_source AND r.collection_id=a->>'collectionId' AND r.account_id=(a->>'accountId')::uuid
  AND r.principal_user_id=a->>'principalUserId' AND r.installation_id=(a->>'installationId')::uuid
  AND r.grant_id=(a->>'grantId')::uuid AND r.grant_version=(a->>'grantVersion')::bigint
  AND (s.enabled OR s.active_binding_id IS NULL) AND w.status='active' AND w.profile_status='approved'
  AND NOT EXISTS(SELECT 1 FROM private.burimunsi_detection_profiles active_filter WHERE active_filter.collection_id=r.collection_id)
  AND w.profile_version=r.profile_version AND encode(sha256(convert_to(w.profile_json,'UTF8')),'hex')=r.profile_sha256
  AND encode(sha256(convert_to(jsonb_build_array(w.id,w.provider,w.status,w.profile_status,w.profile_version,w.profile_json,w.currency,w.timezone)::text,'UTF8')),'hex')=r.profile_tuple_sha256
 FOR SHARE OF r,s,w;
 -- An independently configured detection-only tuple can support provisional
 -- display quotations, but never receiving-account approval or attribution.
 IF v IS NULL THEN
  SELECT jsonb_build_object('profileSha256',r.profile_sha256,'profile',jsonb_build_object(
   'provider',w.provider,'status',w.status,'profile_status','approved','profile_version',d.profile_version,
   'profile_json',d.profile_json,'currency',w.currency,'timezone',w.timezone)) INTO v
  FROM private.burimunsi_unresolved_observations r
  JOIN private.burimunsi_scopes s ON s.collection_id=r.collection_id
  JOIN app.momo_receiving_accounts w ON w.id=s.receiving_account_id
  JOIN private.burimunsi_detection_profiles d ON d.collection_id=r.collection_id
  WHERE r.source_id=p_source AND r.collection_id=a->>'collectionId' AND r.account_id=(a->>'accountId')::uuid
   AND r.principal_user_id=a->>'principalUserId' AND r.installation_id=(a->>'installationId')::uuid
   AND r.grant_id=(a->>'grantId')::uuid AND r.grant_version=(a->>'grantVersion')::bigint
   AND (s.enabled OR s.active_binding_id IS NULL) AND w.status='active' AND d.enabled
   AND d.expected_receiving_account_id=w.id AND d.profile_version=r.profile_version
   AND encode(sha256(convert_to(d.profile_json,'UTF8')),'hex')=r.profile_sha256
   AND encode(sha256(convert_to(jsonb_build_array('detection_only',w.id,w.provider,w.status,w.profile_status,
    w.profile_version,w.profile_json,w.currency,w.timezone,d.revision,d.enabled,d.profile_version,d.profile_json,d.evidence_sha256)::text,'UTF8')),'hex')=r.profile_tuple_sha256
  FOR SHARE OF r,s,w,d;
 END IF;
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RETURN v;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_pin,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

CREATE FUNCTION private.burimunsi_observation_lookup(p_request uuid,p_fingerprint text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(false);c jsonb:=private.burimunsi_observation_consent_current();
 r private.burimunsi_unresolved_observations%ROWTYPE;old_frame text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 IF c->'enabled' IS DISTINCT FROM 'true'::jsonb OR p_request IS NULL OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 SELECT * INTO r FROM private.burimunsi_unresolved_observations WHERE collection_id=a->>'collectionId'
  AND account_id=(a->>'accountId')::uuid AND request_id=p_request;
 IF NOT FOUND THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RETURN NULL;END IF;
 IF r.installation_id IS DISTINCT FROM (a->>'installationId')::uuid OR r.grant_id IS DISTINCT FROM (a->>'grantId')::uuid
  OR r.grant_version IS DISTINCT FROM (a->>'grantVersion')::bigint OR r.fingerprint IS DISTINCT FROM p_fingerprint THEN
  RAISE EXCEPTION 'burimunsi_observation_conflict' USING ERRCODE='23505';END IF;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN private.burimunsi_observation_own(r.source_id,false);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

CREATE FUNCTION private.burimunsi_observation_commit(p_request uuid,p_fingerprint text,p_source text,p_body_sha text,
 p_object_sha text,p_size bigint,p_profile_version text,p_profile_sha text,p_consent_generation bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;c jsonb;ctx jsonb;prior jsonb;expected_id text;h text;
 old_frame text:=current_setting('burimunsi.observation_frame',true);at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 PERFORM private.burimunsi_setup_fence();a:=private.burimunsi_observation_actor(false);c:=private.burimunsi_observation_consent_current();
 IF c->'enabled' IS DISTINCT FROM 'true'::jsonb OR (c->>'generation')::bigint IS DISTINCT FROM p_consent_generation THEN
  RAISE EXCEPTION 'burimunsi_observation_consent_changed' USING ERRCODE='42501';END IF;
 IF p_request IS NULL OR p_fingerprint IS NULL OR p_fingerprint !~ '^[a-f0-9]{64}$' OR p_body_sha IS NULL OR p_body_sha !~ '^[a-f0-9]{64}$'
  OR p_object_sha IS NULL OR p_object_sha !~ '^[a-f0-9]{64}$' OR p_size IS NULL OR p_size NOT BETWEEN 1 AND 131072
  OR p_profile_sha IS NULL OR p_profile_sha !~ '^[a-f0-9]{64}$' OR p_profile_version IS NULL OR length(p_profile_version) NOT BETWEEN 1 AND 128 THEN
  RAISE EXCEPTION 'burimunsi_observation_invalid' USING ERRCODE='22023';END IF;
 h:=encode(sha256(convert_to('collect.storage.entity.v1'||E'\n'||'burimunsi.native.observation.v1'||E'\n'||(a->>'principalUserId')||E'\n'||p_request::text,'UTF8')),'hex');
 expected_id:=substr(h,1,8)||'-'||substr(h,9,4)||'-5'||substr(h,14,3)||'-8'||substr(h,18,3)||'-'||substr(h,21,12);
 IF p_source IS DISTINCT FROM expected_id THEN RAISE EXCEPTION 'burimunsi_observation_invalid' USING ERRCODE='22023';END IF;
 prior:=private.burimunsi_observation_lookup(p_request,p_fingerprint);
 IF prior IS NOT NULL THEN RETURN prior;END IF;
 ctx:=private.burimunsi_observation_context();
 IF ctx->>'profile_version' IS DISTINCT FROM p_profile_version OR ctx->>'profile_sha256' IS DISTINCT FROM p_profile_sha
  OR (ctx->>'consentGeneration')::bigint IS DISTINCT FROM p_consent_generation THEN
  RAISE EXCEPTION 'burimunsi_observation_profile_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 IF NOT EXISTS(SELECT 1 FROM private.burimunsi_observation_requests r WHERE r.source_id=p_source
  AND r.collection_id=a->>'collectionId' AND r.account_id=(a->>'accountId')::uuid AND r.principal_user_id=a->>'principalUserId'
  AND r.installation_id=(a->>'installationId')::uuid AND r.grant_id=(a->>'grantId')::uuid
  AND r.grant_version=(a->>'grantVersion')::bigint AND r.request_id=p_request AND r.fingerprint=p_fingerprint) THEN
  RAISE EXCEPTION 'burimunsi_observation_admission_required' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM private.burimunsi_observation_requests r WHERE r.source_id=p_source
  AND r.initial_profile_tuple_sha256=ctx->>'profile_tuple_sha256') THEN
  RAISE EXCEPTION 'burimunsi_observation_profile_changed' USING ERRCODE='40001';END IF;
 INSERT INTO private.burimunsi_unresolved_observations(source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,native_session_id,
  request_id,fingerprint,body_sha256,object_key,object_sha256,size_bytes,profile_version,profile_sha256,profile_tuple_sha256,consent_generation,created_at)
 VALUES(p_source,a->>'collectionId',(a->>'accountId')::uuid,a->>'principalUserId',(a->>'installationId')::uuid,(a->>'grantId')::uuid,
  (a->>'grantVersion')::bigint,(a->>'sessionId')::uuid,p_request,p_fingerprint,p_body_sha,'sms/'||p_source,p_object_sha,p_size,
  p_profile_version,p_profile_sha,ctx->>'profile_tuple_sha256',p_consent_generation,at_ms);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN private.burimunsi_observation_lookup(p_request,p_fingerprint);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Snapshot revision and page share the same authorizing transaction. The
-- status is synchronized only: it never means parsed, allocated or posted.
CREATE FUNCTION private.burimunsi_observation_page(p_query text,p_filter text,p_limit integer,p_offset integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb:=private.burimunsi_observation_actor(false);c jsonb:=private.burimunsi_observation_consent_current();
 n bigint;matched bigint;rev text;items jsonb;old_frame text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 IF c->'enabled' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 IF p_query IS NULL OR length(p_query)>80 OR p_filter IS NULL OR p_filter NOT IN('all','queued','duplicate','synced','rejected')
  OR p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100 OR p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 100000 THEN
  RAISE EXCEPTION 'burimunsi_observation_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 IF EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations r WHERE r.collection_id=a->>'collectionId'
  AND r.account_id=(a->>'accountId')::uuid AND r.principal_user_id=a->>'principalUserId'
  AND r.installation_id=(a->>'installationId')::uuid AND r.grant_id=(a->>'grantId')::uuid
  AND r.grant_version=(a->>'grantVersion')::bigint AND NOT EXISTS(
   SELECT 1 FROM private.storage_objects o JOIN private.storage_put_intents i ON i.object_key=o.object_key
   WHERE o.object_key=r.object_key AND o.operation_id=i.operation_id AND i.state='committed' AND NOT i.delete_tombstone
    AND NOT i.upload_unresolved AND i.active_attempt IS NULL AND o.sha256=i.sha256 AND o.size=i.size AND o.scope=i.scope
    AND o.scope=jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id)
    AND o.custom_metadata->>'sha256'=r.object_sha256
    AND NOT EXISTS(SELECT 1 FROM private.storage_delete_intents d WHERE d.object_key=r.object_key))) THEN
  RAISE EXCEPTION 'burimunsi_observation_storage_changed' USING ERRCODE='55000';END IF;
 SELECT count(*),encode(sha256(convert_to(coalesce(string_agg(r.source_id||':'||r.created_at::text||':'||r.fingerprint,E'\n'
  ORDER BY r.source_id),''),'UTF8')),'hex') INTO n,rev FROM private.burimunsi_unresolved_observations r
  WHERE r.collection_id=a->>'collectionId' AND r.account_id=(a->>'accountId')::uuid
   AND r.principal_user_id=a->>'principalUserId' AND r.installation_id=(a->>'installationId')::uuid
   AND r.grant_id=(a->>'grantId')::uuid AND r.grant_version=(a->>'grantVersion')::bigint;
 IF n>100000 THEN RAISE EXCEPTION 'burimunsi_observation_snapshot_limit' USING ERRCODE='54000';END IF;
 SELECT count(*) INTO matched FROM private.burimunsi_unresolved_observations r WHERE r.collection_id=a->>'collectionId'
  AND r.account_id=(a->>'accountId')::uuid AND r.principal_user_id=a->>'principalUserId'
  AND r.installation_id=(a->>'installationId')::uuid AND r.grant_id=(a->>'grantId')::uuid
  AND r.grant_version=(a->>'grantVersion')::bigint AND position(lower(p_query) IN lower(r.source_id))>0
  AND p_filter IN('all','synced');
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',q.source_id,'createdAt',q.created_at)
  ORDER BY q.created_at DESC,q.source_id),'[]'::jsonb) INTO items FROM (
   SELECT r.source_id,r.created_at FROM private.burimunsi_unresolved_observations r WHERE r.collection_id=a->>'collectionId'
    AND r.account_id=(a->>'accountId')::uuid AND r.principal_user_id=a->>'principalUserId'
    AND r.installation_id=(a->>'installationId')::uuid AND r.grant_id=(a->>'grantId')::uuid
    AND r.grant_version=(a->>'grantVersion')::bigint AND position(lower(p_query) IN lower(r.source_id))>0
    AND p_filter IN('all','synced') ORDER BY r.created_at DESC,r.source_id LIMIT p_limit OFFSET p_offset
  ) q;
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('revision',rev,'totalCount',matched,'items',items);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;

-- Disclosure is a two-phase operation: the server first reads the protected
-- object outside SQL, then this guarded transaction revalidates the current
-- scope, consent, session, object metadata and both permissions before audit.
CREATE FUNCTION private.burimunsi_observation_reveal_audit(p_source text,p_request uuid,p_reason text,p_session uuid,
 p_body_sha text,p_object_sha text,p_fingerprint text,p_consent_generation bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;c jsonb;r jsonb;
BEGIN
 PERFORM private.burimunsi_setup_fence();a:=private.burimunsi_observation_actor(true);c:=private.burimunsi_observation_consent_current();
 IF p_request IS NULL OR p_session IS NULL OR p_session::text IS DISTINCT FROM a->>'sessionId'
  OR p_reason IS NULL OR btrim(p_reason) IS DISTINCT FROM p_reason OR length(p_reason) NOT BETWEEN 8 AND 1000
  OR p_reason ~ '[[:cntrl:]]' OR c->'enabled' IS DISTINCT FROM 'true'::jsonb
  OR (c->>'generation')::bigint IS DISTINCT FROM p_consent_generation THEN
  RAISE EXCEPTION 'burimunsi_observation_denied' USING ERRCODE='42501';END IF;
 r:=private.burimunsi_observation_own(p_source,true);
 IF r IS NULL OR r->>'bodySha256' IS DISTINCT FROM p_body_sha OR r->>'object_sha256' IS DISTINCT FROM p_object_sha
  OR r->>'fingerprint' IS DISTINCT FROM p_fingerprint THEN
  RAISE EXCEPTION 'burimunsi_observation_changed' USING ERRCODE='40001';END IF;
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
 VALUES(a->>'principalUserId',a->>'sessionId','sms.capture.revealed','burimunsi_observation',p_source,p_request::text,
  jsonb_build_object('reason',p_reason,'purpose','native_own_sms_review','source_kind','unresolved_observation',
   'collection_id',a->>'collectionId','native_actor_id',a->>'accountId','native_session_id',a->>'sessionId',
   'source_sha256',p_body_sha,'object_sha256',p_object_sha)::text,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 RETURN r;
END;$fn$;

-- Collect Admin list/content integration and the retention catalog remain
-- separate release gates; no existing SMS or retention functions change here.
REVOKE ALL ON FUNCTION private.burimunsi_observation_actor(boolean),private.burimunsi_observation_consent_current(),
 private.burimunsi_observation_set_consent(boolean,bigint),private.burimunsi_observation_context(),
 private.burimunsi_observation_prepare(uuid,text,text,text,text,bigint),private.burimunsi_observation_own(text,boolean),private.burimunsi_observation_hint_profile(text),private.burimunsi_observation_lookup(uuid,text),
 private.burimunsi_observation_commit(uuid,text,text,text,text,bigint,text,text,bigint),
 private.burimunsi_observation_page(text,text,integer,integer),
 private.burimunsi_observation_reveal_audit(text,uuid,text,uuid,text,text,text,bigint)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_consent_current(),private.burimunsi_observation_set_consent(boolean,bigint),
 private.burimunsi_observation_context(),private.burimunsi_observation_prepare(uuid,text,text,text,text,bigint),
 private.burimunsi_observation_own(text,boolean),private.burimunsi_observation_hint_profile(text),private.burimunsi_observation_lookup(uuid,text),
 private.burimunsi_observation_commit(uuid,text,text,text,text,bigint,text,text,bigint),
 private.burimunsi_observation_page(text,text,integer,integer),
 private.burimunsi_observation_reveal_audit(text,uuid,text,uuid,text,text,text,bigint) TO collect_runtime;
COMMIT;
