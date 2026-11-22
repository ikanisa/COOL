// Real PostgreSQL 17 with synthetic records. The local adapter simulates TLS
// metadata; it does not prove hosted network, Supavisor or credential behavior.
import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {createHash} from 'node:crypto';
import {readFile,mkdtemp,chmod,rm,writeFile,readdir,access} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {extractSupportedBody,pinnedMigrationIdentities} from '../atomic_cloud_migration.mjs';
import {runRequest,FORMAT} from './operator-core.mjs';
const PROJECT='rrlduytparvsjfmegalh',entries=pinnedMigrationIdentities(),first=entries[14];
const request=(action,preimageSha256)=>({format:FORMAT,action,connection:{host:`db.${PROJECT}.supabase.co`,user:'postgres',password:'synthetic-only'},
 migration:{version:first.version,sourceSha256:first.sha256,preimageSha256:action==='capture'?null:preimageSha256}});
const sql=`CREATE ROLE collect_runtime; CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE ROLE collect_importer;
 CREATE SCHEMA app; CREATE SCHEMA private; CREATE SCHEMA auth; CREATE SCHEMA supabase_migrations;
 GRANT USAGE ON SCHEMA private TO collect_runtime;
 CREATE TABLE supabase_migrations.schema_migrations(version text primary key,name text,statements text[]);
 CREATE TABLE private.collect_fence_control(singleton boolean primary key,project_ref text,mode text,source_sha256 text,epoch bigint,operation_id uuid);
 INSERT INTO private.collect_fence_control VALUES(true,'rrlduytparvsjfmegalh','fenced',repeat('a',64),13,'11111111-1111-4111-8111-111111111111');
 CREATE FUNCTION private._collect_fence_statement() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$BEGIN RETURN NULL; END$$;
 CREATE FUNCTION app.unixepoch() RETURNS bigint LANGUAGE SQL AS $$SELECT 1::bigint$$;
 CREATE TABLE app.users(id text primary key,access_status text,member_type text);
 CREATE TABLE app.auth_sessions(id text primary key,user_id text,surface text,revoked_at bigint,expires_at bigint);
 CREATE TABLE private.auth_principal_links(user_id text,auth_user_id uuid);
 CREATE TABLE auth.users(id uuid primary key,deleted_at timestamptz,banned_until timestamptz);
 CREATE TABLE auth.sessions(id uuid primary key,user_id uuid,not_after timestamptz);
 CREATE TABLE app.notification_events(id text,user_id text,event_type text,status text,created_at bigint,data_json text);
 CREATE TABLE app.notification_devices(id text,user_id text,owner_session_id text,active integer,platform text,provider text,token_hash text);
 CREATE TABLE app.memberships(user_id text,collection_id text,active integer);
 CREATE TABLE app.collections(id text,status text);
 CREATE TABLE app.notification_preferences(user_id text,push_enabled integer,payment_updates integer);
 CREATE TABLE app.privacy_retention_barriers(subject_id text);`;

// Bound every client shutdown. An end() acknowledgement is not a stream-close
// acknowledgement. Destroy only the captured stream and confirm its close.
async function bounded(promise,ms){
 let timer;try{return await Promise.race([promise,new Promise(resolve=>{timer=setTimeout(()=>resolve({timeout:true}),ms);})]);}
 finally{clearTimeout(timer);}
}
async function closeOwnedClients(connections,{graceMs=1000,forceMs=1500}={}){
 const results=await Promise.all(connections.map(async client=>{
  let stream,closedObserved=false,onClose;
  try{stream=client?.connection?.stream;}catch{stream=null;}
  const closed=()=>{try{return closedObserved||stream?.closed===true;}catch{return false;}};
  let resolveClosed;const closeEvent=new Promise(resolve=>{resolveClosed=resolve;});
  try{if(stream&&typeof stream.once==='function'){
   onClose=()=>{closedObserved=true;resolveClosed({closed:true});};stream.once('close',onClose);
  }}catch{onClose=null;}
  try{
   // The rejection is consumed even if it arrives after the grace timer.
   const end=Promise.resolve().then(()=>client.end()).then(()=>({ok:true}),()=>({ok:false}));
   const result=await bounded(end,graceMs);
   if(closed())return true;
   // A resolved end() may precede the socket close event; give that event a
   // bounded opportunity before forcing this exact owned stream closed.
   if(result.ok===true&&onClose){await bounded(closeEvent,graceMs);if(closed())return true;}
   if(!stream||!onClose)return false;
   try{if(typeof stream.destroy!=='function')return false;stream.destroy();}catch{return false;}
   if(closed())return true;
   await bounded(closeEvent,forceMs);return closed();
  }finally{try{if(onClose&&typeof stream.removeListener==='function')stream.removeListener('close',onClose);}catch{}}
 }));
 if(results.some(x=>!x))throw Object.assign(new Error('owned_client_close_unconfirmed'),{code:'owned_client_close_unconfirmed'});
}
// Once the owned cluster exists, every subsequent setup operation is under
// its cleanup boundary. The helper retains an unconfirmed cluster rather than
// removing it, and tracks direct children until their close event.
async function withOperatorFixture(run,{journalFactory=async fixture=>{
 const journal=await mkdtemp(join(fixture.root,'journal-'));await chmod(journal,0o700);return journal;
},clientTimeouts}={}){
 const fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap'}),connections=[];
 try{const journal=await journalFactory(fixture);return await run({fixture,journal,connections});}
 finally{
  try{await closeOwnedClients(connections,clientTimeouts);}
  finally{const closed=await fixture.close();assert.equal(closed.removed,true,'owned fixture cleanup must be confirmed');}
 }
}
async function runOwnedChild(fixture,{args,input,closedStdout=false,signal,timeoutMs=60000,onChild}={}){
 const child=fixture.trackChild(spawn(process.execPath,args,{stdio:['pipe','pipe','pipe'],env:{PATH:'/usr/bin:/bin'}}));
 let out='',err='',spawnError=null,reason=null,forceTimer,unconfirmedTimer,timeout;
 let resolveUnconfirmed;const unconfirmed=new Promise(resolve=>{resolveUnconfirmed=resolve;});
 const closed=new Promise(resolve=>{
  child.once('error',e=>{spawnError=e;});child.once('close',(exit,termination)=>resolve({exit,termination}));
 });
 const stop=why=>{
  if(reason)return;reason=why;
  if(child.exitCode===null&&child.signalCode===null){try{child.kill('SIGTERM');}catch{}}
  forceTimer=setTimeout(()=>{if(child.exitCode===null&&child.signalCode===null){try{child.kill('SIGKILL');}catch{}}},1000);
  // Leave an unconfirmed child registered with the fixture; fixture.close()
  // will retry termination and must retain its cluster if it cannot confirm it.
  unconfirmedTimer=setTimeout(()=>resolveUnconfirmed({unconfirmed:true}),5000);
 };
 const abort=()=>stop('owned_child_aborted');
 if(signal?.aborted)abort();else signal?.addEventListener('abort',abort,{once:true});
 timeout=setTimeout(()=>stop('owned_child_timeout'),timeoutMs);
 child.stdin.on('error',()=>{});
 if(closedStdout)child.stdout.destroy();else child.stdout.on('data',x=>{out+=x;});
 child.stderr.on('data',x=>{err+=x;});
 try{
  onChild?.(child);child.stdin.end(input);
  const result=await Promise.race([closed,unconfirmed]);
  if(result.unconfirmed)throw Object.assign(new Error('owned_child_stop_unconfirmed'),{code:'owned_child_stop_unconfirmed',childStopped:false});
  if(reason)throw Object.assign(new Error(reason),{code:reason,childStopped:true});
  if(spawnError)throw spawnError;
  return {...result,out,err};
 }finally{clearTimeout(timeout);clearTimeout(forceTimer);clearTimeout(unconfirmedTimer);signal?.removeEventListener('abort',abort);}
}

function syntheticOwnedStream({emitClose=true,alreadyClosed=false,markClosed=true}={}){
 const stream=new EventEmitter();stream.closed=alreadyClosed;stream.destroyed=false;stream.destroyCalls=0;
 stream.destroy=()=>{stream.destroyCalls++;stream.destroyed=true;if(emitClose)queueMicrotask(()=>{if(markClosed)stream.closed=true;stream.emit('close');});return stream;};
 return stream;
}
test('owned client teardown confirms closure after resolved, stuck and rejected ends',async()=>{
 const stuck=syntheticOwnedStream(),rejected=syntheticOwnedStream(),eventOnly=syntheticOwnedStream({markClosed:false}),graceful=syntheticOwnedStream(),resolvedOpen=syntheticOwnedStream(),already=syntheticOwnedStream({alreadyClosed:true}),unowned=syntheticOwnedStream();
 let ends=0;
 await closeOwnedClients([
  {connection:{stream:stuck},end(){ends++;return new Promise(()=>{});}},
  {connection:{stream:rejected},end(){ends++;return Promise.reject(Error('synthetic rejected end'));}},
  {connection:{stream:eventOnly},end(){ends++;return Promise.reject(Error('synthetic event-only close'));}},
  {connection:{stream:graceful},end(){ends++;queueMicrotask(()=>{graceful.closed=true;graceful.emit('close');});return Promise.resolve();}},
  {connection:{stream:resolvedOpen},end(){ends++;return Promise.resolve();}},
  {connection:{stream:already},end(){ends++;return Promise.reject(Error('synthetic already closed'));}},
 ],{graceMs:20,forceMs:100});
 assert.equal(ends,6);assert.equal(stuck.destroyCalls,1);assert.equal(rejected.destroyCalls,1);assert.equal(eventOnly.destroyCalls,1);assert.equal(eventOnly.closed,false);
 assert.equal(resolvedOpen.destroyCalls,1);assert.equal(resolvedOpen.closed,true);
 assert.equal(stuck.closed,true);assert.equal(rejected.closed,true);
 assert.equal(graceful.destroyCalls,0);assert.equal(already.destroyCalls,0);assert.equal(unowned.destroyCalls,0);
});
for(const mode of ['stuck','resolved'])test(`unconfirmed owned client close after ${mode} end fails but PostgreSQL still closes`, {timeout:120000},async()=>{
 const stream=syntheticOwnedStream({emitClose:false});let root,serverPid;
 await assert.rejects(withOperatorFixture(async({fixture,connections})=>{
  root=fixture.root;serverPid=fixture.serverPid;
  connections.push({connection:{stream},end(){return mode==='stuck'?new Promise(()=>{}):Promise.resolve();}});
 },{clientTimeouts:{graceMs:20,forceMs:30}}),e=>e.code==='owned_client_close_unconfirmed');
 assert.equal(stream.destroyCalls,1);assert.equal(stream.destroyed,true);assert.equal(stream.closed,false);
 assert.ok(root&&Number.isSafeInteger(serverPid));await assert.rejects(access(root),e=>e.code==='ENOENT');
 assert.throws(()=>process.kill(serverPid,0),e=>e.code==='ESRCH');
});

test('journal setup failure closes the owned PostgreSQL cluster', {timeout:120000},async()=>{
 let root,serverPid;
 await assert.rejects(withOperatorFixture(async()=>assert.fail('setup must fail'),{journalFactory:async fixture=>{
  root=fixture.root;serverPid=fixture.serverPid;await mkdtemp(join(root,'partial-journal-'));throw Error('synthetic journal setup failure');
 }}),/synthetic journal setup failure/);
 assert.ok(root&&Number.isSafeInteger(serverPid));
 await assert.rejects(access(root),e=>e.code==='ENOENT');
 assert.throws(()=>process.kill(serverPid,0),e=>e.code==='ESRCH');
});
test('owned subprocesses are reaped after timeout and abort', {timeout:120000},async()=>withOperatorFixture(async({fixture})=>{
 for(const mode of ['timeout','abort']){
  const controller=new AbortController();let childPid;
  const running=runOwnedChild(fixture,{args:['-e','setInterval(()=>{},1000)'],signal:controller.signal,
   timeoutMs:mode==='timeout'?150:5000,onChild:child=>{childPid=child.pid;}});
  const timer=mode==='abort'?setTimeout(()=>controller.abort(),150):null;
  try{await assert.rejects(running,e=>e.code===`owned_child_${mode==='abort'?'aborted':'timeout'}`&&e.childStopped===true);}
  finally{if(timer)clearTimeout(timer);}
  assert.ok(Number.isSafeInteger(childPid)&&childPid>1);
  assert.throws(()=>process.kill(childPid,0),e=>e.code==='ESRCH');
  assert.equal(fixture.external.size,0,'closed child must be unregistered');
 }
}));

test('real PostgreSQL commit with lost acknowledgement leaves one durable record and requires readback', {timeout:120000},async()=>withOperatorFixture(async({fixture,journal,connections})=>{
 const actual=async(user='postgres')=>{const c=new pg.Client({host:fixture.socket,port:fixture.port,database:'postgres',user,connectionTimeoutMillis:3000});c.on('error',()=>{});await c.connect();connections.push(c);return c;};
 let admin;
  const bootstrap=await actual('fixture_bootstrap');await bootstrap.query('CREATE ROLE postgres LOGIN SUPERUSER');admin=await actual();await admin.query(sql);
  for(const e of entries.slice(0,14)){
   const text=await readFile(new URL(`../../../supabase/migrations/${e.version}_${e.name}.sql`,import.meta.url),'utf8');
   await admin.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',[e.version,e.name,[text]]);
  }
  let loseCommit=false;
  const factory=(options)=>{
   const c=new pg.Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'postgres',connectionTimeoutMillis:3000});
   c.on('error',()=>{});connections.push(c);
   const connection=new EventEmitter();
   const syntheticStream={encrypted:true,authorized:true,servername:`db.${PROJECT}.supabase.co`,destroy(){c.connection.stream?.destroy();}};
   connection.stream=syntheticStream;
   c.connection.on('readyForQuery',msg=>connection.emit('readyForQuery',msg));
   return {connection,connectionParameters:{host:`db.${PROJECT}.supabase.co`,port:5432,database:'postgres',user:'postgres',ssl:options.ssl},
    on:(...args)=>c.on(...args),connect:()=>c.connect(),end:()=>c.end(),
    async query(text,values){const result=await c.query(text,values);if(text==='COMMIT'&&loseCommit){loseCommit=false;throw Error('synthetic lost commit response');}return result;}};
  };
  const captured=await runRequest(request('capture'),{journalRoot:journal,makeClient:factory,environment:{}});
  assert.equal(captured.status,'captured');const pin=captured.result.sha256;assert.match(pin,/^[0-9a-f]{64}$/);
  loseCommit=true;const attempt=await runRequest(request('apply',pin),{journalRoot:journal,makeClient:factory,environment:{}});
  assert.equal(attempt.status,'unconfirmed');assert.equal(attempt.code,'commit_unconfirmed');
  const receipt=JSON.parse(await readFile(join(journal,first.version,'outcome.json'),'utf8'));
  assert.equal(receipt.backendPid,attempt.backendPid);assert.equal(receipt.state,'unconfirmed');
  for(let i=0;i<50;i++){
   const r=await admin.query('SELECT NOT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid=$1) AS gone',[attempt.backendPid]);
   if(r.rows[0].gone)break;await new Promise(resolve=>setTimeout(resolve,20));
  }
  const reconciled=await runRequest(request('reconcile',pin),{journalRoot:journal,makeClient:factory,environment:{}});
  assert.equal(reconciled.status,'recorded');
  assert.equal((await admin.query('SELECT count(*)::integer AS n FROM supabase_migrations.schema_migrations WHERE version=$1',[first.version])).rows[0].n,1);
  assert.equal((await admin.query("SELECT to_regclass('app.client_diagnostic_reports') IS NOT NULL AS ok")).rows[0].ok,true);
  await assert.rejects(runRequest(request('apply',pin),{journalRoot:journal,makeClient:factory,environment:{}}),{code:'apply_already_attempted'});
}));

for(const failureMode of ['open','fsync','closed-stdout','success'])test(`CLI reports or reconciles commit with ${failureMode}`, {timeout:120000},async t=>withOperatorFixture(async({fixture,journal,connections})=>{
 const actual=async(user='postgres')=>{const c=new pg.Client({host:fixture.socket,port:fixture.port,database:'postgres',user,connectionTimeoutMillis:3000});c.on('error',()=>{});await c.connect();connections.push(c);return c;};
  const bootstrap=await actual('fixture_bootstrap');await bootstrap.query('CREATE ROLE postgres LOGIN SUPERUSER');const admin=await actual();await admin.query(sql);
  for(const e of entries.slice(0,14)){
   const text=await readFile(new URL(`../../../supabase/migrations/${e.version}_${e.name}.sql`,import.meta.url),'utf8');
   await admin.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',[e.version,e.name,[text]]);
  }
  const factory=(options)=>{
   const c=new pg.Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'postgres',connectionTimeoutMillis:3000});
   c.on('error',()=>{});connections.push(c);const connection=new EventEmitter();
   connection.stream={encrypted:true,authorized:true,servername:`db.${PROJECT}.supabase.co`,destroy(){c.connection.stream?.destroy();}};
   c.connection.on('readyForQuery',msg=>connection.emit('readyForQuery',msg));
   return {connection,connectionParameters:{host:`db.${PROJECT}.supabase.co`,port:5432,database:'postgres',user:'postgres',ssl:options.ssl},
    on:(...args)=>c.on(...args),connect:()=>c.connect(),end:()=>c.end(),query:(...args)=>c.query(...args)};
  };
  const captured=await runRequest(request('capture'),{journalRoot:journal,makeClient:factory,environment:{}}),pin=captured.result.sha256;
  // The preload is test-owned and only affects this child. It supplies the
  // local Unix-socket PG client with simulated TLS properties and injects a
  // write error exactly when the real CLI tries to record the post-COMMIT result.
  // The other cases exercise the actual output pipe and a normal result.
  const loader=join(fixture.root,'synthetic-cli-loader.mjs');
  const pgPath=fileURLToPath(new URL('../node_modules/pg/lib/index.js',import.meta.url));
  const outcome=join(journal,first.version,'outcome.json');
  const loaderSource=`import {createRequire,syncBuiltinESMExports} from 'node:module';
import {EventEmitter} from 'node:events';
const require=createRequire(import.meta.url),pg=require(${JSON.stringify(pgPath)}),fs=require('node:fs/promises');
const open=fs.open;fs.open=async(...args)=>{if(args[0]===${JSON.stringify(outcome)}&&['open','fsync'].includes(${JSON.stringify(failureMode)})){if(${JSON.stringify(failureMode)}==='open')throw Error('synthetic outcome write failure');const h=await open(...args);h.sync=async()=>{throw Error('synthetic outcome fsync failure');};return h;}return open(...args);};syncBuiltinESMExports();
const RealClient=pg.Client;pg.Client=class {
 constructor(opts){this.connectionParameters=opts;this.inner=new RealClient({host:${JSON.stringify(fixture.socket)},port:${fixture.port},database:'postgres',user:'postgres',connectionTimeoutMillis:3000});
  this.inner.on('error',()=>{});this.connection=new EventEmitter();this.connection.stream={encrypted:true,authorized:true,servername:opts.host,destroy:()=>this.inner.connection.stream?.destroy()};
  this.inner.connection.on('readyForQuery',msg=>this.connection.emit('readyForQuery',msg));}
 on(...a){return this.inner.on(...a);} connect(){return this.inner.connect();} end(){return this.inner.end();} query(...a){return this.inner.query(...a);}
};\n`;
  await writeFile(loader,loaderSource,{mode:0o600});
  const cli=fileURLToPath(new URL('./operator.mjs',import.meta.url));
  const result=await runOwnedChild(fixture,{args:['--import',loader,cli,journal],input:JSON.stringify(request('apply',pin)),closedStdout:failureMode==='closed-stdout',signal:t.signal});
  let backendPid;
  if(failureMode==='closed-stdout'){
   assert.equal(result.exit,1,result.err);assert.equal(result.out,'');
   const saved=JSON.parse(await readFile(outcome,'utf8'));
   assert.equal(saved.state,'committed');backendPid=saved.backendPid;
  }else{
   const response=JSON.parse(result.out);
   if(failureMode==='success'){
    assert.equal(result.exit,0,result.err);assert.equal(response.status,'committed');
   }else{
    assert.equal(result.exit,1,result.err);assert.equal(response.status,'unconfirmed');assert.equal(response.code,'journal_outcome_unconfirmed');
    assert.equal(response.version,first.version);
   }
   backendPid=response.backendPid;
  }
  assert.ok(Number.isSafeInteger(backendPid)&&backendPid>0);
  assert.doesNotMatch(result.out+result.err,/synthetic-only|synthetic outcome write failure/);
  const expectedFiles=failureMode==='open'?['backend.json','intent.json']:['backend.json','intent.json','outcome.json'];
  assert.deepEqual((await readdir(join(journal,first.version))).sort(),expectedFiles);
  assert.equal((await admin.query('SELECT count(*)::integer AS n FROM supabase_migrations.schema_migrations WHERE version=$1',[first.version])).rows[0].n,1);
  assert.equal((await admin.query("SELECT to_regclass('app.client_diagnostic_reports') IS NOT NULL AS ok")).rows[0].ok,true);
  for(let i=0;i<50;i++){
   if((await admin.query('SELECT NOT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid=$1) AS gone',[backendPid])).rows[0].gone)break;
   await new Promise(resolve=>setTimeout(resolve,20));
  }
  const reconciled=await runRequest(request('reconcile',pin),{journalRoot:journal,makeClient:factory,environment:{}});
  assert.equal(reconciled.status,'recorded');
  await assert.rejects(runRequest(request('apply',pin),{journalRoot:journal,makeClient:factory,environment:{}}),{code:'apply_already_attempted'});
}));

test('both pinned migrations commit in order with non-superuser postgres on owned PostgreSQL 17', {timeout:180000},async()=>{
 const pinned=[
  ['20261029120000','6f7c1e537a3c7d114417cfa79bd7b545bbfd17c69ab1d643c806eeb457c81e3f'],
  ['20261029130000','2d5904d5aaae917715c6ff5b996ce5b7395864fc5e225f5aaa67ec7d931a6792'],
 ];
 assert.deepEqual(entries.slice(14).map(e=>[e.version,e.sha256]),pinned);
 const migrations=await Promise.all(entries.map(async e=>{
  const text=await readFile(new URL(`../../../supabase/migrations/${e.version}_${e.name}.sql`,import.meta.url),'utf8');
  assert.equal(createHash('sha256').update(text).digest('hex'),e.sha256);return text;
 }));
 return withOperatorFixture(async({fixture,journal,connections})=>{
 const actual=async(user='postgres')=>{const c=new pg.Client({host:fixture.socket,port:fixture.port,database:'postgres',user,connectionTimeoutMillis:3000});c.on('error',()=>{});await c.connect();connections.push(c);return c;};
 const makeRequest=(entry,action,pin)=>({format:FORMAT,action,connection:{host:`db.${PROJECT}.supabase.co`,user:'postgres',password:'synthetic-only'},
  migration:{version:entry.version,sourceSha256:entry.sha256,preimageSha256:action==='capture'?null:pin}});
 let admin;
  const bootstrap=await actual('fixture_bootstrap');
  // Only fixture bootstrap can create roles or transfer database ownership.
  // Application/auth schemas and predecessor objects are synthetic and owned
  // by postgres; actual cloud ownership and TLS are not established by this test.
  await bootstrap.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS;
   CREATE ROLE collect_runtime; CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE ROLE collect_importer;
   CREATE ROLE collect_outsider; CREATE ROLE collect_acl_carrier; GRANT collect_acl_carrier TO collect_outsider;
   ALTER DATABASE postgres OWNER TO postgres;`);
  admin=await actual();
  const role=(await admin.query("SELECT rolsuper,rolbypassrls,rolcreatedb,rolcreaterole FROM pg_roles WHERE rolname=current_user")).rows[0];
  assert.deepEqual(role,{rolsuper:false,rolbypassrls:true,rolcreatedb:false,rolcreaterole:false});
  const schemaStart=sql.indexOf('\n CREATE SCHEMA app;');assert.ok(schemaStart>0);await admin.query(sql.slice(schemaStart));
  for(let i=0;i<14;i++)await admin.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',[entries[i].version,entries[i].name,[migrations[i]]]);
  const factory=(options)=>{
   const c=new pg.Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'postgres',connectionTimeoutMillis:3000});
   c.on('error',()=>{});connections.push(c);const connection=new EventEmitter();
   connection.stream={encrypted:true,authorized:true,servername:`db.${PROJECT}.supabase.co`,destroy(){c.connection.stream?.destroy();}};
   c.connection.on('readyForQuery',msg=>connection.emit('readyForQuery',msg));
   return {connection,connectionParameters:{host:`db.${PROJECT}.supabase.co`,port:5432,database:'postgres',user:'postgres',ssl:options.ssl},
    on:(...args)=>c.on(...args),connect:()=>c.connect(),end:()=>c.end(),query:(...args)=>c.query(...args)};
  };
  const options={journalRoot:journal,makeClient:factory,environment:{}};
  // The second migration must not capture or write against a 14-entry history.
  await assert.rejects(runRequest(makeRequest(entries[15],'capture'),options),{code:'migration_history_mismatch'});
  assert.equal((await admin.query('SELECT count(*)::int AS n FROM supabase_migrations.schema_migrations')).rows[0].n,14);
  assert.deepEqual((await admin.query("SELECT to_regclass('app.client_diagnostic_reports') AS diagnostics,to_regclass('app.notification_deliveries') AS notifications")).rows[0],{diagnostics:null,notifications:null});

  // If an operator transaction is refused, inspect the exact pinned body in a
  // rolled-back local transaction so the failing owner checks are visible.
  const diagnose=async(index,table)=>{
   await admin.query('BEGIN');
   try{
    await admin.query(extractSupportedBody(migrations[index]));
    const relation=(await admin.query(`SELECT pg_get_userbyid(c.relowner) AS owner,
     has_table_privilege('postgres',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AS owner_table_privilege,
     has_schema_privilege('postgres',n.oid,'CREATE') AS owner_schema_create
     FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND c.relname=$1`,[table])).rows[0];
    const functions=index===15?(await admin.query(`SELECT p.proname AS name,pg_get_userbyid(p.proowner) AS owner,
     has_function_privilege('postgres',p.oid,'EXECUTE') AS owner_execute,has_schema_privilege('postgres',n.oid,'CREATE') AS owner_schema_create
     FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname IN ('notification_delivery_eligible','notification_delivery_guard') ORDER BY p.proname`)).rows:[];
    return {relation,functions};
   }finally{await admin.query('ROLLBACK');}
  };
  const refuseUnsafe=async(index,verifyUnsafe,label)=>{
   // Observe the unsafe grant in a rolled-back candidate before requiring the
   // real operator to refuse the same preimage and roll back all its DDL.
   await admin.query('BEGIN');
   try{await admin.query(extractSupportedBody(migrations[index]));await verifyUnsafe();}
   finally{await admin.query('ROLLBACK');}
   const isolated=await mkdtemp(join(fixture.root,'outsider-journal-'));await chmod(isolated,0o700);
   const probe={...options,journalRoot:isolated};
   const captured=await runRequest(makeRequest(entries[index],'capture'),probe);
   const result=await runRequest(makeRequest(entries[index],'apply',captured.result.sha256),probe);
   assert.deepEqual({status:result.status,code:result.code},{status:'refused',code:'postcondition_mismatch'},label);
   assert.equal((await admin.query('SELECT count(*)::int AS n FROM supabase_migrations.schema_migrations')).rows[0].n,index);
   const table=index===14?'app.client_diagnostic_reports':'app.notification_deliveries';
   assert.equal((await admin.query('SELECT to_regclass($1) AS target',[table])).rows[0].target,null);
  };
  const refuseExtraRuntimeTableGrants=async(index)=>{
   const table=index===14?'app.client_diagnostic_reports':'app.notification_deliveries';
   for(const privilege of ['TRUNCATE','REFERENCES','TRIGGER','MAINTAIN']){
    await admin.query(`ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT ${privilege} ON TABLES TO collect_runtime`);
    try{await refuseUnsafe(index,async()=>{
     assert.equal((await admin.query('SELECT has_table_privilege($1,$2,$3) AS granted',['collect_runtime',table,privilege])).rows[0].granted,true);
    },`${entries[index].version}: extra runtime ${privilege} must be refused`);}
    finally{await admin.query(`ALTER DEFAULT PRIVILEGES IN SCHEMA app REVOKE ${privilege} ON TABLES FROM collect_runtime`);}
   }
  };
  const refuseInheritedRuntimeMaintain=async(index)=>{
   const table=index===14?'app.client_diagnostic_reports':'app.notification_deliveries';
   await bootstrap.query('GRANT pg_maintain TO collect_runtime');
   try{await refuseUnsafe(index,async()=>{
    const observed=(await admin.query(`SELECT pg_has_role('collect_runtime','pg_maintain','USAGE') AS member,
     has_table_privilege('collect_runtime',c.oid,'MAINTAIN') AS granted,
     EXISTS(SELECT 1 FROM aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
      WHERE a.grantee=(SELECT oid FROM pg_roles WHERE rolname='collect_runtime') AND a.privilege_type='MAINTAIN') AS direct_grant
     FROM pg_class c WHERE c.oid=to_regclass($1)`,[table])).rows[0];
    assert.deepEqual(observed,{member:true,granted:true,direct_grant:false});
   },`${entries[index].version}: inherited runtime MAINTAIN must be refused`);}
   finally{await bootstrap.query('REVOKE pg_maintain FROM collect_runtime');}
  };
  const refuseColumnGrant=async(index,role,privilege,column)=>{
   const table=index===14?'app.client_diagnostic_reports':'app.notification_deliveries';
   // The fixture superuser models an independent privileged DDL actor. Its
   // event trigger adds a column-only ACL after CREATE TABLE; it is removed
   // after this local probe and never changes the pinned migration sources.
   await bootstrap.query(`CREATE FUNCTION public.fixture_column_acl() RETURNS event_trigger LANGUAGE plpgsql SECURITY DEFINER
    SET search_path=pg_catalog AS $body$ BEGIN
     IF EXISTS(SELECT 1 FROM pg_event_trigger_ddl_commands() WHERE object_type='table' AND object_identity='${table}') THEN
      EXECUTE 'GRANT ${privilege} (${column}) ON TABLE ${table} TO ${role}';
     END IF;
    END $body$`);
   try{
    await bootstrap.query("CREATE EVENT TRIGGER fixture_column_acl ON ddl_command_end WHEN TAG IN ('CREATE TABLE') EXECUTE FUNCTION public.fixture_column_acl()");
    try{await refuseUnsafe(index,async()=>{
     const observed=(await admin.query(`SELECT has_column_privilege($1,$2,$3,$4) AS granted,has_table_privilege($1,$2,$4) AS table_granted,
      (SELECT attacl IS NOT NULL FROM pg_attribute WHERE attrelid=to_regclass($2) AND attname=$3) AS column_acl`,[role,table,column,privilege])).rows[0];
     assert.deepEqual(observed,{granted:true,table_granted:false,column_acl:true});
    },`${entries[index].version}: ${role} column ${privilege} must be refused`);}
    finally{await bootstrap.query('DROP EVENT TRIGGER fixture_column_acl');}
   }finally{await bootstrap.query('DROP FUNCTION public.fixture_column_acl()');}
  };
  // This tests effective authority from owner-role membership without adding
  // any direct outsider ACL to the new relation. Only the fixture bootstrap
  // superuser can issue this synthetic grant, which is removed immediately.
  await bootstrap.query('GRANT postgres TO collect_outsider WITH INHERIT TRUE');
  try{await refuseUnsafe(14,async()=>{
   const inherited=(await admin.query(`SELECT pg_has_role('collect_outsider','postgres','USAGE') AS owner_member,
    has_table_privilege('collect_outsider','app.client_diagnostic_reports','SELECT') AS granted,
    EXISTS(SELECT 1 FROM pg_class c,aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) a
     WHERE c.oid='app.client_diagnostic_reports'::regclass AND a.grantee=(SELECT oid FROM pg_roles WHERE rolname='collect_outsider')) AS direct_grant`)).rows[0];
   assert.deepEqual(inherited,{owner_member:true,granted:true,direct_grant:false});
  },'owner-role inheritance without an outsider ACL');}
  finally{await bootstrap.query('REVOKE postgres FROM collect_outsider');}
  await admin.query('ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT ON TABLES TO collect_outsider');
  try{await refuseUnsafe(14,async()=>assert.equal((await admin.query("SELECT has_table_privilege('collect_outsider','app.client_diagnostic_reports','SELECT') AS granted")).rows[0].granted,true),'direct outsider table privilege');}
  finally{await admin.query('ALTER DEFAULT PRIVILEGES IN SCHEMA app REVOKE SELECT ON TABLES FROM collect_outsider');}
  await admin.query('ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT ON TABLES TO collect_acl_carrier');
  try{await refuseUnsafe(14,async()=>{
   const inherited=(await admin.query(`SELECT pg_has_role('collect_outsider','collect_acl_carrier','USAGE') AS member,
    has_table_privilege('collect_outsider','app.client_diagnostic_reports','SELECT') AS granted,
    EXISTS(SELECT 1 FROM pg_class c,aclexplode(c.relacl) a WHERE c.oid='app.client_diagnostic_reports'::regclass
     AND a.grantee=(SELECT oid FROM pg_roles WHERE rolname='collect_outsider')) AS direct_grant`)).rows[0];
   assert.deepEqual(inherited,{member:true,granted:true,direct_grant:false});
  },'inherited outsider table privilege');}finally{await admin.query('ALTER DEFAULT PRIVILEGES IN SCHEMA app REVOKE SELECT ON TABLES FROM collect_acl_carrier');}
  await refuseExtraRuntimeTableGrants(14);
  await refuseInheritedRuntimeMaintain(14);
  await refuseColumnGrant(14,'collect_runtime','UPDATE','report_id');
  await refuseColumnGrant(14,'collect_outsider','SELECT','report_id');
  const capturedFirst=await runRequest(makeRequest(entries[14],'capture'),options);
  const firstResult=await runRequest(makeRequest(entries[14],'apply',capturedFirst.result.sha256),options);
  let firstDiagnostic=null;
  if(firstResult.status!=='committed'){
   assert.equal(firstResult.status,'refused','an uncertain first result must never be seeded or retried');
   assert.equal((await admin.query('SELECT count(*)::int AS n FROM supabase_migrations.schema_migrations')).rows[0].n,14);
   firstDiagnostic=await diagnose(14,'client_diagnostic_reports');
   // Synthetic diagnostic only: seed this exact predecessor to independently
   // exercise the second operator refusal. The test still requires BOTH real
   // operator results to be committed and cannot pass on this fallback.
   await admin.query('BEGIN');
   try{await admin.query(extractSupportedBody(migrations[14]));
    await admin.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',[entries[14].version,entries[14].name,[migrations[14]]]);
    await admin.query('COMMIT');
   }catch(e){await admin.query('ROLLBACK');throw e;}
  }
  await admin.query('GRANT CREATE ON SCHEMA private TO collect_outsider');
  try{await refuseUnsafe(15,async()=>assert.equal((await admin.query("SELECT has_schema_privilege('collect_outsider','private','CREATE') AS granted")).rows[0].granted,true),'outsider schema CREATE');}
  finally{await admin.query('REVOKE CREATE ON SCHEMA private FROM collect_outsider');}
  await admin.query('ALTER DEFAULT PRIVILEGES IN SCHEMA private GRANT EXECUTE ON FUNCTIONS TO collect_outsider');
  try{await refuseUnsafe(15,async()=>assert.equal((await admin.query("SELECT has_function_privilege('collect_outsider','private.notification_delivery_guard()','EXECUTE') AS granted")).rows[0].granted,true),'outsider function EXECUTE');}
  finally{await admin.query('ALTER DEFAULT PRIVILEGES IN SCHEMA private REVOKE EXECUTE ON FUNCTIONS FROM collect_outsider');}
  await refuseExtraRuntimeTableGrants(15);
  await refuseInheritedRuntimeMaintain(15);
  await refuseColumnGrant(15,'collect_runtime','REFERENCES','id');
  const capturedSecond=await runRequest(makeRequest(entries[15],'capture'),options);
  const secondResult=await runRequest(makeRequest(entries[15],'apply',capturedSecond.result.sha256),options);
  let secondDiagnostic=null;
  if(secondResult.status==='refused')secondDiagnostic=await diagnose(15,'notification_deliveries');
  assert.deepEqual([firstResult.status,secondResult.status],['committed','committed'],
   `both operator applications must commit; synthetic results=${JSON.stringify({first:{status:firstResult.status,code:firstResult.code},second:{status:secondResult.status,code:secondResult.code},firstDiagnostic,secondDiagnostic})}`);

  const history=(await admin.query('SELECT version,name,statements FROM supabase_migrations.schema_migrations ORDER BY version')).rows;
  assert.deepEqual(history,entries.map((e,i)=>({version:e.version,name:e.name,statements:[migrations[i]]})));
  const tables=(await admin.query(`SELECT c.relname AS name,pg_get_userbyid(c.relowner) AS owner,c.relrowsecurity AS rls,c.relforcerowsecurity AS forced,
   has_table_privilege('collect_runtime',c.oid,'SELECT') AS runtime_select,has_table_privilege('collect_runtime',c.oid,'INSERT') AS runtime_insert,
   has_table_privilege('collect_runtime',c.oid,'UPDATE') AS runtime_update,has_table_privilege('collect_runtime',c.oid,'DELETE') AS runtime_delete,
   has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') AS anon_any,
   has_table_privilege('authenticated',c.oid,'SELECT,INSERT,UPDATE,DELETE') AS authenticated_any,
   has_table_privilege('service_role',c.oid,'SELECT,INSERT,UPDATE,DELETE') AS service_any,
   EXISTS(SELECT 1 FROM pg_policies p WHERE p.schemaname='app' AND p.tablename=c.relname AND p.cmd='ALL'
    AND p.roles=ARRAY['collect_runtime']::name[] AND p.qual='true' AND p.with_check='true') AS runtime_policy,
   ARRAY(SELECT t.tgname::text FROM pg_trigger t WHERE t.tgrelid=c.oid AND NOT t.tgisinternal AND t.tgenabled='A' ORDER BY t.tgname) AS always_triggers
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='app' AND c.relname IN ('client_diagnostic_reports','notification_deliveries') ORDER BY c.relname`)).rows;
  assert.deepEqual(tables,[
   {name:'client_diagnostic_reports',owner:'postgres',rls:true,forced:true,runtime_select:true,runtime_insert:true,runtime_update:false,runtime_delete:true,anon_any:false,authenticated_any:false,service_any:false,runtime_policy:true,always_triggers:['collect_fence_statement_v1']},
   {name:'notification_deliveries',owner:'postgres',rls:true,forced:true,runtime_select:true,runtime_insert:true,runtime_update:true,runtime_delete:false,anon_any:false,authenticated_any:false,service_any:false,runtime_policy:true,always_triggers:['collect_fence_statement_v1','notification_delivery_identity']},
  ]);
  const functions=(await admin.query(`SELECT p.proname AS name,pg_get_userbyid(p.proowner) AS owner,p.prosecdef AS security_definer,
   p.proconfig @> ARRAY['search_path=pg_catalog']::text[] AS safe_path,has_function_privilege('collect_runtime',p.oid,'EXECUTE') AS runtime_execute,
   has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute,has_function_privilege('service_role',p.oid,'EXECUTE') AS service_execute
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private'
    AND p.proname IN ('notification_delivery_eligible','notification_delivery_guard') ORDER BY p.proname`)).rows;
  assert.deepEqual(functions,[
   {name:'notification_delivery_eligible',owner:'postgres',security_definer:true,safe_path:true,runtime_execute:true,anon_execute:false,service_execute:false},
   {name:'notification_delivery_guard',owner:'postgres',security_definer:false,safe_path:true,runtime_execute:true,anon_execute:false,service_execute:false},
  ]);
 });
});
