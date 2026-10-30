-- Additive safe-code diagnostics. Existing baseline/migration bytes stay immutable.
-- Reports contain no subject, session, device, exception, stack, URL or raw text.
BEGIN;
CREATE TABLE app.client_diagnostic_reports (
 report_id text PRIMARY KEY CHECK(report_id ~ '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'),
 payload_sha256 text NOT NULL CHECK(payload_sha256 ~ '^[a-f0-9]{64}$'),
 surface text NOT NULL CHECK(surface IN('member','admin')),
 environment text NOT NULL CHECK(environment IN('local','development','staging','production','unknown')),
 build_version text NOT NULL CHECK(length(build_version)<=32 AND build_version ~ '^(unknown|[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?)$'),
 source_revision text NOT NULL CHECK(source_revision ~ '^(unknown|[a-f0-9]{40}|[a-f0-9]{64})$'),
 code text NOT NULL CHECK(code IN('startupStarted','startupWaiting','startupTimedOut','startupFailed','startupReady','frameworkFailure','platformFailure','diagnosticsSuppressed')),
 fingerprint text NOT NULL CHECK(fingerprint ~ '^[a-f0-9]{64}$'),
 occurrences bigint NOT NULL CHECK(occurrences BETWEEN 1 AND 64),
 attempt bigint NOT NULL CHECK(attempt BETWEEN 1 AND 1000),
 elapsed_ms bigint NOT NULL CHECK(elapsed_ms BETWEEN 0 AND 86400000),
 received_hour bigint NOT NULL CHECK(received_hour>=0 AND received_hour%3600=0),
 expires_at bigint NOT NULL CHECK(expires_at>received_hour AND expires_at<=received_hour+90000)
);
CREATE INDEX client_diagnostic_reports_expiry ON app.client_diagnostic_reports(expires_at,report_id);
ALTER TABLE app.client_diagnostic_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.client_diagnostic_reports FORCE ROW LEVEL SECURITY;
CREATE POLICY client_diagnostic_runtime ON app.client_diagnostic_reports TO collect_runtime USING(true) WITH CHECK(true);
REVOKE ALL ON app.client_diagnostic_reports FROM PUBLIC;
DO $$DECLARE r text;BEGIN
 FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname=r) THEN EXECUTE format('REVOKE ALL ON app.client_diagnostic_reports FROM %I',r);END IF;
 END LOOP;
END$$;
GRANT SELECT,INSERT,DELETE ON app.client_diagnostic_reports TO collect_runtime;
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
 ON app.client_diagnostic_reports FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE app.client_diagnostic_reports ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
COMMIT;
