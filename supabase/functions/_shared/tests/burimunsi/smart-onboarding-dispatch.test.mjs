/** Synthetic journal, signed decoder supervisor and provider. No live data/network. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,createHmac} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {openApplicationWork,guardedFetch,applicationWork,noteUnknownEffect} from '../../application-fence.js';
import {createRosterDecoderBridge} from '../../roster_decoder_bridge.mjs';
import {createGuardedSmartOnboardingImport} from '../../domain/burimunsi/smart-onboarding-dispatch.js';
import {RecordsService} from '../../domain/burimunsi/records-service.js';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
import {canonicalProfile,legacyDeploymentProfile} from '../../deployment-profile.js';
import {admitDirectSupabaseNativeIngress} from '../../native-direct-supabase-ingress.js';
import {syntheticFenceBackend,SYNTHETIC_FENCE_SOURCE} from '../helpers/fenced-unit.js';

const actor={id:'member-actor',sessionId:'member-session',groupId:'group-1',role:'staff',active:true,revoked:false,
 expiresAt:9999999999999,installationId:'device-1',installationProfile:'staff',capabilities:['members.enroll']};
const secret='synthetic-roster-bridge-signing-key-0123456789',endpoint='https://decoder.example.invalid/decode';
const build='a'.repeat(64),policyHash='b'.repeat(64),apiKey='synthetic-provider-key-long-enough';
const toolchain={python:'3.12',pillow:'12.3.0',pypdfium2:'5.2.0',pypdf:'6.19.0',openpyxl:'3.1.5',defusedxml:'0.7.1'};
const corpus=new URL('../../../../../tools/roster-decoder/native-probe/corpus/',import.meta.url);
const hash=value=>createHash('sha256').update(value).digest('hex');
const disclosure={importFlowId:'77777777-7777-4777-8777-777777777777',ocrDisclosureVersion:'burimunsi-ocr-disclosure-v1'};
const rows=[{momoName:'Example Member',momoNumber:'0781234567'}];

async function fixture(){
 const backend=syntheticFenceBackend(),work=await openApplicationWork({backend,sourceSha256:SYNTHETIC_FENCE_SOURCE,kind:'http_collect'});
 const env={COLLECT_FENCE_WORK:work,ROSTER_AI_APPROVAL_SHA256:policyHash,ROSTER_DECODER_BUILD_SHA256:build,
  OPENAI_API_KEY:apiKey,ROSTER_AI_MODEL:'fixture-vision',OPENAI_ORGANIZATION_ID:'org-fixture',OPENAI_PROJECT_ID:'proj-fixture'};
 const state={decoderCalls:0,providerCalls:0,allowed:true,policyCurrent:true,providerFails:false,revokeOnDecode:false,
  reservations:0,phases:[],completed:0,stored:null,clock:0,expireOnDecode:false,
  invalidatePolicyOnDecode:false,revokeOnProvider:false,inSnapshot:false,loseCompletionAck:false};
 const policy={async read(){return {decoder:env.ROSTER_DECODER,decoderBuildSha256:build,policySha256:policyHash,
   apiKey,model:'fixture-vision',organizationId:'org-fixture',projectId:'proj-fixture'};},
  async assertCurrent(){state.onPolicyCheck?.();return state.policyCurrent;}};
 const journal={async reserve(input){state.reservations++;
   if(state.stored){const saved=state.stored;return {...saved,state:saved.state==='completed'?'completed':'pending'};}
   state.stored={state:'reserved',groupId:input.groupId,actorId:input.actorId,sourceSha256:input.sourceSha256,
    mimeType:input.mimeType,policySha256:input.policySha256,decoderBuildSha256:input.decoderBuildSha256,
    importFlowId:input.importFlowId,ocrDisclosureVersion:input.ocrDisclosureVersion,sessionId:input.sessionId,requestId:input.proposedRequestId,reservationId:input.proposedReservationId};return {...state.stored};},
  async advance({receipt,phase}){assert.equal(receipt.requestId,state.stored.requestId);state.phases.push(phase);
   state.stored={...state.stored,state:phase};state.onAdvance?.(phase);return {...state.stored};},
  async complete({receipt,preview}){assert.equal(receipt.requestId,state.stored.requestId);state.completed++;
   state.stored={...state.stored,state:'completed',preview};
   if(state.loseCompletionAck){state.loseCompletionAck=false;throw new Error('synthetic lost acknowledgement');}
   return {...state.stored};}};
 const originalFetch=globalThis.fetch;
 globalThis.fetch=async(url,init)=>{
  assert.equal(state.inSnapshot,false);
  if(url===endpoint){state.decoderCalls++;assert.equal(init.redirect,'error');
   assert.equal(init.headers.Authorization,'Roster-HMAC '+createHmac('sha256',secret).update(init.body).digest('hex'));
   const wire=JSON.parse(init.body),derived=wire.kind==='xlsx'?'Member name\tMoMo name\tMoMo number\nExample\tExample Member\t0781234567':null;
   const frames=wire.kind==='image'?1:0;
   const payload=JSON.stringify({contract_version:1,request_id:wire.request_id,reservation_id:wire.reservation_id,nonce:wire.nonce,
    issued_at:Math.floor(Date.now()/1000),kind:wire.kind,mime:wire.mime,decoder_build_sha256:build,ok:true,
    policy_version:'collect-roster-decoder-v1',toolchain,source_sha256:wire.source_sha256,
    source_size:Buffer.from(wire.content_base64,'base64').length,derived_sha256:derived===null?null:hash(derived),
    frames,pages:wire.kind==='pdf'?1:0,pixels:wire.kind==='image'||wire.kind==='pdf'?1:0,
    expanded_bytes:frames*4,derived_content:derived});
   state.onDecoder?.(init.signal);
   if(state.revokeOnDecode)state.allowed=false;
   if(state.expireOnDecode)state.clock=1001;
   if(state.invalidatePolicyOnDecode)state.policyCurrent=false;
   return Response.json({payload,signature:createHmac('sha256',secret).update(payload).digest('hex')});
  }
  assert.equal(url,'https://api.openai.com/v1/responses');state.providerCalls++;
  assert.equal(init.headers['OpenAI-Organization'],'org-fixture');assert.equal(init.headers['OpenAI-Project'],'proj-fixture');
  assert.equal(init.headers.Authorization,`Bearer ${apiKey}`);assert.equal(JSON.parse(init.body).store,false);
  state.onProvider?.(init.signal);
  if(state.providerFails)throw new Error('synthetic network error');
  if(state.revokeOnProvider)state.allowed=false;
  return Response.json({object:'response',status:'completed',error:null,incomplete_details:null,tools:[],
   output:[{type:'message',role:'assistant',status:'completed',content:[{type:'output_text',annotations:[],text:JSON.stringify({rows})}]}]});
 };
 env.ROSTER_DECODER=createRosterDecoderBridge({protocol:'roster-hmac-v1',endpoint,secret,approvedBuildSha256:build,
  fetchImpl:(...args)=>guardedFetch(env,'decoder',...args),trackPromise:promise=>applicationWork(env).waitUntil(promise),
  onUncertain:()=>noteUnknownEffect(env,'decoder')});
 const importer=createGuardedSmartOnboardingImport({env,groupId:'group-1',policy,journal,clock:()=>state.clock,budgetMs:1000});
 const authorize=async()=>{if(!state.allowed)throw new Error('synthetic authority revoked');return actor;};
 const preview=(bytes,mimeType,consent=true,binding=disclosure)=>importer.preview({actor,groupId:'group-1',bytes,mimeType,externalOcrConsent:consent,...binding,authorize});
 const close=async()=>{try{return await work.finish();}finally{globalThis.fetch=originalFetch;}};
 return {state,preview,close,env,importer};
}

for(const [filename,mime,kind] of [
 ['scanned-multilingual.png','image/png','image'],['scanned-multilingual.pdf','application/pdf','pdf'],
 ['multilingual.xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','xlsx'],
])test('guarded signed '+kind+' import records each phase and recovers without redispatch',async()=>{
 const f=await fixture();try{
  const bytes=new Uint8Array(await readFile(new URL(filename,corpus)));
  const first=await f.preview(bytes,mime),second=await f.preview(bytes,mime);
  assert.deepEqual(second,first);assert.equal(first.sourceKind,kind);assert.equal(first.rows[0].momoNumber,'+250781234567');
  assert.deepEqual(f.state.phases,kind==='xlsx'?['decode']:['decode','extract']);
  assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,kind==='xlsx'?0:1);assert.equal(f.state.completed,1);
  const outcome=await f.close();assert.equal(outcome.externalDispatches,kind==='xlsx'?1:2);
 }catch(error){await f.close();throw error;}
});

test('missing consent or a mismatched policy stops before journal and dispatch',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=await fixture();
 try{await assert.rejects(f.preview(bytes,'image/png',false),/smart_import_consent_required/);
  await assert.rejects(f.preview(bytes,'image/png',true,{}),/smart_import_disclosure_required/);
  f.env.OPENAI_PROJECT_ID='proj-other';await assert.rejects(f.preview(bytes,'image/png'),/smart_import_ocr_unavailable/);
  assert.equal(f.state.reservations,0);assert.equal(f.state.decoderCalls,0);assert.equal(f.state.providerCalls,0);
 }finally{await f.close();}
});

test('revoked enrollment authority after decoder prevents provider dispatch',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=await fixture();f.state.revokeOnDecode=true;
 try{await assert.rejects(f.preview(bytes,'image/png'));
  assert.deepEqual(f.state.phases,['decode']);assert.equal(f.state.providerCalls,0);assert.equal(f.state.completed,0);
 }finally{await f.close();}
});

test('unknown provider outcome remains pending and a repeated upload does not redispatch',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=await fixture();f.state.providerFails=true;
 try{await assert.rejects(f.preview(bytes,'image/png'),/smart_import_ocr_unconfirmed/);
  await assert.rejects(f.preview(bytes,'image/png'),/smart_import_pending/);
  assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,1);assert.equal(f.state.completed,0);
  const outcome=await f.close();assert.equal(outcome.uncertainDispatches,1);
 }catch(error){await f.close();throw error;}
});

test('expired request budget cannot start a provider dispatch after decoding',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=await fixture();f.state.expireOnDecode=true;
 try{await assert.rejects(f.preview(bytes,'image/png'));
  assert.deepEqual(f.state.phases,['decode']);assert.equal(f.state.providerCalls,0);assert.equal(f.state.completed,0);
 }finally{await f.close();}
});

test('a recovered journal record bound to another group is refused',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=await fixture();
 try{await f.preview(bytes,'image/png');f.state.stored.groupId='other';
  await assert.rejects(f.preview(bytes,'image/png'),/smart_import_pending/);
  assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,1);
 }finally{await f.close();}
});

test('policy change after decoder prevents provider dispatch',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=await fixture();f.state.invalidatePolicyOnDecode=true;
 try{await assert.rejects(f.preview(bytes,'image/png'));
  assert.deepEqual(f.state.phases,['decode']);assert.equal(f.state.providerCalls,0);assert.equal(f.state.completed,0);
 }finally{await f.close();}
});

test('revocation during provider execution prevents preview publication',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=await fixture();f.state.revokeOnProvider=true;
 try{await assert.rejects(f.preview(bytes,'image/png'));
  assert.deepEqual(f.state.phases,['decode','extract']);assert.equal(f.state.providerCalls,1);assert.equal(f.state.completed,0);
 }finally{await f.close();}
});

function recordsFor(f){
 const tx={reloadActor:async()=>f.state.allowed?actor:null,loadBinding:async()=>null};
 return new RecordsService({groupId:'group-1',smartOnboardingImport:f.importer,clock:()=>0,
  cursor:{create:async()=>{},read:async()=>{}},store:{async withReadSnapshot(fn){
   assert.equal(f.state.inSnapshot,false);f.state.inSnapshot=true;try{return await fn(tx);}finally{f.state.inSnapshot=false;}}}});
}

test('records authorization and real fenced signed decoder execute without an open snapshot',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=await fixture(),records=recordsFor(f);
 try{const result=await records.onboardingPreview(actor,{bytes,mimeType:'image/png',externalOcrConsent:true,...disclosure});
  assert.equal(result.rows[0].momoNumber,'+250781234567');assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,1);
 }finally{await f.close();}
});

async function nativePreview(f,bytes,signal,fields={}){
 const profile=legacyDeploymentProfile(true),raw=canonicalProfile(profile),unused=()=>assert.fail('unused port');
 const env={COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:hash(raw),APP_ENVIRONMENT:profile.environment,
  SUPABASE_URL:profile.supabase_origin,BURIMUNSI_NATIVE_ENABLED:'true',COLLECT_NATIVE_INGRESS_MODE:'supabase_direct_v1'};
 const req=new Request(profile.supabase_origin+'/v1/burimunsi/members/import/preview',{method:'POST',signal,
  headers:{'content-type':'application/json',authorization:'Bearer '+'a'.repeat(64),'x-burimunsi-installation':actor.installationId,
   'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-generation':'1','x-burimunsi-request':crypto.randomUUID()},
  body:JSON.stringify({mimeType:'image/png',fileBytes:bytes.toString('base64'),externalOcrConsent:true,...disclosure,...fields})});
 const admitted=await admitDirectSupabaseNativeIngress(req,env);
 const handler=createNativeHandler({records:recordsFor(f),auth:{authenticate:async(token,installation)=>{
  assert.equal(token,'a'.repeat(64));assert.equal(installation,actor.installationId);return actor;
 },login:unused,logout:unused,changePasscode:unused,manageStaff:unused},members:{enroll:unused,setActive:unused},
  contributions:{allocate:unused},gateway:{status:unused,replace:unused},strictContract:true,
  groupId:actor.groupId,origin:profile.supabase_origin,networkBucket:admitted.networkBucket});
 const response=await handler(admitted.request);
 assert.equal(req.signal.aborted,signal?.aborted??false);
 assert.equal(admitted.request.signal.aborted,req.signal.aborted);
 return response;
}

test('managed native preview requires the approved disclosure and a flow before reserving OCR',async()=>{
 const bytes=await readFile(new URL('scanned-multilingual.png',corpus)),f=await fixture();
 try{
  for(const [fields,code] of [
   [{ocrDisclosureVersion:'previous'},'contract_value'],[{ocrDisclosureVersion:1},'contract_type'],
   [{ocrDisclosureVersion:undefined},'smart_import_disclosure_required'],[{importFlowId:undefined},'smart_import_disclosure_required'],
   [{externalOcrConsent:false},'smart_import_consent_required']]){
   const response=await nativePreview(f,bytes,undefined,fields);
   assert.equal((await response.json()).error.code,code);
  }
  assert.equal(f.state.reservations,0);assert.equal(f.state.decoderCalls,0);assert.equal(f.state.providerCalls,0);
  const inline=await nativePreview(f,Buffer.from('name,phone\nExample,0781234567'),undefined,
   {mimeType:'text/csv',externalOcrConsent:false,importFlowId:undefined,ocrDisclosureVersion:undefined});
  assert.equal(inline.status,200);assert.equal((await inline.json()).data.sourceKind,'csv');
  assert.equal(f.state.reservations,0);
  const fresh=await nativePreview(f,bytes),original=structuredClone(f.state.stored);
  assert.equal(fresh.status,200);
  const replay=await nativePreview(f,bytes,undefined,{importFlowId:crypto.randomUUID()});
  assert.equal(replay.status,200);assert.deepEqual((await fresh.json()).data,(await replay.json()).data);
  assert.deepEqual(f.state.stored,original);assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,1);
 }finally{await f.close();}
});

test('cancelling an admitted preview before reservation prevents any external work',async()=>{
 const bytes=await readFile(new URL('scanned-multilingual.png',corpus)),f=await fixture(),controller=new AbortController();
 try{
  f.state.onPolicyCheck=()=>controller.abort();
  const stopped=await nativePreview(f,bytes,controller.signal);
  assert.equal(f.state.reservations,0);assert.deepEqual(f.state.phases,[]);
  assert.equal(f.state.decoderCalls,0);assert.equal(f.state.providerCalls,0);
  assert.equal(stopped.status,408);
  f.state.onPolicyCheck=null;
  const fresh=await nativePreview(f,bytes);
  assert.equal(fresh.status,200);assert.equal((await fresh.json()).data.rows[0].momoNumber,'+250781234567');
  assert.equal(f.state.reservations,1);assert.equal(f.state.completed,1);
 }finally{await f.close();}
});

test('cancelling after decode retains the original reservation and prevents external OCR',async()=>{
 const bytes=await readFile(new URL('scanned-multilingual.png',corpus)),f=await fixture(),controller=new AbortController();
 try{
  f.state.onPolicyCheck=()=>{if(f.state.decoderCalls===1)controller.abort();};
  const stopped=await nativePreview(f,bytes,controller.signal);
  assert.equal(f.state.providerCalls,0);assert.equal(f.state.completed,0);assert.deepEqual(f.state.phases,['decode']);
  assert.equal(stopped.status,408);
  const original=structuredClone(f.state.stored);
  assert.equal(original.importFlowId,disclosure.importFlowId);assert.equal(original.sessionId,actor.sessionId);
  assert.equal(original.ocrDisclosureVersion,disclosure.ocrDisclosureVersion);
  assert.equal((await (await nativePreview(f,bytes)).json()).error.code,'smart_import_pending');
  assert.deepEqual(f.state.stored,original);assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,0);
  const outcome=await f.close();assert.equal(outcome.externalDispatches,1);assert.equal(outcome.uncertainDispatches,0);
 }finally{await f.close();}
});

test('cancelling an already dispatched OCR retains its original uncertain attempt and withholds the preview',async()=>{
 const bytes=await readFile(new URL('scanned-multilingual.png',corpus)),f=await fixture(),controller=new AbortController();
 let transportSignal;
 try{
  f.state.onProvider=signal=>{transportSignal=signal;controller.abort();};
  const stopped=await nativePreview(f,bytes,controller.signal);
  assert.equal(transportSignal?.aborted,true);assert.equal(f.state.completed,0);assert.deepEqual(f.state.phases,['decode','extract']);
  assert.equal(stopped.status,408);assert.equal((await stopped.json()).data,undefined);
  const original=structuredClone(f.state.stored);
  assert.equal((await (await nativePreview(f,bytes)).json()).error.code,'smart_import_pending');
  assert.deepEqual(f.state.stored,original);assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,1);
  const outcome=await f.close();assert.equal(outcome.externalDispatches,2);assert.equal(outcome.uncertainDispatches,1);
 }finally{await f.close();}
});

test('cancellation after the durable extract claim preserves that claim without calling OCR',async()=>{
 const bytes=await readFile(new URL('scanned-multilingual.png',corpus)),f=await fixture(),controller=new AbortController();
 try{
  f.state.onAdvance=phase=>{if(phase==='extract')controller.abort();};
  const stopped=await nativePreview(f,bytes,controller.signal);
  assert.equal(stopped.status,408);
  assert.equal(f.state.providerCalls,0);assert.equal(f.state.completed,0);
  assert.deepEqual(f.state.phases,['decode','extract']);
  const original=structuredClone(f.state.stored);
  assert.equal((await (await nativePreview(f,bytes)).json()).error.code,'smart_import_pending');
  assert.deepEqual(f.state.stored,original);assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,0);
  const outcome=await f.close();assert.equal(outcome.externalDispatches,1);assert.equal(outcome.uncertainDispatches,0);
 }finally{await f.close();}
});

test('cancelling a dispatched decoder leaves its original pending work and sends no OCR',async()=>{
 const bytes=await readFile(new URL('scanned-multilingual.png',corpus)),f=await fixture(),controller=new AbortController();
 let transportSignal;
 try{
  f.state.onDecoder=signal=>{transportSignal=signal;controller.abort();};
  const stopped=await nativePreview(f,bytes,controller.signal);
  assert.equal(stopped.status,408);assert.equal(transportSignal?.aborted,true);
  assert.deepEqual(f.state.phases,['decode']);assert.equal(f.state.completed,0);
  const original=structuredClone(f.state.stored);
  assert.equal((await (await nativePreview(f,bytes)).json()).error.code,'smart_import_pending');
  assert.deepEqual(f.state.stored,original);assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,0);
  const outcome=await f.close();assert.equal(outcome.externalDispatches,1);assert.equal(outcome.uncertainDispatches,1);
 }finally{await f.close();}
});

test('recovered previews cannot contain extra data from a corrupt journal',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=await fixture();
 try{await f.preview(bytes,'image/png');f.state.stored.preview.rows[0].unexpected='private';
  await assert.rejects(f.preview(bytes,'image/png'),/smart_import_recovery_invalid/);
  assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,1);
 }finally{await f.close();}
});

test('concurrent uploads of the same source reserve only one dispatch',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=await fixture();
 try{const results=await Promise.allSettled([f.preview(bytes,'image/png'),f.preview(bytes,'image/png')]);
  assert.equal(results.filter(item=>item.status==='fulfilled').length,1);
  assert.match(results.find(item=>item.status==='rejected').reason.message,/smart_import_pending/);
  assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,1);
 }finally{await f.close();}
});

test('a lost completion acknowledgement is recovered without another provider call',async()=>{
 const bytes=new Uint8Array(await readFile(new URL('scanned-multilingual.png',corpus))),f=await fixture();f.state.loseCompletionAck=true;
 try{await assert.rejects(f.preview(bytes,'image/png'),/synthetic lost acknowledgement/);
  const recovered=await f.preview(bytes,'image/png');assert.equal(recovered.rows[0].momoNumber,'+250781234567');
  assert.equal(f.state.decoderCalls,1);assert.equal(f.state.providerCalls,1);assert.equal(f.state.completed,1);
 }finally{await f.close();}
});
