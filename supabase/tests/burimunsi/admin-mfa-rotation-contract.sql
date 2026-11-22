-- Disposable exact-schema fixture ONLY. Seed one active synthetic Owner with
-- a cookie-bound AAL1 app session, a real synthetic verified TOTP factor, and
-- a matching GoTrue session at AAL2 with factor_id and fresh TOTP AMR. The BFF
-- row has the supplied version and a still-live verification lease. Replace
-- placeholders before execution. Never run against live accounts/database.
BEGIN;
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','__OWNER_AUTH_USER__',
 'session_id','__OWNER_SESSION__','aal','aal2','amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',__MFA_AT__::bigint)))::text,true);
DO $rotation$
DECLARE answer jsonb;old_session app.admin_sessions%ROWTYPE;current_session app.admin_sessions%ROWTYPE;meta app.auth_mfa_factors%ROWTYPE;
BEGIN
 SELECT * INTO old_session FROM app.admin_sessions WHERE token_hash='__OWNER_COOKIE_SHA256__';
 IF NOT FOUND OR old_session.issued_assurance_level<>1 THEN RAISE EXCEPTION 'synthetic_owner_not_aal1';END IF;
 BEGIN
  PERFORM private.collect_admin_mfa_prepare_v1('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OWNER_PUBLIC__',
   __BFF_VERSION__::bigint,'__WRONG_LEASE__','__OWNER_FACTOR__'::uuid,'__CANDIDATE_SHA256__','{"synthetic":true}','{"synthetic":true}');
  RAISE EXCEPTION 'admin_mfa_wrong_lease_allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 answer:=private.collect_admin_mfa_prepare_v1('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OWNER_PUBLIC__',
  __BFF_VERSION__::bigint,'__CORRECT_LEASE__','__OWNER_FACTOR__'::uuid,'__CANDIDATE_SHA256__','{"synthetic":true}','{"synthetic":true}');
 IF answer->>'state'<>'pending' OR NOT EXISTS(SELECT 1 FROM app.admin_sessions
  WHERE token_hash='__OWNER_COOKIE_SHA256__' AND issued_assurance_level=1)
  OR NOT EXISTS(SELECT 1 FROM private.bff_sessions WHERE token_hash='__OWNER_COOKIE_SHA256__'
   AND mfa_pending_hash='__CANDIDATE_SHA256__' AND refresh_lease IS NULL) THEN
  RAISE EXCEPTION 'admin_mfa_prepare_mutated_old_authority';END IF;
 BEGIN
  PERFORM private.collect_admin_mfa_complete_v1('__WRONG_CANDIDATE_SHA256__','__OWNER_ORIGIN__');
  RAISE EXCEPTION 'admin_mfa_wrong_candidate_allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF NOT EXISTS(SELECT 1 FROM app.admin_sessions WHERE token_hash='__OWNER_COOKIE_SHA256__' AND issued_assurance_level=1) THEN
  RAISE EXCEPTION 'admin_mfa_wrong_candidate_changed_old_session';END IF;
 answer:=private.collect_admin_mfa_complete_v1('__CANDIDATE_SHA256__','__OWNER_ORIGIN__');
 IF answer->>'state'<>'complete' OR answer->>'public_session_id'<>'__OWNER_PUBLIC__' THEN
  RAISE EXCEPTION 'admin_mfa_complete_unconfirmed';END IF;
 SELECT * INTO current_session FROM app.admin_sessions WHERE token_hash='__CANDIDATE_SHA256__';
 IF NOT FOUND OR current_session.issued_assurance_level<>2 OR current_session.issued_mfa_factor_id<>'__OWNER_FACTOR__'
  OR current_session.issued_mfa_at<>__MFA_AT__::bigint OR current_session.public_id<>old_session.public_id
  OR EXISTS(SELECT 1 FROM app.admin_sessions WHERE token_hash='__OWNER_COOKIE_SHA256__')
  OR NOT EXISTS(SELECT 1 FROM private.bff_sessions WHERE token_hash='__CANDIDATE_SHA256__'
   AND mfa_pending_hash IS NULL AND mfa_pending_factor IS NULL AND mfa_pending_at IS NULL) THEN
  RAISE EXCEPTION 'admin_mfa_rotation_incorrect';END IF;
 SELECT * INTO meta FROM app.auth_mfa_factors WHERE id='__OWNER_FACTOR__';
 IF NOT FOUND OR meta.status<>'verified' OR meta.secret_ciphertext::jsonb<>'{"managed_by":"supabase","version":1}'::jsonb
  OR meta.enrollment_session_id IS NOT NULL OR meta.last_totp_counter IS NOT NULL
  OR meta.user_id<>'__OWNER_PRINCIPAL__' THEN RAISE EXCEPTION 'admin_mfa_managed_metadata_incorrect';END IF;
 BEGIN
  PERFORM private.collect_admin_mfa_complete_v1('__CANDIDATE_SHA256__','__OWNER_ORIGIN__');
  RAISE EXCEPTION 'admin_mfa_candidate_reused';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END;$rotation$;
ROLLBACK;
SELECT 'synthetic_admin_mfa_rotation_pass';
