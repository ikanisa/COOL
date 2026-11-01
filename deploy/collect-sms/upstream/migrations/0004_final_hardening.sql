-- Additive final-source hardening. Does not erase or replay existing jobs.
CREATE TRIGGER ledger_no_recipient_after_redaction BEFORE INSERT ON ledger_notification_receipts
WHEN EXISTS(SELECT 1 FROM ledger_notification_events e WHERE e.application_id=NEW.application_id
 AND e.event_id=NEW.event_id AND e.redacted_at IS NOT NULL)
 AND NOT EXISTS(SELECT 1 FROM ledger_notification_receipts r WHERE r.application_id=NEW.application_id
 AND r.event_id=NEW.event_id AND r.recipient=NEW.recipient)
BEGIN SELECT RAISE(ABORT,'source_facts_redacted'); END;
CREATE TRIGGER ledger_identity_immutable BEFORE UPDATE ON ledger_notification_events
WHEN NEW.application_id<>OLD.application_id OR NEW.event_id<>OLD.event_id OR NEW.created_at<>OLD.created_at
BEGIN SELECT RAISE(ABORT,'ledger_snapshot_immutable'); END;
CREATE INDEX ledger_receipt_reference ON ledger_notification_receipts(event_id,message_id);
CREATE TABLE application_outbox_health(
 application_id TEXT PRIMARY KEY REFERENCES applications(application_id),
 sampled_at TEXT NOT NULL,received_at TEXT NOT NULL,
 pending_count INTEGER NOT NULL CHECK(pending_count BETWEEN 0 AND 1000000000),
 failed_count INTEGER NOT NULL CHECK(failed_count BETWEEN 0 AND 1000000000),
 oldest_pending_at TEXT,
 CHECK((pending_count=0 AND oldest_pending_at IS NULL) OR (pending_count>0 AND oldest_pending_at IS NOT NULL))
);
