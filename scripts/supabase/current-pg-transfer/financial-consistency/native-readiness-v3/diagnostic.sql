-- Check the session before BEGIN; acquire relation locks before the first
-- repeatable-read snapshot so committed DDL cannot be hidden by an old snapshot.
DO $session$ BEGIN
 IF pg_catalog.current_setting('server_version_num')::integer/10000<>17 OR pg_catalog.current_database()<>'postgres'
  OR pg_catalog.inet_server_addr() IS NOT NULL THEN
  RAISE EXCEPTION 'native_source_session_refused' USING ERRCODE='55000';
 END IF;
 PERFORM pg_catalog.set_config('collect.native_diagnostic_backend',pg_catalog.pg_backend_pid()::text,false);
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
  current_setting('collect.native_diagnostic_backend',true) IS DISTINCT FROM pg_backend_pid()::text OR
  current_setting('server_version_num')::integer/10000<>17 OR current_database()<>'postgres' OR inet_server_addr() IS NOT NULL THEN
  RAISE EXCEPTION 'native_source_session_refused' USING ERRCODE='55000';END IF;
 WITH names(name) AS (VALUES ('app.sms_receipts'),('app.momo_transaction_sources'),('app.momo_transactions'),
  ('app.momo_parse_attempts'),('app.momo_financial_links'),('private.burimunsi_native_receipt_origins'),('private.burimunsi_auto_sms_jobs')),
 resolved AS (SELECT to_regclass(name) oid FROM names)
 SELECT EXISTS(SELECT 1 FROM resolved r LEFT JOIN pg_class c ON c.oid=r.oid WHERE r.oid IS NULL OR c.relkind<>'r'
  OR NOT coalesce(has_schema_privilege(current_user,c.relnamespace,'USAGE'),false)
  OR NOT coalesce(has_table_privilege(current_user,r.oid,'SELECT'),false) OR coalesce(row_security_active(r.oid),true)
  OR EXISTS(SELECT 1 FROM pg_inherits i WHERE i.inhrelid=r.oid OR i.inhparent=r.oid)) INTO refused;
 IF refused THEN RAISE EXCEPTION 'native_source_visibility_refused' USING ERRCODE='42501';END IF;
 WITH required(rel,cols,typ) AS (VALUES
  ('app.sms_receipts','id,body_sha256','text'),
  ('app.momo_transaction_sources','transaction_id,raw_sms_id,parse_attempt_id,relation','text'),
  ('app.momo_transactions','id,parse_attempt_id,receiving_account_id,allocation_state,event_kind,currency,mode','text'),
  ('app.momo_transactions','has_conflict,amount_minor','bigint'),
  ('app.momo_parse_attempts','id,raw_sms_id,source_body_sha256','text'),
  ('app.momo_financial_links','transaction_id,payment_id','text'),
  ('private.burimunsi_native_receipt_origins','source_id,fingerprint,body_sha256','text'),
  ('private.burimunsi_auto_sms_jobs','source_id,transaction_id,source_fingerprint,relation,state,payment_outcome,receiving_account_id','text'),
  ('private.burimunsi_auto_sms_jobs','attempt_id','uuid'),
  ('private.burimunsi_auto_sms_jobs','posting_facts','jsonb')),
 expanded AS (SELECT to_regclass(rel) oid,unnest(string_to_array(cols,',')) col,typ FROM required)
 SELECT EXISTS(SELECT 1 FROM expanded r LEFT JOIN pg_attribute a ON a.attrelid=r.oid AND a.attname=r.col
  AND a.attnum>0 AND NOT a.attisdropped WHERE a.attnum IS NULL OR a.atttypid<>to_regtype(r.typ)) INTO refused;
 IF refused THEN RAISE EXCEPTION 'native_source_columns_refused' USING ERRCODE='55000';END IF;
 IF EXISTS(SELECT 1 FROM app.sms_receipts r GROUP BY r.id HAVING r.id IS NULL OR count(*)<>1) THEN
  RAISE EXCEPTION 'native_source_receipt_identity_refused' USING ERRCODE='55000';END IF;
END;$guard$;

WITH joined AS MATERIALIZED (
 SELECT r.id,
  r.id ~ '^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$' AS source_uuid_ok,
  CASE WHEN x.transaction_id IS NOT NULL THEN x.transaction_id=r.id END AS source_id_ok,
  CASE WHEN j.transaction_id IS NOT NULL AND t.id IS NOT NULL THEN j.transaction_id=t.id END AS job_transaction_ok,
  CASE WHEN o.fingerprint IS NOT NULL AND j.source_fingerprint IS NOT NULL THEN
   o.fingerprint ~ '^[0-9a-f]{64}$' AND j.source_fingerprint ~ '^[0-9a-f]{64}$' AND o.fingerprint=j.source_fingerprint END AS fingerprint_ok,
  CASE WHEN t.has_conflict IS NOT NULL THEN t.has_conflict=0 END AS conflict_ok,
  CASE WHEN t.allocation_state IS NOT NULL THEN t.allocation_state='linked' END AS allocation_ok,
  CASE WHEN x.relation IS NOT NULL AND j.relation IS NOT NULL THEN x.relation='accepted' AND j.relation='accepted' END AS relation_ok,
  CASE WHEN x.parse_attempt_id IS NOT NULL AND t.parse_attempt_id IS NOT NULL AND j.attempt_id IS NOT NULL AND a.id IS NOT NULL
    AND a.raw_sms_id IS NOT NULL AND a.source_body_sha256 IS NOT NULL AND r.body_sha256 IS NOT NULL AND o.body_sha256 IS NOT NULL
    AND j.receiving_account_id IS NOT NULL AND t.receiving_account_id IS NOT NULL THEN
   x.parse_attempt_id=t.parse_attempt_id AND x.parse_attempt_id=j.attempt_id::text AND a.id=x.parse_attempt_id
    AND a.raw_sms_id=r.id AND a.source_body_sha256=r.body_sha256 AND o.body_sha256=r.body_sha256
    AND j.receiving_account_id=t.receiving_account_id END AS attempt_ok,
  CASE WHEN t.id IS NOT NULL THEN EXISTS(SELECT 1 FROM app.momo_financial_links f WHERE f.transaction_id=t.id) END AS has_financial_link,
  CASE WHEN t.event_kind IS NULL OR t.currency IS NULL OR t.mode IS NULL OR t.amount_minor IS NULL OR j.state IS NULL OR j.payment_outcome IS NULL
    OR jsonb_typeof(j.posting_facts) IS DISTINCT FROM 'object' OR NOT (j.posting_facts ?& ARRAY['event_kind','payment_outcome','currency','amount_minor','source_mode'])
    OR j.posting_facts->'event_kind'='null'::jsonb OR j.posting_facts->'payment_outcome'='null'::jsonb OR j.posting_facts->'currency'='null'::jsonb
    OR j.posting_facts->'amount_minor'='null'::jsonb OR j.posting_facts->'source_mode'='null'::jsonb THEN NULL
   ELSE t.event_kind='incoming_receipt' AND t.currency='RWF' AND t.mode IN('live','historical') AND t.amount_minor>0
    AND j.state='completed' AND j.payment_outcome='successful'
    AND j.posting_facts->>'event_kind'=t.event_kind AND j.posting_facts->>'payment_outcome'=j.payment_outcome
    AND j.posting_facts->>'currency'=t.currency AND jsonb_typeof(j.posting_facts->'amount_minor')='number'
    AND j.posting_facts->'amount_minor'=to_jsonb(t.amount_minor)
    AND j.posting_facts->>'source_mode'=(CASE WHEN t.mode='live' THEN 'live' ELSE 'catch_up' END) END AS facts_ok,
  CASE WHEN jsonb_typeof(j.posting_facts) IS DISTINCT FROM 'object' OR NOT(j.posting_facts ? 'wallet_balance_after_minor')
    OR j.posting_facts->'wallet_balance_after_minor'='null'::jsonb THEN NULL
   WHEN jsonb_typeof(j.posting_facts->'wallet_balance_after_minor') IS DISTINCT FROM 'number' THEN false
   WHEN j.posting_facts->>'wallet_balance_after_minor' ~ '^(0|[1-9][0-9]{0,15})$'
    THEN (j.posting_facts->>'wallet_balance_after_minor')::numeric<=9007199254740991
   ELSE false END AS wallet_ok
 FROM app.sms_receipts r LEFT JOIN app.momo_transaction_sources x ON x.raw_sms_id=r.id
 LEFT JOIN app.momo_transactions t ON t.id=x.transaction_id
 LEFT JOIN app.momo_parse_attempts a ON a.id=x.parse_attempt_id
 LEFT JOIN private.burimunsi_native_receipt_origins o ON o.source_id=r.id
 LEFT JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=r.id
), grouped AS MATERIALIZED (
 SELECT id,count(*) AS paths,
  CASE WHEN count(*)=1 THEN bool_and(source_uuid_ok) END AS source_uuid_ok,
  CASE WHEN count(*)=1 THEN bool_and(source_id_ok) END AS source_id_ok,
  CASE WHEN count(*)=1 THEN bool_and(job_transaction_ok) END AS job_transaction_ok,
  CASE WHEN count(*)=1 THEN bool_and(fingerprint_ok) END AS fingerprint_ok,
  CASE WHEN count(*)=1 THEN bool_and(conflict_ok) END AS conflict_ok,
  CASE WHEN count(*)=1 THEN bool_and(allocation_ok) END AS allocation_ok,
  CASE WHEN count(*)=1 THEN bool_and(relation_ok) END AS relation_ok,
  CASE WHEN count(*)=1 THEN bool_and(attempt_ok) END AS attempt_ok,
  CASE WHEN count(*)=1 THEN bool_and(has_financial_link) END AS has_financial_link,
  CASE WHEN count(*)=1 THEN bool_and(facts_ok) END AS facts_ok,
  CASE WHEN count(*)=1 THEN bool_and(wallet_ok) END AS wallet_ok
 FROM joined GROUP BY id
), selected AS MATERIALIZED (
 SELECT *,source_uuid_ok AND source_id_ok AND job_transaction_ok AND fingerprint_ok AND conflict_ok AND allocation_ok AND
  relation_ok AND attempt_ok AND facts_ok AND wallet_ok AS selected_fields_ok FROM grouped
)
SELECT jsonb_build_object(
 'format','collect.native-sms-source-selected-fields.v3',
 'observed_at_utc',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
 'server_major',current_setting('server_version_num')::integer/10000,
 'scope',jsonb_build_object(
  'sms_receipts',(SELECT count(*) FROM selected),'momo_transactions',(SELECT count(*) FROM app.momo_transactions),
  'native_origins',(SELECT count(*) FROM private.burimunsi_native_receipt_origins),
  'native_jobs',(SELECT count(*) FROM private.burimunsi_auto_sms_jobs),
  'within_synthetic_receipt_limit',(SELECT count(*) BETWEEN 1 AND 64 FROM selected),
  'receipts_with_multiple_joined_paths',(SELECT count(*) FROM selected WHERE paths>1),
  'receipts_with_financial_link',(SELECT count(*) FROM selected WHERE has_financial_link IS TRUE),
  'receipts_without_financial_link',(SELECT count(*) FROM selected WHERE has_financial_link IS FALSE),
  'receipts_financial_link_unknown',(SELECT count(*) FROM selected WHERE has_financial_link IS NULL),
  'transactions_without_receipt_source',(SELECT count(*) FROM app.momo_transactions t WHERE NOT EXISTS
   (SELECT 1 FROM app.momo_transaction_sources x JOIN app.sms_receipts r ON r.id=x.raw_sms_id WHERE x.transaction_id=t.id)),
  'origins_without_receipt',(SELECT count(*) FROM private.burimunsi_native_receipt_origins o WHERE NOT EXISTS(SELECT 1 FROM app.sms_receipts r WHERE r.id=o.source_id)),
  'jobs_without_receipt',(SELECT count(*) FROM private.burimunsi_auto_sms_jobs j WHERE NOT EXISTS(SELECT 1 FROM app.sms_receipts r WHERE r.id=j.source_id))),
 'selected_fields',jsonb_build_object(
  'source_uuid_format_unsupported',(SELECT count(*) FROM selected WHERE source_uuid_ok IS FALSE),
  'source_uuid_format_unknown',(SELECT count(*) FROM selected WHERE source_uuid_ok IS NULL),
  'transaction_source_id_equal',(SELECT count(*) FROM selected WHERE source_id_ok IS TRUE),
  'transaction_source_id_mismatch',(SELECT count(*) FROM selected WHERE source_id_ok IS FALSE),
  'transaction_source_id_unknown',(SELECT count(*) FROM selected WHERE source_id_ok IS NULL),
  'job_transaction_mismatch',(SELECT count(*) FROM selected WHERE job_transaction_ok IS FALSE),
  'job_transaction_unknown',(SELECT count(*) FROM selected WHERE job_transaction_ok IS NULL),
  'job_origin_fingerprint_equal',(SELECT count(*) FROM selected WHERE fingerprint_ok IS TRUE),
  'job_origin_fingerprint_mismatch',(SELECT count(*) FROM selected WHERE fingerprint_ok IS FALSE),
  'job_origin_fingerprint_unknown',(SELECT count(*) FROM selected WHERE fingerprint_ok IS NULL),
  'has_conflict_nonzero',(SELECT count(*) FROM selected WHERE conflict_ok IS FALSE),
  'has_conflict_unknown',(SELECT count(*) FROM selected WHERE conflict_ok IS NULL),
  'allocation_not_linked',(SELECT count(*) FROM selected WHERE allocation_ok IS FALSE),
  'allocation_unknown',(SELECT count(*) FROM selected WHERE allocation_ok IS NULL),
  'source_job_relation_not_accepted',(SELECT count(*) FROM selected WHERE relation_ok IS FALSE),
  'source_job_relation_unknown',(SELECT count(*) FROM selected WHERE relation_ok IS NULL),
  'attempt_or_receipt_link_mismatch',(SELECT count(*) FROM selected WHERE attempt_ok IS FALSE),
  'attempt_or_receipt_link_unknown',(SELECT count(*) FROM selected WHERE attempt_ok IS NULL),
  'selected_job_facts_mismatch',(SELECT count(*) FROM selected WHERE facts_ok IS FALSE),
  'selected_job_facts_unknown',(SELECT count(*) FROM selected WHERE facts_ok IS NULL),
  'wallet_supported',(SELECT count(*) FROM selected WHERE wallet_ok IS TRUE),
  'wallet_unsupported',(SELECT count(*) FROM selected WHERE wallet_ok IS FALSE),
  'wallet_unknown',(SELECT count(*) FROM selected WHERE wallet_ok IS NULL),
  'all_selected_fields_satisfy',(SELECT count(*) FROM selected WHERE selected_fields_ok IS TRUE),
  'one_or_more_selected_fields_fail',(SELECT count(*) FROM selected WHERE selected_fields_ok IS FALSE),
  'selected_fields_unknown',(SELECT count(*) FROM selected WHERE selected_fields_ok IS NULL),
  'linked_receipts_all_selected_fields_satisfy',(SELECT count(*) FROM selected WHERE has_financial_link IS TRUE AND selected_fields_ok IS TRUE),
  'linked_receipts_selected_fields_fail',(SELECT count(*) FROM selected WHERE has_financial_link IS TRUE AND selected_fields_ok IS FALSE),
  'linked_receipts_selected_fields_unknown',(SELECT count(*) FROM selected WHERE has_financial_link IS TRUE AND selected_fields_ok IS NULL)),
 'visibility',jsonb_build_object('active_rls_filtering',false,'full_table_select_checked',true,'inherited_tables_refused',true,'required_columns_checked',true),
 'importer_qualified',false,'source_frozen',false,'complete_graph_verified',false,'provider_or_object_verified',false,'write_authorized',false
) AS observation;
ROLLBACK;
