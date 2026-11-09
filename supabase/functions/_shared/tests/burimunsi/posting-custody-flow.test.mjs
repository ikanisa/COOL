import test from 'node:test';import assert from 'node:assert/strict';
import {custodySqliteFixture} from './posting-custody-sqlite-fixture.mjs';
for(const mode of ['automatic','exception'])test('actual custody joins, AES-GCM and shared posting statements execute together: '+mode,async()=>{
 const f=await custodySqliteFixture(mode);try{
   await f.run();assert.equal(f.decryptCount(),2);
   assert.equal(f.sqlite.prepare('SELECT count(*) n FROM app.ledger_entries').get().n,1);
   assert.equal(f.sqlite.prepare('SELECT count(*) n FROM app.contribution_posting_snapshots').get().n,1);
   assert.equal(f.sqlite.prepare('SELECT count(*) n FROM app.notification_events').get().n,1);
 }finally{f.close();}
});
for(const [label,sql]of [
 ['missing raw source','DELETE FROM app.sms_receipts'],
 ['a conflict observation',"INSERT INTO app.momo_transaction_sources VALUES('transaction-1','other','other','conflict')"],
 ['parse digest mismatch',"UPDATE app.momo_parse_attempts SET source_body_sha256='bad'"],
 ['changed receiving binding',"UPDATE app.momo_gateway_bindings SET version=3"],
 ['pending storage upload',"UPDATE private.storage_put_intents SET state='pending'"],
 ['unknown upload',"UPDATE private.storage_put_intents SET upload_unresolved=1"],
 ['tombstoned storage',"UPDATE private.storage_put_intents SET delete_tombstone=1"],
 ['unavailable retained ciphertext',"UPDATE private.storage_payload_reservations SET sealed_body=NULL"],
 ['pending deletion',"INSERT INTO private.storage_delete_intents VALUES('sms/raw-1','delete-1')"],
 ['source retention barrier',"INSERT INTO app.privacy_retention_barriers VALUES('gateway-owner-1')"],
 ['changed namespace',"UPDATE private.storage_namespace SET bucket='other'"],
 ['revoked source credential',"UPDATE app.momo_gateway_credentials SET revoked_at='2026-11-07'"],
 ['wrong encrypted size',"UPDATE private.storage_objects SET size=1"],
])test('real SQL custody refusal rolls back allocation: '+label,async()=>{
 const f=await custodySqliteFixture();try{
   f.sqlite.exec(sql);const before=f.snapshot();
   await assert.rejects(f.run(),e=>e.code==='posting_evidence_unavailable');assert.deepEqual(f.snapshot(),before);
   assert.equal(f.state.statements.length,0);
 }finally{f.close();}
});
test('statement failure after successful custody verification rolls back allocation and posting',async()=>{
 const f=await custodySqliteFixture();try{const before=f.snapshot();f.state.failAt=5;await assert.rejects(f.run(),/injected/);assert.equal(f.decryptCount(),2);assert.deepEqual(f.snapshot(),before);}finally{f.close();}
});
