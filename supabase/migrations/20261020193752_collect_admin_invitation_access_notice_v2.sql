-- PRIVATE UNVERSIONED ADDITIVE PROPOSAL. Apply transactionally by Migration.
-- Existing v1 history/bodies stay intact; V2 chooses a message before any I/O.
ALTER TABLE private.admin_invitation_attempts
 ADD COLUMN contract_version bigint NOT NULL DEFAULT 1,
 ADD COLUMN message_kind text NOT NULL DEFAULT 'auth_invite',
 ADD COLUMN template_version text NOT NULL DEFAULT 'managed_invite_v1',
 ADD COLUMN managed_auth_user_id uuid,
 ADD COLUMN notice_origin text,
 ADD COLUMN source_request_id uuid REFERENCES private.admin_invitation_attempts(request_id);
ALTER TABLE private.admin_invitation_attempts DROP CONSTRAINT admin_invitation_attempts_kind_check;
ALTER TABLE private.admin_invitation_attempts ADD CONSTRAINT admin_invitation_attempts_kind_check CHECK(kind IN('invite','resend','notice_repair'));
ALTER TABLE private.admin_invitation_attempts ADD CONSTRAINT admin_invitation_version_shape CHECK((
 (contract_version=1 AND kind IN('invite','resend') AND message_kind='auth_invite' AND template_version='managed_invite_v1'
  AND managed_auth_user_id IS NULL AND notice_origin IS NULL AND source_request_id IS NULL)
 OR
 (contract_version=2
  AND ((message_kind='auth_invite' AND template_version='managed_invite_v1' AND notice_origin IS NULL)
   OR (message_kind='access_notice' AND template_version='access_notice_v1' AND managed_auth_user_id IS NOT NULL
    AND notice_origin ~ '^https://[^/?#@]+$' AND length(notice_origin)<=2048 AND state<>'already_registered'))
  AND (source_request_id IS NULL OR source_request_id<>request_id)
  AND (replayed_request_id IS NOT NULL OR kind<>'notice_repair' OR (message_kind='access_notice' AND source_request_id IS NOT NULL)))
) IS TRUE);
CREATE INDEX admin_invitation_notice_source ON private.admin_invitation_attempts(source_request_id,attempt_sequence DESC)
 WHERE contract_version=2 AND kind='notice_repair' AND replayed_request_id IS NULL;

-- Snapshot the selected Auth subject under a row lock. Common target validation
-- still owns ambiguity, banned/deleted, active canonical mapping and shadowing.
-- FOR UPDATE also fences a concurrent FK-based private link insertion until
-- this short preparation/claim transaction commits. No Auth write is performed.
CREATE FUNCTION private.admin_invitation_v2_target(p_email text,p_expected_principal text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE selected uuid; target jsonb;
BEGIN
 SELECT a.id INTO selected FROM auth.users a WHERE lower(a.email)=p_email FOR UPDATE OF a;
 target:=private.admin_invitation_target(p_email,p_expected_principal);
 IF (target->>'confirmed')::boolean AND selected IS NULL
 THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 RETURN target||jsonb_build_object('managedAuthUserId',selected);
END$$;

CREATE FUNCTION private.admin_invitation_v2_result(p_attempt private.admin_invitation_attempts,p_replayed boolean) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actual private.admin_invitation_attempts%ROWTYPE; result jsonb;
BEGIN
 actual:=p_attempt;
 IF p_attempt.replayed_request_id IS NOT NULL THEN
  SELECT * INTO actual FROM private.admin_invitation_attempts r WHERE r.request_id=p_attempt.replayed_request_id AND r.replayed_request_id IS NULL;
  IF NOT FOUND OR actual.subject_id<>p_attempt.subject_id OR actual.principal_id<>p_attempt.principal_id
   OR actual.subject_identity_sha256<>p_attempt.subject_identity_sha256
  THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 END IF;
 SELECT jsonb_build_object('contractVersion',2,'requestId',actual.request_id::text,'id',a.id,'principalId',actual.principal_id,
   'email',a.email,'emailStatus',actual.state,'accessStatus',a.status,'operation',p_attempt.kind,
   'replayed',p_replayed OR p_attempt.replayed_request_id IS NOT NULL,'duplicate',p_attempt.replayed_request_id IS NOT NULL,
   'messageKind',actual.message_kind,'templateVersion',actual.template_version,'managedAuthUserId',actual.managed_auth_user_id,
   'noticeOrigin',actual.notice_origin,'sourceRequestId',actual.source_request_id)
  INTO result FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id
  WHERE a.id=actual.subject_id AND l.user_id=actual.principal_id AND private.admin_invitation_fingerprint(a.id)=actual.subject_identity_sha256;
 IF result IS NULL THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 RETURN result;
END$$;

-- Retain original v1 implementations as owner-only internal functions. Wrappers
-- reject cross-version keys/IDs and new incompatible duplicate-target requests.
ALTER FUNCTION private.admin_invitation_prepare(text,text,text,text,text,text,text,text,text,text,text,text) RENAME TO admin_invitation_v1_prepare_legacy;
ALTER FUNCTION private.admin_invitation_claim(text,text,text,text,uuid,uuid) RENAME TO admin_invitation_v1_claim_legacy;
ALTER FUNCTION private.admin_invitation_finish(text,text,text,text,uuid,uuid,text,text) RENAME TO admin_invitation_v1_finish_legacy;
ALTER FUNCTION private.admin_invitation_recover(text,text,text,text,text) RENAME TO admin_invitation_v1_recover_legacy;
REVOKE ALL ON FUNCTION private.admin_invitation_v1_prepare_legacy(text,text,text,text,text,text,text,text,text,text,text,text),
 private.admin_invitation_v1_claim_legacy(text,text,text,text,uuid,uuid),private.admin_invitation_v1_finish_legacy(text,text,text,text,uuid,uuid,text,text),
 private.admin_invitation_v1_recover_legacy(text,text,text,text,text) FROM PUBLIC,anon,authenticated,collect_runtime;

CREATE FUNCTION private.admin_invitation_v1_guard(p_actor_id text,p_key text,p_request uuid,p_subject text,p_email text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE retained private.admin_invitation_attempts%ROWTYPE;
BEGIN
 IF p_key IS NOT NULL THEN
  SELECT * INTO retained FROM private.admin_invitation_attempts r WHERE r.actor_id=p_actor_id AND r.idempotency_key=p_key;
  IF FOUND THEN
   IF retained.contract_version<>1 OR EXISTS(SELECT 1 FROM private.admin_invitation_attempts source WHERE source.request_id=retained.replayed_request_id AND source.contract_version<>1)
   THEN RAISE EXCEPTION 'admin_invitation_version_conflict' USING ERRCODE='22023';END IF;
   RETURN;
  END IF;
 ELSIF p_request IS NOT NULL THEN
  SELECT * INTO retained FROM private.admin_invitation_attempts r WHERE r.actor_id=p_actor_id AND r.request_id=p_request;
  IF FOUND AND retained.contract_version<>1 THEN RAISE EXCEPTION 'admin_invitation_version_conflict' USING ERRCODE='22023';END IF;
  RETURN;
 END IF;
 SELECT r.* INTO retained FROM private.admin_invitation_attempts r JOIN app.admin_users a ON a.id=r.subject_id
  WHERE r.replayed_request_id IS NULL AND ((p_subject IS NOT NULL AND a.id=p_subject) OR (p_email IS NOT NULL AND lower(a.email)=p_email))
  ORDER BY r.attempt_sequence DESC LIMIT 1;
 IF FOUND AND retained.contract_version<>1 THEN RAISE EXCEPTION 'admin_invitation_version_conflict' USING ERRCODE='22023';END IF;
END$$;

CREATE FUNCTION private.admin_invitation_prepare(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,
 p_idempotency_key text,p_kind text,p_subject_id text,p_new_principal_id text,p_email text,p_role text,p_display_name text,p_body_sha256 text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 PERFORM private.admin_invitation_v1_guard(p_actor_id,p_idempotency_key,NULL,CASE WHEN p_kind='resend' THEN p_subject_id END,CASE WHEN p_kind='invite' THEN p_email END);
 RETURN private.admin_invitation_v1_prepare_legacy(p_actor_id,p_cookie_hash,p_origin,p_public_session_id,p_idempotency_key,p_kind,p_subject_id,p_new_principal_id,p_email,p_role,p_display_name,p_body_sha256);
END$$;
CREATE FUNCTION private.admin_invitation_claim(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,p_request_id uuid,p_claim_nonce uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);PERFORM private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 PERFORM private.admin_invitation_v1_guard(p_actor_id,NULL,p_request_id,NULL,NULL);
 RETURN private.admin_invitation_v1_claim_legacy(p_actor_id,p_cookie_hash,p_origin,p_public_session_id,p_request_id,p_claim_nonce);
END$$;
CREATE FUNCTION private.admin_invitation_finish(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,p_request_id uuid,p_claim_nonce uuid,p_state text,p_error_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);PERFORM private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 PERFORM private.admin_invitation_v1_guard(p_actor_id,NULL,p_request_id,NULL,NULL);
 RETURN private.admin_invitation_v1_finish_legacy(p_actor_id,p_cookie_hash,p_origin,p_public_session_id,p_request_id,p_claim_nonce,p_state,p_error_code);
END$$;
CREATE FUNCTION private.admin_invitation_recover(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,p_idempotency_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);PERFORM private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 PERFORM private.admin_invitation_v1_guard(p_actor_id,p_idempotency_key,NULL,NULL,NULL);
 RETURN private.admin_invitation_v1_recover_legacy(p_actor_id,p_cookie_hash,p_origin,p_public_session_id,p_idempotency_key);
END$$;

CREATE FUNCTION private.admin_invitation_v2_prepare(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,
 p_idempotency_key text,p_kind text,p_subject_id text,p_new_principal_id text,p_email text,p_role text,p_display_name text,p_body_sha256 text,p_source_request_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE session_uuid uuid; actor_principal text; attempt private.admin_invitation_attempts%ROWTYPE; prior private.admin_invitation_attempts%ROWTYPE;
 source private.admin_invitation_attempts%ROWTYPE; subject app.admin_users%ROWTYPE; principal text; target jsonb;
 selected_kind text:='auth_invite'; selected_template text:='managed_invite_v1'; selected_auth uuid; lineage uuid; selected_origin text;
 initial_state text:='reserved'; allocated_public_id text; duplicate_subject boolean:=false; alias_source uuid;
 current_epoch bigint:=app.unixepoch(); stamp text:=app.strftime('%Y-%m-%dT%H:%M:%fZ','now'); created timestamptz:=clock_timestamp();
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 session_uuid:=private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);actor_principal:=api.current_principal_id();
 IF actor_principal IS NULL THEN RAISE EXCEPTION 'admin_invitation_authority' USING ERRCODE='42501';END IF;
 IF p_idempotency_key IS NULL OR p_idempotency_key !~ '^[A-Za-z0-9._:-]{8,200}$' OR p_kind IS NULL OR p_kind NOT IN('invite','resend','notice_repair')
  OR p_body_sha256 IS NULL OR p_body_sha256 !~ '^[0-9a-f]{64}$' OR p_subject_id IS NULL
  OR p_subject_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  OR (p_kind='notice_repair' AND p_source_request_id IS NULL) OR (p_kind<>'notice_repair' AND p_source_request_id IS NOT NULL)
 THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO attempt FROM private.admin_invitation_attempts r WHERE r.actor_id=p_actor_id AND r.idempotency_key=p_idempotency_key FOR UPDATE;
 IF FOUND THEN
  IF attempt.contract_version<>2 THEN RAISE EXCEPTION 'admin_invitation_version_conflict' USING ERRCODE='22023';END IF;
  IF attempt.kind<>p_kind OR attempt.body_sha256<>p_body_sha256 OR (p_kind<>'invite' AND attempt.subject_id<>p_subject_id)
   OR (p_kind='notice_repair' AND attempt.source_request_id IS DISTINCT FROM p_source_request_id)
  THEN RAISE EXCEPTION 'admin_invitation_idempotency_conflict' USING ERRCODE='22023';END IF;
  IF p_kind='invite' AND NOT EXISTS(SELECT 1 FROM app.admin_users a WHERE a.id=attempt.subject_id AND a.email=p_email AND a.role=p_role AND a.display_name=p_display_name)
  THEN RAISE EXCEPTION 'admin_invitation_idempotency_conflict' USING ERRCODE='22023';END IF;
  RETURN private.admin_invitation_v2_result(attempt,true);
 END IF;
 IF p_kind='invite' THEN
  IF p_email IS NULL OR p_email<>lower(btrim(p_email)) OR length(p_email) NOT BETWEEN 3 AND 254
   OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' OR p_email ~ '[[:cntrl:]]' OR p_email='info@ikanisa.com'
   OR p_role IS NULL OR p_role NOT IN('admin','staff') OR p_display_name IS NULL OR p_display_name<>btrim(p_display_name)
   OR length(p_display_name)>120 OR p_display_name ~ '[[:cntrl:]]' OR p_new_principal_id IS NULL
   OR p_new_principal_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='22023';END IF;
  SELECT * INTO subject FROM app.admin_users a WHERE lower(a.email)=p_email FOR UPDATE;duplicate_subject:=FOUND;
  IF duplicate_subject AND (subject.role<>p_role OR subject.display_name<>p_display_name)
  THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 ELSE
  SELECT * INTO subject FROM app.admin_users a WHERE a.id=p_subject_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;duplicate_subject:=true;
 END IF;
 IF duplicate_subject THEN
  IF subject.role='owner' OR subject.status='revoked' OR (p_kind='resend' AND subject.status<>'invited')
  THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;
  SELECT l.user_id INTO principal FROM app.admin_principal_links l JOIN app.users u ON u.id=l.user_id
   WHERE l.admin_user_id=subject.id AND u.access_status='active' FOR SHARE OF l,u;
  IF principal IS NULL THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
  SELECT * INTO prior FROM private.admin_invitation_attempts r WHERE r.subject_id=subject.id AND r.replayed_request_id IS NULL ORDER BY r.attempt_sequence DESC LIMIT 1 FOR UPDATE;
  IF p_kind='notice_repair' THEN
   SELECT * INTO source FROM private.admin_invitation_attempts r WHERE r.request_id=p_source_request_id AND r.replayed_request_id IS NULL
    AND r.subject_id=subject.id AND r.principal_id=principal AND r.state='already_registered' FOR UPDATE;
   IF NOT FOUND OR source.subject_identity_sha256 IS DISTINCT FROM private.admin_invitation_fingerprint(subject.id)
   THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
   lineage:=source.request_id;
   SELECT r.request_id INTO alias_source FROM private.admin_invitation_attempts r WHERE r.contract_version=2 AND r.kind='notice_repair'
    AND r.source_request_id=source.request_id AND r.replayed_request_id IS NULL ORDER BY r.attempt_sequence LIMIT 1 FOR UPDATE;
   -- Unknown native work never falls through to a notice, even when some
   -- older registered receipt is supplied to the explicit repair route.
   IF alias_source IS NULL AND prior.request_id IS NOT NULL AND prior.state IN('reserved','dispatching','unknown') THEN alias_source:=prior.request_id;END IF;
  ELSIF prior.request_id IS NOT NULL THEN
   PERFORM private.admin_invitation_v2_result(prior,true);
   IF p_kind='invite' OR prior.state NOT IN('accepted','rejected') THEN alias_source:=prior.request_id;
   ELSE lineage:=prior.request_id;END IF;
  ELSE initial_state:='unknown';
  END IF;
  IF alias_source IS NOT NULL THEN
   SELECT * INTO source FROM private.admin_invitation_attempts r WHERE r.request_id=alias_source AND r.replayed_request_id IS NULL;
   PERFORM private.admin_invitation_v2_result(source,true);
   INSERT INTO private.admin_invitation_attempts(actor_id,actor_principal_id,idempotency_key,subject_id,principal_id,body_sha256,kind,
    replayed_request_id,original_session_id,subject_identity_sha256,state,created_at,finished_at,safe_error_code,
    contract_version,message_kind,template_version,managed_auth_user_id,notice_origin,source_request_id)
   VALUES(p_actor_id,actor_principal,p_idempotency_key,subject.id,principal,p_body_sha256,p_kind,source.request_id,session_uuid,
    source.subject_identity_sha256,'unknown',created,created,'invitation_existing_request',2,source.message_kind,source.template_version,
    source.managed_auth_user_id,source.notice_origin,CASE WHEN p_kind='notice_repair' THEN p_source_request_id ELSE source.source_request_id END)
   RETURNING * INTO attempt;
   RETURN private.admin_invitation_v2_result(attempt,true);
  END IF;
  IF initial_state='reserved' THEN target:=private.admin_invitation_v2_target(subject.email,principal);END IF;
 ELSE
  IF EXISTS(SELECT 1 FROM app.admin_users a WHERE a.id=p_subject_id) THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
  target:=private.admin_invitation_v2_target(p_email,NULL);principal:=target->>'principalId';
  IF principal IS NOT NULL AND EXISTS(SELECT 1 FROM app.admin_principal_links l WHERE l.user_id=principal)
  THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
  IF principal IS NULL THEN
   principal:=p_new_principal_id;
   IF EXISTS(SELECT 1 FROM app.users u WHERE u.id=principal) THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
   SELECT app.printf('%06d',min(candidate)) INTO allocated_public_id FROM
    (SELECT 0::bigint AS candidate UNION ALL SELECT u.public_id::bigint+1 FROM app.users u WHERE u.public_id<>'999999') c
    WHERE candidate<1000000 AND NOT EXISTS(SELECT 1 FROM app.users u WHERE u.public_id=app.printf('%06d',candidate));
   IF allocated_public_id IS NULL THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='54000';END IF;
   INSERT INTO app.users(id,public_id,full_name,member_type,created_at,updated_at) VALUES(principal,allocated_public_id,p_display_name,'operator',stamp,stamp);
  END IF;
  INSERT INTO app.admin_users(id,email,role,status,display_name,created_at,invited_at,updated_at)
   VALUES(p_subject_id,p_email,p_role,'invited',p_display_name,current_epoch,current_epoch,current_epoch) RETURNING * INTO subject;
  INSERT INTO app.admin_principal_links(admin_user_id,user_id,approved_by,approved_at) VALUES(subject.id,principal,p_actor_id,stamp);
 END IF;
 IF initial_state='reserved' THEN
  selected_auth:=(target->>'managedAuthUserId')::uuid;
  IF (target->>'confirmed')::boolean THEN selected_kind:='access_notice';selected_template:='access_notice_v1';selected_origin:=p_origin;END IF;
  IF p_kind='notice_repair' AND selected_kind<>'access_notice' THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 END IF;
 INSERT INTO private.admin_invitation_attempts(actor_id,actor_principal_id,idempotency_key,subject_id,principal_id,body_sha256,kind,original_session_id,
  subject_identity_sha256,state,created_at,finished_at,safe_error_code,contract_version,message_kind,template_version,managed_auth_user_id,notice_origin,source_request_id)
 VALUES(p_actor_id,actor_principal,p_idempotency_key,subject.id,principal,p_body_sha256,p_kind,session_uuid,private.admin_invitation_fingerprint(subject.id),
  initial_state,created,CASE WHEN initial_state='unknown' THEN created END,CASE WHEN initial_state='unknown' THEN 'invitation_history_unknown' END,
  2,selected_kind,selected_template,selected_auth,selected_origin,lineage) RETURNING * INTO attempt;
 RETURN private.admin_invitation_v2_result(attempt,false);
END$$;

CREATE FUNCTION private.admin_invitation_v2_claim(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,p_request_id uuid,p_claim_nonce uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE session_uuid uuid; attempt private.admin_invitation_attempts%ROWTYPE; result jsonb; target jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);session_uuid:=private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 IF p_request_id IS NULL OR p_claim_nonce IS NULL THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO attempt FROM private.admin_invitation_attempts r WHERE r.request_id=p_request_id AND r.actor_id=p_actor_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;
 IF attempt.contract_version<>2 THEN RAISE EXCEPTION 'admin_invitation_version_conflict' USING ERRCODE='22023';END IF;
 IF attempt.replayed_request_id IS NOT NULL THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='42501';END IF;
 result:=private.admin_invitation_v2_result(attempt,true);
 IF attempt.state<>'reserved' THEN RETURN result||jsonb_build_object('claimed',false);END IF;
 PERFORM 1 FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id AND l.user_id=attempt.principal_id
  JOIN app.users u ON u.id=l.user_id WHERE a.id=attempt.subject_id AND a.role IN('admin','staff') AND a.status IN('invited','active')
  AND u.access_status='active' AND private.admin_invitation_fingerprint(a.id)=attempt.subject_identity_sha256 FOR SHARE OF a,l,u;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;
 target:=private.admin_invitation_v2_target(result->>'email',attempt.principal_id);
 IF attempt.managed_auth_user_id IS NOT NULL AND (target->>'managedAuthUserId')::uuid IS DISTINCT FROM attempt.managed_auth_user_id
 THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 IF attempt.message_kind='access_notice' THEN
  IF NOT (target->>'confirmed')::boolean OR attempt.notice_origin IS DISTINCT FROM p_origin
  THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 ELSIF (target->>'confirmed')::boolean THEN
  UPDATE private.admin_invitation_attempts SET state='already_registered',finished_at=clock_timestamp(),safe_error_code='email_exists'
   WHERE request_id=attempt.request_id AND state='reserved' RETURNING * INTO attempt;
  RETURN private.admin_invitation_v2_result(attempt,false)||jsonb_build_object('claimed',false);
 ELSIF result->>'accessStatus'<>'invited' THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;
 UPDATE private.admin_invitation_attempts SET state='dispatching',claim_nonce=p_claim_nonce,dispatch_session_id=session_uuid,claimed_at=clock_timestamp()
  WHERE request_id=attempt.request_id AND state='reserved' AND claim_nonce IS NULL RETURNING * INTO attempt;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='42501';END IF;
 RETURN private.admin_invitation_v2_result(attempt,false)||jsonb_build_object('claimed',true);
END$$;

CREATE FUNCTION private.admin_invitation_v2_finish(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,p_request_id uuid,p_claim_nonce uuid,p_state text,p_error_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE session_uuid uuid; attempt private.admin_invitation_attempts%ROWTYPE; result jsonb; target jsonb; safe_code text;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);session_uuid:=private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 IF p_request_id IS NULL OR p_claim_nonce IS NULL OR p_state IS NULL OR p_state NOT IN('accepted','rejected','unknown','already_registered')
 THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO attempt FROM private.admin_invitation_attempts r WHERE r.request_id=p_request_id AND r.actor_id=p_actor_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;
 IF attempt.contract_version<>2 THEN RAISE EXCEPTION 'admin_invitation_version_conflict' USING ERRCODE='22023';END IF;
 IF attempt.replayed_request_id IS NOT NULL OR attempt.claim_nonce IS DISTINCT FROM p_claim_nonce OR attempt.dispatch_session_id IS DISTINCT FROM session_uuid
 THEN RAISE EXCEPTION 'admin_invitation_authority' USING ERRCODE='42501';END IF;
 result:=private.admin_invitation_v2_result(attempt,true);
 PERFORM 1 FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id AND l.user_id=attempt.principal_id
  JOIN app.users u ON u.id=l.user_id WHERE a.id=attempt.subject_id AND a.role IN('admin','staff') AND a.status IN('invited','active')
  AND u.access_status='active' AND private.admin_invitation_fingerprint(a.id)=attempt.subject_identity_sha256 FOR SHARE OF a,l,u;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_subject_unavailable' USING ERRCODE='42501';END IF;
 IF attempt.state=p_state THEN RETURN result;END IF;
 IF attempt.state<>'dispatching' THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='42501';END IF;
 target:=private.admin_invitation_v2_target(result->>'email',attempt.principal_id);
 IF attempt.managed_auth_user_id IS NOT NULL AND (target->>'managedAuthUserId')::uuid IS DISTINCT FROM attempt.managed_auth_user_id
 THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 IF attempt.message_kind='access_notice' THEN
  IF p_state='already_registered' OR NOT (target->>'confirmed')::boolean OR attempt.notice_origin IS DISTINCT FROM p_origin
  THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 ELSIF p_state='already_registered' AND (p_error_code IS DISTINCT FROM 'email_exists' OR NOT (target->>'confirmed')::boolean)
 THEN RAISE EXCEPTION 'admin_invitation_identity_conflict' USING ERRCODE='42501';END IF;
 safe_code:=CASE p_state WHEN 'rejected' THEN 'invitation_rejected' WHEN 'unknown' THEN 'invitation_outcome_unknown' WHEN 'already_registered' THEN 'email_exists' END;
 UPDATE private.admin_invitation_attempts SET state=p_state,finished_at=clock_timestamp(),safe_error_code=safe_code
  WHERE request_id=attempt.request_id AND state='dispatching' AND claim_nonce=p_claim_nonce AND dispatch_session_id=session_uuid RETURNING * INTO attempt;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='42501';END IF;
 RETURN private.admin_invitation_v2_result(attempt,false);
END$$;

CREATE FUNCTION private.admin_invitation_v2_recover(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text,p_idempotency_key text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE attempt private.admin_invitation_attempts%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);PERFORM private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 IF p_idempotency_key IS NULL OR p_idempotency_key !~ '^[A-Za-z0-9._:-]{8,200}$' THEN RAISE EXCEPTION 'admin_invitation_invalid' USING ERRCODE='22023';END IF;
 SELECT * INTO attempt FROM private.admin_invitation_attempts r WHERE r.actor_id=p_actor_id AND r.idempotency_key=p_idempotency_key;
 IF NOT FOUND THEN RETURN jsonb_build_object('found',false);END IF;
 IF attempt.contract_version<>2 THEN RAISE EXCEPTION 'admin_invitation_version_conflict' USING ERRCODE='22023';END IF;
 RETURN private.admin_invitation_v2_result(attempt,true)||jsonb_build_object('found',true);
END$$;

CREATE FUNCTION private.admin_invitation_v2_list(p_actor_id text,p_cookie_hash text,p_origin text,p_public_session_id text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE members jsonb; permissions jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);PERFORM private.admin_invitation_actor(p_actor_id,p_cookie_hash,p_origin,p_public_session_id);
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',a.id,'email',a.email,'role',a.role,'status',a.status,'displayName',a.display_name,
  'createdAt',to_char(to_timestamp(a.created_at) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'invitedAt',CASE WHEN a.invited_at IS NOT NULL THEN to_char(to_timestamp(a.invited_at) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') END,
  'acceptedAt',CASE WHEN a.accepted_at IS NOT NULL THEN to_char(to_timestamp(a.accepted_at) AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') END,'invitation',
  CASE WHEN latest.request_id IS NOT NULL AND latest.subject_identity_sha256=private.admin_invitation_fingerprint(a.id)
   THEN private.admin_invitation_v2_result(latest::private.admin_invitation_attempts,false) ELSE NULL END) ORDER BY a.email),'[]'::jsonb) INTO members
  FROM app.admin_users a LEFT JOIN LATERAL(SELECT r.* FROM private.admin_invitation_attempts r WHERE r.subject_id=a.id
   AND r.replayed_request_id IS NULL ORDER BY r.attempt_sequence DESC LIMIT 1) latest ON true;
 SELECT jsonb_build_object(
  'owner',coalesce(jsonb_agg(c.permission ORDER BY c.permission) FILTER(WHERE c.role='owner'),'[]'::jsonb),
  'admin',coalesce(jsonb_agg(c.permission ORDER BY c.permission) FILTER(WHERE c.role='admin'),'[]'::jsonb),
  'staff',coalesce(jsonb_agg(c.permission ORDER BY c.permission) FILTER(WHERE c.role='staff'),'[]'::jsonb))
  INTO permissions FROM app.admin_account_role_capabilities c;
 RETURN jsonb_build_object('members',members,'permissionsByRole',permissions);
END$$;

REVOKE ALL ON FUNCTION private.admin_invitation_v2_target(text,text),private.admin_invitation_v2_result(private.admin_invitation_attempts,boolean),
 private.admin_invitation_v1_guard(text,text,uuid,text,text) FROM PUBLIC,anon,authenticated,collect_runtime;
REVOKE ALL ON FUNCTION private.admin_invitation_prepare(text,text,text,text,text,text,text,text,text,text,text,text),
 private.admin_invitation_claim(text,text,text,text,uuid,uuid),private.admin_invitation_finish(text,text,text,text,uuid,uuid,text,text),
 private.admin_invitation_recover(text,text,text,text,text),
 private.admin_invitation_v2_prepare(text,text,text,text,text,text,text,text,text,text,text,text,uuid),
 private.admin_invitation_v2_claim(text,text,text,text,uuid,uuid),private.admin_invitation_v2_finish(text,text,text,text,uuid,uuid,text,text),
 private.admin_invitation_v2_recover(text,text,text,text,text),private.admin_invitation_v2_list(text,text,text,text) FROM PUBLIC,anon,authenticated,collect_runtime;
GRANT EXECUTE ON FUNCTION private.admin_invitation_prepare(text,text,text,text,text,text,text,text,text,text,text,text),
 private.admin_invitation_claim(text,text,text,text,uuid,uuid),private.admin_invitation_finish(text,text,text,text,uuid,uuid,text,text),
 private.admin_invitation_recover(text,text,text,text,text),
 private.admin_invitation_v2_prepare(text,text,text,text,text,text,text,text,text,text,text,text,uuid),
 private.admin_invitation_v2_claim(text,text,text,text,uuid,uuid),private.admin_invitation_v2_finish(text,text,text,text,uuid,uuid,text,text),
 private.admin_invitation_v2_recover(text,text,text,text,text),private.admin_invitation_v2_list(text,text,text,text) TO collect_runtime;
-- Existing journal SELECT/RLS, mutation revocations, immutable descriptor
-- trigger and historical actor-principal retention selectors remain in force.
