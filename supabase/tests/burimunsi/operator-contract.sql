-- SQL guard/RLS/idempotency checks only; fixture accounts were never created by
-- GoTrue. This complete transaction rolls back every negative mutation.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000001',
 'session_id','f2000000-0000-4000-8000-000000000001','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
CREATE FUNCTION pg_temp.expect_state(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
 BEGIN EXECUTE statement;
 EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=expected THEN RETURN;END IF;
  RAISE EXCEPTION 'Wrong qualification SQLSTATE %, expected %: %',SQLSTATE,expected,SQLERRM;
 END;
 RAISE EXCEPTION 'Expected qualification SQLSTATE %',expected;
END;$fn$;
DO $contract$
DECLARE t text;r text;before_count bigint;receipt jsonb;again jsonb;directory jsonb;parent record;
BEGIN
 FOREACH t IN ARRAY ARRAY['burimunsi_scopes','burimunsi_accounts','burimunsi_device_grants','burimunsi_device_accounts',
  'burimunsi_sessions','burimunsi_rate_limits','burimunsi_command_receipts','burimunsi_audit','burimunsi_transaction_scopes',
  'burimunsi_receipt_jobs','burimunsi_rematch_jobs','burimunsi_session_links','burimunsi_integration_policies',
  'burimunsi_identity_proofs','burimunsi_worker_grants','burimunsi_schedulers','burimunsi_operator_approvals','burimunsi_owner_commands'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=('private.'||t)::regclass AND tgname='collect_fence_statement_v1' AND tgenabled='A') THEN
   RAISE EXCEPTION 'Missing native ALWAYS fence: %',t;
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
   IF has_table_privilege(r,'private.'||t,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') THEN
    RAISE EXCEPTION 'Private native table privilege leak: % %',t,r;
   END IF;
  END LOOP;
 END LOOP;
 IF has_table_privilege('collect_runtime','private.burimunsi_operator_approvals','INSERT,DELETE,TRUNCATE')
  OR has_column_privilege('collect_runtime','private.burimunsi_operator_approvals','active','UPDATE')
  OR has_column_privilege('collect_runtime','private.burimunsi_operator_approvals','capabilities','UPDATE')
  OR NOT has_column_privilege('collect_runtime','private.burimunsi_operator_approvals','lock_anchor','UPDATE') THEN
  RAISE EXCEPTION 'Owner-only approval privilege boundary failed';
 END IF;
 SELECT * INTO STRICT parent FROM private.burimunsi_managed_admin_snapshot();
 PERFORM private.set_admin_email_context(parent.admin_id,parent.cookie_hash,parent.origin,parent.public_session_id);
 IF private.assert_actor('payments.reconcile',NULL,NULL,2,300)<>'f3000000-0000-4000-8000-000000000001' THEN
  RAISE EXCEPTION 'Real parent context not restored';
 END IF;
 before_count:=(SELECT count(*) FROM private.burimunsi_owner_commands);
 receipt:=private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
  'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group','f6000000-0000-4000-8000-000000000002',
  'f4000000-0000-4000-8000-000000000002','+250780000002','staff',ARRAY['members.enroll','records.read'],true,0);
 again:=private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
  'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group','f6000000-0000-4000-8000-000000000002',
  'f4000000-0000-4000-8000-000000000002','+250780000002','staff',ARRAY['records.read','members.enroll'],true,0);
 IF receipt<>again OR before_count<>(SELECT count(*) FROM private.burimunsi_owner_commands)
  OR (SELECT version FROM private.burimunsi_operator_approvals WHERE phone='+250780000002')<>1 THEN
  RAISE EXCEPTION 'Approval replay mutated state';
 END IF;
 directory:=private.burimunsi_operator_directory('f4000000-0000-4000-8000-000000000001',repeat('a',64),
  'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group','f6000000-0000-4000-8000-000000000002');
 IF directory->>'found'<>'true' OR directory->'receipt'<>receipt THEN RAISE EXCEPTION 'Retained approval outcome missing';END IF;
END;$contract$;
SELECT pg_temp.expect_state($q$SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group','f6000000-0000-4000-8000-000000000002',
 'f4000000-0000-4000-8000-000000000002','+250780000009','staff',ARRAY['records.read','members.enroll'],true,0)$q$,'23505');
SELECT pg_temp.expect_state($q$SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group','f6000000-0000-4000-8000-000000000009',
 'f4000000-0000-4000-8000-000000000002','+250780000002','staff',ARRAY['records.read'],true,0)$q$,'40001');
SELECT pg_temp.expect_state($q$UPDATE private.burimunsi_accounts SET capabilities=ARRAY['records.read','payments.allocate']
 WHERE principal_user_id='f3000000-0000-4000-8000-000000000002'$q$,'42501');
SELECT pg_temp.expect_state($q$UPDATE private.burimunsi_operator_approvals SET principal_user_id='another',version=version+1
 WHERE phone='+250780000002'$q$,'23514');
SELECT pg_temp.expect_state($q$DELETE FROM private.burimunsi_owner_commands$q$,'55000');
-- A changed owner approval revokes already issued native sessions atomically,
-- without revoking the independent device grant or genuine shared Auth session.
INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,created_at)
 VALUES('f9000000-0000-4000-8000-000000000001','buri-qualification-group',
 'f9000000-0000-4000-8000-000000000002',repeat('d',64),'staff',1);
INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id)
 VALUES('f9000000-0000-4000-8000-000000000001','f7000000-0000-4000-8000-000000000002','buri-qualification-group');
INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,
 credential_version,grant_version,token_hash,created_at,expires_at,principal_user_id)
 VALUES('f9000000-0000-4000-8000-000000000003','buri-qualification-group','f7000000-0000-4000-8000-000000000002',
 'f9000000-0000-4000-8000-000000000001','f9000000-0000-4000-8000-000000000002',1,1,repeat('e',64),1,9007199254740991,
 'f3000000-0000-4000-8000-000000000002');
SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000001',repeat('a',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000001','buri-qualification-group','f6000000-0000-4000-8000-000000000003',
 'f4000000-0000-4000-8000-000000000002','+250780000002','staff',ARRAY['records.read'],true,1);
DO $revocation$
BEGIN
 IF (SELECT revoked FROM private.burimunsi_sessions WHERE id='f9000000-0000-4000-8000-000000000003') IS DISTINCT FROM true
  OR (SELECT active FROM private.burimunsi_device_grants WHERE id='f9000000-0000-4000-8000-000000000001') IS DISTINCT FROM true
  OR (SELECT revoked_at FROM app.auth_sessions WHERE id='f2000000-0000-4000-8000-000000000002') IS NOT NULL THEN
  RAISE EXCEPTION 'Approval revocation crossed native/shared authority boundary';
 END IF;
END;$revocation$;
-- Revocation and a missing fresh-email proof are checked against the real SQL
-- context. This does not fabricate a new MFA assertion for native financial work.
SELECT set_config('request.jwt.claims',jsonb_build_object('sub','f1000000-0000-4000-8000-000000000002',
 'session_id','f2000000-0000-4000-8000-000000000002','role','authenticated','aal','aal1','exp',app.unixepoch()+600)::text,true);
SELECT private.set_admin_email_context('f4000000-0000-4000-8000-000000000002',repeat('b',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000002');
SELECT pg_temp.expect_state($q$SELECT private.assert_actor('payments.reconcile',NULL,NULL,2,300)$q$,'42501');
SELECT pg_temp.expect_state($q$SELECT private.burimunsi_operator_approve('f4000000-0000-4000-8000-000000000002',repeat('b',64),
 'https://admin.collect.example','f5000000-0000-4000-8000-000000000002','buri-qualification-group','f6000000-0000-4000-8000-000000000008',
 'f4000000-0000-4000-8000-000000000002','+250780000002','staff',ARRAY['records.read'],true,1)$q$,'42501');
RESET ROLE;
UPDATE app.admin_users SET status='revoked',auth_version=auth_version+1 WHERE id='f4000000-0000-4000-8000-000000000002';
DO $revoked$
BEGIN
 IF EXISTS(SELECT 1 FROM private.burimunsi_managed_admin_snapshot()) OR
  private.burimunsi_operator_is_current('buri-qualification-group','f3000000-0000-4000-8000-000000000002','+250780000002','staff',ARRAY['records.read']) THEN
  RAISE EXCEPTION 'Revoked shared operator still has native access';
 END IF;
END;$revoked$;
ROLLBACK;
