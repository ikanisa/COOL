BEGIN;
SET LOCAL search_path=app,pg_catalog;
CREATE FUNCTION pg_temp.expect_failure(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN IF position(expected IN SQLERRM)>0 THEN RETURN; ELSE RAISE EXCEPTION 'Wrong failure: %, expected %',SQLERRM,expected; END IF; END;
 RAISE EXCEPTION 'Expected failure: %',expected;
END$$;

-- Synthetic retained-byte proof fixture. This seeds the control-plane rows;
-- actual native provider hash/probe behavior is tested by the Storage suite.
CREATE FUNCTION pg_temp.seed_storage(k text,owner_id text,entity text,plain_sha text,purpose text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE scope_json jsonb:=jsonb_build_object('ownerId',owner_id,'entityId',entity,'purpose',purpose);metadata jsonb:=jsonb_build_object('sha256',plain_sha,'source_fingerprint',repeat('d',64));
BEGIN
 INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body) VALUES(k,repeat('d',64),scope_json,'synthetic-only','fixture',plain_sha,'synthetic-encrypted-envelope');
 INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,state) VALUES('fixture:'||k,k,repeat('e',64),repeat('f',64),30,scope_json,'{}',metadata,'committed');
 INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata) VALUES(k,'fixture:'||k,repeat('e',64),repeat('f',64),30,scope_json,'{}',metadata);
END$$;

-- Test-only transaction oracle; this is never a deployed application RPC.
CREATE FUNCTION pg_temp.test_reverse_payment(p_payment_id text,p_expected_revision bigint,p_request_id text,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=app,pg_catalog AS $$
DECLARE actor text; payment app.payments%ROWTYPE; original app.ledger_entries%ROWTYPE; retained app.request_receipts%ROWTYPE; result jsonb; stamp text; entry_id text; body_sha256 text;
BEGIN
 actor:=private.assert_actor('payments.reconcile',NULL,NULL,2,300);
 IF length(trim(p_reason)) NOT BETWEEN 1 AND 500 OR p_request_id !~ '^[0-9a-f-]{36}$' THEN RAISE EXCEPTION 'invalid_parameter' USING ERRCODE='22023'; END IF;
 body_sha256:=encode(sha256(convert_to(jsonb_build_object('payment_id',p_payment_id,'expected_revision',p_expected_revision,'request_id',p_request_id,'reason',p_reason)::text,'UTF8')),'hex');
 -- Serialize one actor/request before checking the retained outcome.
 PERFORM pg_advisory_xact_lock(hashtextextended(actor||':'||p_request_id,0));
 SELECT * INTO retained FROM app.request_receipts WHERE user_id=actor AND request_id=p_request_id;
 IF FOUND THEN
  IF retained.operation<>'supabase.reverse_payment.v1' OR retained.session_id<>api.current_session_id() OR retained.body_sha256<>body_sha256 THEN RAISE EXCEPTION 'request_conflict' USING ERRCODE='23505'; END IF;
  RETURN retained.response_json::jsonb;
 END IF;
 SELECT * INTO payment FROM app.payments WHERE id=p_payment_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'payment_unavailable' USING ERRCODE='P0002'; END IF;
 PERFORM private.lock_collections(ARRAY[payment.collection_id]);
 SELECT * INTO payment FROM app.payments WHERE id=p_payment_id FOR UPDATE;
 IF payment.revision<>p_expected_revision OR payment.status='reversed' THEN RAISE EXCEPTION 'stale_payment' USING ERRCODE='40001'; END IF;
 SELECT * INTO original FROM app.ledger_entries WHERE payment_id=payment.id AND kind='contribution';
 IF NOT FOUND OR EXISTS(SELECT 1 FROM app.ledger_entries WHERE reverses_entry_id=original.id) THEN RAISE EXCEPTION 'invalid_reversal' USING ERRCODE='23514'; END IF;
 stamp:=app.strftime('%Y-%m-%dT%H:%M:%fZ'); entry_id:=gen_random_uuid()::text;
 result:=jsonb_build_object('payment_id',payment.id,'revision',payment.revision+1,'status','reversed');
 INSERT INTO app.request_receipts(user_id,request_id,operation,session_id,body_sha256,response_json,created_at) VALUES(actor,p_request_id,'supabase.reverse_payment.v1',api.current_session_id(),body_sha256,result::text,stamp);
 INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,reverses_entry_id,evidence_id,actor_user_id,request_id,posted_at) VALUES(entry_id,payment.id,payment.collection_id,original.member_id,-original.amount_minor,'reversal',original.id,original.evidence_id,actor,p_request_id,stamp);
 UPDATE app.payments SET status='reversed',revision=revision+1 WHERE id=payment.id;
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at) VALUES(actor,api.current_session_id(),'supabase.reverse_payment.v1','payment',payment.id,p_request_id,jsonb_build_object('reason',p_reason,'request_sha256',body_sha256)::text,stamp);
 RETURN result;
END$$;

INSERT INTO auth.users(id,email) VALUES('10000000-0000-4000-8000-000000000001','info@ikanisa.com'),('10000000-0000-4000-8000-000000000002','member@example.test');
INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','aal2',now()+interval '1 hour'),('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','aal1',now()+interval '1 hour');
INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at) VALUES('30000000-0000-4000-8000-000000000001','info@ikanisa.com','000001','Owner','operator',strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ')),('30000000-0000-4000-8000-000000000002','member@example.test','000002','Member','app',strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES('10000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','synthetic-local-fixture'),('10000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000002','synthetic-local-fixture');
SELECT pg_temp.expect_failure($q$UPDATE private.auth_principal_links SET proof_reference='different-proof' WHERE auth_user_id='10000000-0000-4000-8000-000000000001'$q$,'immutable_managed_principal_link');
INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','admin',unixepoch()-10,unixepoch()-10,unixepoch()+3500),('20000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000002','member',unixepoch(),unixepoch(),unixepoch()+3500);
SELECT pg_temp.expect_failure($q$INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES('20000000-0000-4000-8000-000000000099','30000000-0000-4000-8000-000000000002','member',app.unixepoch(),app.unixepoch(),app.unixepoch()+1000)$q$,'managed_session_required');
INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at) VALUES('40000000-0000-4000-8000-000000000001','info@ikanisa.com','owner','active','!managed-supabase!','Owner',unixepoch(),unixepoch());
INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES('40000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','synthetic-fixture',strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT pg_temp.expect_failure($q$INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at) VALUES('40000000-0000-4000-8000-000000000002','INFO@IKANISA.COM','admin','active','sentinel','Duplicate',app.unixepoch(),app.unixepoch())$q$,'unique');
INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES('50000000-0000-4000-8000-000000000001','fixture-group','30000000-0000-4000-8000-000000000001','Fixture','community',strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.memberships(id,collection_id,user_id,role,joined_at) VALUES('60000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','owner',strftime('%Y-%m-%dT%H:%M:%fZ')),('60000000-0000-4000-8000-000000000002','50000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','member',strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT pg_temp.seed_storage('evidence/fixture','30000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001',repeat('a',64),'payment_evidence');
INSERT INTO app.payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,amount_minor,observed_at,created_at) VALUES('70000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','evidence/fixture',repeat('a',64),12,'text/plain','operator_recorded',1200,strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at) VALUES('80000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','70000000-0000-4000-8000-000000000001',1200,'confirmed',strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at) VALUES('90000000-0000-4000-8000-000000000001','80000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002',1200,'contribution','70000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001',strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT pg_temp.expect_failure($q$UPDATE app.ledger_entries SET amount_minor=1199 WHERE id='90000000-0000-4000-8000-000000000001'$q$,'immutable_ledger');
SELECT pg_temp.expect_failure($q$DELETE FROM app.payment_evidence WHERE id='70000000-0000-4000-8000-000000000001'$q$,'retain_financial_evidence');
SELECT pg_temp.expect_failure($q$INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,reverses_entry_id,evidence_id,actor_user_id,request_id,posted_at) VALUES('90000000-0000-4000-8000-000000000002','80000000-0000-4000-8000-000000000001','50000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002',-1199,'reversal','90000000-0000-4000-8000-000000000001','70000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000002',app.strftime('%Y-%m-%dT%H:%M:%fZ'))$q$,'invalid_reversal');
-- Genuine local managed email OTP plus original BFF fixture. A fresh password,
-- Google token or AAL2 assertion alone does not establish this independent proof.
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email_confirmed_at timestamptz;
UPDATE auth.users SET email_confirmed_at=now() WHERE id='10000000-0000-4000-8000-000000000001';
INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
 SELECT repeat('e',64),'financial-email-public','40000000-0000-4000-8000-000000000001',1,id,'https://admin.collect.ikanisa.com',auth_at,expires_at FROM app.auth_sessions WHERE id='20000000-0000-4000-8000-000000000001';
INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext) VALUES(repeat('e',64),'10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','{}');
SELECT set_config('collect.edge_verified','true',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','10000000-0000-4000-8000-000000000002','session_id','20000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',unixepoch())))::text,true);
SELECT pg_temp.expect_failure($q$SELECT private.assert_actor(NULL,NULL,NULL,2,300)$q$,'mfa_required');
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','10000000-0000-4000-8000-000000000001','session_id','20000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',auth_at)))::text,true) FROM app.auth_sessions WHERE id='20000000-0000-4000-8000-000000000001';
SELECT private.set_admin_email_context('40000000-0000-4000-8000-000000000001',repeat('e',64),'https://admin.collect.ikanisa.com','financial-email-public');
SELECT pg_temp.expect_failure($q$SELECT pg_temp.test_reverse_payment('80000000-0000-4000-8000-000000000001',1,'a0000000-0000-4000-8000-000000000003','fixture')$q$,'recent_email_sign_in_required');
INSERT INTO auth.mfa_amr_claims(session_id,authentication_method,updated_at) SELECT id::uuid,'otp',to_timestamp(auth_at) FROM app.auth_sessions WHERE id='20000000-0000-4000-8000-000000000001';
INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)
 SELECT 'financial-email-initial',encode(sha256(convert_to('email:info@ikanisa.com','UTF8')),'hex'),'email','info@ikanisa.com','admin',0,auth_at-1,auth_at+299,1,auth_at,'accepted' FROM app.auth_sessions WHERE id='20000000-0000-4000-8000-000000000001';
SELECT private.admin_email_record_initial('40000000-0000-4000-8000-000000000001',repeat('e',64),'https://admin.collect.ikanisa.com','financial-email-public','financial-email-initial');
SELECT private.assert_actor('payments.reconcile',NULL,NULL,2,300);
SELECT pg_temp.expect_failure($q$SELECT private.assert_admin_email_context(1)$q$,'recent_email_sign_in_required');
DO $$BEGIN
 IF (SELECT assurance_level<>1 OR mfa_at IS NOT NULL OR mfa_factor_id IS NOT NULL FROM app.auth_sessions WHERE id='20000000-0000-4000-8000-000000000001')
  OR (private.admin_email_status('40000000-0000-4000-8000-000000000001',repeat('e',64),'https://admin.collect.ikanisa.com','financial-email-public')->>'email_verified_at')::bigint IS DISTINCT FROM (SELECT auth_at FROM app.auth_sessions WHERE id='20000000-0000-4000-8000-000000000001')
 THEN RAISE EXCEPTION 'Admin email policy manufactured MFA or renewed proof timestamp';END IF;
END$$;
SELECT pg_temp.expect_failure($q$UPDATE private.admin_sensitive_email_proofs SET verified_at=app.unixepoch()$q$,'retain_admin_email_provenance');
-- Existing optional MFA projection/revocation truth remains independently real.
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','10000000-0000-4000-8000-000000000001','session_id','20000000-0000-4000-8000-000000000001','role','authenticated','aal','aal2','amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',unixepoch())))::text,true);
INSERT INTO auth.mfa_factors(id,user_id,status) VALUES('b0000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','verified');
INSERT INTO auth.mfa_amr_claims(session_id,authentication_method) VALUES('20000000-0000-4000-8000-000000000001','totp');
UPDATE auth.sessions SET factor_id='b0000000-0000-4000-8000-000000000001' WHERE id='20000000-0000-4000-8000-000000000001';
INSERT INTO app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter) VALUES('b0000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','Managed','{"managed_by":"supabase"}','verified',unixepoch(),'20000000-0000-4000-8000-000000000001',unixepoch(),0);
SELECT private.record_mfa_projection('b0000000-0000-4000-8000-000000000001');
UPDATE app.auth_sessions SET assurance_level=2,mfa_factor_id='b0000000-0000-4000-8000-000000000001',mfa_at=unixepoch() WHERE id='20000000-0000-4000-8000-000000000001';
SELECT pg_temp.test_reverse_payment('80000000-0000-4000-8000-000000000001',1,'a0000000-0000-4000-8000-000000000003','fixture');
SELECT pg_temp.test_reverse_payment('80000000-0000-4000-8000-000000000001',1,'a0000000-0000-4000-8000-000000000003','fixture');
SELECT pg_temp.expect_failure($q$SELECT pg_temp.test_reverse_payment('80000000-0000-4000-8000-000000000001',1,'a0000000-0000-4000-8000-000000000003','changed-body')$q$,'request_conflict');
DO $$BEGIN IF (SELECT sum(amount_minor) FROM app.ledger_entries)<>0 OR (SELECT count(*) FROM app.ledger_entries)<>2 OR (SELECT count(*) FROM app.request_receipts WHERE operation='supabase.reverse_payment.v1')<>1 OR (SELECT revision FROM app.payments WHERE id='80000000-0000-4000-8000-000000000001')<>2 THEN RAISE EXCEPTION 'Reversal atomicity/idempotency mismatch'; END IF; END$$;

-- Managed authority is bound to the real actor/session even for retained
-- original mutation-guard protocols; stale/group and spoofed-actor branches.
INSERT INTO app.mutation_guards(id,user_id,session_id,now_seconds) VALUES('valid-guard','30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',unixepoch());
SELECT pg_temp.expect_failure($q$INSERT INTO app.mutation_guards(id,user_id,session_id,now_seconds) VALUES('spoofed-guard','30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002',app.unixepoch())$q$,'session_changed');
SELECT pg_temp.expect_failure($q$INSERT INTO app.mutation_guards(id,user_id,session_id,now_seconds,collection_id,expected_collection_revision) VALUES('stale-guard','30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',app.unixepoch(),'50000000-0000-4000-8000-000000000001',999)$q$,'stale_collection');

-- Alias JSON/type/GLOB validation, rate limiting and atomic rate-bucket writes.
INSERT INTO app.auth_rate_claims(request_id,identity_hash,identity_bucket,ip_bucket,global_bucket,requested_at,hourly_window_ends_at,daily_window_ends_at,identity_limit,ip_limit,global_limit,cooldown_seconds) VALUES('rate-one',repeat('a',64),'identity-a','ip-fixture','global-fixture',unixepoch(),unixepoch()+3600,unixepoch()+86400,10,100,1000,60);
SELECT pg_temp.expect_failure($q$INSERT INTO app.auth_rate_claims(request_id,identity_hash,identity_bucket,ip_bucket,global_bucket,requested_at,hourly_window_ends_at,daily_window_ends_at,identity_limit,ip_limit,global_limit,cooldown_seconds) VALUES('rate-two',repeat('a',64),'identity-a','ip-fixture','global-fixture',app.unixepoch(),app.unixepoch()+3600,app.unixepoch()+86400,10,100,1000,60)$q$,'auth_rate_limited');
SELECT pg_temp.expect_failure($q$INSERT INTO app.auth_rate_claims(request_id,identity_hash,identity_bucket,ip_bucket,global_bucket,requested_at,hourly_window_ends_at,daily_window_ends_at,identity_limit,ip_limit,global_limit,cooldown_seconds,identity_key_id,identity_aliases_json) VALUES('bad-alias',repeat('b',64),'identity-b','ip-fixture','global-fixture',app.unixepoch(),app.unixepoch()+3600,app.unixepoch()+86400,10,100,1000,60,'current-v2','[{"key_id":1,"identity_hash":"bad"}]')$q$,'auth_identity_aliases_invalid');
INSERT INTO app.auth_rate_claims(request_id,identity_hash,identity_bucket,ip_bucket,global_bucket,requested_at,hourly_window_ends_at,daily_window_ends_at,identity_limit,ip_limit,global_limit,cooldown_seconds,identity_key_id,identity_aliases_json) VALUES('rate-three',repeat('b',64),'identity-b','ip-fixture','global-fixture',unixepoch(),unixepoch()+3600,unixepoch()+86400,10,100,1000,60,'current-v2',jsonb_build_array(jsonb_build_object('key_id','current-v2','identity_hash',repeat('b',64)),jsonb_build_object('key_id','legacy-token-hash-v1','identity_hash',repeat('c',64)))::text);
DO $$BEGIN IF (SELECT used FROM app.auth_rate_buckets WHERE bucket_key='ip-fixture')<>2 OR (SELECT count(*) FROM app.auth_identity_rate_aliases WHERE request_id='rate-three')<>2 THEN RAISE EXCEPTION 'Rate admission atomicity/alias capture'; END IF; END$$;

INSERT INTO app.admin_email_otp_challenges(id,user_id,principal_user_id,origin,role,auth_version,challenge_version,account_status,code_hash,created_at,expires_at) VALUES('otp-one','40000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','https://admin.collect.ikanisa.com','owner',1,0,'active',repeat('d',64),unixepoch(),unixepoch()+300);
SELECT pg_temp.expect_failure($q$INSERT INTO app.admin_email_otp_challenges(id,user_id,principal_user_id,origin,role,auth_version,challenge_version,account_status,code_hash,created_at,expires_at) VALUES('otp-two','40000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','https://admin.collect.ikanisa.com','owner',1,0,'active',repeat('d',64),app.unixepoch(),app.unixepoch()+300)$q$,'admin_email_otp_cooldown');
SELECT pg_temp.expect_failure($q$UPDATE app.admin_email_otp_challenges SET role='staff' WHERE id='otp-one'$q$,'immutable_admin_email_otp_identity');

-- Raw receipt retention and processing do not create a financial event.
SELECT pg_temp.seed_storage('sms/raw-one','30000000-0000-4000-8000-000000000002','raw-one',repeat('c',64),'sms_receipt');
INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at) VALUES('raw-one','30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','client-one',repeat('a',64),repeat('b',64),'sms/raw-one',repeat('c',64),20,strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_processing_jobs(raw_sms_id,mode,state,available_at,created_at,updated_at) VALUES('raw-one','live','source_unresolved',unixepoch(),strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT pg_temp.expect_failure($q$UPDATE app.sms_receipts SET body_sha256=repeat('d',64) WHERE id='raw-one'$q$,'immutable_sms_source');
SELECT pg_temp.expect_failure($q$UPDATE app.momo_processing_jobs SET mode='historical' WHERE raw_sms_id='raw-one'$q$,'immutable_momo_source');
SELECT pg_temp.expect_failure($q$INSERT INTO app.momo_processing_guards(id,passed) VALUES('stale-lease',0)$q$,'momo_processing_state');
DO $$BEGIN IF (SELECT count(*) FROM app.ledger_entries)<>2 THEN RAISE EXCEPTION 'Raw capture posted money'; END IF; END$$;

-- Immutable privacy intake and per-subject retention barriers remain real
-- database guards, independently of the new provider's Auth deletion API.
INSERT INTO app.deletion_requests(id,user_id,submission_id,created_at,updated_at) VALUES('privacy-one','30000000-0000-4000-8000-000000000002','privacy-submission',strftime('%Y-%m-%dT%H:%M:%fZ'),strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.privacy_submissions(submission_id,request_id,user_id,originating_session_id,input_sha256,created_at) VALUES('privacy-submission','privacy-one','30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002',repeat('a',64),strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT pg_temp.expect_failure($q$UPDATE app.deletion_requests SET status='completed' WHERE id='privacy-one'$q$,'immutable_privacy_intake');
INSERT INTO app.privacy_retention_plans(id,operation_id,request_id,subject_id,actor_id,session_id,input_sha256,policy_sha256,policy_json,policy_config_revision,source_id,schema_sha256,scope_json,scope_sha256,ledger_sha256,review_revision,created_seconds) VALUES('retention-one','retention-operation','privacy-one','30000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',repeat('a',64),repeat('b',64),'{}',1,repeat('c',64),repeat('d',64),'{}',repeat('e',64),repeat('f',64),0,unixepoch());
INSERT INTO app.privacy_retention_barriers(subject_id,plan_id,source_id,policy_sha256,activated_seconds) VALUES('30000000-0000-4000-8000-000000000002','retention-one',repeat('c',64),repeat('b',64),unixepoch());
SELECT pg_temp.expect_failure($q$UPDATE app.users SET access_status='active' WHERE id='30000000-0000-4000-8000-000000000002'$q$,'privacy_retention_access_quarantined');
SELECT pg_temp.expect_failure($q$INSERT INTO app.notification_devices(id,user_id,token_hash,owner_session_id,provider,token_ciphertext,platform,created_at,updated_at) VALUES('device-one','30000000-0000-4000-8000-000000000002',repeat('a',64),'20000000-0000-4000-8000-000000000002','fcm','{}','android',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'))$q$,'privacy_retention_write_barrier');
SELECT pg_temp.expect_failure($q$DELETE FROM app.privacy_retention_barriers WHERE plan_id='retention-one'$q$,'retention_barrier_requires_separate_recovery_authority');

-- Revoking an approved staff account removes generated grants and revokes its
-- Admin projection; a matching member identity never keeps those grants.
INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at) VALUES('40000000-0000-4000-8000-000000000002','member@example.test','staff','active','!managed-supabase!','Staff',unixepoch(),unixepoch());
INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES('40000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000002','synthetic-fixture',strftime('%Y-%m-%dT%H:%M:%fZ'));
DO $$BEGIN IF NOT EXISTS(SELECT 1 FROM app.admin_grants WHERE user_id='30000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Staff grants not materialized'; END IF; END$$;
UPDATE app.admin_users SET status='revoked',auth_version=auth_version+1 WHERE id='40000000-0000-4000-8000-000000000002';
DO $$BEGIN IF EXISTS(SELECT 1 FROM app.admin_grants WHERE user_id='30000000-0000-4000-8000-000000000002') THEN RAISE EXCEPTION 'Staff grants survived revocation'; END IF; END$$;
UPDATE auth.users SET banned_until=now()+interval '1 hour' WHERE id='10000000-0000-4000-8000-000000000001';
SELECT pg_temp.expect_failure($q$SELECT pg_temp.test_reverse_payment('80000000-0000-4000-8000-000000000001',1,'a0000000-0000-4000-8000-000000000003','fixture')$q$,'session_changed');
ROLLBACK;
