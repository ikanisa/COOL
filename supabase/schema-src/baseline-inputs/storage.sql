-- Durable protected-object control plane. Provider bytes remain private and
-- are accepted only after full body hashing by the native Storage adapter.
-- This SQL does not turn a caller-supplied provider response into proof.
CREATE TABLE private.storage_namespace (
 singleton boolean PRIMARY KEY CHECK(singleton),
 origin text NOT NULL CHECK(origin ~ '^https://[^/?#@[:space:]]+$'),
 bucket text NOT NULL CHECK(bucket ~ '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,99}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.storage_payload_reservations (
 object_key text PRIMARY KEY,
 source_fingerprint text NOT NULL CHECK(source_fingerprint ~ '^[a-f0-9]{64}$'),
 scope jsonb NOT NULL CHECK(jsonb_typeof(scope)='object'),
 aad text NOT NULL CHECK(length(aad) BETWEEN 1 AND 2000),
 key_id text NOT NULL CHECK(length(key_id) BETWEEN 1 AND 200),
 plaintext_sha256 text NOT NULL CHECK(plaintext_sha256 ~ '^[a-f0-9]{64}$'),
 sealed_body text CHECK(octet_length(sealed_body) BETWEEN 1 AND 10700000),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),cleared_at timestamptz,
 CHECK((sealed_body IS NULL)=(cleared_at IS NOT NULL))
);
CREATE INDEX storage_pending_owner ON private.storage_payload_reservations((scope->>'ownerId')) WHERE sealed_body IS NOT NULL;
CREATE TABLE private.storage_put_intents (
 operation_id text PRIMARY KEY,object_key text NOT NULL UNIQUE,
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 sha256 text NOT NULL CHECK(sha256 ~ '^[a-f0-9]{64}$'),size bigint NOT NULL CHECK(size BETWEEN 1 AND 8000000),
 scope jsonb NOT NULL CHECK(jsonb_typeof(scope)='object'),http_metadata jsonb NOT NULL CHECK(jsonb_typeof(http_metadata)='object'),custom_metadata jsonb NOT NULL CHECK(jsonb_typeof(custom_metadata)='object'),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN('pending','committed','erased')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),active_attempt uuid,
 upload_unresolved boolean NOT NULL DEFAULT false,delete_tombstone boolean NOT NULL DEFAULT false,
 last_outcome text,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.storage_upload_attempts (
 id uuid PRIMARY KEY,operation_id text NOT NULL REFERENCES private.storage_put_intents(operation_id),
 outcome text NOT NULL DEFAULT 'started',started_at timestamptz NOT NULL DEFAULT clock_timestamp(),completed_at timestamptz
);
ALTER TABLE private.storage_put_intents ADD CONSTRAINT storage_active_attempt_fk FOREIGN KEY(active_attempt) REFERENCES private.storage_upload_attempts(id) DEFERRABLE INITIALLY DEFERRED;
CREATE TABLE private.storage_objects (
 object_key text PRIMARY KEY,operation_id text NOT NULL UNIQUE REFERENCES private.storage_put_intents(operation_id),
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),sha256 text NOT NULL CHECK(sha256 ~ '^[a-f0-9]{64}$'),size bigint NOT NULL CHECK(size BETWEEN 1 AND 8000000),
 scope jsonb NOT NULL CHECK(jsonb_typeof(scope)='object'),http_metadata jsonb NOT NULL CHECK(jsonb_typeof(http_metadata)='object'),custom_metadata jsonb NOT NULL CHECK(jsonb_typeof(custom_metadata)='object'),etag text,
 committed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE private.storage_delete_intents (
 operation_id text PRIMARY KEY,object_key text NOT NULL UNIQUE REFERENCES private.storage_put_intents(object_key),
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),expected_sha256 text NOT NULL CHECK(expected_sha256 ~ '^[a-f0-9]{64}$'),scope jsonb NOT NULL CHECK(jsonb_typeof(scope)='object'),
 state text NOT NULL DEFAULT 'pending' CHECK(state IN('pending','committed')),
 last_outcome text,absence_proof jsonb,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),committed_at timestamptz,
 CHECK(state<>'committed' OR (committed_at IS NOT NULL AND absence_proof @> '{"headStatus":404,"getStatus":404,"bucketVerified":true}'::jsonb))
);

-- One canonical metadata writer. This view exists for read compatibility only;
-- it has no INSERT/UPDATE/DELETE grants and uses the caller's RLS privileges.
CREATE VIEW private.object_metadata WITH(security_invoker=true) AS
 SELECT object_key,size,http_metadata,custom_metadata,sha256,committed_at AS created_at FROM private.storage_objects;

-- The source implements physical erasure only for its generic upload catalog.
-- Financial evidence, raw SMS and roster sources remain retained. Authority,
-- source/preimage guards, claim and barrier must still be present in this
-- transaction; neither an HTTP callback nor a JSON boolean grants erasure.
CREATE FUNCTION private.assert_storage_delete_authorized(p_key text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE actor text;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key,7346369));
 actor:=private.assert_actor('privacy.review',NULL,NULL,2,300);
 IF EXISTS(SELECT 1 FROM app.payment_evidence WHERE object_key=p_key) OR EXISTS(SELECT 1 FROM app.sms_receipts WHERE object_key=p_key) OR EXISTS(SELECT 1 FROM app.roster_imports WHERE source_object_key=p_key) THEN RAISE EXCEPTION 'storage_retention_class_not_erasable' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM private.storage_put_intents i
  JOIN app.upload_objects o ON o.object_key=i.object_key AND o.sha256=i.sha256 AND o.user_id=i.scope->>'ownerId' AND o.id=i.scope->>'entityId'
  JOIN app.privacy_retention_effects e ON e.object_key=i.object_key AND e.source_sha256=i.sha256
  JOIN app.privacy_retention_tasks t ON t.id=e.task_id AND t.class_name='r2:upload_objects' AND t.action='erase' AND t.state='claimed' AND t.claim_id=e.claim_id AND t.fence=e.fence
  JOIN app.privacy_retention_claims c ON c.id=e.claim_id AND c.task_id=t.id AND c.fence=t.fence AND c.actor_id=actor AND c.session_id=api.current_session_id() AND c.expires_seconds>app.unixepoch()
  JOIN app.privacy_retention_plans p ON p.id=t.plan_id AND p.subject_id=o.user_id
  JOIN app.privacy_retention_barriers b ON b.subject_id=p.subject_id AND (b.plan_id=p.id OR b.plan_id=app.json_extract(p.policy_json,'$.quarantine_continuation.previous_plan_id'))
  JOIN app.runtime_config cfg ON cfg.key='privacy:retention:approved:v1' AND cfg.revision=p.policy_config_revision AND cfg.value_json=p.policy_json
  WHERE i.object_key=p_key AND i.active_attempt IS NULL AND NOT i.upload_unresolved
   AND app.json_numeric(p.policy_json,'$.writer_fence.generic_upload_catalog_only')=1 AND app.json_numeric(p.policy_json,'$.writer_fence.unknown_in_flight')=0
   AND app.julianday(app.json_extract(p.policy_json,'$.expires_at'))>app.julianday('now')
   AND encode(sha256(convert_to(p.policy_json,'UTF8')),'hex')=p.policy_sha256
   AND coalesce((SELECT revision FROM app.privacy_review_heads WHERE request_id=p.request_id),0)=p.review_revision
   AND EXISTS(SELECT 1 FROM app.mutation_guards g WHERE g.user_id=actor AND g.session_id=api.current_session_id() AND g.permission='privacy.review' AND g.minimum_assurance=2 AND g.fresh_seconds<=300)
   AND EXISTS(SELECT 1 FROM app.privacy_retention_guards g WHERE g.plan_id=p.id AND g.class_name=t.class_name AND g.passed=1)
   AND NOT EXISTS(SELECT 1 FROM app.privacy_holds h WHERE h.user_id=p.subject_id AND h.active=1)
   AND NOT EXISTS(SELECT 1 FROM app.native_reservations n WHERE n.user_id=p.subject_id AND n.state NOT IN('completed','rejected'))
   AND NOT EXISTS(SELECT 1 FROM app.roster_imports r WHERE r.user_id=p.subject_id AND r.state IN('processing','ambiguous'))
   AND NOT EXISTS(SELECT 1 FROM app.auth_otp_challenges x WHERE x.identity_value IN(SELECT phone FROM app.users WHERE id=p.subject_id UNION SELECT email FROM app.users WHERE id=p.subject_id) AND x.status IN('dispatching','delivery_unknown'))
 ) THEN RAISE EXCEPTION 'storage_retention_admission_required' USING ERRCODE='42501'; END IF;
END$$;

CREATE FUNCTION private.trg_storage_identity() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE old_json jsonb;new_json jsonb;mutable text[];
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'retain_storage_control_identity' USING ERRCODE='42501'; END IF;
 mutable:=CASE TG_TABLE_NAME
  WHEN 'storage_put_intents' THEN ARRAY['state','attempts','active_attempt','upload_unresolved','delete_tombstone','last_outcome','updated_at']
  WHEN 'storage_upload_attempts' THEN ARRAY['outcome','completed_at']
  WHEN 'storage_delete_intents' THEN ARRAY['state','last_outcome','absence_proof','committed_at']
  WHEN 'storage_payload_reservations' THEN ARRAY['sealed_body','cleared_at']
  ELSE ARRAY[]::text[] END;
 old_json:=to_jsonb(OLD);new_json:=to_jsonb(NEW);
 IF old_json-mutable IS DISTINCT FROM new_json-mutable THEN RAISE EXCEPTION 'immutable_storage_identity' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='storage_namespace' THEN RAISE EXCEPTION 'immutable_storage_namespace' USING ERRCODE='42501'; END IF;
 IF TG_TABLE_NAME='storage_payload_reservations' THEN
  IF OLD.sealed_body IS NULL OR NEW.sealed_body IS NOT NULL OR NEW.cleared_at IS NULL THEN RAISE EXCEPTION 'immutable_storage_payload' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM app.sms_receipts r WHERE r.object_key=OLD.object_key AND r.id=OLD.scope->>'entityId' AND r.owner_user_id=OLD.scope->>'ownerId' AND r.object_sha256=OLD.plaintext_sha256)
   AND NOT EXISTS(SELECT 1 FROM app.payment_evidence r WHERE r.object_key=OLD.object_key AND r.id=OLD.scope->>'entityId' AND r.owner_user_id=OLD.scope->>'ownerId' AND r.object_sha256=OLD.plaintext_sha256)
   AND NOT EXISTS(SELECT 1 FROM app.roster_imports r WHERE r.source_object_key=OLD.object_key AND r.id=OLD.scope->>'entityId' AND r.user_id=OLD.scope->>'ownerId' AND r.source_sha256=OLD.plaintext_sha256 AND r.state='retained')
   AND NOT EXISTS(SELECT 1 FROM private.storage_put_intents i JOIN private.storage_delete_intents d ON d.object_key=i.object_key WHERE i.object_key=OLD.object_key AND i.state='erased' AND i.delete_tombstone AND d.state='committed' AND d.absence_proof @> '{"headStatus":404,"getStatus":404,"bucketVerified":true}'::jsonb)
  THEN RAISE EXCEPTION 'storage_payload_clear_requires_application_or_erasure_commit' USING ERRCODE='42501'; END IF;
 ELSIF TG_TABLE_NAME='storage_put_intents' THEN
  IF (OLD.delete_tombstone AND NOT NEW.delete_tombstone) OR (OLD.upload_unresolved AND NOT NEW.upload_unresolved) OR NEW.attempts<OLD.attempts OR (OLD.state='erased' AND NEW.state<>'erased') OR (OLD.state='committed' AND NEW.state='pending') THEN RAISE EXCEPTION 'storage_state_regression' USING ERRCODE='42501'; END IF;
  IF (NEW.delete_tombstone AND NOT OLD.delete_tombstone) OR (NEW.state='erased' AND OLD.state<>'erased') THEN PERFORM private.assert_storage_delete_authorized(NEW.object_key); END IF;
 ELSIF TG_TABLE_NAME='storage_delete_intents' THEN
  IF OLD.state='committed' AND old_json IS DISTINCT FROM new_json THEN RAISE EXCEPTION 'immutable_storage_delete_result' USING ERRCODE='42501'; END IF;
 ELSIF TG_TABLE_NAME='storage_upload_attempts' THEN
  IF OLD.completed_at IS NOT NULL AND old_json IS DISTINCT FROM new_json THEN RAISE EXCEPTION 'immutable_storage_attempt_result' USING ERRCODE='42501'; END IF;
 END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER storage_namespace_identity BEFORE UPDATE OR DELETE ON private.storage_namespace FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
CREATE TRIGGER storage_payload_identity BEFORE UPDATE OR DELETE ON private.storage_payload_reservations FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
CREATE TRIGGER storage_put_identity BEFORE UPDATE OR DELETE ON private.storage_put_intents FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
CREATE TRIGGER storage_upload_identity BEFORE UPDATE OR DELETE ON private.storage_upload_attempts FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
CREATE TRIGGER storage_delete_identity BEFORE UPDATE OR DELETE ON private.storage_delete_intents FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();
CREATE TRIGGER storage_object_identity BEFORE UPDATE ON private.storage_objects FOR EACH ROW EXECUTE FUNCTION private.trg_storage_identity();

CREATE FUNCTION private.trg_storage_object_delete() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 PERFORM private.assert_storage_delete_authorized(OLD.object_key);
 IF NOT EXISTS(SELECT 1 FROM private.storage_put_intents WHERE object_key=OLD.object_key AND delete_tombstone AND active_attempt IS NULL AND NOT upload_unresolved) THEN RAISE EXCEPTION 'storage_delete_tombstone_required' USING ERRCODE='42501'; END IF;
 RETURN OLD;
END$$;
CREATE TRIGGER storage_object_delete BEFORE DELETE ON private.storage_objects FOR EACH ROW EXECUTE FUNCTION private.trg_storage_object_delete();

-- Journal ordering removes metadata before marking its erasure receipt. Check
-- the final transaction state, so a partial SQL batch cannot commit metadata
-- loss without the exact dual-absence receipt and retained tombstone.
CREATE FUNCTION private.trg_storage_erasure_commit() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM private.storage_objects WHERE object_key=OLD.object_key)
  OR NOT EXISTS(SELECT 1 FROM private.storage_put_intents i JOIN private.storage_delete_intents d ON d.object_key=i.object_key WHERE i.object_key=OLD.object_key AND i.state='erased' AND i.delete_tombstone AND i.active_attempt IS NULL AND NOT i.upload_unresolved AND d.state='committed' AND d.expected_sha256=OLD.sha256 AND d.scope=OLD.scope AND d.absence_proof @> '{"headStatus":404,"getStatus":404,"bucketVerified":true}'::jsonb)
 THEN RAISE EXCEPTION 'storage_erasure_commit_incomplete' USING ERRCODE='42501';END IF;
 UPDATE private.storage_payload_reservations SET sealed_body=NULL,cleared_at=clock_timestamp() WHERE object_key=OLD.object_key AND sealed_body IS NOT NULL;
 RETURN NULL;
END$$;
CREATE CONSTRAINT TRIGGER storage_object_erase_commit AFTER DELETE ON private.storage_objects DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION private.trg_storage_erasure_commit();

CREATE FUNCTION private.trg_storage_reservation_budget() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE count_pending bigint;bytes_pending bigint;
BEGIN
 IF NEW.scope->>'ownerId' IS NULL OR NEW.scope->>'entityId' IS NULL OR NEW.scope->>'purpose' IS NULL OR (SELECT count(*) FROM jsonb_object_keys(NEW.scope))<>3 THEN RAISE EXCEPTION 'invalid_storage_scope' USING ERRCODE='22023'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(NEW.scope->>'ownerId',7346370));
 SELECT count(*),coalesce(sum(octet_length(sealed_body)),0) INTO count_pending,bytes_pending FROM private.storage_payload_reservations WHERE scope->>'ownerId'=NEW.scope->>'ownerId' AND sealed_body IS NOT NULL;
 IF count_pending>=128 OR bytes_pending+octet_length(NEW.sealed_body)>64000000 THEN RAISE EXCEPTION 'storage_pending_budget_exceeded' USING ERRCODE='54000'; END IF;
 RETURN NEW;
END$$;
CREATE TRIGGER storage_reservation_budget BEFORE INSERT ON private.storage_payload_reservations FOR EACH ROW EXECUTE FUNCTION private.trg_storage_reservation_budget();

CREATE FUNCTION private.assert_storage_ready(p_key text,p_owner text,p_entity text,p_plain_sha text,p_purpose text) RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE object private.storage_objects%ROWTYPE;intent private.storage_put_intents%ROWTYPE;reserved private.storage_payload_reservations%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key,7346369));
 -- Immutable metadata needs no UPDATE privilege. The shared per-object
 -- advisory lock serializes this lookup with every journal mutation.
 SELECT * INTO object FROM private.storage_objects WHERE object_key=p_key;
 SELECT * INTO intent FROM private.storage_put_intents WHERE object_key=p_key FOR SHARE;
 SELECT * INTO reserved FROM private.storage_payload_reservations WHERE object_key=p_key FOR UPDATE;
 IF object.object_key IS NULL OR intent.object_key IS NULL OR reserved.object_key IS NULL OR intent.state<>'committed' OR intent.delete_tombstone
  OR object.operation_id<>intent.operation_id OR object.fingerprint<>intent.fingerprint OR object.sha256<>intent.sha256 OR object.size<>intent.size
  OR object.scope IS DISTINCT FROM intent.scope OR object.http_metadata IS DISTINCT FROM intent.http_metadata OR object.custom_metadata IS DISTINCT FROM intent.custom_metadata
  OR object.scope IS DISTINCT FROM jsonb_build_object('ownerId',p_owner,'entityId',p_entity,'purpose',p_purpose)
  OR reserved.scope IS DISTINCT FROM object.scope OR reserved.plaintext_sha256 IS DISTINCT FROM p_plain_sha
  OR object.custom_metadata->>'source_fingerprint' IS DISTINCT FROM reserved.source_fingerprint
  OR object.custom_metadata->>'sha256' IS DISTINCT FROM p_plain_sha
 THEN RAISE EXCEPTION 'storage_not_ready_for_application_commit' USING ERRCODE='42501'; END IF;
END$$;

CREATE FUNCTION private.trg_storage_application_commit() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
DECLARE key text;
BEGIN
 IF TG_TABLE_NAME='sms_receipts' THEN
  key:=NEW.object_key;PERFORM private.assert_storage_ready(key,NEW.owner_user_id,NEW.id,NEW.object_sha256,'sms_receipt');
 ELSIF TG_TABLE_NAME='payment_evidence' THEN
  key:=NEW.object_key;PERFORM private.assert_storage_ready(key,NEW.owner_user_id,NEW.id,NEW.object_sha256,'payment_evidence');
 ELSIF TG_TABLE_NAME='roster_imports' THEN
  IF NEW.state<>'retained' OR OLD.state=NEW.state THEN RETURN NEW; END IF;
  key:=NEW.source_object_key;PERFORM private.assert_storage_ready(key,NEW.user_id,NEW.id,NEW.source_sha256,'roster_source');
  IF NOT EXISTS(SELECT 1 FROM private.storage_objects o WHERE o.object_key=key AND o.sha256=NEW.object_sha256 AND o.custom_metadata->>'source_sha256'=NEW.source_sha256 AND o.custom_metadata->>'object_sha256'=NEW.object_sha256) THEN RAISE EXCEPTION 'roster_storage_source_changed' USING ERRCODE='42501'; END IF;
 END IF;
 UPDATE private.storage_payload_reservations SET sealed_body=NULL,cleared_at=clock_timestamp() WHERE object_key=key AND sealed_body IS NOT NULL;
 RETURN NEW;
END$$;
CREATE TRIGGER storage_sms_application_commit AFTER INSERT ON app.sms_receipts FOR EACH ROW EXECUTE FUNCTION private.trg_storage_application_commit();
CREATE TRIGGER storage_evidence_application_commit AFTER INSERT ON app.payment_evidence FOR EACH ROW EXECUTE FUNCTION private.trg_storage_application_commit();
CREATE TRIGGER storage_roster_application_commit AFTER UPDATE OF state ON app.roster_imports FOR EACH ROW EXECUTE FUNCTION private.trg_storage_application_commit();
