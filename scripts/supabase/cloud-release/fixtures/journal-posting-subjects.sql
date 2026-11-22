-- Synthetic, disposable PostgreSQL only. The fixture seeds recorded graph
-- edges (including deliberately inconsistent references) while fenced.
CREATE TEMP TABLE fixture_journal_postings (
  n integer,tenant text,payer text,actor text,allocator text,evidence_owner text,capture text,relation text
) ON COMMIT DROP;
INSERT INTO fixture_journal_postings VALUES
 (1,'rt-group-a','rt-payer','rt-capture','rt-capture','rt-capture','rt-capture','accepted'),
 (2,'rt-group-b','rt-other-payer','rt-other-actor','rt-other-actor','rt-other-actor','rt-other-actor','accepted'),
 (3,'rt-group-duplicate','rt-dup-payer','rt-actor','rt-allocator','rt-owner','rt-dup-capture','duplicate'),
 (4,'rt-group-cross','rt-cross-payer','rt-cross-actor','rt-cross-actor','rt-cross-actor','rt-cross-actor','accepted'),
 (5,'rt-group-page','rt-page-payer','rt-page','rt-page','rt-page','rt-page','accepted');

INSERT INTO app.collections(id,slug,creator_user_id,title,collection_type,created_at,updated_at)
 SELECT tenant,tenant,'synthetic-primary','Fixture collection','community','2026-11-01','2026-11-01'
 FROM fixture_journal_postings;

INSERT INTO private.burimunsi_accounts
 (id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
 SELECT md5('rt-account-'||n)::uuid,tenant,capture,'+25078007000'||n,'Fixture operator','admin',ARRAY['records.read','sms.read','gateway.manage'],'{}',1,1
 FROM fixture_journal_postings;
INSERT INTO private.burimunsi_native_receipt_origins
 (source_id,collection_id,account_id,principal_user_id,installation_id,grant_id,grant_version,capture_session_id,
  admission_kind,request_id,fingerprint,body_sha256,object_sha256)
 SELECT md5('rt-source-'||n)::uuid::text,tenant,md5('rt-account-'||n)::uuid,capture,gen_random_uuid(),gen_random_uuid(),1,
  gen_random_uuid(),'jobs',gen_random_uuid(),repeat('a',64),repeat('b',64),repeat('c',64)
 FROM fixture_journal_postings;
INSERT INTO app.momo_transactions
 (id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,currency_scale,
  transaction_timezone,transaction_time_source,parse_attempt_id,mode,allocation_state,payer_name,payer_identifier,created_at,updated_at)
 SELECT 'rt-tx-'||n,'rt-wallet-'||n,'fixture','rt-reference-'||n,'incoming_receipt',100,'RWF',0,'Africa/Kigali',
  'sms_body_and_provider_profile',md5('rt-parse-'||n)::uuid::text,'live','linked','rt-name-only','+250780070099','2026-11-01','2026-11-01'
 FROM fixture_journal_postings;
INSERT INTO app.momo_transaction_sources(transaction_id,raw_sms_id,parse_attempt_id,relation,created_at)
 SELECT 'rt-tx-'||n,md5('rt-source-'||n)::uuid::text,md5('rt-parse-'||n)::uuid::text,relation,'2026-11-01'
 FROM fixture_journal_postings;
INSERT INTO private.burimunsi_auto_sms_jobs
 (source_id,collection_id,receiving_account_id,source_fingerprint,profile_sha256,state,phase,attempt_id,
  transaction_id,facts_sha256,relation,payment_outcome,created_at,updated_at)
 SELECT md5('rt-source-'||n)::uuid::text,tenant,'rt-wallet-'||n,repeat('a',64),repeat('b',64),'completed','finished',
  md5('rt-parse-'||n)::uuid,'rt-tx-'||n,repeat('c',64),relation,'successful',1,1 FROM fixture_journal_postings;
INSERT INTO app.payment_evidence
 (id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,observed_at,created_at)
 SELECT 'rt-evidence-'||n,tenant,evidence_owner,'rt-object-'||n,repeat('a',64),12,'text/plain','operator_recorded',
 '2026-11-01','2026-11-01' FROM fixture_journal_postings;
INSERT INTO app.payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at)
 SELECT 'rt-payment-'||n,tenant,payer,'rt-evidence-'||n,100,'reconciled','2026-11-01' FROM fixture_journal_postings;
INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at)
 SELECT 'rt-ledger-'||n,'rt-payment-'||n,tenant,payer,100,'contribution','rt-evidence-'||n,actor,gen_random_uuid(),'2026-11-01'
 FROM fixture_journal_postings;
INSERT INTO app.contribution_posting_snapshots(ledger_entry_id,payment_id,member_balance_after_minor,group_balance_after_minor,posted_at)
 SELECT 'rt-ledger-'||n,'rt-payment-'||n,100,100,'2026-11-01' FROM fixture_journal_postings;
INSERT INTO app.momo_financial_links(transaction_id,payment_id,beneficiary_member_id,linked_by,reason,created_at)
 SELECT 'rt-tx-'||n,'rt-payment-'||n,payer,allocator,'Synthetic immutable link','2026-11-01' FROM fixture_journal_postings;
INSERT INTO private.burimunsi_observation_retry_commands(request_id,source_id,collection_id,account_id,result,created_at)
 SELECT md5('rt-journal-'||n)::uuid,md5('rt-source-'||n)::uuid::text,tenant,md5('rt-account-'||n)::uuid,'scheduled',1
 FROM fixture_journal_postings;
INSERT INTO private.burimunsi_observation_retry_commands(request_id,source_id,collection_id,account_id,result,created_at) VALUES
 (md5('rt-foreign-collection')::uuid,md5('rt-source-1')::uuid::text,'rt-group-b',md5('rt-account-1')::uuid,'scheduled',1),
 (md5('rt-foreign-account')::uuid,md5('rt-source-1')::uuid::text,'rt-group-a',md5('rt-account-2')::uuid,'scheduled',1),
 (md5('rt-ineligible')::uuid,md5('rt-source-1')::uuid::text,'rt-group-a',md5('rt-account-1')::uuid,'not_eligible',1);
-- More than 100 role associations, including a record that straddles the
-- response limit. The same capture principal also owns the base retry.
INSERT INTO private.burimunsi_observation_retry_commands(request_id,source_id,collection_id,account_id,result,created_at)
 SELECT md5('rt-limit-'||n)::uuid,md5('rt-source-5')::uuid::text,'rt-group-page',md5('rt-account-5')::uuid,'scheduled',1
 FROM generate_series(1,25) n;
INSERT INTO private.burimunsi_observation_retry_commands(request_id,source_id,collection_id,account_id,result,created_at)
 VALUES ('00000000-0000-4000-8000-000000000001',md5('rt-source-5')::uuid::text,'rt-group-page',md5('rt-account-5')::uuid,'not_eligible',1);
INSERT INTO private.burimunsi_payment_sms_deliveries
 (attempt_id,collection_id,payment_id,ledger_entry_id,event_id,recipient_user_id,destination_sha256,amount_rwf,
  member_balance_rwf,group_name,posted_at,enabled_at,application_id,message_id,idempotency_key,not_after,next_inspect_at)
 SELECT md5('rt-journal-'||n)::uuid,CASE WHEN n=4 THEN 'rt-group-b' ELSE tenant END,'rt-payment-'||n,
  'rt-ledger-'||n,'rt-event-'||n,payer,encode(sha256(convert_to('+250780070099','UTF8')),'hex'),100,100,'rt-name-only',now(),now(),'fixture',
  'rt-message-'||n,'rt-intent-'||n,now(),now() FROM fixture_journal_postings;
