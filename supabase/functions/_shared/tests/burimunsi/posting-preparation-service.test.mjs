import test from 'node:test';
import assert from 'node:assert/strict';
import {preparationFixture,connectAllocationFlow,ids} from './posting-preparation-service-fixture.mjs';
import {PostgresPostingPreparation} from '../../domain/burimunsi/postgres-posting-preparation.js';
const error=/^posting_preparation_unavailable$/;
const denied=p=>assert.rejects(p,e=>e.message==='posting_preparation_unavailable'&&e.status===503);
const count=(f,table)=>f.sqlite.prepare(`SELECT count(*) AS n FROM ${table}`).get().n;
for(const mode of ['automatic','exception']){
 test('preparation protects original receipt without financial writes: '+mode,async()=>{
  const f=await preparationFixture(mode);try{
   const result=await f.prepare();assert.equal(result.prepared,true);assert.equal(result.evidenceId,f.identity.evidenceId);
   assert.equal(result.sizeBytes,Buffer.byteLength(f.body));assert.equal(f.state.puts,1);
   assert.equal(count(f,'app.payments'),0);assert.equal(count(f,'app.ledger_entries'),0);
   assert.equal(f.sqlite.prepare('SELECT version FROM app.momo_transactions').get().version,3);
   assert.ok(Object.isFrozen(result));assert.equal('body' in result,false);assert.equal(JSON.stringify(result).includes('EXAMPLE PAYER'),false);
  }finally{f.close();}
 });
 test('preparation feeds concrete allocation/custody/shared writer: '+mode,async()=>{
  const f=connectAllocationFlow(await preparationFixture(mode));try{
   await f.prepare();const result=await(mode==='automatic'?f.auto():f.allocate());
   assert.equal(count(f,'app.payments'),1);assert.equal(count(f,'app.ledger_entries'),1);
   assert.equal(count(f,'app.contribution_posting_snapshots'),1);
   await(mode==='automatic'?f.auto():f.allocate());assert.equal(count(f,'app.ledger_entries'),1);
  }finally{f.close();}
 });
}
test('repeat preparation reuses original ciphertext and identity',async()=>{
 const f=await preparationFixture();try{const one=await f.prepare();const sealed=f.sqlite.prepare("SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key=?").get(one.objectKey).sealed_body;
  const two=await f.prepare();assert.deepEqual(one,two);assert.equal(f.sqlite.prepare("SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key=?").get(two.objectKey).sealed_body,sealed);
 }finally{f.close();}
});
for(const [name,sql]of [
 ['source conflict',"UPDATE app.momo_transactions SET has_conflict=1"],
 ['version drift',"UPDATE app.momo_transactions SET version=4"],
 ['inactive member',"UPDATE app.memberships SET active=0"],
 ['operator beneficiary',"UPDATE app.users SET member_type='operator'"],
 ['changed membership',"UPDATE app.memberships SET revision=2"],
 ['revoked gateway',"UPDATE app.momo_gateway_credentials SET revoked_at='2026-11-07'"],
 ['wrong binding',"UPDATE app.momo_gateway_bindings SET version=3"],
 ['stopped binding',"UPDATE app.momo_gateway_bindings SET status='revoked'"],
 ['historical capture',"UPDATE app.momo_gateway_captures SET source_mode='catch_up'"],
 ['incomplete capture',"UPDATE app.momo_gateway_captures SET completeness='incomplete'"],
 ['uncompleted processing',"UPDATE app.momo_processing_jobs SET state='processing'"],
 ['processing error',"UPDATE app.momo_processing_jobs SET last_error='error'"],
 ['wrong account',"UPDATE app.momo_processing_jobs SET receiving_account_id='wrong'"],
 ['changed profile',"UPDATE app.momo_receiving_accounts SET profile_version='new'"],
 ['profile JSON drift',"UPDATE app.momo_receiving_accounts SET profile_json='{}'"],
 ['wrong capture hash',"UPDATE app.momo_gateway_captures SET identity_sha256='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'"],
 ['wrong subscription',"UPDATE app.momo_gateway_captures SET subscription_id=8"],
 ['invalid binding evidence',"UPDATE app.momo_gateway_bindings SET subscription_evidence='{}'"],
 ['raw size drift',"UPDATE app.sms_receipts SET size_bytes=1"],
 ['scrubbed raw reservation',"UPDATE private.storage_payload_reservations SET sealed_body=NULL"],
 ['unresolved raw upload',"UPDATE private.storage_put_intents SET upload_unresolved=1"],
 ['unsettled upload attempt',"UPDATE private.storage_put_intents SET active_attempt='inflight'"],
 ['deleted source',"UPDATE private.storage_put_intents SET delete_tombstone=1"],
 ['wrong namespace',"UPDATE private.storage_namespace SET bucket='other'"],
 ['retention barrier',"INSERT INTO app.privacy_retention_barriers VALUES('gateway-owner-1')"],
 ['delete intent',"INSERT INTO private.storage_delete_intents VALUES('sms/raw-1','delete')"],
])test('refuses before storage: '+name,async()=>{
 const f=await preparationFixture();try{f.sqlite.exec(sql);await denied(f.prepare());assert.equal(f.state.puts,0);assert.equal(count(f,'app.payments'),0);}finally{f.close();}
});
for(const phase of ['before_preparation','after_preparation_source','before_preparation_storage','after_preparation_storage'])
 test('runtime authority refusal at '+phase,async()=>{const f=await preparationFixture();try{
  f.state.onAuthority=p=>{if(p===phase)throw Error('SECRET runtime error');};await denied(f.prepare());assert.equal(count(f,'app.ledger_entries'),0);
  if(phase!=='after_preparation_storage')assert.equal(f.state.puts,0);
 }finally{f.close();}});
test('principal changed after local encryption blocks upload',async()=>{const f=await preparationFixture();try{
 f.state.onEncrypt=()=>{f.state.onAuthority=(_phase,p)=>{p.principalUserId='wrong-user';};};await denied(f.prepare());assert.equal(f.state.puts,0);
}finally{f.close();}});
test('source changed after local encryption blocks upload',async()=>{const f=await preparationFixture();try{
 f.state.onEncrypt=()=>f.sqlite.exec('UPDATE app.momo_transactions SET version=4');await denied(f.prepare());assert.equal(f.state.puts,0);
}finally{f.close();}});
test('source changed during provider request refuses completion and does not delete evidence',async()=>{const f=await preparationFixture();try{
 f.state.afterPut=()=>f.sqlite.exec('UPDATE app.momo_transactions SET version=4');await denied(f.prepare());assert.equal(f.state.puts,1);
 assert.equal(count(f,'private.storage_payload_reservations'),2);assert.equal(count(f,'app.ledger_entries'),0);
}finally{f.close();}});
test('lost storage reply is unresolved; retry preserves identity and ciphertext',async()=>{const f=await preparationFixture();try{
 f.state.afterPut=()=>{throw Error('SECRET provider reply lost');};await denied(f.prepare());assert.equal(count(f,'app.payments'),0);
 const sealed=f.sqlite.prepare("SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key=?").get(f.identity.objectKey).sealed_body;
 f.state.afterPut=null;await f.prepare();assert.equal(f.sqlite.prepare("SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key=?").get(f.identity.objectKey).sealed_body,sealed);
}finally{f.close();}});
for(const [name,change]of [
 ['false durable flag',a=>a.metadataCommitted=false],['false stored flag',a=>a.stored=false],
 ['wrong object key',a=>a.key='evidence/wrong'],['wrong operation',a=>a.operationId='other'],
 ['wrong cipher digest',a=>a.sha256='a'.repeat(64)],['wrong cipher size',a=>a.size++],
])test('storage acknowledgement cannot replace journal proof: '+name,async()=>{const f=await preparationFixture();try{
 f.state.afterPut=change;await denied(f.prepare());assert.equal(count(f,'app.payments'),0);
}finally{f.close();}});
for(const [name,sql]of [
 ['missing reservation',"DELETE FROM private.storage_payload_reservations WHERE object_key LIKE 'evidence/%'"],
 ['missing metadata',"DELETE FROM private.storage_objects WHERE object_key LIKE 'evidence/%'"],
 ['scrubbed evidence',"UPDATE private.storage_payload_reservations SET sealed_body=NULL WHERE object_key LIKE 'evidence/%'"],
 ['uncommitted evidence',"UPDATE private.storage_put_intents SET state='pending' WHERE object_key LIKE 'evidence/%'"],
 ['evidence tombstone',"UPDATE private.storage_put_intents SET delete_tombstone=1 WHERE object_key LIKE 'evidence/%'"],
])test('storage 200 cannot hide '+name,async()=>{const f=await preparationFixture();try{
 f.state.afterPut=()=>f.sqlite.exec(sql);await denied(f.prepare());assert.equal(count(f,'app.payments'),0);
}finally{f.close();}});
test('input is snapshotted before asynchronous work',async()=>{const f=await preparationFixture();try{
 const original=f.command.memberId;f.state.onEncrypt=()=>{f.command.memberId='changed';f.command.receipt.amountRwf=1;};
 const result=await f.prepare();assert.equal(result.evidenceId,f.identity.evidenceId);assert.notEqual(f.command.memberId,original);
}finally{f.close();}});
test('admission replacement during encryption is refused',async()=>{const f=await preparationFixture();try{
 f.state.onEncrypt=()=>{f.db.applicationWork={assert:async()=>{}};};await denied(f.prepare());assert.equal(f.state.puts,0);
}finally{f.close();}});
test('a bare successful HTTP response is not a storage receipt',async()=>{const f=await preparationFixture();try{
 f.media.put=async()=>({status:200});await denied(f.prepare());assert.equal(count(f,'app.payments'),0);
}finally{f.close();}});
for(const key of ['authority','posting','allocation','media','encrypt','keyId'])test('missing preparation dependency '+key,async()=>{
 const f=await preparationFixture();try{assert.throws(()=>new PostgresPostingPreparation({...f.args,[key]:undefined}));assert.equal(f.state.puts,0);}finally{f.close();}
});
test('construction has no SQL or provider effects',async()=>{const f=await preparationFixture();try{
 const n=f.state.queries.length;new PostgresPostingPreparation(f.args);assert.equal(f.state.queries.length,n);assert.equal(f.state.puts,0);
}finally{f.close();}});

for(const [name,value]of [['not ciphertext','plain source must not upload'],['wrong key',JSON.stringify({v:1,kid:'wrong'})],['wrong version',JSON.stringify({v:2,kid:'test-key'})],['null',null]])
 test('invalid encryption result is refused before storage: '+name,async()=>{const f=await preparationFixture();try{
  f.preparation.encrypt=async()=>value;await denied(f.prepare());assert.equal(f.state.puts,0);assert.equal(count(f,'app.ledger_entries'),0);
 }finally{f.close();}});
test('encryption failure is redacted and never uploads plaintext',async()=>{const f=await preparationFixture();try{
 f.preparation.encrypt=async()=>{throw Error('SECRET key details');};await denied(f.prepare());assert.equal(f.state.puts,0);
}finally{f.close();}});
test('initial SQL commit reply loss never proceeds to provider',async()=>{const f=await preparationFixture();try{
 f.state.commitLost=true;await denied(f.prepare());assert.equal(f.state.puts,0);await f.prepare();assert.equal(f.state.puts,1);
}finally{f.close();}});
test('pre-storage SQL commit reply loss never proceeds to provider',async()=>{const f=await preparationFixture();try{
 f.state.onEncrypt=()=>{f.state.commitLost=true;};await denied(f.prepare());assert.equal(f.state.puts,0);
 f.state.onEncrypt=null;await f.prepare();assert.equal(f.state.puts,1);
}finally{f.close();}});
test('post-storage SQL commit reply loss stays unresolved and retry is stable',async()=>{const f=await preparationFixture();try{
 f.state.afterPut=()=>{f.state.commitLost=true;};await denied(f.prepare());assert.equal(count(f,'app.ledger_entries'),0);
 const body=f.sqlite.prepare('SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key=?').get(f.identity.objectKey).sealed_body;
 f.state.afterPut=null;await f.prepare();assert.equal(f.sqlite.prepare('SELECT sealed_body FROM private.storage_payload_reservations WHERE object_key=?').get(f.identity.objectKey).sealed_body,body);
}finally{f.close();}});
test('local encryption must preserve original plaintext bytes',async()=>{const f=await preparationFixture();try{
 const original=f.preparation.encrypt;f.preparation.encrypt=(bytes,aad)=>{bytes[0]^=1;return original(bytes,aad);};await denied(f.prepare());assert.equal(f.state.puts,0);
}finally{f.close();}});
test('preparation refuses after another transaction already posted',async()=>{const f=connectAllocationFlow(await preparationFixture());try{
 await f.prepare();await f.auto();const n=f.state.puts;await denied(f.prepare());assert.equal(f.state.puts,n);assert.equal(count(f,'app.ledger_entries'),1);
}finally{f.close();}});
