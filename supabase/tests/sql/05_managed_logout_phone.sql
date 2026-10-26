BEGIN;
SET LOCAL search_path=app,pg_catalog;
CREATE FUNCTION pg_temp.expect_failure(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$BEGIN
 BEGIN EXECUTE statement;EXCEPTION WHEN OTHERS THEN IF position(expected IN SQLERRM)>0 THEN RETURN;ELSE RAISE EXCEPTION 'Wrong failure %, expected %',SQLERRM,expected;END IF;END;
 RAISE EXCEPTION 'Expected failure %',expected;
END$$;
-- Synthetic identities only. Managed proof is never seeded from legacy OTP.
INSERT INTO auth.users(id,email,phone,phone_confirmed_at) VALUES
 ('11000000-0000-4000-8000-000000000001','info@ikanisa.com',NULL,NULL),
 ('11000000-0000-4000-8000-000000000002','phone@example.test','250788123456',now()-interval '1 minute');
INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES
 ('22000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','aal2',now()+interval '1 hour'),
 ('22000000-0000-4000-8000-000000000002','11000000-0000-4000-8000-000000000002','aal1',now()+interval '1 hour'),
 ('22000000-0000-4000-8000-000000000003','11000000-0000-4000-8000-000000000002','aal1',now()+interval '1 hour');
INSERT INTO app.users(id,email,phone,public_id,full_name,member_type,created_at,updated_at) VALUES
 ('33000000-0000-4000-8000-000000000001','info@ikanisa.com',NULL,'910001','Synthetic Owner','operator',strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('33000000-0000-4000-8000-000000000002','phone@example.test','+250788123456','910002','Synthetic Phone','app',strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES
 ('11000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001','synthetic-local-fixture'),
 ('11000000-0000-4000-8000-000000000002','33000000-0000-4000-8000-000000000002','synthetic-local-fixture');
INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES
 ('22000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001','admin',unixepoch()-10,unixepoch()-10,unixepoch()+3500),
 ('22000000-0000-4000-8000-000000000002','33000000-0000-4000-8000-000000000002','member',unixepoch()-10,unixepoch()-10,unixepoch()+3500),
 ('22000000-0000-4000-8000-000000000003','33000000-0000-4000-8000-000000000002','member',unixepoch()-10,unixepoch()-10,unixepoch()+3500);
INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status)
 VALUES('44000000-0000-4000-8000-000000000001',repeat('a',64),'phone','+250788123456','member',0,unixepoch()-30,unixepoch()+300,'accepted');
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','11000000-0000-4000-8000-000000000002','session_id','22000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',unixepoch()-1)))::text,true);
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_failure($q$SELECT private.record_managed_phone_verification('44000000-0000-4000-8000-000000000001')$q$,'consumed_managed_phone_challenge_required');
SELECT pg_temp.expect_failure($q$INSERT INTO private.managed_phone_verifications(challenge_id,auth_user_id,session_id,user_id,phone,verified_at) VALUES('44000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002','22000000-0000-4000-8000-000000000002','33000000-0000-4000-8000-000000000002','+250788123456',app.unixepoch())$q$,'permission denied');
RESET ROLE;
UPDATE private.supabase_otp_challenges SET attempts=1,consumed_at=unixepoch()-1 WHERE id='44000000-0000-4000-8000-000000000001';
UPDATE auth.users SET phone_confirmed_at=NULL WHERE id='11000000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_failure($q$SELECT private.record_managed_phone_verification('44000000-0000-4000-8000-000000000001')$q$,'confirmed_managed_phone_required');
RESET ROLE;
UPDATE auth.users SET phone_confirmed_at=now()-interval '1 minute',phone='250788123457' WHERE id='11000000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_failure($q$SELECT private.record_managed_phone_verification('44000000-0000-4000-8000-000000000001')$q$,'managed_phone_identity_changed');
RESET ROLE;
UPDATE auth.users SET phone='250788123456' WHERE id='11000000-0000-4000-8000-000000000002';
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','11000000-0000-4000-8000-000000000002','session_id','22000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','amr',jsonb_build_array(jsonb_build_object('method','password','timestamp',unixepoch()-1)))::text,true);
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_failure($q$SELECT private.record_managed_phone_verification('44000000-0000-4000-8000-000000000001')$q$,'original_managed_phone_amr_required');
RESET ROLE;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','11000000-0000-4000-8000-000000000002','session_id','22000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',unixepoch()-31)))::text,true);
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_failure($q$SELECT private.record_managed_phone_verification('44000000-0000-4000-8000-000000000001')$q$,'original_managed_phone_amr_required');
RESET ROLE;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','11000000-0000-4000-8000-000000000002','session_id','22000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',unixepoch()-1)))::text,true);
SET LOCAL ROLE collect_runtime;
SELECT private.record_managed_phone_verification('44000000-0000-4000-8000-000000000001');
SELECT private.record_managed_phone_verification('44000000-0000-4000-8000-000000000001');
DO $$BEGIN
 IF (SELECT count(*) FROM private.managed_phone_verifications)<>1 OR (SELECT verified_at FROM private.managed_phone_verifications)<>app.unixepoch()-1 THEN RAISE EXCEPTION 'Original managed OTP timestamp/idempotency lost';END IF;
 IF NOT private.managed_phone_binding('33000000-0000-4000-8000-000000000002','44000000-0000-4000-8000-000000000001','+250788123456','22000000-0000-4000-8000-000000000002') OR private.managed_phone_binding('33000000-0000-4000-8000-000000000002','44000000-0000-4000-8000-000000000001','+250788123456','22000000-0000-4000-8000-000000000003') THEN RAISE EXCEPTION 'Current phone proof must bind the original session';END IF;
 IF (SELECT count(*) FROM app.auth_otp_verifications)<>0 THEN RAISE EXCEPTION 'Managed proof invented legacy verification';END IF;
END$$;
RESET ROLE;
SELECT pg_temp.expect_failure($q$UPDATE private.managed_phone_verifications SET verified_at=app.unixepoch()$q$,'immutable_managed_phone_verification');
SELECT pg_temp.expect_failure($q$DELETE FROM private.managed_phone_verifications$q$,'immutable_managed_phone_verification');
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','11000000-0000-4000-8000-000000000002','session_id','22000000-0000-4000-8000-000000000003','role','authenticated','aal','aal1','amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',unixepoch()-1)))::text,true);
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_failure($q$SELECT private.record_managed_phone_verification('44000000-0000-4000-8000-000000000001')$q$,'managed_phone_proof_conflict');
RESET ROLE;
-- A real current-job row must qualify through managed proof with ZERO legacy
-- OTP rows; all original payment/ledger/consent/destination predicates remain.
INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES('88000000-0000-4000-8000-000000000001','synthetic-phone-group','33000000-0000-4000-8000-000000000001','Synthetic Phone','community',strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.memberships(id,collection_id,user_id,role,joined_at) VALUES('88000000-0000-4000-8000-000000000002','88000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000002','member',strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body) VALUES('synthetic/phone-evidence',repeat('d',64),'{"ownerId":"33000000-0000-4000-8000-000000000001","entityId":"88000000-0000-4000-8000-000000000003","purpose":"payment_evidence"}','synthetic-only','fixture',repeat('c',64),'synthetic-encrypted-envelope');
INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state) SELECT 'synthetic-phone-evidence',object_key,repeat('e',64),repeat('f',64),30,scope,'{}',jsonb_build_object('sha256',plaintext_sha256,'source_fingerprint',source_fingerprint),'committed' FROM private.storage_payload_reservations WHERE object_key='synthetic/phone-evidence';
INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata) SELECT object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata FROM private.storage_put_intents WHERE object_key='synthetic/phone-evidence';
INSERT INTO app.payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,amount_minor,observed_at,created_at) VALUES('88000000-0000-4000-8000-000000000003','88000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001','synthetic/phone-evidence',repeat('c',64),30,'text/plain','operator_recorded',1200,strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at) VALUES('88000000-0000-4000-8000-000000000004','88000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000002','88000000-0000-4000-8000-000000000003',1200,'confirmed',strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES('88000000-0000-4000-8000-000000000005','88000000-0000-4000-8000-000000000004','88000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000002',1200,'contribution','88000000-0000-4000-8000-000000000003','33000000-0000-4000-8000-000000000001','88000000-0000-4000-8000-000000000006',strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.assisted_sms_policies(collection_id,enabled,revision,template_key,approval_reference_sha256,updated_at) VALUES('88000000-0000-4000-8000-000000000001',1,1,'collect.recorded_contribution.v1',repeat('a',64),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.assisted_sms_authorizations(collection_id,recipient_user_id,enabled,consent_revision,destination_revision,destination_ciphertext,destination_sha256,phone_verification_challenge_id,authorization_receipt_sha256,updated_at) VALUES('88000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000002',1,1,1,'{}',repeat('b',64),'44000000-0000-4000-8000-000000000001',repeat('c',64),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.assisted_sms_jobs(id,payment_id,entry_id,collection_id,recipient_user_id,payment_revision,amount_minor,destination_revision,destination_sha256,destination_ciphertext,consent_revision,policy_revision,policy_approval_sha256,authorization_receipt_sha256,template_key,body_ciphertext,body_sha256,created_at) VALUES('88000000-0000-4000-8000-000000000007','88000000-0000-4000-8000-000000000004','88000000-0000-4000-8000-000000000005','88000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000002',1,1200,1,repeat('b',64),'{}',1,1,repeat('a',64),repeat('c',64),'collect.recorded_contribution.v1','{}',repeat('d',64),strftime('%Y-%m-%dT%H:%M:%fZ'));
DO $$BEGIN IF (SELECT count(*) FROM app.assisted_sms_current_jobs)<>1 THEN RAISE EXCEPTION 'Managed phone proof failed real assisted SMS eligibility';END IF;END$$;
-- Managed logout removes the real session before the local revocation write.
DELETE FROM auth.sessions WHERE id='22000000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_failure($q$UPDATE app.auth_sessions SET assurance_level=assurance_level WHERE id='22000000-0000-4000-8000-000000000002'$q$,'managed_session_required');
SELECT pg_temp.expect_failure($q$UPDATE app.auth_sessions SET expires_at=expires_at+1 WHERE id='22000000-0000-4000-8000-000000000002'$q$,'immutable_session_identity');
UPDATE app.auth_sessions SET revoked_at=app.unixepoch(),revocation_reason='managed_logout' WHERE id='22000000-0000-4000-8000-000000000002' AND revoked_at IS NULL;
SELECT pg_temp.expect_failure($q$UPDATE app.auth_sessions SET revoked_at=NULL,revocation_reason=NULL WHERE id='22000000-0000-4000-8000-000000000002'$q$,'session_revocation_is_final');
DO $$BEGIN
 IF NOT private.managed_phone_binding('33000000-0000-4000-8000-000000000002','44000000-0000-4000-8000-000000000001','+250788123456') OR private.managed_phone_binding('33000000-0000-4000-8000-000000000002','44000000-0000-4000-8000-000000000001','+250788123456','22000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Retained binding/logout isolation lost';END IF;
 IF (SELECT count(*) FROM app.assisted_sms_current_jobs)<>1 THEN RAISE EXCEPTION 'Original managed consent was lost on session logout';END IF;
END$$;
RESET ROLE;
UPDATE auth.users SET phone='250788123457' WHERE id='11000000-0000-4000-8000-000000000002';
DO $$BEGIN IF private.managed_phone_binding('33000000-0000-4000-8000-000000000002','44000000-0000-4000-8000-000000000001','+250788123456') THEN RAISE EXCEPTION 'Changed managed phone retained consent';END IF;IF EXISTS(SELECT 1 FROM app.assisted_sms_current_jobs) THEN RAISE EXCEPTION 'Changed phone remained delivery eligible';END IF;END$$;
UPDATE auth.users SET phone='250788123456',phone_confirmed_at=NULL WHERE id='11000000-0000-4000-8000-000000000002';
DO $$BEGIN IF private.managed_phone_binding('33000000-0000-4000-8000-000000000002','44000000-0000-4000-8000-000000000001','+250788123456') THEN RAISE EXCEPTION 'Unconfirmed managed phone retained consent';END IF;END$$;
UPDATE auth.users SET phone_confirmed_at=now()-interval '1 minute' WHERE id='11000000-0000-4000-8000-000000000002';
-- Admin cookie/BFF deletion must also finish after real AAL2 session removal.
INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at) VALUES('55000000-0000-4000-8000-000000000001','info@ikanisa.com','owner','active','!managed-supabase!','Synthetic Owner',unixepoch(),unixepoch());
INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES('55000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001','synthetic-fixture',strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.admin_sessions(token_hash,user_id,auth_session_id,public_id,auth_version,created_at,expires_at,origin,issued_assurance_level) VALUES(repeat('d',64),'55000000-0000-4000-8000-000000000001','22000000-0000-4000-8000-000000000001','66000000-0000-4000-8000-000000000001',1,unixepoch()-10,unixepoch()+3500,'https://synthetic-admin.example',1);
INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext) VALUES(repeat('d',64),'11000000-0000-4000-8000-000000000001','22000000-0000-4000-8000-000000000001','{}');
INSERT INTO auth.mfa_factors(id,user_id,status) VALUES('77000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','verified');
INSERT INTO auth.mfa_amr_claims(session_id,authentication_method) VALUES('22000000-0000-4000-8000-000000000001','totp');
UPDATE auth.sessions SET factor_id='77000000-0000-4000-8000-000000000001' WHERE id='22000000-0000-4000-8000-000000000001';
INSERT INTO app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter) VALUES('77000000-0000-4000-8000-000000000001','33000000-0000-4000-8000-000000000001','Managed','{"managed_by":"supabase"}','verified',unixepoch(),'22000000-0000-4000-8000-000000000001',unixepoch(),0);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','11000000-0000-4000-8000-000000000001','session_id','22000000-0000-4000-8000-000000000001','role','authenticated','aal','aal2','amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',unixepoch())))::text,true);
SELECT private.record_mfa_projection('77000000-0000-4000-8000-000000000001');
UPDATE app.auth_sessions SET assurance_level=2,mfa_at=unixepoch(),mfa_factor_id='77000000-0000-4000-8000-000000000001' WHERE id='22000000-0000-4000-8000-000000000001';
UPDATE app.admin_sessions SET issued_assurance_level=2,issued_mfa_at=unixepoch(),issued_mfa_factor_id='77000000-0000-4000-8000-000000000001' WHERE token_hash=repeat('d',64);
DELETE FROM auth.mfa_amr_claims WHERE session_id='22000000-0000-4000-8000-000000000001';
DELETE FROM auth.sessions WHERE id='22000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.expect_failure($q$UPDATE app.auth_sessions SET revoked_at=app.unixepoch(),revocation_reason='logout',assurance_level=1,mfa_at=NULL,mfa_factor_id=NULL WHERE id='22000000-0000-4000-8000-000000000001'$q$,'managed_session_required');
SELECT pg_temp.expect_failure($q$UPDATE app.auth_sessions SET mfa_at=mfa_at+1 WHERE id='22000000-0000-4000-8000-000000000001'$q$,'verified_mfa_claim_required');
SELECT pg_temp.expect_failure($q$INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at,revoked_at,revocation_reason) VALUES('22000000-0000-4000-8000-000000000009','33000000-0000-4000-8000-000000000001','admin',app.unixepoch(),app.unixepoch(),app.unixepoch()+10,app.unixepoch(),'logout')$q$,'managed_session_required');
DELETE FROM app.admin_sessions WHERE token_hash=repeat('d',64);
DO $$BEGIN IF EXISTS(SELECT 1 FROM private.bff_sessions) OR NOT EXISTS(SELECT 1 FROM app.auth_sessions WHERE id='22000000-0000-4000-8000-000000000001' AND revoked_at IS NOT NULL AND assurance_level=2 AND mfa_factor_id='77000000-0000-4000-8000-000000000001') THEN RAISE EXCEPTION 'Managed Admin logout failed to revoke and clear custody';END IF;END$$;
RESET ROLE;
DO $$BEGIN IF position('managed_phone_binding' IN pg_get_viewdef('app.assisted_sms_current_jobs'::regclass,true))=0 THEN RAISE EXCEPTION 'Assisted SMS view omitted managed phone eligibility';END IF;END$$;
ROLLBACK;
