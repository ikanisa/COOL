import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {registerHooks} from 'node:module';
import {canonicalProfile,MANAGED_SUPABASE_ORIGIN} from '../../supabase/functions/_shared/deployment-profile.js';
import {admitNativeIngress,verifyNativeIngress,claimNativeIngress,MANAGED_PROOF,MANAGED_WORKER_GUARD,NATIVE_INGRESS_HEADER} from '../../supabase/functions/_shared/native-ingress.js';
import {profile as nativeProfile,defs} from '../../supabase/functions/_shared/domain/burimunsi/wire/burimunsi.generated.mjs';
import {validateSchema} from '../../supabase/functions/_shared/domain/burimunsi/wire/runtime.mjs';
import {canonicalManagedClientAddress,createManagedNativeFrontdoor,managedNativeFrontdoorUnavailable} from './worker.js';

// Synthetic provider/profile/keys only. These tests do not establish the real
// Cloudflare route, header provenance, managed Edge behavior or live devices.
const now=1900000000000;
const profile={format:'collect.deployment.v1',id:'managed-ingress-fixture',mode:'managed',environment:'qualification',
 supabase_origin:MANAGED_SUPABASE_ORIGIN,member_api_origin:'https://api.collect.example',
 admin_origin:'https://admin.collect.example',public_origin:'https://collect.example',google_callback_origin:'https://admin.collect.example'};
const canonical=value=>JSON.stringify(Object.fromEntries(Object.keys(value).sort().map(k=>[k,value[k]])));
const sha=value=>createHash('sha256').update(value).digest('hex');
const key=byte=>Buffer.alloc(32,byte).toString('base64');
function environment(proofOverrides={},envOverrides={}){
 const raw=canonicalProfile(profile),digest=sha(raw);
 const proof=canonical({format:MANAGED_PROOF,status:'reviewed',frontdoorOrigin:profile.member_api_origin,
  networkSource:'cf-connecting-ip',workerGuard:MANAGED_WORKER_GUARD,pseudoIpv4:'off',
  profileSha256:digest,supabaseOrigin:profile.supabase_origin,reviewedAt:now-10000,
  evidenceSha256:'c'.repeat(64),...proofOverrides});
 return {COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:digest,APP_ENVIRONMENT:'qualification',
  SUPABASE_URL:profile.supabase_origin,BURIMUNSI_NATIVE_ENABLED:'true',
  COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON:proof,COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256:sha(proof),
  COLLECT_NATIVE_INGRESS_KEY_ID:'managed-ingress-fixture',COLLECT_NATIVE_INGRESS_KEY_BASE64:key(5),
  DATA_ENCRYPTION_KEY:key(1),SESSION_ENCRYPTION_KEY:key(2),BURIMUNSI_PIN_PEPPER_BASE64:key(3),BURIMUNSI_CURSOR_KEY_BASE64:key(4),...envOverrides};
}
function request({url=profile.member_api_origin+'/functions/v1/collect-api/v1/burimunsi/session/login?foo=1',
 body='{"phone":"+250788123456","pin":"0123"}',headers={},method='POST'}={}){
 return new Request(url,{method,headers:{'content-type':'application/json','cf-connecting-ip':'192.0.2.1',
  'x-burimunsi-installation':'fixture-installation','x-burimunsi-device':'a'.repeat(64),...headers},
  body:method==='GET'?undefined:body});
}
async function admitted(upstream,env){
 const url=new URL(upstream.url);url.pathname=url.pathname.slice('/functions/v1/collect-api'.length);
 const token=await verifyNativeIngress(new Request(url,{method:upstream.method,headers:upstream.headers,
  body:upstream.method==='GET'?undefined:await upstream.arrayBuffer()}),env,{clock:()=>now});
 // This in-memory callback is a synthetic stand-in, not a durable store.
 return claimNativeIngress(token,()=>true);
}

test('managed frontdoor signs the exact request and only the protected backend resolver gets the network bucket',async()=>{
 const env=environment();let count=0,network;
 const frontdoor=await createManagedNativeFrontdoor(env,{clock:()=>now,fetchImpl:async upstream=>{
  count++;assert.equal(upstream.url,profile.supabase_origin+'/functions/v1/collect-api/v1/burimunsi/session/login?foo=1');
  assert.equal(upstream.redirect,'manual');assert.equal(upstream.headers.get('cf-connecting-ip'),null);
  assert.equal(upstream.headers.get('x-forwarded-for'),null);assert.equal(upstream.headers.get('accept-encoding'),'identity');
  const accepted=await admitted(upstream,env);assert.equal(await accepted.request.text(),'{"phone":"+250788123456","pin":"0123"}');
  network=await accepted.networkBucket(accepted.request);assert.match(network,/^[a-f0-9]{64}$/);
  assert.equal(accepted.request.headers.has(NATIVE_INGRESS_HEADER),false);
  return Response.json({ok:true,data:{}},{headers:{'X-BuriMunsi-Contract':'fixture',
   'X-Collect-Native-Ingress':'do-not-return','Set-Cookie':'not-a-native-cookie=1'}});
 }});
 const output=await frontdoor(request({headers:{'x-forwarded-for':'198.51.100.1',
  'x-collect-native-ingress':'untrusted','x-collect-actor':'forged'}}));
 assert.equal(output.status,200);assert.equal(count,1);assert.equal(output.headers.get('x-burimunsi-contract'),'fixture');
 assert.equal(output.headers.get('x-collect-native-ingress'),null);assert.equal(output.headers.get('set-cookie'),null);
 assert.match(output.headers.get('cache-control'),/no-store/);assert(!JSON.stringify(await output.json()).includes(network));
});
test('a direct managed backend request or an altered signed request cannot manufacture a network witness',async()=>{
 const env=environment();
 await assert.rejects(admitNativeIngress(new Request(profile.supabase_origin+'/v1/burimunsi/session/login',{
  method:'POST',headers:{'content-type':'application/json','cf-connecting-ip':'192.0.2.1'},body:'{}'}),env,{clock:()=>now}),
  error=>error.code==='native_ingress_denied');
 const frontdoor=await createManagedNativeFrontdoor(env,{clock:()=>now,fetchImpl:async upstream=>{
  const url=new URL(upstream.url);url.pathname='/v1/burimunsi/session/login';url.search='?foo=2';
  await assert.rejects(admitNativeIngress(new Request(url,{method:'POST',headers:upstream.headers,body:'{}'}),env,{clock:()=>now}),
   error=>error.code==='native_ingress_denied');
  return Response.json({ok:true,data:{}});
 }});
 assert.equal((await frontdoor(request())).status,200);
});
test('the existing managed handler remains closed until it can claim a durable nonce',async()=>{
 const env=environment();let dispatches=0;
 const frontdoor=await createManagedNativeFrontdoor(env,{clock:()=>now,fetchImpl:async upstream=>{
  dispatches++;const url=new URL(upstream.url);url.pathname=url.pathname.slice('/functions/v1/collect-api'.length);
  const logical=new Request(url,{method:upstream.method,headers:upstream.headers,body:await upstream.arrayBuffer()});
  await assert.rejects(admitNativeIngress(logical,env,{clock:()=>now}),
   e=>e.code==='native_ingress_replay_unconfigured'&&e.status===503);
  return Response.json({code:'backend_unavailable'},{status:503});
 }});
 assert.equal((await frontdoor(request())).status,503);assert.equal(dispatches,1);
});
test('the real managed handler stops a signed request at ingress before database or provider setup',async()=>{
 const hooks=registerHooks({resolve(specifier,context,next){
  if(specifier==='npm:postgres@3.4.7')return {url:'data:text/javascript,export default function(){throw Error("unexpected DB operation")}',shortCircuit:true};
  if(specifier==='npm:nodemailer@10.1.7')return {url:'data:text/javascript,export function createTransport(){throw Error("unexpected SMTP operation")}',shortCircuit:true};
  return next(specifier,context);
 }});
 try{
  const {createHandler}=await import('../../supabase/functions/_shared/serve.js'),env=environment();let stage,work=0;
  const handler=createHandler('collect-api',()=>env,{reportHealth:value=>{stage=value.runtimeFailure?.stage;},
   admitNativeIngress:(input,config)=>admitNativeIngress(input,config,{clock:()=>now}),openWork:()=>{work++;throw Error('unexpected fence');}});
  const frontdoor=await createManagedNativeFrontdoor(env,{clock:()=>now,fetchImpl:input=>handler(input)});
  assert.equal((await frontdoor(request())).status,503);assert.equal(stage,'native_ingress');assert.equal(work,0);
  stage=undefined;
  const direct=new Request(profile.supabase_origin+'/functions/v1/collect-api/v1/burimunsi/session/login',
   {method:'POST',headers:{'content-type':'application/json','cf-connecting-ip':'192.0.2.1'},body:'{}'});
  assert.equal((await handler(direct)).status,503);assert.equal(stage,'native_ingress');assert.equal(work,0);
 }finally{hooks.deregister();}
});
test('a repeated managed attestation cannot dispatch twice through an atomic claim interface',async()=>{
 const env=environment(),seen=new Set();let effects=0,claims=0;
 const frontdoor=await createManagedNativeFrontdoor(env,{clock:()=>now,fetchImpl:async upstream=>{
  const copy=upstream.clone(),makeLogical=async value=>{const url=new URL(value.url);url.pathname=url.pathname.slice('/functions/v1/collect-api'.length);
   return new Request(url,{method:value.method,headers:value.headers,body:await value.arrayBuffer()});};
  const first=await verifyNativeIngress(await makeLogical(upstream),env,{clock:()=>now});
  const duplicate=await verifyNativeIngress(await makeLogical(copy),env,{clock:()=>now});
  const consume=async ({nonce})=>{claims++;if(seen.has(nonce))return false;seen.add(nonce);return true;};
  const accepted=await claimNativeIngress(first,consume);effects++;assert.match(await accepted.networkBucket(accepted.request),/^[a-f0-9]{64}$/);
  await assert.rejects(claimNativeIngress(duplicate,consume),e=>e.code==='native_ingress_denied');
  return Response.json({ok:true,data:{}});
 }});
 assert.equal((await frontdoor(request())).status,200);assert.equal(claims,2);assert.equal(effects,1);
});
test('managed authority, idempotency and request headers are bound before nonce storage',async()=>{
 const env=environment();let claims=0;
 const frontdoor=await createManagedNativeFrontdoor(env,{clock:()=>now,fetchImpl:async upstream=>{
  for(const name of ['authorization','cookie','origin','idempotency-key','x-request-id','x-collect-admin','x-burimunsi-group']){
   const copy=upstream.clone(),url=new URL(copy.url),headers=new Headers(copy.headers);url.pathname=url.pathname.slice('/functions/v1/collect-api'.length);
   headers.set(name,'synthetic-altered-value');const body=await copy.arrayBuffer();
   await assert.rejects((async()=>{const token=await verifyNativeIngress(new Request(url,{method:'POST',headers,body}),env,{clock:()=>now});
    await claimNativeIngress(token,()=>{claims++;return true;});})(),e=>e.code==='native_ingress_denied');
  }
  return Response.json({ok:true,data:{}});
 }});
 assert.equal((await frontdoor(request())).status,200);assert.equal(claims,0);
});
test('the managed frontdoor forwards only the exact large preview route and rejects nearby routes before dispatch',async()=>{
 const env=environment();let calls=0;
 const frontdoor=await createManagedNativeFrontdoor(env,{clock:()=>now,fetchImpl:async upstream=>{
  calls++;const accepted=await admitted(upstream,env);assert.equal((await accepted.request.arrayBuffer()).byteLength,8193);
  return Response.json({ok:true,data:{}});
 }});
 const prefix=profile.member_api_origin+'/functions/v1/collect-api/v1/burimunsi';
 assert.equal((await frontdoor(request({url:prefix+'/members/import/preview',body:'x'.repeat(8193)}))).status,200);
 for(const [path,method] of [['/members/import/preview?x=1','POST'],['/members/import-extra','POST'],['/members/import','PATCH']])
  assert.equal((await frontdoor(request({url:prefix+path,method,body:'x'.repeat(8193)}))).status,413);
 assert.equal(calls,1);
});
test('Worker subrequests, missing or invalid peer addresses, and other routes are refused before fetch',async()=>{
 let calls=0;const frontdoor=await createManagedNativeFrontdoor(environment(),{clock:()=>now,fetchImpl:()=>{calls++;throw Error();}});
 const bad=[request({headers:{'cf-worker':'foreign.example'}}),request({headers:{'cf-connecting-ip':''}}),
  request({headers:{'cf-connecting-ip':'2a06:98c0:3600::103'}}),
  request({url:profile.supabase_origin+'/functions/v1/collect-api/v1/burimunsi/session/login'}),
  request({url:profile.member_api_origin+'/functions/v1/admin-api/api/admin/session'}),
  request({url:profile.member_api_origin+'/functions/v1/collect-api/v1/%62urimunsi/session/login'}),
  request({method:'DELETE'})];
 for(const item of bad){const result=await frontdoor(item);assert(result.status>=400);assert.equal(item.bodyUsed,false);}
 assert.equal(calls,0);
});
test('frontdoor refusals use the actual native error contract without fabricating success response markers',async()=>{
 const frontdoor=await createManagedNativeFrontdoor(environment(),{clock:()=>now,
  fetchImpl:async()=>Response.json({ok:true,data:{}})});
 for(const denied of [request({headers:{'cf-worker':'foreign.example'}}),
  request({headers:{'cf-connecting-ip':''}}),request({method:'DELETE'}),
  request({url:profile.member_api_origin+'/not-a-native-route'})]){
  const response=await frontdoor(denied),value=await response.json();
  assert.equal(response.headers.get('x-burimunsi-contract'),nativeProfile.contractVersion);
  assert.equal(value.contractVersion,nativeProfile.contractVersion);validateSchema(defs,'error',value);
 }
 const success=await frontdoor(request());
 assert.equal(success.status,200);assert.equal(success.headers.get('x-burimunsi-contract'),null);
 const unavailable=managedNativeFrontdoorUnavailable();assert.equal(unavailable.status,503);
 validateSchema(defs,'error',await unavailable.json());
});
test('client address normalization is deterministic and does not accept forwarded lists or pseudo Worker IPs',()=>{
 assert.equal(canonicalManagedClientAddress('192.0.2.1'),'192.0.2.1');
 assert.equal(canonicalManagedClientAddress('::ffff:192.0.2.1'),'192.0.2.1');
 assert.equal(canonicalManagedClientAddress('2001:0DB8::1'),'2001:db8::1');
 for(const input of ['',null,'01.2.3.4','192.0.2.256','192.0.2.1,198.51.100.1','[::1]',
  '2a06:98c0:3600::103','localhost'])assert.throws(()=>canonicalManagedClientAddress(input));
});
test('forwarded IP headers cannot change the signed network bucket selected from Cloudflare',async()=>{
 const env=environment(),buckets=[];
 const frontdoor=await createManagedNativeFrontdoor(env,{clock:()=>now,fetchImpl:async upstream=>{
  const witness=await admitted(upstream,env);buckets.push(await witness.networkBucket(witness.request));
  return Response.json({ok:true,data:{}});
 }});
 for(const headers of [
  {'cf-connecting-ip':'192.0.2.1','x-real-ip':'198.51.100.1','x-forwarded-for':'198.51.100.1'},
  {'cf-connecting-ip':'192.0.2.1','x-real-ip':'198.51.100.2','x-forwarded-for':'198.51.100.2'},
  {'cf-connecting-ip':'192.0.2.2','x-real-ip':'198.51.100.1','x-forwarded-for':'198.51.100.1'},
 ])assert.equal((await frontdoor(request({headers}))).status,200);
 assert.equal(buckets[0],buckets[1]);assert.notEqual(buckets[0],buckets[2]);
});
test('managed admission requires its own reviewed exact profile, frontdoor, guard, and separate key',async()=>{
 for(const proof of [{status:'observed'},{frontdoorOrigin:'https://other.example'},{networkSource:'x-forwarded-for'},
  {workerGuard:'disabled'},{pseudoIpv4:'overwrite'},{profileSha256:'0'.repeat(64)},
  {supabaseOrigin:'https://other.example'},{format:'collect.native-ingress.edge-proof.v2'},{reviewedAt:now+1}])
  await assert.rejects(createManagedNativeFrontdoor(environment(proof),{clock:()=>now}));
 for(const change of [{COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON:''},{COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256:'0'.repeat(64)},
  {COLLECT_NATIVE_INGRESS_KEY_BASE64:key(1)},{SUPABASE_URL:'https://other.example'},{BURIMUNSI_NATIVE_ENABLED:'false'}])
  await assert.rejects(createManagedNativeFrontdoor(environment({},change),{clock:()=>now}));
});
test('redirects, unqualified responses and uncertain fetch outcomes never trigger a retry',async()=>{
 const responses=[()=>Response.redirect('https://other.example',302),()=>new Response('<html>bad</html>',{headers:{'content-type':'text/html'}}),
  ()=>new Response('x',{headers:{'content-type':'application/json','content-length':'2000001'}}),()=>{throw Error('network');}];
 for(const make of responses){let calls=0;const frontdoor=await createManagedNativeFrontdoor(environment(),{clock:()=>now,fetchImpl:()=>{calls++;return make();}});
  const output=await frontdoor(request());assert.equal(output.status,503);assert.equal(calls,1);}
});
test('oversized native requests and oversized streamed responses cannot pass through the frontdoor',async()=>{
 let calls=0;const frontdoor=await createManagedNativeFrontdoor(environment(),{clock:()=>now,fetchImpl:()=>{
  calls++;return new Response(new ReadableStream({start(controller){
   controller.enqueue(new Uint8Array(2000001));controller.close();
  }}),{headers:{'content-type':'application/json'}});
 }});
 const oversized=await frontdoor(request({body:'x'.repeat(8193)}));
 assert.equal(oversized.status,413);validateSchema(defs,'error',await oversized.json());assert.equal(calls,0);
 assert.equal((await frontdoor(request())).status,503);assert.equal(calls,1);
});
test('a size error after upstream dispatch remains an uncertain 503, never a definite 413',async()=>{
 let calls=0;const frontdoor=await createManagedNativeFrontdoor(environment(),{clock:()=>now,fetchImpl:()=>{
  calls++;const error=Error('synthetic');error.code='CONTRACT_REQUEST_SIZE';throw error;
 }});
 const response=await frontdoor(request());assert.equal(response.status,503);assert.equal(calls,1);
 const value=await response.json();validateSchema(defs,'error',value);assert.equal(value.error.code,'backend_unavailable');
});
