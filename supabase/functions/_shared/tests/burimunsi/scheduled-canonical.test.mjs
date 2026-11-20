import test from 'node:test';
import assert from 'node:assert/strict';
import {canonicalSchedulerApproval,scheduledCanonicalDrain} from '../../scheduled-canonical.js';

async function fixture(){
 const env={BUILD_SOURCE_ID:'a'.repeat(64),BURIMUNSI_NATIVE_ENABLED:'true',BURIMUNSI_NATIVE_WORKERS_ENABLED:'true',
  BURIMUNSI_CANONICAL_SCHEDULER_ENABLED:'true',BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID:'group-1',
  BURIMUNSI_CANONICAL_SCHEDULER_OWNER:'worker-1',BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN:'abcdefghijklmnop.qrstuvwxyz123456.abcdefghijklmno',
  MOMO_PROCESSING_PAUSED:'false',MOMO_AI_ENABLED:'true',OPENAI_API_KEY:'synthetic-never-sent',
  COLLECT_JOBS_MODE:'receipt_processing_v1',MOMO_AI_MODEL:'synthetic-model',COLLECT_JOBS_PROCESSING_APPROVAL_SHA256:'b'.repeat(64)};
 env.BURIMUNSI_CANONICAL_SCHEDULER_APPROVAL_SHA256=await canonicalSchedulerApproval({sourceSha256:env.BUILD_SOURCE_ID,
  collectionId:env.BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID,owner:env.BURIMUNSI_CANONICAL_SCHEDULER_OWNER});
 const admission={allowed:true,processing:{contract:'collect.receipt-processing.v1',source_sha256:env.BUILD_SOURCE_ID,
  approval_sha256:env.COLLECT_JOBS_PROCESSING_APPROVAL_SHA256,model_id:env.MOMO_AI_MODEL,batch_limit:1}};
 return {env,admission};
}

test('approval digest uses the shared self-hosted configuration contract',async()=>{
 assert.equal(await canonicalSchedulerApproval({sourceSha256:'a'.repeat(64),collectionId:'synthetic-group',owner:'synthetic-worker'}),
  '24391e43b41ddcd13a15750ded18373987d518ced2aec465a33447be796f46fb');
});

test('disabled scheduler does not invoke or expose a financial worker',async()=>{
 for(const flag of [undefined,'false','TRUE',true]){
  const {env,admission}=await fixture();env.BURIMUNSI_CANONICAL_SCHEDULER_ENABLED=flag;
  let calls=0;assert.equal(await scheduledCanonicalDrain(env,admission,{runCycle:async()=>{calls++;}}),null);assert.equal(calls,0);
 }
});

test('an exact admitted release invokes only the server-configured scope and redacts its result',async()=>{
 const {env,admission}=await fixture();let calls=0;
 const actual=await scheduledCanonicalDrain(env,admission,{runCycle:async(input,options)=>{
  calls++;assert.equal(input,env);assert.deepEqual(options,{collectionId:'group-1',owner:'worker-1',
   managedAccessToken:env.BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN});
  return {status:'completed',runId:'private-id',receipts:{posted:1,raw_body:'private message'}};
 }});
 assert.deepEqual(actual,{status:'complete'});assert.equal(calls,1);
 assert.equal(JSON.stringify(actual).includes('private'),false);
});

test('pause, changed source or group, absent admission, invalid credential and missing approval all refuse work',async()=>{
 const mutations=[
  f=>{f.env.MOMO_PROCESSING_PAUSED='true';},f=>{f.admission.allowed=false;},f=>{f.admission.processing=null;},
  f=>{f.admission.processing.batch_limit=2;},f=>{f.admission.processing.source_sha256='c'.repeat(64);},
  f=>{f.env.BURIMUNSI_NATIVE_WORKERS_ENABLED='false';},f=>{f.env.BURIMUNSI_NATIVE_ENABLED='false';},
  f=>{f.env.MOMO_AI_ENABLED='false';},f=>{f.env.OPENAI_API_KEY='';},f=>{f.env.COLLECT_JOBS_MODE='maintenance_only';},
  f=>{f.env.BURIMUNSI_COLLECTION_ID='other-group';},f=>{f.env.BURIMUNSI_CANONICAL_SCHEDULER_OWNER='other-worker';},
  f=>{f.env.BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN='not-a-managed-token';},
  f=>{f.env.BURIMUNSI_CANONICAL_SCHEDULER_APPROVAL_SHA256='c'.repeat(64);},
 ];
 for(const mutate of mutations){const f=await fixture();mutate(f);let calls=0;
  assert.deepEqual(await scheduledCanonicalDrain(f.env,f.admission,{runCycle:async()=>{calls++;}}),
   {status:'unconfirmed',code:'canonical_scheduler_unavailable'});assert.equal(calls,0);}
});

test('busy and yielded are not reported as completed, and errors are redacted',async()=>{
 for(const [response,expected] of [[{status:'busy'},{status:'busy'}],[{status:'yielded'},{status:'yielded'}],
  [{status:'stopped'},{status:'unconfirmed',code:'canonical_scheduler_unavailable'}]]){
  const f=await fixture();assert.deepEqual(await scheduledCanonicalDrain(f.env,f.admission,{runCycle:async()=>response}),expected);
 }
 const f=await fixture(),result=await scheduledCanonicalDrain(f.env,f.admission,{runCycle:async()=>{throw Error('private credential');}});
 assert.deepEqual(result,{status:'unconfirmed',code:'canonical_scheduler_unavailable'});
});
