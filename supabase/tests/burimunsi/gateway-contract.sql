-- QUALIFICATION ONLY; run after operator-seed.sql in the isolated retained DB.
-- The qualifier supplies compiled gateway_inputs from the exact source compiler and
-- holds genuine separately registered WORK admission/lease. This file never
-- invents that admission. Every grant, capture and negative mutation rolls back.
-- Auth/BFF/email rows are SQL fixtures, not GoTrue/provider authentication.
-- Capture/ciphertext metadata below has no real encrypted object/provider bytes.
-- No gateway token, actual pairing, financial posting or delivery is exercised.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=app,pg_catalog;
SET LOCAL statement_timeout='15s';
SET LOCAL lock_timeout='5s';
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
SELECT private.set_admin_email_context('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001');
__GATEWAY_INPUTS__
CREATE FUNCTION pg_temp.gateway_runtime() RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
BEGIN
 IF current_user<>'collect_runtime' OR (SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) THEN
  RAISE EXCEPTION 'Normal gateway runtime role required';END IF;
END;$fn$;
CREATE FUNCTION pg_temp.gateway_classification(p_expected jsonb,p_label text,p_hash text DEFAULT NULL) RETURNS void
 LANGUAGE plpgsql SECURITY INVOKER AS $fn$
DECLARE digest text:=coalesce(p_hash,current_setting('burimunsi.gateway.fixture_code_sha256',true));actual jsonb;
 old_group text:=current_setting('burimunsi.collection_id',true);
 old_guard text:=current_setting('burimunsi.gateway_classification_hash',true);legacy_allowed boolean;
BEGIN
 PERFORM pg_temp.gateway_runtime();
 SELECT r->'classification' INTO STRICT actual FROM pg_temp.buri_gateway_classification_rows(digest) r;
 IF actual IS DISTINCT FROM p_expected THEN RAISE EXCEPTION 'Gateway classification mismatch: %',p_label;END IF;
 SELECT (r->>'allowed')::boolean INTO STRICT legacy_allowed FROM pg_temp.buri_gateway_legacy_guard_rows(digest) r;
 IF legacy_allowed IS DISTINCT FROM (p_expected='{"kind":"non_burimunsi"}'::jsonb) THEN
  RAISE EXCEPTION 'Same-transaction legacy guard mismatch: %',p_label;END IF;
 IF old_group IS DISTINCT FROM current_setting('burimunsi.collection_id',true)
  OR old_guard IS DISTINCT FROM current_setting('burimunsi.gateway_classification_hash',true) THEN
  RAISE EXCEPTION 'Gateway classifier leaked or replaced caller GUCs: %',p_label;END IF;
END;$fn$;
CREATE FUNCTION pg_temp.gateway_expect_state(statement text,expected text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=expected THEN RETURN;END IF;
  RAISE EXCEPTION 'Gateway qualification SQLSTATE %, expected %: %',SQLSTATE,expected,SQLERRM;
 END;
 RAISE EXCEPTION 'Expected gateway qualification SQLSTATE %',expected;
END;$fn$;
CREATE FUNCTION pg_temp.gateway_permission(p_expected bigint,p_label text,
 p_principal text DEFAULT 'f3000000-0000-4000-8000-000000000001',
 p_session text DEFAULT 'f2000000-0000-4000-8000-000000000001') RETURNS void
 LANGUAGE plpgsql SECURITY INVOKER AS $fn$
BEGIN
 PERFORM pg_temp.gateway_runtime();
 IF (SELECT count(*) FROM pg_temp.buri_gateway_permission_rows(p_principal,p_session))<>p_expected THEN
  RAISE EXCEPTION 'Gateway read authority mismatch: %',p_label;END IF;
END;$fn$;
CREATE FUNCTION pg_temp.gateway_pair(p_expected bigint,p_label text,
 p_group text DEFAULT 'buri-qualification-group',
 p_installation text DEFAULT 'fd900000-0000-4000-8000-000000000001',p_hash text DEFAULT NULL) RETURNS void
 LANGUAGE plpgsql SECURITY INVOKER AS $fn$
DECLARE digest text:=coalesce(p_hash,current_setting('burimunsi.gateway.fixture_code_sha256',true));r jsonb;n bigint;
BEGIN
 PERFORM pg_temp.gateway_runtime();
 SELECT count(*) INTO n FROM pg_temp.buri_gateway_pair_rows(digest,p_group,p_installation);
 IF n<>p_expected THEN RAISE EXCEPTION 'Canonical pairing authority mismatch: %',p_label;END IF;
 IF p_expected=1 THEN
  SELECT * INTO STRICT r FROM pg_temp.buri_gateway_pair_rows(digest,p_group,p_installation);
  IF r->>'binding_id'<>'gateway-contract-binding' OR r->>'owner_user_id'<>'f3000000-0000-4000-8000-000000000001'
   OR r->>'originating_session_id'<>'f2000000-0000-4000-8000-000000000001'
   OR r->>'receiving_account_id'<>'buri-qualification-wallet' OR (r->>'binding_version')::bigint<>1 THEN
   RAISE EXCEPTION 'Canonical pairing identity projection mismatch';END IF;
 END IF;
END;$fn$;
DO $preflight$ BEGIN
 PERFORM private._collect_fence_require_operator();
 IF (SELECT count(*) FROM private.burimunsi_accounts)<>2 OR EXISTS(SELECT 1 FROM app.momo_gateway_bindings)
  OR EXISTS(SELECT 1 FROM private.burimunsi_device_grants) OR EXISTS(SELECT 1 FROM private.burimunsi_sessions)
  OR EXISTS(SELECT 1 FROM app.sms_receipts) THEN RAISE EXCEPTION 'Clean operator seed required for gateway qualification';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('private.burimunsi_gateway_pair_classify(text)')
  AND p.prosecdef AND p.provolatile='v' AND pg_get_userbyid(p.proowner)='postgres'
  AND EXISTS(SELECT 1 FROM unnest(p.proconfig) config WHERE replace(config,' ','')='search_path=pg_catalog,pg_temp'))
  OR NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='private.burimunsi_scopes'::regclass AND relrowsecurity AND relforcerowsecurity) THEN
  RAISE EXCEPTION 'Current classifier owner/search path and FORCE RLS required';END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(p.proacl) entry
  WHERE p.oid='private.burimunsi_gateway_pair_classify(text)'::regprocedure AND entry.grantee=0 AND entry.privilege_type='EXECUTE') THEN
  RAISE EXCEPTION 'Classifier PUBLIC execution leak';END IF;
END;$preflight$;
-- Actual canonical rows and an approved native receiving installation, all
-- synthetic and confined to this ROLLBACK. No PIN/native session is issued.
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
 VALUES('fd900000-0000-4000-8000-000000000002','buri-qualification-group','fd900000-0000-4000-8000-000000000001',
 repeat('d',64),'internal_receiver','f7000000-0000-4000-8000-000000000001',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id)
 VALUES('fd900000-0000-4000-8000-000000000002','f7000000-0000-4000-8000-000000000001','buri-qualification-group');
INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,subscription_evidence,created_at)
 VALUES('gateway-contract-binding','f3000000-0000-4000-8000-000000000001','buri-qualification-wallet',
 '{"subscription_id":7}',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
UPDATE private.burimunsi_scopes SET active_binding_id='gateway-contract-binding',binding_version=1,version=version+1
 WHERE collection_id='buri-qualification-group';
INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,claimed_installation_id,created_at)
 VALUES('gateway-contract-pairing','gateway-contract-binding',current_setting('burimunsi.gateway.fixture_code_sha256'),
 'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,'fd900000-0000-4000-8000-000000000001',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
-- A retired binding on the Buri wallet remains blocked without an exact scope;
-- a different wallet with no Buri association is the only legacy-positive case.
INSERT INTO app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,timezone,created_at)
 VALUES('gateway-contract-unscoped-wallet','mtn_momo','00001','QUALIFICATION UNSCOPED',repeat('4',64),
 'Africa/Kigali',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,status,created_at) VALUES
 ('gateway-contract-unscoped-binding','f3000000-0000-4000-8000-000000000001','gateway-contract-unscoped-wallet','active',app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('gateway-contract-related-binding','f3000000-0000-4000-8000-000000000001','buri-qualification-wallet','revoked',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,created_at) VALUES
 ('gateway-contract-unscoped-pairing','gateway-contract-unscoped-binding',repeat('4',64),'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('gateway-contract-related-pairing','gateway-contract-related-binding',repeat('5',64),'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,pending_count,last_contact_at,created_at)
 VALUES('gateway-contract-credential','gateway-contract-binding','gateway-contract-pairing','fd900000-0000-4000-8000-000000000001',
 repeat('e',64),'QUALIFICATION NOT A TOKEN',2,app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
-- The real SMS application-commit trigger requires the existing storage journal.
-- These declarations qualify that SQL lineage only; the sealed bytes are an
-- explicit synthetic placeholder and cannot establish encrypted storage custody.
INSERT INTO private.storage_namespace(singleton,origin,bucket)
 VALUES(true,'https://qualification-storage.invalid','qualification-gateway') ON CONFLICT(singleton) DO NOTHING;
DO $storage_metadata$
DECLARE scope jsonb:=jsonb_build_object('ownerId','f3000000-0000-4000-8000-000000000001',
 'purpose','sms_receipt','entityId','gateway-contract-capture');
 sealed text:='{"qualification_only":true,"note":"NOT ENCRYPTED PROVIDER BYTES"}';
 custom jsonb:=jsonb_build_object('sha256',repeat('2',64),'key_id','qualification-only','source_fingerprint',repeat('3',64));
 cipher_sha text;
BEGIN
 cipher_sha:=encode(sha256(convert_to(sealed,'UTF8')),'hex');
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
 VALUES('sms/gateway-contract-capture',repeat('3',64),scope,'sms:gateway-contract-capture:'||repeat('2',64),
  'qualification-only',repeat('2',64),sealed);
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
 VALUES('qualification:gateway-contract-capture','sms/gateway-contract-capture',repeat('3',64),cipher_sha,
  octet_length(sealed),scope,'{"contentType":"application/octet-stream"}',custom,'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
 VALUES('sms/gateway-contract-capture','qualification:gateway-contract-capture',repeat('3',64),cipher_sha,
  octet_length(sealed),scope,'{"contentType":"application/octet-stream"}',custom);
END;$storage_metadata$;
INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,
 object_key,object_sha256,size_bytes,created_at)
 VALUES('gateway-contract-capture','f3000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000001',
 'gateway-contract-capture',repeat('1',64),repeat('c',64),'sms/gateway-contract-capture',repeat('2',64),1,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_captures(raw_sms_id,credential_id,identity_sha256,captured_at,subscription_id,completeness,source_mode,created_at)
 VALUES('gateway-contract-capture','gateway-contract-credential',repeat('3',64),app.strftime('%Y-%m-%dT%H:%M:%fZ'),7,
 'complete','live',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
-- Preserve a complete canonical credential snapshot to detect a read heartbeat.
SELECT set_config('burimunsi.gateway.fixture_credential_before',
 (SELECT to_jsonb(c)::text FROM app.momo_gateway_credentials c WHERE id='gateway-contract-credential'),true);
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
DO $lineage$ BEGIN
 PERFORM pg_temp.gateway_runtime();
 IF NOT EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes WHERE source_id='gateway-contract-capture'
  AND binding_id='gateway-contract-binding' AND credential_id='gateway-contract-credential'
  AND installation_id='fd900000-0000-4000-8000-000000000001' AND provenance='gateway_capture') THEN
  RAISE EXCEPTION 'Real canonical capture trigger was not exercised';END IF;
 IF (SELECT count(*) FROM app.assisted_sms_current_sessions WHERE user_id='f3000000-0000-4000-8000-000000000001'
  AND auth_session_id='f2000000-0000-4000-8000-000000000001' AND role='owner' AND permission='receivers.manage')<>1 THEN
  RAISE EXCEPTION 'Original current shared owner/email authority required';END IF;
END;$lineage$;
SELECT set_config('burimunsi.gateway_classification_hash','qualification-caller-guard',true);
SELECT pg_temp.gateway_classification('{"kind":"burimunsi","collectionId":"buri-qualification-group"}','exact binding');
SELECT pg_temp.gateway_classification('{"kind":"blocked"}','related scoped wallet',repeat('5',64));
SELECT pg_temp.gateway_classification('{"kind":"non_burimunsi"}','authoritative unscoped candidate',repeat('4',64));
SELECT pg_temp.gateway_classification('{"kind":"blocked"}','unknown candidate',repeat('0',64));
SAVEPOINT classifier_wrong_context_group;
SELECT set_config('burimunsi.collection_id','unrelated-runtime-group',true),
 set_config('burimunsi.gateway_classification_hash',current_setting('burimunsi.gateway.fixture_code_sha256'),true);
DO $runtime_rls$ BEGIN
 IF EXISTS(SELECT 1 FROM private.burimunsi_scopes WHERE collection_id='buri-qualification-group') THEN
  RAISE EXCEPTION 'Forged classifier GUC widened ordinary runtime scope policy';END IF;
 PERFORM pg_temp.gateway_classification('{"kind":"burimunsi","collectionId":"buri-qualification-group"}','classification independent of configured scope');
END;$runtime_rls$;
ROLLBACK TO SAVEPOINT classifier_wrong_context_group;
RELEASE SAVEPOINT classifier_wrong_context_group;
SAVEPOINT classifier_missing_group;
SELECT set_config('burimunsi.collection_id','',true);
SELECT pg_temp.gateway_classification('{"kind":"burimunsi","collectionId":"buri-qualification-group"}','classification independent of missing scope');
ROLLBACK TO SAVEPOINT classifier_missing_group;
RELEASE SAVEPOINT classifier_missing_group;
SAVEPOINT classifier_no_fence;
SELECT set_config('collect.fence_admission_id','',true);
SELECT pg_temp.gateway_expect_state($q$SELECT private.burimunsi_gateway_pair_classify(repeat('4',64))$q$,'55000');
ROLLBACK TO SAVEPOINT classifier_no_fence;
RELEASE SAVEPOINT classifier_no_fence;
SELECT pg_temp.gateway_expect_state($q$SELECT private.burimunsi_gateway_pair_classify('invalid')$q$,'22023');
SELECT pg_temp.gateway_expect_state($q$SELECT private.burimunsi_gateway_pair_classify(repeat('A',64))$q$,'22023');
SELECT pg_temp.gateway_expect_state($q$SELECT private.burimunsi_gateway_pair_classify(repeat('4',64)||E'\n')$q$,'22023');
DO $classifier_grants$
DECLARE r text;
BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
  IF has_function_privilege(r,'private.burimunsi_gateway_pair_classify(text)','EXECUTE') THEN
   RAISE EXCEPTION 'Classifier function privilege leak %',r;END IF;
 END LOOP;
 IF NOT has_function_privilege('collect_runtime','private.burimunsi_gateway_pair_classify(text)','EXECUTE') THEN
  RAISE EXCEPTION 'Classifier runtime execution unavailable';END IF;
END;$classifier_grants$;
-- SET READ ONLY is itself real PostgreSQL enforcement. Rolling back this
-- savepoint restores write mode; no fixture or proof has to be committed.
SAVEPOINT readonly_health;
SET LOCAL transaction_read_only=on;
DO $readonly$ BEGIN
 IF current_setting('transaction_read_only')<>'on' OR current_setting('transaction_isolation')<>'read committed' THEN
  RAISE EXCEPTION 'Actual read-only mode required inside the fenced RC fixture';END IF;
 PERFORM pg_temp.gateway_permission(1,'current owner READ ONLY');
 PERFORM pg_temp.gateway_expect_state($q$SELECT private.burimunsi_gateway_pair_classify(repeat('4',64))$q$,'55000');
 IF (SELECT to_jsonb(c) FROM app.momo_gateway_credentials c WHERE id='gateway-contract-credential')
  IS DISTINCT FROM current_setting('burimunsi.gateway.fixture_credential_before')::jsonb THEN
  RAISE EXCEPTION 'Gateway read mutated contact/custody metadata';END IF;
END;$readonly$;
ROLLBACK TO SAVEPOINT readonly_health;
RELEASE SAVEPOINT readonly_health;
-- A shared staff actor cannot inherit owner gateway-read authority.
SAVEPOINT staff_read;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000002',
 'session_id','f2000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
SELECT pg_temp.gateway_permission(0,'staff role','f3000000-0000-4000-8000-000000000002','f2000000-0000-4000-8000-000000000002');
ROLLBACK TO SAVEPOINT staff_read;
RELEASE SAVEPOINT staff_read;
SAVEPOINT removed_shared_read_grant;
RESET ROLE;
DELETE FROM app.admin_grants WHERE user_id='f3000000-0000-4000-8000-000000000001' AND permission='receivers.read';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_permission(0,'removed shared read grant');
ROLLBACK TO SAVEPOINT removed_shared_read_grant;
RELEASE SAVEPOINT removed_shared_read_grant;
SELECT pg_temp.gateway_permission(0,'other principal','f3000000-0000-4000-8000-000000000002');
SELECT pg_temp.gateway_permission(0,'other original session','f3000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000002');
-- Deliberately remove caller JWT, native and current-browser context. Pairing
-- uses only code hash + exact approved installation + stored original owner.
SELECT set_config('request.jwt.claims','{}',true),set_config('collect.admin_email_context','',true),
 set_config('burimunsi.native_session_id','',true);
DO $anonymous$ BEGIN
 IF private.request_claims()<>'{}'::jsonb OR api.current_session_id() IS NOT NULL
  OR EXISTS(SELECT 1 FROM private.burimunsi_sessions) THEN RAISE EXCEPTION 'Pairing accidentally depended on native/PIN login';END IF;
 PERFORM pg_temp.gateway_pair(1,'anonymous original owner and exact installation');
 PERFORM pg_temp.gateway_permission(0,'anonymous is not owner UI access');
END;$anonymous$;
SELECT pg_temp.gateway_pair(0,'wrong code','buri-qualification-group','fd900000-0000-4000-8000-000000000001',repeat('0',64));
SELECT pg_temp.gateway_pair(0,'wrong installation','buri-qualification-group','fd900000-0000-4000-8000-000000000099');
SELECT pg_temp.gateway_pair(0,'wrong group','buri-qualification-group-other');
SAVEPOINT wrong_runtime_group;
SELECT set_config('burimunsi.collection_id','buri-qualification-group-other',true);
SELECT pg_temp.gateway_pair(0,'runtime scope RLS');
ROLLBACK TO SAVEPOINT wrong_runtime_group;
RELEASE SAVEPOINT wrong_runtime_group;
SAVEPOINT disabled_scope;
RESET ROLE;
UPDATE private.burimunsi_scopes SET enabled=false WHERE collection_id='buri-qualification-group';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'disabled scope');
SELECT pg_temp.gateway_classification('{"kind":"burimunsi","collectionId":"buri-qualification-group"}','disabled scope is never legacy');
ROLLBACK TO SAVEPOINT disabled_scope;
RELEASE SAVEPOINT disabled_scope;
SAVEPOINT dropped_binding;
RESET ROLE;
UPDATE private.burimunsi_scopes SET active_binding_id=NULL WHERE collection_id='buri-qualification-group';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'dropped exact binding');
SELECT pg_temp.gateway_classification('{"kind":"blocked"}','dropped binding retains related scoped wallet');
ROLLBACK TO SAVEPOINT dropped_binding;
RELEASE SAVEPOINT dropped_binding;
SAVEPOINT stale_binding_version;
RESET ROLE;
UPDATE private.burimunsi_scopes SET binding_version=2 WHERE collection_id='buri-qualification-group';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'stale binding version');
ROLLBACK TO SAVEPOINT stale_binding_version;
RELEASE SAVEPOINT stale_binding_version;
SAVEPOINT revoked_installation;
RESET ROLE;
UPDATE private.burimunsi_device_grants SET active=false,version=version+1 WHERE id='fd900000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'revoked receiving grant');
ROLLBACK TO SAVEPOINT revoked_installation;
RELEASE SAVEPOINT revoked_installation;
SAVEPOINT wrong_custodian;
RESET ROLE;
UPDATE private.burimunsi_device_grants SET custodian_account_id='f7000000-0000-4000-8000-000000000002'
 WHERE id='fd900000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'wrong or non-admin custodian');
ROLLBACK TO SAVEPOINT wrong_custodian;
RELEASE SAVEPOINT wrong_custodian;
SAVEPOINT wrong_profile;
RESET ROLE;
UPDATE private.burimunsi_device_grants SET profile='staff' WHERE id='fd900000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'staff installation profile');
ROLLBACK TO SAVEPOINT wrong_profile;
RELEASE SAVEPOINT wrong_profile;
SAVEPOINT inactive_custodian;
RESET ROLE;
UPDATE private.burimunsi_accounts SET active=false WHERE id='f7000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'inactive approved custodian');
ROLLBACK TO SAVEPOINT inactive_custodian;
RELEASE SAVEPOINT inactive_custodian;
SAVEPOINT expired_code;
RESET ROLE;
UPDATE app.momo_gateway_pairings SET expires_at=app.unixepoch()-1 WHERE id='gateway-contract-pairing';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'expired canonical pairing code');
ROLLBACK TO SAVEPOINT expired_code;
RELEASE SAVEPOINT expired_code;
SAVEPOINT old_parent;
RESET ROLE;
UPDATE app.auth_sessions SET revoked_at=app.unixepoch(),revocation_reason='qualification-only'
 WHERE id='f2000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'revoked original shared session');
ROLLBACK TO SAVEPOINT old_parent;
RELEASE SAVEPOINT old_parent;
SAVEPOINT expired_managed_parent;
RESET ROLE;
-- The shared policy compares with transaction-stable now(). A long fixture
-- must expire the session before both that snapshot and the moving clock.
UPDATE auth.sessions SET not_after=least(now(),clock_timestamp())-interval '1 second'
 WHERE id='f2000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'expired original managed session');
ROLLBACK TO SAVEPOINT expired_managed_parent;
RELEASE SAVEPOINT expired_managed_parent;
SAVEPOINT removed_shared_manage_grant;
RESET ROLE;
DELETE FROM app.admin_grants WHERE user_id='f3000000-0000-4000-8000-000000000001' AND permission='receivers.manage';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'removed shared manage grant');
ROLLBACK TO SAVEPOINT removed_shared_manage_grant;
RELEASE SAVEPOINT removed_shared_manage_grant;
SAVEPOINT revoked_native_owner_approval;
RESET ROLE;
UPDATE private.burimunsi_operator_approvals SET active=false,version=version+1,
 updated_at=floor(extract(epoch FROM clock_timestamp())*1000)::bigint
 WHERE collection_id='buri-qualification-group' AND principal_user_id='f3000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.gateway_pair(0,'revoked owner native admission');
ROLLBACK TO SAVEPOINT revoked_native_owner_approval;
RELEASE SAVEPOINT revoked_native_owner_approval;
SELECT pg_temp.gateway_pair(1,'all negative fixture mutations restored');
RESET ROLE;
DO $unchanged$ BEGIN
 IF EXISTS(SELECT 1 FROM private.burimunsi_sessions) OR EXISTS(SELECT 1 FROM app.payments)
  OR EXISTS(SELECT 1 FROM app.ledger_entries) OR (SELECT count(*) FROM app.momo_gateway_credentials)<>1
  OR (SELECT to_jsonb(c) FROM app.momo_gateway_credentials c WHERE id='gateway-contract-credential')
   IS DISTINCT FROM current_setting('burimunsi.gateway.fixture_credential_before')::jsonb THEN
  RAISE EXCEPTION 'Gateway SELECT qualification changed credential, native or financial authority';END IF;
END;$unchanged$;
ROLLBACK;
