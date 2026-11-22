-- Atomic native PIN change and session rotation. The trusted native service
-- verifies the entered current PIN before calling this fenced CAS, using the
-- same server-side pepper boundary as the existing native login path. The DB
-- never receives a PIN or treats renewal as fresh PIN proof.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regprocedure('private.burimunsi_pin_renew_session(text,uuid,text,text,text,bigint)') IS NULL
  OR to_regprocedure('private.burimunsi_pin_rotate_passcode(uuid,uuid,bigint,bigint,jsonb,text,text,bigint)') IS NOT NULL
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_passcode_rotation_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

CREATE FUNCTION private.burimunsi_pin_rotate_passcode(p_account uuid,p_session uuid,p_expected_credential bigint,
 p_expected_version bigint,p_new_hash jsonb,p_replacement_hash text,p_temporary_token text,p_ttl_ms bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor record;a private.burimunsi_accounts%ROWTYPE;device_token text:=current_setting('burimunsi.pin_device',true);
 original_token text:=current_setting('burimunsi.pin_token',true);installation_text text:=current_setting('burimunsi.pin_installation',true);
 original_profile text:=current_setting('burimunsi.pin_profile',true);temporary_session uuid:=gen_random_uuid();replacement_session uuid:=gen_random_uuid();
 temporary_hash text;at_ms bigint;expires_ms bigint;created jsonb;keys text[];
BEGIN
 PERFORM private.burimunsi_setup_fence();
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 IF p_account IS NULL OR p_session IS NULL OR p_expected_credential IS NULL OR p_expected_credential<1
  OR p_expected_version IS NULL OR p_expected_version<1 OR p_ttl_ms IS NULL OR p_ttl_ms<60000 OR p_ttl_ms>28800000
  OR p_replacement_hash IS NULL OR p_replacement_hash !~ '^[a-f0-9]{64}$'
  OR p_temporary_token IS NULL OR p_temporary_token !~ '^[a-f0-9]{64}$'
  OR jsonb_typeof(p_new_hash) IS DISTINCT FROM 'object' THEN
  RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 SELECT array_agg(k ORDER BY k) INTO keys FROM jsonb_object_keys(p_new_hash) k;
 IF keys IS DISTINCT FROM ARRAY['algorithm','hash','iterations','pepperId','salt']::text[]
  OR p_new_hash->>'algorithm' IS DISTINCT FROM 'pbkdf2-sha256+hmac-v1'
  OR coalesce(length(p_new_hash->>'pepperId'),0) NOT BETWEEN 1 AND 128
  OR coalesce(p_new_hash->>'salt','') !~ '^[a-f0-9]{32}$'
  OR coalesce(p_new_hash->>'hash','') !~ '^[a-f0-9]{64}$'
  OR coalesce(p_new_hash->>'iterations','') !~ '^[0-9]{6,7}$' THEN
  RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 IF (p_new_hash->>'iterations')::bigint NOT BETWEEN 600000 AND 2000000 THEN
  RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 SELECT * INTO actor FROM private.burimunsi_pin_context();
 IF NOT FOUND OR actor.account_id<>p_account OR actor.native_session_id<>p_session
  OR installation_text IS NULL OR installation_text !~ '^[a-f0-9-]{36}$'
  OR device_token IS NULL OR device_token !~ '^[a-f0-9]{64}$'
  OR original_token IS NULL OR original_token !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 temporary_hash:=encode(sha256(convert_to(p_temporary_token,'UTF8')),'hex');
 IF p_replacement_hash IN(temporary_hash,encode(sha256(convert_to(original_token,'UTF8')),'hex'),
  encode(sha256(convert_to(device_token,'UTF8')),'hex')) OR p_temporary_token IN(original_token,device_token) THEN
  RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 PERFORM private.burimunsi_pin_assert_actor(NULL,actor.collection_id,NULL,1,NULL);
 SELECT * INTO a FROM private.burimunsi_accounts WHERE collection_id=actor.collection_id AND id=p_account FOR UPDATE;
 IF NOT FOUND OR NOT a.active OR a.removed OR a.version<>p_expected_version OR a.credential_version<>p_expected_credential
  OR a.principal_user_id<>actor.principal_user_id THEN RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 -- Current PIN was verified by the service immediately before entering this
 -- CAS. The temporary session is a fresh proof solely for the established
 -- account trigger; no original session timestamp or authority is rewritten.
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 created:=private.burimunsi_pin_create_session(a.collection_id,a.id,actor.installation_id,actor.profile,
  encode(sha256(convert_to(device_token,'UTF8')),'hex'),a.credential_version,temporary_session,temporary_hash,at_ms,at_ms+60000,a.version);
 IF created->>'created' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 PERFORM private.burimunsi_set_pin_context(p_temporary_token,actor.installation_id,device_token,actor.profile);
 UPDATE private.burimunsi_accounts SET pin_hash=p_new_hash,credential_version=credential_version+1,version=version+1,updated_at=at_ms
  WHERE collection_id=a.collection_id AND id=a.id AND credential_version=p_expected_credential AND version=p_expected_version AND active AND NOT removed;
 IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 UPDATE private.burimunsi_sessions SET revoked=true WHERE collection_id=a.collection_id AND account_id=a.id AND NOT revoked;
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;expires_ms:=at_ms+p_ttl_ms;
 created:=private.burimunsi_pin_create_session(a.collection_id,a.id,actor.installation_id,actor.profile,
  encode(sha256(convert_to(device_token,'UTF8')),'hex'),a.credential_version+1,replacement_session,p_replacement_hash,at_ms,expires_ms,a.version+1);
 IF created->>'created' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'burimunsi_invalid_credentials' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.pin_token',original_token,true);
 PERFORM set_config('burimunsi.pin_installation',installation_text,true);
 PERFORM set_config('burimunsi.pin_device',device_token,true);
 PERFORM set_config('burimunsi.pin_profile',original_profile,true);
 RETURN jsonb_build_object('rotated',true,'expiresAt',expires_ms);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.pin_token',coalesce(original_token,''),true);
 PERFORM set_config('burimunsi.pin_installation',coalesce(installation_text,''),true);
 PERFORM set_config('burimunsi.pin_device',coalesce(device_token,''),true);
 PERFORM set_config('burimunsi.pin_profile',coalesce(original_profile,''),true);
 RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_pin_rotate_passcode(uuid,uuid,bigint,bigint,jsonb,text,text,bigint)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_pin_rotate_passcode(uuid,uuid,bigint,bigint,jsonb,text,text,bigint) TO collect_runtime;
COMMIT;
