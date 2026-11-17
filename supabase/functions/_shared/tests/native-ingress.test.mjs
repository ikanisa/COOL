import test from 'node:test';
import assert from 'node:assert/strict';
import {registerHooks} from 'node:module';
import {createNativeIngressSigner,NATIVE_INGRESS_HEADER} from '../native-ingress.js';
import {admitNativeIngress,environment,now,key,request,signed,canonical,sha,profile} from './native-ingress-fixture.mjs';
const denied=error=>error?.code==='native_ingress_denied';

test('signed actual body/authority is admitted once and resolver survives body consumption without reading it',async()=>{
 const env=environment(),input=await signed(env),body=await input.clone().text();
 const admitted=await admitNativeIngress(input,env,{clock:()=>now});
 assert.equal(admitted.request.headers.has(NATIVE_INGRESS_HEADER),false);assert.equal(await admitted.request.text(),body);
 const network=await admitted.networkBucket(admitted.request);assert.match(network,/^[a-f0-9]{64}$/);
 await assert.rejects(admitted.networkBucket(new Request(admitted.request.url,{headers:input.headers})),denied);
 assert.equal(await admitted.networkBucket(admitted.request),network);
});
test('native PATCH edits retain their exact method, JSON bytes and phone-PIN authority through attestation',async()=>{
 const env=environment(),body='{"id":"fixture-staff","name":"Updated operator"}';
 const input=await signed(env,{path:'/functions/v1/collect-api/v1/burimunsi/staff',method:'PATCH',body,
  headers:{'x-burimunsi-auth':'phone_pin','x-burimunsi-profile':'internal_receiver'}});
 const admitted=await admitNativeIngress(input,env,{clock:()=>now});
 assert.equal(admitted.request.method,'PATCH');assert.equal(await admitted.request.text(),body);
 assert.match(await admitted.networkBucket(admitted.request),/^[a-f0-9]{64}$/);
 for(const change of ['method','body','profile']){
  const fresh=await signed(env,{path:'/functions/v1/collect-api/v1/burimunsi/staff',method:'PATCH',body,
   headers:{'x-burimunsi-auth':'phone_pin','x-burimunsi-profile':'internal_receiver'}});
  const headers=new Headers(fresh.headers);if(change==='profile')headers.set('x-burimunsi-profile','staff');
  await assert.rejects(admitNativeIngress(new Request(fresh.url,{method:change==='method'?'POST':'PATCH',headers,
   body:change==='body'?body.replace('Updated','Forged'):body}),env,{clock:()=>now}),denied);
 }
});
test('network buckets are stable for same address and distinct for other addresses and key purposes',async()=>{
 const env=environment(),signer=await createNativeIngressSigner(env,{clock:()=>now});
 const decode=input=>JSON.parse(Buffer.from(input.headers.get(NATIVE_INGRESS_HEADER),'base64url'));
 const a=decode(await signer(request(),'192.0.2.1')),b=decode(await signer(request(),'192.0.2.1')),c=decode(await signer(request(),'192.0.2.2'));
 assert.equal(a[6],b[6]);assert.notEqual(a[5],b[5]);assert.notEqual(a[6],c[6]);
 assert(!JSON.stringify(a).includes('192.0.2.1'));assert.notEqual(a[6],a[9]);
});
for(const change of ['path','query','method','body','authority','installation','signature'])test('tampered '+change+' cannot borrow another request network identity',async()=>{
 const env=environment(),input=await signed(env),url=new URL(input.url),headers=new Headers(input.headers);let method=input.method,body=await input.text();
 if(change==='path')url.pathname='/v1/burimunsi/session/passcode';
 if(change==='query')url.search='?q=altered';
 if(change==='method'){method='GET';body=undefined;}
 if(change==='body')body=body.replace('0123','9999');
 if(change==='authority')headers.set('x-burimunsi-collect-session','another-managed-session');
 if(change==='installation')headers.set('x-burimunsi-installation','another-installation');
 if(change==='signature'){const parts=JSON.parse(Buffer.from(headers.get(NATIVE_INGRESS_HEADER),'base64url'));parts[9]='0'.repeat(64);headers.set(NATIVE_INGRESS_HEADER,Buffer.from(JSON.stringify(parts)).toString('base64url'));}
 await assert.rejects(admitNativeIngress(new Request(url,{method,headers,body}),env,{clock:()=>now}),denied);
});
test('missing/duplicate/oversized/noncanonical envelopes are rejected before consuming body',async()=>{
 for(const value of [null,'forged','a'.repeat(2049),'one,two']){
  let reads=0;const headers=new Headers({'content-type':'application/json'});if(value!==null)headers.set(NATIVE_INGRESS_HEADER,value);
  const body=new ReadableStream({pull(){reads++;throw Error('must not read rejected body');}});
  const input=new Request(profile.supabase_origin+'/v1/burimunsi/session/login',{method:'POST',headers,body,duplex:'half'});
  // Streams may eagerly pull once at construction; admission adds no pull.
  await Promise.resolve();const before=reads;
  await assert.rejects(admitNativeIngress(input,environment(),{clock:()=>now}),denied);assert.equal(reads,before);
 }
});
test('request attestations expire, cannot be future-dated, and are not valid after admission delay',async()=>{
 for(const time of [now+30001,now-2001])await assert.rejects(admitNativeIngress(await signed(),environment(),{clock:()=>time}),denied);
 let time=now;const admitted=await admitNativeIngress(await signed(),environment(),{clock:()=>time});time+=30001;
 await assert.rejects(admitted.networkBucket(admitted.request),denied);
});
for(const change of [
 {status:'observed'}, {workerGuard:'allow all'}, {frontdoorOrigin:'https://unapproved.example'},
 {networkSource:'x-forwarded-for'}, {pseudoIpv4:'overwrite'}, {profileSha256:'d'.repeat(64)},
 {supabaseOrigin:'https://another.example'}, {evidenceSha256:''}, {reviewedAt:now+1},
 {format:'collect.native-ingress.edge-proof.v1'},
])test('uncertified managed edge configuration fails closed '+Object.keys(change)[0],async()=>{
 await assert.rejects(createNativeIngressSigner(environment({},change),{clock:()=>now}),error=>error.code==='native_ingress_edge_unqualified');
});
test('managed review record is not an expiring credential; each request still expires',async()=>{
 const env=environment({}, {reviewedAt:now-366*86400000}),record=JSON.parse(env.COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON);
 assert.equal(record.workerGuard,'cloudflare_worker_presence_reject');
 let time=now;const signer=await createNativeIngressSigner(env,{clock:()=>time});time+=8*86400000;
 const output=await signer(request(),'192.0.2.1'),url=new URL(output.url);url.pathname=url.pathname.slice('/functions/v1/collect-api'.length);
 const admitted=await admitNativeIngress(new Request(url,{method:'POST',headers:output.headers,body:await output.arrayBuffer()}),env,{clock:()=>time});
 assert.match(await admitted.networkBucket(admitted.request),/^[a-f0-9]{64}$/);
 time+=30001;await assert.rejects(admitted.networkBucket(admitted.request),denied);
});
test('signer rejects any CF-Worker marker before body consumption and never endorses changed Worker client IP',async()=>{
 const signer=await createNativeIngressSigner(environment(),{clock:()=>now});
 for(const marker of ['', 'ikanisa.com', 'foreign.example']){
  const input=request({headers:{'CF-Worker':marker,'X-Real-IP':'198.51.100.99','CF-Connecting-IP':'198.51.100.99'}});
  await assert.rejects(signer(input,'198.51.100.99'),error=>error.code==='native_ingress_network_denied'&&error.status===403);
  assert.equal(input.bodyUsed,false);assert.equal(input.headers.has(NATIVE_INGRESS_HEADER),false);
 }
});
test('proof duplicate keys, changed digest, missing proof and noncanonical record are rejected',async()=>{
 const env=environment();
 for(const change of [
  {COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON:''}, {COLLECT_NATIVE_INGRESS_EDGE_PROOF_SHA256:'0'.repeat(64)},
  {COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON:env.COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON+' '},
  {COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON:env.COLLECT_NATIVE_INGRESS_EDGE_PROOF_JSON.replace('"status":"reviewed"','"status":"observed","status":"reviewed"')},
 ])await assert.rejects(createNativeIngressSigner({...env,...change},{clock:()=>now}));
});
test('ingress key is canonical32-byte and cannot reuse current/prior DATA/BFF/native secrets',async()=>{
 const env=environment();
 for(const value of ['',key(5).slice(0,-1),key(1),key(2),key(3),key(4)])await assert.rejects(createNativeIngressSigner({...env,COLLECT_NATIVE_INGRESS_KEY_BASE64:value},{clock:()=>now}));
 for(const ring of ['DATA_DECRYPTION_KEYS_JSON','SESSION_DECRYPTION_KEYS_JSON'])await assert.rejects(createNativeIngressSigner({...env,[ring]:canonical({prior:key(5)})},{clock:()=>now}));
 await assert.rejects(createNativeIngressSigner({...env,DATA_DECRYPTION_KEYS_JSON:'{"prior":"'+key(5)+'","prior":"'+key(6)+'"}'},{clock:()=>now}));
 await assert.rejects(createNativeIngressSigner({...env,COLLECT_NATIVE_INGRESS_KEY_ID:'../invalid'},{clock:()=>now}));
});
test('profile/origin, encoded aliases and request bytes remain bounded',async()=>{
 const signer=await createNativeIngressSigner(environment(),{clock:()=>now});
 for(const path of ['/functions/v1/collect-api/v1/%62urimunsi/session/login','/functions/v1/admin-api/v1/burimunsi/session/login'])await assert.rejects(signer(request({path}),'192.0.2.1'));
 await assert.rejects(signer(request({body:'x'.repeat(8193)}),'192.0.2.1'),error=>error.code==='CONTRACT_REQUEST_SIZE');
 await assert.rejects(admitNativeIngress(await signed(),{...environment(),SUPABASE_URL:'https://evil.example'},{clock:()=>now}));
});
test('aborted request cannot retain an admitted network witness',async()=>{
 const aborter=new AbortController(),input=await signed(environment(),{signal:aborter.signal});aborter.abort();
 await assert.rejects(admitNativeIngress(input,environment(),{clock:()=>now}),error=>error.code==='CONTRACT_REQUEST_ABORTED');
});
test('real serve boundary invokes ingress before any DB admission; disabled native and unrelated preflight preserve existing behavior',async()=>{
 // Only unavailable external imports are replaced. Real handler runs through
 // profile/CORS/ingress logic. The replacement DB module throws on any use.
 const hooks=registerHooks({resolve(specifier,context,next){
  if(specifier==='npm:postgres@3.4.7')return {url:'data:text/javascript,export default function(){throw Error("unexpected DB operation")}',shortCircuit:true};
  if(specifier==='npm:nodemailer@10.1.7')return {url:'data:text/javascript,export function createTransport(){throw Error("unexpected SMTP operation")}',shortCircuit:true};
  return next(specifier,context);
 }});
 try{
  const {createHandler}=await import('../serve.js');let called=0,stage;
  const input=request(),handler=createHandler('collect-api',()=>environment(),{reportHealth:value=>{stage=value.runtimeFailure?.stage;},
   verifyNativeIngress:async()=>{called++;throw Error('synthetic denial before DB');},claimNativeIngress:()=>{},consumeNativeIngressNonce:()=>{},openWork:()=>{throw Error('unexpected fence operation');}});
  assert.equal((await handler(input)).status,503);assert.equal(called,1);assert.equal(stage,'native_ingress');
  const preflight=new Request(profile.supabase_origin+'/functions/v1/collect-api/v1/burimunsi/session/login',{method:'OPTIONS'});
  assert.equal((await handler(preflight)).status,204);assert.equal(called,1);
  const disabled=createHandler('collect-api',()=>environment({BURIMUNSI_NATIVE_ENABLED:'false'}),{reportHealth:()=>{},verifyNativeIngress:()=>{called++;throw Error();}});
  await disabled(request());assert.equal(called,1);
  // The entrypoint's actual verifier and nonce wiring is exercised by handler-integration.test.mjs.
 }finally{hooks.deregister();}
});
