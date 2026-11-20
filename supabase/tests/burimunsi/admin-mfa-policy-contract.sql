-- Disposable synthetic PostgreSQL fixture ONLY. Seed an active synthetic
-- Owner, current cookie-bound email proof, a real synthetic verified GoTrue
-- TOTP factor, matching AAL2 session/AMR and managed proof, and run against a
-- fenced operator fixture with migration 110100. Substitute placeholders.
-- Never run this file on the live database or real accounts.
BEGIN;
DO $default$
BEGIN
 IF private.collect_admin_mfa_policy_enabled_v1() IS DISTINCT FROM false THEN RAISE EXCEPTION 'admin_mfa_default_not_disabled';END IF;
END;$default$;
UPDATE app.runtime_config SET value_json='{"version":1,"required":true}',revision=revision+1,
 updated_at=to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
 WHERE key='security:admin_mfa_required:v1';
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true);
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','__OWNER_AUTH_USER__',
 'session_id','__OWNER_SESSION__','aal','aal2','amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',__MFA_AT__::bigint)))::text,true);
SELECT private.set_admin_email_context('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OWNER_PUBLIC__');
DO $valid$
BEGIN
 IF private.collect_admin_mfa_policy_enabled_v1() IS DISTINCT FROM true OR (private.assert_admin_email_context(300)).id IS NULL THEN
  RAISE EXCEPTION 'admin_mfa_current_proofs_denied';END IF;
 BEGIN
  UPDATE app.runtime_config SET value_json='{"version":1,"required":false}',revision=revision+1
   WHERE key='security:admin_mfa_required:v1';
  RAISE EXCEPTION 'admin_mfa_runtime_policy_change_allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END;$valid$;
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','__OWNER_AUTH_USER__',
 'session_id','__OWNER_SESSION__','aal','aal1')::text,true);
DO $weak$
BEGIN
 BEGIN
  PERFORM private.assert_admin_email_context(300);
  RAISE EXCEPTION 'admin_mfa_aal1_sensitive_action_allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END;$weak$;
RESET ROLE;
UPDATE auth.mfa_factors SET status='unverified' WHERE id='__OWNER_FACTOR__'::uuid;
SET LOCAL ROLE collect_runtime;
SELECT set_config('request.jwt.claims',jsonb_build_object('role','authenticated','sub','__OWNER_AUTH_USER__',
 'session_id','__OWNER_SESSION__','aal','aal2')::text,true);
DO $revoked$
BEGIN
 BEGIN
  PERFORM private.assert_admin_email_context(300);
  RAISE EXCEPTION 'admin_mfa_revoked_factor_allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END;$revoked$;
ROLLBACK;
SELECT 'synthetic_admin_mfa_policy_pass';
