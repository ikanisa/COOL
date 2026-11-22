-- Invented, intentionally incomplete schema for an owned disposable database only.
CREATE SCHEMA app; CREATE SCHEMA private;
CREATE TABLE app.payments(id text,evidence_id text,collection_id text,member_id text,amount_minor bigint,currency text);
CREATE TABLE app.payment_evidence(id text,owner_user_id text,collection_id text,amount_minor bigint,currency text,object_key text,object_sha256 text,external_reference text);
CREATE TABLE app.ledger_entries(id text,payment_id text,collection_id text,member_id text,amount_minor bigint,currency text,kind text,posted_at text,evidence_id text);
CREATE TABLE app.contribution_posting_snapshots(ledger_entry_id text,payment_id text,member_balance_after_minor bigint,group_balance_after_minor bigint,posted_at text);
CREATE TABLE app.momo_financial_links(payment_id text,transaction_id text,beneficiary_member_id text);
CREATE TABLE app.momo_transactions(id text,amount_minor bigint,currency text,event_kind text,parse_attempt_id text,receiving_account_id text);
CREATE TABLE app.momo_transaction_sources(transaction_id text,raw_sms_id text,parse_attempt_id text,relation text);
CREATE TABLE app.momo_parse_attempts(id text,raw_sms_id text,source_body_sha256 text);
CREATE TABLE app.sms_receipts(id text,owner_user_id text,body_sha256 text);
CREATE TABLE private.burimunsi_auto_sms_jobs(source_id text,transaction_id text,collection_id text,state text,payment_outcome text,attempt_id uuid,receiving_account_id text,relation text);

INSERT INTO app.payments VALUES
 ('private-payment-a','private-evidence-a','private-group','private-member-a',10,'RWF'),
 ('private-payment-b','private-evidence-b','private-group','private-member-b',20,'RWF'),
 ('private-payment-c','private-evidence-c','private-group','private-member-a',30,'RWF');
INSERT INTO app.ledger_entries VALUES
 ('private-ledger-a','private-payment-a','private-group','private-member-a',10,'RWF','contribution','2026-01-01T00:00:00.000Z','private-evidence-a'),
 ('private-ledger-b','private-payment-b','private-group','private-member-b',20,'RWF','contribution','2026-01-01T00:00:01.000Z','private-evidence-b'),
 ('private-ledger-c','private-payment-c','private-group','private-member-a',30,'RWF','contribution','2026-01-01T00:00:02.000Z','private-evidence-c');
INSERT INTO app.contribution_posting_snapshots VALUES
 ('private-ledger-a','private-payment-a',10,10,'2026-01-01T00:00:00.000Z'),
 ('private-ledger-b','private-payment-b',20,30,'2026-01-01T00:00:01.000Z'),
 ('private-ledger-c','private-payment-c',40,60,'2026-01-01T00:00:02.000Z');
INSERT INTO app.sms_receipts VALUES
 ('private-sms-a','private-owner',repeat('a',64)),('private-sms-b','private-owner',repeat('b',64)),('private-sms-c','private-owner',repeat('c',64));
INSERT INTO app.payment_evidence VALUES
 ('private-evidence-a','private-owner','private-group',10,'RWF','evidence/private-evidence-a',repeat('a',64),'sms:'||repeat('a',64)||':private-sms-a'),
 ('private-evidence-b','private-owner','private-group',20,'RWF','evidence/private-evidence-b',repeat('b',64),'sms:'||repeat('b',64)||':private-sms-b'),
 ('private-evidence-c','private-owner','private-group',30,'RWF','evidence/private-evidence-c',repeat('c',64),'sms:'||repeat('c',64)||':private-sms-c');
INSERT INTO app.momo_financial_links VALUES
 ('private-payment-a','private-transaction-a','private-member-a'),
 ('private-payment-b','private-transaction-b','private-member-b'),
 ('private-payment-c','private-transaction-c','private-member-a');
INSERT INTO app.momo_transactions VALUES
 ('private-transaction-a',10,'RWF','incoming_receipt','00000000-0000-0000-0000-000000000001','private-account'),
 ('private-transaction-b',20,'RWF','incoming_receipt','00000000-0000-0000-0000-000000000002','private-account'),
 ('private-transaction-c',30,'RWF','incoming_receipt','00000000-0000-0000-0000-000000000003','private-account');
INSERT INTO app.momo_transaction_sources VALUES
 ('private-transaction-a','private-sms-a','00000000-0000-0000-0000-000000000001','accepted'),
 ('private-transaction-b','private-sms-b','00000000-0000-0000-0000-000000000002','accepted'),
 ('private-transaction-c','private-sms-c','00000000-0000-0000-0000-000000000003','accepted');
INSERT INTO app.momo_parse_attempts VALUES
 ('00000000-0000-0000-0000-000000000001','private-sms-a',repeat('a',64)),
 ('00000000-0000-0000-0000-000000000002','private-sms-b',repeat('b',64)),
 ('00000000-0000-0000-0000-000000000003','private-sms-c',repeat('c',64));
INSERT INTO private.burimunsi_auto_sms_jobs VALUES
 ('private-sms-a','private-transaction-a','private-group','completed','successful','00000000-0000-0000-0000-000000000001','private-account','accepted'),
 ('private-sms-b','private-transaction-b','private-group','completed','successful','00000000-0000-0000-0000-000000000002','private-account','accepted'),
 ('private-sms-c','private-transaction-c','private-group','completed','successful','00000000-0000-0000-0000-000000000003','private-account','accepted');
