import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
import {openApplicationWork} from '../../../supabase/functions/_shared/application-fence.js';
import {createSyntheticSmsSigner,createSyntheticSmsVerifier,claimSyntheticSmsIngress,managedSmsGatewayUnavailable} from './synthetic-ingress.mjs';
import {consumeSyntheticSmsNonce} from './synthetic-nonce-adapter.mjs';
const hash=x=>createHash('sha256').update(x).digest('hex'),key=b=>Buffer.alloc(32,b).toString('base64');
const profile={format:'collect.deployment.v1',id:'sms-fixture',mode:'managed',environment:'qualification',supabase_origin:'https://rrlduytparvsjfmegalh.supabase.co',member_api_origin:'https://sms.example.invalid',admin_origin:'https://admin.example.invalid',public_origin:'https://public.example.invalid',google_callback_origin:'https://admin.example.invalid'};
const raw=canonicalProfile(profile),profileHash=hash(raw);let now=1800000000000;
const proof={evidenceSha256:'e'.repeat(64),format:'collect.sms-ingress.fixture-proof.v1',frontdoorOrigin:profile.member_api_origin,profileSha256:profileHash,reviewedAt:now-1000,status:'synthetic',supabaseOrigin:profile.supabase_origin,workerGuard:'synthetic_cf_worker_reject'};
const canon=x=>JSON.stringify(Object.fromEntries(Object.keys(x).sort().map(k=>[k,x[k]])));
const settings={COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:profileHash,SUPABASE_URL:profile.supabase_origin,APP_ENVIRONMENT:'qualification',COLLECT_SMS_ENABLED:'true',COLLECT_SMS_INGRESS_PROOF_JSON:canon(proof),COLLECT_SMS_INGRESS_PROOF_SHA256:hash(canon(proof)),COLLECT_SMS_INGRESS_KEY_ID:'sms-fixture',COLLECT_SMS_INGRESS_KEY_BASE64:key(7),COLLECT_NATIVE_INGRESS_KEY_BASE64:key(8)};
const clock=()=>now;
const source='a'.repeat(64);
async function work(){let row;const events=[];const backend={register:async(id,sha,kind)=>(row={contractVersion:1,admissionId:id,sourceSha256:sha,epoch:1,state:'active',mode:'open',kind}),
 lease:async()=>({row,assert:async()=>row,release:async()=>events.push('released')}),close:async(_id,_epoch,_sha,state,reason,externalDispatches,uncertainDispatches)=>({...row,state,reason,externalDispatches,uncertainDispatches}),status:async()=>({...row,found:true})};
 return {work:await openApplicationWork({backend,sourceSha256:source,kind:'http_collect'}),events};}
const inbound=(path='/functions/v1/collect-sms/v1/messages',headers={},body='{"message_id":"synthetic"}')=>new Request(profile.member_api_origin+path,{method:'POST',headers:{authorization:'Bearer synthetic-device-secret','idempotency-key':'synthetic-key','content-type':'application/json',...headers},body});

test('synthetic SMS ingress binds the complete request without granting device authority',{timeout:20000},async t=>{
 const sign=await createSyntheticSmsSigner(settings,{clock}),verify=await createSyntheticSmsVerifier(settings,{clock});
 await t.test('preserves application bearer, body, query and encoded message IDs through a committed claim',async()=>{
  const original=inbound('/functions/v1/collect-sms/v1/messages/a%3Ab?x=1',{'x-forwarded-host':'evil.invalid','x-collect-sms-ingress':'forged'});
  const signed=await sign(original),token=await verify(signed),{work:w}=await work();let claims=0;
  const output=await claimSyntheticSmsIngress(token,w,async()=>{claims++;return true;});
  assert.equal(claims,1);assert.equal(output.url,profile.supabase_origin+'/v1/messages/a%3Ab?x=1');
  assert.equal(output.headers.get('authorization'),'Bearer synthetic-device-secret');assert.equal(output.headers.get('idempotency-key'),'synthetic-key');
  assert.equal(output.headers.has('x-collect-sms-ingress'),false);assert.equal(output.headers.has('x-forwarded-host'),false);assert.equal(await output.text(),'{"message_id":"synthetic"}');
  assert.equal((await w.finish()).state,'settled');
 });
 await t.test('direct, wrong-origin, similarly named, unqualified Worker and encoded separators refuse before admission',async()=>{
  await assert.rejects(verify(new Request(profile.supabase_origin+'/functions/v1/collect-sms/v1/messages',{method:'POST',body:'{}'})),/sms_ingress_denied/);
  for(const path of ['/functions/v1/collect-sms-other/v1/messages','/functions/v1/collect-sms/v1/messages/a%2Fb'])await assert.rejects(sign(inbound(path)),/sms_ingress_denied/);
  await assert.rejects(sign(new Request('https://evil.example.invalid/functions/v1/collect-sms/health')),/sms_ingress_denied/);
  await assert.rejects(sign(inbound(undefined,{'cf-worker':'example.invalid'})),/sms_ingress_network_denied/);
 });
 await t.test('body, bearer, idempotency key, origin, method and query tampering fail verification',async()=>{
  const x=await sign(inbound());const body=await x.text();
  const variants=[{body:'{}'},{authorization:'Bearer replacement'},{'idempotency-key':'replacement'},{origin:'https://evil.invalid'},{method:'GET'},{query:'?changed=1'}];
  for(const v of variants){const h=new Headers(x.headers);for(const k of ['authorization','idempotency-key','origin'])if(v[k])h.set(k,v[k]);
   const method=v.method??'POST',url=x.url+(v.query??'');const req=new Request(url,{method,headers:h,body:method==='GET'?undefined:v.body??body});
   await assert.rejects(verify(req),/sms_ingress_denied/);
  }
 });
 await t.test('witness expiry, duplicate nonce and in-memory token reuse fail closed',async()=>{
  const signed=await sign(inbound()),one=await verify(signed.clone()),two=await verify(signed.clone()),seen=new Set();
  const a=await work();await claimSyntheticSmsIngress(one,a.work,async v=>{if(seen.has(v.nonce))return false;seen.add(v.nonce);return true;});
  await assert.rejects(claimSyntheticSmsIngress(one,a.work,async()=>true),/sms_ingress_denied/);await a.work.finish();
  const b=await work();await assert.rejects(claimSyntheticSmsIngress(two,b.work,async v=>!seen.has(v.nonce)),/sms_ingress_denied/);await b.work.finish();
  now+=30001;await assert.rejects(verify(signed.clone()),/sms_ingress_denied/);now-=30001;
 });
 await t.test('late or failed nonce acknowledgement leaves work unresolved and never releases the request',async()=>{
  const token=await verify(await sign(inbound())),{work:w}=await work();let release;const pending=new Promise(r=>{release=r;});
  await assert.rejects(claimSyntheticSmsIngress(token,w,()=>pending,{timeoutMs:30}),/sms_ingress_claim_unconfirmed/);
  let finished=false;const result=w.finish().then(x=>{finished=true;return x;});await new Promise(r=>setTimeout(r,30));assert.equal(finished,false);
  release(true);const state=await result;assert.equal(state.state,'unresolved');assert.equal(state.reason,'work_lost');
 });
 await t.test('nonce adapter binds only its fixed SMS function and marks a failed commit unresolved',async()=>{
  const token=await verify(await sign(inbound())),{work:w}=await work();let query,values;
  const db={prepare(q){query=q;return {bind(...v){values=v;return {async first(column){assert.equal(column,'claimed');return true;}};}};}};
  await claimSyntheticSmsIngress(token,w,v=>consumeSyntheticSmsNonce(db,w,v));
  assert.equal(query,'SELECT collect_sms.consume_ingress_nonce(?::uuid,?::text,?::text,?::bigint) AS claimed');
  assert.equal(values.length,4);assert.equal(values[1],profileHash);assert.equal(values[2],hash(canon(proof)));await w.finish();
  const next=await verify(await sign(inbound())),bad=await work();
  const failed={prepare(){return {bind(){return {async first(){throw Error('synthetic-lost-commit');}};}};}};
  await assert.rejects(claimSyntheticSmsIngress(next,bad.work,v=>consumeSyntheticSmsNonce(failed,bad.work,v)),/sms_ingress_claim_unconfirmed/);
  const state=await bad.work.finish();assert.equal(state.state,'unresolved');assert.equal(state.reason,'work_lost');
 });
 await t.test('cancellation after verification cannot consume a nonce',async()=>{
  const ctl=new AbortController(),req=new Request(profile.member_api_origin+'/collect-sms/v1/messages',{method:'POST',body:'{}',signal:ctl.signal});
  const token=await verify(await sign(req)),{work:w}=await work();ctl.abort();let called=false;
  await assert.rejects(claimSyntheticSmsIngress(token,w,async()=>{called=true;return true;}),/sms_ingress_cancelled/);assert.equal(called,false);await w.finish();
 });
 await t.test('request body limits and cancellation fail closed',async()=>{
  await assert.rejects(sign(inbound(undefined,{},'x'.repeat(262145))),/sms_ingress_body_refused/);
  await assert.rejects(sign(inbound(undefined,{'content-length':'1'},'longer')),/sms_ingress_body_refused/);
  const ctl=new AbortController(),stream=new ReadableStream({pull(){return new Promise(()=>{});}}),request=new Request(profile.member_api_origin+'/collect-sms/v1/messages',{method:'POST',body:stream,duplex:'half',signal:ctl.signal});
  const pending=sign(request);setTimeout(()=>ctl.abort(),30);await assert.rejects(pending,/sms_ingress_body_refused|sms_ingress_cancelled/);
 });
 await t.test('production profiles, absent proof and shared keys cannot enable fixture protocol',async()=>{
  const p={...profile,environment:'production'},r=canonicalProfile(p);
  await assert.rejects(createSyntheticSmsSigner({...settings,APP_ENVIRONMENT:'production',COLLECT_DEPLOYMENT_PROFILE:r,COLLECT_DEPLOYMENT_PROFILE_SHA256:hash(r)},{clock}),/sms_ingress_unconfigured/);
  await assert.rejects(createSyntheticSmsSigner({...settings,COLLECT_SMS_INGRESS_PROOF_SHA256:'0'.repeat(64)},{clock}),/sms_ingress_unconfigured/);
  await assert.rejects(createSyntheticSmsSigner({...settings,COLLECT_NATIVE_INGRESS_KEY_BASE64:settings.COLLECT_SMS_INGRESS_KEY_BASE64},{clock}),/sms_ingress_unconfigured/);
  assert.equal(managedSmsGatewayUnavailable().status,503);
 });
});
