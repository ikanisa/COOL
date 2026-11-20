-- Managed native ingress nonce ledger. This SQL has not been installed and is
-- not yet a versioned migration. Verify the managed owner, role graph and fence
-- preimage before incorporating it into the coordinated migration chain.
BEGIN;
CREATE TABLE private.collect_native_ingress_nonce_uses(
 nonce uuid PRIMARY KEY,
 profile_sha256 text NOT NULL CHECK(profile_sha256 ~ '^[a-f0-9]{64}$'),
 policy_sha256 text NOT NULL CHECK(policy_sha256 ~ '^[a-f0-9]{64}$'),
 signed_at timestamptz NOT NULL,
 expires_at timestamptz NOT NULL,
 consumed_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 CHECK(expires_at=signed_at+interval '30 seconds')
);
CREATE INDEX collect_native_ingress_nonce_expiry ON private.collect_native_ingress_nonce_uses(expires_at,nonce);
ALTER TABLE private.collect_native_ingress_nonce_uses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.collect_native_ingress_nonce_uses FROM PUBLIC;

CREATE FUNCTION private.collect_native_ingress_consume(p_nonce uuid,p_profile text,p_policy text,p_issued_ms bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE now_ms bigint; inserted uuid;
BEGIN
 PERFORM private._collect_fence_require_runtime();
 PERFORM private._collect_fence_require_rc(true);
 PERFORM private.collect_fence_assert_write(
  NULLIF(pg_catalog.current_setting('collect.fence_admission_id',true),'')::uuid,
  NULLIF(pg_catalog.current_setting('collect.fence_epoch',true),'')::bigint,
  NULLIF(pg_catalog.current_setting('collect.fence_source_sha256',true),''));
 IF p_nonce IS NULL OR p_nonce::text !~ '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'
  OR p_profile IS NULL OR p_profile !~ '^[a-f0-9]{64}$' OR p_policy IS NULL OR p_policy !~ '^[a-f0-9]{64}$'
  OR p_issued_ms IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='native_ingress_invalid';END IF;
 -- Serialize capacity and expiry cleanup with every claim. Saturation denies
 -- new claims; this global lock requires production load qualification.
 PERFORM pg_catalog.pg_advisory_xact_lock(7346371,318);
 now_ms:=pg_catalog.floor(pg_catalog.date_part('epoch',pg_catalog.clock_timestamp())*1000)::bigint;
 IF p_issued_ms>now_ms+2000 OR p_issued_ms<now_ms-30000 THEN RETURN false;END IF;
 WITH expired AS (SELECT nonce FROM private.collect_native_ingress_nonce_uses
  WHERE expires_at<pg_catalog.clock_timestamp()-interval '2 minutes' ORDER BY expires_at,nonce LIMIT 256)
 DELETE FROM private.collect_native_ingress_nonce_uses ledger USING expired WHERE ledger.nonce=expired.nonce;
 IF (SELECT pg_catalog.count(*) FROM private.collect_native_ingress_nonce_uses)>=100000 THEN RETURN false;END IF;
 INSERT INTO private.collect_native_ingress_nonce_uses(nonce,profile_sha256,policy_sha256,signed_at,expires_at)
 VALUES(p_nonce,p_profile,p_policy,pg_catalog.to_timestamp(p_issued_ms/1000.0),pg_catalog.to_timestamp(p_issued_ms/1000.0)+interval '30 seconds')
 ON CONFLICT(nonce) DO NOTHING RETURNING nonce INTO inserted;
 RETURN inserted IS NOT NULL;
END;$fn$;
REVOKE ALL ON FUNCTION private.collect_native_ingress_consume(uuid,text,text,bigint) FROM PUBLIC;
-- Remove non-owner default grants before allowing only the runtime entrypoint.
DO $fn$
DECLARE r record;
BEGIN
 FOR r IN SELECT DISTINCT a.grantee FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace,
  LATERAL pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
  WHERE n.nspname='private' AND c.relname='collect_native_ingress_nonce_uses' AND a.grantee<>0 AND a.grantee<>c.relowner
 LOOP EXECUTE pg_catalog.format('REVOKE ALL ON private.collect_native_ingress_nonce_uses FROM %I',pg_catalog.pg_get_userbyid(r.grantee));END LOOP;
 FOR r IN SELECT DISTINCT a.grantee FROM pg_catalog.pg_proc p,
  LATERAL pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
  WHERE p.oid=pg_catalog.to_regprocedure('private.collect_native_ingress_consume(uuid,text,text,bigint)') AND a.grantee<>0 AND a.grantee<>p.proowner
 LOOP EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION private.collect_native_ingress_consume(uuid,text,text,bigint) FROM %I',pg_catalog.pg_get_userbyid(r.grantee));END LOOP;
END;$fn$;
GRANT EXECUTE ON FUNCTION private.collect_native_ingress_consume(uuid,text,text,bigint) TO collect_runtime;
COMMIT;
