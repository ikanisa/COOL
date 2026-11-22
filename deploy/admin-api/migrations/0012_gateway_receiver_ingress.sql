-- Explicit receiver capture grants and immutable signed producer receipts.
-- These records grant no sending, transaction, verification or allocation rights.
PRAGMA foreign_keys=ON;
CREATE TABLE collect_gateway_receiver_grants (
 id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36),
 device_id TEXT NOT NULL REFERENCES collect_gateway_devices(id),
 payee_id TEXT NOT NULL REFERENCES collect_payees(id),
 status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','revoked')),
 version INTEGER NOT NULL DEFAULT 1 CHECK(version BETWEEN 1 AND 9007199254740991),
 created_by_admin_id TEXT NOT NULL REFERENCES admin_users(id),
 creation_operation_request_id TEXT NOT NULL UNIQUE REFERENCES collect_operation_requests(id),
 creation_reason TEXT NOT NULL CHECK(length(trim(creation_reason)) BETWEEN 8 AND 1000),
 created_at INTEGER NOT NULL CHECK(created_at>0),
 revoked_by_admin_id TEXT REFERENCES admin_users(id),
 revocation_operation_request_id TEXT UNIQUE REFERENCES collect_operation_requests(id),
 revocation_reason TEXT CHECK(revocation_reason IS NULL OR length(trim(revocation_reason)) BETWEEN 8 AND 1000),
 revoked_at INTEGER,
 CHECK((status='active' AND version=1 AND revoked_by_admin_id IS NULL AND revocation_operation_request_id IS NULL AND revocation_reason IS NULL AND revoked_at IS NULL)
  OR (status='revoked' AND version=2 AND revoked_by_admin_id IS NOT NULL AND revocation_operation_request_id IS NOT NULL AND revocation_reason IS NOT NULL AND revoked_at>=created_at)),
 UNIQUE(id,device_id,payee_id)
) STRICT;
CREATE UNIQUE INDEX collect_gateway_receiver_active_device ON collect_gateway_receiver_grants(device_id) WHERE status='active';
CREATE INDEX collect_gateway_receiver_grant_payee ON collect_gateway_receiver_grants(payee_id,status,created_at,id);
CREATE TRIGGER collect_gateway_receiver_grant_insert BEFORE INSERT ON collect_gateway_receiver_grants
WHEN NEW.status!='active' OR NEW.version!=1
BEGIN SELECT RAISE(ABORT,'New receiver capture grants must be active'); END;
CREATE TRIGGER collect_gateway_receiver_grant_identity BEFORE UPDATE ON collect_gateway_receiver_grants
BEGIN
 SELECT CASE WHEN NEW.id IS NOT OLD.id OR NEW.device_id IS NOT OLD.device_id OR NEW.payee_id IS NOT OLD.payee_id
  OR NEW.created_by_admin_id IS NOT OLD.created_by_admin_id OR NEW.creation_operation_request_id IS NOT OLD.creation_operation_request_id
  OR NEW.creation_reason IS NOT OLD.creation_reason OR NEW.created_at IS NOT OLD.created_at
  THEN RAISE(ABORT,'Receiver capture grant identity is immutable') END;
 SELECT CASE WHEN OLD.status!='active' OR NEW.status!='revoked' OR NEW.version!=OLD.version+1
  THEN RAISE(ABORT,'Receiver capture grants may only be revoked') END;
END;
CREATE TRIGGER collect_gateway_receiver_grant_no_delete BEFORE DELETE ON collect_gateway_receiver_grants
BEGIN SELECT RAISE(ABORT,'Receiver capture grant evidence cannot be deleted'); END;

-- signed_request_base64 and signature_base64 are private evidence, never DTO fields.
CREATE TABLE collect_gateway_receiver_requests (
 id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36),
 device_id TEXT NOT NULL REFERENCES collect_gateway_devices(id),
 request_id TEXT NOT NULL CHECK(length(request_id)=36),
 request_sha256 TEXT NOT NULL CHECK(length(request_sha256)=64 AND request_sha256 NOT GLOB '*[^a-f0-9]*'),
 signed_request_base64 TEXT NOT NULL CHECK(length(signed_request_base64) BETWEEN 4 AND 174764),
 signature_base64 TEXT NOT NULL CHECK(length(signature_base64) BETWEEN 12 AND 100),
 grant_id TEXT NOT NULL,
 payee_id TEXT NOT NULL,
 client_sms_id TEXT NOT NULL CHECK(length(client_sms_id)=36),
 ingress_id TEXT NOT NULL REFERENCES collect_receipt_ingress(id),
 payload_sha256 TEXT NOT NULL CHECK(length(payload_sha256)=64 AND payload_sha256 NOT GLOB '*[^a-f0-9]*'),
 issued_at TEXT NOT NULL,
 source_received_at INTEGER NOT NULL CHECK(source_received_at>0),
 accepted_at INTEGER NOT NULL CHECK(accepted_at>0),
 response_json TEXT NOT NULL CHECK(json_valid(response_json)),
 FOREIGN KEY(grant_id,device_id,payee_id) REFERENCES collect_gateway_receiver_grants(id,device_id,payee_id),
 UNIQUE(device_id,request_id)
) STRICT;
CREATE INDEX collect_gateway_receiver_request_grant ON collect_gateway_receiver_requests(grant_id,accepted_at,id);
CREATE TRIGGER collect_gateway_receiver_request_source BEFORE INSERT ON collect_gateway_receiver_requests
BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM collect_receipt_ingress i WHERE i.id=NEW.ingress_id AND i.payee_id=NEW.payee_id
  AND i.source_key='gateway:'||NEW.grant_id||':'||NEW.device_id AND i.external_message_id=NEW.client_sms_id
  AND i.payload_sha256=NEW.payload_sha256 AND i.received_at=NEW.source_received_at)
  THEN RAISE(ABORT,'Signed receiver receipt must bind its exact source identity') END;
END;
CREATE TRIGGER collect_gateway_receiver_request_no_update BEFORE UPDATE ON collect_gateway_receiver_requests
BEGIN SELECT RAISE(ABORT,'Signed receiver requests are immutable'); END;
CREATE TRIGGER collect_gateway_receiver_request_no_delete BEFORE DELETE ON collect_gateway_receiver_requests
BEGIN SELECT RAISE(ABORT,'Signed receiver requests cannot be deleted'); END;
