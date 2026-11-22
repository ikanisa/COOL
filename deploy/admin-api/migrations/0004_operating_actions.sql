-- Native operating actions. Existing migrations and source evidence stay intact.
PRAGMA foreign_keys=ON;

ALTER TABLE collect_groups ADD COLUMN version INTEGER NOT NULL DEFAULT 1 CHECK(version>=1 AND version<=9007199254740991);
ALTER TABLE collect_users ADD COLUMN version INTEGER NOT NULL DEFAULT 1 CHECK(version>=1 AND version<=9007199254740991);
ALTER TABLE collect_memberships ADD COLUMN version INTEGER NOT NULL DEFAULT 1 CHECK(version>=1 AND version<=9007199254740991);
ALTER TABLE collect_payees ADD COLUMN version INTEGER NOT NULL DEFAULT 1 CHECK(version>=1 AND version<=9007199254740991);
ALTER TABLE collect_transactions ADD COLUMN version INTEGER NOT NULL DEFAULT 1 CHECK(version>=1 AND version<=9007199254740991);
ALTER TABLE collect_ledger_accounts ADD COLUMN version INTEGER NOT NULL DEFAULT 1 CHECK(version>=1 AND version<=9007199254740991);
ALTER TABLE collect_journals ADD COLUMN version INTEGER NOT NULL DEFAULT 1 CHECK(version>=1 AND version<=9007199254740991);
ALTER TABLE collect_transactions ADD COLUMN recorded_by_admin_id TEXT REFERENCES admin_users(id) ON DELETE RESTRICT;
ALTER TABLE collect_journals ADD COLUMN edited_by_admin_id TEXT REFERENCES admin_users(id) ON DELETE RESTRICT;

CREATE TRIGGER collect_transaction_insert_pending BEFORE INSERT ON collect_transactions
WHEN NEW.verification_status!='pending'
BEGIN SELECT RAISE(ABORT,'New transactions require recorded evidence and independent review'); END;

-- One caller key identifies one request across every operating endpoint.
CREATE UNIQUE INDEX collect_operation_actor_key ON collect_operation_requests(actor_admin_id,idempotency_key);

-- Each batch inserts assertions and deletes them before commit. A false check
-- aborts the entire D1 transaction; no domain mutation can survive the failure.
CREATE TABLE collect_mutation_guards (
  id TEXT PRIMARY KEY NOT NULL,
  passed INTEGER NOT NULL CONSTRAINT collect_operation_guard_failed CHECK(passed=1)
) STRICT;

CREATE TABLE collect_transaction_evidence (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36),
  transaction_id TEXT NOT NULL REFERENCES collect_transactions(id) ON DELETE RESTRICT,
  kind TEXT NOT NULL CHECK(kind IN ('operator_observation','payer_receipt','receiver_statement','provider_statement')),
  reference TEXT NOT NULL CHECK(length(trim(reference)) BETWEEN 8 AND 500),
  artifact_sha256 TEXT NOT NULL CHECK(length(artifact_sha256)=64 AND artifact_sha256 NOT GLOB '*[^a-f0-9]*'),
  recorded_by_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
  operation_request_id TEXT NOT NULL UNIQUE REFERENCES collect_operation_requests(id) ON DELETE RESTRICT,
  recorded_at INTEGER NOT NULL CHECK(recorded_at>0),
  UNIQUE(id,transaction_id),
  UNIQUE(transaction_id,kind,artifact_sha256)
) STRICT;
CREATE TRIGGER collect_transaction_evidence_no_update BEFORE UPDATE ON collect_transaction_evidence
BEGIN SELECT RAISE(ABORT,'Transaction evidence is append-only'); END;
CREATE TRIGGER collect_transaction_evidence_no_delete BEFORE DELETE ON collect_transaction_evidence
BEGIN SELECT RAISE(ABORT,'Transaction evidence is append-only'); END;

CREATE TABLE collect_transaction_reviews (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36),
  transaction_id TEXT NOT NULL REFERENCES collect_transactions(id) ON DELETE RESTRICT,
  evidence_id TEXT NOT NULL,
  outcome TEXT NOT NULL CHECK(outcome IN ('confirmation_recorded','rejection_recorded','evidence_conflict')),
  transaction_version INTEGER NOT NULL CHECK(transaction_version>1),
  reviewed_by_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
  operation_request_id TEXT NOT NULL UNIQUE REFERENCES collect_operation_requests(id) ON DELETE RESTRICT,
  reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 8 AND 1000),
  reviewed_at INTEGER NOT NULL CHECK(reviewed_at>0),
  FOREIGN KEY(evidence_id,transaction_id) REFERENCES collect_transaction_evidence(id,transaction_id) ON DELETE RESTRICT,
  UNIQUE(transaction_id,transaction_version)
) STRICT;
CREATE TRIGGER collect_transaction_review_independent BEFORE INSERT ON collect_transaction_reviews
BEGIN
  SELECT (CASE WHEN NEW.reviewed_by_admin_id=(SELECT recorded_by_admin_id FROM collect_transaction_evidence WHERE id=NEW.evidence_id)
    THEN RAISE(ABORT,'Evidence requires an independent reviewer') END);
  SELECT (CASE WHEN NEW.outcome='confirmation_recorded' AND
    (NEW.reviewed_by_admin_id IS (SELECT recorded_by_admin_id FROM collect_transactions WHERE id=NEW.transaction_id)
      OR (SELECT kind FROM collect_transaction_evidence WHERE id=NEW.evidence_id) NOT IN ('receiver_statement','provider_statement'))
    THEN RAISE(ABORT,'Confirmation requires independent receiver or provider evidence review') END);
END;
CREATE TRIGGER collect_transaction_reviews_no_update BEFORE UPDATE ON collect_transaction_reviews
BEGIN SELECT RAISE(ABORT,'Transaction review history is append-only'); END;
CREATE TRIGGER collect_transaction_reviews_no_delete BEFORE DELETE ON collect_transaction_reviews
BEGIN SELECT RAISE(ABORT,'Transaction review history is append-only'); END;
CREATE TRIGGER collect_transaction_review_required BEFORE UPDATE OF verification_status,verified_by_admin_id,verified_at ON collect_transactions
WHEN NEW.verification_status IS NOT OLD.verification_status OR NEW.verified_by_admin_id IS NOT OLD.verified_by_admin_id OR NEW.verified_at IS NOT OLD.verified_at
BEGIN
  SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM collect_transaction_reviews r WHERE r.transaction_id=NEW.id
    AND r.transaction_version=NEW.version AND r.outcome=NEW.verification_status
    AND r.reviewed_by_admin_id=NEW.verified_by_admin_id AND r.reviewed_at=NEW.verified_at)
    THEN RAISE(ABORT,'Verification requires its immutable review record') END);
END;
CREATE TRIGGER collect_transaction_recorder_immutable BEFORE UPDATE OF recorded_by_admin_id ON collect_transactions
WHEN NEW.recorded_by_admin_id IS NOT OLD.recorded_by_admin_id
BEGIN SELECT RAISE(ABORT,'Transaction recorder is immutable'); END;

CREATE TRIGGER collect_journal_independent_post BEFORE UPDATE OF status ON collect_journals
WHEN NEW.status='posted' AND (NEW.posted_by_admin_id=OLD.created_by_admin_id OR NEW.posted_by_admin_id=OLD.edited_by_admin_id)
BEGIN SELECT RAISE(ABORT,'Posting requires a different administrator from the draft creator and editor'); END;
