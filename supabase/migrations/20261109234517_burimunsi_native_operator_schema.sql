-- Additive BuriMunsi operator metadata on the existing Collect database.
-- No group, wallet, account, PIN, session, device, policy or ledger data is seeded.
-- Original Drive proposals remain unchanged; this is their reconciled successor.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF to_regprocedure('private.admin_invitation_actor(text,text,text,text)') IS NULL
  OR to_regprocedure('private.set_admin_email_context(text,text,text,text)') IS NULL
  OR to_regclass('app.momo_receiving_accounts') IS NULL
  OR to_regclass('app.momo_gateway_bindings') IS NULL
  OR to_regclass('private.burimunsi_accounts') IS NOT NULL
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced') THEN
  RAISE EXCEPTION 'burimunsi_schema_install_precondition' USING ERRCODE='55000';
 END IF;
END;$preflight$;

-- Reconciled source: schema-proposal.sql sha256=0a56327e1fb1eadb96241e495f2f657279931f1323b57db77cc392b1dcc1a799
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

-- Reconciled source: native-principal-session-upgrade-proposal.sql sha256=be0bde85f6d6df3254a666a6529568f905ff90b46c71055e96054fb5ea51d732
ALTER TABLE private.burimunsi_sessions
  ADD COLUMN IF NOT EXISTS principal_user_id text REFERENCES app.users(id);
UPDATE private.burimunsi_sessions SET revoked=true WHERE principal_user_id IS NULL;
ALTER TABLE private.burimunsi_sessions
  ADD CONSTRAINT burimunsi_session_principal_snapshot CHECK(revoked OR principal_user_id IS NOT NULL);
-- An issued session's identity cannot be rewritten; only revocation is mutable.
CREATE FUNCTION private.burimunsi_session_identity_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $body$
BEGIN
 IF (NEW.id,NEW.collection_id,NEW.account_id,NEW.grant_id,NEW.installation_id,
     NEW.principal_user_id,NEW.token_hash,NEW.credential_version,NEW.grant_version,
     NEW.created_at,NEW.expires_at) IS DISTINCT FROM
    (OLD.id,OLD.collection_id,OLD.account_id,OLD.grant_id,OLD.installation_id,
     OLD.principal_user_id,OLD.token_hash,OLD.credential_version,OLD.grant_version,
     OLD.created_at,OLD.expires_at) OR (OLD.revoked AND NOT NEW.revoked) THEN
  RAISE EXCEPTION 'burimunsi_session_identity_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION private.burimunsi_session_identity_immutable() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER burimunsi_session_identity_immutable BEFORE UPDATE ON private.burimunsi_sessions
FOR EACH ROW EXECUTE FUNCTION private.burimunsi_session_identity_immutable();
-- Replacing an operator requires an explicit lifecycle operation, not rebinding
-- another person's native account to a different canonical principal or group.
CREATE FUNCTION private.burimunsi_account_principal_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $body$
BEGIN
 IF (NEW.id,NEW.collection_id,NEW.principal_user_id) IS DISTINCT FROM
    (OLD.id,OLD.collection_id,OLD.principal_user_id) THEN
  RAISE EXCEPTION 'burimunsi_account_principal_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION private.burimunsi_account_principal_immutable() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER burimunsi_account_principal_immutable BEFORE UPDATE ON private.burimunsi_accounts
FOR EACH ROW EXECUTE FUNCTION private.burimunsi_account_principal_immutable();

-- Reconciled source: receipt-jobs-proposal.sql sha256=8a8fcf26f2d15df01812375cb6141174fa4a047c85113dab88dd4335e407c803
CREATE TABLE private.burimunsi_receipt_jobs (
  id uuid PRIMARY KEY,
  collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
  source_id text NOT NULL,
  source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
  binding_id text NOT NULL REFERENCES app.momo_gateway_bindings(id),
  binding_version bigint NOT NULL CHECK(binding_version>0),
  receiving_account_id text NOT NULL REFERENCES app.momo_receiving_accounts(id),
  profile_version text NOT NULL CHECK(length(profile_version) BETWEEN 1 AND 128),
  state text NOT NULL DEFAULT 'queued' CHECK(state IN('queued','running','retry','completed','rejected','dead_letter')),
  lease_owner text,
  lease_version bigint NOT NULL DEFAULT 0 CHECK(lease_version>=0),
  lease_expires_at bigint,
  attempt integer NOT NULL DEFAULT 0 CHECK(attempt>=0),
  max_attempts integer NOT NULL DEFAULT 4 CHECK(max_attempts BETWEEN 4 AND 10),
  next_attempt_at bigint NOT NULL CHECK(next_attempt_at>=0),
  transaction_id text REFERENCES app.momo_transactions(id),
  last_error text CHECK(last_error ~ '^[a-z][a-z0-9_]{0,63}$'),
  created_at bigint NOT NULL CHECK(created_at>=0),
  updated_at bigint NOT NULL CHECK(updated_at>=created_at),
  UNIQUE(collection_id,source_id),
  CHECK(attempt<=max_attempts),
  CHECK((state='running' AND lease_owner IS NOT NULL AND lease_expires_at IS NOT NULL AND lease_version>0 AND attempt>0)
    OR (state<>'running' AND lease_owner IS NULL AND lease_expires_at IS NULL)),
  CHECK(lease_owner IS NULL OR lease_owner ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'),
  CHECK(state<>'completed' OR transaction_id IS NOT NULL)
);
CREATE INDEX burimunsi_receipt_jobs_ready ON private.burimunsi_receipt_jobs
 (collection_id,profile_version,next_attempt_at,created_at,id) WHERE state IN('queued','retry');
CREATE INDEX burimunsi_receipt_jobs_expired ON private.burimunsi_receipt_jobs
 (collection_id,lease_expires_at) WHERE state='running';
CREATE INDEX burimunsi_receipt_jobs_transaction ON private.burimunsi_receipt_jobs(collection_id,transaction_id);
ALTER TABLE private.burimunsi_receipt_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_receipt_jobs FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_receipt_jobs FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON private.burimunsi_receipt_jobs TO collect_runtime;
CREATE POLICY burimunsi_scoped_runtime ON private.burimunsi_receipt_jobs TO collect_runtime
 USING(collection_id=current_setting('burimunsi.collection_id',true))
 WITH CHECK(collection_id=current_setting('burimunsi.collection_id',true));
-- Evidence identity cannot change during a retry, receiver replacement or profile change.
CREATE FUNCTION private.burimunsi_receipt_job_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN
 IF ROW(NEW.id,NEW.collection_id,NEW.source_id,NEW.source_sha256,NEW.binding_id,NEW.binding_version,
    NEW.receiving_account_id,NEW.profile_version,NEW.created_at,NEW.max_attempts)
    IS DISTINCT FROM ROW(OLD.id,OLD.collection_id,OLD.source_id,OLD.source_sha256,OLD.binding_id,OLD.binding_version,
    OLD.receiving_account_id,OLD.profile_version,OLD.created_at,OLD.max_attempts)
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_job_identity_immutable'; END IF;
 IF OLD.transaction_id IS NOT NULL AND NEW.transaction_id IS DISTINCT FROM OLD.transaction_id
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_job_transaction_immutable'; END IF;
 IF OLD.state IN('completed','rejected','dead_letter') AND NEW IS DISTINCT FROM OLD
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_job_terminal_immutable'; END IF;
 IF NEW.attempt<OLD.attempt OR NEW.lease_version<OLD.lease_version
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_job_version_regressed'; END IF;
 RETURN NEW;
END
$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_receipt_job_immutable() FROM PUBLIC;
CREATE TRIGGER burimunsi_receipt_job_immutable BEFORE UPDATE ON private.burimunsi_receipt_jobs
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_receipt_job_immutable();

-- Reconciled source: rematch-jobs-proposal.sql sha256=1e6f3740ec028069a389f6eabf3aafb0dc5a7593b23003d840bc822855c5700b
CREATE TABLE private.burimunsi_rematch_jobs (
 id uuid PRIMARY KEY,
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 receiving_account_id text NOT NULL REFERENCES app.momo_receiving_accounts(id),
 member_id text NOT NULL REFERENCES app.users(id),
 request_id uuid NOT NULL,
 cause text NOT NULL CHECK(cause IN('enrollment','reactivation','verified_identity')),
 cutoff_at bigint NOT NULL CHECK(cutoff_at>=0),
 after_transaction_id text COLLATE "C" NOT NULL DEFAULT '' CHECK(after_transaction_id='' OR after_transaction_id ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'),
 target_transaction_id text REFERENCES app.momo_transactions(id),
 target_outcome text CHECK(target_outcome IN('posted','unallocated','skipped')),
 target_reason text CHECK(target_reason IN('policy_unavailable','scope_mismatch','identity_data_unavailable','masked_identity','invalid_time',
   'invalid_identity','ambiguous_identity','no_verified_identity','member_ineligible','different_member',
   'transaction_conflict','transaction_reversed','already_posted')),
 processed_count bigint NOT NULL DEFAULT 0 CHECK(processed_count>=0),
 lease_start_count bigint NOT NULL DEFAULT 0 CHECK(lease_start_count>=0 AND lease_start_count<=processed_count),
 policy_version text CHECK(length(policy_version) BETWEEN 1 AND 128 AND policy_version !~ '[[:cntrl:]]'),
 state text NOT NULL DEFAULT 'queued' CHECK(state IN('queued','running','retry','completed','dead_letter')),
 lease_owner text CHECK(lease_owner ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'),
 lease_version bigint NOT NULL DEFAULT 0 CHECK(lease_version>=0),
 lease_expires_at bigint,
 attempt integer NOT NULL DEFAULT 0 CHECK(attempt>=0),
 max_attempts integer NOT NULL DEFAULT 4 CHECK(max_attempts BETWEEN 4 AND 10),
 next_attempt_at bigint NOT NULL CHECK(next_attempt_at>=0),
 last_error text CHECK(last_error ~ '^[a-z][a-z0-9_]{0,63}$'),
 created_at bigint NOT NULL CHECK(created_at=cutoff_at),
 updated_at bigint NOT NULL CHECK(updated_at>=created_at),
 UNIQUE(collection_id,request_id),
 CHECK(attempt<=max_attempts),
 CHECK((state='running' AND lease_owner IS NOT NULL AND lease_expires_at IS NOT NULL AND policy_version IS NOT NULL AND lease_version>0 AND attempt>0)
   OR (state<>'running' AND lease_owner IS NULL AND lease_expires_at IS NULL)),
 CHECK(target_transaction_id IS NULL OR target_transaction_id COLLATE "C">after_transaction_id COLLATE "C"),
 CHECK(target_transaction_id IS NOT NULL OR (target_outcome IS NULL AND target_reason IS NULL)),
 CHECK((target_outcome IS NULL AND target_reason IS NULL) OR (target_outcome IS NOT NULL AND ((target_outcome='posted' AND target_reason IS NULL)
   OR (target_outcome IN('unallocated','skipped') AND target_reason IS NOT NULL)))),
 CHECK(state<>'completed' OR target_transaction_id IS NULL)
);
CREATE INDEX burimunsi_rematch_jobs_ready ON private.burimunsi_rematch_jobs(collection_id,next_attempt_at,created_at,id)
 WHERE state IN('queued','retry');
CREATE INDEX burimunsi_rematch_jobs_expired ON private.burimunsi_rematch_jobs(collection_id,lease_expires_at) WHERE state='running';
ALTER TABLE private.burimunsi_rematch_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_rematch_jobs FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_rematch_jobs FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON private.burimunsi_rematch_jobs TO collect_runtime;
CREATE POLICY burimunsi_scoped_runtime ON private.burimunsi_rematch_jobs TO collect_runtime
 USING(collection_id=current_setting('burimunsi.collection_id',true))
 WITH CHECK(collection_id=current_setting('burimunsi.collection_id',true));
CREATE FUNCTION private.burimunsi_rematch_job_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN
 IF ROW(NEW.id,NEW.collection_id,NEW.receiving_account_id,NEW.member_id,NEW.request_id,NEW.cause,NEW.cutoff_at,NEW.created_at,NEW.max_attempts)
  IS DISTINCT FROM ROW(OLD.id,OLD.collection_id,OLD.receiving_account_id,OLD.member_id,OLD.request_id,OLD.cause,OLD.cutoff_at,OLD.created_at,OLD.max_attempts)
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_rematch_identity_immutable'; END IF;
 IF OLD.state IN('completed','dead_letter') AND NEW IS DISTINCT FROM OLD
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_rematch_terminal_immutable'; END IF;
 IF NEW.updated_at<OLD.updated_at OR NEW.lease_version<OLD.lease_version OR NEW.lease_version>OLD.lease_version+1
 THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_rematch_version_invalid'; END IF;
 IF NEW.lease_version=OLD.lease_version+1 THEN
  IF NEW.state<>'running' OR OLD.state NOT IN('queued','retry','running') OR NEW.attempt<>OLD.attempt+1 OR NEW.lease_start_count<>OLD.processed_count
   OR (OLD.state='running' AND OLD.lease_expires_at>floor(extract(epoch FROM clock_timestamp())*1000)::bigint)
  THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_rematch_claim_invalid'; END IF;
 ELSE
  IF NEW.policy_version IS DISTINCT FROM OLD.policy_version OR NEW.lease_start_count<>OLD.lease_start_count
    OR (NEW.state='running' AND NEW.lease_owner IS DISTINCT FROM OLD.lease_owner)
  THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_rematch_lease_immutable'; END IF;
 END IF;
 IF NEW.after_transaction_id IS DISTINCT FROM OLD.after_transaction_id THEN
  IF OLD.state<>'running' OR NEW.state<>'running' OR NEW.lease_version<>OLD.lease_version OR OLD.target_transaction_id IS NULL
   OR OLD.target_outcome IS NULL OR NEW.after_transaction_id IS DISTINCT FROM OLD.target_transaction_id
   OR NEW.target_transaction_id IS NOT NULL OR NEW.processed_count<>OLD.processed_count+1 OR NEW.attempt<>1
  THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_rematch_checkpoint_invalid'; END IF;
 ELSE
  IF NEW.processed_count<>OLD.processed_count OR (OLD.target_transaction_id IS NOT NULL AND NEW.target_transaction_id IS DISTINCT FROM OLD.target_transaction_id)
  THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_rematch_target_immutable'; END IF;
  IF OLD.target_outcome IS NOT NULL AND ROW(NEW.target_outcome,NEW.target_reason) IS DISTINCT FROM ROW(OLD.target_outcome,OLD.target_reason)
  THEN RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_rematch_outcome_immutable'; END IF;
 END IF;
 RETURN NEW;
END
$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_rematch_job_guard() FROM PUBLIC;
CREATE TRIGGER burimunsi_rematch_job_guard BEFORE UPDATE ON private.burimunsi_rematch_jobs
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_rematch_job_guard();
-- The historical cutoff depends on original routing lineage. Scope metadata
-- cannot be rewritten to move an existing transaction into another scan.
CREATE FUNCTION private.burimunsi_transaction_scope_immutable() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $fn$
BEGIN
 IF NEW IS DISTINCT FROM OLD THEN
  RAISE EXCEPTION USING ERRCODE='23514',MESSAGE='burimunsi_transaction_scope_immutable';
 END IF;
 RETURN NEW;
END
$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_transaction_scope_immutable() FROM PUBLIC;
CREATE TRIGGER burimunsi_transaction_scope_immutable BEFORE UPDATE ON private.burimunsi_transaction_scopes
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_transaction_scope_immutable();

-- Reconciled source: canonical-integration-proposal.sql sha256=88d4567002681a1e0d329e57a78178ec3b35e6d97d591a6b3ec14373368d6a3b
CREATE TABLE private.burimunsi_session_links (
 native_session_id uuid PRIMARY KEY REFERENCES private.burimunsi_sessions(id),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 account_id uuid NOT NULL,
 principal_user_id text NOT NULL REFERENCES app.users(id),
 principal_session_id text NOT NULL REFERENCES app.auth_sessions(id),
 created_at bigint NOT NULL CHECK(created_at>=0),
 expires_at bigint NOT NULL CHECK(expires_at>created_at),
 FOREIGN KEY(account_id,collection_id) REFERENCES private.burimunsi_accounts(id,collection_id)
);
CREATE TABLE private.burimunsi_integration_policies (
 lock_anchor smallint NOT NULL DEFAULT 0 CHECK(lock_anchor=0),
 collection_id text PRIMARY KEY REFERENCES private.burimunsi_scopes(collection_id),
 approved_version text NOT NULL CHECK(length(approved_version) BETWEEN 1 AND 128),
 approved_by text NOT NULL REFERENCES app.users(id),
 approved_at bigint NOT NULL CHECK(approved_at>=0),
 expires_at bigint NOT NULL CHECK(expires_at>approved_at),
 revoked_at bigint CHECK(revoked_at>=approved_at),
 source_reference text NOT NULL CHECK(length(source_reference) BETWEEN 1 AND 512),
 native_parser_version text NOT NULL,
 provider_profile_version text NOT NULL,
 provider_profile_sha256 text NOT NULL CHECK(provider_profile_sha256 ~ '^[a-f0-9]{64}$'),
 identity_enabled boolean NOT NULL DEFAULT false,
 processing_enabled boolean NOT NULL DEFAULT false,
 scheduler_enabled boolean NOT NULL DEFAULT false,
 CHECK(NOT scheduler_enabled OR processing_enabled)
);
CREATE TABLE private.burimunsi_identity_proofs (
 lock_anchor smallint NOT NULL DEFAULT 0 CHECK(lock_anchor=0),
 id text PRIMARY KEY CHECK(id ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 member_id text NOT NULL REFERENCES app.users(id),
 phone text NOT NULL CHECK(phone ~ '^\+2507[2389][0-9]{7}$'),
 state text NOT NULL CHECK(state IN('verified','revoked')),
 purpose text NOT NULL CHECK(purpose='own_contributions'),
 verification_method text NOT NULL CHECK(verification_method='collect_owner_review'),
 policy_version text NOT NULL CHECK(length(policy_version) BETWEEN 1 AND 128),
 source_reference text NOT NULL CHECK(length(source_reference) BETWEEN 1 AND 512),
 evidence_sha256 text NOT NULL CHECK(evidence_sha256 ~ '^[a-f0-9]{64}$'),
 approved_by text NOT NULL REFERENCES app.users(id),
 approved_at bigint NOT NULL CHECK(approved_at>=0),
 valid_from bigint NOT NULL CHECK(valid_from>=0),
 valid_until bigint CHECK(valid_until>valid_from),
 revoked_at bigint CHECK(revoked_at>=approved_at),
 CHECK((state='verified' AND revoked_at IS NULL) OR (state='revoked' AND revoked_at IS NOT NULL))
);
-- Overlapping ownership is representable and stays ambiguous, not silently deduplicated.
CREATE INDEX burimunsi_identity_proof_scope ON private.burimunsi_identity_proofs(collection_id,policy_version,phone,valid_from);
CREATE TABLE private.burimunsi_worker_grants (
 lock_anchor smallint NOT NULL DEFAULT 0 CHECK(lock_anchor=0),
 id uuid PRIMARY KEY,
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 owner text NOT NULL CHECK(owner ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$'),
 principal_user_id text NOT NULL REFERENCES app.users(id),
 principal_session_id text NOT NULL REFERENCES app.auth_sessions(id),
 source_sha256 text NOT NULL CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 policy_version text NOT NULL CHECK(length(policy_version) BETWEEN 1 AND 128),
 work_kinds text[] NOT NULL CHECK(cardinality(work_kinds)>0 AND work_kinds <@ ARRAY['receipt','rematch']::text[]),
 enabled boolean NOT NULL DEFAULT false,
 version bigint NOT NULL DEFAULT 1 CHECK(version>0),
 approved_by text NOT NULL REFERENCES app.users(id),
 approved_at bigint NOT NULL CHECK(approved_at>=0),
 expires_at bigint NOT NULL CHECK(expires_at>approved_at),
 revoked_at bigint CHECK(revoked_at>=approved_at),
 UNIQUE(collection_id,owner), CHECK(NOT enabled OR revoked_at IS NULL)
);
CREATE TABLE private.burimunsi_schedulers (
 collection_id text PRIMARY KEY REFERENCES private.burimunsi_scopes(collection_id),
 state text NOT NULL DEFAULT 'idle' CHECK(state IN('idle','running')),
 run_id uuid,lease_owner text,lease_version bigint NOT NULL DEFAULT 0 CHECK(lease_version>=0),
 lease_expires_at bigint,profile_version text,policy_version text,admission_id uuid,
 source_sha256 text CHECK(source_sha256 ~ '^[a-f0-9]{64}$'),
 started_at bigint,completed_at bigint,last_outcome text CHECK(last_outcome IN('completed','yielded','stopped','failed')),
 summary jsonb CHECK(summary IS NULL OR jsonb_typeof(summary)='object'),
 CHECK(state<>'running' OR (run_id IS NOT NULL AND lease_owner IS NOT NULL AND lease_expires_at IS NOT NULL AND
   admission_id IS NOT NULL AND source_sha256 IS NOT NULL AND lease_version>0 AND profile_version IS NOT NULL AND policy_version IS NOT NULL))
);
DO $block$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['burimunsi_session_links','burimunsi_integration_policies','burimunsi_identity_proofs','burimunsi_worker_grants','burimunsi_schedulers'] LOOP
  EXECUTE format('ALTER TABLE private.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE private.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE private.%I FROM PUBLIC,anon,authenticated,collect_runtime',t);
  EXECUTE format('GRANT SELECT ON TABLE private.%I TO collect_runtime',t);
  EXECUTE format('CREATE POLICY burimunsi_scoped_runtime ON private.%I TO collect_runtime USING (collection_id=current_setting(''burimunsi.collection_id'',true)) WITH CHECK (collection_id=current_setting(''burimunsi.collection_id'',true))',t);
 END LOOP;
END
$block$;
-- PostgreSQL row-locking SELECT requires UPDATE on at least one column.
-- Only the invariant sentinel is writable: CHECK + NOT NULL permits no change
-- to its value. No authorization/policy/evidence field receives UPDATE privilege.
-- Qualify this under collect_runtime and FORCE RLS on real PostgreSQL.
GRANT UPDATE(lock_anchor) ON private.burimunsi_integration_policies TO collect_runtime;
GRANT UPDATE(lock_anchor) ON private.burimunsi_identity_proofs TO collect_runtime;
GRANT UPDATE(lock_anchor) ON private.burimunsi_worker_grants TO collect_runtime;
-- Runtime cannot approve identities, processing policy or worker grants, or mutate
-- an issued linkage. No new SECURITY DEFINER function or financial guard bypass.
GRANT INSERT ON private.burimunsi_session_links TO collect_runtime;
GRANT INSERT,UPDATE ON private.burimunsi_schedulers TO collect_runtime;

-- Current shared-session and owner-approved operator bindings follow.
ALTER TABLE private.burimunsi_accounts ADD CONSTRAINT burimunsi_one_principal_per_scope UNIQUE(collection_id,principal_user_id);
CREATE UNIQUE INDEX burimunsi_one_receiving_installation ON private.burimunsi_device_grants(collection_id)
 WHERE active AND profile='internal_receiver';
CREATE UNIQUE INDEX burimunsi_unique_device_secret ON private.burimunsi_device_grants(token_hash);

-- A native login phone is an explicit owner-approved binding to an EXISTING
-- shared identity. It is not a replacement for app.users.phone, a GoTrue signup
-- or an assertion made by a name, PIN, native administrator or client JSON.
CREATE TABLE private.burimunsi_operator_approvals(
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 principal_user_id text NOT NULL REFERENCES app.users(id),
 admin_user_id text NOT NULL REFERENCES app.admin_users(id),
 phone text NOT NULL CHECK(phone ~ '^\+2507[2389][0-9]{7}$'),
 role text NOT NULL CHECK(role IN('admin','staff')),
 capabilities text[] NOT NULL,
 active boolean NOT NULL,
 version bigint NOT NULL CHECK(version BETWEEN 1 AND 9007199254740991),
 approved_by text NOT NULL REFERENCES app.users(id),
 created_at bigint NOT NULL CHECK(created_at>=0),
 updated_at bigint NOT NULL CHECK(updated_at>=created_at),
 lock_anchor smallint NOT NULL DEFAULT 0 CHECK(lock_anchor=0),
 PRIMARY KEY(collection_id,principal_user_id),UNIQUE(collection_id,phone),
 CHECK(cardinality(capabilities)>0 AND 'records.read'=ANY(capabilities)),
 CHECK(capabilities <@ ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage']::text[]),
 CHECK(role='admin' OR capabilities <@ ARRAY['records.read','members.enroll','payments.allocate']::text[])
);
ALTER TABLE private.burimunsi_operator_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_operator_approvals FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_operator_approvals FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
GRANT SELECT,UPDATE(lock_anchor) ON private.burimunsi_operator_approvals TO collect_runtime;
CREATE POLICY burimunsi_scoped_runtime ON private.burimunsi_operator_approvals TO collect_runtime
 USING(collection_id=current_setting('burimunsi.collection_id',true))
 WITH CHECK(collection_id=current_setting('burimunsi.collection_id',true));
CREATE FUNCTION private.burimunsi_operator_approval_identity() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW;END IF;
 IF (NEW.collection_id,NEW.principal_user_id,NEW.admin_user_id,NEW.role,NEW.created_at,NEW.lock_anchor)
  IS DISTINCT FROM (OLD.collection_id,OLD.principal_user_id,OLD.admin_user_id,OLD.role,OLD.created_at,OLD.lock_anchor)
  OR NEW.version<>OLD.version+1 OR NEW.updated_at<OLD.updated_at THEN
  RAISE EXCEPTION 'burimunsi_approval_identity_immutable' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_operator_approval_identity() FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
CREATE TRIGGER burimunsi_operator_approval_identity BEFORE UPDATE ON private.burimunsi_operator_approvals
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_operator_approval_identity();
CREATE TRIGGER burimunsi_operator_approval_retain BEFORE DELETE OR TRUNCATE ON private.burimunsi_operator_approvals
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();

CREATE TABLE private.burimunsi_owner_commands(
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 actor_id text NOT NULL REFERENCES app.users(id),
 request_id uuid NOT NULL,
 principal_session_id text NOT NULL REFERENCES app.auth_sessions(id),
 operation text NOT NULL CHECK(operation='operator_approval'),
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 response jsonb NOT NULL CHECK(jsonb_typeof(response)='object'),
 created_at bigint NOT NULL CHECK(created_at>=0),
 PRIMARY KEY(collection_id,actor_id,request_id)
);
ALTER TABLE private.burimunsi_owner_commands ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_owner_commands FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
CREATE TRIGGER burimunsi_owner_commands_retain BEFORE UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_owner_commands
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_owner_commands ENABLE ALWAYS TRIGGER burimunsi_owner_commands_retain;

-- Snapshot checks intentionally contain no row locks. The existing assert_actor
-- and Admin email helpers lock rows, and cannot run inside a READ ONLY snapshot.
-- Provider JWT verification remains in the existing Edge request gate. This
-- helper additionally requires its actual managed session, active projection,
-- approved global account, current BFF custody and truthful optional AAL2 state.
-- Exactly one BFF tuple must match the signed managed session; ambiguity denies.
CREATE FUNCTION private.burimunsi_managed_admin_snapshot() RETURNS TABLE(
 principal_user_id text,principal_session_id text,now_ms text,session_user_id text,
 surface text,expires_at bigint,revoked_at bigint,admin_id text,cookie_hash text,
 origin text,public_session_id text,transaction_read_only text,shared_role text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 WITH candidates AS MATERIALIZED(
  SELECT u.id AS principal_user_id,s.id AS principal_session_id,
   floor(extract(epoch FROM clock_timestamp())*1000)::text AS now_ms,s.user_id AS session_user_id,
   s.surface,least(s.expires_at,c.expires_at,
    CASE WHEN private.request_claims()->>'exp' ~ '^[0-9]{1,12}$' THEN (private.request_claims()->>'exp')::bigint ELSE 0 END,
    coalesce(floor(extract(epoch FROM managed.not_after))::bigint,s.expires_at)) AS expires_at,s.revoked_at,a.id AS admin_id,
   c.token_hash AS cookie_hash,c.origin,c.public_id AS public_session_id,
   current_setting('transaction_read_only') AS transaction_read_only,a.role AS shared_role
  FROM private.auth_principal_links p
  JOIN app.users u ON u.id=p.user_id AND u.access_status='active'
  JOIN app.auth_sessions s ON s.user_id=u.id AND s.id=api.current_session_id()
  JOIN app.admin_principal_links l ON l.user_id=u.id
  JOIN app.admin_users a ON a.id=l.admin_user_id AND a.status='active'
  JOIN app.admin_sessions c ON c.user_id=a.id AND c.auth_version=a.auth_version AND c.auth_session_id=s.id
  JOIN private.bff_sessions b ON b.token_hash=c.token_hash AND b.auth_user_id=p.auth_user_id AND b.auth_session_id::text=s.id
  JOIN auth.sessions managed ON managed.id=b.auth_session_id AND managed.user_id=b.auth_user_id
  JOIN auth.users actual ON actual.id=managed.user_id
  WHERE current_setting('collect.edge_verified',true)='true'
   AND private.request_claims()->>'role'='authenticated'
   AND p.auth_user_id::text=private.request_claims()->>'sub'
   AND private.is_managed_session(p.auth_user_id,managed.id)
   AND actual.is_anonymous IS NOT TRUE
   AND CASE WHEN private.request_claims()->>'exp' ~ '^[0-9]{1,12}$' THEN (private.request_claims()->>'exp')::bigint ELSE 0 END
    >extract(epoch FROM clock_timestamp())::bigint
   AND s.surface='admin' AND s.revoked_at IS NULL
   AND least(s.expires_at,c.expires_at)>extract(epoch FROM clock_timestamp())::bigint
   AND b.refresh_lease IS NULL AND actual.email_confirmed_at IS NOT NULL
   AND lower(actual.email)=lower(a.email)
   AND lower(a.email) ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' AND length(a.email)<=254
   AND (s.assurance_level=1 OR (s.assurance_level=2 AND to_jsonb(managed)->>'aal'='aal2'
    AND EXISTS(SELECT 1 FROM private.managed_mfa_proofs proof JOIN auth.mfa_factors f ON f.id=proof.factor_id AND f.user_id=proof.user_id
     WHERE proof.session_id=managed.id AND proof.user_id=managed.user_id AND proof.factor_id::text=s.mfa_factor_id
      AND proof.verified_at_epoch=s.mfa_at AND f.status::text='verified'
      AND (to_jsonb(managed)->>'factor_id' IS NULL OR to_jsonb(managed)->>'factor_id'=proof.factor_id::text))))
   AND (c.issued_assurance_level=1 OR (c.issued_assurance_level=2 AND s.assurance_level=2
    AND c.issued_mfa_at=s.mfa_at AND c.issued_mfa_factor_id=s.mfa_factor_id))
 ) SELECT * FROM candidates WHERE (SELECT count(*) FROM candidates)=1
$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_managed_admin_snapshot() FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.burimunsi_managed_admin_snapshot() TO collect_runtime;

CREATE FUNCTION private.burimunsi_operator_is_current(p_collection text,p_principal text,p_phone text,p_role text,p_capabilities text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT p_collection=current_setting('burimunsi.collection_id',true) AND EXISTS(
  SELECT 1 FROM private.burimunsi_operator_approvals o
  JOIN app.users u ON u.id=o.principal_user_id AND u.access_status='active'
  JOIN app.admin_principal_links l ON l.user_id=u.id AND l.admin_user_id=o.admin_user_id
  JOIN app.admin_users a ON a.id=l.admin_user_id AND a.status='active'
  JOIN private.auth_principal_links p ON p.user_id=u.id
  JOIN auth.users actual ON actual.id=p.auth_user_id
  WHERE o.collection_id=p_collection AND o.principal_user_id=p_principal AND o.phone=p_phone
   AND o.active AND o.role=p_role AND p_capabilities <@ o.capabilities AND cardinality(p_capabilities)>0
   AND 'records.read'=ANY(p_capabilities) AND (o.role='staff' OR a.role IN('owner','admin'))
   AND actual.email_confirmed_at IS NOT NULL AND lower(actual.email)=lower(a.email)
   AND actual.deleted_at IS NULL AND (actual.banned_until IS NULL OR actual.banned_until<=statement_timestamp())
 )
$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_operator_is_current(text,text,text,text,text[]) FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.burimunsi_operator_is_current(text,text,text,text,text[]) TO collect_runtime;

CREATE FUNCTION private.burimunsi_account_requires_approval() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF NEW.active AND NOT NEW.removed AND NOT coalesce(private.burimunsi_operator_is_current(
  NEW.collection_id,NEW.principal_user_id,NEW.phone,NEW.role,NEW.capabilities),false) THEN
  RAISE EXCEPTION 'burimunsi_operator_not_approved' USING ERRCODE='42501';
 END IF;
 RETURN NEW;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_account_requires_approval() FROM PUBLIC,anon,authenticated,service_role,collect_runtime,collect_importer;
CREATE TRIGGER burimunsi_account_requires_approval BEFORE INSERT OR UPDATE ON private.burimunsi_accounts
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_account_requires_approval();

-- Same owner/cookie/current-email proof used by Collect team administration.
-- Runtime has no direct write privilege on approvals or retained owner receipts.
CREATE FUNCTION private.burimunsi_operator_approve(
 p_actor text,p_cookie text,p_origin text,p_public text,p_collection text,p_request uuid,
 p_admin text,p_phone text,p_role text,p_capabilities text[],p_active boolean,p_expected bigint
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE principal text;sid text;target text;target_role text;target_status text;target_user_status text;
 prior private.burimunsi_owner_commands%ROWTYPE;retained private.burimunsi_operator_approvals%ROWTYPE;
 fingerprint text;result jsonb;at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 sid:=private.admin_invitation_actor(p_actor,p_cookie,p_origin,p_public)::text;
 principal:=api.current_principal_id();
 IF p_collection IS DISTINCT FROM current_setting('burimunsi.collection_id',true)
  OR p_request IS NULL OR p_admin IS NULL OR p_phone IS NULL OR p_phone !~ '^\+2507[2389][0-9]{7}$'
  OR p_role IS NULL OR p_role NOT IN('admin','staff') OR p_active IS NULL OR p_expected IS NULL OR p_expected<0 OR p_expected>=9007199254740991
  OR p_capabilities IS NULL OR cardinality(p_capabilities) NOT BETWEEN 1 AND 6
  OR array_position(p_capabilities,NULL) IS NOT NULL OR NOT('records.read'=ANY(p_capabilities))
  OR NOT(p_capabilities <@ ARRAY['records.read','members.enroll','payments.allocate','staff.manage','sms.read','gateway.manage']::text[])
  OR (p_role='staff' AND NOT(p_capabilities <@ ARRAY['records.read','members.enroll','payments.allocate']::text[]))
  OR cardinality(p_capabilities)<>(SELECT count(DISTINCT c) FROM unnest(p_capabilities)c)
  OR NOT EXISTS(SELECT 1 FROM private.burimunsi_scopes WHERE collection_id=p_collection) THEN
  RAISE EXCEPTION 'burimunsi_invalid_approval' USING ERRCODE='22023';
 END IF;
 fingerprint:=encode(sha256(convert_to(jsonb_build_array(p_admin,p_phone,p_role,
  (SELECT jsonb_agg(c ORDER BY c) FROM unnest(p_capabilities)c),p_active,p_expected)::text,'UTF8')),'hex');
 SELECT * INTO prior FROM private.burimunsi_owner_commands WHERE collection_id=p_collection AND actor_id=principal AND request_id=p_request;
 IF FOUND THEN
  IF prior.principal_session_id<>sid OR prior.fingerprint<>fingerprint THEN
   RAISE EXCEPTION 'burimunsi_approval_request_conflict' USING ERRCODE='23505';
  END IF;
  RETURN prior.response;
 END IF;
 SELECT u.id,a.role,a.status,u.access_status INTO target,target_role,target_status,target_user_status
 FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id JOIN app.users u ON u.id=l.user_id
 WHERE a.id=p_admin FOR SHARE OF a,l,u;
 IF target IS NULL THEN RAISE EXCEPTION 'burimunsi_shared_operator_unavailable' USING ERRCODE='42501';END IF;
 IF p_active THEN
  IF target_status<>'active' OR target_user_status<>'active' OR (p_role='admin' AND target_role NOT IN('owner','admin')) THEN
   RAISE EXCEPTION 'burimunsi_shared_operator_unavailable' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM private.auth_principal_links p JOIN auth.users actual ON actual.id=p.auth_user_id
   JOIN app.admin_users a ON a.id=p_admin
   WHERE p.user_id=target AND actual.email_confirmed_at IS NOT NULL AND lower(actual.email)=lower(a.email)
    AND actual.deleted_at IS NULL AND (actual.banned_until IS NULL OR actual.banned_until<=clock_timestamp())
   FOR SHARE OF p,actual;
  IF NOT FOUND THEN RAISE EXCEPTION 'burimunsi_shared_operator_unavailable' USING ERRCODE='42501';END IF;
 END IF;
 SELECT * INTO retained FROM private.burimunsi_operator_approvals WHERE collection_id=p_collection AND principal_user_id=target FOR UPDATE;
 IF FOUND THEN
  IF p_expected<>retained.version OR retained.admin_user_id<>p_admin OR retained.role<>p_role THEN
   RAISE EXCEPTION 'burimunsi_approval_changed' USING ERRCODE='40001';
  END IF;
  UPDATE private.burimunsi_operator_approvals SET phone=p_phone,capabilities=p_capabilities,active=p_active,
   version=version+1,approved_by=principal,updated_at=at_ms
   WHERE collection_id=p_collection AND principal_user_id=target;
 ELSE
  IF p_expected<>0 OR NOT p_active THEN RAISE EXCEPTION 'burimunsi_approval_changed' USING ERRCODE='40001';END IF;
  INSERT INTO private.burimunsi_operator_approvals(collection_id,principal_user_id,admin_user_id,phone,role,capabilities,active,version,approved_by,created_at,updated_at)
   VALUES(p_collection,target,p_admin,p_phone,p_role,p_capabilities,true,1,principal,at_ms,at_ms);
 END IF;
 -- A changed owner binding invalidates existing operator sessions. Capture
 -- authority/outbox custody and the genuine managed session remain independent.
 UPDATE private.burimunsi_sessions SET revoked=true WHERE collection_id=p_collection
  AND account_id IN(SELECT id FROM private.burimunsi_accounts WHERE collection_id=p_collection AND principal_user_id=target)
  AND NOT revoked;
 result:=jsonb_build_object('contractVersion',1,'requestId',p_request,'principalId',target,'version',p_expected+1,'active',p_active,'applied',true);
 INSERT INTO private.burimunsi_owner_commands(collection_id,actor_id,request_id,principal_session_id,operation,fingerprint,response,created_at)
  VALUES(p_collection,principal,p_request,sid,'operator_approval',fingerprint,result,at_ms);
 INSERT INTO app.audit_log(actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at)
  VALUES(principal,sid,'burimunsi.operator.approval','user',target,p_request::text,
   jsonb_build_object('collection_id',p_collection,'version',p_expected+1,'active',p_active,'role',p_role)::text,
   to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
 RETURN result;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_operator_approve(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.burimunsi_operator_approve(text,text,text,text,text,uuid,text,text,text,text[],boolean,bigint) TO collect_runtime;

CREATE FUNCTION private.burimunsi_operator_directory(p_actor text,p_cookie text,p_origin text,p_public text,p_collection text,p_request uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE principal text;sid text;receipt private.burimunsi_owner_commands%ROWTYPE;approvals jsonb;team jsonb;
BEGIN
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 sid:=private.admin_invitation_actor(p_actor,p_cookie,p_origin,p_public)::text;principal:=api.current_principal_id();
 IF p_collection IS DISTINCT FROM current_setting('burimunsi.collection_id',true) THEN
  RAISE EXCEPTION 'burimunsi_invalid_approval' USING ERRCODE='22023';
 END IF;
 IF p_request IS NOT NULL THEN
  SELECT * INTO receipt FROM private.burimunsi_owner_commands WHERE collection_id=p_collection AND actor_id=principal AND request_id=p_request;
  IF NOT FOUND THEN RETURN jsonb_build_object('contractVersion',1,'found',false);END IF;
  IF receipt.principal_session_id<>sid THEN RAISE EXCEPTION 'burimunsi_approval_request_conflict' USING ERRCODE='23505';END IF;
  RETURN jsonb_build_object('contractVersion',1,'found',true,'receipt',receipt.response);
 END IF;
 IF (SELECT count(*) FROM private.burimunsi_operator_approvals WHERE collection_id=p_collection)>500
  OR (SELECT count(*) FROM app.admin_users)>500 THEN
  RAISE EXCEPTION 'burimunsi_directory_limit' USING ERRCODE='54000';
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('principalId',o.principal_user_id,'adminId',o.admin_user_id,
  'phone',o.phone,'role',o.role,'capabilities',o.capabilities,'active',o.active,'version',o.version,
  'sharedRole',a.role,'sharedStatus',a.status,'email',a.email,'displayName',a.display_name) ORDER BY a.email),'[]'::jsonb)
 INTO approvals FROM private.burimunsi_operator_approvals o JOIN app.admin_users a ON a.id=o.admin_user_id WHERE o.collection_id=p_collection;
 SELECT coalesce(jsonb_agg(jsonb_build_object('adminId',a.id,'principalId',u.id,'email',a.email,'displayName',a.display_name,'role',a.role) ORDER BY a.email),'[]'::jsonb)
 INTO team FROM app.admin_users a JOIN app.admin_principal_links l ON l.admin_user_id=a.id JOIN app.users u ON u.id=l.user_id
  JOIN private.auth_principal_links p ON p.user_id=u.id JOIN auth.users actual ON actual.id=p.auth_user_id
 WHERE a.status='active' AND u.access_status='active' AND actual.email_confirmed_at IS NOT NULL
  AND lower(actual.email)=lower(a.email) AND actual.deleted_at IS NULL AND (actual.banned_until IS NULL OR actual.banned_until<=clock_timestamp());
 RETURN jsonb_build_object('contractVersion',1,'collectionId',p_collection,
  'configured',EXISTS(SELECT 1 FROM private.burimunsi_scopes WHERE collection_id=p_collection),
  'approvals',approvals,'team',team);
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_operator_directory(text,text,text,text,text,uuid) FROM PUBLIC,anon,authenticated,service_role,collect_importer;
GRANT EXECUTE ON FUNCTION private.burimunsi_operator_directory(text,text,text,text,text,uuid) TO collect_runtime;

-- Every new mutable table participates in the SAME Collect application fence.
-- No new role, unmanaged actor, application fence or financial writer is added.
DO $fence$
DECLARE t text;
BEGIN
 FOREACH t IN ARRAY ARRAY['burimunsi_scopes','burimunsi_accounts','burimunsi_device_grants','burimunsi_device_accounts',
  'burimunsi_sessions','burimunsi_rate_limits','burimunsi_command_receipts','burimunsi_audit','burimunsi_transaction_scopes',
  'burimunsi_receipt_jobs','burimunsi_rematch_jobs','burimunsi_session_links','burimunsi_integration_policies',
  'burimunsi_identity_proofs','burimunsi_worker_grants','burimunsi_schedulers','burimunsi_operator_approvals','burimunsi_owner_commands'] LOOP
  EXECUTE format('REVOKE ALL ON private.%I FROM PUBLIC,anon,authenticated,service_role,collect_importer',t);
  -- Definer helpers also work when the installation owner is NOBYPASSRLS.
  -- This is the existing owner role, with the same server-selected scope;
  -- collect_runtime cannot assume it or write the owner-only approval tables.
  EXECUTE format('CREATE POLICY burimunsi_scoped_owner ON private.%I TO postgres USING(collection_id=current_setting(''burimunsi.collection_id'',true)) WITH CHECK(collection_id=current_setting(''burimunsi.collection_id'',true))',t);
  EXECUTE format('CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.%I FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()',t);
  EXECUTE format('ALTER TABLE private.%I ENABLE ALWAYS TRIGGER collect_fence_statement_v1',t);
 END LOOP;
END;$fence$;
COMMIT;
