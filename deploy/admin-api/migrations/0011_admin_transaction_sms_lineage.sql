-- Reviewed member evidence can describe an existing transaction without
-- rewriting its immutable public identifier or its reference-source origin.
PRAGMA foreign_keys=ON;
CREATE TABLE collect_transaction_sms_sources (
 transaction_id TEXT PRIMARY KEY NOT NULL REFERENCES collect_transactions(id) ON DELETE RESTRICT,
 source_fact_id TEXT NOT NULL UNIQUE REFERENCES collect_sms_facts(id) ON DELETE RESTRICT,
 review_id TEXT NOT NULL UNIQUE REFERENCES collect_member_receipt_reviews(id) ON DELETE RESTRICT,
 actor_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
 operation_request_id TEXT NOT NULL REFERENCES collect_operation_requests(id) ON DELETE RESTRICT,
 created_at INTEGER NOT NULL CHECK(created_at>0)
) STRICT;
CREATE TRIGGER collect_transaction_sms_source_context BEFORE INSERT ON collect_transaction_sms_sources
BEGIN
 SELECT (CASE WHEN NOT EXISTS(
  SELECT 1 FROM collect_transactions t JOIN collect_payees y ON y.id=t.payee_id
  JOIN collect_transaction_public_references public_reference ON public_reference.transaction_id=t.id
  JOIN collect_member_receipt_reviews r ON r.id=NEW.review_id AND r.transaction_id=t.id
  JOIN member_receipt_submissions s ON s.id=r.submission_id
  JOIN collect_transaction_evidence e ON e.id=r.evidence_id AND e.transaction_id=t.id
  JOIN collect_sms_facts f ON f.id=NEW.source_fact_id AND f.member_submission_id=s.id
  JOIN collect_operation_requests o ON o.id=NEW.operation_request_id AND o.actor_admin_id=NEW.actor_admin_id
  WHERE t.id=NEW.transaction_id AND public_reference.source_fact_id IS NULL
   AND r.outcome='reviewed' AND e.kind='payer_receipt' AND e.artifact_sha256=s.body_hash AND f.source_body_sha256=s.body_hash
   AND f.source_kind='member' AND f.extraction_status='parsed' AND f.direction='incoming' AND f.is_payment=1
   AND f.network=t.network AND f.amount_rwf=t.amount_rwf AND f.momo_transaction_reference=t.provider_reference
   AND NEW.created_at>=r.reviewed_at AND NEW.created_at>=f.parsed_at
   AND (NOT (y.momo_number_or_code GLOB '07[2389]???????' OR y.momo_number_or_code GLOB '2507[2389]???????')
    OR f.payee_momo_number IS NULL
    OR (CASE WHEN substr(f.payee_momo_number,1,4)='+250' THEN '0'||substr(f.payee_momo_number,5)
      WHEN substr(f.payee_momo_number,1,3)='250' THEN '0'||substr(f.payee_momo_number,4) ELSE f.payee_momo_number END)
      =(CASE WHEN substr(y.momo_number_or_code,1,3)='250' THEN '0'||substr(y.momo_number_or_code,4) ELSE y.momo_number_or_code END))
   AND ((y.momo_number_or_code GLOB '07[2389]???????' OR y.momo_number_or_code GLOB '2507[2389]???????')
    OR f.payee_momo_code IS NULL OR f.payee_momo_code=y.momo_number_or_code)
   AND NOT EXISTS(SELECT 1 FROM collect_sms_facts other WHERE other.network=f.network
    AND other.momo_transaction_reference=f.momo_transaction_reference AND other.source_body_sha256!=f.source_body_sha256))
  THEN RAISE(ABORT,'Transaction SMS lineage requires explicitly matched reviewed member evidence') END);
END;
CREATE TRIGGER collect_transaction_sms_source_no_update BEFORE UPDATE ON collect_transaction_sms_sources
BEGIN SELECT RAISE(ABORT,'Transaction SMS lineage is immutable'); END;
CREATE TRIGGER collect_transaction_sms_source_no_delete BEFORE DELETE ON collect_transaction_sms_sources
BEGIN SELECT RAISE(ABORT,'Transaction SMS lineage cannot be deleted'); END;
