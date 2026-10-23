-- Fresh email-only member identity and workflow data. No legacy import.
PRAGMA foreign_keys=ON;

-- This is a fresh-backend migration, not a populated-database conversion.
-- D1 cannot rebuild the payee parent while existing transaction RESTRICT foreign
-- keys reference it. Stop before any change if an operator has already created
-- a payee; a separate preservation migration is required in that case.
CREATE TABLE member_migration_fresh_guard (
  payees INTEGER NOT NULL CONSTRAINT member_migration_requires_empty_payees CHECK(payees=0)
) STRICT;
INSERT INTO member_migration_fresh_guard(payees) SELECT count(*) FROM collect_payees;
DROP TABLE member_migration_fresh_guard;

-- Admit separately identified member creators without inventing an admin actor.
PRAGMA defer_foreign_keys=ON;
CREATE TABLE collect_payees_member_upgrade (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36 AND substr(id,9,1)='-' AND substr(id,14,1)='-' AND substr(id,19,1)='-' AND substr(id,24,1)='-' AND length(replace(id,'-',''))=32 AND replace(id,'-','') NOT GLOB '*[^a-f0-9]*'),
  group_id TEXT NOT NULL REFERENCES collect_groups(id) ON DELETE RESTRICT,
  label TEXT NOT NULL CHECK(length(trim(label)) BETWEEN 2 AND 120),
  network TEXT NOT NULL CHECK(network IN ('mtn_momo','airtel_money')),
  momo_number_or_code TEXT NOT NULL CHECK(length(momo_number_or_code) BETWEEN 4 AND 12 AND momo_number_or_code NOT GLOB '*[^0-9]*'),
  rail TEXT NOT NULL DEFAULT 'rwanda_momo' CHECK(rail='rwanda_momo'),
  currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'),
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','inactive')),
  created_by_admin_id TEXT REFERENCES admin_users(id) ON DELETE RESTRICT,
  created_by_member_id TEXT REFERENCES collect_users(id) ON DELETE RESTRICT,
  version INTEGER NOT NULL DEFAULT 1 CHECK(version>=1 AND version<=9007199254740991),
  creation_reason TEXT NOT NULL CHECK(length(trim(creation_reason)) BETWEEN 8 AND 1000),
  created_at INTEGER NOT NULL CHECK(created_at>0),
  CHECK((created_by_admin_id IS NOT NULL) != (created_by_member_id IS NOT NULL)),
  UNIQUE(id,group_id,network),
  UNIQUE(id,group_id),
  UNIQUE(id,network)
) STRICT;
INSERT INTO collect_payees_member_upgrade(id,group_id,label,network,momo_number_or_code,rail,currency,status,created_by_admin_id,creation_reason,created_at,version)
SELECT id,group_id,label,network,momo_number_or_code,rail,currency,status,created_by_admin_id,creation_reason,created_at,version FROM collect_payees;
DROP TABLE collect_payees;
ALTER TABLE collect_payees_member_upgrade RENAME TO collect_payees;
CREATE UNIQUE INDEX collect_payees_active_group ON collect_payees(group_id) WHERE status='active';
CREATE TRIGGER collect_payee_route_immutable BEFORE UPDATE ON collect_payees
WHEN NEW.id IS NOT OLD.id OR NEW.group_id IS NOT OLD.group_id OR NEW.network IS NOT OLD.network
  OR NEW.momo_number_or_code IS NOT OLD.momo_number_or_code OR NEW.rail IS NOT OLD.rail OR NEW.currency IS NOT OLD.currency
  OR NEW.created_by_member_id IS NOT OLD.created_by_member_id OR NEW.created_by_admin_id IS NOT OLD.created_by_admin_id OR NEW.creation_reason IS NOT OLD.creation_reason OR NEW.created_at IS NOT OLD.created_at
BEGIN SELECT RAISE(ABORT,'MoMo payee route and creation evidence are immutable'); END;
CREATE TRIGGER collect_payee_no_delete BEFORE DELETE ON collect_payees
BEGIN SELECT RAISE(ABORT,'Deactivate the payee; do not erase its route'); END;

ALTER TABLE collect_profiles ADD COLUMN momo_provider TEXT NOT NULL DEFAULT '' CHECK(momo_provider IN ('','mtn_momo','airtel_money'));
ALTER TABLE collect_profiles ADD COLUMN momo_number TEXT NOT NULL DEFAULT '';
ALTER TABLE collect_profiles ADD COLUMN momo_pay_code TEXT NOT NULL DEFAULT '';
ALTER TABLE collect_groups ADD COLUMN image_url TEXT;
ALTER TABLE collect_groups ADD COLUMN accent_color_hex TEXT;
ALTER TABLE collect_groups ADD COLUMN share_code TEXT;
CREATE UNIQUE INDEX collect_groups_share_code ON collect_groups(share_code) WHERE share_code IS NOT NULL;
CREATE TABLE member_sessions (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES collect_users(id),token_hash TEXT NOT NULL UNIQUE,refresh_hash TEXT NOT NULL UNIQUE,
 created_at INTEGER NOT NULL,expires_at INTEGER NOT NULL,refresh_until INTEGER NOT NULL,verified_at INTEGER NOT NULL,
 CHECK(expires_at>created_at AND refresh_until>=expires_at)
) STRICT;
CREATE INDEX member_sessions_user ON member_sessions(user_id);
CREATE TABLE member_email_challenges (
 id TEXT PRIMARY KEY,email TEXT NOT NULL,code_hash TEXT NOT NULL,purpose TEXT NOT NULL CHECK(purpose IN ('login','privacy')),
 session_id TEXT,created_at INTEGER NOT NULL,expires_at INTEGER NOT NULL,attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 8),
 state TEXT NOT NULL CHECK(state IN ('pending','accepted','failed','consumed')),provider_reference TEXT,
 CHECK(expires_at>created_at)
) STRICT;
CREATE INDEX member_email_challenge_email ON member_email_challenges(email,created_at);
CREATE TABLE member_rate_limits (key_hash TEXT NOT NULL,bucket INTEGER NOT NULL,count INTEGER NOT NULL,PRIMARY KEY(key_hash,bucket)) STRICT;
CREATE TABLE member_command_guards (id TEXT PRIMARY KEY,allowed INTEGER NOT NULL CHECK(allowed=1)) STRICT;
CREATE TABLE member_requests (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES collect_users(id),scope TEXT NOT NULL,request_hash TEXT NOT NULL,
 result_json TEXT NOT NULL CHECK(json_valid(result_json)),created_at INTEGER NOT NULL,UNIQUE(user_id,scope,id)
) STRICT;
CREATE TRIGGER member_request_immutable BEFORE UPDATE ON member_requests BEGIN SELECT RAISE(ABORT,'Member request evidence is immutable'); END;
CREATE TRIGGER member_request_no_delete BEFORE DELETE ON member_requests BEGIN SELECT RAISE(ABORT,'Member request evidence is immutable'); END;
CREATE TABLE member_contribution_intents (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES collect_users(id),group_id TEXT NOT NULL REFERENCES collect_groups(id),payee_id TEXT NOT NULL REFERENCES collect_payees(id),
 amount_rwf INTEGER NOT NULL CHECK(amount_rwf BETWEEN 1 AND 9007199254740991),sender_phone_hash TEXT,
 status TEXT NOT NULL CHECK(status IN ('pending','expired','cancelled','confirmed')),created_at INTEGER NOT NULL,expires_at INTEGER NOT NULL,
 CHECK(expires_at>created_at)
) STRICT;
CREATE INDEX member_intents_user ON member_contribution_intents(user_id,created_at,id);
CREATE TABLE member_notification_preferences (
 user_id TEXT PRIMARY KEY REFERENCES collect_users(id),revision INTEGER NOT NULL DEFAULT 1,
 contribution_confirmations INTEGER NOT NULL DEFAULT 1 CHECK(contribution_confirmations IN (0,1)),
 payment_reminders INTEGER NOT NULL DEFAULT 1 CHECK(payment_reminders IN (0,1)),
 group_updates INTEGER NOT NULL DEFAULT 1 CHECK(group_updates IN (0,1)),security_notices INTEGER NOT NULL DEFAULT 1 CHECK(security_notices IN (0,1))
) STRICT;
CREATE TABLE member_notification_events (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES collect_users(id),group_id TEXT REFERENCES collect_groups(id),type TEXT NOT NULL,
 title TEXT NOT NULL,body TEXT NOT NULL,deep_link TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'queued' CHECK(status IN ('queued','accepted','read','failed','uncertain','suppressed')),
 created_at INTEGER NOT NULL,sent_at INTEGER,read_at INTEGER,provider_reference TEXT
) STRICT;
CREATE INDEX member_events_user ON member_notification_events(user_id,created_at,id);
CREATE TABLE member_sms_consent (user_id TEXT PRIMARY KEY REFERENCES collect_users(id),enabled INTEGER NOT NULL CHECK(enabled IN(0,1)),momo_number_hash TEXT,updated_at INTEGER NOT NULL) STRICT;
CREATE TABLE member_receipt_submissions (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES collect_users(id),body_hash TEXT NOT NULL,raw_sender TEXT NOT NULL,payload_object_key TEXT NOT NULL,
 received_at INTEGER NOT NULL,created_at INTEGER NOT NULL,status TEXT NOT NULL DEFAULT 'needs_review' CHECK(status IN ('needs_review','rejected','reviewed')),
 UNIQUE(user_id,id)
) STRICT;
CREATE TRIGGER member_receipt_immutable BEFORE UPDATE OF user_id,body_hash,raw_sender,payload_object_key,received_at,created_at ON member_receipt_submissions BEGIN SELECT RAISE(ABORT,'Receipt source evidence is immutable'); END;
CREATE TABLE member_support_requests (id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES collect_users(id),subject TEXT NOT NULL,message TEXT NOT NULL,created_at INTEGER NOT NULL,status TEXT NOT NULL DEFAULT 'open') STRICT;
CREATE TABLE member_privacy_requests (id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES collect_users(id),reason TEXT,created_at INTEGER NOT NULL,status TEXT NOT NULL DEFAULT 'awaiting_review') STRICT;
CREATE UNIQUE INDEX member_privacy_active ON member_privacy_requests(user_id) WHERE status='awaiting_review';
CREATE TABLE member_content (kind TEXT PRIMARY KEY,payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),updated_at INTEGER NOT NULL) STRICT;
CREATE TRIGGER member_identity_revocation AFTER UPDATE OF email,status ON collect_users
WHEN NEW.email IS NOT OLD.email OR NEW.status!='active'
BEGIN
 DELETE FROM member_sessions WHERE user_id=OLD.id;
 UPDATE member_email_challenges SET state='failed' WHERE email=OLD.email AND state IN ('pending','accepted');
END;
CREATE TABLE member_media (
 id TEXT PRIMARY KEY,user_id TEXT NOT NULL REFERENCES collect_users(id),object_key TEXT NOT NULL UNIQUE,
 content_type TEXT NOT NULL CHECK(content_type IN ('image/jpeg','image/png','image/webp')),
 body_hash TEXT NOT NULL,created_at INTEGER NOT NULL
) STRICT;
