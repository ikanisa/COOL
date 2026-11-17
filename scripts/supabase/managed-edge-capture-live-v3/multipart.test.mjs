import test from 'node:test';
import assert from 'node:assert/strict';
import {inspectMultipart} from './multipart.mjs';
const part=(name,filename,body)=>`--fixture-boundary\r\nContent-Disposition: form-data; name="${name}"${filename?`; filename="${filename}"`:''}\r\n\r\n${body}\r\n`;
const valid=()=>Buffer.from(part('metadata',null,'{"entrypoint_path":"index.ts"}')+part('file','index.ts','synthetic body\r\n--fixture-boundaryX still body')+'--fixture-boundary--\r\n');
const ct='multipart/form-data; boundary="fixture-boundary"';
const code=e=>e?.code==='UNSUPPORTED_PROVIDER_BODY';
test('recognizes bounded multipart metadata and at least one file without returning contents',()=>{
 const b=valid();assert.deepEqual(inspectMultipart(b,ct),{contentType:'multipart/form-data; boundary=fixture-boundary',fileCount:1});b.fill(0);
});
test('rejects arbitrary success-body errors, malformed envelopes and missing file content',()=>{
 const examples=[
  [Buffer.from('{"error":"synthetic"}'),'application/json'],
  [valid(),'application/octet-stream'],
  [Buffer.from(part('metadata',null,'{}')+'--fixture-boundary--\r\n'),ct],
  [Buffer.from(part('metadata',null,'{}')+part('file','x','')+'--fixture-boundary--\r\n'),ct],
  [Buffer.from(part('metadata',null,'{"x":1,"x":2}')+part('file','x','body')+'--fixture-boundary--\r\n'),ct],
  [Buffer.from(part('metadata',null,'{}')+part('file','x','body')),ct],
 ];
 for(const [body,type] of examples){assert.throws(()=>inspectMultipart(body,type),code);body.fill(0);}
});
test('accepts documented Supabase file-part forms and optional metadata',()=>{
 const forms=[
  'Supabase-Path: source/index.ts',
  "Content-Disposition: form-data; name=\"file\"; filename*=UTF-8''source%2Findex.ts",
  'Content-Disposition: form-data; name=file; filename=source/index.ts',
  'Content-Disposition: form-data; name="file"; filename="index.ts"',
 ];
 for(const headers of forms){const b=Buffer.from('--fixture-boundary\r\n'+headers+'\r\n\r\nsynthetic-source\r\n--fixture-boundary--\r\n');assert.equal(inspectMultipart(b,ct).fileCount,1);b.fill(0);}
});
test('rejects malformed extended filenames and duplicate disposition parameters',()=>{
 for(const headers of ["Content-Disposition: form-data; name=file; filename*=UTF-8''%ZZ",'Content-Disposition: form-data; name=file; filename=a; filename=b']){
  const b=Buffer.from('--fixture-boundary\r\n'+headers+'\r\n\r\nx\r\n--fixture-boundary--\r\n');assert.throws(()=>inspectMultipart(b,ct),code);b.fill(0);
 }
});
