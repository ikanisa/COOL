-- BuriMunsi automatic payment receipt obligations. No payment or carrier actions.
BEGIN;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $preflight$
BEGIN
 PERFORM private._collect_fence_require_operator();
 IF NOT EXISTS(SELECT 1 FROM private.collect_fence_control WHERE singleton AND mode='fenced') THEN
  RAISE EXCEPTION 'burimunsi_payment_sms_fence_required' USING ERRCODE='55000';
 END IF;
END;$preflight$;

CREATE TABLE private.burimunsi_payment_sms_deliveries (
 attempt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 collection_id text NOT NULL, payment_id text NOT NULL UNIQUE, ledger_entry_id text NOT NULL UNIQUE,
 event_id text NOT NULL UNIQUE, recipient_user_id text NOT NULL,
 destination_sha256 text NOT NULL CHECK(destination_sha256 ~ '^[a-f0-9]{64}$'),
 authorization_revision bigint, amount_rwf bigint NOT NULL CHECK(amount_rwf BETWEEN 1 AND 9007199254740991),
 member_balance_rwf bigint NOT NULL CHECK(member_balance_rwf BETWEEN 0 AND 9007199254740991),
 group_name text NOT NULL CHECK(length(group_name) BETWEEN 1 AND 160),
 posted_at timestamptz NOT NULL, enabled_at timestamptz NOT NULL,
 application_id text NOT NULL, message_id text NOT NULL UNIQUE, idempotency_key text NOT NULL,
 not_after timestamptz NOT NULL,
 body_sha256 text CHECK(body_sha256 ~ '^[a-f0-9]{64}$'),
 state text NOT NULL DEFAULT 'sending' CHECK(state IN ('sending','accepted','unknown','suppressed')),
 provider_state text, evidence_sha256 text CHECK(evidence_sha256 ~ '^[a-f0-9]{64}$'),
 claim_token uuid, claim_phase text CHECK(claim_phase IN ('send','inspect')), lease_until timestamptz,
 next_inspect_at timestamptz NOT NULL, inspect_count integer NOT NULL DEFAULT 0 CHECK(inspect_count BETWEEN 0 AND 12),
 CHECK((claim_token IS NULL)=(claim_phase IS NULL) AND (claim_token IS NULL)=(lease_until IS NULL))
);
CREATE INDEX burimunsi_payment_sms_reconciliation
 ON private.burimunsi_payment_sms_deliveries(collection_id,application_id,next_inspect_at,attempt_id)
 WHERE state IN ('sending','accepted','unknown') AND body_sha256 IS NOT NULL;
ALTER TABLE private.burimunsi_payment_sms_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.burimunsi_payment_sms_deliveries FORCE ROW LEVEL SECURITY;
REVOKE ALL ON private.burimunsi_payment_sms_deliveries FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
CREATE POLICY burimunsi_payment_sms_frame ON private.burimunsi_payment_sms_deliveries TO postgres
 USING(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.payment_sms_frame',true)='1')
 WITH CHECK(current_setting('role',true)='collect_runtime' AND current_setting('collect.edge_verified',true)='true'
  AND current_setting('burimunsi.payment_sms_frame',true)='1');
CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
 ON private.burimunsi_payment_sms_deliveries FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
ALTER TABLE private.burimunsi_payment_sms_deliveries ENABLE ALWAYS TRIGGER collect_fence_statement_v1;

CREATE FUNCTION private._burimunsi_payment_sms_immutable() RETURNS trigger
 LANGUAGE plpgsql SET search_path=pg_catalog,pg_temp AS $fn$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'payment_sms_retained' USING ERRCODE='42501';END IF;
 IF ROW(OLD.attempt_id,OLD.collection_id,OLD.payment_id,OLD.ledger_entry_id,OLD.event_id,OLD.recipient_user_id,
   OLD.destination_sha256,OLD.authorization_revision,OLD.amount_rwf,OLD.member_balance_rwf,OLD.group_name,
   OLD.posted_at,OLD.enabled_at,OLD.application_id,OLD.message_id,OLD.idempotency_key,OLD.not_after)
  IS DISTINCT FROM
  ROW(NEW.attempt_id,NEW.collection_id,NEW.payment_id,NEW.ledger_entry_id,NEW.event_id,NEW.recipient_user_id,
   NEW.destination_sha256,NEW.authorization_revision,NEW.amount_rwf,NEW.member_balance_rwf,NEW.group_name,
   NEW.posted_at,NEW.enabled_at,NEW.application_id,NEW.message_id,NEW.idempotency_key,NEW.not_after)
  OR (OLD.body_sha256 IS NOT NULL AND OLD.body_sha256 IS DISTINCT FROM NEW.body_sha256)
  OR (OLD.claim_phase IS DISTINCT FROM 'send' AND NEW.claim_phase='send') THEN
  RAISE EXCEPTION 'payment_sms_identity_changed' USING ERRCODE='42501';END IF;
 RETURN NEW;
END;$fn$;
CREATE TRIGGER burimunsi_payment_sms_immutable BEFORE UPDATE OR DELETE
 ON private.burimunsi_payment_sms_deliveries FOR EACH ROW EXECUTE FUNCTION private._burimunsi_payment_sms_immutable();
ALTER TABLE private.burimunsi_payment_sms_deliveries ENABLE ALWAYS TRIGGER burimunsi_payment_sms_immutable;

CREATE FUNCTION private._burimunsi_payment_sms_phone(p_number text) RETURNS text
 LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT CASE WHEN n ~ '^\+2507[2389][0-9]{7}$' THEN n
  WHEN n ~ '^002507[2389][0-9]{7}$' THEN '+'||substr(n,3)
  WHEN n ~ '^2507[2389][0-9]{7}$' THEN '+'||n
  WHEN n ~ '^07[2389][0-9]{7}$' THEN '+250'||substr(n,2)
  WHEN n ~ '^7[2389][0-9]{7}$' THEN '+250'||n END
 FROM (SELECT translate(p_number,' ().-','') AS n) formatted
$fn$;

-- The settled ledger and its immutable snapshot supply facts. The captured
-- full payer number must independently equal the active beneficiary's number.
CREATE FUNCTION private._burimunsi_payment_sms_sources(
 p_collection_id text,p_enabled_at timestamptz,p_now timestamptz,p_payment_id text DEFAULT NULL
) RETURNS TABLE(event_id text,payment_id text,ledger_entry_id text,recipient_user_id text,
 destination text,destination_sha256 text,authorization_revision bigint,amount_rwf bigint,
 member_balance_rwf bigint,group_name text,posted_at timestamptz)
 LANGUAGE sql STABLE SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT ev.id,p.id,l.id,u.id,contact.destination,contact.destination_hash,a.consent_revision,p.amount_minor,
  s.member_balance_after_minor,ev.data_json::jsonb->>'group_name',clock.posted_at
 FROM app.payments p
 JOIN app.collections c ON c.id=p.collection_id AND c.status='active'
 JOIN app.users u ON u.id=p.member_id AND u.access_status='active' AND u.member_type<>'operator'
 JOIN app.memberships m ON m.collection_id=c.id AND m.user_id=u.id AND m.active=1
 JOIN app.ledger_entries l ON l.payment_id=p.id AND l.collection_id=c.id AND l.member_id=u.id
  AND l.kind='contribution' AND l.amount_minor=p.amount_minor AND l.currency='RWF' AND l.evidence_id=p.evidence_id
 JOIN app.contribution_posting_snapshots s ON s.payment_id=p.id AND s.ledger_entry_id=l.id AND s.posted_at=l.posted_at
 JOIN app.momo_financial_links f ON f.payment_id=p.id AND f.beneficiary_member_id=u.id AND f.historical_existing=0
 JOIN app.momo_transactions t ON t.id=f.transaction_id AND t.mode='live' AND t.event_kind='incoming_receipt'
  AND t.allocation_state='linked' AND t.has_conflict=0 AND t.currency='RWF' AND t.amount_minor=p.amount_minor
  AND t.transaction_time_source='sms_body_and_provider_profile'
 JOIN private.burimunsi_transaction_scopes x ON x.transaction_id=t.id AND x.collection_id=c.id
  AND x.receiving_account_id=t.receiving_account_id AND x.native_source_id IS NOT NULL AND x.policy_version='native.auto.v1'
 LEFT JOIN app.assisted_sms_authorizations a ON a.collection_id=c.id AND a.recipient_user_id=u.id
 LEFT JOIN app.notification_preferences pref ON pref.user_id=u.id
 CROSS JOIN LATERAL (SELECT private._burimunsi_payment_sms_phone(t.payer_identifier) AS destination) payer
 CROSS JOIN LATERAL (SELECT payer.destination,encode(sha256(convert_to(payer.destination,'UTF8')),'hex') AS destination_hash) contact
 CROSS JOIN LATERAL (SELECT
  CASE WHEN pg_input_is_valid(s.posted_at,'timestamptz') THEN s.posted_at::timestamptz END AS posted_at,
  CASE WHEN pg_input_is_valid(t.transaction_at,'timestamptz') THEN t.transaction_at::timestamptz END AS paid_at) clock
 JOIN LATERAL (
  SELECT n.id,n.data_json FROM app.notification_events n WHERE n.user_id=u.id AND n.event_type='contribution'
   AND n.data_json::jsonb->>'payment_id'=p.id AND n.data_json::jsonb->>'collection_id'=c.id
   AND n.data_json::jsonb->>'amount_rwf'=p.amount_minor::text
   AND n.data_json::jsonb->>'member_balance_after_contribution_rwf'=s.member_balance_after_minor::text
   AND n.data_json::jsonb->>'posted_at'=s.posted_at
   AND n.data_json::jsonb->>'balance_basis'='after_this_contribution'
   AND length(n.data_json::jsonb->>'group_name') BETWEEN 1 AND 160
   AND n.data_json::jsonb->>'group_name' !~ '[[:cntrl:]]'
  ORDER BY n.created_at,n.id LIMIT 1
 ) ev ON true
 WHERE c.id=p_collection_id AND (p_payment_id IS NULL OR p.id=p_payment_id)
  AND p.status IN ('confirmed','reconciled') AND p.rail='rwanda_momo' AND p.currency='RWF' AND p.amount_minor>0
  AND clock.posted_at BETWEEN p_enabled_at AND p_now AND clock.posted_at+interval '5 minutes'>p_now
  AND clock.paid_at BETWEEN p_enabled_at AND clock.posted_at
  AND contact.destination=private._burimunsi_payment_sms_phone(u.momo_number)
  AND (a.recipient_user_id IS NULL OR a.enabled=1 AND a.destination_sha256=contact.destination_hash
   AND (a.phone_verification_challenge_id IS NULL OR private.managed_phone_binding(u.id,a.phone_verification_challenge_id,contact.destination)))
  AND coalesce(pref.payment_updates,1)=1
  AND NOT EXISTS(SELECT 1 FROM app.ledger_entries reversed WHERE reversed.reverses_entry_id=l.id)
  AND NOT EXISTS(SELECT 1 FROM app.momo_transactions reversal WHERE reversal.event_kind='reversal'
    AND reversal.original_transaction_id=t.provider_transaction_id
    AND reversal.receiving_account_id=t.receiving_account_id)
  AND NOT EXISTS(SELECT 1 FROM app.privacy_retention_barriers b WHERE b.subject_id=u.id)
$fn$;

CREATE FUNCTION private._burimunsi_payment_sms_claim_json(
 j private.burimunsi_payment_sms_deliveries,p_destination text
) RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,pg_temp AS $fn$
 SELECT jsonb_build_object(
  'phase',j.claim_phase,'attempt_id',j.attempt_id,'claim_token',j.claim_token,
  'collection_id',j.collection_id,'payment_id',j.payment_id,'ledger_entry_id',j.ledger_entry_id,
  'recipient_user_id',j.recipient_user_id,'destination',p_destination,'destination_sha256',j.destination_sha256,
  'amount_rwf',j.amount_rwf,'member_balance_rwf',j.member_balance_rwf,'group_name',j.group_name,
  'posted_at',to_char(j.posted_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'posted_reference',j.payment_id,
  'application_id',j.application_id,'message_id',j.message_id,'idempotency_key',j.idempotency_key,
  'not_after',to_char(j.not_after AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),'body_sha256',j.body_sha256)
$fn$;

CREATE FUNCTION private.burimunsi_claim_payment_sms(p_collection_id text,p_enabled_at timestamptz,p_application_id text,p_limit integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
 AS $fn$
DECLARE j private.burimunsi_payment_sms_deliveries%ROWTYPE;k text;src record;at timestamptz;
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 PERFORM set_config('burimunsi.payment_sms_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 IF p_collection_id IS NULL OR p_collection_id !~ '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
  OR p_application_id IS NULL OR p_application_id !~ '^app_[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
  OR p_enabled_at IS NULL OR NOT isfinite(p_enabled_at) OR p_limit IS DISTINCT FROM 1 THEN
  RAISE EXCEPTION 'payment_sms_claim_invalid' USING ERRCODE='22023';END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM set_config('burimunsi.collection_id',p_collection_id,true);
 at:=clock_timestamp();
 IF p_enabled_at>at THEN RETURN '[]'::jsonb;END IF;

 -- A lease without an armed body never authorized a POST. It is retained and
 -- cannot become a new send, including after a lost claim acknowledgment.
 UPDATE private.burimunsi_payment_sms_deliveries SET state='suppressed',claim_token=NULL,claim_phase=NULL,lease_until=NULL
 WHERE attempt_id IN(SELECT attempt_id FROM private.burimunsi_payment_sms_deliveries
  WHERE collection_id=p_collection_id AND application_id=p_application_id AND state='sending'
   AND body_sha256 IS NULL AND lease_until<=at ORDER BY lease_until,attempt_id LIMIT 10);

 SELECT * INTO src FROM private._burimunsi_payment_sms_sources(p_collection_id,p_enabled_at,at) s
 WHERE NOT EXISTS(SELECT 1 FROM private.burimunsi_payment_sms_deliveries d WHERE d.payment_id=s.payment_id)
 ORDER BY s.posted_at,s.ledger_entry_id LIMIT 1;
 IF FOUND THEN
  k:='buri-receipt:'||src.ledger_entry_id;
  INSERT INTO private.burimunsi_payment_sms_deliveries(collection_id,payment_id,ledger_entry_id,event_id,recipient_user_id,
   destination_sha256,authorization_revision,amount_rwf,member_balance_rwf,group_name,posted_at,enabled_at,
   application_id,message_id,idempotency_key,not_after,claim_token,claim_phase,lease_until,next_inspect_at)
  VALUES(p_collection_id,src.payment_id,src.ledger_entry_id,src.event_id,src.recipient_user_id,
   src.destination_sha256,src.authorization_revision,src.amount_rwf,src.member_balance_rwf,src.group_name,src.posted_at,p_enabled_at,
   p_application_id,p_application_id||':'||k,k,src.posted_at+interval '5 minutes',gen_random_uuid(),'send',at+interval '45 seconds',at+interval '45 seconds')
  ON CONFLICT(payment_id) DO NOTHING RETURNING * INTO j;
  IF FOUND THEN RETURN jsonb_build_array(private._burimunsi_payment_sms_claim_json(j,src.destination));END IF;
 END IF;

 SELECT * INTO j FROM private.burimunsi_payment_sms_deliveries d
 WHERE d.collection_id=p_collection_id AND d.application_id=p_application_id AND d.body_sha256 IS NOT NULL
  AND (d.lease_until IS NULL OR d.lease_until<=at) AND d.next_inspect_at<=at
  AND d.inspect_count<12 AND d.not_after+interval '24 hours'>at AND d.state IN ('sending','accepted','unknown')
  AND (d.provider_state IS NULL OR d.provider_state IN ('accepted','assigned','phone_accepted','queued','handoff_started','sent','partial','outcome_unknown'))
 ORDER BY d.next_inspect_at,d.attempt_id LIMIT 1 FOR UPDATE SKIP LOCKED;
 IF NOT FOUND THEN RETURN '[]'::jsonb;END IF;
 UPDATE private.burimunsi_payment_sms_deliveries d
  SET claim_token=gen_random_uuid(),claim_phase='inspect',lease_until=at+interval '45 seconds',
   next_inspect_at=at+interval '1 minute',inspect_count=d.inspect_count+1
  WHERE d.attempt_id=j.attempt_id RETURNING d.* INTO j;
 RETURN jsonb_build_array(private._burimunsi_payment_sms_claim_json(j,NULL));
END;$fn$;

CREATE FUNCTION private.burimunsi_prepare_payment_sms(p_collection_id text,p_attempt_id uuid,p_claim_token uuid,p_body_sha256 text)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
 AS $fn$
DECLARE j private.burimunsi_payment_sms_deliveries%ROWTYPE;at timestamptz;
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 PERFORM set_config('burimunsi.payment_sms_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 IF p_body_sha256 IS NULL OR p_body_sha256 !~ '^[a-f0-9]{64}$' THEN RETURN false;END IF;
 PERFORM pg_advisory_xact_lock(734636924058501::bigint);
 PERFORM set_config('burimunsi.collection_id',p_collection_id,true);
 at:=clock_timestamp();
 SELECT * INTO j FROM private.burimunsi_payment_sms_deliveries WHERE collection_id=p_collection_id AND attempt_id=p_attempt_id
  AND claim_token=p_claim_token AND claim_phase='send' AND lease_until>at AND not_after>at
  AND state='sending' AND body_sha256 IS NULL FOR UPDATE;
 IF NOT FOUND THEN RETURN false;END IF;
 IF NOT EXISTS(SELECT 1 FROM private._burimunsi_payment_sms_sources(p_collection_id,j.enabled_at,at,j.payment_id) s
  WHERE ROW(s.event_id,s.ledger_entry_id,s.recipient_user_id,s.destination_sha256,s.authorization_revision,
   s.amount_rwf,s.member_balance_rwf,s.group_name,s.posted_at)
  IS NOT DISTINCT FROM ROW(j.event_id,j.ledger_entry_id,j.recipient_user_id,j.destination_sha256,j.authorization_revision,
   j.amount_rwf,j.member_balance_rwf,j.group_name,j.posted_at)) THEN RETURN false;END IF;
 UPDATE private.burimunsi_payment_sms_deliveries SET body_sha256=p_body_sha256
  WHERE attempt_id=j.attempt_id;
 RETURN FOUND;
END;$fn$;

CREATE FUNCTION private.burimunsi_finish_payment_sms(p_collection_id text,p_attempt_id uuid,p_claim_token uuid,
 p_state text,p_provider_state text,p_evidence_sha256 text)
 RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
 AS $fn$
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 PERFORM set_config('burimunsi.payment_sms_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 IF p_state IS NULL OR p_state NOT IN ('accepted','unknown','suppressed')
  OR p_evidence_sha256 IS NOT NULL AND p_evidence_sha256 !~ '^[a-f0-9]{64}$'
  OR p_state='accepted' AND (p_evidence_sha256 IS NULL OR p_provider_state IS NULL
   OR p_provider_state NOT IN ('accepted','assigned','phone_accepted','queued','handoff_started','sent','delivered',
    'delivery_unconfirmed','partial','outcome_unknown','expired','cancelled','failed'))
  OR p_state<>'accepted' AND p_provider_state IS NOT NULL THEN RETURN false;END IF;
 UPDATE private.burimunsi_payment_sms_deliveries d SET
  state=CASE WHEN p_state='unknown' AND d.provider_state IS NOT NULL THEN d.state ELSE p_state END,
  provider_state=coalesce(p_provider_state,d.provider_state),
  evidence_sha256=CASE WHEN p_state='unknown' AND d.provider_state IS NOT NULL THEN d.evidence_sha256
   ELSE coalesce(p_evidence_sha256,d.evidence_sha256) END,
  claim_token=NULL,claim_phase=NULL,lease_until=NULL,next_inspect_at=clock_timestamp()+interval '1 minute'
 WHERE d.collection_id=p_collection_id AND d.attempt_id=p_attempt_id AND d.claim_token=p_claim_token
  AND (p_state<>'accepted' OR d.body_sha256 IS NOT NULL)
  AND (p_state<>'suppressed' OR d.claim_phase='send' AND d.body_sha256 IS NULL);
 RETURN FOUND;
END;$fn$;

CREATE FUNCTION private.burimunsi_payment_sms_readiness(p_collection_id text,p_enabled_at timestamptz,p_application_id text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp
 AS $fn$
DECLARE at timestamptz:=clock_timestamp();
BEGIN
 PERFORM private.burimunsi_auto_jobs_guard();
 PERFORM set_config('burimunsi.payment_sms_frame','1',true);
 PERFORM set_config('burimunsi.native_receipt_frame','1',true);
 PERFORM set_config('burimunsi.collection_id',p_collection_id,true);
 RETURN jsonb_build_object('contract_version',1,'eligible_count',
  (SELECT count(*) FROM private._burimunsi_payment_sms_sources(p_collection_id,p_enabled_at,at) src
   WHERE NOT EXISTS(SELECT 1 FROM private.burimunsi_payment_sms_deliveries d WHERE d.payment_id=src.payment_id)),
  'unresolved_count',(SELECT count(*) FROM private.burimunsi_payment_sms_deliveries d
   WHERE d.collection_id=p_collection_id AND d.application_id=p_application_id AND (d.state IN ('sending','unknown')
    OR d.state='accepted' AND d.provider_state IN ('accepted','assigned','phone_accepted','queued','handoff_started','sent','partial','outcome_unknown'))));
END;$fn$;

REVOKE ALL ON FUNCTION private._burimunsi_payment_sms_immutable(),private._burimunsi_payment_sms_phone(text),
 private._burimunsi_payment_sms_sources(text,timestamptz,timestamptz,text),
 private._burimunsi_payment_sms_claim_json(private.burimunsi_payment_sms_deliveries,text),
 private.burimunsi_claim_payment_sms(text,timestamptz,text,integer),
 private.burimunsi_prepare_payment_sms(text,uuid,uuid,text),
 private.burimunsi_finish_payment_sms(text,uuid,uuid,text,text,text),
 private.burimunsi_payment_sms_readiness(text,timestamptz,text)
 FROM PUBLIC,anon,authenticated,service_role,collect_importer,collect_runtime;
GRANT EXECUTE ON FUNCTION private.burimunsi_claim_payment_sms(text,timestamptz,text,integer),
 private.burimunsi_prepare_payment_sms(text,uuid,uuid,text),
 private.burimunsi_finish_payment_sms(text,uuid,uuid,text,text,text),
 private.burimunsi_payment_sms_readiness(text,timestamptz,text) TO collect_runtime;

-- Register retained dispatch identity, hashes and unknown outcomes for the
-- existing inspection inventory. Delivery evidence has no erasure authority.
DO $retention$
DECLARE body text;next_body text;entry jsonb;anchor text;
BEGIN
 entry:=jsonb_build_object('name','private:burimunsi_payment_sms_deliveries',
  'relation','private.burimunsi_payment_sms_deliveries','scope','unmapped_private',
  'purpose','Retained payment SMS dispatch identity and uncertain gateway outcomes',
  'known_links','recipient_user_id, collection_id and payment_id identify authorized receipt scope','blocked',true);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure
  AND pg_get_userbyid(proowner)='postgres' AND NOT prosecdef AND provolatile='i'
  AND proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND proacl::text='{postgres=X/postgres}';
 -- A source check avoids evaluating the layered catalog during DDL.
 IF strpos(body,'private:burimunsi_payment_sms_deliveries')>0 THEN
  RAISE EXCEPTION 'payment_sms_retention_changed' USING ERRCODE='55000';END IF;
 next_body:=format('WITH prior(base) AS MATERIALIZED (%s) SELECT jsonb_set(base,''{private_classes}'',(base->''private_classes'')||%L::jsonb) FROM prior',body,jsonb_build_array(entry)::text);
 EXECUTE 'CREATE OR REPLACE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
 SELECT prosrc INTO STRICT body FROM pg_proc WHERE oid='private.retention_capture_inventory_v2(uuid,text,bigint,text,integer)'::regprocedure
  AND pg_get_userbyid(proowner)='postgres' AND prosecdef AND provolatile='v'
  AND proconfig=ARRAY['search_path=pg_catalog, pg_temp'] AND proacl::text='{postgres=X/postgres,collect_runtime=X/postgres}';
 anchor:=$anchor$'private:burimunsi_observation_retry_commands','managed:storage_iceberg'$anchor$;
 IF length(body)-length(replace(body,anchor,''))<>length(anchor) THEN
  RAISE EXCEPTION 'payment_sms_retention_anchor_changed' USING ERRCODE='55000';END IF;
 next_body:=replace(body,anchor,'''private:burimunsi_payment_sms_deliveries'','||anchor);
 EXECUTE 'CREATE OR REPLACE FUNCTION private.retention_capture_inventory_v2(p_operation uuid,p_request text,p_review bigint,p_source text,p_max_rows integer DEFAULT 1000000) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS '||quote_literal(next_body);
END;$retention$;
COMMIT;
