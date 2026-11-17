import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,readdir,rm,stat} from 'node:fs/promises';
import {join} from 'node:path';
import {PhaseJournal} from './diagnostics.mjs';
const plan='a'.repeat(64),operation='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
test('phase records contain bounded categories, not arbitrary headers, bodies or errors',async()=>{
 const dir=await mkdtemp('/private/tmp/collect-edge-diagnostic-test-');
 try{
  const j=new PhaseJournal({archiveDir:dir,scope:'synthetic',operationId:operation,planSha256:plan});await j.start('PROJECT_GET');
  j.response(403,'application/json; token=synthetic-header-secret','gzip;synthetic-header-secret','9999999999999999999',1024);
  const b=Buffer.from('{"secret":"synthetic-body-secret"}');j.body(b);b.fill(0);
  const error=Object.assign(new Error('synthetic-error-secret'),{code:'PROVIDER_HTTP_STATUS',shape:'MIME_TYPE_UNSUPPORTED'});await j.failed(error);
  const files=(await readdir(dir)).sort();assert.equal(files.length,2);let last;
  for(const file of files){const path=join(dir,file),raw=await readFile(path);assert(raw.length<=2048);assert.equal((await stat(path)).mode&0o777,0o600);
   const s=raw.toString();for(const secret of ['synthetic-header-secret','synthetic-body-secret','synthetic-error-secret'])assert(!s.includes(secret));last=JSON.parse(s);}
  assert.deepEqual([last.event,last.phase,last.http_status,last.content_type,last.content_encoding,last.content_length,last.body_shape,last.reason,last.shape_reason],
   ['FAILED','PROJECT_GET',403,'json','other','above_limit','json_like','PROVIDER_HTTP_STATUS','MIME_TYPE_UNSUPPORTED']);
  const other=new PhaseJournal({archiveDir:dir,scope:'synthetic',operationId:operation,planSha256:plan});await assert.rejects(other.start('PROJECT_GET'));
  j.sequence=128;await assert.rejects(j.start('PROJECT_GET'));
 }finally{await rm(dir,{recursive:true,force:true});}
});
test('unrecognized error text is reduced to an unclassified code',async()=>{
 const dir=await mkdtemp('/private/tmp/collect-edge-diagnostic-test-');try{const j=new PhaseJournal({archiveDir:dir,scope:'synthetic',operationId:operation,planSha256:plan});
  await j.start('BODY_VALIDATE','collect-api');await j.failed({code:'synthetic-secret',shape:'synthetic-secret',message:'synthetic-secret'});
  const text=await readFile(join(dir,'EDGE-CAPTURE-PROGRESS-002.json'),'utf8'),r=JSON.parse(text);assert.equal(r.reason,'UNCLASSIFIED');assert.equal(r.shape_reason,null);assert(!text.includes('synthetic-secret'));
 }finally{await rm(dir,{recursive:true,force:true});}
});
