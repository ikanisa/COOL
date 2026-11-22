-- QUALIFICATION ONLY after operator-seed.sql; all state rolls back.
-- Exact compiled shipping authority/match/association SELECTs, real SQL27
-- association trigger and real synthetic AES/control-plane storage records.
-- Root supplies a genuine separately held WORK lease. No GoTrue, provider,
-- media transport, actual lost-network COMMIT or financial posting is claimed.
BEGIN ISOLATION LEVEL READ COMMITTED;
SET LOCAL search_path=app,pg_catalog;
SET LOCAL statement_timeout='15s';
SET LOCAL lock_timeout='5s';
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true),
 set_config('request.jwt.claims','{}',true);
__GATEWAY_UPLOAD_INPUTS__
CREATE FUNCTION pg_temp.upload_runtime() RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
BEGIN
 IF current_user<>'collect_runtime' OR (SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) THEN
  RAISE EXCEPTION 'Normal upload runtime required';END IF;
 PERFORM private.collect_fence_assert_write(current_setting('collect.fence_admission_id')::uuid,
  current_setting('collect.fence_epoch')::bigint,current_setting('collect.fence_source_sha256'));
END;$fn$;
CREATE FUNCTION pg_temp.upload_expect(statement text,expected text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=expected THEN RETURN;END IF;
  RAISE EXCEPTION 'Upload qualification SQLSTATE %, expected %',SQLSTATE,expected;
 END;
 RAISE EXCEPTION 'Expected upload qualification SQLSTATE %',expected;
END;$fn$;
CREATE FUNCTION pg_temp.upload_snapshot() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER AS $fn$
 SELECT current_setting('burimunsi.upload.fixture.snapshot')::jsonb
$fn$;
CREATE FUNCTION pg_temp.upload_guard(p_source text DEFAULT NULL) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
DECLARE k text:=gen_random_uuid()::text;snapshot jsonb:=pg_temp.upload_snapshot();data jsonb;
BEGIN
 PERFORM pg_temp.upload_runtime();PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 data:=current_setting('burimunsi.upload.fixture.inputs')::jsonb->p_source;
 INSERT INTO app.momo_processing_guards(id,passed) SELECT k,CASE WHEN pg_temp.upload_matches(snapshot)
  AND (p_source IS NULL OR pg_temp.upload_associated(snapshot,p_source,data->>'body_sha256',data->>'object_sha256',7,data->>'identity_sha256'))
  THEN 1 ELSE 0 END;
 DELETE FROM app.momo_processing_guards WHERE id=k;
END;$fn$;
CREATE FUNCTION pg_temp.upload_storage(p_id text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
DECLARE data jsonb:=current_setting('burimunsi.upload.fixture.inputs')::jsonb->p_id;
 scope jsonb:=jsonb_build_object('ownerId','f3000000-0000-4000-8000-000000000001','purpose','sms_receipt','entityId',p_id);
 custom jsonb;
BEGIN
 PERFORM pg_temp.upload_runtime();
 custom:=jsonb_build_object('sha256',data->>'object_sha256','key_id','qualification-upload-key','source_fingerprint',data->>'identity_sha256');
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
 VALUES('sms/'||p_id,data->>'identity_sha256',scope,'sms:'||p_id||':'||(data->>'object_sha256'),
  'qualification-upload-key',data->>'object_sha256',data->>'sealed');
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
 VALUES('qualification-upload:'||p_id,'sms/'||p_id,data->>'identity_sha256',data->>'ciphertext_sha256',
  (data->>'ciphertext_size')::bigint,scope,'{"contentType":"application/octet-stream"}',custom,'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
 VALUES('sms/'||p_id,'qualification-upload:'||p_id,data->>'identity_sha256',data->>'ciphertext_sha256',
  (data->>'ciphertext_size')::bigint,scope,'{"contentType":"application/octet-stream"}',custom);
END;$fn$;
CREATE FUNCTION pg_temp.upload_insert(p_id text,p_subscription bigint DEFAULT 7) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
DECLARE data jsonb:=current_setting('burimunsi.upload.fixture.inputs')::jsonb->p_id;
BEGIN
 PERFORM pg_temp.upload_runtime();
 INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,
  object_key,object_sha256,size_bytes,received_at_device,created_at)
 VALUES(p_id,'f3000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000001',p_id,
  data->>'body_sha256',repeat('c',64),'sms/'||p_id,data->>'object_sha256',(data->>'plaintext_size')::bigint,
  NULL,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 INSERT INTO app.momo_gateway_captures(raw_sms_id,credential_id,identity_sha256,service_centre_at,captured_at,
  inbox_received_at,subscription_id,completeness,source_mode,created_at)
 VALUES(p_id,'upload-contract-credential',data->>'identity_sha256',NULL,app.strftime('%Y-%m-%dT%H:%M:%fZ'),
  NULL,p_subscription,'complete','live',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 INSERT INTO app.momo_processing_jobs(raw_sms_id,binding_id,binding_version,receiving_account_id,mode,state,available_at,created_at,updated_at)
 VALUES(p_id,'upload-contract-binding',1,'buri-qualification-wallet','live','pending',app.unixepoch(),
  app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
END;$fn$;
CREATE FUNCTION pg_temp.upload_capture(p_id text,p_subscription bigint DEFAULT 7) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
BEGIN
 PERFORM pg_temp.upload_guard();PERFORM pg_temp.upload_insert(p_id,p_subscription);PERFORM pg_temp.upload_guard(p_id);
END;$fn$;
DO $preflight$ BEGIN
 PERFORM private._collect_fence_require_operator();
 IF EXISTS(SELECT 1 FROM app.sms_receipts) OR EXISTS(SELECT 1 FROM private.burimunsi_device_grants)
  OR NOT EXISTS(SELECT 1 FROM private.burimunsi_accounts WHERE id='f7000000-0000-4000-8000-000000000001') THEN
  RAISE EXCEPTION 'Clean operator seed required for upload qualification';END IF;
END;$preflight$;
-- Declared fixture setup; no public admission, PIN or new Auth identity.
UPDATE app.momo_receiving_accounts SET profile_status='approved',profile_version='upload-qualification-v1',
 profile_json=current_setting('burimunsi.upload.fixture.profile') WHERE id='buri-qualification-wallet';
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
 VALUES('fc900000-0000-4000-8000-000000000001','buri-qualification-group','fc900000-0000-4000-8000-000000000002',
 repeat('d',64),'internal_receiver','f7000000-0000-4000-8000-000000000001',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id)
 VALUES('fc900000-0000-4000-8000-000000000001','f7000000-0000-4000-8000-000000000001','buri-qualification-group');
INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,subscription_evidence,created_at)
 VALUES('upload-contract-binding','f3000000-0000-4000-8000-000000000001','buri-qualification-wallet',
 '{"subscription_id":7}',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,claimed_installation_id,created_at)
 VALUES('upload-contract-pairing','upload-contract-binding',current_setting('burimunsi.upload.fixture.code_hash'),
 'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,'fc900000-0000-4000-8000-000000000002',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at)
 VALUES('upload-contract-credential','upload-contract-binding','upload-contract-pairing','fc900000-0000-4000-8000-000000000002',
 current_setting('burimunsi.upload.fixture.token_hash'),'QUALIFICATION NOT A DELIVERED TOKEN',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
UPDATE private.burimunsi_scopes SET active_binding_id='upload-contract-binding',binding_version=1,version=version+1
 WHERE collection_id='buri-qualification-group';
INSERT INTO private.storage_namespace(singleton,origin,bucket) VALUES(true,'https://qualification-storage.invalid','qualification-upload') ON CONFLICT(singleton) DO NOTHING;
SELECT set_config('burimunsi.upload.fixture.counts',jsonb_build_object('auth',(SELECT count(*) FROM auth.users),
 'sessions',(SELECT count(*) FROM private.burimunsi_sessions),'payments',(SELECT count(*) FROM app.payments),
 'ledger',(SELECT count(*) FROM app.ledger_entries))::text,true);
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.upload_runtime();
SELECT set_config('burimunsi.upload.fixture.snapshot',r::text,true) FROM pg_temp.upload_authority(
 'upload-contract-credential',current_setting('burimunsi.upload.fixture.token_hash'),'buri-qualification-group') r;
DO $current$ BEGIN
 IF NOT pg_temp.upload_matches(pg_temp.upload_snapshot()) THEN RAISE EXCEPTION 'Current upload authority missing';END IF;
END;$current$;
SELECT pg_temp.upload_storage('fc910000-0000-4000-8000-000000000001');
SELECT pg_temp.upload_capture('fc910000-0000-4000-8000-000000000001');
-- Duplicate/lost-outcome reconciliation uses only the exact original SELECT;
-- no second INSERT, storage PUT or financial mutation. Actual network COMMIT
-- loss/read-only transaction orchestration is independently exercised by Node.
DO $original$ DECLARE r jsonb;BEGIN
 SELECT retained INTO STRICT r FROM pg_temp.upload_lookup('f3000000-0000-4000-8000-000000000001','fc910000-0000-4000-8000-000000000001') retained;
 IF r->>'id'<>'fc910000-0000-4000-8000-000000000001' THEN RAISE EXCEPTION 'Wrong original upload';END IF;
END;$original$;
SELECT pg_temp.upload_guard('fc910000-0000-4000-8000-000000000001');
SELECT pg_temp.upload_guard('fc910000-0000-4000-8000-000000000001');
-- Offline/no committed source can never produce an ACK. No simulated transport
-- success is introduced here; host tests prove PUT failure stops SQL dispatch.
SELECT pg_temp.upload_expect($q$SELECT pg_temp.upload_guard('fc910000-0000-4000-8000-000000000002')$q$,'23514');
SELECT pg_temp.upload_storage('fc910000-0000-4000-8000-000000000002');
-- Real trigger would associate this wrong-SIM row; the shipping postcondition
-- must still reject and roll back the entire capture/job transaction.
SELECT pg_temp.upload_expect($q$SELECT pg_temp.upload_capture('fc910000-0000-4000-8000-000000000002',8)$q$,'23514');
DO $wrong_sim$ BEGIN
 IF EXISTS(SELECT 1 FROM app.sms_receipts WHERE id='fc910000-0000-4000-8000-000000000002')
  OR EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes WHERE source_id='fc910000-0000-4000-8000-000000000002') THEN
  RAISE EXCEPTION 'Wrong SIM escaped postcondition rollback';END IF;
END;$wrong_sim$;
RESET ROLE;
SAVEPOINT disabled_scope;
UPDATE private.burimunsi_scopes SET enabled=false,version=version+1 WHERE collection_id='buri-qualification-group';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.upload_expect($q$SELECT pg_temp.upload_guard()$q$,'23514');
RESET ROLE;
ROLLBACK TO SAVEPOINT disabled_scope;
SAVEPOINT revoked_grant;
UPDATE private.burimunsi_device_grants SET active=false,version=version+1 WHERE id='fc900000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.upload_expect($q$SELECT pg_temp.upload_guard()$q$,'23514');
RESET ROLE;
ROLLBACK TO SAVEPOINT revoked_grant;
SAVEPOINT stale_account;
UPDATE private.burimunsi_accounts SET version=version+1 WHERE id='f7000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.upload_expect($q$SELECT pg_temp.upload_guard()$q$,'23514');
RESET ROLE;
ROLLBACK TO SAVEPOINT stale_account;
SAVEPOINT revoked_credential;
UPDATE app.momo_gateway_credentials SET revoked_at=app.strftime('%Y-%m-%dT%H:%M:%fZ') WHERE id='upload-contract-credential';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.upload_expect($q$SELECT pg_temp.upload_guard()$q$,'23514');
RESET ROLE;
ROLLBACK TO SAVEPOINT revoked_credential;
-- SQL27 intentionally does not invent association when grant authority is absent.
-- Demonstrate that later legitimate re-admission cannot ACK that missing proof.
SAVEPOINT missing_association;
UPDATE private.burimunsi_device_grants SET active=false,version=version+1 WHERE id='fc900000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.upload_storage('fc910000-0000-4000-8000-000000000003');
SELECT pg_temp.upload_insert('fc910000-0000-4000-8000-000000000003');
DO $no_association$ BEGIN
 IF EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes WHERE source_id='fc910000-0000-4000-8000-000000000003') THEN
  RAISE EXCEPTION 'Revoked grant associated a source';END IF;
END;$no_association$;
RESET ROLE;
UPDATE private.burimunsi_device_grants SET active=true,version=version+1 WHERE id='fc900000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT set_config('burimunsi.upload.fixture.snapshot',r::text,true) FROM pg_temp.upload_authority(
 'upload-contract-credential',current_setting('burimunsi.upload.fixture.token_hash'),'buri-qualification-group') r;
SELECT pg_temp.upload_guard();
SELECT pg_temp.upload_expect($q$SELECT pg_temp.upload_guard('fc910000-0000-4000-8000-000000000003')$q$,'23514');
RESET ROLE;
ROLLBACK TO SAVEPOINT missing_association;
DO $preserved$ DECLARE before jsonb:=current_setting('burimunsi.upload.fixture.counts')::jsonb;BEGIN
 IF (SELECT count(*) FROM app.sms_receipts)<>1 OR (SELECT count(*) FROM app.momo_gateway_captures)<>1
  OR (SELECT count(*) FROM private.burimunsi_sms_source_scopes)<>1 OR (SELECT count(*) FROM app.momo_processing_jobs)<>1
  OR EXISTS(SELECT 1 FROM app.momo_processing_guards)
  OR (SELECT count(*) FROM auth.users)<>(before->>'auth')::bigint
  OR (SELECT count(*) FROM private.burimunsi_sessions)<>(before->>'sessions')::bigint
  OR (SELECT count(*) FROM app.payments)<>(before->>'payments')::bigint
  OR (SELECT count(*) FROM app.ledger_entries)<>(before->>'ledger')::bigint THEN
  RAISE EXCEPTION 'Upload duplicated evidence or changed independent Auth/financial state';END IF;
END;$preserved$;
ROLLBACK;
