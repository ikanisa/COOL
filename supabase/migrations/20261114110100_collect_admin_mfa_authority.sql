-- WORK IN PROGRESS: no route or feature is enabled. Do not deploy until the
-- cookie-recovery integration and exact-schema race/rollback tests are done.
-- The retired generic projector remains ungranted to collect_runtime.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $preflight$
DECLARE r record;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR to_regprocedure('private.collect_admin_mfa_authorize_v1(text,text,text,text,text,uuid)') IS NOT NULL
  OR EXISTS(SELECT 1 FROM app.runtime_config WHERE key='security:admin_mfa_required:v1')
  OR has_function_privilege('collect_runtime','private.record_mfa_projection(uuid)','EXECUTE')
  OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='private.bff_sessions'::regclass AND attname LIKE 'mfa_pending_%' AND NOT attisdropped)
  OR NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='app.auth_mfa_factors'::regclass
   AND attname='enrollment_session_id' AND attnotnull AND NOT attisdropped)
  OR NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='app.auth_mfa_factors'::regclass
   AND conname='auth_mfa_factors_check' AND encode(sha256(convert_to(pg_get_constraintdef(oid),'UTF8')),'hex')=
    'af9ee0c09d98c542a3761d997ca30368e1f4dd56d747e58419cbd2274c19f15f') THEN
  RAISE EXCEPTION 'admin_mfa_authority_precondition' USING ERRCODE='55000';END IF;
 FOR r IN SELECT * FROM (VALUES
  ('private.record_mfa_projection(uuid)','2e959aaee1723f738014dd2f78705d8b9dfb97759e82f091e60beba6666af289','v','{postgres=X/postgres}'),
  ('private._admin_email_actor(text,text,text,text,boolean)','11b9d6df331abedf985d60d4d54ec1c82407e59836f2c6fafcb43a96e12c9064','v','{postgres=X/postgres}'),
  ('private._admin_email_current(jsonb,bigint)','062d890ba8ca1fecf41472b421d925ddd1f2adbf41e16b580db300659ef11d4d','v','{postgres=X/postgres}'),
  ('private.set_admin_email_context(text,text,text,text)','1a493d2b8a1bc9a8b79896be64a40eb54c9192280f26cf44170e3ba00faa03ca','v','{postgres=X/postgres,collect_runtime=X/postgres}'),
  ('private.assert_admin_email_context(bigint)','5bcde2de29499118c3384a6a124df2772b6cc093ae8f7bdd5bd967d5cfaa1188','v','{postgres=X/postgres,collect_runtime=X/postgres}')
 ) e(sig,hash,volatility,acl) LOOP
  IF to_regprocedure(r.sig) IS NULL OR NOT EXISTS(
   SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure(r.sig) AND pg_get_userbyid(p.proowner)='postgres'
    AND p.prosecdef AND p.provolatile=r.volatility AND p.prokind='f' AND p.proparallel='u'
    AND NOT p.proleakproof AND l.lanname='plpgsql' AND p.proacl::text=r.acl
    AND p.proconfig=ARRAY['search_path=pg_catalog']::text[]
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.hash) THEN
   RAISE EXCEPTION 'admin_mfa_authority_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
END;$preflight$;

-- A pending candidate is not an authenticated Admin cookie. The original
-- cookie keeps its previous assurance until the browser actually presents the
-- candidate and the completion function commits the rotation. The old token
-- is held encrypted only for a narrowly checked expired-candidate fallback.
ALTER TABLE private.bff_sessions
 ADD COLUMN mfa_pending_hash text,
 ADD COLUMN mfa_pending_old_cookie_ciphertext text,
 ADD COLUMN mfa_pending_factor uuid,
 ADD COLUMN mfa_pending_at bigint,
 ADD COLUMN mfa_pending_state text,
 ADD CONSTRAINT bff_mfa_pending_complete CHECK (
  (mfa_pending_hash IS NULL AND mfa_pending_old_cookie_ciphertext IS NULL AND mfa_pending_factor IS NULL AND mfa_pending_at IS NULL AND mfa_pending_state IS NULL)
  OR (mfa_pending_hash IS NOT NULL AND mfa_pending_hash ~ '^[a-f0-9]{64}$'
   AND mfa_pending_old_cookie_ciphertext IS NOT NULL AND app.json_valid(mfa_pending_old_cookie_ciphertext) IS TRUE
   AND mfa_pending_factor IS NOT NULL AND mfa_pending_at IS NOT NULL AND mfa_pending_at>0
   AND mfa_pending_state IS NOT NULL AND mfa_pending_state IN('staged','restoring')));
CREATE UNIQUE INDEX bff_mfa_pending_candidate ON private.bff_sessions(mfa_pending_hash) WHERE mfa_pending_hash IS NOT NULL;

-- Managed GoTrue factors do not have a local TOTP counter or an authoritative
-- local enrollment-session ID. Only the exact metadata marker may leave those
-- two legacy fields null. Existing local-factor constraints remain unchanged.
ALTER TABLE app.auth_mfa_factors ALTER COLUMN enrollment_session_id DROP NOT NULL;
ALTER TABLE app.auth_mfa_factors DROP CONSTRAINT auth_mfa_factors_check;
ALTER TABLE app.auth_mfa_factors ADD CONSTRAINT auth_mfa_factors_check CHECK (
 (status='pending' AND verified_at IS NULL AND last_totp_counter IS NULL AND revoked_at IS NULL AND enrollment_session_id IS NOT NULL)
 OR (status='verified' AND verified_at IS NOT NULL AND revoked_at IS NULL AND
  ((last_totp_counter IS NOT NULL AND enrollment_session_id IS NOT NULL)
   OR (last_totp_counter IS NULL AND enrollment_session_id IS NULL AND secret_ciphertext::jsonb='{"managed_by":"supabase","version":1}'::jsonb)))
 OR (status='revoked' AND revoked_at IS NOT NULL AND
  (enrollment_session_id IS NOT NULL OR secret_ciphertext::jsonb='{"managed_by":"supabase","version":1}'::jsonb)));

CREATE FUNCTION private.collect_admin_mfa_authorize_v1(
 p_actor text,p_cookie text,p_origin text,p_public text,p_action text,p_factor uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;factor_status text;old_context text:=current_setting('collect.admin_email_context',true);
BEGIN
 IF p_action IS NULL OR p_action NOT IN('list','enroll','challenge','verify','cancel')
  OR ((p_action IN('list','enroll')) IS DISTINCT FROM (p_factor IS NULL)) THEN
  RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 -- Same serialization lock used by Admin logout, role and session updates.
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);
 IF actor->>'role' NOT IN('owner','admin','staff') THEN
  RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 -- Check the scoped current Admin grant directly. The retired generic actor
 -- projector and its effective auth.mfa.enroll capability stay untouched.
 PERFORM 1 FROM app.admin_grants g JOIN app.admin_account_role_capabilities c
  ON c.permission=g.permission AND c.role=actor->>'role'
  WHERE g.user_id=actor->>'principal_id' AND g.permission='auth.mfa.enroll'
  FOR SHARE OF g,c;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 IF p_action IN('enroll','cancel') THEN
  PERFORM private.set_admin_email_context(p_actor,p_cookie,p_origin,p_public);
  PERFORM private.assert_admin_email_context(300);
  PERFORM set_config('collect.admin_email_context',coalesce(old_context,''),true);
 END IF;
 IF p_factor IS NOT NULL THEN
  SELECT f.status::text INTO factor_status FROM auth.mfa_factors f
   WHERE f.id=p_factor AND f.user_id::text=actor->>'auth_user_id' AND f.factor_type::text='totp'
   FOR SHARE OF f;
  IF factor_status IS NULL OR factor_status NOT IN('unverified','verified')
   OR (p_action='cancel' AND factor_status<>'unverified') THEN
   RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 END IF;
 RETURN jsonb_build_object('version',1,'action',p_action,'authorized',true,
  'factor_status',factor_status);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('collect.admin_email_context',coalesce(old_context,''),true);
 RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_authorize_v1(text,text,text,text,text,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_authorize_v1(text,text,text,text,text,uuid) TO collect_runtime;
-- In particular, private.record_mfa_projection(uuid) remains owner-only.

-- Only this Admin-specific helper can stage a candidate. Its lease must have
-- been acquired before the provider verification request, and all identities,
-- claims, current factor and GoTrue AMR evidence are rechecked transactionally.
CREATE FUNCTION private.collect_admin_mfa_prepare_v1(
 p_actor text,p_cookie text,p_origin text,p_public text,p_version bigint,p_lease text,
 p_factor uuid,p_new_hash text,p_new_ciphertext text,p_old_cookie_ciphertext text
) RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;claims jsonb:=private.request_claims();claim_at bigint;provider_at bigint;at bigint:=app.unixepoch();
BEGIN
 IF p_lease IS NULL OR p_version IS NULL OR p_factor IS NULL OR p_new_hash IS NULL
  OR p_new_hash !~ '^[a-f0-9]{64}$' OR p_new_hash=p_cookie
  OR p_new_ciphertext IS NULL OR length(p_new_ciphertext)>16384 OR app.json_valid(p_new_ciphertext) IS DISTINCT FROM true
  OR p_old_cookie_ciphertext IS NULL OR length(p_old_cookie_ciphertext)>4096 OR app.json_valid(p_old_cookie_ciphertext) IS DISTINCT FROM true
  OR claims->>'aal' IS DISTINCT FROM 'aal2' THEN
  RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 -- Clear only the caller's still-live lease while holding the row lock; a later
 -- failure rolls this statement back with the rest of the transaction.
 UPDATE private.bff_sessions b SET refresh_lease=NULL,refresh_lease_until=NULL
  WHERE b.token_hash=p_cookie AND b.version=p_version AND b.refresh_lease=p_lease
   AND b.refresh_lease_until>at AND b.mfa_pending_hash IS NULL
  RETURNING b.token_hash INTO p_cookie;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 actor:=private.collect_admin_mfa_authorize_v1(p_actor,p_cookie,p_origin,p_public,'verify',p_factor);
 IF actor->>'factor_status'<>'verified' OR EXISTS(SELECT 1 FROM app.admin_sessions WHERE token_hash=p_new_hash) THEN
  RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 PERFORM 1 FROM auth.sessions s JOIN auth.mfa_factors f ON f.user_id=s.user_id
  WHERE s.id::text=claims->>'session_id' AND s.user_id::text=claims->>'sub'
   AND f.id=p_factor AND f.status::text='verified' AND f.factor_type::text='totp'
   AND to_jsonb(s)->>'aal'='aal2' AND s.factor_id=p_factor
  FOR SHARE OF s,f;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 PERFORM 1 FROM auth.mfa_amr_claims amr WHERE amr.session_id::text=claims->>'session_id'
  AND amr.authentication_method IN('totp','mfa/totp') FOR SHARE OF amr;
 SELECT max((v->>'timestamp')::bigint) INTO claim_at FROM jsonb_array_elements(
  CASE WHEN jsonb_typeof(claims->'amr')='array' THEN claims->'amr' ELSE '[]'::jsonb END) v
  WHERE v->>'method' IN('totp','mfa/totp') AND jsonb_typeof(v->'timestamp')='number'
   AND v->>'timestamp' ~ '^[0-9]{1,12}$';
 SELECT max(floor(extract(epoch FROM amr.updated_at))::bigint) INTO provider_at FROM auth.mfa_amr_claims amr
  WHERE amr.session_id::text=claims->>'session_id' AND amr.authentication_method IN('totp','mfa/totp');
 IF claim_at IS NULL OR provider_at IS NULL OR abs(provider_at-claim_at)>1
  OR provider_at<at-300 OR provider_at>at+30 THEN
  RAISE EXCEPTION 'admin_mfa_proof_unavailable' USING ERRCODE='42501';END IF;
 UPDATE private.bff_sessions SET token_ciphertext=p_new_ciphertext,version=version+1,
  mfa_pending_hash=p_new_hash,mfa_pending_old_cookie_ciphertext=p_old_cookie_ciphertext,
  mfa_pending_factor=p_factor,mfa_pending_at=provider_at,mfa_pending_state='staged'
 WHERE token_hash=p_cookie AND version=p_version AND refresh_lease IS NULL AND mfa_pending_hash IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('version',1,'state','pending');
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_prepare_v1(text,text,text,text,bigint,text,uuid,text,text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_prepare_v1(text,text,text,text,bigint,text,uuid,text,text,text) TO collect_runtime;

-- Finish only when the browser has presented the candidate cookie. The raw
-- candidate never enters SQL: the BFF passes its hash and verified claims.
CREATE FUNCTION private.collect_admin_mfa_complete_v1(p_candidate_hash text,p_origin text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE b private.bff_sessions%ROWTYPE;s app.admin_sessions%ROWTYPE;actor jsonb;f record;verified bigint;at bigint:=app.unixepoch();
BEGIN
 IF p_candidate_hash IS NULL OR p_candidate_hash !~ '^[a-f0-9]{64}$' OR p_origin IS NULL THEN
  RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 SELECT bff.* INTO b FROM private.bff_sessions bff JOIN app.admin_sessions a ON a.token_hash=bff.token_hash
  WHERE bff.mfa_pending_hash=p_candidate_hash AND a.origin=p_origin FOR UPDATE OF bff,a;
 IF NOT FOUND OR b.refresh_lease IS NOT NULL OR b.mfa_pending_state IS DISTINCT FROM 'staged' THEN
  RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 SELECT * INTO s FROM app.admin_sessions WHERE token_hash=b.token_hash FOR UPDATE;
 actor:=private.collect_admin_mfa_authorize_v1(s.user_id,b.token_hash,s.origin,s.public_id,'verify',b.mfa_pending_factor);
 IF actor->>'factor_status'<>'verified' OR b.mfa_pending_at<at-300 OR b.mfa_pending_at>at+30
  OR EXISTS(SELECT 1 FROM app.admin_sessions WHERE token_hash=p_candidate_hash) THEN
  RAISE EXCEPTION 'admin_mfa_proof_unavailable' USING ERRCODE='42501';END IF;
 SELECT factor.id,factor.user_id,factor.friendly_name,factor.created_at INTO f FROM auth.mfa_factors factor
  WHERE factor.id=b.mfa_pending_factor AND factor.user_id=b.auth_user_id
   AND factor.factor_type::text='totp' AND factor.status::text='verified' FOR SHARE OF factor;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 -- The legacy projector remains uncallable by runtime; this scoped function
 -- invokes it only after the exact Admin cookie/session/factor checks above.
 verified:=private.record_mfa_projection(b.mfa_pending_factor);
 IF verified IS DISTINCT FROM b.mfa_pending_at THEN RAISE EXCEPTION 'admin_mfa_proof_changed' USING ERRCODE='42501';END IF;
 INSERT INTO app.auth_mfa_factors(id,user_id,friendly_name,secret_ciphertext,status,created_at,enrollment_session_id,verified_at,last_totp_counter,revoked_at)
 VALUES(f.id::text,(SELECT user_id FROM app.admin_principal_links WHERE admin_user_id=s.user_id),
  coalesce(nullif(f.friendly_name,''),'Authenticator'),'{"managed_by":"supabase","version":1}',
  'verified',floor(extract(epoch FROM f.created_at))::bigint,NULL,verified,NULL,NULL)
 ON CONFLICT(id) DO NOTHING;
 IF NOT EXISTS(SELECT 1 FROM app.auth_mfa_factors factor JOIN app.admin_principal_links l ON l.user_id=factor.user_id
   WHERE factor.id=f.id::text AND l.admin_user_id=s.user_id AND factor.status='verified'
    AND factor.secret_ciphertext::jsonb='{"managed_by":"supabase","version":1}'::jsonb
    AND factor.enrollment_session_id IS NULL AND factor.last_totp_counter IS NULL) THEN
  RAISE EXCEPTION 'admin_mfa_factor_conflict' USING ERRCODE='42501';END IF;
 UPDATE app.auth_sessions SET assurance_level=2,mfa_at=verified,mfa_factor_id=f.id::text
  WHERE id=s.auth_session_id AND revoked_at IS NULL AND expires_at>at;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 UPDATE app.admin_sessions SET token_hash=p_candidate_hash,issued_assurance_level=2,
  issued_mfa_at=verified,issued_mfa_factor_id=f.id::text
  WHERE token_hash=b.token_hash AND public_id=s.public_id AND origin=p_origin;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 UPDATE private.bff_sessions SET mfa_pending_hash=NULL,mfa_pending_old_cookie_ciphertext=NULL,
  mfa_pending_factor=NULL,mfa_pending_at=NULL,mfa_pending_state=NULL WHERE token_hash=p_candidate_hash AND mfa_pending_hash=p_candidate_hash;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 INSERT INTO app.admin_account_audit(id,actor_id,subject_id,action,occurred_at)
  VALUES(gen_random_uuid()::text,s.user_id,s.user_id,'admin_managed_mfa_verified',at);
 RETURN jsonb_build_object('version',1,'state','complete','public_session_id',s.public_id);
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_complete_v1(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_complete_v1(text,text) TO collect_runtime;

-- Preserve the old session on an expired/revoked candidate or a rollback of
-- the feature flag. This atomically prevents a concurrent candidate upgrade;
-- repeat calls are safe if the fallback Set-Cookie response is lost.
CREATE FUNCTION private.collect_admin_mfa_restore_v1(p_candidate_hash text,p_origin text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE b private.bff_sessions%ROWTYPE;s app.admin_sessions%ROWTYPE;
BEGIN
 IF p_candidate_hash IS NULL OR p_candidate_hash !~ '^[a-f0-9]{64}$' OR p_origin IS NULL THEN
  RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 SELECT bff.* INTO b FROM private.bff_sessions bff JOIN app.admin_sessions a ON a.token_hash=bff.token_hash
  WHERE bff.mfa_pending_hash=p_candidate_hash AND a.origin=p_origin FOR UPDATE OF bff,a;
 IF NOT FOUND OR b.refresh_lease IS NOT NULL OR b.mfa_pending_state NOT IN('staged','restoring') THEN
  RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 SELECT * INTO s FROM app.admin_sessions WHERE token_hash=b.token_hash FOR UPDATE;
 PERFORM private.collect_admin_mfa_authorize_v1(s.user_id,b.token_hash,s.origin,s.public_id,'list',NULL);
 UPDATE private.bff_sessions SET mfa_pending_state='restoring'
  WHERE token_hash=b.token_hash AND mfa_pending_hash=p_candidate_hash AND mfa_pending_state IN('staged','restoring');
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('version',1,'state','restore','original_hash',b.token_hash,
  'old_cookie_ciphertext',b.mfa_pending_old_cookie_ciphertext,'auth_user_id',b.auth_user_id,
  'auth_session_id',b.auth_session_id,'public_session_id',s.public_id);
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_restore_v1(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_restore_v1(text,text) TO collect_runtime;

-- No policy row is installed during this migration. An absent key means OFF.
-- Creating or changing the key is blocked until a separately qualified fenced
-- activation migration defines its own narrow authority and recovery path.
CREATE FUNCTION private.collect_admin_mfa_policy_guard_v1() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF TG_OP='DELETE' THEN
  IF OLD.key='security:admin_mfa_required:v1' THEN RAISE EXCEPTION 'admin_mfa_policy_retained' USING ERRCODE='42501';END IF;
  RETURN OLD;
 END IF;
 IF NEW.key='security:admin_mfa_required:v1' OR (TG_OP='UPDATE' AND OLD.key='security:admin_mfa_required:v1') THEN
  RAISE EXCEPTION 'admin_mfa_policy_activation_unavailable' USING ERRCODE='42501';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER collect_admin_mfa_policy_guard_v1 BEFORE INSERT OR UPDATE OR DELETE ON app.runtime_config
 FOR EACH ROW EXECUTE FUNCTION private.collect_admin_mfa_policy_guard_v1();
ALTER TABLE app.runtime_config ENABLE ALWAYS TRIGGER collect_admin_mfa_policy_guard_v1;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_policy_guard_v1() FROM PUBLIC,anon,authenticated,collect_runtime;

CREATE FUNCTION private.collect_admin_mfa_policy_enabled_v1() RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE value jsonb;
BEGIN
 SELECT value_json::jsonb INTO value FROM app.runtime_config WHERE key='security:admin_mfa_required:v1';
 IF NOT FOUND THEN RETURN false;END IF;
 IF value='{"version":1,"required":false}'::jsonb THEN RETURN false;END IF;
 IF value='{"version":1,"required":true}'::jsonb THEN RETURN true;END IF;
 RAISE EXCEPTION 'admin_mfa_policy_unavailable' USING ERRCODE='55000';
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_policy_enabled_v1() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_policy_enabled_v1() TO collect_runtime;

CREATE FUNCTION private.collect_admin_mfa_assert_v1(p_actor jsonb,p_max_age bigint) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE claims jsonb:=private.request_claims();at bigint:=app.unixepoch();
BEGIN
 IF NOT private.collect_admin_mfa_policy_enabled_v1() THEN RETURN;END IF;
 IF p_max_age IS NULL OR p_max_age NOT BETWEEN 1 AND 86400 OR claims->>'aal' IS DISTINCT FROM 'aal2' THEN
  RAISE EXCEPTION 'mfa_required' USING ERRCODE='42501';END IF;
 PERFORM 1 FROM app.admin_sessions c JOIN app.auth_sessions s ON s.id=c.auth_session_id
  JOIN private.bff_sessions b ON b.token_hash=c.token_hash AND b.auth_session_id::text=s.id
  JOIN private.managed_mfa_proofs m ON m.session_id=b.auth_session_id AND m.user_id=b.auth_user_id
  JOIN auth.sessions managed ON managed.id=m.session_id AND managed.user_id=m.user_id
  JOIN auth.mfa_factors f ON f.id=m.factor_id AND f.user_id=m.user_id
  WHERE c.token_hash=p_actor->>'cookie_hash' AND c.user_id=p_actor->>'admin_id'
   AND c.public_id=p_actor->>'public_session_id' AND c.origin=p_actor->>'origin'
   AND s.user_id=p_actor->>'principal_id' AND s.id=p_actor->>'session_id'
   AND claims->>'role'='authenticated' AND claims->>'sub'=m.user_id::text AND claims->>'session_id'=m.session_id::text
   AND c.issued_assurance_level=2 AND s.assurance_level=2 AND s.revoked_at IS NULL
   AND c.issued_mfa_at=s.mfa_at AND m.verified_at_epoch=s.mfa_at
   AND c.issued_mfa_factor_id=s.mfa_factor_id AND m.factor_id::text=s.mfa_factor_id
   AND m.verified_at_epoch BETWEEN at-least(p_max_age,300) AND at
   AND to_jsonb(managed)->>'aal'='aal2' AND managed.factor_id=m.factor_id
   AND f.factor_type::text='totp' AND f.status::text='verified'
  FOR SHARE OF c,s,b,m,managed,f;
 IF NOT FOUND THEN RAISE EXCEPTION 'mfa_required' USING ERRCODE='42501';END IF;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_assert_v1(jsonb,bigint) FROM PUBLIC,anon,authenticated,collect_runtime;

-- Preserve the function's existing ACL and the preexisting email policy. This
-- is reached by both the BFF sensitive-write guard and canonical Admin actor.
CREATE OR REPLACE FUNCTION private.assert_admin_email_context(p_max_age bigint DEFAULT 300)
RETURNS private.admin_sensitive_email_proofs LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $fn$
DECLARE actor jsonb;proof private.admin_sensitive_email_proofs%ROWTYPE;
BEGIN
 actor:=private._admin_email_context();
 proof:=private._admin_email_current(actor,p_max_age);
 PERFORM private.collect_admin_mfa_assert_v1(actor,p_max_age);
 RETURN proof;
END;$fn$;
COMMIT;
