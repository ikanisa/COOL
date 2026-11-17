import {loadProviderRoot} from './managed-cloud-migrations/provider-ca.mjs';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {readFile,realpath} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {extractSupportedBody,pinnedMigrationIdentities,capturePinnedPreimage,executePinnedMigration,reconcilePinnedMigration} from './atomic_cloud_migration.mjs';
import {startOwnedPg17} from './current-pg-transfer/test-support/owned-pg17.mjs';

const entries=pinnedMigrationIdentities(),first=entries[14],second=entries[15];
const args=e=>({version:e.version,expectedSha:e.sha256});
const code=expected=>error=>error?.code===expected&&!String(error).includes('synthetic-secret');
const pgliteSpecifier=process.env.COLLECT_ATOMIC_TEST_PGLITE_MODULE??'@electric-sql/pglite';
let pglite;try{pglite=await import(pgliteSpecifier);}catch{}
const integration={skip:pglite?.PGlite?false:'Install the pinned PGlite dependency or supply COLLECT_ATOMIC_TEST_PGLITE_MODULE.'};

test('synthetic PostgreSQL integration engine is available',()=>{
 assert.ok(pglite?.PGlite,'Install the pinned @electric-sql/pglite package or supply COLLECT_ATOMIC_TEST_PGLITE_MODULE; skipped database tests are not a pass');
});

test('SQL boundary scanner accepts the pinned forms and rejects escaping control',()=>{
 const valid="-- leading ; comment\nBEGIN;\nCREATE TABLE t(v text DEFAULT 'semi;colon');\nDO $$BEGIN RAISE NOTICE 'ok'; END$$;\nCOMMIT; -- trailing\n";
 assert.match(extractSupportedBody(valid),/CREATE TABLE/);
 for(const bad of [
  'BEGIN; CREATE TABLE t(id int); COMMIT; ROLLBACK;',
  'BEGIN; CREATE TABLE t(id int); BEGIN; COMMIT;',
  'BEGIN; DO $$BEGIN COMMIT; END$$; COMMIT;',
  "BEGIN; CREATE TABLE t(v text DEFAULT 'unterminated); COMMIT;",
  'BEGIN; SELECT 1; COMMIT;',
  'BEGIN; CREATE TABLE t(id int); COMMIT',
 ])assert.throws(()=>extractSupportedBody(bad),code('unsupported_sql'));
});

test('unknown migration and mismatched source digest fail before any database call',async()=>{
 let calls=0;const client={query(){calls++;}};
 await assert.rejects(executePinnedMigration(client,args({...first,sha256:'0'.repeat(64)})),code('unapproved_migration_identity'));
 await assert.rejects(executePinnedMigration(client,{version:'20261113130100',expectedSha:'0'.repeat(64)}),code('unapproved_migration_identity'));
 assert.equal(calls,0);
});

let fixturePid=1000;
class PgFixtureClient {
 constructor(db,{commitMode,failBody=false,postBodySql=''}={}){
  this.db=db;this.commitMode=commitMode;this.failBody=failBody;this.postBodySql=postBodySql;this.transaction=false;this.queries=[];this.backendPid=fixturePid++;this.processID=7000;
  this.connection=new EventEmitter();this.connection.stream={encrypted:true,authorized:true,servername:'db.rrlduytparvsjfmegalh.supabase.co',destroy(){this.destroyed=true;}};
  this.connectionParameters={host:'db.rrlduytparvsjfmegalh.supabase.co',port:5432,database:'postgres',user:'postgres',ssl:{rejectUnauthorized:true,ca:loadProviderRoot()}};
 }
 async query(sql,values){
  this.queries.push(sql.startsWith('INSERT INTO supabase_migrations')?'history_insert':sql.split(/\s+/).slice(0,2).join(' '));
  if(sql==='COMMIT'&&this.commitMode){
   const mode=this.commitMode;this.commitMode=undefined;
   await this.db.query(mode==='after'?'COMMIT':'ROLLBACK');this.transaction=false;
   this.connection.emit('readyForQuery',{status:'I'});throw Error('synthetic-secret lost commit acknowledgement');
  }
  try{
   let result;
   if(sql.includes('CREATE TABLE app.client_diagnostic_reports')||sql.includes('CREATE TABLE app.notification_deliveries')){
    await this.db.exec(sql+(this.failBody?'\nSELECT 1/0;':'')+'\n'+this.postBodySql);result={rows:[]};
   }else result=await this.db.query(sql,values);
   if(sql==='BEGIN')this.transaction=true;
   if(sql==='COMMIT'||sql==='ROLLBACK')this.transaction=false;
   // PGlite names its private in-memory database template1. Keep the actual
   // project-ref/mode and PG version from SQL. Its single backend cannot
   // represent independent pg sessions, so simulate their backend PID only.
   if(sql.includes('current_database() AS database')&&result.rows[0]?.database==='template1')result.rows[0].database='postgres';
   if(result.rows?.[0]?.backend_pid!==undefined)result.rows[0].backend_pid=this.backendPid;
   this.connection.emit('readyForQuery',{status:this.transaction?'T':'I'});
   return {...result,command:sql.split(/\s+/)[0].toUpperCase()};
  }catch(error){this.connection.emit('readyForQuery',{status:this.transaction?'E':'I'});throw error;}
 }
}

const syntheticSchema=`
  CREATE ROLE collect_runtime; CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE ROLE collect_importer;
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
  CREATE TABLE app.privacy_retention_barriers(subject_id text);
 `;
async function seedHistory(db){
 for(const entry of entries.slice(0,14)){
  const text=await readFile(new URL(`../../supabase/migrations/${entry.version}_${entry.name}.sql`,import.meta.url),'utf8');
  assert.equal(createHash('sha256').update(text).digest('hex'),entry.sha256);
  await db.query('INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES($1,$2,$3)',[entry.version,entry.name,[text]]);
 }
}
async function fixture(){
 const {PGlite}=pglite;const db=new PGlite();
 await db.exec(syntheticSchema);await seedHistory(db);
 return db;
}
async function exists(db,name){return (await db.query('SELECT to_regclass($1) IS NOT NULL AS present',[name])).rows[0].present;}
async function count(db){return Number((await db.query('SELECT count(*) AS n FROM supabase_migrations.schema_migrations')).rows[0].n);}
async function reviewed(db,entry){return {...args(entry),expectedPreimageSha:(await capturePinnedPreimage(new PgFixtureClient(db),args(entry))).sha256};}
const unchecked=entry=>({...args(entry),expectedPreimageSha:'0'.repeat(64)});

test('both pinned migrations commit in order with original text stored once',integration,async()=>{
 const db=await fixture();try{
  assert.equal((await executePinnedMigration(new PgFixtureClient(db),await reviewed(db,first))).status,'committed');
  assert.equal((await executePinnedMigration(new PgFixtureClient(db),await reviewed(db,second))).status,'committed');
  assert.equal(await count(db),16);assert.equal(await exists(db,'app.client_diagnostic_reports'),true);assert.equal(await exists(db,'app.notification_deliveries'),true);
  const rows=(await db.query('SELECT version,statements FROM supabase_migrations.schema_migrations WHERE version >= $1 ORDER BY version',[first.version])).rows;
  for(const [i,row] of rows.entries()){
   assert.equal(row.statements.length,1);assert.equal(createHash('sha256').update(row.statements[0]).digest('hex'),[first,second][i].sha256);
  }
  const ownership=(await db.query(`SELECT pg_get_userbyid(c.relowner) AS owner,c.relrowsecurity AS rls,c.relforcerowsecurity AS forced,
    has_table_privilege('collect_runtime',c.oid,'SELECT') AS readable,has_table_privilege('anon',c.oid,'SELECT') AS anonymous
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='app' AND c.relname='notification_deliveries'`)).rows[0];
  assert.deepEqual(ownership,{owner:'postgres',rls:true,forced:true,readable:true,anonymous:false});
  const fn=(await db.query(`SELECT pg_get_userbyid(p.proowner) AS owner,p.prosecdef AS definer FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private' AND p.proname='notification_delivery_eligible'`)).rows[0];
  assert.deepEqual(fn,{owner:'postgres',definer:true});
 }finally{await db.close();}
});

test('a reviewed backend pin must match before the migration transaction starts',integration,async()=>{
 const db=await fixture();try{
  const input=await reviewed(db,first),wrong=new PgFixtureClient(db);
  await assert.rejects(executePinnedMigration(wrong,{...input,expectedBackendPid:wrong.backendPid+1}),code('backend_changed'));
  assert.equal(wrong.queries.includes('BEGIN'),false);assert.equal(await count(db),14);
  const right=new PgFixtureClient(db);
  assert.equal((await executePinnedMigration(right,{...input,expectedBackendPid:right.backendPid})).status,'committed');
 }finally{await db.close();}
});

test('reviewed preimage is required and rejects fence or catalog drift',integration,async()=>{
 const db=await fixture();try{
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),args(first)),code('target_preimage_required'));
  const input=await reviewed(db,first);await db.query('UPDATE private.collect_fence_control SET epoch=epoch+1');
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),input),code('target_preimage_mismatch'));
  await db.query('UPDATE private.collect_fence_control SET epoch=epoch-1');
  await db.exec('ALTER TABLE app.users ADD COLUMN unexpected_drift text');
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),input),code('target_preimage_mismatch'));
  assert.equal(await count(db),14);assert.equal(await exists(db,'app.client_diagnostic_reports'),false);
 }finally{await db.close();}
});

test('default privilege and role-graph drift invalidate a reviewed preimage',integration,async()=>{
 const db=await fixture();try{
  await executePinnedMigration(new PgFixtureClient(db),await reviewed(db,first));
  await db.exec('CREATE ROLE audit_probe; GRANT USAGE ON SCHEMA private TO audit_probe');
  const input=await reviewed(db,second);
  await db.exec('ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private GRANT EXECUTE ON FUNCTIONS TO audit_probe');
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),input),code('target_preimage_mismatch'));
  await db.exec('ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA private REVOKE EXECUTE ON FUNCTIONS FROM audit_probe');
  await db.exec('GRANT collect_runtime TO audit_probe');
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),input),code('target_preimage_mismatch'));
  assert.equal(await count(db),15);assert.equal(await exists(db,'app.notification_deliveries'),false);
 }finally{await db.close();}
});

for(const [objectType,schema] of [['FUNCTIONS','private'],['TABLES','app']])test(`unsafe reviewed ${objectType} defaults roll back the migration`,integration,async()=>{
 const db=await fixture();try{
  await executePinnedMigration(new PgFixtureClient(db),await reviewed(db,first));
  await db.exec(`CREATE ROLE audit_probe; GRANT USAGE ON SCHEMA ${schema} TO audit_probe;
   ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA ${schema} GRANT ${objectType==='FUNCTIONS'?'EXECUTE':'SELECT'} ON ${objectType} TO audit_probe`);
  const input=await reviewed(db,second);
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),input),code('postcondition_mismatch'));
  assert.equal(await count(db),15);assert.equal(await exists(db,'app.notification_deliveries'),false);
  assert.equal((await db.query("SELECT to_regprocedure('private.notification_delivery_eligible(text,text,text,text,text,text)') IS NOT NULL AS present")).rows[0].present,false);
 }finally{await db.close();}
});

test('unreviewed CREATE access to the private schema fails the function postcondition',integration,async()=>{
 const db=await fixture();try{
  await executePinnedMigration(new PgFixtureClient(db),await reviewed(db,first));
  await db.exec('CREATE ROLE audit_probe; GRANT CREATE ON SCHEMA private TO audit_probe');
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),await reviewed(db,second)),code('postcondition_mismatch'));
  assert.equal(await count(db),15);assert.equal(await exists(db,'app.notification_deliveries'),false);
 }finally{await db.close();}
});

test('missing runtime schema usage fails closed',integration,async()=>{
 const db=await fixture();try{
  await executePinnedMigration(new PgFixtureClient(db),await reviewed(db,first));
  await db.exec('REVOKE USAGE ON SCHEMA private FROM collect_runtime');
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),await reviewed(db,second)),code('postcondition_mismatch'));
  assert.equal(await count(db),15);assert.equal(await exists(db,'app.notification_deliveries'),false);
 }finally{await db.close();}
});

for(const [label,grant] of [['PUBLIC','PUBLIC'],['an inherited group','audit_group']])test(`unexpected EXECUTE through ${label} rolls back`,integration,async()=>{
 const db=await fixture();try{
  await executePinnedMigration(new PgFixtureClient(db),await reviewed(db,first));
  await db.exec('CREATE ROLE audit_group; CREATE ROLE audit_probe; GRANT audit_group TO audit_probe');
  const input=await reviewed(db,second);
  const postBodySql=`GRANT EXECUTE ON FUNCTION private.notification_delivery_eligible(text,text,text,text,text,text) TO ${grant}`;
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db,{postBodySql}),input),code('postcondition_mismatch'));
  assert.equal(await count(db),15);assert.equal(await exists(db,'app.notification_deliveries'),false);
 }finally{await db.close();}
});

test('hostile session search_path cannot shadow catalog checks or SQL execution',integration,async()=>{
 const db=await fixture();try{
  await db.exec(`CREATE SCHEMA hostile;
   CREATE FUNCTION hostile.pg_backend_pid() RETURNS integer LANGUAGE SQL AS $$SELECT 42$$;
   CREATE FUNCTION hostile.sha256(bytea) RETURNS bytea LANGUAGE SQL AS $$SELECT decode('00','hex')$$;
   SET search_path=hostile,pg_catalog`);
  const input=await reviewed(db,first);
  assert.equal((await executePinnedMigration(new PgFixtureClient(db),input)).status,'committed');
  assert.equal(await exists(db,'app.client_diagnostic_reports'),true);
 }finally{await db.close();}
});

test('a session with a different active role is refused before DDL',integration,async()=>{
 const db=await fixture();try{
  await db.exec(`CREATE ROLE foreign_operator;
   GRANT USAGE ON SCHEMA private,supabase_migrations TO foreign_operator;
   GRANT ALL ON private.collect_fence_control,supabase_migrations.schema_migrations TO foreign_operator;
   SET ROLE foreign_operator`);
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),unchecked(first)),code('unreviewed_database_role'));
  await db.exec('RESET ROLE');assert.equal(await count(db),14);assert.equal(await exists(db,'app.client_diagnostic_reports'),false);
 }finally{await db.close();}
});

test('SQL body failure rolls back and leaves history unchanged',integration,async()=>{
 const db=await fixture();try{
  const input=await reviewed(db,first);
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db,{failBody:true}),input),code('migration_rolled_back'));
  assert.equal(await count(db),14);assert.equal(await exists(db,'app.client_diagnostic_reports_expiry'),false);
  assert.equal(await exists(db,'app.client_diagnostic_reports'),false);
 }finally{await db.close();}
});

test('history insert failure rolls back the already executed DDL',integration,async()=>{
 const db=await fixture();try{
  await db.exec(`CREATE FUNCTION private.reject_new_history() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'synthetic-secret'; END$$;
   CREATE TRIGGER reject_new_history BEFORE INSERT ON supabase_migrations.schema_migrations FOR EACH ROW EXECUTE FUNCTION private.reject_new_history()`);
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),await reviewed(db,first)),code('migration_rolled_back'));
  assert.equal(await count(db),14);assert.equal(await exists(db,'app.client_diagnostic_reports'),false);
 }finally{await db.close();}
});

for(const [mode,expected] of [['after','recorded'],['before','not_recorded']])test(`lost commit acknowledgement reconciles as ${expected}`,integration,async()=>{
 const db=await fixture();try{
  const original=new PgFixtureClient(db,{commitMode:mode});
  let uncertainty;try{await executePinnedMigration(original,await reviewed(db,first));assert.fail('expected unconfirmed commit');}catch(error){uncertainty=error;}
  assert(code('commit_unconfirmed')(uncertainty));assert.equal(uncertainty.backendPid,original.backendPid);
  await assert.rejects(reconcilePinnedMigration(original,{...args(first),priorBackendPid:uncertainty.backendPid}),code('client_discard_required'));
  const sameBackend=new PgFixtureClient(db);sameBackend.backendPid=original.backendPid;
  await assert.rejects(reconcilePinnedMigration(sameBackend,{...args(first),priorBackendPid:uncertainty.backendPid}),code('fresh_connection_required'));
  assert.equal((await reconcilePinnedMigration(new PgFixtureClient(db),{...args(first),priorBackendPid:uncertainty.backendPid})).status,expected);
  assert.equal(await exists(db,'app.client_diagnostic_reports'),mode==='after');
 }finally{await db.close();}
});

test('history mismatch and an unfenced target fail without applying the body',integration,async()=>{
 const db=await fixture();try{
  await db.query("UPDATE supabase_migrations.schema_migrations SET statements=ARRAY['changed'] WHERE version=$1",[entries[0].version]);
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),unchecked(first)),code('migration_history_mismatch'));
  assert.equal(await exists(db,'app.client_diagnostic_reports'),false);
  const original=await readFile(new URL(`../../supabase/migrations/${entries[0].version}_${entries[0].name}.sql`,import.meta.url),'utf8');
  await db.query('UPDATE supabase_migrations.schema_migrations SET statements=$1 WHERE version=$2',[[original],entries[0].version]);
  await db.query("UPDATE private.collect_fence_control SET mode='open'");
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),unchecked(first)),code('target_not_fenced'));
  assert.equal(await count(db),14);assert.equal(await exists(db,'app.client_diagnostic_reports'),false);
 }finally{await db.close();}
});

test('wrong project identity and out-of-order versions remain closed',integration,async()=>{
 const db=await fixture();try{
  await db.query("UPDATE private.collect_fence_control SET project_ref='other-project'");
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),unchecked(first)),code('target_identity_mismatch'));
  await db.query("UPDATE private.collect_fence_control SET project_ref='rrlduytparvsjfmegalh'");
  await assert.rejects(executePinnedMigration(new PgFixtureClient(db),unchecked(second)),code('migration_history_mismatch'));
  assert.equal(await count(db),14);assert.equal(await exists(db,'app.client_diagnostic_reports'),false);
 }finally{await db.close();}
});

test('a non-idle or unverified connection is refused before migration',integration,async()=>{
 const db=await fixture();try{
  const wrong=new PgFixtureClient(db);wrong.connection.stream.authorized=false;
  await assert.rejects(executePinnedMigration(wrong,unchecked(first)),code('unverified_database_connection'));
  const overridden=new PgFixtureClient(db);overridden.connectionParameters.ssl.checkServerIdentity=()=>undefined;
  await assert.rejects(executePinnedMigration(overridden,unchecked(first)),code('unverified_database_connection'));
  const wrongCA=new PgFixtureClient(db);wrongCA.connectionParameters.ssl.ca='synthetic-untrusted-ca';
  await assert.rejects(executePinnedMigration(wrongCA,unchecked(first)),code('unverified_database_connection'));
  const alternateContext=new PgFixtureClient(db);alternateContext.connectionParameters.ssl.secureContext={};
  await assert.rejects(executePinnedMigration(alternateContext,unchecked(first)),code('unverified_database_connection'));
  const wrongUser=new PgFixtureClient(db);wrongUser.connectionParameters.user='cli_login_postgres';
  await assert.rejects(executePinnedMigration(wrongUser,unchecked(first)),code('unverified_database_connection'));
  const wrongPooler=new PgFixtureClient(db);wrongPooler.connectionParameters.host='aws-1-eu-north-1.pooler.supabase.com';
  wrongPooler.connectionParameters.user='postgres.rrlduytparvsjfmegalh';wrongPooler.connection.stream.servername=wrongPooler.connectionParameters.host;
  await assert.rejects(executePinnedMigration(wrongPooler,unchecked(first)),code('unverified_database_connection'));
  const transactionPool=new PgFixtureClient(db);transactionPool.connectionParameters.host='aws-0-eu-north-1.pooler.supabase.com';
  transactionPool.connectionParameters.port=6543;transactionPool.connectionParameters.user='postgres.rrlduytparvsjfmegalh';transactionPool.connection.stream.servername=transactionPool.connectionParameters.host;
  await assert.rejects(executePinnedMigration(transactionPool,unchecked(first)),code('unverified_database_connection'));
  const existing=new PgFixtureClient(db);await existing.query('BEGIN');
  await assert.rejects(executePinnedMigration(existing,unchecked(first)),code('connection_not_idle'));
  await existing.query('ROLLBACK');assert.equal(await count(db),14);
 }finally{await db.close();}
});

test('failed rollback leaves the client unusable and does not auto-retry',integration,async()=>{
 const db=await fixture();try{
  const input=await reviewed(db,first),client=new PgFixtureClient(db,{failBody:true}),query=client.query.bind(client);
  client.query=async(sql,values)=>{if(sql==='ROLLBACK')throw Error('synthetic-secret rollback');return query(sql,values);};
  await assert.rejects(executePinnedMigration(client,input),code('rollback_unconfirmed'));
  await assert.rejects(executePinnedMigration(client,input),code('client_discard_required'));
  assert.equal(client.queries.filter(x=>x==='BEGIN').length,1);
 }finally{await db.close();}
});

test('reconciliation lock failure stays unconfirmed and never retries the body',integration,async()=>{
 const db=await fixture();try{
  const client=new PgFixtureClient(db),query=client.query.bind(client);
  client.query=async(sql,values)=>{if(sql.includes('pg_advisory_xact_lock'))throw Error('synthetic-secret lock failure');return query(sql,values);};
  await assert.rejects(reconcilePinnedMigration(client,{...args(first),priorBackendPid:client.backendPid+1}),code('reconciliation_unconfirmed'));
  assert.equal(await count(db),14);assert.equal(await exists(db,'app.client_diagnostic_reports'),false);
 }finally{await db.close();}
});

for(const [blocked,timeout,expected] of [['COMMIT',15000,'commit_unconfirmed'],['body',65000,'rollback_unconfirmed']])
 test(`hung ${blocked} destroys the connection and remains unconfirmed`,integration,async t=>{
  const db=await fixture();try{
   const input=await reviewed(db,first),client=new PgFixtureClient(db),query=client.query.bind(client);
   let notify;const reached=new Promise(resolve=>{notify=resolve;});
   client.query=async(sql,values)=>{
    if(sql===blocked||(blocked==='body'&&sql.includes('CREATE TABLE app.client_diagnostic_reports'))){notify();return new Promise(()=>{});}
    return query(sql,values);
   };
   t.mock.timers.enable({apis:['setTimeout']});
   const pending=executePinnedMigration(client,input);await reached;t.mock.timers.tick(timeout);
   await assert.rejects(pending,code(expected));assert.equal(client.connection.stream.destroyed,true);
   await assert.rejects(executePinnedMigration(client,input),code('client_discard_required'));
  }finally{t.mock.timers.reset();await db.close();}
 });

test('session-mode pooler works and a changed transaction backend is refused',integration,async()=>{
 const db=await fixture();try{
  const input=await reviewed(db,first);
  const changed=new PgFixtureClient(db),query=changed.query.bind(changed);
  changed.query=async(sql,values)=>{const result=await query(sql,values);if(sql.includes('current_database() AS database'))result.rows[0].backend_pid++;return result;};
  await assert.rejects(executePinnedMigration(changed,input),code('backend_changed'));
  await assert.rejects(executePinnedMigration(changed,input),code('client_discard_required'));
  assert.equal(await exists(db,'app.client_diagnostic_reports'),false);
  const changedAfterBody=new PgFixtureClient(db),afterQuery=changedAfterBody.query.bind(changedAfterBody);
  changedAfterBody.query=async(sql,values)=>{const result=await afterQuery(sql,values);if(sql==='SELECT pg_catalog.pg_backend_pid() AS backend_pid')result.rows[0].backend_pid++;return result;};
  await assert.rejects(executePinnedMigration(changedAfterBody,input),code('backend_changed'));
  assert.equal(await exists(db,'app.client_diagnostic_reports'),false);assert.equal(await count(db),14);
  const sessionPool=new PgFixtureClient(db);sessionPool.connectionParameters.host='aws-0-eu-north-1.pooler.supabase.com';
  sessionPool.connectionParameters.port=5432;sessionPool.connectionParameters.user='postgres.rrlduytparvsjfmegalh';sessionPool.connection.stream.servername=sessionPool.connectionParameters.host;
  assert.equal((await executePinnedMigration(sessionPool,input)).status,'committed');
 }finally{await db.close();}
});

// Optional, task-owned native PostgreSQL fixture. It uses a private Unix socket,
// no TCP listener, no other cluster and no cloud data. TLS properties are
// intentionally simulated so this verifies real transaction/lock behavior,
// not hosted TLS, Supavisor, deployment configuration or production readiness.
const pgBin=process.env.COLLECT_ATOMIC_TEST_PG_BIN_DIR;
const pgSpecifier=process.env.COLLECT_ATOMIC_TEST_PG_MODULE??'pg';
let pgDriver;try{pgDriver=await import(pgSpecifier);}catch{}

async function closeOwnedClients(clients,{graceMs=3000,forcedMs=3000}={}){
 const listeners=[];
 try{
  // Subscribe before end(): a client may resolve end() after a synchronous
  // close event, and an already-resolved end() alone does not prove closure.
  const states=clients.map(client=>{
   const stream=client.connection?.stream,entry={client,stream,closed:false};let resolveClose;
   entry.closePromise=new Promise(resolve=>{resolveClose=resolve;});
   entry.confirmClose=()=>{entry.closed=true;resolveClose();};
   if(stream?.closed===true)entry.confirmClose();
   else if(typeof stream?.once==='function'&&typeof stream.removeListener==='function'){
    const onClose=()=>entry.confirmClose();listeners.push({stream,onClose});stream.once('close',onClose);
    if(stream.closed===true)entry.confirmClose();
   }
   return entry;
  });
  const ended=states.map(entry=>Promise.resolve().then(()=>entry.client.end()).then(()=>{},()=>{}));
  const completion=Promise.all([...ended,...states.map(entry=>entry.closePromise)]);
  const within=async(promise,ms)=>{
   let timer;
   try{return await Promise.race([promise.then(()=>true),new Promise(resolve=>{timer=setTimeout(()=>resolve(false),ms);})]);}
   finally{clearTimeout(timer);}
  };
  await within(completion,graceMs);
  let destroyUnconfirmed=false;
  for(const entry of states){
   const stream=entry.stream;
   if(stream?.closed===true)entry.confirmClose();
   if(entry.closed)continue;
   // Only destroy the exact, still-unconfirmed stream held by this client.
   if(typeof stream?.destroy!=='function'){destroyUnconfirmed=true;continue;}
   try{stream.destroy();}catch{destroyUnconfirmed=true;}
   if(stream.closed===true)entry.confirmClose();
  }
  let settled=await within(completion,forcedMs);
  if(!settled){
   for(const entry of states)if(entry.stream?.closed===true)entry.confirmClose();
   settled=await within(completion,0);
  }
  if(destroyUnconfirmed||!settled)throw new Error('owned client closure unconfirmed');
 }finally{for(const {stream,onClose} of listeners)stream.removeListener('close',onClose);}
}

async function closeOwnedFixtureClients(clients,fixture,options){
 try{await closeOwnedClients(clients,options);}
 finally{const closed=await fixture.close();assert.equal(closed.removed,true,'owned PostgreSQL fixture cleanup must be confirmed');}
}

test('owned client close forces only unresolved streams and bounds settlement',async()=>{
 const untouched={destroyed:false,destroy(){this.destroyed=true;}};
 const makeStream=close=>{
  const stream=new EventEmitter();stream.destroyed=false;stream.closed=false;
  stream.destroy=()=>{stream.destroyed=true;close?.(stream);};return stream;
 };
 const normalStream=makeStream();
 const normal={connection:{stream:normalStream},end:async()=>{normalStream.closed=true;normalStream.emit('close');}};
 let release,eventSeen=false;
 const delayedStream=makeStream(stream=>setTimeout(()=>{stream.closed=true;stream.emit('close');release();},5));
 const delayed={connection:{stream:delayedStream},end:()=>new Promise(resolve=>{release=resolve;})};
 const rejectedStream=makeStream(stream=>setTimeout(()=>{stream.closed=true;stream.emit('close');},5));
 const rejected={connection:{stream:rejectedStream},end:async()=>{throw new Error('synthetic close failure');}};
 const eventOnlyStream=makeStream(stream=>setTimeout(()=>{eventSeen=true;stream.emit('close');},5));
 const eventOnly={connection:{stream:eventOnlyStream},end:async()=>{throw new Error('synthetic close failure');}};
 const flagOnlyStream=makeStream(stream=>{stream.closed=true;});
 const flagOnly={connection:{stream:flagOnlyStream},end:async()=>{throw new Error('synthetic close failure');}};
 const resolvedOpenStream=makeStream(stream=>setTimeout(()=>{stream.closed=true;stream.emit('close');},5));
 const resolvedOpen={connection:{stream:resolvedOpenStream},end:async()=>{}};
 await closeOwnedClients([normal,delayed,rejected,eventOnly,flagOnly,resolvedOpen],{graceMs:10,forcedMs:100});
 assert.equal(normalStream.destroyed,false);assert.equal(untouched.destroyed,false);
 assert.equal(delayedStream.closed,true);assert.equal(rejectedStream.closed,true);assert.equal(flagOnlyStream.closed,true);
 assert.equal(resolvedOpenStream.destroyed,true);assert.equal(resolvedOpenStream.closed,true);
 assert.equal(eventOnlyStream.closed,false);assert.equal(eventSeen,true);
 const neverStream=makeStream(stream=>{stream.closed=true;stream.emit('close');});
 const never={connection:{stream:neverStream},end:()=>new Promise(()=>{})};
 await assert.rejects(closeOwnedClients([never],{graceMs:10,forcedMs:10}),/owned client closure unconfirmed/);
 assert.equal(neverStream.closed,true);
 const destroyedOnlyStream=makeStream();
 const destroyedOnly={connection:{stream:destroyedOnlyStream},end:async()=>{throw new Error('synthetic close failure');}};
 await assert.rejects(closeOwnedClients([destroyedOnly],{graceMs:10,forcedMs:10}),/owned client closure unconfirmed/);
 assert.equal(destroyedOnlyStream.destroyed,true);assert.equal(destroyedOnlyStream.closed,false);
 assert.equal(destroyedOnlyStream.listenerCount('close'),0);
 const resolvedNeverStream=makeStream();
 const resolvedNever={connection:{stream:resolvedNeverStream},end:async()=>{}};
 await assert.rejects(closeOwnedClients([resolvedNever],{graceMs:10,forcedMs:10}),/owned client closure unconfirmed/);
 assert.equal(resolvedNeverStream.destroyed,true);assert.equal(resolvedNeverStream.closed,false);
 assert.equal(resolvedNeverStream.listenerCount('close'),0);
});

test('owned client close removes registered listeners when a later subscription throws',async()=>{
 const first=new EventEmitter(),second=new EventEmitter();first.closed=false;second.closed=false;
 const originalOnce=second.once.bind(second);
 second.once=(...args)=>{originalOnce(...args);throw new Error('synthetic subscription failure');};
 let ended=0,fixtureCloses=0;
 const clients=[first,second].map(stream=>({connection:{stream},end:async()=>{ended++;}}));
 const fixture={close:async()=>{fixtureCloses++;return {removed:true};}};
 await assert.rejects(closeOwnedFixtureClients(clients,fixture,{graceMs:10,forcedMs:10}),/synthetic subscription failure/);
 assert.equal(first.listenerCount('close'),0);assert.equal(second.listenerCount('close'),0);
 assert.equal(ended,0);assert.equal(fixtureCloses,1);
});

test('native PostgreSQL two-session lock and lost-ACK reconciliation',{
 skip:pgBin&&pgDriver?false:'Set COLLECT_ATOMIC_TEST_PG_BIN_DIR and provide pg for the optional native PostgreSQL test.',timeout:45000,
},async()=>{
 const Client=pgDriver.Client??pgDriver.default?.Client;assert.ok(Client);
 assert.equal(await realpath(pgBin),pgBin,'native PostgreSQL bin directory must be a physical path');
 // The reviewed fixture selects its binaries through COLLECT_SYNTHETIC_PG_BIN.
 // Preserve this test's existing explicit PG_BIN selection and restore any
 // previous value even when initialization fails.
 const previousBin=process.env.COLLECT_SYNTHETIC_PG_BIN;let fixture;
 try{
  process.env.COLLECT_SYNTHETIC_PG_BIN=pgBin;
  fixture=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap'});
 }finally{
  if(previousBin===undefined)delete process.env.COLLECT_SYNTHETIC_PG_BIN;
  else process.env.COLLECT_SYNTHETIC_PG_BIN=previousBin;
 }
 const clients=[];
 try{
  assert.equal(fixture.bin,pgBin);
  const bootstrap=new Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'fixture_bootstrap'});
  bootstrap.on('error',()=>{});clients.push(bootstrap);await bootstrap.connect();
  await bootstrap.query('CREATE ROLE postgres LOGIN SUPERUSER');
  for(let i=0;i<3;i++){
   const client=new Client({host:fixture.socket,port:fixture.port,database:'postgres',user:'postgres'});
   client.on('error',()=>{});clients.push(client);await client.connect();
  }
  const [,one,two,observer]=clients;
  await one.query(syntheticSchema);await seedHistory(one);
  const synthetic=(client,loseCommit=false)=>({
   connectionParameters:{host:'db.rrlduytparvsjfmegalh.supabase.co',port:5432,database:'postgres',user:'postgres',ssl:{rejectUnauthorized:true,ca:loadProviderRoot()}},
   connection:{stream:{encrypted:true,authorized:true,servername:'db.rrlduytparvsjfmegalh.supabase.co',destroy:()=>client.connection.stream.destroy()},
    once:(event,fn)=>client.connection.once(event,fn),removeListener:(event,fn)=>client.connection.removeListener(event,fn)},
   async query(sql,values){const result=await client.query(sql,values);if(loseCommit&&sql==='COMMIT'){loseCommit=false;throw Error('synthetic-secret lost acknowledgement');}return result;},
  });
  const source=synthetic(one),preimage=await capturePinnedPreimage(source,args(first));
  const pid=(await one.query('SELECT pg_backend_pid() AS pid')).rows[0].pid;
  await two.query('BEGIN');await two.query('LOCK TABLE supabase_migrations.schema_migrations IN ACCESS EXCLUSIVE MODE');
  const pending=executePinnedMigration(synthetic(one,true),{...args(first),expectedPreimageSha:preimage.sha256});
  void pending.catch(()=>{});
  let blocked=false;
  for(let i=0;i<40&&!blocked;i++){
   await new Promise(resolve=>setTimeout(resolve,50));
   const state=(await observer.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[pid])).rows[0];
   blocked=state?.wait_event_type==='Lock';
  }
  assert.equal(blocked,true,'executor must wait for the independent history lock');
  await two.query('COMMIT');
  let lost;try{await pending;assert.fail('expected lost acknowledgement');}catch(error){lost=error;}
  assert(code('commit_unconfirmed')(lost));assert.equal(lost.backendPid,pid);
  const reconciliation=await reconcilePinnedMigration(synthetic(observer),{...args(first),priorBackendPid:lost.backendPid});
  assert.equal(reconciliation.status,'recorded');
  assert.equal((await observer.query("SELECT count(*)::int AS n FROM supabase_migrations.schema_migrations WHERE version=$1",[first.version])).rows[0].n,1);
  assert.equal((await observer.query("SELECT to_regclass('app.client_diagnostic_reports') IS NOT NULL AS present")).rows[0].present,true);
 }finally{
  await closeOwnedFixtureClients(clients,fixture);
 }
});
