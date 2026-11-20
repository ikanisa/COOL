-- Session identity is checked before BEGIN so a repeatable-read snapshot is not
-- acquired before the required relation locks have been obtained.
DO $session$
BEGIN
 IF pg_catalog.current_setting('server_version_num')::integer/10000<>17 OR
    pg_catalog.current_database()<>'postgres' OR pg_catalog.inet_server_addr() IS NOT NULL THEN
  RAISE EXCEPTION 'financial_consistency_transaction_refused' USING ERRCODE='55000';
 END IF;
 PERFORM pg_catalog.set_config('collect.financial_diagnostic_backend',pg_catalog.pg_backend_pid()::text,false);
END;$session$;
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL timezone='UTC';
SET LOCAL statement_timeout='15s';
-- Hold table shape stable during the visibility check and subsequent reads.
LOCK TABLE app.ledger_entries,app.contribution_posting_snapshots,app.payments,
 app.payment_evidence,app.momo_financial_links,app.momo_transactions,
 app.momo_transaction_sources,app.momo_parse_attempts,app.sms_receipts,private.burimunsi_auto_sms_jobs IN ACCESS SHARE MODE;

DO $guard$
DECLARE refused boolean;
BEGIN
 IF current_setting('transaction_read_only')<>'on' OR current_setting('transaction_isolation')<>'repeatable read' OR
  current_setting('collect.financial_diagnostic_backend',true) IS DISTINCT FROM pg_backend_pid()::text OR
  current_setting('server_version_num')::integer/10000<>17 OR current_database()<>'postgres' OR inet_server_addr() IS NOT NULL THEN
  RAISE EXCEPTION 'financial_consistency_transaction_refused' USING ERRCODE='55000';
 END IF;
 WITH required(name) AS (VALUES
  ('app.ledger_entries'),('app.contribution_posting_snapshots'),('app.payments'),
  ('app.payment_evidence'),('app.momo_financial_links'),('app.momo_transactions'),
  ('app.momo_transaction_sources'),('app.momo_parse_attempts'),('app.sms_receipts'),('private.burimunsi_auto_sms_jobs')),
 resolved AS (SELECT name,to_regclass(name) AS oid FROM required)
 SELECT EXISTS(SELECT 1 FROM resolved r LEFT JOIN pg_class c ON c.oid=r.oid
  WHERE r.oid IS NULL OR c.relkind<>'r'
   OR NOT coalesce(has_schema_privilege(current_user,c.relnamespace,'USAGE'),false)
   OR NOT coalesce(has_table_privilege(current_user,r.oid,'SELECT'),false)
   OR coalesce(row_security_active(r.oid),true)
   OR EXISTS(SELECT 1 FROM pg_inherits i WHERE i.inhrelid=r.oid OR i.inhparent=r.oid)) INTO refused;
 IF refused THEN RAISE EXCEPTION 'financial_consistency_visibility_refused' USING ERRCODE='42501'; END IF;

 WITH required(rel,cols,typ) AS (VALUES
  ('app.ledger_entries','id,payment_id,collection_id,member_id,currency,kind,posted_at,evidence_id','text'),
  ('app.ledger_entries','amount_minor','bigint'),
  ('app.contribution_posting_snapshots','ledger_entry_id,payment_id,posted_at','text'),
  ('app.contribution_posting_snapshots','member_balance_after_minor,group_balance_after_minor','bigint'),
  ('app.payments','id,evidence_id,collection_id,member_id,currency','text'),
  ('app.payments','amount_minor','bigint'),
  ('app.payment_evidence','id,owner_user_id,collection_id,currency,object_key,object_sha256,external_reference','text'),
  ('app.payment_evidence','amount_minor','bigint'),
  ('app.momo_financial_links','payment_id,transaction_id,beneficiary_member_id','text'),
  ('app.momo_transactions','id,currency,event_kind,parse_attempt_id,receiving_account_id','text'),
  ('app.momo_transactions','amount_minor','bigint'),
  ('app.momo_transaction_sources','transaction_id,raw_sms_id,parse_attempt_id,relation','text'),
  ('app.momo_parse_attempts','id,raw_sms_id,source_body_sha256','text'),
  ('app.sms_receipts','id,owner_user_id,body_sha256','text'),
  ('private.burimunsi_auto_sms_jobs','source_id,transaction_id,collection_id,state,payment_outcome,receiving_account_id,relation','text'),
  ('private.burimunsi_auto_sms_jobs','attempt_id','uuid')),
 expanded AS (SELECT to_regclass(rel) AS oid,unnest(string_to_array(cols,',')) AS col,typ FROM required)
 SELECT EXISTS(SELECT 1 FROM expanded r LEFT JOIN pg_attribute a ON a.attrelid=r.oid
  AND a.attname=r.col AND a.attnum>0 AND NOT a.attisdropped
  WHERE a.attnum IS NULL OR a.atttypid<>to_regtype(r.typ)) INTO refused;
 IF refused THEN RAISE EXCEPTION 'financial_consistency_columns_refused' USING ERRCODE='55000'; END IF;
 -- The payment grouping below must not collapse multiple source rows into one.
 IF EXISTS(SELECT 1 FROM app.payments p GROUP BY p.id HAVING p.id IS NULL OR count(*)<>1) THEN
  RAISE EXCEPTION 'financial_consistency_payment_identity_refused' USING ERRCODE='55000';
 END IF;
END;$guard$;

WITH ledger_base AS MATERIALIZED (
 SELECT l.*,s.n AS snapshots,s.wrong_payment,s.payment_snapshots,s.snapshot_posted,s.member_after,s.group_after,
  p.n AS payments,p.unknown AS payment_unknown,p.mismatch AS payment_mismatch,
  (SELECT count(*) FROM app.ledger_entries d WHERE d.id=l.id) AS ledger_id_count,
  CASE WHEN l.posted_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
   AND pg_input_is_valid(l.posted_at,'timestamp with time zone')
   THEN CASE WHEN to_char(l.posted_at::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')=l.posted_at
    THEN l.posted_at::timestamptz END END AS ledger_time,
  CASE WHEN s.snapshot_posted ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$'
   AND pg_input_is_valid(s.snapshot_posted,'timestamp with time zone')
   THEN CASE WHEN to_char(s.snapshot_posted::timestamptz AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')=s.snapshot_posted
    THEN s.snapshot_posted::timestamptz END END AS snapshot_time
 FROM app.ledger_entries l
 LEFT JOIN LATERAL (SELECT count(*) AS n,count(*) FILTER(WHERE z.payment_id IS DISTINCT FROM l.payment_id) AS wrong_payment,
  (SELECT count(*) FROM app.contribution_posting_snapshots q WHERE q.payment_id=l.payment_id) AS payment_snapshots,
  max(z.posted_at) AS snapshot_posted,max(z.member_balance_after_minor) AS member_after,max(z.group_balance_after_minor) AS group_after
  FROM app.contribution_posting_snapshots z WHERE z.ledger_entry_id=l.id) s ON true
 LEFT JOIN LATERAL (SELECT count(*) AS n,
  bool_or(q.collection_id IS NULL OR q.member_id IS NULL OR q.amount_minor IS NULL OR q.currency IS NULL OR q.evidence_id IS NULL) AS unknown,
  bool_or(q.collection_id IS DISTINCT FROM l.collection_id OR q.member_id IS DISTINCT FROM l.member_id OR
   q.amount_minor IS DISTINCT FROM l.amount_minor OR q.currency IS DISTINCT FROM l.currency OR q.evidence_id IS DISTINCT FROM l.evidence_id) AS mismatch
  FROM app.payments q WHERE q.id=l.payment_id) p ON true
), groups AS MATERIALIZED (
 SELECT collection_id,bool_and(coalesce(id IS NOT NULL AND ledger_id_count=1 AND payment_id IS NOT NULL AND member_id IS NOT NULL AND
  evidence_id IS NOT NULL AND kind='contribution' AND amount_minor>0 AND currency='RWF' AND
  snapshots=1 AND wrong_payment=0 AND payment_snapshots=1 AND member_after IS NOT NULL AND member_after>=0 AND
  group_after IS NOT NULL AND group_after>=0 AND payments=1 AND NOT payment_unknown AND NOT payment_mismatch AND
  ledger_time IS NOT NULL AND snapshot_time IS NOT NULL AND ledger_time<=transaction_timestamp()+interval '5 minutes' AND
  snapshot_posted=posted_at,false)) AS eligible
 FROM ledger_base WHERE collection_id IS NOT NULL GROUP BY collection_id
), ordered AS MATERIALIZED (
 SELECT l.*,
  count(*) OVER(PARTITION BY l.collection_id,l.group_after) AS same_balance,
  count(*) OVER(PARTITION BY l.collection_id,l.ledger_time) AS same_time,
  sum(l.amount_minor) OVER(PARTITION BY l.collection_id ORDER BY l.group_after ROWS UNBOUNDED PRECEDING) AS group_sum,
  sum(l.amount_minor) OVER(PARTITION BY l.collection_id,l.member_id ORDER BY l.group_after ROWS UNBOUNDED PRECEDING) AS member_sum,
  lag(l.ledger_time) OVER(PARTITION BY l.collection_id ORDER BY l.group_after) AS previous_time
 FROM ledger_base l JOIN groups g USING(collection_id) WHERE g.eligible
), group_results AS MATERIALIZED (
 SELECT collection_id,bool_or(same_balance>1 OR group_after<>group_sum) AS group_mismatch,
  bool_or(member_after<>member_sum) AS member_mismatch,
  bool_or(previous_time>ledger_time) AS chronology_contradicted,
  bool_or(same_time>1) AS has_tied_time FROM ordered GROUP BY collection_id
), joined_native AS MATERIALIZED (
 SELECT p.id AS payment_id,
  coalesce(e.external_reference LIKE 'sms:%',false) OR j.source_id IS NOT NULL AS native_marker,
  e.id IS NOT NULL AND f.transaction_id IS NOT NULL AND t.id IS NOT NULL AND x.raw_sms_id IS NOT NULL AND
   r.id IS NOT NULL AND j.source_id IS NOT NULL AND j.transaction_id IS NOT NULL AND j.collection_id IS NOT NULL AS path_present,
  e.object_sha256 IS NOT NULL AND r.body_sha256 IS NOT NULL AS digest_present,
  e.object_sha256 IS DISTINCT FROM r.body_sha256 OR e.object_sha256 !~ '^[0-9a-f]{64}$' OR r.body_sha256 !~ '^[0-9a-f]{64}$' AS digest_bad,
  e.external_reference IS NOT NULL AND r.body_sha256 IS NOT NULL AND r.id IS NOT NULL AS reference_present,
  e.external_reference IS DISTINCT FROM ('sms:'||r.body_sha256||':'||r.id) AS reference_bad,
  e.object_key IS NOT NULL AND e.id IS NOT NULL AS key_present,
  e.object_key IS DISTINCT FROM ('evidence/'||e.id) AS key_bad,
  x.relation IS NOT NULL AND j.relation IS NOT NULL AND x.parse_attempt_id IS NOT NULL AND
   t.parse_attempt_id IS NOT NULL AND j.attempt_id IS NOT NULL AND a.id IS NOT NULL AND
   a.raw_sms_id IS NOT NULL AND a.source_body_sha256 IS NOT NULL AND r.body_sha256 IS NOT NULL AND
   j.receiving_account_id IS NOT NULL AND t.receiving_account_id IS NOT NULL AS accepted_linkage_present,
  x.relation IS DISTINCT FROM 'accepted' OR j.relation IS DISTINCT FROM 'accepted' OR
   x.parse_attempt_id IS DISTINCT FROM t.parse_attempt_id OR x.parse_attempt_id IS DISTINCT FROM j.attempt_id::text OR
   a.id IS DISTINCT FROM x.parse_attempt_id OR a.raw_sms_id IS DISTINCT FROM x.raw_sms_id OR
   a.source_body_sha256 IS DISTINCT FROM r.body_sha256 OR j.receiving_account_id IS DISTINCT FROM t.receiving_account_id AS accepted_linkage_bad,
  e.owner_user_id IS NOT NULL AND r.owner_user_id IS NOT NULL AND e.collection_id IS NOT NULL AND p.collection_id IS NOT NULL AND
   e.amount_minor IS NOT NULL AND p.amount_minor IS NOT NULL AND e.currency IS NOT NULL AND p.currency IS NOT NULL AND
   t.amount_minor IS NOT NULL AND t.currency IS NOT NULL AND t.event_kind IS NOT NULL AND f.beneficiary_member_id IS NOT NULL AND
   p.member_id IS NOT NULL AND j.state IS NOT NULL AND j.payment_outcome IS NOT NULL AS fields_present,
  e.owner_user_id IS DISTINCT FROM r.owner_user_id OR e.collection_id IS DISTINCT FROM p.collection_id OR
   e.amount_minor IS DISTINCT FROM p.amount_minor OR e.currency IS DISTINCT FROM p.currency OR
   t.amount_minor IS DISTINCT FROM p.amount_minor OR t.currency IS DISTINCT FROM p.currency OR
   t.event_kind IS DISTINCT FROM 'incoming_receipt' OR p.currency IS DISTINCT FROM 'RWF' OR p.amount_minor<=0 OR
   f.beneficiary_member_id IS DISTINCT FROM p.member_id OR j.transaction_id IS DISTINCT FROM f.transaction_id OR
   j.collection_id IS DISTINCT FROM p.collection_id OR j.state IS DISTINCT FROM 'completed' OR
   j.payment_outcome IS DISTINCT FROM 'successful' AS fields_bad
 FROM app.payments p LEFT JOIN app.payment_evidence e ON e.id=p.evidence_id
 LEFT JOIN app.momo_financial_links f ON f.payment_id=p.id
 LEFT JOIN app.momo_transactions t ON t.id=f.transaction_id
 LEFT JOIN app.momo_transaction_sources x ON x.transaction_id=t.id
 LEFT JOIN app.momo_parse_attempts a ON a.id=x.parse_attempt_id
 LEFT JOIN app.sms_receipts r ON r.id=x.raw_sms_id
 LEFT JOIN private.burimunsi_auto_sms_jobs j ON j.source_id=r.id
), native AS MATERIALIZED (
 SELECT payment_id,bool_or(native_marker) AS candidate,
  count(*)=1 AND bool_and(path_present) AS path,
  bool_and(digest_present) AS digest_present,bool_or(digest_bad) AS digest_bad,
  bool_and(reference_present) AS reference_present,bool_or(reference_bad) AS reference_bad,
  bool_and(key_present) AS key_present,bool_or(key_bad) AS key_bad,
  bool_and(accepted_linkage_present) AS accepted_linkage_present,bool_or(accepted_linkage_bad) AS accepted_linkage_bad,
  bool_and(fields_present) AS fields_present,bool_or(fields_bad) AS fields_bad
 FROM joined_native GROUP BY payment_id
)
SELECT jsonb_build_object(
 'format','collect.financial-consistency.v1',
 'observed_at_utc',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
 'server_major',current_setting('server_version_num')::integer/10000,
 'visibility',jsonb_build_object('active_rls_filtering',false,'table_select_checked',true,'inherited_tables_refused',true,'required_columns_checked',true),
 'timestamps',jsonb_build_object(
  'ledger_entries',(SELECT count(*) FROM ledger_base),
  'ledger_time_unknown_or_noncanonical',(SELECT count(*) FROM ledger_base WHERE ledger_time IS NULL),
  'ledger_time_future_over_five_minutes',(SELECT count(*) FROM ledger_base WHERE ledger_time>transaction_timestamp()+interval '5 minutes'),
  'snapshot_time_unknown_or_noncanonical',(SELECT count(*) FROM ledger_base WHERE snapshots<>1 OR snapshot_time IS NULL),
  'snapshot_text_differs_from_ledger',(SELECT count(*) FROM ledger_base WHERE snapshots=1 AND posted_at IS NOT NULL AND snapshot_posted IS NOT NULL AND snapshot_posted<>posted_at),
  'snapshots_without_ledger_payment_pair',(SELECT count(*) FROM app.contribution_posting_snapshots s WHERE NOT EXISTS
   (SELECT 1 FROM app.ledger_entries l WHERE l.id=s.ledger_entry_id AND l.payment_id=s.payment_id))),
 'balances',jsonb_build_object(
  'groups_with_ledger',(SELECT count(*) FROM groups),
  'null_collection_ledger_entries',(SELECT count(*) FROM ledger_base WHERE collection_id IS NULL),
  'observed_positive_only_candidate_groups',(SELECT count(*) FROM groups WHERE eligible),
  'ineligible_or_unknown_groups',(SELECT count(*) FROM groups WHERE NOT eligible),
  'group_balance_model_contradicted_groups',(SELECT count(*) FROM group_results WHERE group_mismatch),
  'member_balance_model_contradicted_groups',(SELECT count(*) FROM group_results WHERE NOT group_mismatch AND member_mismatch),
  'member_balance_unknown_groups',(SELECT count(*) FROM groups WHERE NOT eligible)+(SELECT count(*) FROM group_results WHERE group_mismatch),
  'chronological_model_contradicted_groups',(SELECT count(*) FROM group_results WHERE NOT group_mismatch AND chronology_contradicted),
  'chronological_model_unknown_groups',(SELECT count(*) FROM groups WHERE NOT eligible)+(SELECT count(*) FROM group_results WHERE group_mismatch),
  'eligible_groups_with_tied_instants',(SELECT count(*) FROM group_results WHERE has_tied_time),
  'eligible_ledger_entries_at_tied_instants',(SELECT count(*) FROM ordered WHERE same_time>1)),
 'native_sms',jsonb_build_object(
  'payments',(SELECT count(*) FROM native),
  'native_candidate_payments',(SELECT count(*) FROM native WHERE candidate),
  'payments_without_native_marker',(SELECT count(*) FROM native WHERE NOT candidate),
  'candidate_path_unknown_or_ambiguous',(SELECT count(*) FROM native WHERE candidate AND NOT path),
  'digest_comparable',(SELECT count(*) FROM native WHERE candidate AND path AND digest_present),
  'digest_mismatch',(SELECT count(*) FROM native WHERE candidate AND path AND digest_present AND digest_bad),
  'digest_unknown',(SELECT count(*) FROM native WHERE candidate AND NOT(path AND digest_present)),
  'reference_comparable',(SELECT count(*) FROM native WHERE candidate AND path AND reference_present),
  'reference_mismatch',(SELECT count(*) FROM native WHERE candidate AND path AND reference_present AND reference_bad),
  'reference_unknown',(SELECT count(*) FROM native WHERE candidate AND NOT(path AND reference_present)),
  'evidence_key_comparable',(SELECT count(*) FROM native WHERE candidate AND path AND key_present),
  'evidence_key_mismatch',(SELECT count(*) FROM native WHERE candidate AND path AND key_present AND key_bad),
  'evidence_key_unknown',(SELECT count(*) FROM native WHERE candidate AND NOT(path AND key_present)),
  'accepted_linkage_comparable',(SELECT count(*) FROM native WHERE candidate AND path AND accepted_linkage_present),
  'accepted_linkage_mismatch',(SELECT count(*) FROM native WHERE candidate AND path AND accepted_linkage_present AND accepted_linkage_bad),
  'accepted_linkage_unknown',(SELECT count(*) FROM native WHERE candidate AND NOT(path AND accepted_linkage_present)),
  'linked_fields_comparable',(SELECT count(*) FROM native WHERE candidate AND path AND fields_present),
  'linked_fields_mismatch',(SELECT count(*) FROM native WHERE candidate AND path AND fields_present AND fields_bad),
  'linked_fields_unknown',(SELECT count(*) FROM native WHERE candidate AND NOT(path AND fields_present))),
 'complete_history_verified',false,'target_compared',false,'object_bytes_verified',false,
 'provider_or_device_verified',false,'write_authorized',false
) AS consistency;
ROLLBACK;
