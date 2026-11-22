PRAGMA foreign_keys = ON;
CREATE TABLE applications (
 application_id TEXT PRIMARY KEY,name TEXT NOT NULL,token_hash TEXT NOT NULL UNIQUE,
 allowed_kinds TEXT NOT NULL CHECK(json_valid(allowed_kinds)),scopes TEXT NOT NULL CHECK(json_valid(scopes)),created_at TEXT NOT NULL,revoked_at TEXT
);
CREATE TABLE devices (
 installation_id TEXT PRIMARY KEY,name TEXT NOT NULL,token_hash TEXT NOT NULL UNIQUE,allowed_kinds TEXT NOT NULL CHECK(json_valid(allowed_kinds)),
 sim_slot INTEGER CHECK(sim_slot IN(0,1)),ready INTEGER NOT NULL DEFAULT 0 CHECK(ready IN(0,1)),revoked_at TEXT,created_at TEXT NOT NULL,last_seen_at TEXT,
 app_version TEXT,os_version TEXT,fcm_token TEXT,fcm_rejected_token_hash TEXT,fcm_pending INTEGER NOT NULL DEFAULT 0,fcm_next_at TEXT,fcm_attempts INTEGER NOT NULL DEFAULT 0,fcm_last_error TEXT,
 wake_revision INTEGER NOT NULL DEFAULT 0,health_json TEXT NOT NULL DEFAULT '{}'
);
CREATE TABLE campaigns (
 campaign_id TEXT PRIMARY KEY,application_id TEXT NOT NULL REFERENCES applications(application_id),name TEXT NOT NULL,text TEXT NOT NULL,
 recipients_json TEXT NOT NULL CHECK(json_valid(recipients_json)),recipient_count INTEGER NOT NULL,expansion_cursor INTEGER NOT NULL DEFAULT 0,
 request_key TEXT NOT NULL,request_digest TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN('draft','running','paused','cancelled','completed')),
 not_after TEXT NOT NULL,scheduled_at TEXT NOT NULL,segments_per_minute INTEGER NOT NULL CHECK(segments_per_minute BETWEEN 1 AND 6000),segments_per_message INTEGER NOT NULL,
 created_at TEXT NOT NULL,updated_at TEXT NOT NULL,UNIQUE(application_id,request_key)
);
CREATE TABLE otp_slots (
 application_id TEXT NOT NULL REFERENCES applications(application_id),phone TEXT NOT NULL,purpose TEXT NOT NULL,generation INTEGER NOT NULL,current_challenge_id TEXT NOT NULL,resend_after TEXT NOT NULL,
 PRIMARY KEY(application_id,phone,purpose)
);
CREATE TABLE otp_challenges (
 challenge_id TEXT PRIMARY KEY,application_id TEXT NOT NULL REFERENCES applications(application_id),phone TEXT NOT NULL,purpose TEXT NOT NULL,generation INTEGER NOT NULL,
 verifier TEXT NOT NULL,expires_at TEXT NOT NULL,remaining_attempts INTEGER NOT NULL CHECK(remaining_attempts BETWEEN 0 AND 5),consumed_at TEXT,created_at TEXT NOT NULL
);
CREATE INDEX otp_binding ON otp_challenges(application_id,phone,purpose);
CREATE INDEX otp_issuance_time ON otp_challenges(application_id,created_at);
CREATE TRIGGER otp_issuance_limits BEFORE INSERT ON otp_challenges
BEGIN
 SELECT RAISE(ABORT,'otp_phone_rate') WHERE (SELECT COUNT(*) FROM otp_challenges WHERE application_id=NEW.application_id AND phone=NEW.phone AND created_at>strftime('%Y-%m-%dT%H:%M:%fZ',NEW.created_at,'-10 minutes'))>=6;
 SELECT RAISE(ABORT,'otp_application_rate') WHERE (SELECT COUNT(*) FROM otp_challenges WHERE application_id=NEW.application_id AND created_at>strftime('%Y-%m-%dT%H:%M:%fZ',NEW.created_at,'-1 minute'))>=120;
END;
CREATE TABLE messages (
 message_id TEXT PRIMARY KEY,application_id TEXT NOT NULL REFERENCES applications(application_id),kind TEXT NOT NULL CHECK(kind IN('otp','receipt','operation','campaign')),
 to_number TEXT NOT NULL,text TEXT NOT NULL,payload_digest TEXT NOT NULL,request_digest TEXT NOT NULL,idempotency_key TEXT NOT NULL,
 priority INTEGER NOT NULL CHECK(priority BETWEEN 0 AND 127),not_after TEXT NOT NULL,available_at TEXT NOT NULL,owner_installation_id TEXT REFERENCES devices(installation_id),assignment_version INTEGER NOT NULL DEFAULT 0,
 state TEXT NOT NULL DEFAULT 'accepted' CHECK(state IN('accepted','assigned','phone_accepted','queued','handoff_started','sent','delivered','delivery_unconfirmed','partial','expired','cancelled','failed','outcome_unknown')),
 cancel_requested INTEGER NOT NULL DEFAULT 0 CHECK(cancel_requested IN(0,1)),created_at TEXT NOT NULL,updated_at TEXT NOT NULL,phone_accepted_at TEXT,
 campaign_id TEXT REFERENCES campaigns(campaign_id),otp_challenge_id TEXT REFERENCES otp_challenges(challenge_id),metadata_json TEXT NOT NULL DEFAULT '{}' CHECK(json_valid(metadata_json)),
 requires_fresh_decision INTEGER NOT NULL DEFAULT 0 CHECK(requires_fresh_decision IN(0,1)),eligibility_until TEXT,segments_estimate INTEGER NOT NULL CHECK(segments_estimate>0),
 unknown_observed INTEGER NOT NULL DEFAULT 0,failure_observed INTEGER NOT NULL DEFAULT 0,UNIQUE(application_id,idempotency_key),
 CHECK((owner_installation_id IS NULL AND assignment_version=0) OR (owner_installation_id IS NOT NULL AND assignment_version>=1))
);
CREATE INDEX messages_pending ON messages(owner_installation_id,state,priority DESC,available_at);
CREATE INDEX messages_application ON messages(application_id,created_at DESC);
CREATE INDEX messages_campaign ON messages(campaign_id,state);
CREATE TABLE contribution_events (
 application_id TEXT NOT NULL REFERENCES applications(application_id),event_id TEXT NOT NULL,facts_json TEXT NOT NULL,facts_digest TEXT NOT NULL,created_at TEXT NOT NULL,PRIMARY KEY(application_id,event_id)
);
CREATE TRIGGER contribution_immutable BEFORE UPDATE ON contribution_events
WHEN NEW.facts_digest<>OLD.facts_digest OR NEW.facts_json<>OLD.facts_json
BEGIN SELECT RAISE(ABORT,'event_immutable'); END;
CREATE TABLE contribution_receipts (
 application_id TEXT NOT NULL,event_id TEXT NOT NULL,recipient TEXT NOT NULL,message_id TEXT NOT NULL UNIQUE REFERENCES messages(message_id),PRIMARY KEY(application_id,event_id,recipient),
 FOREIGN KEY(application_id,event_id) REFERENCES contribution_events(application_id,event_id)
);
CREATE TABLE acceptances (
 message_id TEXT NOT NULL REFERENCES messages(message_id),assignment_version INTEGER NOT NULL,installation_id TEXT NOT NULL REFERENCES devices(installation_id),payload_digest TEXT NOT NULL,accepted_at TEXT NOT NULL,received_at TEXT NOT NULL,
 PRIMARY KEY(message_id,assignment_version)
);
CREATE TRIGGER acceptance_owner BEFORE INSERT ON acceptances
WHEN NOT EXISTS(SELECT 1 FROM messages WHERE message_id=NEW.message_id AND owner_installation_id=NEW.installation_id AND assignment_version=NEW.assignment_version AND payload_digest=NEW.payload_digest)
BEGIN SELECT RAISE(ABORT,'event_wrong_owner_or_digest'); END;
CREATE TRIGGER acceptance_apply AFTER INSERT ON acceptances
BEGIN
 UPDATE messages SET phone_accepted_at=COALESCE(phone_accepted_at,NEW.accepted_at),state=CASE WHEN state IN('accepted','assigned','queued') THEN 'phone_accepted' ELSE state END,updated_at=NEW.received_at WHERE message_id=NEW.message_id;
END;
CREATE TABLE attempts (
 message_id TEXT NOT NULL REFERENCES messages(message_id),attempt_id TEXT NOT NULL,installation_id TEXT NOT NULL REFERENCES devices(installation_id),parts_total INTEGER CHECK(parts_total BETWEEN 1 AND 255),handoff_at TEXT,
 unknown_observed INTEGER NOT NULL DEFAULT 0,failed_observed INTEGER NOT NULL DEFAULT 0,aborted_before_call INTEGER NOT NULL DEFAULT 0,updated_at TEXT NOT NULL,PRIMARY KEY(message_id,attempt_id)
);
CREATE TABLE message_parts (
 message_id TEXT NOT NULL,attempt_id TEXT NOT NULL,part_index INTEGER NOT NULL CHECK(part_index BETWEEN 0 AND 254),sent_at TEXT,delivered_at TEXT,failed_at TEXT,sent_failed_at TEXT,delivery_failed_at TEXT,delivery_unknown_at TEXT,error_code TEXT,
 PRIMARY KEY(message_id,attempt_id,part_index),FOREIGN KEY(message_id,attempt_id) REFERENCES attempts(message_id,attempt_id)
);
CREATE VIEW attempt_evidence AS
SELECT a.*,
 SUM(CASE WHEN p.sent_at IS NOT NULL THEN 1 ELSE 0 END) AS sent_count,
 SUM(CASE WHEN p.delivered_at IS NOT NULL THEN 1 ELSE 0 END) AS delivered_count,
 SUM(CASE WHEN p.sent_failed_at IS NOT NULL AND p.sent_at IS NULL THEN 1 ELSE 0 END) AS send_failure_count,
 SUM(CASE WHEN p.delivery_failed_at IS NOT NULL AND p.delivered_at IS NULL THEN 1 ELSE 0 END) AS delivery_failure_count,
 SUM(CASE WHEN p.delivery_unknown_at IS NOT NULL AND p.delivered_at IS NULL AND p.delivery_failed_at IS NULL THEN 1 ELSE 0 END) AS delivery_unknown_count,
 SUM(CASE WHEN (p.sent_failed_at IS NOT NULL AND p.sent_at IS NULL) OR (p.delivery_failed_at IS NOT NULL AND p.delivered_at IS NULL) THEN 1 ELSE 0 END) AS failure_count
FROM attempts a LEFT JOIN message_parts p ON p.message_id=a.message_id AND p.attempt_id=a.attempt_id GROUP BY a.message_id,a.attempt_id;
CREATE TABLE device_events (
 event_id TEXT PRIMARY KEY,message_id TEXT NOT NULL REFERENCES messages(message_id),installation_id TEXT NOT NULL REFERENCES devices(installation_id),assignment_version INTEGER NOT NULL,attempt_id TEXT,
 type TEXT NOT NULL CHECK(type IN('phone_accepted','handoff_started','part_sent','part_delivered','part_failed','outcome_unknown','expired','cancelled','failed')),at TEXT NOT NULL,received_at TEXT NOT NULL,
 part_index INTEGER,parts_total INTEGER,error_code TEXT,detail_json TEXT NOT NULL,payload_digest TEXT NOT NULL
);
CREATE INDEX device_events_message ON device_events(message_id,received_at);
CREATE TRIGGER event_immutable BEFORE UPDATE ON device_events
WHEN NEW.payload_digest<>OLD.payload_digest
BEGIN SELECT RAISE(ABORT,'event_id_conflict'); END;
CREATE TRIGGER event_owner BEFORE INSERT ON device_events
WHEN NOT EXISTS(SELECT 1 FROM messages WHERE message_id=NEW.message_id AND owner_installation_id=NEW.installation_id AND assignment_version=NEW.assignment_version)
BEGIN SELECT RAISE(ABORT,'event_wrong_owner'); END;
CREATE TRIGGER event_total BEFORE INSERT ON device_events
WHEN NEW.parts_total IS NOT NULL AND (
 EXISTS(SELECT 1 FROM attempts WHERE message_id=NEW.message_id AND attempt_id=NEW.attempt_id AND parts_total IS NOT NULL AND parts_total<>NEW.parts_total)
 OR EXISTS(SELECT 1 FROM message_parts WHERE message_id=NEW.message_id AND attempt_id=NEW.attempt_id AND part_index>=NEW.parts_total))
BEGIN SELECT RAISE(ABORT,'event_part_count_conflict'); END;
CREATE TRIGGER event_part_bounds BEFORE INSERT ON device_events
WHEN NEW.part_index IS NOT NULL AND (NEW.part_index<0 OR NEW.part_index>=255 OR (NEW.parts_total IS NOT NULL AND NEW.part_index>=NEW.parts_total)
 OR EXISTS(SELECT 1 FROM attempts WHERE message_id=NEW.message_id AND attempt_id=NEW.attempt_id AND parts_total IS NOT NULL AND NEW.part_index>=parts_total))
BEGIN SELECT RAISE(ABORT,'event_part_out_of_bounds'); END;
CREATE TRIGGER event_suppression BEFORE INSERT ON device_events
WHEN NOT EXISTS(SELECT 1 FROM device_events WHERE event_id=NEW.event_id) AND NEW.type IN('cancelled','expired') AND (
 EXISTS(SELECT 1 FROM attempts WHERE message_id=NEW.message_id AND ((handoff_at IS NOT NULL AND aborted_before_call=0 AND NOT(NEW.type='expired' AND COALESCE(NEW.error_code,'')='DEADLINE_BEFORE_CALL' AND NEW.attempt_id=attempt_id)) OR unknown_observed=1))
 OR EXISTS(SELECT 1 FROM messages WHERE message_id=NEW.message_id AND unknown_observed=1) OR EXISTS(SELECT 1 FROM message_parts WHERE message_id=NEW.message_id))
BEGIN SELECT RAISE(ABORT,'handoff_cannot_be_suppressed'); END;
CREATE TRIGGER event_handoff_after_suppression BEFORE INSERT ON device_events
WHEN NOT EXISTS(SELECT 1 FROM device_events WHERE event_id=NEW.event_id) AND NEW.type='handoff_started' AND EXISTS(SELECT 1 FROM messages WHERE message_id=NEW.message_id AND state IN('cancelled','expired'))
BEGIN SELECT RAISE(ABORT,'handoff_after_suppression'); END;
CREATE TRIGGER event_abort_evidence BEFORE INSERT ON device_events
WHEN NOT EXISTS(SELECT 1 FROM device_events WHERE event_id=NEW.event_id) AND NEW.error_code IN('ABORTED_BEFORE_CALL','DEADLINE_BEFORE_CALL') AND (
 NEW.attempt_id IS NULL OR EXISTS(SELECT 1 FROM message_parts WHERE message_id=NEW.message_id AND attempt_id=NEW.attempt_id)
 OR EXISTS(SELECT 1 FROM attempts WHERE message_id=NEW.message_id AND attempt_id=NEW.attempt_id AND unknown_observed=1))
BEGIN SELECT RAISE(ABORT,'event_abort_conflicts_with_evidence'); END;
CREATE TRIGGER event_apply AFTER INSERT ON device_events
BEGIN
 INSERT INTO attempts(message_id,attempt_id,installation_id,parts_total,handoff_at,unknown_observed,failed_observed,aborted_before_call,updated_at)
 SELECT NEW.message_id,NEW.attempt_id,NEW.installation_id,NEW.parts_total,CASE WHEN NEW.type='handoff_started' THEN NEW.at END,
 CASE WHEN NEW.type='outcome_unknown' AND COALESCE(json_extract(NEW.detail_json,'$.phase'),'')<>'delivery' AND COALESCE(NEW.error_code,'') NOT LIKE 'DELIVERY_%' THEN 1 ELSE 0 END,
 CASE WHEN NEW.type='failed' THEN 1 ELSE 0 END,CASE WHEN NEW.error_code IN('ABORTED_BEFORE_CALL','DEADLINE_BEFORE_CALL') THEN 1 ELSE 0 END,NEW.received_at
 WHERE NEW.attempt_id IS NOT NULL
 ON CONFLICT(message_id,attempt_id) DO UPDATE SET parts_total=COALESCE(attempts.parts_total,excluded.parts_total),handoff_at=COALESCE(attempts.handoff_at,excluded.handoff_at),
 unknown_observed=MAX(attempts.unknown_observed,excluded.unknown_observed),failed_observed=MAX(attempts.failed_observed,excluded.failed_observed),aborted_before_call=MAX(attempts.aborted_before_call,excluded.aborted_before_call),updated_at=excluded.updated_at;
 INSERT INTO message_parts(message_id,attempt_id,part_index,sent_at,delivered_at,failed_at,sent_failed_at,delivery_failed_at,delivery_unknown_at,error_code)
 SELECT NEW.message_id,NEW.attempt_id,NEW.part_index,
 CASE WHEN NEW.type IN('part_sent','part_delivered') THEN NEW.at END,CASE WHEN NEW.type='part_delivered' THEN NEW.at END,CASE WHEN NEW.type='part_failed' THEN NEW.at END,
 CASE WHEN NEW.type='part_failed' AND COALESCE(json_extract(NEW.detail_json,'$.phase'),'')<>'delivery' AND COALESCE(NEW.error_code,'') NOT LIKE 'DELIVERY_%' THEN NEW.at END,
 CASE WHEN NEW.type='part_failed' AND (json_extract(NEW.detail_json,'$.phase')='delivery' OR NEW.error_code LIKE 'DELIVERY_%') THEN NEW.at END,
 CASE WHEN NEW.type='outcome_unknown' AND (json_extract(NEW.detail_json,'$.phase')='delivery' OR NEW.error_code LIKE 'DELIVERY_%') THEN NEW.at END,NEW.error_code
 WHERE NEW.attempt_id IS NOT NULL AND NEW.part_index IS NOT NULL AND NEW.type IN('part_sent','part_delivered','part_failed','outcome_unknown')
 ON CONFLICT(message_id,attempt_id,part_index) DO UPDATE SET sent_at=COALESCE(message_parts.sent_at,excluded.sent_at),delivered_at=COALESCE(message_parts.delivered_at,excluded.delivered_at),failed_at=COALESCE(message_parts.failed_at,excluded.failed_at),
 sent_failed_at=COALESCE(message_parts.sent_failed_at,excluded.sent_failed_at),delivery_failed_at=COALESCE(message_parts.delivery_failed_at,excluded.delivery_failed_at),delivery_unknown_at=COALESCE(message_parts.delivery_unknown_at,excluded.delivery_unknown_at),error_code=COALESCE(excluded.error_code,message_parts.error_code);
 UPDATE messages SET unknown_observed=MAX(unknown_observed,CASE WHEN NEW.type='outcome_unknown' AND NEW.attempt_id IS NULL THEN 1 ELSE 0 END),
 failure_observed=MAX(failure_observed,CASE WHEN NEW.type='failed' AND NEW.attempt_id IS NULL THEN 1 ELSE 0 END),
 phone_accepted_at=CASE WHEN NEW.type='phone_accepted' THEN COALESCE(phone_accepted_at,NEW.at) ELSE phone_accepted_at END,updated_at=NEW.received_at WHERE message_id=NEW.message_id;
 UPDATE messages SET state=CASE
 WHEN EXISTS(SELECT 1 FROM attempt_evidence a WHERE a.message_id=NEW.message_id AND a.parts_total IS NOT NULL AND a.delivered_count=a.parts_total) THEN 'delivered'
 WHEN EXISTS(SELECT 1 FROM attempt_evidence a WHERE a.message_id=NEW.message_id AND a.parts_total IS NOT NULL AND a.sent_count=a.parts_total AND a.delivery_failure_count=0 AND a.delivery_unknown_count=0) THEN 'sent'
 WHEN EXISTS(SELECT 1 FROM attempt_evidence a WHERE a.message_id=NEW.message_id AND a.parts_total IS NOT NULL AND a.sent_count=a.parts_total AND a.delivery_failure_count=0 AND a.delivery_unknown_count>0) THEN 'delivery_unconfirmed'
 WHEN EXISTS(SELECT 1 FROM attempt_evidence a WHERE a.message_id=NEW.message_id AND a.sent_count>0 AND (a.parts_total IS NULL OR a.failure_count<a.parts_total)) THEN 'partial'
 WHEN unknown_observed=1 OR EXISTS(SELECT 1 FROM attempt_evidence a WHERE a.message_id=NEW.message_id AND a.unknown_observed=1 AND (a.parts_total IS NULL OR a.sent_count<a.parts_total) AND (a.parts_total IS NULL OR a.failure_count<a.parts_total)) THEN 'outcome_unknown'
 WHEN EXISTS(SELECT 1 FROM attempt_evidence a WHERE a.message_id=NEW.message_id AND a.handoff_at IS NOT NULL AND a.aborted_before_call=0 AND a.failed_observed=0 AND (a.parts_total IS NULL OR a.failure_count<a.parts_total)) THEN 'handoff_started'
 WHEN failure_observed=1 OR EXISTS(SELECT 1 FROM attempt_evidence a WHERE a.message_id=NEW.message_id AND (a.failed_observed=1 OR (a.parts_total IS NOT NULL AND a.failure_count=a.parts_total))) THEN 'failed'
 WHEN NEW.type='cancelled' THEN 'cancelled' WHEN NEW.type='expired' THEN 'expired' WHEN state IN('cancelled','expired') THEN state
 WHEN phone_accepted_at IS NOT NULL THEN 'phone_accepted' ELSE state END WHERE message_id=NEW.message_id;
END;
CREATE TABLE campaign_budget (
 campaign_id TEXT NOT NULL REFERENCES campaigns(campaign_id),window_start TEXT NOT NULL,used_segments INTEGER NOT NULL DEFAULT 0 CHECK(used_segments>=0),PRIMARY KEY(campaign_id,window_start)
);
CREATE TABLE dispatch_permits (
 permit_id TEXT PRIMARY KEY,message_id TEXT NOT NULL REFERENCES messages(message_id),campaign_id TEXT NOT NULL REFERENCES campaigns(campaign_id),installation_id TEXT NOT NULL REFERENCES devices(installation_id),
 window_start TEXT NOT NULL,valid_until TEXT NOT NULL,segments INTEGER NOT NULL CHECK(segments>0),created_at TEXT NOT NULL
);
CREATE INDEX permits_message ON dispatch_permits(message_id,valid_until);
CREATE TRIGGER permit_charge AFTER INSERT ON dispatch_permits
BEGIN
 UPDATE campaign_budget SET used_segments=used_segments+NEW.segments WHERE campaign_id=NEW.campaign_id AND window_start=NEW.window_start;
END;
CREATE TABLE audit_events (event_id TEXT PRIMARY KEY,actor_type TEXT NOT NULL,actor_id TEXT NOT NULL,action TEXT NOT NULL,resource_id TEXT NOT NULL,at TEXT NOT NULL);
CREATE INDEX audit_resource ON audit_events(resource_id,at);
CREATE TRIGGER message_wake AFTER INSERT ON messages
BEGIN
 UPDATE devices SET fcm_pending=1,fcm_next_at=NEW.created_at,wake_revision=wake_revision+1 WHERE revoked_at IS NULL AND ready=1 AND EXISTS(SELECT 1 FROM json_each(devices.allowed_kinds) WHERE value=NEW.kind);
END;
