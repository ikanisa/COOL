import {loadProviderRoot} from './provider-ca.mjs';
// Owned private-socket PG17 only. TLS metadata below is a synthetic adapter;
// this suite does not connect to Supabase or qualify a hosted event trigger.
import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {EventEmitter} from 'node:events';
import {readFile} from 'node:fs/promises';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {capturePinnedPreimage,executePinnedMigration,pinnedMigrationIdentities} from '../atomic_cloud_migration.mjs';

const PROJECT='rrlduytparvsjfmegalh',entries=pinnedMigrationIdentities(),first=entries[14];
const args={version:first.version,expectedSha:first.sha256};

// A stalled client end() must not prevent cleanup of the owned PG17 child.
// Destroy only its captured socket and require a close event or closed flag;
// calling destroy() alone does not establish that the socket actually closed.
async function bounded(promise,ms){
 let timer;try{return await Promise.race([promise,new Promise(resolve=>{timer=setTimeout(()=>resolve({timeout:true}),ms);})]);}
 finally{clearTimeout(timer);}
}
async function closeOwnedClients(clients,{graceMs=1000,forceMs=1500}={}){
 const results=await Promise.all(clients.map(async client=>{
  let stream,observed=false,onClose;try{stream=client?.connection?.stream;}catch{stream=null;}
  const isClosed=()=>{try{return observed||stream?.closed===true;}catch{return false;}};
  let resolveClosed;const closeEvent=new Promise(resolve=>{resolveClosed=resolve;});
  try{if(stream&&typeof stream.once==='function'){
   onClose=()=>{observed=true;resolveClosed({closed:true});};stream.once('close',onClose);
  }}catch{onClose=null;}
  try{
   const end=Promise.resolve().then(()=>client.end()).then(()=>({ok:true}),()=>({ok:false}));
   const result=await bounded(end,graceMs);if(isClosed())return true;
   // An end() acknowledgement is not proof that the underlying stream has
   // closed. Give its close event a bounded grace period before forcing it.
   if(result.ok===true&&onClose){await bounded(closeEvent,graceMs);if(isClosed())return true;}
   if(!stream||!onClose||typeof stream.destroy!=='function')return false;
   try{stream.destroy();}catch{return false;}
   if(isClosed())return true;await bounded(closeEvent,forceMs);return isClosed();
  }finally{try{if(onClose&&typeof stream.removeListener==='function')stream.removeListener('close',onClose);}catch{}}
 }));
 if(results.some(x=>!x))throw new Error('owned_client_close_unconfirmed');
}
async function closeOwnedFixture(fixture,clients,timeouts){
 try{await closeOwnedClients(clients,timeouts);}
 finally{const closed=await fixture.close();assert.equal(closed.removed,true,'owned fixture cleanup unconfirmed');}
}

test('fixture shutdown is bounded and still closes the cluster when a socket remains unconfirmed',async()=>{
 let clusterClosed=false;const stream=new EventEmitter();stream.closed=false;stream.destroyed=false;
 stream.destroy=()=>{stream.destroyed=true;};
 const fixture={close:async()=>{clusterClosed=true;return {removed:true};}};
 const client={connection:{stream},end:()=>new Promise(()=>{})};
 await assert.rejects(closeOwnedFixture(fixture,[client],{graceMs:10,forceMs:10}),/owned_client_close_unconfirmed/);
 assert.equal(stream.destroyed,true);assert.equal(stream.closed,false);assert.equal(clusterClosed,true);
 let forced=0;const closedStream=new EventEmitter();closedStream.closed=false;
 closedStream.destroy=()=>{forced++;queueMicrotask(()=>{closedStream.closed=true;closedStream.emit('close');});};
 await closeOwnedClients([{connection:{stream:closedStream},end:()=>new Promise(()=>{})}],{graceMs:10,forceMs:100});
 assert.equal(forced,1);assert.equal(closedStream.closed,true);
});

test('resolved end with an open stream remains unconfirmed and still closes the fixture',async()=>{
 let clusterClosed=false;const stream=new EventEmitter();stream.closed=false;stream.destroyed=false;
 stream.destroy=()=>{stream.destroyed=true;};
 const fixture={close:async()=>{clusterClosed=true;return {removed:true};}};
 await assert.rejects(closeOwnedFixture(fixture,[{connection:{stream},end:async()=>{}}],{graceMs:10,forceMs:10}),
  /owned_client_close_unconfirmed/);
 assert.equal(stream.destroyed,true);assert.equal(stream.closed,false);assert.equal(clusterClosed,true);

 // An end() that resolves just before the close event should not cause a
 // needless destroy, but must still wait for the observed closure.
 let forced=0;const delayed=new EventEmitter();delayed.closed=false;
 delayed.destroy=()=>{forced++;};
 const end=async()=>{setTimeout(()=>{delayed.closed=true;delayed.emit('close');},5);};
 await closeOwnedClients([{connection:{stream:delayed},end}],{graceMs:50,forceMs:20});
 assert.equal(delayed.closed,true);assert.equal(forced,0);
});

test('event-trigger catalogue drift invalidates a reviewed migration preimage', {timeout:120000},async t=>{
 const fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_event_trigger_fixture'}),clients=[];
 const connect=async(user='postgres')=>{const c=new pg.Client({host:fixture.socket,port:fixture.port,database:'postgres',user,connectionTimeoutMillis:3000});
  c.on('error',()=>{});clients.push(c);await c.connect();return c;};
 const wrap=async()=>{const c=await connect(),connection=new EventEmitter();
  connection.stream={encrypted:true,authorized:true,servername:`db.${PROJECT}.supabase.co`,destroy(){c.connection.stream?.destroy();}};
  c.connection.on('readyForQuery',msg=>connection.emit('readyForQuery',msg));
  return {connection,connectionParameters:{host:`db.${PROJECT}.supabase.co`,port:5432,database:'postgres',user:'postgres',ssl:{rejectUnauthorized:true,ca:loadProviderRoot()}},
   query:(...a)=>c.query(...a)};
 };
 try{
  const bootstrap=await connect('fixture_bootstrap');
  await bootstrap.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS;
   CREATE ROLE collect_runtime;CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_importer;
   CREATE ROLE synthetic_provider SUPERUSER NOLOGIN;ALTER DATABASE postgres OWNER TO postgres;`);
  const admin=await connect();
  assert.deepEqual((await admin.query('SELECT current_user AS name,rolsuper FROM pg_roles WHERE rolname=current_user')).rows[0],{name:'postgres',rolsuper:false});
  await admin.query(`CREATE SCHEMA app;CREATE SCHEMA private;CREATE SCHEMA auth;CREATE SCHEMA supabase_migrations;CREATE SCHEMA event_probe;
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
   CREATE TABLE app.privacy_retention_barriers(subject_id text);
   CREATE FUNCTION event_probe.handler() RETURNS event_trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN NULL;END$$;
   CREATE FUNCTION event_probe.other_handler() RETURNS event_trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$BEGIN NULL;END$$;`);
  for(const e of entries.slice(0,14)){
   const sql=await readFile(new URL(`../../../supabase/migrations/${e.version}_${e.name}.sql`,import.meta.url),'utf8');
   await admin.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2,$3)',[e.version,e.name,[sql]]);
  }
  await bootstrap.query(`CREATE EVENT TRIGGER z_ddl ON ddl_command_end WHEN TAG IN ('CREATE TABLE') EXECUTE FUNCTION event_probe.handler();
   CREATE EVENT TRIGGER a_drop ON sql_drop EXECUTE FUNCTION event_probe.other_handler();
   ALTER EVENT TRIGGER a_drop DISABLE;`);
  const capture=async()=>capturePinnedPreimage(await wrap(),args);
  const execute=async(pin)=>executePinnedMigration(await wrap(),{...args,expectedPreimageSha:pin});
  const original=await capture();
  await t.test('stable capture inventories all triggers, including disabled ones, without disclosing function bodies',async()=>{
   const repeat=await capture();assert.equal(original.sha256,repeat.sha256);
   assert.equal(original.preimage.format,'collect.atomic-cloud-preimage.v3');
   assert.deepEqual(original.preimage.eventTriggers.map(x=>[x.name,x.event,x.enabled,x.tags]),
    [['a_drop','sql_drop','D',null],['z_ddl','ddl_command_end','O',['CREATE TABLE']]]);
   const a=original.preimage.eventTriggers[1];
   assert.equal(a.owner,'fixture_bootstrap');assert.equal(a.handler_owner,'postgres');assert.equal(a.handler_security_definer,'true');
   assert.deepEqual(a.handler_search_path,['search_path=pg_catalog']);assert.match(a.handler_definition_sha256,/^[a-f0-9]{64}$/);
   assert.doesNotMatch(JSON.stringify(original.preimage.eventTriggers),/BEGIN NULL;END/);
  });
  const unchanged=async()=>{
   assert.equal((await admin.query('SELECT count(*)::int AS n FROM supabase_migrations.schema_migrations')).rows[0].n,14);
   assert.equal((await admin.query("SELECT to_regclass('app.client_diagnostic_reports') AS target")).rows[0].target,null);
  };
  const refuseDrift=async({change,restore,field,expected,inspect})=>{
   await change();try{
    const changed=await capture();assert.notEqual(changed.sha256,original.sha256);
    if(field){const before=original.preimage.eventTriggers.find(x=>x.name==='z_ddl');const after=changed.preimage.eventTriggers.find(x=>x.name==='z_ddl');
     assert.notDeepEqual(after[field],before[field]);if(expected!==undefined)assert.deepEqual(after[field],expected);if(inspect)inspect(before,after);}
    await assert.rejects(execute(original.sha256),{name:'AtomicMigrationError',code:'target_preimage_mismatch'});await unchanged();
   }finally{await restore();}
   assert.equal((await capture()).sha256,original.sha256);
  };
  await t.test('additional event trigger is rejected without a migration write',async()=>{
   await refuseDrift({change:()=>bootstrap.query('CREATE EVENT TRIGGER transient_ddl ON ddl_command_end EXECUTE FUNCTION event_probe.handler()'),
    restore:()=>bootstrap.query('DROP EVENT TRIGGER transient_ddl')});
  });
  await t.test('enable-state drift is rejected',async()=>{
   await refuseDrift({change:()=>bootstrap.query('ALTER EVENT TRIGGER z_ddl DISABLE'),restore:()=>bootstrap.query('ALTER EVENT TRIGGER z_ddl ENABLE'),field:'enabled',expected:'D'});
  });
  await t.test('tag-filter drift is rejected independently of trigger identity',async()=>{
   // ALTER EVENT TRIGGER does not expose a tag edit. This superuser catalogue
   // mutation is limited to the disposable synthetic cluster and preserves OID
   // so the test specifically establishes that the tag field is fingerprinted.
   await bootstrap.query('SET allow_system_table_mods=on');
   try{await refuseDrift({change:()=>bootstrap.query("UPDATE pg_catalog.pg_event_trigger SET evttags=ARRAY['ALTER TABLE'] WHERE evtname='z_ddl'"),
    restore:()=>bootstrap.query("UPDATE pg_catalog.pg_event_trigger SET evttags=ARRAY['CREATE TABLE'] WHERE evtname='z_ddl'"),field:'tags',expected:['ALTER TABLE']});}
   finally{await bootstrap.query('RESET allow_system_table_mods');}
  });
  await t.test('event and handler identity drift are rejected on the same trigger OID',async()=>{
   // Fixture-only catalogue mutations exercise attributes without relying on a
   // drop/recreate, whose changed OID would independently alter the digest.
   await bootstrap.query('SET allow_system_table_mods=on');
   try{
    await refuseDrift({change:()=>bootstrap.query("UPDATE pg_catalog.pg_event_trigger SET evtevent='sql_drop' WHERE evtname='z_ddl'"),
     restore:()=>bootstrap.query("UPDATE pg_catalog.pg_event_trigger SET evtevent='ddl_command_end' WHERE evtname='z_ddl'"),field:'event',expected:'sql_drop'});
    await refuseDrift({change:()=>bootstrap.query("UPDATE pg_catalog.pg_event_trigger SET evtfoid='event_probe.other_handler()'::regprocedure WHERE evtname='z_ddl'"),
     restore:()=>bootstrap.query("UPDATE pg_catalog.pg_event_trigger SET evtfoid='event_probe.handler()'::regprocedure WHERE evtname='z_ddl'"),field:'handler_name',expected:'other_handler'});
   }finally{await bootstrap.query('RESET allow_system_table_mods');}
  });
  await t.test('handler body, search path, and ownership drift are rejected',async()=>{
   await refuseDrift({change:()=>admin.query('CREATE OR REPLACE FUNCTION event_probe.handler() RETURNS event_trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN PERFORM 1;END$$'),
    restore:()=>admin.query('CREATE OR REPLACE FUNCTION event_probe.handler() RETURNS event_trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog AS $$BEGIN NULL;END$$'),field:'handler_definition_sha256'});
   await refuseDrift({change:()=>admin.query('ALTER FUNCTION event_probe.handler() SET search_path=event_probe,pg_catalog'),
    restore:()=>admin.query('ALTER FUNCTION event_probe.handler() SET search_path=pg_catalog'),field:'handler_search_path'});
   await refuseDrift({change:()=>bootstrap.query('ALTER FUNCTION event_probe.handler() OWNER TO collect_importer'),
    restore:()=>bootstrap.query('ALTER FUNCTION event_probe.handler() OWNER TO postgres'),field:'handler_owner',expected:'collect_importer'});
   await refuseDrift({change:()=>bootstrap.query('ALTER EVENT TRIGGER z_ddl OWNER TO synthetic_provider'),
    restore:()=>bootstrap.query('ALTER EVENT TRIGGER z_ddl OWNER TO fixture_bootstrap'),field:'owner',expected:'synthetic_provider'});
  });
  await t.test('changing handler SECURITY DEFINER to INVOKER is rejected',async()=>{
   await refuseDrift({change:()=>admin.query('ALTER FUNCTION event_probe.handler() SECURITY INVOKER'),
    restore:()=>admin.query('ALTER FUNCTION event_probe.handler() SECURITY DEFINER'),field:'handler_security_definer',expected:'false'});
  });
  await t.test('handler configuration outside search_path changes the definition hash and is rejected',async()=>{
   await refuseDrift({change:()=>admin.query("ALTER FUNCTION event_probe.handler() SET statement_timeout='1s'"),
    restore:()=>admin.query('ALTER FUNCTION event_probe.handler() RESET statement_timeout'),field:'handler_definition_sha256',
    inspect:(before,after)=>{assert.deepEqual(after.handler_search_path,before.handler_search_path);
     assert.equal(after.handler_security_definer,before.handler_security_definer);}});
  });
  await t.test('a correctly serialized v2-style digest cannot authorize the v3 executor',async()=>{
   // v2 used the same ordered fields through defaultAcls, without the event
   // trigger inventory. Preserve that serialization and change only the format.
   const {eventTriggers,...v2}=original.preimage;assert.ok(eventTriggers.length>0);
   assert.deepEqual(Object.keys(v2),['format','projectRef','version','sourceSha256','history','database','serverVersion',
    'sessionRole','activeRole','fence','schemas','relations','functions','roles','memberships','defaultAcls']);
   v2.format='collect.atomic-cloud-preimage.v2';
   const digest=createHash('sha256').update(JSON.stringify(v2)).digest('hex');assert.notEqual(digest,original.sha256);
   await assert.rejects(execute(digest),{name:'AtomicMigrationError',code:'target_preimage_mismatch'});await unchanged();
  });
  await t.test('a still-matching reviewed preimage can commit the exact pinned migration',async()=>{
   assert.equal((await execute(original.sha256)).status,'committed');
   assert.equal((await admin.query('SELECT count(*)::int AS n FROM supabase_migrations.schema_migrations')).rows[0].n,15);
   assert.equal((await admin.query("SELECT to_regclass('app.client_diagnostic_reports') IS NOT NULL AS present")).rows[0].present,true);
  });
 }finally{
  await closeOwnedFixture(fixture,clients);
 }
});
