-- Additive v0.3 schema. No queues, identities, or replay evidence are deleted.
CREATE INDEX messages_history ON messages(created_at DESC,message_id DESC);
CREATE INDEX messages_recipient_history ON messages(to_number,created_at DESC,message_id DESC);
CREATE INDEX messages_state_history ON messages(state,created_at DESC,message_id DESC);
CREATE INDEX event_content_cleanup ON device_events(detail_redacted_at,received_at,event_id);
CREATE INDEX audit_history ON audit_events(at DESC,event_id DESC);
CREATE TABLE otp_capacity_reservations(
 message_id TEXT PRIMARY KEY REFERENCES messages(message_id), installation_id TEXT NOT NULL REFERENCES devices(installation_id),
 slot_start INTEGER NOT NULL,slot_end INTEGER NOT NULL,dispatch_by INTEGER NOT NULL,segments INTEGER NOT NULL CHECK(segments>0),
 CHECK(slot_end>slot_start),CHECK(slot_end<=dispatch_by)
);
CREATE INDEX capacity_device_time ON otp_capacity_reservations(installation_id,slot_end);
CREATE TABLE otp_capacity_requirements(message_id TEXT PRIMARY KEY REFERENCES messages(message_id));
CREATE TRIGGER capacity_required BEFORE INSERT ON otp_capacity_requirements
WHEN NOT EXISTS(SELECT 1 FROM otp_capacity_reservations WHERE message_id=NEW.message_id)
BEGIN SELECT RAISE(ABORT,'otp_capacity_unavailable'); END;
CREATE TABLE sms_templates(
 application_id TEXT NOT NULL REFERENCES applications(application_id),template_key TEXT NOT NULL,version INTEGER NOT NULL CHECK(version>0),
 locale TEXT NOT NULL CHECK(locale IN('en','rw','fr')),kind TEXT NOT NULL CHECK(kind IN('receipt','operation','campaign','otp')),
 body TEXT NOT NULL,schema_json TEXT NOT NULL CHECK(json_valid(schema_json)),digest TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN('draft','published')),
 created_at TEXT NOT NULL,PRIMARY KEY(application_id,template_key,version,locale)
);
CREATE TRIGGER template_immutable BEFORE UPDATE ON sms_templates
WHEN NEW.body<>OLD.body OR NEW.schema_json<>OLD.schema_json OR NEW.digest<>OLD.digest OR NEW.kind<>OLD.kind
 OR NEW.application_id<>OLD.application_id OR NEW.template_key<>OLD.template_key OR NEW.version<>OLD.version OR NEW.locale<>OLD.locale
 OR (OLD.status='published' AND NEW.status<>'published')
BEGIN SELECT RAISE(ABORT,'template_immutable'); END;
CREATE TABLE notification_schedules(
 schedule_id TEXT PRIMARY KEY,application_id TEXT NOT NULL REFERENCES applications(application_id),request_key TEXT NOT NULL,
 request_digest TEXT NOT NULL,name TEXT NOT NULL,to_number TEXT NOT NULL,template_key TEXT NOT NULL,template_version INTEGER NOT NULL,locale TEXT NOT NULL,
 variables_json TEXT NOT NULL CHECK(json_valid(variables_json)),interval_seconds INTEGER NOT NULL CHECK(interval_seconds BETWEEN 60 AND 31536000),
 ttl_seconds INTEGER NOT NULL CHECK(ttl_seconds BETWEEN 30 AND 86400),next_at TEXT NOT NULL,ends_at TEXT NOT NULL,
 active INTEGER NOT NULL DEFAULT 0 CHECK(active IN(0,1)),revision INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,
 UNIQUE(application_id,request_key)
);
CREATE INDEX schedules_due ON notification_schedules(active,next_at,schedule_id);
CREATE TABLE schedule_occurrences(
 schedule_id TEXT NOT NULL REFERENCES notification_schedules(schedule_id),revision INTEGER NOT NULL,due_at TEXT NOT NULL,
 message_id TEXT NOT NULL UNIQUE,created_at TEXT NOT NULL,outcome TEXT NOT NULL CHECK(outcome IN('queued','expired')),
 PRIMARY KEY(schedule_id,revision,due_at)
);
CREATE TABLE webhook_endpoints(
 endpoint_id TEXT PRIMARY KEY,application_id TEXT UNIQUE REFERENCES applications(application_id),url TEXT NOT NULL,
 secret_cipher TEXT NOT NULL,enabled INTEGER NOT NULL CHECK(enabled IN(0,1)),generation INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL,updated_at TEXT NOT NULL
);
-- A NULL application identifies the deployment's alert receiver (at most one).
CREATE UNIQUE INDEX one_alert_receiver ON webhook_endpoints((1)) WHERE application_id IS NULL;
CREATE TABLE webhook_deliveries(
 delivery_id TEXT PRIMARY KEY,endpoint_id TEXT NOT NULL REFERENCES webhook_endpoints(endpoint_id),endpoint_generation INTEGER NOT NULL,
 event_key TEXT NOT NULL,payload_json TEXT NOT NULL CHECK(json_valid(payload_json)),state TEXT NOT NULL DEFAULT 'pending' CHECK(state IN('pending','sending','delivered','failed','cancelled')),
 attempts INTEGER NOT NULL DEFAULT 0,next_at TEXT NOT NULL,lease_id TEXT,lease_until TEXT,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,last_error TEXT,
 UNIQUE(endpoint_id,event_key)
);
CREATE INDEX webhook_due ON webhook_deliveries(state,next_at,lease_until);
CREATE TRIGGER callback_message_created AFTER INSERT ON messages
BEGIN
 INSERT INTO webhook_deliveries(delivery_id,endpoint_id,endpoint_generation,event_key,payload_json,next_at,created_at,updated_at)
 SELECT 'delivery_'||lower(hex(randomblob(16))),e.endpoint_id,e.generation,'created:'||NEW.message_id,
 json_object('type','message.state','message_id',NEW.message_id,'application_id',NEW.application_id,'state',NEW.state,'occurred_at',NEW.created_at),
 NEW.created_at,NEW.created_at,NEW.created_at FROM webhook_endpoints e WHERE e.application_id=NEW.application_id AND e.enabled=1;
END;
CREATE TRIGGER callback_message_state AFTER UPDATE OF state ON messages WHEN NEW.state<>OLD.state
BEGIN
 INSERT INTO webhook_deliveries(delivery_id,endpoint_id,endpoint_generation,event_key,payload_json,next_at,created_at,updated_at)
 SELECT 'delivery_'||lower(hex(randomblob(16))),e.endpoint_id,e.generation,'state:'||NEW.message_id||':'||lower(hex(randomblob(16))),
 json_object('type','message.state','message_id',NEW.message_id,'application_id',NEW.application_id,'state',NEW.state,'occurred_at',NEW.updated_at),
 NEW.updated_at,NEW.updated_at,NEW.updated_at FROM webhook_endpoints e WHERE e.application_id=NEW.application_id AND e.enabled=1;
END;
CREATE TABLE metric_alerts(alert_key TEXT PRIMARY KEY,severity TEXT NOT NULL,active INTEGER NOT NULL,first_seen_at TEXT NOT NULL,last_seen_at TEXT NOT NULL,resolved_at TEXT);
CREATE TABLE metric_alert_events(event_id TEXT PRIMARY KEY,alert_key TEXT NOT NULL,transition TEXT NOT NULL,at TEXT NOT NULL);
CREATE TRIGGER callback_alert AFTER INSERT ON metric_alert_events
BEGIN
 INSERT INTO webhook_deliveries(delivery_id,endpoint_id,endpoint_generation,event_key,payload_json,next_at,created_at,updated_at)
 SELECT 'delivery_'||lower(hex(randomblob(16))),e.endpoint_id,e.generation,NEW.event_id,
 json_object('type','service.alert','alert_key',NEW.alert_key,'transition',NEW.transition,'occurred_at',NEW.at),NEW.at,NEW.at,NEW.at
 FROM webhook_endpoints e WHERE e.application_id IS NULL AND e.enabled=1;
END;

-- Authoritative ledger snapshots are copied for notification only, never computed here.
CREATE TABLE ledger_notification_events(application_id TEXT NOT NULL REFERENCES applications(application_id),event_id TEXT NOT NULL,facts_json TEXT NOT NULL,facts_digest TEXT NOT NULL,created_at TEXT NOT NULL,redacted_at TEXT,PRIMARY KEY(application_id,event_id));
CREATE TABLE ledger_notification_receipts(application_id TEXT NOT NULL,event_id TEXT NOT NULL,recipient TEXT NOT NULL,message_id TEXT NOT NULL UNIQUE REFERENCES messages(message_id),PRIMARY KEY(application_id,event_id,recipient),FOREIGN KEY(application_id,event_id) REFERENCES ledger_notification_events(application_id,event_id));
CREATE TRIGGER ledger_notification_immutable BEFORE UPDATE ON ledger_notification_events
WHEN NEW.facts_digest<>OLD.facts_digest OR (NEW.facts_json<>OLD.facts_json AND NOT(OLD.redacted_at IS NULL AND NEW.redacted_at IS NOT NULL AND NEW.facts_json='{}')) OR (OLD.redacted_at IS NOT NULL AND NEW.redacted_at IS NOT OLD.redacted_at)
BEGIN SELECT RAISE(ABORT,'ledger_snapshot_immutable'); END;
