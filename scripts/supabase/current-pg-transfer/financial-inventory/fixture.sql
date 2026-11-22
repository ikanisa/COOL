-- Synthetic, intentionally incomplete tables: never install in a real database.
CREATE SCHEMA app; CREATE SCHEMA auth; CREATE SCHEMA private; CREATE SCHEMA storage;
CREATE TABLE app.users(id text);
CREATE TABLE auth.users(id text);
CREATE TABLE private.auth_principal_links(user_id text);
CREATE TABLE app.collections(id text);
CREATE TABLE app.memberships(id text);
CREATE TABLE app.sms_receipts(id text,owner_user_id text,body_sha256 text,object_key text,object_sha256 text);
CREATE TABLE app.momo_transactions(id text,amount_minor bigint,currency text);
CREATE TABLE app.momo_transaction_sources(transaction_id text,raw_sms_id text,parse_attempt_id text);
CREATE TABLE app.momo_parse_attempts(id text,raw_sms_id text,source_body_sha256 text);
CREATE TABLE private.burimunsi_native_receipt_origins(source_id text,body_sha256 text,object_sha256 text);
CREATE TABLE app.payment_evidence(id text,collection_id text,owner_user_id text,object_key text,object_sha256 text,amount_minor bigint,currency text);
CREATE TABLE app.payment_intents(id text);
CREATE TABLE app.payments(id text,collection_id text,member_id text,evidence_id text,intent_id text,amount_minor bigint,currency text);
CREATE TABLE app.momo_financial_links(transaction_id text,payment_id text,beneficiary_member_id text,linked_by text);
CREATE TABLE app.ledger_entries(id text,payment_id text,collection_id text,member_id text,currency text,amount_minor bigint,kind text,evidence_id text,actor_user_id text);
CREATE TABLE app.contribution_posting_snapshots(ledger_entry_id text,payment_id text);
CREATE TABLE private.storage_objects(object_key text,scope jsonb,custom_metadata jsonb,sha256 text);
CREATE TABLE private.storage_payload_reservations(object_key text,scope jsonb,aad text,plaintext_sha256 text);
CREATE TABLE private.storage_namespace(singleton boolean,bucket text);
CREATE TABLE storage.objects(bucket_id text,name text,archived_at timestamptz,is_delete_marker boolean);
CREATE TABLE private.collect_fence_control(singleton boolean,mode text,epoch bigint);
CREATE TABLE private.collect_fence_admissions(state text);

INSERT INTO app.users VALUES('private-fixture-owner'),('private-fixture-member');
INSERT INTO auth.users VALUES('private-fixture-auth');
INSERT INTO private.auth_principal_links VALUES('private-fixture-owner');
INSERT INTO app.collections VALUES('private-fixture-collection');
INSERT INTO app.memberships VALUES('private-fixture-membership');
INSERT INTO app.sms_receipts VALUES('private-fixture-sms','private-fixture-owner','body-hash','sms/object','plaintext-sms-hash');
INSERT INTO app.momo_transactions VALUES('private-fixture-txn',1250,'RWF');
INSERT INTO app.momo_transaction_sources VALUES('private-fixture-txn','private-fixture-sms','private-fixture-attempt');
INSERT INTO app.momo_parse_attempts VALUES('private-fixture-attempt','private-fixture-sms','body-hash');
INSERT INTO private.burimunsi_native_receipt_origins VALUES('private-fixture-sms','body-hash','plaintext-sms-hash');
INSERT INTO app.payment_evidence VALUES('private-fixture-evidence','private-fixture-collection','private-fixture-owner','evidence/object','plaintext-evidence-hash',1250,'RWF');
INSERT INTO app.payments VALUES('private-fixture-payment','private-fixture-collection','private-fixture-member','private-fixture-evidence',NULL,1250,'RWF');
INSERT INTO app.momo_financial_links VALUES('private-fixture-txn','private-fixture-payment','private-fixture-member','private-fixture-owner');
INSERT INTO app.ledger_entries VALUES('private-fixture-ledger','private-fixture-payment','private-fixture-collection','private-fixture-member','RWF',1250,'contribution','private-fixture-evidence','private-fixture-owner');
INSERT INTO app.contribution_posting_snapshots VALUES('private-fixture-ledger','private-fixture-payment');
INSERT INTO private.storage_objects VALUES
 ('sms/object','{"ownerId":"private-fixture-owner","entityId":"private-fixture-sms","purpose":"sms_receipt"}','{"sha256":"plaintext-sms-hash"}','different-ciphertext-hash'),
 ('evidence/object','{"ownerId":"private-fixture-owner","entityId":"private-fixture-evidence","purpose":"payment_evidence"}','{"sha256":"plaintext-evidence-hash"}','different-ciphertext-hash');
INSERT INTO private.storage_payload_reservations VALUES
 ('sms/object','{"ownerId":"private-fixture-owner","entityId":"private-fixture-sms","purpose":"sms_receipt"}','sms:private-fixture-sms:plaintext-sms-hash','plaintext-sms-hash'),
 ('evidence/object','{"ownerId":"private-fixture-owner","entityId":"private-fixture-evidence","purpose":"payment_evidence"}','evidence:private-fixture-evidence:plaintext-evidence-hash','plaintext-evidence-hash');
INSERT INTO private.storage_namespace VALUES(true,'private-fixture-bucket');
INSERT INTO storage.objects VALUES('private-fixture-bucket','sms/object',NULL,false),('private-fixture-bucket','evidence/object',NULL,false);
INSERT INTO private.collect_fence_control VALUES(true,'open',3);
INSERT INTO private.collect_fence_admissions VALUES('settled'),('active');
