// Regressions exercise actual synthetic postgres processes, never live clusters.
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {existsSync,lstatSync,mkdtempSync,readFileSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {resolvePg17Bin} from './owned-pg17.mjs';

const bin=resolvePg17Bin(),supervisor=join(import.meta.dirname,'fixture-supervisor.mjs');
const wait=(promise,ms)=>new Promise((resolve,reject)=>{
 const timer=setTimeout(()=>reject(Error('fixture supervisor timeout')),ms);
 promise.then(value=>{clearTimeout(timer);resolve(value);},error=>{clearTimeout(timer);reject(error);});
});
function launch(mode,t,binOverride=bin){
 const child=spawn(process.execPath,[supervisor,mode],{stdio:['ignore','pipe','pipe'],env:{PATH:process.env.PATH??'/usr/bin:/bin',COLLECT_SYNTHETIC_PG_BIN:binOverride}});
 const events=[],listeners=[];let partial='';
 child.stdout.on('data',bytes=>{partial+=bytes.toString();let at;
  while((at=partial.indexOf('\n'))>=0){const line=partial.slice(0,at);partial=partial.slice(at+1);let value;try{value=JSON.parse(line);}catch{continue;}
   events.push(value);for(const listener of [...listeners])if(listener.phase===value.phase){listeners.splice(listeners.indexOf(listener),1);listener.resolve(value);}}
 });
 let stderr='';child.stderr.on('data',b=>{stderr+=b.toString();});
 const closed=new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(code,signal)=>resolve({code,signal}));});
 t.after(async()=>{if(child.exitCode===null&&child.signalCode===null){child.kill('SIGTERM');await wait(closed,15000);}});
 return {child,events,closed,get stderr(){return stderr;},phase(name){const found=events.find(x=>x.phase===name);return found?Promise.resolve(found):wait(new Promise(resolve=>listeners.push({phase:name,resolve})),25000);}};
}
function dead(pid){if(!Number.isSafeInteger(pid)||pid<2)return false;try{process.kill(pid,0);return false;}catch(e){return e?.code==='ESRCH';}}
async function removeOnlyAfterIndependentStop(root,pid){
 const base=process.platform==='darwin'?'/private/tmp':'/tmp';
 assert.equal(dirname(root),realpathSync(base));assert.match(root,/\/collect-pg-transfer-[A-Za-z0-9]+$/);
 if(!existsSync(root)){assert.equal(dead(pid),true);return;}
 assert.equal(lstatSync(root).isSymbolicLink(),false);assert.equal(dead(pid),true);
 // A signaled test runner may exit while its child is finishing the already
 // confirmed recursive removal; let that removal complete before inspecting.
 for(let i=0;i<20&&existsSync(root)&&!existsSync(join(root,'db','PG_VERSION'));i++)await new Promise(resolve=>setTimeout(resolve,25));
 if(!existsSync(root))return;
 assert.equal(existsSync(join(root,'db','postmaster.pid')),false);
 const status=spawnSync(join(bin,'pg_ctl'),['-D',join(root,'db'),'status'],{stdio:'ignore',timeout:5000});
 if(status.status!==3)for(let i=0;i<20&&existsSync(root);i++)await new Promise(resolve=>setTimeout(resolve,25));
 if(!existsSync(root))return;
 assert.equal(status.status,3);rmSync(root,{recursive:true,force:true});
}

function launchNodeTestRunner(t,startup=false){
 const fixtureCase=join(import.meta.dirname,'runner-signal-fixture.case.mjs');
 const child=spawn(process.execPath,['--test',fixtureCase],{stdio:['ignore','pipe','pipe'],env:{PATH:process.env.PATH??'/usr/bin:/bin',COLLECT_SYNTHETIC_PG_BIN:bin,COLLECT_FIXTURE_STARTUP_GATE:startup?'1':'0'}});
 let partial='';const event=new Promise((resolve,reject)=>{
  child.stdout.on('data',bytes=>{partial+=bytes.toString();let end;
   while((end=partial.indexOf('\n'))>=0){const line=partial.slice(0,end);partial=partial.slice(end+1);const at=line.indexOf('FIXTURE_EVENT ');
    if(at>=0){try{const value=JSON.parse(line.slice(at+'FIXTURE_EVENT '.length));if(value.phase===(startup?'server_spawned':'ready'))resolve(value);}catch{}}}
  });child.once('error',reject);
 });
 child.stderr.resume();const closed=new Promise((resolve,reject)=>{child.once('error',reject);child.once('close',(code,signal)=>resolve({code,signal}));});
 t.after(async()=>{if(child.exitCode===null&&child.signalCode===null){child.kill('SIGTERM');await wait(closed,15000);}});
 return {child,event:wait(event,25000),closed};
}

for(const signal of ['SIGTERM','SIGINT'])test(`${signal} stops a confirmed server before removing its fixture`,{timeout:40000},async t=>{
 const p=launch('ready',t);const ready=await p.phase('ready');p.child.kill(signal);
 const exit=await wait(p.closed,20000);assert.equal(exit.code,signal==='SIGINT'?130:143);
 assert.equal(dead(ready.pid),true);assert.equal(existsSync(ready.root),false);
});

for(const signal of ['SIGTERM','SIGINT'])test(`${signal} during unconfirmed startup stops the owned process and retains the directory`,{timeout:40000},async t=>{
 const p=launch('startup-signal',t),started=await p.phase('server_spawned');p.child.kill(signal);
 const exit=await wait(p.closed,20000);assert.equal(exit.code,signal==='SIGINT'?130:143);assert.equal(existsSync(started.root),true);
 await removeOnlyAfterIndependentStop(started.root,started.pid);
});

test('failed startup acknowledgement retains the directory even after the server exits',{timeout:40000},async t=>{
 const p=launch('startup-failure',t),started=await p.phase('server_spawned'),failed=await p.phase('failed');
 assert.equal(failed.code,'fixture_start_unconfirmed');assert.equal(failed.root,started.root);assert.equal((await wait(p.closed,20000)).code,0);
 assert.equal(existsSync(started.root),true);await removeOnlyAfterIndependentStop(started.root,started.pid);
});

test('unconfirmed stop preserves its directory until separately verified',{timeout:40000},async t=>{
 const p=launch('stop-unconfirmed',t),ready=await p.phase('ready'),closed=await p.phase('closed');
 assert.equal(closed.removed,false);assert.equal(closed.root,ready.root);assert.equal((await wait(p.closed,20000)).code,0);
 assert.equal(existsSync(ready.root),true);await removeOnlyAfterIndependentStop(ready.root,ready.pid);
});

for(const signal of ['SIGTERM','SIGINT'])test(`${signal} while initdb is running forwards cancellation before cleanup`,{timeout:40000},async t=>{
 // The controlled stub never starts a backend, making independent cleanup
 // possible; the fixture must still retain its root after interrupted initdb.
 const base=process.platform==='darwin'?'/private/tmp':'/tmp',fake=mkdtempSync(join(base,'collect-fixture-bin-'));
 const quote=s=>"'"+s.replaceAll("'","'\\''")+"'";
 for(const name of ['postgres','pg_ctl','pg_isready'])writeFileSync(join(fake,name),'#!/bin/sh\nexec '+quote(join(bin,name))+' "$@"\n',{mode:0o700});
 writeFileSync(join(fake,'initdb'),`#!/bin/sh
/bin/sleep 60 &
child=$!
printf '%s' "$child" > "$TMPDIR/bootstrap-child.pid"
trap 'wait "$child" 2>/dev/null; exit 143' TERM INT
wait "$child"
`,{mode:0o700});
 const p=launch('initdb-signal',t,fake);
 try{
  const started=await p.phase('initdb_spawned'),marker=join(started.root,'bootstrap-child.pid');
  for(let i=0;i<100&&!existsSync(marker);i++)await new Promise(resolve=>setTimeout(resolve,10));
  assert.equal(existsSync(marker),true);const nested=Number(readFileSync(marker,'utf8'));
  assert.equal(dead(started.pid),false);assert.equal(dead(nested),false);p.child.kill(signal);
  assert.equal((await wait(p.closed,20000)).code,signal==='SIGINT'?130:143);assert.equal(dead(started.pid),true);assert.equal(dead(nested),true);
  assert.equal(existsSync(started.root),true);assert.equal(existsSync(join(started.root,'db')),false);
  assert.equal(p.events.some(x=>x.phase==='server_spawned'),false);rmSync(started.root,{recursive:true,force:true});
 }finally{
  if(p.child.exitCode===null&&p.child.signalCode===null){p.child.kill('SIGTERM');await wait(p.closed,15000);}
  rmSync(fake,{recursive:true,force:true});
 }
});

for(const signal of ['SIGTERM','SIGINT'])test(`node --test forwards ${signal} to the owned fixture`,{timeout:45000},async t=>{
 const p=launchNodeTestRunner(t),ready=await p.event;p.child.kill(signal);await wait(p.closed,20000);
 const deadline=Date.now()+10000;while(!dead(ready.pid)&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,50));
 if(!dead(ready.pid)){
  // Do not kill an unrelated/reused PID: require the private fixture PID file
  // still binds the same child before attempting synthetic-server cleanup.
  throw Error('node test runner did not confirm fixture server shutdown; fixture retained');
 }
 if(existsSync(ready.root))await removeOnlyAfterIndependentStop(ready.root,ready.pid);
});

for(const signal of ['SIGTERM','SIGINT'])test(`node --test forwards ${signal} during unconfirmed server startup`,{timeout:45000},async t=>{
 const p=launchNodeTestRunner(t,true),started=await p.event;p.child.kill(signal);await wait(p.closed,20000);
 const deadline=Date.now()+10000;while(!dead(started.pid)&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,50));
 assert.equal(dead(started.pid),true);assert.equal(existsSync(started.root),true);
 await removeOnlyAfterIndependentStop(started.root,started.pid);
});
