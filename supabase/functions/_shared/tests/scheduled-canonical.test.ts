import {assertEquals} from 'jsr:@std/assert@1.0.14';
import {fencedTest,SYNTHETIC_FENCE_SOURCE} from './helpers/fenced-unit.js';
import {createScheduledHandler} from './helpers/fenced-handler.js';
import {canonicalSchedulerApproval} from '../scheduled-canonical.js';

const contract={contract:'collect.receipt-processing.v1',source_sha256:SYNTHETIC_FENCE_SOURCE,
 approval_sha256:'b'.repeat(64),model_id:'synthetic-model',batch_limit:1};
const cleanup=async()=>({status:'complete',examined_limit:100,purged:0,provider_calls:0});
const receipts=async()=>({processed:0,results:[],paused:false});
const request=()=>new Request('https://fixture.example/functions/v1/collect-jobs',{method:'POST',
 headers:{Authorization:'Bearer synthetic-job-token','Content-Type':'application/json'},
 body:JSON.stringify({dispatch_id:crypto.randomUUID(),processing_admission:contract})});
async function environment(){return {SUPABASE_URL:'https://rrlduytparvsjfmegalh.supabase.co',
 COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test',
 SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret',APP_ENVIRONMENT:'test',
 FIXTURE_JOB_TOKEN:'synthetic-job-token',COLLECT_JOBS_MODE:'receipt_processing_v1',
 COLLECT_JOBS_PROCESSING_APPROVAL_SHA256:contract.approval_sha256,MOMO_PROCESSING_PAUSED:'false',
 MOMO_AI_ENABLED:'true',MOMO_AI_MODEL:contract.model_id,OPENAI_API_KEY:'synthetic-never-sent',
 BURIMUNSI_NATIVE_ENABLED:'true',BURIMUNSI_NATIVE_WORKERS_ENABLED:'true',
 BURIMUNSI_CANONICAL_SCHEDULER_ENABLED:'true',BURIMUNSI_CANONICAL_SCHEDULER_COLLECTION_ID:'synthetic-group',
 BURIMUNSI_CANONICAL_SCHEDULER_OWNER:'synthetic-worker',
 BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN:'abcdefghijklmnop.qrstuvwxyz123456.abcdefghijklmno',
 BURIMUNSI_CANONICAL_SCHEDULER_APPROVAL_SHA256:await canonicalSchedulerApproval({sourceSha256:SYNTHETIC_FENCE_SOURCE,
  collectionId:'synthetic-group',owner:'synthetic-worker'})};}

fencedTest('canonical worker stays absent from the response and untouched when disabled',async()=>{
 const env=await environment();env.BURIMUNSI_CANONICAL_SCHEDULER_ENABLED='false';let calls=0;
 const handler=createScheduledHandler(()=>env,cleanup,receipts,{processCanonical:async()=>{calls++;}});
 const response=await handler(request()),body=await response.json();assertEquals(response.status,200);
 assertEquals(calls,0);assertEquals(Object.hasOwn(body,'canonical_processing'),false);
});

fencedTest('exact receipt admission dispatches a bounded canonical cycle and redacts output',async()=>{
 const env=await environment();let calls=0;
 const handler=createScheduledHandler(()=>env,cleanup,receipts,{processCanonical:async(_env:unknown,options:any)=>{
  calls++;assertEquals(options.collectionId,'synthetic-group');assertEquals(options.owner,'synthetic-worker');
  return {status:'completed',runId:'private-run',receipts:{raw_body:'private-message'}};
 }});
 const response=await handler(request()),body=await response.json();assertEquals(response.status,200);assertEquals(calls,1);
 assertEquals(body.canonical_processing,{status:'complete'});assertEquals(JSON.stringify(body).includes('private-'),false);
 assertEquals(JSON.stringify(body).includes(env.BURIMUNSI_CANONICAL_SCHEDULER_MANAGED_ACCESS_TOKEN),false);
});

fencedTest('unapproved canonical configuration returns unconfirmed without starting a worker',async()=>{
 const env=await environment();env.BURIMUNSI_CANONICAL_SCHEDULER_APPROVAL_SHA256='c'.repeat(64);let calls=0;
 const handler=createScheduledHandler(()=>env,cleanup,receipts,{processCanonical:async()=>{calls++;}});
 const response=await handler(request()),body=await response.json();assertEquals(response.status,503);assertEquals(calls,0);
 assertEquals(body.canonical_processing,{status:'unconfirmed',code:'canonical_scheduler_unavailable'});
});
