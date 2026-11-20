-- Default-off scheduler discovery only. It posts no payments or ledger entries.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode='fenced')
  OR to_regprocedure('private.burimunsi_native_work_enqueue(uuid,text)') IS NULL
  OR to_regprocedure('private._burimunsi_native_work_authority(uuid)') IS NULL
  OR to_regprocedure('private.burimunsi_native_work_sources(uuid,integer)') IS NOT NULL THEN
  RAISE EXCEPTION 'native_work_discovery_precondition' USING ERRCODE='55000';END IF;
END;$preflight$;

-- Cross-collection visibility exists only inside the separately fenced,
-- internal jobs scan. Each returned grant is individually reauthorized below.
CREATE POLICY native_work_grant_scan ON private.burimunsi_native_work_grants FOR SELECT TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.native_work_scan_frame',true)='1'
  AND source_sha256=current_setting('collect.fence_source_sha256',true));

CREATE FUNCTION private.burimunsi_native_work_sources(p_grant uuid,p_limit integer) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE a jsonb;source jsonb;item record;result jsonb:='[]'::jsonb;at_ms bigint;scope text:=current_setting('burimunsi.collection_id',true);
 old_work text:=current_setting('burimunsi.native_work_frame',true);
 old_obs text:=current_setting('burimunsi.observation_frame',true);
 old_native text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 10 THEN RAISE EXCEPTION 'native_work_invalid' USING ERRCODE='22023';END IF;
 a:=private._burimunsi_native_work_authority(p_grant);
 PERFORM set_config('burimunsi.native_work_frame','1',true);PERFORM set_config('burimunsi.observation_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 FOR item IN SELECT j.source_id FROM private.burimunsi_auto_sms_jobs j
  JOIN private.burimunsi_native_receipt_origins n ON n.source_id=j.source_id AND n.collection_id=j.collection_id
  JOIN private.burimunsi_observation_requests q ON q.source_id=j.source_id AND q.collection_id=j.collection_id
  JOIN private.burimunsi_transaction_scopes x ON x.transaction_id=j.transaction_id AND x.collection_id=j.collection_id
   AND x.native_source_id=j.source_id AND x.receiving_account_id=j.receiving_account_id
  WHERE j.collection_id=scope AND j.state='completed' AND j.relation='accepted' AND q.source_key IS NOT NULL
   AND q.source_key_content_sha256 IS NOT NULL AND q.source_key_body_sha256=n.body_sha256
   AND NOT EXISTS(SELECT 1 FROM private.burimunsi_native_financial_work w WHERE w.collection_id=scope
    AND (w.source_id=j.source_id OR w.transaction_id=j.transaction_id))
  ORDER BY hashtextextended(j.source_id,at_ms/300000),j.source_id LIMIT 50 LOOP
  BEGIN
   source:=private._burimunsi_native_work_source(item.source_id);
   IF source->>'sourceId'=item.source_id THEN result:=result||to_jsonb(item.source_id);END IF;
  EXCEPTION WHEN insufficient_privilege OR serialization_failure THEN NULL;END;
  EXIT WHEN jsonb_array_length(result)>=p_limit;
 END LOOP;
 PERFORM set_config('burimunsi.native_work_frame',coalesce(old_work,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);RETURN result;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.native_work_frame',coalesce(old_work,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_obs,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_native,''),true);RAISE;
END;$fn$;

CREATE FUNCTION private.burimunsi_native_work_discover(p_limit integer,p_filter text DEFAULT NULL) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE f private.collect_fence_admissions%ROWTYPE;g record;v jsonb;outcome jsonb:='[]'::jsonb;at_ms bigint;
 old_group text:=current_setting('burimunsi.collection_id',true);old_scan text:=current_setting('burimunsi.native_work_scan_frame',true);
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 10 OR (p_filter IS NOT NULL AND p_filter !~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$') THEN
  RAISE EXCEPTION 'native_work_invalid' USING ERRCODE='22023';END IF;
 PERFORM private.burimunsi_auto_jobs_guard();
 f:=private._collect_fence_admission(current_setting('collect.fence_admission_id',true)::uuid,
  current_setting('collect.fence_epoch',true)::bigint,current_setting('collect.fence_source_sha256',true));
 at_ms:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 PERFORM set_config('burimunsi.native_work_scan_frame','1',true);
 FOR g IN SELECT id,collection_id FROM private.burimunsi_native_work_grants
  WHERE enabled AND revoked_at IS NULL AND source_sha256=f.source_sha256 AND approved_at<=at_ms AND expires_at>at_ms
   AND (p_filter IS NULL OR collection_id=p_filter)
  ORDER BY hashtextextended(id::text,at_ms/300000),id LIMIT 100 LOOP
  PERFORM set_config('burimunsi.collection_id',g.collection_id,true);
  BEGIN
   v:=private._burimunsi_native_work_authority(g.id);
   IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(outcome) existing WHERE existing->>'groupId'=g.collection_id)
    AND (jsonb_array_length(private.burimunsi_native_work_sources(g.id,1))>0
     OR jsonb_array_length(private.burimunsi_native_work_candidates(g.id,1))>0) THEN
    outcome:=outcome||jsonb_build_array(jsonb_build_object('groupId',g.collection_id,'grantId',g.id));
   END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL;END;
  EXIT WHEN jsonb_array_length(outcome)>=p_limit;
 END LOOP;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 PERFORM set_config('burimunsi.native_work_scan_frame',coalesce(old_scan,''),true);RETURN outcome;
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 PERFORM set_config('burimunsi.native_work_scan_frame',coalesce(old_scan,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_work_sources(uuid,integer),private.burimunsi_native_work_discover(integer,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_work_sources(uuid,integer),private.burimunsi_native_work_discover(integer,text) TO collect_runtime;
COMMIT;
