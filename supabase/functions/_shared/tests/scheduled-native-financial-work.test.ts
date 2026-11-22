import {assertEquals} from 'jsr:@std/assert@1.0.14';
import {fencedTest,SYNTHETIC_FENCE_SOURCE} from './helpers/fenced-unit.js';
import {createScheduledHandler} from './helpers/fenced-handler.js';

const approval={contract:'collect.receipt-processing.v1',source_sha256:SYNTHETIC_FENCE_SOURCE,
 approval_sha256:'b'.repeat(64),model_id:'synthetic-model',batch_limit:1};
const cleanup=async()=>({status:'complete',examined_limit:100,purged:0,provider_calls:0});
const receipts=async()=>({processed:0,results:[],paused:false});
const environment=()=>({SUPABASE_URL:'https://rrlduytparvsjfmegalh.supabase.co',
 COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test',
 SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret',APP_ENVIRONMENT:'test',
 FIXTURE_JOB_TOKEN:'synthetic-job-token',COLLECT_JOBS_MODE:'receipt_processing_v1',
 COLLECT_JOBS_PROCESSING_APPROVAL_SHA256:approval.approval_sha256,MOMO_PROCESSING_PAUSED:'false',
 MOMO_AI_ENABLED:'true',MOMO_AI_MODEL:approval.model_id,OPENAI_API_KEY:'synthetic-never-sent'});
const request=(token='synthetic-job-token')=>new Request('https://fixture.example/functions/v1/collect-jobs',{
 method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},
 body:JSON.stringify({dispatch_id:crypto.randomUUID(),processing_admission:approval})});

fencedTest('native financial queue is absent by default from the scheduled response',async()=>{
 const response=await createScheduledHandler(environment,cleanup,receipts)(request());
 const body=await response.json();assertEquals(response.status,200);
 assertEquals(Object.hasOwn(body,'native_financial_work'),false);
});
fencedTest('an enabled switch remains held when shared retention mapping is unreviewed',async()=>{
 const handler=createScheduledHandler(()=>({...environment(),BURIMUNSI_NATIVE_FINANCIAL_QUEUE_ENABLED:'true'}),cleanup,receipts);
 const response=await handler(request()),body=await response.json();assertEquals(response.status,200);
 assertEquals(body.native_financial_work,{status:'held',code:'retention_scope_unapproved'});
});
fencedTest('scheduled native work receives the admitted dispatch and exposes only its outcome',async()=>{
 let calls=0;
 const handler=createScheduledHandler(environment,cleanup,receipts,{processNativeFinancialWork:async(_env:unknown,admission:any)=>{
  calls++;assertEquals(admission.allowed,true);assertEquals(admission.processing.source_sha256,SYNTHETIC_FENCE_SOURCE);
  return {status:'held',code:'independent_evidence_unavailable'};
 }});
 const response=await handler(request()),body=await response.json();assertEquals(response.status,200);assertEquals(calls,1);
 assertEquals(body.native_financial_work,{status:'held',code:'independent_evidence_unavailable'});
});
fencedTest('unconfirmed native work makes the scheduled result unconfirmed',async()=>{
 const handler=createScheduledHandler(environment,cleanup,receipts,{processNativeFinancialWork:async()=>({status:'unconfirmed',code:'native_financial_work_unavailable'})});
 const response=await handler(request()),body=await response.json();assertEquals(response.status,503);
 assertEquals(body.native_financial_work.code,'native_financial_work_unavailable');
});
fencedTest('untrusted job token cannot invoke the native queue',async()=>{
 let calls=0;const handler=createScheduledHandler(environment,cleanup,receipts,{processNativeFinancialWork:async()=>{calls++;}});
 const response=await handler(request('wrong-token'));assertEquals(response.status,401);assertEquals(calls,0);
});
