import test from 'node:test';
import assert from 'node:assert/strict';
import {preparedFlow,ids,count} from './prepared-contribution-fixture.mjs';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
import {composeNativeContributions} from '../../domain/burimunsi/compose.js';
import {processReceiptBatch} from '../../domain/burimunsi/worker.js';
import {processRematchBatch} from '../../domain/burimunsi/rematch-worker.js';
import {profile,fullSource} from './fixtures.mjs';
const unused=()=>{throw Error('unexpected unrelated adapter');};
function handler(f){return createNativeHandler({
 auth:{login:unused,authenticate:async()=>f.actor,logout:unused,changePasscode:unused,manageStaff:unused},
 records:{home:unused,page:unused,detail:unused,exportLedger:unused,commandStatus:unused},
 members:{enroll:unused,setActive:unused},gateway:{status:unused,replace:unused},
 contributions:f.service,origin:'https://example.test',networkBucket:unused
});}
function request(f,extra={}){return new Request('https://example.test/v1/burimunsi/payments/'+f.command.receiptId+'/allocate',{
 method:'POST',headers:{'content-type':'application/json','x-burimunsi-installation':'test-device','authorization':'Bearer '+'a'.repeat(64),
  'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':crypto.randomUUID(),'x-burimunsi-generation':'1'},
 body:JSON.stringify({memberId:ids.member,expectedVersion:3,note:'Verified original source and identity',requestId:ids.request,...extra})});}

test('native HTTP allocation route runs preparation and returns only canonical public result',async()=>{
 const f=await preparedFlow('exception');try{const h=handler(f),r=await h(request(f)),body=await r.json();
  assert.equal(r.status,200);assert.equal(body.data.amountRwf,12500);assert.equal(body.data.memberId,ids.member);
  assert.equal(f.state.puts,1);assert.equal(count(f,'app.ledger_entries'),1);
  for(const secret of ['sealed_body','objectKey','principalUserId','identityIds','requestDigest','raw_body'])assert.equal(JSON.stringify(body).includes(secret),false,secret);
  const replay=await h(request(f));assert.equal(replay.status,200);assert.equal(f.state.puts,1);
 }finally{f.close();}
});
for(const key of ['objectKey','actor','receipt','policyVersion','work'])test('HTTP rejects client-supplied preparation '+key,async()=>{
 const f=await preparedFlow('exception');try{const r=await handler(f)(request(f,{[key]:'forged'}));
  assert.equal(r.status,400);assert.equal(f.state.puts,0);assert.equal(count(f,'app.ledger_entries'),0);
 }finally{f.close();}
});
test('HTTP preparation failure is redacted, retryable and never a successful credit',async()=>{
 const f=await preparedFlow('exception');try{f.media.put=async()=>{throw Error('SECRET provider request');};
  const r=await handler(f)(request(f));assert.equal(r.status,503);
  assert.deepEqual(await r.json(),{ok:false,error:{code:'posting_preparation_unavailable'}});assert.equal(count(f,'app.ledger_entries'),0);
 }finally{f.close();}
});

// Real worker and preparation/posting paths; queue claim/ingestion/checkpoints
// below are synthetic adapters. Not evidence of a connected production scheduler.
function receiptWorker(f){let pending=true;const events=[];
 const job={id:crypto.randomUUID(),owner:'worker-1',groupId:ids.group,profileVersion:profile.version,receivingAccountId:'wallet-1',leaseVersion:1,attempt:1,maxAttempts:4};
 const store={assertProcessingAdmission:async()=>{},claimNext:async()=>{if(!pending)return null;pending=false;return job;},
  loadSource:async()=>({...fullSource,groupId:ids.group,receivingAccountId:'wallet-1'}),
  commitCanonicalReceipt:async()=>({durable:true,transactionId:f.command.receiptId,hasConflict:false}),
  finishJob:async c=>{events.push(['finish',c]);return {applied:true};},failJob:async c=>{events.push(['fail',c]);return {applied:true,state:'retry'};}};
 return {events,run:()=>processReceiptBatch({store,contributions:f.service,groupId:ids.group,owner:'worker-1',profile})};
}
test('receipt worker invokes connected preparation then posting before its completion checkpoint',async()=>{
 const f=await preparedFlow();try{const w=receiptWorker(f),r=await w.run();
  assert.equal(r.posted,1);assert.equal(r.retained,1);assert.equal(w.events[0][0],'finish');
  assert.equal(f.state.plans[0].work.kind,'receipt');assert.equal(f.state.puts,1);assert.equal(count(f,'app.ledger_entries'),1);
 }finally{f.close();}
});
test('receipt worker retries failed preparation without a completion checkpoint',async()=>{
 const f=await preparedFlow();try{f.media.put=async()=>{throw Error('SECRET');};const w=receiptWorker(f),r=await w.run();
  assert.equal(r.retry,1);assert.equal(r.posted,0);assert.equal(w.events[0][0],'fail');assert.equal(count(f,'app.ledger_entries'),0);
 }finally{f.close();}
});
function rematchWorker(f){let pending=true,target=true;const events=[];
 const job={id:crypto.randomUUID(),owner:'worker-1',groupId:ids.group,state:'running',memberId:ids.member,policyVersion:'verified-test-v1',leaseVersion:1,attempt:1,maxAttempts:4};
 const store={claimNext:async()=>{if(!pending)return null;pending=false;return job;},
  nextTarget:async()=>{if(!target)return null;target=false;return {transactionId:f.command.receiptId,outcome:null};},
  advanceTarget:async()=>{assert.equal(f.outcomes.length,1);events.push('advance');return {applied:true,outcome:'posted'};},
  yieldJob:async()=>({applied:true}),failJob:async()=>{events.push('fail');return {applied:true,state:'retry'};}};
 return {events,run:()=>processRematchBatch({store,contributions:f.service,groupId:ids.group,owner:'worker-1'})};
}
test('enrollment-rematch worker prepares, posts, retains outcome and then advances',async()=>{
 const f=await preparedFlow();try{const w=rematchWorker(f),r=await w.run();
  assert.equal(r.postedObservations,1);assert.equal(r.completed,1);assert.deepEqual(w.events,['advance']);
  assert.equal(f.state.plans[0].work.kind,'rematch');assert.equal(f.outcomes.length,1);assert.equal(count(f,'app.ledger_entries'),1);
 }finally{f.close();}
});
test('rematch preparation failure has no retained outcome/checkpoint or financial effect',async()=>{
 const f=await preparedFlow();try{f.media.put=async()=>{throw Error('SECRET');};const w=rematchWorker(f),r=await w.run();
  assert.equal(r.retry,1);assert.equal(r.postedObservations,0);assert.deepEqual(w.events,['fail']);
  assert.equal(f.outcomes.length,0);assert.equal(count(f,'app.ledger_entries'),0);
 }finally{f.close();}
});
for(const flag of ['true',1,null])test('shared contribution factory rejects non-boolean preparation switch '+JSON.stringify(flag),()=>{
 assert.throws(()=>composeNativeContributions({config:{enabled:true,groupId:ids.group,postingPreparationEnabled:flag},ports:{canonical:{inCanonicalTransaction:unused}}}),/invalid_worker_config/);
});
test('shared contribution factory refuses missing enabled preparation instead of bypassing it',()=>{
 assert.throws(()=>composeNativeContributions({config:{enabled:true,groupId:ids.group,postingPreparationEnabled:true},ports:{canonical:{inCanonicalTransaction:unused}}}),/collect_adapter_required/);
});
test('disabled preparation preserves explicit legacy selection',()=>{
 const c=composeNativeContributions({config:{enabled:true,groupId:ids.group,postingPreparationEnabled:false},ports:{canonical:{inCanonicalTransaction:unused},preparation:{prepare:unused}}});
 assert.equal(c.preparation,null);
});

test('native request composition actually forwards the enabled preparation port',async()=>{
 const {composeNativeRequest}=await import('../../domain/burimunsi/compose.js');
 const f=await preparedFlow('exception');try{
  const auth={};for(const k of ['consumeAttempts','findAccount','findDeviceGrant','createSessionIfCurrent','changePinIfCurrent','mutateStaff','findStaff','retainedStaffCommand','revokeSession'])auth[k]=unused;
  auth.loadSession=async()=>f.actor;
  const h=composeNativeRequest({admission:{verified:true,groupId:ids.group},
   config:{enabled:true,groupId:ids.group,origin:'https://example.test',postingPreparationEnabled:true},
   ports:{auth,canonical:f.store,preparation:f.preparation,records:{withReadSnapshot:unused},gateway:{withAuthorityTransaction:unused,withReadSnapshot:unused}},
   secrets:{pinPepper:new Uint8Array(32).fill(1),pinPepperId:'synthetic-only',cursorKey:new Uint8Array(32).fill(2)},networkBucket:unused});
  const reply=await h(request(f));assert.equal(reply.status,200);assert.equal(f.state.puts,1);assert.equal(count(f,'app.ledger_entries'),1);
 }finally{f.close();}
});
