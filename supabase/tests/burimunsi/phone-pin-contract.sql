-- QUALIFICATION ONLY. Disposable retained-schema database, after operator-seed.
-- Deterministic tokens below are public synthetic fixtures, never runtime secrets.
-- This qualifies the private SQL CAS/proof/guard contract, not the JS PIN
-- derivation, GoTrue, provider delivery, Android installation or real SIM capture.
-- The existing approved principals are reused; no GoTrue/BFF rows are created.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
CREATE FUNCTION pg_temp.pin_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'Native PIN qualification: %',label;END IF;END;$fn$;
CREATE FUNCTION pg_temp.pin_expect(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=expected THEN RETURN;END IF;
  RAISE EXCEPTION 'Native PIN SQLSTATE %, expected %, message %',SQLSTATE,expected,SQLERRM;
 END;
 RAISE EXCEPTION 'Native PIN expected SQLSTATE %',expected;
END;$fn$;
CREATE FUNCTION pg_temp.pin_clear() RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 PERFORM set_config('burimunsi.pin_token','',true),set_config('burimunsi.pin_installation','',true),
  set_config('burimunsi.pin_device','',true),set_config('burimunsi.pin_profile','',true);
END;$fn$;
CREATE FUNCTION pg_temp.pin_login(phone text,installation uuid,network_digit text DEFAULT '1') RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT private.burimunsi_pin_login_account(phone,encode(sha256(convert_to(phone,'UTF8')),'hex'),installation,
  repeat(network_digit,64),floor(extract(epoch FROM clock_timestamp())*1000)::bigint)
$fn$;
CREATE FUNCTION pg_temp.pin_create(account uuid,installation uuid,token_digit text,device_digit text,
 credential bigint DEFAULT 1,version bigint DEFAULT 1,scope text DEFAULT 'buri-qualification-group')
RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT private.burimunsi_pin_create_session(scope,account,installation,'internal_receiver',
  encode(sha256(convert_to(repeat(device_digit,64),'UTF8')),'hex'),credential,gen_random_uuid(),
  encode(sha256(convert_to(repeat(token_digit,64),'UTF8')),'hex'),
  floor(extract(epoch FROM clock_timestamp())*1000)::bigint,
  floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,version)
$fn$;
CREATE FUNCTION pg_temp.pin_set(token_digit text,installation uuid,device_digit text) RETURNS jsonb LANGUAGE sql AS $fn$
 SELECT private.burimunsi_set_pin_context(repeat(token_digit,64),installation,repeat(device_digit,64),'internal_receiver')
$fn$;
CREATE FUNCTION pg_temp.pin_exists(token_digit text,installation uuid,device_digit text) RETURNS boolean LANGUAGE sql AS $fn$
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(repeat(token_digit,64),installation,repeat(device_digit,64),'internal_receiver'))
$fn$;
DO $catalog$
DECLARE t text;r text;f text;
BEGIN
 PERFORM private._collect_fence_require_operator();
 FOREACH t IN ARRAY ARRAY['burimunsi_pin_login_limits','burimunsi_native_staff_delegations','burimunsi_pin_session_links'] LOOP
  PERFORM pg_temp.pin_check(EXISTS(SELECT 1 FROM pg_class WHERE oid=('private.'||t)::regclass AND relrowsecurity AND relforcerowsecurity),'FORCE RLS '||t);
  PERFORM pg_temp.pin_check(EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=('private.'||t)::regclass AND tgname='collect_fence_statement_v1' AND tgenabled='A'),'ALWAYS fence '||t);
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
   PERFORM pg_temp.pin_check(NOT has_table_privilege(r,'private.'||t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),'private table ACL '||r||' '||t);
  END LOOP;
  PERFORM pg_temp.pin_check(NOT has_table_privilege('collect_runtime','private.'||t,'INSERT,UPDATE,DELETE,TRUNCATE'),'owner-only native metadata '||t);
 END LOOP;
 FOREACH f IN ARRAY ARRAY['private.burimunsi_pin_login_account(text,text,uuid,text,bigint)',
  'private.burimunsi_pin_create_session(text,uuid,uuid,text,text,bigint,uuid,text,bigint,bigint,bigint)',
  'private.burimunsi_pin_session_context(text,uuid,text,text)','private.burimunsi_pin_context()',
  'private.burimunsi_set_pin_context(text,uuid,text,text)',
  'private.burimunsi_pin_resolve_staff(text,uuid,text,text,text,text[],uuid)'] LOOP
  PERFORM pg_temp.pin_check(has_function_privilege('collect_runtime',f,'EXECUTE'),'runtime contract '||f);
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
   PERFORM pg_temp.pin_check(NOT has_function_privilege(r,f,'EXECUTE'),'private function ACL '||r||' '||f);
  END LOOP;
 END LOOP;
 PERFORM pg_temp.pin_check(NOT has_function_privilege('collect_runtime','private.burimunsi_pin_login_budget(text,uuid,text,bigint)','EXECUTE'),'budget cannot be bypassed separately');
 PERFORM pg_temp.pin_check(to_regclass('private.burimunsi_one_receiving_installation') IS NULL,'ordinary installations not singleton');
 PERFORM pg_temp.pin_check(EXISTS(SELECT 1 FROM pg_index WHERE indexrelid='private.burimunsi_scoped_device_secret'::regclass AND indisunique),'scoped installation secret uniqueness');
 PERFORM pg_temp.pin_check((SELECT count(*) FROM auth.users)=2 AND (SELECT count(*) FROM app.auth_sessions)=2
  AND (SELECT count(*) FROM private.bff_sessions)=2 AND (SELECT count(*) FROM app.admin_users)=2,'clean synthetic seed');
END;$catalog$;
-- A scope can await receiver activation while its approved operators sign in.
UPDATE private.burimunsi_scopes SET enabled=false WHERE collection_id='buri-qualification-group';
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
SELECT set_config('burimunsi.collection_id','untrusted-client-scope',true);
SELECT pg_temp.pin_check(pg_temp.pin_login('+250780000001','fe900000-0000-4000-8000-000000000001')->'account'->>'groupId'='buri-qualification-group','server-owned phone scope lookup before pairing');
SELECT pg_temp.pin_check(pg_temp.pin_login('+250780000099','fe900000-0000-4000-8000-000000000002')->'account'='null'::jsonb,'unknown phone generic empty account');
-- Admission has account, installation and trusted-network limits, all global
-- across possible scopes. Every denied call returns normally (durable commit).
DO $budgets$
DECLARE result jsonb;i integer;
BEGIN
 FOR i IN 1..6 LOOP
  result:=pg_temp.pin_login('+250780000098','fe900000-0000-4000-8000-000000000003','2');
  PERFORM pg_temp.pin_check((result->>'allowed')::boolean=(i<=5),'account admission limit '||i);
  PERFORM pg_temp.pin_check(result->'account'='null'::jsonb,'budget never reveals unknown identity');
 END LOOP;
 FOR i IN 1..11 LOOP
  result:=pg_temp.pin_login('+25078'||lpad((100+i)::text,7,'0'),'fe900000-0000-4000-8000-000000000004','3');
  PERFORM pg_temp.pin_check((result->>'allowed')::boolean=(i<=10),'installation admission limit '||i);
 END LOOP;
 FOR i IN 1..51 LOOP
  result:=pg_temp.pin_login('+25078'||lpad((200+i)::text,7,'0'),gen_random_uuid(),'4');
  PERFORM pg_temp.pin_check((result->>'allowed')::boolean=(i<=50),'network admission limit '||i);
 END LOOP;
END;$budgets$;
SELECT pg_temp.pin_expect($q$SELECT private.burimunsi_pin_login_account('+250780000001',repeat('f',64),gen_random_uuid(),repeat('5',64),floor(extract(epoch FROM clock_timestamp())*1000)::bigint)$q$,'22023');
SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);
-- Staff can sign in first on the ordinary receiver-profile APK, without gaining
-- custody; a subsequent valid admin PIN reuses the same local installation.
SELECT pg_temp.pin_check((pg_temp.pin_create('f7000000-0000-4000-8000-000000000002','fe900000-0000-4000-8000-000000000010','b','a')->>'created')::boolean,'first staff installation registration');
SELECT pg_temp.pin_set('b','fe900000-0000-4000-8000-000000000010','a');
SELECT pg_temp.pin_check((SELECT d.custodian_account_id IS NULL FROM private.burimunsi_device_grants d JOIN private.burimunsi_pin_context() c ON c.grant_id=d.id),'staff receives no SMS custody');
SELECT pg_temp.pin_expect($q$SELECT private.burimunsi_pin_resolve_staff('buri-qualification-group',api.current_session_id()::uuid,api.current_principal_id(),'Forbidden Staff','+250780000005',ARRAY['records.read'],gen_random_uuid())$q$,'42501');
SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000010','c','a');
SELECT pg_temp.pin_set('c','fe900000-0000-4000-8000-000000000010','a');
SELECT private.burimunsi_pin_claim_custody('buri-qualification-group',(SELECT grant_id FROM private.burimunsi_pin_context()),'f7000000-0000-4000-8000-000000000001');
SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000002','fe900000-0000-4000-8000-000000000010','d','a');
SELECT pg_temp.pin_set('d','fe900000-0000-4000-8000-000000000010','a');
SELECT pg_temp.pin_check((SELECT d.custodian_account_id='f7000000-0000-4000-8000-000000000001'::uuid AND d.version=1 FROM private.burimunsi_device_grants d JOIN private.burimunsi_pin_context() c ON c.grant_id=d.id),'account switch preserves independent custodian and grant');
SELECT pg_temp.pin_expect($q$SELECT private.burimunsi_pin_claim_custody('buri-qualification-group',(SELECT grant_id FROM private.burimunsi_pin_context()),'f7000000-0000-4000-8000-000000000001')$q$,'42501');
SELECT pg_temp.pin_set('c','fe900000-0000-4000-8000-000000000010','a');
SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000011','f','e');
SELECT pg_temp.pin_expect($q$SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000012','9','a')$q$,'42501');
SELECT pg_temp.pin_expect($q$SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000010','9','e')$q$,'42501');
SELECT pg_temp.pin_expect($q$SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000012','9','7',2,1)$q$,'42501');
SELECT pg_temp.pin_expect($q$SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000012','9','7',1,2)$q$,'42501');
-- Raw proof is mandatory. Stored session/device hashes, actor IDs, valid web
-- claims, arbitrary routing GUCs and a correct installation alone do not suffice.
SELECT pg_temp.pin_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(
 encode(sha256(convert_to(repeat('c',64),'UTF8')),'hex'),'fe900000-0000-4000-8000-000000000010',repeat('a',64),'internal_receiver')),'stored session hash not bearer');
SELECT pg_temp.pin_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_session_context(
 repeat('c',64),'fe900000-0000-4000-8000-000000000010',encode(sha256(convert_to(repeat('a',64),'UTF8')),'hex'),'internal_receiver')),'stored device hash not bearer');
SELECT pg_temp.pin_check(NOT pg_temp.pin_exists('c','fe900000-0000-4000-8000-000000000011','a'),'wrong installation denied');
SELECT pg_temp.pin_expect($q$SELECT private.assert_actor('users.manage','another-scope',NULL,1,300)$q$,'42501');
SELECT pg_temp.pin_expect($q$SELECT private.assert_actor('admin_users.manage','buri-qualification-group',NULL,1,300)$q$,'42501');
SELECT pg_temp.pin_expect($q$SELECT private.assert_actor('users.manage','buri-qualification-group',NULL,2,300)$q$,'42501');
SAVEPOINT spoof;
SELECT set_config('burimunsi.pin_token',repeat('0',64),true),set_config('burimunsi.actor_id','f7000000-0000-4000-8000-000000000001',true),
 set_config('request.jwt.claims','{"sub":"f1000000-0000-4000-8000-000000000001","session_id":"f2000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
SELECT pg_temp.pin_check(api.current_principal_id() IS NULL AND api.current_session_id() IS NULL,'forged native context cannot fall back to web claims');
SELECT pg_temp.pin_expect($q$SELECT private.assert_actor()$q$,'42501');
ROLLBACK TO spoof;
-- Truthful native provenance enters the existing canonical command guard.
INSERT INTO app.mutation_guards(id,user_id,session_id,now_seconds,collection_id,permission,fresh_seconds)
 VALUES('pin-valid-member',api.current_principal_id(),api.current_session_id(),app.unixepoch(),'buri-qualification-group','users.manage',300);
SELECT pg_temp.pin_expect($q$INSERT INTO app.mutation_guards(id,user_id,session_id,now_seconds,collection_id,permission,fresh_seconds)
 VALUES('pin-fake-actor','f3000000-0000-4000-8000-000000000002',api.current_session_id(),app.unixepoch(),'buri-qualification-group','users.manage',300)$q$,'42501');
SELECT pg_temp.pin_expect($q$INSERT INTO app.mutation_guards(id,user_id,session_id,now_seconds,permission,fresh_seconds)
 VALUES('pin-global',api.current_principal_id(),api.current_session_id(),app.unixepoch(),'users.manage',300)$q$,'42501');
SELECT pg_temp.pin_expect($q$SELECT private.assert_actor('payments.reconcile','buri-qualification-group',NULL,1,300)$q$,'42501');
SELECT pg_temp.pin_expect($q$SELECT private.assert_actor('sms.reveal','buri-qualification-group',NULL,1,300)$q$,'42501');
-- Genuine scoped staff identity/delegation from the original Add Staff form.
DO $staff$
DECLARE target jsonb;again jsonb;
BEGIN
 target:=private.burimunsi_pin_resolve_staff('buri-qualification-group',api.current_session_id()::uuid,api.current_principal_id(),
  'QUALIFICATION Native Staff','+250780000006',ARRAY['records.read','members.enroll'],'fe600000-0000-4000-8000-000000000006');
 again:=private.burimunsi_pin_resolve_staff('buri-qualification-group',api.current_session_id()::uuid,api.current_principal_id(),
  'QUALIFICATION Native Staff','+250780000006',ARRAY['members.enroll','records.read'],'fe600000-0000-4000-8000-000000000006');
 PERFORM pg_temp.pin_check(target=again,'scoped staff resolver replay');
 INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
  VALUES('fe700000-0000-4000-8000-000000000006','buri-qualification-group',target->>'id','+250780000006','QUALIFICATION Native Staff','staff',
   ARRAY['records.read','members.enroll'],'{"qualification_only":true}',1,1);
 PERFORM pg_temp.pin_check(private.burimunsi_operator_is_current('buri-qualification-group',target->>'id','+250780000006','staff',ARRAY['records.read','payments.allocate']),'current parent grants bounded staff edit ceiling');
END;$staff$;
SELECT pg_temp.pin_expect($q$SELECT private.burimunsi_pin_resolve_staff('another-scope',api.current_session_id()::uuid,api.current_principal_id(),'Forbidden Staff','+250780000007',ARRAY['records.read'],gen_random_uuid())$q$,'42501');
SELECT pg_temp.pin_expect($q$SELECT private.burimunsi_pin_resolve_staff('buri-qualification-group',api.current_session_id()::uuid,api.current_principal_id(),'Forbidden Staff','+250780000007',ARRAY['records.read','gateway.manage'],gen_random_uuid())$q$,'42501');
RESET ROLE;
SELECT pg_temp.pin_check((SELECT count(*) FROM auth.users)=2 AND (SELECT count(*) FROM app.auth_sessions)=2
 AND (SELECT count(*) FROM private.bff_sessions)=2 AND (SELECT count(*) FROM app.admin_users)=2
 AND NOT EXISTS(SELECT 1 FROM app.admin_principal_links WHERE user_id=(SELECT principal_user_id FROM private.burimunsi_accounts WHERE id='fe700000-0000-4000-8000-000000000006')),'native staff creates no global Auth/Admin authority');
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.pin_create('fe700000-0000-4000-8000-000000000006','fe900000-0000-4000-8000-000000000013','9','7');
SELECT pg_temp.pin_set('9','fe900000-0000-4000-8000-000000000013','7');
SELECT pg_temp.pin_check(private.assert_actor('users.manage','buri-qualification-group',NULL,1,300)=api.current_principal_id(),'genuine delegated staff command authority');
SELECT pg_temp.pin_expect($q$UPDATE private.burimunsi_accounts SET capabilities=ARRAY['records.read','payments.allocate'],version=version+1,credential_version=credential_version+1
 WHERE id='fe700000-0000-4000-8000-000000000006'$q$,'42501');
SELECT pg_temp.pin_set('c','fe900000-0000-4000-8000-000000000010','a');
UPDATE private.burimunsi_accounts SET name='QUALIFICATION Edited Staff',phone='+250780000007',capabilities=ARRAY['records.read','payments.allocate'],
 version=version+1,credential_version=credential_version+1,updated_at=2 WHERE id='fe700000-0000-4000-8000-000000000006';
SELECT pg_temp.pin_check(NOT pg_temp.pin_exists('9','fe900000-0000-4000-8000-000000000013','7'),'staff phone/capability edit invalidates prior opaque session');
-- Current parent/principal, approval, credential, account, scope and grant state
-- are rechecked on every request. Savepoint mutations deliberately roll back.
SAVEPOINT parent_disabled;
SELECT pg_temp.pin_clear();
UPDATE private.burimunsi_accounts SET active=false WHERE id='f7000000-0000-4000-8000-000000000001';
SELECT pg_temp.pin_check(NOT pg_temp.pin_exists('c','fe900000-0000-4000-8000-000000000010','a'),'disabled native parent denied');
SELECT pg_temp.pin_check(pg_temp.pin_login('+250780000007',gen_random_uuid(),'6')->'account'='null'::jsonb,'disabled delegator denies new staff login');
ROLLBACK TO parent_disabled;
SAVEPOINT stale_account;
UPDATE private.burimunsi_accounts SET version=version+1 WHERE id='f7000000-0000-4000-8000-000000000001';
SELECT pg_temp.pin_check(NOT pg_temp.pin_exists('c','fe900000-0000-4000-8000-000000000010','a'),'stale account version denied');
SELECT pg_temp.pin_expect($q$SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000011','8','e',1,1)$q$,'42501');
ROLLBACK TO stale_account;
SAVEPOINT stale_credential;
SELECT pg_temp.pin_clear();
UPDATE private.burimunsi_accounts SET credential_version=credential_version+1,version=version+1 WHERE id='f7000000-0000-4000-8000-000000000001';
SELECT pg_temp.pin_check(NOT pg_temp.pin_exists('c','fe900000-0000-4000-8000-000000000010','a'),'stale credential version denied');
ROLLBACK TO stale_credential;
SAVEPOINT stale_scope;
UPDATE private.burimunsi_scopes SET version=version+1 WHERE collection_id='buri-qualification-group';
SELECT pg_temp.pin_check(NOT pg_temp.pin_exists('c','fe900000-0000-4000-8000-000000000010','a'),'stale scope version denied');
ROLLBACK TO stale_scope;
SAVEPOINT revoked_grant;
UPDATE private.burimunsi_device_grants SET active=false,version=version+1 WHERE installation_id='fe900000-0000-4000-8000-000000000010';
SELECT pg_temp.pin_check(NOT pg_temp.pin_exists('c','fe900000-0000-4000-8000-000000000010','a'),'revoked installation denied');
SELECT pg_temp.pin_expect($q$SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000010','8','a')$q$,'42501');
ROLLBACK TO revoked_grant;
SAVEPOINT stale_approval;
RESET ROLE;
UPDATE private.burimunsi_operator_approvals SET version=version+1,updated_at=updated_at+1 WHERE principal_user_id='f3000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.pin_check(NOT pg_temp.pin_exists('c','fe900000-0000-4000-8000-000000000010','a'),'stale approval snapshot denied');
ROLLBACK TO stale_approval;
SAVEPOINT disabled_principal;
RESET ROLE;
UPDATE app.users SET access_status='suspended',revision=revision+1 WHERE id='f3000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.pin_check(NOT pg_temp.pin_exists('c','fe900000-0000-4000-8000-000000000010','a'),'disabled current principal denied');
ROLLBACK TO disabled_principal;
SAVEPOINT custody_conflict;
UPDATE private.burimunsi_device_grants SET custodian_account_id='f7000000-0000-4000-8000-000000000002'
 WHERE installation_id='fe900000-0000-4000-8000-000000000010';
SELECT pg_temp.pin_expect($q$SELECT private.burimunsi_pin_claim_custody('buri-qualification-group',(SELECT grant_id FROM private.burimunsi_pin_context()),'f7000000-0000-4000-8000-000000000001')$q$,'42501');
ROLLBACK TO custody_conflict;
-- An ambiguous approved phone is never resolved by arbitrary caller group.
-- Different approved phone/scope can reuse the SAME ordinary installation key.
SAVEPOINT second_scope;
SELECT pg_temp.pin_clear();
RESET ROLE;
SELECT set_config('burimunsi.collection_id','pin-qualification-other-group',true);
INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)
 VALUES('pin-qualification-other-group','pin-qualification-other-group','f3000000-0000-4000-8000-000000000001','QUALIFICATION OTHER','community',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at)
 VALUES('pin-qualification-other-group','buri-qualification-wallet',false,1);
INSERT INTO private.burimunsi_operator_approvals(collection_id,principal_user_id,admin_user_id,phone,role,capabilities,active,version,approved_by,created_at,updated_at)
 VALUES('pin-qualification-other-group','f3000000-0000-4000-8000-000000000001','f4000000-0000-4000-8000-000000000001','+250780000001','admin',
 ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],true,1,'f3000000-0000-4000-8000-000000000001',1,1);
INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
 VALUES('fe700000-0000-4000-8000-000000000020','pin-qualification-other-group','f3000000-0000-4000-8000-000000000001','+250780000001','QUALIFICATION Other Admin','admin',
 ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],'{"qualification_only":true}',1,1);
SET LOCAL ROLE collect_runtime;
SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT pg_temp.pin_check(pg_temp.pin_login('+250780000001',gen_random_uuid(),'6')->'account'='null'::jsonb,'ambiguous phone denied despite caller scope');
SELECT pg_temp.pin_expect($q$SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000011','8','e')$q$,'42501');
RESET ROLE;
SELECT set_config('burimunsi.collection_id','pin-qualification-other-group',true);
UPDATE private.burimunsi_operator_approvals SET phone='+250780000003',version=version+1,updated_at=updated_at+1 WHERE collection_id='pin-qualification-other-group';
UPDATE private.burimunsi_accounts SET phone='+250780000003',version=version+1,credential_version=credential_version+1,updated_at=2 WHERE collection_id='pin-qualification-other-group';
SET LOCAL ROLE collect_runtime;
SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT pg_temp.pin_check(pg_temp.pin_login('+250780000003',gen_random_uuid(),'6')->'account'->>'groupId'='pin-qualification-other-group','new operator selects approved scope independently');
SELECT pg_temp.pin_create('fe700000-0000-4000-8000-000000000020','fe900000-0000-4000-8000-000000000010','8','a',2,2,'pin-qualification-other-group');
SELECT pg_temp.pin_check((SELECT collection_id='pin-qualification-other-group' FROM private.burimunsi_pin_session_context(repeat('8',64),'fe900000-0000-4000-8000-000000000010',repeat('a',64),'internal_receiver')),'same installation different approved scope');
SELECT pg_temp.pin_check(pg_temp.pin_exists('c','fe900000-0000-4000-8000-000000000010','a'),'different scope sign-in preserves earlier independent grant');
SELECT pg_temp.pin_expect($q$SELECT pg_temp.pin_create('fe700000-0000-4000-8000-000000000020','fe900000-0000-4000-8000-000000000012','9','a',2,2,'pin-qualification-other-group')$q$,'42501');
ROLLBACK TO second_scope;
-- The real canonical receiving binding/credential/SIM authorizes SMS disclosure,
-- while an ordinary admin installation with no such credential stays denied.
SELECT pg_temp.pin_clear();
RESET ROLE;
INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,version,subscription_evidence,created_at)
 VALUES('pin-qualification-binding','f3000000-0000-4000-8000-000000000001','buri-qualification-wallet',1,'{"subscription_id":0}',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,claimed_installation_id,created_at)
 VALUES('pin-qualification-pairing','pin-qualification-binding',repeat('5',64),'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,
 'fe900000-0000-4000-8000-000000000010',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at)
 VALUES('pin-qualification-credential','pin-qualification-binding','pin-qualification-pairing','fe900000-0000-4000-8000-000000000010',repeat('6',64),'{}',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
UPDATE private.burimunsi_scopes SET enabled=true,active_binding_id='pin-qualification-binding',version=version+1 WHERE collection_id='buri-qualification-group';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000010','1','a');
SELECT pg_temp.pin_set('1','fe900000-0000-4000-8000-000000000010','a');
INSERT INTO app.mutation_guards(id,user_id,session_id,now_seconds,collection_id,permission,fresh_seconds)
 VALUES('pin-valid-sms',api.current_principal_id(),api.current_session_id(),app.unixepoch(),'buri-qualification-group','sms.reveal',300);
INSERT INTO app.mutation_guards(id,user_id,session_id,now_seconds,collection_id,permission,fresh_seconds)
 VALUES('pin-valid-finance',api.current_principal_id(),api.current_session_id(),app.unixepoch(),'buri-qualification-group','payments.reconcile',300);
SELECT pg_temp.pin_create('f7000000-0000-4000-8000-000000000001','fe900000-0000-4000-8000-000000000011','2','e');
SELECT pg_temp.pin_set('2','fe900000-0000-4000-8000-000000000011','e');
SELECT pg_temp.pin_expect($q$SELECT private.assert_actor('sms.reveal','buri-qualification-group',NULL,1,300)$q$,'42501');
SELECT pg_temp.pin_set('1','fe900000-0000-4000-8000-000000000010','a');
SAVEPOINT disabled_receiving;
UPDATE private.burimunsi_scopes SET enabled=false WHERE collection_id='buri-qualification-group';
SELECT pg_temp.pin_check(pg_temp.pin_exists('1','fe900000-0000-4000-8000-000000000010','a'),'receiving pause does not fabricate an interactive credential revocation');
SELECT pg_temp.pin_expect($q$SELECT private.assert_actor('sms.reveal','buri-qualification-group',NULL,1,300)$q$,'42501');
SELECT pg_temp.pin_expect($q$SELECT private.assert_actor('payments.reconcile','buri-qualification-group',NULL,1,300)$q$,'42501');
ROLLBACK TO disabled_receiving;
-- Old/expired genuine native-shaped fixture sessions prove freshness derives
-- from PIN authentication time, never JWT/MFA/email timestamps or NEW.now_seconds.
SELECT pg_temp.pin_clear();
RESET ROLE;
INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,credential_version,grant_version,token_hash,created_at,expires_at,principal_user_id,auth_method)
 SELECT 'fe000000-0000-4000-8000-000000000031',collection_id,account_id,grant_id,installation_id,credential_version,grant_version,
 encode(sha256(convert_to(repeat('3',64),'UTF8')),'hex'),floor(extract(epoch FROM clock_timestamp())*1000)::bigint-301000,
 floor(extract(epoch FROM clock_timestamp())*1000)::bigint+600000,principal_user_id,'phone_pin'
 FROM private.burimunsi_sessions WHERE token_hash=encode(sha256(convert_to(repeat('1',64),'UTF8')),'hex');
INSERT INTO private.burimunsi_pin_session_links(native_session_id,collection_id,account_id,principal_user_id,account_version,scope_version,authority_snapshot,created_at)
 SELECT s.id,l.collection_id,l.account_id,l.principal_user_id,l.account_version,l.scope_version,l.authority_snapshot,s.created_at
 FROM private.burimunsi_pin_session_links l JOIN private.burimunsi_sessions s ON s.id='fe000000-0000-4000-8000-000000000031'
 WHERE l.native_session_id=(SELECT id FROM private.burimunsi_sessions WHERE token_hash=encode(sha256(convert_to(repeat('1',64),'UTF8')),'hex'));
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.pin_set('3','fe900000-0000-4000-8000-000000000010','a');
SELECT pg_temp.pin_expect($q$SELECT private.assert_actor('users.manage','buri-qualification-group',NULL,1,300)$q$,'42501');
SELECT pg_temp.pin_set('1','fe900000-0000-4000-8000-000000000010','a');
-- Logout revokes the interactive token only, preserving canonical custody and
-- the durable gateway credential needed for independently authorized capture.
UPDATE private.burimunsi_sessions SET revoked=true WHERE id=api.current_session_id()::uuid;
SELECT pg_temp.pin_check(NOT pg_temp.pin_exists('1','fe900000-0000-4000-8000-000000000010','a'),'opaque logout revocation');
SELECT pg_temp.pin_clear();
RESET ROLE;
SELECT pg_temp.pin_check((SELECT revoked_at IS NULL FROM app.momo_gateway_credentials WHERE id='pin-qualification-credential')
 AND (SELECT d.active AND d.custodian_account_id='f7000000-0000-4000-8000-000000000001'::uuid FROM private.burimunsi_device_grants d WHERE d.installation_id='fe900000-0000-4000-8000-000000000010'),'logout preserves separate capture authority');
SELECT pg_temp.pin_check((SELECT count(*) FROM auth.users)=2 AND (SELECT count(*) FROM app.auth_sessions)=2
 AND (SELECT count(*) FROM private.bff_sessions)=2 AND (SELECT count(*) FROM app.admin_users)=2
 AND (SELECT count(*) FROM app.ledger_entries)=0,'no fake web Auth or financial ledger writes');
-- Existing web Admin still requires genuine managed/BFF/email proof.
SET LOCAL ROLE collect_runtime;
SELECT set_config('request.jwt.claims','{"sub":"f1000000-0000-4000-8000-000000000001","session_id":"f2000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal2"}',true);
SELECT pg_temp.pin_expect($q$SELECT private.assert_actor('payments.reconcile',NULL,NULL,2,300)$q$,'42501');
ROLLBACK;
