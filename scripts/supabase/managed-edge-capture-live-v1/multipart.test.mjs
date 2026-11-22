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
