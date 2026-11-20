import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash,randomUUID} from 'node:crypto';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import pg from '../../node_modules/pg/lib/index.js';
import {withOwnedArchiveFixture} from '../../managed-migration-next/synthetic-fixture.mjs';
import {beginCapture,bindOwnedActor,readCapture} from './journal.mjs';
import {startSyntheticCapture,reconcileSyntheticCapture,managedCaptureV3} from './runner.mjs';
const sha=x=>createHash('sha256').update(x).digest('hex'),pause=ms=>new Promise(r=>setTimeout(r,ms));
const code=x=>e=>e?.captureCode===x;
async function manifest(){return sha(await readFile(new URL('./SOURCE-PINS.json',import.meta.url)));}
function child(){return spawn('/bin/sleep',['30'],{detached:true,stdio:['ignore','ignore','ignore']});}
function closed(c){return new Promise(resolve=>c.once('close',resolve));}

test('managed capture v3 refuses before accessing credentials',async()=>{
 let read=false;await assert.rejects(managedCaptureV3({get secret(){read=true;return 'synthetic';}}),code('MANAGED_CAPTURE_UNQUALIFIED'));assert.equal(read,false);
});

test('capture intent is one-use and incomplete actor/backend evidence never proves closure',{timeout:30000},async()=>{
 await withOwnedArchiveFixture(async f=>{
  const racingRoot=join(f.fixtureRoot,'v3-racing');await mkdir(racingRoot,{mode:0o700});const racePin=await manifest();
  const race=await Promise.allSettled([beginCapture(racingRoot,racePin),beginCapture(racingRoot,racePin)]);
  assert.equal(race.filter(x=>x.status==='fulfilled').length,1);assert.equal(race.filter(x=>x.status==='rejected'&&x.reason?.captureCode==='CAPTURE_ALREADY_ATTEMPTED').length,1);
  const root=join(f.fixtureRoot,'v3-missing');await mkdir(root,{mode:0o700});const pin=await manifest(),job=await beginCapture(root,pin);
  await assert.rejects(beginCapture(root,pin),code('CAPTURE_ALREADY_ATTEMPTED'));
  const c=child(),done=closed(c),confirm=await bindOwnedActor(job,c);process.kill(-c.pid,'SIGTERM');await done;assert.equal(await confirm(),true);
  let called=false;const r=await reconcileSyntheticCapture({root,manifestSha256:pin,connectObserver:()=>{called=true;}});
  assert.equal(r.status,'unknown_do_not_retry');assert.equal(called,false);
  const root2=join(f.fixtureRoot,'v3-no-closure');await mkdir(root2,{mode:0o700});const job2=await beginCapture(root2,pin);
  const c2=child(),done2=closed(c2);await bindOwnedActor(job2,c2);process.kill(-c2.pid,'SIGTERM');await done2;
  // The original supervisor never records an observed group closure.
  const q=await reconcileSyntheticCapture({root:root2,manifestSha256:pin,connectObserver:()=>{throw Error('must not connect');}});
  assert.equal(q.status,'unknown_do_not_retry');
 });
});

test('backend record without the original supervisor closure receipt stays unknown after server exit',{timeout:180000},async()=>{
 await withOwnedArchiveFixture(async f=>{
  const root=join(f.fixtureRoot,'v3-supervisor-crash');await mkdir(root,{mode:0o700});const pin=await manifest(),job=await beginCapture(root,pin),cp=f.owner.connectionParameters;
  const worker=spawn(process.execPath,[new URL('./worker.mjs',import.meta.url).pathname,pin,'synthetic'],{detached:true,stdio:['pipe','pipe','ignore','ipc'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
  worker.stdout.resume();worker.stdin.on('error',()=>{});const done=closed(worker);await bindOwnedActor(job,worker);
  const held=new Promise((resolve,reject)=>{const t=setTimeout(()=>reject(Error('fixture worker did not lock')),8000);worker.on('message',m=>{if(m?.status==='fixture_lock_held'){clearTimeout(t);resolve();}});});
  worker.stdin.end(JSON.stringify({mode:'synthetic',job,holdMs:1800,fixture:{host:cp.host,port:cp.port,database:f.database,executed:f.executed.map(x=>({version:x.version,name:x.name,sha256:x.sha256}))}}));
  await held;const record=JSON.parse(await readFile(join(root,'active-capture','backend.json'),'utf8'));
  process.kill(-worker.pid,'SIGTERM');await done; // Simulate the supervisor failing before it records the observed closure.
  const end=Date.now()+6000;let present=true;while(Date.now()<end&&present){present=(await f.admin.query('SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE pid=$1) p',[record.pid])).rows[0].p;if(present)await pause(50);}
  assert.equal(present,false);let called=false;
  const result=await reconcileSyntheticCapture({root,manifestSha256:pin,connectObserver:()=>{called=true;}});
  assert.equal(result.status,'unknown_do_not_retry');assert.equal(called,false);
 });
});

test('a failed backend-record fsync/create prevents the worker from acquiring a WORK lock',{timeout:180000},async()=>{
 await withOwnedArchiveFixture(async f=>{
  const root=join(f.fixtureRoot,'v3-record-failure');await mkdir(root,{mode:0o700});const pin=await manifest(),job=await beginCapture(root,pin),cp=f.owner.connectionParameters;
  await writeFile(join(job.dir,'backend.json'),'{}',{mode:0o600});
  const worker=spawn(process.execPath,[new URL('./worker.mjs',import.meta.url).pathname,pin,'synthetic'],{detached:true,stdio:['pipe','pipe','ignore','ipc'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
  worker.stdout.resume();worker.stdin.on('error',()=>{});const done=closed(worker);const confirm=await bindOwnedActor(job,worker);let held=false;
  worker.on('message',m=>{if(m?.status==='fixture_lock_held')held=true;});
  worker.stdin.end(JSON.stringify({mode:'synthetic',job,holdMs:1000,fixture:{host:cp.host,port:cp.port,database:f.database,executed:f.executed.map(x=>({version:x.version,name:x.name,sha256:x.sha256}))}}));
  await done;assert.equal(await confirm(),true);assert.equal(held,false);
  const n=(await f.admin.query(`SELECT count(*)::int n FROM pg_locks l JOIN pg_stat_activity a ON a.pid=l.pid
   WHERE a.application_name=$1 AND l.locktype='advisory'`,[job.intent.applicationName])).rows[0].n;assert.equal(n,0);
  const result=await reconcileSyntheticCapture({root,manifestSha256:pin,connectObserver:()=>{throw Error('must not connect');}});
  assert.equal(result.status,'unknown_do_not_retry');
 });
});

test('stopped worker leaves a held server lock unknown until the exact session disappears twice',{timeout:180000},async()=>{
 await withOwnedArchiveFixture(async f=>{
  const {owner,admin,database,backendPid,executed}=f;await admin.query('GRANT pg_read_all_stats TO postgres WITH INHERIT TRUE');
  const root=join(f.fixtureRoot,'v3-delay');await mkdir(root,{mode:0o700});const pin=await manifest(),cp=owner.connectionParameters;
  const fixture={host:cp.host,port:cp.port,database,executed:executed.map(x=>({version:x.version,name:x.name,sha256:x.sha256}))};
  const run=await startSyntheticCapture({root,manifestSha256:pin,fixture,holdMs:3200});
  const held=new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('worker never acquired fixture lock')),8000);run.child.on('message',m=>{if(m?.status==='fixture_lock_held'){clearTimeout(timer);resolve();}});});
  await held;process.kill(-run.child.pid,'SIGTERM');const state=await run.done;assert.equal(state.status,'actor_closed_server_reconciliation_required');
  const record=await readCapture(root,pin),prior=record.backend.pid;
  const active=(await admin.query('SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE pid=$1) a,EXISTS(SELECT 1 FROM pg_locks WHERE pid=$1 AND locktype=$2) l',[prior,'advisory'])).rows[0];
  assert.deepEqual(active,{a:true,l:true});
  let observers=0;async function connectObserver(){observers++;const c=new pg.Client({host:cp.host,port:cp.port,database,user:'postgres',application_name:'fixture_observer_'+randomUUID().slice(0,8)});c.on('error',()=>{});await c.connect();return c;}
  assert.equal((await reconcileSyntheticCapture({root,manifestSha256:pin,connectObserver})).status,'unknown_do_not_retry');
  const end=Date.now()+7000;let present=true;while(Date.now()<end&&present){present=(await admin.query('SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE pid=$1) p',[prior])).rows[0].p;if(present)await pause(50);}
  assert.equal(present,false);
  const started=Date.now();const stalled=await reconcileSyntheticCapture({root,manifestSha256:pin,timeoutMs:1000,connectObserver:()=>new Promise(()=>{})});
  assert.equal(stalled.status,'unknown_do_not_retry');assert.ok(Date.now()-started<3000);
  // Simulate a reused PID: the recorded number now belongs to an unrelated
  // live session. Reconciliation must remain unknown, regardless of start time.
  const other=await connectObserver(),backendFile=join(root,'active-capture','backend.json'),original=await readFile(backendFile,'utf8'),altered=JSON.parse(original);
  try{
   altered.pid=other.processID;await writeFile(backendFile,JSON.stringify(altered));
   assert.equal((await reconcileSyntheticCapture({root,manifestSha256:pin,connectObserver})).status,'unknown_do_not_retry');
   await writeFile(backendFile,original);const wrong=JSON.parse(original);wrong.systemIdentifier='1234567890123456789';await writeFile(backendFile,JSON.stringify(wrong));
   assert.equal((await reconcileSyntheticCapture({root,manifestSha256:pin,connectObserver})).status,'unknown_do_not_retry');
   await writeFile(backendFile,original);const restart=JSON.parse(original);restart.postmasterStart='2000-01-01T00:00:00.000000Z';await writeFile(backendFile,JSON.stringify(restart));
   assert.equal((await reconcileSyntheticCapture({root,manifestSha256:pin,connectObserver})).status,'unknown_do_not_retry');
   await writeFile(backendFile,original);
  }finally{await other.end();}
  const collision=new pg.Client({host:cp.host,port:cp.port,database,user:'postgres',application_name:record.intent.applicationName});collision.on('error',()=>{});await collision.connect();
  try{assert.equal((await reconcileSyntheticCapture({root,manifestSha256:pin,connectObserver})).status,'unknown_do_not_retry');}finally{await collision.end();}
  const result=await reconcileSyntheticCapture({root,manifestSha256:pin,connectObserver});
  assert.deepEqual(result,{status:'actor_and_server_closure_observed',writeAuthorized:false});assert.ok(observers>=5);
  await assert.rejects(startSyntheticCapture({root,manifestSha256:pin,fixture}),code('CAPTURE_ALREADY_ATTEMPTED'));
 });
});
