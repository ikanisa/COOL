import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
import {openApplicationWork} from '../../../supabase/functions/_shared/application-fence.js';
import {createSyntheticSmsSigner,createSyntheticSmsVerifier,claimSyntheticSmsIngress,managedSmsGatewayUnavailable} from './synthetic-ingress.mjs';
const hash=x=>createHash('sha256').update(x).digest('hex'),key=b=>Buffer.alloc(32,b).toString('base64');
const profile={format:'collect.deployment.v1',id:'sms-fixture',mode:'managed',environment:'qualification',supabase_origin:'https://rrlduytparvsjfmegalh.supabase.co',member_api_origin:'https://sms.example.invalid',admin_origin:'https://admin.example.invalid',public_origin:'https://public.example.invalid',google_callback_origin:'https://admin.example.invalid'};
const raw=canonicalProfile(profile),profileHash=hash(raw);let now=1800000000000;
const proof={evidenceSha256:'e'.repeat(64),format:'collect.sms-ingress.fixture-proof.v1',frontdoorOrigin:profile.member_api_origin,profileSha256:profileHash,reviewedAt:now-1000,status:'synthetic',supabaseOrigin:profile.supabase_origin,workerGuard:'synthetic_cf_worker_reject'};
const canon=x=>JSON.stringify(Object.fromEntries(Object.keys(x).sort().map(k=>[k,x[k]])));
const settings={COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:profileHash,SUPABASE_URL:profile.supabase_origin,APP_ENVIRONMENT:'qualification',COLLECT_SMS_ENABLED:'true',COLLECT_SMS_INGRESS_PROOF_JSON:canon(proof),COLLECT_SMS_INGRESS_PROOF_SHA256:hash(canon(proof)),COLLECT_SMS_INGRESS_KEY_ID:'sms-fixture',COLLECT_SMS_INGRESS_KEY_BASE64:key(7),COLLECT_NATIVE_INGRESS_KEY_BASE64:key(8)};
const clock=()=>now;
async function work(){let row;const backend={register:async(id,sha,kind)=>(row={contractVersion:1,admissionId:id,sourceSha256:sha,epoch:1,state:'active',mode:'open',kind}),
 lease:async()=>({row,assert:async()=>row,release:async()=>{}}),close:async(_id,_epoch,_sha,state,reason,externalDispatches,uncertainDispatches)=>({...row,state,reason,externalDispatches,uncertainDispatches}),status:async()=>({...row,found:true})};
 return openApplicationWork({backend,sourceSha256:'a'.repeat(64),kind:'http_collect'});}
const inbound=(path='/functions/v1/collect-sms/v1/messages',headers={},body='{"message_id":"synthetic"}')=>new Request(profile.member_api_origin+path,{method:'POST',headers:{authorization:'Bearer synthetic-device-secret','idempotency-key':'synthetic-key','content-type':'application/json',...headers},body});

test('synthetic SMS witness rejects unauthorised alteration and unbound callbacks',{timeout:20000},async t=>{
 const sign=await createSyntheticSmsSigner(settings,{clock}),verify=await createSyntheticSmsVerifier(settings,{clock});
 await t.test('signed request retains bearer, body, query and encoded message IDs',async()=>{
  const x=await sign(inbound('/functions/v1/collect-sms/v1/messages/a%3Ab?x=1',{'x-forwarded-host':'evil.invalid','x-collect-sms-ingress':'forged'}));
  assert.equal(x.url,profile.supabase_origin+'/functions/v1/collect-sms/v1/messages/a%3Ab?x=1');
  assert.equal(x.headers.get('authorization'),'Bearer synthetic-device-secret');assert.equal(x.headers.get('idempotency-key'),'synthetic-key');assert.equal(x.headers.has('x-forwarded-host'),false);
  assert.equal(await x.clone().text(),'{"message_id":"synthetic"}');assert.equal(typeof await verify(x),'object');
 });
 await t.test('direct, wrong-origin, similarly named, unqualified Worker and encoded separators refuse',async()=>{
  await assert.rejects(verify(new Request(profile.supabase_origin+'/functions/v1/collect-sms/v1/messages',{method:'POST',body:'{}'})),/sms_ingress_denied/);
  for(const path of ['/functions/v1/collect-sms-other/v1/messages','/functions/v1/collect-sms/v1/messages/a%2Fb'])await assert.rejects(sign(inbound(path)),/sms_ingress_denied/);
  await assert.rejects(sign(new Request('https://evil.example.invalid/functions/v1/collect-sms/health')),/sms_ingress_denied/);
  await assert.rejects(sign(inbound(undefined,{'cf-worker':'example.invalid'})),/sms_ingress_network_denied/);
 });
 await t.test('body, bearer, idempotency key, origin, method and query tampering fail verification',async()=>{
  const x=await sign(inbound()),body=await x.text();
  for(const v of [{body:'{}'},{authorization:'Bearer replacement'},{'idempotency-key':'replacement'},{origin:'https://evil.invalid'},{method:'GET'},{query:'?changed=1'}]){
   const h=new Headers(x.headers);for(const k of ['authorization','idempotency-key','origin'])if(v[k])h.set(k,v[k]);const method=v.method??'POST';
   await assert.rejects(verify(new Request(x.url+(v.query??''),{method,headers:h,body:method==='GET'?undefined:v.body??body})),/sms_ingress_denied/);
  }
 });
 await t.test('arbitrary claim callback cannot dispatch or reuse an opaque token',async()=>{
  const token=await verify(await sign(inbound())),w=await work();let called=false;
  await assert.rejects(claimSyntheticSmsIngress(token,w,async()=>{called=true;return true;}),/sms_ingress_unconfigured/);assert.equal(called,false);
  await assert.rejects(claimSyntheticSmsIngress(token,w,async()=>true),/sms_ingress_denied/);await w.finish();
 });
 await t.test('witness expiry, body limits and request cancellation fail closed',async()=>{
  const signed=await sign(inbound());now+=30001;await assert.rejects(verify(signed),/sms_ingress_denied/);now-=30001;
  await assert.rejects(sign(inbound(undefined,{},'x'.repeat(262145))),/sms_ingress_body_refused/);
  await assert.rejects(sign(inbound(undefined,{'content-length':'1'},'longer')),/sms_ingress_body_refused/);
  const ctl=new AbortController(),stream=new ReadableStream({pull(){return new Promise(()=>{});}}),req=new Request(profile.member_api_origin+'/collect-sms/v1/messages',{method:'POST',body:stream,duplex:'half',signal:ctl.signal});
  const pending=sign(req);setTimeout(()=>ctl.abort(),30);await assert.rejects(pending,/sms_ingress_body_refused|sms_ingress_cancelled/);
 });
 await t.test('production profiles, absent proof and shared keys cannot enable fixture protocol',async()=>{
  const p={...profile,environment:'production'},r=canonicalProfile(p);
  await assert.rejects(createSyntheticSmsSigner({...settings,APP_ENVIRONMENT:'production',COLLECT_DEPLOYMENT_PROFILE:r,COLLECT_DEPLOYMENT_PROFILE_SHA256:hash(r)},{clock}),/sms_ingress_unconfigured/);
  await assert.rejects(createSyntheticSmsSigner({...settings,COLLECT_SMS_INGRESS_PROOF_SHA256:'0'.repeat(64)},{clock}),/sms_ingress_unconfigured/);
  await assert.rejects(createSyntheticSmsSigner({...settings,COLLECT_NATIVE_INGRESS_KEY_BASE64:settings.COLLECT_SMS_INGRESS_KEY_BASE64},{clock}),/sms_ingress_unconfigured/);
  assert.equal(managedSmsGatewayUnavailable().status,503);
 });
});
