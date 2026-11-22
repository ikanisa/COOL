-- Proposed additive schema; not a migration and not applied by this package.
-- Incorporate into the reviewed managed migration chain only after checking
-- target roles, privacy retention, backup and source/target identity evidence.
CREATE TABLE private.collect_migration_actor_lineage (
  source_actor_id text PRIMARY KEY REFERENCES app.users(id),
  cloud_primary_id text NOT NULL REFERENCES app.users(id),
  operation_id uuid NOT NULL,
  snapshot_hmac text NOT NULL CHECK (snapshot_hmac ~ '^[a-f0-9]{64}$'),
  envelope jsonb NOT NULL CHECK (
    jsonb_typeof(envelope) = 'object' AND
    envelope->>'version' = '1' AND envelope->>'algorithm' = 'AES-256-GCM' AND
    jsonb_typeof(envelope->'nonce') = 'string' AND
    jsonb_typeof(envelope->'ciphertext') = 'string' AND
    jsonb_typeof(envelope->'tag') = 'string'
  ),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp(),
  CHECK (source_actor_id <> cloud_primary_id)
);

ALTER TABLE private.collect_migration_actor_lineage ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_migration_actor_lineage FORCE ROW LEVEL SECURITY;
CREATE POLICY collect_migration_actor_lineage_owner ON private.collect_migration_actor_lineage
  TO postgres USING (true) WITH CHECK (true);
REVOKE ALL ON private.collect_migration_actor_lineage
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;

CREATE FUNCTION private.collect_migration_actor_lineage_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $fn$
BEGIN
  RAISE EXCEPTION 'migration_actor_lineage_immutable' USING ERRCODE='23514';
END
$fn$;
REVOKE ALL ON FUNCTION private.collect_migration_actor_lineage_immutable()
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
CREATE TRIGGER collect_migration_actor_lineage_immutable
  BEFORE UPDATE OR DELETE ON private.collect_migration_actor_lineage
  FOR EACH ROW EXECUTE FUNCTION private.collect_migration_actor_lineage_immutable();
ALTER TABLE private.collect_migration_actor_lineage
  ENABLE ALWAYS TRIGGER collect_migration_actor_lineage_immutable;

-- A receipt is inserted with the graph and remains in the same transaction.
-- It lets an operator reconcile an uncertain COMMIT without replaying rows.
-- HMACs are keyed with the separately protected migration custody key.
CREATE TABLE private.collect_migration_import_receipts (
  operation_id uuid PRIMARY KEY,
  source_actor_id text NOT NULL REFERENCES private.collect_migration_actor_lineage(source_actor_id),
  cloud_primary_id text NOT NULL REFERENCES app.users(id),
  snapshot_hmac text NOT NULL CHECK (snapshot_hmac ~ '^[a-f0-9]{64}$'),
  object_proof_hmac text NOT NULL CHECK (object_proof_hmac ~ '^[a-f0-9]{64}$'),
  counts jsonb NOT NULL CHECK (jsonb_typeof(counts) = 'object'),
  created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
ALTER TABLE private.collect_migration_import_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_migration_import_receipts FORCE ROW LEVEL SECURITY;
CREATE POLICY collect_migration_import_receipts_owner ON private.collect_migration_import_receipts
  TO postgres USING (true) WITH CHECK (true);
REVOKE ALL ON private.collect_migration_import_receipts
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
CREATE FUNCTION private.collect_migration_import_receipts_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $fn$
BEGIN
  RAISE EXCEPTION 'migration_import_receipts_immutable' USING ERRCODE='23514';
END
$fn$;
REVOKE ALL ON FUNCTION private.collect_migration_import_receipts_immutable()
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
CREATE TRIGGER collect_migration_import_receipts_immutable
  BEFORE UPDATE OR DELETE ON private.collect_migration_import_receipts
  FOR EACH ROW EXECUTE FUNCTION private.collect_migration_import_receipts_immutable();
ALTER TABLE private.collect_migration_import_receipts
  ENABLE ALWAYS TRIGGER collect_migration_import_receipts_immutable;

-- Marks immutable imported evidence as historical. Runtime may read markers
-- only to deny automatic work; it cannot create or alter them.
CREATE TABLE private.collect_imported_native_history (
  source_id text PRIMARY KEY REFERENCES private.burimunsi_native_receipt_origins(source_id)
    DEFERRABLE INITIALLY DEFERRED,
  collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
  request_id uuid NOT NULL,
  transaction_id text REFERENCES app.momo_transactions(id) DEFERRABLE INITIALLY DEFERRED,
  body_sha256 text NOT NULL CHECK (body_sha256 ~ '^[a-f0-9]{64}$'),
  object_sha256 text NOT NULL CHECK (object_sha256 ~ '^[a-f0-9]{64}$'),
  source_fingerprint text NOT NULL CHECK (source_fingerprint ~ '^[a-f0-9]{64}$'),
  operation_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT statement_timestamp()
);
CREATE INDEX collect_imported_native_history_transaction ON private.collect_imported_native_history(transaction_id)
  WHERE transaction_id IS NOT NULL;
ALTER TABLE private.collect_imported_native_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.collect_imported_native_history FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.collect_imported_native_history
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
GRANT SELECT ON private.collect_imported_native_history TO collect_runtime;
CREATE POLICY collect_imported_native_history_runtime ON private.collect_imported_native_history
  FOR SELECT TO collect_runtime USING (true);
CREATE POLICY collect_imported_native_history_owner ON private.collect_imported_native_history
  TO postgres USING (true) WITH CHECK (true);

CREATE FUNCTION private.collect_imported_native_history_immutable()
RETURNS trigger LANGUAGE plpgsql SECURITY INVOKER SET search_path=pg_catalog AS $fn$
BEGIN
  RAISE EXCEPTION 'imported_native_history_immutable' USING ERRCODE='23514';
END
$fn$;
REVOKE ALL ON FUNCTION private.collect_imported_native_history_immutable()
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
CREATE TRIGGER collect_imported_native_history_immutable
  BEFORE UPDATE OR DELETE ON private.collect_imported_native_history
  FOR EACH ROW EXECUTE FUNCTION private.collect_imported_native_history_immutable();
ALTER TABLE private.collect_imported_native_history
  ENABLE ALWAYS TRIGGER collect_imported_native_history_immutable;

-- Recheck the completed cross-table provenance at commit, not just in JS.
CREATE FUNCTION private.collect_imported_native_history_check()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM private.burimunsi_native_receipt_origins o
    JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=o.source_id
    JOIN app.sms_receipts r ON r.id=o.source_id
    WHERE o.source_id=NEW.source_id AND o.collection_id=NEW.collection_id
      AND o.request_id=NEW.request_id AND o.body_sha256=NEW.body_sha256
      AND o.object_sha256=NEW.object_sha256 AND o.fingerprint=NEW.source_fingerprint
      AND j.collection_id=o.collection_id AND j.source_fingerprint=o.fingerprint
      AND j.transaction_id IS NOT DISTINCT FROM NEW.transaction_id
      AND r.owner_user_id=o.principal_user_id AND r.client_envelope_id=o.request_id::text
      AND r.body_sha256=o.body_sha256 AND r.object_sha256=o.object_sha256
      AND r.object_key='sms/'||o.source_id AND r.originating_session_id IS NULL
      AND r.receiver_hash IS NULL AND r.evidence_level='client_received'
  ) THEN RAISE EXCEPTION 'imported_native_history_mismatch' USING ERRCODE='23514'; END IF;
  RETURN NULL;
END
$fn$;
REVOKE ALL ON FUNCTION private.collect_imported_native_history_check()
  FROM PUBLIC, anon, authenticated, service_role, collect_runtime, collect_importer;
CREATE CONSTRAINT TRIGGER collect_imported_native_history_check
  AFTER INSERT ON private.collect_imported_native_history
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
  EXECUTE FUNCTION private.collect_imported_native_history_check();
