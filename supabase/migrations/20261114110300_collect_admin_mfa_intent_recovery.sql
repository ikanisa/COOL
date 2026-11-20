-- WORK IN PROGRESS. Admin-only, initiator-bound recovery of a lost provider
-- reply. This feature remains disabled pending exact-schema/race/browser UAT.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE r record;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR to_regprocedure('private.collect_admin_mfa_intent_begin_v1(text,text,text,text,uuid,uuid,text,text,bigint,bigint)') IS NOT NULL
  OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='private.bff_sessions'::regclass AND attname LIKE 'mfa_intent_%' AND NOT attisdropped) THEN
  RAISE EXCEPTION 'admin_mfa_intent_precondition' USING ERRCODE='55000';END IF;
 FOR r IN SELECT * FROM (VALUES
  ('private.collect_admin_mfa_authorize_v1(text,text,text,text,text,uuid)','7fc8f629df736f3b0e3ecd39aade96d40b442e4b1c8e27a66a8eaf42c14b9c85'),
  ('private.collect_admin_mfa_prepare_v1(text,text,text,text,bigint,text,uuid,text,text,text)','f0e97003e37e9c615185e3e2993d8e06d196e70e2f082a29ada234a6652de762'),
  ('private.collect_admin_mfa_complete_v1(text,text)','7f6273394c7b79875ee89246c02551fd93d5625c289f86eb57bde33ef04213e5'),
  ('private.collect_admin_mfa_restore_v1(text,text)','7275136718c4362a6363347dacc111cdbaba4bd4bb2864fb24841d55060f5c9f')
 ) e(sig,hash) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang WHERE p.oid=to_regprocedure(r.sig)
   AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef AND p.provolatile='v' AND p.prokind='f'
   AND p.proparallel='u' AND NOT p.proleakproof AND l.lanname='plpgsql'
   AND p.proacl::text='{postgres=X/postgres,collect_runtime=X/postgres}'
   AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp']::text[]
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.hash) THEN
   RAISE EXCEPTION 'admin_mfa_intent_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
END;$preflight$;

ALTER TABLE private.bff_sessions
 ADD COLUMN mfa_intent_hash text,
 ADD COLUMN mfa_intent_factor uuid,
 ADD COLUMN mfa_intent_challenge uuid,
 ADD COLUMN mfa_intent_started_at bigint,
 ADD COLUMN mfa_intent_old_tokens text,
 ADD COLUMN mfa_intent_candidate_ciphertext text,
 ADD CONSTRAINT bff_mfa_intent_complete CHECK (
  (mfa_intent_hash IS NULL AND mfa_intent_factor IS NULL AND mfa_intent_challenge IS NULL
   AND mfa_intent_started_at IS NULL AND mfa_intent_old_tokens IS NULL AND mfa_intent_candidate_ciphertext IS NULL)
  OR (mfa_intent_hash IS NOT NULL AND mfa_intent_hash ~ '^[a-f0-9]{64}$' AND mfa_intent_factor IS NOT NULL AND mfa_intent_challenge IS NOT NULL
   AND mfa_intent_started_at IS NOT NULL AND mfa_intent_started_at>0 AND mfa_intent_old_tokens IS NOT NULL AND app.json_valid(mfa_intent_old_tokens) IS TRUE
   AND (mfa_intent_candidate_ciphertext IS NULL OR app.json_valid(mfa_intent_candidate_ciphertext) IS TRUE)));

-- A challenge is bound before dispatch to the exact original Admin cookie,
-- current verified account, lease/version and a per-tab opaque intent hash.
CREATE FUNCTION private.collect_admin_mfa_intent_begin_v1(p_actor text,p_cookie text,p_origin text,p_public text,
 p_factor uuid,p_challenge uuid,p_intent text,p_lease text,p_until bigint,p_version bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE actor jsonb;at bigint:=app.unixepoch();n integer;
BEGIN
 IF p_factor IS NULL OR p_challenge IS NULL OR p_intent IS NULL OR p_intent !~ '^[a-f0-9]{64}$' OR p_lease IS NULL OR length(p_lease)>100
  OR p_version IS NULL OR p_until IS NULL OR p_until NOT BETWEEN at+1 AND at+60 THEN RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM private.collect_admin_mfa_authorize_v1(p_actor,p_cookie,p_origin,p_public,'verify',p_factor);
 actor:=private._admin_email_actor(p_actor,p_cookie,p_origin,p_public,true);
 PERFORM 1 FROM auth.mfa_challenges c JOIN auth.mfa_factors f ON f.id=c.factor_id
  WHERE c.id=p_challenge AND c.factor_id=p_factor AND f.user_id::text=actor->>'auth_user_id'
   AND c.verified_at IS NULL AND c.created_at BETWEEN clock_timestamp()-interval '300 seconds' AND clock_timestamp()+interval '1 second'
  FOR SHARE OF c,f;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 UPDATE private.bff_sessions SET refresh_lease=p_lease,refresh_lease_until=p_until,
  mfa_intent_hash=p_intent,mfa_intent_factor=p_factor,mfa_intent_challenge=p_challenge,
  mfa_intent_started_at=at,mfa_intent_old_tokens=token_ciphertext,mfa_intent_candidate_ciphertext=NULL
 WHERE token_hash=p_cookie AND version=p_version AND refresh_lease IS NULL AND mfa_pending_hash IS NULL AND mfa_intent_hash IS NULL;
 GET DIAGNOSTICS n=ROW_COUNT;IF n<>1 THEN RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('state','claimed','version',p_version);
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_intent_begin_v1(text,text,text,text,uuid,uuid,text,text,bigint,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_intent_begin_v1(text,text,text,text,uuid,uuid,text,text,bigint,bigint) TO collect_runtime;

-- A definite rejection may clear only the same intent, provided its challenge
-- remains unverified. An uncertain provider outcome never reaches this helper.
CREATE FUNCTION private.collect_admin_mfa_intent_release_v1(p_actor text,p_cookie text,p_origin text,p_public text,p_factor uuid,p_challenge uuid,p_intent text,p_lease text,p_version bigint)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM private._collect_fence_require_runtime();PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM 1 FROM auth.mfa_challenges c WHERE c.id=p_challenge AND c.factor_id=p_factor AND c.verified_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN RETURN false;END IF;
 UPDATE private.bff_sessions b SET refresh_lease=NULL,refresh_lease_until=NULL
 WHERE b.token_hash=p_cookie AND b.version=p_version AND b.refresh_lease=p_lease AND b.mfa_intent_hash=p_intent
  AND b.mfa_intent_factor=p_factor AND b.mfa_intent_challenge=p_challenge AND b.mfa_pending_hash IS NULL
  AND EXISTS(SELECT 1 FROM auth.mfa_challenges c WHERE c.id=p_challenge AND c.factor_id=p_factor AND c.verified_at IS NULL);
 IF NOT FOUND THEN RETURN false;END IF;
 PERFORM private.collect_admin_mfa_authorize_v1(p_actor,p_cookie,p_origin,p_public,'verify',p_factor);
 UPDATE private.bff_sessions SET mfa_intent_hash=NULL,mfa_intent_factor=NULL,mfa_intent_challenge=NULL,
  mfa_intent_started_at=NULL,mfa_intent_old_tokens=NULL,mfa_intent_candidate_ciphertext=NULL WHERE token_hash=p_cookie;
 RETURN FOUND;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_intent_release_v1(text,text,text,text,uuid,uuid,text,text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_intent_release_v1(text,text,text,text,uuid,uuid,text,text,bigint) TO collect_runtime;

-- Recover only after the original lease expires and the exact challenge was
-- verified. A staged candidate is recoverable only by the same intent.
CREATE FUNCTION private.collect_admin_mfa_intent_recover_v1(p_actor text,p_cookie text,p_origin text,p_public text,
 p_factor uuid,p_challenge uuid,p_intent text,p_lease text,p_until bigint)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE b private.bff_sessions%ROWTYPE;actor jsonb;at bigint:=app.unixepoch();
BEGIN
 IF p_factor IS NULL OR p_challenge IS NULL OR p_intent IS NULL OR p_intent !~ '^[a-f0-9]{64}$' OR p_lease IS NULL OR length(p_lease)>100
  OR p_until IS NULL OR p_until NOT BETWEEN at+1 AND at+60 THEN RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 SELECT bff.* INTO b FROM private.bff_sessions bff JOIN app.admin_sessions s ON s.token_hash=bff.token_hash
  WHERE bff.token_hash=p_cookie AND s.user_id=p_actor AND s.origin=p_origin AND s.public_id=p_public FOR UPDATE OF bff,s;
 IF NOT FOUND OR b.mfa_intent_hash IS DISTINCT FROM p_intent OR b.mfa_intent_factor IS DISTINCT FROM p_factor
  OR b.mfa_intent_challenge IS DISTINCT FROM p_challenge OR b.mfa_intent_started_at<at-300 THEN
  RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 IF b.refresh_lease IS NOT NULL AND b.refresh_lease_until>at THEN RAISE EXCEPTION 'admin_mfa_session_busy' USING ERRCODE='55000';END IF;
 UPDATE private.bff_sessions SET refresh_lease=NULL,refresh_lease_until=NULL WHERE token_hash=p_cookie;
 actor:=private.collect_admin_mfa_authorize_v1(p_actor,p_cookie,p_origin,p_public,'verify',p_factor);
 PERFORM 1 FROM auth.mfa_challenges c JOIN auth.mfa_factors f ON f.id=c.factor_id
  JOIN auth.sessions s ON s.user_id=f.user_id AND s.id=b.auth_session_id
  JOIN auth.mfa_amr_claims a ON a.session_id=s.id AND a.authentication_method='totp'
  WHERE c.id=p_challenge AND c.factor_id=p_factor AND f.user_id=b.auth_user_id AND f.status::text='verified'
   AND c.verified_at IS NOT NULL AND c.verified_at>=to_timestamp(b.mfa_intent_started_at-1)
   AND c.verified_at<=clock_timestamp()+interval '1 second' AND f.factor_type::text='totp'
   AND to_jsonb(s)->>'aal'='aal2' AND s.factor_id=p_factor
   AND abs(extract(epoch FROM (a.updated_at-c.verified_at)))<=2
  FOR SHARE OF c,f,s,a;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_proof_unavailable' USING ERRCODE='42501';END IF;
 IF b.mfa_pending_hash IS NOT NULL THEN
  IF b.mfa_pending_state<>'staged' OR b.mfa_intent_candidate_ciphertext IS NULL THEN RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
  RETURN jsonb_build_object('state','staged','candidate_ciphertext',b.mfa_intent_candidate_ciphertext,'candidate_hash',b.mfa_pending_hash);
 END IF;
 UPDATE private.bff_sessions SET refresh_lease=p_lease,refresh_lease_until=p_until WHERE token_hash=p_cookie;
 RETURN jsonb_build_object('state','claimed','version',b.version,'old_tokens',b.mfa_intent_old_tokens);
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_intent_recover_v1(text,text,text,text,uuid,uuid,text,text,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_intent_recover_v1(text,text,text,text,uuid,uuid,text,text,bigint) TO collect_runtime;

-- The original staged operation additionally proves its exact verified intent
-- and stores the candidate encrypted so a lost BFF response can be recovered.
CREATE FUNCTION private.collect_admin_mfa_intent_prepare_v1(p_actor text,p_cookie text,p_origin text,p_public text,p_version bigint,p_lease text,
 p_factor uuid,p_challenge uuid,p_intent text,p_new_hash text,p_new_ciphertext text,p_old_cookie_ciphertext text,p_candidate_ciphertext text)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE b private.bff_sessions%ROWTYPE;result jsonb;at bigint:=app.unixepoch();
BEGIN
 IF p_candidate_ciphertext IS NULL OR length(p_candidate_ciphertext)>4096 OR app.json_valid(p_candidate_ciphertext) IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 SELECT * INTO b FROM private.bff_sessions WHERE token_hash=p_cookie FOR UPDATE;
 IF NOT FOUND OR b.version<>p_version OR b.refresh_lease IS DISTINCT FROM p_lease OR b.refresh_lease_until<=at
  OR b.mfa_intent_hash IS DISTINCT FROM p_intent OR b.mfa_intent_factor IS DISTINCT FROM p_factor
  OR b.mfa_intent_challenge IS DISTINCT FROM p_challenge OR b.mfa_intent_started_at<at-300
  OR NOT EXISTS(SELECT 1 FROM auth.mfa_challenges c WHERE c.id=p_challenge AND c.factor_id=p_factor AND c.verified_at IS NOT NULL
   AND c.verified_at>=to_timestamp(b.mfa_intent_started_at-1)) THEN
  RAISE EXCEPTION 'admin_mfa_denied' USING ERRCODE='42501';END IF;
 result:=private.collect_admin_mfa_prepare_v1(p_actor,p_cookie,p_origin,p_public,p_version,p_lease,p_factor,p_new_hash,p_new_ciphertext,p_old_cookie_ciphertext);
 UPDATE private.bff_sessions SET mfa_intent_candidate_ciphertext=p_candidate_ciphertext
  WHERE token_hash=p_cookie AND mfa_pending_hash=p_new_hash AND mfa_intent_hash=p_intent;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 RETURN result;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_intent_prepare_v1(text,text,text,text,bigint,text,uuid,uuid,text,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_intent_prepare_v1(text,text,text,text,bigint,text,uuid,uuid,text,text,text,text,text) TO collect_runtime;

CREATE FUNCTION private.collect_admin_mfa_intent_complete_v1(p_candidate text,p_origin text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE result jsonb;
BEGIN
 result:=private.collect_admin_mfa_complete_v1(p_candidate,p_origin);
 UPDATE private.bff_sessions SET mfa_intent_hash=NULL,mfa_intent_factor=NULL,mfa_intent_challenge=NULL,
  mfa_intent_started_at=NULL,mfa_intent_old_tokens=NULL,mfa_intent_candidate_ciphertext=NULL WHERE token_hash=p_candidate AND mfa_pending_hash IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 RETURN result;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_intent_complete_v1(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_intent_complete_v1(text,text) TO collect_runtime;

CREATE FUNCTION private.collect_admin_mfa_intent_restore_v1(p_candidate text,p_origin text) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE result jsonb;
BEGIN
 result:=private.collect_admin_mfa_restore_v1(p_candidate,p_origin);
 UPDATE private.bff_sessions SET token_ciphertext=mfa_intent_old_tokens WHERE mfa_pending_hash=p_candidate
  AND mfa_pending_state='restoring' AND mfa_intent_old_tokens IS NOT NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_mfa_session_changed' USING ERRCODE='42501';END IF;
 RETURN result;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_intent_restore_v1(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_intent_restore_v1(text,text) TO collect_runtime;

-- The returned original cookie only resumes AAL1 after acknowledging the
-- exact rollback; a generic refresh must still refuse AAL2 token promotion.
CREATE FUNCTION private.collect_admin_mfa_intent_ack_restore_v1(p_actor text,p_cookie text,p_origin text,p_public text)
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM private.collect_admin_mfa_authorize_v1(p_actor,p_cookie,p_origin,p_public,'list',NULL);
 UPDATE private.bff_sessions SET mfa_pending_hash=NULL,mfa_pending_old_cookie_ciphertext=NULL,mfa_pending_factor=NULL,mfa_pending_at=NULL,mfa_pending_state=NULL,
  mfa_intent_hash=NULL,mfa_intent_factor=NULL,mfa_intent_challenge=NULL,mfa_intent_started_at=NULL,mfa_intent_old_tokens=NULL,mfa_intent_candidate_ciphertext=NULL
 WHERE token_hash=p_cookie AND mfa_pending_state='restoring' AND token_ciphertext=mfa_intent_old_tokens AND refresh_lease IS NULL;
 RETURN FOUND;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_admin_mfa_intent_ack_restore_v1(text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.collect_admin_mfa_intent_ack_restore_v1(text,text,text,text) TO collect_runtime;

-- Runtime may only reach the predecessor through the intent wrappers.
REVOKE EXECUTE ON FUNCTION private.collect_admin_mfa_prepare_v1(text,text,text,text,bigint,text,uuid,text,text,text),
 private.collect_admin_mfa_complete_v1(text,text),private.collect_admin_mfa_restore_v1(text,text) FROM collect_runtime;
COMMIT;
