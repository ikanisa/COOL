-- Actual SQL/RLS qualification on the disposable schema33 copy. Effects roll
-- back. Not a provider, handset/SIM or external acknowledgement acceptance.
BEGIN;
SET LOCAL search_path=app,pg_catalog;
SELECT set_config('collect.edge_verified','true',true),set_config('burimunsi.collection_id','buri-qualification-group',true),
 set_config('collect.fence_admission_id','__ADMISSION_ID__',true),set_config('collect.fence_epoch','__ADMISSION_EPOCH__',true),
 set_config('collect.fence_source_sha256','__ADMISSION_SOURCE__',true);
__NATIVE_PAIR_INPUTS__
__HANDOFF_SUPPORT__
-- Runtime has only the bounded public helpers, never the internal Owner or
-- commit primitive. Actor/scope GUCs do not confer target authority.
DO $acl$ DECLARE f text;r text;t text;BEGIN
 FOREACH t IN ARRAY ARRAY['burimunsi_gateway_handoffs','burimunsi_gateway_pair_targets','burimunsi_gateway_retirements'] LOOP
  PERFORM pg_temp.h_check(EXISTS(SELECT 1 FROM pg_class WHERE oid=('private.'||t)::regclass AND relrowsecurity AND relforcerowsecurity),'force RLS '||t);
  PERFORM pg_temp.h_check(EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid=('private.'||t)::regclass AND tgname='collect_fence_statement_v1' AND tgenabled='A'),'always fence '||t);
  PERFORM pg_temp.h_check(NOT has_table_privilege('collect_runtime','private.'||t,'INSERT,UPDATE,DELETE,TRUNCATE'),'metadata owner writes '||t);
 END LOOP;
 FOREACH f IN ARRAY ARRAY['private.burimunsi_gateway_commit_handoff(uuid,text,uuid)','private.burimunsi_gateway_admin_handoff(jsonb,jsonb,text,jsonb)',
 'private.burimunsi_gateway_lock_target(text,uuid,uuid,uuid,bigint)','private.burimunsi_gateway_target_snapshot(text,uuid,uuid,uuid,bigint)'] LOOP
  PERFORM pg_temp.h_check(NOT has_function_privilege('collect_runtime',f,'EXECUTE'),'internal helper denied '||f);
 END LOOP;
 FOREACH f IN ARRAY ARRAY['private.burimunsi_gateway_retire(text,text,uuid,text)','private.burimunsi_gateway_retirement_outcome(text,uuid,text,text,uuid,text)','private.burimunsi_gateway_pair_target(text,uuid)'] LOOP
  PERFORM pg_temp.h_check(has_function_privilege('collect_runtime',f,'EXECUTE'),'runtime narrow helper '||f);
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role','collect_importer'] LOOP
   PERFORM pg_temp.h_check(NOT has_function_privilege(r,f,'EXECUTE'),'private helper ACL '||f||r);
  END LOOP;
 END LOOP;
END;$acl$;
SELECT pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',
 pg_temp.h_raw('old-device'),'internal_receiver','fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))->>'state'='unknown','missing original outcome is unknown only');
SAVEPOINT wrong_code;
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('wrong-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('wrong-code','fd332000-0000-4000-8000-000000000001'))$q$,'42501');
ROLLBACK TO wrong_code;
SAVEPOINT wrong_fingerprint;
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),
 'fd332000-0000-4000-8000-000000000001',repeat('0',64))$q$,'23505');
ROLLBACK TO wrong_fingerprint;
SAVEPOINT target_not_old;
SELECT pg_temp.h_set('new-current','fd330000-0000-4000-8000-000000000002','new-device');
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'42501');
ROLLBACK TO target_not_old;
SAVEPOINT sibling_not_custodian;
SELECT pg_temp.h_set('sibling-current','fd330000-0000-4000-8000-000000000001','old-device');
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'42501');
ROLLBACK TO sibling_not_custodian;
SAVEPOINT target_changed;
SELECT pg_temp.h_owner();RESET ROLE;
UPDATE private.burimunsi_device_grants SET active=false,version=version+1 WHERE installation_id='fd330000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_set('old-current','fd330000-0000-4000-8000-000000000001','old-device');
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'40001');
ROLLBACK TO target_changed;
SAVEPOINT target_registration_proof_revoked;
RESET ROLE;
UPDATE private.burimunsi_sessions SET revoked=true WHERE installation_id='fd330000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_check(jsonb_array_length(pg_temp.h_directory()->'installations')=1,'NULL custody without recent current registration is hidden');
SELECT pg_temp.h_set('old-current','fd330000-0000-4000-8000-000000000001','old-device');
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'40001');
ROLLBACK TO target_registration_proof_revoked;
SAVEPOINT source_cas_changed;
SELECT pg_temp.h_owner();RESET ROLE;
UPDATE app.momo_gateway_credentials SET token_sha256=pg_temp.h_raw('changed-key') WHERE id='handoff-old-key';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_set('old-current','fd330000-0000-4000-8000-000000000001','old-device');
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'40001');
ROLLBACK TO source_cas_changed;
SAVEPOINT pending_queue;
RESET ROLE;
UPDATE app.momo_gateway_credentials SET pending_count=1 WHERE id='handoff-old-key';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'55000');
ROLLBACK TO pending_queue;
SAVEPOINT unresolved_storage;
RESET ROLE;
INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata,upload_unresolved)
 VALUES('handoff-unknown-sms-upload','handoff-unknown-sms-object',repeat('1',64),repeat('2',64),1,
 '{"ownerId":"f3000000-0000-4000-8000-000000000001","purpose":"sms_receipt"}','{}','{}',true);
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'55000');
ROLLBACK TO unresolved_storage;
-- Uploaded immutable capture/source association is already committed to SQL
-- storage. Local/device pending_count=0 does not settle server processing.
SAVEPOINT uploaded_server_work;
RESET ROLE;
SELECT pg_temp.h_capture('handoff-pending-upload','handoff-old-key','complete','live');
INSERT INTO app.momo_processing_jobs(raw_sms_id,binding_id,binding_version,receiving_account_id,mode,state,available_at,created_at,updated_at)
 VALUES('handoff-pending-upload','handoff-old-binding',1,'buri-qualification-wallet','live','pending',app.unixepoch(),app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT pg_temp.h_check(EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes WHERE source_id='handoff-pending-upload' AND binding_id='handoff-old-binding'),'actual immutable uploaded source association');
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'55000');
RESET ROLE;
UPDATE app.momo_processing_jobs SET state='completed' WHERE raw_sms_id='handoff-pending-upload';
INSERT INTO private.burimunsi_receipt_jobs(id,collection_id,source_id,source_sha256,binding_id,binding_version,receiving_account_id,profile_version,next_attempt_at,created_at,updated_at)
 SELECT 'fd335000-0000-4000-8000-000000000001','buri-qualification-group',r.id,r.body_sha256,'handoff-old-binding',1,'buri-qualification-wallet','qualification-only',1,1,1
 FROM app.sms_receipts r WHERE r.id='handoff-pending-upload';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'55000');
RESET ROLE;
UPDATE private.burimunsi_receipt_jobs SET state='rejected' WHERE id='fd335000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_check(private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))->>'retired'='true','terminal rejected job remains history and does not block');
ROLLBACK TO uploaded_server_work;
SAVEPOINT completed_but_unallocated;
RESET ROLE;
SELECT pg_temp.h_capture('handoff-unallocated-upload','handoff-old-key','complete','live');
SELECT pg_temp.h_transaction('handoff-unallocated-upload','handoff-unallocated-transaction');
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'55000');
-- Linked state alone, without the complete original financial posting, also
-- cannot strand the payment by retiring its source authority.
RESET ROLE;
UPDATE app.momo_transactions SET allocation_state='linked',version=version+1 WHERE id='handoff-unallocated-transaction';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'55000');
ROLLBACK TO completed_but_unallocated;
-- Reuse SQL02/native history's declared synthetic financial-storage and
-- contribution shape. Shipping triggers stay enabled; this tests the barrier's
-- real RLS traversal, not actual provider evidence or the financial writer.
SAVEPOINT populated_settled_history;
RESET ROLE;
SELECT pg_temp.h_owner();
SELECT pg_temp.h_capture('handoff-settled-upload','handoff-old-key','complete','live');
SELECT pg_temp.h_transaction('handoff-settled-upload','handoff-settled-transaction');
INSERT INTO app.memberships(id,collection_id,user_id,role,joined_at)
 VALUES('fd336000-0000-4000-8000-000000000001','buri-qualification-group','f3000000-0000-4000-8000-000000000002','member',app.strftime('%Y-%m-%dT%H:%M:%fZ'))
 ON CONFLICT(collection_id,user_id) DO NOTHING;
SELECT pg_temp.h_seed_financial_storage('evidence/handoff-settled-evidence','f3000000-0000-4000-8000-000000000001','handoff-settled-evidence',
 (SELECT body_sha256 FROM app.sms_receipts WHERE id='handoff-settled-upload'),'payment_evidence');
INSERT INTO app.payment_evidence(id,collection_id,owner_user_id,object_key,object_sha256,size_bytes,content_type,authenticity,external_reference,
 receiver_momo_number,receiver_network,amount_minor,observed_at,created_at)
 SELECT 'handoff-settled-evidence','buri-qualification-group','f3000000-0000-4000-8000-000000000001','evidence/handoff-settled-evidence',body_sha256,12,
 'text/plain','operator_recorded','handoff-settled-transaction','00000','mtn_momo',100,app.strftime('%Y-%m-%dT%H:%M:%fZ'),app.strftime('%Y-%m-%dT%H:%M:%fZ')
 FROM app.sms_receipts WHERE id='handoff-settled-upload';
INSERT INTO app.payments(id,collection_id,member_id,evidence_id,amount_minor,status,created_at)
 VALUES('handoff-settled-payment','buri-qualification-group','f3000000-0000-4000-8000-000000000002','handoff-settled-evidence',100,'reconciled',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.momo_financial_links(transaction_id,payment_id,beneficiary_member_id,linked_by,reason,created_at)
 VALUES('handoff-settled-transaction','handoff-settled-payment','f3000000-0000-4000-8000-000000000002','f3000000-0000-4000-8000-000000000001',
 'QUALIFICATION existing settled contribution',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
UPDATE app.momo_transactions SET allocation_state='linked',version=version+1 WHERE id='handoff-settled-transaction';
SAVEPOINT partial_contribution;
INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at)
 VALUES('handoff-partial-entry','handoff-settled-payment','buri-qualification-group','f3000000-0000-4000-8000-000000000002',50,'contribution',
 'handoff-settled-evidence','f3000000-0000-4000-8000-000000000001','fd336000-0000-4000-8000-000000000002',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_set('old-current','fd330000-0000-4000-8000-000000000001','old-device');
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'55000');
ROLLBACK TO partial_contribution;
INSERT INTO app.ledger_entries(id,payment_id,collection_id,member_id,amount_minor,kind,evidence_id,actor_user_id,request_id,posted_at)
 VALUES('handoff-settled-entry','handoff-settled-payment','buri-qualification-group','f3000000-0000-4000-8000-000000000002',100,'contribution',
 'handoff-settled-evidence','f3000000-0000-4000-8000-000000000001','fd336000-0000-4000-8000-000000000003',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
INSERT INTO app.contribution_posting_snapshots(ledger_entry_id,payment_id,member_balance_after_minor,group_balance_after_minor,posted_at)
 SELECT id,payment_id,100,100,posted_at FROM app.ledger_entries WHERE id='handoff-settled-entry';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_set('old-current','fd330000-0000-4000-8000-000000000001','old-device');
SELECT pg_temp.h_check(private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))->>'retired'='true','actual runtime barrier allows fully settled populated source history');
RESET ROLE;
SELECT pg_temp.h_owner();
SELECT pg_temp.h_check((SELECT amount_minor=100 AND payment_id='handoff-settled-payment' FROM app.ledger_entries WHERE id='handoff-settled-entry')
 AND (SELECT amount_minor=100 AND status='reconciled' FROM app.payments WHERE id='handoff-settled-payment')
 AND (SELECT count(*) FROM app.contribution_posting_snapshots WHERE ledger_entry_id='handoff-settled-entry')=1
 AND EXISTS(SELECT 1 FROM private.burimunsi_sms_source_scopes WHERE source_id='handoff-settled-upload' AND binding_id='handoff-old-binding'),
 'settled ledger/snapshot/payment/original source rows retained after retirement');
ROLLBACK TO populated_settled_history;
SAVEPOINT rematch_obligation;
RESET ROLE;
INSERT INTO private.burimunsi_rematch_jobs(id,collection_id,receiving_account_id,member_id,request_id,cause,cutoff_at,next_attempt_at,created_at,updated_at)
 VALUES('fd335000-0000-4000-8000-000000000002','buri-qualification-group','buri-qualification-wallet','f3000000-0000-4000-8000-000000000002',
 'fd335000-0000-4000-8000-000000000003','enrollment',1,1,1,1);
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))$q$,'55000');
ROLLBACK TO rematch_obligation;
SAVEPOINT expired_handoff;
RESET ROLE;
-- Synthetic expired authorization, inserted by fixture owner (runtime cannot
-- forge one). Existing history remains intact and identity triggers stay on.
UPDATE private.burimunsi_gateway_handoffs SET state='expired' WHERE id='fd331000-0000-4000-8000-000000000002';
INSERT INTO private.burimunsi_gateway_handoffs SELECT (jsonb_populate_record(NULL::private.burimunsi_gateway_handoffs,
 to_jsonb(h)||jsonb_build_object('id','fd331000-0000-4000-8000-000000000099','state','prepared',
 'code_hash',encode(sha256(convert_to(pg_temp.h_raw('expired-code'),'UTF8')),'hex'),'target_binding_id','handoff-expired-binding',
 'target_pairing_id','handoff-expired-pairing','created_at',floor(extract(epoch FROM clock_timestamp())*1000)::bigint-2000,
 'expires_at',floor(extract(epoch FROM clock_timestamp())*1000)::bigint-1000))).* FROM private.burimunsi_gateway_handoffs h WHERE id='fd331000-0000-4000-8000-000000000002';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_expect($q$SELECT private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('expired-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('expired-code','fd332000-0000-4000-8000-000000000001'))$q$,'40001');
ROLLBACK TO expired_handoff;
-- Alternative lost-old-phone path is an actual current Shared Owner email
-- action, with a distinct truthful method and no fabricated old-phone ACK.
SAVEPOINT owner_lost;
DO $owner$ DECLARE command jsonb;r jsonb;l jsonb;BEGIN
 command:=jsonb_build_object('operation','finalize_replacement','collectionId','buri-qualification-group',
 'requestId','fd331000-0000-4000-8000-000000000003','expectedScopeVersion',2,'receivingAccountId','buri-qualification-wallet',
 'reason','QUALIFICATION old phone lost','handoffId','fd331000-0000-4000-8000-000000000002');
 r:=pg_temp.h_apply(command);
 PERFORM pg_temp.h_check((SELECT count(*) FROM jsonb_object_keys(r))=12 AND r->>'retirementMethod'='owner_lost' AND r->>'scopeVersion'='3','genuine owner lost receipt');
 PERFORM pg_temp.h_check(pg_temp.h_apply(command)=r,'owner original result lookup, no duplicate mutation');
 l:=pg_temp.h_lookup('fd331000-0000-4000-8000-000000000002',true);
 PERFORM pg_temp.h_check(l->>'phase'='retired' AND l->>'retirementRequired'='false' AND l->>'codeHash'=pg_temp.h_get('prepare-delivery')->>'codeHash','original challenge after owner lost');
 PERFORM pg_temp.h_check(pg_temp.h_lookup('fd331000-0000-4000-8000-000000000002')->'receipt'=pg_temp.h_get('prepared'),'original21 receipt immutable after finalization');
END;$owner$;
SELECT pg_temp.h_expect($q$SELECT pg_temp.h_lookup('fd331000-0000-4000-8000-000000000003',true)$q$,'41000');
SELECT pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000001',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001')) IS NULL,'owner lost never fabricates old native ACK');
ROLLBACK TO owner_lost;
SELECT pg_temp.h_set('old-current','fd330000-0000-4000-8000-000000000001','old-device');
DO $retire$ DECLARE result jsonb;recovery jsonb;BEGIN
 result:=private.burimunsi_gateway_retire('buri-qualification-group',pg_temp.h_raw('replacement-code'),'fd332000-0000-4000-8000-000000000001',
 pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'));
 INSERT INTO pg_temp.h_state VALUES('retired',result);
 PERFORM pg_temp.h_check(result=jsonb_build_object('retired',true,'handoffId','fd331000-0000-4000-8000-000000000002',
 'requestId','fd332000-0000-4000-8000-000000000001','reauthenticationRequired',true),'old phone ACK contains no target secret/identity ports');
 PERFORM pg_temp.h_check(NOT EXISTS(SELECT 1 FROM private.burimunsi_pin_context()),'normal native scope remains stale after retire');
 recovery:=private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000001',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'));
 PERFORM pg_temp.h_check(recovery->>'state'='retired' AND recovery->'ack'=result AND (SELECT count(*) FROM jsonb_object_keys(recovery))=10,'bound limited recovery after scope retirement');
END;$retire$;
-- Serial CAS one-winner: a competing Owner finalize has no remaining prepared
-- authorization; no second binding/credential may be manufactured.
SELECT pg_temp.h_expect($q$SELECT pg_temp.h_apply(jsonb_build_object('operation','finalize_replacement','collectionId','buri-qualification-group',
 'requestId','fd331000-0000-4000-8000-000000000004','expectedScopeVersion',2,'receivingAccountId','buri-qualification-wallet',
 'reason','QUALIFICATION competing owner request','handoffId','fd331000-0000-4000-8000-000000000002'))$q$,'40001');
RESET ROLE;
SELECT pg_temp.h_check((SELECT status='revoked' FROM app.momo_gateway_bindings WHERE id='handoff-old-binding')
 AND (SELECT revoked_at IS NOT NULL FROM app.momo_gateway_credentials WHERE id='handoff-old-key')
 AND (SELECT version=3 AND active_binding_id='handoff-new-binding' FROM private.burimunsi_scopes WHERE collection_id='buri-qualification-group')
 AND (SELECT count(*) FROM app.momo_gateway_bindings)=2 AND (SELECT count(*) FROM app.ledger_entries)=0,'capture retirement preserves source history and financial ledger');
SET LOCAL ROLE collect_runtime;
-- Limited recovery tolerates only expected retirement invalidations, not PIN,
-- account, principal, request or original token/device proof changes.
SELECT pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('new-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000001',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001')) IS NULL,'wrong device proof denied');
SELECT pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),
 'staff','fd332000-0000-4000-8000-000000000001',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001')) IS NULL,'wrong profile denied');
SELECT pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000001',repeat('0',64)) IS NULL,'wrong fingerprint denied');
SELECT pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000002',repeat('0',64)) IS NULL,'unknown request cannot use retired authority');
SAVEPOINT retired_grant;
RESET ROLE;
UPDATE private.burimunsi_sessions SET revoked=true WHERE token_hash=encode(sha256(convert_to(pg_temp.h_raw('old-current'),'UTF8')),'hex');
UPDATE private.burimunsi_device_grants SET active=false,version=version+1 WHERE installation_id='fd330000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000001',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001'))->>'state'='retired','exact ACK survives grant/session retirement');
ROLLBACK TO retired_grant;
SAVEPOINT pin_changed;
SELECT pg_temp.h_owner();RESET ROLE;
UPDATE private.burimunsi_accounts SET credential_version=credential_version+1,version=version+1 WHERE id='f7000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000001',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001')) IS NULL,'changed PIN/account denies even retired ACK');
ROLLBACK TO pin_changed;
SAVEPOINT original_expiry;
SELECT pg_temp.h_owner();RESET ROLE;
-- A complete immutable expired synthetic session+receipt, never an UPDATE to
-- an existing session identity. The normal runtime cannot forge these rows.
DO $expired_original$ DECLARE at_ms bigint:=floor(extract(epoch FROM clock_timestamp())*1000)::bigint;BEGIN
 INSERT INTO private.burimunsi_sessions SELECT(jsonb_populate_record(NULL::private.burimunsi_sessions,to_jsonb(s)||jsonb_build_object(
 'id','fd333000-0000-4000-8000-000000000099','token_hash',encode(sha256(convert_to(pg_temp.h_raw('expired-original'),'UTF8')),'hex'),
 'created_at',at_ms-2000,'expires_at',at_ms-1000))).* FROM private.burimunsi_sessions s WHERE token_hash=encode(sha256(convert_to(pg_temp.h_raw('old-current'),'UTF8')),'hex');
 INSERT INTO private.burimunsi_pin_session_links SELECT(jsonb_populate_record(NULL::private.burimunsi_pin_session_links,to_jsonb(l)||jsonb_build_object(
 'native_session_id','fd333000-0000-4000-8000-000000000099','created_at',at_ms-2000))).* FROM private.burimunsi_pin_session_links l JOIN private.burimunsi_sessions s ON s.id=l.native_session_id
 WHERE s.token_hash=encode(sha256(convert_to(pg_temp.h_raw('old-current'),'UTF8')),'hex');
 INSERT INTO private.burimunsi_gateway_retirements SELECT(jsonb_populate_record(NULL::private.burimunsi_gateway_retirements,to_jsonb(r)||jsonb_build_object(
 'session_id','fd333000-0000-4000-8000-000000000099','request_id','fd332000-0000-4000-8000-000000000099',
 'fingerprint',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000099'),'created_at',at_ms-1500,'recover_until',at_ms-1000,
 'response',r.response||jsonb_build_object('requestId','fd332000-0000-4000-8000-000000000099')))).* FROM private.burimunsi_gateway_retirements r
 WHERE r.request_id='fd332000-0000-4000-8000-000000000001';
END;$expired_original$;
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('expired-original'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000099',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000099')) IS NULL,'original expired token denies retired ACK');
ROLLBACK TO original_expiry;
SAVEPOINT principal_changed;
SELECT pg_temp.h_owner();RESET ROLE;
UPDATE app.users SET access_status='suspended' WHERE id='f3000000-0000-4000-8000-000000000001';
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_check(private.burimunsi_gateway_retirement_outcome(pg_temp.h_raw('old-current'),'fd330000-0000-4000-8000-000000000001',pg_temp.h_raw('old-device'),
 'internal_receiver','fd332000-0000-4000-8000-000000000001',pg_temp.h_fingerprint('replacement-code','fd332000-0000-4000-8000-000000000001')) IS NULL,'disabled principal denies retired ACK');
ROLLBACK TO principal_changed;
-- After original PIN sign-in only target can Pair; old caller cannot turn a
-- retirement code into the new target's receiving secret.
SELECT pg_temp.h_login('old-after','fd330000-0000-4000-8000-000000000001','old-device');
SELECT pg_temp.h_set('old-after','fd330000-0000-4000-8000-000000000001','old-device');
SELECT pg_temp.h_check(NOT private.burimunsi_gateway_pair_target(pg_temp.h_raw('replacement-code'),'fd330000-0000-4000-8000-000000000001'),'old caller cannot pair target');
SELECT pg_temp.h_login('new-after','fd330000-0000-4000-8000-000000000002','new-device');
SELECT pg_temp.h_set('new-after','fd330000-0000-4000-8000-000000000002','new-device');
SELECT pg_temp.h_check(private.burimunsi_gateway_pair_target(pg_temp.h_raw('replacement-code'),'fd330000-0000-4000-8000-000000000002'),'only exact fresh target can pair');
SELECT private.burimunsi_pin_claim_custody('buri-qualification-group',(SELECT grant_id FROM private.burimunsi_pin_context()),'f7000000-0000-4000-8000-000000000001');
RESET ROLE;
INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at)
 VALUES('handoff-new-key','handoff-new-binding','handoff-new-pairing','fd330000-0000-4000-8000-000000000002',
 pg_temp.h_raw('new-gateway-key'),'QUALIFICATION NOT A REAL GATEWAY CREDENTIAL',app.strftime('%Y-%m-%dT%H:%M:%fZ'));
SELECT pg_temp.h_check((SELECT count(*) FROM app.momo_gateway_credentials WHERE revoked_at IS NULL)=1
 AND (SELECT count(*) FROM app.momo_gateway_credentials)=2 AND (SELECT count(*) FROM auth.users)=2
 AND (SELECT count(*) FROM app.auth_sessions)=2 AND (SELECT count(*) FROM app.ledger_entries)=0,'single capture with history and unchanged web Auth');
SET LOCAL ROLE collect_runtime;
SELECT pg_temp.h_check(pg_temp.h_directory()->'scopes'->0->'pendingReplacement'='null'::jsonb,'pending hides after actual target Pair');
ROLLBACK;
