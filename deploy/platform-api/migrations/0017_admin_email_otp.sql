PRAGMA foreign_keys = ON;

-- Passwordless admission is restricted to the separately approved Admin account
-- and its explicit canonical principal. Member email equality grants no access.
CREATE TABLE admin_email_otp_challenges (
 id TEXT PRIMARY KEY,
 user_id TEXT NOT NULL REFERENCES admin_users(id),
 principal_user_id TEXT NOT NULL REFERENCES users(id),
 origin TEXT NOT NULL CHECK(origin LIKE 'https://%'),
 role TEXT NOT NULL CHECK(role IN ('owner','admin','staff')),
 auth_version INTEGER NOT NULL,
 challenge_version INTEGER NOT NULL,
 account_status TEXT NOT NULL CHECK(account_status IN ('invited','active')),
 code_hash TEXT NOT NULL CHECK(length(code_hash)=64),
 created_at INTEGER NOT NULL,
 expires_at INTEGER NOT NULL CHECK(expires_at>created_at),
 attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),
 delivery_status TEXT NOT NULL DEFAULT 'pending'
   CHECK(delivery_status IN ('pending','accepted','unknown','failed','superseded')),
 used_at INTEGER,
 consumed_session_id TEXT UNIQUE,
 CHECK((used_at IS NULL AND consumed_session_id IS NULL)
   OR (used_at IS NOT NULL AND consumed_session_id IS NOT NULL))
) STRICT;
CREATE INDEX admin_email_otp_user ON admin_email_otp_challenges(user_id,created_at DESC);
CREATE INDEX admin_email_otp_expiry ON admin_email_otp_challenges(expires_at);
CREATE TRIGGER admin_email_otp_cooldown BEFORE INSERT ON admin_email_otp_challenges BEGIN
 SELECT CASE WHEN EXISTS(SELECT 1 FROM admin_email_otp_challenges
   WHERE user_id=NEW.user_id AND created_at+60>NEW.created_at)
 THEN RAISE(ABORT,'admin_email_otp_cooldown') END;
END;
CREATE TRIGGER admin_email_otp_identity BEFORE UPDATE OF id,user_id,principal_user_id,origin,role,
 auth_version,challenge_version,account_status,code_hash,created_at,expires_at ON admin_email_otp_challenges
 BEGIN SELECT RAISE(ABORT,'immutable_admin_email_otp_identity'); END;
CREATE TRIGGER admin_email_otp_consumed BEFORE UPDATE ON admin_email_otp_challenges
 WHEN OLD.used_at IS NOT NULL
 BEGIN SELECT RAISE(ABORT,'admin_email_otp_already_consumed'); END;
