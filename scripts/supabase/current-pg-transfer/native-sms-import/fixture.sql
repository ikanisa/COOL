-- Extends the financial fixture; these tables are synthetic attestations, not
-- copies of the real native-account, observation, Storage or session schema.
CREATE TABLE src.native_lineage(
 source_id text PRIMARY KEY,principal_user_id text NOT NULL,
 account_id uuid NOT NULL,installation_id uuid NOT NULL,grant_id uuid NOT NULL,
 grant_version bigint NOT NULL,capture_session_id uuid NOT NULL,admitting_session_id uuid,
 admission_kind text NOT NULL,request_id uuid NOT NULL,observation_fingerprint text NOT NULL,
 profile_sha256 text NOT NULL,facts_sha256 text NOT NULL,phase text NOT NULL,lease_token uuid,lease_until bigint,retry_lease uuid,
 attempt_id text NOT NULL,relation text NOT NULL,payment_outcome text NOT NULL,
 observation_request_settled boolean NOT NULL,storage_intent_settled boolean NOT NULL,
 upload_unresolved boolean NOT NULL,delete_tombstone boolean NOT NULL
);
CREATE TABLE private.native_lineage(LIKE src.native_lineage INCLUDING ALL);
CREATE TABLE private.fixture_native_dependencies(
 source_id text PRIMARY KEY,collection_id text NOT NULL,source_owner text NOT NULL,target_owner text NOT NULL,
 account_id uuid NOT NULL,installation_id uuid NOT NULL,grant_id uuid NOT NULL,grant_version bigint NOT NULL,
 capture_session_id uuid NOT NULL,admitting_session_id uuid,request_id uuid NOT NULL,
 account_inert boolean NOT NULL,grant_inert boolean NOT NULL,sessions_revoked boolean NOT NULL,
 mapping_reviewed boolean NOT NULL,runtime_replay_disabled boolean NOT NULL,evidence_sha256 text NOT NULL
);
CREATE TABLE private.fixture_native_receipts(
 operation_id uuid PRIMARY KEY,collection_id text NOT NULL UNIQUE,plan_sha256 text NOT NULL,
 source_hmac text NOT NULL,post_hmac text NOT NULL,source_owner text NOT NULL,target_owner text NOT NULL,
 source_auth uuid NOT NULL,target_auth uuid NOT NULL,sms_count integer NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT,UPDATE ON src.native_lineage,private.native_lineage,private.fixture_native_dependencies,private.fixture_native_receipts TO fixture_operator;
GRANT INSERT ON app.sms_receipts,app.momo_parse_attempts,app.momo_transactions,app.momo_transaction_sources,
 private.origins,private.jobs,private.scopes,private.native_lineage,private.fixture_native_receipts TO fixture_operator;
