import {assertEquals} from 'jsr:@std/assert@1.0.14';
import {fencedTest,SYNTHETIC_FENCE_SOURCE} from './helpers/fenced-unit.js';
import {createScheduledHandler} from './helpers/fenced-handler.js';

const approval={contract:'collect.receipt-processing.v1',source_sha256:SYNTHETIC_FENCE_SOURCE,
 approval_sha256:'b'.repeat(64),model_id:'synthetic-model',batch_limit:1};
const environment=()=>({SUPABASE_URL:'https://fixture.example',
 COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test',
 SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret',APP_ENVIRONMENT:'test',
 COLLECT_JOB_TOKEN:'synthetic-job-token',COLLECT_JOBS_MODE:'receipt_processing_v1',
 COLLECT_JOBS_PROCESSING_APPROVAL_SHA256:approval.approval_sha256,MOMO_PROCESSING_PAUSED:'false',
 MOMO_AI_ENABLED:'true',MOMO_AI_MODEL:approval.model_id,OPENAI_API_KEY:'synthetic-never-sent',
 BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true'});
const cleanup=async()=>({status:'complete',purged:0});
const receipts=async()=>({processed:0,results:[],paused:false});
const auto=async()=>({status:'complete',processed:0,results:[]});
const request=(token='synthetic-job-token',contract=approval)=>new Request('https://fixture.example/functions/v1/collect-jobs',{
 method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},
 body:JSON.stringify({dispatch_id:crypto.randomUUID(),processing_admission:contract})});

fencedTest('native auto cycle invokes the existing ledger under the admitted jobs work and redacts output',async()=>{
 let calls=0;
 const handler=createScheduledHandler(environment,cleanup,receipts,{processNativeAuto:auto,
  processNativeSmsLedger:async(env:any,options:any)=>{
   calls++;assertEquals(env.DB.applicationWork.kind,'jobs');assertEquals(options,{limit:1});
   return {status:'complete',processed:1,results:[{state:'unmatched',rawBody:'private-source',memberId:'private-member'}]};
  }});
 const response=await handler(request()),body=await response.json();
 assertEquals(response.status,200);assertEquals(calls,1);
 assertEquals(body.native_sms_ledger,{status:'complete',processed:1,results:[{state:'unmatched'}]});
 assertEquals(JSON.stringify(body).includes('private-'),false);
});
fencedTest('unknown native ledger outcomes make the tick unconfirmed',async()=>{
 const handler=createScheduledHandler(environment,cleanup,receipts,{processNativeAuto:auto,
  processNativeSmsLedger:async()=>{throw Error('private SQL failure');}});
 const response=await handler(request()),body=await response.json();
 assertEquals(response.status,503);assertEquals(body.native_sms_ledger,{status:'unconfirmed',code:'native_sms_ledger_unconfirmed'});
 assertEquals(JSON.stringify(body).includes('private SQL'),false);
});
fencedTest('unapproved receipt dispatch cannot start the native ledger',async()=>{
 let calls=0;
 const handler=createScheduledHandler(environment,cleanup,receipts,{processNativeAuto:auto,
  processNativeSmsLedger:async()=>{calls++;return {status:'complete',processed:0,results:[]};}});
 const response=await handler(request('synthetic-job-token',{...approval,source_sha256:'c'.repeat(64)}));
 assertEquals(response.status,503);assertEquals(calls,0);
});
fencedTest('unauthenticated jobs cannot invoke the native ledger',async()=>{
 let calls=0;
 const handler=createScheduledHandler(environment,cleanup,receipts,{processNativeAuto:auto,
  processNativeSmsLedger:async()=>{calls++;}});
 assertEquals((await handler(request('wrong-token'))).status,401);assertEquals(calls,0);
});
fencedTest('disabled native SMS processing leaves the ledger untouched',async()=>{
 let calls=0;
 const handler=createScheduledHandler(()=>({...environment(),BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'false'}),cleanup,receipts,
  {processNativeSmsLedger:async()=>{calls++;}});
 const response=await handler(request()),body=await response.json();assertEquals(response.status,200);
 assertEquals(calls,0);assertEquals(Object.hasOwn(body,'native_sms_ledger'),false);
});
