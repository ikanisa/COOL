import test from 'node:test';
import assert from 'node:assert/strict';
import {digest} from '../../domain/core.js';
import {createSmartOnboardingPolicy} from '../../domain/burimunsi/smart-onboarding-policy.js';

const now=1794560000000,build='a'.repeat(64),approvalId='11111111-1111-4111-8111-111111111111';
async function fixture(){
 const p={schema_version:1,status:'approved',enabled:true,purpose:'collect_roster_pdf_image_extraction',provider:'openai',
  responses_endpoint:'https://api.openai.com/v1/responses',decoder_url:'https://roster-decoder.internal/decode',
  approval_id:approvalId,approval_evidence_sha256:'b'.repeat(64),decoder_build_sha256:build,project_id:'proj-synthetic',
  organization_id:'org-synthetic',model:'fixture-vision',processing_region_evidence_ref:'ref:region',retention_evidence_ref:'ref:retention',
  decoder_processor_evidence_ref:'ref:decoder',decoder_region_evidence_ref:'ref:region',decoder_retention_evidence_ref:'ref:retention',
  approved_at:new Date(now-1000).toISOString(),valid_until:new Date(now+100000).toISOString()};
 const raw=JSON.stringify(p),env={ROSTER_AI_APPROVAL_JSON:raw,ROSTER_AI_APPROVAL_SHA256:await digest(raw),
  ROSTER_DECODER_BUILD_SHA256:build,OPENAI_PROJECT_ID:p.project_id,OPENAI_ORGANIZATION_ID:p.organization_id,
  ROSTER_AI_MODEL:p.model,OPENAI_API_KEY:'synthetic-key-not-real-1234567890',ROSTER_DECODER:{fetch:async()=>{throw new Error('no network');}}};
 let time=now;return {p,env,policy:createSmartOnboardingPolicy({env,clock:()=>time}),setTime:value=>{time=value;},
  async revise(){env.ROSTER_AI_APPROVAL_JSON=JSON.stringify(p);env.ROSTER_AI_APPROVAL_SHA256=await digest(env.ROSTER_AI_APPROVAL_JSON);}};
}
test('existing approved roster policy is checked and rebound before dispatch',async()=>{
 const f=await fixture(),snapshot=await f.policy.read();assert.equal(snapshot.decoder,f.env.ROSTER_DECODER);
 assert.equal(snapshot.projectId,'proj-synthetic');assert.equal(await f.policy.assertCurrent(snapshot),true);
 f.env.OPENAI_PROJECT_ID='other';assert.equal(await f.policy.assertCurrent(snapshot),false);
});
for(const [name,change] of [
 ['wrong purpose',p=>p.purpose='unrelated'],['disabled approval',p=>p.enabled=false],
 ['unapproved status',p=>p.status='draft'],['wrong provider',p=>p.provider='other'],
 ['wrong endpoint',p=>p.responses_endpoint='https://other.invalid/'],['missing retention evidence',p=>delete p.retention_evidence_ref],
 ['wrong build',p=>p.decoder_build_sha256='d'.repeat(64)],['invalid approval ID',p=>p.approval_id='not-a-uuid'],
 ['future approval',p=>p.approved_at=new Date(now+500).toISOString()],['expired approval',p=>p.valid_until=new Date(now).toISOString()],
])test('rejects '+name+' without a provider call',async()=>{
 const f=await fixture();change(f.p);await f.revise();await assert.rejects(f.policy.read(),/smart_import_ocr_unavailable/);
});
test('changed bytes, key, decoder or elapsed approval invalidates the original snapshot',async()=>{
 for(const change of [f=>f.env.ROSTER_AI_APPROVAL_JSON+=' ',f=>f.env.OPENAI_API_KEY+='x',
  f=>f.env.ROSTER_DECODER={fetch:async()=>{}},f=>f.setTime(now+100001)]){
  const f=await fixture(),snapshot=await f.policy.read();change(f);assert.equal(await f.policy.assertCurrent(snapshot),false);
 }
});
