import {test} from 'node:test';
import assert from 'node:assert/strict';
import {applicationWorkTuple,openApplicationWork} from '../../application-fence.js';
import {digest} from '../../domain/core.js';
import {canonicalJson,sha256} from '../../domain/burimunsi/values.js';
import {observationContentFingerprint} from '../../domain/burimunsi/postgres-observations.js';
import {PostgresNativeAuthority} from '../../domain/burimunsi/postgres-authority.js';
import {PostgresPostingCustody} from '../../domain/burimunsi/postgres-posting-custody.js';
import {PostgresStorageWitnesses} from '../../domain/burimunsi/postgres-storage-witnesses.js';
import {PostgresNativeFinancialCustody} from '../../domain/burimunsi/postgres-native-financial-custody.js';

const group='fixture-group',sourceId='11111111-1111-4111-8111-111111111111';
const jobId='22222222-2222-4222-8222-222222222222',leaseToken='33333333-3333-4333-8333-333333333333';
const owner='fixture-owner',accountId='fixture-wallet',transactionId='fixture-transaction';
const clone=v=>structuredClone(v),bytes=s=>new TextEncoder().encode(s);
const body='You have received RWF 1,500 from +250788111222. TxId: TX-556677. Receiver code: 48271.';
const profile={sender_allowlist:['SYNTHETIC-MOMO'],currency_aliases:['RWF'],incoming_prefixes:['You have received'],
 transaction_id_prefixes:['TxId:'],date_format:'YMD_HMS',utc_offset_minutes:120,
 recipient_rules:[{role:'recipient',kind:'public_code',prefix:'Receiver code: ',suffix:'.',digit_count:5,format:'digits'}]};
const output={schema_version:'momo-extraction.v1',event_kind:'incoming_receipt',payment_outcome:'successful',
 transaction_id_raw:'TX-556677',original_transaction_id_raw:null,transaction_datetime_raw:null,principal_amount_raw:'1,500',currency_raw:'RWF',
 payer_name_raw:null,payer_identifier_raw:'+250788111222',payment_reference_raw:null,fee_amount_raw:null,wallet_balance_after_raw:null,
 evidence:{incoming_success:'You have received RWF 1,500',principal:'You have received RWF 1,500',transaction_id:'TxId: TX-556677',
 transaction_datetime:null,payer:'from +250788111222',fee:null,wallet_balance_after:null},issues:[]};
async function fixture(t,{withoutConfirmation=false,sourceBody=body}={}){
 let row;const backend={async register(id,source,kind){row={contractVersion:1,admissionId:id,epoch:1,sourceSha256:source,state:'active',mode:'open',kind};return row;},
 async lease(){return{row,async assert(){return row;},async release(){}};},async close(_id,_epoch,_source,state,reason,externalDispatches,uncertainDispatches){row={...row,state,reason,externalDispatches,uncertainDispatches};return row;},async status(){return {...row,found:true};}};
 const work=await openApplicationWork({backend,sourceSha256:'a'.repeat(64),kind:'jobs'});t.after(async()=>work.finish());
 const tuple=applicationWorkTuple(work),payload={raw_sender:'SYNTHETIC-MOMO',raw_body:sourceBody,source_mode:'catch_up',complete:false,
 captured_at:'2026-11-13T11:01:00.000Z',service_centre_at:null,inbox_received_at:'2026-11-13T11:00:00.000Z',subscription_id:null,
 provenance:'native_observation_unverified'},raw=bytes(JSON.stringify(payload)),bodySha=await sha256(sourceBody),objectSha=await digest(raw);
 const contentSha=await observationContentFingerprint({rawSender:payload.raw_sender,serviceCentreAt:null,inboxReceivedAt:payload.inbox_received_at,subscriptionId:null},bodySha);
 const sourceKey='b'.repeat(64),fingerprint='c'.repeat(64),receiverHash=await sha256('48271'),cipher=JSON.stringify({v:1,kid:'fixture-key',data:'synthetic'}),cipherBytes=bytes(cipher),cipherHash=await digest(cipherBytes);
 const scope={ownerId:owner,purpose:'sms_receipt',entityId:sourceId},aad=`sms:${sourceId}:${objectSha}`;
 const descriptor={scope,aad,keyId:'fixture-key',plaintextSha256:objectSha,requestDigest:fingerprint,
  httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:objectSha,key_id:'fixture-key'}};
 const sourceFingerprint=await sha256(canonicalJson(descriptor)),customMetadata={...descriptor.customMetadata,source_fingerprint:sourceFingerprint};
 const put={object_key:'sms/'+sourceId,operation_id:'fixture-operation',fingerprint:'d'.repeat(64),sha256:cipherHash,size:cipherBytes.length,
  scope,http_metadata:descriptor.httpMetadata,custom_metadata:customMetadata,state:'committed',active_attempt:null,upload_unresolved:false,delete_tombstone:false};
 const metadata=Object.fromEntries(Object.entries(put).filter(([k])=>!['state','active_attempt','upload_unresolved','delete_tombstone'].includes(k)));
 const reservation={object_key:put.object_key,source_fingerprint:sourceFingerprint,scope,aad,key_id:'fixture-key',plaintext_sha256:objectSha,sealed_body:null};
 const claimed={contractVersion:1,kind:'native_receipt',groupId:group,sourceId,transactionId,jobId,workerGrantId:'fixture-grant',workerGrantVersion:1,
  owner:'fixture-worker',leaseToken,leaseVersion:1,leaseExpiresAt:1900000000000,admissionId:tuple[0],admissionEpoch:tuple[1],sourceCodeSha256:tuple[2],
  sourceKey,sourceKeyContentSha256:contentSha,sourceKeyBodySha256:bodySha,bodySha256:bodySha,objectSha256:objectSha,sourceFingerprint:fingerprint,
  ownerUserId:owner,objectSizeBytes:raw.length,transactionMode:'historical'};
 const proof={id:sourceId,sourceId,object_key:put.object_key,object_sha256:objectSha,bodySha256:bodySha,fingerprint,
  principalUserId:owner,size_bytes:raw.length};
 const transaction={id:transactionId,groupId:group,sourceId,receivingAccountId:accountId,provider:'mtn_momo',providerTransactionId:'TX-556677',
  eventKind:'incoming_receipt',paymentOutcome:'successful',amountMinor:1500,currency:'RWF',mode:'historical',allocationState:'unallocated',hasConflict:0,
  parseAttemptId:'fixture-attempt',parseOutput:clone(output),payerIdentifier:'+250788111222'};
 const account={id:accountId,provider:'mtn_momo',public_code:'48271',receiver_hash:receiverHash,status:'active',profile_status:'approved',
  profile_version:'fixture.v1',profile_json:JSON.stringify(profile),currency:'RWF',timezone:'Africa/Kigali'};
 const receipt={sourceId,groupId:group,ownerUserId:owner,bodySha256:bodySha,objectSha256:objectSha,objectSizeBytes:raw.length,
  sourceFingerprint:fingerprint,evidenceLevel:'client_received',transaction,account};
 const state={snapshot:{work:claimed,capture:{kind:'jobs',actor:{collectionId:group},proof},receipt},
  confirmation:withoutConfirmation?null:{kind:'independent_provider_receipt_v1',state:'settled',id:'fixture-confirmation',version:1,evidenceSha256:'e'.repeat(64),
   groupId:group,sourceId,sourceKey,bodySha256:bodySha,transactionId,receivingAccountId:accountId,receiverHash,provider:'mtn_momo',
   providerTransactionId:'TX-556677',eventKind:'incoming_receipt',amountMinor:1500,currency:'RWF'},
  put,metadata,reservation,raw,cipherBytes,cipherHash,customMetadata,mediaGets:0,denied:false};
 const namespace={origin:'https://fixture.example',bucket:'fixture'};
 const tx={async unsafe(sql){
  if(sql.includes('private.burimunsi_native_custody_snapshot')){if(state.denied)throw Object.assign(Error('revoked'),{code:'42501'});return[{result:clone(state.snapshot)}];}
  if(sql.includes('FROM private.storage_namespace'))return[clone(namespace)];
  if(sql.includes('FROM app.privacy_retention_barriers')||sql.includes('FROM private.storage_delete_intents'))return[];
  if(sql.includes('FROM private.storage_put_intents'))return[clone(state.put)];
  if(sql.includes('FROM private.storage_objects'))return[clone(state.metadata)];
  if(sql.includes('FROM private.storage_payload_reservations'))return[clone(state.reservation)];
  return [];
 }};
 const db={applicationWork:work,async transaction(fn){return fn(tx);},async context(){},async readContext(){}};
 const media={namespace,async get(key){state.mediaGets++;return{key,size:state.cipherBytes.length,sha256:state.cipherHash,httpMetadata:put.http_metadata,
  customMetadata:state.customMetadata,async arrayBuffer(){return state.cipherBytes.slice().buffer;}};}};
 const authority=new PostgresNativeAuthority({db,groupId:group});
 const witnesses=new PostgresStorageWitnesses({db,groupId:group,namespace,media,applicationWorkTuple});
 const custody=new PostgresPostingCustody({db,groupId:group,namespace,decrypt:async()=>state.raw.slice(),storageWitnesses:witnesses});
 state.confirmationCalls=[];
 const confirmation={async locked(...args){state.confirmationCalls.push(args);return clone(state.confirmation);}};
 const port=new PostgresNativeFinancialCustody({authority,custody,witnesses,confirmation});
 return {state,port,tx,cmd:{jobId,leaseToken,leaseVersion:1}};
}

test('a keyed catch-up source keeps its mode and needs independent settled-recipient evidence',async t=>{
 const f=await fixture(t),out=await f.port.prepare(f.cmd);assert.equal(out.state,'ready');
 const proof=await f.port.assertInTransaction(f.tx,out.proof);assert.equal(proof.sourceMode,'catch_up');assert.equal(proof.sourceComplete,false);
 assert.equal(proof.recipientEvidence,'provider_and_quote');assert.equal(f.state.mediaGets,1);assert.equal(Object.keys(out.proof).length,0);
 f.port.release(out.proof);await assert.rejects(()=>f.port.assertInTransaction(f.tx,out.proof));
});
test('independent provider recipient supports a source without recipient grammar',async t=>{
 const f=await fixture(t,{sourceBody:body.replace(' Receiver code: 48271.',' Thank you.')});
 const value={...profile};delete value.recipient_rules;f.state.snapshot.receipt.account.profile_json=JSON.stringify(value);
 const out=await f.port.prepare(f.cmd);assert.equal(out.state,'ready');
 const proof=await f.port.assertInTransaction(f.tx,out.proof);assert.equal(proof.recipientEvidence,'provider');f.port.release(out.proof);
});
test('the same digits under a different recipient type cannot impersonate the configured code',async t=>{
 const f=await fixture(t);f.state.snapshot.receipt.account.profile_json=JSON.stringify({...profile,
  recipient_rules:[{...profile.recipient_rules[0],kind:'account_number'}]});
 await assert.rejects(()=>f.port.prepare(f.cmd));
});
test('standard PIN safety advice remains usable without upgrading the retained source',async t=>{
 const f=await fixture(t,{sourceBody:body+' Never share your PIN.'});const out=await f.port.prepare(f.cmd);
 assert.equal(out.state,'ready');const proof=await f.port.assertInTransaction(f.tx,out.proof);
 assert.equal(proof.sourceMode,'catch_up');assert.equal(proof.sourceComplete,false);f.port.release(out.proof);
});
test('without a source-bound independent provider confirmation it does not fetch or admit',async t=>{
 const f=await fixture(t,{withoutConfirmation:true});assert.deepEqual(await f.port.prepare(f.cmd),{state:'unavailable'});assert.equal(f.state.mediaGets,0);
});
test('provider lookup receives only a scoped immutable identity',async t=>{
 const f=await fixture(t),out=await f.port.prepare(f.cmd);assert.equal(out.state,'ready');
 assert.ok(f.state.confirmationCalls.length>0);
 for(const [sql,identity,...extra] of f.state.confirmationCalls){
  assert.equal(sql,f.tx);assert.deepEqual(extra,[]);assert.ok(Object.isFrozen(identity));
  assert.deepEqual(Object.keys(identity).sort(),['admissionId','bodySha256','groupId','jobId','leaseVersion','sourceId','sourceKey','transactionId'].sort());
  assert.equal(identity.groupId,group);assert.equal(identity.sourceId,sourceId);assert.equal(identity.transactionId,transactionId);
 }
 f.port.release(out.proof);
});
for(const [name,change] of [
 ['legacy unkeyed source',s=>{s.snapshot.work.sourceKey=null;}],
 ['changed source/body key',s=>{s.snapshot.work.sourceKeyBodySha256='f'.repeat(64);}],
 ['changed capture grant or admission',s=>{s.snapshot.work.admissionEpoch=4;}],
 ['different collection',s=>{s.snapshot.work.groupId='other-group';}],
 ['different wallet',s=>{s.confirmation.receivingAccountId='other-wallet';}],
 ['different receipt reference',s=>{s.confirmation.providerTransactionId='OTHER';}],
 ['different receipt amount',s=>{s.confirmation.amountMinor=1501;}],
 ['different recipient',s=>{s.confirmation.receiverHash='f'.repeat(64);}],
 ['unsettled receipt',s=>{s.confirmation.state='pending';}],
 ['unverified receiving profile',s=>{s.snapshot.receipt.account.profile_status='unverified';}],
 ['unbound canonical source',s=>{s.snapshot.receipt.transaction.sourceId='other-source';}],
 ['historical upgraded to live',s=>{s.snapshot.work.transactionMode='live';s.snapshot.receipt.transaction.mode='live';}],
 ['transaction conflict',s=>{s.snapshot.receipt.transaction.hasConflict=1;}],
 ['provider profile changed after parsing',s=>{s.snapshot.receipt.account.profile_json=JSON.stringify({...profile,sender_allowlist:['OTHER']});}],
 ['corrupted storage source fingerprint',s=>{s.reservation.source_fingerprint='f'.repeat(64);}],
 ['invalid encrypted bytes',s=>{s.cipherBytes[0]^=1;}],
]) test('custody refuses '+name,async t=>{const f=await fixture(t);change(f.state);await assert.rejects(()=>f.port.prepare(f.cmd));});
test('revoked native lease after preflight cannot reuse an otherwise valid proof',async t=>{
 const f=await fixture(t),out=await f.port.prepare(f.cmd);assert.equal(out.state,'ready');f.state.denied=true;
 await assert.rejects(()=>f.port.assertInTransaction(f.tx,out.proof));f.port.release(out.proof);
});
test('a changed provider record after preflight cannot authorize the original proof',async t=>{
 const f=await fixture(t),out=await f.port.prepare(f.cmd);assert.equal(out.state,'ready');f.state.confirmation.version++;
 await assert.rejects(()=>f.port.assertInTransaction(f.tx,out.proof));f.port.release(out.proof);
});
test('a caller-created object cannot impersonate a custody proof',async t=>{
 const f=await fixture(t);await assert.rejects(()=>f.port.assertInTransaction(f.tx,Object.freeze({verified:true})));
});
test('a shorter model reference must not match a longer visible reference',async t=>{
 const f=await fixture(t),tx=f.state.snapshot.receipt.transaction;
 tx.providerTransactionId='TX-5566';tx.parseOutput.transaction_id_raw='TX-5566';tx.parseOutput.evidence.transaction_id='TxId: TX-5566';
 f.state.confirmation.providerTransactionId='TX-5566';
 await assert.rejects(()=>f.port.prepare(f.cmd));
});
test('a shorter model amount must not match a longer visible amount',async t=>{
 const f=await fixture(t),tx=f.state.snapshot.receipt.transaction;
 tx.amountMinor=1;tx.parseOutput.principal_amount_raw='1';tx.parseOutput.evidence.incoming_success='You have received RWF 1';
 tx.parseOutput.evidence.principal='You have received RWF 1';f.state.confirmation.amountMinor=1;
 await assert.rejects(()=>f.port.prepare(f.cmd));
});
test('a shorter payer phone must not match the beginning of a longer visible token',async t=>{
 const f=await fixture(t,{sourceBody:body.replace('+250788111222','+2507881112229')});
 await assert.rejects(()=>f.port.prepare(f.cmd));
});
