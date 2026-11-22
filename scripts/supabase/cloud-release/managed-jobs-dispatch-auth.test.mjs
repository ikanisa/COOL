import assert from 'node:assert/strict';
import {createHash,createHmac,randomBytes,randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {startOwnedPg17} from '../current-pg-transfer/test-support/owned-pg17.mjs';
import {verifyBinaryPins,verifyEnvironment,BIN} from '../managed-identity-provider-compat/fixture-safety.mjs';
import {dispatchMessage,verifyManagedJobSignature,claimManagedJobDispatch,completeManagedJobDispatch,nativeSmsAdmission} from '../../../supabase/functions/_shared/managed-jobs-dispatch-auth.mjs';

const {Client}=createRequire(import.meta.url)('pg');
const source='a'.repeat(64),key=randomBytes(32).toString('hex'),project='rrlduytparvsjfmegalh';
const env={COLLECT_JOB_AUTH_MODE:'supabase_dispatch_hmac_v1',SUPABASE_URL:`https://${project}.supabase.co`,BUILD_SOURCE_ID:source,COLLECT_JOB_SIGNING_KEY:key};
const signature=(id,expires)=>'Bearer '+createHmac('sha256',key).update(dispatchMessage(source,id,expires)).digest('hex');
const expires=Math.floor(Date.now()/1000)+60;
const id=randomUUID(),payload={dispatch_id:id,dispatch_expires_at:expires};
assert.equal(await verifyManagedJobSignature(env,payload,signature(id,expires)),true);
for(const changed of [
 {...env,COLLECT_JOB_AUTH_MODE:'legacy'}, {...env,SUPABASE_URL:'https://attacker.example'},
 {...env,BUILD_SOURCE_ID:'b'.repeat(64)}, {...env,COLLECT_JOB_SIGNING_KEY:'c'.repeat(64)},
 {...env,COLLECT_JOB_SIGNING_KEY:''},
])assert.equal(await verifyManagedJobSignature(changed,payload,signature(id,expires)),false);
for(const [p,a] of [[{},signature(id,expires)],[payload,'Bearer '+'0'.repeat(64)],[payload,signature(id,expires)+' '],[payload,'Bearer '+key],
 [{...payload,dispatch_expires_at:Math.floor(Date.now()/1000)-1},signature(id,expires)],
 [{...payload,dispatch_expires_at:Math.floor(Date.now()/1000)+3600},signature(id,expires)]])
 assert.equal(await verifyManagedJobSignature(env,p,a),false);
let dbCalls=0;
const badDb={prepare(){dbCalls++;throw Error('must_not_reach_db');}};
assert.equal(await claimManagedJobDispatch(badDb,env,payload,'Bearer '+key),false);assert.equal(dbCalls,0);
const admissionContract={contract:'collect.native-sms-automation.v1',source_sha256:source,approval_sha256:'b'.repeat(64),model_id:'test-model',batch_limit:1};
const nativeEnv={...env,BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED:'true',COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256:'b'.repeat(64),MOMO_AI_MODEL:'test-model',MOMO_AI_ENABLED:'true',OPENAI_API_KEY:'fixture',AI:{run(){}}};
assert.deepEqual(nativeSmsAdmission(env,payload),{allowed:true,enabled:false});
assert.equal(nativeSmsAdmission(nativeEnv,payload).allowed,false);
assert.equal(nativeSmsAdmission(env,{...payload,native_sms_admission:admissionContract}).allowed,false);
assert.equal(nativeSmsAdmission(nativeEnv,{...payload,native_sms_admission:admissionContract}).allowed,true);
for(const altered of [{...admissionContract,source_sha256:'c'.repeat(64)},{...admissionContract,approval_sha256:'c'.repeat(64)},{...admissionContract,batch_limit:2},{...admissionContract,model_id:'other'},{...admissionContract,extra:true}])
 assert.equal(nativeSmsAdmission(nativeEnv,{...payload,native_sms_admission:altered}).allowed,false);

verifyEnvironment(process.env);await verifyBinaryPins();
const f=await startOwnedPg17({prefix:'collect-pg-transfer-',initialUser:'fixture_bootstrap',clusterName:'collect_managed_jobs_auth_fixture'});
assert.equal(f.bin,BIN);const clients=[];
async function connect(user){const c=new Client({host:f.socket,port:f.port,database:'postgres',user,connectionTimeoutMillis:5000});c.on('error',()=>{});await c.connect();clients.push(c);return c;}
let checks=0;
try{
 const superuser=await connect('fixture_bootstrap');
 await superuser.query(`CREATE ROLE postgres LOGIN NOSUPERUSER NOBYPASSRLS;CREATE ROLE anon;CREATE ROLE authenticated;CREATE ROLE service_role;CREATE ROLE collect_runtime;CREATE ROLE collect_importer;GRANT collect_runtime,anon TO postgres;
 CREATE SCHEMA extensions;CREATE EXTENSION pgcrypto WITH SCHEMA extensions;GRANT USAGE ON SCHEMA extensions TO postgres;
 CREATE SCHEMA private AUTHORIZATION postgres;CREATE SCHEMA collect_ops AUTHORIZATION postgres;CREATE SCHEMA vault AUTHORIZATION postgres;
 GRANT USAGE ON SCHEMA private TO collect_runtime;`);
 const owner=await connect('postgres');
 await owner.query(`CREATE TABLE vault.decrypted_secrets(name text PRIMARY KEY,decrypted_secret text);
 CREATE TABLE collect_ops.jobs_dispatches(id uuid PRIMARY KEY,state text NOT NULL,net_request_id bigint);
 CREATE TABLE private.collect_fence_admissions(admission_id uuid PRIMARY KEY,epoch bigint,source_sha256 text,kind text,state text);
 CREATE FUNCTION private._collect_fence_require_runtime() RETURNS void LANGUAGE plpgsql AS $$ BEGIN
  IF current_setting('role',true) IS DISTINCT FROM 'collect_runtime' OR current_setting('collect.edge_verified',true) IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'denied';END IF;END $$;
 CREATE FUNCTION private.collect_fence_assert_write(uuid,bigint,text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM private.collect_fence_admissions a WHERE a.admission_id=$1 AND a.epoch=$2 AND a.source_sha256=$3 AND a.state='active') THEN RAISE EXCEPTION 'fenced';END IF;RETURN jsonb_build_object('contractVersion',1,'epoch',$2,'mode','open');END $$;
 CREATE FUNCTION private._collect_fence_statement() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RETURN NULL;END $$;`);
 await owner.query('INSERT INTO vault.decrypted_secrets VALUES($1,$2)',['collect_job_signing_key_v1',key]);
 await owner.query(await readFile(new URL('./managed-jobs-dispatch-claim.sql',import.meta.url),'utf8'));
 assert.equal((await owner.query("SELECT tgenabled FROM pg_trigger WHERE tgrelid='private.collect_managed_job_tickets'::regclass AND tgname='collect_fence_statement_v1'")).rows[0].tgenabled,'A');
 assert.deepEqual((await owner.query("SELECT session_user,current_user,inet_server_addr() IS NULL AS socket,current_setting('cluster_name') AS cluster")).rows[0],
  {session_user:'postgres',current_user:'postgres',socket:true,cluster:'collect_managed_jobs_auth_fixture'});
 async function ticket(i,p={dispatch_id:i,dispatch_expires_at:expires}){
  await owner.query('INSERT INTO collect_ops.jobs_dispatches VALUES($1,$2,$3)',[i,'awaiting',1]);
  await owner.query(`INSERT INTO private.collect_managed_job_tickets(dispatch_id,source_sha256,payload,created_at,expires_at)
   VALUES($1,$2,$3::jsonb,statement_timestamp()-interval '1 minute',to_timestamp($4::bigint))`,[i,source,JSON.stringify(p),p.dispatch_expires_at]);
 }
 async function admission(kind='jobs'){const v=randomUUID();await owner.query('INSERT INTO private.collect_fence_admissions VALUES($1,1,$2,$3,$4)',[v,source,kind,'active']);return v;}
 async function attempt(c,i,p,auth,aid){
  await c.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  try{await c.query('SET LOCAL ROLE collect_runtime');await c.query("SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',$2,true)",[aid,source]);
   const result=(await c.query('SELECT private.collect_managed_job_claim($1,$2,$3::jsonb,$4) accepted',[i,source,JSON.stringify(p),auth.slice(7)])).rows[0].accepted;
   await c.query('COMMIT');return result;
  }catch(e){await c.query('ROLLBACK');throw e;}
 }
 async function complete(c,i,aid,digest){
  await c.query('BEGIN ISOLATION LEVEL READ COMMITTED');try{await c.query('SET LOCAL ROLE collect_runtime');await c.query("SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch','1',true),set_config('collect.fence_source_sha256',$2,true)",[aid,source]);
   const got=(await c.query('SELECT private.collect_managed_job_complete($1,$2,$3) AS accepted',[i,source,digest])).rows[0].accepted;await c.query('COMMIT');return got;
  }catch(e){await c.query('ROLLBACK');throw e;}}
 await ticket(id);const aid=await admission(),actor=await connect('postgres');
 assert.equal(await attempt(actor,id,{...payload,extra:true},signature(id,expires),aid),false);checks++;
 assert.equal(await attempt(actor,id,payload,'Bearer '+'0'.repeat(64),aid),false);checks++;
 assert.equal(await attempt(actor,id,payload,signature(id,expires),await admission('http_collect')),false);checks++;
 assert.equal(await attempt(actor,id,payload,signature(id,expires),aid),true);checks++;
 assert.equal(await attempt(actor,id,payload,signature(id,expires),aid),false);checks++;
 assert.equal(await complete(actor,id,await admission(),'d'.repeat(64)),false);
 assert.equal(await complete(actor,id,aid,'d'.repeat(64)),true);
 assert.equal(await complete(actor,id,aid,'d'.repeat(64)),false);checks++;
 const expired=randomUUID(),oldExpiry=Math.floor(Date.now()/1000)-30;await ticket(expired,{dispatch_id:expired,dispatch_expires_at:oldExpiry});
 assert.equal(await attempt(actor,expired,{dispatch_id:expired,dispatch_expires_at:oldExpiry},signature(expired,oldExpiry),aid),false);checks++;
 const unsent=randomUUID();await ticket(unsent);await owner.query('UPDATE collect_ops.jobs_dispatches SET net_request_id=NULL WHERE id=$1',[unsent]);
 assert.equal(await attempt(actor,unsent,{dispatch_id:unsent,dispatch_expires_at:expires},signature(unsent,expires),aid),false);checks++;
 const race=randomUUID();await ticket(race);const runners=[];
 for(let i=0;i<12;i++)runners.push({c:await connect('postgres'),a:await admission()});
 const results=await Promise.all(runners.map(({c,a})=>attempt(c,race,{dispatch_id:race,dispatch_expires_at:expires},signature(race,expires),a)));
 assert.equal(results.filter(Boolean).length,1);checks++;
 await actor.query('BEGIN');await actor.query('SET LOCAL ROLE collect_runtime');
 await assert.rejects(actor.query('SELECT * FROM private.collect_managed_job_tickets'));await actor.query('ROLLBACK');checks++;
 await actor.query('BEGIN');await actor.query('SET LOCAL ROLE anon');
 await assert.rejects(actor.query('SELECT private.collect_managed_job_claim(NULL,NULL,NULL,NULL)'));await actor.query('ROLLBACK');checks++;
 const direct=randomUUID();await ticket(direct);const directAid=await admission();
 const adapter={prepare(sql){return {bind(i,s,p,a){return {first:async()=>({accepted:sql.includes('collect_managed_job_complete')?await complete(actor,i,directAid,p):await attempt(actor,i,JSON.parse(p),'Bearer '+a,directAid)})};}};}};
 assert.equal(await claimManagedJobDispatch(adapter,env,{dispatch_id:direct,dispatch_expires_at:expires},signature(direct,expires)),true);
 assert.equal(await claimManagedJobDispatch(adapter,env,{dispatch_id:direct,dispatch_expires_at:expires},signature(direct,expires)),false);checks++;
 const response=Response.json({status:'complete'});assert.equal(await completeManagedJobDispatch(adapter,env,direct,response),true);
 assert.equal((await owner.query('SELECT response_sha256 FROM private.collect_managed_job_tickets WHERE dispatch_id=$1',[direct])).rows[0].response_sha256,createHash('sha256').update(await response.text()).digest('hex'));
 assert.equal(await completeManagedJobDispatch(adapter,env,direct,Response.json({status:'complete'})),false);checks++;
 // The node-postgres fixture above does not reproduce postgres@3.4.7's JSONB
 // serializer. Exercise the actual Edge adapter with the pinned deployment text and runtime module
 // against the same owned database, including maintenance/native bodies and
 // altered/null/replay negatives. The Deno process receives synthetic data only.
 const cases=[],driverExpires=Math.floor(Date.now()/1000)+120;
 for(let i=0;i<4;i++){
  const dispatch=randomUUID(),a=await admission();
  const p={dispatch_id:dispatch,dispatch_expires_at:driverExpires,...(i%2?{native_sms_admission:admissionContract}: {})};
  await ticket(dispatch,p);cases.push({admission:a,payload:p});
 }
 const driver=execFileSync(process.env.DENO_BIN??'deno',['run','--no-prompt','--node-modules-dir=none','--allow-env','--allow-read','--allow-write','--allow-net',fileURLToPath(new URL('./managed-jobs-dispatch-driver.test.ts',import.meta.url))],
  {encoding:'utf8',timeout:30000,env:{...process.env,COLLECT_SYNTHETIC_DRIVER_FIXTURE:JSON.stringify({socket:f.socket,port:f.port,key,source,cases})}});
 const driverResult=JSON.parse(driver.trim());assert.equal(driverResult.checks,20);assert.equal(driverResult.provider_calls,0);checks++;
 console.log(JSON.stringify({suite:'managed-jobs-dispatch-auth',checks,signature_validation:'passed',real_edge_driver_checks:driverResult.checks,fixture:'owned socket-only PostgreSQL 17',provider_calls:0}));
}finally{for(const c of clients)await c.end().catch(()=>{});await f.close();}
