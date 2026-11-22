import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawn,execFileSync} from 'node:child_process';
import {writeFile,open} from 'node:fs/promises';
import {join} from 'node:path';
import {createServer} from 'node:net';
import pg from '../../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../test-support/owned-pg17.mjs';
import {preflightPlanDigest} from '../principal-mapping-preflight/preflight.mjs';
import {planDigest,targetConfig,validateEnvelope} from './protocol.mjs';
import {hasPinnedProviderSSL} from '../../managed-cloud-migrations/provider-ca.mjs';
const CLI=new URL('./supervisor.mjs',import.meta.url).pathname;
const srcAuth='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',cloudAuth='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const sourceId='synthetic-source-person',targetId='synthetic-cloud-primary',profile='synthetic-profile',ph=createHash('sha256').update(profile).digest('hex');
const pass1='synthetic-source-secret',pass2='synthetic-target-secret';
const wait=ms=>new Promise(r=>setTimeout(r,ms));

function childOf(ppid){try{const s=execFileSync('/bin/ps',['-axo','pid=,ppid='],{encoding:'utf8',timeout:2000});for(const line of s.split('\n')){const [pid,parent]=line.trim().split(/\s+/).map(Number);if(parent===ppid)return pid;}}catch{}return null;}
async function launch(f,envelope,{pin,raw,env={},stdinFd=null,onStart=null}={}){
 const input=raw??JSON.stringify(envelope),arg=pin??planDigest(envelope.plan);
 const child=f.trackChild(spawn(process.execPath,[CLI,arg],{stdio:[stdinFd??'pipe','pipe','pipe'],env:{PATH:'/usr/bin:/bin',LC_ALL:'C',...env}}));
 let out='',err='';child.stdout.on('data',b=>{out+=b.toString('utf8');});child.stderr.on('data',b=>{err+=b.toString('utf8');});
 const done=new Promise(resolve=>{child.once('error',()=>resolve({code:null,signal:null,error:true,out,err}));child.once('close',(code,signal)=>resolve({code,signal,out,err}));});
 if(stdinFd===null){child.stdin.on('error',()=>{});if(onStart)await onStart(child);if(input!==null)child.stdin.end(input);}else if(onStart)await onStart(child);
 const result=await done;let body;try{body=JSON.parse(result.out);}catch{body=null;}return {...result,body};
}

test('credentialed supervisor uses owned PG17, isolated sockets and aggregate output',{timeout:90000},async t=>{
 const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_principal_operator_fixture'}),clients=[],sockets=new Set();
 let server;
 async function connect(database){const c=new pg.Client({host:f.socket,port:f.port,database,user:'fixture_bootstrap'});await c.connect();clients.push(c);return c;}
 try{
  const admin=await connect('postgres');await admin.query('CREATE DATABASE collect_fixture_source');await admin.query('CREATE DATABASE collect_fixture_target');
  const source=await connect('collect_fixture_source'),target=await connect('collect_fixture_target');
  for(const c of [source,target])await c.query(`CREATE SCHEMA app;CREATE SCHEMA auth;CREATE SCHEMA private;
   CREATE TABLE app.users(id text PRIMARY KEY,phone text,email text,public_id text NOT NULL,access_status text NOT NULL);
   CREATE TABLE auth.users(id uuid PRIMARY KEY,email varchar(255),deleted_at timestamptz,banned_until timestamptz);
   CREATE TABLE private.auth_principal_links(auth_user_id uuid,user_id text);
   CREATE TABLE private.collect_deployment_identity(singleton boolean PRIMARY KEY,profile_raw text,profile_sha256 text)`);
  await source.query('INSERT INTO private.collect_deployment_identity VALUES(true,$1,$2)',[profile,ph]);
  await source.query("INSERT INTO auth.users(id,email) VALUES($1,'same@example.invalid')",[srcAuth]);
  await source.query("INSERT INTO app.users VALUES('synthetic-source-person',NULL,'same@example.invalid','source-public','active')");
  await source.query('INSERT INTO private.auth_principal_links VALUES($1,$2)',[srcAuth,sourceId]);
  await target.query("INSERT INTO auth.users(id,email) VALUES($1,'same@example.invalid')",[cloudAuth]);
  await target.query("INSERT INTO app.users VALUES('synthetic-cloud-primary',NULL,'same@example.invalid','target-public','active')");
  await target.query('INSERT INTO private.auth_principal_links VALUES($1,$2)',[cloudAuth,targetId]);
  const id=(await source.query(`SELECT system_identifier::text AS "systemIdentifier",to_char(pg_postmaster_start_time() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"') AS "postmasterStartedAt",current_setting('server_version_num') AS "serverVersion" FROM pg_catalog.pg_control_system()`)).rows[0];
  const side=(database,auth_user_id,app_user_id,first)=>({kind:'synthetic',host:f.socket,port:f.port,database,session_user:'fixture_bootstrap',current_user:'fixture_bootstrap',profile_sha256:first?ph:null,auth_user_id,app_user_id});
  const pre={format:'collect.principal-mapping-preflight.v1',project_ref:'rrlduytparvsjfmegalh',owner_decision:'same_person_keep_cloud_primary',decision_reference_sha256:'a'.repeat(64),source_set_sha256:'b'.repeat(64),max_rows:16,statement_timeout_ms:500,total_timeout_ms:3000,
   source:side('collect_fixture_source',srcAuth,sourceId,true),target:side('collect_fixture_target',cloudAuth,targetId,false)};
  const mk=(p=pre,identity=id,deadlineMs=4000)=>({format:'collect.principal-supervisor.v1',preflight:p,preflightSha256:preflightPlanDigest(p),sourceIdentity:identity,deadlineMs});
  const envelope=(p=mk())=>({plan:p,sourcePassword:pass1,targetPassword:pass2});
  const hidden=[srcAuth,cloudAuth,sourceId,targetId,pass1,pass2,'same@example.invalid'];
  function noLeaks(r){for(const x of hidden)assert.equal((r.out+'\n'+r.err).includes(x),false);}
  await t.test('real worker observes selected pair and emits only validated aggregates',async()=>{
   const r=await launch(f,envelope());assert.equal(r.code,0,JSON.stringify(r));assert.equal(r.body.status,'aggregate_observation');assert.equal(r.body.source.selected_exact_links,1);assert.equal(r.body.target.selected_exact_links,1);
   assert.equal(r.body.email_is_identity_proof,false);assert.equal(r.body.other_identity_mappings_inferred,false);assert.equal(r.body.write_authorized,false);assert.equal('plan_sha256' in r.body,false);noLeaks(r);
   assert.equal((await admin.query("SELECT count(*)::int n FROM pg_stat_activity WHERE application_name='collect_principal_preflight'")).rows[0].n,0);
  });
  await t.test('wrong source cluster or reviewed profile is refused without identifying output',async()=>{
   const wrong={...id,systemIdentifier:id.systemIdentifier.slice(0,-1)+(id.systemIdentifier.endsWith('1')?'2':'1')};
   const a=await launch(f,envelope(mk(pre,wrong)));assert.equal(a.code,1);assert.equal(a.body.reason,'source_identity_refused');noLeaks(a);
   const changed={...pre,source:{...pre.source,profile_sha256:'c'.repeat(64)}};const b=await launch(f,envelope(mk(changed)));assert.equal(b.code,1);assert.equal(b.body.reason,'preflight_refused');noLeaks(b);
  });
  await t.test('invalid pin, malformed plan and unexpected environment fail before observation',async()=>{
   const a=await launch(f,envelope(),{pin:'f'.repeat(64)});assert.equal(a.code,1);assert.equal(a.body.reason,'plan_refused');noLeaks(a);
   const malformed={...pre,source:{...pre.source,auth_user_id:'not-valid'}};const b=await launch(f,envelope(mk(malformed)));assert.equal(b.code,1);assert.equal(b.body.reason,'plan_refused');noLeaks(b);
   const c=await launch(f,envelope(),{env:{PGHOST:'synthetic-do-not-use'}});assert.equal(c.code,1);assert.equal(c.body.reason,'input_refused');noLeaks(c);
  });
  await t.test('direct project options pin TLS and the unreviewed real pair cannot connect',async()=>{
   const targetManaged={...pre.target,kind:'managed',host:'db.rrlduytparvsjfmegalh.supabase.co',port:5432,database:'postgres',session_user:'postgres',current_user:'postgres'};
   const cfg=targetConfig(targetManaged,pass2,1000);assert.equal(hasPinnedProviderSSL(cfg.ssl),true);assert.deepEqual(Object.keys(cfg.ssl).sort(),['ca','rejectUnauthorized']);
   assert.throws(()=>targetConfig({...targetManaged,host:'wrong.example.invalid'},pass2,1000),/plan_refused/);
   const real={...pre,source:{...pre.source,kind:'local'},target:targetManaged};
   const tcp=envelope(mk({...real,source:{...real.source,host:'127.0.0.1'}}));
   assert.throws(()=>validateEnvelope(tcp,planDigest(tcp.plan)),/plan_refused/);
   const e=envelope(mk(real));assert.throws(()=>validateEnvelope(e,planDigest(e.plan)),/managed_preimage_unavailable/);
   const r=await launch(f,e);assert.equal(r.code,1);assert.equal(r.body.reason,'managed_preimage_unavailable');noLeaks(r);
  });
  await t.test('regular-file stdin, malformed input and oversized private input are refused',async()=>{
   const file=join(f.root,'synthetic-private-input');await writeFile(file,JSON.stringify(envelope()),{mode:0o600});const fd=await open(file,'r');
   try{const a=await launch(f,envelope(),{stdinFd:fd.fd});assert.equal(a.code,1);assert.equal(a.body.reason,'input_refused');noLeaks(a);}finally{await fd.close();}
   const b=await launch(f,envelope(),{raw:'{"duplicate":1,"duplicate":2}'});assert.equal(b.code,1);assert.equal(b.body.reason,'input_refused');noLeaks(b);
   const c=await launch(f,envelope(),{raw:'x'.repeat(40000)});assert.equal(c.code,1);assert.equal(c.body.reason,'input_refused');noLeaks(c);
  });
  await t.test('source lock refusal closes both clients',async()=>{
   await source.query('BEGIN');await source.query('LOCK TABLE app.users IN ACCESS EXCLUSIVE MODE');
   try{const r=await launch(f,envelope());assert.equal(r.code,1);assert.equal(r.body.reason,'preflight_refused');noLeaks(r);}
   finally{await source.query('ROLLBACK');}
   assert.equal((await admin.query("SELECT count(*)::int n FROM pg_stat_activity WHERE application_name='collect_principal_preflight'")).rows[0].n,0);
  });
  server=createServer(socket=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket));});const fakePort=f.port===64999?64998:64999;
  await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(join(f.socket,'.s.PGSQL.'+fakePort),resolve);});
  const stalled={...pre,source:{...pre.source,port:fakePort},statement_timeout_ms:250,total_timeout_ms:500};const stalledEnvelope=envelope(mk(stalled,id,1000));
  await t.test('stalled source handshake terminates within its timeout',async()=>{
   const start=Date.now(),r=await launch(f,stalledEnvelope);assert.equal(r.code,1);assert.ok(['connection_refused','observation_deadline'].includes(r.body.reason??r.body.status));assert.ok(Date.now()-start<5000);noLeaks(r);
  });
  await t.test('stalled target handshake closes the already opened source session',async()=>{
   const p={...pre,target:{...pre.target,port:fakePort},statement_timeout_ms:250,total_timeout_ms:500};
   const r=await launch(f,envelope(mk(p,id,1000)));assert.equal(r.code,1);assert.ok(['connection_refused','observation_deadline'].includes(r.body.reason??r.body.status));noLeaks(r);
   assert.equal((await admin.query("SELECT count(*)::int n FROM pg_stat_activity WHERE application_name='collect_principal_preflight'")).rows[0].n,0);
  });
  await t.test('outer SIGINT and SIGTERM cancel a blocked owned worker',async()=>{
   for(const sig of ['SIGINT','SIGTERM']){
    const r=await launch(f,stalledEnvelope,{onStart:async c=>{setTimeout(()=>{try{c.kill(sig);}catch{}},150);}});
    assert.equal(r.code,1);assert.equal(r.body.status,'observation_interrupted');noLeaks(r);
   }
  });
  await t.test('deadline escalates a stopped owned worker and reaps its process group',async()=>{
   let worker;
   const r=await launch(f,stalledEnvelope,{onStart:async c=>{setTimeout(async()=>{const end=Date.now()+700;while(Date.now()<end&&!worker){worker=childOf(c.pid);if(!worker)await wait(10);}if(worker)try{process.kill(worker,'SIGSTOP');}catch{}},30);}});
   assert.ok(worker,'owned worker not found');assert.equal(r.code,1);assert.equal(r.body.status,'observation_deadline');noLeaks(r);
   assert.throws(()=>process.kill(worker,0),e=>e.code==='ESRCH');
  });
 }finally{
  for(const x of sockets)x.destroy();if(server)await new Promise(r=>server.close(r));
  await Promise.allSettled(clients.map(c=>c.end().catch(()=>{})));const closed=await f.close();assert.equal(closed.removed,true);
 }
});
