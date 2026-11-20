-- Disposable schema clone only. The native-capture FK graph and immutable
-- storage are represented by synthetic rows, and the custody snapshot is a
-- test double. This isolates the work/lease contract; it does not prove custody.
BEGIN;
SET LOCAL session_replication_role=replica;
INSERT INTO private.collect_owner_identity(singleton,operation_id,admin_user_id,principal_user_id,owner_email,approval_reference)
 VALUES(true,'10000000-0000-4000-8000-000000000001','synthetic-admin','synthetic-owner','owner@synthetic.invalid','synthetic-only-owner');
INSERT INTO app.users(id,email,full_name,public_id,member_type,created_at,updated_at)
 VALUES('synthetic-owner','owner@synthetic.invalid','Synthetic Owner','900001','operator','2026-01-01','2026-01-01');
INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at)
 VALUES('synthetic-admin','owner@synthetic.invalid','owner','active','synthetic','Synthetic Owner',1,1);
INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)
 VALUES('synthetic-admin','synthetic-owner','synthetic-only','2026-01-01');
INSERT INTO auth.users(id,email,email_confirmed_at,is_anonymous)
 VALUES('60000000-0000-4000-8000-000000000001','owner@synthetic.invalid',now(),false);
INSERT INTO auth.sessions(id,user_id,aal,not_after)
 VALUES('60000000-0000-4000-8000-000000000002','60000000-0000-4000-8000-000000000001','aal1',now()+interval '1 hour');
INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)
 VALUES('60000000-0000-4000-8000-000000000001','synthetic-owner','synthetic-only');
INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)
 VALUES('60000000-0000-4000-8000-000000000002','synthetic-owner','admin',app.unixepoch(),app.unixepoch(),app.unixepoch()+3500);
INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
 VALUES(repeat('a',64),'60000000-0000-4000-8000-000000000003','synthetic-admin',1,
 '60000000-0000-4000-8000-000000000002','https://admin.synthetic.invalid',app.unixepoch(),app.unixepoch()+3500);
INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext)
 VALUES(repeat('a',64),'60000000-0000-4000-8000-000000000001','60000000-0000-4000-8000-000000000002','{}');
INSERT INTO auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at)
 VALUES('60000000-0000-4000-8000-000000000004','60000000-0000-4000-8000-000000000002','otp',now(),now());
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','admin_users.manage'),('owner','receivers.manage'),('owner','payments.reconcile') ON CONFLICT DO NOTHING;
INSERT INTO app.admin_grants(user_id,permission,granted_by,granted_at)
 VALUES('synthetic-owner','admin_users.manage','synthetic-only','2026-01-01'),('synthetic-owner','receivers.manage','synthetic-only','2026-01-01'),
 ('synthetic-owner','payments.reconcile','synthetic-only','2026-01-01');
INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)
 VALUES('synthetic-email-challenge',encode(sha256(convert_to('email:owner@synthetic.invalid','UTF8')),'hex'),'email','owner@synthetic.invalid','admin',0,
 app.unixepoch()-1,app.unixepoch()+299,1,app.unixepoch(),'accepted');
INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)
 VALUES('synthetic-group','synthetic-group','synthetic-owner','Synthetic Group','community','2026-01-01','2026-01-01');
INSERT INTO app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,timezone,profile_status,profile_version,profile_json,created_at)
 VALUES('synthetic-wallet','mtn_momo','00000','Synthetic Receiver',repeat('a',64),'Africa/Kigali','approved','synthetic-profile','{"synthetic":true}','2026-01-01');
INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at)
 VALUES('synthetic-group','synthetic-wallet',true,1);
INSERT INTO private.burimunsi_integration_policies(collection_id,approved_version,approved_by,approved_at,expires_at,source_reference,
 native_parser_version,provider_profile_version,provider_profile_sha256,identity_enabled,processing_enabled,scheduler_enabled)
 VALUES('synthetic-group','synthetic-policy','synthetic-owner',1,9000000000000,'synthetic-only',
 'synthetic-parser','synthetic-profile',encode(sha256(convert_to('{"synthetic":true}','UTF8')),'hex'),true,true,true);
INSERT INTO private.burimunsi_observation_requests(source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,
 native_session_id,request_id,fingerprint,initial_profile_version,initial_profile_sha256,initial_profile_tuple_sha256,initial_consent_generation,created_at,
 source_key,source_key_content_sha256,source_key_body_sha256)
 SELECT source,'synthetic-group','20000000-0000-4000-8000-000000000001'::uuid,'synthetic-owner',
 '20000000-0000-4000-8000-000000000002'::uuid,'20000000-0000-4000-8000-000000000003'::uuid,1,
 '20000000-0000-4000-8000-000000000004'::uuid,request::uuid,repeat('f',64),'synthetic-profile',repeat('d',64),repeat('e',64),1,1,
 CASE WHEN legacy THEN NULL WHEN right(source,1)='3' THEN repeat('9',64) ELSE repeat('b',64) END,CASE WHEN legacy THEN NULL ELSE repeat('c',64) END,CASE WHEN legacy THEN NULL ELSE repeat('d',64) END
 FROM (VALUES('30000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001',false),
             ('30000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000002',true),
             ('30000000-0000-4000-8000-000000000003','40000000-0000-4000-8000-000000000003',false)) v(source,request,legacy);
INSERT INTO private.burimunsi_unresolved_observations(source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,
 native_session_id,request_id,fingerprint,body_sha256,object_key,object_sha256,size_bytes,profile_version,profile_sha256,profile_tuple_sha256,consent_generation,created_at)
 SELECT source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,native_session_id,request_id,fingerprint,
 repeat('d',64),'sms/'||source_id,repeat('e',64),100,'synthetic-profile',repeat('d',64),repeat('e',64),1,1
 FROM private.burimunsi_observation_requests WHERE collection_id='synthetic-group';
INSERT INTO app.sms_receipts(id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,created_at)
 SELECT source_id,principal_user_id,NULL,request_id::text,body_sha256,NULL,object_key,object_sha256,size_bytes,'2026-01-01'
 FROM private.burimunsi_unresolved_observations WHERE collection_id='synthetic-group';
INSERT INTO private.burimunsi_native_receipt_origins(source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,
 capture_session_id,admitting_session_id,admission_kind,request_id,fingerprint,body_sha256,object_sha256)
 SELECT source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,native_session_id,native_session_id,
 'native_actor',request_id,fingerprint,body_sha256,object_sha256 FROM private.burimunsi_unresolved_observations WHERE collection_id='synthetic-group';
INSERT INTO app.momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,currency_scale,
 transaction_timezone,transaction_time_source,parse_attempt_id,mode,allocation_state,created_at,updated_at)
 SELECT source_id,'synthetic-wallet','mtn_momo','synthetic-ref-'||right(source_id,1),'incoming_receipt',100,'RWF',0,'Africa/Kigali',
 'missing_provider_time','synthetic-attempt-'||right(source_id,1),'historical',CASE WHEN right(source_id,1)='3' THEN 'linked' ELSE 'unallocated' END,'2026-01-01','2026-01-01'
 FROM private.burimunsi_unresolved_observations WHERE collection_id='synthetic-group';
INSERT INTO private.burimunsi_transaction_scopes(transaction_id,collection_id,receiving_account_id,source_binding_id,source_binding_version,policy_version,created_at,native_source_id)
 SELECT id,'synthetic-group','synthetic-wallet',NULL,NULL,'native.auto.v1',1,id FROM app.momo_transactions WHERE receiving_account_id='synthetic-wallet';
INSERT INTO private.burimunsi_auto_sms_jobs(source_id,collection_id,receiving_account_id,source_fingerprint,profile_sha256,state,phase,
 attempt_id,transaction_id,facts_sha256,relation,payment_outcome,created_at,updated_at)
 SELECT source_id,'synthetic-group','synthetic-wallet',fingerprint,repeat('d',64),'completed','finished',
 ('50000000-0000-4000-8000-00000000000'||right(source_id,1))::uuid,source_id,repeat('1',64),'accepted','successful',1,1
 FROM private.burimunsi_unresolved_observations WHERE collection_id='synthetic-group';
-- One already-posted synthetic ledger row is a readback fixture only; the
-- work functions must neither create a credit nor allow it to be counted twice.
INSERT INTO app.payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,amount_minor,currency,observed_at,created_at)
 VALUES('synthetic-evidence','synthetic-group','synthetic-owner','synthetic/evidence',repeat('e',64),100,'application/octet-stream','operator_recorded','synthetic-reference',100,'RWF','2026-01-01','2026-01-01');
INSERT INTO app.payments(id,collection_id,member_id,evidence_id,amount_minor,currency,rail,status,created_at)
 VALUES('synthetic-payment','synthetic-group','synthetic-owner','synthetic-evidence',100,'RWF','rwanda_momo','confirmed','2026-01-01');
INSERT INTO app.momo_financial_links(transaction_id,payment_id,beneficiary_member_id,linked_by,reason,historical_existing,created_at)
 VALUES('30000000-0000-4000-8000-000000000003','synthetic-payment','synthetic-owner','synthetic-owner','synthetic-fixture',0,'2026-01-01');
INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,currency,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at)
 VALUES('synthetic-ledger','synthetic-payment','synthetic-group','synthetic-owner','RWF',100,'contribution','synthetic-evidence','synthetic-owner','synthetic-ledger-request','2026-01-01');
-- Only this underlying custody/consent snapshot is substituted in the
-- disposable fixture. The new source join, keys, fence and lease SQL are real.
CREATE OR REPLACE FUNCTION private.burimunsi_auto_snapshot(p_source text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE calls integer:=coalesce(nullif(current_setting('fixture.source_calls',true),''),'0')::integer+1;
BEGIN
 PERFORM set_config('fixture.source_calls',calls::text,true);
 IF current_setting('fixture.source_signal_at',true)=calls::text THEN
  PERFORM pg_advisory_xact_lock(current_setting('fixture.source_signal_key',true)::bigint);END IF;
 IF current_setting('fixture.source_delay_at',true)=calls::text THEN PERFORM pg_sleep(2.5);END IF;
 IF current_setting('fixture.source_revoked',true)='true' THEN RAISE EXCEPTION 'synthetic_source_revoked' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('kind','jobs','proof',jsonb_build_object('sourceId',p_source));
END;$fn$;
COMMIT;
