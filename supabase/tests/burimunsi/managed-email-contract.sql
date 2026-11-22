-- QUALIFICATION ONLY after operator-seed and rolled-back Buri contracts.
-- The caller supplies a separately held genuine runtime lease. These two
-- installation grants are declared SQL fixtures, not phone/MDM provisioning.
-- All calls with a positive outcome use collect_runtime and EMPTY JWT claims.
-- No OTP, PIN, raw device token, provider send or new Auth/session is created.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true),
 set_config('request.jwt.claims','{}',true);
CREATE FUNCTION pg_temp.email_require(p_condition boolean,p_label text) RETURNS void
 LANGUAGE plpgsql SECURITY INVOKER AS $fn$
BEGIN IF p_condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'Native email qualification failed: %',p_label;END IF;END;$fn$;
CREATE FUNCTION pg_temp.email_reserve(p_n integer,p_hash text DEFAULT repeat('d',64),p_email text DEFAULT 'buri-staff@example.invalid',
 p_profile text DEFAULT 'staff',p_install uuid DEFAULT 'fd100000-0000-4000-8000-000000000001') RETURNS jsonb
 LANGUAGE sql SECURITY INVOKER AS $fn$
 SELECT private.burimunsi_managed_email_reserve('fd300000-0000-4000-8000-'||lpad(p_n::text,12,'0'),
 p_install,p_hash,p_email,p_profile,repeat('f',64))
$fn$;
CREATE FUNCTION pg_temp.email_assert(p_n integer,p_auth uuid DEFAULT NULL,p_consume boolean DEFAULT false) RETURNS boolean
 LANGUAGE sql SECURITY INVOKER AS $fn$
 SELECT private.burimunsi_managed_email_assert('fd300000-0000-4000-8000-'||lpad(p_n::text,12,'0'),p_auth,p_consume)
$fn$;
CREATE FUNCTION pg_temp.email_denied(p_statement text) RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
BEGIN
 BEGIN EXECUTE p_statement;EXCEPTION WHEN insufficient_privilege THEN RETURN;END;
 RAISE EXCEPTION 'Expected native email permission denial';
END;$fn$;
DO $catalog$
DECLARE t text;r text;f text;
BEGIN
 PERFORM private._collect_fence_require_operator();
 PERFORM pg_temp.email_require((SELECT count(*)=2 FROM auth.users),'clean synthetic seed identities');
 PERFORM pg_temp.email_require(NOT EXISTS(SELECT 1 FROM private.burimunsi_device_grants),'clean device grants');
 FOREACH t IN ARRAY ARRAY['burimunsi_email_preauth','burimunsi_email_preauth_limits'] LOOP
  PERFORM pg_temp.email_require(EXISTS(SELECT 1 FROM pg_class WHERE oid=('private.'||t)::regclass
   AND relrowsecurity AND relforcerowsecurity AND pg_get_userbyid(relowner)='postgres'),'owner/forced RLS');
  PERFORM pg_temp.email_require(EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=('private.'||t)::regclass
   AND tgname='collect_fence_statement_v1' AND tgenabled='A'),'always statement fence');
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_runtime','collect_importer'] LOOP
   PERFORM pg_temp.email_require(NOT has_table_privilege(r,'private.'||t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'),'no direct table authority');
  END LOOP;
 END LOOP;
 PERFORM pg_temp.email_require(NOT has_column_privilege('collect_runtime','private.supabase_otp_challenges','native_preauth','INSERT'),
  'native marker cannot be inserted by ordinary OTP path');
 FOREACH f IN ARRAY ARRAY['private.burimunsi_managed_email_reserve(text,uuid,text,text,text,text)',
  'private.burimunsi_managed_email_assert(text,uuid,boolean)'] LOOP
  PERFORM pg_temp.email_require(has_function_privilege('collect_runtime',f,'EXECUTE') AND EXISTS(
   SELECT 1 FROM pg_proc WHERE oid=f::regprocedure AND prosecdef AND pg_get_userbyid(proowner)='postgres'
    AND EXISTS(SELECT 1 FROM unnest(proconfig) config WHERE replace(config,' ','')='search_path=pg_catalog,pg_temp')),'narrow helper owner/search path');
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
   PERFORM pg_temp.email_require(NOT has_function_privilege(r,f,'EXECUTE'),'no public/helper authority');
  END LOOP;
 END LOOP;
 PERFORM pg_temp.email_require(NOT has_function_privilege('collect_runtime',
  'private.burimunsi_managed_email_candidate(uuid,text,text,text)','EXECUTE'),'internal candidate not a public identity directory');
END;$catalog$;
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
 VALUES('fd200000-0000-4000-8000-000000000001','buri-qualification-group','fd100000-0000-4000-8000-000000000001',repeat('d',64),'staff',NULL,1),
 ('fd200000-0000-4000-8000-000000000002','buri-qualification-group','fd100000-0000-4000-8000-000000000002',repeat('e',64),'internal_receiver','f7000000-0000-4000-8000-000000000001',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id) VALUES
 ('fd200000-0000-4000-8000-000000000001','f7000000-0000-4000-8000-000000000002','buri-qualification-group'),
 ('fd200000-0000-4000-8000-000000000002','f7000000-0000-4000-8000-000000000001','buri-qualification-group');
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.email_denied('SELECT * FROM private.burimunsi_email_preauth');
SELECT pg_temp.email_denied('SELECT * FROM private.burimunsi_email_preauth_limits');
SELECT pg_temp.email_denied($sql$SELECT private.burimunsi_managed_email_candidate(
 'fd100000-0000-4000-8000-000000000001',repeat('d',64),'buri-staff@example.invalid','staff')$sql$);

SAVEPOINT positive;
DO $positive$
DECLARE r jsonb;
BEGIN
 -- Wrong ambient group is not an unauthenticated authority selector. Discovery
 -- uses the exact current token and restores the caller's previous GUC.
 PERFORM set_config('burimunsi.collection_id','not-a-real-scope',true);
 r:=pg_temp.email_reserve(1);
 PERFORM pg_temp.email_require(r->>'allowed'='true' AND r->>'collectionId'='buri-qualification-group','exact discovery without managed actor');
 PERFORM pg_temp.email_require(current_setting('burimunsi.collection_id')='not-a-real-scope','discovery context restoration');
 PERFORM pg_temp.email_require(pg_temp.email_assert(1),'pre-dispatch current snapshot');
 PERFORM pg_temp.email_require(NOT pg_temp.email_assert(1,'f1000000-0000-4000-8000-000000000001',true),'wrong real Auth subject');
 UPDATE private.supabase_otp_challenges SET delivery_status='accepted',attempts=1 WHERE id='fd300000-0000-4000-8000-000000000001';
 PERFORM pg_temp.email_require(pg_temp.email_assert(1,'f1000000-0000-4000-8000-000000000002',true),'exact existing identity consumes');
 PERFORM pg_temp.email_require(NOT pg_temp.email_assert(1,'f1000000-0000-4000-8000-000000000002',true),'one-shot replay denial');
 PERFORM pg_temp.email_require((pg_temp.email_reserve(2)->>'code')='auth_rate_limited','shared real 60-second cooldown retained');
END;$positive$;
ROLLBACK TO positive;

SAVEPOINT denied;
DO $denied$
BEGIN
 PERFORM pg_temp.email_require(pg_temp.email_reserve(3,repeat('a',64))->>'allowed'='false','wrong token');
 PERFORM pg_temp.email_require(pg_temp.email_reserve(4,repeat('d',64),'info@ikanisa.com')->>'allowed'='false','different approved account email');
 PERFORM pg_temp.email_require(pg_temp.email_reserve(5,repeat('d',64),'buri-staff@example.invalid','internal_receiver')->>'allowed'='false','wrong installation profile');
 PERFORM pg_temp.email_require(pg_temp.email_reserve(6,repeat('d',64),'buri-staff@example.invalid','staff',
  'fd100000-0000-4000-8000-000000000099')->>'allowed'='false','unregistered installation');
 PERFORM pg_temp.email_require(NOT EXISTS(SELECT 1 FROM private.supabase_otp_challenges WHERE native_preauth),'denied requests cannot reserve provider challenges');
END;$denied$;
ROLLBACK TO denied;

SAVEPOINT current_grant;
SELECT pg_temp.email_require(pg_temp.email_reserve(7)->>'allowed'='true','before token rotation');
UPDATE private.burimunsi_device_grants SET token_hash=repeat('a',64),version=version+1
 WHERE id='fd200000-0000-4000-8000-000000000001';
SELECT pg_temp.email_require(NOT pg_temp.email_assert(7),'rotation invalidates original preauth');
ROLLBACK TO current_grant;
SAVEPOINT revoked_grant;
UPDATE private.burimunsi_device_grants SET active=false,version=version+1 WHERE id='fd200000-0000-4000-8000-000000000001';
SELECT pg_temp.email_require(pg_temp.email_reserve(8)->>'allowed'='false','revoked grant');
ROLLBACK TO revoked_grant;
SAVEPOINT disabled_account;
SELECT pg_temp.email_require(pg_temp.email_reserve(9)->>'allowed'='true','before account disable');
UPDATE private.burimunsi_accounts SET active=false,version=version+1 WHERE id='f7000000-0000-4000-8000-000000000002';
SELECT pg_temp.email_require(NOT pg_temp.email_assert(9),'disabled native account');
ROLLBACK TO disabled_account;
SAVEPOINT disabled_scope;
SELECT pg_temp.email_require(pg_temp.email_reserve(10)->>'allowed'='true','before scope disable');
UPDATE private.burimunsi_scopes SET enabled=false,version=version+1 WHERE collection_id='buri-qualification-group';
SELECT pg_temp.email_require(NOT pg_temp.email_assert(10),'disabled scope');
ROLLBACK TO disabled_scope;
SAVEPOINT approval_revoked;
SELECT pg_temp.email_require(pg_temp.email_reserve(14)->>'allowed'='true','before approval revoke');
RESET ROLE;
UPDATE private.burimunsi_operator_approvals SET active=false,version=version+1
 WHERE collection_id='buri-qualification-group' AND principal_user_id='f3000000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.email_require(NOT pg_temp.email_assert(14),'owner approval revoke');
ROLLBACK TO approval_revoked;

SAVEPOINT auth_unconfirmed;
RESET ROLE;
UPDATE auth.users SET email_confirmed_at=NULL WHERE id='f1000000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.email_require(pg_temp.email_reserve(11)->>'allowed'='false','existing unconfirmed Auth user cannot use exemption');
ROLLBACK TO auth_unconfirmed;
SAVEPOINT auth_banned;
RESET ROLE;
UPDATE auth.users SET banned_until=now()+interval '1 hour' WHERE id='f1000000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.email_require(pg_temp.email_reserve(12)->>'allowed'='false','banned managed identity');
ROLLBACK TO auth_banned;
SAVEPOINT owner_receiver;
-- A separate declared non-owner Admin/custodian avoids the original owner's
-- genuine 60-second OTP cooldown without changing its schema-fixed email.
-- Obtain its native approval through the existing real owner/session proof.
-- Every added synthetic identity, approval and device grant rolls back below.
RESET ROLE;
INSERT INTO auth.users(id,email,email_confirmed_at,is_anonymous) VALUES
 ('fd400000-0000-4000-8000-000000000003','preauth-receiver@example.invalid',now(),false);
INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at) VALUES
 ('fd500000-0000-4000-8000-000000000003','preauth-receiver@example.invalid','000003','QUALIFICATION Receiver','operator',
 app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES
 ('fd400000-0000-4000-8000-000000000003','fd500000-0000-4000-8000-000000000003','synthetic-native-email-qualification');
INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at) VALUES
 ('fd600000-0000-4000-8000-000000000003','preauth-receiver@example.invalid','admin','active','supabase-managed',
 'QUALIFICATION Receiver',app.unixepoch(),app.unixepoch());
INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES
 ('fd600000-0000-4000-8000-000000000003','fd500000-0000-4000-8000-000000000003','synthetic-qualification',
 app.strftime('%Y-%m-%dT%H:%M:%fZ'));
-- The existing scope retains its unique native admin. The receiver fixture
-- uses a separate declared collection/account/scope, all inside this savepoint.
INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES
 ('buri-email-receiver-group','buri-email-receiver-group','f3000000-0000-4000-8000-000000000001',
 'QUALIFICATION EMAIL RECEIVER','community',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,timezone,created_at) VALUES
 ('buri-email-receiver-wallet','mtn_momo','00003','QUALIFICATION EMAIL RECEIVER',repeat('b',64),'Africa/Kigali',
 app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at) VALUES
 ('buri-email-receiver-group','buri-email-receiver-wallet',true,floor(extract(epoch FROM clock_timestamp())*1000)::bigint);
SELECT set_config('burimunsi.collection_id','buri-email-receiver-group',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600,
 'amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',auth_at)))::text,true)
 FROM app.auth_sessions WHERE id='f2000000-0000-4000-8000-000000000001';
SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-email-receiver-group',
 'fd800000-0000-4000-8000-000000000003','fd600000-0000-4000-8000-000000000003','+250780000003','admin',
 ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],true,0);
INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at) VALUES
 ('fd700000-0000-4000-8000-000000000003','buri-email-receiver-group','fd500000-0000-4000-8000-000000000003',
 '+250780000003','QUALIFICATION Receiver','admin',
 ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],'{"qualification_only":true}',1,1);
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at) VALUES
 ('fd200000-0000-4000-8000-000000000003','buri-email-receiver-group','fd100000-0000-4000-8000-000000000003',
 repeat('c',64),'internal_receiver','fd700000-0000-4000-8000-000000000003',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id) VALUES
 ('fd200000-0000-4000-8000-000000000003','fd700000-0000-4000-8000-000000000003','buri-email-receiver-group');
SELECT set_config('request.jwt.claims','{}',true);
SET LOCAL ROLE collect_runtime;
DO $receiver$
DECLARE r jsonb;
BEGIN
 r:=pg_temp.email_reserve(13,repeat('c',64),'preauth-receiver@example.invalid','internal_receiver','fd100000-0000-4000-8000-000000000003');
 PERFORM pg_temp.email_require(r->>'allowed'='true' AND r->>'collectionId'='buri-email-receiver-group' AND pg_temp.email_assert(13),'receiver exact active approved custodian');
END;$receiver$;
ROLLBACK TO owner_receiver;
RESET ROLE;
SELECT pg_temp.email_require((SELECT count(*)=2 FROM auth.users)
 AND (SELECT email='info@ikanisa.com' FROM app.admin_users WHERE id='f4000000-0000-4000-8000-000000000001')
 AND NOT EXISTS(SELECT 1 FROM private.burimunsi_device_grants WHERE id='fd200000-0000-4000-8000-000000000003')
 AND NOT EXISTS(SELECT 1 FROM private.burimunsi_scopes WHERE collection_id='buri-email-receiver-group')
 AND (SELECT count(*)=1 FROM private.burimunsi_accounts WHERE collection_id='buri-qualification-group' AND role='admin' AND NOT removed),
 'receiver fixture rolls back and preserves original owner');
SET LOCAL ROLE collect_runtime;

SAVEPOINT email_budget;
DO $email_budget$
DECLARE i integer;r jsonb;
BEGIN
 FOR i IN 1..6 LOOP r:=pg_temp.email_reserve(20+i);END LOOP;
 PERFORM pg_temp.email_require(r->>'code'='auth_rate_limited','approved device attempts consume durable email budget');
END;$email_budget$;
ROLLBACK TO email_budget;
SAVEPOINT network_budget;
DO $network_budget$
DECLARE i integer;r jsonb;
BEGIN
 FOR i IN 1..51 LOOP
  r:=pg_temp.email_reserve(100+i,repeat('a',64),'wrong-'||i||'@example.invalid','staff',
   ('fd100000-0000-4000-8000-'||lpad(i::text,12,'0'))::uuid);
 END LOOP;
 PERFORM pg_temp.email_require(r->>'code'='auth_rate_limited','network budget spans different devices/emails');
END;$network_budget$;
ROLLBACK TO network_budget;
SAVEPOINT missing_binding;
RESET ROLE;
INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,
 created_at,expires_at,delivery_status,native_preauth) VALUES('fd300000-0000-4000-8000-000000000999',
 encode(sha256(convert_to('email:missing-binding@example.invalid','UTF8')),'hex'),'email','missing-binding@example.invalid',
 'admin',0,app.unixepoch(),app.unixepoch()+300,'accepted',true);
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.email_require(NOT pg_temp.email_assert(999),'native marker without exact protected binding never falls back');
ROLLBACK TO missing_binding;
RESET ROLE;
DO $effects$
BEGIN
 PERFORM pg_temp.email_require((SELECT count(*)=2 FROM auth.users),'no Auth creation');
 PERFORM pg_temp.email_require((SELECT count(*)=2 FROM auth.sessions),'no managed session creation');
 PERFORM pg_temp.email_require(NOT EXISTS(SELECT 1 FROM private.burimunsi_sessions),'no native session creation');
 PERFORM pg_temp.email_require(NOT EXISTS(SELECT 1 FROM app.ledger_entries),'no financial posting');
END;$effects$;
ROLLBACK;
