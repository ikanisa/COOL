-- SYNTHETIC-ONLY CANDIDATE: encrypted quarantine only. It is deliberately
-- refused outside a fixture-named Unix-socket database because adding this
-- relation to private without a retention inventory update breaks Collect's
-- existing unknown-class checks. This is not a production migration.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='30s';
SET LOCAL search_path=pg_catalog,pg_temp;
DO $$ DECLARE control private.collect_fence_control%ROWTYPE; BEGIN
 IF session_user<>'postgres' OR current_user<>'postgres'
  OR current_database() !~ '^collect_fixture_[a-z0-9_]+$' OR inet_server_addr() IS NOT NULL
  OR current_setting('cluster_name',true) IS DISTINCT FROM 'collect_quarantine_synthetic_only'
  OR coalesce(current_setting('role',true),'none') NOT IN('none','postgres')
  OR current_setting('transaction_isolation')<>'read committed'
  OR to_regclass('private.collect_pg_transfer_quarantine') IS NOT NULL
  OR to_regprocedure('private._collect_pg_quarantine_immutable()') IS NOT NULL
  OR to_regclass('private.collect_fence_control') IS NULL
  OR to_regclass('private.collect_deployment_identity') IS NULL
  OR to_regclass('private.collect_fence_admissions') IS NULL
  THEN RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='quarantine_install_refused'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(7346371,1);PERFORM pg_catalog.pg_advisory_xact_lock(7346371,2);
 SELECT * INTO control FROM private.collect_fence_control WHERE singleton IS TRUE FOR UPDATE;
 IF NOT FOUND OR control.project_ref IS DISTINCT FROM 'rrlduytparvsjfmegalh' OR control.mode IS DISTINCT FROM 'fenced'
  OR EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE state IS DISTINCT FROM 'settled' OR uncertain_dispatches IS DISTINCT FROM 0)
  OR NOT EXISTS(SELECT 1 FROM private.collect_deployment_identity WHERE singleton IS TRUE
   AND profile_sha256=pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(profile_raw,'UTF8')),'hex'))
 THEN RAISE EXCEPTION USING ERRCODE='55000', MESSAGE='quarantine_install_refused'; END IF;
END $$;
CREATE TABLE private.collect_pg_transfer_quarantine (
 operation_id uuid PRIMARY KEY,
 source_identity_sha256 text NOT NULL CHECK(source_identity_sha256 ~ '^[a-f0-9]{64}$'),
 source_batch_id uuid NOT NULL,
 plan_sha256 text NOT NULL CHECK(plan_sha256 ~ '^[a-f0-9]{64}$'),
 envelope_sha256 text NOT NULL CHECK(envelope_sha256 ~ '^[a-f0-9]{64}$'),
 envelope bytea NOT NULL CHECK(octet_length(envelope) BETWEEN 33 AND 4194336),
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(source_identity_sha256,source_batch_id),
 CHECK(encode(sha256(envelope),'hex')=envelope_sha256)
);
ALTER TABLE private.collect_pg_transfer_quarantine ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.collect_pg_transfer_quarantine FROM PUBLIC,anon,authenticated,service_role,collect_runtime;
CREATE FUNCTION private._collect_pg_quarantine_immutable() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $$BEGIN
  RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='quarantine_immutable';
 END$$;
CREATE TRIGGER collect_pg_quarantine_immutable BEFORE UPDATE OR DELETE OR TRUNCATE
 ON private.collect_pg_transfer_quarantine FOR EACH STATEMENT EXECUTE FUNCTION private._collect_pg_quarantine_immutable();
ALTER TABLE private.collect_pg_transfer_quarantine ENABLE ALWAYS TRIGGER collect_pg_quarantine_immutable;
REVOKE ALL ON FUNCTION private._collect_pg_quarantine_immutable() FROM PUBLIC,anon,authenticated,service_role,collect_runtime;
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT DISTINCT a.grantee FROM pg_catalog.pg_class c,
  LATERAL pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
  WHERE c.oid='private.collect_pg_transfer_quarantine'::regclass AND a.grantee<>0 AND a.grantee<>c.relowner
 LOOP EXECUTE format('REVOKE ALL ON private.collect_pg_transfer_quarantine FROM %I',pg_catalog.pg_get_userbyid(r.grantee)); END LOOP;
 FOR r IN SELECT DISTINCT a.grantee FROM pg_catalog.pg_proc p,
  LATERAL pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
  WHERE p.oid='private._collect_pg_quarantine_immutable()'::regprocedure AND a.grantee<>0 AND a.grantee<>p.proowner
 LOOP EXECUTE format('REVOKE ALL ON FUNCTION private._collect_pg_quarantine_immutable() FROM %I',pg_catalog.pg_get_userbyid(r.grantee)); END LOOP;
END $$;
COMMIT;
