import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomBytes} from 'node:crypto';
import {ChildProcess} from 'node:child_process';
import {closeSync,createWriteStream,mkdtempSync,openSync,readFileSync,rmSync,statSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {Readable,Writable} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {authenticateSyntheticArchive,createSyntheticEncryptor,pipeSyntheticArchiveTo,StreamArchiveError} from './stream-archive.mjs';
import {BoundBackupError,syntheticBoundTestHelpers} from './synthetic-bound-backup.mjs';
const code=x=>e=>e instanceof StreamArchiveError&&e.code===x;
test('single synthetic AES-GCM stream remains bounded for large archives',{timeout:30000},async t=>{
 const root=mkdtempSync('/private/tmp/collect-stream-fixture-'),key=randomBytes(32),path=join(root,'archive.enc'),total=16*1024*1024+19,sourceHash=createHash('sha256');
 try{
  await t.test('managed mode rejects before inspecting key',async()=>{let reads=0;const o={mode:'managed'};Object.defineProperty(o,'key',{get(){reads++;throw Error();}});assert.throws(()=>createSyntheticEncryptor(o),code('managed_execution_closed'));assert.equal(reads,0);});
  async function* source(){let n=0;while(n<total){const size=Math.min(512*1024,total-n),b=Buffer.alloc(size,(n/4096)%251);sourceHash.update(b);n+=size;yield b;}}
  await pipeline(Readable.from(source()),createSyntheticEncryptor({mode:'synthetic',key}),createWriteStream(path,{flags:'wx',mode:0o600}));
  const sourceDigest=sourceHash.digest('hex'),size=statSync(path).size;
  await t.test('authenticates and streams a 16 MiB archive without a plaintext file',async()=>{const fd=openSync(path,'r');try{
   const r=await authenticateSyntheticArchive({mode:'synthetic',key,fd,signal:null});assert.equal(r.archiveBytes,total);
   const h=createHash('sha256');let received=0;const output=new Writable({write(b,_e,cb){h.update(b);received+=b.length;cb();}});
   await pipeSyntheticArchiveTo({mode:'synthetic',key,fd,writable:output,signal:null});assert.equal(received,total);assert.equal(h.digest('hex'),sourceDigest);
  }finally{closeSync(fd);}});
  await t.test('rejects wrong key, modified ciphertext, tag, context and truncated archive',async()=>{const original=readFileSync(path);let i=0;
   for(const [change,expected] of [[b=>{b[100]^=1;},'archive_authentication_failed'],[b=>{b[b.length-1]^=1;},'archive_authentication_failed'],[b=>{b[30]^=1;},'archive_context_refused']]){
    const b=Buffer.from(original);change(b);const p=join(root,'bad-'+i++);writeFileSync(p,b,{mode:0o600});const fd=openSync(p,'r');try{await assert.rejects(authenticateSyntheticArchive({mode:'synthetic',key,fd,signal:null}),code(expected));}finally{closeSync(fd);}}
   const p=join(root,'truncated');writeFileSync(p,original.subarray(0,original.length-1),{mode:0o600});let fd=openSync(p,'r');try{await assert.rejects(authenticateSyntheticArchive({mode:'synthetic',key,fd,signal:null}),code('archive_authentication_failed'));}finally{closeSync(fd);}
   fd=openSync(path,'r');try{await assert.rejects(authenticateSyntheticArchive({mode:'synthetic',key:randomBytes(32),fd,signal:null}),code('archive_authentication_failed'));}finally{closeSync(fd);}
  });
  await t.test('pre-aborted authentication and early-closing consumers are reported',async()=>{const fd=openSync(path,'r');try{
   const ctl=new AbortController();ctl.abort();await assert.rejects(authenticateSyntheticArchive({mode:'synthetic',key,fd,signal:ctl.signal}),code('aborted'));
   const output=new Writable({write(_b,_e,cb){const e=Error('closed');e.code='EPIPE';cb(e);}});await assert.rejects(pipeSyntheticArchiveTo({mode:'synthetic',key,fd,writable:output,signal:null}),code('consumer_closed_early'));
  }finally{closeSync(fd);}});
  await t.test('a stalled inspection pipe is terminated and the child reaped',async()=>{
   const fake=join(root,'hung-restore');writeFileSync(fake,`#!/bin/sh\nexec '${process.execPath.replaceAll("'","'\\''")}' -e 'process.on("SIGTERM",()=>{});process.stdin.pause();setInterval(()=>{},1000)'\n`,{mode:0o700});
   const original=ChildProcess.prototype.kill,signals=[];let pid;
   ChildProcess.prototype.kill=function(sig){if(this.spawnfile===fake){pid=this.pid;signals.push(sig);}return original.call(this,sig);};
   const fd=openSync(path,'r');try{await assert.rejects(syntheticBoundTestHelpers.inspect(fd,key,fake,null),e=>e instanceof BoundBackupError&&e.code==='inspection_timed_out');
    assert(signals.includes('SIGTERM'));assert(signals.includes('SIGKILL'));assert.throws(()=>process.kill(pid,0),e=>e.code==='ESRCH');
   }finally{ChildProcess.prototype.kill=original;closeSync(fd);}
  });
 }finally{key.fill(0);rmSync(root,{recursive:true,force:true});}
});
