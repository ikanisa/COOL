PRAGMA foreign_keys = ON;
CREATE TABLE users (
 id TEXT PRIMARY KEY, phone TEXT UNIQUE, email TEXT UNIQUE, full_name TEXT NOT NULL DEFAULT '',
 public_id TEXT NOT NULL UNIQUE, country_code TEXT NOT NULL DEFAULT 'RW',
 currency_code TEXT NOT NULL DEFAULT 'RWF', momo_provider TEXT NOT NULL DEFAULT '',
 momo_number TEXT NOT NULL DEFAULT '', momo_pay_code TEXT NOT NULL DEFAULT '',
 access_status TEXT NOT NULL DEFAULT 'active' CHECK(access_status IN ('active','suspended','deleted')),
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE admin_grants (
 user_id TEXT NOT NULL REFERENCES users(id), permission TEXT NOT NULL,
 granted_by TEXT, granted_at TEXT NOT NULL, PRIMARY KEY(user_id,permission)
) STRICT;
CREATE TABLE admin_role_assignments (user_id TEXT NOT NULL REFERENCES users(id),role TEXT NOT NULL CHECK(role IN ('platform_owner','operator','reviewer','auditor')),granted_by TEXT,granted_at TEXT NOT NULL,PRIMARY KEY(user_id,role)) STRICT;
CREATE TABLE collections (
 id TEXT PRIMARY KEY, slug TEXT NOT NULL UNIQUE, creator_user_id TEXT NOT NULL REFERENCES users(id),
 title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', collection_type TEXT NOT NULL,
 country_code TEXT NOT NULL DEFAULT 'RW' CHECK(country_code='RW'), currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'),
 status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','archived','suspended')),
 visibility_status TEXT NOT NULL DEFAULT 'private' CHECK(visibility_status IN ('private','public_pending','public_approved')),
 is_platform_sponsored INTEGER NOT NULL DEFAULT 0 CHECK(is_platform_sponsored IN (0,1)),
 receiver_momo_number TEXT, receiver_network TEXT, receiver_display_label TEXT,
 share_code_hash TEXT UNIQUE, share_code_ciphertext TEXT, share_code_version INTEGER NOT NULL DEFAULT 1,
 revision INTEGER NOT NULL DEFAULT 1, data_json TEXT NOT NULL DEFAULT '{}' CHECK(json_valid(data_json)),
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE memberships (
 id TEXT PRIMARY KEY, collection_id TEXT NOT NULL REFERENCES collections(id), user_id TEXT NOT NULL REFERENCES users(id),
 role TEXT NOT NULL DEFAULT 'member' CHECK(role IN ('owner','admin','member')),
 active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)), joined_at TEXT NOT NULL,
 UNIQUE(collection_id,user_id)
) STRICT;
CREATE INDEX membership_actor ON memberships(user_id,active,collection_id);
CREATE UNIQUE INDEX one_active_owner ON memberships(collection_id) WHERE active=1 AND role='owner';
CREATE TABLE payment_intents (
 id TEXT PRIMARY KEY, collection_id TEXT NOT NULL REFERENCES collections(id), member_id TEXT NOT NULL REFERENCES users(id),
 amount_minor INTEGER NOT NULL CHECK(amount_minor>0 AND amount_minor<=9007199254740991),
 currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'), rail TEXT NOT NULL DEFAULT 'rwanda_momo' CHECK(rail='rwanda_momo'),
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','expired','cancelled','matched','ambiguous')),
 receiver_momo_number TEXT NOT NULL, receiver_network TEXT NOT NULL, receiver_label TEXT NOT NULL DEFAULT '',
 originating_session_id TEXT NOT NULL, created_at TEXT NOT NULL, expires_at TEXT NOT NULL,
 request_id TEXT NOT NULL, request_sha256 TEXT NOT NULL, UNIQUE(member_id,request_id)
) STRICT;
CREATE INDEX intent_actor ON payment_intents(member_id,created_at,id);
CREATE TABLE payment_evidence (
 id TEXT PRIMARY KEY, collection_id TEXT REFERENCES collections(id), owner_user_id TEXT NOT NULL REFERENCES users(id),
 object_key TEXT NOT NULL UNIQUE, object_sha256 TEXT NOT NULL CHECK(length(object_sha256)=64),
 size_bytes INTEGER NOT NULL CHECK(size_bytes>0), content_type TEXT NOT NULL,
 authenticity TEXT NOT NULL CHECK(authenticity IN ('operator_recorded','provider_authenticated')),
 external_reference TEXT, receiver_momo_number TEXT, amount_minor INTEGER CHECK(amount_minor IS NULL OR (amount_minor>0 AND amount_minor<=9007199254740991)),
 currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'), observed_at TEXT NOT NULL, created_at TEXT NOT NULL,
 retained_until TEXT, legal_hold INTEGER NOT NULL DEFAULT 0 CHECK(legal_hold IN (0,1)),
 UNIQUE(owner_user_id,external_reference)
) STRICT;
CREATE TABLE payments (
 id TEXT PRIMARY KEY, collection_id TEXT NOT NULL REFERENCES collections(id), member_id TEXT REFERENCES users(id),
 evidence_id TEXT NOT NULL REFERENCES payment_evidence(id), intent_id TEXT REFERENCES payment_intents(id),
 amount_minor INTEGER NOT NULL CHECK(amount_minor>0 AND amount_minor<=9007199254740991),
 currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'), rail TEXT NOT NULL DEFAULT 'rwanda_momo' CHECK(rail='rwanda_momo'),
 status TEXT NOT NULL CHECK(status IN ('recorded','reconciled','confirmed','corrected','reversed','ambiguous')),
 payer_display_name TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 1,
 UNIQUE(evidence_id)
) STRICT;
CREATE INDEX payment_collection ON payments(collection_id,created_at,id);
CREATE TABLE ledger_entries (
 id TEXT PRIMARY KEY, payment_id TEXT NOT NULL REFERENCES payments(id), collection_id TEXT NOT NULL REFERENCES collections(id),
 member_id TEXT REFERENCES users(id), currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'),
 amount_minor INTEGER NOT NULL CHECK(amount_minor!=0 AND abs(amount_minor)<=9007199254740991),
 kind TEXT NOT NULL CHECK(kind IN ('contribution','reversal','correction')),
 reverses_entry_id TEXT UNIQUE REFERENCES ledger_entries(id), evidence_id TEXT NOT NULL REFERENCES payment_evidence(id),
 actor_user_id TEXT NOT NULL REFERENCES users(id), request_id TEXT NOT NULL UNIQUE, posted_at TEXT NOT NULL,
 CHECK((kind='contribution' AND amount_minor>0 AND reverses_entry_id IS NULL) OR (kind!='contribution' AND reverses_entry_id IS NOT NULL))
) STRICT;
CREATE INDEX ledger_actor_history ON ledger_entries(member_id,posted_at,id);
CREATE UNIQUE INDEX one_contribution_per_payment ON ledger_entries(payment_id) WHERE kind='contribution';
CREATE TABLE reconciliations (
 id TEXT PRIMARY KEY, payment_id TEXT NOT NULL REFERENCES payments(id), proposed_member_id TEXT NOT NULL REFERENCES users(id),
 proposed_by TEXT NOT NULL REFERENCES users(id), proposed_session_id TEXT NOT NULL,
 expected_payment_revision INTEGER NOT NULL, status TEXT NOT NULL CHECK(status IN ('proposed','approved','rejected','cancelled')),
 evidence_id TEXT NOT NULL REFERENCES payment_evidence(id), approved_by TEXT REFERENCES users(id),
 request_id TEXT NOT NULL UNIQUE, request_sha256 TEXT NOT NULL, created_at TEXT NOT NULL, approved_at TEXT
) STRICT;
CREATE TABLE notification_preferences (
 user_id TEXT PRIMARY KEY REFERENCES users(id), push_enabled INTEGER NOT NULL DEFAULT 1, payment_updates INTEGER NOT NULL DEFAULT 1,
 group_updates INTEGER NOT NULL DEFAULT 1, revision INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE notification_devices (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), token_hash TEXT NOT NULL UNIQUE,
 owner_session_id TEXT NOT NULL, provider TEXT NOT NULL, token_ciphertext TEXT NOT NULL, platform TEXT NOT NULL CHECK(platform IN ('android','ios','web')),
 active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE notification_events (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), event_type TEXT NOT NULL, title TEXT NOT NULL,
 body TEXT NOT NULL, data_json TEXT NOT NULL DEFAULT '{}' CHECK(json_valid(data_json)),
 status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','sent','failed','read')),
 created_at TEXT NOT NULL, read_at TEXT
) STRICT;
CREATE INDEX notification_owner ON notification_events(user_id,created_at,id);
CREATE TABLE support_requests (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), collection_id TEXT REFERENCES collections(id),
 kind TEXT NOT NULL, message TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'received', created_at TEXT NOT NULL
) STRICT;
CREATE TABLE runtime_config (
 key TEXT PRIMARY KEY, value_json TEXT NOT NULL CHECK(json_valid(value_json)), revision INTEGER NOT NULL DEFAULT 1,
 updated_by TEXT REFERENCES users(id), updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE audit_log (
 id INTEGER PRIMARY KEY AUTOINCREMENT, actor_user_id TEXT REFERENCES users(id), actor_session_id TEXT,
 action TEXT NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT, request_id TEXT,
 details_json TEXT NOT NULL CHECK(json_valid(details_json)), created_at TEXT NOT NULL
) STRICT;
CREATE INDEX audit_entity ON audit_log(entity_type,entity_id,id);
CREATE TABLE request_receipts (
 user_id TEXT NOT NULL REFERENCES users(id), request_id TEXT NOT NULL, operation TEXT NOT NULL,
 session_id TEXT NOT NULL, body_sha256 TEXT NOT NULL CHECK(length(body_sha256)=64), response_json TEXT NOT NULL CHECK(json_valid(response_json)),
 created_at TEXT NOT NULL, PRIMARY KEY(user_id,request_id)
) STRICT;
CREATE TABLE deletion_requests (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), submission_id TEXT NOT NULL,
 reason TEXT, status TEXT NOT NULL DEFAULT 'received' CHECK(status IN ('received','under_review','scheduled','erasing','completed','rejected','on_hold','failed')),
 revision INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
 UNIQUE(user_id,submission_id)
) STRICT;
CREATE UNIQUE INDEX one_active_deletion ON deletion_requests(user_id) WHERE status IN ('received','under_review','scheduled','erasing','on_hold','failed');
CREATE TABLE deletion_reviews (
 id TEXT PRIMARY KEY, request_id TEXT NOT NULL REFERENCES deletion_requests(id), actor_user_id TEXT NOT NULL REFERENCES users(id),
 expected_revision INTEGER NOT NULL, outcome TEXT NOT NULL, details_json TEXT NOT NULL CHECK(json_valid(details_json)),
 created_at TEXT NOT NULL
) STRICT;
CREATE TABLE privacy_holds (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), category TEXT NOT NULL, reason_code TEXT NOT NULL,
 active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, released_at TEXT
) STRICT;
CREATE TABLE upload_objects (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), collection_id TEXT REFERENCES collections(id),
 object_key TEXT NOT NULL UNIQUE, sha256 TEXT NOT NULL, size_bytes INTEGER NOT NULL, content_type TEXT NOT NULL,
 purpose TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'retained', created_at TEXT NOT NULL, deleted_at TEXT
) STRICT;
CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_log BEGIN SELECT RAISE(ABORT,'immutable_audit'); END;
CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_log BEGIN SELECT RAISE(ABORT,'immutable_audit'); END;
CREATE TRIGGER ledger_no_update BEFORE UPDATE ON ledger_entries BEGIN SELECT RAISE(ABORT,'immutable_ledger'); END;
CREATE TRIGGER ledger_no_delete BEFORE DELETE ON ledger_entries BEGIN SELECT RAISE(ABORT,'immutable_ledger'); END;
CREATE TRIGGER evidence_no_rewrite BEFORE UPDATE OF object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,receiver_momo_number,amount_minor,currency,observed_at ON payment_evidence BEGIN SELECT RAISE(ABORT,'immutable_evidence'); END;
CREATE TRIGGER evidence_no_delete BEFORE DELETE ON payment_evidence BEGIN SELECT RAISE(ABORT,'retain_financial_evidence'); END;
CREATE TRIGGER reversal_matches BEFORE INSERT ON ledger_entries WHEN NEW.reverses_entry_id IS NOT NULL BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM ledger_entries e WHERE e.id=NEW.reverses_entry_id AND e.payment_id=NEW.payment_id AND e.collection_id=NEW.collection_id AND e.member_id IS NEW.member_id AND e.currency=NEW.currency AND e.amount_minor=-NEW.amount_minor AND e.evidence_id=NEW.evidence_id AND e.kind='contribution') THEN RAISE(ABORT,'invalid_reversal') END);
END;
CREATE TRIGGER receipt_no_update BEFORE UPDATE ON request_receipts BEGIN SELECT RAISE(ABORT,'immutable_receipt'); END;
CREATE TRIGGER receipt_no_delete BEFORE DELETE ON request_receipts BEGIN SELECT RAISE(ABORT,'retain_request_receipt'); END;
