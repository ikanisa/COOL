import {loadReviewedPlatformFixture} from './testing/curated-platform-fixture.mjs';
// PRIVATE PROPOSED scripts/supabase/test_schema.mjs. Not executed by author.
import {readdir,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {validateTarget} from './data_stage.mjs';

const url=process.env.COLLECT_TEST_PG_URL;
const target=validateTarget(url,'local',{localTest:true});
if(!/^\/collect_[a-z0-9_]+_test$/.test(target.pathname))throw new Error('Use a dedicated collect_*_test fixture database');
const root=resolve(import.meta.dirname,'../..');
const require=createRequire(import.meta.url);const {Client}=require(process.env.COLLECT_PG_MODULE??'pg');
const options={connectionString:url,connectionTimeoutMillis:5000,statement_timeout:30000};
const db=new Client(options),lease=new Client(options);
// This value is meaningful ONLY inside the explicitly loopback fixture database.
// It is a real initialized synthetic source, not a bypass/default runtime flag.
const fixtureSource='a'.repeat(64),baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
async function runtimeCall(text,values){
 await db.query('BEGIN ISOLATION LEVEL READ COMMITTED');
 try{
  await db.query('SET LOCAL ROLE collect_runtime');
  await db.query("SELECT pg_catalog.set_config('collect.edge_verified','true',true)");
  const result=await db.query(text,values);
  await db.query('COMMIT');return result.rows[0]?.value;
 }catch(error){await db.query('ROLLBACK').catch(()=>{});throw error;}
}
async function admittedSuite(name,source){
 const begin=source.indexOf('BEGIN;\n');
 if(begin<0||!/^(?:\s|--[^\n]*(?:\n|$))*$/.test(source.slice(0,begin))||!source.endsWith('ROLLBACK;\n'))throw new Error('Suite must retain an outer BEGIN/ROLLBACK: '+name);
 const id=randomUUID();
 const registered=await runtimeCall('SELECT private.collect_fence_register($1,$2,$3) AS value',[id,fixtureSource,'jobs']);
 if(registered?.state!=='active'||registered?.mode!=='open'||registered?.sourceSha256!==fixtureSource||registered?.epoch!==1)throw new Error('Synthetic admission refused');
 let held=false;
 try{
  await lease.query('BEGIN ISOLATION LEVEL READ COMMITTED');held=true;
  await lease.query("SET LOCAL idle_in_transaction_session_timeout='120s'");
  await lease.query("SET LOCAL statement_timeout='30s'");
  await lease.query("SET LOCAL lock_timeout='5s'");
  await lease.query('SET LOCAL ROLE collect_runtime');
  await lease.query("SELECT pg_catalog.set_config('collect.edge_verified','true',true)");
  await lease.query('SELECT pg_catalog.pg_advisory_xact_lock_shared(7346371,1)');
  const proof=(await lease.query('SELECT private.collect_fence_assert_work($1,$2,$3) AS value',[id,registered.epoch,fixtureSource])).rows[0].value;
  if(proof.mode!=='open'||proof.admissionId!==id)throw new Error('Synthetic work lease not OPEN');
  // Generated UUID/epoch/source contain only fixed grammar, never SQL/raw input.
  const context=`SELECT pg_catalog.set_config('collect.edge_verified','true',true),pg_catalog.set_config('collect.fence_admission_id','${id}',true),pg_catalog.set_config('collect.fence_epoch','${registered.epoch}',true),pg_catalog.set_config('collect.fence_source_sha256','${fixtureSource}',true);\n`;
  await db.query(source.slice(0,begin)+'BEGIN;\n'+context+source.slice(begin+'BEGIN;\n'.length));
  await lease.query('SELECT private.collect_fence_assert_work($1,$2,$3)',[id,registered.epoch,fixtureSource]);
  await runtimeCall('SELECT private.collect_fence_close($1,$2,$3,$4,$5,$6,$7) AS value',[id,registered.epoch,fixtureSource,'settled','completed',0,0]);
  // Work lifetime ends only after exact durable closure, never at suite return.
  await lease.query('ROLLBACK');held=false;
 }catch(error){
  await db.query('ROLLBACK').catch(()=>{});
  // Preserve loss/unconfirmed work. No test-only erasure or automatic resolution.
  await runtimeCall('SELECT private.collect_fence_close($1,$2,$3,$4,$5,$6,$7) AS value',[id,registered.epoch,fixtureSource,'unresolved','work_lost',0,0]).catch(()=>{});
  if(held)await lease.query('ROLLBACK').catch(()=>{});
  throw error;
 }
}
try{
 await db.connect();await lease.connect();
 // Existing reset boundary remains restricted to the dedicated loopback fixture.
 await db.query('DROP SCHEMA IF EXISTS app CASCADE; DROP SCHEMA IF EXISTS private CASCADE; DROP SCHEMA IF EXISTS api CASCADE; DROP SCHEMA IF EXISTS auth CASCADE; DROP SCHEMA IF EXISTS realtime CASCADE;');
 const fixture=await readFile(resolve(root,'supabase/tests/sql/00_local_auth_fixture.sql'),'utf8');await db.query(fixture);
 const reviewedPlatform=await loadReviewedPlatformFixture(root),migrations=reviewedPlatform.names;
 await reviewedPlatform.apply(text=>db.query(text));
 if(!(await db.query("SELECT pg_catalog.to_regprocedure('private.collect_fence_initialize(uuid,text,text)') AS installed")).rows[0].installed)throw new Error('Fenced SQL suite requires the reviewed additive fence migration');
 await db.query('SELECT private.collect_fence_initialize($1,$2,$3)',[randomUUID(),fixtureSource,baseline]);
 const tests=(await readdir(resolve(root,'supabase/tests/sql'))).filter(n=>/^\d+_[a-z0-9_]+\.sql$/.test(n)&&!n.startsWith('00_')).sort();
 if(!tests.length)throw new Error('No PostgreSQL acceptance cases');
 for(const name of tests){await admittedSuite(name,await readFile(resolve(root,'supabase/tests/sql',name),'utf8'));console.log('PASS '+name);}
 const counts=await db.query("select (select count(*) from pg_tables where schemaname='app') as app_tables,(select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='app' and not t.tgisinternal) as app_triggers");
 console.log(JSON.stringify({database:'isolated_local_fixture',migration_count:migrations.length,sql_suites:tests.length,...counts.rows[0],synthetic_fence_source:fixtureSource,genuine_durable_admission:true,hosted_acceptance:false}));
}finally{await db.end();await lease.end();}
