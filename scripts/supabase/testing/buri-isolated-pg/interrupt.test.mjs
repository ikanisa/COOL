import test from 'node:test';import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp,readdir,realpath,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';

// Run this file directly, not through `node --test`: the process receiving a
// cancellation must wait for its own qualification child to stop its cluster.
let activeChild=null,interrupted=null;
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>{
 if(!interrupted)interrupted=signal;
 if(activeChild)activeChild.kill('SIGTERM');
});

test('SIGTERM during the history suite stops and removes its owned database', {timeout:180000},async()=>{
 assert.equal(process.env.COLLECT_BURI_TEST_PG_QUALIFY,'true');assert.ok(process.env.COLLECT_BURI_TEST_PG_BIN_DIR);
 const parent=await realpath(process.env.COLLECT_BURI_TEST_TMP_ROOT??tmpdir());
 const root=await mkdtemp(join(parent,'collect-buri-signal-test-'));
 let complete=false;
 try{
  const env={PATH:'/usr/bin:/bin',LC_ALL:'C',COLLECT_BURI_TEST_PG_QUALIFY:'true',
   COLLECT_BURI_TEST_PG_BIN_DIR:process.env.COLLECT_BURI_TEST_PG_BIN_DIR,COLLECT_BURI_TEST_TMP_ROOT:root};
  const child=spawn(process.execPath,[fileURLToPath(new URL('./qualify.mjs',import.meta.url))],{env,stdio:['ignore','pipe','pipe']});
  activeChild=child;if(interrupted)child.kill('SIGTERM');
  let output='',signalled=false,timedOut=false;
  const timer=setTimeout(()=>{timedOut=true;child.kill('SIGTERM');},45000);
  child.stdout.on('data',chunk=>{
   output+=chunk.toString();
   if(!signalled&&output.includes('Synthetic PostgreSQL suite started: observation-history')){
    signalled=true;setTimeout(()=>child.kill('SIGTERM'),300);
   }
  });
  child.stderr.resume();
  const result=await new Promise((resolvePromise,reject)=>{
   child.once('error',reject);child.once('close',(code,signal)=>resolvePromise({code,signal}));
  });
  clearTimeout(timer);activeChild=null;
  if(interrupted||timedOut){
   // Only remove the outer directory after the qualification process has
   // handled TERM and confirmed removal of its own PostgreSQL directory.
   if(result.signal===null&&(await readdir(root)).length===0)complete=true;
   throw Error(interrupted?'SYNTHETIC_BURI_INTERRUPT_TEST_INTERRUPTED: '+interrupted:'SYNTHETIC_BURI_INTERRUPT_TEST_TIMED_OUT');
  }
  assert.equal(signalled,true,'history suite must start before interruption');
  assert.notEqual(result.code,0,'an interrupted qualification must not pass');
  assert.equal(result.signal,null,'the harness should handle termination and finish cleanup');
  assert.deepEqual(await readdir(root),[],'the owned cluster must stop before its directory is removed');
  complete=true;
 }finally{if(complete)await rm(root,{recursive:true,force:true});else console.error('Interrupted fixture evidence retained at '+root);}
});
