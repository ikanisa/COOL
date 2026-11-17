import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {SupabaseNativeTransport} from '../storage/supabase-transport.js';
import {StorageProtocolError,sha256} from '../storage/protocol.js';

// Exercise the actual bucket method with synthetic HTTP and a journal that
// fails on any access. No application database or provider is contacted.
const adapters=readFileSync(new URL('../adapters.js',import.meta.url),'utf8');
const start=adapters.indexOf('export class SupabaseObjectBucket {'),end=adapters.indexOf('\n// Leave room for JSON escaping',start);
assert(start>=0&&end>start);
class ApiError extends Error{constructor(status,code,message){super(message);this.status=status;this.code=code;}}
const Bucket=new Function('StorageProtocolError','ApiError','unavailable','sha256',
 adapters.slice(start,end).replace('export class','class')+';return SupabaseObjectBucket;')(
 StorageProtocolError,ApiError,name=>new ApiError(503,name+'_unavailable','Synthetic unavailable'),sha256);
const key='sms/00000000-0000-4000-8000-000000000001';
function fixture(payload){
 const calls=[],bytes=new TextEncoder().encode(payload);
 const transport=new SupabaseNativeTransport({url:'https://storage.example.invalid',bucket:'collect-evidence',secretKey:'sb_secret_synthetic',
  fetchImpl:async(url,init)=>{
   const path=new URL(url).pathname;calls.push({path,method:init.method});
   if(path==='/storage/v1/bucket/collect-evidence')return Response.json({id:'collect-evidence',name:'collect-evidence',public:false});
   assert.equal(path,'/storage/v1/object/authenticated/collect-evidence/'+key);
   return new Response(init.method==='HEAD'?null:bytes,{status:200,headers:{'content-length':String(bytes.length)}});
  }});
 const journal=new Proxy({},{get(){throw Error('journal must never be accessed');}});
 return {calls,bytes,media:Object.assign(Object.create(Bucket.prototype),{transport,journal,
  namespace:{origin:'https://storage.example.invalid',bucket:'collect-evidence'}})};
}
test('read-only verified probe uses only bucket GET, object HEAD and object GET',async()=>{
 const f=fixture('synthetic encrypted object'),hash=await sha256(f.bytes);
 const result=await f.media.getVerifiedReadOnly(key,{sha256:hash,size:f.bytes.length});
 assert.equal(new TextDecoder().decode(result),'synthetic encrypted object');
 assert.deepEqual(f.calls.map(x=>x.method),['GET','HEAD','GET']);
});
test('read-only probe fails closed on changed content without touching the journal',async()=>{
 const f=fixture('changed encrypted object');
 await assert.rejects(f.media.getVerifiedReadOnly(key,{sha256:'a'.repeat(64),size:f.bytes.length}),e=>e.status===503);
 assert.deepEqual(f.calls.map(x=>x.method),['GET','HEAD','GET']);
 await assert.rejects(f.media.getVerifiedReadOnly('other/key',{sha256:'a'.repeat(64),size:1}),e=>e.status===400);
 assert.equal(f.calls.length,3);
});
test('read-only probe rejects a changed Storage namespace before any request',async()=>{
 const f=fixture('synthetic encrypted object');f.media.namespace={origin:'https://other.invalid',bucket:'collect-evidence'};
 await assert.rejects(f.media.getVerifiedReadOnly(key,{sha256:await sha256(f.bytes),size:f.bytes.length}),e=>e.status===503);
 assert.equal(f.calls.length,0);
});
