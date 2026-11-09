-- v0.12.0 upgrade for an environment that already applied the older proposal.
-- NOT APPLIED. Reconcile and generate the normal Collect migration before use.
-- Do not backfill an old native session from today's account mapping: that
-- would manufacture historical authority. Revoke it and require a new sign-in.
BEGIN;
ALTER TABLE private.burimunsi_sessions
  ADD COLUMN IF NOT EXISTS principal_user_id text REFERENCES app.users(id);
UPDATE private.burimunsi_sessions SET revoked=true WHERE principal_user_id IS NULL;
ALTER TABLE private.burimunsi_sessions
  ADD CONSTRAINT burimunsi_session_principal_snapshot CHECK(revoked OR principal_user_id IS NOT NULL);
-- An issued session's identity cannot be rewritten; only revocation is mutable.
CREATE FUNCTION private.burimunsi_session_identity_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $body$
BEGIN
 IF (NEW.id,NEW.collection_id,NEW.account_id,NEW.grant_id,NEW.installation_id,
     NEW.principal_user_id,NEW.token_hash,NEW.credential_version,NEW.grant_version,
     NEW.created_at,NEW.expires_at) IS DISTINCT FROM
    (OLD.id,OLD.collection_id,OLD.account_id,OLD.grant_id,OLD.installation_id,
     OLD.principal_user_id,OLD.token_hash,OLD.credential_version,OLD.grant_version,
     OLD.created_at,OLD.expires_at) OR (OLD.revoked AND NOT NEW.revoked) THEN
  RAISE EXCEPTION 'burimunsi_session_identity_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION private.burimunsi_session_identity_immutable() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER burimunsi_session_identity_immutable BEFORE UPDATE ON private.burimunsi_sessions
FOR EACH ROW EXECUTE FUNCTION private.burimunsi_session_identity_immutable();
-- Replacing an operator requires an explicit lifecycle operation, not rebinding
-- another person's native account to a different canonical principal or group.
CREATE FUNCTION private.burimunsi_account_principal_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $body$
BEGIN
 IF (NEW.id,NEW.collection_id,NEW.principal_user_id) IS DISTINCT FROM
    (OLD.id,OLD.collection_id,OLD.principal_user_id) THEN
  RAISE EXCEPTION 'burimunsi_account_principal_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION private.burimunsi_account_principal_immutable() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER burimunsi_account_principal_immutable BEFORE UPDATE ON private.burimunsi_accounts
FOR EACH ROW EXECUTE FUNCTION private.burimunsi_account_principal_immutable();
COMMIT;
