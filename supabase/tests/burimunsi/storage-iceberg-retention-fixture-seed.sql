-- Synthetic-only owner authority for the networkless Iceberg retention fixture.
-- The fixture has no real identities, provider calls or financial records.
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
 SELECT '60000000-0000-4000-8000-000000000004',id::uuid,'otp',to_timestamp(auth_at),to_timestamp(auth_at)
 FROM app.auth_sessions WHERE id='60000000-0000-4000-8000-000000000002';
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','admin_users.manage'),('owner','receivers.manage'),('owner','payments.reconcile') ON CONFLICT DO NOTHING;
INSERT INTO app.admin_grants(user_id,permission,granted_by,granted_at)
 VALUES('synthetic-owner','admin_users.manage','synthetic-only','2026-01-01'),('synthetic-owner','receivers.manage','synthetic-only','2026-01-01'),
 ('synthetic-owner','payments.reconcile','synthetic-only','2026-01-01');
INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)
 SELECT 'synthetic-email-challenge',encode(sha256(convert_to('email:owner@synthetic.invalid','UTF8')),'hex'),'email','owner@synthetic.invalid','admin',0,
 auth_at-1,auth_at+299,1,auth_at,'accepted'
 FROM app.auth_sessions WHERE id='60000000-0000-4000-8000-000000000002';
INSERT INTO app.admin_account_role_capabilities(role,permission) VALUES('owner','privacy.review') ON CONFLICT DO NOTHING;
INSERT INTO app.admin_grants(user_id,permission,granted_by,granted_at) VALUES('synthetic-owner','privacy.review','synthetic-only','2026-01-01');
INSERT INTO app.users(id,email,full_name,public_id,member_type,created_at,updated_at)
 VALUES('b0000000-0000-4000-8000-000000000001','subject@synthetic.invalid','Synthetic Subject','900002','operator','2026-01-01','2026-01-01');
INSERT INTO app.deletion_requests(id,user_id,submission_id,reason,created_at,updated_at)
 VALUES('b0000000-0000-4000-8000-000000000002','b0000000-0000-4000-8000-000000000001','b0000000-0000-4000-8000-000000000005','synthetic','2026-01-01','2026-01-01');
COMMIT;
