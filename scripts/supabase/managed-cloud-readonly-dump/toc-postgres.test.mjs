import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash,randomBytes} from 'node:crypto';
import {mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import pg from '../node_modules/pg/lib/index.js';
import {resolvePg17Bin,startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {createTocScanner} from './toc.mjs';
import {planDigest,runReviewedDump} from './supervisor.mjs';
function outcome(c){return new Promise((resolve,reject)=>{c.once('error',reject);c.once('close',(code,signal)=>resolve({code,signal}));});}
test('a real owned pg_restore TOC larger than 512 KiB is streamed and checked',{timeout:180000},async()=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_toc_fixture'});let admin,source;
 try{
  admin=new pg.Client({host:f.socket,port:f.port,user:'fixture_bootstrap',database:'postgres'});await admin.connect();await admin.query('CREATE DATABASE collect_fixture_dump');
  source=new pg.Client({host:f.socket,port:f.port,user:'fixture_bootstrap',database:'collect_fixture_dump'});await source.connect();
  await source.query(`CREATE SCHEMA app;DO $test$ BEGIN FOR i IN 1..3600 LOOP EXECUTE format('CREATE TABLE app.%I(id integer)', 'synthetic_'||lpad(i::text,4,'0')||repeat('x',40)); END LOOP;END $test$;`);
  const bin=resolvePg17Bin(),env={PATH:'/usr/bin:/bin',LC_ALL:'C'},dump=spawn(join(bin,'pg_dump'),['--format=custom','--no-password','-h',f.socket,'-p',String(f.port),'-U','fixture_bootstrap','-d','collect_fixture_dump'],{stdio:['ignore','pipe','pipe'],env});
  let stderr=0,size=0,chunks=[];dump.stderr.on('data',x=>stderr+=x.length);const a=outcome(dump);
  for await(const x of dump.stdout){size+=x.length;assert(size<=32*1024*1024);chunks.push(x);}assert.deepEqual(await a,{code:0,signal:null});const archive=Buffer.concat(chunks);for(const x of chunks)x.fill(0);chunks=[];
  const restore=spawn(join(bin,'pg_restore'),['--list'],{stdio:['pipe','pipe','pipe'],env}),b=outcome(restore),scanner=createTocScanner();
  restore.stderr.on('data',x=>stderr+=x.length);restore.stdout.on('data',x=>scanner.push(x));restore.stdin.on('error',()=>{});restore.stdin.end(archive);
  try{assert.deepEqual(await b,{code:0,signal:null});assert.equal(stderr,0);assert(scanner.finish(['app']).bytes>512*1024);}
  finally{scanner.clear();archive.fill(0);}
  // The actual supervisor must accept the same large TOC, not just the parser
  // in isolation. All database rows and credentials here are synthetic.
  const journalRoot=join(f.root,'journal'),artifactRoot=join(f.root,'artifacts'),secrets=join(f.root,'secrets');for(const p of [journalRoot,artifactRoot,secrets])mkdirSync(p,{mode:0o700});
  const passwordPath=join(secrets,'password'),keyPath=join(secrets,'key'),key=randomBytes(32);writeFileSync(passwordPath,'synthetic-password',{mode:0o600});writeFileSync(keyPath,key,{mode:0o600});key.fill(0);
  const h=name=>createHash('sha256').update(readFileSync(join(bin,name))).digest('hex');
  const request={mode:'synthetic',operationId:'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',journalRoot,artifactRoot,passwordPath,keyPath,
   dumpToolSha256:h('pg_dump'),dumpExecutableSha256:h('.pg_dump-wrapped'),restoreToolSha256:h('pg_restore'),restoreExecutableSha256:h('.pg_restore-wrapped'),fixture:{socket:f.socket,port:f.port}};
  const plan={deadlineMs:90000,request},result=await runReviewedDump({plan,expectedPlanSha256:planDigest(plan)});assert.equal(result.status,'completed_point_in_time');assert.equal(result.retryAuthorized,false);
 }finally{if(source)await source.end();if(admin)await admin.end();const r=await f.close();assert.equal(r.removed,true);}
});
