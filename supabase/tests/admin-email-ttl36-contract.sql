-- Disposable retained-QA database only. Synthetic managed Auth rows are SQL
-- fixtures, not provider signups, delivery, CAPTCHA or production acceptance.
-- Root first commits a genuine http_admin admission for this actual QA source.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SET LOCAL statement_timeout='45s';
SET LOCAL lock_timeout='5s';
DO $frame$
BEGIN
 IF current_database()!~'^collect_burimunsi_[a-f0-9]{24}_test$' OR current_user<>'postgres' THEN
  RAISE EXCEPTION 'disposable_QA_database_required';END IF;
 PERFORM pg_advisory_xact_lock_shared(7346371,1);
 PERFORM set_config('collect.edge_verified','true',true);
 PERFORM set_config('collect.fence_admission_id','__ADMISSION_ID__',true);
 PERFORM set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true);
 PERFORM set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true);
END;$frame$;
SET LOCAL ROLE collect_runtime;
DO $work$ BEGIN
 PERFORM private.collect_fence_assert_work('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__,'__ADMISSION_SOURCE__');
END;$work$;
RESET ROLE;

CREATE FUNCTION pg_temp.ttl36_require(p_ok boolean,p_label text) RETURNS void
 LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'TTL36 qualification: %',p_label;END IF;END$$;
CREATE FUNCTION pg_temp.ttl36_expect(p_sql text,p_state text) RETURNS void
 LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
 BEGIN EXECUTE p_sql;EXCEPTION WHEN OTHERS THEN
  IF SQLSTATE=p_state THEN RETURN;END IF;RAISE;END;
 RAISE EXCEPTION 'TTL36 expected SQLSTATE %',p_state;
END$$;
CREATE FUNCTION pg_temp.ttl36_claims(p_session text,p_at bigint) RETURNS void
 LANGUAGE plpgsql SECURITY INVOKER AS $$
BEGIN
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub','e1360000-0000-4000-8000-000000000001',
  'session_id',p_session,'role','authenticated','aal','aal1','exp',app.unixepoch()+3600,
  'amr',jsonb_build_array(jsonb_build_object('method','otp','timestamp',p_at)))::text,true);
END$$;
CREATE FUNCTION pg_temp.ttl36_prepare(p_id text,p_ttl integer) RETURNS jsonb
 LANGUAGE sql SECURITY INVOKER AS $$
 SELECT private.admin_email_prepare('e4360000-0000-4000-8000-000000000001',repeat('6',64),
  'https://admin.collect.example','e5360000-0000-4000-8000-000000000001',p_id,p_ttl)
$$;

INSERT INTO auth.users(id,email,email_confirmed_at,is_anonymous)
 VALUES('e1360000-0000-4000-8000-000000000001','ttl36-admin@example.invalid',now(),false);
INSERT INTO auth.sessions(id,user_id,aal,not_after) VALUES
 ('e2360000-0000-4000-8000-000000000001','e1360000-0000-4000-8000-000000000001','aal1',now()+interval '1 hour'),
 ('e2360000-0000-4000-8000-000000000002','e1360000-0000-4000-8000-000000000001','aal1',now()+interval '1 hour'),
 ('e2360000-0000-4000-8000-000000000003','e1360000-0000-4000-8000-000000000001','aal1',now()+interval '1 hour');
INSERT INTO app.users(id,email,public_id,full_name,member_type,created_at,updated_at)
 VALUES('e3360000-0000-4000-8000-000000000001','ttl36-admin@example.invalid','360001','QUALIFICATION TTL36','operator',
  app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference)
 VALUES('e1360000-0000-4000-8000-000000000001','e3360000-0000-4000-8000-000000000001','synthetic-TTL36-only');
INSERT INTO app.auth_sessions(id,user_id,surface,auth_at,created_at,expires_at)
 SELECT 'e2360000-0000-4000-8000-'||lpad(n::text,12,'0'),'e3360000-0000-4000-8000-000000000001','admin',
  app.unixepoch()-CASE WHEN n=3 THEN 400 ELSE 0 END,app.unixepoch()-CASE WHEN n=3 THEN 400 ELSE 0 END,
  app.unixepoch()+3500 FROM unnest(ARRAY[1,3]) n;
INSERT INTO auth.mfa_amr_claims(id,session_id,authentication_method,created_at,updated_at)
 SELECT ('e8360000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
  ('e2360000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,'otp',
  to_timestamp(s.auth_at),to_timestamp(s.auth_at)
 FROM generate_series(1,3) n JOIN app.auth_sessions s
  ON s.id='e2360000-0000-4000-8000-'||lpad(CASE WHEN n=3 THEN '3' ELSE '1' END,12,'0');
INSERT INTO app.admin_users(id,email,role,status,password_hash,display_name,created_at,updated_at)
 VALUES('e4360000-0000-4000-8000-000000000001','ttl36-admin@example.invalid','admin','active','supabase-managed',
  'QUALIFICATION TTL36',app.unixepoch(),app.unixepoch());
INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at)
 VALUES('e4360000-0000-4000-8000-000000000001','e3360000-0000-4000-8000-000000000001','synthetic-TTL36-only',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.admin_sessions(token_hash,public_id,user_id,auth_version,auth_session_id,origin,created_at,expires_at)
 SELECT repeat(CASE WHEN n=1 THEN '6' ELSE '7' END,64),'e5360000-0000-4000-8000-'||lpad(n::text,12,'0'),
  'e4360000-0000-4000-8000-000000000001',1,s.id,'https://admin.collect.example',s.auth_at,s.expires_at
 FROM unnest(ARRAY[1,3]) n JOIN app.auth_sessions s ON s.id='e2360000-0000-4000-8000-'||lpad(n::text,12,'0');
INSERT INTO private.bff_sessions(token_hash,auth_user_id,auth_session_id,token_ciphertext) VALUES
 (repeat('6',64),'e1360000-0000-4000-8000-000000000001','e2360000-0000-4000-8000-000000000001','{}'),
 (repeat('7',64),'e1360000-0000-4000-8000-000000000001','e2360000-0000-4000-8000-000000000003','{}');
DO $$BEGIN PERFORM pg_temp.ttl36_claims('e2360000-0000-4000-8000-000000000001',
 (SELECT auth_at FROM app.auth_sessions WHERE id='e2360000-0000-4000-8000-000000000001'));END$$;

SET LOCAL ROLE collect_runtime;
SAVEPOINT new_deadline;
DO $positive$
DECLARE r jsonb;again jsonb;n bigint;
BEGIN
 r:=pg_temp.ttl36_prepare('e6360000-0000-4000-8000-000000000001',1800);
 PERFORM pg_temp.ttl36_require((r->'challenge'->>'expires_at')::bigint-(r->'challenge'->>'created_at')::bigint=1800,'actual server deadline is1800');
 PERFORM pg_temp.ttl36_require((r->'challenge'->>'expires_at')::bigint-app.unixepoch() BETWEEN 1798 AND 1800,'truthful remaining deadline');
 again:=pg_temp.ttl36_prepare('e6360000-0000-4000-8000-000000000001',60);
 PERFORM pg_temp.ttl36_require(again->'challenge'=r->'challenge','original reservation is not shortened/extended or replayed');
 SELECT count(*) INTO n FROM private.supabase_otp_challenges;
 PERFORM pg_temp.ttl36_expect($q$SELECT pg_temp.ttl36_prepare('e6360000-0000-4000-8000-000000000099',59)$q$,'22023');
 PERFORM pg_temp.ttl36_expect($q$SELECT pg_temp.ttl36_prepare('e6360000-0000-4000-8000-000000000099',1801)$q$,'22023');
 PERFORM pg_temp.ttl36_expect($q$SELECT pg_temp.ttl36_prepare('e6360000-0000-4000-8000-000000000099',NULL)$q$,'22023');
 PERFORM pg_temp.ttl36_require((SELECT count(*)=n FROM private.supabase_otp_challenges),'invalid policy has no reservation effects');
END;$positive$;
ROLLBACK TO new_deadline;
SAVEPOINT old_deadline;
DO $$DECLARE r jsonb;BEGIN
 r:=private.admin_email_prepare('e4360000-0000-4000-8000-000000000001',repeat('6',64),
  'https://admin.collect.example','e5360000-0000-4000-8000-000000000001','e6360000-0000-4000-8000-000000000002');
 PERFORM pg_temp.ttl36_require((r->'challenge'->>'expires_at')::bigint-(r->'challenge'->>'created_at')::bigint=300,'old overload stays300');
END$$;
ROLLBACK TO old_deadline;
SAVEPOINT lower_bound;
DO $$DECLARE r jsonb;BEGIN
 r:=pg_temp.ttl36_prepare('e6360000-0000-4000-8000-000000000003',60);
 PERFORM pg_temp.ttl36_require((r->'challenge'->>'expires_at')::bigint-(r->'challenge'->>'created_at')::bigint=60,'approved lower bound');
END$$;
ROLLBACK TO lower_bound;
RESET ROLE;

-- Historical pending fixture: the code was requested15 minutes ago and was
-- actually verified NOW in the synthetic managed session. No clock is changed.
SAVEPOINT old_pending_fresh_event;
INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,
 created_at,expires_at,attempts,consumed_at,delivery_status)
 SELECT 'e6360000-0000-4000-8000-000000000010',encode(sha256(convert_to('email:ttl36-admin@example.invalid','UTF8')),'hex'),
  'email','ttl36-admin@example.invalid','admin',0,auth_at-900,auth_at+900,1,auth_at,'accepted'
 FROM app.auth_sessions WHERE id='e2360000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
DO $$DECLARE r jsonb;BEGIN
 r:=private.admin_email_record_initial('e4360000-0000-4000-8000-000000000001',repeat('6',64),
  'https://admin.collect.example','e5360000-0000-4000-8000-000000000001','e6360000-0000-4000-8000-000000000010');
 PERFORM pg_temp.ttl36_require(r->'challenge'->>'verification_state'='verified','initial consumed proof accepts15-minute pending code with fresh AMR');
 PERFORM private.set_admin_email_context('e4360000-0000-4000-8000-000000000001',repeat('6',64),'https://admin.collect.example','e5360000-0000-4000-8000-000000000001');
 PERFORM pg_temp.ttl36_require(private.admin_email_is_current(300),'fresh consumed proof remains current');
END$$;
ROLLBACK TO old_pending_fresh_event;
RESET ROLE;

SAVEPOINT candidate_bounds;
DO $candidate$
DECLARE actor jsonb;c private.supabase_otp_challenges;r jsonb;
BEGIN
 actor:=private._admin_email_actor('e4360000-0000-4000-8000-000000000001',repeat('6',64),'https://admin.collect.example','e5360000-0000-4000-8000-000000000001',true);
 c.id:='e6360000-0000-4000-8000-000000000020';c.identity_type:='email';c.identity_value:='ttl36-admin@example.invalid';
 c.surface:='admin';c.registration_allowed:=0;c.created_at:=app.unixepoch()-900;c.expires_at:=c.created_at+1800;
 c.delivery_status:='accepted';c.attempts:=1;
 PERFORM pg_temp.ttl36_claims('e2360000-0000-4000-8000-000000000002',
  (SELECT floor(extract(epoch FROM updated_at))::bigint FROM auth.mfa_amr_claims WHERE session_id='e2360000-0000-4000-8000-000000000002' AND authentication_method='otp'));
 r:=private._admin_email_candidate(actor,c,false);
 PERFORM pg_temp.ttl36_require(r->>'session_id'='e2360000-0000-4000-8000-000000000002','reauth15-minute pending with current actual managed AMR');
 c.expires_at:=c.created_at+1801;
 BEGIN PERFORM private._admin_email_candidate(actor,c,false);RAISE EXCEPTION 'overlong candidate accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 c.created_at:=app.unixepoch()-1900;c.expires_at:=c.created_at+1800;
 BEGIN PERFORM private._admin_email_candidate(actor,c,false);RAISE EXCEPTION 'expired candidate accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 c.created_at:=app.unixepoch()-900;c.expires_at:=c.created_at+1800;
 UPDATE auth.mfa_amr_claims SET updated_at=to_timestamp(app.unixepoch()-400)
  WHERE session_id='e2360000-0000-4000-8000-000000000002' AND authentication_method='otp';
 PERFORM pg_temp.ttl36_claims('e2360000-0000-4000-8000-000000000002',app.unixepoch()-400);
 BEGIN PERFORM private._admin_email_candidate(actor,c,false);RAISE EXCEPTION 'stale reauth AMR accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END;$candidate$;
ROLLBACK TO candidate_bounds;
DO $$BEGIN PERFORM pg_temp.ttl36_claims('e2360000-0000-4000-8000-000000000001',
 (SELECT auth_at FROM app.auth_sessions WHERE id='e2360000-0000-4000-8000-000000000001'));END$$;

SAVEPOINT expired_receipt;
WITH clock AS MATERIALIZED(SELECT app.unixepoch() AS at)
INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at)
 SELECT 'e6360000-0000-4000-8000-000000000030',encode(sha256(convert_to('email:ttl36-admin@example.invalid','UTF8')),'hex'),
  'email','ttl36-admin@example.invalid','admin',0,at-1900,at-100 FROM clock;
INSERT INTO private.admin_email_operations(challenge_id,mode,admin_id,principal_id,original_auth_user_id,original_session_id,cookie_hash,
 public_session_id,auth_version,origin,identity_value,created_at)
 SELECT 'e6360000-0000-4000-8000-000000000030','reauth','e4360000-0000-4000-8000-000000000001','e3360000-0000-4000-8000-000000000001',
 'e1360000-0000-4000-8000-000000000001','e2360000-0000-4000-8000-000000000001',repeat('6',64),'e5360000-0000-4000-8000-000000000001',1,
 'https://admin.collect.example','ttl36-admin@example.invalid',created_at
 FROM private.supabase_otp_challenges WHERE id='e6360000-0000-4000-8000-000000000030';
SET LOCAL ROLE collect_runtime;
DO $$DECLARE r jsonb;expiry bigint;BEGIN
 SELECT expires_at INTO expiry FROM private.supabase_otp_challenges WHERE id='e6360000-0000-4000-8000-000000000030';
 r:=pg_temp.ttl36_prepare('e6360000-0000-4000-8000-000000000030',1800);
 PERFORM pg_temp.ttl36_require((r->'challenge'->>'expires_at')::bigint=expiry AND expiry<app.unixepoch(),'existing expired receipt never extended');
 r:=private.admin_email_verify_claim('e4360000-0000-4000-8000-000000000001',repeat('6',64),'https://admin.collect.example',
  'e5360000-0000-4000-8000-000000000001','e6360000-0000-4000-8000-000000000030','e9360000-0000-4000-8000-000000000001');
 PERFORM pg_temp.ttl36_require(r->>'claimed'='false','expired challenge cannot start verification');
END$$;
ROLLBACK TO expired_receipt;
RESET ROLE;

-- Retained valid historical proof, not an attempt to record a stale event now.
SAVEPOINT old_proof;
INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,attempts,consumed_at,delivery_status)
 SELECT 'e6360000-0000-4000-8000-000000000040',encode(sha256(convert_to('email:ttl36-admin@example.invalid','UTF8')),'hex'),
 'email','ttl36-admin@example.invalid','admin',0,auth_at-500,auth_at+1300,1,auth_at,'accepted'
 FROM app.auth_sessions WHERE id='e2360000-0000-4000-8000-000000000003';
INSERT INTO private.admin_email_operations(challenge_id,mode,admin_id,principal_id,original_auth_user_id,original_session_id,cookie_hash,
 public_session_id,auth_version,origin,identity_value,created_at,verification_state,cleanup_state,verified_session_id,verified_amr_at)
 SELECT 'e6360000-0000-4000-8000-000000000040','initial','e4360000-0000-4000-8000-000000000001','e3360000-0000-4000-8000-000000000001',
 'e1360000-0000-4000-8000-000000000001',id::uuid,repeat('7',64),'e5360000-0000-4000-8000-000000000003',1,'https://admin.collect.example',
 'ttl36-admin@example.invalid',auth_at-500,'verified','not_required',id::uuid,auth_at
 FROM app.auth_sessions WHERE id='e2360000-0000-4000-8000-000000000003';
INSERT INTO private.admin_sensitive_email_proofs(challenge_id,admin_id,principal_id,auth_user_id,original_session_id,cookie_hash,
 public_session_id,auth_version,origin,identity_value,verified_session_id,verified_at)
 SELECT challenge_id,admin_id,principal_id,original_auth_user_id,original_session_id,cookie_hash,public_session_id,auth_version,origin,identity_value,
 verified_session_id,verified_amr_at FROM private.admin_email_operations WHERE challenge_id='e6360000-0000-4000-8000-000000000040';
DO $$BEGIN PERFORM pg_temp.ttl36_claims('e2360000-0000-4000-8000-000000000003',
 (SELECT auth_at FROM app.auth_sessions WHERE id='e2360000-0000-4000-8000-000000000003'));END$$;
SET LOCAL ROLE collect_runtime;
DO $$BEGIN
 PERFORM private.set_admin_email_context('e4360000-0000-4000-8000-000000000001',repeat('7',64),'https://admin.collect.example','e5360000-0000-4000-8000-000000000003');
 PERFORM pg_temp.ttl36_require(NOT private.admin_email_is_current(300),'consumed proof older than300 remains stale');
 PERFORM pg_temp.ttl36_expect($q$SELECT private.admin_email_record_initial('e4360000-0000-4000-8000-000000000001',repeat('7',64),
  'https://admin.collect.example','e5360000-0000-4000-8000-000000000003','e6360000-0000-4000-8000-000000000040')$q$,'42501');
END$$;
ROLLBACK TO old_proof;
RESET ROLE;
ROLLBACK;
SELECT jsonb_build_object('status','pass','fixture','admin-email-ttl36','synthetic_only',true,'provider_calls',0,'all_fixture_changes_rolled_back',true);
