import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import pg from '../../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../test-support/owned-pg17.mjs';

const {Client}=pg;
const sql=await readFile(new URL('./inventory.sql',import.meta.url),'utf8');
const fixtureSql=await readFile(new URL('./fixture.sql',import.meta.url),'utf8');

async function within(promise,ms){
 let timer;try{return await Promise.race([promise.then(()=>true),new Promise(resolve=>{timer=setTimeout(()=>resolve(false),ms);})]);}
 finally{clearTimeout(timer);}
}
async function closeOwnedClient(client){
 const stream=client?.connection?.stream;let listener;
 try{
  if(!stream){await within(Promise.resolve().then(()=>client.end()).catch(()=>{}),2000);return;}
  let markClosed;const closed=new Promise(resolve=>{markClosed=resolve;});
  listener=()=>markClosed();stream.once('close',listener);if(stream.closed)markClosed();
  const end=Promise.resolve().then(()=>client.end()).catch(()=>{});
  if(!await within(Promise.all([end,closed]),2000)){
   stream.destroy();if(stream.closed)markClosed();
   if(!await within(Promise.all([end,closed]),2000))throw new Error('owned client closure unconfirmed');
  }
 }finally{if(listener&&stream)stream.removeListener('close',listener);}
}

test('count-only financial graph inventory on owned PostgreSQL 17', {timeout:90000},async t=>{
 const fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap'});
 const db=new Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'fixture_bootstrap',connectionTimeoutMillis:3000});
 db.on('error',()=>{});
 const inventory=async()=>{
  const results=await db.query(sql);const selected=(Array.isArray(results)?results:[results]).filter(r=>r.command==='SELECT');
  assert.equal(selected.length,1);assert.equal(selected[0].rows.length,1);return selected[0].rows[0].inventory;
 };
 try{
  await db.connect();
  assert.deepEqual((await db.query("SELECT inet_server_addr() IS NULL AS socket,current_setting('server_version_num')::int/10000 AS major")).rows[0],{socket:true,major:17});
  await db.query(fixtureSql);

  await t.test('reports consistent links without returning private cells or authorizing a write',async()=>{
   const x=await inventory();
   assert.equal(x.format,'collect.financial-source-inventory.v1');
   assert.equal(x.totals.payments,1);assert.equal(x.totals.sms_receipts,1);
   assert.equal(x.payment_graph.intent_not_used,1);assert.equal(x.payment_graph.distinct_beneficiary_records,1);
   assert.equal(x.payment_graph.payments_with_auth_linked_beneficiary,0);assert.equal(x.payment_graph.payments_with_auth_linked_evidence_owner,1);
   for(const name of ['missing_evidence','evidence_field_mismatches','missing_nonnull_intent','missing_financial_link','multiple_financial_links',
    'link_beneficiary_mismatches','missing_linked_transaction','transaction_amount_or_currency_mismatches','missing_contribution','multiple_contributions',
    'contribution_field_mismatches','missing_contribution_snapshot','missing_evidence_journal','evidence_journal_plaintext_digest_mismatches',
    'evidence_journal_scope_mismatches','missing_evidence_reservation','evidence_reservation_mismatches','missing_current_evidence_object_metadata'])assert.equal(x.payment_graph[name],0,name);
   for(const [name,value] of Object.entries(x.sms_graph))if(!['source_links','distinct_receipts'].includes(name))assert.equal(value,0,name);
   for(const [name,value] of Object.entries(x.coverage))assert.equal(value,0,name);
   assert.equal(x.source_fence.mode,'open');assert.equal(x.source_fence.non_settled_admissions,1);
   for(const name of ['target_compared','object_bytes_verified','key_compatibility_verified','complete_dependency_graph_verified','write_authorized'])assert.equal(x[name],false,name);
   assert.doesNotMatch(JSON.stringify(x),/private-fixture|plaintext-evidence-hash|different-ciphertext-hash/);
  });

  await t.test('detects payment, ledger, snapshot and link drift without treating a reversal as a duplicate contribution',async()=>{
   await db.query("UPDATE app.ledger_entries SET amount_minor=9; DELETE FROM app.contribution_posting_snapshots; UPDATE app.momo_financial_links SET beneficiary_member_id='other'");
   let x=await inventory();assert.equal(x.payment_graph.contribution_field_mismatches,1);assert.equal(x.payment_graph.missing_contribution_snapshot,1);assert.equal(x.payment_graph.link_beneficiary_mismatches,1);
   await db.query("UPDATE app.ledger_entries SET amount_minor=1250; INSERT INTO app.contribution_posting_snapshots VALUES('private-fixture-ledger','private-fixture-payment'); UPDATE app.momo_financial_links SET beneficiary_member_id='private-fixture-member'; INSERT INTO app.ledger_entries VALUES('private-fixture-reversal','private-fixture-payment','private-fixture-collection','private-fixture-member','RWF',-1250,'reversal','private-fixture-evidence','private-fixture-owner')");
   x=await inventory();assert.equal(x.totals.reversal_entries,1);assert.equal(x.payment_graph.multiple_contributions,0);assert.equal(x.payment_graph.contribution_field_mismatches,0);
   await db.query("DELETE FROM app.ledger_entries WHERE kind='reversal'; INSERT INTO app.momo_financial_links VALUES('private-fixture-txn','private-fixture-payment','private-fixture-member','private-fixture-owner')");
   x=await inventory();assert.equal(x.payment_graph.payments,1);assert.equal(x.payment_graph.multiple_financial_links,1);
   await db.query("DELETE FROM app.momo_financial_links WHERE ctid IN (SELECT ctid FROM app.momo_financial_links LIMIT 1)");
  });

  await t.test('detects incorrect plaintext metadata, scope, AAD and archived object without comparing ciphertext digest to plaintext',async()=>{
   await db.query("UPDATE private.storage_objects SET custom_metadata='{}'::jsonb,scope='{}'::jsonb WHERE object_key='evidence/object'; UPDATE private.storage_payload_reservations SET aad='wrong' WHERE object_key='sms/object'; UPDATE storage.objects SET archived_at=now() WHERE name='evidence/object'");
   let x=await inventory();assert.equal(x.payment_graph.evidence_journal_plaintext_digest_mismatches,1);assert.equal(x.payment_graph.evidence_journal_scope_mismatches,1);
   assert.equal(x.payment_graph.missing_current_evidence_object_metadata,1);assert.equal(x.sms_graph.reservation_mismatches,1);
   await db.query("UPDATE private.storage_objects SET custom_metadata='{\"sha256\":\"plaintext-evidence-hash\"}',scope='{\"ownerId\":\"private-fixture-owner\",\"entityId\":\"private-fixture-evidence\",\"purpose\":\"payment_evidence\"}' WHERE object_key='evidence/object'; UPDATE private.storage_payload_reservations SET aad='sms:private-fixture-sms:plaintext-sms-hash' WHERE object_key='sms/object'; UPDATE storage.objects SET archived_at=NULL WHERE name='evidence/object'");
   x=await inventory();assert.equal(x.payment_graph.evidence_journal_plaintext_digest_mismatches,0);assert.equal(x.sms_graph.reservation_mismatches,0);
  });

  await t.test('detects missing parse records and wrong native source hashes',async()=>{
   await db.query("DELETE FROM app.momo_parse_attempts; UPDATE private.burimunsi_native_receipt_origins SET body_sha256='wrong'");
   const x=await inventory();assert.equal(x.sms_graph.missing_parse_attempt,1);assert.equal(x.sms_graph.origin_hash_mismatches,1);
   await db.query("INSERT INTO app.momo_parse_attempts VALUES('private-fixture-attempt','private-fixture-sms','body-hash'); UPDATE private.burimunsi_native_receipt_origins SET body_sha256='body-hash'");
  });

  await t.test('reports records outside the linked graph without assuming they are erroneous',async()=>{
   await db.query("INSERT INTO app.sms_receipts VALUES('private-fixture-unlinked','private-fixture-owner','hash','unused/object','hash'); INSERT INTO app.momo_transactions VALUES('private-fixture-unlinked-txn',1,'RWF')");
   const x=await inventory();assert.equal(x.coverage.sms_receipts_without_transaction_source,1);assert.equal(x.coverage.momo_transactions_without_source,1);
   assert.equal(x.sms_graph.source_links,1);assert.doesNotMatch(JSON.stringify(x),/private-fixture-unlinked/);
   await db.query("DELETE FROM app.sms_receipts WHERE id='private-fixture-unlinked'; DELETE FROM app.momo_transactions WHERE id='private-fixture-unlinked-txn'");
  });

  await t.test('treats an unknown admission state as non-settled',async()=>{
   await db.query('INSERT INTO private.collect_fence_admissions VALUES(NULL)');
   const x=await inventory();assert.equal(x.source_fence.non_settled_admissions,2);
   await db.query('DELETE FROM private.collect_fence_admissions WHERE state IS NULL');
  });

  await t.test('refuses filtered RLS and insufficient SELECT instead of reporting false zeroes',async()=>{
   await db.query('CREATE ROLE financial_fixture_reader; GRANT USAGE ON SCHEMA app,auth,private,storage TO financial_fixture_reader; GRANT SELECT ON ALL TABLES IN SCHEMA app,auth,private,storage TO financial_fixture_reader; ALTER TABLE app.payments ENABLE ROW LEVEL SECURITY; SET ROLE financial_fixture_reader');
   try{await assert.rejects(inventory(),e=>e.code==='42501'&&e.message==='financial_inventory_visibility_refused');}
   finally{await db.query('ROLLBACK; RESET ROLE; ALTER TABLE app.payments DISABLE ROW LEVEL SECURITY');}
   await db.query('REVOKE SELECT ON app.sms_receipts FROM financial_fixture_reader; SET ROLE financial_fixture_reader');
   try{await assert.rejects(inventory(),e=>e.code==='42501'&&e.message==='financial_inventory_visibility_refused');}
   finally{await db.query('ROLLBACK; RESET ROLE');}
  });

  await t.test('refuses inherited table shapes rather than omitting child rows',async()=>{
   await db.query('CREATE TABLE app.payments_child() INHERITS(app.payments)');
   try{await assert.rejects(inventory(),e=>e.code==='42501'&&e.message==='financial_inventory_visibility_refused');}
   finally{await db.query('ROLLBACK; DROP TABLE app.payments_child');}
  });
 }finally{
  try{await closeOwnedClient(db);}
  finally{const closed=await fixture.close();assert.equal(closed.removed,true,'owned PostgreSQL fixture cleanup must be confirmed');}
 }
});
