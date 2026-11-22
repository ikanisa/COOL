-- Disposable synthetic PostgreSQL fixture only. Substitute all placeholders
-- with seeded identities in a 006-equivalent schema plus migration 110100.
-- The Owner has a current email proof, the two Owner TOTP factors have the
-- named states, FOREIGN_FACTOR belongs to a different real synthetic user,
-- and STAFF represents a distinct active Admin-surface staff session.
-- Never run against real accounts or a live database.
BEGIN;
DO $privileges$
BEGIN
 IF has_function_privilege('collect_runtime','private.record_mfa_projection(uuid)','EXECUTE')
  OR has_function_privilege('anon','private.collect_admin_mfa_authorize_v1(text,text,text,text,text,uuid)','EXECUTE')
  OR has_function_privilege('authenticated','private.collect_admin_mfa_authorize_v1(text,text,text,text,text,uuid)','EXECUTE')
  OR NOT has_function_privilege('collect_runtime','private.collect_admin_mfa_authorize_v1(text,text,text,text,text,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'admin_mfa_wrong_grant';END IF;
END;$privileges$;
SET LOCAL ROLE collect_runtime;
SELECT set_config('collect.edge_verified','true',true);
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"__OWNER_AUTH_USER__","session_id":"__OWNER_SESSION__","aal":"aal1"}',true);
SELECT set_config('collect.admin_email_context','prior-context',true);
DO $owner$
DECLARE answer jsonb;
BEGIN
 answer:=private.collect_admin_mfa_authorize_v1('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OWNER_PUBLIC__','list',NULL);
 IF answer->'authorized' IS DISTINCT FROM 'true'::jsonb OR answer->>'action'<>'list' OR answer->'factor_status' IS DISTINCT FROM 'null'::jsonb THEN
  RAISE EXCEPTION 'admin_mfa_list_incorrect';END IF;
 answer:=private.collect_admin_mfa_authorize_v1('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OWNER_PUBLIC__','enroll',NULL);
 IF answer->'authorized' IS DISTINCT FROM 'true'::jsonb THEN RAISE EXCEPTION 'admin_mfa_enroll_incorrect';END IF;
 answer:=private.collect_admin_mfa_authorize_v1('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OWNER_PUBLIC__','challenge','__OWNER_PENDING_FACTOR__'::uuid);
 IF answer->>'factor_status'<>'unverified' THEN RAISE EXCEPTION 'admin_mfa_pending_incorrect';END IF;
 answer:=private.collect_admin_mfa_authorize_v1('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OWNER_PUBLIC__','verify','__OWNER_VERIFIED_FACTOR__'::uuid);
 IF answer->>'factor_status'<>'verified' THEN RAISE EXCEPTION 'admin_mfa_verified_incorrect';END IF;
 answer:=private.collect_admin_mfa_authorize_v1('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OWNER_PUBLIC__','cancel','__OWNER_PENDING_FACTOR__'::uuid);
 IF answer->>'factor_status'<>'unverified' OR current_setting('collect.admin_email_context',true)<>'prior-context' THEN
  RAISE EXCEPTION 'admin_mfa_context_changed';END IF;
 BEGIN
  PERFORM private.collect_admin_mfa_authorize_v1('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OWNER_PUBLIC__','verify','__FOREIGN_FACTOR__'::uuid);
  RAISE EXCEPTION 'admin_mfa_foreign_factor_allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  PERFORM private.collect_admin_mfa_authorize_v1('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OWNER_PUBLIC__','cancel','__OWNER_VERIFIED_FACTOR__'::uuid);
  RAISE EXCEPTION 'admin_mfa_verified_cancel_allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  PERFORM private.collect_admin_mfa_authorize_v1('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OWNER_PUBLIC__','enroll','__OWNER_PENDING_FACTOR__'::uuid);
  RAISE EXCEPTION 'admin_mfa_invalid_action_allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  PERFORM private.collect_admin_mfa_authorize_v1('__OWNER_ADMIN__','__OWNER_COOKIE_SHA256__','__OWNER_ORIGIN__','__OTHER_PUBLIC__','list',NULL);
  RAISE EXCEPTION 'admin_mfa_foreign_cookie_allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF current_setting('collect.admin_email_context',true)<>'prior-context' THEN RAISE EXCEPTION 'admin_mfa_exception_context_changed';END IF;
END;$owner$;
SELECT set_config('request.jwt.claims','{"role":"authenticated","sub":"__STAFF_AUTH_USER__","session_id":"__STAFF_SESSION__","aal":"aal1"}',true);
DO $staff$
BEGIN
 IF (private.collect_admin_mfa_authorize_v1('__STAFF_ADMIN__','__STAFF_COOKIE_SHA256__','__STAFF_ORIGIN__','__STAFF_PUBLIC__','list',NULL)->>'authorized') IS DISTINCT FROM 'true' THEN
  RAISE EXCEPTION 'admin_mfa_staff_self_access_missing';END IF;
 BEGIN
  PERFORM private.record_mfa_projection('__OWNER_VERIFIED_FACTOR__'::uuid);
  RAISE EXCEPTION 'admin_mfa_retired_projector_allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END;$staff$;
ROLLBACK;
SELECT 'synthetic_admin_mfa_authority_pass';
