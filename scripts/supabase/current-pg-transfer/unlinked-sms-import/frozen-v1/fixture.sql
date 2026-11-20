-- Synthetic extension of the existing financial/native fixtures. This is not
-- the real Collect catalogue and deliberately has no production replay path.
ALTER TABLE src.sms_receipts ALTER COLUMN originating_session_id DROP NOT NULL,ALTER COLUMN receiver_hash DROP NOT NULL;
ALTER TABLE src.momo_transactions ALTER COLUMN provider_transaction_id DROP NOT NULL,ALTER COLUMN amount_minor DROP NOT NULL,
 ALTER COLUMN currency DROP NOT NULL,ALTER COLUMN currency_scale DROP NOT NULL;
ALTER TABLE src.momo_transactions DROP CONSTRAINT momo_transactions_event_kind_check;
ALTER TABLE src.momo_transactions ADD CONSTRAINT unlinked_event_kind_check
 CHECK(event_kind IN ('incoming_receipt','outgoing','reversal','failed','pending','other','unknown'));
ALTER TABLE src.momo_transactions DROP CONSTRAINT momo_transactions_allocation_state_check;
ALTER TABLE src.momo_transactions ADD CONSTRAINT unlinked_allocation_state_check
 CHECK(allocation_state IN ('unallocated','linked','needs_review','not_applicable'));
ALTER TABLE src.momo_transactions ADD CONSTRAINT unlinked_nullable_fact_shape CHECK(
 (provider_transaction_id IS NOT NULL AND amount_minor IS NOT NULL AND currency IS NOT NULL AND currency_scale IS NOT NULL)
 OR (allocation_state='not_applicable' AND ((currency IS NULL AND currency_scale IS NULL) OR (currency IS NOT NULL AND currency_scale=0)))
 OR (provider_transaction_id IS NULL AND event_kind='incoming_receipt' AND amount_minor IS NOT NULL AND amount_minor>0
   AND currency IS NOT NULL AND currency='RWF' AND currency_scale IS NOT NULL AND currency_scale=0));
ALTER TABLE src.jobs ADD COLUMN posting_output jsonb,ADD COLUMN posting_next_attempt_at bigint NOT NULL DEFAULT 0,
 ADD COLUMN posting_failure_count integer NOT NULL DEFAULT 0,ADD COLUMN posting_last_error text;
ALTER TABLE src.jobs ADD CONSTRAINT unlinked_posting_pair CHECK((posting_facts IS NULL)=(posting_output IS NULL));

-- Inert fixture quarantine: no application tables, financial writer, worker,
-- credential or replay endpoint consumes these rows. Content is synthetic.
CREATE TABLE private.fixture_unlinked_claims(
 operation_id uuid PRIMARY KEY,collection_id text NOT NULL UNIQUE,plan_sha256 text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private.fixture_unlinked_receipts(
 operation_id uuid PRIMARY KEY,collection_id text NOT NULL,plan_sha256 text NOT NULL,
 context_hmac text NOT NULL,identity_hmac text NOT NULL,post_hmac text NOT NULL,
 source_owner text NOT NULL,target_owner text NOT NULL,source_auth uuid NOT NULL,target_auth uuid NOT NULL,
 sms_count integer NOT NULL CHECK(sms_count BETWEEN 1 AND 64),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE private.fixture_unlinked_items(
 source_id text PRIMARY KEY,operation_id uuid NOT NULL REFERENCES private.fixture_unlinked_receipts(operation_id),
 payload jsonb NOT NULL CHECK(jsonb_typeof(payload)='object')
);
REVOKE ALL ON private.fixture_unlinked_claims,private.fixture_unlinked_receipts,private.fixture_unlinked_items FROM PUBLIC,fixture_runtime;
GRANT SELECT,INSERT,MAINTAIN ON private.fixture_unlinked_claims,private.fixture_unlinked_receipts,private.fixture_unlinked_items TO fixture_operator;
GRANT USAGE ON SCHEMA private TO fixture_runtime;
