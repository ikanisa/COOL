import test from 'node:test';
import fs from 'node:fs';
import {syncBuiltinESMExports} from 'node:module';
import assert from 'node:assert/strict';
import {createHash,randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {closeSync,mkdirSync,openSync,readFileSync,readdirSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import pg from '../node_modules/pg/lib/index.js';
import {resolvePg17Bin,startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {authenticateAndInspectArchive} from './archive.mjs';
import {executeReadOnlyDump} from './execute.mjs';
import {readAttempt} from './journal.mjs';
import {openInventory} from './manifest-crypto.mjs';
const {Client}=pg,sha=b=>createHash('sha256').update(b).digest('hex'),id='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',planSha256='d'.repeat(64);
test('read-only dump worker on owned synthetic PostgreSQL',{timeout:90000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_dump_fixture'}),clients=[],key=randomBytes(32);
 const journalRoot=join(f.root,'journal'),artifactRoot=join(f.root,'artifacts'),secrets=join(f.root,'secrets');for(const p of [journalRoot,artifactRoot,secrets])mkdirSync(p,{mode:0o700});
 const passwordPath=join(secrets,'password'),keyPath=join(secrets,'key');writeFileSync(passwordPath,'synthetic:secret',{mode:0o600});writeFileSync(keyPath,key,{mode:0o600});
 async function connect(db='postgres'){const c=new Client({host:f.socket,port:f.port,database:db,user:'fixture_bootstrap'});await c.connect();clients.push(c);return c;}
 try{
  const a=await connect();await a.query('CREATE DATABASE collect_fixture_dump');await a.query('CREATE DATABASE collect_fixture_restore');const source=await connect('collect_fixture_dump');
  await source.query("CREATE SCHEMA app;CREATE SCHEMA private;CREATE SCHEMA auth;CREATE SCHEMA storage;CREATE TABLE app.records(id int PRIMARY KEY);INSERT INTO app.records VALUES(1),(2)");
  const bin=resolvePg17Bin(),hash=n=>sha(readFileSync(join(bin,n))),q={mode:'synthetic',operationId:id,journalRoot,artifactRoot,passwordPath,keyPath,
   dumpToolSha256:hash('pg_dump'),dumpExecutableSha256:hash('.pg_dump-wrapped'),restoreToolSha256:hash('pg_restore'),restoreExecutableSha256:hash('.pg_restore-wrapped'),fixture:{socket:f.socket,port:f.port}};
  await t.test('creates authenticated dump and encrypted snapshot inventory and never authorizes retry',async()=>{
   const result=await executeReadOnlyDump(q,planSha256);assert.equal(result.status,'completed_point_in_time');assert.equal(readAttempt({mode:'synthetic',root:journalRoot,operationId:id,planSha256}).artifactSha256,result.bundleSha256);
   const files=readdirSync(artifactRoot).sort();assert.deepEqual(files,[`backup-${id}.inventory.gcm`,`backup-${id}.pgc.gcm`]);
   const side=readFileSync(join(artifactRoot,files[0]));assert.equal(sha(side),result.inventorySha256);const inventory=openInventory({key,operationId:id,bytes:side});assert.equal(inventory.database,'collect_fixture_dump');assert(inventory.inventory.some(x=>x.schema==='auth'));
   const archive=join(artifactRoot,files[1]),buf=readFileSync(archive),magic=Buffer.byteLength('COLLECTPGBKUP1'),len=buf.readUInt32BE(magic+12),metadata=JSON.parse(buf.subarray(magic+12+4,magic+12+4+len).toString());
   assert.equal(metadata.snapshot_sha256,result.snapshotSha256);assert.equal(sha(buf),result.dumpSha256);assert(!buf.includes(Buffer.from('PGDMP')));assert(!buf.includes(Buffer.from('synthetic:secret')));
   const fd=openSync(archive,'r'),restore=spawn(join(bin,'pg_restore'),['--exit-on-error','--no-owner','--no-acl','-h',f.socket,'-p',String(f.port),'-U','fixture_bootstrap','-d','collect_fixture_restore'],{stdio:['pipe','ignore','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C'}});let stderr='';restore.stderr.on('data',b=>stderr+=b);const done=new Promise(resolve=>restore.on('close',(status,signal)=>resolve({status,signal})));
   try{await authenticateAndInspectArchive({fd,key,expectedMetadata:metadata,writable:restore.stdin});assert.deepEqual(await done,{status:0,signal:null},stderr);}finally{closeSync(fd);}
   const restored=await connect('collect_fixture_restore');assert.deepEqual((await restored.query('SELECT id FROM app.records ORDER BY id')).rows,[{id:1},{id:2}]);
   await assert.rejects(executeReadOnlyDump(q,planSha256));
  });
  await t.test('link-time mutation leaves retained artifacts and an unknown journal outcome',async()=>{
   const jr=join(f.root,'mutation-journal'),ar=join(f.root,'mutation-artifacts');mkdirSync(jr,{mode:0o700});mkdirSync(ar,{mode:0o700});
   const op='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',changed={...q,operationId:op,journalRoot:jr,artifactRoot:ar},original=fs.linkSync;let touched=false;
   fs.linkSync=(src,dst)=>{if(typeof src==='string'&&src.endsWith('.partial')&&!src.endsWith('.inventory.partial')){const fd=fs.openSync(src,'r+');try{const magic=Buffer.byteLength('COLLECTPGBKUP1'),head=Buffer.alloc(magic+16),b=Buffer.alloc(1);assert.equal(fs.readSync(fd,head,0,head.length,0),head.length);const pos=head.length+head.readUInt32BE(magic+12)+1;assert.equal(fs.readSync(fd,b,0,1,pos),1);b[0]^=1;assert.equal(fs.writeSync(fd,b,0,1,pos),1);touched=true;}finally{fs.closeSync(fd);}}return original(src,dst);};syncBuiltinESMExports();
   try{await assert.rejects(executeReadOnlyDump(changed,planSha256));assert.equal(touched,true);assert.equal(readAttempt({mode:'synthetic',root:jr,operationId:op,planSha256}).status,'outcome_unknown');
    const files=readdirSync(ar);assert(files.some(x=>x.endsWith('.partial')));assert(files.some(x=>x.endsWith('.pgc.gcm')));
   }finally{fs.linkSync=original;syncBuiltinESMExports();}
  });
 }finally{await Promise.allSettled(clients.map(c=>c.end()));key.fill(0);const r=await f.close();assert.equal(r.removed,true);}
});
