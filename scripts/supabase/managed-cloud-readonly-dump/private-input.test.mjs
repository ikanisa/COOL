import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {appendFileSync,chmodSync,linkSync,mkdtempSync,renameSync,rmSync,symlinkSync,unlinkSync,utimesSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {InputError,readPrivateKey,readPrivatePassword} from './private-input.mjs';
const code=x=>e=>e instanceof InputError&&e.code===x;
test('private synthetic input is independently supervised',{timeout:15000},async t=>{
 const root=mkdtempSync('/private/tmp/collect-input-fixture-'),path=join(root,'secret'),secret=Buffer.from('synthetic:private\\secret');
 const options=(changes={})=>({mode:'synthetic',path,signal:null,testHang:false,...changes});
 try{
  writeFileSync(path,secret,{mode:0o600});
  await t.test('managed input rejects synthetic hang injection',async()=>{await assert.rejects(readPrivatePassword(options({mode:'managed',testHang:true})),code('invalid_input'));});
  await t.test('managed input refuses the synthetic read gate before returning bytes',async()=>{
   const child=spawn(process.execPath,[fileURLToPath(new URL('./private-input-worker.mjs',import.meta.url))],{stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});let output=0;
   child.stdout.on('data',b=>{output+=b.length;b.fill(0);});const closed=new Promise(resolve=>child.once('close',(status,signal)=>resolve({status,signal})));
   child.stdin.end(JSON.stringify({mode:'managed',path,kind:'password',testPauseAfterRead:true}));assert.deepEqual(await closed,{status:2,signal:null});assert.equal(output,0);
  });
  await t.test('reads only the exact bytes of a private regular file',async()=>{const b=await readPrivatePassword(options());assert(b.equals(secret));b.fill(0);});
  await t.test('removes at most one final LF or CRLF and preserves spaces',async()=>{
   const p=join(root,'line-password');for(const eol of ['\n','\r\n']){writeFileSync(p,'  synthetic secret  '+eol,{mode:0o600});const b=await readPrivatePassword(options({path:p}));assert.equal(b.toString(),'  synthetic secret  ');b.fill(0);}
   for(const bad of ['\n','\r\n','synthetic\r','synthetic\n\n','synthetic\r\n\r\n','synthetic\nnext','synthetic\rnext','synthetic\0secret']){
    writeFileSync(p,bad,{mode:0o600});await assert.rejects(readPrivatePassword(options({path:p})),code('private_input_refused'));
   }
  });
  await t.test('rejects file growth, edit or replacement during a read without releasing bytes',async()=>{
   for(const mutate of [p=>appendFileSync(p,'more'),p=>{writeFileSync(p,'abcdefghij');utimesSync(p,0,0);},p=>{renameSync(p,p+'.old');writeFileSync(p,'0123456789',{mode:0o600});}]){
    const p=join(root,'racing');writeFileSync(p,'0123456789',{mode:0o600});
    const child=spawn(process.execPath,[fileURLToPath(new URL('./private-input-worker.mjs',import.meta.url))],{stdio:['pipe','pipe','ignore','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
    let output=0;child.stdout.on('data',b=>{output+=b.length;b.fill(0);});const closed=new Promise(resolve=>child.once('close',(status,signal)=>resolve({status,signal})));
    child.stdio[3].once('data',()=>{mutate(p);child.stdio[3].write('continue');});child.stdin.end(JSON.stringify({mode:'synthetic',path:p,kind:'password',testPauseAfterRead:true}));
    assert.deepEqual(await closed,{status:2,signal:null});assert.equal(output,0);rmSync(p,{force:true});rmSync(p+'.old',{force:true});
   }
  });
  await t.test('key input is exactly 32 bytes and accepts arbitrary binary bytes',async()=>{const p=join(root,'key');const raw=Buffer.alloc(32);raw[2]=10;writeFileSync(p,raw,{mode:0o600});const b=await readPrivateKey(options({path:p}));assert(b.equals(raw));b.fill(0);
   await assert.rejects(readPrivateKey(options()),code('private_input_refused'));});
  await t.test('refuses public modes, symlinks, hard links, FIFOs and empty files',async()=>{
   chmodSync(path,0o644);try{await assert.rejects(readPrivatePassword(options()),code('private_input_refused'));}finally{chmodSync(path,0o600);}
   const sym=join(root,'link');symlinkSync(path,sym);try{await assert.rejects(readPrivatePassword(options({path:sym})),code('private_input_refused'));}finally{unlinkSync(sym);}
   const hard=join(root,'hard');linkSync(path,hard);try{await assert.rejects(readPrivatePassword(options()),code('private_input_refused'));}finally{unlinkSync(hard);}
   const fifo=join(root,'fifo');assert.equal(spawnSync('/usr/bin/mkfifo',[fifo],{stdio:'ignore'}).status,0);try{await assert.rejects(readPrivatePassword(options({path:fifo})),code('private_input_refused'));}finally{unlinkSync(fifo);}
   const empty=join(root,'empty');writeFileSync(empty,'',{mode:0o600});await assert.rejects(readPrivatePassword(options({path:empty})),code('private_input_refused'));
  });
  await t.test('pre-abort and a stalled worker fail without indefinite input wait',async()=>{
   const ctl=new AbortController();ctl.abort();await assert.rejects(readPrivatePassword(options({signal:ctl.signal})),code('aborted'));
   const start=Date.now();await assert.rejects(readPrivatePassword(options({testHang:true})),code('input_timed_out'));assert(Date.now()-start<4000);
  });
 }finally{secret.fill(0);rmSync(root,{recursive:true,force:true});}
});
