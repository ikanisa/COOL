-- QUALIFICATION ONLY. Existing retained-schema disposable DB after operator-seed.
-- The producer below is compiled from actual momo_pipeline.finishStatements.
-- Root also runs the original JS native Allocate against these fixture guards.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),
 set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true),
 set_config('burimunsi.collection_id','buri-qualification-group',true);
__ADOPTION_INPUTS__
CREATE FUNCTION pg_temp.adoption_check(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'Canonical adoption qualification: %',label;END IF;END;$fn$;
CREATE FUNCTION pg_temp.adoption_expect(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN BEGIN EXECUTE statement;EXCEPTION WHEN OTHERS THEN
 IF SQLSTATE=expected THEN RETURN;END IF;RAISE EXCEPTION 'Adoption SQLSTATE %, expected %, message %',SQLSTATE,expected,SQLERRM;
 END;RAISE EXCEPTION 'Expected adoption SQLSTATE %',expected;END;$fn$;
UPDATE app.momo_receiving_accounts SET profile_status='approved',profile_version='adoption-profile.v1',
 profile_json=current_setting('burimunsi.adoption.fixture.profile'),status='active' WHERE id='buri-qualification-wallet';
UPDATE app.collections SET receiver_network='mtn_momo',receiver_momo_number='00000',receiver_display_label='QUALIFICATION ONLY'
 WHERE id='buri-qualification-group';
INSERT INTO private.storage_namespace(singleton,origin,bucket)
 VALUES(true,'https://qualification-storage.invalid','qualification-adoption') ON CONFLICT(singleton) DO NOTHING;
SELECT pg_temp.adoption_check((SELECT origin='https://qualification-storage.invalid' AND bucket='qualification-adoption'
 FROM private.storage_namespace WHERE singleton),'exact fixture storage namespace');
INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,version,status,subscription_evidence,created_at)
 VALUES('adoption-binding','f3000000-0000-4000-8000-000000000001','buri-qualification-wallet',1,'active',
 '{"subscription_id":7}',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
UPDATE private.burimunsi_scopes SET active_binding_id='adoption-binding',binding_version=1,version=version+1
 WHERE collection_id='buri-qualification-group';
INSERT INTO app.users(id,public_id,full_name,member_type,momo_number,created_at,updated_at)
 VALUES('fc940000-0000-4000-8000-000000000003','940003','QUALIFICATION Adopted Member','direct','0789444111',
 app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.memberships(id,collection_id,user_id,role,active,revision,joined_at)
 VALUES('fc940000-0000-4000-8000-000000000005','buri-qualification-group','fc940000-0000-4000-8000-000000000003','member',1,1,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
SET LOCAL ROLE collect_runtime;
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
SELECT private.burimunsi_pin_create_session('buri-qualification-group','f7000000-0000-4000-8000-000000000001',
 'fc940000-0000-4000-8000-000000000002','internal_receiver',encode(sha256(convert_to(repeat('4',64),'UTF8')),'hex'),1,
 'fc940000-0000-4000-8000-000000000004',encode(sha256(convert_to(repeat('3',64),'UTF8')),'hex'),
 floor(extract(epoch FROM clock_timestamp())*1000)::bigint,floor(extract(epoch FROM clock_timestamp())*1000)::bigint+1800000,1);
SELECT private.burimunsi_set_pin_context(repeat('3',64),'fc940000-0000-4000-8000-000000000002',repeat('4',64),'internal_receiver');
SELECT private.burimunsi_pin_claim_custody('buri-qualification-group',(SELECT grant_id FROM private.burimunsi_pin_context()),
 'f7000000-0000-4000-8000-000000000001');
INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,claimed_installation_id,created_at)
 VALUES('adoption-pairing','adoption-binding',repeat('5',64),'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,
 'fc940000-0000-4000-8000-000000000002',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at)
 VALUES('adoption-key','adoption-binding','adoption-pairing','fc940000-0000-4000-8000-000000000002',repeat('6',64),
 'QUALIFICATION NOT A REAL GATEWAY CREDENTIAL',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
RESET ROLE;
CREATE FUNCTION pg_temp.adoption_capture(p_source text,p_bad_hash boolean DEFAULT false,p_native boolean DEFAULT true,
 p_key text DEFAULT 'adoption-key',p_body text DEFAULT NULL,p_sealed_body text DEFAULT NULL,
 p_key_id text DEFAULT 'qualification-only') RETURNS void LANGUAGE plpgsql SECURITY INVOKER AS $fn$
DECLARE payload text:=current_setting('burimunsi.adoption.fixture.payload');
 body text:=coalesce(p_body,current_setting('burimunsi.adoption.fixture.body'));route record;
 sealed text;plain_sha text;cipher_sha text;fingerprint text;scope jsonb;custom jsonb;
BEGIN
 SELECT b.*,w.receiver_hash,k.id AS credential,k.installation_id INTO STRICT route
 FROM app.momo_gateway_credentials k JOIN app.momo_gateway_bindings b ON b.id=k.binding_id
 JOIN app.momo_receiving_accounts w ON w.id=b.receiving_account_id WHERE k.id=p_key;
 payload:=(payload::jsonb||jsonb_build_object('raw_body',body,'gateway_binding_id',route.id,
  'gateway_binding_version',route.version,'subscription_id',(route.subscription_evidence::jsonb)->'subscription_id'))::text;
 -- Main fixture body retains byte-exact compiler payload for the real AES proof.
 IF p_key='adoption-key' AND p_body IS NULL THEN payload:=current_setting('burimunsi.adoption.fixture.payload');END IF;
 -- Same pre-application custody ordering as source/gateway-upload fixtures.
 -- SQL-only cases label synthetic ciphertext honestly. The Node Allocate proof
 -- passes actual AES bytes, whose external transport is an in-memory fixture.
 sealed:=coalesce(p_sealed_body,jsonb_build_object('v',1,'kid',p_key_id,'note','NOT ENCRYPTED PROVIDER BYTES','source',p_source)::text);
 plain_sha:=encode(sha256(convert_to(payload,'UTF8')),'hex');
 cipher_sha:=encode(sha256(convert_to(sealed,'UTF8')),'hex');
 fingerprint:=encode(sha256(convert_to('qualification-adoption-original:'||p_source,'UTF8')),'hex');
 scope:=jsonb_build_object('ownerId',route.owner_user_id,'purpose','sms_receipt','entityId',p_source);
 custom:=jsonb_build_object('sha256',plain_sha,'key_id',p_key_id,'source_fingerprint',fingerprint);
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
 VALUES('sms/'||p_source,fingerprint,scope,'sms:'||p_source||':'||plain_sha,p_key_id,plain_sha,sealed);
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state)
 VALUES('qualification-adoption:sms/'||p_source,'sms/'||p_source,fingerprint,cipher_sha,octet_length(sealed),scope,
 '{"contentType":"application/octet-stream"}',custom,'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata)
 VALUES('sms/'||p_source,'qualification-adoption:sms/'||p_source,fingerprint,cipher_sha,octet_length(sealed),scope,
 '{"contentType":"application/octet-stream"}',custom);
 INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at)
 VALUES(p_source,route.owner_user_id,'f2000000-0000-4000-8000-000000000001',gen_random_uuid()::text,
 CASE WHEN p_bad_hash THEN repeat('f',64) ELSE encode(sha256(convert_to(body,'UTF8')),'hex') END,route.receiver_hash,'sms/'||p_source,
 encode(sha256(convert_to(payload,'UTF8')),'hex'),octet_length(payload),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 IF p_native THEN
  INSERT INTO app.momo_gateway_captures(raw_sms_id,credential_id,identity_sha256,captured_at,completeness,source_mode,subscription_id,created_at)
  VALUES(p_source,p_key,encode(sha256(convert_to(payload,'UTF8')),'hex'),
   app.strftime('%Y-%m-%dT%H:%M:%fZ'),'complete','live',(route.subscription_evidence::jsonb->>'subscription_id')::bigint,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 END IF;
 INSERT INTO app.momo_processing_jobs(raw_sms_id,binding_id,binding_version,receiving_account_id,mode,state,attempt_count,lease_token,lease_until,available_at,created_at,updated_at)
 VALUES(p_source,route.id,route.version,route.receiving_account_id,'live','processing',1,'QUALIFICATION lease',app.unixepoch()+180,app.unixepoch(),
 app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
END;$fn$;
SET LOCAL ROLE collect_runtime;
-- __ADOPTION_CASES__ Node's actual-JS proof reuses only the setup above.
SELECT pg_temp.adoption_check(NOT has_function_privilege('collect_runtime','private.burimunsi_adopt_completed_receipt()','EXECUTE'),
 'trigger is not an arbitrary scope/RPC grant');
SELECT pg_temp.adoption_check(EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='app.momo_processing_jobs'::regclass
 AND tgname='burimunsi_adopt_completed_receipt' AND tgenabled='A'),'ALWAYS terminal-job hook');
-- The demonstrated guard remains active: application rows without committed
-- scoped custody are denied; there is no trigger disable/replica-role override.
SELECT pg_temp.adoption_expect($q$INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,
 body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at)
 VALUES('fc940000-0000-4000-8000-000000000000','f3000000-0000-4000-8000-000000000001',
 'f2000000-0000-4000-8000-000000000001','qualification-no-custody',repeat('a',64),repeat('c',64),
 'sms/fc940000-0000-4000-8000-000000000000',repeat('b',64),1,app.strftime('%Y-%m-%dT%H:%M:%fZ'))$q$,'42501');
DO $storage_acl$
DECLARE role_name text;
BEGIN
 PERFORM pg_temp.adoption_check(has_column_privilege('collect_runtime','private.storage_namespace','singleton','UPDATE')
  AND NOT has_table_privilege('collect_runtime','private.storage_namespace','UPDATE')
  AND NOT has_column_privilege('collect_runtime','private.storage_namespace','origin','UPDATE')
  AND NOT has_column_privilege('collect_runtime','private.storage_namespace','bucket','UPDATE'), 'namespace row-lock column only');
 PERFORM pg_temp.adoption_check(has_column_privilege('collect_runtime','private.storage_objects','object_key','UPDATE')
  AND NOT has_table_privilege('collect_runtime','private.storage_objects','UPDATE')
  AND NOT has_column_privilege('collect_runtime','private.storage_objects','sha256','UPDATE')
  AND NOT has_column_privilege('collect_runtime','private.storage_objects','operation_id','UPDATE'), 'object row-lock key column only');
 FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
  PERFORM pg_temp.adoption_check(NOT has_column_privilege(role_name,'private.storage_namespace','singleton','UPDATE')
   AND NOT has_column_privilege(role_name,'private.storage_objects','object_key','UPDATE'), 'nonruntime roles gain no storage column rights '||role_name);
 END LOOP;
 PERFORM pg_temp.adoption_check(NOT pg_has_role('collect_runtime','postgres','MEMBER')
  AND EXISTS(SELECT 1 FROM pg_roles WHERE rolname='collect_runtime' AND NOT rolsuper AND NOT rolbypassrls AND NOT rolcreaterole),
  'runtime cannot inherit owner or bypass role');
END;$storage_acl$;
-- Actual original namespace query, under collect_runtime and the real WORK.
SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE;
SELECT pg_temp.adoption_expect($q$UPDATE private.storage_namespace SET singleton=singleton WHERE singleton=true$q$,'42501');
SELECT pg_temp.adoption_expect($q$UPDATE private.storage_namespace SET origin=origin WHERE singleton=true$q$,'42501');
SELECT pg_temp.adoption_expect($q$UPDATE private.storage_namespace SET bucket=bucket WHERE singleton=true$q$,'42501');
SELECT pg_temp.adoption_expect($q$DELETE FROM private.storage_namespace WHERE singleton=true$q$,'42501');
SAVEPOINT unassociated;
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000008',false,false);
SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000008','QUALIFICATION lease');
SELECT pg_temp.adoption_check((SELECT count(*) FROM app.momo_transactions)=1
 AND (SELECT count(*) FROM private.burimunsi_transaction_scopes)=0,'unassociated canonical source remains a legitimate unassociated fact');
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000006');
SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000006','QUALIFICATION lease');
SELECT pg_temp.adoption_check((SELECT count(*) FROM app.momo_transactions)=1
 AND (SELECT count(*) FROM app.momo_transaction_sources WHERE relation='duplicate')=1
 AND (SELECT count(*) FROM private.burimunsi_transaction_scopes)=0,'later native duplicate never retroactively adopts an unassociated original');
ROLLBACK TO unassociated;
SAVEPOINT nonreceipt;
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000009');
UPDATE app.momo_processing_jobs SET state='completed',lease_token=NULL,lease_until=NULL
 WHERE raw_sms_id='fc940000-0000-4000-8000-000000000009';
SELECT pg_temp.adoption_check((SELECT count(*) FROM app.momo_transactions)=0
 AND (SELECT count(*) FROM private.burimunsi_transaction_scopes)=0,'terminal nonreceipt cannot invent a fact or routing scope');
ROLLBACK TO nonreceipt;
SAVEPOINT capture_before_replacement;
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000007');
RESET ROLE;
INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,version,status,subscription_evidence,created_at)
 VALUES('adoption-future-binding','f3000000-0000-4000-8000-000000000001','buri-qualification-wallet',1,'active',
 '{"subscription_id":8}',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
UPDATE private.burimunsi_scopes SET active_binding_id='adoption-future-binding',version=version+1 WHERE collection_id='buri-qualification-group';
UPDATE app.momo_gateway_bindings SET status='revoked',revoked_at=app.strftime('%Y-%m-%dT%H:%M:%fZ') WHERE id='adoption-binding';
UPDATE app.momo_gateway_credentials SET revoked_at=app.strftime('%Y-%m-%dT%H:%M:%fZ') WHERE id='adoption-key';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000007','QUALIFICATION lease');
SELECT pg_temp.adoption_check((SELECT source_binding_id FROM private.burimunsi_transaction_scopes)='adoption-binding'
 AND (SELECT active_binding_id FROM private.burimunsi_scopes WHERE collection_id='buri-qualification-group')='adoption-future-binding',
 'queued accepted receipt retains capture-time binding after replacement and retirement');
ROLLBACK TO capture_before_replacement;
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000010');
SELECT pg_temp.adoption_check((SELECT count(*) FROM private.burimunsi_sms_source_scopes
 WHERE source_id='fc940000-0000-4000-8000-000000000010')=1,'real native capture-time attribution exists');
SELECT pg_temp.adoption_check((SELECT sealed_body IS NULL AND cleared_at IS NOT NULL
 FROM private.storage_payload_reservations WHERE object_key='sms/fc940000-0000-4000-8000-000000000010'),
 'real application-commit trigger scrubbed the staged SMS reservation');
DO $object_lock$
DECLARE before_row jsonb;after_row jsonb;
BEGIN
 SELECT to_jsonb(o) INTO STRICT before_row FROM private.storage_objects o
 WHERE object_key='sms/fc940000-0000-4000-8000-000000000010' FOR UPDATE OF o;
 -- The existing object identity trigger permits an exact no-op. Report that
 -- truthfully; it does not permit a changed key or any new metadata grant.
 UPDATE private.storage_objects SET object_key=object_key
 WHERE object_key='sms/fc940000-0000-4000-8000-000000000010';
 SELECT to_jsonb(o) INTO STRICT after_row FROM private.storage_objects o
 WHERE object_key='sms/fc940000-0000-4000-8000-000000000010';
 PERFORM pg_temp.adoption_check(before_row=after_row,'real object row lock/no-op preserves every metadata value');
END;$object_lock$;
SELECT pg_temp.adoption_expect($q$UPDATE private.storage_objects SET object_key='sms/qualification-changed-key'
 WHERE object_key='sms/fc940000-0000-4000-8000-000000000010'$q$,'42501');
SELECT pg_temp.adoption_expect($q$UPDATE private.storage_objects SET sha256=sha256
 WHERE object_key='sms/fc940000-0000-4000-8000-000000000010'$q$,'42501');
SELECT pg_temp.adoption_expect($q$UPDATE private.storage_objects SET operation_id=operation_id
 WHERE object_key='sms/fc940000-0000-4000-8000-000000000010'$q$,'42501');
SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000010','QUALIFICATION lease');
SELECT pg_temp.adoption_check((SELECT count(*) FROM private.burimunsi_transaction_scopes x
 JOIN app.momo_transaction_sources s ON s.transaction_id=x.transaction_id
 WHERE s.raw_sms_id='fc940000-0000-4000-8000-000000000010' AND x.collection_id='buri-qualification-group'
 AND x.receiving_account_id='buri-qualification-wallet' AND x.source_binding_id='adoption-binding'
 AND x.source_binding_version=1 AND x.policy_version='canonical.manual.v1')=1,'original producer atomically adopts accepted fact');
CREATE TEMP TABLE adoption_first_scope AS SELECT * FROM private.burimunsi_transaction_scopes;
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000011');
SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000011','QUALIFICATION lease');
SELECT pg_temp.adoption_check((SELECT count(*) FROM app.momo_transactions)=1
 AND (SELECT count(*) FROM app.momo_transaction_sources WHERE relation='duplicate')=1
 AND (SELECT jsonb_agg(to_jsonb(x)) FROM private.burimunsi_transaction_scopes x)=
     (SELECT jsonb_agg(to_jsonb(x)) FROM adoption_first_scope x),'same-fact duplicate preserves first immutable scope verbatim');
SAVEPOINT repeated_same_source;
-- Existing Admin reparse marks completed -> pending; the actual worker then
-- owns a fresh processing lease and next attempt, without deleting history.
UPDATE app.momo_processing_jobs SET state='pending',available_at=app.unixepoch(),last_error=NULL
 WHERE raw_sms_id='fc940000-0000-4000-8000-000000000010';
UPDATE app.momo_processing_jobs SET state='processing',attempt_count=attempt_count+1,
 lease_token='QUALIFICATION repeat',lease_until=app.unixepoch()+180
 WHERE raw_sms_id='fc940000-0000-4000-8000-000000000010' AND state='pending';
SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000010','QUALIFICATION repeat',2);
SELECT pg_temp.adoption_check((SELECT count(*) FROM app.momo_transactions)=1
 AND (SELECT count(*) FROM app.momo_transaction_sources WHERE raw_sms_id='fc940000-0000-4000-8000-000000000010' AND relation='accepted')=1
 AND (SELECT count(*) FROM app.momo_transaction_sources WHERE raw_sms_id='fc940000-0000-4000-8000-000000000010' AND relation='duplicate')=1
 AND (SELECT attempt_count FROM app.momo_processing_jobs WHERE raw_sms_id='fc940000-0000-4000-8000-000000000010' AND state='completed')=2
 AND (SELECT jsonb_agg(to_jsonb(x)) FROM private.burimunsi_transaction_scopes x)=
     (SELECT jsonb_agg(to_jsonb(x)) FROM adoption_first_scope x),'same source current duplicate attempt completes while retaining original accepted fact/scope');
UPDATE app.momo_processing_jobs SET state='pending',available_at=app.unixepoch(),last_error=NULL
 WHERE raw_sms_id='fc940000-0000-4000-8000-000000000010';
UPDATE app.momo_processing_jobs SET state='processing',attempt_count=attempt_count+1,
 lease_token='QUALIFICATION nonreceipt',lease_until=app.unixepoch()+180
 WHERE raw_sms_id='fc940000-0000-4000-8000-000000000010' AND state='pending';
SELECT pg_temp.adoption_finish_nonreceipt('fc940000-0000-4000-8000-000000000010','QUALIFICATION nonreceipt',3);
SELECT pg_temp.adoption_check((SELECT count(*) FROM app.momo_parse_attempts
 WHERE raw_sms_id='fc940000-0000-4000-8000-000000000010' AND attempt_number=3 AND outcome='non_payment')=1
 AND (SELECT count(*) FROM app.momo_transaction_sources s JOIN app.momo_parse_attempts a ON a.id=s.parse_attempt_id
 WHERE s.raw_sms_id='fc940000-0000-4000-8000-000000000010' AND a.attempt_number=3)=0
 AND (SELECT attempt_count FROM app.momo_processing_jobs WHERE raw_sms_id='fc940000-0000-4000-8000-000000000010' AND state='completed')=3
 AND (SELECT count(*) FROM app.momo_transactions)=1
 AND (SELECT jsonb_agg(to_jsonb(x)) FROM private.burimunsi_transaction_scopes x)=
     (SELECT jsonb_agg(to_jsonb(x)) FROM adoption_first_scope x),'current no-fact completion never reads/deletes/reassigns an older accepted association');
ROLLBACK TO repeated_same_source;
SELECT pg_temp.adoption_check((SELECT count(*) FROM app.payments)=0 AND (SELECT count(*) FROM app.ledger_entries)=0
 AND (SELECT count(*) FROM private.burimunsi_integration_policies)=0
 AND (SELECT count(*) FROM private.burimunsi_worker_grants)=0
 AND (SELECT count(*) FROM private.burimunsi_identity_proofs)=0
 AND (SELECT count(*) FROM app.momo_transactions WHERE allocation_state='unallocated' AND payer_identifier='*****001')=1,
 'unmatched masked payer remains an unallocated orphan; routing creates no financial effect or approval');
SAVEPOINT immutable_scope;
SELECT pg_temp.adoption_expect($q$UPDATE private.burimunsi_transaction_scopes SET policy_version='invented.approval'$q$,'23514');
ROLLBACK TO immutable_scope;
SAVEPOINT canonical_core_conflict;
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000015',false,true,'adoption-key',current_setting('burimunsi.adoption.fixture.conflict_body'));
SELECT pg_temp.adoption_finish_conflict('fc940000-0000-4000-8000-000000000015','QUALIFICATION lease');
SELECT pg_temp.adoption_check((SELECT count(*) FROM app.momo_transactions WHERE has_conflict=1 AND allocation_state='needs_review')=1
 AND (SELECT state FROM app.momo_processing_jobs WHERE raw_sms_id='fc940000-0000-4000-8000-000000000015')='needs_review'
 AND (SELECT count(*) FROM app.momo_transaction_sources WHERE relation='conflict')=1
 AND (SELECT jsonb_agg(to_jsonb(x)) FROM private.burimunsi_transaction_scopes x)=
     (SELECT jsonb_agg(to_jsonb(x)) FROM adoption_first_scope x),'different immutable core facts use canonical conflict/manual-review path without scope reassignment');
ROLLBACK TO canonical_core_conflict;
SAVEPOINT wrong_wallet;
RESET ROLE;
INSERT INTO app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,timezone,profile_status,profile_version,profile_json,created_at)
 VALUES('adoption-other-wallet','mtn_momo','00001','QUALIFICATION SECOND WALLET',repeat('d',64),'Africa/Kigali','approved','adoption-profile.v1',
 current_setting('burimunsi.adoption.fixture.profile'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,version,status,subscription_evidence,created_at)
 VALUES('adoption-other-binding','f3000000-0000-4000-8000-000000000001','adoption-other-wallet',1,'active','{"subscription_id":7}',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,claimed_installation_id,created_at)
 VALUES('adoption-other-pairing','adoption-other-binding',repeat('7',64),'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,
 'fc940000-0000-4000-8000-000000000002',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at)
 VALUES('adoption-other-key','adoption-other-binding','adoption-other-pairing','fc940000-0000-4000-8000-000000000002',repeat('8',64),
 'QUALIFICATION NOT A REAL GATEWAY CREDENTIAL',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
UPDATE private.burimunsi_scopes SET receiving_account_id='adoption-other-wallet',active_binding_id='adoption-other-binding',version=version+1
 WHERE collection_id='buri-qualification-group';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000016',false,true,'adoption-other-key');
SELECT pg_temp.adoption_check((SELECT receiving_account_id FROM private.burimunsi_sms_source_scopes
 WHERE source_id='fc940000-0000-4000-8000-000000000016')='adoption-other-wallet','second wallet was independently captured');
SELECT pg_temp.adoption_expect($q$SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000016','QUALIFICATION lease')$q$,'23514');
SELECT pg_temp.adoption_finish_other_wallet('fc940000-0000-4000-8000-000000000016','QUALIFICATION lease');
SELECT pg_temp.adoption_check((SELECT count(*) FROM app.momo_transactions)=2
 AND (SELECT count(*) FROM private.burimunsi_transaction_scopes WHERE receiving_account_id='adoption-other-wallet')=1
 AND (SELECT jsonb_agg(to_jsonb(x)) FROM private.burimunsi_transaction_scopes x WHERE receiving_account_id='buri-qualification-wallet')=
     (SELECT jsonb_agg(to_jsonb(x)) FROM adoption_first_scope x),'cross-wallet reference is refused; same provider ID on its own wallet remains a distinct immutable fact');
ROLLBACK TO wrong_wallet;
SAVEPOINT cross_group_duplicate;
RESET ROLE;
SELECT set_config('burimunsi.pin_token','',true),set_config('burimunsi.pin_installation','',true),
 set_config('burimunsi.pin_device','',true),set_config('burimunsi.pin_profile','',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
SELECT private.set_admin_email_context('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001');
INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)
 VALUES('adoption-other-group','adoption-other-group','f3000000-0000-4000-8000-000000000001','QUALIFICATION SECOND GROUP','community',
 app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT set_config('burimunsi.collection_id','adoption-other-group',true);
INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at)
 VALUES('adoption-other-group','buri-qualification-wallet',true,1);
SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','adoption-other-group',
 'fc941000-0000-4000-8000-000000000001','f4000000-0000-4000-8000-000000000001','+250780000001','admin',
 ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],true,0);
INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
 VALUES('fc941000-0000-4000-8000-000000000002','adoption-other-group','f3000000-0000-4000-8000-000000000001',
 '+250780000001','QUALIFICATION SECOND CUSTODIAN','admin',
 ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],'{"qualification_only":true}',1,1);
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
 VALUES('fc941000-0000-4000-8000-000000000003','adoption-other-group','fc941000-0000-4000-8000-000000000004',
 repeat('9',64),'internal_receiver','fc941000-0000-4000-8000-000000000002',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id)
 VALUES('fc941000-0000-4000-8000-000000000003','fc941000-0000-4000-8000-000000000002','adoption-other-group');
INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,version,status,subscription_evidence,created_at)
 VALUES('adoption-cross-binding','f3000000-0000-4000-8000-000000000001','buri-qualification-wallet',1,'active','{"subscription_id":7}',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
UPDATE private.burimunsi_scopes SET active_binding_id='adoption-cross-binding',version=version+1 WHERE collection_id='adoption-other-group';
INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,claimed_installation_id,created_at)
 VALUES('adoption-cross-pairing','adoption-cross-binding',repeat('a',64),'f2000000-0000-4000-8000-000000000001',app.unixepoch()+600,
 'fc941000-0000-4000-8000-000000000004',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at)
 VALUES('adoption-cross-key','adoption-cross-binding','adoption-cross-pairing','fc941000-0000-4000-8000-000000000004',repeat('b',64),
 'QUALIFICATION NOT A REAL GATEWAY CREDENTIAL',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000017',false,true,'adoption-cross-key');
SELECT pg_temp.adoption_check((SELECT collection_id FROM private.burimunsi_sms_source_scopes
 WHERE source_id='fc940000-0000-4000-8000-000000000017')='adoption-other-group','same wallet second group has real independent immutable capture scope');
SELECT pg_temp.adoption_expect($q$SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000017','QUALIFICATION lease')$q$,'23514');
ROLLBACK TO cross_group_duplicate;
SAVEPOINT source_hash_conflict;
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000012',true);
SELECT pg_temp.adoption_expect($q$SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000012','QUALIFICATION lease')$q$,'23514');
ROLLBACK TO source_hash_conflict;
SAVEPOINT expired_lease;
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000013');
UPDATE app.momo_processing_jobs SET lease_until=app.unixepoch()-1 WHERE raw_sms_id='fc940000-0000-4000-8000-000000000013';
SELECT pg_temp.adoption_expect($q$SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000013','QUALIFICATION lease')$q$,'23514');
ROLLBACK TO expired_lease;
SAVEPOINT missing_work;
SELECT pg_temp.adoption_capture('fc940000-0000-4000-8000-000000000014');
SELECT set_config('collect.fence_admission_id','',true);
SELECT pg_temp.adoption_expect($q$SELECT pg_temp.adoption_finish('fc940000-0000-4000-8000-000000000014','QUALIFICATION lease')$q$,'55000');
ROLLBACK TO missing_work;
SELECT pg_temp.adoption_check((SELECT count(*) FROM app.momo_transactions)=1 AND (SELECT count(*) FROM private.burimunsi_transaction_scopes)=1,
 'failed batch cannot publish a candidate fact or another scope');
SELECT pg_temp.adoption_check(current_setting('burimunsi.collection_id')='buri-qualification-group'
 AND coalesce(current_setting('burimunsi.canonical_source_id',true),'')='','derived scope context does not leak');
ROLLBACK;
