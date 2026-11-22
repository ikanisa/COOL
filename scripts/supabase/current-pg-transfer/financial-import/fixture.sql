-- Disposable synthetic fixture only. Selected table definitions are copied
-- from the Collect baseline; later mutations and full production constraints,
-- triggers, RLS and provider services are intentionally not reproduced.
CREATE SCHEMA src; CREATE SCHEMA app; CREATE SCHEMA auth; CREATE SCHEMA private;
CREATE FUNCTION app.json_valid(value text) RETURNS boolean LANGUAGE plpgsql IMMUTABLE STRICT AS $$BEGIN PERFORM value::jsonb;RETURN true;EXCEPTION WHEN invalid_text_representation THEN RETURN false;END$$;
SET search_path=app,pg_catalog;
CREATE TABLE sms_receipts ( id TEXT PRIMARY KEY NOT NULL , owner_user_id TEXT NOT NULL , originating_session_id TEXT NOT NULL , client_envelope_id TEXT NOT NULL , body_sha256 TEXT NOT NULL CHECK ( length ( body_sha256 ) = 64 ) , receiver_hash TEXT NOT NULL CHECK ( length ( receiver_hash ) = 64 ) , object_key TEXT NOT NULL UNIQUE , object_sha256 TEXT NOT NULL CHECK ( length ( object_sha256 ) = 64 ) , size_bytes BIGINT NOT NULL CHECK ( size_bytes BETWEEN 1 AND 131072 ) , received_at_device TEXT , status TEXT NOT NULL DEFAULT 'received' CHECK ( status IN ( 'received' , 'under_review' , 'rejected' , 'linked' ) ) , evidence_level TEXT NOT NULL DEFAULT 'client_received' CHECK ( evidence_level = 'client_received' ) , created_at TEXT NOT NULL , UNIQUE ( owner_user_id , client_envelope_id ) );
CREATE TABLE momo_parse_attempts ( id TEXT PRIMARY KEY , raw_sms_id TEXT NOT NULL , attempt_number BIGINT NOT NULL , model_id TEXT NOT NULL , schema_version TEXT NOT NULL , prompt_version TEXT NOT NULL , parser_version TEXT NOT NULL , profile_version TEXT NOT NULL , profile_json TEXT NOT NULL CHECK ( json_valid ( profile_json ) ) , source_body_sha256 TEXT NOT NULL , output_json TEXT CHECK ( output_json IS NULL OR json_valid ( output_json ) ) , validation_json TEXT NOT NULL CHECK ( json_valid ( validation_json ) ) , outcome TEXT NOT NULL CHECK ( outcome IN ( 'accepted' , 'duplicate' , 'conflict' , 'non_payment' , 'needs_review' , 'retry' , 'superseded' ) ) , created_at TEXT NOT NULL , UNIQUE ( raw_sms_id , attempt_number ) );
CREATE TABLE momo_transactions ( id TEXT PRIMARY KEY , receiving_account_id TEXT NOT NULL , provider TEXT NOT NULL , provider_transaction_id TEXT NOT NULL , event_kind TEXT NOT NULL CHECK ( event_kind IN ( 'incoming_receipt' , 'reversal' ) ) , original_transaction_id TEXT , amount_minor BIGINT NOT NULL CHECK ( amount_minor > 0 AND amount_minor <= 9007199254740991 ) , currency TEXT NOT NULL CHECK ( currency = 'RWF' ) , currency_scale BIGINT NOT NULL CHECK ( currency_scale = 0 ) , payer_name TEXT , payer_identifier TEXT , payer_last3 TEXT CHECK ( payer_last3 IS NULL OR ( length ( payer_last3 ) = 3 AND ( payer_last3 !~ '^.*[^0-9].*$' ) ) ) , transaction_at TEXT , transaction_datetime_raw TEXT , transaction_timezone TEXT NOT NULL , transaction_time_source TEXT NOT NULL , fee_minor BIGINT CHECK ( fee_minor IS NULL OR fee_minor >= 0 ) , wallet_balance_after_minor BIGINT CHECK ( wallet_balance_after_minor IS NULL OR wallet_balance_after_minor >= 0 ) , parse_attempt_id TEXT NOT NULL , mode TEXT NOT NULL CHECK ( mode IN ( 'live' , 'historical' ) ) , allocation_state TEXT NOT NULL DEFAULT 'unallocated' CHECK ( allocation_state IN ( 'unallocated' , 'linked' , 'needs_review' ) ) , has_conflict BIGINT NOT NULL DEFAULT 0 CHECK ( has_conflict IN ( 0 , 1 ) ) , version BIGINT NOT NULL DEFAULT 1 , created_at TEXT NOT NULL , updated_at TEXT NOT NULL , UNIQUE ( provider , receiving_account_id , event_kind , provider_transaction_id ) );
CREATE TABLE momo_transaction_sources ( transaction_id TEXT NOT NULL , raw_sms_id TEXT NOT NULL , parse_attempt_id TEXT NOT NULL , relation TEXT NOT NULL CHECK ( relation IN ( 'accepted' , 'duplicate' , 'conflict' ) ) , created_at TEXT NOT NULL , PRIMARY KEY ( transaction_id , raw_sms_id , parse_attempt_id ) );
CREATE TABLE payment_evidence ( id TEXT PRIMARY KEY , collection_id TEXT , owner_user_id TEXT NOT NULL , object_key TEXT NOT NULL UNIQUE , object_sha256 TEXT NOT NULL CHECK ( length ( object_sha256 ) = 64 ) , size_bytes BIGINT NOT NULL CHECK ( size_bytes > 0 ) , content_type TEXT NOT NULL , authenticity TEXT NOT NULL CHECK ( authenticity IN ( 'operator_recorded' , 'provider_authenticated' ) ) , external_reference TEXT , receiver_momo_number TEXT , amount_minor BIGINT CHECK ( amount_minor IS NULL OR ( amount_minor > 0 AND amount_minor <= 9007199254740991 ) ) , currency TEXT NOT NULL DEFAULT 'RWF' CHECK ( currency = 'RWF' ) , observed_at TEXT NOT NULL , created_at TEXT NOT NULL , retained_until TEXT , legal_hold BIGINT NOT NULL DEFAULT 0 CHECK ( legal_hold IN ( 0 , 1 ) ) , receiver_network TEXT , receiver_display_label TEXT , UNIQUE ( owner_user_id , external_reference ) );
CREATE TABLE payments ( id TEXT PRIMARY KEY , collection_id TEXT NOT NULL , member_id TEXT , evidence_id TEXT NOT NULL , intent_id TEXT , amount_minor BIGINT NOT NULL CHECK ( amount_minor > 0 AND amount_minor <= 9007199254740991 ) , currency TEXT NOT NULL DEFAULT 'RWF' CHECK ( currency = 'RWF' ) , rail TEXT NOT NULL DEFAULT 'rwanda_momo' CHECK ( rail = 'rwanda_momo' ) , status TEXT NOT NULL CHECK ( status IN ( 'recorded' , 'reconciled' , 'confirmed' , 'corrected' , 'reversed' , 'ambiguous' ) ) , payer_display_name TEXT NOT NULL DEFAULT '' , created_at TEXT NOT NULL , revision BIGINT NOT NULL DEFAULT 1 , UNIQUE ( evidence_id ) );
CREATE TABLE momo_financial_links ( transaction_id TEXT PRIMARY KEY , payment_id TEXT NOT NULL UNIQUE , beneficiary_member_id TEXT NOT NULL , linked_by TEXT NOT NULL , reason TEXT NOT NULL , historical_existing BIGINT NOT NULL DEFAULT 0 CHECK ( historical_existing IN ( 0 , 1 ) ) , created_at TEXT NOT NULL );
CREATE TABLE ledger_entries ( id TEXT PRIMARY KEY , payment_id TEXT NOT NULL , collection_id TEXT NOT NULL , member_id TEXT , currency TEXT NOT NULL DEFAULT 'RWF' CHECK ( currency = 'RWF' ) , amount_minor BIGINT NOT NULL CHECK ( amount_minor != 0 AND abs ( amount_minor ) <= 9007199254740991 ) , kind TEXT NOT NULL CHECK ( kind IN ( 'contribution' , 'reversal' , 'correction' ) ) , reverses_entry_id TEXT UNIQUE , evidence_id TEXT NOT NULL , actor_user_id TEXT NOT NULL , request_id TEXT NOT NULL UNIQUE , posted_at TEXT NOT NULL , CHECK ( ( kind = 'contribution' AND amount_minor > 0 AND reverses_entry_id IS NULL ) OR ( kind != 'contribution' AND reverses_entry_id IS NOT NULL ) ) );
CREATE TABLE contribution_posting_snapshots ( ledger_entry_id TEXT PRIMARY KEY , payment_id TEXT NOT NULL UNIQUE , member_balance_after_minor BIGINT NOT NULL CHECK ( member_balance_after_minor >= 0 AND member_balance_after_minor <= 9007199254740991 ) , group_balance_after_minor BIGINT NOT NULL CHECK ( group_balance_after_minor >= 0 AND group_balance_after_minor <= 9007199254740991 ) , posted_at TEXT NOT NULL );
ALTER TABLE app.sms_receipts ALTER COLUMN originating_session_id DROP NOT NULL,ALTER COLUMN receiver_hash DROP NOT NULL;
ALTER TABLE app.momo_transactions ALTER COLUMN provider_transaction_id DROP NOT NULL,ALTER COLUMN amount_minor DROP NOT NULL,ALTER COLUMN currency DROP NOT NULL,ALTER COLUMN currency_scale DROP NOT NULL;
ALTER TABLE app.momo_transactions DROP CONSTRAINT momo_transactions_event_kind_check;
ALTER TABLE app.momo_transactions ADD CONSTRAINT momo_transactions_event_kind_check CHECK(event_kind IN ('incoming_receipt','outgoing','reversal','failed','pending','other','unknown'));
ALTER TABLE app.momo_transactions DROP CONSTRAINT momo_transactions_allocation_state_check;
ALTER TABLE app.momo_transactions ADD CONSTRAINT momo_transactions_allocation_state_check CHECK(allocation_state IN ('unallocated','linked','needs_review','not_applicable'));
SET search_path=public,pg_catalog;
CREATE TABLE src.sms_receipts (LIKE app.sms_receipts INCLUDING ALL);
CREATE TABLE src.momo_parse_attempts (LIKE app.momo_parse_attempts INCLUDING ALL);
CREATE TABLE src.momo_transactions (LIKE app.momo_transactions INCLUDING ALL);
CREATE TABLE src.momo_transaction_sources (LIKE app.momo_transaction_sources INCLUDING ALL);
CREATE TABLE src.payment_evidence (LIKE app.payment_evidence INCLUDING ALL);
CREATE TABLE src.payments (LIKE app.payments INCLUDING ALL);
CREATE TABLE src.momo_financial_links (LIKE app.momo_financial_links INCLUDING ALL);
CREATE TABLE src.ledger_entries (LIKE app.ledger_entries INCLUDING ALL);
CREATE TABLE src.contribution_posting_snapshots (LIKE app.contribution_posting_snapshots INCLUDING ALL);
CREATE TABLE src.users(id text PRIMARY KEY,active boolean NOT NULL);
CREATE TABLE app.users(LIKE src.users INCLUDING ALL);
CREATE TABLE src.auth_users(id uuid PRIMARY KEY,active boolean NOT NULL);
CREATE TABLE auth.users(LIKE src.auth_users INCLUDING ALL);
CREATE TABLE src.auth_links(auth_id uuid PRIMARY KEY REFERENCES src.auth_users(id),user_id text NOT NULL UNIQUE REFERENCES src.users(id));
CREATE TABLE private.auth_links(auth_id uuid PRIMARY KEY REFERENCES auth.users(id),user_id text NOT NULL UNIQUE REFERENCES app.users(id));
CREATE TABLE src.collections(id text PRIMARY KEY,creator_user_id text NOT NULL REFERENCES src.users(id));
CREATE TABLE app.collections(id text PRIMARY KEY,creator_user_id text NOT NULL REFERENCES app.users(id));
CREATE TABLE src.memberships(id text PRIMARY KEY,collection_id text NOT NULL REFERENCES src.collections(id),user_id text NOT NULL REFERENCES src.users(id),UNIQUE(collection_id,user_id));
CREATE TABLE app.memberships(id text PRIMARY KEY,collection_id text NOT NULL REFERENCES app.collections(id),user_id text NOT NULL REFERENCES app.users(id),UNIQUE(collection_id,user_id));
CREATE TABLE src.origins(source_id text PRIMARY KEY,collection_id text NOT NULL,principal_user_id text NOT NULL,body_sha256 text NOT NULL,object_sha256 text NOT NULL);
CREATE TABLE private.origins(LIKE src.origins INCLUDING ALL);
CREATE TABLE src.jobs(source_id text PRIMARY KEY,transaction_id text NOT NULL,collection_id text NOT NULL,source_fingerprint text NOT NULL,state text NOT NULL,posting_facts jsonb);
CREATE TABLE private.jobs(LIKE src.jobs INCLUDING ALL);
CREATE TABLE src.scopes(source_id text PRIMARY KEY,transaction_id text NOT NULL,collection_id text NOT NULL,receiving_account_id text NOT NULL);
CREATE TABLE private.scopes(LIKE src.scopes INCLUDING ALL);
CREATE TABLE src.object_proofs(object_key text PRIMARY KEY,owner_id text NOT NULL,entity_id text NOT NULL,purpose text NOT NULL,plaintext_sha256 text NOT NULL,ciphertext_sha256 text NOT NULL,aad text NOT NULL,verified boolean NOT NULL);
CREATE TABLE private.object_proofs(LIKE src.object_proofs INCLUDING ALL);
-- Synthetic assertions only; they do not prove real ledger completeness.
CREATE TABLE private.fixture_history_attestation(collection_id text PRIMARY KEY,complete_ledger boolean NOT NULL,no_prior_deletions boolean NOT NULL,reviewed boolean NOT NULL,evidence_sha256 text NOT NULL);
CREATE TABLE private.fixture_fences(side text PRIMARY KEY,epoch bigint NOT NULL,mode text NOT NULL);
CREATE TABLE private.fixture_admissions(state text,uncertain_dispatches integer);
CREATE TABLE private.fixture_financial_receipts(operation_id uuid PRIMARY KEY,collection_id text NOT NULL UNIQUE,plan_sha256 text NOT NULL,source_hmac text NOT NULL,post_hmac text NOT NULL,source_owner text NOT NULL,target_owner text NOT NULL,source_auth uuid NOT NULL,target_auth uuid NOT NULL,payment_count integer NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
ALTER TABLE app.sms_receipts ADD FOREIGN KEY(owner_user_id) REFERENCES app.users(id);
ALTER TABLE app.momo_parse_attempts ADD FOREIGN KEY(raw_sms_id) REFERENCES app.sms_receipts(id);
ALTER TABLE app.momo_transactions ADD FOREIGN KEY(parse_attempt_id) REFERENCES app.momo_parse_attempts(id);
ALTER TABLE app.momo_transaction_sources ADD FOREIGN KEY(transaction_id) REFERENCES app.momo_transactions(id),ADD FOREIGN KEY(raw_sms_id) REFERENCES app.sms_receipts(id),ADD FOREIGN KEY(parse_attempt_id) REFERENCES app.momo_parse_attempts(id);
ALTER TABLE app.payment_evidence ADD FOREIGN KEY(owner_user_id) REFERENCES app.users(id),ADD FOREIGN KEY(collection_id) REFERENCES app.collections(id);
ALTER TABLE app.payments ADD FOREIGN KEY(collection_id) REFERENCES app.collections(id),ADD FOREIGN KEY(member_id) REFERENCES app.users(id),ADD FOREIGN KEY(evidence_id) REFERENCES app.payment_evidence(id);
ALTER TABLE app.momo_financial_links ADD FOREIGN KEY(transaction_id) REFERENCES app.momo_transactions(id),ADD FOREIGN KEY(payment_id) REFERENCES app.payments(id),ADD FOREIGN KEY(beneficiary_member_id) REFERENCES app.users(id),ADD FOREIGN KEY(linked_by) REFERENCES app.users(id);
ALTER TABLE app.ledger_entries ADD FOREIGN KEY(payment_id) REFERENCES app.payments(id),ADD FOREIGN KEY(collection_id) REFERENCES app.collections(id),ADD FOREIGN KEY(member_id) REFERENCES app.users(id),ADD FOREIGN KEY(evidence_id) REFERENCES app.payment_evidence(id),ADD FOREIGN KEY(actor_user_id) REFERENCES app.users(id),ADD FOREIGN KEY(reverses_entry_id) REFERENCES app.ledger_entries(id);
ALTER TABLE app.contribution_posting_snapshots ADD FOREIGN KEY(payment_id) REFERENCES app.payments(id),ADD FOREIGN KEY(ledger_entry_id) REFERENCES app.ledger_entries(id);
CREATE FUNCTION private.fixture_financial_guard() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN
 IF coalesce(current_setting('collect.fixture_financial_operation',true),'')='' OR
 (SELECT count(*) FROM private.fixture_fences WHERE mode='fenced')<>2 OR
 EXISTS(SELECT 1 FROM private.fixture_admissions WHERE state IS DISTINCT FROM 'settled' OR uncertain_dispatches IS DISTINCT FROM 0)
 THEN RAISE EXCEPTION 'fixture_financial_fenced' USING ERRCODE='42501'; END IF;RETURN NULL;END$$;
DO $triggers$ DECLARE n text;BEGIN
 FOREACH n IN ARRAY ARRAY['payment_evidence','payments','momo_financial_links','ledger_entries','contribution_posting_snapshots'] LOOP
 EXECUTE format('CREATE TRIGGER fixture_financial_guard BEFORE INSERT ON app.%I FOR EACH STATEMENT EXECUTE FUNCTION private.fixture_financial_guard()',n);
 EXECUTE format('ALTER TABLE app.%I ENABLE ALWAYS TRIGGER fixture_financial_guard',n);
 END LOOP;END;$triggers$;
GRANT USAGE ON SCHEMA src,app,auth,private TO fixture_operator;
-- Broad privileges intentionally support the disposable fixture only.
GRANT SELECT,UPDATE ON ALL TABLES IN SCHEMA src,app,auth,private TO fixture_operator;
GRANT INSERT ON app.payment_evidence,app.payments,app.momo_financial_links,app.ledger_entries,app.contribution_posting_snapshots,private.fixture_financial_receipts TO fixture_operator;
