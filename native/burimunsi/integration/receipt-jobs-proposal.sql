-- Additive operational queue; NOT an automatically applied migration.
-- Requires reconciled schema-proposal.sql and actual Collect app tables/roles.
-- No raw SMS, PIN, phone, balance or duplicate ledger is stored here.
BEGIN;
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
COMMIT;
