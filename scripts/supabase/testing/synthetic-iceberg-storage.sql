-- Test-fixture metadata only. Never execute on an application database.
-- The owner, columns and foreign keys match the Storage catalog admitted by
-- the reviewed 307 migration; there are no rows or remote objects.
DO $fixture$
DECLARE role_row pg_roles%ROWTYPE;
BEGIN
 IF current_user<>'collect_test' OR session_user<>'collect_test'
  OR host(inet_server_addr()) IS DISTINCT FROM '127.0.0.1'
  OR current_database() !~ '^collect_selfhost_(backend|auth|notifications|recovery|gateway|integration)_[a-f0-9]{24}_test$'
  OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=current_user AND rolsuper)
  OR to_regnamespace('storage') IS NOT NULL THEN
  RAISE EXCEPTION 'synthetic_iceberg_fixture_required' USING ERRCODE='55000';END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.synthetic.iceberg.storage.role',0));
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='supabase_storage_admin') THEN
  CREATE ROLE supabase_storage_admin NOLOGIN NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB NOBYPASSRLS NOREPLICATION;
 END IF;
 SELECT * INTO STRICT role_row FROM pg_roles WHERE rolname='supabase_storage_admin';
 IF role_row.rolcanlogin OR role_row.rolsuper OR role_row.rolinherit OR role_row.rolcreaterole
  OR role_row.rolcreatedb OR role_row.rolbypassrls OR role_row.rolreplication THEN
  RAISE EXCEPTION 'synthetic_iceberg_role_invalid' USING ERRCODE='55000';END IF;
END;$fixture$;
CREATE SCHEMA storage AUTHORIZATION supabase_storage_admin;
SET ROLE supabase_storage_admin;
CREATE TYPE storage.buckettype AS ENUM ('ANALYTICS');
CREATE TABLE storage.buckets_analytics(
 name text NOT NULL,
 type storage.buckettype NOT NULL DEFAULT 'ANALYTICS'::storage.buckettype,
 format text NOT NULL DEFAULT 'ICEBERG'::text,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 deleted_at timestamptz
);
CREATE TABLE storage.iceberg_namespaces(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 bucket_name text NOT NULL,
 name text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
 catalog_id uuid NOT NULL REFERENCES storage.buckets_analytics(id) ON DELETE CASCADE
);
CREATE TABLE storage.iceberg_tables(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 namespace_id uuid NOT NULL REFERENCES storage.iceberg_namespaces(id) ON DELETE CASCADE,
 bucket_name text NOT NULL,
 name text NOT NULL,
 location text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 remote_table_id text,
 shard_key text,
 shard_id text,
 catalog_id uuid NOT NULL REFERENCES storage.buckets_analytics(id) ON DELETE CASCADE
);
ALTER TABLE storage.buckets_analytics ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.iceberg_namespaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.iceberg_tables ENABLE ROW LEVEL SECURITY;
RESET ROLE;
GRANT USAGE,CREATE ON SCHEMA storage TO postgres;
