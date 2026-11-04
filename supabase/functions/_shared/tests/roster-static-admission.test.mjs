import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {attestAdminEmailAccount,bindAdminEmailActor} from '../domain/admin_email_policy.js';
import {functionRpc} from '../domain/roster.js';

const corpus=new URL('../../../../tools/roster-decoder/native-probe/corpus/',import.meta.url);
const localFixtures=new URL('./fixtures/',import.meta.url);
const fixture=(base,name)=>readFileSync(new URL(name,base));
function actor(){
 const userId=randomUUID(),sessionId=randomUUID();
 const account={id:randomUUID(),principal_id:userId,auth_user_id:randomUUID(),auth_session_id:sessionId,
  token_hash:'a'.repeat(64),public_id:randomUUID(),origin:'https://admin.example.invalid',auth_version:1};
 attestAdminEmailAccount(account,{contract_version:1,public_session_id:account.public_id,
  email_verified_at:Math.floor(Date.now()/1000),proof_id:randomUUID()});
 return bindAdminEmailActor({surface:'admin',userId,sessionId,permissions:new Set(['roster.import'])},account);
}
function request(sourceType,mime,bytes){
 return {contract_version:1,request_id:randomUUID(),source_type:sourceType,filename:'fixture',mime_type:mime,
  content_base64:Buffer.from(bytes).toString('base64'),ai_consent:true,consent_version:'roster-ai-extraction-v1'};
}
function trapEnvironment(){
 const touched=[];const stop=new Error('database boundary reached');
 return {touched,stop,env:{DB:{prepare(){touched.push('database');throw stop;}},
  PRIVATE_MEDIA:{async put(){touched.push('storage write');throw stop;},async get(){touched.push('storage read');throw stop;}},
  ROSTER_DECODER:{async fetch(){touched.push('decoder');throw stop;}}}};
}

test('animated PNG, WebP, multi-picture JPEG and JPEG video are refused before storage or processing',async t=>{
 const providerCalls=[];const originalFetch=globalThis.fetch;
 globalThis.fetch=async(...args)=>{providerCalls.push(args);throw new Error('unexpected provider call');};
 t.after(()=>{globalThis.fetch=originalFetch;});
 const cases=[['animated PNG',fixture(corpus,'animation-3.png'),'image/png'],
  ['animated WebP',fixture(corpus,'animation-3.webp'),'image/webp'],
  ['multi-picture JPEG',fixture(localFixtures,'roster-image-multiframe.mpo'),'image/jpeg'],
  ['JPEG with video',Buffer.concat([fixture(corpus,'scanned-multilingual.jpg'),fixture(localFixtures,'roster-motion-h264.mp4')]),'image/jpeg']];
 for(const [name,bytes,mime] of cases){
  const {env,touched}=trapEnvironment();
  await assert.rejects(()=>functionRpc('roster-import-upload',request('image',mime,bytes),env,actor()),
   error=>error.status===400&&error.code==='roster_animated_image_unsupported'&&/static image/i.test(error.message));
  assert.deepEqual(touched,[],name);
 }
 assert.deepEqual(providerCalls,[]);
});

test('ordinary static images and supported documents pass image admission and reach the existing database boundary',async()=>{
 const cases=[['image','image/png',fixture(corpus,'scanned-multilingual.png')],
  ['image','image/jpeg',fixture(corpus,'scanned-multilingual.jpg')],
  ['image','image/webp',fixture(corpus,'scanned-multilingual.webp')],
  ['pdf','application/pdf',fixture(corpus,'scanned-multilingual.pdf')],
  ['csv','text/csv',fixture(corpus,'english.csv')],
  ['txt','text/plain',Buffer.from('Example,Example,0788123456')],
  ['xlsx','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',fixture(corpus,'multilingual.xlsx')]];
 for(const [kind,mime,bytes] of cases){
  const {env,touched,stop}=trapEnvironment();
  const body=request(kind,mime,bytes);if(kind==='xlsx')body.derived_content='Name\tMoMo name\tPhone\nExample\tExample\t0788123456';
  await assert.rejects(()=>functionRpc('roster-import-upload',body,env,actor()),error=>error===stop);
  assert.deepEqual(touched,['database'],mime);
 }
});
