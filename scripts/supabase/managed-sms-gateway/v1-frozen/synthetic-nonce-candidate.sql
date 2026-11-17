-- Uninstalled, unversioned qualification candidate. This file must not be
-- applied to a managed project; actual predecessor, privileges and retention
-- treatment require independent review and a forward migration decision.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$ BEGIN
 IF current_user<>'postgres' OR session_user<>'postgres' OR current_setting('transaction_isolation')<>'read committed'
  OR to_regclass('private.collect_sms_fence_admissions') IS NULL OR to_regclass('private.collect_deployment_identity') IS NULL
  OR to_regprocedure('collect_sms.work_assert_write(uuid,bigint,text)') IS NULL
  OR to_regprocedure('private.collect_assert_deployment(text)') IS NULL
  OR NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='collect_sms_runtime')
  OR to_regclass('private.collect_sms_ingress_nonce_uses') IS NOT NULL
  OR to_regprocedure('collect_sms.consume_ingress_nonce(uuid,text,text,bigint)') IS NOT NULL
 THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='sms_nonce_predecessor_unqualified';END IF;
END;$preflight$;
CREATE TABLE private.collect_sms_ingress_nonce_uses(
 nonce uuid PRIMARY KEY,
 profile_sha256 text NOT NULL CHECK(profile_sha256 ~ '^[a-f0-9]{64}$'),
 policy_sha256 text NOT NULL CHECK(policy_sha256 ~ '^[a-f0-9]{64}$'),
 signed_at timestamptz NOT NULL,
 expires_at timestamptz NOT NULL,
 consumed_at timestamptz NOT NULL DEFAULT pg_catalog.clock_timestamp(),
 CHECK(expires_at=signed_at+interval '30 seconds')
);
CREATE INDEX collect_sms_ingress_nonce_expiry ON private.collect_sms_ingress_nonce_uses(expires_at,nonce);
ALTER TABLE private.collect_sms_ingress_nonce_uses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.collect_sms_ingress_nonce_uses FROM PUBLIC;
CREATE FUNCTION collect_sms.consume_ingress_nonce(p_nonce uuid,p_profile text,p_policy text,p_issued_ms bigint)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE now_ms bigint;inserted uuid;admission uuid;profile text;
BEGIN
 admission:=NULLIF(current_setting('collect.fence_admission_id',true),'')::uuid;
 PERFORM collect_sms.work_assert_write(admission,NULLIF(current_setting('collect.fence_epoch',true),'')::bigint,
  NULLIF(current_setting('collect.fence_source_sha256',true),''));
 IF p_nonce IS NULL OR p_nonce::text !~ '^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$'
  OR p_profile IS NULL OR p_profile !~ '^[a-f0-9]{64}$' OR p_policy IS NULL OR p_policy !~ '^[a-f0-9]{64}$'
  OR p_issued_ms IS NULL THEN RAISE EXCEPTION USING ERRCODE='22023',MESSAGE='sms_ingress_invalid';END IF;
 SELECT profile_sha256 INTO profile FROM private.collect_sms_fence_admissions WHERE admission_id=admission;
 IF profile IS DISTINCT FROM p_profile THEN RAISE EXCEPTION USING ERRCODE='55000',MESSAGE='sms_ingress_profile_conflict';END IF;
 PERFORM private.collect_assert_deployment(p_profile);
 PERFORM pg_catalog.pg_advisory_xact_lock(7346371,319);
 now_ms:=pg_catalog.floor(pg_catalog.date_part('epoch',pg_catalog.clock_timestamp())*1000)::bigint;
 IF p_issued_ms>now_ms+2000 OR p_issued_ms<now_ms-30000 THEN RETURN false;END IF;
 WITH expired AS (SELECT nonce FROM private.collect_sms_ingress_nonce_uses
  WHERE expires_at<pg_catalog.clock_timestamp()-interval '2 minutes' ORDER BY expires_at,nonce LIMIT 256)
 DELETE FROM private.collect_sms_ingress_nonce_uses ledger USING expired WHERE ledger.nonce=expired.nonce;
 IF (SELECT pg_catalog.count(*) FROM private.collect_sms_ingress_nonce_uses)>=100000 THEN RETURN false;END IF;
 INSERT INTO private.collect_sms_ingress_nonce_uses(nonce,profile_sha256,policy_sha256,signed_at,expires_at)
 VALUES(p_nonce,p_profile,p_policy,pg_catalog.to_timestamp(p_issued_ms/1000.0),pg_catalog.to_timestamp(p_issued_ms/1000.0)+interval '30 seconds')
 ON CONFLICT(nonce) DO NOTHING RETURNING nonce INTO inserted;
 RETURN inserted IS NOT NULL;
END;$fn$;
REVOKE ALL ON FUNCTION collect_sms.consume_ingress_nonce(uuid,text,text,bigint) FROM PUBLIC;
DO $acl$ DECLARE r record;BEGIN
 FOR r IN SELECT DISTINCT a.grantee FROM pg_catalog.pg_class c,LATERAL pg_catalog.aclexplode(coalesce(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
  WHERE c.oid='private.collect_sms_ingress_nonce_uses'::regclass AND a.grantee<>0 AND a.grantee<>c.relowner
 LOOP EXECUTE pg_catalog.format('REVOKE ALL ON private.collect_sms_ingress_nonce_uses FROM %I',pg_catalog.pg_get_userbyid(r.grantee));END LOOP;
 FOR r IN SELECT DISTINCT a.grantee FROM pg_catalog.pg_proc p,LATERAL pg_catalog.aclexplode(coalesce(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
  WHERE p.oid='collect_sms.consume_ingress_nonce(uuid,text,text,bigint)'::regprocedure AND a.grantee<>0 AND a.grantee<>p.proowner
 LOOP EXECUTE pg_catalog.format('REVOKE ALL ON FUNCTION collect_sms.consume_ingress_nonce(uuid,text,text,bigint) FROM %I',pg_catalog.pg_get_userbyid(r.grantee));END LOOP;
END;$acl$;
GRANT EXECUTE ON FUNCTION collect_sms.consume_ingress_nonce(uuid,text,text,bigint) TO collect_sms_runtime;
COMMIT;
