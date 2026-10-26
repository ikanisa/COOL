-- Managed Auth is the identity authority. These are immutable principal links
-- and server-side custody/projections, never a transplant of legacy tokens.
CREATE TABLE private.auth_principal_links (
 auth_user_id uuid PRIMARY KEY REFERENCES auth.users(id),
 user_id text NOT NULL UNIQUE REFERENCES app.users(id),
 linked_at timestamptz NOT NULL DEFAULT now(),
 proof_reference text NOT NULL CHECK(length(proof_reference)>0)
);
CREATE FUNCTION private.trg_auth_principal_link_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'immutable_managed_principal_link' USING ERRCODE='42501';END$$;
CREATE TRIGGER auth_principal_link_identity BEFORE UPDATE OR DELETE ON private.auth_principal_links FOR EACH ROW EXECUTE FUNCTION private.trg_auth_principal_link_identity();
CREATE TABLE private.supabase_otp_challenges (
 id text PRIMARY KEY, identity_hash text NOT NULL CHECK(length(identity_hash)=64), identity_type text NOT NULL CHECK(identity_type IN('phone','email')),
 identity_value text NOT NULL, surface text NOT NULL CHECK(surface IN('member','admin')),
 registration_allowed bigint NOT NULL CHECK(registration_allowed IN(0,1)),
 created_at bigint NOT NULL, expires_at bigint NOT NULL CHECK(expires_at>created_at),
 attempts bigint NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5), consumed_at bigint,
 delivery_status text NOT NULL DEFAULT 'reserved' CHECK(delivery_status IN('reserved','accepted','rejected','unknown'))
);
CREATE INDEX supabase_otp_identity_cooldown ON private.supabase_otp_challenges(identity_hash,surface,created_at DESC);
CREATE FUNCTION private.trg_supabase_otp_admission() RETURNS trigger LANGUAGE plpgsql SET search_path=private,pg_catalog AS $$
BEGIN
 -- Lock the identity before checking the previous reservation. The reservation
 -- is committed before the provider call; a missing acknowledgement keeps it.
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.identity_hash||':'||NEW.surface,1));
 IF EXISTS(SELECT 1 FROM private.supabase_otp_challenges c WHERE c.identity_hash=NEW.identity_hash AND c.surface=NEW.surface AND c.created_at+60>NEW.created_at) THEN RAISE EXCEPTION 'otp_cooldown' USING ERRCODE='P0001'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER supabase_otp_admission BEFORE INSERT ON private.supabase_otp_challenges FOR EACH ROW EXECUTE FUNCTION private.trg_supabase_otp_admission();
CREATE FUNCTION private.trg_supabase_otp_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'retain_managed_otp_admission' USING ERRCODE='42501';END IF;
 IF to_jsonb(OLD)-ARRAY['attempts','consumed_at','delivery_status'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['attempts','consumed_at','delivery_status'] THEN RAISE EXCEPTION 'immutable_managed_otp_identity' USING ERRCODE='42501';END IF;
 IF NEW.attempts<OLD.attempts OR (OLD.consumed_at IS NOT NULL AND NEW.consumed_at IS DISTINCT FROM OLD.consumed_at) THEN RAISE EXCEPTION 'managed_otp_state_regression' USING ERRCODE='42501';END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER supabase_otp_identity BEFORE UPDATE OR DELETE ON private.supabase_otp_challenges FOR EACH ROW EXECUTE FUNCTION private.trg_supabase_otp_identity();
CREATE TABLE private.bff_sessions (
 token_hash text PRIMARY KEY REFERENCES app.admin_sessions(token_hash) ON UPDATE CASCADE ON DELETE CASCADE,
 auth_user_id uuid NOT NULL REFERENCES auth.users(id), auth_session_id uuid NOT NULL UNIQUE,
 token_ciphertext text NOT NULL CHECK(app.json_valid(token_ciphertext)),
 version bigint NOT NULL DEFAULT 1, refresh_lease text, refresh_lease_until bigint
);
CREATE TABLE private.managed_mfa_proofs (
 session_id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES auth.users(id),
 factor_id uuid NOT NULL, verified_at_epoch bigint NOT NULL,
 CHECK(verified_at_epoch>0)
);
-- Original managed OTP proof is retained independently of the provider's
-- disposable session row. Only record_managed_phone_verification may write it.
CREATE TABLE private.managed_phone_verifications (
 challenge_id text PRIMARY KEY REFERENCES private.supabase_otp_challenges(id),
 auth_user_id uuid NOT NULL REFERENCES auth.users(id), session_id uuid NOT NULL,
 user_id text NOT NULL REFERENCES app.users(id),
 phone text NOT NULL CHECK(phone ~ '^\+[1-9][0-9]{6,14}$'),
 verified_at bigint NOT NULL CHECK(verified_at>0)
);
CREATE FUNCTION private.trg_managed_phone_proof_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'immutable_managed_phone_verification' USING ERRCODE='42501';END$$;
CREATE TRIGGER managed_phone_proof_identity BEFORE UPDATE OR DELETE ON private.managed_phone_verifications FOR EACH ROW EXECUTE FUNCTION private.trg_managed_phone_proof_identity();
-- Bind the same managed OAuth handoff to its original product surface and
-- exact browser origin. A legacy flow without this context is inadmissible.
CREATE TABLE private.google_flow_context (
 flow_id text PRIMARY KEY REFERENCES app.auth_google_flows(id),
 surface text NOT NULL CHECK(surface IN('member','admin')),
 request_origin text CHECK(request_origin IS NULL OR length(request_origin) BETWEEN 1 AND 2048),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(surface<>'admin' OR request_origin IS NOT NULL)
);
CREATE FUNCTION private.trg_google_flow_context_identity() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'immutable_google_flow_context' USING ERRCODE='42501';END$$;
CREATE TRIGGER google_flow_context_identity BEFORE UPDATE OR DELETE ON private.google_flow_context FOR EACH ROW EXECUTE FUNCTION private.trg_google_flow_context_identity();

CREATE FUNCTION private.request_claims() RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
BEGIN RETURN coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb;
EXCEPTION WHEN invalid_text_representation THEN RETURN '{}'::jsonb; END$$;
CREATE FUNCTION api.current_principal_id() RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT l.user_id FROM private.auth_principal_links l
 WHERE l.auth_user_id::text=private.request_claims()->>'sub'
$$;
CREATE FUNCTION api.current_session_id() RETURNS text LANGUAGE sql STABLE AS $$SELECT private.request_claims()->>'session_id'$$;
CREATE FUNCTION private.is_managed_session(p_auth_user_id uuid,p_session_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT private.request_claims()->>'sub'=p_auth_user_id::text AND private.request_claims()->>'session_id'=p_session_id::text
 AND private.request_claims()->>'role'='authenticated' AND EXISTS(
 SELECT 1 FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id WHERE s.id=p_session_id AND s.user_id=p_auth_user_id
 AND (to_jsonb(u)->>'deleted_at') IS NULL
 AND (to_jsonb(u)->>'banned_until' IS NULL OR (to_jsonb(u)->>'banned_until')::timestamptz<=now())
 AND (to_jsonb(s)->>'not_after' IS NULL OR (to_jsonb(s)->>'not_after')::timestamptz>now()))
$$;
CREATE FUNCTION private.session_expiry(p_requested_epoch bigint) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE claims jsonb:=private.request_claims(); actual jsonb; limited bigint;
BEGIN
 IF NOT coalesce(private.is_managed_session((claims->>'sub')::uuid,(claims->>'session_id')::uuid),false) THEN RAISE EXCEPTION 'managed_session_required' USING ERRCODE='42501'; END IF;
 IF p_requested_epoch<=extract(epoch FROM now())::bigint OR p_requested_epoch>extract(epoch FROM now())::bigint+2592000 THEN RAISE EXCEPTION 'invalid_session_lifetime' USING ERRCODE='22023'; END IF;
 SELECT to_jsonb(s) INTO actual FROM auth.sessions s WHERE s.id::text=claims->>'session_id';
 limited:=p_requested_epoch;
 IF actual->>'not_after' IS NOT NULL THEN limited:=least(limited,floor(extract(epoch FROM (actual->>'not_after')::timestamptz))::bigint); END IF;
 RETURN limited;
END$$;
CREATE FUNCTION private.record_managed_phone_verification(p_challenge_id text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE claims jsonb:=private.request_claims();principal uuid;session_uuid uuid;legacy_id text;actual_phone text;confirmed timestamptz;canonical_phone text;verified bigint;challenge private.supabase_otp_challenges%ROWTYPE;retained private.managed_phone_verifications%ROWTYPE;
BEGIN
 principal:=(claims->>'sub')::uuid;session_uuid:=(claims->>'session_id')::uuid;legacy_id:=api.current_principal_id();
 IF p_challenge_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' OR legacy_id IS NULL OR NOT coalesce(private.is_managed_session(principal,session_uuid),false) THEN RAISE EXCEPTION 'managed_phone_proof_required' USING ERRCODE='42501';END IF;
 SELECT * INTO challenge FROM private.supabase_otp_challenges WHERE id=p_challenge_id FOR SHARE;
 IF NOT FOUND OR challenge.identity_type<>'phone' OR challenge.surface<>'member' OR challenge.delivery_status NOT IN('accepted','unknown') OR challenge.consumed_at IS NULL OR challenge.consumed_at NOT BETWEEN challenge.created_at AND challenge.expires_at THEN RAISE EXCEPTION 'consumed_managed_phone_challenge_required' USING ERRCODE='42501';END IF;
 SELECT u.phone,u.phone_confirmed_at INTO actual_phone,confirmed FROM auth.users u WHERE u.id=principal;
 IF actual_phone !~ '^\+?[1-9][0-9]{6,14}$' OR confirmed IS NULL THEN RAISE EXCEPTION 'confirmed_managed_phone_required' USING ERRCODE='42501';END IF;
 canonical_phone:='+'||ltrim(actual_phone,'+');
 IF canonical_phone IS DISTINCT FROM challenge.identity_value OR NOT EXISTS(SELECT 1 FROM app.users u JOIN app.auth_sessions s ON s.user_id=u.id WHERE u.id=legacy_id AND u.phone=canonical_phone AND u.access_status='active' AND s.id=session_uuid::text AND s.surface='member' AND s.revoked_at IS NULL AND s.expires_at>extract(epoch FROM now())::bigint) THEN RAISE EXCEPTION 'managed_phone_identity_changed' USING ERRCODE='42501';END IF;
 -- The timestamp belongs to the signed OTP event; observing it again cannot
 -- manufacture a fresh proof. Other AMR methods, strings and metadata fail.
 SELECT max(CASE WHEN item->>'timestamp' ~ '^[0-9]{1,12}$' THEN (item->>'timestamp')::bigint END) INTO verified FROM jsonb_array_elements(CASE WHEN jsonb_typeof(claims->'amr')='array' THEN claims->'amr' ELSE '[]'::jsonb END) item WHERE item->>'method'='otp' AND jsonb_typeof(item->'timestamp')='number';
 IF verified IS NULL OR verified NOT BETWEEN challenge.created_at AND challenge.consumed_at+1 OR verified>extract(epoch FROM now())::bigint+1 THEN RAISE EXCEPTION 'original_managed_phone_amr_required' USING ERRCODE='42501';END IF;
 INSERT INTO private.managed_phone_verifications(challenge_id,auth_user_id,session_id,user_id,phone,verified_at) VALUES(p_challenge_id,principal,session_uuid,legacy_id,canonical_phone,verified) ON CONFLICT(challenge_id) DO NOTHING;
 SELECT * INTO retained FROM private.managed_phone_verifications WHERE challenge_id=p_challenge_id;
 IF retained.auth_user_id IS DISTINCT FROM principal OR retained.session_id IS DISTINCT FROM session_uuid OR retained.user_id IS DISTINCT FROM legacy_id OR retained.phone IS DISTINCT FROM canonical_phone OR retained.verified_at IS DISTINCT FROM verified THEN RAISE EXCEPTION 'managed_phone_proof_conflict' USING ERRCODE='42501';END IF;
 RETURN p_challenge_id;
END$$;
CREATE FUNCTION private.managed_phone_binding(p_user_id text,p_challenge_id text,p_phone text,p_session_id text DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM private.managed_phone_verifications p
 JOIN private.auth_principal_links l ON l.auth_user_id=p.auth_user_id AND l.user_id=p.user_id
 JOIN app.users u ON u.id=p.user_id JOIN auth.users a ON a.id=p.auth_user_id
 JOIN private.supabase_otp_challenges c ON c.id=p.challenge_id
 WHERE p.user_id=p_user_id AND p.challenge_id=p_challenge_id AND p.phone=p_phone AND u.phone=p.phone AND u.access_status='active'
 AND a.phone_confirmed_at IS NOT NULL AND a.phone ~ '^\+?[1-9][0-9]{6,14}$' AND '+'||ltrim(a.phone,'+')=p.phone
 AND to_jsonb(a)->>'deleted_at' IS NULL AND (to_jsonb(a)->>'banned_until' IS NULL OR (to_jsonb(a)->>'banned_until')::timestamptz<=now())
 AND c.identity_type='phone' AND c.surface='member' AND c.identity_value=p.phone AND c.delivery_status IN('accepted','unknown')
 AND c.consumed_at BETWEEN c.created_at AND c.expires_at AND p.verified_at BETWEEN c.created_at AND c.consumed_at+1
 AND (p_session_id IS NULL OR (p.session_id::text=p_session_id AND private.request_claims()->>'session_id'=p_session_id AND private.request_claims()->>'sub'=p.auth_user_id::text AND private.is_managed_session(p.auth_user_id,p.session_id)
 AND EXISTS(SELECT 1 FROM app.auth_sessions s WHERE s.id=p_session_id AND s.user_id=p.user_id AND s.surface='member' AND s.revoked_at IS NULL AND s.expires_at>extract(epoch FROM now())::bigint))))
$$;
CREATE FUNCTION private.record_mfa_projection(p_factor_id uuid) RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE claims jsonb:=private.request_claims(); verified_at bigint; managed_verified_at bigint; actual jsonb; principal uuid; session_uuid uuid;
BEGIN
 principal:=(claims->>'sub')::uuid; session_uuid:=(claims->>'session_id')::uuid;
 IF claims->>'aal' IS DISTINCT FROM 'aal2' OR NOT coalesce(private.is_managed_session(principal,session_uuid),false) THEN RAISE EXCEPTION 'managed_mfa_required' USING ERRCODE='42501'; END IF;
 SELECT to_jsonb(s) INTO actual FROM auth.sessions s JOIN auth.mfa_factors f ON f.user_id=s.user_id AND f.id=p_factor_id WHERE s.id=session_uuid AND s.user_id=principal AND f.status::text='verified' AND to_jsonb(s)->>'aal'='aal2';
 IF actual IS NULL OR (actual->>'factor_id' IS NOT NULL AND actual->>'factor_id'<>p_factor_id::text) THEN RAISE EXCEPTION 'managed_mfa_required' USING ERRCODE='42501'; END IF;
 SELECT max((item->>'timestamp')::bigint) INTO verified_at FROM jsonb_array_elements(CASE WHEN jsonb_typeof(claims->'amr')='array' THEN claims->'amr' ELSE '[]'::jsonb END) item WHERE item->>'method' IN('totp','mfa/totp') AND item->>'timestamp' ~ '^[0-9]+$';
 SELECT max(floor(extract(epoch FROM updated_at))::bigint) INTO managed_verified_at FROM auth.mfa_amr_claims WHERE session_id=session_uuid AND authentication_method IN('totp','mfa/totp');
 IF managed_verified_at IS NULL OR verified_at IS NULL OR abs(managed_verified_at-verified_at)>1 THEN RAISE EXCEPTION 'managed_mfa_amr_required' USING ERRCODE='42501'; END IF;
 verified_at:=managed_verified_at;
 IF verified_at IS NULL OR verified_at<extract(epoch FROM now())::bigint-300 OR verified_at>extract(epoch FROM now())::bigint+30 THEN RAISE EXCEPTION 'fresh_mfa_required' USING ERRCODE='42501'; END IF;
 INSERT INTO private.managed_mfa_proofs(session_id,user_id,factor_id,verified_at_epoch) VALUES(session_uuid,principal,p_factor_id,verified_at) ON CONFLICT(session_id) DO UPDATE SET factor_id=excluded.factor_id,verified_at_epoch=excluded.verified_at_epoch WHERE managed_mfa_proofs.user_id=excluded.user_id AND managed_mfa_proofs.verified_at_epoch<=excluded.verified_at_epoch;
 RETURN verified_at;
END$$;

CREATE FUNCTION private.assert_actor(p_permission text DEFAULT NULL,p_collection_id text DEFAULT NULL,p_group_role text DEFAULT NULL,p_min_aal bigint DEFAULT 1,p_fresh_seconds bigint DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=app,pg_catalog AS $$
DECLARE principal text; claims jsonb; projected app.auth_sessions%ROWTYPE; managed jsonb; now_seconds bigint:=app.unixepoch();
BEGIN
 claims:=private.request_claims(); principal:=api.current_principal_id();
 IF principal IS NULL OR claims->>'role' IS DISTINCT FROM 'authenticated' THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501'; END IF;
 SELECT s.* INTO projected FROM app.auth_sessions s JOIN app.users u ON u.id=s.user_id
 WHERE s.id=api.current_session_id() AND s.user_id=principal AND s.revoked_at IS NULL
 AND s.expires_at>now_seconds AND u.access_status='active' FOR SHARE OF s,u;
 IF NOT FOUND THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501'; END IF;
 SELECT to_jsonb(s) INTO managed FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id
 WHERE s.id::text=projected.id AND u.id::text=claims->>'sub'
 AND (to_jsonb(u)->>'deleted_at') IS NULL
 AND (to_jsonb(u)->>'banned_until' IS NULL OR (to_jsonb(u)->>'banned_until')::timestamptz<=now())
 AND (to_jsonb(s)->>'not_after' IS NULL OR (to_jsonb(s)->>'not_after')::timestamptz>now()) FOR SHARE OF s,u;
 IF managed IS NULL THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501'; END IF;
 IF p_min_aal>1 AND (claims->>'aal' IS DISTINCT FROM 'aal2' OR managed->>'aal' IS DISTINCT FROM 'aal2' OR projected.assurance_level<>2 OR projected.mfa_at IS NULL OR projected.mfa_at<now_seconds-300 OR NOT EXISTS(SELECT 1 FROM private.managed_mfa_proofs proof JOIN auth.mfa_factors f ON f.id=proof.factor_id AND f.user_id=proof.user_id WHERE proof.session_id::text=projected.id AND proof.user_id::text=claims->>'sub' AND proof.factor_id::text=projected.mfa_factor_id AND f.status::text='verified' AND proof.verified_at_epoch=projected.mfa_at)) THEN RAISE EXCEPTION 'mfa_required' USING ERRCODE='42501'; END IF;
 IF p_fresh_seconds IS NOT NULL AND greatest(projected.auth_at,coalesce(projected.mfa_at,0))<now_seconds-p_fresh_seconds THEN RAISE EXCEPTION 'fresh_auth_required' USING ERRCODE='42501'; END IF;
 IF p_permission IS NOT NULL AND (projected.surface<>'admin' OR NOT EXISTS(SELECT 1 FROM app.admin_grants g WHERE g.user_id=principal AND g.permission=p_permission)) THEN RAISE EXCEPTION 'permission_denied' USING ERRCODE='42501'; END IF;
 IF p_collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.memberships m JOIN app.collections c ON c.id=m.collection_id WHERE m.user_id=principal AND m.collection_id=p_collection_id AND m.active=1 AND c.status='active' AND (p_group_role IS NULL OR m.role=p_group_role OR (p_group_role='admin' AND m.role='owner'))) THEN RAISE EXCEPTION 'group_access_denied' USING ERRCODE='42501'; END IF;
 RETURN principal;
END$$;

-- This additional guard binds the existing169 source guards to the real
-- managed identity/session. A forged application session row is insufficient.
CREATE FUNCTION private.trg_managed_mutation_admission() RETURNS trigger LANGUAGE plpgsql SET search_path=app,pg_catalog AS $$
DECLARE principal text;
BEGIN
 principal:=private.assert_actor(NEW.permission,NEW.collection_id,NEW.required_group_role,coalesce(NEW.minimum_assurance,1),NEW.fresh_seconds);
 IF NEW.user_id IS DISTINCT FROM principal OR NEW.session_id IS DISTINCT FROM api.current_session_id() THEN RAISE EXCEPTION 'session_changed' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER managed_mutation_admission BEFORE INSERT ON app.mutation_guards FOR EACH ROW EXECUTE FUNCTION private.trg_managed_mutation_admission();

CREATE FUNCTION private.trg_managed_auth_projection() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=app,pg_catalog AS $$
DECLARE actual jsonb;
BEGIN
 -- Access can always be irreversibly removed after provider logout. This
 -- exception changes no identity, expiry or assurance and cannot renew access.
 IF TG_OP='UPDATE' THEN
  IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL AND NEW.revocation_reason IS NOT NULL AND length(btrim(NEW.revocation_reason))>0 AND NEW.revoked_at>=OLD.created_at AND to_jsonb(OLD)-ARRAY['revoked_at','revocation_reason']=to_jsonb(NEW)-ARRAY['revoked_at','revocation_reason'] THEN RETURN NEW;END IF;
 END IF;
 SELECT to_jsonb(s) INTO actual FROM auth.sessions s JOIN private.auth_principal_links l ON l.auth_user_id=s.user_id WHERE s.id::text=NEW.id AND l.user_id=NEW.user_id;
 IF actual IS NULL THEN RAISE EXCEPTION 'managed_session_required' USING ERRCODE='42501'; END IF;
 IF NEW.assurance_level=2 AND actual->>'aal' IS DISTINCT FROM 'aal2' THEN RAISE EXCEPTION 'managed_mfa_required' USING ERRCODE='42501'; END IF;
 IF actual->>'not_after' IS NOT NULL AND NEW.expires_at>extract(epoch FROM (actual->>'not_after')::timestamptz)::bigint THEN RAISE EXCEPTION 'managed_session_expiry_exceeded' USING ERRCODE='42501'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER managed_auth_projection BEFORE INSERT OR UPDATE ON app.auth_sessions FOR EACH ROW EXECUTE FUNCTION private.trg_managed_auth_projection();

-- Curated replacement of the local-TOTP claim proof. A managed Auth proof is
-- required instead of inventing a TOTP counter/challenge or copying a secret.
CREATE OR REPLACE FUNCTION private.trg_auth_mfa_verified_session() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=app,pg_catalog AS $$
BEGIN
 IF TG_OP='UPDATE' THEN
  IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL AND NEW.revocation_reason IS NOT NULL AND length(btrim(NEW.revocation_reason))>0 AND NEW.revoked_at>=OLD.created_at AND to_jsonb(OLD)-ARRAY['revoked_at','revocation_reason']=to_jsonb(NEW)-ARRAY['revoked_at','revocation_reason'] THEN RETURN NEW;END IF;
 END IF;
 IF NEW.assurance_level=2 AND NOT EXISTS(SELECT 1 FROM private.managed_mfa_proofs p JOIN auth.sessions s ON s.id=p.session_id AND s.user_id=p.user_id JOIN auth.mfa_factors f ON f.id=p.factor_id AND f.user_id=p.user_id JOIN private.auth_principal_links l ON l.auth_user_id=p.user_id WHERE p.session_id::text=NEW.id AND l.user_id=NEW.user_id AND p.factor_id::text=NEW.mfa_factor_id AND p.verified_at_epoch=NEW.mfa_at AND p.verified_at_epoch>=app.unixepoch()-300 AND to_jsonb(s)->>'aal'='aal2' AND f.status::text='verified') THEN RAISE EXCEPTION 'verified_mfa_claim_required'; END IF;
 RETURN NEW;
END$$;

DO $$BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='collect_runtime') THEN CREATE ROLE collect_runtime NOLOGIN NOINHERIT NOBYPASSRLS; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='collect_importer') THEN CREATE ROLE collect_importer NOLOGIN NOINHERIT NOBYPASSRLS; END IF;
END$$;
GRANT USAGE ON SCHEMA app,private,api TO collect_runtime;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA app TO collect_runtime;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA app TO collect_runtime;
GRANT SELECT,INSERT ON private.auth_principal_links TO collect_runtime;
GRANT SELECT,INSERT,UPDATE ON private.supabase_otp_challenges TO collect_runtime;
GRANT SELECT,INSERT,UPDATE,DELETE ON private.bff_sessions TO collect_runtime;
GRANT SELECT,INSERT ON private.storage_namespace TO collect_runtime;
GRANT SELECT,INSERT,UPDATE ON private.storage_payload_reservations,private.storage_put_intents,private.storage_upload_attempts,private.storage_delete_intents TO collect_runtime;
GRANT SELECT,INSERT,DELETE ON private.storage_objects TO collect_runtime;
GRANT SELECT ON private.object_metadata TO collect_runtime;
-- Managed MFA proofs can only be written by the verified helper.
GRANT SELECT ON private.managed_mfa_proofs TO collect_runtime;
GRANT SELECT ON private.managed_phone_verifications TO collect_runtime;
GRANT SELECT,INSERT ON private.google_flow_context TO collect_runtime;
REVOKE ALL ON ALL TABLES IN SCHEMA app,private FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app,private,api FROM PUBLIC;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA app,private TO collect_runtime;
GRANT EXECUTE ON FUNCTION api.current_principal_id(),api.current_session_id() TO collect_runtime;
DO $$DECLARE t record; r text; BEGIN
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='app' LOOP
  EXECUTE format('ALTER TABLE app.%I ENABLE ROW LEVEL SECURITY',t.tablename);
  EXECUTE format('CREATE POLICY edge_runtime ON app.%I FOR ALL TO collect_runtime USING (true) WITH CHECK (true)',t.tablename);
 END LOOP;
 FOR t IN SELECT tablename FROM pg_tables WHERE schemaname='private' LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t.tablename);
  EXECUTE format('CREATE POLICY edge_runtime ON private.%I FOR ALL TO collect_runtime USING (true) WITH CHECK (true)',t.tablename);
 END LOOP;
 FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN
   EXECUTE format('REVOKE ALL ON SCHEMA app,private FROM %I',r);
   EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA app,private FROM %I',r);
   EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA app,private FROM %I',r);
   EXECUTE format('GRANT USAGE ON SCHEMA api TO %I',r);
  END IF;
 END LOOP;
END$$;
ALTER DEFAULT PRIVILEGES IN SCHEMA app,private,api REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA app,private,api REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
