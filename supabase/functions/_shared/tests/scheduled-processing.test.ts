import {assertEquals,assertThrows} from 'jsr:@std/assert@1.0.14';
import {fencedTest,SYNTHETIC_FENCE_SOURCE} from './helpers/fenced-unit.js';
import {createScheduledHandler} from './helpers/fenced-handler.js';
import {parseScheduledDispatch,scheduledProcessingResult,scheduledNotificationResult} from '../scheduled-processing.js';

const contract=()=>({contract:'collect.receipt-processing.v1',source_sha256:SYNTHETIC_FENCE_SOURCE,
 approval_sha256:'b'.repeat(64),model_id:'synthetic-reviewed-model',batch_limit:1});
const environment=()=>({SUPABASE_URL:'https://fixture.example',COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test',
 SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret',APP_ENVIRONMENT:'test',COLLECT_JOB_TOKEN:'synthetic-job-token',
 COLLECT_JOBS_MODE:'receipt_processing_v1',COLLECT_JOBS_PROCESSING_APPROVAL_SHA256:contract().approval_sha256,
 MOMO_PROCESSING_PAUSED:'false',MOMO_AI_ENABLED:'true',MOMO_AI_MODEL:contract().model_id,OPENAI_API_KEY:'synthetic-never-sent'});
const cleanup=async()=>({status:'complete',examined_limit:100,purged:0,provider_calls:0});
const request=(payload:unknown,token='synthetic-job-token')=>new Request('https://fixture.example/functions/v1/collect-jobs',{
 method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(payload)});
const dispatch=()=>({dispatch_id:crypto.randomUUID(),processing_admission:contract()});

fencedTest('admitted scheduled receipt mode binds the contract and processes exactly one queued job',async()=>{
 const input=dispatch();let calls=0;
 const handler=createScheduledHandler(environment,cleanup,async(env:Record<string,unknown>,options:unknown)=>{
  calls++;assertEquals(options,{limit:1});assertEquals(env.MOMO_PROCESSING_PAUSED,'false');
  return {processed:1,results:[{state:'completed',transaction_id:'must-not-leak',relation:'accepted',raw_body:'must-not-leak'}]};
 });
 const response=await handler(request(input)),body=await response.json();
 assertEquals(response.status,200);assertEquals(calls,1);assertEquals(body.dispatch_id,input.dispatch_id);
 assertEquals(body.processing_admission,input.processing_admission);
 assertEquals(body.processing,{status:'complete',paused:false,processed:1,results:[{state:'completed'}]});
 assertEquals(JSON.stringify(body).includes('must-not-leak'),false);
});

fencedTest('legacy empty or UUID-only jobs never admit active processing',async()=>{
 let calls=0;const handler=createScheduledHandler(environment,cleanup,async()=>{calls++;throw Error('not admitted');});
 for(const input of [{},{dispatch_id:crypto.randomUUID()}]){
  const response=await handler(request(input)),body=await response.json();
  assertEquals(response.status,503);assertEquals(body.processing.code,'processing_admission_required');
  assertEquals(Object.hasOwn(body,'processing_admission'),false);
 }
 assertEquals(calls,0);
});

fencedTest('receipt admission refuses source, approval, model and pause drift without touching the queue',async()=>{
 let calls=0;
 for(const patch of [{source_sha256:'c'.repeat(64)},{approval_sha256:'c'.repeat(64)},{model_id:'different-model'}]){
  const handler=createScheduledHandler(environment,cleanup,async()=>{calls++;throw Error('not admitted');});
  const response=await handler(request({...dispatch(),processing_admission:{...contract(),...patch}}));
  assertEquals(response.status,503);assertEquals((await response.json()).processing.code,'processing_admission_changed');
 }
 for(const patch of [{MOMO_PROCESSING_PAUSED:'true'},{MOMO_PROCESSING_PAUSED:'FALSE'},{COLLECT_JOBS_PROCESSING_APPROVAL_SHA256:''},{MOMO_AI_MODEL:''}]){
  const handler=createScheduledHandler(()=>({...environment(),...patch}),cleanup,async()=>{calls++;throw Error('not admitted');});
  const response=await handler(request(dispatch()));assertEquals(response.status,503);
  assertEquals((await response.json()).processing.code,'processing_admission_changed');
 }
 assertEquals(calls,0);
});

fencedTest('processing mode and provider availability must be explicit before provider work',async()=>{
 let calls=0;
 for(const [patch,code]of [
  [{COLLECT_JOBS_MODE:'unknown'},'job_mode_unavailable'],
  [{COLLECT_JOBS_MODE:'maintenance_only'},'maintenance_gate_changed'],
  [{MOMO_AI_ENABLED:'false'},'processing_provider_unavailable'],
  [{MOMO_AI_ENABLED:'TRUE'},'processing_provider_unavailable'],
  [{OPENAI_API_KEY:''},'processing_provider_unavailable'],
 ] as const){
  const handler=createScheduledHandler(()=>({...environment(),...patch}),cleanup,async()=>{calls++;throw Error('not admitted');});
  const response=await handler(request(dispatch()));assertEquals(response.status,503);assertEquals((await response.json()).processing.code,code);
 }
 assertEquals(calls,0);
});

fencedTest('malformed, enlarged and unauthenticated processing requests are refused before any work',async()=>{
 let cleanupCalls=0,receiptCalls=0;
 const handler=createScheduledHandler(environment,async()=>{cleanupCalls++;return cleanup();},async()=>{receiptCalls++;return {processed:0,results:[]};});
 for(const admission of [null,[],{...contract(),batch_limit:2},{...contract(),batch_limit:'1'},{...contract(),unexpected:'unreviewed'},
  {...contract(),source_sha256:'A'.repeat(64)},{...contract(),model_id:'bad\nmodel'}]){
  const response=await handler(request({...dispatch(),processing_admission:admission}));assertEquals(response.status,400);
 }
 const enlarged=await handler(request({...dispatch(),padding:'x'.repeat(2048)}));assertEquals(enlarged.status,413);
 const unauthorized=await handler(request(dispatch(),'wrong'));assertEquals(unauthorized.status,401);
 assertEquals(cleanupCalls,0);assertEquals(receiptCalls,0);
});

fencedTest('durable retry and review outcomes are acknowledgements; uncertain lease outcomes remain unconfirmed',async()=>{
 for(const state of ['retry','needs_review','not_claimed','superseded']){
  const handler=createScheduledHandler(environment,cleanup,async()=>({processed:1,results:[{state}]}));
  const response=await handler(request(dispatch()));assertEquals(response.status,200);assertEquals((await response.json()).processing.results,[{state}]);
 }
 for(const result of [{processed:1,results:[{state:'retry_on_lease_expiry'}]},{processed:2,results:[{state:'completed'},{state:'completed'}]},
  {processed:1,results:[]},{processed:0,results:[],paused:true}]){
  const handler=createScheduledHandler(environment,cleanup,async()=>result),response=await handler(request(dispatch()));
  assertEquals(response.status,503);assertEquals((await response.json()).processing.code,'receipt_processing_unconfirmed');
 }
});

fencedTest('empty admitted queue confirms its bounded run without inventing receipt progress',async()=>{
 const handler=createScheduledHandler(environment,cleanup,async()=>({processed:0,results:[]})),response=await handler(request(dispatch()));
 assertEquals(response.status,200);assertEquals((await response.json()).processing,{status:'complete',paused:false,processed:0,results:[]});
});

fencedTest('diagnostic cleanup uncertainty is reported separately from acknowledged receipt work',async()=>{
 const original=console.error,logs:unknown[][]=[];console.error=(...values:unknown[])=>{logs.push(values);};
 try{
  const handler=createScheduledHandler(environment,cleanup,async()=>({processed:1,results:[{state:'completed'}]}),{
   cleanupDiagnostics:async(_env:unknown,options:unknown)=>{assertEquals(options,{limit:1000});throw Error('sensitive-provider-detail');},
  });
  const response=await handler(request(dispatch())),body=await response.json();assertEquals(response.status,200);
  assertEquals(body.processing.status,'complete');assertEquals(body.diagnostics,{status:'unconfirmed'});
  assertEquals(logs,[[JSON.stringify({service:'collect_platform_api',event:'diagnostics_cleanup_unconfirmed'})]]);
 }finally{console.error=original;}
});

fencedTest('primary cleanup failure and receipt commit uncertainty cannot become successful dispatch acknowledgements',async()=>{
 for(const [maintenance,processing]of [
  [async()=>{throw Error('cleanup unknown');},async()=>({processed:1,results:[{state:'completed'}]})],
  [cleanup,async()=>{throw Error('receipt commit unknown');}],
 ]){
  const handler=createScheduledHandler(environment,maintenance,processing),response=await handler(request(dispatch()));assertEquals(response.status,503);
 }
});

fencedTest('processing response projection refuses unknown states and never echoes domain result payloads',()=>{
 assertEquals(scheduledProcessingResult({processed:1,results:[{state:'completed',arbitrary:'source bytes'}]}),{status:'complete',paused:false,processed:1,results:[{state:'completed'}]});
 for(const value of [null,[],{processed:0.5,results:[]},{processed:1,results:[{state:'sent'}]},{processed:0,results:[{state:'completed'}]}])assertEquals(scheduledProcessingResult(value).status,'unconfirmed');
 assertThrows(()=>parseScheduledDispatch({processing_admission:contract()}));
});

const pushContract=()=>({contract:'collect.android-push.v1',source_sha256:SYNTHETIC_FENCE_SOURCE,approval_sha256:'c'.repeat(64),
 project_id:'synthetic-collect',android_package:'app.cool.mobile',admitted_from:1793232000,batch_limit:1});
// The adapter validates these public configuration fields without importing a
// key or doing HTTP. The injected bounded worker never invokes this dummy key.
const pushEnvironment=()=>({...environment(),COLLECT_JOBS_MODE:'notification_delivery_v1',MOMO_PROCESSING_PAUSED:'true',
 COLLECT_PUSH_ENABLED:'true',COLLECT_JOBS_PUSH_APPROVAL_SHA256:pushContract().approval_sha256,COLLECT_PUSH_ADMITTED_FROM:String(pushContract().admitted_from),
 FCM_PROJECT_ID:pushContract().project_id,FCM_ANDROID_PACKAGE:pushContract().android_package,
 FCM_SERVICE_ACCOUNT_JSON:JSON.stringify({type:'service_account',project_id:pushContract().project_id,private_key_id:'synthetic-key',
  client_email:'synthetic@synthetic-collect.iam.gserviceaccount.com',private_key:'-----BEGIN PRIVATE KEY-----\nAA==\n-----END PRIVATE KEY-----\n',token_uri:'https://oauth2.googleapis.com/token'})});
const pushDispatch=()=>({dispatch_id:crypto.randomUUID(),notification_admission:pushContract()});
const pushResult=(state='accepted')=>({status:'complete',paused:false,processed:1,results:[{state}],recovered_unknown:0});
const pausedReceipts=async()=>({processed:0,results:[],paused:true});

fencedTest('explicit push-only mode leaves receipt processing paused and admits one bound notification attempt',async()=>{
 const input=pushDispatch();let sends=0;
 const handler=createScheduledHandler(pushEnvironment,cleanup,pausedReceipts,{processNotifications:async(_env:unknown,options:unknown)=>{
  sends++;assertEquals(options,{limit:1,admission:pushContract()});return {...pushResult(),results:[{state:'accepted',message:'must-not-leak'}]};
 }});
 const response=await handler(request(input)),body=await response.json();assertEquals(response.status,200);assertEquals(sends,1);
 assertEquals(body.notification_admission,pushContract());assertEquals(body.notifications,pushResult());assertEquals(body.processing.paused,true);
 assertEquals(Object.hasOwn(body,'processing_admission'),false);assertEquals(JSON.stringify(body).includes('must-not-leak'),false);
});

fencedTest('combined mode requires both independent exact admissions before receipt or push work',async()=>{
 let receipts=0,push=0;
 const combined=()=>({...pushEnvironment(),COLLECT_JOBS_MODE:'receipt_and_push_v1',MOMO_PROCESSING_PAUSED:'false'});
 const handler=createScheduledHandler(combined,cleanup,async()=>{receipts++;return {processed:1,results:[{state:'completed'}]};},{processNotifications:async()=>{push++;return pushResult();}});
 for(const input of [dispatch(),pushDispatch()])assertEquals((await handler(request(input))).status,503);
 assertEquals(receipts,0);assertEquals(push,0);
 const response=await handler(request({...dispatch(),notification_admission:pushContract()})),body=await response.json();
 assertEquals(response.status,200);assertEquals(receipts,1);assertEquals(push,1);assertEquals(body.processing.processed,1);assertEquals(body.notifications.processed,1);
});

fencedTest('push approval, source, package, project, lower-bound or enablement drift cannot touch the queue',async()=>{
 let sends=0;
 for(const patch of [{source_sha256:'d'.repeat(64)},{approval_sha256:'d'.repeat(64)},{project_id:'another-project'},
  {android_package:'app.cool.mobile.dev'},{admitted_from:pushContract().admitted_from-1}]){
  const handler=createScheduledHandler(pushEnvironment,cleanup,pausedReceipts,{processNotifications:async()=>{sends++;return pushResult();}});
  const response=await handler(request({...pushDispatch(),notification_admission:{...pushContract(),...patch}}));
  assertEquals(response.status,503);assertEquals((await response.json()).processing.code,'notification_admission_changed');
 }
 for(const patch of [{COLLECT_PUSH_ENABLED:'false'},{COLLECT_PUSH_ENABLED:'TRUE'},{FCM_SERVICE_ACCOUNT_JSON:''},{FCM_SERVICE_ACCOUNT_JSON:'{}'},
  {COLLECT_JOBS_MODE:'maintenance_only'},{MOMO_PROCESSING_PAUSED:'false'}]){
  const handler=createScheduledHandler(()=>({...pushEnvironment(),...patch}),cleanup,pausedReceipts,{processNotifications:async()=>{sends++;return pushResult();}});
  assertEquals((await handler(request(pushDispatch()))).status,503);
 }
 assertEquals(sends,0);
});

fencedTest('malformed notification admission is refused before cleanup and dispatch',async()=>{
 let work=0;const handler=createScheduledHandler(pushEnvironment,async()=>{work++;return cleanup();},pausedReceipts,{processNotifications:async()=>{work++;return pushResult();}});
 for(const admission of [null,[],{...pushContract(),batch_limit:2},{...pushContract(),admitted_from:'1793232000'},
  {...pushContract(),credential:'not allowed'},{...pushContract(),android_package:'app.cool.mobile.gateway'}]){
  assertEquals((await handler(request({...pushDispatch(),notification_admission:admission}))).status,400);
 }
 assertEquals(work,0);
});

fencedTest('recorded terminal notification uncertainty is acknowledged without authorizing any resend',async()=>{
 for(const state of ['accepted','retry','rejected','suppressed','unknown']){
  const handler=createScheduledHandler(pushEnvironment,cleanup,pausedReceipts,{processNotifications:async()=>pushResult(state)});
  const response=await handler(request(pushDispatch()));assertEquals(response.status,200);assertEquals((await response.json()).notifications.results,[{state}]);
 }
 for(const result of [{...pushResult(),status:'unconfirmed'},{...pushResult(),processed:2},{...pushResult(),results:[{state:'sending'}]},
  {...pushResult(),recovered_unknown:101},{...pushResult(),paused:true}]){
  const handler=createScheduledHandler(pushEnvironment,cleanup,pausedReceipts,{processNotifications:async()=>result});
  const response=await handler(request(pushDispatch()));assertEquals(response.status,503);assertEquals((await response.json()).notifications.status,'unconfirmed');
 }
 const failing=createScheduledHandler(pushEnvironment,cleanup,pausedReceipts,{processNotifications:async()=>{throw Error('commit response lost');}});
 assertEquals((await failing(request(pushDispatch()))).status,503);
});

fencedTest('notification response projects state only and bounds stale-send recovery independently',()=>{
 assertEquals(scheduledNotificationResult({...pushResult('unknown'),recovered_unknown:100,results:[{state:'unknown',token:'must-not-leak'}]}),{...pushResult('unknown'),recovered_unknown:100});
 for(const value of [null,{},[],{...pushResult(),processed:0},{...pushResult(),recovered_unknown:-1},{...pushResult(),recovered_unknown:'1'}])assertEquals(scheduledNotificationResult(value).status,'unconfirmed');
});
