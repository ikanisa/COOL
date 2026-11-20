-- Count-only, source-local inventory. This script does not migrate or repair data.
-- Every result is from one read-only PostgreSQL snapshot; a separate target or
-- object-store observation is not part of that snapshot.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path=pg_catalog,pg_temp;
SET LOCAL statement_timeout='15s';

DO $guard$
DECLARE missing_or_filtered boolean;
BEGIN
 IF current_setting('transaction_read_only')<>'on' OR
    current_setting('transaction_isolation')<>'repeatable read' OR
    current_setting('server_version_num')::integer/10000<>17 THEN
  RAISE EXCEPTION 'financial_inventory_transaction_refused' USING ERRCODE='55000';
 END IF;
 WITH required(name) AS (VALUES
  ('app.collections'),('app.memberships'),('app.users'),('auth.users'),
  ('private.auth_principal_links'),('app.sms_receipts'),('app.momo_transactions'),
  ('app.momo_transaction_sources'),('app.momo_parse_attempts'),
  ('private.burimunsi_native_receipt_origins'),('app.payment_evidence'),
  ('app.payment_intents'),('app.payments'),('app.momo_financial_links'),
  ('app.ledger_entries'),('app.contribution_posting_snapshots'),
  ('private.storage_objects'),('private.storage_payload_reservations'),
  ('private.storage_namespace'),('storage.objects'),
  ('private.collect_fence_control'),('private.collect_fence_admissions')),
 resolved AS (SELECT name,to_regclass(name) AS oid FROM required)
 SELECT EXISTS(SELECT 1 FROM resolved r LEFT JOIN pg_class c ON c.oid=r.oid
  WHERE r.oid IS NULL OR c.relkind<>'r'
   OR NOT coalesce(has_table_privilege(current_user,r.oid,'SELECT'),false)
   OR coalesce(row_security_active(r.oid),true)
   OR EXISTS(SELECT 1 FROM pg_inherits i WHERE i.inhrelid=r.oid OR i.inhparent=r.oid))
 INTO missing_or_filtered;
 IF missing_or_filtered THEN
  RAISE EXCEPTION 'financial_inventory_visibility_refused' USING ERRCODE='42501';
 END IF;
END;$guard$;

WITH p AS (
 SELECT p.*,e.id AS found_evidence,e.owner_user_id AS evidence_owner,
  e.object_key AS evidence_key,e.object_sha256 AS evidence_plaintext_sha,
  e.collection_id AS evidence_collection,e.amount_minor AS evidence_amount,e.currency AS evidence_currency,
  (SELECT count(*) FROM app.momo_financial_links f WHERE f.payment_id=p.id) AS link_count,
  (SELECT count(*) FROM app.ledger_entries l WHERE l.payment_id=p.id AND l.kind='contribution') AS contribution_count
 FROM app.payments p LEFT JOIN app.payment_evidence e ON e.id=p.evidence_id
), payment_graph AS (
 SELECT jsonb_build_object(
  'payments',count(*),
  'missing_evidence',count(*) FILTER(WHERE found_evidence IS NULL),
  'evidence_field_mismatches',count(*) FILTER(WHERE found_evidence IS NOT NULL AND
   (evidence_collection IS DISTINCT FROM collection_id OR evidence_amount IS DISTINCT FROM amount_minor OR evidence_currency IS DISTINCT FROM currency)),
  'intent_not_used',count(*) FILTER(WHERE intent_id IS NULL),
  'missing_nonnull_intent',count(*) FILTER(WHERE intent_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM app.payment_intents i WHERE i.id=p.intent_id)),
  'missing_financial_link',count(*) FILTER(WHERE link_count=0),
  'multiple_financial_links',count(*) FILTER(WHERE link_count>1),
  'link_beneficiary_mismatches',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM app.momo_financial_links f WHERE f.payment_id=p.id AND f.beneficiary_member_id IS DISTINCT FROM p.member_id)),
  'missing_linked_transaction',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM app.momo_financial_links f WHERE f.payment_id=p.id AND NOT EXISTS(SELECT 1 FROM app.momo_transactions t WHERE t.id=f.transaction_id))),
  'transaction_amount_or_currency_mismatches',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM app.momo_financial_links f JOIN app.momo_transactions t ON t.id=f.transaction_id WHERE f.payment_id=p.id AND (t.amount_minor IS DISTINCT FROM p.amount_minor OR t.currency IS DISTINCT FROM p.currency))),
  'missing_contribution',count(*) FILTER(WHERE contribution_count=0),
  'multiple_contributions',count(*) FILTER(WHERE contribution_count>1),
  'contribution_field_mismatches',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM app.ledger_entries l WHERE l.payment_id=p.id AND l.kind='contribution' AND
   (l.collection_id IS DISTINCT FROM p.collection_id OR l.member_id IS DISTINCT FROM p.member_id OR l.currency IS DISTINCT FROM p.currency OR l.evidence_id IS DISTINCT FROM p.evidence_id OR l.amount_minor IS DISTINCT FROM p.amount_minor))),
  'missing_contribution_snapshot',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM app.ledger_entries l WHERE l.payment_id=p.id AND l.kind='contribution' AND NOT EXISTS(SELECT 1 FROM app.contribution_posting_snapshots s WHERE s.ledger_entry_id=l.id AND s.payment_id=p.id))),
  'missing_evidence_journal',count(*) FILTER(WHERE found_evidence IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private.storage_objects o WHERE o.object_key=p.evidence_key)),
  'evidence_journal_plaintext_digest_mismatches',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM private.storage_objects o WHERE o.object_key=p.evidence_key AND (o.custom_metadata->>'sha256') IS DISTINCT FROM p.evidence_plaintext_sha)),
  'evidence_journal_scope_mismatches',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM private.storage_objects o WHERE o.object_key=p.evidence_key AND ((o.scope->>'ownerId') IS DISTINCT FROM p.evidence_owner OR (o.scope->>'entityId') IS DISTINCT FROM p.found_evidence OR (o.scope->>'purpose') IS DISTINCT FROM 'payment_evidence'))),
  'missing_evidence_reservation',count(*) FILTER(WHERE found_evidence IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private.storage_payload_reservations r WHERE r.object_key=p.evidence_key)),
  'evidence_reservation_mismatches',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM private.storage_payload_reservations r WHERE r.object_key=p.evidence_key AND
   (r.plaintext_sha256 IS DISTINCT FROM p.evidence_plaintext_sha OR r.aad IS DISTINCT FROM ('evidence:'||p.found_evidence||':'||p.evidence_plaintext_sha) OR
    (r.scope->>'ownerId') IS DISTINCT FROM p.evidence_owner OR (r.scope->>'entityId') IS DISTINCT FROM p.found_evidence OR (r.scope->>'purpose') IS DISTINCT FROM 'payment_evidence'))),
  'missing_current_evidence_object_metadata',count(*) FILTER(WHERE found_evidence IS NOT NULL AND NOT EXISTS(SELECT 1 FROM storage.objects s JOIN private.storage_namespace n ON n.singleton AND s.bucket_id=n.bucket WHERE s.name=p.evidence_key AND s.archived_at IS NULL AND coalesce(s.is_delete_marker,false)=false)),
  'distinct_beneficiary_records',count(DISTINCT member_id),
  'distinct_evidence_owner_records',count(DISTINCT evidence_owner),
  'payments_with_auth_linked_beneficiary',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM private.auth_principal_links a WHERE a.user_id=p.member_id)),
  'payments_with_auth_linked_evidence_owner',count(*) FILTER(WHERE EXISTS(SELECT 1 FROM private.auth_principal_links a WHERE a.user_id=p.evidence_owner))
 ) AS value FROM p
), sms_graph AS (
 SELECT jsonb_build_object(
  'source_links',count(*),'distinct_receipts',count(DISTINCT x.raw_sms_id),
  'missing_transaction',count(*) FILTER(WHERE t.id IS NULL),
  'missing_receipt',count(*) FILTER(WHERE r.id IS NULL),
  'missing_parse_attempt',count(*) FILTER(WHERE a.id IS NULL),
  'parse_source_mismatches',count(*) FILTER(WHERE a.id IS NOT NULL AND (a.raw_sms_id IS DISTINCT FROM r.id OR a.source_body_sha256 IS DISTINCT FROM r.body_sha256)),
  'missing_native_origin',count(*) FILTER(WHERE n.source_id IS NULL),
  'origin_hash_mismatches',count(*) FILTER(WHERE n.source_id IS NOT NULL AND (n.body_sha256 IS DISTINCT FROM r.body_sha256 OR n.object_sha256 IS DISTINCT FROM r.object_sha256)),
  'missing_object_journal',count(*) FILTER(WHERE r.id IS NOT NULL AND o.object_key IS NULL),
  'journal_plaintext_digest_mismatches',count(*) FILTER(WHERE o.object_key IS NOT NULL AND (o.custom_metadata->>'sha256') IS DISTINCT FROM r.object_sha256),
  'journal_scope_mismatches',count(*) FILTER(WHERE o.object_key IS NOT NULL AND ((o.scope->>'ownerId') IS DISTINCT FROM r.owner_user_id OR (o.scope->>'entityId') IS DISTINCT FROM r.id OR (o.scope->>'purpose') IS DISTINCT FROM 'sms_receipt')),
  'missing_reservation',count(*) FILTER(WHERE r.id IS NOT NULL AND z.object_key IS NULL),
  'reservation_mismatches',count(*) FILTER(WHERE z.object_key IS NOT NULL AND (z.plaintext_sha256 IS DISTINCT FROM r.object_sha256 OR z.aad IS DISTINCT FROM ('sms:'||r.id||':'||r.object_sha256) OR (z.scope->>'ownerId') IS DISTINCT FROM r.owner_user_id OR (z.scope->>'entityId') IS DISTINCT FROM r.id OR (z.scope->>'purpose') IS DISTINCT FROM 'sms_receipt')),
  'missing_current_object_metadata',count(*) FILTER(WHERE r.id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM storage.objects s JOIN private.storage_namespace sn ON sn.singleton AND s.bucket_id=sn.bucket WHERE s.name=r.object_key AND s.archived_at IS NULL AND coalesce(s.is_delete_marker,false)=false))
 ) AS value FROM app.momo_transaction_sources x
 LEFT JOIN app.momo_transactions t ON t.id=x.transaction_id
 LEFT JOIN app.sms_receipts r ON r.id=x.raw_sms_id
 LEFT JOIN app.momo_parse_attempts a ON a.id=x.parse_attempt_id
 LEFT JOIN private.burimunsi_native_receipt_origins n ON n.source_id=x.raw_sms_id
 LEFT JOIN private.storage_objects o ON o.object_key=r.object_key
 LEFT JOIN private.storage_payload_reservations z ON z.object_key=r.object_key
)
SELECT jsonb_build_object(
 'format','collect.financial-source-inventory.v1',
 'observed_at_utc',to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
 'server_major',current_setting('server_version_num')::integer/10000,
 'totals',jsonb_build_object(
  'collections',(SELECT count(*) FROM app.collections),'memberships',(SELECT count(*) FROM app.memberships),
  'app_users',(SELECT count(*) FROM app.users),'auth_users',(SELECT count(*) FROM auth.users),
  'principal_links',(SELECT count(*) FROM private.auth_principal_links),
  'sms_receipts',(SELECT count(*) FROM app.sms_receipts),'momo_transactions',(SELECT count(*) FROM app.momo_transactions),
  'payment_evidence',(SELECT count(*) FROM app.payment_evidence),'payments',(SELECT count(*) FROM app.payments),
  'ledger_entries',(SELECT count(*) FROM app.ledger_entries),'reversal_entries',(SELECT count(*) FROM app.ledger_entries WHERE kind='reversal'),
  'financial_links',(SELECT count(*) FROM app.momo_financial_links),'posting_snapshots',(SELECT count(*) FROM app.contribution_posting_snapshots),
  'storage_objects',(SELECT count(*) FROM storage.objects),'storage_namespace_rows',(SELECT count(*) FROM private.storage_namespace WHERE singleton)),
 'source_fence',jsonb_build_object('mode',(SELECT mode FROM private.collect_fence_control WHERE singleton),
  'epoch',(SELECT epoch FROM private.collect_fence_control WHERE singleton),
  'non_settled_admissions',(SELECT count(*) FROM private.collect_fence_admissions WHERE state IS DISTINCT FROM 'settled')),
 'payment_graph',(SELECT value FROM payment_graph),'sms_graph',(SELECT value FROM sms_graph),
 'coverage',jsonb_build_object(
  'sms_receipts_without_transaction_source',(SELECT count(*) FROM app.sms_receipts r WHERE NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources x WHERE x.raw_sms_id=r.id)),
  'momo_transactions_without_source',(SELECT count(*) FROM app.momo_transactions t WHERE NOT EXISTS(SELECT 1 FROM app.momo_transaction_sources x WHERE x.transaction_id=t.id)),
  'evidence_without_payment',(SELECT count(*) FROM app.payment_evidence e WHERE NOT EXISTS(SELECT 1 FROM app.payments p WHERE p.evidence_id=e.id)),
  'ledger_entries_without_payment',(SELECT count(*) FROM app.ledger_entries l WHERE NOT EXISTS(SELECT 1 FROM app.payments p WHERE p.id=l.payment_id)),
  'snapshots_without_ledger_payment_pair',(SELECT count(*) FROM app.contribution_posting_snapshots s WHERE NOT EXISTS(SELECT 1 FROM app.ledger_entries l WHERE l.id=s.ledger_entry_id AND l.payment_id=s.payment_id)),
  'financial_links_without_payment',(SELECT count(*) FROM app.momo_financial_links f WHERE NOT EXISTS(SELECT 1 FROM app.payments p WHERE p.id=f.payment_id)),
  'financial_links_without_transaction',(SELECT count(*) FROM app.momo_financial_links f WHERE NOT EXISTS(SELECT 1 FROM app.momo_transactions t WHERE t.id=f.transaction_id)),
  'native_origins_without_receipt',(SELECT count(*) FROM private.burimunsi_native_receipt_origins n WHERE NOT EXISTS(SELECT 1 FROM app.sms_receipts r WHERE r.id=n.source_id))),
 'target_compared',false,'object_bytes_verified',false,'key_compatibility_verified',false,
 'complete_dependency_graph_verified',false,'write_authorized',false
) AS inventory;
ROLLBACK;
