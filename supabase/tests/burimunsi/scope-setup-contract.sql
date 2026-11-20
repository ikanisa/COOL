-- QUALIFICATION ONLY. Real schema/functions after operator-seed. Source inputs
-- contain hashes/ciphertext only. The external harness owns a genuine admission
-- and lease; fixtures cannot mint one. All setup effects roll back. No carrier,
-- upload, provider, actual pairing or financial action is performed.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
__SETUP_INPUTS__
CREATE FUNCTION pg_temp.setup_expect(statement text,expected text,expected_message text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=expected AND(expected_message IS NULL OR SQLERRM=expected_message) THEN RETURN;END IF;
  RAISE EXCEPTION 'Setup qualification SQLSTATE %, expected % (message matched=%)',SQLSTATE,expected,
   expected_message IS NULL OR SQLERRM=expected_message;
 END;
 RAISE EXCEPTION 'Expected setup qualification SQLSTATE %',expected;
END;$fn$;
CREATE FUNCTION pg_temp.setup_apply(p_name text,p_overrides jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY INVOKER AS $fn$
DECLARE input jsonb:=pg_temp.setup_fixture(p_name);
BEGIN RETURN private.burimunsi_setup_apply('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001',input->'command'||p_overrides,
 input->>'fingerprint',nullif(input->'delivery','null'::jsonb));END;$fn$;
CREATE FUNCTION pg_temp.setup_lookup(p_request uuid,p_delivery boolean DEFAULT false) RETURNS jsonb LANGUAGE sql SECURITY INVOKER AS $fn$
 SELECT private.burimunsi_setup_lookup('f4000000-0000-4000-8000-000000000001',repeat('a',64),
  'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',p_request,p_delivery)
$fn$;
CREATE FUNCTION pg_temp.setup_cancel(p_collection text,p_request uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER AS $fn$
 SELECT private.burimunsi_setup_cancel('f4000000-0000-4000-8000-000000000001',repeat('a',64),
  'https://admin.collect.example','f5000000-0000-4000-8000-000000000001',p_collection,p_request)
$fn$;
DO $preflight$ DECLARE r text;f text;BEGIN
 PERFORM private._collect_fence_require_operator();
 IF EXISTS(SELECT 1 FROM private.burimunsi_scope_setup_commands) OR EXISTS(SELECT 1 FROM private.burimunsi_device_grants)
  OR (SELECT count(*) FROM auth.users)<>2 OR(SELECT count(*) FROM private.burimunsi_accounts)<>2 THEN
  RAISE EXCEPTION 'Clean operator-seed setup qualification required';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='private.burimunsi_scope_setup_commands'::regclass AND relrowsecurity AND relforcerowsecurity)
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_scope_setup_commands'::regclass AND tgname='collect_fence_statement_v1' AND tgenabled='A')
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_scope_setup_commands'::regclass AND tgname='burimunsi_setup_retain' AND tgenabled='A') THEN
  RAISE EXCEPTION 'Setup custody/fence/retention boundary missing';END IF;
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer','collect_runtime'] LOOP
  IF has_table_privilege(r,'private.burimunsi_scope_setup_commands','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
   RAISE EXCEPTION 'Setup private custody privilege leak %',r;END IF;
 END LOOP;
 FOREACH f IN ARRAY ARRAY['private.burimunsi_setup_directory(text,text,text,text,text)',
  'private.burimunsi_setup_apply(text,text,text,text,jsonb,text,jsonb)','private.burimunsi_setup_lookup(text,text,text,text,text,uuid,boolean)',
  'private.burimunsi_setup_cancel(text,text,text,text,text,uuid)','private.burimunsi_resolve_installation_scope(uuid,text)'] LOOP
  IF NOT has_function_privilege('collect_runtime',f,'EXECUTE') OR NOT EXISTS(
   SELECT 1 FROM pg_proc WHERE oid=f::regprocedure AND prosecdef AND pg_get_userbyid(proowner)='postgres') THEN
   RAISE EXCEPTION 'Setup narrow owner helper missing %',f;END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
   IF has_function_privilege(r,f,'EXECUTE') THEN RAISE EXCEPTION 'Setup helper privilege leak % %',f,r;END IF;
  END LOOP;
 END LOOP;
END;$preflight$;
-- Synthetic existing Collect destination approval and disabled native draft;
-- these are rollback-only qualification data, never deployment configuration.
UPDATE app.collections SET receiver_network='mtn_momo',receiver_momo_number='00000' WHERE id='buri-qualification-group';
UPDATE private.burimunsi_scopes SET enabled=false WHERE collection_id='buri-qualification-group';
INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,receiver_network,receiver_momo_number,created_at,updated_at)
 VALUES('buri-unprepared-qualification-group','buri-unprepared-qualification-group','f3000000-0000-4000-8000-000000000001',
 'QUALIFICATION UNPREPARED','community','mtn_momo','00000',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
 VALUES('fe100000-0000-4000-8000-000000000002','buri-qualification-group','fe100000-0000-4000-8000-000000000001',
 pg_temp.setup_fixture('deviceHash')#>>'{}','internal_receiver','f7000000-0000-4000-8000-000000000001',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id)
 VALUES('fe100000-0000-4000-8000-000000000002','f7000000-0000-4000-8000-000000000001','buri-qualification-group');
CREATE TEMP TABLE setup_unchanged AS SELECT jsonb_build_object(
 'ledger',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM app.ledger_entries t),
 'payments',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM app.payments t),
 'credentials',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM app.momo_gateway_credentials t),
 'native_sessions',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM private.burimunsi_sessions t),
 'native_accounts',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM private.burimunsi_accounts t),
 'destination',(SELECT jsonb_build_object('provider',receiver_network,'route',receiver_momo_number) FROM app.collections WHERE id='buri-qualification-group')) AS value;
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
DO $directory$ DECLARE d jsonb;BEGIN
 IF current_user<>'collect_runtime' OR(SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) THEN RAISE EXCEPTION 'Normal runtime role required';END IF;
 d:=private.burimunsi_setup_directory('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group');
 IF d->>'contractVersion'<>'1' OR jsonb_array_length(d->'installations')<>1 OR jsonb_array_length(d->'collections')<>2 THEN
  RAISE EXCEPTION 'Real shared setup directory mismatch';END IF;
END;$directory$;
SAVEPOINT setup_wrong_owner;
SELECT pg_temp.setup_expect($q$SELECT private.burimunsi_setup_directory('f4000000-0000-4000-8000-000000000002',repeat('b',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000002',NULL)$q$,'42501');
ROLLBACK TO SAVEPOINT setup_wrong_owner;
SAVEPOINT setup_wrong_destination;
SELECT pg_temp.setup_expect($q$SELECT pg_temp.setup_apply('prepare','{"receivingAccountId":"no-existing-wallet"}')$q$,'40001','burimunsi_receiver_mismatch');
ROLLBACK TO SAVEPOINT setup_wrong_destination;
SAVEPOINT setup_stale_version;
SELECT pg_temp.setup_expect($q$SELECT pg_temp.setup_apply('prepare','{"expectedScopeVersion":0}')$q$,'40001','burimunsi_scope_changed');
ROLLBACK TO SAVEPOINT setup_stale_version;
DO $prepare$ DECLARE r jsonb;BEGIN
 r:=pg_temp.setup_apply('prepare');IF r->>'scopeVersion'<>'2' OR r->>'enabled'<>'false' OR r->'bindingId'<>'null'::jsonb THEN RAISE EXCEPTION 'Disabled scope prepare mismatch';END IF;
 IF pg_temp.setup_apply('prepare')<>r THEN RAISE EXCEPTION 'Original prepare receipt changed';END IF;
END;$prepare$;
SAVEPOINT setup_tuple_mismatch;
SELECT pg_temp.setup_expect($q$SELECT pg_temp.setup_apply('activate','{"custodianAccountId":"f7000000-0000-4000-8000-000000000002"}')$q$,'22023','burimunsi_setup_invalid');
ROLLBACK TO SAVEPOINT setup_tuple_mismatch;
SAVEPOINT setup_wrong_custodian;
SELECT pg_temp.setup_expect($q$SELECT pg_temp.setup_apply('wrongCustodian')$q$,'40001','burimunsi_scope_changed');
ROLLBACK TO SAVEPOINT setup_wrong_custodian;
SAVEPOINT setup_revoked_grant;
RESET ROLE;
UPDATE private.burimunsi_device_grants SET active=false WHERE id='fe100000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.setup_expect($q$SELECT pg_temp.setup_apply('activate')$q$,'40001','burimunsi_scope_changed');
ROLLBACK TO SAVEPOINT setup_revoked_grant;
DO $activate$ DECLARE r jsonb;l jsonb;BEGIN
 r:=pg_temp.setup_apply('activate');IF r->>'scopeVersion'<>'3' OR r->>'enabled'<>'true' OR r->>'subscriptionId'<>'7'
  OR r ?| ARRAY['pairingCode','ciphertext','codeHash'] THEN RAISE EXCEPTION 'Activation public receipt mismatch';END IF;
 IF pg_temp.setup_apply('activate')<>r THEN RAISE EXCEPTION 'Original activation receipt changed';END IF;
 l:=pg_temp.setup_lookup('fe600000-0000-4000-8000-000000000002',true);
 IF l->>'found'<>'true' OR l->>'ciphertext' IS DISTINCT FROM pg_temp.setup_fixture('activate')->'delivery'->>'ciphertext'
  OR l->>'codeHash' IS DISTINCT FROM pg_temp.setup_fixture('activate')->'delivery'->>'codeHash'
  OR l ? 'pairingCode' THEN RAISE EXCEPTION 'Protected original pairing custody mismatch';END IF;
 IF pg_temp.setup_cancel('buri-qualification-group','fe600000-0000-4000-8000-000000000002')<>r THEN
  RAISE EXCEPTION 'Cancellation fabricated success after activation';END IF;
 IF private.burimunsi_resolve_installation_scope('fe100000-0000-4000-8000-000000000001',pg_temp.setup_fixture('deviceHash')#>>'{}')<>
  '{"collectionId":"buri-qualification-group"}'::jsonb THEN RAISE EXCEPTION 'Managed installation did not discover its actual scope';END IF;
END;$activate$;
SAVEPOINT setup_renew_unpaired;
DO $renew$ DECLARE r jsonb;BEGIN
 r:=pg_temp.setup_apply('renew');
 IF r->>'scopeVersion'<>'4' OR r->>'bindingId' IS DISTINCT FROM pg_temp.setup_fixture('activate')->'delivery'->>'bindingId'
  OR r->>'pairingId' IS NOT DISTINCT FROM pg_temp.setup_fixture('activate')->'delivery'->>'pairingId' THEN
  RAISE EXCEPTION 'Unpaired setup renewal did not preserve the original binding';END IF;
END;$renew$;
SELECT pg_temp.setup_expect($q$SELECT pg_temp.setup_lookup('fe600000-0000-4000-8000-000000000002',true)$q$,'41000','burimunsi_setup_delivery_expired');
ROLLBACK TO SAVEPOINT setup_renew_unpaired;
SAVEPOINT setup_preserve_paired_phone;
RESET ROLE;
INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at)
 VALUES('scope-qualification-credential',pg_temp.setup_fixture('activate')->'delivery'->>'bindingId',
 pg_temp.setup_fixture('activate')->'delivery'->>'pairingId','fe100000-0000-4000-8000-000000000001',repeat('8',64),
 'QUALIFICATION NOT A REAL CREDENTIAL',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.setup_expect($q$SELECT pg_temp.setup_apply('renew')$q$,'55000','gateway_handoff_unavailable');
ROLLBACK TO SAVEPOINT setup_preserve_paired_phone;
SAVEPOINT setup_bad_device;
SELECT pg_temp.setup_expect($q$SELECT private.burimunsi_resolve_installation_scope('fe100000-0000-4000-8000-000000000009',repeat('0',64))$q$,'42501','burimunsi_scope_denied');
ROLLBACK TO SAVEPOINT setup_bad_device;
SAVEPOINT setup_scope_bound_devices;
RESET ROLE;
SELECT set_config('burimunsi.collection_id','buri-unprepared-qualification-group',true);
INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at)
 VALUES('buri-unprepared-qualification-group','buri-qualification-wallet',true,1);
SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-unprepared-qualification-group',
 'fe600000-0000-4000-8000-000000000098','f4000000-0000-4000-8000-000000000001','+250780000001','admin',
 ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],true,0);
INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
 VALUES('fe700000-0000-4000-8000-000000000099','buri-unprepared-qualification-group','f3000000-0000-4000-8000-000000000001',
 '+250780000001','QUALIFICATION Owner','admin',ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],
 '{"qualification_only":true}',1,1);
-- The same physical installation/profile may serve different approved phone
-- scopes. This never gives the legacy hash-only resolver authority to choose an
-- arbitrary group: its pre-existing ambiguity denial remains mandatory.
SAVEPOINT setup_shared_installation;
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
 VALUES('fe100000-0000-4000-8000-000000000099','buri-unprepared-qualification-group','fe100000-0000-4000-8000-000000000001',
 pg_temp.setup_fixture('deviceHash')#>>'{}','internal_receiver','fe700000-0000-4000-8000-000000000099',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id)
 VALUES('fe100000-0000-4000-8000-000000000099','fe700000-0000-4000-8000-000000000099','buri-unprepared-qualification-group');
SET LOCAL ROLE collect_runtime;
SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT pg_temp.setup_expect($q$SELECT private.burimunsi_resolve_installation_scope('fe100000-0000-4000-8000-000000000001',pg_temp.setup_fixture('deviceHash')#>>'{}')$q$,
 '42501','burimunsi_scope_denied');
ROLLBACK TO setup_shared_installation;
-- A copied secret on a DIFFERENT installation or profile remains globally
-- forbidden, including across scopes. No managed/BFF authority is relaxed.
SELECT pg_temp.setup_expect($q$INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
 VALUES('fe100000-0000-4000-8000-000000000099','buri-unprepared-qualification-group','fe100000-0000-4000-8000-000000000009',
 pg_temp.setup_fixture('deviceHash')#>>'{}','internal_receiver','fe700000-0000-4000-8000-000000000099',1)$q$,
 '23505','burimunsi_device_secret_collision');
SELECT pg_temp.setup_expect($q$INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
 VALUES('fe100000-0000-4000-8000-000000000099','buri-unprepared-qualification-group','fe100000-0000-4000-8000-000000000001',
 pg_temp.setup_fixture('deviceHash')#>>'{}','staff','fe700000-0000-4000-8000-000000000099',1)$q$,
 '23505','burimunsi_device_secret_collision');
-- Distinct legacy proof continues to resolve only its own approved scope.
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
 VALUES('fe100000-0000-4000-8000-000000000099','buri-unprepared-qualification-group','fe100000-0000-4000-8000-000000000001',
 pg_temp.setup_fixture('otherDeviceHash')#>>'{}','internal_receiver','fe700000-0000-4000-8000-000000000099',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id)
 VALUES('fe100000-0000-4000-8000-000000000099','fe700000-0000-4000-8000-000000000099','buri-unprepared-qualification-group');
SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);
SET LOCAL ROLE collect_runtime;
DO $scope_devices$ BEGIN
 IF pg_temp.setup_fixture('deviceHash')=pg_temp.setup_fixture('otherDeviceHash') THEN RAISE EXCEPTION 'Distinct qualification device proofs required';END IF;
 IF private.burimunsi_resolve_installation_scope('fe100000-0000-4000-8000-000000000001',pg_temp.setup_fixture('deviceHash')#>>'{}')<>
  '{"collectionId":"buri-qualification-group"}'::jsonb THEN RAISE EXCEPTION 'Existing device proof was retargeted';END IF;
 IF private.burimunsi_resolve_installation_scope('fe100000-0000-4000-8000-000000000001',pg_temp.setup_fixture('otherDeviceHash')#>>'{}')<>
  '{"collectionId":"buri-unprepared-qualification-group"}'::jsonb THEN RAISE EXCEPTION 'Distinct device proof did not resolve its own scope';END IF;
END;$scope_devices$;
ROLLBACK TO SAVEPOINT setup_scope_bound_devices;
SAVEPOINT setup_lost_grant;
RESET ROLE;
UPDATE private.burimunsi_device_grants SET active=false WHERE id='fe100000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.setup_expect($q$SELECT pg_temp.setup_lookup('fe600000-0000-4000-8000-000000000002',true)$q$,'41000','burimunsi_setup_delivery_expired');
SELECT pg_temp.setup_expect($q$SELECT private.burimunsi_resolve_installation_scope('fe100000-0000-4000-8000-000000000001',pg_temp.setup_fixture('deviceHash')#>>'{}')$q$,'42501','burimunsi_scope_denied');
ROLLBACK TO SAVEPOINT setup_lost_grant;
SAVEPOINT setup_expired_owner;
RESET ROLE;
UPDATE auth.sessions SET not_after=least(now(),clock_timestamp())-interval '1 second' WHERE id='f2000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.setup_expect($q$SELECT pg_temp.setup_lookup('fe600000-0000-4000-8000-000000000002',true)$q$,'42501');
ROLLBACK TO SAVEPOINT setup_expired_owner;
DO $cancel_missing$ DECLARE r jsonb;BEGIN
 r:=pg_temp.setup_cancel('buri-unprepared-qualification-group','fe600000-0000-4000-8000-000000000003');
 IF r<>'{"contractVersion":1,"collectionId":"buri-unprepared-qualification-group","requestId":"fe600000-0000-4000-8000-000000000003","operation":"cancelled","applied":false}'::jsonb THEN
  RAISE EXCEPTION 'Missing original cancellation mismatch';END IF;
END;$cancel_missing$;
SELECT pg_temp.setup_expect($q$SELECT private.burimunsi_setup_apply('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001',pg_temp.setup_fixture('cancelPrepare'),
 pg_temp.setup_fixture('cancelFingerprint')#>>'{}',NULL)$q$,'23505','burimunsi_setup_request_conflict');
RESET ROLE;
DO $preserved$ DECLARE current_value jsonb;BEGIN
 IF EXISTS(SELECT 1 FROM private.burimunsi_scopes WHERE collection_id='buri-unprepared-qualification-group')
  OR(SELECT count(*) FROM private.burimunsi_scope_setup_commands)<>3
  OR(SELECT count(*) FROM app.momo_gateway_bindings)<>1 OR(SELECT count(*) FROM app.momo_gateway_pairings)<>1
  OR coalesce(current_setting('burimunsi.scope_setup_scan',true),'')<>''
  OR coalesce(current_setting('burimunsi.resolve_installation',true),'')<>''
  OR coalesce(current_setting('burimunsi.resolve_device_hash',true),'')<>''
  OR current_setting('burimunsi.collection_id',true)<>'buri-qualification-group' THEN RAISE EXCEPTION 'Setup effects/GUC restoration mismatch';END IF;
 SELECT jsonb_build_object(
  'ledger',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM app.ledger_entries t),
  'payments',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM app.payments t),
  'credentials',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM app.momo_gateway_credentials t),
  'native_sessions',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM private.burimunsi_sessions t),
  'native_accounts',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]') FROM private.burimunsi_accounts t),
  'destination',(SELECT jsonb_build_object('provider',receiver_network,'route',receiver_momo_number) FROM app.collections WHERE id='buri-qualification-group')) INTO current_value;
 IF current_value<>(SELECT value FROM setup_unchanged) THEN RAISE EXCEPTION 'Setup changed financial/auth/native/destination state';END IF;
END;$preserved$;
SELECT jsonb_build_object('contract','collect.burimunsi.scope-setup-sql-fixture.v1','result','PASS','production_acceptance',false);
ROLLBACK;
