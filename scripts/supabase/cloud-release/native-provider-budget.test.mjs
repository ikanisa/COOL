// Real reservation SQL in an owned local PostgreSQL17. Admissions and provider
// I/O are explicit doubles; no live credits, messages or financial writes.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {verifyBinaryPins,verifyEnvironment,BIN} from '../managed-identity-provider-compat/fixture-safety.mjs';
import {withNativeProviderBudget} from '../../../supabase/functions/_shared/native-provider-budget.mjs';
import {renderNativeProviderBudget} from './native-provider-budget-render.mjs';
verifyEnvironment(process.env);await verifyBinaryPins();
const {Client}=createRequire(import.meta.url)('pg'),source='a'.repeat(64),approval='b'.repeat(64),model='gpt-5.4-mini-2026-03-17';
const rendered=await renderNativeProviderBudget();assert.match(rendered.sql,/remaining_native_provider_requests'\)::bigint<2/);
assert.match(rendered.sql,/remaining_provider_requests'\)::bigint<10000/);
assert.equal(rendered.sql,await readFile(new URL('../../../supabase/migrations/20261117081411_collect_native_provider_budget.sql',import.meta.url),'utf8'));
const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_native_budget_fixture'});
assert.equal(f.bin,BIN);const clients=[];
async function connect(user){const c=new Client({host:f.socket,port:f.port,database:'postgres',user,connectionTimeoutMillis:5000});c.on('error',()=>{});await c.connect();clients.push(c);return c;}
let checks=0,providerCalls=0;
try{
 const root=await connect('fixture_bootstrap');
 await root.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS;CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_runtime;CREATE ROLE collect_importer;GRANT collect_runtime TO postgres;
 CREATE SCHEMA private AUTHORIZATION postgres;CREATE SCHEMA collect_ops AUTHORIZATION postgres;GRANT USAGE ON SCHEMA private TO collect_runtime;`);
 const db=await connect('postgres');
 await db.query(`CREATE TABLE collect_ops.jobs_config(singleton boolean PRIMARY KEY,enabled boolean NOT NULL DEFAULT false,readiness jsonb,last_probe_id uuid);INSERT INTO collect_ops.jobs_config(singleton,enabled) VALUES(true,false);
 CREATE FUNCTION collect_ops.pause_jobs() RETURNS void LANGUAGE sql AS $$ UPDATE collect_ops.jobs_config SET enabled=false $$;
 CREATE TABLE collect_ops.jobs_dispatches(id uuid PRIMARY KEY,state text,net_request_id bigint);
 CREATE TABLE private.collect_fence_admissions(admission_id uuid PRIMARY KEY,epoch bigint,source_sha256 text,kind text,state text);
 CREATE TABLE private.collect_managed_job_tickets(dispatch_id uuid PRIMARY KEY,source_sha256 text,admission_id uuid,claimed_at timestamptz,completed_at timestamptz,expires_at timestamptz,payload jsonb);
 ALTER TABLE private.collect_managed_job_tickets ENABLE ROW LEVEL SECURITY;ALTER TABLE private.collect_managed_job_tickets FORCE ROW LEVEL SECURITY;
 CREATE POLICY ticket_owner ON private.collect_managed_job_tickets TO postgres USING(true) WITH CHECK(true);
 CREATE FUNCTION private._collect_fence_require_operator() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF current_user<>'postgres' OR current_setting('role',true)='collect_runtime' THEN RAISE EXCEPTION 'denied';END IF;END $$;
 CREATE FUNCTION private._collect_fence_require_runtime() RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF current_setting('role',true) IS DISTINCT FROM 'collect_runtime' THEN RAISE EXCEPTION 'denied';END IF;END $$;
 CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN IF $1 IS NOT NULL AND NOT EXISTS(SELECT 1 FROM private.collect_fence_admissions WHERE admission_id=$1 AND epoch=$2 AND source_sha256=$3 AND state='active') THEN RAISE EXCEPTION 'fenced';END IF;RETURN '{}'::jsonb;END $$;
 CREATE FUNCTION private.collect_fence_owner_status() RETURNS jsonb LANGUAGE sql AS $$ SELECT jsonb_build_object('sourceSha256','${source}') $$;
 CREATE FUNCTION private._collect_fence_statement() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF current_setting('role',true)='collect_runtime' THEN PERFORM private.collect_fence_assert_write(current_setting('collect.fence_admission_id')::uuid,current_setting('collect.fence_epoch')::bigint,current_setting('collect.fence_source_sha256'));END IF;RETURN NULL;END $$;
 CREATE TRIGGER collect_fence_statement_v1 BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON private.collect_managed_job_tickets FOR EACH STATEMENT EXECUTE FUNCTION private._collect_fence_statement();
 ALTER TABLE private.collect_managed_job_tickets ENABLE ALWAYS TRIGGER collect_fence_statement_v1;`);
 await db.query(rendered.original);await db.query('REVOKE ALL ON FUNCTION private._collect_fence_scheduler_status() FROM PUBLIC');
 await db.query(rendered.sql);
 await assert.rejects(db.query('SELECT collect_ops.configure_native_provider_budget($1,$2,$3,$4)',[source,model,approval,'2026-12-01T00:00:00Z']));checks++;
 await db.query('SELECT collect_ops.configure_native_provider_budget($1,$2,$3,$4)',[source,model,approval,'2026-11-30T23:59:59Z']);
 await assert.rejects(db.query('SELECT collect_ops.configure_native_provider_budget($1,$2,$3,$4)',[source,model,approval,'2026-11-30T23:59:59Z']));checks++;
 const admission={contract:'collect.native-sms-automation.v1',source_sha256:source,approval_sha256:approval,model_id:model,batch_limit:1};
 const ready={format:'collect.jobs.readiness.v1',project_ref:'rrlduytparvsjfmegalh',endpoint:'https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-jobs',
  deployment_sha256:source,runtime_evidence_sha256:source,token_custody_evidence_sha256:source,copy_inventory_evidence_sha256:source,
  quota_evidence_sha256:source,verified_at:new Date().toISOString(),momo_processing_paused:true,remaining_invocations:10000,evidence_file_sha256:source,
  native_sms_admission:admission,native_provider_evidence_sha256:source,native_guard_evidence_sha256:source,remaining_native_provider_requests:2};
 await db.query('SELECT collect_ops.record_jobs_readiness($1)',[ready]);checks++;
 for(const bad of [{...ready,remaining_native_provider_requests:1},{...ready,remaining_native_provider_requests:10000},
  {...ready,native_sms_admission:{...admission,approval_sha256:'c'.repeat(64)}},{...ready,remaining_invocations:9999}])
  await assert.rejects(db.query('SELECT collect_ops.record_jobs_readiness($1)',[bad]));checks++;
 async function fixture(kind='jobs',changes={}){const id=randomUUID(),aid=randomUUID(),payload={dispatch_id:id,native_sms_admission:admission};
  await db.query('INSERT INTO private.collect_fence_admissions VALUES($1,1,$2,$3,$4)',[aid,source,kind,'active']);
  await db.query('INSERT INTO collect_ops.jobs_dispatches VALUES($1,$2,1)',[id,'awaiting']);
  await db.query("INSERT INTO private.collect_managed_job_tickets(dispatch_id,source_sha256,admission_id,claimed_at,expires_at,payload) VALUES($1,$2,$3,clock_timestamp(),clock_timestamp()+interval '2 minutes',$4)",[id,source,aid,payload]);return {id,aid,payload,...changes};}
 async function reserve(c,t,args=[t.id,source,model,approval]){await c.query('BEGIN');try{await c.query('SET LOCAL ROLE collect_runtime');await c.query("SELECT set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',$2,true)",[t.aid,source]);const v=(await c.query('SELECT private.collect_native_provider_reserve($1,$2,$3,$4) AS accepted',args)).rows[0];await c.query('COMMIT');return v;}catch(e){await c.query('ROLLBACK');throw e;}}
 const actor=await connect('postgres'),other=await connect('postgres'),t=await fixture();
 const used=async()=>Number((await db.query('SELECT native_provider_used AS n FROM collect_ops.jobs_config')).rows[0].n);
 assert.equal(await used(),0);checks++;
 for(const args of [[t.id,'c'.repeat(64),model,approval],[t.id,source,'wrong',approval],[t.id,source,model,'c'.repeat(64)]])assert.equal((await reserve(actor,t,args)).accepted,false);checks++;
 const http=await fixture('http_collect');assert.equal((await reserve(actor,http)).accepted,false);checks++;
 const wrong=await fixture();assert.equal((await reserve(actor,{...wrong,aid:t.aid})).accepted,false);checks++;
 await db.query('UPDATE private.collect_managed_job_tickets SET claimed_at=NULL WHERE dispatch_id=$1',[wrong.id]);assert.equal((await reserve(actor,wrong)).accepted,false);checks++;
 const expired=await fixture();await db.query("UPDATE private.collect_managed_job_tickets SET expires_at=clock_timestamp()-interval '1 second' WHERE dispatch_id=$1",[expired.id]);assert.equal((await reserve(actor,expired)).accepted,false);checks++;
 const done=await fixture();await db.query('UPDATE private.collect_managed_job_tickets SET completed_at=clock_timestamp() WHERE dispatch_id=$1',[done.id]);assert.equal((await reserve(actor,done)).accepted,false);checks++;
 const noNative=await fixture();await db.query("UPDATE private.collect_managed_job_tickets SET payload=payload-'native_sms_admission' WHERE dispatch_id=$1",[noNative.id]);assert.equal((await reserve(actor,noNative)).accepted,false);checks++;
 assert.equal(await used(),0);checks++;
 const calls=await Promise.all([reserve(actor,t),reserve(other,t)]);assert(calls.every(x=>x.accepted));assert.equal((await reserve(actor,t)).accepted,false);assert.equal(await used(),2);checks++;
 const work={kind:'jobs',async assert(){}};let reserveCalls=0;
 const wrappedTicket=await fixture();
 const env={SUPABASE_URL:'https://rrlduytparvsjfmegalh.supabase.co',COLLECT_JOB_AUTH_MODE:'supabase_dispatch_hmac_v1',BUILD_SOURCE_ID:source,COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256:approval,BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true',MOMO_AI_ENABLED:'true',MOMO_AI_MODEL:model,OPENAI_API_KEY:'synthetic',COLLECT_FENCE_WORK:work,
  DB:{applicationWork:work,prepare(){return{bind(...args){return{first:async()=>{reserveCalls++;return reserve(actor,wrappedTicket,args);}};}};}},AI:{async run(){providerCalls++;return{response:'synthetic'};}}};
 const wrapped=withNativeProviderBudget(env,wrappedTicket.payload);assert.equal(reserveCalls,0);assert.equal(await used(),2);checks++;
 const options={max_tokens:1400,response_format:{json_schema:{properties:{schema_version:{enum:['momo-native-extraction.v2']}}}}};
 await wrapped.AI.run('legacy',options);assert.equal(reserveCalls,1);assert.equal(providerCalls,1);checks++;
 await assert.rejects(wrapped.AI.run('legacy',{...options,max_tokens:1401}));assert.equal(reserveCalls,1);checks++;
 const badWork={kind:'http_collect',async assert(){}};await assert.rejects(withNativeProviderBudget({...env,COLLECT_FENCE_WORK:badWork,DB:{...env.DB,applicationWork:badWork}},wrappedTicket.payload).AI.run('legacy',options));assert.equal(reserveCalls,1);checks++;
 // Simulate an already-consumed lifetime budget using fixture-owner setup;
 // the production runtime has neither table privilege nor a reset function.
 await db.query('UPDATE collect_ops.jobs_config SET native_provider_used=399');const finalA=await fixture(),finalB=await fixture();
 const final=await Promise.all([reserve(actor,finalA),reserve(other,finalB)]);assert.equal(final.filter(x=>x.accepted).length,1);assert.equal(await used(),400);checks++;
 await assert.rejects(wrapped.AI.run('legacy',options));assert.equal(providerCalls,1);checks++;
 await db.query("UPDATE collect_ops.jobs_config SET native_provider_used=0,native_provider_expires_at=clock_timestamp()-interval '1 second'");assert.equal((await reserve(actor,await fixture())).accepted,false);
 await assert.rejects(db.query('SELECT collect_ops.record_jobs_readiness($1)',[ready]));checks++;
 const blocked=await fixture();await other.query('BEGIN');await other.query('SELECT 1 FROM private.collect_managed_job_tickets WHERE dispatch_id=$1 FOR UPDATE',[blocked.id]);
 await db.query("UPDATE collect_ops.jobs_config SET native_provider_expires_at=clock_timestamp()+interval '100 milliseconds'");
 const crossingExpiry=reserve(actor,blocked);await db.query('SELECT pg_sleep(0.2)');await other.query('COMMIT');
 assert.equal((await crossingExpiry).accepted,false);assert.equal(await used(),0);checks++;
 await actor.query('SET ROLE collect_runtime');await assert.rejects(actor.query('UPDATE collect_ops.jobs_config SET native_provider_used=0'));await assert.rejects(actor.query('SELECT collect_ops.configure_native_provider_budget($1,$2,$3,$4)',[source,model,approval,'2026-11-30T23:59:59Z']));await actor.query('RESET ROLE');checks++;
 const guards=(await db.query("SELECT relforcerowsecurity,(SELECT tgenabled FROM pg_trigger WHERE tgrelid=c.oid AND tgname='collect_fence_statement_v1') AS trigger FROM pg_class c WHERE oid='private.collect_managed_job_tickets'::regclass")).rows[0];assert.equal(guards.relforcerowsecurity,true);assert.equal(guards.trigger,'A');checks++;
 // Exercise the actual fence inventory against the new owner-only function,
 // using bounded scheduler doubles and the untouched original guard rules.
 await db.query(`CREATE TABLE private.collect_fence_control(singleton boolean PRIMARY KEY);
 CREATE TABLE private.collect_fence_scheduler_lifecycle(dispatch_id uuid,native_epoch text);
 ALTER TABLE collect_ops.jobs_dispatches ADD COLUMN native_epoch text;
 UPDATE collect_ops.jobs_dispatches SET state='confirmed';`);
 for(const [name,args] of [['cleanup_google_expired',''],['reconcile_jobs',''],['dispatch_jobs','text,uuid'],['activate_jobs','text'],['review_unknown_jobs','uuid,text'],['tick_jobs','']])
  await db.query(`CREATE FUNCTION collect_ops.${name}(${args}) RETURNS void LANGUAGE plpgsql AS $$BEGIN
 -- collect_fence_sql2_write_guard_v1
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 END$$;`);
 await db.query('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA collect_ops FROM PUBLIC');
 const coverage=async()=>{const v=(await db.query('SELECT private._collect_fence_scheduler_status() AS value')).rows[0].value;assert.equal(v.checked,true);return v.coverageVerified;};
 await db.query(rendered.original.replace('CREATE FUNCTION ','CREATE OR REPLACE FUNCTION '));assert.equal(await coverage(),false);
 await db.query(rendered.schedulerStatus);assert.equal(await coverage(),true);checks++;
 const setupSignature='collect_ops.configure_native_provider_budget(text,text,text,timestamptz)';
 const setupDefinition=(await db.query('SELECT pg_get_functiondef($1::regprocedure) AS definition',[setupSignature])).rows[0].definition;
 await db.query('GRANT EXECUTE ON FUNCTION '+setupSignature+' TO collect_runtime');assert.equal(await coverage(),false);
 await db.query('REVOKE ALL ON FUNCTION '+setupSignature+' FROM collect_runtime');assert.equal(await coverage(),true);checks++;
 await db.query('GRANT EXECUTE ON FUNCTION '+setupSignature+' TO PUBLIC');assert.equal(await coverage(),false);
 await db.query('REVOKE ALL ON FUNCTION '+setupSignature+' FROM PUBLIC');assert.equal(await coverage(),true);checks++;
 await db.query(setupDefinition.replace(' -- collect_fence_sql2_write_guard_v1\n',''));assert.equal(await coverage(),false);
 await db.query(setupDefinition);assert.equal(await coverage(),true);checks++;
 await db.query('ALTER FUNCTION '+setupSignature+' SECURITY DEFINER');assert.equal(await coverage(),false);
 await db.query('ALTER FUNCTION '+setupSignature+' SECURITY INVOKER');assert.equal(await coverage(),true);checks++;
 const oldDefinition=(await db.query("SELECT pg_get_functiondef('collect_ops.reconcile_jobs()'::regprocedure) AS definition")).rows[0].definition;
 await db.query(oldDefinition.replace(' -- collect_fence_sql2_write_guard_v1\n',''));assert.equal(await coverage(),false);
 await db.query(oldDefinition);assert.equal(await coverage(),true);checks++;
 await db.query('CREATE FUNCTION collect_ops.unreviewed_budget_function() RETURNS void LANGUAGE sql AS $$ SELECT $$;REVOKE ALL ON FUNCTION collect_ops.unreviewed_budget_function() FROM PUBLIC');
 assert.equal(await coverage(),false);await db.query('DROP FUNCTION collect_ops.unreviewed_budget_function()');assert.equal(await coverage(),true);checks++;
 await db.query('CREATE FUNCTION collect_ops.configure_native_provider_budget(text,text,text,timestamp) RETURNS void LANGUAGE sql AS $$ SELECT $$;REVOKE ALL ON FUNCTION collect_ops.configure_native_provider_budget(text,text,text,timestamp) FROM PUBLIC');
 assert.equal(await coverage(),false);await db.query('DROP FUNCTION collect_ops.configure_native_provider_budget(text,text,text,timestamp)');assert.equal(await coverage(),true);checks++;
 console.log(JSON.stringify({suite:'native-provider-budget',checks,actualSql:true,concurrentLifetimeCap:true,concurrentDispatchCap:true,syntheticProviderCalls:providerCalls,liveProviderCalls:0,cloudWrites:0}));
}finally{for(const c of clients)await c.end().catch(()=>{});await f.close();}
