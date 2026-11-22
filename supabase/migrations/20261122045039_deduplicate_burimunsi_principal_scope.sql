-- Keep the account uniqueness constraint and remove its duplicate write index.
BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;
SET LOCAL lock_timeout = '5s';
LOCK TABLE private.burimunsi_accounts IN ACCESS EXCLUSIVE MODE;

DO $index_check$
DECLARE
  duplicate_index regclass := to_regclass('private.burimunsi_provisioning_one_principal_per_scope');
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint AS constraint_def
    JOIN pg_index AS index_def ON index_def.indexrelid = constraint_def.conindid
    WHERE constraint_def.conrelid = 'private.burimunsi_accounts'::regclass
      AND constraint_def.conname = 'burimunsi_one_principal_per_scope'
      AND constraint_def.contype = 'u'
      AND constraint_def.convalidated
      AND index_def.indisvalid AND index_def.indisready AND index_def.indimmediate
      AND pg_get_indexdef(index_def.indexrelid) =
        'CREATE UNIQUE INDEX burimunsi_one_principal_per_scope ON private.burimunsi_accounts USING btree (collection_id, principal_user_id)'
  ) THEN
    RAISE EXCEPTION 'burimunsi_principal_scope_constraint_changed' USING ERRCODE = '55000';
  END IF;

  IF duplicate_index IS NOT NULL AND (
    pg_get_indexdef(duplicate_index) IS DISTINCT FROM
      'CREATE UNIQUE INDEX burimunsi_provisioning_one_principal_per_scope ON private.burimunsi_accounts USING btree (collection_id, principal_user_id)'
    OR EXISTS (SELECT 1 FROM pg_constraint WHERE conindid = duplicate_index)
  ) THEN
    RAISE EXCEPTION 'burimunsi_principal_scope_index_changed' USING ERRCODE = '55000';
  END IF;
END;
$index_check$;

DROP INDEX IF EXISTS private.burimunsi_provisioning_one_principal_per_scope;
COMMIT;
