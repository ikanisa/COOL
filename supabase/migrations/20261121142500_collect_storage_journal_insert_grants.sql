-- Journal creation accepts only the arguments supplied by PostgresStorageJournal.
-- PostgreSQL supplies initial state, evidence timestamps and empty completion fields.
BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $grants$
DECLARE
  target record;
  relation regclass;
BEGIN
  PERFORM private._collect_fence_require_operator();
  PERFORM 1 FROM private.collect_fence_control WHERE singleton AND mode = 'fenced' FOR SHARE;
  IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'collect_runtime' AND NOT rolsuper AND NOT rolbypassrls
  ) OR pg_has_role('collect_runtime', 'postgres', 'MEMBER') THEN
    RAISE EXCEPTION 'storage_journal_insert_precondition' USING ERRCODE = '55000';
  END IF;

  FOR target IN SELECT * FROM (VALUES
    ('private.storage_namespace', ARRAY['singleton','origin','bucket']),
    ('private.storage_payload_reservations', ARRAY['object_key','source_fingerprint','scope','aad','key_id','plaintext_sha256','sealed_body']),
    ('private.storage_put_intents', ARRAY['operation_id','object_key','fingerprint','sha256','size','scope','http_metadata','custom_metadata']),
    ('private.storage_upload_attempts', ARRAY['id','operation_id']),
    ('private.storage_objects', ARRAY['object_key','operation_id','fingerprint','sha256','size','scope','http_metadata','custom_metadata','etag']),
    ('private.storage_delete_intents', ARRAY['operation_id','object_key','fingerprint','expected_sha256','scope'])
  ) AS expected(name, columns) LOOP
    relation := to_regclass(target.name);
    IF NOT EXISTS (
      SELECT 1 FROM pg_class WHERE oid = relation AND relkind = 'r' AND pg_get_userbyid(relowner) = 'postgres'
    ) OR NOT has_table_privilege('collect_runtime', relation, 'INSERT') THEN
      RAISE EXCEPTION 'storage_journal_insert_preimage_changed' USING ERRCODE = '55000';
    END IF;

    EXECUTE format('REVOKE INSERT ON TABLE %s FROM collect_runtime', relation);
    EXECUTE format('GRANT INSERT (%s) ON TABLE %s TO collect_runtime', array_to_string(target.columns, ','), relation);
    IF has_table_privilege('collect_runtime', relation, 'INSERT') OR EXISTS (
      SELECT 1 FROM pg_attribute WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped
        AND (has_column_privilege('collect_runtime', relation, attnum, 'INSERT')
               IS DISTINCT FROM (attname::text = ANY(target.columns))
          OR has_column_privilege('collect_runtime', relation, attnum, 'INSERT WITH GRANT OPTION'))
    ) THEN
      RAISE EXCEPTION 'storage_journal_insert_unexpected_grants' USING ERRCODE = '55000';
    END IF;
  END LOOP;
END;
$grants$;
COMMIT;
