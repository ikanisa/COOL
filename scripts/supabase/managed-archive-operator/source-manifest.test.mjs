import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,realpath,writeFile,rm,symlink} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash} from 'node:crypto';
import {spawn} from 'node:child_process';
import {verifyManifestFile} from './source-manifest.mjs';
import {captureManagedArchive} from './operator.mjs';
const sha=x=>createHash('sha256').update(x).digest('hex');
const code=x=>e=>e?.archiveCode===x;

test('owned source/tool manifest detects changed bytes, duplicate paths and symlink substitution',async()=>{
 const root=await mkdtemp(join(await realpath(tmpdir()),'collect-archive-pins-'));
 try{
  const file=join(root,'source.mjs'),manifest=join(root,'manifest.json');await writeFile(file,'fixture version one');
  const build=inputs=>JSON.stringify({format:'collect.managed-archive-operator.source-pins.v2',inputs});
  const payload=build([{path:file,sha256:sha('fixture version one')}]);await writeFile(manifest,payload);
  assert.deepEqual(await verifyManifestFile(manifest,sha(payload),{required:[file]}),{status:'source_verified',manifestSha256:sha(payload)});
  await writeFile(file,'fixture version two');await assert.rejects(verifyManifestFile(manifest,sha(payload)),code('SOURCE_MANIFEST_REFUSED'));
  const duplicate=build([{path:file,sha256:sha('fixture version two')},{path:file,sha256:sha('fixture version two')}]);
  await writeFile(manifest,duplicate);await assert.rejects(verifyManifestFile(manifest,sha(duplicate)),code('SOURCE_MANIFEST_REFUSED'));
  const duplicateKey=duplicate.replace('"inputs":','"inputs":[],"inputs":');
  await writeFile(manifest,duplicateKey);await assert.rejects(verifyManifestFile(manifest,sha(duplicateKey)),code('SOURCE_MANIFEST_REFUSED'));
  const link=join(root,'linked.mjs');await symlink(file,link);const linked=build([{path:link,sha256:sha('fixture version two')}]);
  await writeFile(manifest,linked);await assert.rejects(verifyManifestFile(manifest,sha(linked)),code('SOURCE_MANIFEST_REFUSED'));
 }finally{await rm(root,{recursive:true,force:true});}
});

test('wrong external manifest pin refuses before accessing a credential property or reading a private pipe',{timeout:30000},async()=>{
 let read=false;await assert.rejects(captureManagedArchive({implementationManifestSha256:'f'.repeat(64),get secret(){read=true;return 'invented-secret';}}),code('SOURCE_MANIFEST_REFUSED'));
 assert.equal(read,false);
 for(const name of ['supervisor.mjs','worker.mjs']){
  const cli=new URL('./'+name,import.meta.url),child=spawn(process.execPath,[cli.pathname,'f'.repeat(64)],{env:{PATH:'/usr/bin:/bin',LC_ALL:'C'},stdio:['pipe','pipe','pipe']});
  let out='',err='';child.stdout.on('data',b=>out+=b);child.stderr.on('data',b=>err+=b);child.stdin.on('error',()=>{});
  const result=new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',exit=>resolve(exit));});
  child.stdin.write('invented-secret-do-not-print'); // The pipe remains open while the verifier refuses.
  assert.equal(await result,1);assert.equal(JSON.parse(out).code,'SOURCE_MANIFEST_REFUSED');assert.equal((out+err).includes('invented-secret'),false);
 }
});
