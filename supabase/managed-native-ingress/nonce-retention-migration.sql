-- Managed native ingress replay ledger and blocked retention classification.
-- Candidate only: requires the exact predecessor and a fenced controller.
-- NOT DEPLOYABLE: the transitive admission/stopped-fence helper preimages and
-- their dependent authority have not yet been completely qualified.
-- Privileged function/schema actors must be excluded through COMMIT; the table
-- locks below do not prevent an independent CREATE OR REPLACE FUNCTION.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE r record;c private.collect_fence_control%ROWTYPE;
BEGIN
 IF session_user<>'postgres' OR current_user<>'postgres' OR current_setting('transaction_isolation')<>'read committed'
  OR current_setting('session_replication_role')<>'origin'
  OR to_regclass('private.collect_native_ingress_nonce_uses') IS NOT NULL
  OR to_regprocedure('private.collect_native_ingress_consume(uuid,text,text,bigint)') IS NOT NULL THEN
  RAISE EXCEPTION 'native_nonce_install_refused' USING ERRCODE='55000';END IF;
 FOR r IN SELECT * FROM (VALUES
  ('private._collect_fence_require_operator()','fa446551edab1748df7dcdc4c69fcc6ecd72df24d689f75a12d3c70ae9d8dd1c',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._collect_fence_transition()','1b4739456fe0c4408b7dcfeb24d8090c22779ea8c970f3fb3b8fc7c78259c936',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._collect_fence_no_erasure()','36d8e62e234269e7b637fd276c2e08f393e2506abb41bd907b5cd60887ebe149',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._collect_stopped_no_late_close()','26ae7696161edb78444588742fc3b32030760bcce0fad7784b5876d2600d0c22',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._collect_admission_archive_track()','c0e2146288e88995ffbf3634b23cb67f2c3304f64e6480dd42b23c3cc5cc4832',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._collect_fence_require_runtime()','2fb9650e6abe3114a4e04caaef0fdbd80091f4025310510a8ebf8e201c96a5d0',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._collect_fence_require_rc(boolean)','f29634a277e50d7e4751357550a4f8eed0bd5717178703ef92d95ce30bd1b552',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private.collect_fence_assert_write(uuid,bigint,text)','c29a20edd15233a50c7d561be8f038f6d0fbc125d6f57a85f6d1b11fd6a50949',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}'),
  ('private._retention_manifest_catalog_v2()','aa9aa0086b70ced2d8533946c98e53814c183891c9057c307b3d207a30650674',false,'i',ARRAY['search_path=pg_catalog, pg_temp']::text[],'sql','{postgres=X/postgres}'),
  ('private._retention_manifest_schema_v2()','afad38d443badf352c865abb5ca1f9fd939566da05c1c29f50f10ab8905a3feb',true,'s',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._retention_manifest_rows_v2(text)','5aa6ca4011d0fa45e644066da4e90fd74fa55fe0c115a13c047e5399319a30a0',true,'s',ARRAY['search_path=app, pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._retention_row_policy_v2(uuid,text,text,text)','642f9f6545776e0ed6abca60007a9ea8c2d79faed0945d70ccbc8219eaa86228',true,'s',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','9f89fad1121d4f33e25fb5b9a7f56ff67873bf101ab3d7da294ca3f141b713f5',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}')
 ) e(sig,hash,definer,volatility,config,language,acl) LOOP
  IF to_regprocedure(r.sig) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
    WHERE p.oid=to_regprocedure(r.sig) AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef=r.definer
    AND p.provolatile=r.volatility AND p.prokind='f' AND p.proparallel='u' AND NOT p.proleakproof
    AND l.lanname=r.language AND p.proacl::text=r.acl AND p.proconfig=r.config
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.hash) THEN
   RAISE EXCEPTION 'native_nonce_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
 PERFORM private._collect_fence_require_operator();
 PERFORM pg_advisory_xact_lock(7346371,1);PERFORM pg_advisory_xact_lock(7346371,2);
 LOCK TABLE private.collect_fence_control,private.collect_fence_admissions IN SHARE ROW EXCLUSIVE MODE;
 IF EXISTS(SELECT 1 FROM (VALUES
   ('collect_fence_control','1ecbcd5962b5dcb0eb2fd9e219cd8dca7f983bc0a05d3039edc2b46d6908a8fc'),
   ('collect_fence_admissions','250401909be86e65510c89e1c17593c1b0935c53e3fbf0eb533b79bc5469dd00')
  ) expected(name,shape) WHERE NOT EXISTS(SELECT 1 FROM pg_class rel JOIN pg_namespace n ON n.oid=rel.relnamespace
   WHERE n.nspname='private' AND rel.relname=expected.name AND rel.relkind='r' AND NOT rel.relispartition AND NOT rel.relhassubclass
    AND rel.relrowsecurity AND NOT rel.relforcerowsecurity AND pg_get_userbyid(rel.relowner)='postgres'
    AND coalesce(rel.relacl,acldefault('r',rel.relowner))::text='{postgres=arwdDxtm/postgres}' AND NOT EXISTS(SELECT 1 FROM pg_policy pol WHERE pol.polrelid=rel.oid)
    AND NOT EXISTS(SELECT 1 FROM pg_attribute a WHERE a.attrelid=rel.oid AND a.attnum>0 AND NOT a.attisdropped AND a.attacl IS NOT NULL)
    AND NOT EXISTS(SELECT 1 FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid=a.attrelid AND d.adnum=a.attnum
     WHERE a.attrelid=rel.oid AND a.attnum>0 AND NOT a.attisdropped AND
      (a.attidentity<>'' OR a.attgenerated<>'' OR a.attcollation NOT IN(0,'pg_catalog."default"'::regcollation)
       OR coalesce(pg_get_expr(d.adbin,d.adrelid),'')<>CASE
        WHEN rel.relname='collect_fence_admissions' AND a.attname IN('external_dispatches','uncertain_dispatches') THEN '0'
        WHEN (rel.relname='collect_fence_admissions' AND a.attname='created_at') OR (rel.relname='collect_fence_control' AND a.attname='changed_at') THEN 'clock_timestamp()'
        ELSE '' END))
    AND encode(sha256(convert_to(coalesce((SELECT string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod)||':'||a.attnotnull::text,',' ORDER BY a.attnum)
     FROM pg_attribute a WHERE a.attrelid=rel.oid AND a.attnum>0 AND NOT a.attisdropped),'')||'|'||coalesce((SELECT string_agg(pg_get_constraintdef(x.oid),';' ORDER BY x.conname)
     FROM pg_constraint x WHERE x.conrelid=rel.oid),''),'UTF8')),'hex')=expected.shape))
  OR EXISTS(SELECT 1 FROM (VALUES
   ('collect_fence_control','collect_fence_no_erasure','private._collect_fence_no_erasure()',42,'O'),
   ('collect_fence_control','collect_fence_transition','private._collect_fence_transition()',19,'O'),
   ('collect_fence_admissions','collect_fence_no_erasure','private._collect_fence_no_erasure()',42,'O'),
   ('collect_fence_admissions','collect_fence_transition','private._collect_fence_transition()',19,'O'),
   ('collect_fence_admissions','collect_stopped_no_late_close','private._collect_stopped_no_late_close()',19,'A'),
   ('collect_fence_admissions','collect_admission_archive_track','private._collect_admission_archive_track()',21,'A')
  ) expected(rel,name,fn,kind,enabled) WHERE NOT EXISTS(SELECT 1 FROM pg_trigger t WHERE t.tgrelid=to_regclass('private.'||expected.rel)
   AND t.tgname=expected.name AND t.tgenabled=expected.enabled AND NOT t.tgisinternal AND t.tgfoid=to_regprocedure(expected.fn)
   AND t.tgtype=expected.kind AND t.tgqual IS NULL AND t.tgnargs=0 AND t.tgattr::text='' AND t.tgconstraint=0
   AND t.tgoldtable IS NULL AND t.tgnewtable IS NULL))
  OR (SELECT count(*) FROM pg_trigger t WHERE t.tgrelid IN('private.collect_fence_control'::regclass,'private.collect_fence_admissions'::regclass) AND NOT t.tgisinternal)<>6 THEN
  RAISE EXCEPTION 'native_nonce_fence_guard_changed' USING ERRCODE='55000';END IF;
 SELECT * INTO c FROM private.collect_fence_control WHERE singleton FOR UPDATE;
 IF NOT FOUND OR c.project_ref<>'rrlduytparvsjfmegalh' OR c.mode<>'fenced'
  OR EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE state<>'settled' OR uncertain_dispatches>0)
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') entry
   WHERE entry->>'relation'='private.collect_native_ingress_nonce_uses') THEN
  RAISE EXCEPTION 'native_nonce_requires_settled_fence' USING ERRCODE='55000';END IF;
END;$preflight$;

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
-- The replay table is shared operational custody; no subject selector or
-- personal erasure disposition is inferred from the absence of a mapping.
DO $retention$
DECLARE body text;next_body text;anchor text;replacement text;entry jsonb;
BEGIN
 entry:=jsonb_build_object('name','private:collect_native_ingress_nonce_uses','relation','private.collect_native_ingress_nonce_uses',
  'scope','unmapped_private','purpose','Short-lived signed native ingress replay claims; subject association unverified',
  'known_links','random nonce, deployment profile and policy hashes; no subject selector is asserted','blocked',true);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure;
 next_body:=format('SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||%L::jsonb) FROM (%s) prior(base)',jsonb_build_array(entry)::text,body);
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure;
 anchor:=$a$'managed:storage_iceberg','private:burimunsi_native_lease_history'$a$;
 replacement:=$b$'managed:storage_iceberg','private:collect_native_ingress_nonce_uses','private:burimunsi_native_lease_history'$b$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'native_nonce_retention_anchor_changed' USING ERRCODE='55000';END IF;
 next_body:=replace(body,anchor,replacement);
 EXECUTE 'CREATE OR REPLACE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
END;$retention$;
COMMIT;
