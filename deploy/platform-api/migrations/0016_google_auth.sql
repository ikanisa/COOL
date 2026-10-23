-- Google is an authentication method for member sessions, never an Admin grant.
CREATE TABLE auth_google_flows (
 id TEXT PRIMARY KEY,
 state_hash TEXT NOT NULL UNIQUE CHECK(length(state_hash)=64),
 nonce TEXT NOT NULL,
 provider_verifier TEXT NOT NULL CHECK(json_valid(provider_verifier)),
 client_challenge TEXT NOT NULL CHECK(length(client_challenge)=43),
 client_state TEXT NOT NULL,
 return_origin TEXT,
 registration_allowed INTEGER NOT NULL CHECK(registration_allowed IN (0,1)),
 created_at INTEGER NOT NULL,
 expires_at INTEGER NOT NULL CHECK(expires_at>created_at),
 status TEXT NOT NULL CHECK(status IN ('pending','exchanging','ready','consumed','failed')),
 google_subject TEXT,
 email TEXT,
 handoff_hash TEXT UNIQUE,
 consumed_operation_id TEXT UNIQUE
);
CREATE INDEX auth_google_flows_expiry ON auth_google_flows(expires_at);
CREATE TABLE auth_google_identities (
 subject TEXT PRIMARY KEY,
 user_id TEXT NOT NULL UNIQUE REFERENCES users(id),
 created_at TEXT NOT NULL
);
