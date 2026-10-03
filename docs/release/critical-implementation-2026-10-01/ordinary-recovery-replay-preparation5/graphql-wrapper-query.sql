-- PostgreSQL17 read-only recovery identity. Names replace OIDs; source/default/
-- configuration values are hashed. This does not read business or Auth rows.
-- Full archive data, schema and role comparisons remain separate requirements.
-- NULL ACLs expand to PostgreSQL defaults: pg_dump may omit redundant default
-- ACL entries. Explicit empty ACLs retain zero grants; all entries remain intact.
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL timezone = 'UTC';
SET LOCAL statement_timeout = '120s';
WITH ns AS (
  SELECT * FROM pg_namespace WHERE left(nspname,3) <> 'pg_' AND nspname <> 'information_schema'
), rel AS (
  SELECT c.*, n.nspname FROM pg_class c JOIN ns n ON n.oid=c.relnamespace
), routine AS (
  SELECT p.*, n.nspname FROM pg_proc p JOIN ns n ON n.oid=p.pronamespace
), dependency AS (
  SELECT d.deptype, a.type AS object_type, a.schema AS object_schema,
    a.identity AS object_identity, b.type AS referenced_type,
    b.schema AS referenced_schema, b.identity AS referenced_identity
  FROM pg_depend d
  CROSS JOIN LATERAL pg_identify_object(d.classid,d.objid,d.objsubid) a
  CROSS JOIN LATERAL pg_identify_object(d.refclassid,d.refobjid,d.refobjsubid) b
  WHERE (a.schema IN (SELECT nspname FROM ns) OR b.schema IN (SELECT nspname FROM ns))
    -- Rebuilt TOAST names and internal FK trigger names contain source OIDs.
    -- Their logical table/column/constraint definitions are compared above.
    AND (a.schema IS NULL OR left(a.schema,3) <> 'pg_')
    AND NOT (d.classid='pg_trigger'::regclass AND EXISTS (
      SELECT 1 FROM pg_trigger t WHERE t.oid=d.objid AND t.tgisinternal))
)
SELECT jsonb_build_object(
 'schemas',(SELECT coalesce(jsonb_agg(jsonb_build_array(nspname,pg_get_userbyid(nspowner),
   to_jsonb(ARRAY(SELECT x::text FROM unnest(coalesce(nspacl,acldefault('n',nspowner))) x ORDER BY x::text COLLATE "C")))
   ORDER BY nspname COLLATE "C"),'[]') FROM ns),
 'functions',(SELECT coalesce(jsonb_agg(jsonb_build_array(nspname,proname,
   pg_get_function_identity_arguments(oid),prokind,pg_get_userbyid(proowner),
   prosecdef,provolatile,proparallel,proleakproof,proisstrict,
   to_jsonb(ARRAY(SELECT x::text FROM unnest(coalesce(proacl,acldefault('f',proowner))) x ORDER BY x::text COLLATE "C")),
   encode(sha256(convert_to(prosrc,'UTF8')),'hex'),
   CASE WHEN prokind <> 'a' THEN encode(sha256(convert_to(pg_get_functiondef(oid),'UTF8')),'hex') END)
   ORDER BY nspname COLLATE "C",proname COLLATE "C",pg_get_function_identity_arguments(oid) COLLATE "C"),'[]') FROM routine),
 'dependencies',(SELECT coalesce(jsonb_agg(jsonb_build_array(deptype,object_type,object_schema,
   object_identity,referenced_type,referenced_schema,referenced_identity)
   ORDER BY deptype,object_type COLLATE "C",object_schema COLLATE "C",object_identity COLLATE "C",
   referenced_type COLLATE "C",referenced_schema COLLATE "C",referenced_identity COLLATE "C"),'[]') FROM dependency)
);
COMMIT;
