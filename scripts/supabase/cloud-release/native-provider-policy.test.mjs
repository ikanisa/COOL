// Verify the actual forward SQL against isolated PostgreSQL 17. Only synthetic
// identities, tickets and provider doubles are used; no production traffic.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {randomUUID,createHash} from 'node:crypto';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {verifyBinaryPins,verifyEnvironment,BIN} from '../managed-identity-provider-compat/fixture-safety.mjs';
import {renderNativeProviderBudget} from './native-provider-budget-render.mjs';
import {renderNativeProviderPolicy} from './native-provider-policy-render.mjs';
import {withNativeProviderBudget} from '../../../supabase/functions/_shared/native-provider-budget.mjs';

verifyEnvironment(process.env);await verifyBinaryPins();
const previous=await renderNativeProviderBudget(),candidate=await renderNativeProviderPolicy();
assert.equal(candidate.sql,await readFile(new URL('../../../supabase/migrations/20261117134926_collect_native_provider_policy.sql',import.meta.url),'utf8'));
const {Client}=createRequire(import.meta.url)('pg'),source='a'.repeat(64),approval='b'.repeat(64),oldModel='gpt-5.4-mini-2026-03-17',newModel='synthetic-alternate-model-v1';
const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_native_policy_fixture'});
assert.equal(f.bin,BIN);const clients=[];
async function connect(user){const c=new Client({host:f.socket,port:f.port,database:'postgres',user,connectionTimeoutMillis:5000});c.on('error',()=>{});await c.connect();clients.push(c);return c;}
let checks=0;
try{
 const root=await connect('fixture_bootstrap');
 await root.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS;CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_runtime;CREATE ROLE collect_importer;GRANT collect_runtime TO postgres;
 CREATE SCHEMA private AUTHORIZATION postgres;CREATE SCHEMA collect_ops AUTHORIZATION postgres;CREATE SCHEMA cron AUTHORIZATION postgres;GRANT USAGE ON SCHEMA private TO collect_runtime;`);
 const db=await connect('postgres');
 await db.query(`CREATE TABLE cron.job(jobid bigint PRIMARY KEY,active boolean NOT NULL);INSERT INTO cron.job VALUES(1,false);
 CREATE TABLE collect_ops.jobs_config(singleton boolean PRIMARY KEY,enabled boolean NOT NULL DEFAULT false,cron_job_id bigint,readiness jsonb,last_probe_id uuid);INSERT INTO collect_ops.jobs_config(singleton,enabled,cron_job_id) VALUES(true,false,1);
 CREATE FUNCTION collect_ops.pause_jobs() RETURNS void LANGUAGE sql AS $$ UPDATE collect_ops.jobs_config SET enabled=false $$;
 CREATE TABLE collect_ops.jobs_dispatches(id uuid PRIMARY KEY,state text,net_request_id bigint);
 CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY,mode text);INSERT INTO private.collect_fence_control VALUES(true,'fenced');
 CREATE TABLE private.collect_fence_admissions(admission_id uuid PRIMARY KEY,epoch bigint,source_sha256 text,kind text,state text);
 CREATE TABLE private.collect_managed_job_tickets(dispatch_id uuid PRIMARY KEY,source_sha256 text,admission_id uuid,claimed_at timestamptz,completed_at timestamptz,expires_at timestamptz,payload jsonb);
 ALTER TABLE private.collect_managed_job_tickets ENABLE ROW LEVEL SECURITY;ALTER TABLE private.collect_managed_job_tickets FORCE ROW LEVEL SECURITY;
 CREATE POLICY ticket_owner ON private.collect_managed_job_tickets TO postgres USING(true) WITH CHECK(true);
 CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF current_user<>'postgres' OR current_setting('role',true)='collect_runtime' THEN RAISE EXCEPTION 'denied';END IF;END $$;
 CREATE FUNCTION private._collect_fence_require_runtime() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF current_setting('role',true) IS DISTINCT FROM 'collect_runtime' THEN RAISE EXCEPTION 'denied';END IF;END $$;
 CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN IF $1 IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE admission_id=$1 AND epoch=$2 AND source_sha256=$3 AND state='active') THEN RAISE EXCEPTION 'fenced';END IF;RETURN '{}'::jsonb;END $$;
 CREATE FUNCTION private.collect_fence_owner_status() RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('sourceSha256','${source}') $$;
 CREATE FUNCTION private._collect_fence_statement() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF current_setting('role',true)='collect_runtime' THEN PERFORM private.collect_fence_assert_write(current_setting('collect.fence_admission_id')::uuid,current_setting('collect.fence_epoch')::bigint,current_setting('collect.fence_source_sha256'));END IF;RETURN NULL;END $$;
 CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.collect_managed_job_tickets FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();ALTER TABLE private.collect_managed_job_tickets ENABLE ALWAYS TRIGGER collect_fence_statement_v1;`);
 await db.query(previous.original);await db.query('REVOKE ALL ON FUNCTION private._collect_fence_scheduler_status() FROM PUBLIC');await db.query(previous.sql);
 // The original scheduler migration had already made this owner-only in Cloud.
 await db.query('REVOKE ALL ON FUNCTION collect_ops.record_jobs_readiness(jsonb) FROM PUBLIC');
 await db.query('SELECT collect_ops.configure_native_provider_budget($1,$2,$3,$4)',[source,oldModel,approval,'2026-11-30T23:59:59Z']);
 await db.query('UPDATE collect_ops.jobs_config SET native_provider_used=398');
 await db.query('UPDATE cron.job SET active=true');await assert.rejects(db.query(candidate.sql));await db.query('ROLLBACK');await db.query('UPDATE cron.job SET active=false');checks++;
 await db.query(candidate.sql);
 const postimages={
  'collect_ops.record_jobs_readiness(jsonb)':/ AS \$\$([^]*?)\$\$;/.exec(candidate.readiness)?.[1],
  'collect_ops.configure_native_provider_budget(text,text,text,timestamptz)':/ AS \$budget_setup\$([^]*?)\$budget_setup\$;/.exec(candidate.setup)?.[1],
  'private.collect_native_provider_reserve(uuid,text,text,text)':/ AS \$budget_reserve\$([^]*?)\$budget_reserve\$;/.exec(candidate.reserve)?.[1]};
 for(const [signature,body] of Object.entries(postimages)){
  assert.ok(body);const actual=(await db.query("SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') digest FROM pg_proc WHERE oid=to_regprocedure($1)",[signature])).rows[0]?.digest;
  assert.equal(actual,createHash('sha256').update(body).digest('hex'));
 }checks++;
 let state=(await db.query('SELECT native_provider_source_sha256 source,native_provider_model_id model,native_provider_approval_sha256 approval,native_provider_used used,native_provider_limit AS "limit",native_provider_expires_at expiry FROM collect_ops.jobs_config')).rows[0];
 assert.deepEqual(state,{source,model:oldModel,approval,used:'398',limit:null,expiry:null});checks++;
 const admission={contract:'collect.native-sms-automation.v1',source_sha256:source,approval_sha256:approval,model_id:oldModel,batch_limit:1};
 const ready={format:'collect.jobs.readiness.v1',project_ref:'rrlduytparvsjfmegalh',endpoint:'https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-jobs',deployment_sha256:source,runtime_evidence_sha256:source,token_custody_evidence_sha256:source,copy_inventory_evidence_sha256:source,quota_evidence_sha256:source,verified_at:new Date().toISOString(),momo_processing_paused:true,remaining_invocations:50000,evidence_file_sha256:source,native_sms_admission:admission,native_provider_evidence_sha256:source,native_guard_evidence_sha256:source,remaining_native_provider_requests:null};
 await db.query('SELECT collect_ops.record_jobs_readiness($1)',[ready]);checks++;
 for(const bad of [{...ready,remaining_invocations:49999},{...ready,remaining_native_provider_requests:400},{...ready,native_sms_admission:{...admission,model_id:'wrong'}},{...ready,native_sms_admission:{...admission,approval_sha256:'c'.repeat(64)}}])await assert.rejects(db.query('SELECT collect_ops.record_jobs_readiness($1)',[bad]));checks++;
 async function fixture(kind='jobs',payload=admission){const id=randomUUID(),aid=randomUUID();await db.query('INSERT INTO private.collect_fence_admissions VALUES($1,1,$2,$3,$4)',[aid,source,kind,'active']);await db.query('INSERT INTO collect_ops.jobs_dispatches VALUES($1,$2,1)',[id,'awaiting']);
  await db.query("INSERT INTO private.collect_managed_job_tickets(dispatch_id,source_sha256,admission_id,claimed_at,expires_at,payload) VALUES($1,$2,$3,clock_timestamp(),clock_timestamp()+interval '2 minutes',$4)",[id,source,aid,{dispatch_id:id,native_sms_admission:payload}]);return{id,aid,payload:{dispatch_id:id,native_sms_admission:payload}};}
 async function reserve(c,t,args=[t.id,source,oldModel,approval]){await c.query('BEGIN');try{await c.query('SET LOCAL ROLE collect_runtime');await c.query("SELECT set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',$2,true)",[t.aid,source]);const v=(await c.query('SELECT private.collect_native_provider_reserve($1,$2,$3,$4) AS accepted',args)).rows[0].accepted;await c.query('COMMIT');return v;}catch(e){await c.query('ROLLBACK');throw e;}}
 const a=await connect('postgres'),b=await connect('postgres'),ticket=await fixture();
 assert.deepEqual(await Promise.all([reserve(a,ticket),reserve(b,ticket)]),[true,true]);assert.equal(await reserve(a,ticket),false);
 assert.equal(Number((await db.query('SELECT native_provider_used AS n FROM collect_ops.jobs_config')).rows[0].n),400);checks++;
 const next=await fixture();assert.equal(await reserve(a,next),true);assert.equal(Number((await db.query('SELECT native_provider_used AS n FROM collect_ops.jobs_config')).rows[0].n),401);checks++;
 for(const args of [[next.id,'c'.repeat(64),oldModel,approval],[next.id,source,'wrong',approval],[next.id,source,oldModel,'c'.repeat(64)]])assert.equal(await reserve(a,next,args),false);checks++;
 assert.equal(await reserve(a,await fixture('http_collect')),false);checks++;
 await a.query('SET ROLE collect_runtime');await assert.rejects(a.query('UPDATE collect_ops.jobs_config SET native_provider_used=0'));await assert.rejects(a.query('SELECT collect_ops.configure_native_provider_budget($1,$2,$3,$4)',[source,newModel,approval,null]));await a.query('RESET ROLE');checks++;
 await db.query('UPDATE collect_ops.jobs_config SET native_provider_limit=402');
 const final1=await fixture(),final2=await fixture(),last=await Promise.all([reserve(a,final1),reserve(b,final2)]);assert.equal(last.filter(Boolean).length,1);checks++;
 await assert.rejects(db.query('SELECT collect_ops.record_jobs_readiness($1)',[ready]));
 await db.query('UPDATE collect_ops.jobs_config SET native_provider_limit=410');await db.query('SELECT collect_ops.record_jobs_readiness($1)',[{...ready,remaining_native_provider_requests:8}]);
 await assert.rejects(db.query('SELECT collect_ops.record_jobs_readiness($1)',[{...ready,remaining_native_provider_requests:9}]));checks++;
 await db.query("UPDATE collect_ops.jobs_config SET native_provider_limit=NULL,native_provider_expires_at=clock_timestamp()-interval '1 second'");assert.equal(await reserve(a,await fixture()),false);
 await assert.rejects(db.query('SELECT collect_ops.record_jobs_readiness($1)',[ready]));checks++;
 await db.query('UPDATE collect_ops.jobs_config SET native_provider_model_id=$1,native_provider_expires_at=NULL',[newModel]);
 const alt={...admission,model_id:newModel},altTicket=await fixture('jobs',alt);assert.equal(await reserve(a,altTicket,[altTicket.id,source,newModel,approval]),true);checks++;
 const work={kind:'jobs',async assert(){}},env={SUPABASE_URL:'https://rrlduytparvsjfmegalh.supabase.co',COLLECT_JOB_AUTH_MODE:'supabase_dispatch_hmac_v1',BUILD_SOURCE_ID:source,COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256:approval,BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true',MOMO_AI_ENABLED:'true',MOMO_AI_MODEL:newModel,OPENAI_API_KEY:'synthetic',COLLECT_FENCE_WORK:work,
  DB:{applicationWork:work,prepare(){return{bind(...args){return{first:async()=>({accepted:await reserve(a,altTicket,args)})};}};}},AI:{async run(){return{response:'synthetic'};}}};
 const wrapped=withNativeProviderBudget(env,altTicket.payload),options={max_tokens:1400,response_format:{json_schema:{properties:{schema_version:{enum:['momo-native-extraction.v2']}}}}};
 assert.deepEqual(await wrapped.AI.run('legacy',options),{response:'synthetic'});await assert.rejects(wrapped.AI.run('legacy',options));checks++;
 console.log(JSON.stringify({suite:'native-provider-policy',checks,actualMigration:true,retainedCounter:true,noArbitraryLimit:true,cloudWrites:0,providerCalls:0}));
}finally{for(const c of clients)await c.end().catch(()=>{});await f.close();}
