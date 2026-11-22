-- QUALIFICATION ONLY. Run after operator-seed and the rolled-back operator /
-- member contracts in the disposable retained-native database. The qualifier
-- supplies source-compiled protected inputs and a separately held genuine WORK
-- lease. No lease, provider authentication, email or native login is fabricated.
-- All extra confirmed identities/session rows below are explicit SQL fixtures.
-- No plaintext PIN or device token enters SQL; all mutations roll back.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
__PROVISIONING_INPUTS__
CREATE FUNCTION pg_temp.provisioning_expect(statement text,expected text,expected_message text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=expected AND (expected_message IS NULL OR SQLERRM=expected_message) THEN RETURN;END IF;
  RAISE EXCEPTION 'Provisioning qualification SQLSTATE %, expected % (message matched=%)',SQLSTATE,expected,
   expected_message IS NULL OR SQLERRM=expected_message;
 END;
 RAISE EXCEPTION 'Expected provisioning qualification SQLSTATE %',expected;
END;$fn$;
CREATE FUNCTION pg_temp.provisioning_apply(p_name text,p_overrides jsonb DEFAULT '{}'::jsonb,p_fingerprint text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY INVOKER AS $fn$
DECLARE input jsonb:=pg_temp.provisioning_fixture(p_name);
BEGIN
 RETURN private.burimunsi_provisioning_apply('f4000000-0000-4000-8000-000000000001',repeat('a',64),
  'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',
  input->'command'||p_overrides,coalesce(p_fingerprint,input->>'fingerprint'),input->>'ciphertext');
END;$fn$;
CREATE FUNCTION pg_temp.provisioning_lookup(p_request uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER AS $fn$
 SELECT private.burimunsi_provisioning_lookup('f4000000-0000-4000-8000-000000000001',repeat('a',64),
  'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',p_request)
$fn$;
CREATE FUNCTION pg_temp.provisioning_delivery(p_name text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER AS $fn$
 SELECT private.burimunsi_provisioning_delivery('f4000000-0000-4000-8000-000000000001',repeat('a',64),
  'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',
  (pg_temp.provisioning_fixture(p_name)->'command'->>'requestId')::uuid,
  (pg_temp.provisioning_fixture(p_name)->'command'->>'installationId')::uuid,
  pg_temp.provisioning_fixture(p_name)->'command'->>'profile',
  (pg_temp.provisioning_fixture(p_name)->'command'->>'expectedGrantVersion')::bigint+1)
$fn$;
DO $preflight$
DECLARE r text;f text;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF (SELECT count(*) FROM private.burimunsi_accounts)<>2 OR EXISTS(SELECT 1 FROM private.burimunsi_sessions)
  OR EXISTS(SELECT 1 FROM private.burimunsi_device_grants) OR EXISTS(SELECT 1 FROM private.burimunsi_provisioning_commands)
  OR (SELECT count(*) FROM auth.users)<>2 OR (SELECT version FROM private.burimunsi_scopes WHERE collection_id='buri-qualification-group')<>1 THEN
  RAISE EXCEPTION 'Clean operator-seed provisioning qualification required';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='private.burimunsi_provisioning_commands'::regclass AND relrowsecurity AND relforcerowsecurity)
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_provisioning_commands'::regclass
   AND tgname='collect_fence_statement_v1' AND tgenabled='A')
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_provisioning_commands'::regclass
   AND tgname='burimunsi_provisioning_retain' AND tgenabled='A')
  OR NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_accounts'::regclass
   AND tgname='burimunsi_provisioning_account_identity' AND tgenabled='A') THEN
  RAISE EXCEPTION 'Provisioning catalog/fence/immutable retention boundary missing';
 END IF;
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer','collect_runtime'] LOOP
  IF has_table_privilege(r,'private.burimunsi_provisioning_commands','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
   RAISE EXCEPTION 'Provisioning owner custody privilege leak %',r;
  END IF;
 END LOOP;
 FOREACH f IN ARRAY ARRAY['private.burimunsi_provisioning_directory(text,text,text,text,text)',
  'private.burimunsi_provisioning_lookup(text,text,text,text,text,uuid)',
  'private.burimunsi_provisioning_cancel(text,text,text,text,text,uuid)',
  'private.burimunsi_provisioning_apply(text,text,text,text,text,jsonb,text,text)',
  'private.burimunsi_provisioning_delivery(text,text,text,text,text,uuid,uuid,text,bigint)'] LOOP
  IF NOT has_function_privilege('collect_runtime',f,'EXECUTE') OR
   NOT EXISTS(SELECT 1 FROM pg_proc WHERE oid=f::regprocedure AND prosecdef AND pg_get_userbyid(proowner)='postgres') THEN
   RAISE EXCEPTION 'Provisioning narrow owner helper missing %',f;
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
   IF has_function_privilege(r,f,'EXECUTE') THEN RAISE EXCEPTION 'Provisioning helper privilege leak % %',f,r;END IF;
  END LOOP;
 END LOOP;
END;$preflight$;

-- Additional shared identity is a confirmed SQL fixture, never a new GoTrue
-- signup or a Buri-created credential universe. Real owner approval is reused.
INSERT INTO auth.users(id,email,email_confirmed_at,is_anonymous)
 VALUES('fc100000-0000-4000-8000-000000000003','provisioning-staff@example.invalid',now(),false);
INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at)
 VALUES('fc300000-0000-4000-8000-000000000003','provisioning-staff@example.invalid','000003','QUALIFICATION Provisioning Staff',
  'operator',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)
 VALUES('fc100000-0000-4000-8000-000000000003','fc300000-0000-4000-8000-000000000003','synthetic-provisioning-qualification');
INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at)
 VALUES('fc400000-0000-4000-8000-000000000003','provisioning-staff@example.invalid','staff','active','supabase-managed',
  'QUALIFICATION Provisioning Staff',app.unixepoch(),app.unixepoch());
INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)
 VALUES('fc400000-0000-4000-8000-000000000003','fc300000-0000-4000-8000-000000000003',
  'synthetic-provisioning-qualification',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',
 'fc600000-0000-4000-8000-000000000091','fc400000-0000-4000-8000-000000000003',
 '+250780000003','staff',ARRAY['records.read','members.enroll'],true,0);

-- A second genuine-shaped owner BFF session deliberately has NO recent email
-- proof. This isolates the fresh-email guard from ordinary role/session access.
INSERT INTO auth.sessions(id,user_id,aal,not_after)
 VALUES('fc200000-0000-4000-8000-000000000009','f1000000-0000-4000-8000-000000000001','aal1',now()+interval '1 hour');
INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)
 VALUES('fc200000-0000-4000-8000-000000000009','f3000000-0000-4000-8000-000000000001',
  'admin',app.unixepoch()-10,app.unixepoch()-10,app.unixepoch()+3500);
INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
 SELECT repeat('9',64),'fc500000-0000-4000-8000-000000000009','f4000000-0000-4000-8000-000000000001',
  1,id,'https://admin.collect.example',auth_at,expires_at FROM app.auth_sessions WHERE id='fc200000-0000-4000-8000-000000000009';
INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)
 VALUES(repeat('9',64),'f1000000-0000-4000-8000-000000000001','fc200000-0000-4000-8000-000000000009','{}');

-- Native session fixtures allow revocation isolation checks; they were not
-- admitted by the HTTP native login. No plaintext bearer is retained in SQL.
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at) VALUES
 ('fc900000-0000-4000-8000-000000000081','buri-qualification-group','fc900000-0000-4000-8000-000000000082',
  pg_temp.provisioning_fixture('sessionHashes')->>'staff','staff','f7000000-0000-4000-8000-000000000002',1),
 ('fc900000-0000-4000-8000-000000000083','buri-qualification-group','fc900000-0000-4000-8000-000000000084',
  pg_temp.provisioning_fixture('sessionHashes')->>'owner','staff','f7000000-0000-4000-8000-000000000001',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id) VALUES
 ('fc900000-0000-4000-8000-000000000081','f7000000-0000-4000-8000-000000000002','buri-qualification-group'),
 ('fc900000-0000-4000-8000-000000000083','f7000000-0000-4000-8000-000000000001','buri-qualification-group');
INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,credential_version,grant_version,
 token_hash,created_at,expires_at,principal_user_id) VALUES
 ('fd000000-0000-4000-8000-000000000001','buri-qualification-group','f7000000-0000-4000-8000-000000000002',
  'fc900000-0000-4000-8000-000000000081','fc900000-0000-4000-8000-000000000082',1,1,
  pg_temp.provisioning_fixture('sessionHashes')->>'staff',1,9007199254740991,'f3000000-0000-4000-8000-000000000002'),
 ('fd000000-0000-4000-8000-000000000002','buri-qualification-group','f7000000-0000-4000-8000-000000000001',
  'fc900000-0000-4000-8000-000000000083','fc900000-0000-4000-8000-000000000084',1,1,
  pg_temp.provisioning_fixture('sessionHashes')->>'owner',1,9007199254740991,'f3000000-0000-4000-8000-000000000001');
INSERT INTO private.burimunsi_command_receipts(collection_id,actor_id,request_id,session_id,operation,fingerprint,response,created_at)
 VALUES('buri-qualification-group','f7000000-0000-4000-8000-000000000002','fd600000-0000-4000-8000-000000000001',
  'fd000000-0000-4000-8000-000000000001','qualification.unknown_checkpoint',repeat('7',64),'{"status":"operation_unknown","qualification_only":true}',1);

-- Independent canonical credential custody: metadata fixture, not a real token,
-- pairing action, upload or provider transaction. Native rotation must not touch it.
INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,version,subscription_evidence,created_at)
 VALUES('provisioning-canonical-binding','f3000000-0000-4000-8000-000000000001','buri-qualification-wallet',1,
  '{"qualification_only":true}',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,claimed_installation_id,created_at)
 VALUES('provisioning-canonical-pairing','provisioning-canonical-binding',repeat('6',64),
  'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,'fc900000-0000-4000-8000-000000000003',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at)
 VALUES('provisioning-canonical-credential','provisioning-canonical-binding','provisioning-canonical-pairing',
  'fc900000-0000-4000-8000-000000000003',repeat('5',64),'QUALIFICATION NOT A REAL CREDENTIAL',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
CREATE TEMP TABLE provisioning_unchanged AS SELECT jsonb_build_object(
 'ledger',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) FROM app.ledger_entries t),
 'payments',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) FROM app.payments t),
 'transactions',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) FROM app.momo_transactions t),
 'captures',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.raw_sms_id),'[]'::jsonb) FROM app.momo_gateway_captures t),
 'bindings',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) FROM app.momo_gateway_bindings t),
 'credentials',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) FROM app.momo_gateway_credentials t),
 'native_journal',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.request_id),'[]'::jsonb) FROM private.burimunsi_command_receipts t)
) AS value;

SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
DO $normal_runtime$ BEGIN
 IF current_user<>'collect_runtime' OR (SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) THEN
  RAISE EXCEPTION 'Provisioning must exercise normal fenced runtime';
 END IF;
END;$normal_runtime$;
SELECT pg_temp.provisioning_expect($q$SELECT * FROM private.burimunsi_provisioning_commands$q$,'42501');
SELECT pg_temp.provisioning_expect($q$UPDATE private.burimunsi_provisioning_commands SET delivery_ciphertext=NULL$q$,'42501');
-- Wrong owner/cookie/public-session/origin never reaches the provisioning writer.
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_directory('f4000000-0000-4000-8000-000000000002',
 repeat('b',64),'https://admin.collect.example','f5000000-0000-4000-8000-000000000002','buri-qualification-group')$q$,'42501');
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_directory('f4000000-0000-4000-8000-000000000001',
 repeat('0',64),'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group')$q$,'42501');
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_directory('f4000000-0000-4000-8000-000000000001',
 repeat('a',64),'https://elsewhere.example.invalid','f5000000-0000-4000-8000-000000000001','buri-qualification-group')$q$,'42501');
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_directory('f4000000-0000-4000-8000-000000000001',
 repeat('a',64),'https://admin.collect.example','f5000000-0000-4000-8000-000000000002','buri-qualification-group')$q$,'42501');
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_directory('f4000000-0000-4000-8000-000000000001',
 repeat('a',64),'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','not-the-server-scope')$q$,'42501');
SAVEPOINT email_missing;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','fc200000-0000-4000-8000-000000000009','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_directory('f4000000-0000-4000-8000-000000000001',
 repeat('9',64),'https://admin.collect.example','fc500000-0000-4000-8000-000000000009','buri-qualification-group')$q$,
 '42501','recent_email_sign_in_required');
ROLLBACK TO SAVEPOINT email_missing;
SAVEPOINT admission_changed;
SELECT set_config('collect.fence_source_sha256',repeat('0',64),true);
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('initial')$q$,'55000');
ROLLBACK TO SAVEPOINT admission_changed;

-- Strict protected-record policy, current approval and version assertions.
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('initial','{"extra_field":true}')$q$,'22023');
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('initial',jsonb_build_object('pinHash',
 pg_temp.provisioning_fixture('initial')->'command'->'pinHash'||'{"iterations":599999}'::jsonb))$q$,'22023');
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('initial','{"approvalVersion":2}')$q$,'40001');
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('initial','{"scopeVersion":2}')$q$,'40001');
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('initial','{"expectedAccountVersion":1}')$q$,'40001');
DO $initial$
DECLARE receipt jsonb;again jsonb;outcome jsonb;directory jsonb;
BEGIN
 receipt:=pg_temp.provisioning_apply('initial');again:=pg_temp.provisioning_apply('initial');
 IF receipt<>again OR receipt->>'accountId'<>'fc700000-0000-4000-8000-000000000003'
  OR receipt->>'accountVersion'<>'1' OR receipt->>'credentialVersion'<>'1' OR receipt->>'applied'<>'true'
  OR receipt ?| ARRAY['pin','pinHash','tokenHash','installationToken','ciphertext'] THEN
  RAISE EXCEPTION 'Initial native PIN/idempotency receipt contract';
 END IF;
 outcome:=pg_temp.provisioning_lookup('fc600000-0000-4000-8000-000000000001');
 IF outcome->>'found'<>'true' OR outcome->'receipt'<>receipt THEN RAISE EXCEPTION 'Original committed PIN outcome missing';END IF;
 IF NOT EXISTS(SELECT 1 FROM private.burimunsi_accounts WHERE id='fc700000-0000-4000-8000-000000000003'
  AND principal_user_id='fc300000-0000-4000-8000-000000000003' AND phone='+250780000003' AND role='staff'
  AND capabilities=ARRAY['records.read','members.enroll'] AND version=1 AND credential_version=1
  AND pin_hash=pg_temp.provisioning_fixture('initial')->'command'->'pinHash') THEN
  RAISE EXCEPTION 'Initial native account is not exact current approved identity';
 END IF;
 directory:=private.burimunsi_provisioning_directory('f4000000-0000-4000-8000-000000000001',repeat('a',64),
  'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group');
 IF directory->>'configured'<>'true' OR jsonb_array_length(directory->'accounts')<>3
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(directory->'accounts') a WHERE a ?| ARRAY['pinHash','pin_hash','tokenHash','installationToken','ciphertext'])
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(directory->'grants') g WHERE g ?| ARRAY['tokenHash','token_hash','installationToken','ciphertext']) THEN
  RAISE EXCEPTION 'Native directory leaks protected custody or omits approved identity';
 END IF;
END;$initial$;
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('initial','{}',repeat('e',64))$q$,'23505');
SELECT pg_temp.provisioning_expect($q$INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,active,created_at,updated_at)
 VALUES('fc700000-0000-4000-8000-000000000099','buri-qualification-group','fc300000-0000-4000-8000-000000000003',
 '+250780000099','QUALIFICATION DUPLICATE','staff',ARRAY['records.read'],pg_temp.provisioning_fixture('initial')->'command'->'pinHash',false,1,1)$q$,'23505');
SELECT pg_temp.provisioning_expect($q$UPDATE private.burimunsi_accounts SET active=false,
 principal_user_id='f3000000-0000-4000-8000-000000000002' WHERE id='fc700000-0000-4000-8000-000000000003'$q$,'23514');
SELECT pg_temp.provisioning_expect($q$UPDATE private.burimunsi_accounts SET created_at=created_at+1
 WHERE id='fc700000-0000-4000-8000-000000000003'$q$,'23514');

DO $pin_reset$
DECLARE r jsonb;
BEGIN
 r:=pg_temp.provisioning_apply('resetStaff');
 IF r->>'accountVersion'<>'2' OR r->>'credentialVersion'<>'2'
  OR (SELECT revoked FROM private.burimunsi_sessions WHERE id='fd000000-0000-4000-8000-000000000001') IS DISTINCT FROM true
  OR (SELECT revoked FROM private.burimunsi_sessions WHERE id='fd000000-0000-4000-8000-000000000002') IS DISTINCT FROM false
  OR NOT EXISTS(SELECT 1 FROM private.burimunsi_accounts WHERE id='f7000000-0000-4000-8000-000000000002'
   AND version=2 AND credential_version=2 AND pin_hash=pg_temp.provisioning_fixture('resetStaff')->'command'->'pinHash')
  OR (SELECT active FROM private.burimunsi_device_grants WHERE id='fc900000-0000-4000-8000-000000000081') IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'PIN reset failed exact version/session isolation';
 END IF;
 r:=pg_temp.provisioning_apply('resetOwner');
 IF r->>'accountVersion'<>'2' OR r->>'credentialVersion'<>'2'
  OR (SELECT revoked FROM private.burimunsi_sessions WHERE id='fd000000-0000-4000-8000-000000000002') IS DISTINCT FROM true
  OR (SELECT revoked_at FROM app.auth_sessions WHERE id='f2000000-0000-4000-8000-000000000001') IS NOT NULL THEN
  RAISE EXCEPTION 'Native owner PIN reset changed shared managed identity';
 END IF;
END;$pin_reset$;
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('resetStaff',
 '{"requestId":"fc600000-0000-4000-8000-000000000092"}')$q$,'40001');

-- Owner approval/version, confirmed Auth and capability ceiling remain current.
SAVEPOINT approval_reduced;
SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',
 'fc600000-0000-4000-8000-000000000093','fc400000-0000-4000-8000-000000000003',
 '+250780000003','staff',ARRAY['records.read'],true,1);
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('grantStaff')$q$,'40001');
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('grantStaff','{"approvalVersion":2}')$q$,'42501');
ROLLBACK TO SAVEPOINT approval_reduced;
SAVEPOINT approval_disabled;
SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',
 'fc600000-0000-4000-8000-000000000094','fc400000-0000-4000-8000-000000000003',
 '+250780000003','staff',ARRAY['records.read','members.enroll'],false,1);
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('grantStaff','{"approvalVersion":2}')$q$,'42501');
ROLLBACK TO SAVEPOINT approval_disabled;
SAVEPOINT confirmation_removed;
RESET ROLE;
UPDATE auth.users SET email_confirmed_at=NULL WHERE id='fc100000-0000-4000-8000-000000000003';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('grantStaff')$q$,'42501');
ROLLBACK TO SAVEPOINT confirmation_removed;
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('grantStaff','{"profile":"internal_receiver"}')$q$,'42501');

DO $staff_grant$
DECLARE receipt jsonb;delivery jsonb;
BEGIN
 receipt:=pg_temp.provisioning_apply('grantStaff');delivery:=pg_temp.provisioning_delivery('grantStaff');
 IF receipt->>'grantVersion'<>'1' OR receipt->>'active'<>'true' OR receipt ?| ARRAY['installationToken','tokenHash','ciphertext']
  OR delivery->'receipt'<>receipt OR delivery->>'ciphertext'<>pg_temp.provisioning_fixture('grantStaff')->>'ciphertext'
  OR delivery->>'tokenHash'<>pg_temp.provisioning_fixture('grantStaff')->'command'->>'tokenHash'
  OR delivery ? 'installationToken'
  OR NOT EXISTS(SELECT 1 FROM private.burimunsi_device_grants WHERE id='fc900000-0000-4000-8000-000000000002'
    AND installation_id='fc900000-0000-4000-8000-000000000001' AND profile='staff' AND active AND version=1
    AND custodian_account_id='fc700000-0000-4000-8000-000000000003'
    AND token_hash=pg_temp.provisioning_fixture('grantStaff')->'command'->>'tokenHash') THEN
  RAISE EXCEPTION 'Exact staff grant/hash-only ciphertext custody contract';
 END IF;
 IF pg_temp.provisioning_lookup('fc600000-0000-4000-8000-000000000004')->'receipt'<>receipt
  OR pg_temp.provisioning_apply('grantStaff')<>receipt THEN RAISE EXCEPTION 'Lost grant outcome/replay contract';END IF;
END;$staff_grant$;
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_delivery('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',
 'fc600000-0000-4000-8000-000000000004','fc900000-0000-4000-8000-000000000003','staff',1)$q$,'42501','burimunsi_delivery_expired');
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_delivery('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',
 'fc600000-0000-4000-8000-000000000004','fc900000-0000-4000-8000-000000000001','internal_receiver',1)$q$,'42501','burimunsi_delivery_expired');
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_delivery('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',
 'fc600000-0000-4000-8000-000000000004','fc900000-0000-4000-8000-000000000001','staff',2)$q$,'42501','burimunsi_delivery_expired');

-- An expired row is a declared immutable SQL fixture, not a clock override or a
-- changed production receipt. Its ciphertext is actually source-encrypted for
-- this different request's AAD; the expiry guard must deny it before release.
RESET ROLE;
WITH clock AS MATERIALIZED(SELECT floor(extract(epoch FROM clock_timestamp())*1000)::bigint AS at_ms)
INSERT INTO private.burimunsi_provisioning_commands(collection_id,actor_id,request_id,principal_session_id,
 operation,fingerprint,response,delivery_ciphertext,delivery_expires_at,created_at)
 SELECT collection_id,actor_id,'fc600000-0000-4000-8000-000000000090',principal_session_id,operation,
  repeat('4',64),response||jsonb_build_object('requestId','fc600000-0000-4000-8000-000000000090',
   'deliveryExpiresAt',clock.at_ms-100),
  pg_temp.provisioning_fixture('expiredDelivery')->>'ciphertext',clock.at_ms-100,clock.at_ms-900100
 FROM private.burimunsi_provisioning_commands CROSS JOIN clock WHERE request_id='fc600000-0000-4000-8000-000000000004';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_delivery('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',
 'fc600000-0000-4000-8000-000000000090','fc900000-0000-4000-8000-000000000001','staff',1)$q$,'42501','burimunsi_delivery_expired');
SAVEPOINT scope_changed;
UPDATE private.burimunsi_scopes SET version=version+1 WHERE collection_id='buri-qualification-group';
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_delivery('grantStaff')$q$,'42501','burimunsi_delivery_expired');
ROLLBACK TO SAVEPOINT scope_changed;
SAVEPOINT account_changed;
UPDATE private.burimunsi_accounts SET version=version+1,credential_version=credential_version+1
 WHERE id='fc700000-0000-4000-8000-000000000003';
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_delivery('grantStaff')$q$,'42501','burimunsi_delivery_expired');
ROLLBACK TO SAVEPOINT account_changed;
SAVEPOINT delivery_approval_changed;
SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group',
 'fc600000-0000-4000-8000-000000000097','fc400000-0000-4000-8000-000000000003',
 '+250780000003','staff',ARRAY['records.read','members.enroll'],true,1);
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_delivery('grantStaff')$q$,'42501','burimunsi_delivery_expired');
ROLLBACK TO SAVEPOINT delivery_approval_changed;

INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,credential_version,grant_version,token_hash,created_at,expires_at,principal_user_id)
 VALUES('fd000000-0000-4000-8000-000000000003','buri-qualification-group','fc700000-0000-4000-8000-000000000003',
  'fc900000-0000-4000-8000-000000000002','fc900000-0000-4000-8000-000000000001',1,1,
  pg_temp.provisioning_fixture('sessionHashes')->>'newStaff',1,9007199254740991,'fc300000-0000-4000-8000-000000000003');
DO $rotate_staff$
DECLARE r jsonb;
BEGIN
 r:=pg_temp.provisioning_apply('rotateStaff');
 IF r->>'grantVersion'<>'2' OR (SELECT revoked FROM private.burimunsi_sessions WHERE id='fd000000-0000-4000-8000-000000000003') IS DISTINCT FROM true
  OR (SELECT token_hash FROM private.burimunsi_device_grants WHERE id='fc900000-0000-4000-8000-000000000002')<>
   pg_temp.provisioning_fixture('rotateStaff')->'command'->>'tokenHash' THEN RAISE EXCEPTION 'Native staff rotation failed';END IF;
 IF (pg_temp.provisioning_delivery('rotateStaff'))->'receipt'<>r THEN RAISE EXCEPTION 'Rotated custody unavailable';END IF;
END;$rotate_staff$;
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_delivery('grantStaff')$q$,'42501','burimunsi_delivery_expired');
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('rotateStaff',
 '{"requestId":"fc600000-0000-4000-8000-000000000095"}')$q$,'40001');
DO $revoke_staff$ DECLARE r jsonb;
BEGIN
 r:=pg_temp.provisioning_apply('revokeStaff');
 IF r->>'grantVersion'<>'3' OR r->>'active'<>'false' OR r->'deliveryExpiresAt'<>'null'::jsonb
  OR (SELECT active FROM private.burimunsi_device_grants WHERE id='fc900000-0000-4000-8000-000000000002') IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Native staff revocation failed';END IF;
END;$revoke_staff$;
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_delivery('rotateStaff')$q$,'42501','burimunsi_delivery_expired');

DO $receiver$ DECLARE r jsonb;
BEGIN
 r:=pg_temp.provisioning_apply('grantReceiver');
 IF r->>'profile'<>'internal_receiver' OR r->>'accountId'<>'f7000000-0000-4000-8000-000000000001'
  OR (pg_temp.provisioning_delivery('grantReceiver'))->'receipt'<>r THEN RAISE EXCEPTION 'Exact receiver custodian grant failed';END IF;
END;$receiver$;
-- Multiple ordinary installations can register without becoming a second
-- canonical SMS receiver. Existing owner/BFF/email approval stays mandatory.
SAVEPOINT ordinary_second_installation;
DO $second_installation$
DECLARE result jsonb;before_binding jsonb;before_credentials jsonb;
BEGIN
 SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) INTO before_binding FROM app.momo_gateway_bindings b;
 SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) INTO before_credentials FROM app.momo_gateway_credentials c;
 result:=pg_temp.provisioning_apply('secondReceiver');
 IF result->>'profile'<>'internal_receiver' OR result->>'grantVersion'<>'1'
  OR (pg_temp.provisioning_delivery('secondReceiver'))->'receipt'<>result
  OR (SELECT count(*) FROM private.burimunsi_device_grants WHERE collection_id='buri-qualification-group' AND active AND profile='internal_receiver')<>2
  OR before_binding IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(b) ORDER BY b.id) FROM app.momo_gateway_bindings b)
  OR before_credentials IS DISTINCT FROM (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.id) FROM app.momo_gateway_credentials c) THEN
  RAISE EXCEPTION 'Ordinary installation registration changed canonical receiving authority';
 END IF;
END;$second_installation$;
ROLLBACK TO ordinary_second_installation;
-- A second installation may not copy another installation's secret, including
-- by changing the profile. These are still real database uniqueness failures.
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('secondReceiver',
 jsonb_build_object('tokenHash',pg_temp.provisioning_fixture('grantReceiver')->'command'->>'tokenHash'))$q$,'23505');
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('secondReceiver',
 jsonb_build_object('profile','staff','tokenHash',pg_temp.provisioning_fixture('grantReceiver')->'command'->>'tokenHash'))$q$,'23505');
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('rotateReceiver','{"profile":"staff"}')$q$,'40001');
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('rotateReceiver',
 '{"accountId":"f7000000-0000-4000-8000-000000000002"}')$q$,'40001');
INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,credential_version,grant_version,token_hash,created_at,expires_at,principal_user_id)
 VALUES('fd000000-0000-4000-8000-000000000004','buri-qualification-group','f7000000-0000-4000-8000-000000000001',
  'fc900000-0000-4000-8000-000000000004','fc900000-0000-4000-8000-000000000003',2,1,
  pg_temp.provisioning_fixture('sessionHashes')->>'receiver',1,9007199254740991,'f3000000-0000-4000-8000-000000000001');
DO $receiver_rotation$ DECLARE r jsonb;
BEGIN
 r:=pg_temp.provisioning_apply('rotateReceiver');
 IF r->>'grantVersion'<>'2' OR (SELECT revoked FROM private.burimunsi_sessions WHERE id='fd000000-0000-4000-8000-000000000004') IS DISTINCT FROM true
  OR (pg_temp.provisioning_delivery('rotateReceiver'))->'receipt'<>r THEN RAISE EXCEPTION 'Receiver rotation/session custody failed';END IF;
 INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,credential_version,grant_version,token_hash,created_at,expires_at,principal_user_id)
  VALUES('fd000000-0000-4000-8000-000000000005','buri-qualification-group','f7000000-0000-4000-8000-000000000001',
   'fc900000-0000-4000-8000-000000000004','fc900000-0000-4000-8000-000000000003',2,2,
   pg_temp.provisioning_fixture('sessionHashes')->>'receiverRevoked',1,9007199254740991,'f3000000-0000-4000-8000-000000000001');
 r:=pg_temp.provisioning_apply('revokeReceiver');
 IF r->>'active'<>'false' OR r->>'grantVersion'<>'3'
  OR (SELECT revoked FROM private.burimunsi_sessions WHERE id='fd000000-0000-4000-8000-000000000005') IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Receiver revoke/session invalidation failed';END IF;
END;$receiver_rotation$;
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_delivery('grantReceiver')$q$,'42501','burimunsi_delivery_expired');
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_delivery('rotateReceiver')$q$,'42501','burimunsi_delivery_expired');

-- Cancellation is a durable original-key tombstone. A committed request wins
-- its race and returns its original receipt; no mutation is erased/repeated.
DO $cancel$ DECLARE r jsonb;again jsonb;
BEGIN
 r:=private.burimunsi_provisioning_cancel('f4000000-0000-4000-8000-000000000001',repeat('a',64),
  'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group','fc600000-0000-4000-8000-000000000004');
 IF r<>pg_temp.provisioning_lookup('fc600000-0000-4000-8000-000000000004')->'receipt' OR r->>'operation'<>'grant_installation' THEN
  RAISE EXCEPTION 'Cancellation erased a committed grant';END IF;
 r:=private.burimunsi_provisioning_cancel('f4000000-0000-4000-8000-000000000001',repeat('a',64),
  'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group','fc600000-0000-4000-8000-000000000096');
 again:=pg_temp.provisioning_lookup('fc600000-0000-4000-8000-000000000096')->'receipt';
 IF r<>again OR r->>'operation'<>'cancelled' OR r->>'applied'<>'false' OR r ?| ARRAY['pin','pinHash','installationToken','ciphertext'] THEN
  RAISE EXCEPTION 'Cancellation original-key tombstone contract';END IF;
END;$cancel$;
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_apply('initial',
 '{"requestId":"fc600000-0000-4000-8000-000000000096"}')$q$,'23505');
SAVEPOINT changed_bff;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','fc200000-0000-4000-8000-000000000009','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_lookup('fc600000-0000-4000-8000-000000000004')$q$,'42501');
ROLLBACK TO SAVEPOINT changed_bff;
-- The second BFF cannot acquire a new independent proof by bypassing the seeded
-- identity's OTP cooldown. Stage an attempt one second after the actual retained
-- challenge, always in the past: no wall-clock sleep or future proof is invented.
-- A declared Auth AMR row alone is not sensitive-Admin email authority. This is a
-- negative chronology/proof test, not a newly verified cross-session BFF test.
SAVEPOINT same_owner_new_session;
RESET ROLE;
INSERT INTO auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at)
 SELECT 'fc800000-0000-4000-8000-000000000009'::uuid,id::uuid,'otp',to_timestamp(auth_at),to_timestamp(auth_at)
 FROM app.auth_sessions WHERE id='fc200000-0000-4000-8000-000000000009';
SELECT pg_temp.provisioning_expect($q$INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,
 created_at,expires_at,attempts,consumed_at,delivery_status)
 SELECT 'provisioning-owner-new-session-email',identity_hash,identity_type,identity_value,surface,registration_allowed,
 created_at+1,created_at+301,0,NULL,'pending'
 FROM private.supabase_otp_challenges WHERE id='buri-qualification-email'$q$,'P0001','otp_cooldown');
DO $no_invented_proof$ BEGIN
 IF EXISTS(SELECT 1 FROM private.supabase_otp_challenges WHERE id='provisioning-owner-new-session-email')
  OR EXISTS(SELECT 1 FROM private.admin_sensitive_email_proofs WHERE public_session_id='fc500000-0000-4000-8000-000000000009') THEN
  RAISE EXCEPTION 'Cooldown must not mint a challenge or a second BFF verification';
 END IF;
END;$no_invented_proof$;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','fc200000-0000-4000-8000-000000000009','role','authenticated','aal','aal1','exp',app.unixepoch()+600,
 'amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',auth_at)))::text,true)
 FROM app.auth_sessions WHERE id='fc200000-0000-4000-8000-000000000009';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.provisioning_expect($q$SELECT private.admin_email_record_initial('f4000000-0000-4000-8000-000000000001',repeat('9',64),
 'https://admin.collect.example','fc500000-0000-4000-8000-000000000009','provisioning-owner-new-session-email')$q$,'42501','admin_email_denied');
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_lookup('f4000000-0000-4000-8000-000000000001',repeat('9',64),
 'https://admin.collect.example','fc500000-0000-4000-8000-000000000009','buri-qualification-group',
 'fc600000-0000-4000-8000-000000000004')$q$,'42501','recent_email_sign_in_required');
SELECT pg_temp.provisioning_expect($q$SELECT private.burimunsi_provisioning_cancel('f4000000-0000-4000-8000-000000000001',repeat('9',64),
 'https://admin.collect.example','fc500000-0000-4000-8000-000000000009','buri-qualification-group',
 'fc600000-0000-4000-8000-000000000004')$q$,'42501','recent_email_sign_in_required');
ROLLBACK TO SAVEPOINT same_owner_new_session;
SAVEPOINT owner_revoked;
RESET ROLE;
UPDATE app.admin_users SET auth_version=auth_version+1 WHERE id='f4000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.provisioning_expect($q$SELECT pg_temp.provisioning_lookup('fc600000-0000-4000-8000-000000000004')$q$,'42501');
ROLLBACK TO SAVEPOINT owner_revoked;

RESET ROLE;
DO $retained$
DECLARE observed jsonb;
BEGIN
 IF (SELECT count(*) FROM private.burimunsi_provisioning_commands)<>11
  OR EXISTS(SELECT 1 FROM private.burimunsi_provisioning_commands WHERE response ?| ARRAY['pin','pinHash','tokenHash','installationToken','ciphertext'])
  OR EXISTS(SELECT 1 FROM private.burimunsi_provisioning_commands WHERE operation='grant_installation' AND
    (delivery_ciphertext IS NULL OR delivery_ciphertext NOT LIKE '{"v":1,%' OR delivery_expires_at-created_at<>900000))
  OR EXISTS(SELECT 1 FROM private.burimunsi_provisioning_commands WHERE operation<>'grant_installation' AND delivery_ciphertext IS NOT NULL)
  OR (SELECT count(*) FROM auth.users)<>3 OR (SELECT count(*) FROM private.burimunsi_accounts)<>3 THEN
  RAISE EXCEPTION 'Provisioning retained outcome/ciphertext-only invariants';
 END IF;
 SELECT jsonb_build_object(
  'ledger',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) FROM app.ledger_entries t),
  'payments',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) FROM app.payments t),
  'transactions',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) FROM app.momo_transactions t),
  'captures',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.raw_sms_id),'[]'::jsonb) FROM app.momo_gateway_captures t),
  'bindings',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) FROM app.momo_gateway_bindings t),
  'credentials',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id),'[]'::jsonb) FROM app.momo_gateway_credentials t),
  'native_journal',(SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.request_id),'[]'::jsonb) FROM private.burimunsi_command_receipts t)
 ) INTO observed;
 IF observed IS DISTINCT FROM (SELECT value FROM provisioning_unchanged)
  OR EXISTS(SELECT 1 FROM app.auth_sessions WHERE id IN('f2000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000002') AND revoked_at IS NOT NULL) THEN
  RAISE EXCEPTION 'Native provisioning changed independent canonical capture/financial journal/shared sign-in';
 END IF;
END;$retained$;
SELECT pg_temp.provisioning_expect($q$UPDATE private.burimunsi_provisioning_commands SET fingerprint=repeat('0',64)$q$,'55000');
SELECT pg_temp.provisioning_expect($q$DELETE FROM private.burimunsi_provisioning_commands$q$,'55000');
ROLLBACK;
