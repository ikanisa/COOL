import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomBytes,webcrypto} from 'node:crypto';
import {link,mkdtemp,realpath,readFile,readdir,rm,symlink,unlink,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {encrypt} from '../../../../supabase/functions/_shared/domain/encryption.js';
import {FORMAT,nativeObservationId,retainOfflineWitness,reconcileOfflineWitness,managedTransfer} from './custody.mjs';
if(!globalThis.crypto)globalThis.crypto=webcrypto;
const sha=x=>createHash('sha256').update(x).digest('hex');
const canonical=x=>x===null||typeof x!=='object'?JSON.stringify(x):Array.isArray(x)?'['+x.map(canonical).join(',')+']':'{'+Object.keys(x).sort().map(k=>JSON.stringify(k)+':'+canonical(x[k])).join(',')+'}';
const request='11111111-1111-4111-8111-111111111111',operation='22222222-2222-4222-8222-222222222222';
async function fixture({targetOwner='synthetic-cloud-owner'}={}){
 const owner='synthetic-local-owner',id=nativeObservationId(owner,request),sourceKey=randomBytes(32),journalKey=randomBytes(32);
 const payload={raw_sender:'Synthetic sender',raw_body:'SYNTHETIC-PRIVATE-SMS-Canary',source_mode:'live',complete:true,
  captured_at:'2026-01-01T00:00:00Z',service_centre_at:null,inbox_received_at:null,subscription_id:null,provenance:'native_observation_unverified'};
 const plain=Buffer.from(JSON.stringify(payload)),objHash=sha(plain),bodyHash=sha(Buffer.from(payload.raw_body)),aad=`sms:${id}:${objHash}`;
 const env={DATA_KEY_ID:'synthetic-key-id',DATA_ENCRYPTION_KEY:sourceKey.toString('base64')};
 const ciphertext=Buffer.from(await encrypt(env,plain,aad));const scope={ownerId:owner,purpose:'sms_receipt',entityId:id};
 const source={id,owner,request_id:request,body_sha256:bodyHash,object_sha256:objHash,size_bytes:plain.length,fingerprint:sha('synthetic-request')};
 const key='sms/'+id,http={contentType:'application/octet-stream'},baseCustom={sha256:objHash,key_id:env.DATA_KEY_ID};
 const sourceDescriptor={scope,aad,keyId:env.DATA_KEY_ID,plaintextSha256:objHash,requestDigest:source.fingerprint,httpMetadata:http,customMetadata:baseCustom};
 const sf=sha(canonical(sourceDescriptor)),custom={...baseCustom,source_fingerprint:sf},ctSha=sha(ciphertext);
 const put={key,size:ciphertext.length,sha256:ctSha,scope,httpMetadata:http,customMetadata:custom},fp=sha(canonical(put));
 const intent={key,operation_id:sha('collect.storage.put.v1\n'+key),fingerprint:fp,sha256:ctSha,size:ciphertext.length,scope,http_metadata:http,custom_metadata:custom,
  state:'committed',active_attempt:null,upload_unresolved:false,delete_tombstone:false};
 const object={key,operation_id:intent.operation_id,fingerprint:fp,sha256:ctSha,size:ciphertext.length,scope,http_metadata:http,custom_metadata:custom};
 const plan={format:FORMAT,operation_id:operation,source,target:{owner:targetOwner,key_id:env.DATA_KEY_ID},
  reservation:{key,scope,aad,key_id:env.DATA_KEY_ID,plaintext_sha256:objHash,source_fingerprint:sf},intent,object};
 const root=await realpath(await mkdtemp(join(await realpath(tmpdir()),'collect-history-test-')));
 const options=()=>{const planJson=canonical(plan);return {planJson,expectedPlanSha256:sha(planJson),root,journalKey,ciphertext,sourceKey,targetKey:Buffer.from(sourceKey)};};
 return {root,plan,options,sourceKey,journalKey,ciphertext,payload,plain};
}
async function use(body){const f=await fixture();try{return await body(f);}finally{f.sourceKey.fill(0);f.journalKey.fill(0);f.plain.fill(0);await rm(f.root,{recursive:true,force:true});}}

test('real application AES-GCM format can be checked and retained without emitting plaintext',()=>use(async f=>{
 const opts=f.options(),result=await retainOfflineWitness(opts);
 assert.equal(result.status,'witness_retained');assert.equal(result.target_owner_derives_same_source_id,false);
 assert.equal(result.external_dispatch,false);assert.equal(result.production_write_authorized,false);
 const dir=join(f.root,operation),files=await readdir(dir);assert.deepEqual(files.sort(),['artifact.enc','intent.enc','receipt.enc']);
 for(const name of files){const raw=await readFile(join(dir,name),'utf8');assert.doesNotMatch(raw,/SYNTHETIC-PRIVATE-SMS-Canary|synthetic-local-owner|synthetic-cloud-owner/);}
 const check=await reconcileOfflineWitness(opts);assert.equal(check.status,'witness_and_receipt_authenticated');assert.equal(check.automatic_retry,false);
 assert.equal((await retainOfflineWitness(opts)).status,'reconciliation_required');
}));

test('owner substitution does not prove identity; original and mapped source-ID derivation stay distinct',()=>use(async f=>{
 f.plan.target.owner=f.plan.source.owner;const r=await retainOfflineWitness(f.options());
 assert.equal(r.status,'witness_retained');assert.equal(r.target_owner_derives_same_source_id,true);assert.equal(r.production_write_authorized,false);
}));

test('bad metadata, mapping preimage, AAD, identity and pending storage are refused before creating a claim',async()=>{
 for(const mutate of [p=>p.reservation.aad+='x',p=>p.source.owner+='x',p=>p.intent.upload_unresolved=true,p=>p.intent.active_attempt='open',
  p=>p.object.fingerprint='0'.repeat(64),p=>p.target.key_id='wrong-key-id',p=>p.intent.scope.ownerId='another-owner']){
  await use(async f=>{mutate(f.plan);const out=await retainOfflineWitness(f.options());assert.equal(out.status,'refused');assert.deepEqual(await readdir(f.root),[]);});
 }
});

test('wrong destination key and wrong body digest retain a claim but never create an artifact',async()=>{
 await use(async f=>{const x=f.options();x.targetKey=randomBytes(32);const out=await retainOfflineWitness(x);
  assert.equal(out.status,'custody_incomplete_do_not_retry');assert.deepEqual(await readdir(join(f.root,operation)),['intent.enc']);
  assert.equal((await retainOfflineWitness(f.options())).status,'reconciliation_required');assert.equal((await reconcileOfflineWitness(f.options())).status,'custody_unconfirmed_do_not_retry');});
 await use(async f=>{f.plan.source.body_sha256='f'.repeat(64);const out=await retainOfflineWitness(f.options());
  assert.equal(out.status,'custody_incomplete_do_not_retry');assert.deepEqual(await readdir(join(f.root,operation)),['intent.enc']);});
});

test('changed ciphertext is refused after claim even if operation acknowledgement is lost',()=>use(async f=>{
 const x=f.options(),b=Buffer.from(x.ciphertext);b[b.length-2]^=1;x.ciphertext=b;
 assert.equal((await retainOfflineWitness(x)).status,'custody_incomplete_do_not_retry');
 assert.equal((await reconcileOfflineWitness(f.options())).status,'custody_unconfirmed_do_not_retry');
 assert.equal((await retainOfflineWitness(f.options())).status,'reconciliation_required');
}));

test('tampering and missing receipt cannot reconcile as a retained witness',async()=>{
 await use(async f=>{const x=f.options();assert.equal((await retainOfflineWitness(x)).status,'witness_retained');
  const path=join(f.root,operation,'artifact.enc'),data=await readFile(path);data[Math.floor(data.length/2)]^=1;await writeFile(path,data);
  assert.equal((await reconcileOfflineWitness(x)).status,'custody_unconfirmed_do_not_retry');});
 await use(async f=>{const x=f.options();assert.equal((await retainOfflineWitness(x)).status,'witness_retained');
  await unlink(join(f.root,operation,'receipt.enc'));assert.equal((await reconcileOfflineWitness(x)).status,'custody_unconfirmed_do_not_retry');
  assert.equal((await retainOfflineWitness(x)).status,'reconciliation_required');});
 await use(async f=>{const x=f.options();assert.equal((await retainOfflineWitness(x)).status,'witness_retained');
  await link(join(f.root,operation,'artifact.enc'),join(f.root,operation,'artifact-copy.enc'));
  assert.equal((await reconcileOfflineWitness(x)).status,'custody_unconfirmed_do_not_retry');});
});

test('shared buffers and a symlinked custody root are refused',async()=>{
 await use(async f=>{const x=f.options();x.journalKey=Buffer.from(new SharedArrayBuffer(32));
  assert.equal((await retainOfflineWitness(x)).status,'refused');assert.deepEqual(await readdir(f.root),[]);});
 await use(async f=>{const x=f.options(),alias=join(f.root,'alias');await symlink(f.root,alias);x.root=alias;
  assert.equal((await retainOfflineWitness(x)).status,'refused');assert.deepEqual(await readdir(f.root),['alias']);});
 await use(async f=>{const x=f.options();x.journalKey=Buffer.from(f.sourceKey);
  assert.equal((await retainOfflineWitness(x)).status,'refused');assert.deepEqual(await readdir(f.root),[]);});
});

test('same operation has one local witness claimant',()=>use(async f=>{
 const x=f.options(),results=await Promise.all([retainOfflineWitness(x),retainOfflineWitness(x)]);
 assert.deepEqual(results.map(v=>v.status).sort(),['reconciliation_required','witness_retained']);
 assert.equal((await reconcileOfflineWitness(x)).status,'witness_and_receipt_authenticated');
}));

test('managed dispatch is hard-refused and cannot call adapters',()=>{
 let called=false;const result=managedTransfer({connect(){called=true;},write(){called=true;}});
 assert.equal(result.status,'managed_transfer_unqualified');assert.equal(result.automatic_retry,false);assert.equal(result.external_dispatch,false);assert.equal(called,false);
});
