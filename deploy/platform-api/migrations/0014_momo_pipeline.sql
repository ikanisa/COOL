-- MoMo notification evidence and durable extraction. No ledger/balance writes.
PRAGMA foreign_keys=ON;
CREATE TABLE momo_receiving_accounts (
 id TEXT PRIMARY KEY, provider TEXT NOT NULL CHECK(provider IN('mtn_momo','airtel_money')),
 public_code TEXT NOT NULL, recipient_name TEXT NOT NULL, receiver_hash TEXT NOT NULL CHECK(length(receiver_hash)=64),
 currency TEXT NOT NULL DEFAULT 'RWF' CHECK(currency='RWF'), timezone TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'active' CHECK(status IN('active','suspended')),
 profile_status TEXT NOT NULL DEFAULT 'unverified' CHECK(profile_status IN('unverified','approved')),
 profile_version TEXT NOT NULL DEFAULT 'unverified', profile_json TEXT NOT NULL DEFAULT '{}' CHECK(json_valid(profile_json)),
 created_at TEXT NOT NULL, UNIQUE(provider,receiver_hash)
) STRICT;
CREATE TABLE momo_gateway_bindings (
 id TEXT PRIMARY KEY, owner_user_id TEXT NOT NULL REFERENCES users(id),
 receiving_account_id TEXT NOT NULL REFERENCES momo_receiving_accounts(id), version INTEGER NOT NULL DEFAULT 1 CHECK(version>0),
 status TEXT NOT NULL DEFAULT 'active' CHECK(status IN('active','revoked')),
 subscription_evidence TEXT, created_at TEXT NOT NULL, revoked_at TEXT,
 UNIQUE(id,version,receiving_account_id)
) STRICT;
CREATE INDEX momo_binding_owner ON momo_gateway_bindings(owner_user_id,status,id);
CREATE TRIGGER momo_binding_identity BEFORE UPDATE OF id,owner_user_id,receiving_account_id,version,subscription_evidence,created_at ON momo_gateway_bindings
BEGIN SELECT RAISE(ABORT,'immutable_gateway_binding'); END;
CREATE TRIGGER momo_binding_no_delete BEFORE DELETE ON momo_gateway_bindings BEGIN SELECT RAISE(ABORT,'retain_gateway_binding'); END;
CREATE TRIGGER momo_account_identity BEFORE UPDATE OF id,provider,public_code,receiver_hash,currency,timezone ON momo_receiving_accounts
BEGIN SELECT RAISE(ABORT,'immutable_receiving_account'); END;

CREATE TABLE momo_processing_jobs (
 raw_sms_id TEXT PRIMARY KEY REFERENCES sms_receipts(id),
 binding_id TEXT REFERENCES momo_gateway_bindings(id), binding_version INTEGER,
 receiving_account_id TEXT REFERENCES momo_receiving_accounts(id), mode TEXT NOT NULL CHECK(mode IN('live','historical')),
 state TEXT NOT NULL CHECK(state IN('pending','processing','retry','completed','needs_review','source_unresolved')),
 attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count>=0), max_attempts INTEGER NOT NULL DEFAULT 4 CHECK(max_attempts>=4), available_at INTEGER NOT NULL,
 lease_token TEXT, lease_until INTEGER, last_error TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
 CHECK((binding_id IS NULL AND binding_version IS NULL AND (receiving_account_id IS NULL OR mode='historical')) OR
  (binding_id IS NOT NULL AND binding_version IS NOT NULL AND receiving_account_id IS NOT NULL))
) STRICT;
CREATE INDEX momo_job_ready ON momo_processing_jobs(state,available_at,raw_sms_id);
CREATE TRIGGER momo_job_enrollment BEFORE INSERT ON momo_processing_jobs WHEN NEW.binding_id IS NOT NULL BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM momo_gateway_bindings b JOIN momo_receiving_accounts a ON a.id=b.receiving_account_id
  JOIN sms_receipts s ON s.id=NEW.raw_sms_id WHERE b.id=NEW.binding_id AND b.version=NEW.binding_version
  AND b.receiving_account_id=NEW.receiving_account_id AND b.owner_user_id=s.owner_user_id AND b.status='active'
  AND a.status='active' AND a.receiver_hash=s.receiver_hash) THEN RAISE(ABORT,'gateway_binding_changed') END;
END;
CREATE TRIGGER momo_job_source_identity BEFORE UPDATE OF raw_sms_id,binding_id,binding_version,receiving_account_id,mode,created_at ON momo_processing_jobs
BEGIN SELECT RAISE(ABORT,'immutable_momo_source'); END;

CREATE TABLE momo_parse_attempts (
 id TEXT PRIMARY KEY, raw_sms_id TEXT NOT NULL REFERENCES sms_receipts(id), attempt_number INTEGER NOT NULL,
 model_id TEXT NOT NULL, schema_version TEXT NOT NULL, prompt_version TEXT NOT NULL, parser_version TEXT NOT NULL,
 profile_version TEXT NOT NULL, profile_json TEXT NOT NULL CHECK(json_valid(profile_json)), source_body_sha256 TEXT NOT NULL,
 output_json TEXT CHECK(output_json IS NULL OR json_valid(output_json)), validation_json TEXT NOT NULL CHECK(json_valid(validation_json)),
 outcome TEXT NOT NULL CHECK(outcome IN('accepted','duplicate','conflict','non_payment','needs_review','retry','superseded')),
 created_at TEXT NOT NULL, UNIQUE(raw_sms_id,attempt_number)
) STRICT;
CREATE TRIGGER momo_attempt_no_update BEFORE UPDATE ON momo_parse_attempts BEGIN SELECT RAISE(ABORT,'immutable_momo_attempt'); END;
CREATE TRIGGER momo_attempt_no_delete BEFORE DELETE ON momo_parse_attempts BEGIN SELECT RAISE(ABORT,'retain_momo_attempt'); END;

CREATE TABLE momo_transactions (
 id TEXT PRIMARY KEY, receiving_account_id TEXT NOT NULL REFERENCES momo_receiving_accounts(id),
 provider TEXT NOT NULL, provider_transaction_id TEXT NOT NULL, event_kind TEXT NOT NULL CHECK(event_kind IN('incoming_receipt','reversal')),
 original_transaction_id TEXT, amount_minor INTEGER NOT NULL CHECK(amount_minor>0 AND amount_minor<=9007199254740991),
 currency TEXT NOT NULL CHECK(currency='RWF'), currency_scale INTEGER NOT NULL CHECK(currency_scale=0),
 payer_name TEXT, payer_identifier TEXT, payer_last3 TEXT CHECK(payer_last3 IS NULL OR (length(payer_last3)=3 AND payer_last3 NOT GLOB '*[^0-9]*')),
 transaction_at TEXT, transaction_datetime_raw TEXT, transaction_timezone TEXT NOT NULL, transaction_time_source TEXT NOT NULL,
 fee_minor INTEGER CHECK(fee_minor IS NULL OR fee_minor>=0), wallet_balance_after_minor INTEGER CHECK(wallet_balance_after_minor IS NULL OR wallet_balance_after_minor>=0),
 parse_attempt_id TEXT NOT NULL REFERENCES momo_parse_attempts(id), mode TEXT NOT NULL CHECK(mode IN('live','historical')),
 allocation_state TEXT NOT NULL DEFAULT 'unallocated' CHECK(allocation_state IN('unallocated','linked','needs_review')),
 has_conflict INTEGER NOT NULL DEFAULT 0 CHECK(has_conflict IN(0,1)), version INTEGER NOT NULL DEFAULT 1,
 created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
 UNIQUE(provider,receiving_account_id,event_kind,provider_transaction_id)
) STRICT;
CREATE INDEX momo_transaction_page ON momo_transactions(created_at,id);
CREATE TRIGGER momo_transaction_facts BEFORE UPDATE OF id,receiving_account_id,provider,provider_transaction_id,event_kind,original_transaction_id,amount_minor,currency,currency_scale,payer_name,payer_identifier,payer_last3,transaction_at,transaction_datetime_raw,transaction_timezone,transaction_time_source,fee_minor,wallet_balance_after_minor,parse_attempt_id,mode,created_at ON momo_transactions
BEGIN SELECT RAISE(ABORT,'immutable_momo_transaction_facts'); END;
CREATE TRIGGER momo_transaction_no_delete BEFORE DELETE ON momo_transactions BEGIN SELECT RAISE(ABORT,'retain_momo_transaction'); END;
CREATE TABLE momo_transaction_sources (
 transaction_id TEXT NOT NULL REFERENCES momo_transactions(id), raw_sms_id TEXT NOT NULL REFERENCES sms_receipts(id),
 parse_attempt_id TEXT NOT NULL REFERENCES momo_parse_attempts(id), relation TEXT NOT NULL CHECK(relation IN('accepted','duplicate','conflict')),
 created_at TEXT NOT NULL, PRIMARY KEY(transaction_id,raw_sms_id,parse_attempt_id)
) STRICT;
CREATE TRIGGER momo_transaction_source_no_update BEFORE UPDATE ON momo_transaction_sources BEGIN SELECT RAISE(ABORT,'immutable_momo_source_link'); END;
CREATE TRIGGER momo_transaction_source_no_delete BEFORE DELETE ON momo_transaction_sources BEGIN SELECT RAISE(ABORT,'retain_momo_source_link'); END;
CREATE TABLE momo_processing_guards(id TEXT PRIMARY KEY,passed INTEGER NOT NULL CONSTRAINT momo_processing_state CHECK(passed=1)) STRICT;
