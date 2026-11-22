CREATE TABLE admin_operator_notes (
 id TEXT PRIMARY KEY,
 entity_type TEXT NOT NULL CHECK(entity_type IN ('collection','profile')),
 entity_id TEXT NOT NULL,
 body_ciphertext TEXT NOT NULL,
 body_sha256 TEXT NOT NULL CHECK(length(body_sha256)=64),
 created_by TEXT NOT NULL REFERENCES users(id),
 session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 created_at TEXT NOT NULL
) STRICT;
CREATE INDEX admin_operator_notes_entity ON admin_operator_notes(entity_type,entity_id,created_at,id);
CREATE TRIGGER admin_operator_note_target BEFORE INSERT ON admin_operator_notes BEGIN
 SELECT (CASE WHEN (NEW.entity_type='collection' AND NOT EXISTS(SELECT 1 FROM collections WHERE id=NEW.entity_id))
 OR (NEW.entity_type='profile' AND NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.entity_id))
 THEN RAISE(ABORT,'operator_note_target_unavailable') END);
END;
