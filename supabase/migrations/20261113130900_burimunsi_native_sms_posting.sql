-- Extend the existing native SMS processing job with source-bound parse facts.
-- Posting remains in the existing Collect payment/ledger transaction.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';SET LOCAL statement_timeout='60s';
DO $check$
DECLARE body text;
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF current_user<>'postgres' OR session_user<>'postgres'
  OR NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced')
  OR EXISTS(SELECT 1 FROM private.collect_fence_control WHERE mode<>'fenced')
  OR to_regprocedure('private.burimunsi_auto_plan(text)') IS NULL
  OR to_regclass('private.burimunsi_auto_sms_jobs') IS NULL
  OR to_regprocedure('private.burimunsi_native_sms_post_candidates(integer)') IS NOT NULL THEN
  RAISE EXCEPTION 'native_sms_posting_precondition' USING ERRCODE='55000';END IF;
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.burimunsi_auto_finish(text,uuid,text,text,uuid,text,jsonb,jsonb)'::regprocedure;
 IF encode(sha256(convert_to(body,'UTF8')),'hex')<>'6c6a19c0047cc876e30db070b104e999f267d259f4b00e6a4e1ac4c109229271' THEN
  RAISE EXCEPTION 'native_sms_posting_predecessor_changed' USING ERRCODE='55000';END IF;
END;$check$;

ALTER TABLE private.burimunsi_auto_sms_jobs
 ADD COLUMN posting_facts jsonb,
 ADD COLUMN posting_output jsonb,
 ADD COLUMN posting_next_attempt_at bigint NOT NULL DEFAULT 0 CHECK(posting_next_attempt_at>=0),
 ADD CONSTRAINT native_sms_posting_facts_shape CHECK((posting_facts IS NULL)=(posting_output IS NULL));

-- An independently supplied provider reference is not required for a native
-- receipt: a complete amount/currency/balance and retained source identify it.
ALTER TABLE app.momo_transactions DROP CONSTRAINT burimunsi_native_nullable_fact_shape;
ALTER TABLE app.momo_transactions ADD CONSTRAINT burimunsi_native_nullable_fact_shape CHECK(
 (provider_transaction_id IS NOT NULL AND amount_minor IS NOT NULL AND currency IS NOT NULL AND currency_scale IS NOT NULL)
 OR (allocation_state='not_applicable' AND (currency IS NULL AND currency_scale IS NULL OR currency IS NOT NULL AND currency_scale=0))
 OR (provider_transaction_id IS NULL AND event_kind='incoming_receipt' AND amount_minor IS NOT NULL AND amount_minor>0
     AND currency IS NOT NULL AND currency='RWF' AND currency_scale IS NOT NULL AND currency_scale=0));

-- Keep the parser's original source and transaction semantics, accepting the
-- source-grounded receipt with no provider reference and retaining last digits.
DO $finish$
DECLARE body text;anchor text;replacement text;
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.burimunsi_auto_finish(text,uuid,text,text,uuid,text,jsonb,jsonb)'::regprocedure;
 anchor:=$old$CASE WHEN kind='incoming_receipt' AND outcome='successful' AND amount IS NOT NULL AND ref IS NOT NULL
    AND p_facts->>'currency' IS NOT NULL THEN 'unallocated' ELSE 'not_applicable' END$old$;
 replacement:=$new$CASE WHEN kind='incoming_receipt' AND outcome='successful' AND amount IS NOT NULL AND balance IS NOT NULL
    AND p_facts->>'currency' IS NOT NULL THEN 'unallocated' ELSE 'not_applicable' END$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'native_sms_posting_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 anchor:=$old$p_facts->>'counterparty_name',p_facts->>'counterparty_identifier',NULL,$old$;
 replacement:=$new$p_facts->>'counterparty_name',p_facts->>'counterparty_identifier',
   CASE WHEN length(regexp_replace(coalesce(p_facts->>'counterparty_identifier',''),'[^0-9]','','g'))>=3
    THEN right(regexp_replace(p_facts->>'counterparty_identifier','[^0-9]','','g'),3) ELSE NULL END,$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'native_sms_posting_anchor_changed' USING ERRCODE='55000';END IF;
 body:=replace(body,anchor,replacement);
 EXECUTE 'CREATE OR REPLACE FUNCTION private.burimunsi_auto_finish(p_source text,p_lease uuid,p_fingerprint text,p_profile_sha text,p_attempt uuid,p_model text,p_output jsonb,p_facts jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(body);
END;$finish$;

-- A bounded selector returns only opaque, server-owned identities to an
-- already-admitted jobs worker. Delayed unmatched jobs cannot starve later ones.
CREATE FUNCTION private.burimunsi_native_sms_post_candidates(p_limit integer) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE answer jsonb;old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 IF p_limit IS NULL OR p_limit<>1 THEN RAISE EXCEPTION 'native_sms_posting_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT coalesce(jsonb_agg(jsonb_build_object('groupId',collection_id,'sourceId',source_id) ORDER BY due,created_at,source_id),'[]'::jsonb)
 INTO answer FROM (
  SELECT j.collection_id,j.source_id,j.posting_next_attempt_at AS due,j.created_at
  FROM private.burimunsi_auto_sms_jobs j JOIN app.momo_transactions t ON t.id=j.transaction_id
  WHERE j.state='completed' AND j.relation='accepted'
   AND t.event_kind IN ('incoming_receipt','outgoing','unknown') AND t.has_conflict=0
   AND (j.posting_facts IS NULL OR (j.posting_facts->>'event_kind'='incoming_receipt'
       AND t.allocation_state IN ('unallocated','not_applicable')))
   AND j.posting_next_attempt_at<=floor(extract(epoch FROM clock_timestamp())*1000)::bigint
   AND NOT EXISTS(SELECT 1 FROM app.momo_financial_links f WHERE f.transaction_id=t.id)
  ORDER BY j.posting_next_attempt_at,j.created_at,j.source_id LIMIT p_limit
 ) q;
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RETURN answer;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_sms_post_candidates(integer) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_sms_post_candidates(integer) TO collect_runtime;

-- Source, capture principal and parse attempt are joined from retained rows,
-- never supplied by the Android request or scheduler caller.
CREATE FUNCTION private.burimunsi_native_sms_post_snapshot(p_source text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE v_row record;answer jsonb;old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();PERFORM private.burimunsi_auto_plan(p_source);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT j.collection_id,j.source_id,j.source_fingerprint,j.relation,j.payment_outcome,j.posting_facts,j.posting_output,
  o.principal_user_id,o.capture_session_id,r.body_sha256,r.object_sha256,r.object_key,r.size_bytes,
  t.id AS transaction_id,t.receiving_account_id,t.provider,t.provider_transaction_id,t.event_kind,t.amount_minor,t.currency,
  t.payer_name,t.payer_identifier,t.wallet_balance_after_minor,t.mode,t.allocation_state,t.has_conflict,t.version,t.transaction_at,t.created_at,
  a.output_json,a.model_id,a.profile_version,a.profile_json,w.public_code,g.receiver_display_label,
  EXISTS(SELECT 1 FROM app.momo_financial_links f WHERE f.transaction_id=t.id) AS has_link,
  EXISTS(SELECT 1 FROM app.momo_financial_links f JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=j.collection_id
   JOIN app.ledger_entries l ON l.payment_id=p.id AND l.collection_id=p.collection_id AND l.kind='contribution'
    AND l.member_id=p.member_id AND l.amount_minor=p.amount_minor AND l.evidence_id=p.evidence_id
   JOIN app.contribution_posting_snapshots s ON s.payment_id=p.id AND s.ledger_entry_id=l.id
   WHERE f.transaction_id=t.id AND f.beneficiary_member_id=p.member_id AND p.amount_minor=t.amount_minor
    AND p.status IN ('reconciled','confirmed') AND NOT EXISTS(SELECT 1 FROM app.ledger_entries undo WHERE undo.reverses_entry_id=l.id)) AS link_posted
 INTO v_row FROM private.burimunsi_auto_sms_jobs j
 JOIN private.burimunsi_native_receipt_origins o ON o.source_id=j.source_id AND o.collection_id=j.collection_id
 JOIN private.burimunsi_transaction_scopes x ON x.native_source_id=j.source_id AND x.transaction_id=j.transaction_id AND x.collection_id=j.collection_id
 JOIN app.sms_receipts r ON r.id=j.source_id AND r.owner_user_id=o.principal_user_id AND r.body_sha256=o.body_sha256 AND r.object_sha256=o.object_sha256
 JOIN app.momo_transactions t ON t.id=j.transaction_id AND t.receiving_account_id=j.receiving_account_id AND t.receiving_account_id=x.receiving_account_id
 JOIN app.momo_parse_attempts a ON a.id=j.attempt_id::text AND a.raw_sms_id=j.source_id AND a.source_body_sha256=r.body_sha256
 JOIN app.momo_receiving_accounts w ON w.id=t.receiving_account_id AND w.status='active'
 JOIN app.collections g ON g.id=j.collection_id AND g.status='active'
 WHERE j.source_id=p_source AND j.collection_id=current_setting('burimunsi.collection_id',true)
  AND j.state='completed' AND j.relation='accepted'
  AND t.event_kind IN ('incoming_receipt','outgoing','unknown')
 FOR UPDATE OF j,t FOR SHARE OF o,r,a,w,g,x;
 IF NOT FOUND THEN RAISE EXCEPTION 'native_sms_posting_source_changed' USING ERRCODE='40001';END IF;
 answer:=to_jsonb(v_row);PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RETURN answer;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_sms_post_snapshot(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_sms_post_snapshot(text) TO collect_runtime;

CREATE FUNCTION private.burimunsi_native_sms_post_defer(p_source text,p_delay_ms integer) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE old_frame text:=current_setting('burimunsi.native_receipt_frame',true);n integer;
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 IF p_delay_ms IS NULL OR p_delay_ms NOT BETWEEN 1000 AND 86400000 THEN RAISE EXCEPTION 'native_sms_posting_invalid' USING ERRCODE='22023';END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 UPDATE private.burimunsi_auto_sms_jobs SET posting_next_attempt_at=floor(extract(epoch FROM clock_timestamp())*1000)::bigint+p_delay_ms
  WHERE source_id=p_source AND collection_id=current_setting('burimunsi.collection_id',true) AND state='completed';
 GET DIAGNOSTICS n=ROW_COUNT;PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RETURN n=1;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_sms_post_defer(text,integer) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_sms_post_defer(text,integer) TO collect_runtime;

CREATE FUNCTION private.burimunsi_native_sms_post_facts(p_source text,p_fingerprint text,p_output jsonb,p_facts jsonb) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
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
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_native_sms_post_facts(text,text,jsonb,jsonb) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_native_sms_post_facts(text,text,jsonb,jsonb) TO collect_runtime;
-- Add only source-grounded facts to the existing role-checked record projection.
DO $projection$
DECLARE body text;anchor text;replacement text;
BEGIN
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.burimunsi_auto_projection(text)'::regprocedure;
 anchor:=$old$RETURN jsonb_build_object('sourceId',j.source_id,'outcome',j.payment_outcome,'canReveal',can_reveal);$old$;
 replacement:=$new$RETURN jsonb_build_object('sourceId',j.source_id,'outcome',coalesce(j.posting_facts->>'payment_outcome',j.payment_outcome),'canReveal',can_reveal,'facts',j.posting_facts);$new$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN RAISE EXCEPTION 'native_sms_projection_anchor_changed' USING ERRCODE='55000';END IF;
 EXECUTE 'CREATE OR REPLACE FUNCTION private.burimunsi_auto_projection(p_source text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(replace(body,anchor,replacement));
END;$projection$;

CREATE FUNCTION private.burimunsi_admin_sms_facts(p_transaction text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $fn$
DECLARE v jsonb;answer jsonb;old_frame text:=current_setting('burimunsi.native_receipt_frame',true);
BEGIN
 v:=private.burimunsi_admin_transaction_visibility(p_transaction);
 IF v->>'kind' IS DISTINCT FROM 'visible' THEN RETURN NULL;END IF;
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 SELECT j.posting_facts INTO answer FROM private.burimunsi_auto_sms_jobs j
 WHERE j.transaction_id=p_transaction AND j.collection_id=v->>'groupId' AND j.state='completed' AND j.relation='accepted';
 PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RETURN answer;
EXCEPTION WHEN OTHERS THEN PERFORM set_config('burimunsi.native_receipt_frame',coalesce(old_frame,''),true);RAISE;
END;$fn$;
REVOKE ALL ON FUNCTION private.burimunsi_admin_sms_facts(text) FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_admin_sms_facts(text) TO collect_runtime;
COMMIT;
