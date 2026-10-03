CREATE ROLE postgres NOSUPERUSER CREATEROLE CREATEDB LOGIN;
CREATE ROLE collect_catalog_reader NOLOGIN;
GRANT collect_catalog_reader TO postgres;
ALTER DATABASE postgres OWNER TO postgres;
SET ROLE postgres;
CREATE SCHEMA supabase_migrations AUTHORIZATION postgres;
CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY);
INSERT INTO supabase_migrations.schema_migrations VALUES ('202605230001'),('20261002050000');
CREATE SCHEMA auth AUTHORIZATION postgres;
CREATE SCHEMA receipt_worker_private AUTHORIZATION postgres;
ALTER DEFAULT PRIVILEGES IN SCHEMA receipt_worker_private GRANT SELECT ON TABLES TO collect_catalog_reader;
CREATE TYPE receipt_worker_private.outcome AS ENUM ('unknown','handled');
CREATE DOMAIN receipt_worker_private.positive_amount AS bigint CHECK (VALUE>=0);
CREATE TABLE receipt_worker_private.events(id bigint PRIMARY KEY,amount receipt_worker_private.positive_amount NOT NULL,
  outcome receipt_worker_private.outcome NOT NULL DEFAULT 'unknown');
CREATE TABLE public.receipts(id bigint PRIMARY KEY,event_id bigint REFERENCES receipt_worker_private.events(id),
  worker_secret text DEFAULT 'SYNTHETIC_CONFIG_SECRET');
CREATE INDEX receipt_event_idx ON public.receipts(event_id);
ALTER TABLE receipt_worker_private.events ENABLE ROW LEVEL SECURITY;
CREATE POLICY reader ON receipt_worker_private.events FOR SELECT TO collect_catalog_reader USING (amount>=0);
CREATE FUNCTION receipt_worker_private.guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
  SET search_path=pg_catalog AS $$BEGIN RETURN NEW; END$$;
REVOKE ALL ON FUNCTION receipt_worker_private.guard() FROM PUBLIC;
CREATE TRIGGER guard BEFORE INSERT ON public.receipts FOR EACH ROW EXECUTE FUNCTION receipt_worker_private.guard();
CREATE VIEW public.receipt_evidence AS SELECT r.id,e.amount FROM public.receipts r JOIN receipt_worker_private.events e ON e.id=r.event_id;
INSERT INTO receipt_worker_private.events VALUES (1,500,'handled');
INSERT INTO public.receipts(id,event_id) VALUES (1,1);
RESET ROLE;
