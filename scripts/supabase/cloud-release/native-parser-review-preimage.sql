-- Function definitions only, captured read-only from the fenced predecessor; no rows or credentials.
-- private.burimunsi_auto_retry(text,uuid,text,text,text) sha256 a4d11f82ce94ec665aa29df8b3157b3646fca571552d2c892247c5be08400a14
CREATE OR REPLACE FUNCTION private.burimunsi_auto_retry(p_source text, p_lease uuid, p_fingerprint text, p_profile_sha text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE snap jsonb;proof jsonb;profile jsonb;j private.burimunsi_auto_sms_jobs%ROWTYPE;
 at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;at_next bigint;
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();snap:=private.burimunsi_auto_snapshot(p_source);proof:=snap->'proof';profile:=snap->'profile';
 IF p_lease IS NULL OR p_reason IS NULL OR p_reason NOT IN ('provider_unavailable','invalid_output') OR proof IS NULL
  OR proof->>'fingerprint' IS DISTINCT FROM p_fingerprint OR profile IS NULL
  OR profile->>'profileSha256' IS DISTINCT FROM p_profile_sha THEN
  RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO j FROM private.burimunsi_auto_sms_jobs WHERE source_id=p_source FOR UPDATE;
 IF NOT FOUND OR ROW(j.source_fingerprint,j.profile_sha256) IS DISTINCT FROM ROW(p_fingerprint,p_profile_sha) THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 IF j.state IN ('retry','failed') AND j.retry_lease=p_lease AND j.last_error=p_reason THEN
  PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
  RETURN jsonb_build_object('sourceId',p_source,'state',j.state,'attemptCount',j.attempt_count,'nextAttemptAt',j.next_attempt_at);
 END IF;
 IF j.state<>'processing' OR j.lease_token IS DISTINCT FROM p_lease OR j.lease_until<=at_ms THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 -- A temporary provider or parsing failure must not strand a message forever.
 -- Retry automatically with a capped hourly backoff to avoid a tight loop.
 at_next:=at_ms+least(3600000::bigint,10000::bigint*(1::bigint << least(j.attempt_count-1,9)::integer));
 UPDATE private.burimunsi_auto_sms_jobs SET state='retry',
  phase='preflight',lease_token=NULL,lease_until=NULL,
  retry_lease=p_lease,last_error=p_reason,next_attempt_at=at_next,updated_at=at_ms WHERE source_id=p_source;
 IF private.burimunsi_auto_snapshot(p_source) IS DISTINCT FROM snap THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('sourceId',p_source,'state','retry',
  'attemptCount',j.attempt_count,'nextAttemptAt',at_next);
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$function$
;

-- private.burimunsi_auto_finish(text,uuid,text,text,uuid,text,jsonb,jsonb) sha256 cf330a71bf9121f56a87f6ceaa9a4e5c1ec64d46a5d102a7409bde128ae80472
CREATE OR REPLACE FUNCTION private.burimunsi_auto_finish(p_source text, p_lease uuid, p_fingerprint text, p_profile_sha text, p_attempt uuid, p_model text, p_output jsonb, p_facts jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE a jsonb;proof jsonb;profile jsonb;snap jsonb;j private.burimunsi_auto_sms_jobs%ROWTYPE;
 t app.momo_transactions%ROWTYPE;sc private.burimunsi_transaction_scopes%ROWTYPE;canonical_facts jsonb;canonical_ids text[];
 expected_keys text[]:=ARRAY['amount_minor','counterparty_identifier','counterparty_name','currency','event_kind',
  'fee_minor','original_transaction_id','payment_outcome','provider_transaction_id','source_mode','transaction_at',
  'transaction_datetime_raw','wallet_balance_after_minor'];
 keys text[];k text;typ text;kind text;outcome text;ref text;wallet_provider text;wallet_timezone text;
 amount bigint;fee bigint;balance bigint;fhash text;new_id text;v_relation text:='accepted';
 at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;
 stamp text:=app.strftime('%Y-%m-%dT%H:%M:%fZ');
 old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
 old_group text:=current_setting('burimunsi.collection_id',true);
BEGIN
 PERFORM private.burimunsi_setup_fence();PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 snap:=private.burimunsi_auto_snapshot(p_source);a:=snap->'actor';proof:=snap->'proof';profile:=snap->'profile';
 IF proof IS NULL OR proof->>'fingerprint' IS DISTINCT FROM p_fingerprint OR profile IS NULL
  OR profile->>'profileSha256' IS DISTINCT FROM p_profile_sha OR p_attempt IS NULL OR p_lease IS NULL
  OR p_model IS NULL OR p_model !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$'
  OR jsonb_typeof(p_facts) IS DISTINCT FROM 'object'
  OR p_output IS NOT NULL AND (jsonb_typeof(p_output)<>'object' OR octet_length(p_output::text)>65536) THEN
  RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 SELECT array_agg(x ORDER BY x) INTO keys FROM jsonb_object_keys(p_facts) AS x;
 IF keys IS DISTINCT FROM expected_keys THEN RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 FOREACH k IN ARRAY ARRAY['event_kind','payment_outcome','source_mode'] LOOP
  IF jsonb_typeof(p_facts->k) IS DISTINCT FROM 'string' THEN RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['provider_transaction_id','original_transaction_id','currency','counterparty_name',
  'counterparty_identifier','transaction_at','transaction_datetime_raw'] LOOP
  typ:=jsonb_typeof(p_facts->k);
  IF typ NOT IN ('string','null') OR (typ='string' AND (length(p_facts->>k) NOT BETWEEN 1 AND 512
    OR p_facts->>k ~ '[[:cntrl:]]')) THEN RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 END LOOP;
 FOREACH k IN ARRAY ARRAY['amount_minor','fee_minor','wallet_balance_after_minor'] LOOP
  typ:=jsonb_typeof(p_facts->k);
  IF typ NOT IN ('number','null') OR (typ='number' AND
    (p_facts->>k !~ '^(0|[1-9][0-9]{0,15})$' OR (p_facts->>k)::numeric>9007199254740991)) THEN
   RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 END LOOP;
 kind:=p_facts->>'event_kind';outcome:=p_facts->>'payment_outcome';ref:=p_facts->>'provider_transaction_id';
 amount:=(p_facts->>'amount_minor')::bigint;fee:=(p_facts->>'fee_minor')::bigint;
 balance:=(p_facts->>'wallet_balance_after_minor')::bigint;
 IF p_facts->>'source_mode' NOT IN ('live','catch_up') OR kind NOT IN ('incoming_receipt','outgoing','reversal','failed','pending','other','unknown')
  OR outcome NOT IN ('successful','failed','pending','unknown') OR amount=0
  OR ref IS NOT NULL AND (length(ref)>160 OR ref ~ '[[:space:]]')
  OR p_facts->>'original_transaction_id' IS NOT NULL AND length(p_facts->>'original_transaction_id')>160
  OR p_facts->>'currency' IS NOT NULL AND p_facts->>'currency'<>'RWF'
  OR p_facts->>'transaction_at' IS NOT NULL AND
   (p_facts->>'transaction_at' !~ '(Z|[+-][0-9]{2}:[0-9]{2})$' OR NOT pg_input_is_valid(p_facts->>'transaction_at','timestamp with time zone'))
  OR kind IN ('incoming_receipt','outgoing','reversal') AND outcome<>'successful'
  OR kind='failed' AND outcome<>'failed' OR kind='pending' AND outcome<>'pending' THEN
  RAISE EXCEPTION 'burimunsi_auto_invalid' USING ERRCODE='22023';END IF;
 fhash:=encode(sha256(convert_to(jsonb_build_object('model',p_model,'output',p_output,'facts',p_facts)::text,'UTF8')),'hex');
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT * INTO j FROM private.burimunsi_auto_sms_jobs WHERE source_id=p_source FOR UPDATE;
 IF NOT FOUND OR ROW(j.collection_id,j.source_fingerprint,j.profile_sha256)
  IS DISTINCT FROM ROW(a->>'collectionId',p_fingerprint,p_profile_sha) THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 IF j.state='completed' THEN
  IF j.attempt_id IS DISTINCT FROM p_attempt OR j.facts_sha256 IS DISTINCT FROM fhash THEN
   RAISE EXCEPTION 'burimunsi_auto_conflict' USING ERRCODE='23505';END IF;
  PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
  RETURN jsonb_build_object('sourceId',p_source,'transactionId',j.transaction_id,'state','completed','relation',j.relation);
 END IF;
 IF j.lease_token IS DISTINCT FROM p_lease OR j.lease_until<=at_ms
  OR (p_model='local' AND j.phase<>'preflight') OR (p_model<>'local' AND j.phase<>'dispatched') THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 SELECT w.provider,w.timezone INTO wallet_provider,wallet_timezone FROM app.momo_receiving_accounts w
 JOIN private.burimunsi_scopes s ON s.receiving_account_id=w.id
 WHERE s.collection_id=j.collection_id AND w.id=j.receiving_account_id AND w.status='active' FOR SHARE OF s,w;
 IF NOT FOUND OR wallet_provider IS DISTINCT FROM profile->'profile'->>'provider'
  OR wallet_timezone IS DISTINCT FROM profile->'profile'->>'timezone' THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 new_id:=p_source;
 IF j.event_identity_sha256 IS NULL THEN RAISE EXCEPTION 'burimunsi_native_event_required' USING ERRCODE='55000';END IF;
 IF (SELECT count(DISTINCT prior.transaction_id) FROM private.burimunsi_auto_sms_jobs prior
  JOIN app.momo_transactions canonical ON canonical.id=prior.transaction_id
  JOIN private.burimunsi_native_receipt_origins origin ON origin.source_id=prior.source_id
   AND origin.collection_id=prior.collection_id AND origin.fingerprint=prior.source_fingerprint
  WHERE prior.collection_id=j.collection_id AND prior.receiving_account_id=j.receiving_account_id
   AND (prior.event_identity_sha256=j.event_identity_sha256 OR
    ((canonical.provider_transaction_id IS NOT NULL OR EXISTS(
     SELECT 1 FROM private.burimunsi_auto_sms_jobs facts_job WHERE facts_job.transaction_id=canonical.id
      AND facts_job.collection_id=j.collection_id AND facts_job.receiving_account_id=j.receiving_account_id
      AND facts_job.state='completed' AND facts_job.relation='accepted'
      AND facts_job.posting_facts->>'provider_transaction_id' IS NOT NULL)) AND origin.body_sha256=proof->>'bodySha256') OR
    (j.event_inbox_sha256 IS NOT NULL AND prior.event_inbox_sha256=j.event_inbox_sha256
     AND NOT (j.event_has_service_time AND EXISTS(SELECT 1 FROM private.burimunsi_auto_sms_jobs strong
      WHERE strong.collection_id=j.collection_id AND strong.receiving_account_id=j.receiving_account_id
       AND strong.transaction_id=prior.transaction_id AND strong.state='completed' AND strong.relation IN ('accepted','duplicate','conflict')
       AND strong.event_has_service_time AND strong.event_identity_sha256<>j.event_identity_sha256))))
   AND prior.source_id<>j.source_id AND prior.state='completed' AND prior.relation IN ('accepted','duplicate','conflict'))>1 THEN
  RAISE EXCEPTION 'burimunsi_native_event_ambiguous' USING ERRCODE='40001';END IF;
 SELECT canonical.* INTO t FROM private.burimunsi_auto_sms_jobs prior
 JOIN app.momo_transactions canonical ON canonical.id=prior.transaction_id
 JOIN private.burimunsi_native_receipt_origins origin ON origin.source_id=prior.source_id
  AND origin.collection_id=prior.collection_id AND origin.fingerprint=prior.source_fingerprint
 WHERE prior.collection_id=j.collection_id AND prior.receiving_account_id=j.receiving_account_id
  AND (prior.event_identity_sha256=j.event_identity_sha256 OR
   ((canonical.provider_transaction_id IS NOT NULL OR EXISTS(
     SELECT 1 FROM private.burimunsi_auto_sms_jobs facts_job WHERE facts_job.transaction_id=canonical.id
      AND facts_job.collection_id=j.collection_id AND facts_job.receiving_account_id=j.receiving_account_id
      AND facts_job.state='completed' AND facts_job.relation='accepted'
      AND facts_job.posting_facts->>'provider_transaction_id' IS NOT NULL)) AND origin.body_sha256=proof->>'bodySha256') OR
   (j.event_inbox_sha256 IS NOT NULL AND prior.event_inbox_sha256=j.event_inbox_sha256
    AND NOT (j.event_has_service_time AND EXISTS(SELECT 1 FROM private.burimunsi_auto_sms_jobs strong
     WHERE strong.collection_id=j.collection_id AND strong.receiving_account_id=j.receiving_account_id
      AND strong.transaction_id=prior.transaction_id AND strong.state='completed' AND strong.relation IN ('accepted','duplicate','conflict')
      AND strong.event_has_service_time AND strong.event_identity_sha256<>j.event_identity_sha256))))
  AND prior.source_id<>j.source_id AND prior.state='completed' AND prior.relation IN ('accepted','duplicate','conflict')
 ORDER BY prior.created_at,prior.source_id LIMIT 1 FOR UPDATE OF canonical;
 IF NOT FOUND AND ref IS NOT NULL THEN
  SELECT array_agg(canonical.id ORDER BY canonical.id) INTO canonical_ids FROM app.momo_transactions canonical
  WHERE canonical.provider=wallet_provider AND canonical.receiving_account_id=j.receiving_account_id
   AND ((canonical.event_kind=kind AND canonical.provider_transaction_id=ref) OR EXISTS(
    SELECT 1 FROM private.burimunsi_auto_sms_jobs facts_job WHERE facts_job.transaction_id=canonical.id
     AND facts_job.collection_id=j.collection_id AND facts_job.receiving_account_id=j.receiving_account_id
     AND facts_job.state='completed' AND facts_job.relation='accepted'
     AND facts_job.posting_facts->>'event_kind'=kind
     AND coalesce(canonical.provider_transaction_id,facts_job.posting_facts->>'provider_transaction_id')=ref));
  IF cardinality(canonical_ids)>1 THEN RAISE EXCEPTION 'burimunsi_native_event_ambiguous' USING ERRCODE='40001';END IF;
  IF cardinality(canonical_ids)=1 THEN
   SELECT * INTO t FROM app.momo_transactions WHERE id=canonical_ids[1] FOR UPDATE;
  END IF;
 END IF;
 IF t.id IS NOT NULL THEN
   PERFORM set_config('burimunsi.collection_id',j.collection_id,true);
   SELECT * INTO sc FROM private.burimunsi_transaction_scopes WHERE transaction_id=t.id;
   IF NOT FOUND OR ROW(sc.collection_id,sc.receiving_account_id) IS DISTINCT FROM ROW(j.collection_id,j.receiving_account_id) THEN
    RAISE EXCEPTION 'burimunsi_auto_scope_conflict' USING ERRCODE='23514';END IF;
   -- Historical canonical rows may predate the source-bound facts projection.
   -- Prefer that one accepted job's validated facts only in this local record;
   -- never rewrite the immutable transaction or its existing financial effect.
   canonical_facts:=(SELECT facts_job.posting_facts FROM private.burimunsi_auto_sms_jobs facts_job
    WHERE facts_job.transaction_id=t.id AND facts_job.collection_id=j.collection_id
     AND facts_job.receiving_account_id=j.receiving_account_id
     AND facts_job.state='completed' AND facts_job.relation='accepted');
   IF canonical_facts IS NOT NULL THEN
    t:=jsonb_populate_record(t,jsonb_build_object(
     'event_kind',canonical_facts->'event_kind','amount_minor',canonical_facts->'amount_minor',
     'currency',canonical_facts->'currency','payer_name',canonical_facts->'counterparty_name',
     'payer_identifier',canonical_facts->'counterparty_identifier','transaction_at',canonical_facts->'transaction_at',
     'fee_minor',canonical_facts->'fee_minor','wallet_balance_after_minor',canonical_facts->'wallet_balance_after_minor',
     'provider_transaction_id',coalesce(t.provider_transaction_id,canonical_facts->>'provider_transaction_id')));
   END IF;
   v_relation:=CASE WHEN t.event_kind=kind AND (ref IS NULL OR t.provider_transaction_id IS NULL OR ref=t.provider_transaction_id)
    AND ROW(t.amount_minor,t.currency,t.payer_name,t.payer_identifier,t.transaction_at,t.fee_minor,t.wallet_balance_after_minor)
     IS NOT DISTINCT FROM ROW(amount,p_facts->>'currency',p_facts->>'counterparty_name',p_facts->>'counterparty_identifier',
      p_facts->>'transaction_at',fee,balance) THEN 'duplicate' ELSE 'conflict' END;
   new_id:=t.id;
 END IF;
 INSERT INTO app.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,
  profile_version,profile_json,source_body_sha256,output_json,validation_json,outcome,created_at)
 VALUES(p_attempt::text,p_source,1,p_model,'burimunsi-auto.v1','burimunsi-auto.v1','burimunsi-auto.v1',
  profile->'profile'->>'profile_version',profile->'profile'->>'profile_json',proof->>'bodySha256',
  p_output::text,'[]',v_relation,stamp);
 IF v_relation='accepted' THEN
  INSERT INTO app.momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,original_transaction_id,
   amount_minor,currency,currency_scale,payer_name,payer_identifier,payer_last3,transaction_at,transaction_datetime_raw,
   transaction_timezone,transaction_time_source,fee_minor,wallet_balance_after_minor,parse_attempt_id,mode,allocation_state,created_at,updated_at)
  VALUES(new_id,j.receiving_account_id,wallet_provider,ref,kind,p_facts->>'original_transaction_id',amount,p_facts->>'currency',
   CASE WHEN p_facts->>'currency' IS NULL THEN NULL ELSE 0 END,p_facts->>'counterparty_name',p_facts->>'counterparty_identifier',
   CASE WHEN length(regexp_replace(coalesce(p_facts->>'counterparty_identifier',''),'[^0-9]','','g'))>=3
    THEN right(regexp_replace(p_facts->>'counterparty_identifier','[^0-9]','','g'),3) ELSE NULL END,
   p_facts->>'transaction_at',p_facts->>'transaction_datetime_raw',wallet_timezone,
   CASE WHEN p_facts->>'transaction_at' IS NULL THEN 'missing_provider_time' ELSE 'sms_body_and_provider_profile' END,
   fee,balance,p_attempt::text,CASE WHEN p_facts->>'source_mode'='live' THEN 'live' ELSE 'historical' END,
   CASE WHEN kind='incoming_receipt' AND outcome='successful' AND amount IS NOT NULL AND balance IS NOT NULL
    AND p_facts->>'currency' IS NOT NULL THEN 'unallocated' ELSE 'not_applicable' END,stamp,stamp);
  PERFORM set_config('burimunsi.collection_id',j.collection_id,true);
  INSERT INTO private.burimunsi_transaction_scopes(transaction_id,collection_id,receiving_account_id,source_binding_id,
   source_binding_version,policy_version,created_at,native_source_id)
  VALUES(new_id,j.collection_id,j.receiving_account_id,NULL,NULL,'native.auto.v1',at_ms,p_source);
 END IF;
 INSERT INTO app.momo_transaction_sources(transaction_id,raw_sms_id,parse_attempt_id,relation,created_at)
 VALUES(new_id,p_source,p_attempt::text,v_relation,stamp);
 UPDATE private.burimunsi_auto_sms_jobs SET state='completed',phase='finished',lease_token=NULL,lease_until=NULL,
  attempt_id=p_attempt,transaction_id=new_id,facts_sha256=fhash,relation=v_relation,payment_outcome=outcome,updated_at=at_ms
  WHERE source_id=p_source;
 IF private.burimunsi_auto_snapshot(p_source) IS DISTINCT FROM snap THEN
  RAISE EXCEPTION 'burimunsi_auto_source_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 RETURN jsonb_build_object('sourceId',p_source,'transactionId',new_id,'state','completed','relation',v_relation);
EXCEPTION WHEN OTHERS THEN
 PERFORM set_config('burimunsi.collection_id',coalesce(old_group,''),true);
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$function$
;

-- private.burimunsi_native_sms_post_facts(text,text,jsonb,jsonb) sha256 23ec864069cd4260ae6da8f96acae3ab0129ca367922c39529f94a7e96b2059e
CREATE OR REPLACE FUNCTION private.burimunsi_native_sms_post_facts(p_source text, p_fingerprint text, p_output jsonb, p_facts jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
DECLARE r jsonb;old_frame text:=current_setting('burimunsi.native_receipt_frame',true);n integer;
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();r:=private.burimunsi_native_sms_post_snapshot(p_source);
 IF r->>'source_fingerprint' IS DISTINCT FROM p_fingerprint OR jsonb_typeof(p_output) IS DISTINCT FROM 'object'
  OR jsonb_typeof(p_facts) IS DISTINCT FROM 'object' OR octet_length(p_output::text)>65536 OR octet_length(p_facts::text)>8192
  OR NOT (p_facts ?& ARRAY['event_kind','payment_outcome','currency','amount_minor','source_mode',
    'wallet_balance_after_minor','counterparty_name','counterparty_identifier','transaction_at','transaction_datetime_raw',
    'provider_transaction_id','original_transaction_id','fee_minor','transaction_time_source','transaction_timezone'])
  OR (p_facts->>'event_kind' IS DISTINCT FROM 'incoming_receipt' AND p_facts->>'event_kind' IS DISTINCT FROM 'outgoing')
  OR p_facts->>'payment_outcome' IS DISTINCT FROM 'successful'
  OR p_facts->>'currency' IS DISTINCT FROM 'RWF' OR jsonb_typeof(p_facts->'amount_minor') IS DISTINCT FROM 'number'
  OR p_facts->>'amount_minor' !~ '^[1-9][0-9]{0,15}$' OR (p_facts->>'amount_minor')::numeric>9007199254740991
  OR jsonb_typeof(p_facts->'counterparty_name') NOT IN ('string','null')
  OR jsonb_typeof(p_facts->'counterparty_identifier') NOT IN ('string','null')
  OR jsonb_typeof(p_facts->'transaction_at') NOT IN ('string','null')
  OR jsonb_typeof(p_facts->'transaction_datetime_raw') NOT IN ('string','null')
  OR jsonb_typeof(p_facts->'transaction_time_source') NOT IN ('string','null')
  OR jsonb_typeof(p_facts->'transaction_timezone') NOT IN ('string','null')
  OR jsonb_typeof(p_facts->'provider_transaction_id') NOT IN ('string','null')
  OR jsonb_typeof(p_facts->'original_transaction_id') NOT IN ('string','null')
  OR jsonb_typeof(p_facts->'fee_minor') NOT IN ('number','null')
  OR jsonb_typeof(p_facts->'wallet_balance_after_minor') NOT IN ('number','null')
  OR (r->>'event_kind'<>'unknown' AND p_facts->>'event_kind' IS DISTINCT FROM r->>'event_kind')
  OR (r->'amount_minor'<>'null'::jsonb AND p_facts->'amount_minor' IS DISTINCT FROM r->'amount_minor')
  OR (r->'currency'<>'null'::jsonb AND p_facts->'currency' IS DISTINCT FROM r->'currency')
  OR (p_facts->>'event_kind'='incoming_receipt' AND
      (jsonb_typeof(p_facts->'wallet_balance_after_minor') IS DISTINCT FROM 'number'
       OR p_facts->>'wallet_balance_after_minor' !~ '^(0|[1-9][0-9]{0,15})$'
       OR (p_facts->>'wallet_balance_after_minor')::numeric>9007199254740991))
  OR p_facts->>'source_mode' IS DISTINCT FROM (CASE WHEN r->>'mode'='live' THEN 'live' ELSE 'catch_up' END) THEN
  RAISE EXCEPTION 'native_sms_posting_facts_changed' USING ERRCODE='40001';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 UPDATE private.burimunsi_auto_sms_jobs SET posting_facts=p_facts,posting_output=p_output
  WHERE source_id=p_source AND collection_id=current_setting('burimunsi.collection_id',true)
   AND (posting_facts IS NULL OR (posting_facts=p_facts AND posting_output=p_output));
 GET DIAGNOSTICS n=ROW_COUNT;PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);
 IF n<>1 THEN RAISE EXCEPTION 'native_sms_posting_facts_changed' USING ERRCODE='40001';END IF;RETURN true;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$function$
;

-- collect_ops.reconcile_jobs() sha256 9bb836da08ef8f9bccd63e0c85d6ed7b900c2957b9a7805102d8f5260b2905ef
CREATE OR REPLACE FUNCTION collect_ops.reconcile_jobs()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE d collect_ops.jobs_dispatches%ROWTYPE;r record;payload jsonb;v_reason text;observed integer:=0;uncertain integer:=0;purged integer;confirmed boolean;processing_ok boolean;notifications_ok boolean;native_ok boolean;native_epoch_now text;
BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.rrlduytparvsjfmegalh',0));
 PERFORM 1 FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 native_epoch_now:=collect_ops.native_jobs_epoch();
 FOR d IN SELECT * FROM collect_ops.jobs_dispatches WHERE state='awaiting' ORDER BY created_at,id LIMIT 20 FOR UPDATE LOOP
  IF native_epoch_now IS NULL OR d.native_epoch IS DISTINCT FROM native_epoch_now THEN
   -- Never match a surviving durable request to a recycled native numeric ID.
   UPDATE collect_ops.jobs_dispatches SET state='unconfirmed',reason='native_transport_instance_changed',http_status=NULL,maintenance_purged=NULL,response_sha256=NULL,observed_at=clock_timestamp() WHERE id=d.id;
   observed:=observed+1;uncertain:=uncertain+1;PERFORM collect_ops.pause_jobs();CONTINUE;
  END IF;
  SELECT status_code,timed_out,error_msg IS NOT NULL AS failed,CASE WHEN octet_length(content)<=16384 THEN content ELSE NULL END AS content INTO r FROM net._http_response WHERE id=d.net_request_id ORDER BY created DESC LIMIT 1;
  IF NOT FOUND THEN
   IF d.created_at>clock_timestamp()-interval '180 seconds' THEN CONTINUE;END IF;
   v_reason:='reply_missing';confirmed:=false;purged:=NULL;
  ELSE
   confirmed:=false;processing_ok:=false;notifications_ok:=false;purged:=NULL;payload:=NULL;v_reason:='reply_unconfirmed';
   IF r.content IS NOT NULL THEN BEGIN payload:=r.content::jsonb;EXCEPTION WHEN OTHERS THEN payload:=NULL;END;END IF;
   IF payload->'maintenance'->>'purged' ~ '^(0|[1-9][0-9]{0,2})$' THEN purged:=(payload->'maintenance'->>'purged')::integer;END IF;
   IF d.runtime_contract IS NULL THEN
    processing_ok:=NOT coalesce(payload?'processing_admission',false) AND payload->'processing'->>'status' IS DISTINCT FROM 'unconfirmed' AND payload->'processing'->'paused'='true'::jsonb
     AND payload->'processing'->'processed'='0'::jsonb AND payload->'processing'->'results'='[]'::jsonb;
   ELSIF payload->'processing_admission'=d.runtime_contract AND payload->'processing'->>'status'='complete'
    AND payload->'processing'->'paused'='false'::jsonb AND payload->'processing'->'processed' IN('0'::jsonb,'1'::jsonb)
    AND jsonb_typeof(payload->'processing'->'results')='array' THEN
    processing_ok:=to_jsonb(jsonb_array_length(payload->'processing'->'results'))=payload->'processing'->'processed';
    IF processing_ok THEN
     processing_ok:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'processing'->'results') item
      WHERE jsonb_typeof(item) IS DISTINCT FROM 'object' OR item->>'state' IS NULL OR item->>'state' NOT IN('completed','needs_review','retry','not_claimed','superseded')
       OR item IS DISTINCT FROM jsonb_build_object('state',item->>'state'));
    END IF;
   END IF;
   IF d.notification_contract IS NULL THEN
    notifications_ok:=NOT coalesce(payload?'notification_admission',false) AND(NOT coalesce(payload?'notifications',false) OR(
     payload->'notifications'->>'status'='disabled' AND payload->'notifications'->'paused'='true'::jsonb
     AND payload->'notifications'->'processed'='0'::jsonb AND payload->'notifications'->'results'='[]'::jsonb AND payload->'notifications'->'recovered_unknown'='0'::jsonb));
   ELSIF payload->'notification_admission'=d.notification_contract AND payload->'notifications'->>'status'='complete'
    AND payload->'notifications'->'paused'='false'::jsonb AND payload->'notifications'->'processed' IN('0'::jsonb,'1'::jsonb)
    AND jsonb_typeof(payload->'notifications'->'results')='array' AND jsonb_typeof(payload->'notifications'->'recovered_unknown')='number'
    AND (CASE WHEN payload->'notifications'->>'recovered_unknown' ~ '^(0|[1-9][0-9]{0,2})$' THEN(payload->'notifications'->>'recovered_unknown')::integer ELSE 101 END) BETWEEN 0 AND 100 THEN
    notifications_ok:=to_jsonb(jsonb_array_length(payload->'notifications'->'results'))=payload->'notifications'->'processed';
    IF notifications_ok THEN
     notifications_ok:=NOT EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'notifications'->'results') item
      WHERE jsonb_typeof(item) IS DISTINCT FROM 'object' OR item->>'state' IS NULL OR item->>'state' NOT IN('accepted','retry','rejected','suppressed','unknown')
       OR item IS DISTINCT FROM jsonb_build_object('state',item->>'state'));
    END IF;
   END IF;
   native_ok:=false;
   IF d.native_contract IS NULL THEN
    native_ok:=NOT coalesce(payload?'native_sms_admission',false) AND NOT coalesce(payload?'native_auto_processing',false) AND NOT coalesce(payload?'native_sms_ledger',false);
   ELSIF payload->'native_sms_admission'=d.native_contract AND payload->'native_auto_processing'->>'status'='complete'
    AND payload->'native_sms_ledger'->>'status'='complete' AND payload->'native_auto_processing'->'processed' IN('0'::jsonb,'1'::jsonb)
    AND payload->'native_sms_ledger'->'processed' IN('0'::jsonb,'1'::jsonb)
    AND jsonb_typeof(payload->'native_auto_processing'->'results')='array' AND jsonb_typeof(payload->'native_sms_ledger'->'results')='array' THEN
    native_ok:=to_jsonb(jsonb_array_length(payload->'native_auto_processing'->'results'))=payload->'native_auto_processing'->'processed'
     AND to_jsonb(jsonb_array_length(payload->'native_sms_ledger'->'results'))=payload->'native_sms_ledger'->'processed'
     AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'native_auto_processing'->'results') item WHERE
      ((item->>'state'='completed' AND item->>'relation' IN('accepted','duplicate','conflict') AND item=jsonb_build_object('state',item->>'state','relation',item->>'relation'))
       OR (item->>'state' IN('security_message','not_claimed','retry') AND item=jsonb_build_object('state',item->>'state'))) IS NOT TRUE)
     AND NOT EXISTS(SELECT 1 FROM jsonb_array_elements(payload->'native_sms_ledger'->'results') item WHERE
      (item->>'state' IN('posted','unmatched','already_posted','not_financial') AND item=jsonb_build_object('state',item->>'state')) IS NOT TRUE);
   END IF;
   IF r.status_code=200 AND NOT coalesce(r.timed_out,true) AND NOT r.failed AND jsonb_typeof(payload->'dispatch_id')='string' AND payload->>'dispatch_id'=d.id::text AND payload->'maintenance'->>'status'='complete'
    AND payload->'maintenance'->>'examined_limit'='100' AND payload->'maintenance'->>'provider_calls'='0'
    AND jsonb_typeof(payload->'maintenance'->'purged')='number' AND payload->'maintenance'->>'purged' ~ '^(0|[1-9][0-9]{0,2})$'
    AND purged BETWEEN 0 AND 100 AND coalesce(processing_ok,false) AND coalesce(notifications_ok,false) AND coalesce(native_ok,false)
    AND EXISTS(SELECT 1 FROM private.collect_managed_job_tickets t WHERE t.dispatch_id=d.id AND t.source_sha256=private.collect_fence_owner_status()->>'sourceSha256'
     AND t.completed_at IS NOT NULL AND t.response_sha256=encode(sha256(convert_to(r.content,'UTF8')),'hex')) THEN
    confirmed:=true;v_reason:='reply_confirmed';purged:=(payload->'maintenance'->>'purged')::integer;
   ELSIF r.status_code=200 AND (jsonb_typeof(payload->'dispatch_id') IS DISTINCT FROM 'string' OR payload->>'dispatch_id' IS DISTINCT FROM d.id::text) THEN v_reason:='dispatch_identity_mismatch';
   ELSIF r.status_code=200 AND d.runtime_contract IS NOT NULL AND payload->'processing_admission' IS DISTINCT FROM d.runtime_contract THEN v_reason:='processing_admission_mismatch';
   ELSIF r.status_code=200 AND d.notification_contract IS NOT NULL AND payload->'notification_admission' IS DISTINCT FROM d.notification_contract THEN v_reason:='notification_admission_mismatch';
   ELSIF r.status_code=200 AND(NOT coalesce(processing_ok,false) OR NOT coalesce(notifications_ok,false) OR NOT coalesce(native_ok,false)) THEN v_reason:='runtime_gate_changed';
   ELSIF r.status_code BETWEEN 400 AND 499 THEN v_reason:='http_rejected';END IF;
  END IF;
  UPDATE collect_ops.jobs_dispatches SET state=CASE WHEN confirmed THEN 'confirmed' ELSE 'unconfirmed' END,reason=v_reason,http_status=CASE WHEN r.status_code BETWEEN 100 AND 599 THEN r.status_code ELSE NULL END,maintenance_purged=CASE WHEN confirmed THEN purged ELSE NULL END,
   response_sha256=CASE WHEN r.content IS NOT NULL THEN encode(sha256(convert_to(r.content,'UTF8')),'hex') ELSE NULL END,observed_at=clock_timestamp() WHERE id=d.id;
  observed:=observed+1;
  IF NOT confirmed THEN uncertain:=uncertain+1;PERFORM collect_ops.pause_jobs();END IF;
 END LOOP;
 RETURN jsonb_build_object('observed',observed,'unconfirmed',uncertain);
END$function$
;
