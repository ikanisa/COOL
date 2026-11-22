/** Closed runtime assembly tests. Genuine application-work JS branding over an
 * explicitly synthetic lease backend; DB/storage/provider methods throw if
 * called. No DB, provider, credentials, scheduler or deployment is activated. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createCollectNativeRuntime,createCollectNativeWorkerRuntime,runCollectNativeScheduledCycle} from '../../domain/burimunsi/collect-runtime.js';
import {collectNativeRoute} from '../../domain/burimunsi/collect-route.js';
import {openApplicationWork} from '../../application-fence.js';
import {canonicalProfile} from '../../deployment-profile.js';
import {sha256} from '../../domain/burimunsi/values.js';
const SOURCE='a'.repeat(64);
const PROFILE={format:'collect.deployment.v1',id:'buri-runtime-fixture',mode:'managed',environment:'qualification',
 supabase_origin:'https://rrlduytparvsjfmegalh.supabase.co',member_api_origin:'https://member.example.test',
 admin_origin:'https://admin.example.test',public_origin:'https://public.example.test',google_callback_origin:'https://admin.example.test'};
const b64=byte=>Buffer.alloc(32,byte).toString('base64');
const serverNetwork=()=>{throw Error('This construction test must not resolve a network identity');};
async function fixture(kind='http_collect'){
 const state={calls:0,asserts:0};
 const forbidden=()=>{state.calls++;throw Error('Runtime construction performed operational I/O');};
 const row={contractVersion:1,admissionId:'11111111-1111-4111-8111-111111111111',sourceSha256:SOURCE,epoch:1,kind,state:'active',mode:'open'};
 const work=await openApplicationWork({sourceSha256:SOURCE,kind,id:row.admissionId,backend:{register:async()=>row,
  lease:async()=>({row,assert:async()=>{state.asserts++;return row;},release:async()=>{}}),
  close:async(_id,_epoch,_source,outcome,reason,externalDispatches,uncertainDispatches)=>
   ({...row,state:outcome,reason,externalDispatches,uncertainDispatches}),status:forbidden}});
 const env={BURIMUNSI_NATIVE_ENABLED:'true',BURIMUNSI_COLLECTION_ID:'buri-runtime-fixture',BUILD_SOURCE_ID:SOURCE,
  APP_ENVIRONMENT:'qualification',SUPABASE_URL:PROFILE.supabase_origin,
  COLLECT_DEPLOYMENT_PROFILE:canonicalProfile(PROFILE),COLLECT_DEPLOYMENT_PROFILE_SHA256:await sha256(canonicalProfile(PROFILE)),
  COLLECT_FENCE_WORK:work,DB:{applicationWork:work,transaction:forbidden,context:forbidden,readContext:forbidden,prepare:forbidden,statement:forbidden,setClaims:forbidden},
  PRIVATE_MEDIA:{namespace:{origin:PROFILE.supabase_origin,bucket:'collect-evidence'},get:forbidden,put:forbidden},
  DATA_KEY_ID:'data-fixture',DATA_ENCRYPTION_KEY:b64(1),SESSION_KEY_ID:'bff-fixture',SESSION_ENCRYPTION_KEY:b64(2),
  BURIMUNSI_PIN_PEPPER_BASE64:b64(3),BURIMUNSI_PIN_PEPPER_ID:'native-fixture',BURIMUNSI_CURSOR_KEY_BASE64:b64(4),
  MOMO_PROCESSING_PAUSED:'true'};
 return {env,work,state,close:()=>work.finish()};
}
for(const value of [undefined,'false','TRUE',true,1])test('HTTP factory is inert unless exact enabled string: '+String(value),async()=>{
 const env=new Proxy({BURIMUNSI_NATIVE_ENABLED:value},{get(target,key){if(key==='BURIMUNSI_NATIVE_ENABLED')return target[key];throw Error('Disabled runtime inspected '+String(key));}});
 assert.equal(await createCollectNativeRuntime(env),null);
});
test('closed HTTP factory creates a branded route with no DB/provider/work-assert side effects',async()=>{
 const f=await fixture();try{
  const before={...f.env};const route=await createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork});
  assert.equal(typeof route,'function');assert.deepEqual(f.env,before);assert.equal(f.state.calls,0);assert.equal(f.state.asserts,0);
  // The real dispatcher recognizes its brand; missing managed auth fails before
  // any native/PIN or provider operation, rather than accepting an env function.
  const response=await collectNativeRoute(new Request(PROFILE.supabase_origin+'/v1/burimunsi/session'),{...f.env,BURIMUNSI_NATIVE_ROUTE:route});
  assert.equal(response.status,401);assert.equal(f.state.calls,0);
 }finally{await f.close();}
});
test('retired Staff passcode configuration cannot disable sign-in or worker startup',async()=>{
 const f=await fixture(),jobs=await fixture('jobs');try{
  f.env.BURIMUNSI_DEFAULT_STAFF_PIN='retired';
  jobs.env.BURIMUNSI_DEFAULT_STAFF_PIN='retired';
  jobs.env.BURIMUNSI_NATIVE_WORKERS_ENABLED='true';
  assert.equal(typeof await createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork}),'function');
  assert.equal(typeof (await createCollectNativeWorkerRuntime(jobs.env)).processReceipts,'function');
  assert.equal(f.state.calls,0);assert.equal(jobs.state.calls,0);
 }finally{await Promise.all([f.close(),jobs.close()]);}
});
test('scheduled cycle rejects an invalid managed credential before any worker or SQL action',async()=>{
 const f=await fixture('jobs');try{
  f.env.BURIMUNSI_NATIVE_WORKERS_ENABLED='true';
  await assert.rejects(runCollectNativeScheduledCycle(f.env,{collectionId:'buri-runtime-fixture',owner:'worker-1',
   managedAccessToken:'not-a-managed-session'}),e=>e.code==='managed_session_required');
  assert.equal(f.state.calls,0);
 }finally{await f.close();}
});
for(const group of [undefined,''])test('HTTP construction has no required business group: '+String(group),async()=>{
 const f=await fixture();try{f.env.BURIMUNSI_COLLECTION_ID=group;
  assert.equal(typeof await createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork}),'function');
  assert.equal(f.state.calls,0);assert.equal(f.state.asserts,0);
 }finally{await f.close();}
});
test('dynamic worker facade selects only explicit trusted server groups and creates no schedule',async()=>{
 const f=await fixture('jobs');try{f.env.BURIMUNSI_NATIVE_WORKERS_ENABLED='true';delete f.env.BURIMUNSI_COLLECTION_ID;
  const facade=await createCollectNativeWorkerRuntime(f.env);assert.deepEqual(Object.keys(facade),['forCollection']);
  const a=await facade.forCollection('first-approved-group'),b=await facade.forCollection('second-approved-group');
  assert.equal(typeof a.processReceipts,'function');assert.equal(typeof b.processReceipts,'function');assert.notEqual(a,b);
  await assert.rejects(facade.forCollection('../foreign'));assert.equal(f.state.calls,0);assert.equal(f.state.asserts,0);
 }finally{await f.close();}
});

test('advanced onboarding flag alone performs no provider or database work at runtime construction',async()=>{
 const f=await fixture();try{f.env.BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED='true';
  assert.equal(typeof await createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork}),'function');
  assert.equal(f.state.calls,0);assert.equal(f.state.asserts,0);
 }finally{await f.close();}
});
