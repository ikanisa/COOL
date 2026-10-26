-- Scoped incoming gateway credentials and links to the existing financial owner.
INSERT INTO admin_account_role_capabilities(role,permission) VALUES
 ('owner','sms.reveal'),('owner','sms.extract'),('admin','sms.reveal'),('admin','sms.extract');
INSERT OR IGNORE INTO admin_grants(user_id,permission,granted_by,granted_at)
 SELECT link.user_id,cap.permission,'admin-account:'||account.id,strftime('%Y-%m-%dT%H:%M:%fZ','now')
 FROM admin_users account JOIN admin_principal_links link ON link.admin_user_id=account.id
 JOIN users principal ON principal.id=link.user_id JOIN admin_account_role_capabilities cap ON cap.role=account.role
 WHERE account.status='active' AND account.role IN('owner','admin') AND principal.access_status='active'
 AND cap.permission IN('sms.reveal','sms.extract');
CREATE TABLE momo_gateway_pairings (
 id TEXT PRIMARY KEY, binding_id TEXT NOT NULL REFERENCES momo_gateway_bindings(id),
 code_sha256 TEXT NOT NULL UNIQUE, originating_session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 expires_at INTEGER NOT NULL, claimed_installation_id TEXT, created_at TEXT NOT NULL
) STRICT;
CREATE TABLE momo_gateway_credentials (
 id TEXT PRIMARY KEY, binding_id TEXT NOT NULL UNIQUE REFERENCES momo_gateway_bindings(id),
 pairing_id TEXT NOT NULL UNIQUE REFERENCES momo_gateway_pairings(id), installation_id TEXT NOT NULL,
 token_sha256 TEXT NOT NULL UNIQUE, token_ciphertext TEXT NOT NULL,
 last_contact_at TEXT, last_sms_at TEXT, pending_count INTEGER NOT NULL DEFAULT 0 CHECK(pending_count>=0),
 oldest_pending_at TEXT, revoked_at TEXT, created_at TEXT NOT NULL
) STRICT;
CREATE TABLE momo_gateway_captures (
 raw_sms_id TEXT PRIMARY KEY REFERENCES sms_receipts(id), credential_id TEXT NOT NULL REFERENCES momo_gateway_credentials(id),
 identity_sha256 TEXT NOT NULL, service_centre_at TEXT, captured_at TEXT NOT NULL, inbox_received_at TEXT,
 subscription_id INTEGER, completeness TEXT NOT NULL CHECK(completeness IN('complete','incomplete','inconsistent')),
 source_mode TEXT NOT NULL CHECK(source_mode IN('live','catch_up')), created_at TEXT NOT NULL
) STRICT;
CREATE TRIGGER momo_gateway_capture_immutable BEFORE UPDATE ON momo_gateway_captures BEGIN SELECT RAISE(ABORT,'immutable_gateway_capture'); END;
CREATE TRIGGER momo_gateway_capture_retain BEFORE DELETE ON momo_gateway_captures BEGIN SELECT RAISE(ABORT,'retain_gateway_capture'); END;
CREATE TABLE momo_source_resolutions (
 id TEXT PRIMARY KEY,raw_sms_id TEXT NOT NULL UNIQUE REFERENCES sms_receipts(id),
 receiving_account_id TEXT NOT NULL REFERENCES momo_receiving_accounts(id),source_body_sha256 TEXT NOT NULL,
 reviewed_by TEXT NOT NULL REFERENCES users(id),evidence_reference TEXT NOT NULL,reason TEXT NOT NULL,created_at TEXT NOT NULL
) STRICT;
CREATE TRIGGER momo_source_resolution_immutable BEFORE UPDATE ON momo_source_resolutions BEGIN SELECT RAISE(ABORT,'immutable_source_resolution'); END;
CREATE TRIGGER momo_source_resolution_retain BEFORE DELETE ON momo_source_resolutions BEGIN SELECT RAISE(ABORT,'retain_source_resolution'); END;
DROP TRIGGER momo_job_source_identity;
CREATE TRIGGER momo_job_source_identity BEFORE UPDATE OF raw_sms_id,binding_id,binding_version,receiving_account_id,mode,created_at ON momo_processing_jobs
WHEN NOT(OLD.state='source_unresolved' AND OLD.binding_id IS NULL AND OLD.receiving_account_id IS NULL AND
 NEW.raw_sms_id=OLD.raw_sms_id AND NEW.binding_id IS NULL AND NEW.binding_version IS NULL AND NEW.mode='historical' AND NEW.created_at=OLD.created_at AND
 EXISTS(SELECT 1 FROM momo_source_resolutions r JOIN sms_receipts s ON s.id=r.raw_sms_id JOIN momo_receiving_accounts a ON a.id=r.receiving_account_id
 WHERE r.raw_sms_id=NEW.raw_sms_id AND r.receiving_account_id=NEW.receiving_account_id AND r.source_body_sha256=s.body_sha256 AND a.receiver_hash=s.receiver_hash))
BEGIN SELECT RAISE(ABORT,'immutable_momo_source'); END;
CREATE TABLE momo_financial_links (
 transaction_id TEXT PRIMARY KEY REFERENCES momo_transactions(id), payment_id TEXT NOT NULL UNIQUE REFERENCES payments(id),
 beneficiary_member_id TEXT NOT NULL REFERENCES users(id), linked_by TEXT NOT NULL REFERENCES users(id),
 reason TEXT NOT NULL, historical_existing INTEGER NOT NULL DEFAULT 0 CHECK(historical_existing IN(0,1)), created_at TEXT NOT NULL
) STRICT;
CREATE TRIGGER momo_financial_link_immutable BEFORE UPDATE ON momo_financial_links BEGIN SELECT RAISE(ABORT,'immutable_momo_financial_link'); END;
CREATE TRIGGER momo_financial_link_retain BEFORE DELETE ON momo_financial_links BEGIN SELECT RAISE(ABORT,'retain_momo_financial_link'); END;
CREATE UNIQUE INDEX one_payment_per_intent ON payments(intent_id) WHERE intent_id IS NOT NULL;
CREATE TABLE contribution_posting_snapshots (
 ledger_entry_id TEXT PRIMARY KEY REFERENCES ledger_entries(id), payment_id TEXT NOT NULL UNIQUE REFERENCES payments(id),
 member_balance_after_minor INTEGER NOT NULL CHECK(member_balance_after_minor>=0 AND member_balance_after_minor<=9007199254740991),
 group_balance_after_minor INTEGER NOT NULL CHECK(group_balance_after_minor>=0 AND group_balance_after_minor<=9007199254740991),
 posted_at TEXT NOT NULL
) STRICT;
CREATE TRIGGER contribution_snapshot_immutable BEFORE UPDATE ON contribution_posting_snapshots BEGIN SELECT RAISE(ABORT,'immutable_contribution_snapshot'); END;
CREATE TRIGGER contribution_snapshot_retain BEFORE DELETE ON contribution_posting_snapshots BEGIN SELECT RAISE(ABORT,'retain_contribution_snapshot'); END;
