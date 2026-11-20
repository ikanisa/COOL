-- Disposable PostgreSQL qualification only. The harness supplies the existing
-- real fenced source/storage fixtures and the exact SQL emitted by the current
-- PostgresRecordsStore. All identifiers and payment facts below are synthetic;
-- this contract rolls back and never invokes a provider or financial writer.
__SOURCE_SETUP__
__FINANCIAL_STORAGE_HELPER__
SELECT pg_temp.source_capture('source-contract-complete-a','source-contract-credential-a','complete','live');
INSERT INTO app.users(id,public_id,full_name,momo_number,member_type,created_at,updated_at) VALUES
 ('f3000000-0000-4000-8000-000000000011','900011','Alice Member','0780000011','direct',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('f3000000-0000-4000-8000-000000000012','900012','Bob Member','0780000012','direct',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('f3000000-0000-4000-8000-000000000013','900013','Charlie Other','0780000013','direct',app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.memberships(id,collection_id,user_id,joined_at) VALUES
 ('query-membership-a','buri-qualification-group','f3000000-0000-4000-8000-000000000011',app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('query-membership-b','buri-qualification-group','f3000000-0000-4000-8000-000000000012',app.strftime('%Y-%m-%dT%H:%M:%fZ')),
 ('query-membership-c','buri-qualification-group-2','f3000000-0000-4000-8000-000000000013',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
CREATE FUNCTION pg_temp.query_fixture(n integer,g text,payer text,payer_phone text,member_id text,payment_member text,
 payment_status text,alloc text,conflict bigint,p_at text DEFAULT '2026-11-11T10:00:00Z',p_timezone text DEFAULT 'Africa/Kigali') RETURNS void LANGUAGE plpgsql AS $fn$
DECLARE tx text:='query-tx-'||n;attempt text:='query-attempt-'||n;evidence text:='query-evidence-'||n;
 source_hash text;binding text:=CASE WHEN g='buri-qualification-group' THEN 'source-contract-binding-a' ELSE 'source-contract-binding-b' END;
BEGIN
 PERFORM set_config('burimunsi.collection_id',g,true);
 SELECT body_sha256 INTO STRICT source_hash FROM app.sms_receipts WHERE id='source-contract-complete-a';
 INSERT INTO app.momo_parse_attempts(id,raw_sms_id,attempt_number,model_id,schema_version,prompt_version,parser_version,
  profile_version,profile_json,source_body_sha256,validation_json,outcome,created_at)
 VALUES(attempt,'source-contract-complete-a',n,'fixture','fixture','fixture','fixture','fixture','{}',source_hash,'[]','accepted',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 INSERT INTO app.momo_transactions(id,receiving_account_id,provider,provider_transaction_id,event_kind,amount_minor,currency,currency_scale,
  payer_name,payer_identifier,transaction_at,transaction_datetime_raw,transaction_timezone,transaction_time_source,parse_attempt_id,mode,
  allocation_state,has_conflict,created_at,updated_at)
 VALUES(tx,'buri-qualification-wallet','mtn_momo','QUALIFICATION-'||n,'incoming_receipt',n*11000,'RWF',0,payer,payer_phone,
  p_at,'2026-11-11 12:00:00',p_timezone,'provider_sms',attempt,'live',alloc,conflict,
  app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 INSERT INTO private.burimunsi_transaction_scopes(transaction_id,collection_id,receiving_account_id,source_binding_id,source_binding_version,policy_version,created_at)
 VALUES(tx,g,'buri-qualification-wallet',binding,1,'fixture',1);
 IF payment_status IS NOT NULL THEN
  PERFORM pg_temp.h_seed_financial_storage('evidence/'||evidence,'f3000000-0000-4000-8000-000000000001',evidence,source_hash,'payment_evidence');
  INSERT INTO app.payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,
   receiver_momo_number,receiver_network,amount_minor,observed_at,created_at)
  VALUES(evidence,g,'f3000000-0000-4000-8000-000000000001','evidence/'||evidence,source_hash,12,'text/plain','operator_recorded',tx,
   '00000','mtn_momo',n*11000,app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
  INSERT INTO app.payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at)
  VALUES('query-payment-'||n,g,payment_member,evidence,n*11000,payment_status,app.strftime('%Y-%m-%dT%H:%M:%fZ'));
  INSERT INTO app.momo_financial_links(transaction_id,payment_id,beneficiary_member_id,linked_by,reason,created_at)
  VALUES(tx,'query-payment-'||n,member_id,'f3000000-0000-4000-8000-000000000001','synthetic query qualification',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
 END IF;
END;$fn$;
SELECT pg_temp.query_fixture(1,'buri-qualification-group','Origin Alice','***111','f3000000-0000-4000-8000-000000000011','f3000000-0000-4000-8000-000000000011','reconciled','linked',0);
SELECT pg_temp.query_fixture(2,'buri-qualification-group','Literal 100%','***222','f3000000-0000-4000-8000-000000000011',NULL,'recorded','linked',0);
SELECT pg_temp.query_fixture(3,'buri-qualification-group','Conflict','***333','f3000000-0000-4000-8000-000000000012','f3000000-0000-4000-8000-000000000012','reconciled','linked',1);
SELECT pg_temp.query_fixture(4,'buri-qualification-group','No member','***444',NULL,NULL,NULL,'unallocated',0);
SELECT pg_temp.query_fixture(5,'buri-qualification-group-2','Other group','***555','f3000000-0000-4000-8000-000000000013','f3000000-0000-4000-8000-000000000013','reconciled','linked',0);
SELECT pg_temp.query_fixture(6,'buri-qualification-group','Literal _ marker','***666','f3000000-0000-4000-8000-000000000012','f3000000-0000-4000-8000-000000000012','confirmed','linked',0);
SELECT pg_temp.query_fixture(7,'buri-qualification-group','Inconsistent posted','***777','f3000000-0000-4000-8000-000000000012','f3000000-0000-4000-8000-000000000012','confirmed','unallocated',0);
SELECT pg_temp.query_fixture(8,'buri-qualification-group','Inconsistent reversed','***888','f3000000-0000-4000-8000-000000000012','f3000000-0000-4000-8000-000000000012','reversed','unallocated',0);
SELECT pg_temp.query_fixture(20,'buri-qualification-group','Pending contribution','***999','f3000000-0000-4000-8000-000000000011','f3000000-0000-4000-8000-000000000011','confirmed','linked',0);
SELECT pg_temp.query_fixture(21,'buri-qualification-group','Partial contribution','***999','f3000000-0000-4000-8000-000000000011','f3000000-0000-4000-8000-000000000011','confirmed','linked',0);
SELECT pg_temp.query_fixture(22,'buri-qualification-group','Wrong beneficiary','***999','f3000000-0000-4000-8000-000000000011','f3000000-0000-4000-8000-000000000011','confirmed','linked',0);
SELECT pg_temp.query_fixture(23,'buri-qualification-group','Cross-group member','***999','f3000000-0000-4000-8000-000000000013','f3000000-0000-4000-8000-000000000013','confirmed','linked',0);
__BASE_LEDGER__
SET LOCAL ROLE collect_runtime;
SELECT set_config('burimunsi.collection_id','buri-qualification-group',true);
SELECT private.collect_fence_assert_write('__ADMISSION_ID__'::uuid,__ADMISSION_EPOCH__::bigint,'__ADMISSION_SOURCE__');
__QUERY_ASSERTIONS__
__HOME_ASSERTIONS__
ROLLBACK;
