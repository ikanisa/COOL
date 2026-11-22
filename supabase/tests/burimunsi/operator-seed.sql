-- QUALIFICATION ONLY. Synthetic identities on the real retained Supabase schema.
-- The harness creates a separate disposable, network-isolated test database.
-- These are SQL fixtures, not GoTrue signups, email delivery or production grants.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);
INSERT INTO auth.users(id,email,email_confirmed_at,is_anonymous) VALUES
 ('f1000000-0000-4000-8000-000000000001','info@ikanisa.com',now(),false),
 ('f1000000-0000-4000-8000-000000000002','buri-staff@example.invalid',now(),false);
INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES
 ('f2000000-0000-4000-8000-000000000001','f1000000-0000-4000-8000-000000000001','aal1',now()+interval '1 hour'),
 ('f2000000-0000-4000-8000-000000000002','f1000000-0000-4000-8000-000000000002','aal1',now()+interval '1 hour');
INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at) VALUES
 ('f3000000-0000-4000-8000-000000000001','info@ikanisa.com','000001','QUALIFICATION Owner','operator',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('f3000000-0000-4000-8000-000000000002','buri-staff@example.invalid','000002','QUALIFICATION Staff','operator',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES
 ('f1000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','synthetic-buri-native-schema-qualification'),
 ('f1000000-0000-4000-8000-000000000002','f3000000-0000-4000-8000-000000000002','synthetic-buri-native-schema-qualification');
INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at) VALUES
 ('f2000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','admin',app.unixepoch()-10,app.unixepoch()-10,app.unixepoch()+3500),
 ('f2000000-0000-4000-8000-000000000002','f3000000-0000-4000-8000-000000000002','admin',app.unixepoch()-10,app.unixepoch()-10,app.unixepoch()+3500);
INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at) VALUES
 ('f4000000-0000-4000-8000-000000000001','info@ikanisa.com','owner','active','supabase-managed','QUALIFICATION Owner',app.unixepoch(),app.unixepoch()),
 ('f4000000-0000-4000-8000-000000000002','buri-staff@example.invalid','staff','active','supabase-managed','QUALIFICATION Staff',app.unixepoch(),app.unixepoch());
INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES
 ('f4000000-0000-4000-8000-000000000001','f3000000-0000-4000-8000-000000000001','synthetic-qualification',app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('f4000000-0000-4000-8000-000000000002','f3000000-0000-4000-8000-000000000002','synthetic-qualification',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
 SELECT repeat('a',64),'f5000000-0000-4000-8000-000000000001','f4000000-0000-4000-8000-000000000001',1,id,'https://admin.collect.example',auth_at,expires_at
 FROM app.auth_sessions WHERE id='f2000000-0000-4000-8000-000000000001';
INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
 SELECT repeat('b',64),'f5000000-0000-4000-8000-000000000002','f4000000-0000-4000-8000-000000000002',1,id,'https://admin.collect.example',auth_at,expires_at
 FROM app.auth_sessions WHERE id='f2000000-0000-4000-8000-000000000002';
INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext) VALUES
 (repeat('a',64),'f1000000-0000-4000-8000-000000000001','f2000000-0000-4000-8000-000000000001','{}'),
 (repeat('b',64),'f1000000-0000-4000-8000-000000000002','f2000000-0000-4000-8000-000000000002','{}');
INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at) VALUES
 ('buri-qualification-group','buri-qualification-group','f3000000-0000-4000-8000-000000000001','QUALIFICATION ONLY','community',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_receiving_accounts(id,provider,public_code,recipient_name,receiver_hash,timezone,created_at) VALUES
 ('buri-qualification-wallet','mtn_momo','00000','QUALIFICATION ONLY',repeat('c',64),'Africa/Kigali',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.burimunsi_scopes(collection_id,receiving_account_id,enabled,created_at)
 VALUES('buri-qualification-group','buri-qualification-wallet',true,floor(extract(epoch FROM clock_timestamp())*1000)::bigint);
SELECT set_config('collect.edge_verified','true',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600,
 'amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',auth_at)))::text,true)
 FROM app.auth_sessions WHERE id='f2000000-0000-4000-8000-000000000001';
INSERT INTO auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at)
 SELECT 'f8000000-0000-4000-8000-000000000001'::uuid,id::uuid,'otp',to_timestamp(auth_at),to_timestamp(auth_at)
 FROM app.auth_sessions WHERE id='f2000000-0000-4000-8000-000000000001';
INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)
 SELECT 'buri-qualification-email',encode(sha256(convert_to('email:info@ikanisa.com','UTF8')),'hex'),'email','info@ikanisa.com','admin',0,
 auth_at-1,auth_at+299,1,auth_at,'accepted' FROM app.auth_sessions WHERE id='f2000000-0000-4000-8000-000000000001';
SELECT private.admin_email_record_initial('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-email');
SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group','f6000000-0000-4000-8000-000000000001',
 'f4000000-0000-4000-8000-000000000001','+250780000001','admin',
 ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],true,0);
SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group','f6000000-0000-4000-8000-000000000002',
 'f4000000-0000-4000-8000-000000000002','+250780000002','staff',ARRAY['records.read','members.enroll'],true,0);
INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at) VALUES
 ('f7000000-0000-4000-8000-000000000001','buri-qualification-group','f3000000-0000-4000-8000-000000000001','+250780000001','QUALIFICATION Owner','admin',
 ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage'],'{"qualification_only":true}',1,1),
 ('f7000000-0000-4000-8000-000000000002','buri-qualification-group','f3000000-0000-4000-8000-000000000002','+250780000002','QUALIFICATION Staff','staff',
 ARRAY['records.read','members.enroll'],'{"qualification_only":true}',1,1);
DO $check$
BEGIN
 IF (SELECT count(*) FROM private.burimunsi_owner_commands)<>2 OR (SELECT count(*) FROM app.ledger_entries)<>0
  OR (SELECT count(*) FROM auth.users)<>2 OR (SELECT count(*) FROM private.burimunsi_accounts)<>2 THEN
  RAISE EXCEPTION 'qualification_seed_mismatch';
 END IF;
END;$check$;
COMMIT;
