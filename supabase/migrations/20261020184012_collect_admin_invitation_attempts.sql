-- PRIVATE PROPOSAL ONLY. Migration owner assigns an adoption timestamp.
-- One preparation and at most one native GoTrue /invite dispatch. This journal
-- does not claim delivery and does not create or confirm a managed Auth user.
CREATE TABLE private.admin_invitation_attempts (
 request_id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
 attempt_sequence bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
 actor_id text NOT NULL REFERENCES app.admin_users(id),
 actor_principal_id text NOT NULL REFERENCES app.users(id),
 idempotency_key text NOT NULL CHECK(idempotency_key ~ '^[A-Za-z0-9._:-]{8,200}$'),
 subject_id text NOT NULL REFERENCES app.admin_users(id),
 principal_id text NOT NULL REFERENCES app.users(id),
 body_sha256 text NOT NULL CHECK(body_sha256 ~ '^[0-9a-f]{64}$'),
 kind text NOT NULL CHECK(kind IN('invite','resend')),
 replayed_request_id uuid REFERENCES private.admin_invitation_attempts(request_id),
 original_session_id uuid NOT NULL,
 subject_identity_sha256 text NOT NULL CHECK(subject_identity_sha256 ~ '^[0-9a-f]{64}$'),
 state text NOT NULL CHECK(state IN('reserved','dispatching','accepted','rejected','unknown','already_registered')),
 claim_nonce uuid,
 dispatch_session_id uuid,
 created_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 claimed_at timestamptz,
 finished_at timestamptz,
 safe_error_code text CHECK(safe_error_code IS NULL OR safe_error_code IN('invitation_rejected','invitation_outcome_unknown','invitation_history_unknown','invitation_existing_request','email_exists')),
 UNIQUE(actor_id,idempotency_key),
 CHECK((claim_nonce IS NULL AND dispatch_session_id IS NULL AND claimed_at IS NULL)
    OR (claim_nonce IS NOT NULL AND dispatch_session_id IS NOT NULL AND claimed_at IS NOT NULL)),
 CHECK((state='reserved' AND claim_nonce IS NULL AND finished_at IS NULL AND safe_error_code IS NULL)
    OR (state='dispatching' AND claim_nonce IS NOT NULL AND finished_at IS NULL AND safe_error_code IS NULL)
    OR (state IN('accepted','rejected') AND claim_nonce IS NOT NULL AND finished_at IS NOT NULL)
    OR (state IN('unknown','already_registered') AND finished_at IS NOT NULL)),
 CHECK(claimed_at IS NULL OR claimed_at>=created_at),
 CHECK(finished_at IS NULL OR finished_at>=coalesce(claimed_at,created_at)),
 CHECK(replayed_request_id IS NULL OR (replayed_request_id<>request_id AND state='unknown' AND claim_nonce IS NULL AND safe_error_code='invitation_existing_request'))
);
CREATE INDEX admin_invitation_subject_latest ON private.admin_invitation_attempts(subject_id,attempt_sequence DESC);

CREATE FUNCTION private.trg_admin_invitation_identity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='42501';END IF;
 IF to_jsonb(NEW)-ARRAY['state','claim_nonce','dispatch_session_id','claimed_at','finished_at','safe_error_code']
    IS DISTINCT FROM to_jsonb(OLD)-ARRAY['state','claim_nonce','dispatch_session_id','claimed_at','finished_at','safe_error_code']
 THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 IF NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW;END IF;
 IF OLD.state='reserved' AND NEW.state='dispatching' AND NEW.claim_nonce IS NOT NULL
    AND NEW.dispatch_session_id IS NOT NULL AND NEW.claimed_at IS NOT NULL
    AND NEW.finished_at IS NULL AND NEW.safe_error_code IS NULL THEN RETURN NEW;END IF;
 IF OLD.state='reserved' AND NEW.state='already_registered' AND NEW.claim_nonce IS NULL
    AND NEW.dispatch_session_id IS NULL AND NEW.claimed_at IS NULL AND NEW.finished_at IS NOT NULL
    AND NEW.safe_error_code='email_exists' THEN RETURN NEW;END IF;
 IF OLD.state='dispatching' AND NEW.state IN('accepted','rejected','unknown','already_registered')
    AND NEW.claim_nonce=OLD.claim_nonce AND NEW.dispatch_session_id=OLD.dispatch_session_id
    AND NEW.claimed_at=OLD.claimed_at AND NEW.finished_at IS NOT NULL THEN RETURN NEW;END IF;
 RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='42501';
END$$;
CREATE TRIGGER admin_invitation_identity BEFORE UPDATE OR DELETE ON private.admin_invitation_attempts
FOR EACH ROW EXECUTE FUNCTION private.trg_admin_invitation_identity();

-- The caller's cookie tuple is required in addition to the signed managed
-- claims. A fresh managed owner in a different browser is not this cookie.
CREATE FUNCTION private.admin_invitation_actor(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE principal text; session_uuid uuid; claims jsonb:=private.request_claims(); current_epoch bigint:=app.unixepoch();
BEGIN
 BEGIN
  principal:=private.assert_actor('admin_users.manage',NULL,NULL,2,300);
  session_uuid:=(claims->>'session_id')::uuid;
  IF p_actor_id IS NULL OR p_cookie_hash IS NULL OR p_cookie_hash !~ '^[0-9a-f]{64}$'
     OR p_origin IS NULL OR length(p_origin)>2048 OR p_origin !~ '^https://[^/?#@]+$'
     OR p_public_session_id IS NULL OR length(p_public_session_id) NOT BETWEEN 1 AND 200
     OR NOT coalesce(private.is_managed_session((claims->>'sub')::uuid,session_uuid),false)
  THEN RAISE EXCEPTION 'admin_invitation_authority';END IF;
  PERFORM 1 FROM app.admin_users a
   JOIN app.admin_principal_links l ON l.admin_user_id=a.id AND l.user_id=principal
   JOIN app.users u ON u.id=l.user_id AND u.access_status='active'
   JOIN app.admin_sessions c ON c.user_id=a.id AND c.auth_version=a.auth_version
   JOIN app.auth_sessions s ON s.id=c.auth_session_id AND s.user_id=principal
   JOIN private.bff_sessions b ON b.token_hash=c.token_hash AND b.auth_session_id=session_uuid
   JOIN private.auth_principal_links p ON p.auth_user_id=b.auth_user_id AND p.user_id=principal
   JOIN private.managed_mfa_proofs m ON m.session_id=b.auth_session_id AND m.user_id=b.auth_user_id
   JOIN auth.sessions actual ON actual.id=m.session_id AND actual.user_id=m.user_id
   JOIN auth.mfa_factors f ON f.id=m.factor_id AND f.user_id=m.user_id
   WHERE a.id=p_actor_id AND a.email='info@ikanisa.com' AND a.role='owner' AND a.status='active'
   AND c.token_hash=p_cookie_hash AND c.public_id=p_public_session_id AND c.origin=p_origin
   AND c.auth_session_id=session_uuid::text AND c.expires_at>current_epoch
   AND c.issued_assurance_level=2 AND c.issued_mfa_at BETWEEN current_epoch-300 AND current_epoch
   AND c.issued_mfa_at=s.mfa_at AND c.issued_mfa_factor_id=s.mfa_factor_id
   AND s.surface='admin' AND s.revoked_at IS NULL AND s.expires_at>current_epoch
   AND s.assurance_level=2 AND b.auth_user_id::text=claims->>'sub'
   AND b.refresh_lease IS NULL AND m.verified_at_epoch=s.mfa_at AND m.factor_id::text=s.mfa_factor_id
   AND f.status::text='verified' AND to_jsonb(actual)->>'aal'='aal2'
   AND (to_jsonb(actual)->>'factor_id' IS NULL OR to_jsonb(actual)->>'factor_id'=m.factor_id::text)
   FOR SHARE OF a,l,u,c,s,b,p,m,actual,f;
  IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_authority';END IF;
 EXCEPTION WHEN OTHERS THEN
  RAISE EXCEPTION 'admin_invitation_authority' USING ERRCODE='42501';
 END;
 RETURN session_uuid;
END$$;

CREATE FUNCTION private.admin_invitation_fingerprint(p_subject_id text) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT encode(sha256(convert_to(jsonb_build_array(a.id,a.email,a.role,a.display_name,l.user_id)::text,'UTF8')),'hex')
 FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id WHERE a.id=p_subject_id
$$;

-- Read actual managed identity, never an app email or user metadata. A linked
-- unconfirmed identity cannot be repurposed into an approved Admin principal.
-- Without a private link, a local email/confirmed-phone match is ambiguous:
-- refuse it before creation rather than shadowing or auto-linking that member.
-- A confirmed identity with no link and no local match remains a no-send
-- result; normal Admin authentication owns its existing linking checks.
CREATE FUNCTION private.admin_invitation_target(p_email text,p_expected_principal text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE target record; total integer:=0; confirmed boolean:=false; linked_principal text; canonical_confirmed_phone text;
BEGIN
 FOR target IN SELECT u.id,u.email_confirmed_at,to_jsonb(u) AS document FROM auth.users u
   WHERE lower(u.email)=p_email FOR SHARE OF u
 LOOP
  total:=total+1;
  IF total>1 OR target.document->>'deleted_at' IS NOT NULL
     OR (target.document->>'banned_until' IS NOT NULL AND (target.document->>'banned_until')::timestamptz>now())
  THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
  confirmed:=target.email_confirmed_at IS NOT NULL;
  IF target.document->>'phone_confirmed_at' IS NOT NULL AND target.document->>'phone' ~ '^\+?[1-9][0-9]{6,14}$'
  THEN canonical_confirmed_phone:='+'||ltrim(target.document->>'phone','+');END IF;
  SELECT l.user_id INTO linked_principal FROM private.auth_principal_links l WHERE l.auth_user_id=target.id FOR SHARE OF l;
  IF linked_principal IS NOT NULL THEN
   PERFORM 1 FROM app.users u WHERE u.id=linked_principal AND u.access_status='active' FOR SHARE OF u;
   IF NOT FOUND OR NOT confirmed OR (p_expected_principal IS NOT NULL AND linked_principal<>p_expected_principal)
   THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
  END IF;
 END LOOP;
 IF linked_principal IS NULL AND EXISTS(SELECT 1 FROM app.users u WHERE lower(u.email)=p_email
   OR (canonical_confirmed_phone IS NOT NULL AND u.phone=canonical_confirmed_phone))
 THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('confirmed',confirmed,'principalId',linked_principal);
END$$;

CREATE FUNCTION private.admin_invitation_result(p_attempt private.admin_invitation_attempts,p_replayed boolean)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE result jsonb; source private.admin_invitation_attempts%ROWTYPE;
BEGIN
 source:=p_attempt;
 IF p_attempt.replayed_request_id IS NOT NULL THEN
  SELECT * INTO source FROM private.admin_invitation_attempts r WHERE r.request_id=p_attempt.replayed_request_id AND r.replayed_request_id IS NULL;
  IF NOT FOUND OR source.subject_id<>p_attempt.subject_id OR source.principal_id<>p_attempt.principal_id
     OR source.subject_identity_sha256<>p_attempt.subject_identity_sha256
  THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 END IF;
 SELECT jsonb_build_object('requestId',source.request_id::text,'id',a.id,'principalId',source.principal_id,
   'email',a.email,'emailStatus',source.state,'replayed',p_replayed OR p_attempt.replayed_request_id IS NOT NULL,
   'duplicate',p_attempt.replayed_request_id IS NOT NULL,'sourceRequestId',source.request_id::text,
   'operation',p_attempt.kind,'accessStatus',a.status)
 INTO result FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id
 WHERE a.id=source.subject_id AND l.user_id=source.principal_id
 AND private.admin_invitation_fingerprint(a.id)=source.subject_identity_sha256;
 IF result IS NULL THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 RETURN result;
END$$;

CREATE FUNCTION private.admin_invitation_prepare(
 p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,
 p_idempotency_key text,p_kind text,p_subject_id text,p_new_principal_id text,
 p_email text,p_role text,p_display_name text,p_body_sha256 text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE session_uuid uuid; actor_principal text; attempt private.admin_invitation_attempts%ROWTYPE; prior private.admin_invitation_attempts%ROWTYPE;
 subject app.admin_users%ROWTYPE; principal text; managed jsonb; initial_state text; allocated_public_id text; duplicate_subject boolean:=false;
 current_epoch bigint:=app.unixepoch(); timestamp_text text:=app.strftime('%Y-%m-%dT%H:%M:%fZ','now'); attempt_created timestamptz:=clock_timestamp();
BEGIN
 -- Same lock order as PostgresDatabase.batch, before any authority row locks.
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 session_uuid:=private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 actor_principal:=api.current_principal_id();
 IF actor_principal IS NULL THEN RAISE EXCEPTION 'admin_invitation_authority' USING ERRCODE='42501';END IF;
 IF p_idempotency_key IS NULL OR p_idempotency_key !~ '^[A-Za-z0-9._:-]{8,200}$'
    OR p_kind IS NULL OR p_kind NOT IN('invite','resend') OR p_body_sha256 IS NULL OR p_body_sha256 !~ '^[0-9a-f]{64}$'
    OR p_subject_id IS NULL OR p_subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO attempt FROM private.admin_invitation_attempts r WHERE r.actor_id=p_actor_id AND r.idempotency_key=p_idempotency_key FOR UPDATE;
 IF FOUND THEN
  IF attempt.kind<>p_kind OR attempt.body_sha256<>p_body_sha256 OR (p_kind='resend' AND attempt.subject_id<>p_subject_id)
  THEN RAISE EXCEPTION 'admin_invitation_idempotency_conflict' USING ERRCODE='22023';END IF;
  IF p_kind='invite' AND NOT EXISTS(SELECT 1 FROM app.admin_users a WHERE a.id=attempt.subject_id AND a.email=p_email AND a.role=p_role AND a.display_name=p_display_name)
  THEN RAISE EXCEPTION 'admin_invitation_idempotency_conflict' USING ERRCODE='22023';END IF;
  RETURN private.admin_invitation_result(attempt,true);
 END IF;
 IF p_kind='invite' THEN
  IF p_email IS NULL OR p_email<>lower(btrim(p_email)) OR length(p_email) NOT BETWEEN 3 AND 254
     OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' OR p_email ~ '[[:cntrl:]]'
     OR p_email='info@ikanisa.com' OR p_role IS NULL OR p_role NOT IN('admin','staff')
     OR p_display_name IS NULL OR p_display_name<>btrim(p_display_name) OR length(p_display_name)>120 OR p_display_name ~ '[[:cntrl:]]'
     OR p_new_principal_id IS NULL OR p_new_principal_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='22023';END IF;
  SELECT * INTO subject FROM app.admin_users a WHERE lower(a.email)=p_email FOR UPDATE;
  duplicate_subject:=FOUND;
  IF duplicate_subject AND (subject.role<>p_role OR subject.display_name<>p_display_name)
  THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 ELSE
  SELECT * INTO subject FROM app.admin_users a WHERE a.id=p_subject_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='22023';END IF;
  duplicate_subject:=true;
 END IF;
 IF duplicate_subject THEN
  IF subject.role='owner' OR subject.status='revoked' OR (p_kind='resend' AND subject.status<>'invited')
  THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;
  SELECT l.user_id INTO principal FROM app.admin_principal_links l JOIN app.users u ON u.id=l.user_id
   WHERE l.admin_user_id=subject.id AND u.access_status='active' FOR SHARE OF l,u;
  IF principal IS NULL THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
  SELECT * INTO prior FROM private.admin_invitation_attempts r WHERE r.subject_id=subject.id AND r.replayed_request_id IS NULL ORDER BY r.attempt_sequence DESC LIMIT 1 FOR UPDATE;
  IF FOUND THEN
   PERFORM private.admin_invitation_result(prior,true);
   -- Only explicit resend following a known accepted/rejected outcome may
   -- reserve another dispatch. Unknown and dispatching retain their history.
   IF p_kind='invite' OR prior.state NOT IN('accepted','rejected') THEN
    INSERT INTO private.admin_invitation_attempts(actor_id,actor_principal_id,idempotency_key,subject_id,principal_id,body_sha256,kind,replayed_request_id,
      original_session_id,subject_identity_sha256,state,created_at,finished_at,safe_error_code)
     VALUES(p_actor_id,actor_principal,p_idempotency_key,subject.id,principal,p_body_sha256,p_kind,prior.request_id,
      session_uuid,prior.subject_identity_sha256,'unknown',attempt_created,attempt_created,'invitation_existing_request') RETURNING * INTO attempt;
    RETURN private.admin_invitation_result(attempt,true);
   END IF;
  ELSE
   initial_state:='unknown';
  END IF;
  IF initial_state IS NULL THEN
   managed:=private.admin_invitation_target(subject.email,principal);
   initial_state:=CASE WHEN (managed->>'confirmed')::boolean THEN 'already_registered' ELSE 'reserved' END;
  END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM app.admin_users a WHERE a.id=p_subject_id)
  THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
  managed:=private.admin_invitation_target(p_email,NULL);
  principal:=managed->>'principalId';
  IF principal IS NOT NULL AND EXISTS(SELECT 1 FROM app.admin_principal_links l WHERE l.user_id=principal)
  THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
  IF principal IS NULL THEN
   principal:=p_new_principal_id;
   IF EXISTS(SELECT 1 FROM app.users u WHERE u.id=principal)
   THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
   SELECT app.printf('%06d',min(candidate)) INTO allocated_public_id
    FROM (SELECT 0::bigint AS candidate UNION ALL SELECT u.public_id::bigint+1 FROM app.users u WHERE u.public_id<>'999999') c
    WHERE candidate<1000000 AND NOT EXISTS(SELECT 1 FROM app.users u WHERE u.public_id=app.printf('%06d',candidate));
   IF allocated_public_id IS NULL THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='54000';END IF;
   INSERT INTO app.users(id,public_id,full_name,member_type,created_at,updated_at)
    VALUES(principal,allocated_public_id,p_display_name,'operator',timestamp_text,timestamp_text);
  END IF;
  INSERT INTO app.admin_users(id,email,role,status,display_name,created_at,invited_at,updated_at)
   VALUES(p_subject_id,p_email,p_role,'invited',p_display_name,current_epoch,current_epoch,current_epoch) RETURNING * INTO subject;
  INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES(subject.id,principal,p_actor_id,timestamp_text);
  initial_state:=CASE WHEN (managed->>'confirmed')::boolean THEN 'already_registered' ELSE 'reserved' END;
 END IF;
 INSERT INTO private.admin_invitation_attempts(actor_id,actor_principal_id,idempotency_key,subject_id,principal_id,body_sha256,kind,original_session_id,
   subject_identity_sha256,state,created_at,finished_at,safe_error_code)
 VALUES(p_actor_id,actor_principal,p_idempotency_key,subject.id,principal,p_body_sha256,p_kind,session_uuid,
   private.admin_invitation_fingerprint(subject.id),initial_state,attempt_created,
   CASE WHEN initial_state IN('unknown','already_registered') THEN attempt_created END,
   CASE initial_state WHEN 'unknown' THEN 'invitation_history_unknown' WHEN 'already_registered' THEN 'email_exists' END)
 RETURNING * INTO attempt;
 RETURN private.admin_invitation_result(attempt,false);
END$$;

CREATE FUNCTION private.admin_invitation_claim(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,p_request_id uuid,p_claim_nonce uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE session_uuid uuid; attempt private.admin_invitation_attempts%ROWTYPE; managed jsonb; result jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 session_uuid:=private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 IF p_request_id IS NULL OR p_claim_nonce IS NULL THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO attempt FROM private.admin_invitation_attempts r WHERE r.request_id=p_request_id AND r.actor_id=p_actor_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;
 IF attempt.replayed_request_id IS NOT NULL THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='42501';END IF;
 result:=private.admin_invitation_result(attempt,true);
 IF attempt.state<>'reserved' THEN RETURN result||jsonb_build_object('claimed',false);END IF;
 PERFORM 1 FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id AND l.user_id=attempt.principal_id
   JOIN app.users u ON u.id=l.user_id
   WHERE a.id=attempt.subject_id AND a.status='invited' AND a.role IN('admin','staff') AND u.access_status='active'
   AND private.admin_invitation_fingerprint(a.id)=attempt.subject_identity_sha256 FOR SHARE OF a,l,u;
 IF NOT FOUND
 THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;
 managed:=private.admin_invitation_target(result->>'email',attempt.principal_id);
 IF (managed->>'confirmed')::boolean THEN
  UPDATE private.admin_invitation_attempts SET state='already_registered',finished_at=clock_timestamp(),safe_error_code='email_exists'
   WHERE request_id=attempt.request_id AND state='reserved' RETURNING * INTO attempt;
  RETURN private.admin_invitation_result(attempt,false)||jsonb_build_object('claimed',false);
 END IF;
 UPDATE private.admin_invitation_attempts SET state='dispatching',claim_nonce=p_claim_nonce,
   dispatch_session_id=session_uuid,claimed_at=clock_timestamp()
  WHERE request_id=attempt.request_id AND state='reserved' AND claim_nonce IS NULL RETURNING * INTO attempt;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='42501';END IF;
 RETURN private.admin_invitation_result(attempt,false)||jsonb_build_object('claimed',true);
END$$;

CREATE FUNCTION private.admin_invitation_finish(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,p_request_id uuid,p_claim_nonce uuid,p_state text,p_error_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE session_uuid uuid; attempt private.admin_invitation_attempts%ROWTYPE; result jsonb; managed jsonb; safe_code text;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 session_uuid:=private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 IF p_request_id IS NULL OR p_claim_nonce IS NULL OR p_state IS NULL OR p_state NOT IN('accepted','rejected','unknown','already_registered')
 THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO attempt FROM private.admin_invitation_attempts r WHERE r.request_id=p_request_id AND r.actor_id=p_actor_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;
 IF attempt.replayed_request_id IS NOT NULL THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='42501';END IF;
 IF attempt.claim_nonce IS DISTINCT FROM p_claim_nonce OR attempt.dispatch_session_id IS DISTINCT FROM session_uuid
 THEN RAISE EXCEPTION 'admin_invitation_authority' USING ERRCODE='42501';END IF;
 result:=private.admin_invitation_result(attempt,true);
 PERFORM 1 FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id AND l.user_id=attempt.principal_id
   JOIN app.users u ON u.id=l.user_id
   WHERE a.id=attempt.subject_id AND a.status IN('invited','active') AND a.role IN('admin','staff') AND u.access_status='active'
   AND private.admin_invitation_fingerprint(a.id)=attempt.subject_identity_sha256 FOR SHARE OF a,l,u;
 IF NOT FOUND
 THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;
 IF attempt.state=p_state THEN RETURN result;END IF;
 IF attempt.state<>'dispatching' THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='42501';END IF;
 IF p_state='already_registered' THEN
  IF p_error_code IS DISTINCT FROM 'email_exists' THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='22023';END IF;
  managed:=private.admin_invitation_target(result->>'email',attempt.principal_id);
  IF NOT (managed->>'confirmed')::boolean THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 END IF;
 safe_code:=CASE p_state WHEN 'rejected' THEN 'invitation_rejected' WHEN 'unknown' THEN 'invitation_outcome_unknown' WHEN 'already_registered' THEN 'email_exists' END;
 UPDATE private.admin_invitation_attempts SET state=p_state,finished_at=clock_timestamp(),safe_error_code=safe_code
  WHERE request_id=attempt.request_id AND state='dispatching' AND claim_nonce=p_claim_nonce AND dispatch_session_id=session_uuid RETURNING * INTO attempt;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='42501';END IF;
 RETURN private.admin_invitation_result(attempt,false);
END$$;

CREATE FUNCTION private.admin_invitation_recover(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,p_idempotency_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE attempt private.admin_invitation_attempts%ROWTYPE;
BEGIN
 -- No journal writes or provider work. The lock keeps the same lock order as
 -- mutations while obtaining current authority SHARE locks in this transaction.
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 IF p_idempotency_key IS NULL OR p_idempotency_key !~ '^[A-Za-z0-9._:-]{8,200}$'
 THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO attempt FROM private.admin_invitation_attempts r WHERE r.actor_id=p_actor_id AND r.idempotency_key=p_idempotency_key;
 IF NOT FOUND THEN RETURN jsonb_build_object('found',false);END IF;
 RETURN private.admin_invitation_result(attempt,true)||jsonb_build_object('found',true);
END$$;

ALTER TABLE private.admin_invitation_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY edge_runtime_read ON private.admin_invitation_attempts FOR SELECT TO collect_runtime USING(true);
REVOKE ALL ON TABLE private.admin_invitation_attempts FROM PUBLIC,anon,authenticated,collect_runtime;
GRANT SELECT ON TABLE private.admin_invitation_attempts TO collect_runtime;
REVOKE ALL ON SEQUENCE private.admin_invitation_attempts_attempt_sequence_seq FROM PUBLIC,anon,authenticated,collect_runtime;
REVOKE ALL ON FUNCTION private.trg_admin_invitation_identity(),private.admin_invitation_actor(text,text,text,text),
 private.admin_invitation_fingerprint(text),private.admin_invitation_target(text,text),
 private.admin_invitation_result(private.admin_invitation_attempts,boolean) FROM PUBLIC,anon,authenticated,collect_runtime;
REVOKE ALL ON FUNCTION private.admin_invitation_prepare(text,text,text,text,text,text,text,text,text,text,text,text),
 private.admin_invitation_claim(text,text,text,text,uuid,uuid),private.admin_invitation_finish(text,text,text,text,uuid,uuid,text,text),
 private.admin_invitation_recover(text,text,text,text,text) FROM PUBLIC,anon,authenticated,collect_runtime;
GRANT EXECUTE ON FUNCTION private.admin_invitation_prepare(text,text,text,text,text,text,text,text,text,text,text,text),
 private.admin_invitation_claim(text,text,text,text,uuid,uuid),private.admin_invitation_finish(text,text,text,text,uuid,uuid,text,text),
 private.admin_invitation_recover(text,text,text,text,text) TO collect_runtime;
