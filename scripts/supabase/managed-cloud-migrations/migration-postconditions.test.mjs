import {loadProviderRoot} from './provider-ca.mjs';
// Owned synthetic PG17 cluster, private socket only. The adapter's TLS
// metadata is simulated; this does not establish hosted Supabase behavior.
import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {createHash} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from '../node_modules/pg/lib/index.js';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {capturePinnedPreimage,executePinnedMigration,pinnedMigrationIdentities} from '../atomic_cloud_migration.mjs';

const PROJECT='rrlduytparvsjfmegalh',entries=pinnedMigrationIdentities();
async function bounded(promise,ms){let timer;try{return await Promise.race([promise,new Promise(resolve=>{timer=setTimeout(()=>resolve(null),ms);})]);}finally{clearTimeout(timer);}}
async function closeClients(clients,{graceMs=1000,forceMs=1500}={}){
 const result=await Promise.all(clients.map(async c=>{
  let stream;try{stream=c.connection?.stream;}catch{return false;}
  let observed=false,signal;const closed=new Promise(resolve=>{signal=resolve;});
  const onClose=()=>{observed=true;signal(true);};
  const isClosed=()=>observed||stream?.closed===true;
  try{
   // Some stream implementations can attach the listener and then throw.
   // Keep its original reference and remove it in finally in either case.
   try{if(typeof stream?.once==='function')stream.once('close',onClose);}catch{}
   const ended=await bounded(Promise.resolve().then(()=>c.end()).then(()=>true,()=>false),graceMs);
   if(isClosed())return true;
   if(ended){await bounded(closed,graceMs);if(isClosed())return true;}
   if(!stream||typeof stream.destroy!=='function')return false;
   try{stream.destroy();}catch{return false;}
   if(!isClosed())await bounded(closed,forceMs);return isClosed();
  }finally{try{if(typeof stream?.removeListener==='function')stream.removeListener('close',onClose);}catch{}}
 }));
 if(result.some(x=>!x))throw new Error('owned_client_close_unconfirmed');
}
async function closeFixture(fixture,clients,timeouts){
 try{await closeClients(clients,timeouts);}
 finally{const stopped=await fixture.close();assert.equal(stopped.removed,true,'owned fixture cleanup unconfirmed');}
}

test('fixture cleanup removes a listener when stream.once attaches then throws',async()=>{
 const stream=new EventEmitter();let stopped=false;stream.closed=false;stream.destroyed=false;
 const once=stream.once.bind(stream);
 stream.once=(event,listener)=>{once(event,listener);throw new Error('synthetic subscribe failure');};
 stream.destroy=()=>{stream.destroyed=true;};
 const fixture={close:async()=>{stopped=true;return {removed:true};}};
 await assert.rejects(closeFixture(fixture,[{connection:{stream},end:async()=>{}}],{graceMs:10,forceMs:10}),
  /owned_client_close_unconfirmed/);
 assert.equal(stream.destroyed,true);assert.equal(stream.closed,false);
 assert.equal(stream.listenerCount('close'),0);assert.equal(stopped,true);
});

test('migration policy, trigger and handler postconditions roll back tampering', {timeout:120000},async t=>{
 const fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_migration_postconditions'}),clients=[];
 const connect=async(user='postgres')=>{const c=new pg.Client({host:fixture.socket,port:fixture.port,database:'postgres',user,connectionTimeoutMillis:3000});
  c.on('error',()=>{});clients.push(c);await c.connect();return c;};
 const wrap=async({afterBody,afterHistory}={})=>{
  const c=await connect(),connection=new EventEmitter();let injected=false;
  connection.stream={encrypted:true,authorized:true,servername:`db.${PROJECT}.supabase.co`,destroy(){c.connection.stream?.destroy();}};
  c.connection.on('readyForQuery',msg=>connection.emit('readyForQuery',msg));
  return {connection,connectionParameters:{host:`db.${PROJECT}.supabase.co`,port:5432,database:'postgres',user:'postgres',ssl:{rejectUnauthorized:true,ca:loadProviderRoot()}},
   async query(sql,values){
    const result=await c.query(sql,values);
    const body=sql.includes('CREATE TABLE app.client_diagnostic_reports')||sql.includes('CREATE TABLE app.notification_deliveries');
    const history=sql.startsWith('INSERT INTO supabase_migrations.schema_migrations');
    if(!injected&&((afterBody&&body)||(afterHistory&&history))){injected=true;await c.query(afterBody??afterHistory);}
    return result;
   }};
 };
 const input=e=>({version:e.version,expectedSha:e.sha256});
 const capture=async e=>capturePinnedPreimage(await wrap(),input(e));
 const execute=async(e,pin,mutation)=>executePinnedMigration(await wrap(mutation),{...input(e),expectedPreimageSha:pin});
 try{
  const bootstrap=await connect('fixture_bootstrap');
  await bootstrap.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS;
   CREATE ROLE collect_runtime;CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_importer;
   ALTER DATABASE postgres OWNER TO postgres;`);
  const admin=await connect();
  assert.deepEqual((await admin.query('SELECT current_user AS name,rolsuper FROM pg_roles WHERE rolname=current_user')).rows[0],{name:'postgres',rolsuper:false});
  await admin.query(`CREATE SCHEMA app;CREATE SCHEMA private;CREATE SCHEMA auth;CREATE SCHEMA supabase_migrations;
   GRANT USAGE ON SCHEMA private TO collect_runtime;
   CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,name text,statements text[]);
   CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,project_ref text,mode text,source_sha256 text,epoch bigint,operation_id uuid);
   INSERT INTO private.collect_fence_control VALUES(true,'rrlduytparvsjfmegalh','fenced',repeat('a',64),13,'11111111-1111-4111-8111-111111111111');
   CREATE FUNCTION private._collect_fence_statement() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$BEGIN RETURN NULL; END$$;
   CREATE FUNCTION app.unixepoch() RETURNS bigint LANGUAGE SQL AS $$SELECT 1::bigint$$;
   CREATE TABLE app.users(id text PRIMARY KEY,access_status text,member_type text);
   CREATE TABLE app.auth_sessions(id text PRIMARY KEY,user_id text,surface text,revoked_at bigint,expires_at bigint);
   CREATE TABLE private.auth_principal_links(user_id text,auth_user_id uuid);
   CREATE TABLE auth.users(id uuid PRIMARY KEY,deleted_at timestamptz,banned_until timestamptz);
   CREATE TABLE auth.sessions(id uuid PRIMARY KEY,user_id uuid,not_after timestamptz);
   CREATE TABLE app.notification_events(id text,user_id text,event_type text,status text,created_at bigint,data_json text);
   CREATE TABLE app.notification_devices(id text,user_id text,owner_session_id text,active integer,platform text,provider text,token_hash text);
   CREATE TABLE app.memberships(user_id text,collection_id text,active integer);
   CREATE TABLE app.collections(id text,status text);
   CREATE TABLE app.notification_preferences(user_id text,push_enabled integer,payment_updates integer);
   CREATE TABLE app.privacy_retention_barriers(subject_id text);`);
  let notificationSource;
  for(let i=0;i<entries.length;i++){
   const e=entries[i],text=await readFile(new URL(`../../../supabase/migrations/${e.version}_${e.name}.sql`,import.meta.url),'utf8');
   assert.equal(createHash('sha256').update(text).digest('hex'),e.sha256);
   if(i<14)await admin.query('INSERT INTO supabase_migrations.schema_migrations VALUES($1,$2,$3)',[e.version,e.name,[text]]);
   if(i===15)notificationSource=text;
  }
  await t.test('pinned source contains the expected handler body bytes',()=>{
   for(const [name,digest] of [['notification_delivery_eligible','a73a683350d36e98f8cc6ad58ec8282f35f97810dcbe501c1d2a5e012bc43b14'],
    ['notification_delivery_guard','fa428c8984e60270924304b21766397313a5373f8ed3dcba012bc4017507932a']]){
    const re=new RegExp(`^CREATE FUNCTION private\\.${name}\\([^\\n]*\\)\\s*RETURNS [^\\n]*? AS \\$\\$([\\s\\S]*?)\\$\\$;`,'gm');
    const matches=[...notificationSource.matchAll(re)];assert.equal(matches.length,1);
    assert.equal(createHash('sha256').update(matches[0][1]).digest('hex'),digest);
   }
  });
  async function unchanged(index,table){
   assert.equal((await admin.query('SELECT count(*)::int AS n FROM supabase_migrations.schema_migrations')).rows[0].n,index);
   assert.equal((await admin.query('SELECT to_regclass($1) AS target',[`app.${table}`])).rows[0].target,null);
  }
  async function exercise(index,cases){
   const e=entries[index],table=index===14?'client_diagnostic_reports':'notification_deliveries',pin=(await capture(e)).sha256;
   for(const [description,sql,afterHistory=false] of cases)await t.test(description,async()=>{
    await assert.rejects(execute(e,pin,afterHistory?{afterHistory:sql}:{afterBody:sql}),{name:'AtomicMigrationError',code:'postcondition_mismatch'});
    await unchanged(index,table);
   });
   await t.test(`untampered ${e.version} commits`,async()=>{
    assert.equal((await execute(e,pin)).status,'committed');
    assert.equal((await admin.query('SELECT count(*)::int AS n FROM supabase_migrations.schema_migrations')).rows[0].n,index+1);
    assert.equal((await admin.query('SELECT to_regclass($1) IS NOT NULL AS present',[`app.${table}`])).rows[0].present,true);
   });
  }
  await exercise(14,[
   ['diagnostics rejects an extra policy','CREATE POLICY extra_policy ON app.client_diagnostic_reports TO anon USING(true)'],
   ['diagnostics rejects a missing policy','DROP POLICY client_diagnostic_runtime ON app.client_diagnostic_reports'],
   ['diagnostics rejects a different policy role','ALTER POLICY client_diagnostic_runtime ON app.client_diagnostic_reports TO anon'],
   ['diagnostics rejects a changed policy predicate','ALTER POLICY client_diagnostic_runtime ON app.client_diagnostic_reports USING(false)'],
   ['diagnostics rejects a disabled fence trigger','ALTER TABLE app.client_diagnostic_reports DISABLE TRIGGER collect_fence_statement_v1'],
   ['diagnostics rejects a missing fence trigger','DROP TRIGGER collect_fence_statement_v1 ON app.client_diagnostic_reports'],
   ['diagnostics rejects an extra trigger','CREATE TRIGGER extra_trigger BEFORE INSERT ON app.client_diagnostic_reports FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement()'],
   ['diagnostics rejects a fence trigger with arguments',`DROP TRIGGER collect_fence_statement_v1 ON app.client_diagnostic_reports;
    CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON app.client_diagnostic_reports FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement('extra');
    ALTER TABLE app.client_diagnostic_reports ENABLE ALWAYS TRIGGER collect_fence_statement_v1`],
   ['diagnostics rejects fence handler body drift','CREATE OR REPLACE FUNCTION private._collect_fence_statement() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$BEGIN RETURN OLD; END$$'],
   ['diagnostics rechecks after history insertion','DROP POLICY client_diagnostic_runtime ON app.client_diagnostic_reports',true],
  ]);
  await exercise(15,[
   ['notification rejects an extra policy','CREATE POLICY extra_policy ON app.notification_deliveries TO anon USING(true)'],
   ['notification rejects a changed policy check','ALTER POLICY notification_delivery_runtime ON app.notification_deliveries WITH CHECK(false)'],
   ['notification rejects a disabled identity trigger','ALTER TABLE app.notification_deliveries DISABLE TRIGGER notification_delivery_identity'],
   ['notification rejects a missing identity trigger','DROP TRIGGER notification_delivery_identity ON app.notification_deliveries'],
   ['notification rejects a wrong trigger handler',`DROP TRIGGER notification_delivery_identity ON app.notification_deliveries;
    CREATE TRIGGER notification_delivery_identity BEFORE INSERT OR UPDATE OR DELETE ON app.notification_deliveries FOR EACH ROW EXECUTE FUNCTION private._collect_fence_statement();
    ALTER TABLE app.notification_deliveries ENABLE ALWAYS TRIGGER notification_delivery_identity`],
   ['notification rejects guard-body drift','CREATE OR REPLACE FUNCTION private.notification_delivery_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$BEGIN RETURN NEW;END$$'],
   ['notification rejects eligibility-body drift',`CREATE OR REPLACE FUNCTION private.notification_delivery_eligible(p_event_id text,p_device_id text,p_user_id text,p_session_id text,p_token_sha256 text,p_event_sha256 text)
    RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog AS $$SELECT true$$`],
   ['notification rejects changed eligibility volatility','ALTER FUNCTION private.notification_delivery_eligible(text,text,text,text,text,text) VOLATILE'],
   ['notification rejects added handler configuration',"ALTER FUNCTION private.notification_delivery_guard() SET statement_timeout='1s'"],
   ['notification rechecks after history insertion','DROP TRIGGER notification_delivery_identity ON app.notification_deliveries',true],
  ]);
 }finally{
  await closeFixture(fixture,clients);
 }
});
