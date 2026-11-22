CREATE FUNCTION private.burimunsi_observation_reconcile_verified_status() RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE base jsonb;cid text;rev text;extra text;witness_count bigint;
 witness_pending boolean;witness_unmatched boolean;
 old_w text:=current_setting('collect.sms_witness_frame',true);
 old_frame text:=current_setting('burimunsi.observation_frame',true);
BEGIN
 -- The original pinned function independently checks current actor, consent,
 -- group and source custody. Its flags are lower bounds for this status.
 base:=private.burimunsi_observation_reconcile_status();cid:=base->>'groupId';
 IF cid IS NULL OR cid IS DISTINCT FROM current_setting('burimunsi.collection_id',true)
  OR jsonb_typeof(base->'hasPending') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(base->'hasRecorded') IS DISTINCT FROM 'boolean'
  OR jsonb_typeof(base->'hasUnmatchedCanonical') IS DISTINCT FROM 'boolean'
  OR coalesce(base->>'revision','') !~ '^[a-f0-9]{64}$' THEN
  RAISE EXCEPTION 'sms_recovery_status_denied' USING ERRCODE='42501';END IF;
 PERFORM set_config('burimunsi.observation_frame','1',true);
 PERFORM set_config('collect.sms_witness_frame','1',true);
 SELECT count(*) INTO witness_count FROM (SELECT 1 FROM private.collect_sms_witnesses w
  WHERE w.collection_id=cid LIMIT 100001) bounded;
 IF witness_count>100000 THEN RAISE EXCEPTION 'sms_witness_limit' USING ERRCODE='54000';END IF;
 SELECT EXISTS(SELECT 1 FROM private.collect_sms_witnesses w
  LEFT JOIN private.storage_put_intents i ON i.object_key=w.object_key
  LEFT JOIN private.burimunsi_unresolved_observations r ON r.object_key=w.object_key AND r.collection_id=cid
  LEFT JOIN private.burimunsi_sms_source_scopes scoped ON 'sms/'||scoped.source_id=w.object_key AND scoped.collection_id=cid
  WHERE w.collection_id=cid
   AND ((r.object_key IS NULL AND scoped.source_id IS NULL) OR i.object_key IS NULL
     OR i.scope->>'ownerId' IS DISTINCT FROM w.owner_id OR i.active_attempt IS NOT NULL OR i.upload_unresolved))
  OR EXISTS(SELECT 1 FROM private.storage_payload_reservations p
   LEFT JOIN private.collect_sms_witnesses w ON w.object_key=p.object_key
   LEFT JOIN private.burimunsi_unresolved_observations r ON r.object_key=p.object_key AND r.collection_id=cid
   LEFT JOIN private.burimunsi_observation_requests q ON 'sms/'||q.source_id=p.object_key AND q.collection_id=cid
   LEFT JOIN private.burimunsi_sms_source_scopes scoped ON 'sms/'||scoped.source_id=p.object_key AND scoped.collection_id=cid
   LEFT JOIN private.storage_put_intents i ON i.object_key=p.object_key
   WHERE p.scope->>'purpose'='sms_receipt' AND w.object_key IS NULL
    AND (q.collection_id=cid OR r.collection_id=cid OR scoped.collection_id=cid)
    AND ((r.object_key IS NULL AND scoped.source_id IS NULL) OR i.active_attempt IS NOT NULL OR i.upload_unresolved))
  INTO witness_pending;
 SELECT EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations r
  JOIN private.collect_sms_witnesses w ON w.collection_id=cid AND w.body_sha256=r.body_sha256 AND w.object_key<>r.object_key
  WHERE r.collection_id=cid
   AND (EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations other WHERE other.object_key=w.object_key AND other.collection_id=cid)
     OR EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes other WHERE other.collection_id=cid AND 'sms/'||other.source_id=w.object_key)))
  OR EXISTS(SELECT 1 FROM private.burimunsi_unresolved_observations r
   JOIN private.burimunsi_sms_source_scopes scoped ON scoped.collection_id=cid
   JOIN app.sms_receipts s ON s.id=scoped.source_id AND s.body_sha256=r.body_sha256 AND s.object_key<>r.object_key
   WHERE r.collection_id=cid) INTO witness_unmatched;
 WITH entries AS (
  SELECT w.object_key AS k,encode(sha256(convert_to(jsonb_build_array(to_jsonb(w),to_jsonb(i),to_jsonb(r),to_jsonb(s))::text,'UTF8')),'hex') AS h
  FROM private.collect_sms_witnesses w LEFT JOIN private.storage_put_intents i ON i.object_key=w.object_key
  LEFT JOIN private.burimunsi_unresolved_observations r ON r.object_key=w.object_key AND r.collection_id=cid
  LEFT JOIN app.sms_receipts s ON s.object_key=w.object_key AND s.owner_user_id=w.owner_id
  WHERE w.collection_id=cid
 ) SELECT encode(sha256(convert_to(coalesce(string_agg(h,E'\n' ORDER BY k),''),'UTF8')),'hex') INTO extra FROM entries;
 rev:=encode(sha256(convert_to(jsonb_build_array(base->>'revision',extra,witness_pending,witness_unmatched)::text,'UTF8')),'hex');
 PERFORM set_config('collect.sms_witness_frame',coalesce(old_w,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('groupId',cid,'hasPending',(base->>'hasPending')::boolean OR witness_pending,
  'hasRecorded',(base->>'hasRecorded')::boolean,'recordedCount',base->'recordedCount',
  'hasUnmatchedCanonical',(base->>'hasUnmatchedCanonical')::boolean OR witness_unmatched,'revision',rev);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('collect.sms_witness_frame',coalesce(old_w,''),true);
 PERFORM set_config('burimunsi.observation_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_observation_reconcile_verified_status() FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_observation_reconcile_verified_status() TO collect_runtime;
