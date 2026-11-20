import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,randomBytes} from 'node:crypto';
import {mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {planDigest,readReviewedDumpStatus,runReviewedDump} from './supervisor.mjs';
const sha=b=>createHash('sha256').update(b).digest('hex');
test('synthetic child failures expose phase, exit and stderr length without stderr content',{timeout:90000},async()=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_diagnostic_fixture'}),old=process.env.COLLECT_SYNTHETIC_PG_BIN,key=randomBytes(32),bin=join(f.root,'synthetic-tools'),secrets=join(f.root,'secrets');let admin,source;
 try{
  mkdirSync(bin,{mode:0o700});mkdirSync(secrets,{mode:0o700});const passwordPath=join(secrets,'password'),keyPath=join(secrets,'key');writeFileSync(passwordPath,'synthetic-password',{mode:0o600});writeFileSync(keyPath,key,{mode:0o600});
  const script=(name,body)=>writeFileSync(join(bin,name),body,{mode:0o700});
  script('postgres','#!/bin/sh\nprintf "postgres (PostgreSQL) 17.11\\n"\n');for(const name of ['initdb','pg_ctl','pg_isready','.pg_dump-wrapped','pg_restore','.pg_restore-wrapped'])script(name,'#!/bin/sh\nexit 0\n');
  admin=new pg.Client({host:f.socket,port:f.port,user:'fixture_bootstrap',database:'postgres'});await admin.connect();await admin.query('CREATE DATABASE collect_fixture_dump');
  source=new pg.Client({host:f.socket,port:f.port,user:'fixture_bootstrap',database:'collect_fixture_dump'});await source.connect();await source.query('CREATE SCHEMA app; CREATE SCHEMA private; CREATE SCHEMA auth; CREATE SCHEMA storage; CREATE TABLE app.records(id int)');
  process.env.COLLECT_SYNTHETIC_PG_BIN=bin;const canary='synthetic-private-stderr-canary\n';
  for(const [n,exit,expected] of [[1,42,'dump_exit_refused'],[2,0,'dump_stderr_refused']]){
   script('pg_dump',`#!/bin/sh\nprintf 'synthetic fixture body'\nprintf '${canary.trim()}\\n' >&2\nexit ${exit}\n`);
   const journalRoot=join(f.root,'journal'+n),artifactRoot=join(f.root,'artifacts'+n);mkdirSync(journalRoot,{mode:0o700});mkdirSync(artifactRoot,{mode:0o700});
   const h=name=>sha(readFileSync(join(bin,name))),operationId=`${String(n).repeat(8)}-${String(n).repeat(4)}-4${String(n).repeat(3)}-8${String(n).repeat(3)}-${String(n).repeat(12)}`;
   const request={mode:'synthetic',operationId,journalRoot,artifactRoot,passwordPath,keyPath,dumpToolSha256:h('pg_dump'),dumpExecutableSha256:h('.pg_dump-wrapped'),restoreToolSha256:h('pg_restore'),restoreExecutableSha256:h('.pg_restore-wrapped'),fixture:{socket:f.socket,port:f.port}};
   const plan={deadlineMs:30000,request},pin=planDigest(plan),result=await runReviewedDump({plan,expectedPlanSha256:pin});
   assert.equal(result.status,'worker_outcome_unconfirmed');assert.equal(result.retryAuthorized,false);assert(!JSON.stringify(result).includes(canary.trim()));
   assert(result.diagnostics.some(x=>x.phase==='dump_started'));assert(result.diagnostics.some(x=>x.phase===expected));
   assert.deepEqual(result.diagnostics.find(x=>x.phase==='dump_process_closed'),{phase:'dump_process_closed',exitCode:exit,signal:null,stderrBytes:Buffer.byteLength(canary)});
   const status=await readReviewedDumpStatus({mode:'synthetic',root:journalRoot,operationId,expectedPlanSha256:pin,deadlineMs:3000});assert.equal(status.status,'outcome_unknown');assert.equal(status.retryAuthorized,false);
  }
  script('pg_dump',`#!/bin/sh\nexec "${join(f.bin,'pg_dump')}" "$@"\n`);
  for(const [n,body,expected] of [
   [3,"printf '1; 2615 20 SCHEMA - other owner\\n'",'toc_missing_schema_refused'],
   [4,"/usr/bin/awk 'BEGIN {for(i=0;i<20000;i++) printf \"x\"; printf \"\\n\"}'",'toc_line_bound_refused'],
   [5,"/usr/bin/awk 'BEGIN {for(i=0;i<120000;i++) print \"1; 1259 999 TABLE app synthetic_fixture_record_with_very_long_name owner\"}'",'toc_total_bound_refused']
  ]){
   script('pg_restore',`#!/bin/sh\n/bin/cat >/dev/null\n${body}\n`);
   const journalRoot=join(f.root,'journal'+n),artifactRoot=join(f.root,'artifacts'+n);mkdirSync(journalRoot,{mode:0o700});mkdirSync(artifactRoot,{mode:0o700});
   const h=name=>sha(readFileSync(join(bin,name))),operationId=`${String(n).repeat(8)}-${String(n).repeat(4)}-4${String(n).repeat(3)}-8${String(n).repeat(3)}-${String(n).repeat(12)}`;
   const request={mode:'synthetic',operationId,journalRoot,artifactRoot,passwordPath,keyPath,dumpToolSha256:h('pg_dump'),dumpExecutableSha256:h('.pg_dump-wrapped'),restoreToolSha256:h('pg_restore'),restoreExecutableSha256:h('.pg_restore-wrapped'),fixture:{socket:f.socket,port:f.port}};
   const plan={deadlineMs:30000,request},pin=planDigest(plan),result=await runReviewedDump({plan,expectedPlanSha256:pin});
   assert.equal(result.status,'worker_outcome_unconfirmed');assert.equal(result.retryAuthorized,false);assert(result.diagnostics.some(x=>x.phase===expected));
   const status=await readReviewedDumpStatus({mode:'synthetic',root:journalRoot,operationId,expectedPlanSha256:pin,deadlineMs:3000});assert.equal(status.status,'outcome_unknown');assert.equal(status.retryAuthorized,false);
  }
  script('pg_dump',"#!/bin/sh\nprintf 'synthetic fixture body'\nexec /bin/sleep 30\n");
  const journalRoot=join(f.root,'journal6'),artifactRoot=join(f.root,'artifacts6');mkdirSync(journalRoot,{mode:0o700});mkdirSync(artifactRoot,{mode:0o700});
  const h=name=>sha(readFileSync(join(bin,name))),operationId='66666666-6666-4666-8666-666666666666';
  const request={mode:'synthetic',operationId,journalRoot,artifactRoot,passwordPath,keyPath,dumpToolSha256:h('pg_dump'),dumpExecutableSha256:h('.pg_dump-wrapped'),restoreToolSha256:h('pg_restore'),restoreExecutableSha256:h('.pg_restore-wrapped'),fixture:{socket:f.socket,port:f.port}};
  const plan={deadlineMs:3000,request},pin=planDigest(plan),timed=await runReviewedDump({plan,expectedPlanSha256:pin});
  assert.equal(timed.status,'deadline_terminated_outcome_unknown');assert.equal(timed.retryAuthorized,false);assert(timed.diagnostics.some(x=>x.phase==='dump_started'));assert(!JSON.stringify(timed).includes('synthetic fixture body'));
  const status=await readReviewedDumpStatus({mode:'synthetic',root:journalRoot,operationId,expectedPlanSha256:pin,deadlineMs:3000});assert(['dispatch_intent','outcome_unknown'].includes(status.status));assert.equal(status.retryAuthorized,false);
 }finally{if(old===undefined)delete process.env.COLLECT_SYNTHETIC_PG_BIN;else process.env.COLLECT_SYNTHETIC_PG_BIN=old;key.fill(0);if(source)await source.end();if(admin)await admin.end();const r=await f.close();assert.equal(r.removed,true);}
});
