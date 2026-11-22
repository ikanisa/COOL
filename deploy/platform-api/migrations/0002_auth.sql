PRAGMA foreign_keys = ON;

CREATE TABLE auth_otp_challenges (
 id TEXT PRIMARY KEY,
 identity_hash TEXT NOT NULL CHECK(length(identity_hash)=64),
 identity_type TEXT NOT NULL CHECK(identity_type IN ('phone','email')),
 identity_value TEXT NOT NULL,
 surface TEXT NOT NULL CHECK(surface IN ('member','admin')),
 registration_allowed INTEGER NOT NULL CHECK(registration_allowed IN (0,1)),
 code_hash TEXT NOT NULL CHECK(length(code_hash)=64),
 created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL CHECK(expires_at>created_at),
 attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),
 status TEXT NOT NULL CHECK(status IN ('dispatching','accepted','delivery_unknown','superseded','consumed')),
 consumed_at INTEGER, consumed_operation_id TEXT UNIQUE,
 CHECK((status='consumed' AND consumed_at IS NOT NULL AND consumed_operation_id IS NOT NULL)
    OR (status!='consumed' AND consumed_at IS NULL AND consumed_operation_id IS NULL))
);
CREATE INDEX auth_otp_identity ON auth_otp_challenges(identity_hash,surface,created_at);

CREATE TABLE auth_rate_buckets (
 bucket_key TEXT PRIMARY KEY, used INTEGER NOT NULL CHECK(used>=0),
 window_ends_at INTEGER NOT NULL
);
CREATE TABLE auth_otp_throttles (
 identity_hash TEXT PRIMARY KEY, last_requested_at INTEGER NOT NULL
);
CREATE TABLE auth_rate_claims (
 request_id TEXT PRIMARY KEY,
 identity_hash TEXT NOT NULL, identity_bucket TEXT NOT NULL,
 ip_bucket TEXT NOT NULL, global_bucket TEXT NOT NULL,
 requested_at INTEGER NOT NULL, hourly_window_ends_at INTEGER NOT NULL,
 daily_window_ends_at INTEGER NOT NULL,
 identity_limit INTEGER NOT NULL CHECK(identity_limit BETWEEN 1 AND 100),
 ip_limit INTEGER NOT NULL CHECK(ip_limit BETWEEN 1 AND 1000),
 global_limit INTEGER NOT NULL CHECK(global_limit BETWEEN 1 AND 100000),
 cooldown_seconds INTEGER NOT NULL CHECK(cooldown_seconds BETWEEN 60 AND 3600)
);
-- The complete spend admission is one SQLite transaction. A refused scope
-- rolls back all three counters, the cooldown, challenge and audit together.
CREATE TRIGGER auth_rate_admission BEFORE INSERT ON auth_rate_claims BEGIN
 SELECT (CASE WHEN
   COALESCE((SELECT used FROM auth_rate_buckets WHERE bucket_key=NEW.identity_bucket),0)>=NEW.identity_limit
   OR COALESCE((SELECT used FROM auth_rate_buckets WHERE bucket_key=NEW.ip_bucket),0)>=NEW.ip_limit
   OR COALESCE((SELECT used FROM auth_rate_buckets WHERE bucket_key=NEW.global_bucket),0)>=NEW.global_limit
   OR EXISTS(SELECT 1 FROM auth_otp_throttles WHERE identity_hash=NEW.identity_hash
      AND last_requested_at+NEW.cooldown_seconds>NEW.requested_at)
 THEN RAISE(ABORT,'auth_rate_limited') END);
 INSERT INTO auth_rate_buckets(bucket_key,used,window_ends_at)
 VALUES(NEW.identity_bucket,1,NEW.hourly_window_ends_at)
 ON CONFLICT(bucket_key) DO UPDATE SET used=used+1;
 INSERT INTO auth_rate_buckets(bucket_key,used,window_ends_at)
 VALUES(NEW.ip_bucket,1,NEW.hourly_window_ends_at)
 ON CONFLICT(bucket_key) DO UPDATE SET used=used+1;
 INSERT INTO auth_rate_buckets(bucket_key,used,window_ends_at)
 VALUES(NEW.global_bucket,1,NEW.daily_window_ends_at)
 ON CONFLICT(bucket_key) DO UPDATE SET used=used+1;
 INSERT INTO auth_otp_throttles(identity_hash,last_requested_at)
 VALUES(NEW.identity_hash,NEW.requested_at)
 ON CONFLICT(identity_hash) DO UPDATE SET last_requested_at=NEW.requested_at;
END;

CREATE TABLE auth_sessions (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id),
 surface TEXT NOT NULL CHECK(surface IN ('member','admin')),
 auth_at INTEGER NOT NULL, created_at INTEGER NOT NULL,
 expires_at INTEGER NOT NULL CHECK(expires_at>created_at),
 revoked_at INTEGER, revocation_reason TEXT,
 assurance_level INTEGER NOT NULL DEFAULT 1 CHECK(assurance_level IN (1,2)),
 mfa_at INTEGER, mfa_factor_id TEXT REFERENCES auth_mfa_factors(id),
 CHECK((assurance_level=1 AND mfa_at IS NULL AND mfa_factor_id IS NULL)
    OR (assurance_level=2 AND mfa_at>=auth_at AND mfa_factor_id IS NOT NULL)),
 CHECK((revoked_at IS NULL AND revocation_reason IS NULL)
    OR (revoked_at IS NOT NULL AND revocation_reason IS NOT NULL))
);
CREATE INDEX auth_sessions_user ON auth_sessions(user_id,revoked_at,expires_at);
CREATE TABLE auth_mfa_factors (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), friendly_name TEXT NOT NULL,
 secret_ciphertext TEXT NOT NULL CHECK(json_valid(secret_ciphertext)),
 status TEXT NOT NULL CHECK(status IN ('pending','verified','revoked')),
 created_at INTEGER NOT NULL, enrollment_session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 verified_at INTEGER, last_totp_counter INTEGER CHECK(last_totp_counter>=0), revoked_at INTEGER,
 CHECK((status='pending' AND verified_at IS NULL AND last_totp_counter IS NULL AND revoked_at IS NULL)
    OR (status='verified' AND verified_at IS NOT NULL AND last_totp_counter IS NOT NULL AND revoked_at IS NULL)
    OR (status='revoked' AND revoked_at IS NOT NULL))
);
CREATE UNIQUE INDEX one_pending_mfa_factor ON auth_mfa_factors(user_id) WHERE status='pending';
CREATE TABLE auth_mfa_challenges (
 id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id), session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 factor_id TEXT NOT NULL REFERENCES auth_mfa_factors(id), created_at INTEGER NOT NULL,
 expires_at INTEGER NOT NULL CHECK(expires_at>created_at), attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),
 consumed_at INTEGER, consumed_operation_id TEXT UNIQUE,
 CHECK((consumed_at IS NULL AND consumed_operation_id IS NULL) OR (consumed_at IS NOT NULL AND consumed_operation_id IS NOT NULL))
);
CREATE TABLE auth_mfa_budgets (
 user_id TEXT NOT NULL REFERENCES users(id), window_start INTEGER NOT NULL,
 kind TEXT NOT NULL CHECK(kind IN ('challenge','verification')), used INTEGER NOT NULL CHECK(used>=1 AND used<=10),
 PRIMARY KEY(user_id,window_start,kind)
);
CREATE TABLE auth_mfa_claims (
 operation_id TEXT PRIMARY KEY, challenge_id TEXT NOT NULL UNIQUE REFERENCES auth_mfa_challenges(id),
 factor_id TEXT NOT NULL REFERENCES auth_mfa_factors(id), user_id TEXT NOT NULL REFERENCES users(id),
 session_id TEXT NOT NULL REFERENCES auth_sessions(id), totp_counter INTEGER NOT NULL CHECK(totp_counter>=0),
 verified_at INTEGER NOT NULL, UNIQUE(factor_id,totp_counter)
);
CREATE TABLE auth_mfa_revocations (
 operation_id TEXT PRIMARY KEY, factor_id TEXT NOT NULL UNIQUE REFERENCES auth_mfa_factors(id),
 user_id TEXT NOT NULL REFERENCES users(id), session_id TEXT NOT NULL REFERENCES auth_sessions(id), revoked_at INTEGER NOT NULL
);
CREATE TRIGGER auth_mfa_factor_identity BEFORE UPDATE OF id,user_id,friendly_name,secret_ciphertext,created_at,enrollment_session_id ON auth_mfa_factors
 BEGIN SELECT RAISE(ABORT,'immutable_mfa_factor'); END;
CREATE TRIGGER auth_mfa_factor_final BEFORE UPDATE ON auth_mfa_factors WHEN OLD.status='revoked'
 BEGIN SELECT RAISE(ABORT,'mfa_revocation_is_final'); END;
CREATE TRIGGER auth_mfa_counter_monotonic BEFORE UPDATE OF last_totp_counter ON auth_mfa_factors
 WHEN OLD.last_totp_counter IS NOT NULL AND (NEW.last_totp_counter IS NULL OR NEW.last_totp_counter<=OLD.last_totp_counter)
 BEGIN SELECT RAISE(ABORT,'mfa_code_replay'); END;
CREATE TRIGGER auth_mfa_claim_no_update BEFORE UPDATE ON auth_mfa_claims
 BEGIN SELECT RAISE(ABORT,'immutable_mfa_claim'); END;
CREATE TRIGGER auth_mfa_claim_no_delete BEFORE DELETE ON auth_mfa_claims
 BEGIN SELECT RAISE(ABORT,'retain_mfa_claim'); END;
CREATE TRIGGER auth_mfa_verified_session BEFORE UPDATE OF assurance_level,mfa_at,mfa_factor_id ON auth_sessions
 WHEN NEW.assurance_level=2 AND NOT EXISTS(SELECT 1 FROM auth_mfa_claims c JOIN auth_mfa_factors f ON f.id=c.factor_id
   WHERE c.session_id=NEW.id AND c.factor_id=NEW.mfa_factor_id AND c.user_id=NEW.user_id AND c.verified_at=NEW.mfa_at
     AND f.status='verified' AND f.last_totp_counter=c.totp_counter)
 BEGIN SELECT RAISE(ABORT,'verified_mfa_claim_required'); END;
CREATE TABLE auth_refresh_tokens (
 token_hash TEXT PRIMARY KEY CHECK(length(token_hash)=64),
 session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL CHECK(expires_at>created_at),
 used_at INTEGER, replaced_by_hash TEXT,
 CHECK((used_at IS NULL AND replaced_by_hash IS NULL)
    OR (used_at IS NOT NULL AND length(replaced_by_hash)=64))
);
CREATE INDEX auth_refresh_session ON auth_refresh_tokens(session_id);
CREATE TABLE auth_otp_verifications (
 operation_id TEXT PRIMARY KEY, challenge_id TEXT NOT NULL UNIQUE REFERENCES auth_otp_challenges(id),
 user_id TEXT NOT NULL REFERENCES users(id), session_id TEXT NOT NULL UNIQUE REFERENCES auth_sessions(id),
 verified_at INTEGER NOT NULL
);
CREATE TRIGGER auth_verification_no_update BEFORE UPDATE ON auth_otp_verifications
 BEGIN SELECT RAISE(ABORT,'immutable_auth_verification'); END;
CREATE TRIGGER auth_verification_no_delete BEFORE DELETE ON auth_otp_verifications
 BEGIN SELECT RAISE(ABORT,'retain_auth_verification'); END;
CREATE TRIGGER auth_session_identity_no_update
 BEFORE UPDATE OF id,user_id,surface,auth_at,created_at,expires_at ON auth_sessions
 BEGIN SELECT RAISE(ABORT,'immutable_session_identity'); END;
CREATE TRIGGER auth_session_no_unrevoke BEFORE UPDATE OF revoked_at,revocation_reason ON auth_sessions
 WHEN OLD.revoked_at IS NOT NULL AND (NEW.revoked_at IS NOT OLD.revoked_at OR NEW.revocation_reason IS NOT OLD.revocation_reason)
 BEGIN SELECT RAISE(ABORT,'session_revocation_is_final'); END;
