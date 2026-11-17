/** Local temporary socket and synthetic bindings; the upstream is a test double. */
import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {mkdtemp,chmod,rm,readFile,realpath} from 'node:fs/promises';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {createNativeIngressApplication,serveNativeIngress} from '../../../../deploy/self-hosted/native-ingress.mjs';
import {admitNativeIngress,createNativeIngressSigner,NATIVE_INGRESS_HEADER} from '../native-ingress.js';
import {MAX_NATIVE_REQUEST_BYTES,MAX_NATIVE_BATCH_REQUEST_BYTES,MAX_NATIVE_PREVIEW_REQUEST_BYTES,nativeRequestBodyLimit} from '../domain/burimunsi/wire/request-boundary.mjs';
import {environment,now,profile} from './native-ingress-fixture.mjs';

const prefix='/functions/v1/collect-api',preview='/v1/burimunsi/members/import/preview',batch='/v1/burimunsi/members/import';
const defaultRoute='/v1/burimunsi/session/login',sha=value=>createHash('sha256').update(value).digest('hex');
const fixture=async()=>{
 const owned=process.env.COLLECT_OWNED_SYNTHETIC_JPEG_FIXTURE;
 const jpeg=owned?await readFile(owned):await readFile(new URL('./fixtures/roster-image-progressive.jpg',import.meta.url));
 // Force the routine synthetic transport sample above the legacy cap without
 // changing the independently owned exact JPEG when supplied.
 const bytes=owned?jpeg:Buffer.concat([jpeg,Buffer.alloc(12288)]);
 const body=JSON.stringify({mimeType:'image/jpeg',fileBytes:bytes.toString('base64'),externalOcrConsent:true});
 assert.ok(Buffer.byteLength(body)>MAX_NATIVE_REQUEST_BYTES);
 return {body,size:Buffer.byteLength(body),sha256:sha(body)};
};
const origin=profile.supabase_origin,host=new URL(origin).host;
function request(route,body,{physical=true,method='POST',headers={}}={}){
 const fields=new Headers({'Content-Type':'application/json','X-BuriMunsi-Auth':'phone_pin'});
 for(const [name,value]of Object.entries(headers))fields.set(name,value);
 return new Request(origin+(physical?prefix:'')+route,{method,headers:fields,body});
}
function viaSocket(path,route,body,{method='POST',headers={},declared=true}={}){
 return new Promise((resolve,reject)=>{
  const req=http.request({socketPath:path,path:prefix+route,method,agent:false,headers:{Host:host,'Content-Type':'application/json',
   'X-BuriMunsi-Auth':'phone_pin','CF-Connecting-IP':'192.0.2.1',...(declared?{'Content-Length':Buffer.byteLength(body)}:{}),...headers}},res=>{
    res.resume();res.once('end',()=>resolve(res.statusCode));
   });
  req.once('error',error=>reject(new Error(`${method} ${route} declared=${declared} bytes=${Buffer.byteLength(body)}: ${error.code}`,{cause:error})));req.end(body);
 });
}
test('only exact import POST targets get the already defined route caps',()=>{
 assert.equal(nativeRequestBodyLimit('POST',preview),MAX_NATIVE_PREVIEW_REQUEST_BYTES);
 assert.equal(nativeRequestBodyLimit('POST',batch),MAX_NATIVE_BATCH_REQUEST_BYTES);
 for(const [method,route] of [['PATCH',preview],['GET',preview],['PUT',batch],['post',preview],['POST',defaultRoute],
  ['POST',preview+'?'],['POST',preview+'?x=1'],['POST',preview+'/'],['POST',preview.replace('preview','%70review')],
  ['POST','/v1/burimunsi/members/import//preview'],['POST',prefix+preview]]){
  assert.equal(nativeRequestBodyLimit(method,route),MAX_NATIVE_REQUEST_BYTES);
 }
});
test('expanded preview crosses the real private Unix listener and both HMAC body checks intact',async()=>{
 const tmp=await mkdtemp(join(await realpath('/tmp'),'buri-import-')),socket=join(tmp,'native.sock');await chmod(tmp,0o700);
 const env=environment({COLLECT_NATIVE_INGRESS_SOCKET:socket}),image=await fixture(),clock=()=>now;
 let calls=0;
 const server=await serveNativeIngress(env,{clock,fetchImpl:async outgoing=>{
  calls++;assert.equal(new URL(outgoing.url).origin,'http://127.0.0.1:55101');
  assert.ok(outgoing.headers.has(NATIVE_INGRESS_HEADER));
  const route=new URL(outgoing.url).pathname.slice(prefix.length);
  const forwarded=await outgoing.text();assert.equal(sha(forwarded),route===preview?image.sha256:sha('x'.repeat(8500)));
  const edge=request(route,forwarded,{physical:false,headers:Object.fromEntries(outgoing.headers)});
  const admitted=await admitNativeIngress(edge,env,{clock});
  assert.equal(admitted.request.headers.has(NATIVE_INGRESS_HEADER),false);
  assert.match(await admitted.networkBucket(admitted.request),/^[a-f0-9]{64}$/);
  assert.equal(sha(await admitted.request.text()),sha(forwarded));
  return Response.json({ok:true});
 }});
 try{
  assert.equal(await viaSocket(socket,preview,image.body),200);
  assert.equal(await viaSocket(socket,preview,image.body,{declared:false}),200);
  assert.equal(await viaSocket(socket,batch,'x'.repeat(8500)),200);
  assert.equal(calls,3);
  for(const [route,change] of [[defaultRoute,{}],[preview+'?x=1',{}],[preview+'?',{}],[preview+'/',{}],
     [preview.replace('preview','%70review'),{}],[preview,{method:'PATCH'}],[preview,{headers:{'CF-Worker':''}}],
     [preview,{headers:{'Content-Length':MAX_NATIVE_PREVIEW_REQUEST_BYTES+1}}],[batch,{headers:{'Content-Length':MAX_NATIVE_BATCH_REQUEST_BYTES+1}}]]){
   // Advertise the oversized request without racing the early 413 response
   // against socket writes; the standalone chunked case still sends the body.
   assert.equal(await viaSocket(socket,route,'',{...change,headers:{'Content-Length':image.size,...change.headers}}),
    Object.hasOwn(change.headers??{},'CF-Worker')?403:413);
  }
  // The stream is cancelled at the fixed bound; a transport that observes the
  // close before the 413 is also a denial and may never reach the upstream.
  try{assert.equal(await viaSocket(socket,defaultRoute,'x'.repeat(MAX_NATIVE_REQUEST_BYTES+1),{declared:false}),413);}
  catch(error){if(!['EPIPE','ECONNRESET'].includes(error.cause?.code))throw error;}
  assert.equal(calls,3);
 }finally{
  await new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve()));
  await rm(tmp,{recursive:true,force:true});
 }
});
test('host application and shared signer keep the limit and reject altered authenticated bytes',async()=>{
 const env=environment(),clock=()=>now,image=await fixture();let calls=0;
 const app=await createNativeIngressApplication(env,{clock,fetchImpl:async()=>{calls++;return Response.json({ok:true});}});
 const invoke=(route,body,options)=>app(request(route,body,options),{rawTarget:prefix+route,clientAddress:'192.0.2.1'});
 assert.equal((await invoke(preview,image.body,{headers:{'Content-Length':image.size}})).status,200);
 assert.equal((await invoke(defaultRoute,image.body,{headers:{'Content-Length':image.size}})).status,413);
 assert.equal((await invoke(preview,image.body,{headers:{'Content-Length':MAX_NATIVE_PREVIEW_REQUEST_BYTES+1}})).status,413);
 assert.equal(calls,1);
 const signer=await createNativeIngressSigner(env,{clock});
 for(const route of [defaultRoute,preview+'?',preview+'?x=1',preview+'/']){
  await assert.rejects(signer(request(route,image.body),'192.0.2.1'),error=>error?.code==='CONTRACT_REQUEST_SIZE');
 }
 await assert.rejects(signer(request(preview,image.body,{method:'PATCH'}),'192.0.2.1'),error=>error?.code==='CONTRACT_REQUEST_SIZE');
 await assert.rejects(signer(request(preview,image.body,{headers:{'Content-Length':MAX_NATIVE_PREVIEW_REQUEST_BYTES+1}}),'192.0.2.1'),
  error=>error?.code==='CONTRACT_REQUEST_SIZE');
 const signed=await signer(request(preview,image.body),'192.0.2.1'),headers=Object.fromEntries(signed.headers);
 await assert.rejects(admitNativeIngress(request(preview,image.body.slice(0,-1)+' ',{physical:false,headers}),env,{clock}));
 await assert.rejects(admitNativeIngress(request(preview+'?',image.body,{physical:false,headers}),env,{clock}),
  error=>error?.code==='CONTRACT_REQUEST_SIZE');
 await assert.rejects(admitNativeIngress(request(preview,image.body,{physical:false,headers:{...headers,'X-BuriMunsi-Auth':'other'}}),env,{clock}));
});
