-- Candidate additive schema for the scoped native operator realm.
-- NOT APPLIED. Generate a normal Collect migration after schema/guard reconciliation.
-- No users, credentials, wallet, ledger, policy approval or active gateway are seeded.
-- The existing app ledger and receiving-account identities remain authoritative.
BEGIN;
CREATE TABLE private.burimunsi_scopes (
  collection_id text PRIMARY KEY REFERENCES app.collections(id),
  receiving_account_id text NOT NULL REFERENCES app.momo_receiving_accounts(id),
  enabled boolean NOT NULL DEFAULT false,
  active_binding_id text UNIQUE REFERENCES app.momo_gateway_bindings(id),
  binding_version bigint NOT NULL DEFAULT 1 CHECK(binding_version>0),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  created_at bigint NOT NULL
);
CREATE TABLE private.burimunsi_accounts (
  id uuid PRIMARY KEY,
  collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
  principal_user_id text NOT NULL REFERENCES app.users(id),
  phone text NOT NULL CHECK(phone ~ '^\+2507[2389][0-9]{7}$'),
  name text NOT NULL CHECK(length(name) BETWEEN 2 AND 100),
  role text NOT NULL CHECK(role IN ('admin','staff')),
  capabilities text[] NOT NULL,
  pin_hash jsonb NOT NULL CHECK(jsonb_typeof(pin_hash)='object'),
  active boolean NOT NULL DEFAULT true,
  removed boolean NOT NULL DEFAULT false,
  credential_version bigint NOT NULL DEFAULT 1 CHECK(credential_version>0),
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  created_at bigint NOT NULL,
  updated_at bigint NOT NULL,
  UNIQUE(collection_id,phone), UNIQUE(id,collection_id),
  CHECK(capabilities <@ ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage']::text[]),
  CHECK('records.read'=ANY(capabilities)),
  CHECK(role='admin' OR capabilities <@ ARRAY['records.read','members.enroll','payments.allocate']::text[]),
  CHECK(NOT removed OR NOT active)
);
CREATE UNIQUE INDEX burimunsi_one_admin ON private.burimunsi_accounts(collection_id) WHERE role='admin' AND NOT removed;
CREATE TABLE private.burimunsi_device_grants (
  id uuid PRIMARY KEY,
  collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
  installation_id uuid NOT NULL,
  token_hash text NOT NULL CHECK(token_hash ~ '^[a-f0-9]{64}$'),
  profile text NOT NULL CHECK(profile IN ('staff','internal_receiver')),
  custodian_account_id uuid,
  active boolean NOT NULL DEFAULT true,
  version bigint NOT NULL DEFAULT 1 CHECK(version>0),
  created_at bigint NOT NULL,
  UNIQUE(collection_id,installation_id), UNIQUE(id,collection_id),
  FOREIGN KEY(custodian_account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id)
);
CREATE TABLE private.burimunsi_device_accounts (
  grant_id uuid NOT NULL,
  account_id uuid NOT NULL,
  collection_id text NOT NULL,
  PRIMARY KEY(grant_id,account_id),
  FOREIGN KEY(grant_id,collection_id) REFERENCES private.burimunsi_device_grants(id,collection_id),
  FOREIGN KEY(account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id)
);
CREATE TABLE private.burimunsi_sessions (
  id uuid PRIMARY KEY,
  collection_id text NOT NULL,
  account_id uuid NOT NULL,
  grant_id uuid NOT NULL,
  installation_id uuid NOT NULL,
  credential_version bigint NOT NULL,
  grant_version bigint NOT NULL,
  token_hash text NOT NULL UNIQUE CHECK(token_hash ~ '^[a-f0-9]{64}$'),
  created_at bigint NOT NULL,
  expires_at bigint NOT NULL CHECK(expires_at>created_at),
  revoked boolean NOT NULL DEFAULT false,
  FOREIGN KEY(account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id),
  FOREIGN KEY(grant_id,collection_id) REFERENCES private.burimunsi_device_grants(id,collection_id)
);
CREATE INDEX burimunsi_account_sessions ON private.burimunsi_sessions(collection_id,account_id);
CREATE TABLE private.burimunsi_rate_limits (
  collection_id text NOT NULL,
  bucket text NOT NULL CHECK(length(bucket) BETWEEN 1 AND 200),
  window_start bigint NOT NULL,
  window_ms bigint NOT NULL CHECK(window_ms>0),
  attempts bigint NOT NULL CHECK(attempts>0),
  expires_at bigint NOT NULL,
  PRIMARY KEY(collection_id,bucket,window_start)
);
CREATE TABLE private.burimunsi_command_receipts (
  collection_id text NOT NULL,
  actor_id uuid NOT NULL,
  request_id uuid NOT NULL,
  session_id uuid NOT NULL,
  operation text NOT NULL,
  fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
  response jsonb NOT NULL,
  created_at bigint NOT NULL,
  PRIMARY KEY(collection_id,actor_id,request_id),
  FOREIGN KEY(actor_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id)
);
-- This is operational audit metadata, NOT a savings/financial ledger.
CREATE TABLE private.burimunsi_audit (
  id uuid PRIMARY KEY,
  collection_id text NOT NULL,
  actor_id uuid NOT NULL,
  action text NOT NULL,
  entity_id text,
  request_id uuid,
  at_ms bigint NOT NULL
);
-- One authoritative scope per existing canonical transaction. This is routing
-- metadata, not another transaction or financial ledger. Populate only in the
-- admitted source-processing transaction after verifying original binding lineage.
CREATE TABLE private.burimunsi_transaction_scopes (
  transaction_id text PRIMARY KEY REFERENCES app.momo_transactions(id),
  collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
  receiving_account_id text NOT NULL REFERENCES app.momo_receiving_accounts(id),
  source_binding_id text NOT NULL REFERENCES app.momo_gateway_bindings(id),
  source_binding_version bigint NOT NULL CHECK(source_binding_version>0),
  policy_version text NOT NULL,
  created_at bigint NOT NULL
);
-- No direct PostgREST/anon/authenticated access. Runtime's group is server-configured.
DO $block$
DECLARE table_name text;
BEGIN
 FOREACH table_name IN ARRAY ARRAY['burimunsi_scopes','burimunsi_accounts','burimunsi_device_grants','burimunsi_device_accounts','burimunsi_sessions','burimunsi_rate_limits','burimunsi_command_receipts','burimunsi_audit','burimunsi_transaction_scopes'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',table_name);
  EXECUTE format('ALTER TABLE private.%I FORCE ROW LEVEL SECURITY',table_name);
  EXECUTE format('REVOKE ALL ON TABLE private.%I FROM PUBLIC,anon,authenticated',table_name);
  EXECUTE format('GRANT SELECT,INSERT,UPDATE ON TABLE private.%I TO collect_runtime',table_name);
  EXECUTE format('CREATE POLICY burimunsi_scoped_runtime ON private.%I TO collect_runtime USING (collection_id = current_setting(''burimunsi.collection_id'',true)) WITH CHECK (collection_id = current_setting(''burimunsi.collection_id'',true))',table_name);
 END LOOP;
END
$block$;
-- Ledger/balance tables, global authentication and existing financial guards are untouched.
COMMIT;
