// TEST-ONLY. This module creates, owns and destroys a new socket-only PG17
// cluster. It never accepts a host, port, client, credential or existing DB.
import {copyFile,mkdir,readFile} from 'node:fs/promises';
import {randomBytes,createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {join,resolve} from 'node:path';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {EXACT_CURRENT16,loadReviewedPlatformFixture,renderSyntheticSql} from '../testing/curated-platform-fixture.mjs';
import {pinnedMigrationIdentities} from '../atomic_cloud_migration.mjs';
import {BIN,verifyBinaryPins,verifyEnvironment} from '../managed-identity-provider-compat/fixture-safety.mjs';
const ROOT=resolve(import.meta.dirname,'../../..');
const {Client}=createRequire(import.meta.url)('pg');
const sha=x=>createHash('sha256').update(x).digest('hex');
const need=(ok,code)=>{if(!ok)throw Error(code);};
const expected=pinnedMigrationIdentities();
const bounded=(promise,ms)=>new Promise(resolve=>{
 let done=false;const timer=setTimeout(()=>{if(!done){done=true;resolve(false);}},ms);
 promise.then(value=>{if(!done){done=true;clearTimeout(timer);resolve(value);}},()=>{if(!done){done=true;clearTimeout(timer);resolve(false);}});
});
async function closeClients(clients){
 const results=await Promise.all(clients.map(async c=>{
  const stream=c.connection?.stream;if(!stream||stream.closed)return true;
  let listener;const closed=new Promise(resolve=>{listener=()=>resolve(true);stream.once('close',listener);});
  try{
   void Promise.resolve().then(()=>c.end()).catch(()=>{});
   if(await bounded(closed,1000)||stream.closed)return true;
   try{stream.destroy();}catch{return false;}
   return await bounded(closed,2000)||stream.closed===true;
  }finally{stream.removeListener('close',listener);}
 }));return results.every(Boolean);
}

// Only the internal executor can obtain a context. The external callback gets
// the clients solely to introduce synthetic drift in the owned disposable DB.
export async function withOwnedArchiveFixture(run){
 let f;const clients=[];
 try{
  verifyEnvironment(process.env);await verifyBinaryPins();
  f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_archive_next_fixture'});
  need(f.bin===BIN,'PINNED_SYNTHETIC_PG_REQUIRED');
  async function connect(user,database){const c=new Client({host:f.socket,port:f.port,user,database,connectionTimeoutMillis:5000,statement_timeout:65000});c.on('error',()=>{});await c.connect();clients.push(c);return c;}
  const bootstrap=await connect('fixture_bootstrap','postgres');
  const own=(await bootstrap.query("SELECT session_user u,current_user c,inet_server_addr() IS NULL sock,current_setting('cluster_name') n,current_setting('server_version_num')::int/10000 v")).rows[0];
  need(own.u==='fixture_bootstrap'&&own.c===own.u&&own.sock&&own.n==='collect_archive_next_fixture'&&own.v===17,'OWNED_FIXTURE_REQUIRED');
  await bootstrap.query('CREATE ROLE fixture_custodian LOGIN SUPERUSER');
  const custodian=await connect('fixture_custodian','postgres');
  await bootstrap.end();
  await custodian.query('ALTER ROLE fixture_bootstrap RENAME TO collect_test');
  await custodian.end();
  const root=await connect('collect_test','postgres');await root.query('DROP ROLE fixture_custodian');
  const database='collect_archive_'+randomBytes(12).toString('hex')+'_test';
  await root.query(`CREATE DATABASE "${database}" OWNER collect_test TEMPLATE template0 ENCODING 'UTF8'`);
  const admin=await connect('collect_test',database);
  const prefix=join(f.root,'original16');
  await mkdir(join(prefix,'supabase/migrations'),{recursive:true});await mkdir(join(prefix,'supabase/tests/sql'),{recursive:true});
  for(const name of EXACT_CURRENT16)await copyFile(join(ROOT,'supabase/migrations',name),join(prefix,'supabase/migrations',name));
  await copyFile(join(ROOT,'supabase/tests/sql/00_local_auth_fixture.sql'),join(prefix,'supabase/tests/sql/00_local_auth_fixture.sql'));
  const base=await loadReviewedPlatformFixture(prefix,{includeStoppedAdmissionLifecycleMigration:true});
  const original16=[...base.rawMigrations,base.clientDiagnostics,base.notificationDelivery];
  need(original16.length===16&&expected.length===16,'EXACT_16_REQUIRED');
  for(let i=0;i<16;i++)need(original16[i].name===`${expected[i].version}_${expected[i].name}.sql`&&original16[i].sha256===expected[i].sha256,'PREDECESSOR_SOURCE_CHANGED');
  await admin.query(base.auth);
  for(const item of base.rawMigrations.slice(0,8))await admin.query(item.sql);
  // A purely synthetic primary account and its immutable link precede the
  // original fence; no real account identifiers or provider data are used.
  await admin.query(`INSERT INTO auth.users(id,email) VALUES('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','synthetic@example.invalid');
   INSERT INTO app.users(id,email,public_id,created_at,updated_at) VALUES('synthetic-primary','synthetic@example.invalid','synthetic-public','2026-01-01','2026-01-01');
   INSERT INTO private.auth_principal_links(auth_user_id,user_id,proof_reference) VALUES('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','synthetic-primary','synthetic-proof')`);
  await admin.query(base.rawMigrations[8].sql);
  const realtime=await readFile(join(ROOT,'scripts/supabase/testing/member-realtime-interface.sql'));
  need(sha(realtime)===base.binding.interface_sha256,'SYNTHETIC_REALTIME_INTERFACE_CHANGED');
  await admin.query(realtime.toString('utf8'));
  let refused=false;try{await admin.query(base.rawMigrations[9].sql);}catch(e){refused=e.code==='55000'&&e.message==='member_realtime_metadata_not_reviewed';}
  finally{await admin.query('ROLLBACK');}
  need(refused,'HOSTED_REALTIME_PREIMAGE_MUST_REFUSE_FIXTURE');
  const syntheticRealtime=renderSyntheticSql(base.rawMigrations[9].sql,base.binding);
  await admin.query(syntheticRealtime);
  for(const item of base.rawMigrations.slice(10,13))await admin.query(item.sql);
  // Transfer ownership inside the brand-new fixture to a non-superuser, matching
  // the ownership prerequisites of the real stopped-admission migration.
  await admin.query(`DO $fixture$ DECLARE r record; BEGIN
   IF current_database()<>'${database}' OR inet_server_addr() IS NOT NULL OR current_setting('cluster_name')<>'collect_archive_next_fixture'
    OR session_user<>'collect_test' THEN RAISE EXCEPTION 'OWNED_FIXTURE_REQUIRED';END IF;
   FOR r IN SELECT nspname FROM pg_namespace WHERE nspowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND nspname NOT LIKE 'pg_%' AND nspname<>'information_schema' LOOP EXECUTE format('ALTER SCHEMA %I OWNER TO postgres',r.nspname);END LOOP;
   FOR r IN SELECT c.oid::regclass obj,c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND c.relkind IN('r','p','v','m','f') LOOP EXECUTE format('ALTER %s %s OWNER TO postgres',CASE r.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END,r.obj);END LOOP;
   FOR r IN SELECT c.oid::regclass obj FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND c.relkind='S' LOOP EXECUTE format('ALTER SEQUENCE %s OWNER TO postgres',r.obj);END LOOP;
   FOR r IN SELECT p.oid::regprocedure obj FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND p.prokind='f' LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',r.obj);END LOOP;
  END;$fixture$;`);
  await root.query(`ALTER DATABASE "${database}" OWNER TO postgres`);
  await root.query('ALTER ROLE postgres LOGIN NOSUPERUSER NOINHERIT CREATEROLE NOCREATEDB NOBYPASSRLS NOREPLICATION');
  const owner=await connect('postgres',database),watcher=await connect('collect_test',database);
  await owner.query(base.stoppedAdmissionLifecycle.sql);await owner.query(base.clientDiagnostics.sql);await owner.query(base.notificationDelivery.sql);
  await owner.query('CREATE SCHEMA supabase_migrations; CREATE TABLE supabase_migrations.schema_migrations(version text PRIMARY KEY,name text,statements text[])');
  const executed=original16.map((x,i)=>({version:expected[i].version,name:expected[i].name,sql:i===9?syntheticRealtime:x.sql,sha256:i===9?base.binding.synthetic_sql_sha256:x.sha256}));
  // Synthetic setup history records only SQL actually executed above; realtime
  // intentionally records the fixture bytes rather than the hosted bytes.
  for(const row of executed)await owner.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',[row.version,row.name,[row.sql]]);
  const id=(await owner.query("SELECT current_database() d,session_user s,current_user c,inet_server_addr() IS NULL socket,current_setting('cluster_name') n,current_setting('server_version_num')::int/10000 v,pg_backend_pid() p")).rows[0];
  need(id.d===database&&id.s==='postgres'&&id.c==='postgres'&&id.socket&&id.n==='collect_archive_next_fixture'&&id.v===17,'OWNED_OWNER_CONNECTION_REQUIRED');
  return await run({owner,admin,watcher,database,backendPid:id.p,executed,fixtureRoot:f.root});
 }finally{
  const clientsClosed=await closeClients(clients);
  if(f){const result=await f.close();need(result.removed===true&&clientsClosed,'FIXTURE_STOP_UNCONFIRMED');}
  await verifyBinaryPins();
 }
}
