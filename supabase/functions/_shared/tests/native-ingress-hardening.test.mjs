import test from 'node:test';
import assert from 'node:assert/strict';
import {createHmac} from 'node:crypto';
import {claimNativeIngress,createNativeIngressSigner,verifyNativeIngress} from '../native-ingress.js';
import {environment,now,request,signed,key,sha} from './native-ingress-fixture.mjs';

const denied=error=>error?.code==='native_ingress_denied';
const store=()=>{
 const used=new Set();
 return async ({nonce})=>{if(used.has(nonce))return false;used.add(nonce);return true;};
};
test('the Cloud signer binds authority, request and idempotency headers into the digest',async()=>{
 const signer=await createNativeIngressSigner(environment(),{clock:()=>now});
 const output=await signer(request({headers:{'idempotency-key':'idempotent','x-request-id':'request','x-collect-admin':'admin'}}),'192.0.2.1');
 const parts=JSON.parse(Buffer.from(output.headers.get('x-collect-native-ingress'),'base64url')),signature=parts.pop();
 const names=['authorization','cookie','apikey','origin','content-type','x-collect-csrf','x-collect-requested-with','x-collect-review-reason',
  'idempotency-key','x-request-id','x-collect-admin'];
 const fields=[...output.headers].filter(([name])=>name.startsWith('x-burimunsi-')||names.includes(name)).sort(([a],[b])=>a.localeCompare(b));
 assert.equal(parts[8],sha(JSON.stringify(fields)));
 const signing=createHmac('sha256',Buffer.from(key(5),'base64')).update('collect.native-ingress.signing-key.v1').digest();
 try{assert.equal(signature,createHmac('sha256',signing).update(JSON.stringify(['collect.native-ingress.v1',...parts,'POST','collect-api','/v1/burimunsi/session/login'])).digest('hex'));}
 finally{signing.fill(0);}
});
async function signedBody(path,size,{method='POST',clock=()=>now}={}){
 const env=environment(),signer=await createNativeIngressSigner(env,{clock});
 const output=await signer(request({path:'/functions/v1/collect-api/v1/burimunsi'+path,body:'x'.repeat(size),method}),'192.0.2.1');
 const url=new URL(output.url);url.pathname=url.pathname.slice('/functions/v1/collect-api'.length);
 return {env,input:new Request(url,{method:output.method,headers:output.headers,body:await output.arrayBuffer()})};
}

test('an opaque token releases one verified request only after a committed nonce claim',async()=>{
 const env=environment(),input=await signed(env),replay=input.clone(),consume=store();
 const first=await verifyNativeIngress(input,env,{clock:()=>now}),second=await verifyNativeIngress(replay,env,{clock:()=>now});
 assert.deepEqual(Object.keys(first),[]);assert.equal(first.request,undefined);assert.equal(first.networkBucket,undefined);
 const outcomes=await Promise.allSettled([claimNativeIngress(first,consume),claimNativeIngress(second,consume)]);
 assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
 assert.equal(outcomes.filter(x=>x.status==='rejected'&&denied(x.reason)).length,1);
 const admitted=outcomes.find(x=>x.status==='fulfilled').value;
 assert.match(await admitted.networkBucket(admitted.request),/^[a-f0-9]{64}$/);
 await assert.rejects(claimNativeIngress(first,consume));await assert.rejects(claimNativeIngress(second,consume));
 await assert.rejects(admitted.networkBucket(new Request(admitted.request.url)),denied);
});
test('failed and unconfirmed claims never release a witness and cannot reuse the token',async()=>{
 for(const consume of [()=>false,()=>null,()=>1,()=>{throw Error('private database failure');}]){
  const env=environment(),token=await verifyNativeIngress(await signed(env),env,{clock:()=>now});
  await assert.rejects(claimNativeIngress(token,consume));await assert.rejects(claimNativeIngress(token,()=>true));
 }
 const invalidEnv=environment(),invalid=await verifyNativeIngress(await signed(invalidEnv),invalidEnv,{clock:()=>now});
 await assert.rejects(claimNativeIngress(invalid,null));await assert.rejects(claimNativeIngress(invalid,()=>true));
 const env=environment(),input=await signed(env),copy=input.clone(),consume=store();
 const a=await verifyNativeIngress(input,env,{clock:()=>now}),b=await verifyNativeIngress(copy,env,{clock:()=>now});
 await assert.rejects(claimNativeIngress(a,async values=>{assert.equal(await consume(values),true);throw Error('lost acknowledgement');}),
  e=>e.code==='native_ingress_store_unavailable'&&!e.message.includes('lost acknowledgement'));
 await assert.rejects(claimNativeIngress(b,consume),denied);
});
test('claim and network witness reject expiration, backward clock skew and cancellation',async()=>{
 for(const offset of [30001,-2001]){
  const env=environment();let clock=now,calls=0;
  const token=await verifyNativeIngress(await signed(env),env,{clock:()=>clock});clock+=offset;
  await assert.rejects(claimNativeIngress(token,()=>{calls++;return true;}),denied);assert.equal(calls,0);
 }
 const env=environment();let clock=now;const token=await verifyNativeIngress(await signed(env),env,{clock:()=>clock});
 const admitted=await claimNativeIngress(token,()=>true);clock+=30001;
 await assert.rejects(admitted.networkBucket(admitted.request),denied);
 const aborter=new AbortController(),input=await signed(env,{signal:aborter.signal});
 const pending=await verifyNativeIngress(input,env,{clock:()=>now});aborter.abort();let calls=0;
 await assert.rejects(claimNativeIngress(pending,()=>{calls++;return true;}),e=>e.code==='CONTRACT_REQUEST_ABORTED');assert.equal(calls,0);
});
test('a committed claim that returns too late cannot release a witness or be replayed',async()=>{
 const env=environment(),input=await signed(env),copy=input.clone(),consume=store();let clock=now;
 const token=await verifyNativeIngress(input,env,{clock:()=>clock}),duplicate=await verifyNativeIngress(copy,env,{clock:()=>clock});
 await assert.rejects(claimNativeIngress(token,async value=>{const committed=await consume(value);clock+=30001;return committed;}),denied);
 clock=now;await assert.rejects(claimNativeIngress(duplicate,consume),denied);
});
test('cancellation during a committed claim never releases the request',async()=>{
 const env=environment(),aborter=new AbortController(),input=await signed(env,{signal:aborter.signal}),
  duplicate=new Request(input.clone(),{signal:new AbortController().signal}),consume=store();
 const token=await verifyNativeIngress(input,env,{clock:()=>now}),replay=await verifyNativeIngress(duplicate,env,{clock:()=>now});
 await assert.rejects(claimNativeIngress(token,async value=>{const committed=await consume(value);aborter.abort();return committed;}),
  e=>e.code==='CONTRACT_REQUEST_ABORTED');
 await assert.rejects(claimNativeIngress(replay,consume),denied);
});
test('a clock shift during body verification cannot create a dispatchable token',async()=>{
 const env=environment(),input=await signed(env);let reads=0;
 await assert.rejects(verifyNativeIngress(input,env,{clock:()=>++reads<3?now:now-2001}),denied);
});
test('changed Cloud authority headers cannot reach the nonce store',async()=>{
 for(const name of ['authorization','cookie','origin','x-burimunsi-group']){
  const env=environment(),input=await signed(env),headers=new Headers(input.headers),body=await input.arrayBuffer();let calls=0;
  headers.set(name,'synthetic-altered-value');
  await assert.rejects((async()=>{const token=await verifyNativeIngress(new Request(input.url,{method:'POST',headers,body}),env,{clock:()=>now});
   await claimNativeIngress(token,()=>{calls++;return true;});})(),denied);
  assert.equal(calls,0);
 }
});
for(const [path,limit] of [['/session/login',8192],['/members/import',524288],['/members/import/preview',6991532]])
 test(`exact ${path} transport bound is ${limit} bytes`,async()=>{
  const {env,input}=await signedBody(path,limit),token=await verifyNativeIngress(input,env,{clock:()=>now});
  const admitted=await claimNativeIngress(token,store());assert.equal((await admitted.request.arrayBuffer()).byteLength,limit);
  await assert.rejects(signedBody(path,limit+1),e=>e.code==='CONTRACT_REQUEST_SIZE');
 });
test('queries, similar paths and different methods do not expand the request limit',async()=>{
 for(const [path,method] of [['/members/import?x=1','POST'],['/members/import/preview?x=1','POST'],
  ['/members/import-extra','POST'],['/members/import','PATCH']])
  await assert.rejects(signedBody(path,8193,{method}),e=>e.code==='CONTRACT_REQUEST_SIZE');
});
test('declared body length is independently checked before a nonce can be claimed',async()=>{
 const {env,input}=await signedBody('/members/import/preview',20),headers=new Headers(input.headers),body=await input.arrayBuffer();
 headers.set('content-length','21');let calls=0;
 await assert.rejects((async()=>{const token=await verifyNativeIngress(new Request(input.url,{method:'POST',headers,body}),env,{clock:()=>now});
  await claimNativeIngress(token,()=>{calls++;return true;});})(),e=>e.code==='CONTRACT_CONTENT_LENGTH');
 assert.equal(calls,0);
});
