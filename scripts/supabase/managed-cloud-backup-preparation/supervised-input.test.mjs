import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {chmodSync,linkSync,mkdtempSync,rmSync,symlinkSync,unlinkSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {InputError,dispatchManagedBackup,readSyntheticPrivateKey,readSyntheticPrivatePassword} from './supervised-input.mjs';
const code=x=>e=>e instanceof InputError&&e.code===x;
test('private synthetic input is independently supervised',{timeout:15000},async t=>{
 const root=mkdtempSync('/private/tmp/collect-input-fixture-'),path=join(root,'secret'),secret=Buffer.from('synthetic:private\\secret');
 const options=(changes={})=>({mode:'synthetic',path,signal:null,testHang:false,...changes});
 try{
  writeFileSync(path,secret,{mode:0o600});
  await t.test('managed dispatch and input reject before accessing credentials',async()=>{let reads=0;const o={mode:'managed'};Object.defineProperty(o,'path',{get(){reads++;throw Error();}});
   await assert.rejects(readSyntheticPrivatePassword(o),code('managed_execution_closed'));await assert.rejects(dispatchManagedBackup(o),code('managed_execution_closed'));assert.equal(reads,0);});
  await t.test('reads only the exact bytes of a private regular file',async()=>{const b=await readSyntheticPrivatePassword(options());assert(b.equals(secret));b.fill(0);});
  await t.test('key input is exactly 32 bytes and accepts arbitrary binary bytes',async()=>{const p=join(root,'key');const raw=Buffer.alloc(32);raw[2]=10;writeFileSync(p,raw,{mode:0o600});const b=await readSyntheticPrivateKey(options({path:p}));assert(b.equals(raw));b.fill(0);
   await assert.rejects(readSyntheticPrivateKey(options()),code('private_input_refused'));});
  await t.test('refuses public modes, symlinks, hard links, FIFOs, empty and newline files',async()=>{
   chmodSync(path,0o644);try{await assert.rejects(readSyntheticPrivatePassword(options()),code('private_input_refused'));}finally{chmodSync(path,0o600);}
   const sym=join(root,'link');symlinkSync(path,sym);try{await assert.rejects(readSyntheticPrivatePassword(options({path:sym})),code('private_input_refused'));}finally{unlinkSync(sym);}
   const hard=join(root,'hard');linkSync(path,hard);try{await assert.rejects(readSyntheticPrivatePassword(options()),code('private_input_refused'));}finally{unlinkSync(hard);}
   const fifo=join(root,'fifo');assert.equal(spawnSync('/usr/bin/mkfifo',[fifo],{stdio:'ignore'}).status,0);try{await assert.rejects(readSyntheticPrivatePassword(options({path:fifo})),code('private_input_refused'));}finally{unlinkSync(fifo);}
   const empty=join(root,'empty');writeFileSync(empty,'',{mode:0o600});await assert.rejects(readSyntheticPrivatePassword(options({path:empty})),code('private_input_refused'));
   const newline=join(root,'newline');writeFileSync(newline,'synthetic\n',{mode:0o600});await assert.rejects(readSyntheticPrivatePassword(options({path:newline})),code('private_input_refused'));
  });
  await t.test('pre-abort and a stalled worker fail without indefinite input wait',async()=>{
   const ctl=new AbortController();ctl.abort();await assert.rejects(readSyntheticPrivatePassword(options({signal:ctl.signal})),code('aborted'));
   const start=Date.now();await assert.rejects(readSyntheticPrivatePassword(options({testHang:true})),code('input_timed_out'));assert(Date.now()-start<4000);
  });
 }finally{secret.fill(0);rmSync(root,{recursive:true,force:true});}
});
