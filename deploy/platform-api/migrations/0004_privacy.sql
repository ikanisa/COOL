CREATE TABLE privacy_submissions (
 submission_id TEXT PRIMARY KEY, request_id TEXT NOT NULL REFERENCES deletion_requests(id),
 user_id TEXT NOT NULL REFERENCES users(id), originating_session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 input_sha256 TEXT NOT NULL CHECK(length(input_sha256)=64), created_at TEXT NOT NULL
);
CREATE INDEX privacy_submission_request ON privacy_submissions(request_id);
CREATE TRIGGER privacy_submission_admission BEFORE INSERT ON privacy_submissions BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM deletion_requests r WHERE r.id=NEW.request_id AND r.user_id=NEW.user_id)
 THEN RAISE(ABORT,'privacy_request_conflict') END);
 SELECT (CASE WHEN (SELECT count(*) FROM privacy_submissions WHERE request_id=NEW.request_id)>=32
 THEN RAISE(ABORT,'privacy_request_submission_limit') END);
END;
CREATE TRIGGER privacy_submissions_no_update BEFORE UPDATE ON privacy_submissions
 BEGIN SELECT RAISE(ABORT,'immutable_privacy_submission'); END;
CREATE TRIGGER privacy_submissions_no_delete BEFORE DELETE ON privacy_submissions
 BEGIN SELECT RAISE(ABORT,'retain_privacy_submission'); END;
CREATE TRIGGER privacy_intake_no_update BEFORE UPDATE ON deletion_requests
 BEGIN SELECT RAISE(ABORT,'immutable_privacy_intake'); END;
CREATE TRIGGER privacy_intake_no_delete BEFORE DELETE ON deletion_requests
 BEGIN SELECT RAISE(ABORT,'retain_privacy_intake'); END;
CREATE TRIGGER privacy_intake_no_erasure BEFORE INSERT ON deletion_requests WHEN NEW.status!='received'
 BEGIN SELECT RAISE(ABORT,'privacy_policy_authority_unavailable'); END;
CREATE TABLE privacy_review_heads (
 request_id TEXT PRIMARY KEY REFERENCES deletion_requests(id),
 revision INTEGER NOT NULL DEFAULT 0 CHECK(revision BETWEEN 0 AND 1000000000),
 fence INTEGER NOT NULL DEFAULT 0 CHECK(fence BETWEEN 0 AND 1000000000),
 state TEXT NOT NULL DEFAULT 'awaiting_review' CHECK(state IN ('awaiting_review','claim_active','blocked')),
 latest_claim_id TEXT REFERENCES privacy_review_claims(claim_id), last_outcome_id TEXT REFERENCES privacy_review_outcomes(outcome_request_id),
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
 CHECK((state='awaiting_review' AND revision=0 AND fence=0 AND latest_claim_id IS NULL AND last_outcome_id IS NULL)
 OR (state='claim_active' AND revision>0 AND fence>0 AND latest_claim_id IS NOT NULL AND last_outcome_id IS NULL)
 OR (state='blocked' AND revision>=2 AND fence>0 AND latest_claim_id IS NOT NULL AND last_outcome_id IS NOT NULL))
);
CREATE TABLE privacy_review_claims (
 claim_id TEXT PRIMARY KEY, claim_request_id TEXT NOT NULL UNIQUE, request_id TEXT NOT NULL REFERENCES deletion_requests(id),
 actor_id TEXT NOT NULL REFERENCES users(id), originating_session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 expected_revision INTEGER NOT NULL CHECK(expected_revision BETWEEN 0 AND 999999998),
 revision INTEGER NOT NULL CHECK(revision=expected_revision+1), fence INTEGER NOT NULL CHECK(fence BETWEEN 1 AND 1000000000),
 lease_seconds INTEGER NOT NULL CHECK(lease_seconds BETWEEN 1 AND 120), claimed_at TEXT NOT NULL, expires_at TEXT NOT NULL CHECK(expires_at>claimed_at)
);
CREATE INDEX privacy_claim_request ON privacy_review_claims(request_id);
CREATE TABLE privacy_review_outcomes (
 outcome_request_id TEXT PRIMARY KEY, request_id TEXT NOT NULL REFERENCES deletion_requests(id),
 claim_id TEXT NOT NULL UNIQUE REFERENCES privacy_review_claims(claim_id), actor_id TEXT NOT NULL REFERENCES users(id),
 originating_session_id TEXT NOT NULL REFERENCES auth_sessions(id), fence INTEGER NOT NULL CHECK(fence>0),
 revision INTEGER NOT NULL CHECK(revision BETWEEN 2 AND 1000000000),
 outcome_code TEXT NOT NULL CHECK(outcome_code='policy_authority_unavailable'), recorded_at TEXT NOT NULL
);
CREATE TRIGGER privacy_claim_binding BEFORE INSERT ON privacy_review_claims BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM privacy_review_heads h WHERE h.request_id=NEW.request_id
  AND h.revision=NEW.expected_revision AND h.fence=NEW.fence-1 AND h.state!='blocked'
  AND (h.latest_claim_id IS NULL OR EXISTS(SELECT 1 FROM privacy_review_claims old
    WHERE old.claim_id=h.latest_claim_id AND old.expires_at<=NEW.claimed_at)))
 THEN RAISE(ABORT,'privacy_review_source_changed') END);
 SELECT (CASE WHEN (SELECT count(*) FROM privacy_review_claims WHERE request_id=NEW.request_id)>=32
 THEN RAISE(ABORT,'privacy_review_claim_limit') END);
END;
CREATE TRIGGER privacy_outcome_binding BEFORE INSERT ON privacy_review_outcomes BEGIN
 SELECT (CASE WHEN NOT EXISTS(SELECT 1 FROM privacy_review_claims c JOIN privacy_review_heads h ON h.request_id=c.request_id
  WHERE c.claim_id=NEW.claim_id AND c.request_id=NEW.request_id AND c.actor_id=NEW.actor_id AND c.originating_session_id=NEW.originating_session_id
   AND c.fence=NEW.fence AND c.fence=h.fence AND h.state='claim_active' AND h.latest_claim_id=c.claim_id
   AND h.revision=c.revision AND NEW.revision=h.revision+1 AND c.claimed_at<=NEW.recorded_at AND c.expires_at>NEW.recorded_at)
 THEN RAISE(ABORT,'privacy_review_claim_stale') END);
END;
CREATE TRIGGER privacy_review_head_binding BEFORE UPDATE ON privacy_review_heads BEGIN
 SELECT (CASE WHEN NEW.request_id IS NOT OLD.request_id OR NEW.created_at IS NOT OLD.created_at OR NEW.updated_at<OLD.updated_at OR OLD.state='blocked'
 THEN RAISE(ABORT,'immutable_privacy_review_head') END);
 SELECT (CASE WHEN NOT ((NEW.state='claim_active' AND NEW.revision=OLD.revision+1 AND NEW.fence=OLD.fence+1 AND NEW.last_outcome_id IS NULL
  AND EXISTS(SELECT 1 FROM privacy_review_claims c WHERE c.claim_id=NEW.latest_claim_id AND c.request_id=NEW.request_id
   AND c.expected_revision=OLD.revision AND c.revision=NEW.revision AND c.fence=NEW.fence AND c.claimed_at=NEW.updated_at))
 OR (NEW.state='blocked' AND OLD.state='claim_active' AND NEW.revision=OLD.revision+1 AND NEW.fence=OLD.fence AND NEW.latest_claim_id=OLD.latest_claim_id
  AND EXISTS(SELECT 1 FROM privacy_review_outcomes o WHERE o.outcome_request_id=NEW.last_outcome_id AND o.request_id=NEW.request_id
   AND o.claim_id=NEW.latest_claim_id AND o.revision=NEW.revision AND o.fence=NEW.fence AND o.recorded_at=NEW.updated_at)))
 THEN RAISE(ABORT,'privacy_review_revision_invalid') END);
END;
CREATE TRIGGER privacy_review_head_no_delete BEFORE DELETE ON privacy_review_heads
 BEGIN SELECT RAISE(ABORT,'retain_privacy_review_head'); END;
CREATE TRIGGER privacy_claim_no_update BEFORE UPDATE ON privacy_review_claims
 BEGIN SELECT RAISE(ABORT,'immutable_privacy_review_claim'); END;
CREATE TRIGGER privacy_claim_no_delete BEFORE DELETE ON privacy_review_claims
 BEGIN SELECT RAISE(ABORT,'retain_privacy_review_claim'); END;
CREATE TRIGGER privacy_outcome_no_update BEFORE UPDATE ON privacy_review_outcomes
 BEGIN SELECT RAISE(ABORT,'immutable_privacy_review_outcome'); END;
CREATE TRIGGER privacy_outcome_no_delete BEFORE DELETE ON privacy_review_outcomes
 BEGIN SELECT RAISE(ABORT,'retain_privacy_review_outcome'); END;
