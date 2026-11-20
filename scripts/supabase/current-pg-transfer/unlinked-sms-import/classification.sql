-- Count-only local-source classification. The precheck is deliberately before
-- BEGIN; the physical backend must remain the same through the transaction.
DO $session$ BEGIN
 IF pg_catalog.current_setting('server_version_num')::integer/10000<>17 OR pg_catalog.current_database()<>'postgres'
  OR pg_catalog.inet_server_addr() IS NOT NULL THEN RAISE EXCEPTION 'unlinked_source_session_refused' USING ERRCODE='55000';END IF;
 PERFORM pg_catalog.set_config('collect.unlinked_diagnostic_backend',pg_catalog.pg_backend_pid()::text,false);
END;$session$;
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL statement_timeout='15s';
LOCK TABLE app.sms_receipts,app.momo_transaction_sources,app.momo_transactions,app.momo_parse_attempts,
 app.momo_financial_links,private.burimunsi_native_receipt_origins,private.burimunsi_auto_sms_jobs IN ACCESS SHARE MODE;
DO $guard$
DECLARE refused boolean;
BEGIN
 IF current_setting('transaction_read_only')<>'on' OR current_setting('transaction_isolation')<>'repeatable read' OR
  current_setting('collect.unlinked_diagnostic_backend',true) IS DISTINCT FROM pg_backend_pid()::text OR
  current_setting('server_version_num')::integer/10000<>17 OR current_database()<>'postgres' OR inet_server_addr() IS NOT NULL THEN
  RAISE EXCEPTION 'unlinked_source_session_refused' USING ERRCODE='55000';END IF;
 WITH names(name) AS (VALUES ('app.sms_receipts'),('app.momo_transaction_sources'),('app.momo_transactions'),
  ('app.momo_parse_attempts'),('app.momo_financial_links'),('private.burimunsi_native_receipt_origins'),('private.burimunsi_auto_sms_jobs')),
 resolved AS (SELECT to_regclass(name) oid FROM names)
 SELECT EXISTS(SELECT 1 FROM resolved r LEFT JOIN pg_class c ON c.oid=r.oid WHERE r.oid IS NULL OR c.relkind<>'r'
  OR NOT coalesce(has_schema_privilege(current_user,c.relnamespace,'USAGE'),false)
  OR NOT coalesce(has_table_privilege(current_user,r.oid,'SELECT'),false) OR coalesce(row_security_active(r.oid),true)
  OR EXISTS(SELECT 1 FROM pg_inherits i WHERE i.inhrelid=r.oid OR i.inhparent=r.oid)) INTO refused;
 IF refused THEN RAISE EXCEPTION 'unlinked_source_visibility_refused' USING ERRCODE='42501';END IF;
 WITH required(rel,cols,typ) AS (VALUES
  ('app.sms_receipts','id,body_sha256','text'),
  ('app.momo_transaction_sources','transaction_id,raw_sms_id,parse_attempt_id,relation','text'),
  ('app.momo_transactions','id,parse_attempt_id,receiving_account_id,allocation_state,event_kind,currency,provider_transaction_id','text'),
  ('app.momo_transactions','has_conflict,amount_minor,currency_scale,wallet_balance_after_minor','bigint'),
  ('app.momo_parse_attempts','id,raw_sms_id,source_body_sha256','text'),
  ('app.momo_financial_links','transaction_id','text'),
  ('private.burimunsi_native_receipt_origins','source_id,fingerprint,body_sha256','text'),
  ('private.burimunsi_auto_sms_jobs','source_id,transaction_id,source_fingerprint,relation,state,phase,payment_outcome,receiving_account_id','text'),
  ('private.burimunsi_auto_sms_jobs','attempt_id','uuid'),('private.burimunsi_auto_sms_jobs','posting_facts','jsonb')),
 expanded AS (SELECT to_regclass(rel) oid,unnest(string_to_array(cols,',')) col,typ FROM required)
 SELECT EXISTS(SELECT 1 FROM expanded r LEFT JOIN pg_attribute a ON a.attrelid=r.oid AND a.attname=r.col
  AND a.attnum>0 AND NOT a.attisdropped WHERE a.attnum IS NULL OR a.atttypid<>to_regtype(r.typ)) INTO refused;
 IF refused THEN RAISE EXCEPTION 'unlinked_source_columns_refused' USING ERRCODE='55000';END IF;
 IF EXISTS(SELECT 1 FROM app.sms_receipts r GROUP BY r.id HAVING r.id IS NULL OR count(*)<>1) THEN
  RAISE EXCEPTION 'unlinked_source_receipt_identity_refused' USING ERRCODE='55000';END IF;
END;$guard$;

WITH joined AS MATERIALIZED (
 SELECT r.id,t.id transaction_id,t.allocation_state,t.event_kind,t.provider_transaction_id,t.amount_minor,t.currency,t.currency_scale,
 t.wallet_balance_after_minor,t.has_conflict,j.source_id IS NOT NULL AS job_present,j.state,j.phase,j.payment_outcome,j.posting_facts,
 CASE WHEN t.id IS NOT NULL THEN EXISTS(SELECT 1 FROM app.momo_financial_links f WHERE f.transaction_id=t.id) END AS linked,
 CASE WHEN x.relation IS NOT NULL AND j.relation IS NOT NULL THEN x.relation='accepted' AND j.relation='accepted' END AS relation_ok,
 CASE WHEN t.id IS NOT NULL AND j.transaction_id IS NOT NULL AND x.parse_attempt_id IS NOT NULL AND t.parse_attempt_id IS NOT NULL
  AND j.attempt_id IS NOT NULL AND a.id IS NOT NULL AND a.raw_sms_id IS NOT NULL AND a.source_body_sha256 IS NOT NULL
  AND r.body_sha256 IS NOT NULL AND o.body_sha256 IS NOT NULL AND j.receiving_account_id IS NOT NULL AND t.receiving_account_id IS NOT NULL
  THEN t.id=r.id AND j.transaction_id=t.id AND x.parse_attempt_id=t.parse_attempt_id AND x.parse_attempt_id=j.attempt_id::text
   AND a.id=x.parse_attempt_id AND a.raw_sms_id=r.id AND a.source_body_sha256=r.body_sha256 AND o.body_sha256=r.body_sha256
   AND j.receiving_account_id=t.receiving_account_id END AS graph_ok,
 CASE WHEN o.fingerprint IS NOT NULL AND j.source_fingerprint IS NOT NULL THEN o.fingerprint=j.source_fingerprint END AS fingerprint_ok
 FROM app.sms_receipts r LEFT JOIN app.momo_transaction_sources x ON x.raw_sms_id=r.id
 LEFT JOIN app.momo_transactions t ON t.id=x.transaction_id LEFT JOIN app.momo_parse_attempts a ON a.id=x.parse_attempt_id
 LEFT JOIN private.burimunsi_native_receipt_origins o ON o.source_id=r.id LEFT JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=r.id
), grouped AS MATERIALIZED (
 SELECT id,count(*) paths,
  CASE WHEN count(*)=1 THEN bool_and(linked) END linked,
  CASE WHEN count(*)=1 THEN bool_and(relation_ok) END relation_ok,
  CASE WHEN count(*)=1 THEN bool_and(graph_ok) END graph_ok,
  CASE WHEN count(*)=1 THEN bool_and(fingerprint_ok) END fingerprint_ok,
  CASE WHEN count(*)=1 THEN max(allocation_state) END allocation_state,
  CASE WHEN count(*)=1 THEN max(event_kind) END event_kind,
  CASE WHEN count(*)=1 THEN max(state) END state,
  CASE WHEN count(*)=1 THEN max(phase) END phase,
  CASE WHEN count(*)=1 THEN max(payment_outcome) END payment_outcome,
  CASE WHEN count(*)=1 THEN bool_and(job_present) END job_present,
  CASE WHEN count(*)=1 THEN bool_and(has_conflict IS DISTINCT FROM 0) END conflict_nonzero_or_unknown,
  CASE WHEN count(*)=1 THEN bool_and(provider_transaction_id IS NULL) END provider_reference_null,
  CASE WHEN count(*)=1 THEN bool_and(amount_minor IS NULL) END amount_null,
  CASE WHEN count(*)=1 THEN bool_and(currency IS NULL) END currency_null,
  CASE WHEN count(*)=1 THEN bool_and(currency_scale IS NULL) END currency_scale_null,
  CASE WHEN count(*)=1 THEN bool_and(wallet_balance_after_minor IS NULL) END transaction_wallet_null,
  CASE WHEN count(*)=1 THEN bool_and(job_present AND posting_facts IS NULL) END facts_sql_null,
  CASE WHEN count(*)=1 THEN bool_and(posting_facts='null'::jsonb) END facts_json_null,
  CASE WHEN count(*)=1 THEN bool_and(jsonb_typeof(posting_facts)='object') END facts_object,
  CASE WHEN count(*)=1 THEN bool_and(job_present AND (posting_facts IS NULL OR jsonb_typeof(posting_facts) IS DISTINCT FROM 'object'
   OR NOT(posting_facts ?& ARRAY['event_kind','payment_outcome','currency','amount_minor','source_mode'])
   OR posting_facts->'event_kind'='null'::jsonb OR posting_facts->'payment_outcome'='null'::jsonb
   OR posting_facts->'currency'='null'::jsonb OR posting_facts->'amount_minor'='null'::jsonb OR posting_facts->'source_mode'='null'::jsonb)) END facts_incomplete,
  CASE WHEN count(*)=1 THEN bool_and(jsonb_typeof(posting_facts)='object' AND NOT(posting_facts ? 'wallet_balance_after_minor')) END wallet_key_missing,
  CASE WHEN count(*)=1 THEN bool_and(posting_facts->'wallet_balance_after_minor'='null'::jsonb) END wallet_json_null
 FROM joined GROUP BY id
), selected AS MATERIALIZED (SELECT * FROM grouped WHERE linked IS FALSE)
SELECT jsonb_build_object('format','collect.native-unlinked-classification.v1',
 'observed_at_utc',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
 'scope',jsonb_build_object('receipts',(SELECT count(*) FROM grouped),'linked',(SELECT count(*) FROM grouped WHERE linked IS TRUE),
  'unlinked',(SELECT count(*) FROM selected),'link_unknown',(SELECT count(*) FROM grouped WHERE linked IS NULL),
  'multiple_paths',(SELECT count(*) FROM grouped WHERE paths<>1)),
 'unlinked',jsonb_build_object(
  'allocation_unallocated',(SELECT count(*) FROM selected WHERE allocation_state='unallocated'),
  'allocation_needs_review',(SELECT count(*) FROM selected WHERE allocation_state='needs_review'),
  'allocation_not_applicable',(SELECT count(*) FROM selected WHERE allocation_state='not_applicable'),
  'allocation_other_or_null',(SELECT count(*) FROM selected WHERE allocation_state IS NULL OR allocation_state NOT IN('unallocated','needs_review','not_applicable')),
  'state_completed',(SELECT count(*) FROM selected WHERE state='completed'),
  'state_other_or_null',(SELECT count(*) FROM selected WHERE state IS DISTINCT FROM 'completed'),
  'phase_finished',(SELECT count(*) FROM selected WHERE phase='finished'),
  'phase_other_or_null',(SELECT count(*) FROM selected WHERE phase IS DISTINCT FROM 'finished'),
  'event_incoming',(SELECT count(*) FROM selected WHERE event_kind='incoming_receipt'),
  'event_outgoing',(SELECT count(*) FROM selected WHERE event_kind='outgoing'),
  'event_reversal',(SELECT count(*) FROM selected WHERE event_kind='reversal'),
  'event_failed_pending_other_unknown',(SELECT count(*) FROM selected WHERE event_kind IN('failed','pending','other','unknown') OR event_kind IS NULL),
  'outcome_successful',(SELECT count(*) FROM selected WHERE payment_outcome='successful'),
  'outcome_not_successful_or_null',(SELECT count(*) FROM selected WHERE payment_outcome IS DISTINCT FROM 'successful'),
  'relation_not_accepted_or_unknown',(SELECT count(*) FROM selected WHERE relation_ok IS DISTINCT FROM true),
  'graph_mismatch_or_unknown',(SELECT count(*) FROM selected WHERE graph_ok IS DISTINCT FROM true),
  'fingerprint_mismatch_or_unknown',(SELECT count(*) FROM selected WHERE fingerprint_ok IS DISTINCT FROM true),
  'job_missing',(SELECT count(*) FROM selected WHERE job_present IS FALSE),
  'conflict_nonzero_or_unknown',(SELECT count(*) FROM selected WHERE conflict_nonzero_or_unknown IS TRUE),
  'provider_reference_null',(SELECT count(*) FROM selected WHERE provider_reference_null IS TRUE),
  'amount_null',(SELECT count(*) FROM selected WHERE amount_null IS TRUE),
  'currency_null',(SELECT count(*) FROM selected WHERE currency_null IS TRUE),
  'currency_scale_null',(SELECT count(*) FROM selected WHERE currency_scale_null IS TRUE),
  'transaction_wallet_null',(SELECT count(*) FROM selected WHERE transaction_wallet_null IS TRUE),
  'posting_facts_sql_null',(SELECT count(*) FROM selected WHERE facts_sql_null IS TRUE),
  'posting_facts_json_null',(SELECT count(*) FROM selected WHERE facts_json_null IS TRUE),
  'posting_facts_object',(SELECT count(*) FROM selected WHERE facts_object IS TRUE),
  'posting_facts_incomplete',(SELECT count(*) FROM selected WHERE facts_incomplete IS TRUE),
  'wallet_key_missing',(SELECT count(*) FROM selected WHERE wallet_key_missing IS TRUE),
  'wallet_json_null',(SELECT count(*) FROM selected WHERE wallet_json_null IS TRUE)),
 'visibility',jsonb_build_object('active_rls_filtering',false,'full_table_select_checked',true,'inherited_tables_refused',true,'required_columns_checked',true),
 'source_frozen',false,'complete_graph_verified',false,'provider_or_object_verified',false,'write_authorized',false) AS observation;
ROLLBACK;
