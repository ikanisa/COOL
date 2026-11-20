/** Existing fence/journal/provider contract with a local byte-preserving JPEG port. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {digest} from '../../domain/core.js';
import {openApplicationWork} from '../../application-fence.js';
import {createNativeRosterJpegDecoder,NATIVE_JPEG_IDENTITY,NATIVE_JPEG_PROTOCOL} from '../../roster_native_jpeg_decoder.mjs';
import {createSmartOnboardingPolicy} from '../../domain/burimunsi/smart-onboarding-policy.js';
import {createGuardedSmartOnboardingImport} from '../../domain/burimunsi/smart-onboarding-dispatch.js';
import {syntheticFenceBackend,SYNTHETIC_FENCE_SOURCE} from '../helpers/fenced-unit.js';

const now=1794828000000,build='a'.repeat(64),groupId='group-1',model='existing-vision-snapshot';
const actor={id:'actor-1',sessionId:'session-1',groupId};
const jpeg=()=>readFile(new URL('../fixtures/roster-image-progressive.jpg',import.meta.url));
async function policyFixture(){
 const p={schema_version:2,status:'owner_authorized',enabled:true,purpose:'collect_roster_static_jpeg_preview',provider:'openai',
  responses_endpoint:'https://api.openai.com/v1/responses',decoder_protocol:NATIVE_JPEG_PROTOCOL,decoder_identity:NATIVE_JPEG_IDENTITY,
  decoder_build_sha256:build,model,collection_id:groupId,source_sha256:SYNTHETIC_FENCE_SOURCE,authorization_evidence_sha256:'b'.repeat(64),
  technical_checks_sha256:'c'.repeat(64),authorized_at:new Date(now-1000).toISOString(),valid_until:null,request_consent_required:true,preview_only:true};
 const env={BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED:'true',BUILD_SOURCE_ID:SYNTHETIC_FENCE_SOURCE,
  MOMO_AI_MODEL:model,ROSTER_AI_MODEL:model,ROSTER_DECODER_PROTOCOL:NATIVE_JPEG_PROTOCOL,ROSTER_DECODER_URL:NATIVE_JPEG_IDENTITY,
  ROSTER_DECODER_SECRET:'',ROSTER_DECODER_BUILD_SHA256:build,OPENAI_API_KEY:'synthetic-existing-key-1234567890'};
 env.ROSTER_DECODER=createNativeRosterJpegDecoder({protocol:NATIVE_JPEG_PROTOCOL,identity:NATIVE_JPEG_IDENTITY,approvedBuildSha256:build});
 const revise=async()=>{env.ROSTER_AI_APPROVAL_JSON=JSON.stringify(p);env.ROSTER_AI_APPROVAL_SHA256=await digest(env.ROSTER_AI_APPROVAL_JSON);};
 await revise();return {p,env,revise,policy:createSmartOnboardingPolicy({env,clock:()=>now})};
}
test('source-bound owner JPEG policy omits absent project/org and detects runtime revocation',async()=>{
 const f=await policyFixture(),snapshot=await f.policy.read({groupId,mimeType:'image/jpeg'});
 assert.equal(snapshot.projectId,undefined);assert.equal(snapshot.organizationId,undefined);
 assert.equal(await f.policy.assertCurrent(snapshot),true);
 f.env.BURIMUNSI_SMART_ONBOARDING_ADVANCED_ENABLED='false';assert.equal(await f.policy.assertCurrent(snapshot),false);
});
for(const [name,change] of [
 ['bad expiry',f=>f.p.valid_until='not-a-date'],['wrong source',f=>f.p.source_sha256='d'.repeat(64)],
 ['wrong collection',f=>f.p.collection_id='other'],['new model',f=>f.p.model='another'],
 ['invented organization',f=>f.p.organization_id='org-fiction'],['missing evidence',f=>delete f.p.authorization_evidence_sha256],
 ['extra approval claim',f=>f.p.legal_approval=true],['unbranded decoder',f=>f.env.ROSTER_DECODER={...f.env.ROSTER_DECODER}],
])test('native policy refuses '+name,async()=>{
 const f=await policyFixture();change(f);await f.revise();await assert.rejects(f.policy.read({groupId,mimeType:'image/jpeg'}),/smart_import_ocr_unavailable/);
});
test('native policy does not enable other image/document formats',async()=>{
 const f=await policyFixture();for(const mimeType of ['image/png','application/pdf'])
  await assert.rejects(f.policy.read({groupId,mimeType}),/smart_import_ocr_unavailable/);
});
async function dispatchFixture(){
 const f=await policyFixture(),work=await openApplicationWork({backend:syntheticFenceBackend(),sourceSha256:SYNTHETIC_FENCE_SOURCE,kind:'http_collect'});
 f.env.COLLECT_FENCE_WORK=work;
 const state={calls:0,reservations:0,phases:[],completed:0,stored:null,fails:false};
 const journal={async reserve(v){state.reservations++;if(state.stored)return {...state.stored,state:state.stored.state==='completed'?'completed':'pending'};
  state.stored={state:'reserved',groupId:v.groupId,actorId:v.actorId,sourceSha256:v.sourceSha256,mimeType:v.mimeType,policySha256:v.policySha256,
   decoderBuildSha256:v.decoderBuildSha256,requestId:v.proposedRequestId,reservationId:v.proposedReservationId};return {...state.stored};},
  async advance({phase}){state.phases.push(phase);state.stored={...state.stored,state:phase};return {...state.stored};},
  async complete({preview}){state.completed++;state.stored={...state.stored,state:'completed',preview};return {...state.stored};}};
 const originalFetch=globalThis.fetch;
 globalThis.fetch=async(url,init)=>{
  assert.equal(url,'https://api.openai.com/v1/responses');state.calls++;
  assert.equal(Object.hasOwn(init.headers,'OpenAI-Organization'),false);assert.equal(Object.hasOwn(init.headers,'OpenAI-Project'),false);
  const wire=JSON.parse(init.body);assert.equal(wire.model,model);assert.equal(wire.store,false);assert.deepEqual(wire.tools,[]);
  assert.equal(wire.input[0].content[0].image_url,'data:image/jpeg;base64,'+(await jpeg()).toString('base64'));
  if(state.fails)throw new Error('synthetic unknown provider outcome');
  return Response.json({object:'response',status:'completed',error:null,incomplete_details:null,tools:[],output:[
   {type:'reasoning',id:'rs_fixture',summary:[]},
   {type:'message',role:'assistant',status:'completed',content:[{type:'output_text',annotations:[],text:JSON.stringify({rows:[{momoName:'Synthetic Example',momoNumber:'0781234567'}]})}]}]});
 };
 const importer=createGuardedSmartOnboardingImport({env:f.env,groupId,policy:f.policy,journal});
 return {...f,state,preview:async(consent=true,mimeType='image/jpeg')=>importer.preview({actor,groupId,bytes:new Uint8Array(await jpeg()),mimeType,externalOcrConsent:consent,authorize:async()=>actor}),
  async close(){try{return await work.finish();}finally{globalThis.fetch=originalFetch;}}};
}
test('JPEG preview uses one admitted provider call, zero decoder network calls and recovers exact output',async()=>{
 const f=await dispatchFixture();try{
  const first=await f.preview(),again=await f.preview();assert.deepEqual(again,first);
  assert.equal(first.rows[0].momoNumber,'+250781234567');assert.deepEqual(f.state.phases,['decode','extract']);
  assert.equal(f.state.calls,1);assert.equal(f.state.completed,1);assert.equal((await f.close()).externalDispatches,1);
 }catch(error){await f.close();throw error;}
});
test('consent and exact source binding fail before journal or provider',async()=>{
 const f=await dispatchFixture();try{
  await assert.rejects(f.preview(false),/smart_import_consent_required/);
  f.env.BUILD_SOURCE_ID='d'.repeat(64);await assert.rejects(f.preview(),/smart_import_ocr_unavailable/);
  assert.equal(f.state.reservations,0);assert.equal(f.state.calls,0);
 }finally{await f.close();}
});
test('unknown provider outcome remains pending without a second call',async()=>{
 const f=await dispatchFixture();f.state.fails=true;try{
  await assert.rejects(f.preview(),/smart_import_ocr_unconfirmed/);await assert.rejects(f.preview(),/smart_import_pending/);
  assert.equal(f.state.calls,1);assert.equal(f.state.completed,0);assert.equal((await f.close()).uncertainDispatches,1);
 }catch(error){await f.close();throw error;}
});
