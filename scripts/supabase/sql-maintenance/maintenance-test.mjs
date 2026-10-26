import {loadReviewedPlatformFixture,ORIGINAL_NINE} from '../testing/curated-platform-fixture.mjs';
// Root executes. Real local PostgreSQL transactions; SYNTHETIC Cron only.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,readdir} from 'node:fs/promises';
import {createHash,randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {isAbsolute,resolve} from 'node:path';
import {render,preflight,status,operate} from './operator.mjs';
const sha=v=>createHash('sha256').update(v).digest('hex');
// Override is solely for the owner's private qualification copy, never CI.
const privateSourceRoot=process.env.COLLECT_SQL_MAINTENANCE_SOURCE_ROOT;
assert(privateSourceRoot===undefined||isAbsolute(privateSourceRoot),'Private qualification source-root override must be absolute');
const root=privateSourceRoot??resolve(import.meta.dirname,'../../..');
const sourceFiles=['supabase/schema-src/baseline.sql','supabase/schema-src/authority.sql','supabase/functions/_shared/auth-cleanup.js'];
// Actual curated schema/fence inputs, never a stub assertion or test bypass.
const fixtureSource='a'.repeat(64),fixtureBaseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const curatedMigrationPins={
 "20261020134444_collect_curated_platform_baseline.sql": "0d943d17ddd92e809856831427cfc81b1264301dabdb867e1c90322d46b5a6f0",
 "20261020135932_collect_runtime_role_and_function_paths.sql": "59e4b13ddc81abeb39fb59b005c71a29f947023502727c118c9eb00b479e08a1",
 "20261020174856_collect_retention_retry_authority.sql": "d3ba38736fa46b70a0bb66520deffa56fd6f7317deb7c0144f8e06d791f8808c",
 "20261020184012_collect_admin_invitation_attempts.sql": "c6dc8aa6ac5130162c6e69904aae7221edde6dcb0c898af2cf9e10dba444b665",
 "20261020190301_collect_rls_helper_permissions.sql": "dccb79af17182164dc6afe0b8339b70bd35a80fc4a1c1fa7df1a09408310a645",
 "20261020191847_collect_privacy_email_reauthentication.sql": "d6f002a6e904226a88e666c70937a142f06aa5a7e29874c6edb564d59c5fcab4",
 "20261020193752_collect_admin_invitation_access_notice_v2.sql": "b48a381169e777160a37396539248325e40b331a61db986622514724517f8467",
 "20261020195249_collect_admin_invitation_public_id_preservation.sql": "78f8c454a9825b0d9e25622b0659245d9568e7b95f637d3e20160a945b4e0850",
 "20261022195747_collect_application_mutation_fence.sql": "714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497"
};
async function curatedFixture(root){
 assert.deepEqual(curatedMigrationPins,ORIGINAL_NINE,'All nine predecessor migration pins remain exact');
 return loadReviewedPlatformFixture(root);
}
const connection=process.env.COLLECT_SQL_MAINTENANCE_TEST_DATABASE_URL;
test('direct SQL maintenance on isolated PostgreSQL with explicit synthetic Cron',async t=>{
 assert(connection,'Root must supply the owned loopback fixture URL; no silent database-test skip');
 const url=new URL(connection);
 assert(['postgres:','postgresql:'].includes(url.protocol));assert(['127.0.0.1','localhost'].includes(url.hostname));
 const legacy=['127.0.0.1','localhost'].includes(url.hostname)&&url.port==='55439';
 const synthetic=process.env.COLLECT_CI_SYNTHETIC==='true'&&url.hostname==='127.0.0.1'&&/^[1-9][0-9]{0,4}$/.test(url.port)&&Number(url.port)<=65535;
 assert(legacy||synthetic,'Only original port or explicitly synthetic literal-loopback fixture port');assert.equal(url.pathname,'/collect_sql_maintenance_test');assert.equal(decodeURIComponent(url.username),'collect_test');assert(url.password);assert.equal(url.search,'');assert.equal(url.hash,'');
 const r=await render({fixture:true});
 const sourcePins=JSON.parse(await readFile(new URL('./source-pins.json',import.meta.url),'utf8'));
 assert.equal(sourcePins.format,'collect.sql-maintenance.fixture-source-pins.v1');
 assert.deepEqual(Object.keys(sourcePins.files).sort(),[...sourceFiles].sort(),'The three existing semantic-source pins remain exact; curated9/auth inputs are independently pinned');
 for(const f of sourceFiles){assert.match(sourcePins.files[f],/^[a-f0-9]{64}$/);assert.equal(sha(await readFile(resolve(root,f))),sourcePins.files[f],'Qualified canonical source changed: '+f);}
 const full=await curatedFixture(root);
 assert.equal(sha(await readFile(new URL('./install.sql.in',import.meta.url))),'d52bc469b9f4f245f749a2f0c71acf5a01f08ce4478352368b972c418a234d57','Reviewed first-BEGIN cleanup guard template required');
 const require=createRequire(import.meta.url),{Client}=require(process.env.COLLECT_PG_MODULE??'pg');
 const adminUrl=new URL(url);adminUrl.pathname='/postgres';const admin=new Client({connectionString:adminUrl.href});await admin.connect();
 try{const operator=(await admin.query("SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname='postgres'")).rows[0];assert(operator&&operator.rolsuper===false&&operator.rolbypassrls===false,'Preexisting non-superuser postgres qualification role required; no global role changes');const existing=(await admin.query("SELECT pg_get_userbyid(datdba) AS owner FROM pg_database WHERE datname='collect_sql_maintenance_test'")).rows[0];if(!existing)await admin.query('CREATE DATABASE collect_sql_maintenance_test OWNER postgres');else assert.equal(existing.owner,'postgres');}finally{await admin.end();}
 const connect=async()=>{const c=new Client({connectionString:url.href});await c.connect();await c.query('SET ROLE postgres');return c;};
 const db=await connect();
 const seed=async({expires,status='ready',id=randomUUID()}={})=>{
  const actualId=id??randomUUID(),expiry=expires??Math.floor(Date.now()/1000)-60;
  await db.query("INSERT INTO app.auth_google_flows(id,state_hash,nonce,provider_verifier,client_challenge,client_state,return_origin,registration_allowed,created_at,expires_at,status,email,google_subject) VALUES($1,$2,$3,$4,$5,$6,$7,0,$8,$9,$10,$11,$12)",[actualId,sha(actualId),'nonce-'+actualId,'{"synthetic_ciphertext":"fixture-only"}','c'.repeat(43),'client-'+actualId,'https://synthetic-admin.example.test',expiry-300,expiry,status,'synthetic-'+actualId+'@example.test','subject-'+actualId]);
  await db.query("INSERT INTO private.google_flow_context(flow_id,surface,request_origin) VALUES($1,'admin','https://synthetic-admin.example.test')",[actualId]);return actualId;
 };
 const row=async id=>(await db.query('SELECT to_jsonb(f) AS value FROM app.auth_google_flows f WHERE id=$1',[id])).rows[0]?.value;
 const contexts=async()=>(await db.query('SELECT to_jsonb(c) AS value FROM private.google_flow_context c ORDER BY flow_id')).rows.map(x=>x.value);
 const metadata=v=>Object.fromEntries(Object.entries(v).filter(([k])=>!['provider_verifier','status'].includes(k)));
 try{
  const identity=(await db.query('SELECT current_user AS owner,current_database() AS database')).rows[0];assert.equal(identity.owner,'postgres');assert.equal(identity.database,'collect_sql_maintenance_test');
  // This explicitly named new fixture database is the ONLY reset boundary.
  // Reset ONLY this explicitly validated owned loopback fixture. Apply actual
  // sources as its fixture admin, without changing any global role attributes.
  await db.query('RESET ROLE');
  await db.query('DROP SCHEMA IF EXISTS collect_ops,cron,api,private,app,auth,realtime CASCADE');
  await full.apply(text=>db.query(text),{includeAuth:true});
  // Deliberate LOCAL fixture ownership: the real non-super/non-bypass postgres
  // owns the cleanup subjects and every new fence control/function it invokes.
  // This ownership block changes no source body, role membership, policy or global role attribute.
  await db.query(`GRANT USAGE,CREATE ON SCHEMA app,private TO postgres;
ALTER TABLE app.auth_google_flows OWNER TO postgres;
ALTER TABLE private.google_flow_context OWNER TO postgres;
ALTER FUNCTION app.json_valid(text) OWNER TO postgres;
ALTER TABLE private.collect_fence_control OWNER TO postgres;
ALTER TABLE private.collect_fence_admissions OWNER TO postgres;
ALTER TABLE private.collect_fence_operations OWNER TO postgres;
ALTER TABLE private.collect_fence_scheduler_lifecycle OWNER TO postgres;
DO $local_owner$ DECLARE routine record;BEGIN
 FOR routine IN SELECT f.oid::regprocedure AS signature FROM pg_catalog.pg_proc f JOIN pg_catalog.pg_namespace n ON n.oid=f.pronamespace
 WHERE n.nspname='private' AND (left(f.proname,14)='collect_fence_' OR left(f.proname,15)='_collect_fence_') LOOP
  EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',routine.signature);
 END LOOP;
END;$local_owner$;`);
  await db.query('SET ROLE postgres');
  await db.query(await readFile(new URL('./cron-fixture.sql',import.meta.url),'utf8'));await db.query("SET cron.timezone='GMT'");
  const fence=(await db.query('SELECT private.collect_fence_initialize($1,$2,$3) AS value',[randomUUID(),fixtureSource,fixtureBaseline])).rows[0].value;
  assert.equal(fence.mode,'open');assert.equal(fence.sourceSha256,fixtureSource);assert.equal(fence.resourceLimits.capacityBlocked,false);
  const fullScope=(await db.query("SELECT (SELECT count(*)::integer FROM pg_catalog.pg_tables WHERE schemaname='app') AS app,(SELECT count(*)::integer FROM pg_catalog.pg_tables WHERE schemaname='private') AS private,(SELECT count(*)::integer FROM pg_catalog.pg_trigger WHERE tgname='collect_fence_statement_v1' AND tgenabled='A' AND tgtype=62) AS guards,(SELECT pg_catalog.pg_get_userbyid(c.relowner) FROM pg_catalog.pg_class c WHERE c.oid='private.collect_fence_control'::regclass) AS control_owner")).rows[0];
  assert.deepEqual(fullScope,{app:97,private:18,guards:111,control_owner:'postgres'});
  const stable=(await db.query("SELECT rolsuper,rolbypassrls FROM pg_catalog.pg_roles WHERE rolname='postgres'")).rows[0];assert.deepEqual(stable,{rolsuper:false,rolbypassrls:false});
  await t.test('production rendering is fixed to postgres and has no network/Vault/managed mutations',async()=>{
   const production=await render();assert.equal(production.operatorRole,'postgres');assert.equal(production.database,'postgres');
   assert(!production.sql.includes('net.http'));assert(!production.sql.includes('vault.'));assert(!production.sql.includes('auth.sessions'));assert(!production.sql.includes('momo_'));assert(production.sql.includes('SECURITY INVOKER'));
   await assert.rejects(()=>preflight(db,production));
  });
  await t.test('install is inactive, source data untouched, and exact reinstall reconciles',async()=>{
   const id=await seed();const before=await row(id),ctx=await contexts();
   const installed=await operate(db,'install-inactive',{rendered:r});assert.equal(installed.active,false);assert.deepEqual(await row(id),before);assert.deepEqual(await contexts(),ctx);
   assert.equal((await operate(db,'install-inactive',{rendered:r})).reconciled_existing,true);assert.equal((await db.query('SELECT count(*)::integer AS n FROM cron.job')).rows[0].n,1);
   await assert.rejects(()=>operate(db,'activate',{rendered:r}),/fresh committed probe/);
  });
  await t.test('PUBLIC and all existing client/runtime/importer roles have no maintenance entrypoint',async()=>{
   const roles=(await db.query("SELECT rolname FROM pg_roles WHERE rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer') ORDER BY rolname")).rows.map(x=>x.rolname);
   assert(roles.includes('anon')&&roles.includes('authenticated')&&roles.includes('collect_runtime')&&roles.includes('collect_importer'),'Expected preexisting qualification roles; no global role changes supplied');
   for(const role of roles){await db.query('BEGIN');try{await db.query('SET LOCAL ROLE '+role);await assert.rejects(()=>db.query('SELECT collect_ops.cleanup_google_expired()'),/permission denied/);}finally{await db.query('ROLLBACK');}}
  });
  await t.test('at most100 expired rows change only payload/status and all context/terminal/future metadata survives',async()=>{
   await db.query('TRUNCATE private.google_flow_context,app.auth_google_flows');
   const expired=[];for(let i=0;i<105;i++)expired.push(await seed({status:['pending','exchanging','ready'][i%3]}));
   const future=await seed({expires:Math.floor(Date.now()/1000)+3600}),consumed=await seed({status:'consumed'}),failed=await seed({status:'failed'});
   const before=new Map();for(const id of [...expired,future,consumed,failed])before.set(id,await row(id));const ctx=await contexts();
   const first=await operate(db,'probe',{rendered:r});assert.equal(first.result.purged,100);assert.equal(first.result.provider_calls,0);
   const changed=[];for(const id of expired){const after=await row(id);assert.deepEqual(metadata(after),metadata(before.get(id)));if(after.status==='failed'){assert.equal(after.provider_verifier,'{}');changed.push(id);}else assert.deepEqual(after,before.get(id));}assert.equal(changed.length,100);
   for(const id of [future,consumed,failed])assert.deepEqual(await row(id),before.get(id));assert.deepEqual(await contexts(),ctx);
   assert.equal((await operate(db,'probe',{rendered:r})).result.purged,5);assert.equal((await operate(db,'probe',{rendered:r})).result.purged,0);
  });
  await t.test('row-lock winner is skipped, its consumed result cannot be resurrected, and independent connections finish remaining work',async()=>{
   const id=await seed({status:'exchanging'}),locker=await connect();
   try{await locker.query('BEGIN');await locker.query('SELECT id FROM app.auth_google_flows WHERE id=$1 FOR UPDATE',[id]);assert.equal((await operate(db,'probe',{rendered:r})).result.purged,0);await locker.query("UPDATE app.auth_google_flows SET status='consumed',provider_verifier='{}',consumed_operation_id=$2 WHERE id=$1",[id,randomUUID()]);await locker.query('COMMIT');}finally{await locker.query('ROLLBACK').catch(()=>{});await locker.end();}
   assert.equal((await operate(db,'probe',{rendered:r})).result.purged,0);assert.equal((await row(id)).status,'consumed');
   for(let i=0;i<150;i++)await seed();const clients=await Promise.all([0,1].map(()=>connect()));
   try{const replies=await Promise.all(clients.map(c=>c.query('SELECT collect_ops.cleanup_google_expired() AS result')));const counts=replies.map(x=>x.rows[0].result.purged);assert(counts.every(n=>n>=0&&n<=100));assert.equal(counts.reduce((a,b)=>a+b,0),150);}finally{await Promise.all(clients.map(c=>c.end()));}
  });
  await t.test('SQL rollback changes neither subject state nor context',async()=>{
   const id=await seed();const before=await row(id),ctx=await contexts();await db.query('BEGIN');try{assert.equal((await db.query('SELECT collect_ops.cleanup_google_expired() AS result')).rows[0].result.purged,1);}finally{await db.query('ROLLBACK');}assert.deepEqual(await row(id),before);assert.deepEqual(await contexts(),ctx);
  });
  await t.test('lost committed probe reply is not activation evidence; safe next cleanup is idempotent',async()=>{
   const id=await seed();const uncertain={async query(...args){const result=await db.query(...args);if(args[0]==='SELECT collect_ops.cleanup_google_expired() AS result')throw Error('Synthetic reply lost after commit');return result;}};
   await assert.rejects(()=>operate(uncertain,'probe',{rendered:r}),/reply lost/);assert.equal((await row(id)).status,'failed');await assert.rejects(()=>operate(db,'activate',{rendered:r}),/fresh committed probe/);assert.equal((await operate(db,'probe',{rendered:r})).result.purged,0);
  });
  await t.test('activation requires same fresh function/job evidence; pause and status read back exact native identity',async()=>{
   const probe=await operate(db,'probe',{rendered:r});
   for(const bad of [{...probe,job_id:'9999'},{...probe,function_sha256:'f'.repeat(64)},{...probe,checked_at:'2000-01-01T00:00:00Z'},{...probe,outcome:'unconfirmed'},{...probe,result:{...probe.result,provider_calls:1}}])await assert.rejects(()=>operate(db,'activate',{rendered:r,probeEvidence:bad}),/fresh committed probe/);
   assert.equal((await operate(db,'activate',{rendered:r,probeEvidence:probe})).active,true);await assert.rejects(()=>operate(db,'probe',{rendered:r}),/Inactive probe/);assert.equal((await operate(db,'deactivate',{rendered:r})).active,false);assert.equal((await status(db,r)).active,false);
  });
  await t.test('Cron command or owner drift is refused instead of replaced',async()=>{
   await db.query("UPDATE cron.job SET command='SELECT 123;'");await assert.rejects(()=>operate(db,'install-inactive',{rendered:r}),/identity drift/);await db.query("UPDATE cron.job SET command='SELECT collect_ops.cleanup_google_expired();',username='synthetic-wrong-owner'");await assert.rejects(()=>status(db,r),/identity drift/);await db.query("UPDATE cron.job SET username='postgres'");assert.equal((await status(db,r)).active,false);
  });
  await t.test('explicit nonowner function ACL is refused even before schema access exists',async()=>{
   await db.query('GRANT EXECUTE ON FUNCTION collect_ops.cleanup_google_expired() TO pg_read_all_settings');
   try{await assert.rejects(()=>status(db,r),/access drift/);}finally{await db.query('REVOKE EXECUTE ON FUNCTION collect_ops.cleanup_google_expired() FROM pg_read_all_settings');}
   assert.equal((await status(db,r)).active,false);
  });
  await t.test('real application fence stops cleanup and even zero-row subject mutation while preserving ciphertext/context',async()=>{
   const id=await seed(),before=await row(id),ctx=await contexts(),operation=randomUUID();
   const closed=(await db.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3) AS value',[operation,1,fixtureSource])).rows[0].value;
   assert.equal(closed.mode,'quiescing');
   await assert.rejects(()=>operate(db,'probe',{rendered:r}),/collect_fence_closed/);
   await assert.rejects(()=>db.query('SELECT collect_ops.cleanup_google_expired()'),/collect_fence_closed/);
   for(const sql of ['UPDATE app.auth_google_flows SET status=status WHERE false','DELETE FROM app.auth_google_flows WHERE false','INSERT INTO app.auth_google_flows SELECT * FROM app.auth_google_flows WHERE false','TRUNCATE private.google_flow_context,app.auth_google_flows'])await assert.rejects(()=>db.query(sql),/collect_fence_closed/);
   assert.deepEqual(await row(id),before);assert.deepEqual(await contexts(),ctx);
   const fenced=(await db.query('SELECT private.collect_fence_drain($1,$2,$3) AS value',[operation,1,fixtureSource])).rows[0].value;
   assert.equal(fenced.mode,'fenced');assert.equal(fenced.applicationFenceComplete,true);assert.equal(fenced.schedulerStatus.coverageVerified,true);assert.equal(fenced.wholeSystemAcceptance,false);assert.equal(fenced.sb29Satisfied,false);
   await assert.rejects(()=>db.query('SELECT collect_ops.cleanup_google_expired()'),/collect_fence_closed/);
   assert.equal((await operate(db,'deactivate',{rendered:r})).active,false);
   assert.deepEqual(await row(id),before);assert.deepEqual(await contexts(),ctx);
  });
  console.log(JSON.stringify({qualification:'real local PostgreSQL only; Cron is a synthetic interface double',source_pins:Object.fromEntries(await Promise.all(sourceFiles.map(async f=>[f,sha(await readFile(root+'/'+f))]))),rendered_fixture_sql_sha256:r.sqlSha,fixture_database:r.database,curated_migrations:10,real_application_fence:true,native_scheduling_executed:false,provider_calls:0}));
 }finally{await db.end();}
});
