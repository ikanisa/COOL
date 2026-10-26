BEGIN;
SET LOCAL search_path=app,pg_catalog;
CREATE FUNCTION pg_temp.expect_failure(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$BEGIN
 BEGIN EXECUTE statement;EXCEPTION WHEN OTHERS THEN IF position(expected IN SQLERRM)>0 THEN RETURN;ELSE RAISE EXCEPTION 'Wrong failure %, expected %',SQLERRM,expected;END IF;END;
 RAISE EXCEPTION 'Expected failure %',expected;
END$$;
CREATE FUNCTION pg_temp.seed_object(k text,entity text,purpose text,owner_id text DEFAULT 'storage-member',tombstone boolean DEFAULT false) RETURNS void LANGUAGE plpgsql AS $$
DECLARE scope_json jsonb:=jsonb_build_object('ownerId',owner_id,'entityId',entity,'purpose',purpose);metadata jsonb:=jsonb_build_object('sha256',repeat('a',64),'source_fingerprint',repeat('b',64),'source_sha256',repeat('a',64),'object_sha256',repeat('c',64));
BEGIN
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body) VALUES(k,repeat('b',64),scope_json,'synthetic-aad','synthetic-key',repeat('a',64),'synthetic-sealed-envelope');
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state,delete_tombstone) VALUES('put:'||k,k,repeat('d',64),repeat('c',64),40,scope_json,'{}',metadata,'committed',tombstone);
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata) VALUES(k,'put:'||k,repeat('d',64),repeat('c',64),40,scope_json,'{}',metadata);
END$$;

INSERT INTO private.storage_namespace(singleton,origin,bucket) VALUES(true,'https://synthetic-storage.example','synthetic-evidence');
SELECT pg_temp.expect_failure($q$UPDATE private.storage_namespace SET bucket='another-bucket'$q$,'immutable_storage_identity');
SELECT pg_temp.expect_failure($q$DELETE FROM private.storage_namespace$q$,'retain_storage_control_identity');
SELECT pg_temp.seed_object('fixture/good','raw-good','sms_receipt');
SELECT private.assert_storage_ready('fixture/good','storage-member','raw-good',repeat('a',64),'sms_receipt');
SELECT pg_temp.expect_failure($q$SELECT private.assert_storage_ready('fixture/good','other-member','raw-good',repeat('a',64),'sms_receipt')$q$,'storage_not_ready');
SELECT pg_temp.expect_failure($q$SELECT private.assert_storage_ready('fixture/good','storage-member','other-entity',repeat('a',64),'sms_receipt')$q$,'storage_not_ready');
SELECT pg_temp.expect_failure($q$SELECT private.assert_storage_ready('fixture/good','storage-member','raw-good',repeat('f',64),'sms_receipt')$q$,'storage_not_ready');
SELECT pg_temp.expect_failure($q$UPDATE private.storage_payload_reservations SET sealed_body='different-random-cipher' WHERE object_key='fixture/good'$q$,'immutable_storage_payload');
SELECT pg_temp.expect_failure($q$UPDATE private.storage_payload_reservations SET sealed_body=NULL,cleared_at=clock_timestamp() WHERE object_key='fixture/good'$q$,'storage_payload_clear_requires_application_or_erasure_commit');
SELECT pg_temp.expect_failure($q$UPDATE private.storage_put_intents SET sha256=repeat('e',64) WHERE object_key='fixture/good'$q$,'immutable_storage_identity');
SELECT pg_temp.expect_failure($q$DELETE FROM private.storage_objects WHERE object_key='fixture/good'$q$,'session_changed');
SELECT pg_temp.expect_failure($q$UPDATE private.storage_put_intents SET delete_tombstone=true WHERE object_key='fixture/good'$q$,'session_changed');
UPDATE private.storage_put_intents SET upload_unresolved=true WHERE object_key='fixture/good';
SELECT pg_temp.expect_failure($q$UPDATE private.storage_put_intents SET upload_unresolved=false WHERE object_key='fixture/good'$q$,'storage_state_regression');

-- Genuine synthetic managed Auth relation, with a stable legacy principal.
INSERT INTO auth.users(id,email) VALUES('c1000000-0000-4000-8000-000000000001','info@ikanisa.com');
INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES('c2000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','aal1',now()+interval '1 hour');
INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at) VALUES('storage-member','info@ikanisa.com','999999','Synthetic Storage','app',strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES('c1000000-0000-4000-8000-000000000001','storage-member','synthetic-local-fixture');
INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES('c2000000-0000-4000-8000-000000000001','storage-member','admin',unixepoch()-10,unixepoch()-10,unixepoch()+3500);

-- Missing metadata cannot produce a durable raw capture row.
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_failure($q$INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at) VALUES('raw-missing','storage-member','c2000000-0000-4000-8000-000000000001','missing',repeat('d',64),repeat('e',64),'fixture/missing',repeat('a',64),10,app.strftime('%Y-%m-%dT%H:%M:%fZ'))$q$,'storage_not_ready');

-- A later application failure rolls back both reference and spool clearing.
DO $$BEGIN
 BEGIN
  INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at) VALUES('raw-good','storage-member','c2000000-0000-4000-8000-000000000001','good',repeat('d',64),repeat('e',64),'fixture/good',repeat('a',64),10,strftime('%Y-%m-%dT%H:%M:%fZ'));
  RAISE EXCEPTION 'synthetic_application_rollback';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'synthetic_application_rollback' THEN RAISE;END IF;
 END;
 IF EXISTS(SELECT 1 FROM app.sms_receipts WHERE id='raw-good') OR (SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key='fixture/good') IS NULL THEN RAISE EXCEPTION 'Application rollback lost retry payload';END IF;
END$$;
INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at) VALUES('raw-good','storage-member','c2000000-0000-4000-8000-000000000001','good',repeat('d',64),repeat('e',64),'fixture/good',repeat('a',64),10,strftime('%Y-%m-%dT%H:%M:%fZ'));
DO $$BEGIN
 IF (SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key='fixture/good') IS NOT NULL OR (SELECT cleared_at FROM private.storage_payload_reservations WHERE object_key='fixture/good') IS NULL THEN RAISE EXCEPTION 'Reference did not clear encrypted spool';END IF;
 IF EXISTS(SELECT 1 FROM app.ledger_entries) THEN RAISE EXCEPTION 'Raw capture affected ledger';END IF;
END$$;
SELECT pg_temp.expect_failure($q$UPDATE private.storage_payload_reservations SET sealed_body='new-nonce',cleared_at=NULL WHERE object_key='fixture/good'$q$,'immutable_storage_payload');

-- Correct source but a durable tombstone must defeat the final capture ACK.
SELECT pg_temp.seed_object('fixture/tombstone','raw-tombstone','sms_receipt','storage-member',true);
-- Import/test owner can seed an initial tombstone; runtime cannot transition to
-- it without current source retention approval. The final fence still rejects.
SELECT pg_temp.expect_failure($q$INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at) VALUES('raw-tombstone','storage-member','c2000000-0000-4000-8000-000000000001','tombstone',repeat('d',64),repeat('e',64),'fixture/tombstone',repeat('a',64),10,app.strftime('%Y-%m-%dT%H:%M:%fZ'))$q$,'storage_not_ready');

-- Roster insertion reserves source identity before the provider upload; only
-- reserved->retained requires committed object bytes and clears its spool.
RESET ROLE;
INSERT INTO app.admin_grants(user_id,permission,granted_at) VALUES('storage-member','roster.import',strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO auth.mfa_factors(id,user_id,status) VALUES('c3000000-0000-4000-8000-000000000001','c1000000-0000-4000-8000-000000000001','verified');
INSERT INTO auth.mfa_amr_claims(session_id,authentication_method) VALUES('c2000000-0000-4000-8000-000000000001','totp');
UPDATE auth.sessions SET aal='aal2',factor_id='c3000000-0000-4000-8000-000000000001' WHERE id='c2000000-0000-4000-8000-000000000001';
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','c1000000-0000-4000-8000-000000000001','session_id','c2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal2','amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',unixepoch())))::text,true);
INSERT INTO app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter) VALUES('c3000000-0000-4000-8000-000000000001','storage-member','Synthetic','{"managed_by":"supabase"}','verified',unixepoch(),'c2000000-0000-4000-8000-000000000001',unixepoch(),0);
SELECT private.record_mfa_projection('c3000000-0000-4000-8000-000000000001');
UPDATE app.auth_sessions SET assurance_level=2,mfa_factor_id='c3000000-0000-4000-8000-000000000001',mfa_at=unixepoch() WHERE id='c2000000-0000-4000-8000-000000000001';
-- The Admin surface now also needs its real account/BFF link and independent
-- email proof. Optional MFA above stays truthful; it does not substitute for it.
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz;
UPDATE auth.users SET email_confirmed_at=now() WHERE id='c1000000-0000-4000-8000-000000000001';
-- This existing positive roster/privacy fixture needs the actual Owner capability set.
-- Explicit privacy-grant removal/revocation negatives below remain independent.
INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at) VALUES('storage-admin','info@ikanisa.com','owner','active','!managed-supabase!','Synthetic Storage',unixepoch(),unixepoch());
INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES('storage-admin','storage-member','synthetic-fixture',strftime('%Y-%m-%dT%H:%M:%fZ'));
-- Keep the existing missing-privacy-permission negative probe below meaningful.
DELETE FROM app.admin_grants WHERE user_id='storage-member' AND permission='privacy.review';
INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
 SELECT repeat('e',64),'storage-email-public','storage-admin',1,id,'https://admin.collect.ikanisa.com',auth_at,expires_at FROM app.auth_sessions WHERE id='c2000000-0000-4000-8000-000000000001';
INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext) VALUES(repeat('e',64),'c1000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000001','{}');
INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at) SELECT id::uuid,'otp',to_timestamp(auth_at) FROM app.auth_sessions WHERE id='c2000000-0000-4000-8000-000000000001';
SELECT set_config('collect.edge_verified','true',true);
SELECT set_config('request.jwt.claims',(private.request_claims()||jsonb_build_object('amr',(private.request_claims()->'amr')||jsonb_build_array(jsonb_build_object('method','otp','timestamp',auth_at))))::text,true) FROM app.auth_sessions WHERE id='c2000000-0000-4000-8000-000000000001';
INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)
 SELECT 'storage-email-initial',encode(sha256(convert_to('email:info@ikanisa.com','UTF8')),'hex'),'email','info@ikanisa.com','admin',0,auth_at-1,auth_at+299,1,auth_at,'accepted' FROM app.auth_sessions WHERE id='c2000000-0000-4000-8000-000000000001';
SELECT private.admin_email_record_initial('storage-admin',repeat('e',64),'https://admin.collect.ikanisa.com','storage-email-public','storage-email-initial');
SELECT private.set_admin_email_context('storage-admin',repeat('e',64),'https://admin.collect.ikanisa.com','storage-email-public');
SELECT pg_temp.seed_object('fixture/roster','roster-one','roster_source');
INSERT INTO app.roster_imports(id,user_id,session_id,request_id,request_sha256,source_sha256,object_sha256,source_object_key,source_size,source_kind,source_receipt_json,source_ciphertext,state,created_seconds,expires_seconds) VALUES('roster-one','storage-member','c2000000-0000-4000-8000-000000000001','roster-request',repeat('d',64),repeat('a',64),repeat('c',64),'fixture/roster',10,'csv','{}','{}','reserved',unixepoch(),unixepoch()+3600);
UPDATE app.roster_imports SET state='retained' WHERE id='roster-one';
DO $$BEGIN IF (SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key='fixture/roster') IS NOT NULL THEN RAISE EXCEPTION 'Roster finalization kept duplicate encrypted spool';END IF;END$$;

-- The generic-upload class has a real current policy/claim/effect/barrier.
-- A hold, revoked reviewer or incomplete journal finalization blocks erasure.
SELECT pg_temp.seed_object('fixture/erasable','upload-one','generic_upload','retention-subject');
INSERT INTO app.users(id,public_id,full_name,member_type,created_at,updated_at) VALUES('retention-subject','999998','Synthetic Retention','app',strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.upload_objects(id,user_id,object_key,sha256,size_bytes,content_type,purpose,created_at) VALUES('upload-one','retention-subject','fixture/erasable',repeat('c',64),40,'application/octet-stream','synthetic',strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT pg_temp.expect_failure($q$UPDATE private.storage_put_intents SET delete_tombstone=true WHERE object_key='fixture/erasable'$q$,'permission_denied');
INSERT INTO app.admin_grants(user_id,permission,granted_at) VALUES('storage-member','privacy.review',strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT pg_temp.expect_failure($q$UPDATE private.storage_put_intents SET delete_tombstone=true WHERE object_key='fixture/erasable'$q$,'storage_retention_admission_required');
INSERT INTO app.deletion_requests(id,user_id,submission_id,created_at,updated_at) VALUES('storage-delete-request','retention-subject','storage-delete-submission',strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.runtime_config(key,value_json,updated_at) VALUES('privacy:retention:approved:v1',jsonb_build_object('expires_at',now()+interval '1 hour','writer_fence',jsonb_build_object('generic_upload_catalog_only',true,'unknown_in_flight',false))::text,strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.privacy_retention_plans(id,operation_id,request_id,subject_id,actor_id,session_id,input_sha256,policy_sha256,policy_json,policy_config_revision,source_id,schema_sha256,scope_json,scope_sha256,ledger_sha256,review_revision,created_seconds)
 SELECT 'storage-retention-plan','storage-plan-op','storage-delete-request','retention-subject','storage-member','c2000000-0000-4000-8000-000000000001',repeat('a',64),encode(sha256(convert_to(value_json,'UTF8')),'hex'),value_json,revision,repeat('b',64),repeat('c',64),'{}',repeat('d',64),repeat('e',64),0,unixepoch() FROM app.runtime_config WHERE key='privacy:retention:approved:v1';
INSERT INTO app.privacy_retention_tasks(id,plan_id,class_name,action,expected_json,state,fence,claim_id) VALUES('storage-retention-task','storage-retention-plan','r2:upload_objects','erase','{}','claimed',1,'storage-retention-claim');
INSERT INTO app.privacy_retention_claims(id,operation_id,task_id,actor_id,session_id,input_sha256,expected_revision,fence,claimed_seconds,expires_seconds) VALUES('storage-retention-claim','storage-claim-op','storage-retention-task','storage-member','c2000000-0000-4000-8000-000000000001',repeat('a',64),0,1,unixepoch(),unixepoch()+120);
INSERT INTO app.privacy_retention_effects(operation_id,task_id,claim_id,fence,source_sha256,object_key,object_version,started_seconds) VALUES('storage-effect','storage-retention-task','storage-retention-claim',1,repeat('c',64),'fixture/erasable','synthetic-version',unixepoch());
INSERT INTO app.privacy_retention_barriers(subject_id,plan_id,source_id,policy_sha256,activated_seconds) SELECT subject_id,id,source_id,policy_sha256,unixepoch() FROM app.privacy_retention_plans WHERE id='storage-retention-plan';
INSERT INTO app.mutation_guards(id,user_id,session_id,now_seconds,permission,fresh_seconds,minimum_assurance,expected_mfa_at) VALUES('storage-actor-guard','storage-member','c2000000-0000-4000-8000-000000000001',unixepoch(),'privacy.review',300,2,NULL);
INSERT INTO app.privacy_retention_guards(id,plan_id,class_name,passed) VALUES('storage-source-guard','storage-retention-plan','r2:upload_objects',1);
INSERT INTO private.storage_delete_intents(operation_id,object_key,fingerprint,expected_sha256,scope) SELECT 'delete:fixture/erasable',object_key,repeat('f',64),sha256,scope FROM private.storage_put_intents WHERE object_key='fixture/erasable';
SELECT pg_temp.expect_failure($q$SELECT private.assert_storage_delete_authorized('fixture/erasable')$q$,'storage_retention_admission_required');
INSERT INTO app.privacy_retention_outcomes(operation_id,task_id,claim_id,fence,input_sha256,outcome_json,observed_seconds)
 SELECT 'storage-send-start',t.id,c.id,c.fence,repeat('a',64),jsonb_build_object('contract_version',1,'verified',false,'disposition','catalog_object_send_started',
  'original_effect_operation_id',e.operation_id,'object_key_sha256',encode(sha256(convert_to(e.object_key,'UTF8')),'hex'),
  'source_sha256',e.source_sha256,'source_id',p.source_id,'policy_sha256',p.policy_sha256,'erasure_completed',false,'all_data_erased',false)::text,unixepoch()
 FROM app.privacy_retention_effects e JOIN app.privacy_retention_tasks t ON t.id=e.task_id JOIN app.privacy_retention_claims c ON c.id=t.claim_id JOIN app.privacy_retention_plans p ON p.id=t.plan_id
 WHERE e.operation_id='storage-effect';
SET LOCAL ROLE collect_runtime;
UPDATE private.storage_put_intents SET delete_tombstone=true WHERE object_key='fixture/erasable';
INSERT INTO app.privacy_holds(id,user_id,category,reason_code,created_at) VALUES('storage-hold','retention-subject','synthetic','fixture',strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT pg_temp.expect_failure($q$DELETE FROM private.storage_objects WHERE object_key='fixture/erasable'$q$,'storage_retention_admission_required');
UPDATE app.privacy_holds SET active=0 WHERE id='storage-hold';
DELETE FROM app.admin_grants WHERE user_id='storage-member' AND permission='privacy.review';
SELECT pg_temp.expect_failure($q$DELETE FROM private.storage_objects WHERE object_key='fixture/erasable'$q$,'permission_denied');
INSERT INTO app.admin_grants(user_id,permission,granted_at) VALUES('storage-member','privacy.review',strftime('%Y-%m-%dT%H:%M:%fZ'));
DO $$BEGIN
 BEGIN
  DELETE FROM private.storage_objects WHERE object_key='fixture/erasable';
  SET CONSTRAINTS private.storage_object_erase_commit IMMEDIATE;
  RAISE EXCEPTION 'Expected incomplete erasure rejection';
 EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'storage_erasure_commit_incomplete' THEN RAISE;END IF;
 END;
 IF NOT EXISTS(SELECT 1 FROM private.storage_objects WHERE object_key='fixture/erasable') THEN RAISE EXCEPTION 'Incomplete erasure lost metadata';END IF;
END$$;
DELETE FROM private.storage_objects WHERE object_key='fixture/erasable';
UPDATE private.storage_put_intents SET state='erased' WHERE object_key='fixture/erasable';
UPDATE private.storage_delete_intents SET state='committed',absence_proof='{"headStatus":404,"getStatus":404,"bucketVerified":true}',committed_at=clock_timestamp() WHERE object_key='fixture/erasable';
SET CONSTRAINTS private.storage_object_erase_commit IMMEDIATE;
DO $$BEGIN IF EXISTS(SELECT 1 FROM private.storage_objects WHERE object_key='fixture/erasable') OR (SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key='fixture/erasable') IS NOT NULL THEN RAISE EXCEPTION 'Verified erasure did not finalize metadata/spool';END IF;END$$;
RESET ROLE;

-- Budget is durable across separate workers and is enforced by the database.
INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)
 SELECT 'budget/'||n,repeat('a',64),jsonb_build_object('ownerId','budget-owner','entityId',n::text,'purpose','sms_receipt'),'synthetic','test',repeat('b',64),'x' FROM generate_series(1,128)n;
SELECT pg_temp.expect_failure($q$INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body) VALUES('budget/129',repeat('a',64),'{"ownerId":"budget-owner","entityId":"129","purpose":"sms_receipt"}','synthetic','test',repeat('b',64),'x')$q$,'storage_pending_budget_exceeded');
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_failure($q$INSERT INTO private.object_metadata(object_key,size,http_metadata,custom_metadata,sha256) VALUES('legacy-writer',1,'{}','{}',repeat('a',64))$q$,'permission denied');
SELECT pg_temp.expect_failure($q$UPDATE private.storage_namespace SET origin='https://other.example'$q$,'permission denied');
RESET ROLE;
ROLLBACK;
