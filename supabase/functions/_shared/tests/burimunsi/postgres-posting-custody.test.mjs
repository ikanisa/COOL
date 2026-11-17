import {sha256} from '../../domain/burimunsi/values.js';
import test from 'node:test';import assert from 'node:assert/strict';
import {custodyFixture,encryptionBlob,namespace,encryption} from './posting-custody-fixture.mjs';
import {PostgresPostingCustody} from '../../domain/burimunsi/postgres-posting-custody.js';
const rejected=async f=>assert.rejects(f.run(),e=>e.code==='posting_evidence_unavailable'&&!JSON.stringify(e).includes('EXAMPLE PAYER'));
test('custody uses exact pinned Collect encryption source',()=>assert.equal(encryptionBlob,'8c9e64903e9e840bf3d3d4e67a3750be25f91084'));
test('verifies both committed ciphertext journals and actual decrypted payloads without exposing content',async()=>{
 const f=await custodyFixture();assert.deepEqual(await f.run(),{verified:true});assert.equal(f.state.decrypts,2);
 assert.ok(f.state.queries.every(q=>/^SELECT\b/.test(q.text)));
 assert.ok(f.state.queries.filter(q=>q.text.includes('hashtextextended')).length>=4);
});
test('handles UTF-8 byte counts rather than JavaScript string length',async()=>{const f=await custodyFixture({body:'EXAMPLE: amafaranga 12,500 RWF — Élodie 📩'});assert.deepEqual(await f.run(),{verified:true});});
test('native exception also verifies original source custody',async()=>{const f=await custodyFixture();f.descriptor.command.mode='exception';delete f.descriptor.command.policyVersion;assert.deepEqual(await f.run(),{verified:true});});
for(const [field,value]of Object.entries({
 collection_id:'other',payment_group:'other',evidence_group:'other',transaction_id:'other',payment_id:'other',evidence_id:'other',beneficiary_member_id:'other',receiving_account_id:'other',
 source_binding_id:'other',source_binding_version:3,event_kind:'outgoing',mode:'historical',has_conflict:1,allocation_state:'unallocated',source_conflict:true,relation:'duplicate',parse_outcome:'conflict',
 parse_attempt_id:'other',canonical_attempt:'other',completeness:'incomplete',source_mode:'catch_up',job_mode:'historical',job_state:'processing',job_error:'unknown',parse_profile_json:'{}',wallet_profile_json:'{}',raw_owner:'other',job_binding:'other',credential_binding:'other',job_account:'other',
 binding_account:'other',job_binding_version:3,binding_version:3,binding_status:'revoked',credential_revoked:'2026-11-07',wallet_status:'disabled',profile_status:'unverified',parse_profile:'old',
 raw_key:'sms/other',evidence_key:'evidence/other',evidence_sha256:'f'.repeat(64),evidence_size:1,raw_sha256:'bad',body_sha256:'a'.repeat(64),source_body_sha256:'a'.repeat(64),identity_sha256:'b'.repeat(64),
 receiver_hash:'bad',wallet_hash:'2'.repeat(64),currency:'USD',evidence_currency:'USD',amount_minor:1,payment_amount:1,evidence_amount:1,provider_transaction_id:'OTHER',external_reference:'OTHER',
 provider:'other',wallet_provider:'airtel_money',receiver_network:'airtel_money',receiver_momo_number:'0790000002',public_code:'invalid',raw_size:1,policy_version:'other',source_conflict:null,
 subscription_evidence:'{"subscription_id":8}',subscription_id:8
}))test('refuses incompatible retained lineage: '+field,async()=>{const f=await custodyFixture();f.state.row[field]=value;await rejected(f);});
for(const field of ['source_binding_version','job_binding_version','binding_version','evidence_size','amount_minor','payment_amount','evidence_amount','raw_size'])
 test('refuses missing numeric measurement: '+field,async()=>{const f=await custodyFixture();f.state.row[field]=null;await rejected(f);});
for(const missing of ['namespace','lineage','put','metadata','reservation'])test('refuses missing '+missing,async()=>{const f=await custodyFixture();f.state.missing=missing;await rejected(f);});
test('refuses multiple accepted lineage rows',async()=>{const f=await custodyFixture();f.state.duplicate=true;await rejected(f);});
for(const key of ['sms/raw-1','evidence/evidence-1']){
 for(const [part,field,value]of [
   ['put','state','pending'],['put','state','erased'],['put','active_attempt','inflight'],['put','upload_unresolved',true],['put','upload_unresolved',null],['put','delete_tombstone',true],
   ['metadata','operation_id','other'],['metadata','fingerprint','e'.repeat(64)],['metadata','sha256','f'.repeat(64)],['metadata','size',1],
   ['reservation','plaintext_sha256','c'.repeat(64)],['reservation','source_fingerprint','a'.repeat(64)],['reservation','aad','wrong'],['reservation','key_id','wrong'],['reservation','sealed_body',null]
 ])test('refuses '+key+' '+part+'.'+field+'='+String(value).slice(0,12),async()=>{const f=await custodyFixture();f.state.journals.get(key)[part][field]=value;await rejected(f);});
 for(const part of ['put','metadata','reservation'])test('refuses '+key+' '+part+' scope substitution',async()=>{const f=await custodyFixture();f.state.journals.get(key)[part].scope.ownerId='other';await rejected(f);});
 test('refuses pending delete for '+key,async()=>{const f=await custodyFixture();f.state.deletions.push(key);await rejected(f);});
}
for(const owner of ['principal-1','gateway-owner-1'])test('refuses retention barrier for '+owner,async()=>{const f=await custodyFixture();f.state.barriers.push(owner);await rejected(f);});
for(const field of ['origin','bucket'])test('refuses changed storage namespace '+field,async()=>{const f=await custodyFixture();f.state.namespace[field]='other';await rejected(f);});
test('rejects key loss without revealing ciphertext or cause',async()=>{const f=await custodyFixture();f.env.DATA_ENCRYPTION_KEY=Buffer.alloc(32,20).toString('base64');await rejected(f);});
test('supports real decryption using retained prior key after rotation',async()=>{
 const f=await custodyFixture(),old=f.env.DATA_ENCRYPTION_KEY;
 f.env.DATA_KEY_ID='new-test-key';f.env.DATA_ENCRYPTION_KEY=Buffer.alloc(32,21).toString('base64');f.env.DATA_DECRYPTION_KEYS_JSON=JSON.stringify({'test-only-key':old});
 assert.deepEqual(await f.run(),{verified:true});
});
for(const [name,change]of [
 ['binding',p=>p.gateway_binding_id='other'],['binding version',p=>p.gateway_binding_version=3],['route',p=>p.receiver_momo_number='0790000002'],
 ['incomplete',p=>p.completeness='incomplete'],['catch up',p=>p.source_mode='catch_up'],['SIM',p=>p.subscription_id=8],['sender',p=>p.raw_sender=''],['body',p=>p.raw_body='changed body']
])test('authentic ciphertext does not excuse wrong payload '+name,async()=>{const f=await custodyFixture({payloadChange:change});await rejected(f);});
test('rejects ciphertext alteration even before decryption',async()=>{const f=await custodyFixture();f.state.journals.get('sms/raw-1').reservation.sealed_body+=' ';await rejected(f);assert.equal(f.state.decrypts,0);});
test('rejects source changes during awaited decryption',async()=>{const f=await custodyFixture();f.state.onDecrypt=()=>{f.state.row.profile_version='new';};await rejected(f);});
test('rejects metadata changes during awaited decryption',async()=>{const f=await custodyFixture();f.state.onDecrypt=()=>{f.state.journals.get('sms/raw-1').put.upload_unresolved=true;};await rejected(f);});
test('rejects a namespace replacement during decryption',async()=>{const f=await custodyFixture();f.state.onDecrypt=()=>{f.state.namespace.bucket='other';};await rejected(f);});
test('rejects replaced application admission after awaited assertion',async()=>{const f=await custodyFixture();f.state.onAssert=()=>{f.db.applicationWork={assert:async()=>{}};};await rejected(f);});
test('rejects admission replacement while decrypting',async()=>{const f=await custodyFixture();f.state.onDecrypt=()=>{f.db.applicationWork={assert:async()=>{}};};await rejected(f);});
test('snapshots caller descriptor before the first await',async()=>{
 const f=await custodyFixture();let first=true;f.state.onAssert=()=>{if(first){first=false;f.descriptor.command.memberId='other';f.descriptor.objectKey='evidence/other';}};
 assert.deepEqual(await f.run(),{verified:true});
});
test('constructor requires local decrypt and performs no I/O',()=>{
 let calls=0;const db={applicationWork:{assert:async()=>{calls++;}}};
 assert.throws(()=>new PostgresPostingCustody({qualificationOnly:true,db,groupId:'group-1',namespace}));
 new PostgresPostingCustody({qualificationOnly:true,db,groupId:'group-1',namespace,decrypt:async()=>{calls++;}});assert.equal(calls,0);
});
for(const origin of ['http://example.test','https://user:pass@example.test','https://example.test/path','not-a-url'])test('rejects ambiguous namespace origin '+origin,()=>assert.throws(()=>new PostgresPostingCustody({qualificationOnly:true,db:{applicationWork:{assert:async()=>{}}},groupId:'group-1',namespace:{...namespace,origin},decrypt:async()=>{}})));

test('AES-GCM rejects altered ciphertext even when corrupt journal hashes agree',async()=>{
 const f=await custodyFixture(),j=f.state.journals.get('sms/raw-1');
 const sealed=JSON.parse(j.reservation.sealed_body);const bytes=Buffer.from(sealed.data,'base64');bytes[0]^=1;sealed.data=bytes.toString('base64');
 j.reservation.sealed_body=JSON.stringify(sealed);const hash=await sha256(j.reservation.sealed_body);
 j.put.sha256=hash;j.metadata.sha256=hash;await rejected(f);assert.equal(f.state.decrypts,1);
});
test('AES-GCM rejects authentic ciphertext prepared under another AAD',async()=>{
 const f=await custodyFixture(),j=f.state.journals.get('sms/raw-1');
 const plain=await encryption.decrypt(f.env,j.reservation.sealed_body,j.reservation.aad);
 j.reservation.sealed_body=await encryption.encrypt(f.env,plain,'another-context');
 const hash=await sha256(j.reservation.sealed_body);j.put.sha256=hash;j.metadata.sha256=hash;
 j.put.size=Buffer.byteLength(j.reservation.sealed_body);j.metadata.size=j.put.size;
 await rejected(f);assert.equal(f.state.decrypts,1);
});
