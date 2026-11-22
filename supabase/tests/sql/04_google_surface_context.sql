BEGIN;
SET LOCAL search_path=app,pg_catalog;
CREATE FUNCTION pg_temp.expect_failure(statement text,expected text) RETURNS void LANGUAGE plpgsql AS $$BEGIN
 BEGIN EXECUTE statement;EXCEPTION WHEN OTHERS THEN IF position(expected IN SQLERRM)>0 THEN RETURN;ELSE RAISE EXCEPTION 'Wrong failure %, expected %',SQLERRM,expected;END IF;END;
 RAISE EXCEPTION 'Expected failure %',expected;
END$$;
INSERT INTO app.auth_google_flows(id,state_hash,nonce,provider_verifier,client_challenge,client_state,registration_allowed,created_at,expires_at,status)
 VALUES('synthetic-admin-flow',repeat('a',64),'synthetic-nonce','{}',repeat('b',43),'synthetic-state',0,unixepoch(),unixepoch()+300,'pending'),('synthetic-member-flow',repeat('c',64),'synthetic-nonce','{}',repeat('d',43),'synthetic-state',0,unixepoch(),unixepoch()+300,'pending');
SELECT pg_temp.expect_failure($q$INSERT INTO private.google_flow_context(flow_id,surface) VALUES('synthetic-admin-flow','admin')$q$,'check constraint');
INSERT INTO private.google_flow_context(flow_id,surface,request_origin) VALUES('synthetic-admin-flow','admin','https://synthetic-admin.example'),('synthetic-member-flow','member',NULL);
SELECT pg_temp.expect_failure($q$UPDATE private.google_flow_context SET surface='member' WHERE flow_id='synthetic-admin-flow'$q$,'immutable_google_flow_context');
SELECT pg_temp.expect_failure($q$UPDATE private.google_flow_context SET request_origin='https://different.example' WHERE flow_id='synthetic-admin-flow'$q$,'immutable_google_flow_context');
SELECT pg_temp.expect_failure($q$DELETE FROM private.google_flow_context WHERE flow_id='synthetic-admin-flow'$q$,'immutable_google_flow_context');
INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status) VALUES('synthetic-managed-otp',repeat('a',64),'email','synthetic@example.test','member',0,unixepoch(),unixepoch()+300,'accepted');
SELECT pg_temp.expect_failure($q$UPDATE private.supabase_otp_challenges SET identity_value='different@example.test' WHERE id='synthetic-managed-otp'$q$,'immutable_managed_otp_identity');
UPDATE private.supabase_otp_challenges SET attempts=1,consumed_at=unixepoch() WHERE id='synthetic-managed-otp';
SELECT pg_temp.expect_failure($q$UPDATE private.supabase_otp_challenges SET attempts=0 WHERE id='synthetic-managed-otp'$q$,'managed_otp_state_regression');
SELECT pg_temp.expect_failure($q$UPDATE private.supabase_otp_challenges SET consumed_at=NULL WHERE id='synthetic-managed-otp'$q$,'managed_otp_state_regression');
SELECT pg_temp.expect_failure($q$DELETE FROM private.supabase_otp_challenges WHERE id='synthetic-managed-otp'$q$,'retain_managed_otp_admission');
SET LOCAL ROLE collect_runtime;
DO $$BEGIN IF (SELECT surface FROM private.google_flow_context WHERE flow_id='synthetic-admin-flow')<>'admin' THEN RAISE EXCEPTION 'Runtime context lookup failed';END IF;END$$;
SELECT pg_temp.expect_failure($q$UPDATE private.google_flow_context SET surface='member' WHERE flow_id='synthetic-admin-flow'$q$,'permission denied');
RESET ROLE;
ROLLBACK;
