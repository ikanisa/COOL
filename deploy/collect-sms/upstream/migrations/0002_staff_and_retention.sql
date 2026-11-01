-- Additive upgrade; apply after 0001. Never recreate existing message tables.
CREATE TABLE staff_accounts (
 staff_id TEXT PRIMARY KEY,name TEXT NOT NULL,
 role TEXT NOT NULL CHECK(role IN('administrator','operator','viewer')),
 key_hash TEXT NOT NULL UNIQUE,key_expires_at TEXT NOT NULL,
 generation INTEGER NOT NULL DEFAULT 1 CHECK(generation>0),
 created_at TEXT NOT NULL,updated_at TEXT NOT NULL,revoked_at TEXT
);
CREATE TABLE staff_sessions (
 session_id TEXT PRIMARY KEY,staff_id TEXT NOT NULL REFERENCES staff_accounts(staff_id),
 token_hash TEXT NOT NULL UNIQUE,generation INTEGER NOT NULL,
 created_at TEXT NOT NULL,expires_at TEXT NOT NULL,revoked_at TEXT
);
CREATE INDEX staff_sessions_owner ON staff_sessions(staff_id,expires_at);
ALTER TABLE messages ADD COLUMN content_redacted_at TEXT;
ALTER TABLE messages ADD COLUMN content_hold INTEGER NOT NULL DEFAULT 0 CHECK(content_hold IN(0,1));
ALTER TABLE campaigns ADD COLUMN content_redacted_at TEXT;
ALTER TABLE campaigns ADD COLUMN content_hold INTEGER NOT NULL DEFAULT 0 CHECK(content_hold IN(0,1));
ALTER TABLE contribution_events ADD COLUMN content_redacted_at TEXT;
ALTER TABLE device_events ADD COLUMN detail_redacted_at TEXT;
CREATE INDEX messages_retention ON messages(content_redacted_at,state,not_after,updated_at);
CREATE INDEX campaigns_retention ON campaigns(content_redacted_at,status,not_after);
-- Retained identities/digests prevent redacted content being re-created on replay.
CREATE TRIGGER message_no_rehydration BEFORE UPDATE ON messages
WHEN OLD.content_redacted_at IS NOT NULL AND (
 NEW.text<>OLD.text OR NEW.metadata_json<>OLD.metadata_json OR
 NEW.payload_digest<>OLD.payload_digest OR NEW.request_digest<>OLD.request_digest OR
 NEW.content_redacted_at IS NULL OR NEW.message_id<>OLD.message_id OR
 NEW.application_id<>OLD.application_id OR NEW.idempotency_key<>OLD.idempotency_key)
BEGIN SELECT RAISE(ABORT,'event_content_redacted'); END;
CREATE TRIGGER campaign_no_rehydration BEFORE UPDATE ON campaigns
WHEN OLD.content_redacted_at IS NOT NULL AND (
 NEW.text<>OLD.text OR NEW.recipients_json<>OLD.recipients_json OR
 NEW.request_digest<>OLD.request_digest OR NEW.request_key<>OLD.request_key OR
 NEW.content_redacted_at IS NULL OR NEW.campaign_id<>OLD.campaign_id OR NEW.application_id<>OLD.application_id OR
 NEW.status IN('draft','running','paused'))
BEGIN SELECT RAISE(ABORT,'event_content_redacted'); END;
DROP TRIGGER contribution_immutable;
CREATE TRIGGER contribution_immutable BEFORE UPDATE ON contribution_events
WHEN NEW.application_id<>OLD.application_id OR NEW.event_id<>OLD.event_id OR
 NEW.facts_digest<>OLD.facts_digest OR NEW.created_at<>OLD.created_at OR
 (OLD.content_redacted_at IS NOT NULL AND (NEW.facts_json<>OLD.facts_json OR NEW.content_redacted_at IS NULL)) OR
 (OLD.content_redacted_at IS NULL AND NEW.facts_json<>OLD.facts_json AND NOT(NEW.facts_json='{}' AND NEW.content_redacted_at IS NOT NULL))
BEGIN SELECT RAISE(ABORT,'event_immutable'); END;
-- Reduce new late callback details after content redaction, retaining the phase
-- used by event_apply, but never resetting its digest, owner or per-part evidence.
CREATE TRIGGER late_event_detail_redaction AFTER INSERT ON device_events
WHEN EXISTS(SELECT 1 FROM messages WHERE message_id=NEW.message_id AND content_redacted_at IS NOT NULL)
BEGIN
 UPDATE device_events SET detail_json=CASE WHEN json_extract(detail_json,'$.phase')='delivery' THEN '{"phase":"delivery"}' ELSE '{}' END,
 detail_redacted_at=NEW.received_at WHERE event_id=NEW.event_id;
END;
