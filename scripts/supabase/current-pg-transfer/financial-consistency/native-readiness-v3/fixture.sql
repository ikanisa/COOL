-- Invented, intentionally partial schema for an owned disposable cluster only.
CREATE SCHEMA app; CREATE SCHEMA private;
CREATE TABLE app.sms_receipts(id text,body_sha256 text);
CREATE TABLE app.momo_transaction_sources(transaction_id text,raw_sms_id text,parse_attempt_id text,relation text);
CREATE TABLE app.momo_transactions(id text,parse_attempt_id text,receiving_account_id text,has_conflict bigint,allocation_state text,event_kind text,currency text,mode text,amount_minor bigint);
CREATE TABLE app.momo_parse_attempts(id text,raw_sms_id text,source_body_sha256 text);
CREATE TABLE app.momo_financial_links(transaction_id text,payment_id text);
CREATE TABLE private.burimunsi_native_receipt_origins(source_id text,fingerprint text,body_sha256 text);
CREATE TABLE private.burimunsi_auto_sms_jobs(source_id text,transaction_id text,source_fingerprint text,relation text,state text,payment_outcome text,attempt_id uuid,receiving_account_id text,posting_facts jsonb);
INSERT INTO app.sms_receipts VALUES('10000000-0000-4000-8000-000000000001',repeat('a',64)),('10000000-0000-4000-8000-000000000002',repeat('b',64));
INSERT INTO app.momo_transaction_sources VALUES
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000001','accepted'),
 ('10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000002','accepted');
INSERT INTO app.momo_transactions VALUES
 ('10000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000001','private-account',0,'linked','incoming_receipt','RWF','live',10),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000002','private-account',0,'linked','incoming_receipt','RWF','historical',20);
INSERT INTO app.momo_parse_attempts VALUES
 ('00000000-0000-0000-0000-000000000001','10000000-0000-4000-8000-000000000001',repeat('a',64)),
 ('00000000-0000-0000-0000-000000000002','10000000-0000-4000-8000-000000000002',repeat('b',64));
INSERT INTO app.momo_financial_links VALUES('10000000-0000-4000-8000-000000000001','private-payment-a'),('10000000-0000-4000-8000-000000000002','private-payment-b');
INSERT INTO private.burimunsi_native_receipt_origins VALUES
 ('10000000-0000-4000-8000-000000000001',repeat('c',64),repeat('a',64)),('10000000-0000-4000-8000-000000000002',repeat('d',64),repeat('b',64));
INSERT INTO private.burimunsi_auto_sms_jobs VALUES
 ('10000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',repeat('c',64),'accepted','completed','successful','00000000-0000-0000-0000-000000000001','private-account',
  '{"event_kind":"incoming_receipt","payment_outcome":"successful","currency":"RWF","amount_minor":10,"source_mode":"live","wallet_balance_after_minor":0}'),
 ('10000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000002',repeat('d',64),'accepted','completed','successful','00000000-0000-0000-0000-000000000002','private-account',
  '{"event_kind":"incoming_receipt","payment_outcome":"successful","currency":"RWF","amount_minor":20,"source_mode":"catch_up","wallet_balance_after_minor":30}');
