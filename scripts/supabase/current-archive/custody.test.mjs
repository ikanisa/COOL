import test from 'node:test';import assert from 'node:assert/strict';import crypto,{randomBytes} from 'node:crypto';import {syncBuiltinESMExports} from 'node:module';import {mkdtemp,mkdir,chmod,readFile,writeFile,appendFile,open,stat,rename,symlink,link,rm,realpath} from 'node:fs/promises';import {resolve} from 'node:path';import {tmpdir} from 'node:os';
import {snapshot as oldSnapshot} from './fixtures.mjs';import {canonical} from './codec.mjs';import {encryptSnapshot,decryptSnapshot,writeEncryptedBundle,readEncryptedBundle,readPrivateFile} from './bundle.mjs';import {compilePlanningRequest,preparePlanCandidate,compileCaptureRequest,assembleManagementSnapshot} from './capture.mjs';
function snapshot(){const old=oldSnapshot(),planning=compilePlanningRequest({expectedMigrationCount:8}),postgres={...old.postgres,database:'postgres',backend_pid:'1',row_security:'off',application_name:'collect.archive.'+planning.request_id.replaceAll('-','')};delete postgres.rolled_back;const metadata={format:'collect.mgmt.metadata.v1',postgres,relations:old.tables.map((t,i)=>({schema:t.schema,name:t.name,kind:t.kind,oid:String(i+1),columns_record:canonical(t.columns)})),migrations:old.migrations.map(({sha256,...m})=>m),catalog_record:canonical(old.catalog),sequences_record:'[]'};const plan=preparePlanCandidate(metadata,{runtimeSourceSha256:old.runtime_source_sha256,sourceMigrations:old.migrations.map(({observed_record,observed_record_sha256,...m})=>m),expectedMigrationCount:8}),compiled=compileCaptureRequest(plan);postgres.application_name='collect.archive.'+compiled.request_id.replaceAll('-','');const payload={format:'collect.mgmt.data.v1',postgres,tables:old.tables.map((t,i)=>({schema:t.schema,name:t.name,kind:t.kind,oid:String(i+1),columns_record:canonical(t.columns),measure:{index:i,rows:String(t.rows.length),bytes:'1',max_cell:'1'},cells:t.rows.map(r=>r.cells)})),migrations:metadata.migrations,catalog_record:metadata.catalog_record,sequences:[]};return assembleManagementSnapshot({status:201,body:Buffer.from(JSON.stringify([{kind:'capture',payload:JSON.stringify(payload)}]))},plan,compiled);}
test('AES256GCM wrong key and header/IV/tag/ciphertext tampering cannot authenticate',()=>{const key=randomBytes(32),bytes=encryptSnapshot(snapshot(),key);assert.equal(decryptSnapshot(bytes,key).snapshot.project_ref,'rrlduytparvsjfmegalh');assert.throws(()=>decryptSnapshot(bytes,randomBytes(32)));for(const mutate of [x=>x.header.archive_id='f'.repeat(36),x=>x.header.plaintext_bytes++,x=>x.iv=Buffer.alloc(12).toString('base64url'),x=>x.tag=Buffer.alloc(16).toString('base64url'),x=>x.ciphertext='A'+x.ciphertext.slice(1)]){const x=JSON.parse(bytes);mutate(x);assert.throws(()=>decryptSnapshot(Buffer.from(canonical(x)),key));}key.fill(0);});
test('private custody rejects shared permissions, symbolic/hard links, nested keys and replaced ciphertext',async t=>{const d=await mkdtemp(resolve(await realpath(tmpdir()),'collect-archive-custody-'));await chmod(d,0o700);t.after(()=>rm(d,{recursive:true,force:true}));const a=resolve(d,'a'),k=resolve(d,'k');await mkdir(a,{mode:0o700});await mkdir(k,{mode:0o700});const r=await writeEncryptedBundle(snapshot(),{archiveDirectory:a,keyDirectory:k});const args={archivePath:r.archive_path,keyPath:r.key_path,expectedArchiveSha256:r.archive_sha256};await readEncryptedBundle(args);await chmod(r.key_path,0o644);await assert.rejects(readEncryptedBundle(args));await chmod(r.key_path,0o600);const sym=resolve(k,'sym');await symlink(r.key_path,sym);await assert.rejects(readPrivateFile(sym,32));await link(r.key_path,resolve(k,'hard'));await assert.rejects(readEncryptedBundle(args));await assert.rejects(writeEncryptedBundle(snapshot(),{archiveDirectory:d,keyDirectory:k}),{code:'KEY_CUSTODY_SEPARATION_REQUIRED'});await writeFile(r.archive_path,'tampered',{mode:0o600});await assert.rejects(readEncryptedBundle(args),{code:'ARCHIVE_HASH_MISMATCH'});});

// Instrument the real crypto implementation: retain references to each plaintext
// buffer so the test can inspect them after success or an authentication error.
function withPlaintextTracking(run,{splitFinal=false}={}){
 const factory=crypto.createDecipheriv,concat=Buffer.concat,seen={updates:[],finals:[],assembled:[],updateHadNonzero:false};
 crypto.createDecipheriv=(...args)=>{
  const decipher=factory(...args),update=decipher.update.bind(decipher),final=decipher.final.bind(decipher);let tail;
  decipher.update=(...args)=>{const actual=update(...args);let b=actual;if(splitFinal){assert.ok(actual.length>1);tail=actual.subarray(actual.length-1);b=actual.subarray(0,actual.length-1);}seen.updates.push(b);seen.updateHadNonzero||=b.some(x=>x!==0);return b;};
  decipher.final=(...args)=>{const actual=final(...args);if(splitFinal)assert.equal(actual.length,0);const b=splitFinal?tail:actual;seen.finals.push(b);return b;};return decipher;
 };
 syncBuiltinESMExports();
 Buffer.concat=(parts,...args)=>{const out=concat(parts,...args);if(parts.some(p=>seen.updates.includes(p)))seen.assembled.push(out);return out;};
 try{run(seen);}finally{Buffer.concat=concat;crypto.createDecipheriv=factory;syncBuiltinESMExports();}
}
function expectPlaintextWiped(seen,authenticated){
 assert.equal(seen.updates.length,1);assert.ok(seen.updateHadNonzero);assert.ok(seen.updates[0].every(x=>x===0));
 assert.equal(seen.finals.length,authenticated?1:0);assert.ok(seen.finals.every(b=>b.length>0&&b.every(x=>x===0)));
 assert.equal(seen.assembled.length,authenticated?1:0);assert.ok(seen.assembled.every(b=>b.length>0&&b.every(x=>x===0)));
}
function rebindingMismatch(bytes,key,s){
 const x=JSON.parse(bytes),plain=Buffer.from(canonical(s));
 try{
  x.header.runtime_source_sha256=x.header.runtime_source_sha256==='0'.repeat(64)?'1'.repeat(64):'0'.repeat(64);
  const cipher=crypto.createCipheriv('aes-256-gcm',key,Buffer.from(x.iv,'base64url'),{authTagLength:16});cipher.setAAD(Buffer.from(canonical(x.header)));
  x.ciphertext=Buffer.concat([cipher.update(plain),cipher.final()]).toString('base64url');x.tag=cipher.getAuthTag().toString('base64url');return Buffer.from(canonical(x));
 }finally{plain.fill(0);}
}
test('decrypt wipes update, final and assembled plaintext on success, bad tag and post-auth validation failure',()=>{
 const s=snapshot(),key=randomBytes(32),bytes=encryptSnapshot(s,key),tampered=JSON.parse(bytes),tag=Buffer.from(tampered.tag,'base64url');tag[0]^=1;tampered.tag=tag.toString('base64url');
 const mismatch=rebindingMismatch(bytes,key,s);
 try{
  withPlaintextTracking(seen=>{assert.deepEqual(decryptSnapshot(bytes,key).snapshot,s);expectPlaintextWiped(seen,true);},{splitFinal:true});
  withPlaintextTracking(seen=>{assert.throws(()=>decryptSnapshot(Buffer.from(canonical(tampered)),key),{code:'AUTHENTICATION_FAILED'});expectPlaintextWiped(seen,false);});
  withPlaintextTracking(seen=>{assert.throws(()=>decryptSnapshot(mismatch,key),{code:'HEADER_SNAPSHOT_MISMATCH'});expectPlaintextWiped(seen,true);},{splitFinal:true});
 }finally{key.fill(0);tag.fill(0);}
});
test('private reader bounds the actual read and rejects growth after its first stat',async t=>{
 const d=await mkdtemp(resolve(await realpath(tmpdir()),'collect-private-growth-'));t.after(()=>rm(d,{recursive:true,force:true}));const path=resolve(d,'input');await writeFile(path,'ABCD',{mode:0o600});
 const identity=await stat(path),sample=await open(path,'r'),proto=Object.getPrototypeOf(sample);await sample.close();
 const originalStat=proto.stat,originalRead=proto.read,originalReadFile=proto.readFile,reads=[],buffers=[];let target,grown=false,readFileCalls=0;
 proto.stat=async function(...args){const value=await originalStat.apply(this,args);if(!grown&&value.dev===identity.dev&&value.ino===identity.ino){grown=true;target=this;await appendFile(path,Buffer.alloc(64*1024,0x61));}return value;};
 proto.read=async function(...args){if(this===target){buffers.push(args[0]);reads.push(args[2]);}return originalRead.apply(this,args);};
 proto.readFile=async function(...args){if(this===target)readFileCalls++;return originalReadFile.apply(this,args);};
 try{
  await assert.rejects(readPrivateFile(path,8),{code:'FILE_CHANGED'});assert.equal(grown,true);assert.equal((await stat(path)).size,4+64*1024);
  assert.equal(readFileCalls,0);assert.ok(reads.length>0);assert.ok(reads.reduce((a,b)=>a+b,0)<=5);assert.ok(buffers.every(b=>b.every(x=>x===0)));
 }finally{proto.stat=originalStat;proto.read=originalRead;proto.readFile=originalReadFile;}
});
test('private reader preserves exact returned bytes, empty files, caps and path identity',async t=>{
 const d=await mkdtemp(resolve(await realpath(tmpdir()),'collect-private-bounds-'));t.after(()=>rm(d,{recursive:true,force:true}));const path=resolve(d,'input'),empty=resolve(d,'empty');
 await writeFile(path,'synthetic',{mode:0o600});await writeFile(empty,'',{mode:0o600});assert.equal((await readPrivateFile(path,9)).toString(),'synthetic');assert.equal((await readPrivateFile(empty,0)).length,0);
 await assert.rejects(readPrivateFile(path,8),{code:'PRIVATE_FILE_REQUIRED'});await assert.rejects(readPrivateFile(path,Infinity),{code:'PRIVATE_FILE_REQUIRED'});
 const identity=await stat(path),sample=await open(path,'r'),proto=Object.getPrototypeOf(sample);await sample.close();const originalStat=proto.stat;let replaced=false;
 proto.stat=async function(...args){const value=await originalStat.apply(this,args);if(!replaced&&value.dev===identity.dev&&value.ino===identity.ino){replaced=true;await rename(path,resolve(d,'original'));await writeFile(path,'synthetic',{mode:0o600});}return value;};
 try{await assert.rejects(readPrivateFile(path,9),{code:'FILE_CHANGED'});assert.equal(replaced,true);}finally{proto.stat=originalStat;}
});
