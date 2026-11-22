import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {bindNativeResponse,contractRoute,validateNativeRequest} from '../../domain/burimunsi/wire/native-contract.mjs';
import {canonicalProfile,legacyDeploymentProfile} from '../../deployment-profile.js';

await import('../helpers/node-postgres-import.mjs');
const {createHandler}=await import('../../serve.js');
const {collectNativeRoute}=await import('../../domain/burimunsi/collect-route.js');
const hash=value=>createHash('sha256').update(value).digest('hex');
const id='10000000-0000-4000-8000-000000000001',installation='20000000-0000-4000-8000-000000000002';
const prefix='/v1/burimunsi/sms/observations/';
const operations=[
 ['POST','recover-held','observationRecoverHeld'],
 ['POST','recover-held-ack','observationRecoverHeldAck'],
 ['GET','reconcile-verified-status','observationReconcileVerifiedStatus'],
];
const binding={requestId:id,generation:'1',installationId:installation,groupId:'fixture-group',actorId:id};
const held={requestId:id,rawSender:'Fixture',rawBody:'Synthetic receipt',sourceMode:'catch_up',complete:false,
 capturedAt:'2026-11-17T12:00:00.000Z',serviceCentreAt:null,inboxReceivedAt:'2026-11-17T12:00:00.000Z',
 subscriptionId:null,sourceKey:'c'.repeat(64),expectedConsentGeneration:2};

test('held wire requires the original consent and binds acknowledgment identity and retry policy',()=>{
 for(const [method,path,operation] of operations){
  assert.equal(contractRoute(method,'/sms/observations/'+path).operation,operation);
  if(method==='GET'){assert.doesNotThrow(()=>validateNativeRequest(operation,null));continue;}
  assert.doesNotThrow(()=>validateNativeRequest(operation,held));
  const {expectedConsentGeneration,...predecessor}=held;
  assert.throws(()=>validateNativeRequest(operation,predecessor));
  for(const changed of [{expectedConsentGeneration:0},{sourceMode:'live',complete:true},{inboxReceivedAt:null},
   {rawBody:'€'.repeat(1001)}])assert.throws(()=>validateNativeRequest(operation,{...held,...changed}));
 }
 const ack={requestId:id,sourceKey:held.sourceKey,bodySha256:hash(held.rawBody),
  state:'unconfirmed',sourceId:null,autoProcessing:'unknown',financialEffects:0,retryAllowed:false};
 const bind=data=>bindNativeResponse({operation:'observationRecoverHeldAck',observationBodySha256:hash(held.rawBody)},binding,held,data);
 assert.doesNotThrow(()=>bind(ack));
 assert.doesNotThrow(()=>bind({...ack,state:'acknowledged',sourceId:installation,autoProcessing:'held'}));
 for(const change of [{sourceKey:'e'.repeat(64)},{bodySha256:'e'.repeat(64)},{requestId:installation},{sourceId:installation},{state:'acknowledged'},
  {autoProcessing:'held'},{financialEffects:1},{retryAllowed:true}])assert.throws(()=>bind({...ack,...change}));
});

test('managed raw held paths return native 404 before ingress reads, admission or dispatch',async t=>{
 const profile=legacyDeploymentProfile(true),serialized=canonicalProfile(profile),events=[];
 const denied=stage=>(..._args)=>{events.push(stage);throw Error('unexpected external operation');};
 t.mock.method(globalThis,'fetch',denied('network'));
 t.mock.method(globalThis,'__collectFencePostgresFixture',denied('database'));
 for(const mode of ['supabase_direct_v1','signed_frontdoor_v1']){
  const env={COLLECT_DEPLOYMENT_PROFILE:serialized,COLLECT_DEPLOYMENT_PROFILE_SHA256:hash(serialized),
   APP_ENVIRONMENT:profile.environment,SUPABASE_URL:profile.supabase_origin,BURIMUNSI_NATIVE_ENABLED:'true',
   COLLECT_NATIVE_INGRESS_MODE:mode};
  const handler=createHandler('collect-api',()=>env,{openWork:denied('fence'),reportHealth:denied('failure'),
   admitDirectSupabaseNativeIngress:denied('direct ingress'),verifyNativeIngress:denied('signed ingress')});
  for(const [method,suffix] of operations){
   for(const attempt of [1,2]){
    let pulls=0,cancellations=0;
    const input=method==='GET'?{}:{body:new ReadableStream({
     pull(controller){pulls++;controller.close();},cancel(){cancellations++;}
    },{highWaterMark:0}),duplex:'half'};
    const req=new Request(profile.supabase_origin+'/functions/v1/collect-api'+prefix+suffix,{method,...input});
    const response=await handler(req);
    assert.equal(response.status,404,mode+' '+suffix+' '+attempt);
    assert.equal(response.headers.get('Cache-Control'),'no-store');
    assert.equal(response.headers.get('X-BuriMunsi-Contract'),'burimunsi.native.v1');
    assert.deepEqual(await response.json(),{contractVersion:'burimunsi.native.v1',ok:false,error:{code:'not_found'}});
    assert.equal(pulls,0);assert.equal(cancellations,method==='GET'?0:1);
   }
   const inner=await collectNativeRoute(new Request(profile.supabase_origin+prefix+suffix,{method}),{});
   assert.equal(inner.status,404);
  }
 }
 assert.deepEqual(events,[]);
});
