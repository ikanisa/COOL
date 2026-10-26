import {assertEquals} from 'jsr:@std/assert@1.0.14';
import {fencedTest,syntheticFenceBackend,ownFixtureWork,SYNTHETIC_FENCE_SOURCE} from './helpers/fenced-unit.js';
import {openApplicationWork} from '../application-fence.js';
import {createHandler,createScheduledHandler} from '../serve.js';
import {ApiError} from '../domain/core.js';
import {createPlatformHealthReporter} from '../domain/observability.js';
const base=()=>({SUPABASE_URL:'https://fixture.example',COLLECT_DATABASE_URL:'postgres://fixture:synthetic@127.0.0.1:55439/collect_edge_test',SUPABASE_PUBLISHABLE_KEY:'synthetic-public',SUPABASE_SECRET_KEY:'synthetic-secret',APP_ENVIRONMENT:'test',BUILD_SOURCE_ID:SYNTHETIC_FENCE_SOURCE,COLLECT_JOB_TOKEN:'synthetic-job-token',MOMO_PROCESSING_PAUSED:'true'});
const fakeOpen=async(options:any)=>ownFixtureWork(await openApplicationWork({...options,backend:syntheticFenceBackend()}));
function capture(){let clock=0;const rows:any[]=[];const report=createPlatformHealthReporter({emit:(level:string,text:string)=>rows.push({level,...JSON.parse(text)}),clock:()=>clock});return{rows,report,nextMinute(){clock+=60000;}};}
const health=()=>new Request('https://backend.example/functions/v1/collect-api/health');

fencedTest('outer generic503 uses one response/log UUID and only the original redacted runtime diagnostic fields',async()=>{
 const {rows,report}=capture(),secret='synthetic-secret-must-not-appear';
 const handler=createHandler('collect-api',()=>({...base(),COLLECT_DATABASE_URL:'postgres://operator:'+secret+'@db.example.test/postgres?options='+secret}),{reportHealth:report});
 const response=await handler(health()),body=await response.json();assertEquals(response.status,503);
 assertEquals(Object.keys(body).sort(),['code','message','request_id']);assertEquals(body.code,'backend_unavailable');assertEquals(body.message,'The backend is unavailable.');
 assertEquals(rows.length,1);const event=rows[0];assertEquals(event.request_id,body.request_id);assertEquals(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(event.request_id),true);
 assertEquals(event.event,'runtime_unavailable');assertEquals(event.source_id,SYNTHETIC_FENCE_SOURCE);assertEquals(event.stage,'normalization');assertEquals(event.reason,'database_overrides_rejected');assertEquals(event.database_profile,{parameter_count:1,parameters:['options'],ssl_modes:[],host:'other',port:'other'});
 assertEquals(JSON.stringify({rows,body}).includes(secret),false);assertEquals(response.headers.get('Access-Control-Allow-Origin'),null);
});

fencedTest('domain-style failures and outer runtime failures consume one reporter64+1 budget; suppression is redacted and resets next minute',async()=>{
 const c=capture(),handler=createHandler('collect-api',()=>{throw Error('synthetic raw credential');},{reportHealth:c.report});
 for(let index=0;index<70;index++){
  if(index%2===0)c.report({status:500,component:'auth',requestId:crypto.randomUUID(),sourceId:SYNTHETIC_FENCE_SOURCE,elapsedMs:1});
  else assertEquals((await handler(health())).status,503);
 }
 assertEquals(c.rows.length,65);assertEquals(c.rows.filter(row=>row.event==='runtime_unavailable').length,32);assertEquals(c.rows.filter(row=>row.event==='service_degraded').length,32);
 assertEquals(c.rows[64],{level:'warn',service:'collect_platform_api',schema_version:1,event:'events_suppressed',component:'platform',status:null,request_id:null,source_id:SYNTHETIC_FENCE_SOURCE,elapsed_ms:null});
 assertEquals(JSON.stringify(c.rows).includes('synthetic raw credential'),false);c.nextMinute();const response=await handler(health()),body=await response.json();assertEquals(c.rows.length,66);assertEquals(c.rows[65].request_id,body.request_id);assertEquals(c.rows[65].event,'runtime_unavailable');
});

fencedTest('outer preflight and ordinary origin/path denials remain exact and emit no health failure',async()=>{
 const c=capture(),handler=createHandler('admin-api',()=>({ADMIN_ORIGIN:'https://admin.example'}),{reportHealth:c.report});
 const request=(origin:string,method='OPTIONS',path='/api/admin/auth/session')=>new Request('https://backend.example/functions/v1/admin-api'+path,{method,headers:{Origin:origin}});
 const okay=await handler(request('https://admin.example'));assertEquals(okay.status,204);assertEquals(okay.headers.get('Access-Control-Allow-Origin'),'https://admin.example');assertEquals(okay.headers.get('Access-Control-Allow-Credentials'),'true');
 const denied=await handler(request('https://evil.example'));assertEquals(denied.status,403);assertEquals(await denied.json(),{code:'origin_denied'});assertEquals(denied.headers.get('Access-Control-Allow-Origin'),null);
 const missing=await handler(request('https://admin.example','GET','/health'));assertEquals(missing.status,404);assertEquals(await missing.json(),{code:'not_found'});assertEquals(c.rows,[]);
});

fencedTest('custom fenced503 retains exact payload and CORS without inventing response correlation or starting work',async()=>{
 const c=capture();let admissions=0;
 const handler=createHandler('collect-api',()=>({...base(),ALLOWED_ORIGINS:'https://member.example'}),{reportHealth:c.report,openWork:async()=>{admissions++;throw new ApiError(503,'application_fenced','The service is temporarily paused. Keep the original request pending.');}});
 const response=await handler(new Request(health(),{headers:{Origin:'https://member.example'}}));
 assertEquals(response.status,503);assertEquals(await response.json(),{code:'application_fenced',message:'The service is temporarily paused. Keep the original request pending.'});assertEquals(response.headers.get('Access-Control-Allow-Origin'),'https://member.example');assertEquals(admissions,1);assertEquals(c.rows.length,1);assertEquals(c.rows[0].request_id,null);assertEquals(c.rows[0].event,'service_degraded');
});

fencedTest('scheduled503 preserves exact response with valid dispatch ID and explicit null correlation when no ID was submitted',async()=>{
 for(const dispatch of [crypto.randomUUID(),'11111111-1111-7111-8111-111111111111',null]){
  const c=capture();let cleanup=0,processing=0;
  const handler=createScheduledHandler(()=>base(),async()=>{cleanup++;throw Error('synthetic private SQL failure');},async()=>{processing++;return{processed:0,results:[],paused:true};},{openWork:fakeOpen,reportHealth:c.report});
  const request=new Request('https://backend.example/functions/v1/collect-jobs',{method:'POST',headers:{Authorization:'Bearer synthetic-job-token',...(dispatch?{'Content-Type':'application/json'}:{})},...(dispatch?{body:JSON.stringify({dispatch_id:dispatch})}:{})});
  const response=await handler(request),body=await response.json();assertEquals(response.status,503);assertEquals(body,{...(dispatch?{dispatch_id:dispatch}:{}),maintenance:{status:'unconfirmed',code:'auth_cleanup_unconfirmed'},processing:{processed:0,results:[],paused:true},realtime:{status:'disabled',scanned:0,attempted:0,failed:0,overflowed:0,delivery_confirmed:false,authoritative_polling:true}});
  assertEquals(cleanup,1);assertEquals(processing,1);assertEquals(c.rows.length,1);assertEquals(c.rows[0].component,'operations');assertEquals(c.rows[0].request_id,null);assertEquals(c.rows[0].dispatch_id,dispatch);assertEquals(c.rows[0].event,'service_degraded');assertEquals(JSON.stringify(c.rows).includes('synthetic private SQL failure'),false);
 }
});

fencedTest('scheduled authority/method/payload denials do not enter maintenance or failure budget; observer failure cannot change503',async()=>{
 const c=capture();let starts=0;
 const handler=createScheduledHandler(()=>base(),async()=>{starts++;throw Error('not admitted');},async()=>({processed:0,results:[],paused:true}),{openWork:fakeOpen,reportHealth:c.report});
 const url='https://backend.example/functions/v1/collect-jobs';
 assertEquals((await handler(new Request(url,{method:'POST'}))).status,401);
 assertEquals((await handler(new Request(url,{method:'GET',headers:{Authorization:'Bearer synthetic-job-token'}}))).status,405);
 assertEquals((await handler(new Request(url,{method:'POST',headers:{Authorization:'Bearer synthetic-job-token','Content-Type':'application/json'},body:'{"dispatch_id":"invalid"}'}))).status,400);
 assertEquals(starts,0);assertEquals(c.rows,[]);
 const unavailable=createScheduledHandler(()=>({COLLECT_JOB_TOKEN:'synthetic-job-token'}),undefined,undefined,{reportHealth:()=>{throw Error('synthetic observer failure');}});
 const response=await unavailable(new Request(url,{method:'POST',headers:{Authorization:'Bearer synthetic-job-token'}}));assertEquals(response.status,503);assertEquals(await response.json(),{code:'backend_unavailable',message:'The backend is unavailable.'});
});

fencedTest('scheduled normalization failure reports actual raw configuration presence and only closed diagnostic classes',async()=>{
 const c=capture(),secret='synthetic-secret-never-record',dispatch='11111111-1111-7111-8111-111111111111';let admissions=0;
 const input={...base(),COLLECT_DATABASE_URL:'postgres://operator:'+secret+'@db.example.test:5432/postgres?sslmode='+secret+'&'+secret+'='+secret+'&options='+secret,SUPABASE_DB_URL:'postgres://operator:'+secret+'@db.example.test/postgres',SUPABASE_PUBLISHABLE_KEYS:JSON.stringify({default:secret}),SUPABASE_SECRET_KEYS:JSON.stringify({default:secret})};
 const handler=createScheduledHandler(()=>input,undefined,undefined,{reportHealth:c.report,openWork:async()=>{admissions++;throw Error('Admission must not run after normalization failure');}});
 const response=await handler(new Request('https://backend.example/functions/v1/collect-jobs',{method:'POST',headers:{Authorization:'Bearer synthetic-job-token','Content-Type':'application/json'},body:JSON.stringify({dispatch_id:dispatch})}));
 assertEquals(response.status,503);assertEquals(await response.json(),{code:'backend_unavailable',message:'The backend is unavailable.'});assertEquals(admissions,0);assertEquals(c.rows.length,1);
 const event=c.rows[0];assertEquals(event.event,'runtime_unavailable');assertEquals(event.stage,'normalization');assertEquals(event.reason,'database_overrides_rejected');assertEquals(event.source_id,SYNTHETIC_FENCE_SOURCE);assertEquals(event.request_id,null);assertEquals(event.dispatch_id,dispatch);
 assertEquals(event.configured,{supabase_origin:true,injected_database:true,custom_database:true,publishable_dictionary:true,secret_dictionary:true});assertEquals(event.database_profile,{parameter_count:3,parameters:['options','other','sslmode'],ssl_modes:['other'],host:'other',port:'5432'});assertEquals(JSON.stringify(c.rows).includes(secret),false);
});
