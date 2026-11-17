-- Additive administrator-only processing status and explicit, idempotent retry.
-- The original v1 observation page and its response shape remain unchanged.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR to_regprocedure('private.burimunsi_observation_history_rows(text)') IS NULL
  OR to_regprocedure('private.burimunsi_observation_storage_matches(text,jsonb,text)') IS NULL
  OR to_regprocedure('private.burimunsi_observation_own(text,boolean)') IS NULL
  OR to_regprocedure('private.collect_imported_native_source(text)') IS NULL
  OR to_regprocedure('private.collect_imported_native_job_transaction(text)') IS NULL
  OR to_regclass('private.burimunsi_auto_sms_jobs') IS NULL THEN
  RAISE EXCEPTION 'observation_processing_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

CREATE TABLE private.burimunsi_observation_retry_commands (
 request_id uuid PRIMARY KEY, source_id text NOT NULL,
 collection_id text NOT NULL, account_id uuid NOT NULL,
 result text NOT NULL CHECK(result IN ('scheduled','not_eligible')),
 created_at bigint NOT NULL
);
ALTER TABLE private.burimunsi_observation_retry_commands ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_observation_retry_commands FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_observation_retry_commands FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE POLICY burimunsi_observation_retry_frame ON private.burimunsi_observation_retry_commands TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.native_receipt_frame',true)='1')
 WITH CHECK(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.native_receipt_frame',true)='1');
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
 ON private.burimunsi_observation_retry_commands FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.burimunsi_observation_retry_commands ENABLE ALWAYS TRIGGER collect_fence_statement_v1;
CREATE FUNCTION private.burimunsi_observation_retry_immutable() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN RAISE EXCEPTION 'observation_retry_immutable' USING ERRCODE='23514';END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_retry_immutable() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE TRIGGER burimunsi_observation_retry_immutable BEFORE UPDATE OR DELETE
 ON private.burimunsi_observation_retry_commands FOR EACH ROW EXECUTE FUNCTION private.burimunsi_observation_retry_immutable();
ALTER TABLE private.burimunsi_observation_retry_commands ENABLE ALWAYS TRIGGER burimunsi_observation_retry_immutable;

-- A batch uses the same scoped observation authority as the existing page and
-- disclosure. A source outside that scope yields no information about it.
CREATE FUNCTION private.burimunsi_observation_processing_status(p_sources jsonb) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb; source text; owned boolean; own_proof jsonb; j private.burimunsi_auto_sms_jobs%ROWTYPE;
 status text; can_retry boolean; result jsonb:='[]'::jsonb;
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 a:=private.burimunsi_observation_actor(false);
 IF jsonb_typeof(p_sources) IS DISTINCT FROM 'array' OR jsonb_array_length(p_sources) NOT BETWEEN 1 AND 100
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_sources) x WHERE jsonb_typeof(x)<>'string' OR x#>>'{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
  OR (SELECT count(DISTINCT x) FROM jsonb_array_elements_text(p_sources) x)<>jsonb_array_length(p_sources) THEN
  RAISE EXCEPTION 'observation_processing_invalid' USING ERRCODE='22023';END IF;
 FOR source IN SELECT jsonb_array_elements_text(p_sources) LOOP
  status:='unknown';can_retry:=false;
  SELECT EXISTS(SELECT 1 FROM private.burimunsi_observation_history_rows(source) r
   WHERE private.burimunsi_observation_storage_matches(r.object_key,
    jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id),r.object_sha256)) INTO owned;
  IF owned THEN
   IF private.collect_imported_native_source(source) THEN status:='historical';
   ELSE
    own_proof:=private.burimunsi_observation_own(source,false);
    PERFORM set_config('burimunsi.native_receipt_frame','1',true);
    SELECT * INTO j FROM private.burimunsi_auto_sms_jobs WHERE source_id=source AND collection_id=a->>'collectionId';
    IF NOT FOUND THEN status:='pending';
    ELSIF j.state='processing' THEN status:='pending';
    ELSIF j.state='retry' THEN
     status:=CASE WHEN j.last_error='invalid_output' AND j.invalid_output_count>=5 THEN 'needs_review' ELSE 'retrying' END;
     can_retry:=own_proof IS NOT NULL AND NOT private.collect_imported_native_job_transaction(source);
    ELSIF j.state='failed' THEN status:='needs_review';
    ELSIF j.state='security_message' THEN status:='security';
    ELSIF j.state='completed' AND j.relation='conflict' THEN status:='conflict';
    ELSIF j.state='completed' AND j.relation='duplicate' THEN status:='duplicate';
    ELSIF j.state='completed' AND j.posting_last_error IS NOT NULL THEN status:='needs_review';
    ELSIF j.state='completed' THEN status:='parsed';END IF;
    PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
   END IF;
  END IF;
  result:=result||jsonb_build_array(jsonb_build_object('sourceId',source,'status',status,'canRetry',can_retry));
 END LOOP;
 RETURN jsonb_build_object('groupId',a->>'collectionId','statuses',result);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_processing_status(jsonb) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_processing_status(jsonb) TO collect_runtime;

-- No job is created and no facts, lease or financial state are altered. The
-- existing worker must still re-check consent, source, profile and replay guards.
CREATE FUNCTION private.burimunsi_observation_processing_retry(p_source text,p_request uuid) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb; prior private.burimunsi_observation_retry_commands%ROWTYPE; result text:='not_eligible'; n integer;
 now_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();
 a:=private.burimunsi_observation_actor(false);
 IF p_request IS NULL OR p_source IS NULL OR p_source !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
  RAISE EXCEPTION 'observation_processing_invalid' USING ERRCODE='22023';END IF;
 IF NOT EXISTS(SELECT 1 FROM private.burimunsi_observation_history_rows(p_source) r
  WHERE private.burimunsi_observation_storage_matches(r.object_key,
   jsonb_build_object('ownerId',r.principal_user_id,'purpose','sms_receipt','entityId',r.source_id),r.object_sha256)) THEN
  RAISE EXCEPTION 'observation_processing_denied' USING ERRCODE='42501';END IF;
 -- A retry uses an immutable caller request identity, serialized across races.
 PERFORM pg_advisory_xact_lock(hashtextextended(p_request::text,0));
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO prior FROM private.burimunsi_observation_retry_commands WHERE request_id=p_request;
 IF FOUND THEN
  IF ROW(prior.source_id,prior.collection_id,prior.account_id) IS DISTINCT FROM
   ROW(p_source,a->>'collectionId',(a->>'accountId')::uuid) THEN
   RAISE EXCEPTION 'observation_retry_request_changed' USING ERRCODE='40001';END IF;
  result:=prior.result;
 ELSE
  IF NOT private.collect_imported_native_source(p_source) AND NOT private.collect_imported_native_job_transaction(p_source)
   AND private.burimunsi_observation_own(p_source,false) IS NOT NULL THEN
   UPDATE private.burimunsi_auto_sms_jobs SET next_attempt_at=least(next_attempt_at,now_ms),updated_at=now_ms
    WHERE source_id=p_source AND collection_id=a->>'collectionId' AND state='retry'
     AND lease_token IS NULL AND lease_until IS NULL AND next_attempt_at IS NOT NULL;
   GET DIAGNOSTICS n=ROW_COUNT;
   IF n=1 THEN result:='scheduled';END IF;
  END IF;
  INSERT INTO private.burimunsi_observation_retry_commands(request_id,source_id,collection_id,account_id,result,created_at)
   VALUES(p_request,p_source,a->>'collectionId',(a->>'accountId')::uuid,result,now_ms);
 END IF;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('groupId',a->>'collectionId','sourceId',p_source,'requestId',p_request,'result',result);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_processing_retry(text,uuid) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_processing_retry(text,uuid) TO collect_runtime;

-- Register the journal for retention inspection without asserting complete
-- subject mapping, a zero count, or any authority to erase it.
DO $retention$
DECLARE body text;next_body text;entry jsonb;anchor text;replacement text;item record;
BEGIN
 IF to_regprocedure('private._retention_manifest_catalog_v2()') IS NULL OR
  to_regprocedure('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)') IS NULL OR
  EXISTS(SELECT 1 FROM jsonb_array_elements(private._retention_manifest_catalog_v2()->'private_classes') c
   WHERE c->>'relation'='private.burimunsi_observation_retry_commands') THEN
  RAISE EXCEPTION 'observation_retry_retention_precondition' USING ERRCODE='55000';END IF;
 FOR item IN SELECT * FROM (VALUES
  ('private._retention_manifest_catalog_v2()','6ccf4d61b7641ef391ae4e1de36da0d80a7fcecfa1dea713f7f1b622ca2dd3c8',false,'i','{postgres=X/postgres}'),
  ('private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)','a28c21fff3a44cf97d118337654b414b00d9aaed7835d13dd70d171d1956681d',true,'v','{postgres=X/postgres,collect_runtime=X/postgres}')
 ) e(signature,digest,definer,volatility,acl) LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_proc p WHERE p.oid=to_regprocedure(item.signature)
   AND pg_get_userbyid(p.proowner)='postgres' AND p.prosecdef=item.definer AND p.provolatile=item.volatility::"char"
   AND p.proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND p.proacl::text=item.acl
   AND encode(sha256(convert_to(p.prosrc,'UTF8')),'hex')=item.digest) THEN
   RAISE EXCEPTION 'observation_retry_retention_predecessor_changed' USING ERRCODE='55000';END IF;
 END LOOP;
 entry:=jsonb_build_object('name','private:burimunsi_observation_retry_commands',
  'relation','private.burimunsi_observation_retry_commands','scope','unmapped_private',
  'purpose','Immutable observation retry request and account references; inspection only, effects blocked',
  'known_links','account_id identifies the operator; source_id identifies the retained observation','blocked',true);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure;
 next_body:=format('SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||%L::jsonb) FROM (%s) prior(base)',jsonb_build_array(entry)::text,body);
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure;
 anchor:=$a$'managed:storage_iceberg','private:burimunsi_native_lease_history'$a$;
 replacement:=$b$'private:burimunsi_observation_retry_commands','managed:storage_iceberg','private:burimunsi_native_lease_history'$b$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'observation_retry_retention_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(replace(body,anchor,replacement));
END;$retention$;
COMMIT;
