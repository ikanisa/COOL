import test from 'node:test';
import assert from 'node:assert/strict';
import {openApplicationWork} from '../../application-fence.js';
import {qualifyNativeFinancialWork as scheduledNativeFinancialWork,scheduledNativeFinancialWork as productionScheduler} from '../../scheduled-native-financial-work.js';

const SHA='a'.repeat(64),APPROVAL='b'.repeat(64),GROUP='synthetic-group';
const GRANT='11111111-1111-4111-8111-111111111111',SOURCE='22222222-2222-4222-8222-222222222222',JOB='33333333-3333-4333-8333-333333333333';
function backend(){const rows=new Map();return {rows,async register(id,source,kind){const r={contractVersion:1,admissionId:id,epoch:1,sourceSha256:source,state:'active',mode:'open',kind};rows.set(id,r);return {...r};},
 async lease(id){return {row:{...rows.get(id)},async assert(){return {...rows.get(id)};},async release(){}};},
 async close(id,epoch,source,state,reason,externalDispatches,uncertainDispatches){const r={...rows.get(id),state,reason,externalDispatches,uncertainDispatches};rows.set(id,r);return {...r};},async status(id){return {...rows.get(id),found:rows.has(id)};}};}
async function fixture(run){
 const b=backend(),work=await openApplicationWork({backend:b,sourceSha256:SHA,kind:'jobs'});
 const env={DB:{applicationWork:work},BUILD_SOURCE_ID:SHA,BURIMUNSI_NATIVE_ENABLED:'true',BURIMUNSI_NATIVE_WORKERS_ENABLED:'true',
  BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true',BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED:'true',MOMO_PROCESSING_PAUSED:'false',
  MOMO_AI_ENABLED:'true',MOMO_AI_MODEL:'synthetic-model',OPENAI_API_KEY:'synthetic-only',COLLECT_JOBS_MODE:'receipt_processing_v1',
  COLLECT_JOBS_PROCESSING_APPROVAL_SHA256:APPROVAL};
 const admission={allowed:true,processing:{contract:'collect.receipt-processing.v1',source_sha256:SHA,approval_sha256:APPROVAL,model_id:'synthetic-model',batch_limit:1}};
 const state={find:0,sources:0,enqueued:0,claims:0,deferred:0,now:0,leasedUntil:0};
 const jobs={async sources(){state.sources++;return [SOURCE];},async enqueue(grant,id){assert.equal(grant,GRANT);assert.equal(id,SOURCE);state.enqueued++;return {durable:true,state:'queued'};},
  async candidates(){return state.leasedUntil>state.now?[]:[JOB];},async claim(grant,id){assert.equal(grant,GRANT);assert.equal(id,JOB);state.claims++;state.leasedUntil=state.now+180000;return {jobId:JOB,leaseToken:'44444444-4444-4444-8444-444444444444',leaseVersion:state.claims};},
  async defer(_lease,reason,delay){assert.equal(reason,'evidence_unavailable');assert.equal(delay,300000);state.deferred++;state.leasedUntil=state.now+delay;return {state:'waiting'};}};
 const options={find:async()=>{state.find++;return [{groupId:GROUP,grantId:GRANT}];},makeJobs:(_env,group)=>{assert.equal(group,GROUP);return jobs;}};
 try{await run({env,admission,state,jobs,options,b,work});}finally{await work.finish();}
}

test('production scheduler cannot activate with unreviewed multi-subject retention',async()=>{
 assert.equal(await productionScheduler({}),null);
 assert.deepEqual(await productionScheduler({BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED:'true',MOMO_PROCESSING_PAUSED:'true'}),{status:'paused'});
 assert.deepEqual(await productionScheduler({BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED:'true',MOMO_PROCESSING_PAUSED:'false'}),
  {status:'held',code:'retention_scope_unapproved'});
});

test('default-off and global pause perform no queue work',()=>fixture(async({env,admission,state,options})=>{
 delete env.BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED;assert.equal(await scheduledNativeFinancialWork(env,admission,options),null);
 env.BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED='true';env.MOMO_PROCESSING_PAUSED='true';
 assert.deepEqual(await scheduledNativeFinancialWork(env,admission,options),{status:'paused'});assert.equal(state.find,0);
}));
test('admitted lane enqueues and defers without exposing data or invoking a writer',()=>fixture(async({env,admission,state,options})=>{
 const r=await scheduledNativeFinancialWork(env,admission,options);assert.deepEqual(r,{status:'held',code:'independent_evidence_unavailable'});
 assert.equal(state.enqueued,1);assert.equal(state.claims,1);assert.equal(state.deferred,1);assert(!JSON.stringify(r).includes(SOURCE));
}));
test('missing processing approval, wrong source and disabled runtime never start work',()=>fixture(async({env,admission,state,options})=>{
 for(const change of [()=>admission.allowed=false,()=>admission.processing.source_sha256='c'.repeat(64),()=>env.BURIMUNSI_NATIVE_WORKERS_ENABLED='false']){
  const old={allowed:admission.allowed,source:admission.processing.source_sha256,flag:env.BURIMUNSI_NATIVE_WORKERS_ENABLED};change();
  assert.equal((await scheduledNativeFinancialWork(env,admission,options)).status,'unconfirmed');
  admission.allowed=old.allowed;admission.processing.source_sha256=old.source;env.BURIMUNSI_NATIVE_WORKERS_ENABLED=old.flag;
 }
 assert.equal(state.find,0);
}));
test('pause changing after a read prevents enqueue or claim',()=>fixture(async({env,admission,state,jobs,options})=>{
 jobs.sources=async()=>{env.MOMO_PROCESSING_PAUSED='true';return [SOURCE];};
 assert.equal((await scheduledNativeFinancialWork(env,admission,options)).status,'unconfirmed');assert.equal(state.enqueued,0);assert.equal(state.claims,0);
}));
test('changed processing mode or admission during a read cannot authorize enqueue',()=>fixture(async({env,admission,state,jobs,options})=>{
 const saved=admission.processing;jobs.sources=async()=>{admission.processing={...saved};return [SOURCE];};
 assert.equal((await scheduledNativeFinancialWork(env,admission,options)).status,'unconfirmed');assert.equal(state.enqueued,0);
 admission.processing=saved;jobs.sources=async()=>{env.COLLECT_JOBS_MODE='receipt_and_push_v1';return [SOURCE];};
 assert.equal((await scheduledNativeFinancialWork(env,admission,options)).status,'unconfirmed');assert.equal(state.enqueued,0);
}));
test('a stopped worker leaves its lease for expiry and a later run can reclaim it',()=>fixture(async({env,admission,state,jobs,options})=>{
 const claim=jobs.claim;jobs.claim=async(...args)=>{const lease=await claim(...args);env.MOMO_PROCESSING_PAUSED='true';return lease;};
 assert.equal((await scheduledNativeFinancialWork(env,admission,options)).status,'unconfirmed');assert.equal(state.claims,1);assert.equal(state.deferred,0);
 env.MOMO_PROCESSING_PAUSED='false';jobs.claim=claim;state.now=180001;
 assert.equal((await scheduledNativeFinancialWork(env,admission,options)).status,'held');assert.equal(state.claims,2);assert.equal(state.deferred,1);
}));
test('revoked source is skipped without leaking its error or starting a financial writer',()=>fixture(async({env,admission,state,jobs,options})=>{
 jobs.enqueue=async()=>{const e=new Error('private synthetic text');e.code='42501';throw e;};jobs.candidates=async()=>[];
 const r=await scheduledNativeFinancialWork(env,admission,options);assert.deepEqual(r,{status:'idle'});assert.equal(state.claims,0);assert(!JSON.stringify(r).includes('private'));
}));
