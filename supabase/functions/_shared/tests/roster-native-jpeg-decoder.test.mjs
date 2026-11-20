/** Byte-only synthetic admission tests. No pixel decoder or network provider. */
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createNativeRosterJpegDecoder,isNativeRosterJpegDecoder,NATIVE_JPEG_PROTOCOL,NATIVE_JPEG_IDENTITY} from '../roster_native_jpeg_decoder.mjs';

const build='a'.repeat(64),context={requestId:'11111111-1111-4111-8111-111111111111',reservationId:'22222222-2222-4222-8222-222222222222'};
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const jpeg=()=>readFile(new URL('./fixtures/roster-image-progressive.jpg',import.meta.url));
const port=()=>createNativeRosterJpegDecoder({protocol:NATIVE_JPEG_PROTOCOL,identity:NATIVE_JPEG_IDENTITY,approvedBuildSha256:build,secret:''});
function request(bytes,change=value=>value,options={}){
 const value=change({schema_version:1,source_sha256:hash(bytes),decoder_build_sha256:build,mime_type:'image/jpeg',content_base64:bytes.toString('base64')});
 return new Request(NATIVE_JPEG_IDENTITY,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(value),...options});
}
test('native JPEG port preserves original source bytes and has an honest local identity',async()=>{
 const bytes=await jpeg(),decoder=port();assert.equal(isNativeRosterJpegDecoder(decoder),true);
 assert.equal(isNativeRosterJpegDecoder({...decoder}),false);assert.equal(decoder.identity,NATIVE_JPEG_IDENTITY);
 const result=await (await decoder.fetch(request(bytes),context)).json();
 assert.deepEqual(result,{source_sha256:hash(bytes),decoder_build_sha256:build,content:[{type:'input_image',image_url:'data:image/jpeg;base64,'+bytes.toString('base64')}]});
});
for(const [name,change] of [
 ['wrong source hash',v=>({...v,source_sha256:'b'.repeat(64)})],
 ['wrong build',v=>({...v,decoder_build_sha256:'b'.repeat(64)})],
 ['non-JPEG declared MIME',v=>({...v,mime_type:'image/png'})],
 ['unknown logical field',v=>({...v,extra:true})],
 ['noncanonical base64',v=>({...v,content_base64:v.content_base64+'\n'})],
])test('native JPEG port refuses '+name,async()=>{
 await assert.rejects(port().fetch(request(await jpeg(),change),context),/roster_native_jpeg_invalid/);
});
test('truncated JPEG and multi-picture JPEG are refused despite matching hashes',async()=>{
 const bytes=await jpeg(),mpo=await readFile(new URL('./fixtures/roster-image-multiframe.mpo',import.meta.url));
 for(const invalid of [bytes.subarray(0,bytes.length-2),mpo])await assert.rejects(port().fetch(request(invalid),context),/roster_native_jpeg_invalid/);
});
test('unbounded input, wrong protocol, secret or request lineage is refused',async()=>{
 for(const config of [{protocol:'roster-hmac-v1'},{identity:'https://other.invalid/'},{secret:'not-a-native-secret'},{approvedBuildSha256:'invalid'}])
  assert.throws(()=>createNativeRosterJpegDecoder({protocol:NATIVE_JPEG_PROTOCOL,identity:NATIVE_JPEG_IDENTITY,approvedBuildSha256:build,...config}),/roster_native_jpeg_invalid/);
 const bytes=await jpeg();await assert.rejects(port().fetch(request(bytes),{...context,extra:true}),/roster_native_jpeg_invalid/);
 const oversized=request(bytes);oversized.headers.set('Content-Length',String(8*1024*1024+1));
 await assert.rejects(port().fetch(oversized,context),/roster_native_jpeg_invalid/);
});
test('abort cancels a pending local request body and settles without dispatch',async()=>{
 const controller=new AbortController();let cancelled=false;
 const body=new ReadableStream({start(){},cancel(){cancelled=true;}});
 const req=new Request(NATIVE_JPEG_IDENTITY,{method:'POST',headers:{'Content-Type':'application/json'},body,duplex:'half',signal:controller.signal});
 const result=port().fetch(req,context);controller.abort();await assert.rejects(result);assert.equal(cancelled,true);
});
