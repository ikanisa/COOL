// Real SQL in an owned socket-only PG17 fixture; Cron, pg_net, Vault and the
// fence are explicit doubles. No cloud writes, provider calls or SMS occur.
import assert from 'node:assert/strict';
import {createHash,createHmac,randomBytes,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {verifyBinaryPins,verifyEnvironment,BIN} from '../managed-identity-provider-compat/fixture-safety.mjs';
import {renderManagedScheduler} from './managed-jobs-scheduler.mjs';
import {renderManagedJobsHandler} from './managed-jobs-handler-patch.mjs';
import {expectedSchedulerBodies} from './managed-jobs-operator.mjs';
import {dispatchMessage,verifyManagedJobSignature} from './managed-jobs-dispatch-auth.mjs';

verifyEnvironment(process.env);await verifyBinaryPins();
const {Client}=createRequire(import.meta.url)('pg'),src='a'.repeat(64),key=randomBytes(32).toString('hex'),project='rrlduytparvsjfmegalh';
const env={COLLECT_JOB_AUTH_MODE:'supabase_dispatch_hmac_v1',SUPABASE_URL:`https://${project}.supabase.co`,BUILD_SOURCE_ID:src,COLLECT_JOB_SIGNING_KEY:key};
const rendered=await renderManagedScheduler(),handler=await renderManagedJobsHandler();
assert.match(handler.serve,/claimManagedJobDispatch\(env\.DB,input,payload,token\)/);
assert.match(handler.processing,/dispatch_expires_at/);
const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_managed_scheduler_fixture'});
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
  INSERT INTO private.collect_fence_control VALUES(true,'fenced','rrlduytparvsjfmegalh');
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
 const fixtureSql=rendered.sql.replace('f70925051147096cfb72869b401fdb69c976b68034c87e8c3e98ee8b5f350ed0',cleanupHash)
  .replace('09ecc11aca46af15d7f981b5d5c7c7d3775be6fc245c8ff73f48f61269e37671',retentionHash);
 await db.query(fixtureSql);
 const bodies=expectedSchedulerBodies(rendered.sql);
 const actual=(await db.query(`SELECT n.nspname,p.proname,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') AS digest FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE (n.nspname='collect_ops' AND p.proname=ANY($1::text[])) OR (n.nspname='private' AND p.proname=ANY($2::text[]))`,[Object.keys(bodies.ops),Object.keys(bodies.private)])).rows;
 assert.equal(actual.length,11);for(const x of actual)assert.equal(x.digest,bodies[x.nspname==='collect_ops'?'ops':'private'][x.proname]);checks++;
 assert.equal((await db.query("SELECT private._retention_manifest_catalog_v2()->'private_classes' AS classes")).rows[0].classes[0].blocked,true);checks++;
 assert.deepEqual((await db.query('SELECT enabled,(SELECT active FROM cron.job) AS active FROM collect_ops.jobs_config')).rows[0],{enabled:false,active:false});checks++;
 assert.equal((await db.query('SELECT collect_ops.tick_jobs() AS v')).rows[0].v.state,'disabled');checks++;
 const ready={format:'collect.jobs.readiness.v1',project_ref:project,endpoint:`https://${project}.supabase.co/functions/v1/collect-jobs`,
  deployment_sha256:'1'.repeat(64),runtime_evidence_sha256:'2'.repeat(64),token_custody_evidence_sha256:'3'.repeat(64),
  copy_inventory_evidence_sha256:'4'.repeat(64),quota_evidence_sha256:'5'.repeat(64),verified_at:new Date().toISOString(),
  momo_processing_paused:true,remaining_invocations:10000,evidence_file_sha256:'6'.repeat(64)};
 const baseReply={maintenance:{status:'complete',examined_limit:100,purged:0,provider_calls:0},processing:{processed:0,results:[],paused:true}};
 async function probe(r){await db.query('SELECT collect_ops.record_jobs_readiness($1::jsonb)',[r]);return (await db.query("SELECT collect_ops.dispatch_jobs('probe',$1::uuid) AS v",[randomUUID()])).rows[0].v;}
 async function queued(d){const q=(await db.query("SELECT headers,convert_from(body,'UTF8')::jsonb AS body FROM net.http_request_queue WHERE id=$1",[d.net_request_id])).rows[0];assert(q);return q;}
 async function claim(q){const aid=randomUUID();await db.query('INSERT INTO private.collect_fence_admissions VALUES($1,1,$2,$3,$4)',[aid,src,'jobs','active']);
  await db.query('BEGIN');try{await db.query('SET LOCAL ROLE collect_runtime');await db.query("SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',$2,true)",[aid,src]);
   const got=(await db.query('SELECT private.collect_managed_job_claim($1,$2,$3,$4) AS ok',[q.body.dispatch_id,src,q.body,q.headers.Authorization.slice(7)])).rows[0].ok;await db.query('COMMIT');if(got)q.admission=aid;return got;
  }catch(e){await db.query('ROLLBACK');throw e;}}
 async function reply(d,q,value,complete=true){const body=JSON.stringify({dispatch_id:d.dispatch_id,...value});
  if(complete){await db.query('BEGIN');try{await db.query('SET LOCAL ROLE collect_runtime');await db.query("SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',$2,true)",[q.admission,src]);
   assert.equal((await db.query('SELECT private.collect_managed_job_complete($1,$2,$3) AS ok',[d.dispatch_id,src,createHash('sha256').update(body).digest('hex')])).rows[0].ok,true);await db.query('COMMIT');
  }catch(e){await db.query('ROLLBACK');throw e;}}
  await db.query('INSERT INTO net._http_response(id,status_code,content) VALUES($1,200,$2)',[d.net_request_id,body]);await db.query('DELETE FROM net.http_request_queue WHERE id=$1',[d.net_request_id]);await db.query('SELECT collect_ops.reconcile_jobs()');return (await db.query('SELECT state,reason FROM collect_ops.jobs_dispatches WHERE id=$1',[d.dispatch_id])).rows[0];}
 const p=await probe(ready),q=await queued(p);
 assert.equal(await verifyManagedJobSignature(env,q.body,q.headers.Authorization),true);
 assert.equal(q.headers.Authorization,'Bearer '+createHmac('sha256',key).update(dispatchMessage(src,p.dispatch_id,q.body.dispatch_expires_at)).digest('hex'));
 assert.equal(JSON.stringify(q).includes(key),false);checks++;
 assert.equal(await claim(q),true);assert.equal(await claim(q),false);checks++;
 assert.equal((await reply(p,q,baseReply)).state,'confirmed');checks++;
 await db.query('SELECT collect_ops.activate_jobs($1)',['6'.repeat(64)]);
 assert.equal((await db.query('SELECT enabled FROM collect_ops.jobs_config')).rows[0].enabled,true);checks++;
 const admission={contract:'collect.native-sms-automation.v1',source_sha256:src,approval_sha256:'b'.repeat(64),model_id:'fixture-model',batch_limit:1};
 const nativeReady={...ready,native_sms_admission:admission,native_provider_evidence_sha256:'c'.repeat(64),native_guard_evidence_sha256:'d'.repeat(64),remaining_native_provider_requests:10000,evidence_file_sha256:'7'.repeat(64)};
 for(const bad of [{...nativeReady,native_sms_admission:{...admission,batch_limit:2}},{...nativeReady,native_sms_admission:{...admission,source_sha256:'e'.repeat(64)}},{...nativeReady,native_guard_evidence_sha256:null},{...nativeReady,remaining_native_provider_requests:9999}])
  await assert.rejects(db.query('SELECT collect_ops.record_jobs_readiness($1)',[bad]));checks++;
 const n=await probe(nativeReady),nq=await queued(n);assert.deepEqual(nq.body.native_sms_admission,admission);assert.equal(await claim(nq),true);
 const nativeReply={...baseReply,native_sms_admission:admission,native_auto_processing:{status:'complete',processed:1,results:[{state:'completed',relation:'duplicate'}]},native_sms_ledger:{status:'complete',processed:0,results:[]}};
 assert.equal((await reply(n,nq,nativeReply)).state,'confirmed');await db.query('SELECT collect_ops.activate_jobs($1)',['7'.repeat(64)]);checks++;
 const periodic=(await db.query('SELECT collect_ops.tick_jobs() AS v')).rows[0].v;assert.equal(periodic.state,'awaiting');const pq=await queued(periodic);assert.equal(await claim(pq),true);
 const malformed={...nativeReply,native_auto_processing:{status:'complete',processed:1,results:[{state:null}]}};
 assert.equal((await reply(periodic,pq,malformed)).state,'unconfirmed');
 assert.deepEqual((await db.query('SELECT enabled,(SELECT active FROM cron.job) AS active FROM collect_ops.jobs_config')).rows[0],{enabled:false,active:false});checks++;
 await db.query("UPDATE collect_ops.jobs_dispatches SET created_at=clock_timestamp()-interval '6 minutes' WHERE id=$1",[periodic.dispatch_id]);
 await db.query('SELECT collect_ops.review_unknown_jobs($1,$2)',[periodic.dispatch_id,'8'.repeat(64)]);
 const forged=await probe(ready),fq=await queued(forged);assert.equal(await claim(fq),true);
 assert.equal((await reply(forged,fq,baseReply,false)).state,'unconfirmed');checks++;
 assert.equal((await db.query("SELECT count(*)::int AS n FROM net.http_request_queue")).rows[0].n,0);checks++;
 console.log(JSON.stringify({suite:'managed-jobs-scheduler',checks,fixture:'owned socket-only PostgreSQL 17; provider interfaces are doubles',cloud_calls:0}));
}finally{for(const c of clients)await c.end().catch(()=>{});await f.close();}
