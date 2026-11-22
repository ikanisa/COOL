-- Admin emailed-code pending lifetime, selected only by the trusted server.
-- The six-/seven-argument overloads accept approved60..1800 second policy.
-- Existing overloads retain300 seconds. No challenge is extended or rewritten.
-- OTP AMR/consumed proof freshness remains300 seconds, including reauth where
-- the prior300-second challenge duration previously implied that same bound.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE r record;c private.collect_fence_control%ROWTYPE;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR coalesce(current_setting('role',true),'none') NOT IN('none','postgres')
  OR current_setting('transaction_isolation')<>'read committed'
  OR current_setting('transaction_read_only')<>'off'
  OR current_setting('server_version_num')::integer/10000<>17
  OR to_regprocedure('private.admin_email_prepare(text,text,text,text,text,integer)') IS NOT NULL
  OR to_regprocedure('private.burimunsi_managed_email_reserve(text,uuid,text,text,text,text,integer)') IS NOT NULL THEN
  RAISE EXCEPTION 'admin_email_ttl_install_precondition' USING ERRCODE='55000';END IF;
 FOR r IN SELECT * FROM(VALUES
 ('private.admin_email_prepare(text,text,text,text,text)','28ec79a0f19df8e048aef431a328d2e44e969183181691a7976e3acbe6535c78','search_path=pg_catalog'),
 ('private.burimunsi_managed_email_reserve(text,uuid,text,text,text,text)','b5ba660a94efb83e0ea7e59e6012543c0a0d6a86046fffa5b33f3eccb7e493f7','search_path=pg_catalog,pg_temp'),
 ('private._admin_email_candidate(jsonb,private.supabase_otp_challenges,boolean)','2cad19075b60fb862bb11fa362f89751727f0a26d65a04c2400b330e4f675dd4','search_path=pg_catalog'),
 ('private._admin_email_current(jsonb,bigint)','062d890ba8ca1fecf41472b421d925ddd1f2adbf41e16b580db300659ef11d4d','search_path=pg_catalog')
 )v(signature,body_sha256,path) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(r.signature)
   AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.body_sha256
   AND cardinality(p.proconfig)=1 AND replace(p.proconfig[1],' ','')=r.path) THEN
   RAISE EXCEPTION 'admin_email_ttl_function_preimage' USING ERRCODE='55000';END IF;
 END LOOP;
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 PERFORM private._collect_fence_require_upgrade_locks();
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND OR c.mode<>'fenced' OR c.project_ref<>'rrlduytparvsjfmegalh'
  OR c.baseline_manifest_sha256<>'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3' THEN
  RAISE EXCEPTION 'admin_email_ttl_fenced_install_required' USING ERRCODE='55000';END IF;
END;$preflight$;

-- Closed server-only envelope. HTTP request bodies never supply this value;
-- collect_runtime still needs all existing actor/device/fence authority.
CREATE FUNCTION private.admin_email_prepare(p_actor text,p_cookie text,p_origin text,p_public text,p_challenge text,p_ttl_seconds integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb; operation private.admin_email_operations%ROWTYPE; at bigint:=app.unixepoch();
BEGIN
 IF p_ttl_seconds IS NULL OR p_ttl_seconds NOT BETWEEN 60 AND 1800 THEN
  RAISE EXCEPTION 'admin_email_ttl_invalid' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);
 IF p_challenge IS NULL OR p_challenge !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 THEN RAISE EXCEPTION 'admin_email_invalid' USING ERRCODE='22023';END IF;
 IF EXISTS(SELECT 1 FROM private.admin_email_operations WHERE challenge_id=p_challenge) THEN
  operation:=private._admin_email_operation(actor,p_challenge);RETURN private._admin_email_result(operation);
 END IF;
 INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at)
 VALUES(p_challenge,encode(sha256(convert_to('email:'||(actor->>'identity_value'),'UTF8')),'hex'),'email',actor->>'identity_value','admin',0,at,at+p_ttl_seconds);
 INSERT INTO private.admin_email_operations(challenge_id,mode,admin_id,principal_id,original_auth_user_id,original_session_id,
   cookie_hash,public_session_id,auth_version,origin,identity_value,created_at)
 VALUES(p_challenge,'reauth',actor->>'admin_id',actor->>'principal_id',(actor->>'auth_user_id')::uuid,(actor->>'session_id')::uuid,
   p_cookie,p_public,(actor->>'auth_version')::bigint,p_origin,actor->>'identity_value',at) RETURNING * INTO operation;
 RETURN private._admin_email_result(operation,true,false);
END$$;

CREATE FUNCTION private.burimunsi_managed_email_reserve(p_challenge text,p_install uuid,p_hash text,p_email text,p_profile text,p_network text,p_ttl_seconds integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_window text:=current_setting('burimunsi.email_preauth',true);candidate jsonb;at bigint:=app.unixepoch();
 identity_digest text;bucket_key text;bucket_limit integer;n bigint;allowed boolean:=true;
BEGIN
 IF p_ttl_seconds IS NULL OR p_ttl_seconds NOT BETWEEN 60 AND 1800 THEN
  RAISE EXCEPTION 'admin_email_ttl_invalid' USING ERRCODE='22023';END IF;
 PERFORM private.burimunsi_setup_fence();
 IF p_challenge IS NULL OR p_challenge !~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$'
  OR p_install IS NULL OR p_hash IS NULL OR p_hash !~ '^[a-f0-9]{64}$' OR p_network IS NULL OR p_network !~ '^[a-f0-9]{64}$'
  OR p_email IS NULL OR length(p_email)>254 OR p_email<>lower(p_email)
  OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  OR p_profile IS NULL OR p_profile NOT IN('staff','internal_receiver') THEN
  RETURN jsonb_build_object('allowed',false);END IF;
 identity_digest:=encode(sha256(convert_to('email:'||p_email,'UTF8')),'hex');
 BEGIN
  PERFORM set_config('burimunsi.email_preauth','1',true);
  INSERT INTO private.burimunsi_email_preauth_limits(bucket,window_start,attempts)
   VALUES('network:'||p_network,(at/900)*900,1) ON CONFLICT(bucket,window_start)
   DO UPDATE SET attempts=private.burimunsi_email_preauth_limits.attempts+1 RETURNING attempts INTO n;
  allowed:=n<=50;
  IF allowed THEN candidate:=private.burimunsi_managed_email_candidate(p_install,p_hash,p_email,p_profile);END IF;
  -- A guessed public installation UUID/email cannot exhaust somebody else's
  -- device/email budget. Charge those only after the strong device proof, and
  -- key the device bucket to this exact credential generation, not the UUID.
  IF candidate IS NOT NULL THEN
   FOR bucket_key,bucket_limit IN SELECT * FROM(VALUES
    ('device:'||encode(sha256(convert_to(p_install::text||':'||p_hash,'UTF8')),'hex'),10),
    ('email:'||identity_digest,5)) AS budgets(bucket,maximum) ORDER BY bucket LOOP
    INSERT INTO private.burimunsi_email_preauth_limits(bucket,window_start,attempts)
     VALUES(bucket_key,(at/900)*900,1) ON CONFLICT(bucket,window_start)
     DO UPDATE SET attempts=private.burimunsi_email_preauth_limits.attempts+1 RETURNING attempts INTO n;
    IF n>bucket_limit THEN allowed:=false;END IF;
   END LOOP;
  END IF;
  IF NOT allowed THEN candidate:=jsonb_build_object('allowed',false,'code','auth_rate_limited');
  ELSIF candidate IS NULL THEN candidate:=jsonb_build_object('allowed',false);
  ELSIF EXISTS(SELECT 1 FROM private.supabase_otp_challenges c WHERE c.identity_hash=identity_digest AND c.created_at+60>at) THEN
   candidate:=jsonb_build_object('allowed',false,'code','auth_rate_limited');
  ELSE
   INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status,native_preauth)
    VALUES(p_challenge,identity_digest,'email',p_email,'admin',0,at,at+p_ttl_seconds,'reserved',true);
   INSERT INTO private.burimunsi_email_preauth(challenge_id,collection_id,installation_id,token_hash,email,profile,snapshot,created_at)
    VALUES(p_challenge,candidate->>'collectionId',p_install,p_hash,p_email,p_profile,candidate,at);
   candidate:=jsonb_build_object('allowed',true,'challengeId',p_challenge,'collectionId',candidate->>'collectionId',
    'createdAt',at,'expiresAt',at+p_ttl_seconds);
  END IF;
 EXCEPTION WHEN OTHERS THEN
  PERFORM set_config('burimunsi.email_preauth',coalesce(old_window,''),true);RAISE;
 END;
 PERFORM set_config('burimunsi.email_preauth',coalesce(old_window,''),true);
 RETURN candidate;
END;$fn$;

-- Pending30 minutes never means a30-minute authentication proof.
CREATE OR REPLACE FUNCTION private._admin_email_candidate(p_actor jsonb,p_challenge private.supabase_otp_challenges,p_initial boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE claims jsonb:=private.request_claims(); candidate uuid; subject uuid; event_at bigint;
BEGIN
 candidate:=(claims->>'session_id')::uuid;subject:=(claims->>'sub')::uuid;
 IF candidate='00000000-0000-0000-0000-000000000000'::uuid OR subject='00000000-0000-0000-0000-000000000000'::uuid
  OR claims->>'role' IS DISTINCT FROM 'authenticated' OR subject::text IS DISTINCT FROM p_actor->>'auth_user_id'
  OR (p_initial AND candidate::text IS DISTINCT FROM p_actor->>'session_id')
  OR (NOT p_initial AND candidate::text=p_actor->>'session_id')
  OR NOT coalesce(private.is_managed_session(subject,candidate),false)
  OR p_challenge.identity_type<>'email' OR p_challenge.surface<>'admin' OR p_challenge.registration_allowed<>0
  OR p_challenge.privacy_mode IS NOT NULL OR p_challenge.identity_value IS DISTINCT FROM p_actor->>'identity_value'
  OR p_challenge.delivery_status NOT IN('accepted','unknown') OR p_challenge.attempts NOT BETWEEN 1 AND 5
  OR p_challenge.expires_at>p_challenge.created_at+1800 OR (NOT p_initial AND app.unixepoch()>p_challenge.expires_at)
 THEN RAISE EXCEPTION 'admin_email_candidate_denied' USING ERRCODE='42501';END IF;
 PERFORM 1 FROM auth.users u WHERE u.id=subject AND u.email_confirmed_at IS NOT NULL AND lower(u.email)=p_challenge.identity_value FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_email_candidate_denied' USING ERRCODE='42501';END IF;
 SELECT max(floor(extract(epoch FROM updated_at))::bigint) INTO event_at FROM auth.mfa_amr_claims
 WHERE session_id=candidate AND authentication_method='otp';
 IF event_at IS NULL OR event_at NOT BETWEEN greatest(1,p_challenge.created_at) AND least(app.unixepoch(),p_challenge.expires_at)
  OR event_at<app.unixepoch()-300
  OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(claims->'amr')='array' THEN claims->'amr' ELSE '[]'::jsonb END) item
   WHERE item->>'method'='otp' AND jsonb_typeof(item->'timestamp')='number' AND item->>'timestamp' ~ '^[0-9]{1,16}$'
    AND abs((item->>'timestamp')::bigint-event_at)<=1)
  OR (p_initial AND (p_actor->>'auth_at')::bigint<>event_at)
  OR (NOT p_initial AND EXISTS(SELECT 1 FROM app.auth_sessions WHERE id=candidate::text))
 THEN RAISE EXCEPTION 'admin_email_candidate_denied' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('session_id',candidate,'amr_at',event_at);
END$$;

ALTER FUNCTION private.admin_email_prepare(text,text,text,text,text,integer) OWNER TO postgres;
ALTER FUNCTION private.burimunsi_managed_email_reserve(text,uuid,text,text,text,text,integer) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.admin_email_prepare(text,text,text,text,text,integer),
 private.burimunsi_managed_email_reserve(text,uuid,text,text,text,text,integer)
 FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
GRANT EXECUTE ON FUNCTION private.admin_email_prepare(text,text,text,text,text,integer),
 private.burimunsi_managed_email_reserve(text,uuid,text,text,text,text,integer) TO collect_runtime;
-- CREATE OR REPLACE preserves the existing internal candidate owner/ACL.
COMMIT;
