-- Additive operational scheduling only; not an applied migration.
-- Requires schema-proposal.sql and current Collect tables/guards reconciled in staging.
-- No member identity, raw SMS, balance, second ledger, or processing approval is created.
BEGIN;
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
COMMIT;
