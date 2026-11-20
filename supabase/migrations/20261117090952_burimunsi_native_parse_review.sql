-- A repeatedly unsupported extraction remains encrypted and retryable with a
-- slower backoff; provider outages retain their separate existing retry path.
-- A verified provider transaction ID independently identifies an incoming
-- payment when its SMS omits wallet balance; no-reference receipts retain the
-- existing balance requirement and all event/source guards.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $preflight$
DECLARE item record;p pg_proc%ROWTYPE;expected_config text[];
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR to_regclass('private.burimunsi_auto_sms_jobs') IS NULL
  OR EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid='private.burimunsi_auto_sms_jobs'::regclass
    AND attname='invalid_output_count' AND attnum>0 AND NOT attisdropped) THEN
  RAISE EXCEPTION 'native_parse_review_precondition' USING ERRCODE='55000';END IF;
 FOR item IN SELECT * FROM (VALUES
  ('private.burimunsi_auto_retry(text,uuid,text,text,text)','a4d11f82ce94ec665aa29df8b3157b3646fca571552d2c892247c5be08400a14',true,'{postgres=X/postgres,collect_runtime=X/postgres}'),
  ('private.burimunsi_auto_finish(text,uuid,text,text,uuid,text,jsonb,jsonb)','cf330a71bf9121f56a87f6ceaa9a4e5c1ec64d46a5d102a7409bde128ae80472',true,'{postgres=X/postgres,collect_runtime=X/postgres}'),
  ('private.burimunsi_native_sms_post_facts(text,text,jsonb,jsonb)','23ec864069cd4260ae6da8f96acae3ab0129ca367922c39529f94a7e96b2059e',true,'{postgres=X/postgres,collect_runtime=X/postgres}')
 ) AS x(signature,digest,security_definer,acl) LOOP
  SELECT * INTO p FROM pg_proc WHERE oid=to_regprocedure(item.signature);
  expected_config:=CASE WHEN item.security_definer THEN ARRAY['search_path=pg_catalog, pg_temp'] ELSE ARRAY['search_path=pg_catalog'] END;
  IF NOT FOUND OR pg_get_userbyid(p.proowner)<>'postgres' OR p.prosecdef IS DISTINCT FROM item.security_definer
   OR p.proacl::text IS DISTINCT FROM item.acl OR p.proconfig IS DISTINCT FROM expected_config
   OR encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') IS DISTINCT FROM item.digest THEN
   RAISE EXCEPTION 'native_parse_review_preimage_changed: %',item.signature USING ERRCODE='55000';END IF;
 END LOOP;
END;$preflight$;

ALTER TABLE private.burimunsi_auto_sms_jobs
 ADD COLUMN invalid_output_count integer NOT NULL DEFAULT 0 CHECK(invalid_output_count BETWEEN 0 AND 5);

DO $retry$
DECLARE oldbody text;definition text;anchor text;replacement text;
BEGIN
 SELECT p.prosrc,pg_get_functiondef(p.oid) INTO STRICT oldbody,definition
 FROM pg_proc p WHERE p.oid='private.burimunsi_auto_retry(text,uuid,text,text,text)'::regprocedure;
 anchor:=$old$at_next:=at_ms+least(3600000::bigint,10000::bigint*(1::bigint << least(j.attempt_count-1,9)::integer));
 UPDATE private.burimunsi_auto_sms_jobs SET state='retry',
  phase='preflight',lease_token=NULL,lease_until=NULL,
  retry_lease=p_lease,last_error=p_reason,next_attempt_at=at_next,updated_at=at_ms WHERE source_id=p_source;$old$;
 replacement:=$new$IF p_reason='invalid_output' AND j.invalid_output_count>=4 THEN
  at_next:=at_ms+86400000::bigint;
 ELSE
  at_next:=at_ms+least(3600000::bigint,10000::bigint*(1::bigint << least(j.attempt_count-1,9)::integer));
 END IF;
 UPDATE private.burimunsi_auto_sms_jobs SET state='retry',
  phase='preflight',lease_token=NULL,lease_until=NULL,
  invalid_output_count=least(5,j.invalid_output_count+CASE WHEN p_reason='invalid_output' THEN 1 ELSE 0 END),
  retry_lease=p_lease,last_error=p_reason,next_attempt_at=at_next,updated_at=at_ms WHERE source_id=p_source;$new$;
 IF length(oldbody)-length(replace(oldbody,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'native_parse_review_retry_anchor_changed' USING ERRCODE='55000';END IF;
 oldbody:=replace(oldbody,anchor,replacement);
 EXECUTE 'CREATE OR REPLACE FUNCTION private.burimunsi_auto_retry(p_source text,p_lease uuid,p_fingerprint text,p_profile_sha text,p_reason text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(oldbody);
END;$retry$;

DO $finish$
DECLARE body text;anchor text;replacement text;
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.burimunsi_auto_finish(text,uuid,text,text,uuid,text,jsonb,jsonb)'::regprocedure;
 anchor:=$old$CASE WHEN kind='incoming_receipt' AND outcome='successful' AND amount IS NOT NULL AND balance IS NOT NULL
    AND p_facts->>'currency' IS NOT NULL THEN 'unallocated' ELSE 'not_applicable' END$old$;
 replacement:=$new$CASE WHEN kind='incoming_receipt' AND outcome='successful' AND amount IS NOT NULL AND (balance IS NOT NULL OR ref IS NOT NULL)
    AND p_facts->>'currency' IS NOT NULL THEN 'unallocated' ELSE 'not_applicable' END$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'native_parse_review_finish_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION private.burimunsi_auto_finish(p_source text,p_lease uuid,p_fingerprint text,p_profile_sha text,p_attempt uuid,p_model text,p_output jsonb,p_facts jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(replace(body,anchor,replacement));
END;$finish$;

DO $facts$
DECLARE body text;anchor text;replacement text;
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.burimunsi_native_sms_post_facts(text,text,jsonb,jsonb)'::regprocedure;
 anchor:=$old$OR (p_facts->>'event_kind'='incoming_receipt' AND
      (jsonb_typeof(p_facts->'wallet_balance_after_minor') IS DISTINCT FROM 'number'
       OR p_facts->>'wallet_balance_after_minor' !~ '^(0|[1-9][0-9]{0,15})$'
       OR (p_facts->>'wallet_balance_after_minor')::numeric>9007199254740991))$old$;
 replacement:=$new$OR (p_facts->>'event_kind'='incoming_receipt' AND p_facts->'wallet_balance_after_minor'='null'::jsonb
      AND (NULLIF(p_facts->>'provider_transaction_id','') IS NULL
       OR length(p_facts->>'provider_transaction_id')>160 OR p_facts->>'provider_transaction_id' ~ '[[:space:]]'
       OR r->>'provider_transaction_id' IS DISTINCT FROM p_facts->>'provider_transaction_id'))
  OR (p_facts->>'event_kind'='incoming_receipt' AND jsonb_typeof(p_facts->'wallet_balance_after_minor')='number'
      AND (p_facts->>'wallet_balance_after_minor' !~ '^(0|[1-9][0-9]{0,15})$'
       OR (p_facts->>'wallet_balance_after_minor')::numeric>9007199254740991))$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'native_parse_review_facts_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION private.burimunsi_native_sms_post_facts(p_source text,p_fingerprint text,p_output jsonb,p_facts jsonb) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(replace(body,anchor,replacement));
END;$facts$;

COMMIT;
