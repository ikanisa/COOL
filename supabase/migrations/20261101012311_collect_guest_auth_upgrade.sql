-- Restricted guest identity and same-Auth-UUID conversion. This installs no
-- provider or send capability. A guest never gets an app.users principal.
BEGIN;

CREATE TABLE private.guest_upgrade_challenges (
 id uuid PRIMARY KEY,
 auth_user_id uuid NOT NULL,
 initiating_session_id uuid NOT NULL,
 identity_type text NOT NULL CHECK(identity_type IN('email','phone')),
 identity_value text NOT NULL CHECK(octet_length(identity_value)<=254),
 channel text NOT NULL CHECK(channel IN('email','sms','whatsapp')),
 created_at bigint NOT NULL,
 expires_at bigint NOT NULL CHECK(expires_at=created_at+300),
 delivery_status text NOT NULL DEFAULT 'reserved' CHECK(delivery_status IN('reserved','accepted','rejected','unknown')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),
 verification_state text NOT NULL DEFAULT 'none' CHECK(verification_state IN('none','verifying','rejected','unknown','verified')),
 verification_operation uuid,
 verified_session_id uuid,
 verified_at bigint,
 CHECK((identity_type='email' AND channel='email') OR(identity_type='phone' AND channel IN('sms','whatsapp'))),
 CHECK((verification_state='none' AND attempts=0 AND verification_operation IS NULL) OR
       (verification_state<>'none' AND attempts>0 AND verification_operation IS NOT NULL)),
 CHECK((verification_state='verified' AND verified_session_id IS NOT NULL AND verified_at IS NOT NULL) OR
       (verification_state<>'verified' AND verified_session_id IS NULL AND verified_at IS NULL))
);
CREATE INDEX guest_upgrade_owner ON private.guest_upgrade_challenges(auth_user_id,created_at DESC,id);
CREATE INDEX guest_upgrade_identity ON private.guest_upgrade_challenges(identity_type,identity_value,created_at DESC);
ALTER TABLE private.guest_upgrade_challenges ENABLE ROW LEVEL SECURITY;
-- Only pinned SECURITY DEFINER helpers owned by the migration owner can see
-- this table. Client and runtime roles have neither policies nor privileges.
-- Do not FORCE RLS here: it would also deny the definer's guarded transitions.
REVOKE ALL ON private.guest_upgrade_challenges FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.guest_upgrade_challenges
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.guest_upgrade_challenges ENABLE ALWAYS TRIGGER collect_fence_statement_v1;

CREATE FUNCTION private.guest_managed_session(p_auth_user_id uuid,p_session_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT private.request_claims()->>'sub'=p_auth_user_id::text AND private.request_claims()->>'session_id'=p_session_id::text
 AND private.request_claims()->>'role'='authenticated' AND EXISTS(
 SELECT 1 FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id WHERE s.id=p_session_id AND s.user_id=p_auth_user_id
 AND (to_jsonb(u)->>'deleted_at') IS NULL
 AND (to_jsonb(u)->>'banned_until' IS NULL OR(to_jsonb(u)->>'banned_until')::timestamptz<=now())
 AND (to_jsonb(s)->>'not_after' IS NULL OR(to_jsonb(s)->>'not_after')::timestamptz>now()))
$$;

CREATE FUNCTION private.guest_auth_session(p_allow_converted boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c jsonb:=private.request_claims(); subject uuid; sid uuid; native jsonb;
BEGIN
 IF c->'is_anonymous' IS DISTINCT FROM 'true'::jsonb OR c->>'role' IS DISTINCT FROM 'authenticated'
  OR current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'guest_session_required' USING ERRCODE='42501';
 END IF;
 BEGIN subject:=(c->>'sub')::uuid; sid:=(c->>'session_id')::uuid;
 EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'guest_session_required' USING ERRCODE='42501'; END;
 IF subject IS NULL OR sid IS NULL OR NOT coalesce(private.guest_managed_session(subject,sid),false) THEN
  RAISE EXCEPTION 'guest_session_required' USING ERRCODE='42501';
 END IF;
 SELECT to_jsonb(u) INTO native FROM auth.users u WHERE u.id=subject;
 IF native IS NULL OR (NOT p_allow_converted AND native->'is_anonymous' IS DISTINCT FROM 'true'::jsonb)
  OR EXISTS(SELECT 1 FROM private.auth_principal_links l WHERE l.auth_user_id=subject) AND NOT p_allow_converted THEN
  RAISE EXCEPTION 'guest_session_required' USING ERRCODE='42501';
 END IF;
 RETURN jsonb_build_object('auth_user_id',subject,'session_id',sid,'is_anonymous',native->'is_anonymous');
END$$;

CREATE FUNCTION private.guest_identity_available(p_type text,p_value text,p_auth uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT p_type IN('email','phone') AND p_auth IS NOT NULL
 AND NOT EXISTS(SELECT 1 FROM auth.users u WHERE u.id<>p_auth AND
  ((p_type='email' AND lower(u.email)=p_value) OR(p_type='phone' AND ltrim(u.phone,'+')=ltrim(p_value,'+'))))
 AND NOT EXISTS(SELECT 1 FROM app.users u WHERE
  ((p_type='email' AND lower(u.email)=p_value) OR(p_type='phone' AND u.phone=p_value))
  AND NOT EXISTS(SELECT 1 FROM private.auth_principal_links l WHERE l.auth_user_id=p_auth AND l.user_id=u.id))
 AND NOT EXISTS(SELECT 1 FROM app.admin_users a WHERE p_type='email' AND lower(a.email)=p_value
  AND NOT EXISTS(SELECT 1 FROM app.admin_principal_links a_link JOIN private.auth_principal_links l ON l.user_id=a_link.user_id
   WHERE a_link.admin_user_id=a.id AND l.auth_user_id=p_auth))
$$;

CREATE FUNCTION private.guest_upgrade_begin(p_id uuid,p_type text,p_value text,p_channel text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb:=private.guest_auth_session(); at bigint:=app.unixepoch(); subject uuid:=(actor->>'auth_user_id')::uuid;
BEGIN
 IF p_id IS NULL OR NOT((p_type='email' AND p_channel='email' AND p_value=lower(p_value) AND p_value ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')
  OR(p_type='phone' AND p_channel IN('sms','whatsapp') AND p_value ~ '^\+2507[2389][0-9]{7}$')) OR octet_length(p_value)>254 THEN
  RAISE EXCEPTION 'invalid_identity' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('collect:guest:'||subject::text,0));
 PERFORM pg_advisory_xact_lock(hashtextextended('collect:guest-identity:'||p_type||':'||p_value,0));
 IF EXISTS(SELECT 1 FROM private.guest_upgrade_challenges c WHERE
  (c.auth_user_id=subject AND (c.created_at>at-60 OR c.verification_state IN('verifying','unknown')))
  OR(c.identity_type=p_type AND c.identity_value=p_value AND c.created_at>at-60)) THEN
  RAISE EXCEPTION 'guest_upgrade_busy' USING ERRCODE='P0001';
 END IF;
 IF NOT private.guest_identity_available(p_type,p_value,subject) THEN RAISE EXCEPTION 'identity_already_exists' USING ERRCODE='23505';END IF;
 INSERT INTO private.guest_upgrade_challenges(id,auth_user_id,initiating_session_id,identity_type,identity_value,channel,created_at,expires_at)
 VALUES(p_id,subject,(actor->>'session_id')::uuid,p_type,p_value,p_channel,at,at+300);
 RETURN jsonb_build_object('id',p_id,'created_at',at,'expires_at',at+300);
END$$;

CREATE FUNCTION private.guest_upgrade_read(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb:=private.guest_auth_session(true); result jsonb;
BEGIN
 SELECT to_jsonb(c) INTO result FROM private.guest_upgrade_challenges c WHERE c.id=p_id
  AND c.auth_user_id=(actor->>'auth_user_id')::uuid AND c.initiating_session_id=(actor->>'session_id')::uuid;
 IF result IS NULL THEN RAISE EXCEPTION 'guest_challenge_required' USING ERRCODE='42501';END IF;
 RETURN result;
END$$;

-- Recovery may outlive the original access JWT. The edge obtains a fresh
-- GoTrue-verified token from the retained refresh credential, then this helper
-- binds its *native* session to the initiating session. An expired decoded JWT
-- is never authority, and a new login for the same user cannot take ownership.
CREATE FUNCTION private.guest_upgrade_recovery_read(p_id uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE claims jsonb:=private.request_claims(); subject uuid; sid uuid; native jsonb; result jsonb;
BEGIN
 IF current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true'
  OR claims->>'role' IS DISTINCT FROM 'authenticated' OR jsonb_typeof(claims->'is_anonymous') IS DISTINCT FROM 'boolean' THEN
  RAISE EXCEPTION 'guest_session_required' USING ERRCODE='42501';END IF;
 BEGIN subject:=(claims->>'sub')::uuid; sid:=(claims->>'session_id')::uuid;
 EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'guest_session_required' USING ERRCODE='42501';END;
 IF subject IS NULL OR sid IS NULL OR NOT coalesce(private.guest_managed_session(subject,sid),false) THEN
  RAISE EXCEPTION 'guest_session_required' USING ERRCODE='42501';END IF;
 SELECT to_jsonb(u) INTO native FROM auth.users u WHERE u.id=subject;
 IF native->'is_anonymous' IS DISTINCT FROM claims->'is_anonymous' THEN
  RAISE EXCEPTION 'guest_session_required' USING ERRCODE='42501';END IF;
 SELECT to_jsonb(c) INTO result FROM private.guest_upgrade_challenges c WHERE c.id=p_id
  AND c.auth_user_id=subject AND c.initiating_session_id=sid
  AND c.verification_state IN('verifying','unknown','verified');
 IF result IS NULL THEN RAISE EXCEPTION 'guest_challenge_required' USING ERRCODE='42501';END IF;
 RETURN result;
END$$;

CREATE FUNCTION private.guest_upgrade_delivery(p_id uuid,p_status text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb:=private.guest_auth_session(true); c private.guest_upgrade_challenges%ROWTYPE;
BEGIN
 IF p_status NOT IN('accepted','rejected','unknown') THEN RAISE EXCEPTION 'invalid_delivery_state' USING ERRCODE='22023';END IF;
 SELECT * INTO c FROM private.guest_upgrade_challenges WHERE id=p_id FOR UPDATE;
 IF c.id IS NULL OR c.auth_user_id<>(actor->>'auth_user_id')::uuid OR c.initiating_session_id<>(actor->>'session_id')::uuid THEN
  RAISE EXCEPTION 'guest_challenge_required' USING ERRCODE='42501';END IF;
 IF c.delivery_status='reserved' THEN UPDATE private.guest_upgrade_challenges SET delivery_status=p_status WHERE id=p_id;
 ELSIF c.delivery_status<>p_status THEN RAISE EXCEPTION 'delivery_state_retained' USING ERRCODE='42501';END IF;
END$$;

CREATE FUNCTION private.guest_upgrade_claim(p_id uuid,p_operation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb:=private.guest_auth_session(); c private.guest_upgrade_challenges%ROWTYPE;
BEGIN
 SELECT * INTO c FROM private.guest_upgrade_challenges WHERE id=p_id FOR UPDATE;
 IF p_operation IS NULL OR c.id IS NULL OR c.auth_user_id<>(actor->>'auth_user_id')::uuid
  OR c.initiating_session_id<>(actor->>'session_id')::uuid OR c.expires_at<=app.unixepoch()
  OR c.attempts>=5 OR c.delivery_status NOT IN('accepted','unknown') OR c.verification_state NOT IN('none','rejected')
  OR EXISTS(SELECT 1 FROM private.guest_upgrade_challenges newer WHERE newer.auth_user_id=c.auth_user_id AND newer.created_at>c.created_at)
 THEN RAISE EXCEPTION 'guest_challenge_required' USING ERRCODE='42501';END IF;
 IF NOT private.guest_identity_available(c.identity_type,c.identity_value,c.auth_user_id) THEN
  RAISE EXCEPTION 'identity_already_exists' USING ERRCODE='23505';END IF;
 UPDATE private.guest_upgrade_challenges SET attempts=attempts+1,verification_state='verifying',verification_operation=p_operation
 WHERE id=p_id RETURNING * INTO c;
 RETURN to_jsonb(c);
END$$;

CREATE FUNCTION private.guest_upgrade_failure(p_id uuid,p_operation uuid,p_status text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE actor jsonb:=private.guest_auth_session(true);
BEGIN
 IF p_status NOT IN('rejected','unknown') THEN RAISE EXCEPTION 'invalid_verification_state' USING ERRCODE='22023';END IF;
 UPDATE private.guest_upgrade_challenges SET verification_state=p_status WHERE id=p_id
  AND auth_user_id=(actor->>'auth_user_id')::uuid AND initiating_session_id=(actor->>'session_id')::uuid
  AND verification_operation=p_operation AND verification_state='verifying';
 IF NOT FOUND THEN RAISE EXCEPTION 'guest_verification_state_retained' USING ERRCODE='42501';END IF;
END$$;

CREATE FUNCTION private.guest_upgrade_finish(p_id uuid,p_operation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE c private.guest_upgrade_challenges%ROWTYPE; claims jsonb:=private.request_claims();
 subject uuid; sid uuid; native jsonb; confirmed text;
BEGIN
 IF current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true' OR claims->>'role' IS DISTINCT FROM 'authenticated'
  OR claims->'is_anonymous' IS DISTINCT FROM 'false'::jsonb THEN RAISE EXCEPTION 'verified_identity_required' USING ERRCODE='42501';END IF;
 BEGIN subject:=(claims->>'sub')::uuid; sid:=(claims->>'session_id')::uuid;
 EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'invalid_session' USING ERRCODE='42501';END;
 IF NOT coalesce(private.guest_managed_session(subject,sid),false) THEN RAISE EXCEPTION 'invalid_session' USING ERRCODE='42501';END IF;
 SELECT * INTO c FROM private.guest_upgrade_challenges WHERE id=p_id FOR UPDATE;
 SELECT to_jsonb(u) INTO native FROM auth.users u WHERE u.id=subject;
 IF c.id IS NULL OR c.auth_user_id<>subject OR c.verification_operation IS DISTINCT FROM p_operation
  OR c.verification_state NOT IN('verifying','unknown','verified') OR native->'is_anonymous' IS DISTINCT FROM 'false'::jsonb THEN
  RAISE EXCEPTION 'guest_challenge_required' USING ERRCODE='42501';END IF;
 confirmed:=CASE WHEN c.identity_type='email' AND native->>'email_confirmed_at' IS NOT NULL THEN lower(native->>'email')
  WHEN c.identity_type='phone' AND native->>'phone_confirmed_at' IS NOT NULL THEN '+'||ltrim(native->>'phone','+') ELSE NULL END;
 IF confirmed IS DISTINCT FROM c.identity_value OR NOT private.guest_identity_available(c.identity_type,c.identity_value,subject) THEN
  RAISE EXCEPTION 'verified_identity_mismatch' USING ERRCODE='42501';END IF;
 IF c.verification_state='verified' THEN
  -- Retain the first durable verification; a refresh must not rewrite evidence.
  RETURN jsonb_build_object('auth_user_id',subject,'verified_session_id',c.verified_session_id,'verified_at',c.verified_at);
 END IF;
 UPDATE private.guest_upgrade_challenges SET verification_state='verified',verified_session_id=sid,verified_at=app.unixepoch() WHERE id=p_id;
 RETURN jsonb_build_object('auth_user_id',subject,'verified_session_id',sid,'verified_at',app.unixepoch());
END$$;

CREATE FUNCTION private.guest_upgrade_projection_allowed() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT NOT EXISTS(SELECT 1 FROM private.guest_upgrade_challenges c WHERE c.auth_user_id::text=private.request_claims()->>'sub')
 OR EXISTS(SELECT 1 FROM private.guest_upgrade_challenges c JOIN auth.users u ON u.id=c.auth_user_id
  WHERE c.auth_user_id::text=private.request_claims()->>'sub' AND c.verification_state='verified'
   AND to_jsonb(u)->'is_anonymous'='false'::jsonb AND private.request_claims()->'is_anonymous'='false'::jsonb
   AND ((c.identity_type='email' AND u.email_confirmed_at IS NOT NULL AND lower(u.email)=c.identity_value)
    OR(c.identity_type='phone' AND u.phone_confirmed_at IS NOT NULL AND '+'||ltrim(u.phone,'+')=c.identity_value)))
$$;

REVOKE ALL ON FUNCTION private.guest_managed_session(uuid,uuid),private.guest_auth_session(boolean),private.guest_identity_available(text,text,uuid),
 private.guest_upgrade_begin(uuid,text,text,text),private.guest_upgrade_read(uuid),private.guest_upgrade_recovery_read(uuid),private.guest_upgrade_delivery(uuid,text),
 private.guest_upgrade_claim(uuid,uuid),private.guest_upgrade_failure(uuid,uuid,text),private.guest_upgrade_finish(uuid,uuid),private.guest_upgrade_projection_allowed()
 FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.guest_auth_session(boolean),private.guest_upgrade_begin(uuid,text,text,text),
 private.guest_upgrade_read(uuid),private.guest_upgrade_recovery_read(uuid),private.guest_upgrade_delivery(uuid,text),private.guest_upgrade_claim(uuid,uuid),
 private.guest_upgrade_failure(uuid,uuid,text),private.guest_upgrade_finish(uuid,uuid),private.guest_upgrade_projection_allowed() TO collect_runtime;
-- Existing application authority remains unavailable to guests even if a stale
-- token or an accidentally created principal link is presented directly.
CREATE OR REPLACE FUNCTION private.is_managed_session(p_auth_user_id uuid,p_session_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT private.request_claims()->>'sub'=p_auth_user_id::text AND private.request_claims()->>'session_id'=p_session_id::text
 AND private.request_claims()->>'role'='authenticated' AND EXISTS(
 SELECT 1 FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id WHERE s.id=p_session_id AND s.user_id=p_auth_user_id
 AND (to_jsonb(u)->>'deleted_at') IS NULL
 AND (to_jsonb(u)->>'banned_until' IS NULL OR(to_jsonb(u)->>'banned_until')::timestamptz<=now())
 AND (to_jsonb(s)->>'not_after' IS NULL OR(to_jsonb(s)->>'not_after')::timestamptz>now())
 AND NOT coalesce((to_jsonb(u)->>'is_anonymous')::boolean,false)
 AND NOT coalesce((private.request_claims()->>'is_anonymous')::boolean,false))
 -- Disabling new guest signups must never release an unresolved conversion.
 AND private.guest_upgrade_projection_allowed()
$$;
COMMIT;
