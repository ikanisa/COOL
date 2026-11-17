-- Synthetic-only isolated PostgreSQL fixture. Never run against Collect data.
CREATE SCHEMA private;
CREATE TABLE private.synthetic_onboarding_fixture_marker(marker text NOT NULL);
INSERT INTO private.synthetic_onboarding_fixture_marker VALUES ('burimunsi-onboarding-synthetic-only-v1');
DO $$DECLARE r text;BEGIN FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer','collect_runtime'] LOOP
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('CREATE ROLE %I NOLOGIN',r);END IF;END LOOP;END;$$;
CREATE TABLE private.collect_fence_control(mode text NOT NULL);
INSERT INTO private.collect_fence_control VALUES ('fenced');
CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE sql AS 'SELECT';
CREATE FUNCTION private._collect_fence_statement() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RETURN NULL;END;$$;
CREATE TABLE private.burimunsi_command_receipts(collection_id text NOT NULL,actor_id uuid NOT NULL,request_id uuid NOT NULL,
 session_id uuid NOT NULL,operation text NOT NULL,fingerprint text NOT NULL,response jsonb NOT NULL,created_at bigint NOT NULL,
 PRIMARY KEY(collection_id,actor_id,request_id));
ALTER TABLE private.burimunsi_command_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_command_receipts FORCE ROW LEVEL SECURITY;
CREATE POLICY burimunsi_scoped_runtime ON private.burimunsi_command_receipts TO collect_runtime
 USING (collection_id=current_setting('burimunsi.collection_id',true)) WITH CHECK(collection_id=current_setting('burimunsi.collection_id',true));
GRANT USAGE ON SCHEMA private TO collect_runtime;
GRANT SELECT,INSERT,UPDATE ON private.burimunsi_command_receipts TO collect_runtime;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_command_receipts
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.burimunsi_command_receipts ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
