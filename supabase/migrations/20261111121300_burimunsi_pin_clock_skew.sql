-- Additive correction for immediate native-session rejection under permitted
-- edge/database clock skew. Historical migrations remain unchanged.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;SET LOCAL lock_timeout='5s';SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
   WHERE p.oid=to_regprocedure('private.burimunsi_pin_create_session(text,uuid,uuid,text,text,bigint,uuid,text,bigint,bigint,bigint)')
    AND pg_get_userbyid(p.proowner)='postgres' AND p.prokind='f' AND p.prosecdef AND NOT p.proleakproof
    AND p.provolatile='v' AND p.proparallel='u' AND l.lanname='plpgsql'
    AND p.proacl::text='{postgres=X/postgres,collect_runtime=X/postgres}'
    AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')='6f8469a4740ca0bc3ff4ef6f63cd7baf791016e4bb2bce0f8c498c7796cca7f7') THEN
  RAISE EXCEPTION 'burimunsi_session_clock_predecessor_changed' USING ERRCODE='55000';END IF;
END;$preflight$;
CREATE OR REPLACE FUNCTION private.burimunsi_pin_create_session(p_collection text,p_account uuid,p_installation uuid,p_profile text,
 p_device_token_hash text,p_credential_version bigint,p_session uuid,p_session_token_hash text,p_created_ms bigint,p_expires_ms bigint,p_account_version bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.pin_frame',true);a private.burimunsi_accounts%ROWTYPE;
 scope private.burimunsi_scopes%ROWTYPE;d private.burimunsi_device_grants%ROWTYPE;proof jsonb;
 at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;matches bigint;
 actual_created bigint;actual_expires bigint;
BEGIN
 PERFORM private.burimunsi_setup_fence();
 IF p_account IS NULL OR p_session IS NULL OR p_installation IS NULL OR p_collection IS NULL
  OR p_profile NOT IN('staff','internal_receiver') OR p_profile IS NULL
  OR p_device_token_hash IS NULL OR p_device_token_hash !~ '^[a-f0-9]{64}$'
  OR p_session_token_hash IS NULL OR p_session_token_hash !~ '^[a-f0-9]{64}$'
  OR p_device_token_hash=p_session_token_hash OR p_credential_version IS NULL OR p_credential_version<1
  OR p_account_version IS NULL OR p_account_version<1
  OR p_created_ms IS NULL OR p_created_ms NOT BETWEEN at_ms-5000 AND at_ms+5000
  OR p_expires_ms IS NULL OR p_expires_ms<=at_ms OR p_expires_ms<=p_created_ms OR p_expires_ms>p_created_ms+28800000 THEN
  RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';
 END IF;
 -- The request and database clocks may differ within the admitted 5-second
 -- window. Never issue a not-yet-valid session: its origin is no later than
 -- either observed clock, and shortening the expiry preserves the requested TTL.
 actual_created:=least(p_created_ms,at_ms);
 actual_expires:=actual_created+(p_expires_ms-p_created_ms);
 IF actual_expires<=at_ms THEN RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.pin_frame','1',true);
 SELECT * INTO a FROM private.burimunsi_accounts WHERE collection_id=p_collection AND id=p_account FOR UPDATE;
 IF NOT FOUND OR NOT a.active OR a.removed OR a.credential_version<>p_credential_version OR a.version<>p_account_version THEN
  RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';
 END IF;
 SELECT * INTO scope FROM private.burimunsi_scopes WHERE collection_id=p_collection FOR SHARE;
 proof:=private.burimunsi_pin_authority_snapshot(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities);
 IF scope.collection_id IS NULL OR proof IS NULL THEN RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 -- The selected phone must still be globally unambiguous at the CAS boundary.
 SELECT count(*) INTO matches FROM private.burimunsi_accounts other
  JOIN private.burimunsi_scopes s ON s.collection_id=other.collection_id
  JOIN app.collections c ON c.id=s.collection_id AND c.status='active'
  WHERE other.phone=a.phone AND other.active AND NOT other.removed
   AND private.burimunsi_pin_authority_snapshot(other.collection_id,other.principal_user_id,other.phone,other.role,other.capabilities) IS NOT NULL;
 IF matches<>1 THEN RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 SELECT * INTO d FROM private.burimunsi_device_grants WHERE collection_id=p_collection AND installation_id=p_installation FOR UPDATE;
 IF FOUND THEN
  IF NOT d.active OR d.token_hash<>p_device_token_hash OR d.profile<>p_profile THEN
   RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM private.burimunsi_device_grants WHERE token_hash=p_device_token_hash
   AND (installation_id<>p_installation OR profile<>p_profile)) THEN
   RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
  INSERT INTO private.burimunsi_device_grants(id,collection_id,installation_id,token_hash,profile,custodian_account_id,created_at)
   VALUES(gen_random_uuid(),p_collection,p_installation,p_device_token_hash,p_profile,NULL,at_ms)
   RETURNING * INTO d;
 END IF;
 INSERT INTO private.burimunsi_device_accounts(grant_id,account_id,collection_id) VALUES(d.id,a.id,p_collection)
  ON CONFLICT(grant_id,account_id) DO NOTHING;
 IF actual_expires<=floor(extract(epoch FROM clock_timestamp())*1000)::bigint THEN
  RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,credential_version,grant_version,
  token_hash,created_at,expires_at,principal_user_id,auth_method)
  VALUES(p_session,p_collection,a.id,d.id,p_installation,a.credential_version,d.version,p_session_token_hash,
   actual_created,actual_expires,a.principal_user_id,'phone_pin');
 INSERT INTO private.burimunsi_pin_session_links(native_session_id,collection_id,account_id,principal_user_id,
  account_version,scope_version,authority_snapshot,created_at)
  VALUES(p_session,p_collection,a.id,a.principal_user_id,a.version,scope.version,proof,actual_created);
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('created',true,'expiresAt',actual_expires,'grantId',d.id,'grantVersion',d.version);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
COMMIT;
