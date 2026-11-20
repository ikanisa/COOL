-- Forward migration from Collect production-20261116-005 after Storage v1.90.1.
-- Vendor identity: supabase/storage b2614c21b8133353009f284e1c9f8e8fbf9dda10.
-- Apply through the fenced migration operator with the next Collect receipt.
BEGIN;
SET LOCAL search_path = pg_catalog, pg_temp;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $install$
DECLARE
  expected_profile constant text := '18f9b92d996651911d57693b7ba7e3c1c782c85cf17142983f2061ea592de5c1';
  expected_source constant text := '9559229f34e297bbc7ad7c379a27e2a81fd4f419b4bfbce8926c290730c3067c';
  expected_app_prefix constant text := '24610061c44731ecaec5d748c4bace03ad6388ebce30c462602079abf8667e12';
  expected_storage_prefix constant text := 'df563bbf22c90a397c3baee6f48c08566d7cf3a1dc23aeee2d08623a7e9f94dc';
  expected_storage_suffix constant jsonb := '[
    [75, "enforce-bucket-lifecycle-update-role", "8454a556116c985db857d3b99de94a31a68ad273"],
    [76, "noncurrent-lifecycle", "052cbe11956fd14b85861fc19537c0303b73010e"],
    [77, "noncurrent-lifecycle-archived-order-index", "d68b03438a987aa1324a0fca68f7078cb2ffb849"],
    [78, "noncurrent-lifecycle-archived-due-index", "c82ba0e577ec5c3496b1077ff385ce4645497698"],
    [79, "lifecycle-writer-coordination", "3b38458424d2099e6b2e3cb4233590060f527fe1"],
    [80, "revoke-extra-lifecycle-postgres-grants", "18cfbf5c5b356469e1e95f3aa1b59ba111d82a06"]
  ]';
  expected_shape constant text := '967a55245c51a1fee2dcaa65d1598fde05d60a0cc7f6f5b0eb9287c556f3f89e';
  lifecycle_classes constant jsonb :=
    '["managed:storage_bucket_lifecycle_states","managed:storage_lifecycle_abandoned_artifacts"]';
  shape_sql constant text := $shape$
WITH lifecycle_relations AS (
  SELECT c.*
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'storage'
    AND c.relname IN ('bucket_lifecycle_states', 'lifecycle_abandoned_artifacts')
), relation_shapes AS (
  SELECT lifecycle_row.relname, jsonb_build_object(
    'name', lifecycle_row.relname,
    'kind', lifecycle_row.relkind,
    'owner', pg_get_userbyid(lifecycle_row.relowner),
    'persistence', lifecycle_row.relpersistence,
    'partition', lifecycle_row.relispartition,
    'rls', lifecycle_row.relrowsecurity,
    'force_rls', lifecycle_row.relforcerowsecurity,
    'acl', (
      SELECT jsonb_agg(jsonb_build_object(
        'grantor', pg_get_userbyid(a.grantor),
        'role', CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END,
        'privilege', a.privilege_type, 'grantable', a.is_grantable)
        ORDER BY pg_get_userbyid(a.grantor) COLLATE "C",
                 (CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END) COLLATE "C",
                 a.privilege_type COLLATE "C")
      FROM pg_catalog.aclexplode(coalesce(lifecycle_row.relacl, acldefault('r', lifecycle_row.relowner))) a
    ),
    'columns', (
      SELECT jsonb_agg(jsonb_build_object(
        'name', a.attname, 'type', format_type(a.atttypid, a.atttypmod),
        'not_null', a.attnotnull, 'generated', a.attgenerated, 'identity', a.attidentity,
        'acl', a.attacl::text, 'default', pg_get_expr(d.adbin, d.adrelid)) ORDER BY a.attnum)
      FROM pg_catalog.pg_attribute a
      LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
      WHERE a.attrelid = lifecycle_row.oid AND a.attnum > 0 AND NOT a.attisdropped
    ),
    'constraints', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'name', c.conname, 'type', c.contype, 'definition', pg_get_constraintdef(c.oid, true),
        'validated', c.convalidated) ORDER BY c.conname COLLATE "C"), '[]'::jsonb)
      FROM pg_catalog.pg_constraint c WHERE c.conrelid = lifecycle_row.oid
    ),
    'indexes', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'name', x.relname, 'definition', pg_get_indexdef(x.oid), 'valid', i.indisvalid,
        'ready', i.indisready, 'live', i.indislive) ORDER BY x.relname COLLATE "C"), '[]'::jsonb)
      FROM pg_catalog.pg_index i JOIN pg_catalog.pg_class x ON x.oid = i.indexrelid
      WHERE i.indrelid = lifecycle_row.oid
    ),
    'user_triggers', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'name', t.tgname, 'definition', pg_get_triggerdef(t.oid), 'enabled', t.tgenabled)
        ORDER BY t.tgname COLLATE "C"), '[]'::jsonb)
      FROM pg_catalog.pg_trigger t WHERE t.tgrelid = lifecycle_row.oid AND NOT t.tgisinternal
    ),
    'policies', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'name', p.polname, 'command', p.polcmd, 'permissive', p.polpermissive,
        'roles', (SELECT jsonb_agg(role_name ORDER BY role_name COLLATE "C") FROM (
          SELECT CASE WHEN role_id = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_id) END AS role_name
          FROM unnest(p.polroles) AS grantees(role_id)
        ) roles),
        'using', pg_get_expr(p.polqual, p.polrelid), 'check', pg_get_expr(p.polwithcheck, p.polrelid))
        ORDER BY p.polname COLLATE "C"), '[]'::jsonb)
      FROM pg_catalog.pg_policy p WHERE p.polrelid = lifecycle_row.oid
    )
  ) AS shape
  FROM lifecycle_relations lifecycle_row
), observed AS (
  SELECT count(*) AS relation_count, coalesce(jsonb_agg(shape ORDER BY relname COLLATE "C"), '[]'::jsonb) AS shape
  FROM relation_shapes
)
SELECT jsonb_build_object(
  'relation_count', relation_count,
  'sha256', encode(sha256(convert_to(shape::text, 'UTF8')), 'hex'),
  'shape', shape
)
FROM observed
$shape$;
  predecessor record;
  receipt_count bigint;
  prefix_digest text;
  storage_suffix jsonb;
  observed_shape jsonb;
  body text;
  anchor text;
  next_body text;
BEGIN
  PERFORM private._collect_fence_require_operator();
  PERFORM private.collect_assert_deployment(expected_profile);
  IF current_user <> 'postgres' OR session_user <> 'postgres'
    OR NOT EXISTS (
      SELECT 1 FROM private.collect_fence_control
      WHERE singleton AND mode = 'fenced' AND source_sha256 = expected_source
    )
    OR EXISTS (SELECT 1 FROM private.collect_fence_control WHERE mode <> 'fenced')
  THEN
    RAISE EXCEPTION 'storage_lifecycle_retention_precondition' USING ERRCODE = '55000';
  END IF;

  SELECT count(*), encode(sha256(convert_to(
    string_agg(version || ':' || source_sha256 || ':' || profile_sha256, E'\n' ORDER BY version COLLATE "C"),
    'UTF8')), 'hex')
  INTO receipt_count, prefix_digest
  FROM supabase_migrations.collect_installation_steps;
  IF receipt_count <> 61 OR prefix_digest IS DISTINCT FROM expected_app_prefix THEN
    RAISE EXCEPTION 'storage_lifecycle_retention_app_history_changed' USING ERRCODE = '55000';
  END IF;

  SELECT count(*), encode(sha256(convert_to(
    (jsonb_agg(jsonb_build_array(id, name, hash) ORDER BY id) FILTER (WHERE id BETWEEN 0 AND 74))::text,
    'UTF8')), 'hex'),
    jsonb_agg(jsonb_build_array(id, name, hash) ORDER BY id) FILTER (WHERE id >= 75)
  INTO receipt_count, prefix_digest, storage_suffix
  FROM storage.migrations;
  IF receipt_count <> 81 OR prefix_digest IS DISTINCT FROM expected_storage_prefix
    OR storage_suffix IS DISTINCT FROM expected_storage_suffix
  THEN
    RAISE EXCEPTION 'storage_lifecycle_retention_vendor_history_changed' USING ERRCODE = '55000';
  END IF;

  FOR predecessor IN SELECT * FROM (VALUES
    ('private._retention_manifest_catalog_v2()', 'd52ac01bf7b93c13358eacf5d12c3effa6a5ac2baedd6941eed937bee3e69c14',
      false, 'i', 'pg_catalog, pg_temp', 'sql', '{postgres=X/postgres}'),
    ('private._retention_manifest_schema_v2()', 'afad38d443badf352c865abb5ca1f9fd939566da05c1c29f50f10ab8905a3feb',
      true, 's', 'pg_catalog, pg_temp', 'plpgsql', '{postgres=X/postgres}'),
    ('private._retention_manifest_rows_v2(text)', '25597e57accb602949e65108db895113ee66e657b5c20e4cc1fbbdabf266973a',
      true, 's', 'app, pg_catalog, pg_temp', 'plpgsql', '{postgres=X/postgres}'),
    ('private._retention_manifest_managed_rows_v2(text,integer)', 'db1a1d463de7d7e40bf5c3a7ff73f9d82f2b7b538c670bd8b2bd1c7c8ee19f21',
      true, 's', 'app, pg_catalog, pg_temp', 'plpgsql', '{postgres=X/postgres}'),
    ('private._retention_row_policy_v2(uuid,text,text,text)', '642f9f6545776e0ed6abca60007a9ea8c2d79faed0945d70ccbc8219eaa86228',
      true, 's', 'pg_catalog, pg_temp', 'plpgsql', '{postgres=X/postgres}'),
    ('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)', 'd9364415fdc44d1052619b7e916f6949b0c53ab0e6c344b67b0eee62af4f0adc',
      true, 'v', 'pg_catalog, pg_temp', 'plpgsql', '{postgres=X/postgres,collect_runtime=X/postgres}'),
    ('private.retention_inventory_page_v2(uuid,text,integer,boolean)', '99820b4f1d91afa5610edda1f138d4c12bcd9765297225c684cc9f26c6e5266f',
      true, 'v', 'pg_catalog, pg_temp', 'plpgsql', '{postgres=X/postgres,collect_runtime=X/postgres}')
  ) AS value(signature, body_sha256, definer, volatility, search_path, language, acl) LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid = p.prolang
      WHERE p.oid = to_regprocedure(predecessor.signature)
        AND pg_get_userbyid(p.proowner) = 'postgres'
        AND p.prosecdef = predecessor.definer AND p.provolatile = predecessor.volatility
        AND p.prokind = 'f' AND p.proparallel = 'u' AND NOT p.proleakproof
        AND l.lanname = predecessor.language AND p.proacl::text = predecessor.acl
        AND p.proconfig = ARRAY['search_path=' || predecessor.search_path]
        AND encode(sha256(convert_to(p.prosrc, 'UTF8')), 'hex') = predecessor.body_sha256
    ) THEN
      RAISE EXCEPTION 'storage_lifecycle_retention_predecessor_changed' USING ERRCODE = '55000';
    END IF;
  END LOOP;

  EXECUTE shape_sql INTO observed_shape;
  IF (observed_shape->>'relation_count')::integer IS DISTINCT FROM 2
    OR observed_shape->>'sha256' IS DISTINCT FROM expected_shape
    OR private._retention_manifest_catalog_v2()->'copy_classes'
       ?| ARRAY['managed:storage_bucket_lifecycle_states', 'managed:storage_lifecycle_abandoned_artifacts']
  THEN
    RAISE EXCEPTION 'storage_lifecycle_retention_schema_changed' USING ERRCODE = '55000';
  END IF;

  -- Use the existing unverified, subject-count-unknown and erasure-blocked copy descriptor.
  SELECT prosrc INTO STRICT body FROM pg_proc
  WHERE oid = 'private._retention_manifest_catalog_v2()'::regprocedure;
  next_body := format(
    'SELECT jsonb_set(base, ''{copy_classes}'', (base->''copy_classes'') || %L::jsonb) FROM (%s) prior(base)',
    lifecycle_classes, body
  );
  EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb'
    || ' LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS ' || quote_literal(next_body);

  SELECT prosrc INTO STRICT body FROM pg_proc
  WHERE oid = 'private._retention_manifest_schema_v2()'::regprocedure;
  anchor := $anchor$'buckets','buckets_analytics','buckets_vectors','iceberg_namespaces','iceberg_tables','migrations'$anchor$;
  IF length(body) - length(replace(body, anchor, '')) <> length(anchor) THEN
    RAISE EXCEPTION 'storage_lifecycle_retention_schema_anchor_changed' USING ERRCODE = '55000';
  END IF;
  next_body := replace(body, anchor, anchor
    || $relations$,'bucket_lifecycle_states','lifecycle_abandoned_artifacts'$relations$);

  -- Recheck both exact shapes on future captures while retaining all unknown-relation refusals.
  anchor := E'BEGIN\n FOR r IN SELECT n.nspname,c.relname,c.relkind,c.oid FROM pg_class';
  IF length(next_body) - length(replace(next_body, anchor, '')) <> length(anchor) THEN
    RAISE EXCEPTION 'storage_lifecycle_retention_shape_anchor_changed' USING ERRCODE = '55000';
  END IF;
  next_body := replace(next_body, anchor, format($verify$BEGIN
 IF ((%s)->>'sha256') IS DISTINCT FROM %L THEN
  RAISE EXCEPTION 'retention_manifest_storage_lifecycle_shape_changed' USING ERRCODE = '42501';
 END IF;
 FOR r IN SELECT n.nspname,c.relname,c.relkind,c.oid FROM pg_class$verify$, shape_sql, expected_shape));
  EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_schema_v2() RETURNS jsonb'
    || ' LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS ' || quote_literal(next_body);

  -- Treat both classes as unresolved copies when sealing a new manifest.
  SELECT prosrc INTO STRICT body FROM pg_proc
  WHERE oid = 'private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure;
  anchor := $anchor$'managed:storage','managed:storage_iceberg_namespaces','managed:storage_iceberg_tables','r2:sms_receipts'$anchor$;
  IF length(body) - length(replace(body, anchor, '')) <> length(anchor) THEN
    RAISE EXCEPTION 'storage_lifecycle_retention_capture_anchor_changed' USING ERRCODE = '55000';
  END IF;
  next_body := replace(body, anchor, anchor
    || $classes$,'managed:storage_bucket_lifecycle_states','managed:storage_lifecycle_abandoned_artifacts'$classes$);
  EXECUTE 'CREATE OR REPLACE FUNCTION private.retention_capture_inventory_v2('
    || 'p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000)'
    || ' RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS ' || quote_literal(next_body);

  PERFORM private._retention_manifest_schema_v2();
END;
$install$;
COMMIT;
