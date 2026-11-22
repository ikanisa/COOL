-- Restrict the existing runtime role to the columns written by native
-- account/session, gateway replacement and protected Storage entrypoints.
BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $grants$
DECLARE
  target record;
  relation regclass;
  privilege text;
  columns text[];
BEGIN
  PERFORM private._collect_fence_require_operator();
  PERFORM 1 FROM private.collect_fence_control WHERE singleton AND mode = 'fenced' FOR SHARE;
  IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'collect_runtime'
      AND NOT rolsuper AND NOT rolbypassrls
  ) OR pg_has_role('collect_runtime', 'postgres', 'MEMBER') THEN
    RAISE EXCEPTION 'collect_scoped_writer_precondition' USING ERRCODE = '55000';
  END IF;

  FOR target IN SELECT * FROM (VALUES
    ('private.burimunsi_accounts',
      ARRAY['id','collection_id','principal_user_id','phone','name','role','capabilities','pin_hash','created_at','updated_at'],
      ARRAY['name','phone','capabilities','pin_hash','active','removed','version','credential_version','updated_at']),
    ('private.burimunsi_sessions',
      ARRAY['id','collection_id','account_id','grant_id','installation_id','credential_version','grant_version',
            'token_hash','created_at','expires_at','principal_user_id'],
      ARRAY['revoked']),
    ('private.burimunsi_scopes', NULL, ARRAY['active_binding_id','binding_version','version']),
    ('private.storage_payload_reservations', NULL, ARRAY['sealed_body','cleared_at']),
    ('private.storage_put_intents', NULL,
      ARRAY['state','attempts','active_attempt','last_outcome','updated_at','upload_unresolved','delete_tombstone']),
    ('private.storage_upload_attempts', NULL, ARRAY['outcome','completed_at']),
    ('private.storage_delete_intents', NULL, ARRAY['state','last_outcome','absence_proof','committed_at'])
  ) AS expected(name, insert_columns, update_columns) LOOP
    relation := to_regclass(target.name);
    IF NOT EXISTS (
      SELECT 1 FROM pg_class WHERE oid = relation AND relkind = 'r'
        AND pg_get_userbyid(relowner) = 'postgres'
    ) THEN
      RAISE EXCEPTION 'collect_scoped_writer_relation_changed' USING ERRCODE = '55000';
    END IF;

    FOREACH privilege IN ARRAY ARRAY['INSERT','UPDATE'] LOOP
      columns := CASE privilege WHEN 'INSERT' THEN target.insert_columns ELSE target.update_columns END;
      IF columns IS NULL THEN CONTINUE; END IF;
      IF NOT has_table_privilege('collect_runtime', relation, privilege) THEN
        RAISE EXCEPTION 'collect_scoped_writer_preimage_changed' USING ERRCODE = '55000';
      END IF;
      EXECUTE format('REVOKE %s ON TABLE %s FROM collect_runtime', privilege, relation);
      EXECUTE format('GRANT %s (%s) ON TABLE %s TO collect_runtime',
        privilege, array_to_string(columns, ','), relation);
      IF has_table_privilege('collect_runtime', relation, privilege)
        OR EXISTS (
          SELECT 1 FROM pg_attribute
          WHERE attrelid = relation AND attnum > 0 AND NOT attisdropped
            AND (
              has_column_privilege('collect_runtime', relation, attnum, privilege)
                IS DISTINCT FROM (attname::text = ANY(columns))
              OR has_column_privilege('collect_runtime', relation, attnum, privilege || ' WITH GRANT OPTION')
            )
        ) THEN
        RAISE EXCEPTION 'collect_scoped_writer_unexpected_grants' USING ERRCODE = '55000';
      END IF;
    END LOOP;
  END LOOP;
END;
$grants$;
COMMIT;
