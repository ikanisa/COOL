// Real scheduler SQL in an owned, socket-only PostgreSQL 17 fixture. Cron,
// pg_net, Vault and the fence are doubles. There are no cloud writes, real SMS,
// financial postings or provider calls.
import assert from 'node:assert/strict';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {verifyBinaryPins,verifyEnvironment,BIN} from '../managed-identity-provider-compat/fixture-safety.mjs';
import {renderManagedScheduler} from './managed-jobs-scheduler.mjs';
import {drainNativeAutoTransactions} from '../../../supabase/functions/_shared/domain/burimunsi/postgres-native-auto-worker.js';
import {drainNativeSmsLedger} from '../../../supabase/functions/_shared/domain/burimunsi/postgres-native-sms-ledger.js';

verifyEnvironment(process.env);await verifyBinaryPins();
const {Client}=createRequire(import.meta.url)('pg');
const src='a'.repeat(64),key=randomBytes(32).toString('hex'),project='rrlduytparvsjfmegalh';
const migration=await readFile(new URL('../../../supabase/migrations/20261117135049_collect_sms_schedule_one_minute.sql',import.meta.url),'utf8');
const rendered=await renderManagedScheduler();
const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_minute_schedule_fixture'});
assert.equal(f.bin,BIN);const clients=[];
async function connect(user){const c=new Client({host:f.socket,port:f.port,database:'postgres',user,connectionTimeoutMillis:5000});c.on('error',()=>{});await c.connect();clients.push(c);return c;}
let checks=0;
try{
 const root=await connect('fixture_bootstrap');
 await root.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS;CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_runtime;CREATE ROLE collect_importer;GRANT collect_runtime TO postgres;
  GRANT CREATE ON DATABASE postgres TO postgres;CREATE SCHEMA extensions;CREATE EXTENSION pgcrypto WITH SCHEMA extensions;GRANT USAGE ON SCHEMA extensions TO postgres;
  CREATE SCHEMA private AUTHORIZATION postgres;CREATE SCHEMA collect_ops AUTHORIZATION postgres;GRANT USAGE ON SCHEMA private TO collect_runtime;`);
 const db=await connect('postgres');
 await db.query(`CREATE FUNCTION collect_ops.cleanup_google_expired() RETURNS void LANGUAGE sql AS $$ SELECT $$;
  REVOKE ALL ON FUNCTION collect_ops.cleanup_google_expired() FROM PUBLIC;
  CREATE TABLE private.collect_fence_control(singleton boolean,mode text,project_ref text);
  INSERT INTO private.collect_fence_control VALUES(true,'fenced','${project}');
  CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE sql AS $$ SELECT $$;
  CREATE FUNCTION private._retention_manifest_catalog_v2() RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,pg_temp AS $$ SELECT '{"private_classes":[]}'::jsonb $$;
  REVOKE ALL ON FUNCTION private._retention_manifest_catalog_v2() FROM PUBLIC;
  CREATE TABLE private.collect_fence_admissions(admission_id uuid PRIMARY KEY,epoch bigint,source_sha256 text,kind text,state text);
  CREATE FUNCTION private._collect_fence_require_runtime() RETURNS void LANGUAGE plpgsql AS $$ BEGIN
   IF current_setting('role',true) IS DISTINCT FROM 'collect_runtime' OR current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'denied';END IF;END $$;
  CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS jsonb LANGUAGE sql AS $$ SELECT '{}'::jsonb $$;
  CREATE FUNCTION private._collect_fence_statement() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL;END $$;
  CREATE FUNCTION private.collect_fence_owner_status() RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('sourceSha256','${src}') $$;`);
 await db.query(await readFile(new URL('../../../supabase/jobs/test-fixture.sql',import.meta.url),'utf8'));
 await db.query('INSERT INTO vault.secrets(name,decrypted_secret) VALUES($1,$2)',['collect_job_signing_key_v1',key]);
 const cleanupHash=(await db.query("SELECT encode(sha256(convert_to(pg_get_functiondef('collect_ops.cleanup_google_expired()'::regprocedure),'UTF8')),'hex') AS v")).rows[0].v;
 const retentionHash=(await db.query("SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') AS v FROM pg_proc WHERE oid='private._retention_manifest_catalog_v2()'::regprocedure")).rows[0].v;
 await db.query(rendered.sql.replace('f70925051147096cfb72869b401fdb69c976b68034c87e8c3e98ee8b5f350ed0',cleanupHash)
  .replace('09ecc11aca46af15d7f981b5d5c7c7d3775be6fc245c8ff73f48f61269e37671',retentionHash));

 // Fail closed for an active scheduler, a pending dispatch, or a modified
 // function, and leave the original Cron identity intact after each failure.
 async function rejected(){try{await db.query(migration);assert.fail('migration unexpectedly succeeded');}catch(e){await db.query('ROLLBACK');assert.match(e.message,/one_minute_scheduler_(precondition|preimage_changed)/);}}
 await db.query('UPDATE collect_ops.jobs_config SET enabled=true WHERE singleton');await rejected();await db.query('UPDATE collect_ops.jobs_config SET enabled=false WHERE singleton');checks++;
 const pending=randomUUID();await db.query("INSERT INTO collect_ops.jobs_dispatches(id,kind,state) VALUES($1,'probe','awaiting')",[pending]);
 await rejected();await db.query('DELETE FROM collect_ops.jobs_dispatches WHERE id=$1',[pending]);checks++;
 await db.query('ALTER FUNCTION collect_ops.activate_jobs(text) SET search_path=public');await rejected();
 await db.query('ALTER FUNCTION collect_ops.activate_jobs(text) SET search_path=pg_catalog');checks++;
 assert.deepEqual((await db.query('SELECT schedule,active FROM cron.job')).rows[0],{schedule:'*/5 * * * *',active:false});

 await db.query(migration);
 assert.deepEqual((await db.query('SELECT schedule,active FROM cron.job')).rows[0],{schedule:'* * * * *',active:false});
 assert.deepEqual((await db.query('SELECT enabled,last_probe_id FROM collect_ops.jobs_config')).rows[0],{enabled:false,last_probe_id:null});checks++;
 const hashes=(await db.query(`SELECT p.proname,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') AS digest,p.proacl::text AS acl,p.prosecdef
  FROM pg_proc p WHERE p.oid IN ('collect_ops.dispatch_jobs(text,uuid)'::regprocedure,'collect_ops.activate_jobs(text)'::regprocedure) ORDER BY p.proname`)).rows;
 assert.deepEqual(hashes,[{proname:'activate_jobs',digest:'18fb407a536fa422aa539a15b161c75af638a295159f020eebc5af1692c188d3',acl:'{postgres=X/postgres}',prosecdef:false},
  {proname:'dispatch_jobs',digest:'00e49b5d9603cd8564555252cc62b23d667fd9f611c558c46459e4b7580d9f72',acl:'{postgres=X/postgres}',prosecdef:false}]);checks++;
 await rejected();checks++; // A forward migration cannot be applied twice.

 const ready={format:'collect.jobs.readiness.v1',project_ref:project,endpoint:`https://${project}.supabase.co/functions/v1/collect-jobs`,
  deployment_sha256:'1'.repeat(64),runtime_evidence_sha256:'2'.repeat(64),token_custody_evidence_sha256:'3'.repeat(64),
  copy_inventory_evidence_sha256:'4'.repeat(64),quota_evidence_sha256:'5'.repeat(64),verified_at:new Date().toISOString(),
  momo_processing_paused:true,remaining_invocations:10000,evidence_file_sha256:'6'.repeat(64)};
 const baseReply={maintenance:{status:'complete',examined_limit:100,purged:0,provider_calls:0},processing:{processed:0,results:[],paused:true}};
 async function queue(d){return (await db.query("SELECT headers,convert_from(body,'UTF8')::jsonb AS body FROM net.http_request_queue WHERE id=$1",[d.net_request_id])).rows[0];}
 async function finish(d){
  const q=await queue(d),aid=randomUUID();assert(q);await db.query('INSERT INTO private.collect_fence_admissions VALUES($1,1,$2,$3,$4)',[aid,src,'jobs','active']);
  const payload=JSON.stringify({dispatch_id:d.dispatch_id,...baseReply});
  await db.query('BEGIN');try{await db.query('SET LOCAL ROLE collect_runtime');
   await db.query("SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',$2,true)",[aid,src]);
   assert.equal((await db.query('SELECT private.collect_managed_job_claim($1,$2,$3,$4) AS ok',[q.body.dispatch_id,src,q.body,q.headers.Authorization.slice(7)])).rows[0].ok,true);
   assert.equal((await db.query('SELECT private.collect_managed_job_complete($1,$2,$3) AS ok',[d.dispatch_id,src,createHash('sha256').update(payload).digest('hex')])).rows[0].ok,true);
   await db.query('COMMIT');
  }catch(e){await db.query('ROLLBACK');throw e;}
  await db.query('INSERT INTO net._http_response(id,status_code,content) VALUES($1,200,$2)',[d.net_request_id,payload]);
  await db.query('DELETE FROM net.http_request_queue WHERE id=$1',[d.net_request_id]);await db.query('SELECT collect_ops.reconcile_jobs()');
  assert.equal((await db.query('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[d.dispatch_id])).rows[0].state,'confirmed');
 }
 await db.query('SELECT collect_ops.record_jobs_readiness($1::jsonb)',[ready]);
 const probe=(await db.query("SELECT collect_ops.dispatch_jobs('probe',$1::uuid) AS v",[randomUUID()])).rows[0].v;await finish(probe);
 await db.query('SELECT collect_ops.activate_jobs($1)',['6'.repeat(64)]);
 const first=(await db.query('SELECT collect_ops.tick_jobs() AS v')).rows[0].v;assert.equal(first.state,'awaiting');
 const blocked=(await db.query("SELECT collect_ops.dispatch_jobs('scheduled',$1::uuid) AS v",[randomUUID()])).rows[0].v;
 assert.equal(blocked.state,'blocked_pending_reconciliation');await finish(first);checks++;
 const firstSlot=(await db.query('SELECT slot FROM collect_ops.jobs_dispatches WHERE id=$1',[first.dispatch_id])).rows[0].slot;
 const replay=(await db.query("SELECT collect_ops.dispatch_jobs('scheduled',$1::uuid) AS v",[randomUUID()])).rows[0].v;
 if(replay.replayed){assert.equal(replay.dispatch_id,first.dispatch_id);}
 else {assert.equal(replay.state,'awaiting');
  const later=(await db.query('SELECT slot FROM collect_ops.jobs_dispatches WHERE id=$1',[replay.dispatch_id])).rows[0].slot;
  assert(later.getTime()>firstSlot.getTime());assert.equal((later.getTime()-firstSlot.getTime())%60000,0);await finish(replay);}checks++;

 // The old 10,000 ceiling is gone; 50,000 remains a hard monthly dispatch
 // ceiling. Synthetic probe rows avoid altering SMS or financial state.
 await db.query("INSERT INTO collect_ops.jobs_dispatches(id,kind,state) SELECT gen_random_uuid(),'probe','reviewed_unknown' FROM generate_series(1,10001)");
 const afterTen=(await db.query("SELECT collect_ops.dispatch_jobs('scheduled',$1::uuid) AS v",[randomUUID()])).rows[0].v;
 assert.notEqual(afterTen.state,'monthly_budget_exhausted');if(afterTen.state==='awaiting')await finish(afterTen);
 const current=(await db.query("SELECT count(*)::int AS n FROM collect_ops.jobs_dispatches WHERE created_at>=date_trunc('month',clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'")).rows[0].n;
 await db.query("INSERT INTO collect_ops.jobs_dispatches(id,kind,state) SELECT gen_random_uuid(),'probe','reviewed_unknown' FROM generate_series(1,$1)",[50000-current]);
 assert.equal((await db.query("SELECT collect_ops.dispatch_jobs('scheduled',$1::uuid) AS v",[randomUUID()])).rows[0].v.state,'monthly_budget_exhausted');
 assert.equal((await db.query('SELECT enabled FROM collect_ops.jobs_config')).rows[0].enabled,false);checks++;

 // Call the actual native drain functions with empty selectors: neither the
 // OpenAI adapter nor a financial posting can be reached without a candidate.
 let aiCalls=0,queries=0;const work={kind:'jobs',assert:async()=>{}};
 const emptyDb={applicationWork:work,context:async()=>{},transaction:async fn=>fn({unsafe:async sql=>{
  queries++;if(sql.includes('pg_advisory_xact_lock'))return [];
  assert.match(sql,/burimunsi_auto_collections|burimunsi_native_sms_post_candidates/);return [{result:[]}];}})};
 const env={DB:emptyDb,BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true',MOMO_AI_ENABLED:'true',MOMO_AI_MODEL:'fixture-model',OPENAI_API_KEY:'fixture',AI:{run:async()=>{aiCalls++;throw Error('unexpected AI call');}}};
 assert.deepEqual(await drainNativeAutoTransactions(env,{limit:1}),{status:'complete',processed:0,results:[]});
 assert.deepEqual(await drainNativeSmsLedger(env,{limit:1}),{status:'complete',processed:0,results:[]});
 assert.equal(aiCalls,0);assert.equal(queries,3);checks++;
 console.log(JSON.stringify({suite:'managed-jobs-schedule-one-minute',checks,fixture:'owned socket-only PostgreSQL 17',provider_calls:0,cloud_calls:0}));
}finally{for(const c of clients)await c.end().catch(()=>{});await f.close();}
