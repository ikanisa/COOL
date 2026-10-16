-- Signed observations only: no outbound SMS grant, dispatch or carrier proof.
PRAGMA foreign_keys=ON;
CREATE TABLE collect_gateway_devices (
 id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36),label TEXT NOT NULL CHECK(length(trim(label)) BETWEEN 2 AND 120),
 app_id TEXT NOT NULL CHECK(length(app_id) BETWEEN 3 AND 160),installation_id TEXT NOT NULL UNIQUE CHECK(length(installation_id)=36),
 public_key_spki_base64 TEXT NOT NULL CHECK(length(public_key_spki_base64)=124),
 key_sha256 TEXT NOT NULL UNIQUE CHECK(length(key_sha256)=64 AND key_sha256 NOT GLOB '*[^a-f0-9]*'),
 signing_certificate_sha256 TEXT NOT NULL CHECK(length(signing_certificate_sha256)=64 AND signing_certificate_sha256 NOT GLOB '*[^a-f0-9]*'),
 state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','active','revoked')),
 version INTEGER NOT NULL DEFAULT 1 CHECK(version BETWEEN 1 AND 9007199254740991),
 created_by_admin_id TEXT NOT NULL REFERENCES admin_users(id),created_at INTEGER NOT NULL CHECK(created_at>0),
 activated_by_admin_id TEXT REFERENCES admin_users(id),activated_at INTEGER,
 revoked_by_admin_id TEXT REFERENCES admin_users(id),revoked_at INTEGER,
 CHECK((activated_at IS NULL AND activated_by_admin_id IS NULL) OR (activated_at IS NOT NULL AND activated_at>=created_at AND activated_by_admin_id IS NOT NULL)),
 CHECK((state!='revoked' AND revoked_at IS NULL AND revoked_by_admin_id IS NULL) OR (state='revoked' AND revoked_at IS NOT NULL AND revoked_at>=created_at AND revoked_by_admin_id IS NOT NULL)),
 CHECK(state!='active' OR activated_at IS NOT NULL),CHECK(state!='pending' OR activated_at IS NULL)
) STRICT;
CREATE TRIGGER collect_gateway_device_insert_pending BEFORE INSERT ON collect_gateway_devices
WHEN NEW.state!='pending' OR NEW.version!=1 OR NEW.activated_at IS NOT NULL OR NEW.revoked_at IS NOT NULL
BEGIN SELECT RAISE(ABORT,'Enroll a pending gateway before activation'); END;
CREATE TRIGGER collect_gateway_device_identity BEFORE UPDATE ON collect_gateway_devices
BEGIN
 SELECT (CASE WHEN NEW.id IS NOT OLD.id OR NEW.label IS NOT OLD.label OR NEW.app_id IS NOT OLD.app_id
  OR NEW.installation_id IS NOT OLD.installation_id OR NEW.public_key_spki_base64 IS NOT OLD.public_key_spki_base64
  OR NEW.key_sha256 IS NOT OLD.key_sha256 OR NEW.signing_certificate_sha256 IS NOT OLD.signing_certificate_sha256
  OR NEW.created_by_admin_id IS NOT OLD.created_by_admin_id OR NEW.created_at IS NOT OLD.created_at
  THEN RAISE(ABORT,'Gateway enrollment identity is immutable') END);
 SELECT (CASE WHEN NEW.version!=OLD.version+1 OR NOT ((OLD.state='pending' AND NEW.state IN ('active','revoked')) OR (OLD.state='active' AND NEW.state='revoked'))
  THEN RAISE(ABORT,'Gateway state transition is invalid') END);
 SELECT (CASE WHEN OLD.state='active' AND (NEW.activated_at IS NOT OLD.activated_at OR NEW.activated_by_admin_id IS NOT OLD.activated_by_admin_id)
  THEN RAISE(ABORT,'Gateway activation evidence is immutable') END);
END;
CREATE TRIGGER collect_gateway_device_no_delete BEFORE DELETE ON collect_gateway_devices
BEGIN SELECT RAISE(ABORT,'Gateway identity must be revoked, not deleted'); END;

CREATE TABLE collect_gateway_heartbeats (
 id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36),device_id TEXT NOT NULL REFERENCES collect_gateway_devices(id),
 request_id TEXT NOT NULL CHECK(length(request_id)=36),request_sha256 TEXT NOT NULL CHECK(length(request_sha256)=64 AND request_sha256 NOT GLOB '*[^a-f0-9]*'),
 issued_at TEXT NOT NULL,reported_at TEXT NOT NULL,observations_json TEXT NOT NULL CHECK(json_valid(observations_json)),
 ingested_at INTEGER NOT NULL CHECK(ingested_at>0),carrier_proof INTEGER NOT NULL DEFAULT 0 CHECK(carrier_proof=0),
 UNIQUE(device_id,request_id)
) STRICT;
CREATE INDEX collect_gateway_heartbeat_device ON collect_gateway_heartbeats(device_id,ingested_at,id);
CREATE TRIGGER collect_gateway_heartbeat_no_update BEFORE UPDATE ON collect_gateway_heartbeats
BEGIN SELECT RAISE(ABORT,'Gateway observations are append-only'); END;
CREATE TRIGGER collect_gateway_heartbeat_no_delete BEFORE DELETE ON collect_gateway_heartbeats
BEGIN SELECT RAISE(ABORT,'Gateway replay evidence cannot be deleted'); END;

ALTER TABLE member_receipt_submissions ADD COLUMN version INTEGER NOT NULL DEFAULT 1 CHECK(version BETWEEN 1 AND 9007199254740991);
CREATE TABLE collect_member_receipt_reviews (
 id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36),submission_id TEXT NOT NULL UNIQUE REFERENCES member_receipt_submissions(id),
 outcome TEXT NOT NULL CHECK(outcome IN ('reviewed','rejected')),
 transaction_id TEXT REFERENCES collect_transactions(id),evidence_id TEXT REFERENCES collect_transaction_evidence(id),
 actor_admin_id TEXT NOT NULL REFERENCES admin_users(id),operation_request_id TEXT NOT NULL UNIQUE REFERENCES collect_operation_requests(id),
 reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 8 AND 1000),reviewed_at INTEGER NOT NULL CHECK(reviewed_at>0),
 CHECK((transaction_id IS NULL AND evidence_id IS NULL) OR (outcome='reviewed' AND transaction_id IS NOT NULL AND evidence_id IS NOT NULL)),
 FOREIGN KEY(evidence_id,transaction_id) REFERENCES collect_transaction_evidence(id,transaction_id)
) STRICT;
CREATE TRIGGER collect_member_receipt_review_source BEFORE INSERT ON collect_member_receipt_reviews
WHEN NEW.transaction_id IS NOT NULL
BEGIN
 SELECT (CASE WHEN (SELECT kind FROM collect_transaction_evidence WHERE id=NEW.evidence_id)!='payer_receipt'
  OR (SELECT verification_status FROM collect_transactions WHERE id=NEW.transaction_id)!='pending'
  THEN RAISE(ABORT,'Member receipts can only attach pending payer evidence') END);
END;
CREATE TRIGGER collect_member_receipt_review_no_update BEFORE UPDATE ON collect_member_receipt_reviews
BEGIN SELECT RAISE(ABORT,'Member receipt review evidence is append-only'); END;
CREATE TRIGGER collect_member_receipt_review_no_delete BEFORE DELETE ON collect_member_receipt_reviews
BEGIN SELECT RAISE(ABORT,'Member receipt review evidence is append-only'); END;
CREATE TRIGGER collect_member_receipt_review_state BEFORE UPDATE OF status,version ON member_receipt_submissions
WHEN NEW.status IS NOT OLD.status OR NEW.version IS NOT OLD.version
BEGIN
 SELECT (CASE WHEN OLD.status!='needs_review' OR NEW.version!=OLD.version+1 OR NOT EXISTS(
  SELECT 1 FROM collect_member_receipt_reviews r WHERE r.submission_id=OLD.id AND r.outcome=NEW.status)
  THEN RAISE(ABORT,'Receipt state requires its immutable review record') END);
END;
