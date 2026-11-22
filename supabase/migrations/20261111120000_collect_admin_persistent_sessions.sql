-- Renew a real, revocable Admin session without turning token refresh into a
-- new sign-in or fresh email/MFA proof. The original session identity is kept.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR coalesce(current_setting('role',true),'none') NOT IN('none','postgres')
  OR current_setting('transaction_isolation')<>'read committed'
  OR current_setting('transaction_read_only')<>'off'
  OR current_setting('server_version_num')::integer/10000<>17
  OR to_regprocedure('private.collect_admin_renew_session(text,text)') IS NOT NULL
  OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_trigger t ON t.tgfoid=p.oid
   WHERE p.oid=to_regprocedure('private.trg_auth_session_identity_no_update()')
    AND pg_get_userbyid(p.proowner)='postgres' AND NOT p.prosecdef
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='c4f6b053a83eb595a07ceb2a1ff55bb14c5570cce486be5a27417f0200b4a601'
    AND t.tgrelid=to_regclass('app.auth_sessions') AND t.tgname='auth_session_identity_no_update' AND t.tgenabled='O')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'admin_session_renewal_precondition' USING ERRCODE='55000';
 END IF;
END;$preflight$;

CREATE OR REPLACE FUNCTION private.trg_auth_session_identity_no_update() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF (NEW.id,NEW.user_id,NEW.surface,NEW.auth_at,NEW.created_at)
      IS NOT DISTINCT FROM (OLD.id,OLD.user_id,OLD.surface,OLD.auth_at,OLD.created_at)
  AND OLD.surface='admin' AND OLD.revoked_at IS NULL AND NEW.revoked_at IS NULL
  AND NEW.expires_at>OLD.expires_at
  AND current_user='postgres' AND current_setting('role',true)='collect_runtime'
  AND EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure('private.collect_admin_renew_session(text,text)')
    AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef)
  AND current_setting('collect.admin_session_renewal',true)=
    jsonb_build_array(txid_current(),OLD.id,OLD.expires_at,NEW.expires_at)::text THEN
  RETURN NEW;
 END IF;
 RAISE EXCEPTION USING ERRCODE='P0001',MESSAGE='immutable_session_identity';
END;$fn$;

CREATE FUNCTION private.collect_admin_renew_session(p_cookie text,p_origin text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE claims jsonb:=private.request_claims();bound record;provider record;
 old_marker text:=current_setting('collect.admin_session_renewal',true);
 token_digest text;at_seconds bigint:=extract(epoch FROM now())::bigint;new_expiry bigint;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 PERFORM private._collect_fence_require_rc(true);
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 IF p_cookie IS NULL OR p_cookie !~ '^[a-f0-9]{64}$' OR p_origin IS NULL OR p_origin NOT LIKE 'https://%'
  OR claims->>'role' IS DISTINCT FROM 'authenticated' OR claims->>'sub' IS NULL OR claims->>'session_id' IS NULL THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='admin_session_renewal_denied';
 END IF;
 token_digest:=encode(sha256(convert_to(p_cookie,'UTF8')),'hex');
 SELECT s.token_hash,s.auth_session_id,s.expires_at AS admin_expiry,p.expires_at AS projection_expiry,
   a.email AS approved_email,b.auth_user_id,b.auth_session_id AS provider_session_id
 INTO bound
 FROM app.admin_sessions s
 JOIN app.admin_users a ON a.id=s.user_id AND a.status='active' AND a.auth_version=s.auth_version
 JOIN app.admin_principal_links l ON l.admin_user_id=a.id
 JOIN app.users u ON u.id=l.user_id AND u.access_status='active'
 JOIN app.auth_sessions p ON p.id=s.auth_session_id AND p.user_id=u.id AND p.surface='admin' AND p.revoked_at IS NULL
 JOIN private.bff_sessions b ON b.token_hash=s.token_hash AND b.auth_session_id::text=s.auth_session_id
 WHERE s.token_hash=token_digest AND s.origin=p_origin AND b.auth_user_id::text=claims->>'sub'
  AND b.auth_session_id::text=claims->>'session_id'
 FOR UPDATE OF s,p,a,u,b;
 IF NOT FOUND OR bound.admin_expiry IS DISTINCT FROM bound.projection_expiry THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='admin_session_renewal_denied';
 END IF;
 -- Keep the managed provider session live for the whole renewal transaction.
 SELECT session.id INTO provider FROM auth.sessions session JOIN auth.users identity ON identity.id=session.user_id
  WHERE session.id=bound.provider_session_id AND session.user_id=bound.auth_user_id
   AND identity.email_confirmed_at IS NOT NULL AND lower(identity.email)=bound.approved_email
  FOR SHARE OF session,identity;
 IF NOT FOUND OR NOT coalesce(private.is_managed_session(bound.auth_user_id,bound.provider_session_id),false) THEN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='admin_session_renewal_denied';
 END IF;
 new_expiry:=private.session_expiry(at_seconds+2592000);
 IF new_expiry<=at_seconds THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='admin_session_renewal_denied';END IF;
 IF new_expiry>bound.projection_expiry THEN
  PERFORM set_config('collect.admin_session_renewal',
   jsonb_build_array(txid_current(),bound.auth_session_id,bound.projection_expiry,new_expiry)::text,true);
  UPDATE app.auth_sessions SET expires_at=new_expiry
   WHERE id=bound.auth_session_id AND expires_at=bound.projection_expiry AND revoked_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='40001',MESSAGE='admin_session_changed';END IF;
  PERFORM set_config('collect.admin_session_renewal',coalesce(old_marker,''),true);
  UPDATE app.admin_sessions SET expires_at=new_expiry WHERE token_hash=bound.token_hash AND expires_at=bound.admin_expiry;
  IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='40001',MESSAGE='admin_session_changed';END IF;
 ELSE
  new_expiry:=bound.projection_expiry;
 END IF;
 RETURN jsonb_build_object('expiresAt',new_expiry);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('collect.admin_session_renewal',coalesce(old_marker,''),true);
 IF SQLSTATE='22P02' THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='admin_session_renewal_denied';END IF;
 RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_renew_session(text,text) FROM PUBLIC, anon, authenticated, service_role, collect_importer;
GRANT EXECUTE ON FUNCTION private.collect_admin_renew_session(text,text) TO collect_runtime;
COMMIT;
