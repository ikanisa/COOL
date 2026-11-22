-- PRIVATE, UNVERSIONED additive proposal. Migration alone adopts/executes it.
-- Local flow/expected-subject proof; this does not claim provider-causal OTP
-- purpose, create an identity, or change existing privacy intake authority.
ALTER TABLE private.supabase_otp_challenges
 ADD COLUMN privacy_mode text,
 ADD COLUMN privacy_context_hash text,
 ADD COLUMN privacy_expected_auth_user_id uuid,
 ADD COLUMN privacy_expected_user_id text,
 ADD COLUMN privacy_initiating_session_id uuid,
 ADD COLUMN privacy_initiating_user_revision bigint,
 ADD COLUMN privacy_send_claim uuid,
 ADD COLUMN privacy_verification_state text,
 ADD COLUMN privacy_verification_operation_id uuid,
 ADD COLUMN privacy_verify_receipts jsonb NOT NULL DEFAULT '{}'::jsonb,
 ADD COLUMN privacy_verified_auth_user_id uuid,
 ADD COLUMN privacy_verified_user_id text,
 ADD COLUMN privacy_verified_session_id uuid,
 ADD COLUMN privacy_verified_amr_at bigint,
 ADD COLUMN privacy_cancelled_at bigint,
 ADD COLUMN privacy_cleanup_state text,
 ADD COLUMN privacy_cleanup_claim uuid,
 ADD COLUMN privacy_cleanup_session_id uuid;

ALTER TABLE private.supabase_otp_challenges ADD CONSTRAINT privacy_email_shape CHECK((
 (privacy_mode IS NULL AND privacy_context_hash IS NULL
  AND privacy_expected_auth_user_id IS NULL AND privacy_expected_user_id IS NULL
  AND privacy_initiating_session_id IS NULL AND privacy_initiating_user_revision IS NULL
  AND privacy_send_claim IS NULL AND privacy_verification_state IS NULL AND privacy_verification_operation_id IS NULL
  AND privacy_verify_receipts='{}'::jsonb AND privacy_verified_auth_user_id IS NULL AND privacy_verified_user_id IS NULL
  AND privacy_verified_session_id IS NULL AND privacy_verified_amr_at IS NULL AND privacy_cancelled_at IS NULL
  AND privacy_cleanup_state IS NULL AND privacy_cleanup_claim IS NULL AND privacy_cleanup_session_id IS NULL)
 OR
 (privacy_mode IN('current_session','portal_bootstrap') AND privacy_context_hash ~ '^[0-9a-f]{64}$'
  AND identity_type='email' AND surface='member' AND registration_allowed=0 AND expires_at<=created_at+300
  AND privacy_verification_state IN('not_started','verifying','rejected','unconfirmed','verified')
  AND jsonb_typeof(privacy_verify_receipts)='object' AND length(privacy_verify_receipts::text)<=4096
  AND privacy_cleanup_state IN('not_started','claimed','confirmed','unconfirmed')
  AND ((privacy_mode='current_session' AND privacy_expected_auth_user_id IS NOT NULL AND privacy_expected_user_id IS NOT NULL
    AND privacy_initiating_session_id IS NOT NULL AND privacy_initiating_user_revision>=1)
   OR (privacy_mode='portal_bootstrap' AND privacy_expected_auth_user_id IS NULL AND privacy_expected_user_id IS NULL
    AND privacy_initiating_session_id IS NULL AND privacy_initiating_user_revision IS NULL))
  AND ((privacy_verification_state='not_started' AND privacy_verification_operation_id IS NULL AND attempts=0)
   OR (privacy_verification_state<>'not_started' AND privacy_verification_operation_id IS NOT NULL AND attempts>=1))
  AND ((privacy_verification_state<>'verified' AND consumed_at IS NULL AND privacy_verified_auth_user_id IS NULL
    AND privacy_verified_user_id IS NULL AND privacy_verified_session_id IS NULL AND privacy_verified_amr_at IS NULL)
   OR (privacy_verification_state='verified' AND consumed_at IS NOT NULL AND privacy_verified_auth_user_id IS NOT NULL
    AND privacy_verified_user_id IS NOT NULL AND privacy_verified_session_id IS NOT NULL
    AND privacy_verified_amr_at BETWEEN created_at AND consumed_at AND consumed_at<=expires_at))
  AND ((privacy_cleanup_claim IS NULL AND privacy_cleanup_session_id IS NULL AND privacy_cleanup_state IN('not_started','unconfirmed'))
   OR (privacy_cleanup_claim IS NOT NULL AND privacy_cleanup_session_id=privacy_verified_session_id
    AND privacy_verification_state='verified' AND privacy_cleanup_state IN('claimed','confirmed','unconfirmed')))
  AND (privacy_cancelled_at IS NULL OR privacy_cancelled_at>=created_at))
) IS TRUE);

-- Invoker trigger: current_user is the runtime for direct generic-column DML,
-- but the trusted owner inside the narrow SECURITY DEFINER helper. No GUC gate.
CREATE FUNCTION private.trg_privacy_email_write_gate() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF current_user='collect_runtime' AND (NEW.privacy_mode IS NOT NULL OR (TG_OP='UPDATE' AND OLD.privacy_mode IS NOT NULL))
 THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER privacy_email_write_gate BEFORE INSERT OR UPDATE ON private.supabase_otp_challenges
 FOR EACH ROW EXECUTE FUNCTION private.trg_privacy_email_write_gate();

CREATE OR REPLACE FUNCTION private.trg_supabase_otp_identity() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE entry record; previous jsonb; receipt_count integer;
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'retain_managed_otp_admission' USING ERRCODE='42501';END IF;
 IF OLD.privacy_mode IS NULL THEN
  -- Exact original generic/phone identity and monotonic-state rule.
  IF to_jsonb(OLD)-ARRAY['attempts','consumed_at','delivery_status'] IS DISTINCT FROM to_jsonb(NEW)-ARRAY['attempts','consumed_at','delivery_status']
  THEN RAISE EXCEPTION 'immutable_managed_otp_identity' USING ERRCODE='42501';END IF;
 ELSE
  IF to_jsonb(OLD)-ARRAY['attempts','consumed_at','delivery_status','privacy_send_claim','privacy_verification_state','privacy_verification_operation_id','privacy_verify_receipts','privacy_verified_auth_user_id','privacy_verified_user_id','privacy_verified_session_id','privacy_verified_amr_at','privacy_cancelled_at','privacy_cleanup_state','privacy_cleanup_claim','privacy_cleanup_session_id']
   IS DISTINCT FROM to_jsonb(NEW)-ARRAY['attempts','consumed_at','delivery_status','privacy_send_claim','privacy_verification_state','privacy_verification_operation_id','privacy_verify_receipts','privacy_verified_auth_user_id','privacy_verified_user_id','privacy_verified_session_id','privacy_verified_amr_at','privacy_cancelled_at','privacy_cleanup_state','privacy_cleanup_claim','privacy_cleanup_session_id']
  THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
  IF (OLD.privacy_send_claim IS NOT NULL AND NEW.privacy_send_claim IS DISTINCT FROM OLD.privacy_send_claim)
   OR (OLD.delivery_status<>'reserved' AND NEW.delivery_status<>OLD.delivery_status)
   OR (OLD.privacy_cancelled_at IS NOT NULL AND NEW.privacy_cancelled_at IS DISTINCT FROM OLD.privacy_cancelled_at)
   OR (OLD.privacy_cleanup_claim IS NOT NULL AND (NEW.privacy_cleanup_claim IS DISTINCT FROM OLD.privacy_cleanup_claim OR NEW.privacy_cleanup_session_id IS DISTINCT FROM OLD.privacy_cleanup_session_id))
  THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
  IF OLD.privacy_verified_session_id IS NOT NULL AND
   jsonb_build_array(NEW.privacy_verified_auth_user_id,NEW.privacy_verified_user_id,NEW.privacy_verified_session_id,NEW.privacy_verified_amr_at,NEW.privacy_verification_state,NEW.privacy_verification_operation_id,NEW.privacy_verify_receipts)
   IS DISTINCT FROM jsonb_build_array(OLD.privacy_verified_auth_user_id,OLD.privacy_verified_user_id,OLD.privacy_verified_session_id,OLD.privacy_verified_amr_at,OLD.privacy_verification_state,OLD.privacy_verification_operation_id,OLD.privacy_verify_receipts)
  THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
  IF (OLD.privacy_cleanup_state='confirmed' AND NEW.privacy_cleanup_state<>'confirmed')
   OR (OLD.privacy_cleanup_state='unconfirmed' AND OLD.privacy_cleanup_claim IS NOT NULL AND NEW.privacy_cleanup_state<>'unconfirmed')
   OR (OLD.privacy_cleanup_state='claimed' AND NEW.privacy_cleanup_state NOT IN('claimed','confirmed','unconfirmed'))
  THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
  FOR entry IN SELECT key,value FROM jsonb_each(OLD.privacy_verify_receipts) LOOP
   previous:=NEW.privacy_verify_receipts->entry.key;
   IF previous IS NULL OR previous->'admitted_at' IS DISTINCT FROM entry.value->'admitted_at'
    OR (entry.value->>'state'<>'verifying' AND previous IS DISTINCT FROM entry.value)
    OR (entry.value->>'state'='verifying' AND previous->>'state' NOT IN('verifying','rejected','unconfirmed','verified'))
   THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
  END LOOP;
  SELECT count(*) INTO receipt_count FROM jsonb_object_keys(NEW.privacy_verify_receipts);
  IF receipt_count<>NEW.attempts OR receipt_count>5 THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 END IF;
 IF NEW.attempts<OLD.attempts OR (OLD.consumed_at IS NOT NULL AND NEW.consumed_at IS DISTINCT FROM OLD.consumed_at)
 THEN RAISE EXCEPTION 'managed_otp_state_regression' USING ERRCODE='42501';END IF;
 RETURN NEW;
END$$;

CREATE FUNCTION private.privacy_email_native() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE principal text; result jsonb;
BEGIN
 BEGIN
  principal:=private.assert_actor(NULL,NULL,NULL,1,NULL);
  SELECT jsonb_build_object('auth_user_id',a.id::text,'user_id',u.id,'session_id',s.id,
    'user_revision',u.revision,'identity_value',lower(a.email)) INTO result
   FROM app.users u JOIN private.auth_principal_links l ON l.user_id=u.id
   JOIN auth.users a ON a.id=l.auth_user_id JOIN app.auth_sessions s ON s.user_id=u.id
   WHERE u.id=principal AND u.access_status='active' AND s.id=api.current_session_id() AND s.surface='member'
    AND s.revoked_at IS NULL AND s.expires_at>app.unixepoch() AND a.id::text=private.request_claims()->>'sub'
    AND a.email_confirmed_at IS NOT NULL AND lower(a.email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    AND length(a.email)<=254 AND a.email !~ '[[:cntrl:]]'
   FOR SHARE OF u,l,a,s;
  IF result IS NULL THEN RAISE EXCEPTION 'privacy_email_denied';END IF;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END;
 RETURN result;
END$$;

CREATE FUNCTION private.privacy_email_row(p_id text,p_context_hash text,p_original boolean DEFAULT true,p_write boolean DEFAULT true)
RETURNS private.supabase_otp_challenges LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE challenge private.supabase_otp_challenges%ROWTYPE; original jsonb; claims jsonb:=private.request_claims();
BEGIN
 IF p_id IS NULL OR p_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  OR p_context_hash IS NULL OR p_context_hash !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 IF p_write THEN
  SELECT * INTO challenge FROM private.supabase_otp_challenges c WHERE c.id=p_id AND c.privacy_context_hash=p_context_hash AND c.privacy_mode IS NOT NULL FOR UPDATE;
 ELSE
  SELECT * INTO challenge FROM private.supabase_otp_challenges c WHERE c.id=p_id AND c.privacy_context_hash=p_context_hash AND c.privacy_mode IS NOT NULL FOR SHARE;
 END IF;
 IF NOT FOUND THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 IF p_original THEN
  IF challenge.privacy_mode='current_session' THEN
   original:=private.privacy_email_native();
   IF original->>'auth_user_id' IS DISTINCT FROM challenge.privacy_expected_auth_user_id::text
    OR original->>'user_id' IS DISTINCT FROM challenge.privacy_expected_user_id
    OR original->>'session_id' IS DISTINCT FROM challenge.privacy_initiating_session_id::text
    OR (original->>'user_revision')::bigint IS DISTINCT FROM challenge.privacy_initiating_user_revision
    OR original->>'identity_value' IS DISTINCT FROM challenge.identity_value
   THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
  ELSIF claims->>'sub' IS NOT NULL OR claims->>'session_id' IS NOT NULL OR claims->>'role' IS NOT NULL
  THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 END IF;
 RETURN challenge;
END$$;

CREATE FUNCTION private.privacy_email_pending(p_challenge private.supabase_otp_challenges) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT p_challenge.privacy_cancelled_at IS NULL AND p_challenge.consumed_at IS NULL
  AND app.unixepoch() BETWEEN p_challenge.created_at AND p_challenge.expires_at
  AND NOT EXISTS(SELECT 1 FROM private.supabase_otp_challenges c WHERE c.identity_hash=p_challenge.identity_hash
   AND c.surface=p_challenge.surface AND c.created_at>p_challenge.created_at)
$$;

CREATE FUNCTION private.privacy_email_result(p_challenge private.supabase_otp_challenges,p_operation uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT jsonb_build_object('challenge',jsonb_build_object(
  'id',p_challenge.id,'mode',p_challenge.privacy_mode,'identity_value',p_challenge.identity_value,
  'created_at',p_challenge.created_at,'expires_at',p_challenge.expires_at,'delivery_status',p_challenge.delivery_status,
  'verification_state',coalesce(p_challenge.privacy_verify_receipts->p_operation::text->>'state',p_challenge.privacy_verification_state),
  'verification_operation_id',CASE WHEN p_operation IS NOT NULL AND p_challenge.privacy_verify_receipts ? p_operation::text THEN p_operation ELSE p_challenge.privacy_verification_operation_id END,
  'expected_auth_user_id',p_challenge.privacy_expected_auth_user_id,'expected_user_id',p_challenge.privacy_expected_user_id,
  'initiating_session_id',p_challenge.privacy_initiating_session_id,'initiating_user_revision',p_challenge.privacy_initiating_user_revision,
  'verified_session_id',p_challenge.privacy_verified_session_id,'verified_amr_at',p_challenge.privacy_verified_amr_at,
  'cancelled',p_challenge.privacy_cancelled_at IS NOT NULL,'cleanup_state',p_challenge.privacy_cleanup_state))
$$;

CREATE FUNCTION private.privacy_email_event(p_challenge private.supabase_otp_challenges) RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$
 SELECT min(t.event_at) FROM (
  SELECT CASE WHEN jsonb_typeof(item)='object' AND item->>'method'='otp' AND jsonb_typeof(item->'timestamp')='number'
   AND item->>'timestamp' ~ '^[0-9]{1,16}$' THEN (item->>'timestamp')::bigint END AS event_at
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(private.request_claims()->'amr')='array' THEN private.request_claims()->'amr' ELSE '[]'::jsonb END) item
 ) t WHERE t.event_at BETWEEN greatest(1,p_challenge.created_at) AND least(app.unixepoch(),p_challenge.expires_at)
  AND t.event_at<=9007199254740991
$$;

CREATE FUNCTION private.privacy_email_candidate(p_challenge private.supabase_otp_challenges,p_cleanup boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE claims jsonb:=private.request_claims(); actual_session uuid; actual_auth uuid; principal text; event_at bigint; projected app.auth_sessions%ROWTYPE;
BEGIN
 BEGIN
  actual_session:=(claims->>'session_id')::uuid;actual_auth:=(claims->>'sub')::uuid;
  IF claims->>'role' IS DISTINCT FROM 'authenticated' OR NOT coalesce(private.is_managed_session(actual_auth,actual_session),false)
  THEN RAISE EXCEPTION 'privacy_email_denied';END IF;
  SELECT l.user_id INTO principal FROM private.auth_principal_links l JOIN auth.users a ON a.id=l.auth_user_id
   JOIN app.users u ON u.id=l.user_id WHERE a.id=actual_auth
   AND (p_cleanup OR (a.email_confirmed_at IS NOT NULL AND lower(a.email)=p_challenge.identity_value AND u.access_status='active')) FOR SHARE OF l,a,u;
  IF principal IS NULL OR (p_challenge.privacy_mode='current_session' AND
   (actual_auth IS DISTINCT FROM p_challenge.privacy_expected_auth_user_id OR principal IS DISTINCT FROM p_challenge.privacy_expected_user_id
    OR actual_session=p_challenge.privacy_initiating_session_id)) THEN RAISE EXCEPTION 'privacy_email_denied';END IF;
  event_at:=private.privacy_email_event(p_challenge);
  IF event_at IS NULL OR (NOT p_cleanup AND (app.unixepoch()>p_challenge.expires_at OR event_at<app.unixepoch()-300))
  THEN RAISE EXCEPTION 'privacy_email_denied';END IF;
  SELECT * INTO projected FROM app.auth_sessions s WHERE s.id=actual_session::text AND s.user_id=principal
   AND s.surface='member' AND s.auth_at=event_at AND (p_cleanup OR (s.revoked_at IS NULL AND s.expires_at>app.unixepoch())) FOR SHARE OF s;
  IF NOT FOUND THEN RAISE EXCEPTION 'privacy_email_denied';END IF;
  IF p_cleanup THEN
   IF actual_auth IS DISTINCT FROM p_challenge.privacy_verified_auth_user_id OR principal IS DISTINCT FROM p_challenge.privacy_verified_user_id
    OR actual_session IS DISTINCT FROM p_challenge.privacy_verified_session_id OR event_at IS DISTINCT FROM p_challenge.privacy_verified_amr_at
   THEN RAISE EXCEPTION 'privacy_email_denied';END IF;
  ELSIF p_challenge.privacy_mode='current_session' THEN
   -- Candidate claims are installed. Original authority comes only from the
   -- immutable snapshot and actual original managed/application rows.
   PERFORM 1 FROM app.users u JOIN private.auth_principal_links l ON l.user_id=u.id
    JOIN auth.users a ON a.id=l.auth_user_id JOIN auth.sessions managed ON managed.user_id=a.id
    JOIN app.auth_sessions s ON s.id=managed.id::text AND s.user_id=u.id
    WHERE u.id=p_challenge.privacy_expected_user_id AND u.access_status='active' AND u.revision=p_challenge.privacy_initiating_user_revision
     AND a.id=p_challenge.privacy_expected_auth_user_id AND managed.id=p_challenge.privacy_initiating_session_id
     AND s.surface='member' AND s.revoked_at IS NULL AND s.expires_at>app.unixepoch()
     AND a.email_confirmed_at IS NOT NULL AND lower(a.email)=p_challenge.identity_value
     AND to_jsonb(a)->>'deleted_at' IS NULL AND (to_jsonb(a)->>'banned_until' IS NULL OR (to_jsonb(a)->>'banned_until')::timestamptz<=now())
     AND (to_jsonb(managed)->>'not_after' IS NULL OR (to_jsonb(managed)->>'not_after')::timestamptz>now())
    FOR SHARE OF u,l,a,managed,s;
   IF NOT FOUND THEN RAISE EXCEPTION 'privacy_email_denied';END IF;
  END IF;
 EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END;
 RETURN jsonb_build_object('auth_user_id',actual_auth,'user_id',principal,'session_id',actual_session,'amr_at',event_at);
END$$;

CREATE FUNCTION private.privacy_email_prepare(p_id text,p_mode text,p_identity text,p_context_hash text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE challenge private.supabase_otp_challenges%ROWTYPE; native jsonb; target text; at bigint:=app.unixepoch();
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 IF p_id IS NULL OR p_id !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  OR p_context_hash IS NULL OR p_context_hash !~ '^[0-9a-f]{64}$' OR p_mode IS NULL OR p_mode NOT IN('current_session','portal_bootstrap')
 THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 IF p_mode='current_session' THEN
  IF p_identity IS NOT NULL THEN RAISE EXCEPTION 'privacy_email_invalid' USING ERRCODE='22023';END IF;
  native:=private.privacy_email_native();target:=native->>'identity_value';
 ELSE
  IF private.request_claims()->>'sub' IS NOT NULL OR private.request_claims()->>'session_id' IS NOT NULL OR private.request_claims()->>'role' IS NOT NULL
  THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
  target:=p_identity;
  IF target IS NULL OR target<>lower(btrim(target)) OR length(target) NOT BETWEEN 3 AND 254
   OR target !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' OR target ~ '[[:cntrl:]]'
  THEN RAISE EXCEPTION 'privacy_email_invalid' USING ERRCODE='22023';END IF;
 END IF;
 SELECT * INTO challenge FROM private.supabase_otp_challenges c WHERE c.id=p_id FOR UPDATE;
 IF FOUND THEN
  IF challenge.privacy_mode IS DISTINCT FROM p_mode OR challenge.privacy_context_hash IS DISTINCT FROM p_context_hash OR challenge.identity_value IS DISTINCT FROM target
  THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
  challenge:=private.privacy_email_row(p_id,p_context_hash,true,true);
  RETURN private.privacy_email_result(challenge)||jsonb_build_object('created',false);
 END IF;
 INSERT INTO private.supabase_otp_challenges(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status,
  privacy_mode,privacy_context_hash,privacy_expected_auth_user_id,privacy_expected_user_id,privacy_initiating_session_id,privacy_initiating_user_revision,
  privacy_verification_state,privacy_cleanup_state)
 VALUES(p_id,encode(sha256(convert_to('email:'||target,'UTF8')),'hex'),'email',target,'member',0,at,at+300,'reserved',p_mode,p_context_hash,
  (native->>'auth_user_id')::uuid,native->>'user_id',(native->>'session_id')::uuid,(native->>'user_revision')::bigint,'not_started','not_started') RETURNING * INTO challenge;
 RETURN private.privacy_email_result(challenge)||jsonb_build_object('created',true);
END$$;

CREATE FUNCTION private.privacy_email_send_claim(p_id text,p_context_hash text,p_claim uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE challenge private.supabase_otp_challenges%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);challenge:=private.privacy_email_row(p_id,p_context_hash);
 IF p_claim IS NULL THEN RAISE EXCEPTION 'privacy_email_invalid' USING ERRCODE='22023';END IF;
 IF challenge.privacy_send_claim IS NOT NULL THEN RETURN private.privacy_email_result(challenge)||jsonb_build_object('claimed',false);END IF;
 IF NOT private.privacy_email_pending(challenge) THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 UPDATE private.supabase_otp_challenges SET privacy_send_claim=p_claim WHERE id=p_id RETURNING * INTO challenge;
 RETURN private.privacy_email_result(challenge)||jsonb_build_object('claimed',true);
END$$;

CREATE FUNCTION private.privacy_email_send_finish(p_id text,p_context_hash text,p_claim uuid,p_outcome text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE challenge private.supabase_otp_challenges%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);challenge:=private.privacy_email_row(p_id,p_context_hash);
 IF p_claim IS NULL OR challenge.privacy_send_claim IS DISTINCT FROM p_claim THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 IF p_outcome IS NULL OR p_outcome NOT IN('accepted','rejected','unknown') THEN RAISE EXCEPTION 'privacy_email_invalid' USING ERRCODE='22023';END IF;
 IF challenge.delivery_status=p_outcome THEN RETURN private.privacy_email_result(challenge);END IF;
 IF challenge.delivery_status<>'reserved' THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 UPDATE private.supabase_otp_challenges SET delivery_status=p_outcome WHERE id=p_id RETURNING * INTO challenge;
 RETURN private.privacy_email_result(challenge);
END$$;

CREATE FUNCTION private.privacy_email_verify_claim(p_id text,p_context_hash text,p_operation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE challenge private.supabase_otp_challenges%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);challenge:=private.privacy_email_row(p_id,p_context_hash);
 IF p_operation IS NULL THEN RAISE EXCEPTION 'privacy_email_invalid' USING ERRCODE='22023';END IF;
 IF challenge.privacy_verify_receipts ? p_operation::text THEN RETURN private.privacy_email_result(challenge,p_operation)||jsonb_build_object('claimed',false);END IF;
 IF NOT private.privacy_email_pending(challenge) OR NOT(challenge.delivery_status IN('accepted','unknown')
   OR (challenge.privacy_mode='portal_bootstrap' AND challenge.delivery_status='rejected'))
  OR challenge.attempts>=5 OR challenge.privacy_verification_state NOT IN('not_started','rejected')
 THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 UPDATE private.supabase_otp_challenges SET attempts=attempts+1,privacy_verification_operation_id=p_operation,privacy_verification_state='verifying',
  privacy_verify_receipts=privacy_verify_receipts||jsonb_build_object(p_operation::text,jsonb_build_object('state','verifying','admitted_at',app.unixepoch()))
  WHERE id=p_id RETURNING * INTO challenge;
 RETURN private.privacy_email_result(challenge)||jsonb_build_object('claimed',true);
END$$;

CREATE FUNCTION private.privacy_email_verify_finish(p_id text,p_context_hash text,p_operation uuid,p_outcome text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE challenge private.supabase_otp_challenges%ROWTYPE; old_state text;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);challenge:=private.privacy_email_row(p_id,p_context_hash);
 IF p_operation IS NULL OR NOT(challenge.privacy_verify_receipts ? p_operation::text) THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 IF p_outcome IS NULL OR p_outcome NOT IN('rejected','unconfirmed') THEN RAISE EXCEPTION 'privacy_email_invalid' USING ERRCODE='22023';END IF;
 old_state:=challenge.privacy_verify_receipts->p_operation::text->>'state';
 IF old_state=p_outcome THEN RETURN private.privacy_email_result(challenge,p_operation);END IF;
 IF old_state<>'verifying' OR challenge.privacy_verification_operation_id IS DISTINCT FROM p_operation
 THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 UPDATE private.supabase_otp_challenges SET privacy_verification_state=p_outcome,
  privacy_verify_receipts=jsonb_set(privacy_verify_receipts,ARRAY[p_operation::text,'state'],to_jsonb(p_outcome))
  WHERE id=p_id RETURNING * INTO challenge;
 RETURN private.privacy_email_result(challenge,p_operation);
END$$;

CREATE FUNCTION private.privacy_email_consume(p_id text,p_context_hash text,p_operation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE challenge private.supabase_otp_challenges%ROWTYPE; candidate jsonb; proof jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);challenge:=private.privacy_email_row(p_id,p_context_hash,false,true);
 IF p_operation IS NULL OR challenge.privacy_verification_operation_id IS DISTINCT FROM p_operation
 THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 IF challenge.privacy_verification_state<>'verifying' OR NOT private.privacy_email_pending(challenge)
 THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 candidate:=private.privacy_email_candidate(challenge,false);
 UPDATE private.supabase_otp_challenges SET consumed_at=app.unixepoch(),privacy_verification_state='verified',
  privacy_verify_receipts=jsonb_set(privacy_verify_receipts,ARRAY[p_operation::text,'state'],'"verified"'::jsonb),
  privacy_verified_auth_user_id=(candidate->>'auth_user_id')::uuid,privacy_verified_user_id=candidate->>'user_id',
  privacy_verified_session_id=(candidate->>'session_id')::uuid,privacy_verified_amr_at=(candidate->>'amr_at')::bigint
  WHERE id=p_id RETURNING * INTO challenge;
 proof:=jsonb_build_object('purpose','account_deletion_request','challenge_id',challenge.id,'user_id',challenge.privacy_verified_user_id,
  'auth_user_id',challenge.privacy_verified_auth_user_id,'initiating_session_id',challenge.privacy_initiating_session_id,
  'session_id',challenge.privacy_verified_session_id,'method','otp','authenticated_at',challenge.privacy_verified_amr_at,'expires_at',challenge.expires_at);
 RETURN private.privacy_email_result(challenge)||jsonb_build_object('proof',proof);
END$$;

CREATE FUNCTION private.privacy_email_status(p_id text,p_context_hash text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 RETURN private.privacy_email_result(private.privacy_email_row(p_id,p_context_hash,true,false));
END$$;

CREATE FUNCTION private.privacy_email_cancel(p_id text,p_context_hash text,p_operation uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE challenge private.supabase_otp_challenges%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);challenge:=private.privacy_email_row(p_id,p_context_hash);
 IF p_operation IS DISTINCT FROM challenge.privacy_verification_operation_id THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 IF challenge.privacy_cancelled_at IS NULL THEN
  UPDATE private.supabase_otp_challenges SET privacy_cancelled_at=app.unixepoch(),
   privacy_cleanup_state=CASE WHEN privacy_cleanup_claim IS NULL AND privacy_verification_state IN('verifying','unconfirmed','verified') THEN 'unconfirmed' ELSE privacy_cleanup_state END
   WHERE id=p_id RETURNING * INTO challenge;
 END IF;
 RETURN private.privacy_email_result(challenge);
END$$;

CREATE FUNCTION private.privacy_email_cleanup_claim(p_id text,p_context_hash text,p_operation uuid,p_claim uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE challenge private.supabase_otp_challenges%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);challenge:=private.privacy_email_row(p_id,p_context_hash,false,true);
 IF p_operation IS NULL OR p_claim IS NULL OR challenge.privacy_verification_state<>'verified'
  OR challenge.privacy_verification_operation_id IS DISTINCT FROM p_operation
 THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 -- Irreversible exact-candidate retirement only: no new 300s/flow-expiry or
 -- original-session-live requirement after the successful immutable consume.
 PERFORM private.privacy_email_candidate(challenge,true);
 IF challenge.privacy_cleanup_claim IS NOT NULL THEN RETURN private.privacy_email_result(challenge)||jsonb_build_object('claimed',false);END IF;
 UPDATE private.supabase_otp_challenges SET privacy_cancelled_at=coalesce(privacy_cancelled_at,app.unixepoch()),privacy_cleanup_state='claimed',
  privacy_cleanup_claim=p_claim,privacy_cleanup_session_id=privacy_verified_session_id WHERE id=p_id RETURNING * INTO challenge;
 RETURN private.privacy_email_result(challenge)||jsonb_build_object('claimed',true);
END$$;

CREATE FUNCTION private.privacy_email_cleanup_finish(p_id text,p_context_hash text,p_operation uuid,p_claim uuid,p_outcome text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$
DECLARE challenge private.supabase_otp_challenges%ROWTYPE; claims jsonb:=private.request_claims();
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);challenge:=private.privacy_email_row(p_id,p_context_hash,false,true);
 IF p_operation IS NULL OR p_claim IS NULL OR challenge.privacy_verification_state<>'verified'
  OR challenge.privacy_verification_operation_id IS DISTINCT FROM p_operation OR challenge.privacy_cleanup_claim IS DISTINCT FROM p_claim
  OR challenge.privacy_cleanup_session_id IS DISTINCT FROM challenge.privacy_verified_session_id
  OR claims->>'role' IS DISTINCT FROM 'authenticated' OR claims->>'sub' IS DISTINCT FROM challenge.privacy_verified_auth_user_id::text
  OR claims->>'session_id' IS DISTINCT FROM challenge.privacy_cleanup_session_id::text
  OR private.privacy_email_event(challenge) IS DISTINCT FROM challenge.privacy_verified_amr_at
  OR NOT EXISTS(SELECT 1 FROM private.auth_principal_links l WHERE l.auth_user_id=challenge.privacy_verified_auth_user_id AND l.user_id=challenge.privacy_verified_user_id)
 THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 IF p_outcome IS NULL OR p_outcome NOT IN('confirmed','unconfirmed') THEN RAISE EXCEPTION 'privacy_email_invalid' USING ERRCODE='22023';END IF;
 IF challenge.privacy_cleanup_state=p_outcome THEN RETURN private.privacy_email_result(challenge);END IF;
 IF challenge.privacy_cleanup_state<>'claimed' THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 IF p_outcome='confirmed' THEN
  -- The definite provider logout may already have deleted auth.sessions.
  -- Only remove this exact recorded application's access; never infer another
  -- session, recreate an Auth row, or promote an unknown cleanup outcome.
  UPDATE app.auth_sessions SET revoked_at=app.unixepoch(),revocation_reason='privacy_email_candidate_cleanup'
   WHERE id=challenge.privacy_cleanup_session_id::text AND user_id=challenge.privacy_verified_user_id
    AND surface='member' AND auth_at=challenge.privacy_verified_amr_at AND revoked_at IS NULL;
  IF NOT EXISTS(SELECT 1 FROM app.auth_sessions s WHERE s.id=challenge.privacy_cleanup_session_id::text
   AND s.user_id=challenge.privacy_verified_user_id AND s.surface='member' AND s.auth_at=challenge.privacy_verified_amr_at
   AND s.revoked_at IS NOT NULL AND s.revocation_reason IS NOT NULL)
  THEN RAISE EXCEPTION 'privacy_email_denied' USING ERRCODE='42501';END IF;
 END IF;
 UPDATE private.supabase_otp_challenges SET privacy_cleanup_state=p_outcome WHERE id=p_id RETURNING * INTO challenge;
 RETURN private.privacy_email_result(challenge);
END$$;

-- Table-wide rights would permit writes to new privacy columns. Remove both
-- table and any historical column ACLs, then restore the exact generic writers.
REVOKE INSERT,UPDATE,DELETE ON TABLE private.supabase_otp_challenges FROM PUBLIC,anon,authenticated,collect_runtime;
DO $acl$
DECLARE columns text;
BEGIN
 SELECT string_agg(quote_ident(a.attname),',' ORDER BY a.attnum) INTO columns FROM pg_attribute a
 WHERE a.attrelid='private.supabase_otp_challenges'::regclass AND a.attnum>0 AND NOT a.attisdropped;
 EXECUTE format('REVOKE INSERT(%s),UPDATE(%s) ON TABLE private.supabase_otp_challenges FROM PUBLIC,anon,authenticated,collect_runtime',columns,columns);
END $acl$;
GRANT INSERT(id,identity_hash,identity_type,identity_value,surface,registration_allowed,created_at,expires_at,delivery_status)
 ON private.supabase_otp_challenges TO collect_runtime;
GRANT UPDATE(attempts,consumed_at,delivery_status) ON private.supabase_otp_challenges TO collect_runtime;
REVOKE ALL ON FUNCTION private.trg_privacy_email_write_gate(),private.privacy_email_native(),
 private.privacy_email_row(text,text,boolean,boolean),private.privacy_email_pending(private.supabase_otp_challenges),
 private.privacy_email_result(private.supabase_otp_challenges,uuid),private.privacy_email_event(private.supabase_otp_challenges),
 private.privacy_email_candidate(private.supabase_otp_challenges,boolean)
 FROM PUBLIC,anon,authenticated,collect_runtime;
REVOKE ALL ON FUNCTION private.privacy_email_prepare(text,text,text,text),private.privacy_email_send_claim(text,text,uuid),
 private.privacy_email_send_finish(text,text,uuid,text),private.privacy_email_verify_claim(text,text,uuid),
 private.privacy_email_verify_finish(text,text,uuid,text),private.privacy_email_consume(text,text,uuid),
 private.privacy_email_status(text,text),private.privacy_email_cancel(text,text,uuid),
 private.privacy_email_cleanup_claim(text,text,uuid,uuid),private.privacy_email_cleanup_finish(text,text,uuid,uuid,text)
 FROM PUBLIC,anon,authenticated,collect_runtime;
GRANT EXECUTE ON FUNCTION private.privacy_email_prepare(text,text,text,text),private.privacy_email_send_claim(text,text,uuid),
 private.privacy_email_send_finish(text,text,uuid,text),private.privacy_email_verify_claim(text,text,uuid),
 private.privacy_email_verify_finish(text,text,uuid,text),private.privacy_email_consume(text,text,uuid),
 private.privacy_email_status(text,text),private.privacy_email_cancel(text,text,uuid),
 private.privacy_email_cleanup_claim(text,text,uuid,uuid),private.privacy_email_cleanup_finish(text,text,uuid,uuid,text) TO collect_runtime;
