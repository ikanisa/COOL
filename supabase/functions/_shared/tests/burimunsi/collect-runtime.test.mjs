/** Closed runtime assembly tests. Genuine application-work JS branding over an
 * explicitly synthetic lease backend; DB/storage/provider methods throw if
 * called. No DB, provider, credentials, scheduler or deployment is activated. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createCollectNativeRuntime,createCollectNativeWorkerRuntime,runCollectNativeScheduledCycle,heldRecoveryScope} from '../../domain/burimunsi/collect-runtime.js';
import {collectNativeRoute} from '../../domain/burimunsi/collect-route.js';
import {openApplicationWork} from '../../application-fence.js';
import {canonicalProfile} from '../../deployment-profile.js';
import {sha256} from '../../domain/burimunsi/values.js';
const SOURCE='a'.repeat(64);

test('held recovery requires a matching source and exactly one explicit collection',()=>{
 const base={BUILD_SOURCE_ID:SOURCE,BURIMUNSI_SMS_OBSERVATIONS_ENABLED:'true'};
 assert.equal(heldRecoveryScope(base),null);
 assert.equal(heldRecoveryScope({...base,BURIMUNSI_HELD_RECOVERY_SOURCE_SHA256:'',BURIMUNSI_HELD_RECOVERY_COLLECTION_ID:''}),null);
 const enabled={...base,BURIMUNSI_HELD_RECOVERY_SOURCE_SHA256:SOURCE,BURIMUNSI_HELD_RECOVERY_COLLECTION_ID:'group-1'};
 assert.deepEqual(heldRecoveryScope(enabled),{sourceSha256:SOURCE,groupId:'group-1'});
 for(const invalid of [
  {...enabled,BURIMUNSI_HELD_RECOVERY_SOURCE_SHA256:undefined},
  {...enabled,BURIMUNSI_HELD_RECOVERY_COLLECTION_ID:undefined},
  {...enabled,BURIMUNSI_HELD_RECOVERY_SOURCE_SHA256:'b'.repeat(64)},
  {...enabled,BUILD_SOURCE_ID:'b'.repeat(64)},
  {...enabled,BURIMUNSI_HELD_RECOVERY_COLLECTION_ID:'group/other'},
  {...enabled,BURIMUNSI_SMS_OBSERVATIONS_ENABLED:'false'},
 ])assert.throws(()=>heldRecoveryScope(invalid),e=>e.code==='held_recovery_configuration_invalid');
});
const PROFILE={format:'collect.deployment.v1',id:'buri-runtime-fixture',mode:'self_hosted',environment:'qualification',
 supabase_origin:'https://supabase.example.test',member_api_origin:'https://member.example.test',
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
test('staff default is accepted only as four digits and remains server-side',async()=>{
 const f=await fixture();try{
  f.env.BURIMUNSI_DEFAULT_STAFF_PIN='1357';
  assert.equal(typeof await createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork}),'function');
  assert.equal(f.state.calls,0);
  f.env.BURIMUNSI_DEFAULT_STAFF_PIN='bad';
  await assert.rejects(createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork}),e=>e.code==='authentication_unconfigured');
  assert.equal(f.state.calls,0);
 }finally{await f.close();}
});
test('enabled factory refuses raw-header/env-string/default network substitutes',async()=>{
 const f=await fixture();try{
  f.env.BURIMUNSI_NATIVE_NETWORK_BUCKET='f'.repeat(64);f.env.trustedNetworkBucket=serverNetwork;
  for(const options of [undefined,{trustedNetworkBucket:'CF-Connecting-IP'},{trustedNetworkBucket:[]},{trustedNetworkBucket:{verified:true}}])
   await assert.rejects(createCollectNativeRuntime(f.env,options),e=>e.code==='trusted_network_resolver_required');
  assert.equal(f.state.calls,0);assert.equal(f.state.asserts,0);
 }finally{await f.close();}
});
test('explicit test environment is confined to the existing qualification profile rule',async()=>{
 const f=await fixture();try{f.env.APP_ENVIRONMENT='test';assert.equal(typeof await createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork}),'function');assert.equal(f.state.calls,0);}finally{await f.close();}
});
for(const [name,change]of [
 ['missing profile',e=>delete e.COLLECT_DEPLOYMENT_PROFILE],
 ['profile hash',e=>e.COLLECT_DEPLOYMENT_PROFILE_SHA256='b'.repeat(64)],
 ['different Supabase',e=>e.SUPABASE_URL='https://foreign.example.test'],
 ['different environment',e=>e.APP_ENVIRONMENT='production'],
 ['path collection',e=>e.BURIMUNSI_COLLECTION_ID='../foreign'],
 ['invalid staff phone preservation flag',e=>e.BURIMUNSI_STAFF_PIN_PHONE_PRESERVATION_ENABLED='yes'],
 ['invalid advanced smart onboarding flag',e=>e.BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED='yes'],
 ['unbranded work',e=>e.COLLECT_FENCE_WORK={assert:async()=>{}}],
 ['source replacement',e=>e.BUILD_SOURCE_ID='b'.repeat(64)],
 ['different DB admission',e=>e.DB.applicationWork={assert:async()=>{}}],
 ['storage namespace',e=>e.PRIVATE_MEDIA.namespace.origin='https://foreign.example.test'],
 ['storage bucket',e=>e.COLLECT_PRIVATE_BUCKET='foreign'],
 ['storage env string',e=>e.PRIVATE_MEDIA='injected'],
 ['missing data key ID',e=>delete e.DATA_KEY_ID],
])test('closed assembly refuses '+name,async()=>{
 const f=await fixture();try{change(f.env);await assert.rejects(createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork}));assert.equal(f.state.calls,0);}finally{await f.close();}
});
for(const [name,change]of [
 ['missing native pepper',e=>delete e.BURIMUNSI_PIN_PEPPER_BASE64],
 ['missing native pepper ID',e=>delete e.BURIMUNSI_PIN_PEPPER_ID],
 ['missing cursor',e=>delete e.BURIMUNSI_CURSOR_KEY_BASE64],
 ['malformed cursor',e=>e.BURIMUNSI_CURSOR_KEY_BASE64='not base64'],
 ['short cursor',e=>e.BURIMUNSI_CURSOR_KEY_BASE64=Buffer.alloc(31,4).toString('base64')],
 ['noncanonical cursor',e=>e.BURIMUNSI_CURSOR_KEY_BASE64=e.BURIMUNSI_CURSOR_KEY_BASE64.replace(/=$/,'')],
 ['same pepper and cursor',e=>e.BURIMUNSI_CURSOR_KEY_BASE64=e.BURIMUNSI_PIN_PEPPER_BASE64],
 ['pepper reused from DATA',e=>e.BURIMUNSI_PIN_PEPPER_BASE64=e.DATA_ENCRYPTION_KEY],
 ['pepper reused from BFF',e=>e.BURIMUNSI_PIN_PEPPER_BASE64=e.SESSION_ENCRYPTION_KEY],
 ['cursor reused from DATA',e=>e.BURIMUNSI_CURSOR_KEY_BASE64=e.DATA_ENCRYPTION_KEY],
 ['cursor reused from BFF',e=>e.BURIMUNSI_CURSOR_KEY_BASE64=e.SESSION_ENCRYPTION_KEY],
 ['DATA reused as BFF',e=>e.SESSION_ENCRYPTION_KEY=e.DATA_ENCRYPTION_KEY],
 ['prior DATA reused as BFF',e=>e.DATA_DECRYPTION_KEYS_JSON=JSON.stringify({prior:e.SESSION_ENCRYPTION_KEY})],
 ['cursor reused from prior DATA key',e=>e.DATA_DECRYPTION_KEYS_JSON=JSON.stringify({prior:e.BURIMUNSI_CURSOR_KEY_BASE64})],
 ['pepper reused from prior BFF key',e=>e.SESSION_DECRYPTION_KEYS_JSON=JSON.stringify({prior:e.BURIMUNSI_PIN_PEPPER_BASE64})],
 ['malformed old keyring',e=>e.DATA_DECRYPTION_KEYS_JSON='[]'],
 ['duplicate old key IDs',e=>e.DATA_DECRYPTION_KEYS_JSON='{"prior":"'+b64(5)+'","prior":"'+b64(6)+'"}'],
])test('independent protected secret boundary refuses '+name,async()=>{
 const f=await fixture();try{change(f.env);await assert.rejects(createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork}),e=>e.status===503);
  assert.equal(f.state.calls,0);assert.equal(f.state.asserts,0);
 }finally{await f.close();}
});
test('caller bridge maps and env route functions do not enter closed composition',async()=>{
 const f=await fixture();try{
  f.env.BURIMUNSI_NATIVE_ROUTE='client env string';
  const options={trustedNetworkBucket:serverNetwork,get bridgeFactory(){throw Error('Caller bridge was consulted');},get sourceReader(){throw Error('Caller reader was consulted');}};
  assert.equal(typeof await createCollectNativeRuntime(f.env,options),'function');assert.equal(f.state.calls,0);
 }finally{await f.close();}
});
test('empty optional prior keyrings match the existing encryption configuration',async()=>{
 const f=await fixture();try{f.env.DATA_DECRYPTION_KEYS_JSON='';f.env.SESSION_DECRYPTION_KEYS_JSON='';
  assert.equal(typeof await createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork}),'function');assert.equal(f.state.calls,0);
 }finally{await f.close();}
});
test('retained DATA and session key rings initialize the native runtime after a cloud migration',async()=>{
 const f=await fixture();try{
  f.env.DATA_DECRYPTION_KEYS_JSON=JSON.stringify({retainedData:b64(5)});
  f.env.SESSION_DECRYPTION_KEYS_JSON=JSON.stringify({retainedSession:b64(6)});
  const before={...f.env};
  assert.equal(typeof await createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork}),'function');
  assert.deepEqual(f.env,before);assert.equal(f.state.calls,0);assert.equal(f.state.asserts,0);
 }finally{await f.close();}
});
test('HTTP and worker construction require their existing work kind',async()=>{
 const f=await fixture('jobs');try{await assert.rejects(createCollectNativeRuntime(f.env,{trustedNetworkBucket:serverNetwork}),e=>e.code==='request_not_admitted');}finally{await f.close();}
 const other=await fixture();try{other.env.BURIMUNSI_NATIVE_WORKERS_ENABLED='true';await assert.rejects(createCollectNativeWorkerRuntime(other.env),e=>e.code==='request_not_admitted');}finally{await other.close();}
});
for(const value of [undefined,'false','TRUE',true])test('worker remains separately disabled: '+String(value),async()=>{
 const f=await fixture('jobs');try{f.env.BURIMUNSI_NATIVE_WORKERS_ENABLED=value;assert.equal(await createCollectNativeWorkerRuntime(f.env),null);assert.equal(f.state.calls,0);}finally{await f.close();}
});
test('explicit worker composition creates no scheduler/provider effects and preserves processing hold',async()=>{
 const f=await fixture('jobs');try{
  f.env.BURIMUNSI_NATIVE_WORKERS_ENABLED='true';const workers=await createCollectNativeWorkerRuntime(f.env);
  assert.equal(typeof workers.processReceipts,'function');assert.equal(typeof workers.runScheduledCycle,'function');
  assert.equal(f.env.MOMO_PROCESSING_PAUSED,'true');assert.equal(f.state.calls,0);assert.equal(f.state.asserts,0);
 }finally{await f.close();}
});
test('an invalid staff default cannot disable the separately scoped worker',async()=>{
 const f=await fixture('jobs');try{
  f.env.BURIMUNSI_NATIVE_WORKERS_ENABLED='true';f.env.BURIMUNSI_DEFAULT_STAFF_PIN='bad';
  assert.equal(typeof (await createCollectNativeWorkerRuntime(f.env)).processReceipts,'function');
  assert.equal(f.state.calls,0);
 }finally{await f.close();}
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
