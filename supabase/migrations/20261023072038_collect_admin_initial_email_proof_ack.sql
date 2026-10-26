-- Initial Admin email proof may be persisted after the provider's accepted
-- challenge expires, because the signed OTP event and local consumption are
-- already bounded to that challenge. Reauthentication still requires a live
-- challenge, and an initial proof older than five minutes is never accepted.
-- CREATE OR REPLACE retains the existing function owner and EXECUTE grants.
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
  OR p_challenge.expires_at>p_challenge.created_at+300 OR (NOT p_initial AND app.unixepoch()>p_challenge.expires_at)
 THEN RAISE EXCEPTION 'admin_email_candidate_denied' USING ERRCODE='42501';END IF;
 PERFORM 1 FROM auth.users u WHERE u.id=subject AND u.email_confirmed_at IS NOT NULL AND lower(u.email)=p_challenge.identity_value FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'admin_email_candidate_denied' USING ERRCODE='42501';END IF;
 SELECT max(floor(extract(epoch FROM updated_at))::bigint) INTO event_at FROM auth.mfa_amr_claims
 WHERE session_id=candidate AND authentication_method='otp';
 IF event_at IS NULL OR event_at NOT BETWEEN greatest(1,p_challenge.created_at) AND least(app.unixepoch(),p_challenge.expires_at)
  OR (p_initial AND event_at<app.unixepoch()-300)
  OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(claims->'amr')='array' THEN claims->'amr' ELSE '[]'::jsonb END) item
   WHERE item->>'method'='otp' AND jsonb_typeof(item->'timestamp')='number' AND item->>'timestamp' ~ '^[0-9]{1,16}$'
    AND abs((item->>'timestamp')::bigint-event_at)<=1)
  OR (p_initial AND (p_actor->>'auth_at')::bigint<>event_at)
  OR (NOT p_initial AND EXISTS(SELECT 1 FROM app.auth_sessions WHERE id=candidate::text))
 THEN RAISE EXCEPTION 'admin_email_candidate_denied' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('session_id',candidate,'amr_at',event_at);
END$$;

