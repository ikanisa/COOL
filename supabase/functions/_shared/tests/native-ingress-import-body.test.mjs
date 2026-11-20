// In-process managed frontdoor and Edge verification with synthetic requests.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createNativeIngressSigner,NATIVE_INGRESS_HEADER} from '../native-ingress.js';
import {MAX_NATIVE_REQUEST_BYTES,MAX_NATIVE_BATCH_REQUEST_BYTES,MAX_NATIVE_PREVIEW_REQUEST_BYTES,nativeRequestBodyLimit} from '../domain/burimunsi/wire/request-boundary.mjs';
import {admitNativeIngress,environment,now,profile} from './native-ingress-fixture.mjs';
const prefix='/functions/v1/collect-api',preview='/v1/burimunsi/members/import/preview',batch='/v1/burimunsi/members/import',ordinary='/v1/burimunsi/session/login';
const sha=value=>createHash('sha256').update(value).digest('hex');
function request(path,body,{physical=true,method='POST',headers={}}={}){
 const fields=new Headers({'Content-Type':'application/json','X-BuriMunsi-Auth':'phone_pin'});
 for(const [name,value] of Object.entries(headers))fields.set(name,value);
 return new Request(profile.supabase_origin+(physical?prefix:'')+path,{method,headers:fields,body});
}
test('only exact import POST targets get expanded route caps',()=>{
 assert.equal(nativeRequestBodyLimit('POST',preview),MAX_NATIVE_PREVIEW_REQUEST_BYTES);
 assert.equal(nativeRequestBodyLimit('POST',batch),MAX_NATIVE_BATCH_REQUEST_BYTES);
 for(const [method,path] of [['PATCH',preview],['GET',preview],['POST',ordinary],['POST',preview+'?x=1'],['POST',preview+'/']])
  assert.equal(nativeRequestBodyLimit(method,path),MAX_NATIVE_REQUEST_BYTES);
});
test('managed signer and claimed Edge request preserve expanded import bytes and authority',async()=>{
 const jpeg=await readFile(new URL('./fixtures/roster-image-progressive.jpg',import.meta.url));
 const body=JSON.stringify({mimeType:'image/jpeg',fileBytes:Buffer.concat([jpeg,Buffer.alloc(12288)]).toString('base64'),externalOcrConsent:true});
 assert(Buffer.byteLength(body)>MAX_NATIVE_REQUEST_BYTES);
 const env=environment(),clock=()=>now,signer=await createNativeIngressSigner(env,{clock});
 const signed=await signer(request(preview,body),'192.0.2.1'),headers=Object.fromEntries(signed.headers);
 assert(signed.headers.has(NATIVE_INGRESS_HEADER));
 const admitted=await admitNativeIngress(request(preview,body,{physical:false,headers}),env,{clock});
 assert(!admitted.request.headers.has(NATIVE_INGRESS_HEADER));assert.equal(sha(await admitted.request.text()),sha(body));
 assert.match(await admitted.networkBucket(admitted.request),/^[a-f0-9]{64}$/);
 await assert.rejects(admitNativeIngress(request(preview,body.slice(0,-1)+' ',{physical:false,headers}),env,{clock}));
 await assert.rejects(admitNativeIngress(request(preview,body,{physical:false,headers:{...headers,'X-BuriMunsi-Auth':'other'}}),env,{clock}));
 for(const path of [ordinary,preview+'?x=1',preview+'/'])
  await assert.rejects(signer(request(path,body),'192.0.2.1'),error=>error?.code==='CONTRACT_REQUEST_SIZE');
});
