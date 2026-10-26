PRAGMA foreign_keys = ON;

CREATE TABLE admin_users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE COLLATE NOCASE,
  role TEXT NOT NULL CHECK (role IN ('owner', 'admin', 'staff')),
  status TEXT NOT NULL CHECK (status IN ('invited', 'active', 'revoked')),
  password_hash TEXT,
  auth_version INTEGER NOT NULL DEFAULT 1,
  challenge_version INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  invited_at INTEGER,
  accepted_at INTEGER,
  updated_at INTEGER NOT NULL,
  CHECK ((role = 'owner' AND email = 'info@ikanisa.com') OR
         (role != 'owner' AND email != 'info@ikanisa.com')),
  CHECK (status != 'active' OR password_hash IS NOT NULL)
);
CREATE UNIQUE INDEX admin_single_owner ON admin_users(role) WHERE role = 'owner';

CREATE TABLE admin_sessions (
  token_hash TEXT PRIMARY KEY,
  public_id TEXT NOT NULL UNIQUE,
  user_id TEXT NOT NULL REFERENCES admin_users(id),
  auth_version INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX admin_sessions_user ON admin_sessions(user_id);
CREATE INDEX admin_sessions_expiry ON admin_sessions(expires_at);

CREATE TABLE admin_challenges (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES admin_users(id),
  kind TEXT NOT NULL CHECK(kind IN ('invite', 'reset')),
  auth_version INTEGER NOT NULL,
  challenge_version INTEGER NOT NULL,
  delivery_status TEXT NOT NULL DEFAULT 'pending' CHECK(delivery_status IN ('pending','accepted','failed')),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);
CREATE INDEX admin_challenges_user ON admin_challenges(user_id);

CREATE TABLE admin_email_events (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES admin_users(id),
  kind TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('pending','accepted','failed')),
  provider_message_id TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX admin_email_events_user ON admin_email_events(user_id, created_at DESC);

CREATE TABLE admin_rate_limits (
  key_hash TEXT NOT NULL,
  bucket INTEGER NOT NULL,
  count INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  PRIMARY KEY(key_hash, bucket)
);
CREATE INDEX admin_rate_limits_expiry ON admin_rate_limits(expires_at);

CREATE TABLE admin_account_audit (
  id TEXT PRIMARY KEY,
  actor_id TEXT,
  subject_id TEXT,
  action TEXT NOT NULL,
  occurred_at INTEGER NOT NULL
);
