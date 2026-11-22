CREATE TABLE mutation_guards (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL, session_id TEXT NOT NULL, now_seconds INTEGER NOT NULL,
 collection_id TEXT, required_group_role TEXT, permission TEXT, fresh_seconds INTEGER,
 expected_collection_revision INTEGER, payment_id TEXT, expected_payment_revision INTEGER,
 minimum_assurance INTEGER, expected_mfa_at INTEGER, expected_preference_revision INTEGER, invite_collection_id TEXT,expected_share_hash TEXT,expected_share_version INTEGER,recipient_user_id TEXT,recipient_collection_id TEXT
);
CREATE TRIGGER mutation_authority BEFORE INSERT ON mutation_guards BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN users u ON u.id=s.user_id WHERE s.id=NEW.session_id AND s.user_id=NEW.user_id AND s.revoked_at IS NULL AND s.expires_at>NEW.now_seconds AND u.access_status='active') THEN RAISE(ABORT,'session_changed') END);
 SELECT (CASE WHEN NEW.fresh_seconds IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth_sessions s WHERE s.id=NEW.session_id AND (CASE WHEN s.assurance_level=2 THEN s.mfa_at ELSE s.auth_at END)>=NEW.now_seconds-NEW.fresh_seconds) THEN RAISE(ABORT,'fresh_auth_required') END);
 SELECT (CASE WHEN NEW.minimum_assurance IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN auth_mfa_factors f ON f.id=s.mfa_factor_id AND f.status='verified' WHERE s.id=NEW.session_id AND s.assurance_level>=NEW.minimum_assurance AND s.mfa_at=NEW.expected_mfa_at AND s.mfa_at>=NEW.now_seconds-300 AND s.mfa_factor_id IS NOT NULL) THEN RAISE(ABORT,'mfa_required') END);
 SELECT (CASE WHEN NEW.permission IS NOT NULL AND NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN admin_grants g ON g.user_id=s.user_id WHERE s.id=NEW.session_id AND s.surface='admin' AND g.permission=NEW.permission) THEN RAISE(ABORT,'permission_denied') END);
 SELECT (CASE WHEN NEW.collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM memberships m JOIN collections c ON c.id=m.collection_id WHERE m.collection_id=NEW.collection_id AND m.user_id=NEW.user_id AND m.active=1 AND c.status='active' AND (NEW.required_group_role IS NULL OR m.role=NEW.required_group_role OR (NEW.required_group_role='admin' AND m.role='owner'))) THEN RAISE(ABORT,'group_access_denied') END);
 SELECT (CASE WHEN NEW.invite_collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM collections c WHERE c.id=NEW.invite_collection_id AND c.status='active' AND c.share_code_hash=NEW.expected_share_hash AND c.share_code_version=NEW.expected_share_version) THEN RAISE(ABORT,'invitation_changed') END);
 SELECT (CASE WHEN NEW.recipient_user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM memberships m JOIN users u ON u.id=m.user_id WHERE m.user_id=NEW.recipient_user_id AND m.collection_id=NEW.recipient_collection_id AND m.active=1 AND u.access_status='active') THEN RAISE(ABORT,'recipient_changed') END);
 SELECT (CASE WHEN NEW.expected_preference_revision IS NOT NULL AND coalesce((SELECT revision FROM notification_preferences WHERE user_id=NEW.user_id),1)!=NEW.expected_preference_revision THEN RAISE(ABORT,'stale_preferences') END);
 SELECT (CASE WHEN NEW.expected_collection_revision IS NOT NULL AND NOT EXISTS(SELECT 1 FROM collections c WHERE c.id=NEW.collection_id AND c.revision=NEW.expected_collection_revision) THEN RAISE(ABORT,'stale_collection') END);
 SELECT (CASE WHEN NEW.expected_payment_revision IS NOT NULL AND NOT EXISTS(SELECT 1 FROM payments p WHERE p.id=NEW.payment_id AND p.revision=NEW.expected_payment_revision) THEN RAISE(ABORT,'stale_payment') END);
END;
