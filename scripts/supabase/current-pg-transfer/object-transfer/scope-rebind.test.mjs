import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonical,ProtectedStorageProtocol} from '../../../../supabase/functions/_shared/storage/protocol.js';
import {calculateSyntheticScopeRebind,SCOPE_REBIND_FORMAT} from './scope-rebind.mjs';

const hash=text=>createHash('sha256').update(text).digest('hex');
const serialize=plan=>canonical(plan);
const run=plan=>{const body=serialize(plan);return calculateSyntheticScopeRebind(body,hash(body));};
function fixture(purpose){
 const prefix=purpose==='sms_receipt'?'sms':'evidence',entityId='synthetic-entity',bytes=Buffer.from('synthetic ciphertext');
 const scope={ownerId:'synthetic-local-owner',entityId,purpose},keyId='synthetic-key',plaintextSha256='a'.repeat(64);
 const customMetadata={sha256:plaintextSha256,key_id:keyId},httpMetadata={contentType:'application/octet-stream'};
 const descriptor={scope,aad:prefix+':'+entityId+':'+plaintextSha256,keyId,plaintextSha256,
  requestDigest:'b'.repeat(64),httpMetadata,customMetadata};
 const sourceFingerprint=hash(canonical(descriptor)),key=prefix+'/'+entityId,operationId='synthetic-operation';
 const intentDescriptor={key,size:bytes.length,sha256:hash(bytes),scope,httpMetadata,
  customMetadata:{...customMetadata,source_fingerprint:sourceFingerprint}};
 const fingerprint=hash(canonical(intentDescriptor));
 return {bytes,plan:{format:SCOPE_REBIND_FORMAT,mode:'synthetic',
  mapping:{sourceOwner:scope.ownerId,targetOwner:'synthetic-cloud-owner',decisionSha256:'c'.repeat(64)},
  reservation:{...descriptor,sourceFingerprint},intent:{...intentDescriptor,operationId,fingerprint,state:'committed'},
  object:{...intentDescriptor,operationId,fingerprint}}};
}

test('synthetic owner rebind reproduces Storage fingerprints while preserving ciphertext identity',async t=>{
 for(const purpose of ['sms_receipt','payment_evidence'])await t.test(purpose,async()=>{
  const {bytes,plan}=fixture(purpose),before=serialize(plan),candidate=run(plan);
  assert.equal(serialize(plan),before);
  assert.equal(candidate.status,'synthetic_candidate');assert.equal(candidate.writeAuthorized,false);
  assert.equal(candidate.reservation.scope.ownerId,'synthetic-cloud-owner');
  assert.equal(candidate.reservation.aad,plan.reservation.aad);
  assert.equal(candidate.reservation.requestDigest,plan.reservation.requestDigest);
  assert.notEqual(candidate.reservation.sourceFingerprint,plan.reservation.sourceFingerprint);
  assert.notEqual(candidate.intent.fingerprint,plan.intent.fingerprint);
  assert.equal(candidate.object.fingerprint,candidate.intent.fingerprint);
  assert.equal(candidate.intent.key,plan.intent.key);assert.equal(candidate.intent.sha256,plan.intent.sha256);
  assert.equal(candidate.intent.operationId,plan.intent.operationId);
  assert.equal(candidate.intent.customMetadata.source_fingerprint,candidate.reservation.sourceFingerprint);
  const protocol=new ProtectedStorageProtocol({transport:{},journal:{}});
  const actual=(await protocol.describe(candidate.intent.key,bytes,{scope:candidate.intent.scope,
   httpMetadata:candidate.intent.httpMetadata,customMetadata:candidate.intent.customMetadata,
   operationId:candidate.intent.operationId})).intent;
  assert.equal(actual.fingerprint,candidate.intent.fingerprint);
  assert.ok(Object.isFrozen(candidate)&&Object.isFrozen(candidate.reservation.scope));
 });
});

test('scope rebind cannot authorize a managed environment or a changed plan',()=>{
 const {plan}=fixture('sms_receipt');plan.mode='managed';assert.throws(()=>run(plan),{code:'scope_rebind_managed_unqualified'});
 plan.mode='synthetic';const body=serialize(plan);assert.throws(()=>calculateSyntheticScopeRebind(body,'0'.repeat(64)),{code:'scope_rebind_plan_refused'});
 const duplicate=body.replace('"mode":"synthetic"','"mode":"synthetic","mode":"synthetic"');
 assert.notEqual(duplicate,body);assert.throws(()=>calculateSyntheticScopeRebind(duplicate,hash(duplicate)),{code:'scope_rebind_plan_refused'});
});

for(const [name,mutate] of [
 ['source reservation fingerprint',p=>p.reservation.sourceFingerprint='0'.repeat(64)],
 ['request digest',p=>p.reservation.requestDigest='0'.repeat(64)],
 ['intent fingerprint',p=>p.intent.fingerprint='0'.repeat(64)],
 ['object fingerprint',p=>p.object.fingerprint='0'.repeat(64)],
 ['object scope',p=>p.object.scope={...p.object.scope,ownerId:'another-owner'}],
 ['associated data',p=>p.reservation.aad='sms:other:'+p.reservation.plaintextSha256],
 ['ciphertext size',p=>p.object.size++],
 ['same owner',p=>p.mapping.targetOwner=p.mapping.sourceOwner],
 ['invalid UTF-8 owner',p=>p.mapping.targetOwner='\ud800'],
 ['uncommitted intent',p=>p.intent.state='pending'],
])test('scope rebind refuses changed '+name,()=>{
 const {plan}=fixture('sms_receipt');mutate(plan);assert.throws(()=>run(plan),{code:'scope_rebind_preimage_refused'});
});
