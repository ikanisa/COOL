// Native PostgreSQL SQL semantics with explicit Cron/Vault/pg_net doubles.
// No extension, HTTP worker, SMTP transport or live schedule is used.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import process from 'node:process';
import postgres from 'npm:postgres@3.4.7';
import {renderEmailSql,validateEmailReadiness,runEmailOperation} from '../email_jobs_operator.mjs';
import {renderSql as renderJobsSql} from '../jobs_config.mjs';

assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');
const file=Deno.env.get('COLLECT_NOTIFICATION_FIXTURE_FILE');assert(file?.endsWith('/collect-notifications-fixture.private.json'));
const fixture=JSON.parse(await readFile(file!,'utf8')),target=new URL(fixture.url);assert.equal(target.hostname,'127.0.0.1');assert.equal(target.username,'postgres');assert.match(target.pathname,/^\/collect_[a-z0-9_]+_test$/);
const sql=postgres(fixture.url,{max:1,prepare:false,ssl:false,onnotice:()=>{}});let passed=0,profileDouble=false,originalScheduler:string|undefined;
const step=async(name:string,fn:()=>Promise<void>)=>{await fn();passed++;console.log('PASS '+name);};
const profile={format:'collect.deployment.v1',id:'email-fixture',mode:'self_hosted',environment:'qualification',supabase_origin:'https://supabase.email.example.invalid',member_api_origin:'https://api.email.example.invalid',admin_origin:'https://admin.email.example.invalid',public_origin:'https://www.email.example.invalid',google_callback_origin:'https://admin.email.example.invalid'};
const raw=JSON.stringify(Object.fromEntries(Object.keys(profile).sort().map(k=>[k,(profile as any)[k]]))),sha=(value:string)=>createHash('sha256').update(value).digest('hex');
const env={COLLECT_DEPLOYMENT_PROFILE:raw,COLLECT_DEPLOYMENT_PROFILE_SHA256:sha(raw)};
const oldProfile=process.env.COLLECT_DEPLOYMENT_PROFILE,oldDigest=process.env.COLLECT_DEPLOYMENT_PROFILE_SHA256;
try{
 Object.assign(process.env,env);
 assert.equal((await sql`SELECT count(*)AS n FROM pg_extension WHERE extname IN('pg_cron','pg_net','supabase_vault')`)[0].n,'0');
 originalScheduler=(await sql`SELECT pg_get_functiondef('private._collect_fence_scheduler_status()'::regprocedure)AS definition`)[0].definition;
 assert.equal((await sql`SELECT to_regprocedure('private.collect_assert_deployment(text)')AS present`)[0].present,null);
 // Explicit fixture-only identity double. The production owner binding is
 // exercised by the separate complete migration-chain qualification.
 await sql.unsafe("CREATE FUNCTION private.collect_assert_deployment(p text)RETURNS boolean LANGUAGE plpgsql AS $$BEGIN IF p IS DISTINCT FROM '"+sha(raw)+"'THEN RAISE EXCEPTION 'synthetic_profile_mismatch';END IF;RETURN true;END$$;COMMENT ON FUNCTION private.collect_assert_deployment(text)IS 'collect_email_scheduler_profile_assertion_test_double';REVOKE ALL ON FUNCTION private.collect_assert_deployment(text)FROM PUBLIC");profileDouble=true;
 await sql.unsafe('DROP SCHEMA IF EXISTS collect_ops CASCADE;DROP SCHEMA IF EXISTS cron CASCADE;DROP SCHEMA IF EXISTS vault CASCADE;DROP SCHEMA IF EXISTS net CASCADE');
 await sql.unsafe(await readFile(new URL('../../../supabase/jobs/test-fixture.sql',import.meta.url),'utf8'));
 await sql.unsafe((await renderJobsSql()).sql);
 const rendered=await renderEmailSql(env);await sql.unsafe(rendered.sql);
 const source=(await sql`SELECT private.collect_fence_owner_status()AS value`)[0].value.sourceSha256;
 const admission={contract:'collect.contribution-email.v1',source_sha256:source,approval_sha256:'b'.repeat(64),admitted_from:Math.floor(Date.now()/1000)-30,batch_limit:1};
 const readiness={format:'collect.email.readiness.v1',profile_sha256:sha(raw),endpoint:profile.supabase_origin+'/functions/v1/collect-email-jobs',source_sha256:source,deployment_sha256:'c'.repeat(64),runtime_evidence_sha256:'d'.repeat(64),provider_evidence_sha256:'e'.repeat(64),token_custody_evidence_sha256:'f'.repeat(64),copy_inventory_evidence_sha256:'a'.repeat(64),quota_evidence_sha256:'b'.repeat(64),verified_at:new Date().toISOString(),email_admission:admission,monthly_budget:100};
 const evidence=sha(JSON.stringify(readiness));
 const operation=(name:string,options:any={})=>runEmailOperation(name,{sql,env,...options});
 const response=async(id:string,state='accepted',override:any={})=>{
  const row=(await sql`SELECT net_request_id FROM collect_ops.email_dispatches WHERE id=${id}`)[0];
  const body={dispatch_id:id,email_admission:admission,emails:{status:'complete',processed:1,results:[{state,delivery_confirmed:false}]},...override};
  await sql`INSERT INTO net._http_response(id,status_code,content)VALUES(${row.net_request_id},200,${JSON.stringify(body)})`;
 };
 await step('inactive install exposes no scheduler or credential authority to runtime roles',async()=>{
  const state=await operation('status');assert.equal(state.enabled,false);assert.equal(state.cron_active,false);
  const coverage=(await sql`SELECT private._collect_fence_scheduler_status()AS value`)[0].value;assert.equal(coverage.checked,true);assert.equal(coverage.coverageVerified,true);assert.equal(coverage.namedActiveJobs,0);
  for(const role of ['anon','authenticated','service_role','collect_runtime','collect_sms_runtime'])assert.equal((await sql`SELECT has_schema_privilege(${role},'collect_ops','USAGE')AS allowed`)[0].allowed,false);
  assert.equal((await sql`SELECT count(*)AS n FROM net.http_request_queue`)[0].n,'0');
 });
 await step('dual-lane coverage refuses added routines, changed bodies and runtime grants',async()=>{
  const coverage=async()=>(await sql`SELECT private._collect_fence_scheduler_status()AS value`)[0].value;
  const changed=[
   "CREATE FUNCTION collect_ops.email_unreviewed()RETURNS void LANGUAGE sql AS $$SELECT$$;REVOKE ALL ON FUNCTION collect_ops.email_unreviewed()FROM PUBLIC",
   "CREATE OR REPLACE FUNCTION collect_ops.pause_email()RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$BEGIN RETURN '{}'::jsonb;END$$",
   'GRANT EXECUTE ON FUNCTION collect_ops.email_state()TO collect_runtime',
   "CREATE OR REPLACE FUNCTION collect_ops.tick_jobs()RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$BEGIN RETURN '{}'::jsonb;END$$",
  ];
  for(const change of changed){await sql.unsafe('BEGIN');try{await sql.unsafe(change);const status=await coverage();assert.equal(status.coverageVerified,false);assert.equal(status.blocking,true);}finally{await sql.unsafe('ROLLBACK');}}
  assert.equal((await coverage()).coverageVerified,true);
 });
 await step('strict readiness refuses widened batches and binds current source',async()=>{
  validateEmailReadiness(readiness,env);assert.throws(()=>validateEmailReadiness({...readiness,email_admission:{...admission,batch_limit:2}},env));
  await assert.rejects(operation('readiness',{readiness:{...readiness,source_sha256:'f'.repeat(64),evidence_file_sha256:evidence}}));
  await operation('readiness',{readiness:{...readiness,evidence_file_sha256:evidence}});
  await sql`INSERT INTO vault.secrets(name,decrypted_secret)VALUES('collect_email_job_token_v1',${'synthetic-email-token-'+ 'x'.repeat(40)})`;
 });
 let original:string;
 await step('probe retains original identity and repeated invocation never queues another HTTP request',async()=>{
  original=crypto.randomUUID();assert.equal((await operation('probe',{id:original})).state,'awaiting');assert.equal((await operation('probe',{id:original})).replayed,true);
  assert.equal((await sql`SELECT count(*)AS n FROM net.http_request_queue`)[0].n,'1');
  const body=(await sql`SELECT convert_from(body,'UTF8')::jsonb AS value FROM net.http_request_queue`)[0].value;assert.deepEqual(body,{dispatch_id:original,email_admission:admission});
  const coverage=(await sql`SELECT private._collect_fence_scheduler_status()AS value`)[0].value;assert.equal(coverage.pendingNativeRequests,1);assert.equal(coverage.awaitingDispatches,1);assert.equal(coverage.blocking,true);
  await assert.rejects(operation('activate',{evidence}));
 });
 await step('exact confirmed probe enables bounded scheduled work',async()=>{
  await response(original);await operation('reconcile');const state=await operation('activate',{evidence});assert.equal(state.enabled,true);assert.equal(state.cron_active,true);
  const first=(await sql`SELECT collect_ops.tick_email()AS value`)[0].value,second=(await sql`SELECT collect_ops.tick_email()AS value`)[0].value;
  assert.equal(first.state,'awaiting');assert.equal(second.state,'blocked_pending_reconciliation');
 });
 await step('unknown SMTP result pauses the schedule and retains its original obligation',async()=>{
  const row=(await sql`SELECT id FROM collect_ops.email_dispatches WHERE kind='scheduled'`)[0];await response(row.id,'unknown');await operation('reconcile');assert.equal((await operation('status')).enabled,false);
  const retained=(await sql`SELECT state,reason FROM collect_ops.email_dispatches WHERE id=${row.id}`)[0];assert.equal(retained.state,'unconfirmed');assert.equal(retained.reason,'email_outcome_unknown');
  assert.equal((await operation('probe',{id:crypto.randomUUID()})).state,'blocked_pending_reconciliation');
  await assert.rejects(operation('review-unknown',{id:row.id,evidence}));
  await sql`UPDATE collect_ops.email_dispatches SET created_at=clock_timestamp()-interval '6 minutes'WHERE id=${row.id}`;
  await operation('review-unknown',{id:row.id,evidence});assert.equal((await operation('status')).last_probe_id,null);assert.equal((await sql`SELECT state FROM collect_ops.email_dispatches WHERE id=${row.id}`)[0].state,'reviewed_unknown');
  const before=(await sql`SELECT private._collect_fence_scheduler_status()AS value`)[0].value;
  assert.equal(before.reviewedUnknownDispatches,1);assert(before.lifecycleUnproven>=1);
  const native=(await sql`SELECT native_epoch FROM collect_ops.email_dispatches WHERE id=${row.id}`)[0].native_epoch;
  // Explicit synthetic local-lifecycle proof for this no-worker test only.
  // It does not change the retained reviewed_unknown row or claim delivery.
  await sql`INSERT INTO private.collect_fence_scheduler_lifecycle(dispatch_id,native_epoch,evidence_sha256,review_operation_id)VALUES(${row.id},${native},${evidence},${crypto.randomUUID()})`;
  const after=(await sql`SELECT private._collect_fence_scheduler_status()AS value`)[0].value;assert.equal(after.lifecycleUnproven,before.lifecycleUnproven-1);assert.equal(after.reviewedUnknownDispatches,1);
 });
 await step('credential rotation requires a new confirmed probe before activation',async()=>{
  await operation('readiness',{readiness:{...readiness,evidence_file_sha256:evidence}});const id=crypto.randomUUID();await operation('probe',{id});await response(id);await operation('reconcile');
  await sql`UPDATE vault.secrets SET updated_at=clock_timestamp(),decrypted_secret=${'rotated-synthetic-email-token-'+ 'y'.repeat(40)}`;
  await assert.rejects(operation('activate',{evidence}));
 });
 await step('native transport recreation never pairs recycled numeric request IDs with retained dispatch',async()=>{
  const id=crypto.randomUUID();await operation('probe',{id});await sql`SELECT net.collect_test_reset_transport()`;await operation('reconcile');
  assert.equal((await sql`SELECT reason FROM collect_ops.email_dispatches WHERE id=${id}`)[0].reason,'native_transport_instance_changed');assert.equal((await operation('status')).enabled,false);
 });
 const reviewOutstanding=async()=>{
  for(const row of await sql`SELECT id FROM collect_ops.email_dispatches WHERE state='unconfirmed'`){await sql`UPDATE collect_ops.email_dispatches SET created_at=clock_timestamp()-interval '6 minutes'WHERE id=${row.id}`;await operation('review-unknown',{id:row.id,evidence});}
 };
 await step('malformed or widened HTTP replies retain uncertainty instead of aborting reconciliation',async()=>{
  await reviewOutstanding();
  for(const malformed of [null,[],42,{dispatch_id:crypto.randomUUID(),email_admission:admission,emails:null},{dispatch_id:'wrong',email_admission:admission,emails:{status:'complete',processed:0,results:[]}},'delivery-claim']){
   await operation('readiness',{readiness:{...readiness,evidence_file_sha256:evidence}});const id=crypto.randomUUID();await operation('probe',{id});
   const row=(await sql`SELECT net_request_id FROM collect_ops.email_dispatches WHERE id=${id}`)[0];
   const body=malformed==='delivery-claim'?{dispatch_id:id,email_admission:admission,emails:{status:'complete',processed:1,results:[{state:'accepted',delivery_confirmed:true}]}}:malformed;
   await sql`INSERT INTO net._http_response(id,status_code,content)VALUES(${row.net_request_id},200,${JSON.stringify(body)})`;
   await operation('reconcile');assert.equal((await sql`SELECT state FROM collect_ops.email_dispatches WHERE id=${id}`)[0].state,'unconfirmed');assert.equal((await operation('status')).enabled,false);await reviewOutstanding();
  }
 });
 await step('an enqueue failure keeps one rejected original journal without a visible queued request',async()=>{
  const before=(await sql`SELECT count(*)AS n FROM net.http_request_queue`)[0].n,id=crypto.randomUUID();
  await sql`SET collect.test.enqueue_error='true'`;
  try{assert.equal((await operation('probe',{id})).state,'rejected');}finally{await sql`SET collect.test.enqueue_error='false'`;}
  assert.equal((await sql`SELECT count(*)AS n FROM net.http_request_queue`)[0].n,before);assert.equal((await operation('probe',{id})).replayed,true);
 });
 await step('the bounded monthly budget stops dispatch before creating a request',async()=>{
  const changed={...readiness,monthly_budget:1};await operation('readiness',{readiness:{...changed,evidence_file_sha256:sha(JSON.stringify(changed))}});
  const before=(await sql`SELECT count(*)AS n FROM net.http_request_queue`)[0].n;assert.equal((await operation('probe',{id:crypto.randomUUID()})).state,'monthly_budget_exhausted');assert.equal((await sql`SELECT count(*)AS n FROM net.http_request_queue`)[0].n,before);assert.equal((await operation('status')).enabled,false);
 });
 console.log('PASS email scheduler: '+passed+' native SQL cases; all provider interfaces synthetic');
}finally{
 if(originalScheduler)await sql.unsafe(originalScheduler);
 if(profileDouble)await sql.unsafe('DROP FUNCTION private.collect_assert_deployment(text)');
 if(oldProfile===undefined)delete process.env.COLLECT_DEPLOYMENT_PROFILE;else process.env.COLLECT_DEPLOYMENT_PROFILE=oldProfile;
 if(oldDigest===undefined)delete process.env.COLLECT_DEPLOYMENT_PROFILE_SHA256;else process.env.COLLECT_DEPLOYMENT_PROFILE_SHA256=oldDigest;
 await sql.end({timeout:2});
}
