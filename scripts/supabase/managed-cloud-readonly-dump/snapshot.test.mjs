import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {join} from 'node:path';
import {pipeline} from 'node:stream/promises';
import {Writable} from 'node:stream';
import pg from '../node_modules/pg/lib/index.js';
import {resolvePg17Bin,startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {checkDumpVisibility,cleanManagedEnvironment,openPinnedManagedSnapshot,openSyntheticSnapshot,SnapshotError} from './snapshot.mjs';
const {Client}=pg,code=x=>e=>e instanceof SnapshotError&&e.code===x;
function outcome(c){return new Promise((resolve,reject)=>{c.once('error',reject);c.once('close',(status,signal)=>resolve({status,signal}));});}
test('exported repeatable-read snapshot pins synthetic pg_dump',{timeout:90000},async t=>{
 await t.test('poisoned environments are refused without accessing the password',async()=>{let reads=0;const o={};Object.defineProperty(o,'password',{get(){reads++;throw Error();}});const old=process.env.PGOPTIONS;process.env.PGOPTIONS='-c role=other';
  try{await assert.rejects(openPinnedManagedSnapshot(o),code('managed_environment_refused'));assert.equal(reads,0);assert.equal(cleanManagedEnvironment({PGOPTIONS:'-c role=other'},[]),false);assert.equal(cleanManagedEnvironment({PATH:'/usr/bin:/bin'},[]),true);}
  finally{if(old===undefined)delete process.env.PGOPTIONS;else process.env.PGOPTIONS=old;}});
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_snapshot_fixture'}),clients=[];
 async function connect(db='postgres'){const c=new Client({host:f.socket,port:f.port,database:db,user:'fixture_bootstrap'});await c.connect();clients.push(c);return c;}
 try{
  const admin=await connect();await admin.query('CREATE DATABASE collect_fixture_dump');await admin.query('CREATE DATABASE collect_fixture_restore');
  const source=await connect('collect_fixture_dump');await source.query("CREATE SCHEMA app;CREATE SCHEMA private;CREATE SCHEMA collect_sms;CREATE SCHEMA auth;CREATE SCHEMA storage;CREATE TABLE app.records(id int PRIMARY KEY);CREATE TABLE collect_sms.observations(id int);INSERT INTO app.records VALUES(1)");
  await source.query('CREATE ROLE fixture_limited; GRANT USAGE ON SCHEMA app,private,collect_sms,auth,storage,public TO fixture_limited; GRANT SELECT ON app.records,collect_sms.observations TO fixture_limited');
  const asLimited=async fn=>{await source.query('SET ROLE fixture_limited');try{return await fn();}finally{await source.query('RESET ROLE');}};
  await t.test('refuses missing schema, table and sequence privileges',async()=>{
   assert.equal((await asLimited(()=>checkDumpVisibility(source))).inaccessible_tables,0);
   await source.query('REVOKE USAGE ON SCHEMA private FROM fixture_limited');
   await assert.rejects(asLimited(()=>checkDumpVisibility(source)),code('visibility_preflight_refused'));
   await source.query('GRANT USAGE ON SCHEMA private TO fixture_limited; CREATE TABLE app.hidden(id int)');
   await assert.rejects(asLimited(()=>checkDumpVisibility(source)),code('visibility_preflight_refused'));
   await source.query('GRANT SELECT ON app.hidden TO fixture_limited; CREATE SEQUENCE app.counter');
   await assert.rejects(asLimited(()=>checkDumpVisibility(source)),code('visibility_preflight_refused'));
   await source.query('GRANT SELECT ON SEQUENCE app.counter TO fixture_limited');
   assert.equal((await asLimited(()=>checkDumpVisibility(source))).inaccessible_sequences,0);
   await source.query('DROP TABLE app.hidden; DROP SEQUENCE app.counter');
  });
  await t.test('refuses active row security under the dump role',async()=>{
   await source.query('CREATE TABLE app.protected(id int); ALTER TABLE app.protected ENABLE ROW LEVEL SECURITY; GRANT SELECT ON app.protected TO fixture_limited');
   try{await assert.rejects(asLimited(()=>checkDumpVisibility(source)),code('visibility_preflight_refused'));}
   finally{await source.query('DROP TABLE app.protected');}
  });
  await t.test('refuses selected foreign tables before opening a dump',async()=>{
   await source.query('CREATE FOREIGN DATA WRAPPER fixture_fdw; CREATE SERVER fixture_server FOREIGN DATA WRAPPER fixture_fdw; CREATE FOREIGN TABLE app.remote(id int) SERVER fixture_server');
   try{await assert.rejects(openSyntheticSnapshot({mode:'synthetic',socket:f.socket,port:f.port}),code('visibility_preflight_refused'));}
   finally{await source.query('DROP FOREIGN TABLE app.remote; DROP SERVER fixture_server; DROP FOREIGN DATA WRAPPER fixture_fdw');}
  });
  await t.test('dump imports the same live snapshot and excludes a later committed row',async()=>{
   const snap=await openSyntheticSnapshot({mode:'synthetic',socket:f.socket,port:f.port});let closed=false;
   try{assert.equal(snap.metadata.database,'collect_fixture_dump');assert.equal(snap.metadata.session_user,'fixture_bootstrap');assert.match(snap.metadata.snapshot_sha256,/^[a-f0-9]{64}$/);assert(snap.metadata.inventory.some(x=>x.schema==='app'&&x.kind==='r'));assert(snap.metadata.inventory.some(x=>x.schema==='collect_sms'&&x.kind==='r'));assert.equal(snap.metadata.visibility_preflight.rls_active_tables,0);
    await source.query('INSERT INTO app.records VALUES(2)');await snap.assertAlive();const bin=resolvePg17Bin();
    const dump=spawn(join(bin,'pg_dump'),['--format=custom','--no-password','--snapshot='+snap.snapshotId,'-h',f.socket,'-p',String(f.port),'-U','fixture_bootstrap','-d','collect_fixture_dump'],{stdio:['ignore','pipe','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
    const restore=spawn(join(bin,'pg_restore'),['--exit-on-error','--no-owner','--no-acl','-h',f.socket,'-p',String(f.port),'-U','fixture_bootstrap','-d','collect_fixture_restore'],{stdio:['pipe','ignore','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
    let dumpError='',restoreError='';dump.stderr.on('data',b=>dumpError+=b);restore.stderr.on('data',b=>restoreError+=b);const a=outcome(dump),b=outcome(restore);
    await pipeline(dump.stdout,restore.stdin);assert.deepEqual(await a,{status:0,signal:null},dumpError);assert.deepEqual(await b,{status:0,signal:null},restoreError);
    const restored=await connect('collect_fixture_restore');assert.deepEqual((await restored.query('SELECT id FROM app.records ORDER BY id')).rows,[{id:1}]);
    await snap.close();closed=true;
    const retry=spawn(join(bin,'pg_dump'),['--format=custom','--no-password','--snapshot='+snap.snapshotId,'-h',f.socket,'-p',String(f.port),'-U','fixture_bootstrap','-d','collect_fixture_dump'],{stdio:['ignore','pipe','ignore'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});
    const done=outcome(retry);await pipeline(retry.stdout,new Writable({write(_b,_e,cb){cb();}}));assert.notEqual((await done).status,0);
   }finally{if(!closed)await snap.close();}
  });
 }finally{await Promise.allSettled(clients.map(c=>c.end()));const r=await f.close();assert.equal(r.removed,true);}
});
