-- Preserve each newly admitted native work lease's exact grant and source.
-- Earlier lease versions remain unknown; this migration never invents them.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';SET LOCAL statement_timeout='60s';
DO $preflight$
DECLARE r record;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR to_regclass('private.burimunsi_native_lease_history') IS NOT NULL
  OR to_regprocedure('private._burimunsi_native_work_assert_base(uuid,uuid,bigint)') IS NOT NULL THEN
  RAISE EXCEPTION 'native_lease_history_precondition' USING ERRCODE='55000';END IF;
 FOR r IN SELECT * FROM (VALUES
  ('private.burimunsi_native_work_claim(uuid,uuid,bigint)','64f7319ce45a9e9b4f79ae6afe21576ce65fa49100a08aa836be4284988c8c09',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}'),
  ('private.burimunsi_native_work_assert(uuid,uuid,bigint)','217b11996dcdc1f5030f639c74fa97f589a4ee40409754080dbd8c7047345cfd',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}'),
  ('private.burimunsi_native_custody_snapshot(uuid,uuid,bigint)','0477be377dc59302863bcc9f624ce1d81595c1e934ff64c09eff9726c982be23',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}'),
  ('private.burimunsi_native_work_immutable()','f06bbcac768ffcc8713ce217272d7916e527a5d691f264b5ac8c282f107ea820',false,'v',ARRAY['search_path=pg_catalog']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._collect_fence_no_erasure()','36d8e62e234269e7b637fd276c2e08f393e2506abb41bd907b5cd60887ebe149',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._collect_fence_statement()','0b886c44b329012c91e5eb85fce1a160a60e4172e016a284f2c280121b0a217d',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._burimunsi_native_grant_write_guard()','94af0ae5ae7a2e0736edf91898ea4a6d90f2a343108967f23c6ef4cf24d09c36',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._retention_manifest_catalog_v2()','0b97aa502913fa91d518715ad2175d323cdb4ddad087322f172499e73c73adc6',false,'i',ARRAY['search_path=pg_catalog, pg_temp']::text[],'sql','{postgres=X/postgres}'),
  ('private._retention_manifest_schema_v2()','afad38d443badf352c865abb5ca1f9fd939566da05c1c29f50f10ab8905a3feb',true,'s',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._retention_manifest_rows_v2(text)','5aa6ca4011d0fa45e644066da4e90fd74fa55fe0c115a13c047e5399319a30a0',true,'s',ARRAY['search_path=app, pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private._retention_row_policy_v2(uuid,text,text,text)','642f9f6545776e0ed6abca60007a9ea8c2d79faed0945d70ccbc8219eaa86228',true,'s',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres}'),
  ('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','669c2e829964094b9d611952e52a025af221e1cb2efc0496525e4e8705bfb1bd',true,'v',ARRAY['search_path=pg_catalog, pg_temp']::text[],'plpgsql','{postgres=X/postgres,collect_runtime=X/postgres}')
 ) e(sig,hash,definer,volatility,config,language,acl) LOOP
  IF to_regprocedure(r.sig) IS NULL OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_language l ON l.oid=p.prolang
    WHERE p.oid=to_regprocedure(r.sig) AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef=r.definer
    AND p.provolatile=r.volatility AND p.prokind='f' AND p.proparallel='u' AND NOT p.proleakproof
    AND l.lanname=r.language AND p.proacl::text=r.acl AND p.proconfig=r.config
    AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=r.hash) THEN
   RAISE EXCEPTION 'native_lease_history_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM unnest(ARRAY['private.burimunsi_native_financial_work','private.burimunsi_native_work_grants']::text[]) rel
   WHERE NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=to_regclass(rel) AND c.relkind='r' AND c.relrowsecurity AND c.relforcerowsecurity
    AND pg_get_userbyid(c.relowner)='postgres' AND c.relacl::text='{postgres=arwdDxtm/postgres}'))
  OR EXISTS(SELECT 1 FROM (VALUES
   ('private.burimunsi_native_financial_work','collect_fence_statement_v1','private._collect_fence_statement()',62),
   ('private.burimunsi_native_financial_work','native_work_immutable','private.burimunsi_native_work_immutable()',27),
   ('private.burimunsi_native_financial_work','native_financial_work_no_truncate','private._collect_fence_no_erasure()',34),
   ('private.burimunsi_native_work_grants','collect_fence_statement_v1','private._collect_fence_statement()',62),
   ('private.burimunsi_native_work_grants','native_work_immutable','private.burimunsi_native_work_immutable()',27),
   ('private.burimunsi_native_work_grants','native_grant_write_guard','private._burimunsi_native_grant_write_guard()',31),
   ('private.burimunsi_native_work_grants','native_work_grants_no_truncate','private._collect_fence_no_erasure()',34)
  ) t(rel,name,fn,kind) WHERE NOT EXISTS(SELECT 1 FROM pg_trigger g WHERE g.tgrelid=to_regclass(t.rel) AND g.tgname=t.name
    AND g.tgenabled='A' AND NOT g.tgisinternal AND g.tgfoid=to_regprocedure(t.fn) AND g.tgtype=t.kind
    AND g.tgqual IS NULL AND g.tgnargs=0 AND g.tgattr::text='' AND g.tgconstraint=0
    AND g.tgoldtable IS NULL AND g.tgnewtable IS NULL))
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') c
    WHERE c->>'relation'='private.burimunsi_native_lease_history') THEN
  RAISE EXCEPTION 'native_lease_history_schema_changed' USING ERRCODE='55000';END IF;
END;$preflight$;

-- The trigger needs the exact original work check before a history row exists.
-- Only SECURITY DEFINER functions owned by postgres can invoke this copy.
DO $copy_assertion$
DECLARE body text;
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.burimunsi_native_work_assert(uuid,uuid,bigint)'::regprocedure;
 EXECUTE 'CREATE FUNCTION private._burimunsi_native_work_assert_base(p_job uuid,p_token uuid,p_version bigint) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(body);
END;$copy_assertion$;
REVOKE ALL ON FUNCTION private._burimunsi_native_work_assert_base(uuid,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;

CREATE TABLE private.burimunsi_native_lease_history(
 work_id uuid NOT NULL REFERENCES private.burimunsi_native_financial_work(id),
 lease_version bigint NOT NULL CHECK(lease_version BETWEEN 1 AND 9007199254740991),
 collection_id text NOT NULL REFERENCES private.burimunsi_scopes(collection_id),
 source_id text NOT NULL REFERENCES private.burimunsi_native_receipt_origins(source_id),
 transaction_id text NOT NULL REFERENCES app.momo_transactions(id),
 grant_id uuid NOT NULL REFERENCES private.burimunsi_native_work_grants(id),
 grant_version bigint NOT NULL CHECK(grant_version BETWEEN 1 AND 9007199254740991),
 admission_id uuid NOT NULL,admission_epoch bigint NOT NULL CHECK(admission_epoch>0),
 source_code_sha256 text NOT NULL CHECK(source_code_sha256 ~ '^[a-f0-9]{64}$'),
 source_key text NOT NULL CHECK(source_key ~ '^[a-f0-9]{64}$'),
 source_key_content_sha256 text NOT NULL CHECK(source_key_content_sha256 ~ '^[a-f0-9]{64}$'),
 body_sha256 text NOT NULL CHECK(body_sha256 ~ '^[a-f0-9]{64}$'),
 object_sha256 text NOT NULL CHECK(object_sha256 ~ '^[a-f0-9]{64}$'),
 source_fingerprint text NOT NULL CHECK(source_fingerprint ~ '^[a-f0-9]{64}$'),
 source_owner_user_id text NOT NULL REFERENCES app.users(id),
 source_object_size_bytes bigint NOT NULL CHECK(source_object_size_bytes BETWEEN 1 AND 131072),
 transaction_mode text NOT NULL CHECK(transaction_mode IN('live','historical')),
 lease_token_sha256 text NOT NULL CHECK(lease_token_sha256 ~ '^[a-f0-9]{64}$'),
 claimed_at bigint NOT NULL CHECK(claimed_at>=0),lease_expires_at bigint NOT NULL CHECK(lease_expires_at>claimed_at),
 recorded_at bigint NOT NULL CHECK(recorded_at>=0),PRIMARY KEY(work_id,lease_version)
);
CREATE INDEX burimunsi_native_lease_history_grant ON private.burimunsi_native_lease_history(collection_id,grant_id,grant_version,work_id,lease_version);
ALTER TABLE private.burimunsi_native_lease_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_native_lease_history FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.burimunsi_native_lease_history FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE POLICY native_lease_history_runtime ON private.burimunsi_native_lease_history TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.native_lease_history_frame',true)='1' AND collection_id=current_setting('burimunsi.collection_id',true))
 WITH CHECK(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.native_lease_history_frame',true)='1' AND collection_id=current_setting('burimunsi.collection_id',true));
CREATE POLICY native_lease_history_operator ON private.burimunsi_native_lease_history FOR SELECT TO postgres
 USING(current_setting('role',true)='none' AND private._collect_fence_operator());
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_native_lease_history
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
CREATE TRIGGER native_lease_history_retain BEFORE UPDATE OR DELETE OR TRUNCATE ON private.burimunsi_native_lease_history
 FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_no_erasure();
ALTER TABLE private.burimunsi_native_lease_history ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
ALTER TABLE private.burimunsi_native_lease_history ENABLE ALWAYS TRIGGER native_lease_history_retain;

-- The trigger sees only the state transition, then independently reasserts the
-- existing native job, source, scoped grant and admitted fence before writing.
CREATE FUNCTION private.burimunsi_native_record_lease_history() RETURNS trigger
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;at_ms bigint;old_frame text:=current_setting('burimunsi.native_lease_history_frame',true);
BEGIN
 IF TG_OP='INSERT' THEN
  IF NEW.state<>'queued' OR NEW.lease_version<>0 OR NEW.attempts<>0 THEN
   RAISE EXCEPTION 'native_lease_history_invalid_transition' USING ERRCODE='42501';END IF;
  RETURN NEW;
 END IF;
 IF NEW.state<>'leased' THEN RETURN NEW;END IF;
 IF OLD.state='leased' AND NEW.lease_version=OLD.lease_version THEN
  IF ROW(NEW.lease_token,NEW.lease_expires_at,NEW.lease_admission_id,NEW.lease_admission_epoch,NEW.lease_source_sha256,
         NEW.grant_id,NEW.grant_version,NEW.attempts) IS DISTINCT FROM
     ROW(OLD.lease_token,OLD.lease_expires_at,OLD.lease_admission_id,OLD.lease_admission_epoch,OLD.lease_source_sha256,
         OLD.grant_id,OLD.grant_version,OLD.attempts) THEN
   RAISE EXCEPTION 'native_lease_history_invalid_transition' USING ERRCODE='42501';END IF;
  RETURN NEW;
 END IF;
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 IF OLD.state NOT IN('queued','waiting','leased') OR (OLD.state='leased' AND OLD.lease_expires_at>at_ms)
  OR NEW.lease_version<>OLD.lease_version+1 OR NEW.attempts<>OLD.attempts+1 THEN
  RAISE EXCEPTION 'native_lease_history_invalid_transition' USING ERRCODE='42501';END IF;
 a:=private._burimunsi_native_work_assert_base(NEW.id,NEW.lease_token,NEW.lease_version);
 IF a->>'kind' IS DISTINCT FROM 'native_receipt' OR a->>'jobId' IS DISTINCT FROM NEW.id::text OR a->>'groupId' IS DISTINCT FROM NEW.collection_id
  OR a->>'sourceId' IS DISTINCT FROM NEW.source_id OR a->>'transactionId' IS DISTINCT FROM NEW.transaction_id
  OR a->>'workerGrantId' IS DISTINCT FROM NEW.grant_id::text OR (a->>'workerGrantVersion')::bigint IS DISTINCT FROM NEW.grant_version
  OR a->>'admissionId' IS DISTINCT FROM NEW.lease_admission_id::text OR (a->>'admissionEpoch')::bigint IS DISTINCT FROM NEW.lease_admission_epoch
  OR a->>'sourceCodeSha256' IS DISTINCT FROM NEW.lease_source_sha256 OR a->>'sourceKey' IS DISTINCT FROM NEW.source_key
  OR a->>'sourceKeyContentSha256' IS DISTINCT FROM NEW.source_key_content_sha256 OR a->>'sourceKeyBodySha256' IS DISTINCT FROM NEW.body_sha256
  OR a->>'bodySha256' IS DISTINCT FROM NEW.body_sha256 OR a->>'objectSha256' IS DISTINCT FROM NEW.object_sha256
  OR a->>'sourceFingerprint' IS DISTINCT FROM NEW.source_fingerprint OR (a->>'leaseExpiresAt')::bigint IS DISTINCT FROM NEW.lease_expires_at THEN
  RAISE EXCEPTION 'native_lease_history_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_lease_history_frame','1',true);
 INSERT INTO private.burimunsi_native_lease_history(work_id,lease_version,collection_id,source_id,transaction_id,grant_id,grant_version,
  admission_id,admission_epoch,source_code_sha256,source_key,source_key_content_sha256,body_sha256,object_sha256,source_fingerprint,
  source_owner_user_id,source_object_size_bytes,transaction_mode,lease_token_sha256,claimed_at,lease_expires_at,recorded_at)
 VALUES(NEW.id,NEW.lease_version,NEW.collection_id,NEW.source_id,NEW.transaction_id,NEW.grant_id,NEW.grant_version,
  NEW.lease_admission_id,NEW.lease_admission_epoch,NEW.lease_source_sha256,NEW.source_key,NEW.source_key_content_sha256,
  NEW.body_sha256,NEW.object_sha256,NEW.source_fingerprint,a->>'ownerUserId',(a->>'objectSizeBytes')::bigint,a->>'transactionMode',
  encode(sha256(convert_to(NEW.lease_token::text,'UTF8')),'hex'),NEW.updated_at,NEW.lease_expires_at,at_ms);
 PERFORM set_config('burimunsi.native_lease_history_frame',coalesce(old_frame,''),true);
 RETURN NEW;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_lease_history_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_record_lease_history() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER native_lease_history_capture AFTER INSERT OR UPDATE ON private.burimunsi_native_financial_work
 FOR EACH ROW EXECUTE FUNCTION private.burimunsi_native_record_lease_history();
ALTER TABLE private.burimunsi_native_financial_work ENABLE ALWAYS TRIGGER native_lease_history_capture;

-- Preserve the existing assertion's contract, but require its exact immutable
-- lease record. Existing custody, defer and completion callers all use it.
CREATE OR REPLACE FUNCTION private.burimunsi_native_work_assert(p_job uuid,p_token uuid,p_version bigint) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;h private.burimunsi_native_lease_history%ROWTYPE;old_frame text:=current_setting('burimunsi.native_lease_history_frame',true);
BEGIN
 a:=private._burimunsi_native_work_assert_base(p_job,p_token,p_version);
 PERFORM set_config('burimunsi.native_lease_history_frame','1',true);
 SELECT * INTO h FROM private.burimunsi_native_lease_history WHERE work_id=p_job AND lease_version=p_version
  AND collection_id=current_setting('burimunsi.collection_id',true) FOR SHARE;
 IF NOT FOUND OR h.grant_id::text IS DISTINCT FROM a->>'workerGrantId' OR h.grant_version IS DISTINCT FROM (a->>'workerGrantVersion')::bigint
  OR h.source_id IS DISTINCT FROM a->>'sourceId' OR h.transaction_id IS DISTINCT FROM a->>'transactionId'
  OR h.source_key IS DISTINCT FROM a->>'sourceKey' OR h.source_key_content_sha256 IS DISTINCT FROM a->>'sourceKeyContentSha256'
  OR h.body_sha256 IS DISTINCT FROM a->>'bodySha256' OR h.object_sha256 IS DISTINCT FROM a->>'objectSha256'
  OR h.source_fingerprint IS DISTINCT FROM a->>'sourceFingerprint' OR h.source_owner_user_id IS DISTINCT FROM a->>'ownerUserId'
  OR h.source_object_size_bytes IS DISTINCT FROM (a->>'objectSizeBytes')::bigint OR h.transaction_mode IS DISTINCT FROM a->>'transactionMode'
  OR h.admission_id::text IS DISTINCT FROM a->>'admissionId' OR h.admission_epoch IS DISTINCT FROM (a->>'admissionEpoch')::bigint
  OR h.source_code_sha256 IS DISTINCT FROM a->>'sourceCodeSha256' OR h.lease_expires_at IS DISTINCT FROM (a->>'leaseExpiresAt')::bigint
  OR h.lease_token_sha256 IS DISTINCT FROM encode(sha256(convert_to(p_token::text,'UTF8')),'hex') THEN
  RAISE EXCEPTION 'native_lease_history_unavailable' USING ERRCODE='55000';END IF;
 PERFORM set_config('burimunsi.native_lease_history_frame',coalesce(old_frame,''),true);
 RETURN a;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_lease_history_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_work_assert(uuid,uuid,bigint) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_work_assert(uuid,uuid,bigint) TO collect_runtime;

DO $integrate$
DECLARE body text;next_body text;anchor text;replacement text;entry jsonb;
BEGIN
 -- The existing custody snapshot must use the upgraded public assertion at
 -- both checkpoints; its SQL and return contract stay unchanged.
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.burimunsi_native_custody_snapshot(uuid,uuid,bigint)'::regprocedure;
 anchor:='private.burimunsi_native_work_assert(p_job,p_token,p_version)';
 IF length(body)-length(replace(body,anchor,''))<>2*length(anchor) THEN
  RAISE EXCEPTION 'native_lease_history_custody_anchor_changed' USING ERRCODE='55000';END IF;
 -- This class is shared and explicitly inspection-only: no subject totals,
 -- erasure authority, or claim of complete pre-install history is inferred.
 entry:=jsonb_build_object('name','private:burimunsi_native_lease_history','relation','private.burimunsi_native_lease_history',
  'scope','unmapped_private','purpose','Immutable post-install native work/grant lease association; earlier versions remain unknown',
  'known_links','work_id and grant_id bind the actual admitted lease; payer and other shared subjects remain unresolved','blocked',true);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure;
 next_body:=format('SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||%L::jsonb) FROM (%s) prior(base)',jsonb_build_array(entry)::text,body);
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure;
 anchor:=$a$'managed:storage_iceberg','private:burimunsi_native_financial_work'$a$;
 replacement:=$b$'managed:storage_iceberg','private:burimunsi_native_lease_history','private:burimunsi_native_financial_work'$b$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'native_lease_history_retention_anchor_changed' USING ERRCODE='55000';END IF;
 next_body:=replace(body,anchor,replacement);
 EXECUTE 'CREATE OR REPLACE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
END;$integrate$;
COMMIT;
