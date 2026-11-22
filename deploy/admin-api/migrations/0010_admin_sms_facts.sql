-- Preserved SMS observations, not provider verification or settlement. Source
-- payloads stay private R2 objects; parsed columns remain immutable provenance.
PRAGMA foreign_keys=ON;
CREATE TABLE collect_sms_facts (
 id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=36),
 source_kind TEXT NOT NULL CHECK(source_kind IN ('member','receiver')),
 member_submission_id TEXT UNIQUE REFERENCES member_receipt_submissions(id) ON DELETE RESTRICT,
 receiver_ingress_id TEXT UNIQUE REFERENCES collect_receipt_ingress(id) ON DELETE RESTRICT,
 source_body_sha256 TEXT NOT NULL CHECK(length(source_body_sha256)=64 AND source_body_sha256 NOT GLOB '*[^a-f0-9]*'),
 source_payload_sha256 TEXT NOT NULL CHECK(length(source_payload_sha256)=64 AND source_payload_sha256 NOT GLOB '*[^a-f0-9]*'),
 parser_version TEXT NOT NULL,
 extraction_status TEXT NOT NULL CHECK(extraction_status IN ('parsed','needs_review')),
 payer_name TEXT,
 payer_phone TEXT,
 payer_masked_phone TEXT,
 payer_last3 TEXT CHECK(payer_last3 IS NULL OR (length(payer_last3)=3 AND payer_last3 NOT GLOB '*[^0-9]*')),
 payee_momo_number TEXT,
 payee_momo_code TEXT,
 momo_transaction_reference TEXT,
 momo_timestamp_local TEXT,
 momo_timezone_offset TEXT,
 amount_rwf INTEGER CHECK(amount_rwf IS NULL OR amount_rwf BETWEEN 1 AND 9007199254740991),
 wallet_balance_rwf INTEGER CHECK(wallet_balance_rwf IS NULL OR wallet_balance_rwf BETWEEN 0 AND 9007199254740991),
 network TEXT CHECK(network IS NULL OR network IN ('mtn_momo','airtel_money')),
 direction TEXT CHECK(direction IS NULL OR direction IN ('incoming','outgoing')),
 is_payment INTEGER NOT NULL CHECK(is_payment IN (0,1)),
 parsed_by_admin_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE RESTRICT,
 operation_request_id TEXT NOT NULL UNIQUE REFERENCES collect_operation_requests(id) ON DELETE RESTRICT,
 parsed_at INTEGER NOT NULL CHECK(parsed_at>0),
 CHECK((source_kind='member' AND member_submission_id IS NOT NULL AND receiver_ingress_id IS NULL)
  OR (source_kind='receiver' AND receiver_ingress_id IS NOT NULL AND member_submission_id IS NULL)),
 CHECK(payer_phone IS NULL OR payer_masked_phone IS NULL)
) STRICT;
CREATE INDEX collect_sms_provider_reference ON collect_sms_facts(network,momo_transaction_reference,id);
CREATE TRIGGER collect_sms_facts_source BEFORE INSERT ON collect_sms_facts
BEGIN
 SELECT (CASE WHEN NOT ((NEW.source_kind='member' AND EXISTS(SELECT 1 FROM member_receipt_submissions s WHERE s.id=NEW.member_submission_id AND s.body_hash=NEW.source_body_sha256))
  OR (NEW.source_kind='receiver' AND EXISTS(SELECT 1 FROM collect_receipt_ingress s WHERE s.id=NEW.receiver_ingress_id AND s.payload_sha256=NEW.source_payload_sha256)))
  THEN RAISE(ABORT,'Extracted facts require preserved source hashes') END);
END;
CREATE TRIGGER collect_sms_facts_no_update BEFORE UPDATE ON collect_sms_facts
BEGIN SELECT RAISE(ABORT,'Extracted SMS source facts are immutable'); END;
CREATE TRIGGER collect_sms_facts_no_delete BEFORE DELETE ON collect_sms_facts
BEGIN SELECT RAISE(ABORT,'Extracted SMS source facts are immutable'); END;

CREATE TABLE collect_transaction_public_references (
 transaction_id TEXT PRIMARY KEY NOT NULL REFERENCES collect_transactions(id) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
 public_reference TEXT NOT NULL UNIQUE CHECK(length(public_reference)=18 AND public_reference NOT GLOB '*[^0-9]*'),
 payer_last3_known INTEGER NOT NULL CHECK(payer_last3_known IN (0,1)),
 payee_last3_known INTEGER NOT NULL CHECK(payee_last3_known IN (0,1)),
 source_fact_id TEXT REFERENCES collect_sms_facts(id) ON DELETE RESTRICT,
 random_source TEXT NOT NULL CHECK(random_source IN ('sqlite_prng','crypto_get_random_values')),
 created_at INTEGER NOT NULL CHECK(created_at>0),
 CHECK(payer_last3_known=1 OR substr(public_reference,1,3)='000'),
 CHECK(payee_last3_known=1 OR substr(public_reference,4,3)='000'),
 CHECK((payer_last3_known=0 AND payee_last3_known=0) OR source_fact_id IS NOT NULL)
) STRICT;
CREATE TRIGGER collect_transaction_public_reference_no_update BEFORE UPDATE ON collect_transaction_public_references
BEGIN SELECT RAISE(ABORT,'Public transaction references are immutable'); END;
CREATE TRIGGER collect_transaction_public_reference_no_delete BEFORE DELETE ON collect_transaction_public_references
BEGIN SELECT RAISE(ABORT,'Public transaction references are immutable'); END;

-- Public identifiers are not secrets. Fallback explicitly records SQLite PRNG
-- provenance and unknown prefixes. UNIQUE collision aborts the enclosing batch;
-- application callers reconcile the request before any fresh retry.
INSERT INTO collect_transaction_public_references(transaction_id,public_reference,payer_last3_known,payee_last3_known,random_source,created_at)
 SELECT id,'000000'||printf('%012d',abs(random())%1000000000000),0,0,'sqlite_prng',created_at FROM collect_transactions;
CREATE TRIGGER collect_transaction_public_reference_default AFTER INSERT ON collect_transactions
WHEN NOT EXISTS(SELECT 1 FROM collect_transaction_public_references WHERE transaction_id=NEW.id)
BEGIN
 INSERT INTO collect_transaction_public_references(transaction_id,public_reference,payer_last3_known,payee_last3_known,random_source,created_at)
 VALUES(NEW.id,'000000'||printf('%012d',abs(random())%1000000000000),0,0,'sqlite_prng',NEW.created_at);
END;

-- A preinserted cryptographic reference is committed with its new transaction
-- under the deferred FK. Source matching is explicit and contextual, never an
-- inferred cross-account provider-reference or masked-last-three match.
CREATE TRIGGER collect_transaction_public_reference_context AFTER INSERT ON collect_transactions
WHEN EXISTS(SELECT 1 FROM collect_transaction_public_references r WHERE r.transaction_id=NEW.id AND r.source_fact_id IS NOT NULL)
BEGIN
 SELECT (CASE WHEN NOT EXISTS(
  SELECT 1 FROM collect_transaction_public_references r JOIN collect_sms_facts f ON f.id=r.source_fact_id
  JOIN collect_payees y ON y.id=NEW.payee_id
  LEFT JOIN collect_receipt_ingress s ON s.id=f.receiver_ingress_id
  LEFT JOIN collect_member_receipt_reviews m ON m.submission_id=f.member_submission_id
  LEFT JOIN collect_transaction_evidence e ON e.id=m.evidence_id
  WHERE r.transaction_id=NEW.id AND f.network=NEW.network AND f.momo_transaction_reference=NEW.provider_reference
   AND f.amount_rwf=NEW.amount_rwf AND f.direction='incoming' AND f.is_payment=1
   AND ((f.source_kind='receiver' AND s.payee_id=NEW.payee_id AND s.payload_sha256=f.source_payload_sha256)
    OR (f.source_kind='member' AND m.transaction_id=NEW.id AND m.outcome='reviewed' AND e.transaction_id=NEW.id
     AND e.artifact_sha256=f.source_body_sha256 AND e.kind='payer_receipt'))
   AND (r.payer_last3_known=0 OR substr(r.public_reference,1,3)=f.payer_last3)
   AND (r.payee_last3_known=0 OR substr(r.public_reference,4,3)=substr(y.momo_number_or_code,-3))
   AND (NOT (y.momo_number_or_code GLOB '07[2389]???????' OR y.momo_number_or_code GLOB '2507[2389]???????')
    OR f.payee_momo_number IS NULL
    OR (CASE WHEN substr(f.payee_momo_number,1,4)='+250' THEN '0'||substr(f.payee_momo_number,5)
      WHEN substr(f.payee_momo_number,1,3)='250' THEN '0'||substr(f.payee_momo_number,4) ELSE f.payee_momo_number END)
      =(CASE WHEN substr(y.momo_number_or_code,1,3)='250' THEN '0'||substr(y.momo_number_or_code,4) ELSE y.momo_number_or_code END))
   AND ((y.momo_number_or_code GLOB '07[2389]???????' OR y.momo_number_or_code GLOB '2507[2389]???????')
    OR f.payee_momo_code IS NULL OR f.payee_momo_code=y.momo_number_or_code)
   AND NOT EXISTS(SELECT 1 FROM collect_sms_facts other WHERE other.network=f.network
    AND other.momo_transaction_reference=f.momo_transaction_reference AND other.source_body_sha256!=f.source_body_sha256))
  THEN RAISE(ABORT,'Public reference requires explicitly matched receipt evidence') END);
END;

CREATE TRIGGER collect_transaction_public_reference_existing BEFORE INSERT ON collect_transaction_public_references
WHEN NEW.source_fact_id IS NOT NULL AND EXISTS(SELECT 1 FROM collect_transactions WHERE id=NEW.transaction_id)
BEGIN
 SELECT (CASE WHEN NOT EXISTS(
  SELECT 1 FROM collect_transactions t JOIN collect_sms_facts f ON f.id=NEW.source_fact_id JOIN collect_payees y ON y.id=t.payee_id
  LEFT JOIN collect_receipt_ingress s ON s.id=f.receiver_ingress_id
  LEFT JOIN collect_member_receipt_reviews m ON m.submission_id=f.member_submission_id
  LEFT JOIN collect_transaction_evidence e ON e.id=m.evidence_id
  WHERE t.id=NEW.transaction_id AND f.network=t.network AND f.momo_transaction_reference=t.provider_reference AND f.amount_rwf=t.amount_rwf
   AND f.direction='incoming' AND f.is_payment=1
   AND ((f.source_kind='receiver' AND s.payee_id=t.payee_id AND s.payload_sha256=f.source_payload_sha256)
    OR (f.source_kind='member' AND m.transaction_id=t.id AND m.outcome='reviewed' AND e.transaction_id=t.id AND e.kind='payer_receipt' AND e.artifact_sha256=f.source_body_sha256))
   AND (NEW.payer_last3_known=0 OR substr(NEW.public_reference,1,3)=f.payer_last3)
   AND (NEW.payee_last3_known=0 OR substr(NEW.public_reference,4,3)=substr(y.momo_number_or_code,-3))
   AND (NOT (y.momo_number_or_code GLOB '07[2389]???????' OR y.momo_number_or_code GLOB '2507[2389]???????')
    OR f.payee_momo_number IS NULL
    OR (CASE WHEN substr(f.payee_momo_number,1,4)='+250' THEN '0'||substr(f.payee_momo_number,5)
      WHEN substr(f.payee_momo_number,1,3)='250' THEN '0'||substr(f.payee_momo_number,4) ELSE f.payee_momo_number END)
      =(CASE WHEN substr(y.momo_number_or_code,1,3)='250' THEN '0'||substr(y.momo_number_or_code,4) ELSE y.momo_number_or_code END))
   AND ((y.momo_number_or_code GLOB '07[2389]???????' OR y.momo_number_or_code GLOB '2507[2389]???????')
    OR f.payee_momo_code IS NULL OR f.payee_momo_code=y.momo_number_or_code)
   AND NOT EXISTS(SELECT 1 FROM collect_sms_facts other WHERE other.network=f.network AND other.momo_transaction_reference=f.momo_transaction_reference AND other.source_body_sha256!=f.source_body_sha256))
  THEN RAISE(ABORT,'Public reference requires explicitly matched receipt evidence') END);
END;
