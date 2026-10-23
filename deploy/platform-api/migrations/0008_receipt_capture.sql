-- Additive migration after the five verified fresh platform migrations.
ALTER TABLE payment_evidence ADD COLUMN receiver_network TEXT;
ALTER TABLE payment_evidence ADD COLUMN receiver_display_label TEXT;
CREATE TRIGGER evidence_route_snapshot_immutable BEFORE UPDATE OF receiver_network,receiver_display_label ON payment_evidence BEGIN SELECT RAISE(ABORT,'immutable_evidence'); END;
ALTER TABLE mutation_guards ADD COLUMN target_collection_id TEXT;
ALTER TABLE mutation_guards ADD COLUMN expected_target_collection_revision INTEGER;
CREATE TRIGGER mutation_target_collection BEFORE INSERT ON mutation_guards BEGIN
 SELECT (CASE WHEN NEW.target_collection_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM collections c WHERE c.id=NEW.target_collection_id AND c.status='active' AND (NEW.expected_target_collection_revision IS NULL OR c.revision=NEW.expected_target_collection_revision)) THEN RAISE(ABORT,'stale_collection') END);
END;
CREATE TABLE sms_receipts (
 id TEXT PRIMARY KEY NOT NULL,owner_user_id TEXT NOT NULL REFERENCES users(id),originating_session_id TEXT NOT NULL REFERENCES auth_sessions(id),
 client_envelope_id TEXT NOT NULL,body_sha256 TEXT NOT NULL CHECK(length(body_sha256)=64),
 receiver_hash TEXT NOT NULL CHECK(length(receiver_hash)=64),object_key TEXT NOT NULL UNIQUE,object_sha256 TEXT NOT NULL CHECK(length(object_sha256)=64),
 size_bytes INTEGER NOT NULL CHECK(size_bytes BETWEEN 1 AND 131072),received_at_device TEXT,
 status TEXT NOT NULL DEFAULT 'received' CHECK(status IN('received','under_review','rejected','linked')),
 evidence_level TEXT NOT NULL DEFAULT 'client_received' CHECK(evidence_level='client_received'),created_at TEXT NOT NULL,
 UNIQUE(owner_user_id,client_envelope_id)
) STRICT;
CREATE TRIGGER sms_receipt_source_immutable BEFORE UPDATE OF id,owner_user_id,originating_session_id,client_envelope_id,body_sha256,receiver_hash,object_key,object_sha256,size_bytes,received_at_device,evidence_level,created_at ON sms_receipts BEGIN SELECT RAISE(ABORT,'immutable_sms_source'); END;
CREATE TRIGGER sms_receipt_retain BEFORE DELETE ON sms_receipts BEGIN SELECT RAISE(ABORT,'retain_receipt_until_approved_privacy_disposition'); END;
