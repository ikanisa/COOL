import test from 'node:test';
import assert from 'node:assert/strict';
import {PostgresNativeAutoWorker,drainNativeAutoTransactions} from '../../domain/burimunsi/postgres-native-auto-worker.js';
import {MOMO_SCHEMA_VERSION} from '../../domain/momo_pipeline.js';
import {digest} from '../../domain/core.js';
import {canonicalJson,sha256} from '../../domain/burimunsi/values.js';

const group='11111111-1111-4111-8111-111111111111';
const sourceId='22222222-2222-4222-8222-222222222222';
const account={provider:'mtn_momo',status:'active',profile_status:'approved',profile_version:'synthetic-v1',currency:'RWF',timezone:'Africa/Kigali',
 profile_json:JSON.stringify({sender_allowlist:['Example Money'],currency_aliases:['RWF'],incoming_prefixes:['You have received'],
  transaction_id_prefixes:['Reference:'],outgoing_markers:['You have sent'],date_format:'YMD_HMS',utc_offset_minutes:120})};
const response={schema_version:MOMO_SCHEMA_VERSION,event_kind:'outgoing',payment_outcome:'successful',transaction_id_raw:'TX123',
 original_transaction_id_raw:null,transaction_datetime_raw:null,principal_amount_raw:'250',currency_raw:'RWF',payer_name_raw:'Example shop',
 payer_identifier_raw:null,payment_reference_raw:null,fee_amount_raw:null,wallet_balance_after_raw:null,
 evidence:{incoming_success:'You have sent',principal:'You have sent 250 RWF',transaction_id:'Reference: TX123',
  transaction_datetime:null,payer:'to Example shop',fee:null,wallet_balance_after:null},issues:[]};

async function fixture({body='You have sent 250 RWF to Example shop. Reference: TX123.',begun=true,dispatchFail=false,eventConflict=false,providerFail=false,invalid=false,retryAttempt=1,retryState='retry',providerResponse=response,notice=false}={}){
 const events=[],source={provenance:'native_observation_unverified',source_mode:'catch_up',complete:false,
  raw_sender:'Example Money',raw_body:body};
 const bytes=new TextEncoder().encode(JSON.stringify(source));
 const proof={id:sourceId,sourceId,principalUserId:'synthetic-owner',object_key:'sms/'+sourceId,
  object_sha256:await digest(bytes),bodySha256:await sha256(body),size_bytes:bytes.length,fingerprint:'a'.repeat(64)};
 const worker=Object.create(PostgresNativeAutoWorker.prototype);
 worker.groupId=group;worker.env={MOMO_AI_MODEL:'example-model',AI:{async run(_model,request){events.push('provider');
  assert.equal(request.provider_timeout_ms,8000);if(providerFail)throw Error('unknown provider outcome');return {response:invalid?'{}':JSON.stringify(providerResponse)};}}};
 const tx={async unsafe(query,values){
  if(query.includes('auto_begin')){events.push('begin');return [{result:{sourceId,state:'processing',started:begun}}];}
  if(query.includes('auto_dispatch')){events.push('dispatch');if(dispatchFail)throw Error('lost commit acknowledgement');return [{result:true}];}
  if(query.includes('auto_skip_security')){events.push('skip');return [{result:{sourceId,state:'security_message'}}];}
  if(query.includes('auto_retry')){events.push('retry');assert.ok(['provider_unavailable','invalid_output'].includes(values[4]));
   assert.equal(values[4],invalid?'invalid_output':'provider_unavailable');
   return [{result:{sourceId,state:retryState,attemptCount:retryAttempt,nextAttemptAt:retryState==='failed'?null:123456789}}];}
  if(query.includes('auto_event_bind')){events.push('event');assert.equal(values[0],sourceId);assert.equal(values[2],proof.fingerprint);
   assert.match(values[3].identity,/^[a-f0-9]{64}$/);assert.equal(typeof values[3].serviceTimePresent,'boolean');
   if(eventConflict)throw Object.assign(Error('event changed'),{code:'40001'});return [{result:true}];}
  if(query.includes('auto_finish')){events.push('finish');const facts=values[7];assert.equal(typeof facts,'object');
   if(notice){assert.equal(facts.event_kind,'other');assert.equal(facts.amount_minor,null);assert.deepEqual(values[6].issues,[]);assert.equal(values[6].evidence.payer,null);}
   else {assert.equal(facts.event_kind,'outgoing');assert.equal(facts.amount_minor,250);assert.equal(facts.provider_transaction_id,'TX123');}
   return [{result:{sourceId,state:'completed',relation:'accepted'}}];}
  throw Error('unexpected SQL');}};
 worker.authority={async write(fn){return fn(tx);}};
 worker.plan=async()=>({snapshot:{actor:{collectionId:group},proof,profile:{profileSha256:'b'.repeat(64),profile:account}},journal:{}});
 worker.verify=async()=>{events.push('verify');};
 worker.witnesses={async stage(){events.push('stage');return {};},async prefetch(){events.push('prefetch');},
  async sealed(){return 'sealed';},forget(){events.push('forget');}};
 worker.custody={async decrypt(){return bytes;}};
 return {worker,events,bytes};
}

test('an existing observation is parsed only after a durable dispatch and committed once',async()=>{
 const f=await fixture();assert.deepEqual(await f.worker.process(sourceId),{state:'completed',relation:'accepted'});
 assert.deepEqual(f.events,['stage','prefetch','verify','begin','verify','dispatch','provider','verify','event','finish','forget']);
 assert.equal(f.bytes.every(value=>value===0),true);
});
test('an event-binding conflict cannot finish or create a second canonical transaction',async()=>{
 const f=await fixture({eventConflict:true});await assert.rejects(f.worker.process(sourceId),/native_auto_source_changed/);
 assert.equal(f.events.includes('event'),true);assert.equal(f.events.includes('finish'),false);
 assert.equal(f.bytes.every(value=>value===0),true);
});
test('an existing active or dispatched job does not send the provider again',async()=>{
 const f=await fixture({begun:false});assert.deepEqual(await f.worker.process(sourceId),{state:'not_claimed'});
 assert.equal(f.events.includes('provider'),false);assert.equal(f.events.includes('finish'),false);
});
test('a lost dispatch acknowledgement never invokes the provider',async()=>{
 const f=await fixture({dispatchFail:true});await assert.rejects(f.worker.process(sourceId),/native_auto_unavailable/);
 assert.equal(f.events.includes('provider'),false);assert.equal(f.events.includes('finish'),false);
});
test('a provider failure or invalid output schedules an automatic retry without creating a transaction',async()=>{
 for(const option of [{providerFail:true},{invalid:true},{providerFail:true,retryAttempt:8}]){
  const f=await fixture(option),r=await f.worker.process(sourceId);
  assert.equal(r.state,'retry');assert.equal(f.events.includes('retry'),true);
  assert.equal(f.events.includes('finish'),false);assert.equal(f.events.filter(x=>x==='provider').length,1);
 }
});
test('repeated invalid model output retains the message for retry without finishing a transaction',async()=>{
 const f=await fixture({invalid:true,retryAttempt:5});
 assert.deepEqual(await f.worker.process(sourceId),{state:'retry'});
 assert.equal(f.events.filter(x=>x==='provider').length,1);
 assert.equal(f.events.includes('retry'),true);assert.equal(f.events.includes('event'),false);assert.equal(f.events.includes('finish'),false);
 assert.equal(f.bytes.every(value=>value===0),true);
});
test('a temporary provider outage continues to request retry without finishing a transaction',async()=>{
 const f=await fixture({providerFail:true,retryAttempt:50});
 assert.deepEqual(await f.worker.process(sourceId),{state:'retry'});
 assert.equal(f.events.filter(x=>x==='provider').length,1);assert.equal(f.events.includes('finish'),false);
});
test('security-code SMS is retained without sending it to the model',async()=>{
 const f=await fixture({body:'Your one-time code is 123456.'});
 assert.deepEqual(await f.worker.process(sourceId),{state:'security_message'});
 assert.equal(f.events.includes('skip'),true);assert.equal(f.events.includes('provider'),false);
});
test('a non-financial provider notice commits only normalized source-supported facts',async()=>{
 const output={...response,event_kind:'other',payment_outcome:'unknown',transaction_id_raw:null,principal_amount_raw:null,
  currency_raw:null,payer_name_raw:'service',evidence:{incoming_success:null,principal:null,transaction_id:null,
   transaction_datetime:null,payer:'model paraphrase',fee:null,wallet_balance_after:null},issues:['No transaction']};
 const f=await fixture({body:'Your service is available.',providerResponse:output,notice:true});
 assert.deepEqual(await f.worker.process(sourceId),{state:'completed',relation:'accepted'});
 assert.equal(f.events.includes('retry'),false);assert.equal(f.events.includes('finish'),true);
});
test('scheduler is disabled unless explicitly enabled and requires a jobs fence',async()=>{
 assert.deepEqual(await drainNativeAutoTransactions({},{}),{status:'disabled',processed:0,results:[]});
 await assert.rejects(drainNativeAutoTransactions({BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true'},{}),/native_auto_unconfigured/);
});
test('the jobs plan binds the exact group, source and committed storage descriptor',async()=>{
 const f=await fixture(),proof=(await f.worker.plan()).snapshot.proof;
 const snapshot={kind:'jobs',actor:{collectionId:group},proof,profile:{profileSha256:'b'.repeat(64),profile:account}};
 const namespace={origin:'https://example.invalid',bucket:'private'},keyId='key-1';
 const descriptor={scope:{ownerId:proof.principalUserId,purpose:'sms_receipt',entityId:sourceId},
  aad:`sms:${sourceId}:${proof.object_sha256}`,keyId,plaintextSha256:proof.object_sha256,requestDigest:proof.fingerprint,
  httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:proof.object_sha256,key_id:keyId}};
 const journal={reservation:{key_id:keyId,source_fingerprint:await sha256(canonicalJson(descriptor))}};
 const tx={unsafe:async q=>q.includes('auto_plan')?[{result:snapshot}]:[namespace]};
 const worker=Object.create(PostgresNativeAutoWorker.prototype);worker.groupId=group;
 worker.custody={namespace,journal:async()=>journal,sameJournal:(a,b)=>canonicalJson(a)===canonicalJson(b)};
 let sealed=0;worker.witnesses={sealed:async()=>{sealed++;}};
 const initial=await worker.plan(tx,sourceId);await worker.verify(tx,sourceId,initial,{});assert.equal(sealed,1);
 snapshot.actor.collectionId='another-group';await assert.rejects(worker.verify(tx,sourceId,initial,{}),/native_auto_source_changed/);
 assert.equal(sealed,1);
});
