PRAGMA foreign_keys = ON;
CREATE TABLE admin_principal_links (
 admin_user_id TEXT PRIMARY KEY REFERENCES admin_users(id), user_id TEXT NOT NULL UNIQUE REFERENCES users(id),
 approved_by TEXT NOT NULL, approved_at TEXT NOT NULL
) STRICT;
CREATE TRIGGER admin_principal_link_immutable BEFORE UPDATE ON admin_principal_links
 BEGIN SELECT RAISE(ABORT,'explicit_principal_link_required'); END;
CREATE TABLE admin_account_role_capabilities (
 role TEXT NOT NULL CHECK(role IN ('owner','admin','staff')), permission TEXT NOT NULL,
 PRIMARY KEY(role,permission)
) STRICT;
INSERT INTO admin_account_role_capabilities(role,permission) VALUES
 ('staff','overview.read'),('staff','account.manage'),('staff','collections.read'),('staff','users.read'),
 ('staff','receivers.read'),('staff','payments.read'),('staff','ledger.read'),('staff','collections.create'),
 ('staff','reconciliations.read'),('staff','reconciliations.propose'),('staff','auth.mfa.enroll'),
 ('admin','overview.read'),('admin','account.manage'),('admin','collections.read'),('admin','users.read'),
 ('admin','receivers.read'),('admin','payments.read'),('admin','ledger.read'),('admin','collections.create'),
 ('admin','collections.manage'),('admin','users.manage'),('admin','receivers.manage'),('admin','payments.manage'),
 ('admin','payments.write'),('admin','payments.evidence.read'),('admin','payments.reconcile'),
 ('admin','reconciliations.read'),('admin','reconciliations.propose'),('admin','reconciliations.review'),
 ('admin','ledger.manage'),('admin','admin_users.read'),('admin','auth.mfa.enroll'),
 ('owner','overview.read'),('owner','account.manage'),('owner','collections.read'),('owner','users.read'),
 ('owner','receivers.read'),('owner','payments.read'),('owner','ledger.read'),('owner','collections.create'),
 ('owner','collections.manage'),('owner','users.manage'),('owner','receivers.manage'),('owner','payments.manage'),
 ('owner','payments.write'),('owner','payments.evidence.read'),('owner','payments.reconcile'),
 ('owner','reconciliations.read'),('owner','reconciliations.propose'),('owner','reconciliations.review'),
 ('owner','ledger.manage'),('owner','admin_users.read'),('owner','admin_users.manage'),('owner','auth.mfa.enroll'),
 ('owner','privacy.review'),('owner','roster.import'),('owner','audit.read'),('owner','system_health.read');
CREATE TRIGGER admin_role_capabilities_no_update BEFORE UPDATE ON admin_account_role_capabilities
 BEGIN SELECT RAISE(ABORT,'approved_role_capabilities_immutable'); END;
CREATE TRIGGER admin_role_capabilities_no_delete BEFORE DELETE ON admin_account_role_capabilities
 BEGIN SELECT RAISE(ABORT,'approved_role_capabilities_immutable'); END;
-- Links are explicit IDs, never a join on an email address or phone number.
CREATE TRIGGER admin_link_grants AFTER INSERT ON admin_principal_links BEGIN
 INSERT OR IGNORE INTO admin_grants(user_id,permission,granted_by,granted_at)
 SELECT NEW.user_id,c.permission,'admin-account:'||u.id,strftime('%Y-%m-%dT%H:%M:%fZ','now')
 FROM admin_users u JOIN admin_account_role_capabilities c ON c.role=u.role WHERE u.id=NEW.admin_user_id AND u.status='active';
 INSERT OR IGNORE INTO admin_role_assignments(user_id,role,granted_by,granted_at)
 SELECT NEW.user_id,(CASE WHEN u.role='owner' THEN 'platform_owner' ELSE 'operator' END),
 'admin-account:'||u.id,strftime('%Y-%m-%dT%H:%M:%fZ','now') FROM admin_users u WHERE u.id=NEW.admin_user_id AND u.status='active';
END;
CREATE TRIGGER admin_account_authority_changed AFTER UPDATE OF status,role,auth_version ON admin_users
 WHEN NEW.status!=OLD.status OR NEW.role!=OLD.role OR NEW.auth_version!=OLD.auth_version BEGIN
 UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='admin_account_changed'
 WHERE user_id=(SELECT user_id FROM admin_principal_links WHERE admin_user_id=NEW.id) AND surface='admin' AND revoked_at IS NULL;
 DELETE FROM admin_sessions WHERE user_id=NEW.id;
 DELETE FROM admin_grants WHERE user_id=(SELECT user_id FROM admin_principal_links WHERE admin_user_id=NEW.id) AND granted_by='admin-account:'||NEW.id;
 DELETE FROM admin_role_assignments WHERE user_id=(SELECT user_id FROM admin_principal_links WHERE admin_user_id=NEW.id) AND granted_by='admin-account:'||NEW.id;
 INSERT OR IGNORE INTO admin_grants(user_id,permission,granted_by,granted_at)
 SELECT l.user_id,c.permission,'admin-account:'||NEW.id,strftime('%Y-%m-%dT%H:%M:%fZ','now')
 FROM admin_principal_links l JOIN admin_account_role_capabilities c ON c.role=NEW.role WHERE l.admin_user_id=NEW.id AND NEW.status='active';
 INSERT OR IGNORE INTO admin_role_assignments(user_id,role,granted_by,granted_at)
 SELECT l.user_id,(CASE WHEN NEW.role='owner' THEN 'platform_owner' ELSE 'operator' END),'admin-account:'||NEW.id,strftime('%Y-%m-%dT%H:%M:%fZ','now')
 FROM admin_principal_links l WHERE l.admin_user_id=NEW.id AND NEW.status='active';
END;
CREATE TRIGGER admin_principal_link_revoked BEFORE DELETE ON admin_principal_links BEGIN
 UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='admin_principal_unlinked' WHERE user_id=OLD.user_id AND surface='admin' AND revoked_at IS NULL;
 DELETE FROM admin_sessions WHERE user_id=OLD.admin_user_id;
 DELETE FROM admin_grants WHERE user_id=OLD.user_id AND granted_by='admin-account:'||OLD.admin_user_id;
 DELETE FROM admin_role_assignments WHERE user_id=OLD.user_id AND granted_by='admin-account:'||OLD.admin_user_id;
END;
CREATE TRIGGER admin_cookie_session_bound BEFORE INSERT ON admin_sessions BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM admin_users a JOIN admin_principal_links l ON l.admin_user_id=a.id
 JOIN users u ON u.id=l.user_id JOIN auth_sessions s ON s.user_id=u.id
 WHERE a.id=NEW.user_id AND a.status='active' AND a.auth_version=NEW.auth_version AND u.access_status='active'
 AND s.id=NEW.auth_session_id AND s.surface='admin' AND s.auth_at=NEW.created_at AND s.revoked_at IS NULL
 AND s.expires_at=NEW.expires_at AND NEW.issued_assurance_level=1)
 THEN RAISE(ABORT,'admin_session_link_required') END);
END;
CREATE TRIGGER admin_cookie_mfa_bound BEFORE UPDATE OF issued_assurance_level,issued_mfa_at,issued_mfa_factor_id ON admin_sessions
 WHEN NEW.issued_assurance_level=2 BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM auth_sessions s JOIN auth_mfa_factors f ON f.id=s.mfa_factor_id
 WHERE s.id=NEW.auth_session_id AND s.assurance_level=2 AND s.mfa_at=NEW.issued_mfa_at AND s.mfa_factor_id=NEW.issued_mfa_factor_id
 AND s.revoked_at IS NULL AND s.expires_at>unixepoch() AND f.status='verified') THEN RAISE(ABORT,'real_mfa_required') END);
END;
CREATE TRIGGER admin_cookie_session_revoked AFTER DELETE ON admin_sessions BEGIN
 UPDATE auth_sessions SET revoked_at=unixepoch(),revocation_reason='admin_cookie_session_ended' WHERE id=OLD.auth_session_id AND revoked_at IS NULL;
END;
CREATE TABLE admin_account_guards(id TEXT PRIMARY KEY,passed INTEGER NOT NULL CONSTRAINT admin_account_authority CHECK(passed=1)) STRICT;
CREATE TABLE admin_bridge_guards(id TEXT PRIMARY KEY,passed INTEGER NOT NULL CONSTRAINT admin_bridge_state CHECK(passed=1)) STRICT;
CREATE TABLE admin_bridge_requests (
 admin_user_id TEXT NOT NULL REFERENCES admin_users(id), idempotency_key TEXT NOT NULL,
 request_id TEXT NOT NULL UNIQUE, session_id TEXT NOT NULL REFERENCES auth_sessions(id), operation TEXT NOT NULL,
 body_sha256 TEXT NOT NULL, created_at TEXT NOT NULL, PRIMARY KEY(admin_user_id,idempotency_key)
) STRICT;
CREATE TRIGGER admin_bridge_request_no_update BEFORE UPDATE ON admin_bridge_requests BEGIN SELECT RAISE(ABORT,'immutable_admin_bridge_request'); END;
CREATE TRIGGER admin_bridge_request_no_delete BEFORE DELETE ON admin_bridge_requests BEGIN SELECT RAISE(ABORT,'retain_admin_bridge_request'); END;
CREATE TABLE admin_bridge_reconciliation_snapshots (
 reconciliation_id TEXT PRIMARY KEY REFERENCES reconciliations(id),
 collection_id TEXT NOT NULL REFERENCES collections(id), collection_revision INTEGER NOT NULL,
 member_id TEXT NOT NULL REFERENCES users(id), member_revision INTEGER NOT NULL,
 membership_id TEXT NOT NULL REFERENCES memberships(id), membership_revision INTEGER NOT NULL,
 payment_identity_json TEXT NOT NULL CHECK(json_valid(payment_identity_json)),
 receiver_number TEXT,receiver_network TEXT,receiver_label TEXT, created_at TEXT NOT NULL
) STRICT;
CREATE TRIGGER admin_bridge_reconciliation_snapshot_no_update BEFORE UPDATE ON admin_bridge_reconciliation_snapshots
 BEGIN SELECT RAISE(ABORT,'immutable_reconciliation_snapshot'); END;
CREATE TRIGGER admin_bridge_reconciliation_snapshot_no_delete BEFORE DELETE ON admin_bridge_reconciliation_snapshots
 BEGIN SELECT RAISE(ABORT,'retain_reconciliation_snapshot'); END;
CREATE TABLE admin_owner_bootstrap_claims (
 operation_id TEXT PRIMARY KEY,admin_user_id TEXT NOT NULL UNIQUE,principal_user_id TEXT NOT NULL UNIQUE,
 password_hash TEXT NOT NULL,display_name TEXT NOT NULL,approval_reference TEXT NOT NULL,
 created_at TEXT NOT NULL,created_seconds INTEGER NOT NULL
) STRICT;
CREATE TRIGGER admin_owner_bootstrap_admission BEFORE INSERT ON admin_owner_bootstrap_claims BEGIN
 SELECT (CASE WHEN EXISTS(SELECT 1 FROM admin_users WHERE role='owner') OR length(NEW.approval_reference)<8
  OR NEW.password_hash NOT GLOB 'pbkdf2-sha256$600000$*' OR EXISTS(SELECT 1 FROM users WHERE id=NEW.principal_user_id)
  THEN RAISE(ABORT,'explicit_fresh_owner_bootstrap_required') END);
END;
CREATE TRIGGER admin_owner_bootstrap_apply AFTER INSERT ON admin_owner_bootstrap_claims BEGIN
 INSERT INTO users(id,public_id,full_name,member_type,created_at,updated_at)
 VALUES(NEW.principal_user_id,(SELECT printf('%06d',min(candidate)) FROM
 (SELECT 0 AS candidate UNION ALL SELECT CAST(public_id AS INTEGER)+1 FROM users WHERE public_id!='999999') c
 WHERE candidate<1000000 AND NOT EXISTS(SELECT 1 FROM users WHERE public_id=printf('%06d',candidate))),
 NEW.display_name,'operator',NEW.created_at,NEW.created_at);
 INSERT INTO admin_users(id,email,role,status,password_hash,display_name,created_at,accepted_at,updated_at)
 VALUES(NEW.admin_user_id,'info@ikanisa.com','owner','active',NEW.password_hash,NEW.display_name,NEW.created_seconds,NEW.created_seconds,NEW.created_seconds);
 INSERT INTO admin_principal_links(admin_user_id,user_id,approved_by,approved_at)
 VALUES(NEW.admin_user_id,NEW.principal_user_id,NEW.approval_reference,NEW.created_at);
 INSERT INTO admin_account_audit(id,actor_id,subject_id,action,occurred_at)
 VALUES(NEW.operation_id,NEW.admin_user_id,NEW.admin_user_id,'explicit_owner_bootstrapped',NEW.created_seconds);
END;
CREATE TRIGGER admin_owner_bootstrap_no_update BEFORE UPDATE ON admin_owner_bootstrap_claims
 BEGIN SELECT RAISE(ABORT,'immutable_owner_bootstrap'); END;
CREATE TRIGGER admin_owner_bootstrap_no_delete BEFORE DELETE ON admin_owner_bootstrap_claims
 BEGIN SELECT RAISE(ABORT,'retain_owner_bootstrap'); END;
ALTER TABLE users ADD COLUMN member_type TEXT NOT NULL DEFAULT 'app' CHECK(member_type IN ('app','direct','operator'));
ALTER TABLE users ADD COLUMN revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>=1);
ALTER TABLE memberships ADD COLUMN revision INTEGER NOT NULL DEFAULT 1 CHECK(revision>=1);
CREATE TRIGGER user_revision_monotonic AFTER UPDATE OF phone,email,full_name,momo_number,momo_pay_code,momo_provider,access_status ON users
 WHEN NEW.revision=OLD.revision BEGIN UPDATE users SET revision=revision+1 WHERE id=NEW.id; END;
CREATE TRIGGER membership_revision_monotonic AFTER UPDATE OF role,active ON memberships
 WHEN NEW.revision=OLD.revision BEGIN UPDATE memberships SET revision=revision+1 WHERE id=NEW.id; END;
