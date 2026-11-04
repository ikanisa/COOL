// Handler integration boundaries are explicit doubles; no DB/provider request.
// Native row claiming, concurrency and replay are qualified separately.
import assert from 'node:assert/strict';
import {createContributionEmailJobsHandler} from '../email-jobs.js';
import {canonicalProfile} from '../deployment-profile.js';
import {parseEmailJobDispatch,emailJobResult} from '../email-job-contract.js';
const profile={format:'collect.deployment.v1',id:'email-handler',mode:'self_hosted',environment:'qualification',supabase_origin:'https://db.example.invalid',member_api_origin:'https://api.example.invalid',admin_origin:'https://admin.example.invalid',public_origin:'https://www.example.invalid',google_callback_origin:'https://admin.example.invalid'};
const raw=canonicalProfile(profile);
const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(raw))),b=>b.toString(16).padStart(2,'0')).join('');
const admission={contract:'collect.contribution-email.v1',source_sha256:'a'.repeat(64),approval_sha256:'b'.repeat(64),admitted_from:1793480000,batch_limit:1};
const settings={COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:hash,APP_ENVIRONMENT:'test',SUPABASE_URL:profile.supabase_origin,COLLECT_DATABASE_URL:'postgres://collect_runtime:synthetic@127.0.0.1:1/collect_email_handler_test',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic',SUPABASE_SECRET_KEY:'sb_secret_synthetic',COLLECT_EMAIL_JOB_TOKEN:'t'.repeat(48),COLLECT_CONTRIBUTION_EMAIL_ENABLED:'true',BUILD_SOURCE_ID:admission.source_sha256,COLLECT_JOBS_EMAIL_APPROVAL_SHA256:admission.approval_sha256,COLLECT_EMAIL_ADMITTED_FROM:String(admission.admitted_from)};
const envelope=()=>({dispatch_id:crypto.randomUUID(),email_admission:{...admission}});
function fixture({changes={},verified=true,result={status:'complete',processed:0,results:[]},throws=false}:any={}){
 const calls:any[]=[];let finished=0,opened=0;
 const sql={begin:async(fn:any)=>fn(async(parts:any,...values:any[])=>{
  const text=parts.join('?');calls.push({text,values});return text.includes('collect_assert_deployment')?[{allowed:verified}]:[];
 })};
 const handler=createContributionEmailJobsHandler(()=>({...settings,...changes}),{
  databaseFactory:()=>({sql,setApplicationWork:()=>{}}),
  openWork:async()=>{opened++;return {finish:async()=>{finished++;}};},
  processEmails:async(_env:any,input:any)=>{calls.push({input});if(throws)throw Error('synthetic private provider detail');return result;},
 }as any);
 const request=(body:any=envelope(),options:any={})=>new Request(settings.SUPABASE_URL+(options.path??'/functions/v1/collect-email-jobs'),{method:options.method??'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+(options.token??settings.COLLECT_EMAIL_JOB_TOKEN)},body:(options.method??'POST')==='POST'?JSON.stringify(body):undefined});
 return {handler,request,calls,get opened(){return opened;},get finished(){return finished;}};
}
Deno.test('email job parser requires the exact bounded envelope and strips delivery claims',()=>{
 const body=envelope();assert.equal(parseEmailJobDispatch(body).dispatchId,body.dispatch_id);
 for(const bad of [{...body,token:'forbidden'},{...body,email_admission:{...admission,batch_limit:2}},{...body,email_admission:{...admission,recipient:'forbidden'}}])assert.throws(()=>parseEmailJobDispatch(bad));
 assert.deepEqual(emailJobResult({status:'complete',processed:1,results:[{state:'accepted',delivery_confirmed:true}]}),{status:'complete',processed:1,results:[{state:'accepted',delivery_confirmed:false}]});
 assert.equal(emailJobResult({status:'complete',processed:2,results:[]}).status,'unconfirmed');
});
Deno.test('email handler refuses tokens, methods, paths and admission drift before database work',async()=>{
 for(const options of [{token:'wrong'},{method:'GET'},{path:'/functions/v1/collect-jobs'}]){
  const f=fixture();assert.notEqual((await f.handler(f.request(envelope(),options))).status,200);assert.equal(f.calls.length,0);assert.equal(f.opened,0);
 }
 for(const changes of [{COLLECT_CONTRIBUTION_EMAIL_ENABLED:'false'},{COLLECT_JOBS_EMAIL_APPROVAL_SHA256:'c'.repeat(64)},{COLLECT_DEPLOYMENT_PROFILE_SHA256:'0'.repeat(64)}]){
  const f=fixture({changes});assert.equal((await f.handler(f.request())).status,503);assert.equal(f.calls.length,0);assert.equal(f.opened,0);
 }
});
Deno.test('email handler binds the actual database before work and passes the original dispatch ID',async()=>{
 const refused=fixture({verified:false});assert.equal((await refused.handler(refused.request())).status,503);assert.equal(refused.opened,0);
 for(const path of ['/functions/v1/collect-email-jobs','/collect-email-jobs']){
  const f=fixture(),body=envelope(),response=await f.handler(f.request(body,{path}));assert.equal(response.status,200);
  assert.deepEqual(f.calls.at(-1).input,{dispatchId:body.dispatch_id,admission:body.email_admission});
  assert.deepEqual(await response.json(),{...body,emails:{status:'complete',processed:0,results:[]}});
  assert.equal(f.opened,1);assert.equal(f.finished,1);
 }
});
Deno.test('email handler retains explicit unknown results and never exposes provider exception text',async()=>{
 const f=fixture({result:{status:'complete',processed:1,results:[{state:'unknown',delivery_confirmed:false}]}}),body=envelope();
 const response=await f.handler(f.request(body));assert.equal(response.status,200);assert.equal((await response.json()).emails.results[0].state,'unknown');assert.equal(f.finished,1);
 const failed=fixture({throws:true}),rejected=await failed.handler(failed.request());assert.equal(rejected.status,503);assert.deepEqual(await rejected.json(),{code:'email_jobs_unconfirmed'});assert.equal(failed.finished,1);
});
