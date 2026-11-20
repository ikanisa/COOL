-- QUALIFICATION ONLY; run after operator-seed.sql in its isolated retained DB.
-- The qualifier must replace the compiler export and hold a genuine separately
-- registered WORK lease exactly as for member-command-contract.sql. This file
-- never registers/fakes a lease and rolls back all fixtures and privilege tests.
-- Storage records below are synthetic SQL control-plane evidence, NOT valid
-- encryption/provider bytes. No storage retrieval, plaintext disclosure, GoTrue,
-- SMTP, gateway activation, financial posting or production acceptance is tested.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
SELECT private.set_admin_email_context('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001');
__SOURCE_FUNCTIONS__
CREATE FUNCTION pg_temp.source_expect_state(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=expected THEN RETURN;END IF;
  RAISE EXCEPTION 'Source qualification SQLSTATE %, expected %: %',SQLSTATE,expected,SQLERRM;
 END;
 RAISE EXCEPTION 'Expected source qualification SQLSTATE %',expected;
END;$fn$;
DO $preflight$
DECLARE t text;r text;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.burimunsi_accounts WHERE id='f7000000-0000-4000-8000-000000000001')
  OR EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes) OR EXISTS(SELECT 1 FROM app.sms_receipts)
  OR EXISTS(SELECT 1 FROM private.burimunsi_sessions) THEN
  RAISE EXCEPTION 'Clean operator-seed source qualification required';
 END IF;
 FOREACH t IN ARRAY ARRAY['collect_fence_statement_v1','burimunsi_source_scope_immutable'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='private.burimunsi_sms_source_scopes'::regclass
   AND tgname=t AND tgenabled='A') THEN RAISE EXCEPTION 'Missing source ALWAYS guard %',t;END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='app.momo_gateway_captures'::regclass
  AND tgname='burimunsi_scope_new_capture' AND tgenabled='A') THEN RAISE EXCEPTION 'Missing capture ALWAYS association';END IF;
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
  IF has_table_privilege(r,'private.burimunsi_sms_source_scopes','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
   RAISE EXCEPTION 'Source table privilege leak %',r;END IF;
 END LOOP;
 IF NOT has_table_privilege('collect_runtime','private.burimunsi_sms_source_scopes','SELECT')
  OR has_table_privilege('collect_runtime','private.burimunsi_sms_source_scopes','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
  OR has_function_privilege('collect_runtime','private.burimunsi_scope_new_capture()','EXECUTE') THEN
  RAISE EXCEPTION 'Source runtime privilege boundary';
 END IF;
END;$preflight$;
INSERT INTO app.admin_grants(user_id,permission,granted_by,granted_at)
 VALUES('f3000000-0000-4000-8000-000000000001','sms.read','qualification-only',app.strftime('%Y-%m-%dT%H:%M:%fZ'))
 ON CONFLICT(user_id,permission) DO NOTHING;
INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)
 VALUES('buri-qualification-group-2','buri-qualification-group-2','f3000000-0000-4000-8000-000000000001',
  'QUALIFICATION SECOND GROUP','community',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT set_config('burimunsi.collection_id','buri-qualification-group-2',true);
INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at)
 VALUES('buri-qualification-group-2','buri-qualification-wallet',true,1);
SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group-2',
 'fb600000-0000-4000-8000-000000000001','f4000000-0000-4000-8000-000000000001','+250780000001','admin',
 ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],true,0);
INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
 VALUES('fb700000-0000-4000-8000-000000000001','buri-qualification-group-2','f3000000-0000-4000-8000-000000000001',
 '+250780000001','QUALIFICATION SECOND CUSTODIAN','admin',
 ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],'{"qualification_only":true}',1,1);
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
 VALUES('fb900000-0000-4000-8000-000000000001','buri-qualification-group-2','fb900000-0000-4000-8000-000000000002',
 repeat('b',64),'internal_receiver','fb700000-0000-4000-8000-000000000001',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id)
 VALUES('fb900000-0000-4000-8000-000000000001','fb700000-0000-4000-8000-000000000001','buri-qualification-group-2');
SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
 VALUES('fb900000-0000-4000-8000-000000000003','buri-qualification-group','fb900000-0000-4000-8000-000000000004',
 repeat('a',64),'internal_receiver','f7000000-0000-4000-8000-000000000001',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id)
 VALUES('fb900000-0000-4000-8000-000000000003','f7000000-0000-4000-8000-000000000001','buri-qualification-group');
-- Both groups deliberately share one exact wallet. Exact captured binding,
-- approved installation and custodian, rather than wallet aliases, select group.
INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,version,subscription_evidence,created_at) VALUES
 ('source-contract-binding-a','f3000000-0000-4000-8000-000000000001','buri-qualification-wallet',1,'{"subscription_id":7}',app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('source-contract-binding-b','f3000000-0000-4000-8000-000000000001','buri-qualification-wallet',1,'{"subscription_id":8}',app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('source-contract-binding-unapproved','f3000000-0000-4000-8000-000000000001','buri-qualification-wallet',1,NULL,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,claimed_installation_id,created_at) VALUES
 ('source-contract-pairing-a','source-contract-binding-a',repeat('1',64),'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,'fb900000-0000-4000-8000-000000000004',app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('source-contract-pairing-b','source-contract-binding-b',repeat('3',64),'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,'fb900000-0000-4000-8000-000000000002',app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('source-contract-pairing-unapproved','source-contract-binding-unapproved',repeat('5',64),'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,'fb900000-0000-4000-8000-000000000099',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at) VALUES
 ('source-contract-credential-a','source-contract-binding-a','source-contract-pairing-a','fb900000-0000-4000-8000-000000000004',repeat('2',64),'QUALIFICATION NOT A TOKEN',app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('source-contract-credential-b','source-contract-binding-b','source-contract-pairing-b','fb900000-0000-4000-8000-000000000002',repeat('4',64),'QUALIFICATION NOT A TOKEN',app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('source-contract-credential-unapproved','source-contract-binding-unapproved','source-contract-pairing-unapproved','fb900000-0000-4000-8000-000000000099',repeat('6',64),'QUALIFICATION NOT A TOKEN',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
UPDATE private.burimunsi_scopes SET active_binding_id='source-contract-binding-a',binding_version=1,version=version+1
 WHERE collection_id='buri-qualification-group';
SELECT set_config('burimunsi.collection_id','buri-qualification-group-2',true);
UPDATE private.burimunsi_scopes SET active_binding_id='source-contract-binding-b',binding_version=1,version=version+1
 WHERE collection_id='buri-qualification-group-2';
SELECT pg_temp.source_expect_state($q$UPDATE private.burimunsi_scopes SET active_binding_id='source-contract-binding-a'
 WHERE collection_id='buri-qualification-group-2'$q$,'23505');
SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);
INSERT INTO private.storage_namespace(singleton,origin,bucket) VALUES(true,'https://qualification-storage.invalid','qualification-source')
 ON CONFLICT(singleton) DO NOTHING;
CREATE FUNCTION pg_temp.source_capture(p_id text,p_credential text,p_completeness text,p_mode text,p_receiver text DEFAULT repeat('c',64))
 RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE plain text;sealed text;plain_sha text;body_sha text;cipher_sha text;scope jsonb;custom jsonb;fingerprint text;
BEGIN
 plain:=jsonb_build_object('raw_sender','QUALIFICATION SMS','raw_body','QUALIFICATION SOURCE '||p_id,
  'completeness',p_completeness,'source_mode',p_mode)::text;
 sealed:=jsonb_build_object('v',1,'kid','qualification-only','note','NOT ENCRYPTED PROVIDER BYTES','source',p_id)::text;
 plain_sha:=encode(sha256(convert_to(plain,'UTF8')),'hex');body_sha:=encode(sha256(convert_to('QUALIFICATION SOURCE '||p_id,'UTF8')),'hex');
 cipher_sha:=encode(sha256(convert_to(sealed,'UTF8')),'hex');fingerprint:=encode(sha256(convert_to('qualification:'||p_id,'UTF8')),'hex');
 scope:=jsonb_build_object('ownerId','f3000000-0000-4000-8000-000000000001','purpose','sms_receipt','entityId',p_id);
 custom:=jsonb_build_object('sha256',plain_sha,'key_id','qualification-only','source_fingerprint',fingerprint);
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
 VALUES('sms/'||p_id,fingerprint,scope,'sms:'||p_id||':'||plain_sha,'qualification-only',plain_sha,sealed);
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
 VALUES('qualification:'||p_id,'sms/'||p_id,fingerprint,cipher_sha,octet_length(sealed),scope,'{"contentType":"application/octet-stream"}',custom,'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
 VALUES('sms/'||p_id,'qualification:'||p_id,fingerprint,cipher_sha,octet_length(sealed),scope,'{"contentType":"application/octet-stream"}',custom);
 INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,
  object_key,object_sha256,size_bytes,received_at_device,created_at)
 VALUES(p_id,'f3000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000001',p_id,
  body_sha,p_receiver,'sms/'||p_id,plain_sha,octet_length(plain),'2026-11-09 09:00:00',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 INSERT INTO app.momo_gateway_captures(raw_sms_id,credential_id,identity_sha256,service_centre_at,captured_at,
  inbox_received_at,subscription_id,completeness,source_mode,created_at)
 VALUES(p_id,p_credential,fingerprint,NULL,app.strftime('%Y-%m-%dT%H:%M:%fZ'),NULL,NULL,p_completeness,p_mode,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
END;$fn$;
SELECT pg_temp.source_capture('source-contract-complete-a','source-contract-credential-a','complete','live');
SELECT pg_temp.source_capture('source-contract-incomplete-a','source-contract-credential-a','incomplete','live');
SELECT pg_temp.source_capture('source-contract-rejected-a','source-contract-credential-a','inconsistent','live');
UPDATE app.sms_receipts SET status='rejected' WHERE id='source-contract-rejected-a';
SELECT pg_temp.source_capture('source-contract-catchup-a','source-contract-credential-a','complete','catch_up');
SELECT pg_temp.source_capture('source-contract-wallet-mismatch','source-contract-credential-a','complete','live',repeat('e',64));
UPDATE private.burimunsi_scopes SET active_binding_id='source-contract-binding-unapproved',version=version+1
 WHERE collection_id='buri-qualification-group';
SELECT pg_temp.source_capture('source-contract-unapproved','source-contract-credential-unapproved','incomplete','live');
UPDATE private.burimunsi_scopes SET active_binding_id='source-contract-binding-a',version=version+1
 WHERE collection_id='buri-qualification-group';
SELECT set_config('burimunsi.collection_id','buri-qualification-group-2',true);
SELECT pg_temp.source_capture('source-contract-complete-b','source-contract-credential-b','complete','live');
SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);
-- Deliberately contradictory SQL-only parse links qualify the actual lateral
-- aggregation: one source stays one row, multiple IDs yield NULL, and a second
-- group's duplicate/transaction association cannot leak into this group.
CREATE FUNCTION pg_temp.source_relation(p_sequence integer,p_group text,p_relation text) RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE attempt text:='source-contract-attempt-'||p_sequence;transaction_id text:='source-contract-transaction-'||p_sequence;
 old_group text:=current_setting('burimunsi.collection_id',true);source_hash text;
BEGIN
 SELECT body_sha256 INTO STRICT source_hash FROM app.sms_receipts WHERE id='source-contract-complete-a';
 INSERT INTO app.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,
  profile_version,profile_json,source_body_sha256,validation_json,outcome,created_at)
 VALUES(attempt,'source-contract-complete-a',p_sequence,'qualification-only','qualification-only','qualification-only','qualification-only',
  'qualification-only','{}',source_hash,'[]',CASE WHEN p_relation='duplicate' THEN 'duplicate' ELSE 'accepted' END,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 INSERT INTO app.momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,
  currency_scale,transaction_datetime_raw,transaction_timezone,transaction_time_source,parse_attempt_id,mode,created_at,updated_at)
 VALUES(transaction_id,'buri-qualification-wallet','mtn_momo','QUALIFICATION-'||p_sequence,'incoming_receipt',1,'RWF',0,
  '2026-11-09 09:00:00','Africa/Kigali','provider_sms',attempt,'live',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 PERFORM set_config('burimunsi.collection_id',p_group,true);
 INSERT INTO private.burimunsi_transaction_scopes(transaction_id,collection_id,receiving_account_id,source_binding_id,
  source_binding_version,policy_version,created_at)
 VALUES(transaction_id,p_group,'buri-qualification-wallet',CASE WHEN p_group='buri-qualification-group' THEN 'source-contract-binding-a'
  ELSE 'source-contract-binding-b' END,1,'qualification-only',1);
 INSERT INTO app.momo_transaction_sources(transaction_id,raw_sms_id,parse_attempt_id,relation,created_at)
 VALUES(transaction_id,'source-contract-complete-a',attempt,p_relation,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
END;$fn$;
SELECT pg_temp.source_relation(1,'buri-qualification-group','duplicate');
SELECT pg_temp.source_relation(2,'buri-qualification-group','accepted');
SELECT pg_temp.source_relation(3,'buri-qualification-group-2','duplicate');
DO $captured$
BEGIN
 IF (SELECT count(*) FROM private.burimunsi_sms_source_scopes WHERE collection_id='buri-qualification-group')<>4
  OR (SELECT count(*) FROM pg_temp.buri_source_rows('buri-qualification-group'))<>4
  OR EXISTS(SELECT 1 FROM private.storage_payload_reservations WHERE sealed_body IS NOT NULL)
  OR EXISTS(SELECT 1 FROM private.burimunsi_sessions)
  OR EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes WHERE source_id IN('source-contract-unapproved','source-contract-wallet-mismatch')) THEN
  RAISE EXCEPTION 'Capture-time scope/completeness/custody/independence contract';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes WHERE source_id='source-contract-incomplete-a'
  AND provenance='gateway_capture' AND binding_id='source-contract-binding-a' AND binding_version=1
  AND credential_id='source-contract-credential-a' AND installation_id='fb900000-0000-4000-8000-000000000004'
  AND custodian_account_id='f7000000-0000-4000-8000-000000000001' AND grant_id='fb900000-0000-4000-8000-000000000003'
  AND grant_version=1 AND proof_sha256~'^[a-f0-9]{64}$') THEN RAISE EXCEPTION 'Original approval not captured';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_temp.buri_source_rows('buri-qualification-group') r WHERE r->>'id'='source-contract-complete-a'
  AND r->>'duplicate'='true' AND r->'transaction_id'='null'::jsonb AND jsonb_array_length(r->'link_identities')=2) THEN
  RAISE EXCEPTION 'Source links multiplied rows, selected an arbitrary transaction or crossed group';END IF;
END;$captured$;
-- Revocation/replacement changes future capture authority, never old ownership.
UPDATE app.momo_gateway_bindings SET status='revoked',revoked_at=app.strftime('%Y-%m-%dT%H:%M:%fZ') WHERE id='source-contract-binding-a';
UPDATE app.momo_gateway_credentials SET revoked_at=app.strftime('%Y-%m-%dT%H:%M:%fZ') WHERE id='source-contract-credential-a';
UPDATE private.burimunsi_device_grants SET active=false,version=version+1 WHERE id='fb900000-0000-4000-8000-000000000003';
INSERT INTO app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,timezone,created_at)
 VALUES('source-contract-new-wallet','mtn_momo','99999','QUALIFICATION REPLACEMENT',repeat('d',64),'Africa/Kigali',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
UPDATE private.burimunsi_scopes SET receiving_account_id='source-contract-new-wallet',active_binding_id=NULL,version=version+1
 WHERE collection_id='buri-qualification-group';
DO $frozen$
BEGIN
 IF (SELECT count(*) FROM pg_temp.buri_source_rows('buri-qualification-group'))<>4
  OR EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes WHERE collection_id='buri-qualification-group'
   AND (receiving_account_id<>'buri-qualification-wallet' OR grant_version<>1)) THEN
  RAISE EXCEPTION 'Historical source moved with current wallet/grant';END IF;
 IF EXISTS(SELECT 1 FROM pg_temp.buri_current_binding_rows('buri-qualification-group','fb900000-0000-4000-8000-000000000004')) THEN
  RAISE EXCEPTION 'Old installation inherited replacement binding';END IF;
END;$frozen$;
SELECT pg_temp.source_expect_state($q$UPDATE private.burimunsi_sms_source_scopes SET proof_id='tampered'
 WHERE source_id='source-contract-complete-a'$q$,'23514');
SELECT pg_temp.source_expect_state($q$DELETE FROM private.burimunsi_sms_source_scopes WHERE source_id='source-contract-complete-a'$q$,'23514');
SELECT set_config('burimunsi.collection_id','buri-qualification-group-2',true);
SELECT pg_temp.source_expect_state($q$INSERT INTO private.burimunsi_sms_source_scopes
 (source_id,collection_id,receiving_account_id,owner_user_id,source_body_sha256,object_sha256,provenance,proof_id,proof_sha256)
 SELECT id,'buri-qualification-group-2','buri-qualification-wallet',owner_user_id,body_sha256,object_sha256,'owner_adoption','qualification-conflict',repeat('f',64)
 FROM app.sms_receipts WHERE id='source-contract-complete-a'$q$,'23505');
DO $second$ BEGIN
 IF (SELECT count(*) FROM pg_temp.buri_source_rows('buri-qualification-group-2'))<>1
  OR EXISTS(SELECT 1 FROM pg_temp.buri_source_rows('buri-qualification-group-2') r WHERE r->>'id'<>'source-contract-complete-b') THEN
  RAISE EXCEPTION 'Shared-wallet second group inherited first-group history';END IF;
END;$second$;
-- Execute the exported query and permission SELECT as the real non-bypass role.
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
DO $runtime$ BEGIN
 IF current_user<>'collect_runtime' OR (SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname=current_user) THEN
  RAISE EXCEPTION 'Normal runtime role required';END IF;
 IF (SELECT count(*) FROM pg_temp.buri_source_rows('buri-qualification-group-2'))<>1
  OR EXISTS(SELECT 1 FROM pg_temp.buri_source_rows('buri-qualification-group')) THEN RAISE EXCEPTION 'Source RLS group escape';END IF;
 IF (SELECT count(*) FROM pg_temp.buri_metadata_authority_rows())<>1 THEN RAISE EXCEPTION 'Shared SMS metadata grant missing';END IF;
END;$runtime$;
SELECT pg_temp.source_expect_state($q$INSERT INTO private.burimunsi_sms_source_scopes(source_id) SELECT 'unauthorized' WHERE false$q$,'42501');
SELECT pg_temp.source_expect_state($q$UPDATE private.burimunsi_sms_source_scopes SET proof_id=proof_id WHERE false$q$,'42501');
SELECT pg_temp.source_expect_state($q$DELETE FROM private.burimunsi_sms_source_scopes WHERE false$q$,'42501');
SELECT pg_temp.source_expect_state($q$TRUNCATE private.burimunsi_sms_source_scopes$q$,'42501');
SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);
DO $runtime_first$ BEGIN
 IF (SELECT count(*) FROM pg_temp.buri_source_rows('buri-qualification-group'))<>4
  OR EXISTS(SELECT 1 FROM pg_temp.buri_source_rows('buri-qualification-group-2')) THEN RAISE EXCEPTION 'Source RLS inverse escape';END IF;
END;$runtime_first$;
SELECT set_config('collect.fence_admission_id','',true);
SELECT pg_temp.source_expect_state($q$INSERT INTO app.momo_gateway_captures SELECT * FROM app.momo_gateway_captures WHERE false$q$,'55000');
SELECT set_config('collect.fence_admission_id','__ADMISSION_ID__',true);
-- Shared global grant and role ceiling remain independent from native capability.
RESET ROLE;
DELETE FROM app.admin_grants WHERE user_id='f3000000-0000-4000-8000-000000000001' AND permission='sms.read';
SET LOCAL ROLE collect_runtime;
DO $no_grant$ BEGIN IF EXISTS(SELECT 1 FROM pg_temp.buri_metadata_authority_rows()) THEN
 RAISE EXCEPTION 'Removed global sms.read grant still authorizes metadata';END IF;END;$no_grant$;
RESET ROLE;
INSERT INTO app.admin_grants(user_id,permission,granted_by,granted_at)
 VALUES('f3000000-0000-4000-8000-000000000001','sms.read','qualification-only',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
-- The approved role reference is immutable. Every currently supported shared
-- role, INCLUDING staff, has sms.read; do not invent a missing role entitlement.
SELECT pg_temp.source_expect_state($q$DELETE FROM app.admin_account_role_capabilities WHERE role='owner' AND permission='sms.read'$q$,'P0001');
INSERT INTO app.admin_grants(user_id,permission,granted_by,granted_at)
 VALUES('f3000000-0000-4000-8000-000000000002','sms.read','qualification-only',app.strftime('%Y-%m-%dT%H:%M:%fZ'))
 ON CONFLICT(user_id,permission) DO NOTHING;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000002',
 'session_id','f2000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
SELECT private.set_admin_email_context('f4000000-0000-4000-8000-000000000002',repeat('b',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000002');
SET LOCAL ROLE collect_runtime;
DO $staff_ceiling$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM app.admin_account_role_capabilities WHERE role='staff' AND permission='sms.read')
  OR (SELECT count(*) FROM pg_temp.buri_metadata_authority_rows())<>1
  OR NOT EXISTS(SELECT 1 FROM pg_temp.buri_metadata_authority_rows() r
   WHERE r->>'principal_user_id'='f3000000-0000-4000-8000-000000000002'
    AND r->>'principal_session_id'='f2000000-0000-4000-8000-000000000002') THEN
  RAISE EXCEPTION 'Actual approved shared staff read entitlement changed';END IF;
END;$staff_ceiling$;
RESET ROLE;
DELETE FROM app.admin_grants WHERE user_id='f3000000-0000-4000-8000-000000000002' AND permission='sms.read';
SET LOCAL ROLE collect_runtime;
DO $staff_no_grant$ BEGIN IF EXISTS(SELECT 1 FROM pg_temp.buri_metadata_authority_rows()) THEN
 RAISE EXCEPTION 'Shared staff role ceiling bypassed a removed global grant';END IF;END;$staff_no_grant$;
RESET ROLE;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
SELECT private.set_admin_email_context('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001');
DO $no_financial$ BEGIN
 IF EXISTS(SELECT 1 FROM app.payments) OR EXISTS(SELECT 1 FROM app.ledger_entries)
  OR EXISTS(SELECT 1 FROM private.burimunsi_sessions) THEN RAISE EXCEPTION 'Source fixture acquired financial/PIN authority';END IF;
END;$no_financial$;
ROLLBACK;
