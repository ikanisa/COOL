import test from 'node:test';
import assert from 'node:assert/strict';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
import {HELD_V2_PROTOCOL,HELD_V2_MIGRATION_SHA} from '../../domain/burimunsi/held-recovery-v2.js';
import {validateSchema} from '../../domain/burimunsi/wire/runtime.mjs';
import {defs} from '../../domain/burimunsi/wire/burimunsi.generated.mjs';

const actor='11111111-1111-4111-8111-111111111111',install='22222222-2222-4222-8222-222222222222';
const source='33333333-3333-5333-8333-333333333333',sha='a'.repeat(64),noop=async()=>({});
const headers={'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1',
 'x-burimunsi-request':actor,'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json','cache-control':'no-store',
 'x-burimunsi-held-source-sha256':sha,'x-burimunsi-held-migration-sha256':HELD_V2_MIGRATION_SHA};
const request={requestId:actor,rawSender:'Example Money',rawBody:'Received 250 RWF. Reference: 1234.',
 sourceMode:'catch_up',complete:false,capturedAt:'2026-11-11T12:01:00.000Z',serviceCentreAt:null,
 inboxReceivedAt:'2026-11-11T12:00:00.000Z',subscriptionId:null,sourceKey:'a'.repeat(64),expectedConsentGeneration:1};
const capability={protocol:HELD_V2_PROTOCOL,groupId:'group-1',sourceSha256:sha,migrationSha256:HELD_V2_MIGRATION_SHA,consentGeneration:1};
function options(observations){return {auth:{login:noop,authenticate:async()=>({id:actor,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
 records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},contributions:{allocate:noop},
 members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},observations,
 origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop};}
const get=()=>new Request('https://example.invalid/v1/burimunsi/sms/observations/recovery-v2/capability?expectedConsentGeneration=1',{headers});
const post=(body=request)=>new Request('https://example.invalid/v1/burimunsi/sms/observations/recovery-v2/hold',
 {method:'POST',headers,body:JSON.stringify(body)});

test('v2 requires the exact client-pinned release tuple before reading an SMS body',async()=>{
 let calls=0;const enabled={...options({recoveryV2Capability:async()=>capability,recoverHeldV2:async()=>{calls++;return {};}}),
  heldRecoveryV2Enabled:true,heldRecoveryV2SourceSha256:sha};
 const handler=createNativeHandler(enabled),capUrl='https://example.invalid/v1/burimunsi/sms/observations/recovery-v2/capability?expectedConsentGeneration=1';
 const holdUrl='https://example.invalid/v1/burimunsi/sms/observations/recovery-v2/hold';
 for(const name of ['x-burimunsi-held-source-sha256','x-burimunsi-held-migration-sha256']){
  for(const value of [null,'wrong','b'.repeat(64),'duplicate']){
   const h=new Headers(headers);h.delete(name);
   if(value==='duplicate'){h.append(name,headers[name]);h.append(name,headers[name]);}else if(value!==null)h.set(name,value);
   assert.equal((await handler(new Request(capUrl,{headers:h}))).status,403);
   assert.equal((await handler(new Request(holdUrl,{method:'POST',headers:h,body:JSON.stringify(request)}))).status,403);
  }
 }
 assert.equal((await handler(get())).status,200);
 const changed=new Headers(headers);changed.set('x-burimunsi-held-source-sha256','b'.repeat(64));
 assert.equal((await handler(new Request(holdUrl,{method:'POST',headers:changed,body:JSON.stringify(request)}))).status,403);
 assert.equal(calls,0);
});

test('v2 is disabled by default and a permissive old 200 cannot satisfy its capability schema',async()=>{
 let calls=0;const opts=options({recoveryV2Capability:async()=>{calls++;return capability;}});
 assert.equal((await createNativeHandler(opts)(get())).status,404);assert.equal((await createNativeHandler(opts)(post())).status,404);assert.equal(calls,0);
 const old={contractVersion:'burimunsi.native.v1',ok:true,binding:{requestId:actor,generation:'1',installationId:install,groupId:'group-1',actorId:actor},
  data:{requestId:actor,sourceId:source,bodySha256:'b'.repeat(64),status:'source_unresolved',financialEffects:0,autoProcessing:'held'}};
 assert.doesNotThrow(()=>validateSchema(defs,'observationRecoverHeld.response',old));
 assert.throws(()=>validateSchema(defs,'observationRecoveryV2Capability.response',old));
});

test('v2 capability binds the current source, collection, consent, migration and response envelope',async()=>{
 let calls=0;const opts=options({recoveryV2Capability:async()=>{calls++;return capability;}});
 const enabled={...opts,heldRecoveryV2Enabled:true,heldRecoveryV2SourceSha256:sha};
 const ok=await createNativeHandler(enabled)(get());assert.equal(ok.status,200);assert.equal(ok.headers.get('cache-control'),'no-store');
 const body=await ok.json();assert.deepEqual(body.data,capability);assert.equal(body.binding.actorId,actor);
 assert.equal(body.binding.installationId,install);assert.equal(body.binding.requestId,actor);assert.equal(calls,1);
 const oldRoute=new Request('https://example.invalid/v1/burimunsi/sms/observations/recover-held',
  {method:'POST',headers,body:JSON.stringify(request)});
 assert.equal((await createNativeHandler(enabled)(oldRoute)).status,404);
 for(const change of [{sourceSha256:'b'.repeat(64)},{groupId:'other'},{migrationSha256:'0'.repeat(64)},
  {consentGeneration:2},{protocol:'old-server'}]){
  const wrong=createNativeHandler({...enabled,observations:{recoveryV2Capability:async()=>({...capability,...change})}});
  assert.equal((await wrong(get())).status,503);
 }
});

test('v2 mutation requires exact generation and rejects an old-style acknowledgement',async()=>{
 let calls=0;const result={requestId:actor,sourceId:source,bodySha256:'b'.repeat(64),status:'source_unresolved',financialEffects:0,
  autoProcessing:'held',protocol:HELD_V2_PROTOCOL,expectedConsentGeneration:1};
 const opts={...options({recoverHeldV2:async()=>{calls++;return result;}}),heldRecoveryV2Enabled:true,heldRecoveryV2SourceSha256:sha};
 const handler=createNativeHandler(opts);assert.equal((await handler(post())).status,200);
 const {expectedConsentGeneration,...old}=request;
 assert.equal((await handler(post(old))).status,400);assert.equal((await handler(post({...request,expectedConsentGeneration:0}))).status,400);
 assert.equal(calls,1);
 const legacy=createNativeHandler({...opts,observations:{recoverHeldV2:async()=>{const {protocol,...oldResult}=result;return oldResult;}}});
 assert.equal((await legacy(post())).status,503);
});
