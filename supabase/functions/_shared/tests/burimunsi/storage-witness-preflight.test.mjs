import test from 'node:test';
import assert from 'node:assert/strict';
import {storageWitnessFixture} from './storage-witness-fixture.mjs';
import {PostgresPostingCustody} from '../../domain/burimunsi/postgres-posting-custody.js';
import {PostgresStorageWitnesses} from '../../domain/burimunsi/postgres-storage-witnesses.js';
import {encryption} from './posting-custody-fixture.mjs';
import {sha256} from '../../domain/burimunsi/values.js';
const count=(f,table)=>f.sqlite.prepare(`SELECT count(*) AS n FROM ${table}`).get().n;
const unavailable=e=>['posting_preparation_unavailable','posting_allocation_unavailable','posting_evidence_unavailable','storage_preflight_unavailable'].includes(e.code);

for(const mode of ['automatic','exception'])test('real Storage GET preflight supports scrubbed raw and newly scrubbed evidence: '+mode,async()=>{
  const f=await storageWitnessFixture(mode);try{
    await f.prepare();assert(f.state.storageCalls.some(c=>c.method==='GET'&&c.path.includes('/sms/raw-1')));
    const calls=f.state.storageCalls.length;
    await f.run();assert.equal(f.state.storageCalls.length,calls,'financial transaction performs no Storage calls');
    assert.equal(f.state.scrubs,1);assert.equal(count(f,'app.ledger_entries'),1);
    assert.equal(f.sqlite.prepare("SELECT count(*) AS n FROM private.storage_payload_reservations WHERE sealed_body IS NOT NULL").get().n,0);
  }finally{f.close();}
});
for(const mode of ['automatic','exception'])test('plan/preflight/commit orchestration retains the same canonical outcome: '+mode,async()=>{
  const f=(await storageWitnessFixture(mode)).connect();try{
    const result=await(mode==='automatic'?f.auto():f.allocate());assert.equal(result.amountRwf,12500);
    assert.equal(count(f,'app.ledger_entries'),1);const calls=f.state.storageCalls.length;
    await(mode==='automatic'?f.auto():f.allocate());assert.equal(count(f,'app.ledger_entries'),1);
    assert.equal(f.state.storageCalls.length,calls,'durable replay does not redisclose or refetch source');
  }finally{f.close();}
});
for(const [name,change]of [
  ['missing raw object',f=>f.remote.delete('sms/raw-1')],
  ['corrupt raw ciphertext',f=>f.remote.set('sms/raw-1',Buffer.from('invalid'))],
  ['pending upload',f=>f.sqlite.exec("UPDATE private.storage_put_intents SET state='pending'")],
  ['tombstone',f=>f.sqlite.exec('UPDATE private.storage_put_intents SET delete_tombstone=1')],
  ['unresolved upload',f=>f.sqlite.exec('UPDATE private.storage_put_intents SET upload_unresolved=1')],
  ['delete intent',f=>f.sqlite.exec("INSERT INTO private.storage_delete_intents VALUES('sms/raw-1','delete-1')")],
  ['retention barrier',f=>f.sqlite.exec("INSERT INTO app.privacy_retention_barriers VALUES('gateway-owner-1')")],
  ['wrong namespace',f=>f.sqlite.exec("UPDATE private.storage_namespace SET bucket='other'")],
])test('preflight denies '+name+' without a financial effect',async()=>{
  const f=await storageWitnessFixture();try{change(f);await assert.rejects(f.prepare(),unavailable);assert.equal(count(f,'app.payments'),0);assert.equal(count(f,'app.ledger_entries'),0);}finally{f.close();}
});
for(const [name,change]of [
  ['epoch replacement',f=>f.state.tuple[1]++],
  ['source replacement',f=>f.state.tuple[2]='b'.repeat(64)],
  ['work-kind replacement',f=>f.db.applicationWork.kind='replacement'],
  ['work replacement',f=>f.db.applicationWork={assert:async()=>{}}],
  ['namespace replacement',f=>f.media.namespace={...f.media.namespace,bucket:'other'}],
  ['binding revocation',f=>f.sqlite.exec("UPDATE app.momo_gateway_bindings SET status='revoked'")],
  ['source mutation',f=>f.sqlite.exec("UPDATE app.sms_receipts SET body_sha256='"+'b'.repeat(64)+"'")],
])test('replacement during awaited Storage I/O cannot publish a usable witness: '+name,async()=>{
  const f=await storageWitnessFixture();try{let fired=false;f.state.onStorage=async()=>{if(!fired){fired=true;await Promise.resolve();change(f);}};
    await assert.rejects(f.prepare(),unavailable);assert.equal(count(f,'app.payments'),0);assert.equal(count(f,'app.ledger_entries'),0);
  }finally{f.close();}
});
for(const [name,change]of [
  ['expired witness',f=>f.state.now+=300001],
  ['worker lease replacement',f=>f.command.work.leaseVersion++],
  ['request replacement',f=>f.command.requestId='22222222-2222-4222-8222-222222222222'],
  ['principal replacement',f=>f.state.onAuthority=(_phase,p)=>{p.principalSessionId='22222222-2222-4222-8222-222222222222';}],
  ['tombstone',f=>f.sqlite.exec('UPDATE private.storage_put_intents SET delete_tombstone=1')],
  ['reservation identity replacement',f=>f.sqlite.exec("UPDATE private.storage_payload_reservations SET key_id='other'")],
])test('financial transaction revalidates preflight binding and rolls back: '+name,async()=>{
  const f=await storageWitnessFixture();try{await f.prepare();change(f);const before=f.snapshot(),calls=f.state.storageCalls.length;
    await assert.rejects(f.run(),unavailable);assert.deepEqual(f.snapshot(),before);assert.equal(f.state.storageCalls.length,calls);
  }finally{f.close();}
});
test('failure after evidence INSERT scrubbing rolls the entire command back',async()=>{
  const f=await storageWitnessFixture();try{await f.prepare();const before=f.snapshot();f.state.failAt=5;
    await assert.rejects(f.run(),/injected/);assert.equal(f.state.scrubs,1);assert.deepEqual(f.snapshot(),before);assert.equal(count(f,'app.ledger_entries'),0);
  }finally{f.close();}
});
for(const [name,change]of [
  ['source tombstone',f=>f.sqlite.exec("UPDATE private.storage_put_intents SET delete_tombstone=1 WHERE object_key LIKE 'sms/%'")],
  ['retention barrier',f=>f.sqlite.exec("INSERT INTO app.privacy_retention_barriers VALUES('gateway-owner-1')")],
  ['namespace',f=>f.sqlite.exec("UPDATE private.storage_namespace SET bucket='changed'")],
  ['source association',f=>f.sqlite.exec("UPDATE private.burimunsi_sms_source_scopes SET proof_id='changed'")],
  ['admission epoch',f=>f.state.tuple[1]++],
  ['preflight expiry',f=>f.state.now+=300001],
])test('final custody recheck after posting rolls back changed '+name,async()=>{
  const f=await storageWitnessFixture();try{await f.prepare();const before=f.snapshot(),calls=f.state.storageCalls.length;
    f.state.onAuthority=phase=>{if(phase==='after_posting')change(f);};
    await assert.rejects(f.run(),unavailable);assert.deepEqual(f.snapshot(),before);assert.equal(f.state.storageCalls.length,calls);
    assert.equal(count(f,'app.ledger_entries'),0);
  }finally{f.close();}
});
for(const aadChanged of [false,true])test('a verified ciphertext digest cannot substitute for plaintext/AAD integrity: '+aadChanged,async()=>{
  const f=await storageWitnessFixture();try{
    const record=f.sqlite.prepare("SELECT * FROM private.storage_payload_reservations WHERE object_key='sms/raw-1'").get();
    const sealed=await encryption.encrypt(f.env,new TextEncoder().encode('invented source'),aadChanged?'wrong-aad':record.aad);
    const digest=await sha256(sealed);f.remote.set('sms/raw-1',Buffer.from(sealed));
    for(const table of ['storage_put_intents','storage_objects'])f.sqlite.prepare(`UPDATE private.${table} SET sha256=?,size=? WHERE object_key='sms/raw-1'`).run(digest,Buffer.byteLength(sealed));
    await assert.rejects(f.prepare(),unavailable);assert.equal(count(f,'app.payments'),0);
  }finally{f.close();}
});
test('serialized/fabricated preflight plans cannot initiate a Storage read',async()=>{
  const f=await storageWitnessFixture();try{
    for(const plan of [{},JSON.parse('{"verified":true}'),Object.freeze(Object.create(null))])await assert.rejects(f.storageWitnesses.prefetch(plan));
    assert.equal(f.state.storageCalls.length,0);
  }finally{f.close();}
});
test('production constructor refuses an absent/fabricated witness provider',async()=>{
  const f=await storageWitnessFixture();try{for(const storageWitnesses of [undefined,{}, {sealed:async()=> 'untrusted'}]){
    assert.throws(()=>new PostgresPostingCustody({db:f.db,groupId:f.command.groupId,namespace:f.media.namespace,decrypt:f.custody.decrypt,storageWitnesses}));
  }assert.throws(()=>new PostgresStorageWitnesses({db:f.db,groupId:f.command.groupId,namespace:f.media.namespace,media:f.media}));}finally{f.close();}
});
