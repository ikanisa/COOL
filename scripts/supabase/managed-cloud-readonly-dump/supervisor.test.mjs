import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomBytes} from 'node:crypto';
import childProcess from 'node:child_process';
import {spawn} from 'node:child_process';
import {closeSync,existsSync,mkdirSync,openSync,readFileSync,readdirSync,writeFileSync,writeSync} from 'node:fs';
import {join} from 'node:path';
import {syncBuiltinESMExports} from 'node:module';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';
import pg from '../node_modules/pg/lib/index.js';
import {resolvePg17Bin,startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {authenticateAndInspectArchive} from './archive.mjs';
import {cliExitCode,planDigest,readReviewedDumpStatus,runReviewedDump,verifyReviewedDump} from './supervisor.mjs';
import {readAttempt} from './journal.mjs';
import {openInventory} from './manifest-crypto.mjs';
const {Client}=pg,sha=b=>createHash('sha256').update(b).digest('hex'),id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
test('CLI exit code treats only the completed status as success',()=>{
 assert.equal(cliExitCode({status:'completed_point_in_time'}),0);
 for(const status of ['deadline_terminated_outcome_unknown','interrupted_outcome_unknown','interrupted_before_dispatch','group_stop_unconfirmed','worker_outcome_unconfirmed','acknowledgement_missing_do_not_retry','refused','future_unrecognized_status'])assert.equal(cliExitCode({status}),1);
 assert.equal(cliExitCode(null),1);
});
test('read-only dump worker on owned synthetic PostgreSQL',{timeout:90000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_dump_fixture'}),clients=[],key=randomBytes(32);let retain=false;
 const journalRoot=join(f.root,'journal'),artifactRoot=join(f.root,'artifacts'),secrets=join(f.root,'secrets');for(const p of [journalRoot,artifactRoot,secrets])mkdirSync(p,{mode:0o700});
 const passwordPath=join(secrets,'password'),keyPath=join(secrets,'key');writeFileSync(passwordPath,'synthetic:secret',{mode:0o600});writeFileSync(keyPath,key,{mode:0o600});
 async function connect(db='postgres'){const c=new Client({host:f.socket,port:f.port,database:db,user:'fixture_bootstrap'});await c.connect();clients.push(c);return c;}
 try{
  const a=await connect();await a.query('CREATE DATABASE collect_fixture_dump');await a.query('CREATE DATABASE collect_fixture_restore');const source=await connect('collect_fixture_dump');
  await source.query("CREATE SCHEMA app;CREATE SCHEMA private;CREATE SCHEMA collect_sms;CREATE SCHEMA auth;CREATE SCHEMA storage;CREATE TABLE app.records(id int PRIMARY KEY);CREATE TABLE collect_sms.observations(id int);INSERT INTO app.records VALUES(1),(2)");
  const bin=resolvePg17Bin(),hash=n=>sha(readFileSync(join(bin,n))),q={mode:'synthetic',operationId:id,journalRoot,artifactRoot,passwordPath,keyPath,
   dumpToolSha256:hash('pg_dump'),dumpExecutableSha256:hash('.pg_dump-wrapped'),restoreToolSha256:hash('pg_restore'),restoreExecutableSha256:hash('.pg_restore-wrapped'),fixture:{socket:f.socket,port:f.port}};
  await t.test('creates authenticated dump and encrypted snapshot inventory and never authorizes retry',async()=>{
   const plan={deadlineMs:30000,request:q},pin=planDigest(plan);await assert.rejects(runReviewedDump({plan,expectedPlanSha256:'0'.repeat(64)}));assert.deepEqual(readdirSync(journalRoot),[]);
   const result=await runReviewedDump({plan,expectedPlanSha256:pin});assert.equal(result.status,'completed_point_in_time');assert.equal(result.retryAuthorized,false);assert.equal(result.planSha256,pin);
   assert.deepEqual(await readReviewedDumpStatus({mode:'synthetic',root:journalRoot,operationId:id,expectedPlanSha256:pin,deadlineMs:3000}),{status:'completed',planSha256:pin,bundleSha256:result.bundleSha256,retryAuthorized:false});assert.equal(readAttempt({mode:'synthetic',root:journalRoot,operationId:id,planSha256:pin}).artifactSha256,result.bundleSha256);
   const files=readdirSync(artifactRoot).sort();assert.deepEqual(files,[`backup-${id}.inventory.gcm`,`backup-${id}.pgc.gcm`]);
   const verification={mode:'synthetic',journalRoot,artifactRoot,keyPath,operationId:id,expectedPlanSha256:pin,deadlineMs:30000};
   assert.equal((await verifyReviewedDump(verification)).bundleSha256,result.bundleSha256);
   const side=readFileSync(join(artifactRoot,files[0]));assert.equal(sha(side),result.inventorySha256);const inventory=openInventory({key,operationId:id,bytes:side});assert.equal(inventory.database,'collect_fixture_dump');assert(inventory.inventory.some(x=>x.schema==='auth'));assert(inventory.inventory.some(x=>x.schema==='collect_sms'&&x.kind==='r'));
   const archive=join(artifactRoot,files[1]),buf=readFileSync(archive),magic=Buffer.byteLength('COLLECTPGBKUP1'),len=buf.readUInt32BE(magic+12),metadata=JSON.parse(buf.subarray(magic+12+4,magic+12+4+len).toString());
   assert.equal(metadata.snapshot_sha256,result.snapshotSha256);assert.equal(metadata.plan_sha256,pin);assert.equal(sha(buf),result.dumpSha256);assert(!buf.includes(Buffer.from('PGDMP')));assert(!buf.includes(Buffer.from('synthetic:secret')));
   const fd=openSync(archive,'r'),restore=spawn(join(bin,'pg_restore'),['--exit-on-error','--no-owner','--no-acl','-h',f.socket,'-p',String(f.port),'-U','fixture_bootstrap','-d','collect_fixture_restore'],{stdio:['pipe','ignore','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});let stderr='';restore.stderr.on('data',b=>stderr+=b);const done=new Promise(resolve=>restore.on('close',(status,signal)=>resolve({status,signal})));
   try{await authenticateAndInspectArchive({fd,key,expectedMetadata:metadata,writable:restore.stdin});assert.deepEqual(await done,{status:0,signal:null},stderr);}finally{closeSync(fd);}
   const restored=await connect('collect_fixture_restore');assert.deepEqual((await restored.query('SELECT id FROM app.records ORDER BY id')).rows,[{id:1},{id:2}]);
   const tamper=openSync(archive,'r+'),offset=magic+12+4+len+1,original=buf[offset];try{writeSync(tamper,Buffer.from([original^1]),0,1,offset);
    assert.equal((await verifyReviewedDump(verification)).status,'verification_unavailable_do_not_retry');writeSync(tamper,Buffer.from([original]),0,1,offset);
   }finally{closeSync(tamper);}
   assert.equal((await verifyReviewedDump(verification)).bundleSha256,result.bundleSha256);
   const differentPlan=planDigest({deadlineMs:31000,request:q});assert.notEqual(differentPlan,pin);
   assert.equal((await readReviewedDumpStatus({mode:'synthetic',root:journalRoot,operationId:id,expectedPlanSha256:differentPlan,deadlineMs:3000})).status,'status_unavailable_do_not_retry');
   assert.equal((await verifyReviewedDump({...verification,expectedPlanSha256:differentPlan})).status,'verification_unavailable_do_not_retry');
   assert.equal((await runReviewedDump({plan,expectedPlanSha256:planDigest(plan)})).status,'worker_outcome_unconfirmed');
  });
  await t.test('deadline during a blocked dump leaves dispatch unresolved and does not retry',async()=>{
   const jr=join(f.root,'timeout-journal'),ar=join(f.root,'timeout-artifacts');mkdirSync(jr,{mode:0o700});mkdirSync(ar,{mode:0o700});
   const op='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',q2={...q,operationId:op,journalRoot:jr,artifactRoot:ar},plan={deadlineMs:1000,request:q2};
   await source.query('BEGIN; LOCK TABLE app.records IN ACCESS EXCLUSIVE MODE');
   try{const result=await runReviewedDump({plan,expectedPlanSha256:planDigest(plan)});if(result.status==='group_stop_unconfirmed')retain=true;
    assert.equal(result.status,'deadline_terminated_outcome_unknown');assert.equal(result.retryAuthorized,false);
   }finally{await source.query('ROLLBACK');}
   const status=await readReviewedDumpStatus({mode:'synthetic',root:jr,operationId:op,expectedPlanSha256:planDigest(plan),deadlineMs:3000});assert(['dispatch_intent','outcome_unknown'].includes(status.status));assert.equal(status.retryAuthorized,false);
  });
  await t.test('a lost completion acknowledgement is reconciled without redispatch',async()=>{
   const jr=join(f.root,'lost-ack-journal'),ar=join(f.root,'lost-ack-artifacts');mkdirSync(jr,{mode:0o700});mkdirSync(ar,{mode:0o700});
   const op='cccccccc-cccc-4ccc-8ccc-cccccccccccc',q2={...q,operationId:op,journalRoot:jr,artifactRoot:ar},plan={deadlineMs:30000,request:q2},pin=planDigest(plan);
   const child=spawn(process.execPath,[new URL('./lost-ack-fixture-worker.mjs',import.meta.url).pathname],{stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
   let response='';child.stdout.on('data',b=>response+=b);const closed=new Promise(resolve=>child.once('close',(status,signal)=>resolve({status,signal})));
   child.stdin.end(JSON.stringify({request:q2,planSha256:pin}));assert.deepEqual(await closed,{status:0,signal:null});assert.equal(response,'');
   const status=await readReviewedDumpStatus({mode:'synthetic',root:jr,operationId:op,expectedPlanSha256:pin,deadlineMs:3000});assert.equal(status.status,'completed');assert.equal(status.retryAuthorized,false);
   const verified=await verifyReviewedDump({mode:'synthetic',journalRoot:jr,artifactRoot:ar,keyPath,operationId:op,expectedPlanSha256:pin,deadlineMs:30000});assert.equal(verified.bundleSha256,status.bundleSha256);assert.equal(verified.retryAuthorized,false);
   const differentPin=planDigest({...plan,deadlineMs:31000});assert.equal((await readReviewedDumpStatus({mode:'synthetic',root:jr,operationId:op,expectedPlanSha256:differentPin,deadlineMs:3000})).status,'status_unavailable_do_not_retry');
   assert.equal((await runReviewedDump({plan,expectedPlanSha256:pin})).status,'worker_outcome_unconfirmed');
  });
  await t.test('outer CLI TERM and INT stop the owned group and leave a no-retry outcome',async()=>{
   for(const [signal,op] of [['SIGTERM','dddddddd-dddd-4ddd-8ddd-dddddddddddd'],['SIGINT','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee']]){
    const jr=join(f.root,'signal-'+signal+'-journal'),ar=join(f.root,'signal-'+signal+'-artifacts');mkdirSync(jr,{mode:0o700});mkdirSync(ar,{mode:0o700});
    const request={...q,operationId:op,journalRoot:jr,artifactRoot:ar},plan={deadlineMs:30000,request},pin=planDigest(plan);
    await source.query('BEGIN; LOCK TABLE app.records IN ACCESS EXCLUSIVE MODE');
    const child=spawn(process.execPath,[fileURLToPath(new URL('./supervisor.mjs',import.meta.url)),pin],{stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});let out='';
    child.stdout.on('data',b=>out+=b);const closed=new Promise(resolve=>child.once('close',(status,termination)=>resolve({status,signal:termination})));
    try{
     child.stdin.end(JSON.stringify(plan));const end=Date.now()+10000;let waiting=false;
     while(Date.now()<end){try{const st=readAttempt({mode:'synthetic',root:jr,operationId:op,planSha256:pin});if(st.status==='dispatch_intent'){
      const r=await a.query("SELECT count(*)::int AS n FROM pg_catalog.pg_stat_activity WHERE datname='collect_fixture_dump' AND wait_event_type='Lock'");if(r.rows[0].n>0){waiting=true;break;}
     }}catch{}await delay(25);}
     assert.equal(waiting,true,`fixture did not reach a database lock for ${signal}`);child.kill(signal);
     assert.deepEqual(await closed,{status:1,signal:null});const result=JSON.parse(out);assert.equal(result.status,'interrupted_outcome_unknown');assert.equal(result.retryAuthorized,false);
     const status=await readReviewedDumpStatus({mode:'synthetic',root:jr,operationId:op,expectedPlanSha256:pin,deadlineMs:3000});assert(['dispatch_intent','outcome_unknown'].includes(status.status));assert.equal(status.retryAuthorized,false);
    }finally{await source.query('ROLLBACK');if(child.exitCode===null&&child.signalCode===null){child.kill('SIGKILL');retain=true;}}
   }
  });
  await t.test('outer CLI interruption during an unfinished plan closes promptly',async()=>{
   const child=spawn(process.execPath,[fileURLToPath(new URL('./supervisor.mjs',import.meta.url)),'0'.repeat(64)],{stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});let out='';child.stdout.on('data',b=>out+=b);
   const closed=new Promise(resolve=>child.once('close',(status,signal)=>resolve({status,signal})));await delay(300);const started=Date.now();child.kill('SIGTERM');
   assert.deepEqual(await closed,{status:1,signal:null});assert(Date.now()-started<2000);assert.equal(JSON.parse(out).status,'refused');
  });
  await t.test('actual CLI exits zero for a completed dump and nonzero for a deadline or refused worker',async()=>{
   const cli=async plan=>{const pin=planDigest(plan),child=spawn(process.execPath,[fileURLToPath(new URL('./supervisor.mjs',import.meta.url)),pin],{stdio:['pipe','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});let out='';child.stdout.on('data',b=>out+=b);
    const closed=new Promise(resolve=>child.once('close',(status,signal)=>resolve({status,signal})));child.stdin.end(JSON.stringify(plan));const exit=await closed;return {exit,body:JSON.parse(out)};};
   const roots=tag=>{const jr=join(f.root,tag+'-journal'),ar=join(f.root,tag+'-artifacts');mkdirSync(jr,{mode:0o700});mkdirSync(ar,{mode:0o700});return {journalRoot:jr,artifactRoot:ar};};
   const ok={deadlineMs:30000,request:{...q,...roots('exit-ok'),operationId:'11111111-1111-4111-8111-111111111111'}};
   const completed=await cli(ok);assert.deepEqual(completed.exit,{status:0,signal:null});assert.equal(completed.body.status,'completed_point_in_time');
   const bad={deadlineMs:30000,request:{...q,...roots('exit-invalid'),operationId:'22222222-2222-4222-8222-222222222222',unexpected:true}};
   const refused=await cli(bad);assert.deepEqual(refused.exit,{status:1,signal:null});assert.equal(refused.body.status,'worker_outcome_unconfirmed');
   const timeout={deadlineMs:1000,request:{...q,...roots('exit-timeout'),operationId:'33333333-3333-4333-8333-333333333333'}};
   await source.query('BEGIN; LOCK TABLE app.records IN ACCESS EXCLUSIVE MODE');
   try{const timed=await cli(timeout);assert.deepEqual(timed.exit,{status:1,signal:null});assert.equal(timed.body.status,'deadline_terminated_outcome_unknown');assert.equal(timed.body.retryAuthorized,false);}
   finally{await source.query('ROLLBACK');}
   const status=await readReviewedDumpStatus({mode:'synthetic',root:timeout.request.journalRoot,operationId:timeout.request.operationId,expectedPlanSha256:planDigest(timeout),deadlineMs:3000});assert(['dispatch_intent','outcome_unknown'].includes(status.status));
  });
  await t.test('bounded escalation stops a TERM-ignoring owned descendant while its leader is alive',async()=>{
   const marker=join(f.root,'held-grandchild.pid'),grandchild=join(f.root,'held-grandchild.mjs'),leader=join(f.root,'held-leader.mjs');
   writeFileSync(grandchild,`import {writeFileSync} from 'node:fs';\nprocess.on('SIGTERM',()=>{});writeFileSync(${JSON.stringify(marker)},String(process.pid));setInterval(()=>{},1000);\n`,{mode:0o600});
   writeFileSync(leader,`import {spawn} from 'node:child_process';\nprocess.on('SIGTERM',()=>{});spawn(process.execPath,[${JSON.stringify(grandchild)}],{stdio:'ignore'});setInterval(()=>{},1000);\n`,{mode:0o600});
   const original=childProcess.spawn;let ownedLeader,grandchildPid;
   childProcess.spawn=(command,args,options)=>{if(!String(args?.[0]).endsWith('/managed-cloud-readonly-dump/worker.mjs'))throw Error('unexpected fixture spawn');ownedLeader=original(command,[leader],options);return ownedLeader;};syncBuiltinESMExports();
   try{
    const ctl=new AbortController(),plan={deadlineMs:30000,request:{mode:'synthetic',operationId:'ffffffff-ffff-4fff-8fff-ffffffffffff'}},run=runReviewedDump({plan,expectedPlanSha256:planDigest(plan),signal:ctl.signal});
    const end=Date.now()+10000;while(!existsSync(marker)&&Date.now()<end)await delay(25);assert.equal(existsSync(marker),true);grandchildPid=Number(readFileSync(marker,'utf8'));assert(Number.isSafeInteger(grandchildPid)&&grandchildPid>1);
    ctl.abort();const result=await run;assert.equal(result.status,'interrupted_outcome_unknown');assert.equal(result.retryAuthorized,false);
    assert.throws(()=>process.kill(grandchildPid,0),e=>e.code==='ESRCH');
   }finally{
    childProcess.spawn=original;syncBuiltinESMExports();
    if(ownedLeader?.exitCode===null&&ownedLeader.signalCode===null){try{ownedLeader.kill('SIGKILL');}catch{}retain=true;}
    if(grandchildPid){try{process.kill(grandchildPid,0);retain=true;}catch{}}
   }
  });
 }finally{await Promise.allSettled(clients.map(c=>c.end()));key.fill(0);if(retain)process.stderr.write(`[dump-fixture] retained unconfirmed fixture ${f.root}\n`);else{const r=await f.close();assert.equal(r.removed,true);}}
});
