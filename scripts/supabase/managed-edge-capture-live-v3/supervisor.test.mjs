import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {createHash,randomUUID} from 'node:crypto';
import {existsSync} from 'node:fs';
import {appendFile,copyFile,mkdtemp,mkdir,readFile,rm,writeFile} from 'node:fs/promises';
import {dirname,join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {planDigest} from './core.mjs';
const sha=b=>createHash('sha256').update(b).digest('hex'),sleep=ms=>new Promise(r=>setTimeout(r,ms));
const supervisor=fileURLToPath(new URL('./supervisor.mjs',import.meta.url)),worker=fileURLToPath(new URL('./worker.mjs',import.meta.url));
async function fixture(fn,behavior='normal',deadline=30000){
 const root=await mkdtemp('/private/tmp/collect-edge-capture-test-'),archive=join(root,'archive'),keys=join(root,'key');await mkdir(archive,{mode:0o700});await mkdir(keys,{mode:0o700});
 const pin=sha(await readFile(new URL('./LIVE-SOURCE-PINS.json',import.meta.url))),plan={format:'collect.edge-capture.plan.v2',scope:'synthetic',operation_id:randomUUID(),archive_dir:archive,key_dir:keys,token_path:null,source_pins_sha256:pin,deadline_ms:deadline,fixture:behavior};
 let complete=false;try{const result=await fn({root,archive,keys,pin,plan});complete=true;return result;}
 finally{if(complete)await rm(root,{recursive:true,force:true});else process.stderr.write('[edge-fixture] unconfirmed fixture retained\n');}
}
function children(pid){const q=spawnSync('/bin/ps',['-axo','pid=,ppid=,command='],{encoding:'utf8',env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});assert.equal(q.status,0);return q.stdout.split('\n').map(s=>s.match(/^\s*(\d+)\s+(\d+)\s+(.*)$/)).filter(Boolean).filter(x=>Number(x[2])===pid&&x[3].includes(worker)).map(x=>Number(x[1]));}
async function started(f,cli){const end=Date.now()+8000;while(Date.now()<end){const p=children(cli.pid);if(existsSync(join(f.archive,'EDGE-CAPTURE-CLAIM.json'))&&p.length===1)return p[0];await sleep(40);}throw Error('fixture worker did not start');}
function launch(f,action='capture'){const c=spawn(process.execPath,[supervisor,action,planDigest(f.plan),f.pin],{stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});let out='';c.stdout.on('data',b=>out+=b);c.stdin.on('error',()=>{});const done=new Promise(resolve=>c.once('close',(code,signal)=>resolve({code,signal,out})));c.stdin.end(JSON.stringify(f.plan));return {c,done};}
const alive=pid=>{try{process.kill(pid,0);return true;}catch(e){return e?.code!=='ESRCH';}};
test('supervised capture, read-only status and authenticated verification preserve proof boundaries',async()=>{
 await fixture(async f=>{const x=await launch(f).done,r=JSON.parse(x.out);assert.equal(x.code,0);assert.equal(r.status,'completed_point_in_time');assert.equal(r.scope,'synthetic');assert.equal(r.retryAuthorized,false);
  const status=await launch(f,'status').done;assert.equal(status.code,1);assert.equal(JSON.parse(status.out).status,'capture_recorded_unverified');
  const checked=await launch(f,'verify').done;assert.equal(checked.code,0);assert.equal(JSON.parse(checked.out).status,'capture_verified_point_in_time');assert.equal(JSON.parse(checked.out).archive_sha256,r.archive_sha256);assert(!checked.out.includes('synthetic-private-source'));
  const wrong={...f,plan:{...f.plan,deadline_ms:31000}};const other=await launch(wrong,'verify').done;assert.equal(other.code,1);assert.equal(JSON.parse(other.out).status,'capture_unconfirmed');
  const p=join(f.archive,f.plan.operation_id+'.edge.gcm'),b=await readFile(p);b[b.length-17]^=1;await writeFile(p,b);b.fill(0);
  const tampered=await launch(f,'verify').done;assert.equal(tampered.code,1);assert.equal(JSON.parse(tampered.out).status,'worker_outcome_unconfirmed');
 });
 await fixture(async f=>{const x=await launch(f).done,r=JSON.parse(x.out);assert.equal(x.code,1);assert.equal(r.status,'worker_outcome_unconfirmed');assert.equal(r.retryAuthorized,false);},'error_body');
});
test('missing claim remains unconfirmed without reading a key or token',async()=>fixture(async f=>{
 for(const action of ['status','verify']){const x=await launch(f,action).done;assert.equal(x.code,1);assert.equal(JSON.parse(x.out).status,'capture_unconfirmed');}
}));
test('deadline terminates a cancellation-ignoring child without authorizing retry',async()=>fixture(async f=>{
 const begin=Date.now(),x=await launch(f).done,r=JSON.parse(x.out);assert.equal(x.code,1);assert.equal(r.status,'deadline_terminated_outcome_unknown');assert.equal(r.retryAuthorized,false);assert(Date.now()-begin<8000);
},'ignore_abort',1000));
test('outer SIGTERM and SIGINT forward cancellation and report an unknown outcome',async()=>{
 for(const signal of ['SIGTERM','SIGINT'])await fixture(async f=>{
  const {c,done}=launch(f);let pid;try{pid=await started(f,c);c.kill(signal);const result=await done;assert.equal(result.code,1);assert.equal(JSON.parse(result.out).status,'interrupted_or_unconfirmed');assert.equal(alive(pid),false);}
  finally{if(c.exitCode===null&&c.signalCode===null)c.kill('SIGKILL');if(pid&&alive(pid))throw Error('fixture worker stop unconfirmed');}
 },'hang');
});
test('parent SIGKILL closes watchdog and an uncooperative synthetic child exits',async()=>fixture(async f=>{
 const {c,done}=launch(f);let pid;try{pid=await started(f,c);c.kill('SIGKILL');const result=await done;assert.equal(result.signal,'SIGKILL');const end=Date.now()+5000;while(alive(pid)&&Date.now()<end)await sleep(40);assert.equal(alive(pid),false);assert(existsSync(join(f.archive,'EDGE-CAPTURE-CLAIM.json')));assert(!existsSync(join(f.archive,'EDGE-CAPTURE-RESULT.json')));}
 finally{if(c.exitCode===null&&c.signalCode===null)c.kill('SIGKILL');if(pid&&alive(pid))throw Error('fixture worker stop unconfirmed');}
},'ignore_abort'));
test('actual managed transport uses fixed GET endpoints under blocked sockets and a fake token',()=>{
 const script=fileURLToPath(new URL('./transport-mock-fixture.mjs',import.meta.url));
 for(const mode of ['success','status_error','project_403','metadata_403','body_json']){const r=spawnSync(process.execPath,[script,mode],{encoding:'utf8',timeout:15000,env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});assert.equal(r.status,0,r.stderr);const body=JSON.parse(r.stdout);assert.equal(body.fixture,'socket-blocked fake token');assert.equal(body.behavior,mode);assert.equal(body.request_count,mode==='success'?10:mode==='metadata_403'?2:mode==='body_json'?3:1);}
});
test('pinned source verification refuses a changed owned fixture file',async()=>{
 const root=await mkdtemp('/private/tmp/collect-edge-source-pins-'),repo='/Volumes/COLLECT-STAGING-20261109/main-source';
 try{const bytes=await readFile(new URL('./LIVE-SOURCE-PINS.json',import.meta.url)),manifest=JSON.parse(bytes),pin=sha(bytes);
  for(const path of Object.keys(manifest.files)){const target=join(root,path);await mkdir(dirname(target),{recursive:true});await copyFile(join(repo,path),target);}
  const target=join(root,'scripts/supabase/managed-edge-capture-live-v3/LIVE-SOURCE-PINS.json');await writeFile(target,bytes);
  const verifier=await import(pathToFileURL(join(root,'scripts/supabase/managed-edge-capture-live-v3/source-pins.mjs')).href);
  assert.equal(await verifier.verifyPinnedSources(pin),true);await appendFile(join(root,'scripts/supabase/managed-edge-capture-live-v3/core.mjs'),'\n// synthetic change\n');
  await assert.rejects(verifier.verifyPinnedSources(pin),e=>e?.code==='SOURCE_PINS_REFUSED');
 }finally{await rm(root,{recursive:true,force:true});}
});
