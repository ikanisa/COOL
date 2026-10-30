import {loadReviewedPlatformFixture,ORIGINAL_NINE,EXACT_CURRENT11} from './testing/curated-platform-fixture.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile,readdir,mkdtemp,writeFile,chmod,symlink,rm,realpath} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {randomUUID,createHash} from 'node:crypto';
import {loadConfig,renderSql,validateConfig,validateReadiness,readReadiness,validateConnection,previousScheduler} from './jobs_config.mjs';
import {operate} from './jobs_operator.mjs';
const readiness=()=>({format:'collect.jobs.readiness.v1',project_ref:'rrlduytparvsjfmegalh',endpoint:'https://rrlduytparvsjfmegalh.supabase.co/functions/v1/collect-jobs',deployment_sha256:'1'.repeat(64),runtime_evidence_sha256:'2'.repeat(64),token_custody_evidence_sha256:'3'.repeat(64),copy_inventory_evidence_sha256:'4'.repeat(64),quota_evidence_sha256:'5'.repeat(64),verified_at:new Date().toISOString(),momo_processing_paused:true,remaining_invocations:10000});
const withDigest=()=>({...readiness(),evidence_file_sha256:'6'.repeat(64)});
const validReply={maintenance:{status:'complete',examined_limit:100,purged:2,provider_calls:0},processing:{processed:0,results:[],paused:true}};
const processingAdmission=()=>({contract:'collect.receipt-processing.v1',source_sha256:'a'.repeat(64),approval_sha256:'b'.repeat(64),model_id:'synthetic-reviewed-model',batch_limit:1});
const processingReadiness=()=>({...readiness(),format:'collect.jobs.readiness.v2',mode:'receipt_processing_v1',momo_processing_paused:false,processing_admission:processingAdmission(),provider_evidence_sha256:'c'.repeat(64),remaining_provider_requests:10000});
const processingReply=(admission=processingAdmission(),state='completed')=>({maintenance:validReply.maintenance,processing_admission:admission,processing:{status:'complete',processed:1,results:[{state}],paused:false}});
const notificationAdmission=()=>({contract:'collect.android-push.v1',source_sha256:'a'.repeat(64),approval_sha256:'c'.repeat(64),project_id:'synthetic-collect',android_package:'app.cool.mobile',admitted_from:1793232000,batch_limit:1});
const notificationReadiness=(combined=false)=>({...readiness(),format:'collect.jobs.readiness.v3',mode:combined?'receipt_and_push_v1':'notification_delivery_v1',momo_processing_paused:!combined,
 notification_admission:notificationAdmission(),notification_provider_evidence_sha256:'d'.repeat(64),remaining_notification_attempts:10000,remaining_notification_provider_requests:20000,
 ...(combined?{processing_admission:processingAdmission(),provider_evidence_sha256:'c'.repeat(64),remaining_provider_requests:10000}:{})});
const notificationReply=(state='accepted',combined=false)=>({...validReply,...(combined?processingReply():{}),notification_admission:notificationAdmission(),notifications:{status:'complete',paused:false,processed:1,results:[{state}],recovered_unknown:0}});

test('scheduler renderer pins endpoint, transport, cadence, bounds and inactive installation',async()=>{
 const c=await loadConfig(),rendered=await renderSql(c);assert(rendered.sql.includes('vault.decrypted_secrets'));assert(rendered.sql.includes('active:=false'));assert(!rendered.sql.includes('CREATE EXTENSION'));assert(!rendered.sql.includes('vault.create_secret'));
 for(const changed of[{...c,endpoint:'https://evil.example/collect-jobs'},{...c,method:'GET'},{...c,cron:{...c.cron,install_active:true}},{...c,authorization:{...c.authorization,token:'never accept credentials'}},{...c,request:{body:{raw_sms_id:'not allowed'},timeout_ms:120000}},{...c,budgets:{...c.budgets,max_dispatches_per_utc_month:500001}}])assert.throws(()=>validateConfig(changed));
 assert.throws(()=>validateConnection('postgres://x:y@evil.example/postgres'));assert.throws(()=>validateConnection('postgres://x:y@db.rrlduytparvsjfmegalh.supabase.co/postgres?sslmode=disable'));
});
test('readiness accepts only a fresh owned 0600 evidence file without token fields',async()=>{
 const dir=await realpath(await mkdtemp(join(tmpdir(),'collect-jobs-evidence-'))),file=join(dir,'readiness.json');
 try{await writeFile(file,JSON.stringify(readiness()),{mode:0o600});assert.equal((await readReadiness(file)).momo_processing_paused,true);await chmod(file,0o604);await assert.rejects(()=>readReadiness(file));await chmod(file,0o600);const link=join(dir,'linked.json');await symlink(file,link);await assert.rejects(()=>readReadiness(link));assert.throws(()=>validateReadiness({...readiness(),token:'forbidden'}));assert.throws(()=>validateReadiness({...readiness(),verified_at:new Date(Date.now()-3601000).toISOString()}));assert.throws(()=>validateReadiness({...readiness(),momo_processing_paused:false}));}finally{await rm(dir,{recursive:true});}
});
test('processing readiness binds exact source/model/approval and independent bounded quota evidence',()=>{
 const ready=processingReadiness();assert.equal(validateReadiness(ready).mode,'receipt_processing_v1');
 for(const patch of [{momo_processing_paused:true},{remaining_provider_requests:9999},{remaining_provider_requests:'10000'},
  {mode:'maintenance_only'},{provider_evidence_sha256:''},{format:'collect.jobs.readiness.v1'},
  {processing_admission:{...ready.processing_admission,batch_limit:2}},
  {processing_admission:{...ready.processing_admission,source_sha256:'wrong'}},
  {processing_admission:{...ready.processing_admission,model_id:'unsafe\nmodel'}},
  {processing_admission:{...ready.processing_admission,credential:'not permitted'}}])assert.throws(()=>validateReadiness({...ready,...patch}));
});
test('notification and combined readiness require exact independent project/package/source/start and quota approvals',()=>{
 for(const combined of [false,true])assert.equal(validateReadiness(notificationReadiness(combined)).mode,combined?'receipt_and_push_v1':'notification_delivery_v1');
 const ready=notificationReadiness();
 for(const patch of [{momo_processing_paused:false},{remaining_notification_attempts:9999},{remaining_notification_provider_requests:19999},
  {remaining_notification_provider_requests:'20000'},{mode:'receipt_processing_v1'},{notification_provider_evidence_sha256:null},
  {notification_admission:{...ready.notification_admission,batch_limit:2}},{notification_admission:{...ready.notification_admission,admitted_from:'1793232000'}},
  {notification_admission:{...ready.notification_admission,android_package:'app.cool.mobile.gateway'}},{notification_admission:{...ready.notification_admission,private_key:'never accept credentials'}}])assert.throws(()=>validateReadiness({...ready,...patch}));
 const combined=notificationReadiness(true);delete combined.processing_admission;assert.throws(()=>validateReadiness(combined));
});
test('inactive upgrade is exact-predecessor only, retains the journal and preserves all six write guards',async()=>{
 const rendered=await renderSql(),previous=await readFile(new URL('./testing/jobs-predecessor.sql',import.meta.url),'utf8');
 assert.equal(sha(previous),previousScheduler.templateSha,'Unmodified predecessor bootstrap is the upgrade fixture');
 assert.equal((rendered.upgradeSql.match(/CREATE OR REPLACE FUNCTION collect_ops\./g)??[]).length,9);
 assert(rendered.upgradeSql.includes(previousScheduler.configSha));assert(rendered.upgradeSql.includes(previousScheduler.templateSha));
 assert(rendered.upgradeSql.includes("state IN('awaiting','unconfirmed')"));assert(rendered.upgradeSql.includes('AND NOT c.enabled AND NOT j.active'));
 assert(!/DROP (?:SCHEMA|TABLE)|TRUNCATE|DELETE FROM collect_ops\.jobs_dispatches/i.test(rendered.upgradeSql.split('CREATE OR REPLACE FUNCTION')[0]));
 for(const name of ['record_jobs_readiness','reconcile_jobs','dispatch_jobs','activate_jobs','review_unknown_jobs','tick_jobs']){
  const body=rendered.sql.split('CREATE FUNCTION collect_ops.'+name+'(')[1]?.split('END$$;')[0];
  assert.match(body??'',/BEGIN\s*-- collect_fence_sql2_write_guard_v1\s*PERFORM private\.collect_fence_assert_write\(NULL,NULL,NULL\);/);
 }
});
test('local fixture port exception is explicit, literal-loopback and exact-user/name only',()=>{
 const previous=process.env.COLLECT_CI_SYNTHETIC;
 try{
  delete process.env.COLLECT_CI_SYNTHETIC;
  assert.equal(validateConnection('postgres://collect_test:synthetic@127.0.0.1:55439/collect_jobs_test',{localTest:true}).port,'55439');
  assert.throws(()=>validateConnection('postgres://collect_test:synthetic@127.0.0.1:55441/collect_jobs_test',{localTest:true}));
  process.env.COLLECT_CI_SYNTHETIC='true';
  assert.equal(validateConnection('postgres://collect_test:synthetic@127.0.0.1:55441/collect_jobs_test',{localTest:true}).port,'55441');
  for(const candidate of ['postgres://collect_test:synthetic@localhost:55441/collect_jobs_test','postgres://other:synthetic@127.0.0.1:55441/collect_jobs_test','postgres://collect_test:synthetic@127.0.0.1:55441/collect_other_test','postgres://collect_test:synthetic@evil.example:55441/collect_jobs_test','postgres://collect_test:synthetic@127.0.0.1/collect_jobs_test','postgres://collect_test:synthetic@127.0.0.1:55441/collect_jobs_test#ignored','postgres://collect_test:synthetic@127.0.0.1:55441/collect_jobs_test?sslmode=verify-full'])assert.throws(()=>validateConnection(candidate,{localTest:true}));
  // The synthetic flag never broadens the production branch.
  assert.throws(()=>validateConnection('postgres://collect_test:synthetic@127.0.0.1:55441/collect_jobs_test'));
 }finally{if(previous===undefined)delete process.env.COLLECT_CI_SYNTHETIC;else process.env.COLLECT_CI_SYNTHETIC=previous;}
});
const sha=v=>createHash('sha256').update(v).digest('hex');
const root=resolve(import.meta.dirname,'../..');
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
 const fixture=await loadReviewedPlatformFixture(root);assert.deepEqual(fixture.names,EXACT_CURRENT11,'Scheduler qualifier deliberately applies the reviewed SQL11 prefix');return fixture;
}
const url=process.env.COLLECT_JOBS_TEST_DATABASE_URL;
test('scheduler control plane on real PostgreSQL, with explicit Cron/net/Vault interface doubles', {skip:!url},async t=>{
 validateConnection(url,{localTest:true});const full=await curatedFixture(root),rendered=await renderSql(),r=withDigest();
 assert.equal(rendered.templateSha,'85c9128bf7f4f4d91eafe24710e8ae91f9a621fc817eb8443561b06c83d1f2f0','Reviewed six first-BEGIN scheduler guards and receipt/push contracts required');
 const require=createRequire(import.meta.url),{Client}=require(process.env.COLLECT_PG_MODULE??'pg');
 const adminUrl=new URL(url);adminUrl.pathname='/postgres';const admin=new Client({connectionString:adminUrl.href});await admin.connect();try{if(!(await admin.query("SELECT 1 FROM pg_database WHERE datname='collect_jobs_test'")).rowCount)await admin.query('CREATE DATABASE collect_jobs_test');}finally{await admin.end();}
 const db=new Client({connectionString:url});await db.connect();
 const value=async(sql,args=[])=>(await db.query(sql,args)).rows[0];
 const probe=async(id=randomUUID(),reviewed=r)=>{await db.query('SELECT collect_ops.record_jobs_readiness($1::jsonb)',[reviewed]);return (await value("SELECT collect_ops.dispatch_jobs('probe',$1::uuid) AS v",[id])).v;};
 const reply=async(id,payload=validReply,status=200)=>{payload={dispatch_id:id,...payload};await db.query('INSERT INTO net._http_response(id,status_code,content) SELECT net_request_id,$2,$3 FROM collect_ops.jobs_dispatches WHERE id=$1',[id,status,JSON.stringify(payload)]);await db.query('DELETE FROM net.http_request_queue WHERE id=(SELECT net_request_id FROM collect_ops.jobs_dispatches WHERE id=$1)',[id]);return value('SELECT collect_ops.reconcile_jobs() AS v');};
 const review=async(id)=>{await db.query("UPDATE collect_ops.jobs_dispatches SET created_at=clock_timestamp()-interval '6 minutes' WHERE id=$1",[id]);await db.query('SELECT collect_ops.review_unknown_jobs($1,$2)',[id,'7'.repeat(64)]);};
 try{
  // Reset only the exact owned local fixture. Actual application/control SQL
  // remains unstubbed; only Cron/net/Vault interfaces below are doubles.
  await db.query('DROP SCHEMA IF EXISTS collect_ops,cron,net,vault,api,private,app,auth,realtime CASCADE');
  await full.apply(text=>db.query(text),{includeAuth:true});
  await db.query(await readFile(new URL('../../supabase/jobs/test-fixture.sql',import.meta.url),'utf8'));await db.query("INSERT INTO vault.secrets(name,decrypted_secret) VALUES('collect_job_token_v1','SYNTHETIC_ONLY_JOB_TOKEN_NOT_A_REAL_CREDENTIAL')");
  const fence=(await value('SELECT private.collect_fence_initialize($1,$2,$3) AS value',[randomUUID(),fixtureSource,fixtureBaseline])).value;
  assert.equal(fence.mode,'open');assert.equal(fence.sourceSha256,fixtureSource);assert.equal(fence.resourceLimits.capacityBlocked,false);
  const scope=await value("SELECT (SELECT count(*)::integer FROM pg_catalog.pg_tables WHERE schemaname='app') AS app,(SELECT count(*)::integer FROM pg_catalog.pg_tables WHERE schemaname='private') AS private,(SELECT count(*)::integer FROM pg_catalog.pg_trigger WHERE tgname='collect_fence_statement_v1' AND tgenabled='A' AND tgtype=62) AS guards,(SELECT pg_catalog.pg_get_userbyid(c.relowner)=current_user FROM pg_catalog.pg_class c WHERE c.oid='private.collect_fence_control'::regclass) AS owner_matches");
  assert.deepEqual(scope,{app:97,private:21,guards:113,owner_matches:true});
  await t.test('the exact maintenance predecessor upgrades only while inactive and settled, preserving history and Cron identity',async()=>{
   const prior=(await readFile(new URL('./testing/jobs-predecessor.sql',import.meta.url),'utf8'))
    .replaceAll('__CONFIG_SHA256__',previousScheduler.configSha).replaceAll('__TEMPLATE_SHA256__',previousScheduler.templateSha)
    .replaceAll('__PROJECT_REF__',r.project_ref).replaceAll('__ENDPOINT__',r.endpoint).replaceAll('__VAULT_NAME__','collect_job_token_v1')
    .replaceAll('__JOB_NAME__','collect-jobs-maintenance-v1').replaceAll('__SCHEDULE__','*/5 * * * *');
   await db.query(prior);const original=(await operate(db,'status',{rendered})).state;
   assert.equal(original.config_sha256,previousScheduler.configSha);
   await db.query('UPDATE cron.job SET active=true');await assert.rejects(()=>operate(db,'upgrade-inactive',{rendered}),/Deactivate/);
   await operate(db,'deactivate',{rendered});
   const oldId=randomUUID();await db.query("INSERT INTO collect_ops.jobs_dispatches(id,kind,state,created_at)VALUES($1,'probe','unconfirmed',clock_timestamp()-interval '6 minutes')",[oldId]);
   await assert.rejects(()=>operate(db,'upgrade-inactive',{rendered}),/inactive_exact_predecessor/);
   assert.equal((await value('SELECT config_sha256 FROM collect_ops.jobs_config')).config_sha256,previousScheduler.configSha);
   await operate(db,'review-unknown',{rendered,dispatchId:oldId,evidenceSha256:'7'.repeat(64)});
   const upgraded=await operate(db,'upgrade-inactive',{rendered});assert.equal(upgraded.upgraded,true);assert.equal(upgraded.state.cron_job_id,original.cron_job_id);
   assert.equal(upgraded.state.mode,'maintenance_only');assert.equal(upgraded.state.enabled,false);assert.equal(upgraded.state.last_probe_id,null);
   assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[oldId])).state,'reviewed_unknown');
   assert.equal((await operate(db,'upgrade-inactive',{rendered})).reconciled_existing,true);
   // Only this owned synthetic scheduler is cleared for the independent fresh-install cases.
   await db.query('DROP SCHEMA collect_ops CASCADE');await db.query('DELETE FROM cron.job');
  });
  let first;
  await t.test('installation is inactive and disabled ticks cause no HTTP request',async()=>{await operate(db,'install-inactive',{rendered});const s=(await value('SELECT collect_ops.jobs_state() AS v')).v;assert.equal(s.enabled,false);assert.equal(s.cron_active,false);assert.equal((await value('SELECT collect_ops.tick_jobs() AS v')).v.state,'disabled');assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,0);await assert.rejects(()=>db.query('SELECT collect_ops.activate_jobs($1)',['6'.repeat(64)]),/fresh_confirmed_probe/);});
  await t.test('an unknown inactive-install commit is reconciled without replacing a named job',async()=>{assert.equal((await operate(db,'install-inactive',{rendered})).reconciled_existing,true);await db.query("UPDATE cron.job SET command='SELECT 123;'");await assert.rejects(()=>operate(db,'install-inactive',{rendered}),/identity drift/);await db.query("UPDATE cron.job SET command='SELECT collect_ops.tick_jobs();'");assert.equal((await value('SELECT count(*)::int AS n FROM cron.job')).n,1);});
  await t.test('all scheduler PUBLIC execution and application runtime access are denied',async()=>{assert.equal((await value("SELECT count(*)::int AS n FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner)))a WHERE s.nspname='collect_ops' AND a.grantee=0")).n,0);for(const role of['anon','authenticated','collect_runtime','collect_importer']){if((await db.query('SELECT 1 FROM pg_roles WHERE rolname=$1',[role])).rowCount){assert.equal((await value("SELECT has_schema_privilege($1,'collect_ops','USAGE') AS ok",[role])).ok,false);await db.query('BEGIN');try{await db.query('SET LOCAL ROLE '+role);await assert.rejects(()=>db.query('SELECT collect_ops.jobs_state()'),/permission denied/);}finally{await db.query('ROLLBACK');}}}});
  await t.test('readiness without verified timestamp is rejected by SQL too',async()=>{const missing={...r};delete missing.verified_at;await assert.rejects(()=>db.query('SELECT collect_ops.record_jobs_readiness($1)',[missing]),/readiness_required/);});
  await t.test('SQL readiness also rejects any raw credential or unreviewed field',async()=>{await assert.rejects(()=>db.query('SELECT collect_ops.record_jobs_readiness($1)',[{...r,token:'SYNTHETIC_NEVER_STORE'}]),/strict_evidence_fields/);assert.equal((await value('SELECT readiness FROM collect_ops.jobs_config')).readiness,null);});
  await t.test('explicit probe uses exact POST/header/body and persists no credential in durable control rows',async()=>{first=await probe();assert.equal(first.state,'awaiting');const q=await value('SELECT method,url,headers,convert_from(body,\'UTF8\') AS body,timeout_milliseconds FROM net.http_request_queue WHERE id=$1',[first.net_request_id]);assert.equal(q.method,'POST');assert.equal(q.url,r.endpoint);assert.equal(q.headers.Authorization,'Bearer SYNTHETIC_ONLY_JOB_TOKEN_NOT_A_REAL_CREDENTIAL');assert.deepEqual(JSON.parse(q.body),{dispatch_id:first.dispatch_id});assert.equal(q.timeout_milliseconds,120000);const stored=JSON.stringify((await db.query('SELECT to_jsonb(d) AS v FROM collect_ops.jobs_dispatches d')).rows);assert(!stored.includes('SYNTHETIC_ONLY_JOB_TOKEN'));assert(!(await value('SELECT command FROM cron.job')).command.includes('Bearer'));});
  await t.test('commit reply loss is reconciled by the original dispatch id from another connection',async()=>{const other=new Client({connectionString:url});await other.connect();try{assert.equal((await other.query('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[first.dispatch_id])).rows[0].state,'awaiting');const repeated=(await other.query("SELECT collect_ops.dispatch_jobs('probe',$1) AS v",[first.dispatch_id])).rows[0].v;assert.equal(repeated.replayed,true);assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,1);}finally{await other.end();}});
  await t.test('unresolved work blocks another dispatch; only a qualified reply confirms and admits activation',async()=>{assert.equal((await probe()).state,'blocked_pending_reconciliation');await reply(first.dispatch_id);await db.query('SELECT collect_ops.activate_jobs($1)',['6'.repeat(64)]);assert.equal((await value('SELECT collect_ops.jobs_state() AS v')).v.enabled,true);});
  await t.test('simultaneous service connections enqueue only one dispatch for the current five-minute slot',async()=>{const clients=await Promise.all(Array.from({length:4},async()=>{const c=new Client({connectionString:url});await c.connect();return c;}));try{await Promise.all(clients.map(c=>c.query('SELECT collect_ops.tick_jobs()')));}finally{await Promise.all(clients.map(c=>c.end()));}assert.equal((await value("SELECT count(*)::int AS n FROM collect_ops.jobs_dispatches WHERE kind='scheduled'")).n,1);assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,1);});
  await t.test('loss of unlogged queue/response becomes durable ambiguity and disables the schedule',async()=>{await db.query('DELETE FROM net.http_request_queue');await db.query("UPDATE collect_ops.jobs_dispatches SET created_at=clock_timestamp()-interval '181 seconds' WHERE state='awaiting'");await db.query('SELECT collect_ops.reconcile_jobs()');const s=(await value('SELECT collect_ops.jobs_state() AS v')).v;assert.equal(s.enabled,false);assert.equal(s.cron_active,false);assert.equal(s.unconfirmed,1);const unknown=await value("SELECT id,state FROM collect_ops.jobs_dispatches WHERE state='unconfirmed'");assert.equal((await probe()).state,'blocked_pending_reconciliation');await assert.rejects(()=>db.query('SELECT collect_ops.review_unknown_jobs($1,$2)',[unknown.id,'7'.repeat(64)]),/settled_unknown/);await review(unknown.id);assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[unknown.id])).state,'reviewed_unknown');});
  await t.test('HTTP200 with unconfirmed maintenance never becomes an ACK',async()=>{const p=await probe();await reply(p.dispatch_id,{maintenance:{status:'unconfirmed'},processing:{processed:0,results:[],paused:true}});assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).state,'unconfirmed');await review(p.dispatch_id);});
  await t.test('unexpected active receipt processing is detected and quarantined, not reported as maintenance success',async()=>{const p=await probe();await reply(p.dispatch_id,{maintenance:validReply.maintenance,processing:{processed:1,results:[{raw_sms_id:'synthetic-only'}]}});assert.equal((await value('SELECT reason FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).reason,'runtime_gate_changed');await review(p.dispatch_id);});
  await t.test('invalid numeric response cannot throw away the durable ambiguity decision',async()=>{const p=await probe();await reply(p.dispatch_id,{maintenance:{...validReply.maintenance,purged:999},processing:validReply.processing});assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).state,'unconfirmed');await review(p.dispatch_id);});
  await t.test('a rejected enqueue rolls back the fake queue insertion and stores no exception body',async()=>{await db.query("SET collect.test.enqueue_error='true'");const p=await probe();await db.query("SET collect.test.enqueue_error='false'");assert.equal(p.state,'rejected');assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,0);assert.equal((await value('SELECT reason FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).reason,'enqueue_rejected');});
  await t.test('Vault version changes require a new successful probe before activation or next slot',async()=>{const p=await probe();await reply(p.dispatch_id);await db.query("UPDATE vault.secrets SET updated_at=updated_at+interval '1 second'");await assert.rejects(()=>db.query('SELECT collect_ops.activate_jobs($1)',['6'.repeat(64)]),/fresh_confirmed_probe/);const fresh=await probe();await reply(fresh.dispatch_id);await db.query('SELECT collect_ops.activate_jobs($1)',['6'.repeat(64)]);await db.query("UPDATE collect_ops.jobs_dispatches SET slot=slot-interval '5 minutes' WHERE kind='scheduled'");await db.query("UPDATE vault.secrets SET updated_at=updated_at+interval '1 second'");assert.equal((await value('SELECT collect_ops.tick_jobs() AS v')).v.state,'credential_rotation_requires_probe');assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,0);});
  await t.test('changed dependency ACL blocks dispatch before revealing a credential',async()=>{await db.query('GRANT SELECT ON net.http_request_queue TO PUBLIC');assert.equal((await probe()).state,'credential_dependency_acl_changed');await db.query('REVOKE SELECT ON net.http_request_queue FROM PUBLIC');assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,0);});
  await t.test('a missing Vault credential deactivates scheduling without an HTTP retry loop',async()=>{await db.query("UPDATE vault.secrets SET name='synthetic-temporarily-unavailable'");assert.equal((await probe()).state,'private_job_credential_unavailable');await db.query("UPDATE vault.secrets SET name='collect_job_token_v1'");assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,0);});
  await t.test('missing or contradictory dispatch UUID cannot acknowledge even a valid current-instance response',async()=>{
   for(const echoed of [undefined,null,42,randomUUID()]){const p=await probe();const payload={...validReply,dispatch_id:echoed};await reply(p.dispatch_id,payload);assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).state,'unconfirmed');assert.equal((await value('SELECT reason FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).reason,'dispatch_identity_mismatch');await review(p.dispatch_id);}
  });
  await t.test('native queue/reply/sequence reset cannot associate a recycled number with old durable work',async()=>{
   await db.query('SELECT net.collect_test_reset_transport()');const old=await probe();assert.equal(Number(old.net_request_id),1);const before=await value('SELECT native_epoch,state FROM collect_ops.jobs_dispatches WHERE id=$1',[old.dispatch_id]);
   await db.query('SELECT net.collect_test_reset_transport()');const after=(await value('SELECT collect_ops.native_jobs_epoch() AS epoch')).epoch;assert.notEqual(before.native_epoch,after);
   // A different post-reset request can reuse1 and return a perfectly valid
   // body, even echoing the old UUID. Epoch change must reject BEFORE readback.
   await db.query('INSERT INTO net._http_response(id,status_code,content)VALUES(1,200,$1)',[JSON.stringify({dispatch_id:old.dispatch_id,...validReply})]);await db.query('SELECT collect_ops.reconcile_jobs()');
   const rejected=await value('SELECT state,reason,response_sha256,http_status,native_epoch FROM collect_ops.jobs_dispatches WHERE id=$1',[old.dispatch_id]);assert.equal(rejected.state,'unconfirmed');assert.equal(rejected.reason,'native_transport_instance_changed');assert.equal(rejected.response_sha256,null);assert.equal(rejected.http_status,null);assert.equal(rejected.native_epoch,before.native_epoch);assert.equal((await probe()).state,'blocked_pending_reconciliation');await review(old.dispatch_id);
   // Numeric1 may now be used in a NEW epoch without violating durable history.
   const fresh=await probe();assert.equal(Number(fresh.net_request_id),1);assert.notEqual(fresh.dispatch_id,old.dispatch_id);await db.query('SELECT collect_ops.reconcile_jobs()');assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[fresh.dispatch_id])).state,'unconfirmed');assert.equal((await value('SELECT reason FROM collect_ops.jobs_dispatches WHERE id=$1',[fresh.dispatch_id])).reason,'dispatch_identity_mismatch');await review(fresh.dispatch_id);
   // Simulate the synthetic worker having removed that completed queue row.
   await db.query('DELETE FROM net.http_request_queue WHERE id=$1',[fresh.net_request_id]);
   await db.query('DELETE FROM net._http_response');const recovered=await probe();assert.equal(Number(recovered.net_request_id),2);await reply(recovered.dispatch_id);await db.query('SELECT collect_ops.activate_jobs($1)',['6'.repeat(64)]);assert.equal((await value('SELECT collect_ops.jobs_state() AS v')).v.enabled,true);assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[old.dispatch_id])).state,'reviewed_unknown');assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[fresh.dispatch_id])).state,'reviewed_unknown');
  });
  await t.test('a confirmed probe from an earlier native instance cannot admit activation or a new scheduled slot',async()=>{
   const p=await probe();await reply(p.dispatch_id);await db.query('SELECT collect_ops.activate_jobs($1)',['6'.repeat(64)]);await db.query('SELECT net.collect_test_reset_transport()');await assert.rejects(()=>db.query('SELECT collect_ops.activate_jobs($1)',['6'.repeat(64)]),/fresh_confirmed_probe/);assert.equal((await value('SELECT collect_ops.tick_jobs() AS v')).v.state,'native_transport_instance_requires_probe');assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,0);assert.equal((await value('SELECT collect_ops.jobs_state() AS v')).v.enabled,false);const fresh=await probe();await reply(fresh.dispatch_id);await db.query('SELECT collect_ops.activate_jobs($1)',['6'.repeat(64)]);assert.equal((await value('SELECT collect_ops.jobs_state() AS v')).v.enabled,true);
  });
  await t.test('SQL processing admission rejects malformed, stale-source and underfunded readiness before changing control state',async()=>{
   const ready={...processingReadiness(),evidence_file_sha256:'8'.repeat(64)};
   const before=(await value('SELECT readiness FROM collect_ops.jobs_config')).readiness;
   for(const changed of [{...ready,momo_processing_paused:true},{...ready,remaining_provider_requests:9999},
    {...ready,remaining_provider_requests:'10000'},{...ready,provider_evidence_sha256:null},
    {...ready,processing_admission:{...ready.processing_admission,batch_limit:2}},
    {...ready,processing_admission:{...ready.processing_admission,source_sha256:'d'.repeat(64)}},
    {...ready,processing_admission:{...ready.processing_admission,model_id:'bad\nmodel'}},
    {...ready,processing_admission:{...ready.processing_admission,unreviewed:true}}]){
    await assert.rejects(()=>db.query('SELECT collect_ops.record_jobs_readiness($1)',[changed]));
    assert.deepEqual((await value('SELECT readiness FROM collect_ops.jobs_config')).readiness,before);
   }
  });
  await t.test('reviewed periodic mode carries one immutable source/model/approval-bound contract through probe and scheduled dispatch',async()=>{
   const ready={...processingReadiness(),evidence_file_sha256:'8'.repeat(64)},p=await probe(randomUUID(),ready);
   assert.equal(p.state,'awaiting');
   const queued=await value("SELECT convert_from(body,'UTF8') AS body FROM net.http_request_queue WHERE id=$1",[p.net_request_id]);
   assert.deepEqual(JSON.parse(queued.body),{dispatch_id:p.dispatch_id,processing_admission:ready.processing_admission});
   assert.deepEqual((await value('SELECT runtime_contract FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).runtime_contract,ready.processing_admission);
   assert.equal((await value("SELECT collect_ops.dispatch_jobs('probe',$1) AS v",[p.dispatch_id])).v.replayed,true);
   assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,1);
   await reply(p.dispatch_id,{...processingReply(),diagnostics:{status:'unconfirmed'}});
   assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).state,'confirmed');
   await db.query('SELECT collect_ops.activate_jobs($1)',['8'.repeat(64)]);
   await db.query("UPDATE collect_ops.jobs_dispatches SET slot=slot-interval '1 day' WHERE kind='scheduled' AND slot>clock_timestamp()-interval '10 minutes'");
   const scheduled=(await value('SELECT collect_ops.tick_jobs() AS v')).v;assert.equal(scheduled.state,'awaiting');
   assert.deepEqual((await value('SELECT runtime_contract FROM collect_ops.jobs_dispatches WHERE id=$1',[scheduled.dispatch_id])).runtime_contract,ready.processing_admission);
   // A later operator review cannot rewrite what the original dispatch admitted.
   const next={...ready,processing_admission:{...ready.processing_admission,approval_sha256:'d'.repeat(64)},evidence_file_sha256:'9'.repeat(64)};
   await db.query('SELECT collect_ops.record_jobs_readiness($1)',[next]);await reply(scheduled.dispatch_id,processingReply());
   assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[scheduled.dispatch_id])).state,'confirmed');
   await assert.rejects(()=>db.query('SELECT collect_ops.activate_jobs($1)',['9'.repeat(64)]),/fresh_confirmed_probe/);
  });
  await t.test('active responses cannot acknowledge a changed admission, enlarged batch, leaked facts or uncertain lease outcome',async()=>{
   const ready={...processingReadiness(),evidence_file_sha256:'8'.repeat(64)};
   const replies=[validReply,processingReply({...processingAdmission(),source_sha256:'d'.repeat(64)}),
    {...processingReply(),processing:{status:'complete',paused:false,processed:2,results:[{state:'completed'},{state:'completed'}]}},
    {...processingReply(),processing:{status:'complete',paused:false,processed:1,results:[{state:'completed',raw_sms_id:'unreviewed-data'}]}},
    processingReply(processingAdmission(),'retry_on_lease_expiry'),
    {...processingReply(),processing:{status:'complete',paused:false,processed:1,results:[]}}];
   for(const payload of replies){
    const p=await probe(randomUUID(),ready);await reply(p.dispatch_id,payload);
    assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).state,'unconfirmed');
    assert.equal((await value('SELECT collect_ops.jobs_state() AS v')).v.enabled,false);
    await review(p.dispatch_id);
   }
  });
  await t.test('active numeric JSON variants cannot abort reconciliation or erase durable outcomes',async()=>{
   const ready={...processingReadiness(),evidence_file_sha256:'8'.repeat(64)},p=await probe(randomUUID(),ready);
   const body=JSON.stringify({dispatch_id:p.dispatch_id,...processingReply()}).replace('"processed":1','"processed":1.0');
   await db.query('INSERT INTO net._http_response(id,status_code,content)VALUES($1,200,$2)',[p.net_request_id,body]);
   await db.query('DELETE FROM net.http_request_queue WHERE id=$1',[p.net_request_id]);await db.query('SELECT collect_ops.reconcile_jobs()');
   assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).state,'confirmed');
  });
  await t.test('processing source and approval drift stop future periodic work pending a new qualified probe',async()=>{
   const ready={...processingReadiness(),evidence_file_sha256:'8'.repeat(64)},p=await probe(randomUUID(),ready);await reply(p.dispatch_id,processingReply());
   await db.query('SELECT collect_ops.activate_jobs($1)',['8'.repeat(64)]);
   await db.query("UPDATE collect_ops.jobs_dispatches SET slot=slot-interval '1 day' WHERE kind='scheduled' AND slot>clock_timestamp()-interval '10 minutes'");
   await db.query("UPDATE collect_ops.jobs_config SET readiness=jsonb_set(readiness,'{processing_admission,approval_sha256}',$1::jsonb)",[JSON.stringify('d'.repeat(64))]);
   assert.equal((await value('SELECT collect_ops.tick_jobs() AS v')).v.state,'processing_admission_requires_probe');
   assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,0);
   await db.query("UPDATE collect_ops.jobs_config SET readiness=jsonb_set(readiness,'{processing_admission,source_sha256}',$1::jsonb)",[JSON.stringify('e'.repeat(64))]);
   assert.equal((await value("SELECT collect_ops.dispatch_jobs('probe',$1) AS v",[randomUUID()])).v.state,'processing_source_requires_review');
   assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,0);
  });
  await t.test('SQL notification readiness rejects malformed bindings, unapproved modes and insufficient independent quota before effects',async()=>{
   const ready={...notificationReadiness(),evidence_file_sha256:'8'.repeat(64)},before=(await value('SELECT readiness FROM collect_ops.jobs_config')).readiness;
   for(const changed of [{...ready,momo_processing_paused:false},{...ready,remaining_notification_attempts:9999},
    {...ready,remaining_notification_provider_requests:19999},{...ready,mode:'unreviewed'},
    {...ready,notification_admission:{...ready.notification_admission,source_sha256:'e'.repeat(64)}},
    {...ready,notification_admission:{...ready.notification_admission,admitted_from:'1793232000'}},
    {...ready,notification_admission:{...ready.notification_admission,admitted_from:4102444800}},
    {...ready,notification_admission:{...ready.notification_admission,android_package:'unapproved.app'}},
    {...ready,notification_admission:{...ready.notification_admission,batch_limit:2}},
    {...ready,notification_admission:{...ready.notification_admission,credential:'not stored'}}]){
    await assert.rejects(()=>db.query('SELECT collect_ops.record_jobs_readiness($1)',[changed]));
    assert.deepEqual((await value('SELECT readiness FROM collect_ops.jobs_config')).readiness,before);
   }
  });
  await t.test('push-only probe, periodic wake-up and combined mode preserve exact immutable independent dispatch contracts',async()=>{
   const ready={...notificationReadiness(),evidence_file_sha256:'8'.repeat(64)},p=await probe(randomUUID(),ready);
   assert.equal(p.state,'awaiting');const body=JSON.parse((await value("SELECT convert_from(body,'UTF8') AS body FROM net.http_request_queue WHERE id=$1",[p.net_request_id])).body);
   assert.deepEqual(body,{dispatch_id:p.dispatch_id,notification_admission:notificationAdmission()});
   assert.deepEqual(await value('SELECT runtime_contract,notification_contract FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id]),{runtime_contract:null,notification_contract:notificationAdmission()});
   // A known, retained unknown delivery is terminal, not a request to resend.
   // The scheduler acknowledges only the bounded worker's recorded outcome.
   await reply(p.dispatch_id,notificationReply('unknown'));assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).state,'confirmed');
   await db.query('SELECT collect_ops.activate_jobs($1)',['8'.repeat(64)]);
   await db.query("UPDATE collect_ops.jobs_dispatches SET slot=slot-interval '1 day' WHERE kind='scheduled' AND slot>clock_timestamp()-interval '10 minutes'");
   const scheduled=(await value('SELECT collect_ops.tick_jobs() AS v')).v;assert.equal(scheduled.state,'awaiting');
   assert.deepEqual((await value('SELECT notification_contract FROM collect_ops.jobs_dispatches WHERE id=$1',[scheduled.dispatch_id])).notification_contract,notificationAdmission());
   const changed={...ready,notification_admission:{...notificationAdmission(),approval_sha256:'e'.repeat(64)},evidence_file_sha256:'9'.repeat(64)};
   await db.query('SELECT collect_ops.record_jobs_readiness($1)',[changed]);await reply(scheduled.dispatch_id,notificationReply());
   assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[scheduled.dispatch_id])).state,'confirmed');
   await assert.rejects(()=>db.query('SELECT collect_ops.activate_jobs($1)',['9'.repeat(64)]),/fresh_confirmed_probe/);
   const combined={...notificationReadiness(true),evidence_file_sha256:'8'.repeat(64)},both=await probe(randomUUID(),combined);
   const queued=JSON.parse((await value("SELECT convert_from(body,'UTF8') AS body FROM net.http_request_queue WHERE id=$1",[both.net_request_id])).body);
   assert.deepEqual(queued,{dispatch_id:both.dispatch_id,processing_admission:processingAdmission(),notification_admission:notificationAdmission()});assert(Buffer.byteLength(JSON.stringify(queued))<=2048);
   await reply(both.dispatch_id,notificationReply('accepted',true));assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[both.dispatch_id])).state,'confirmed');
  });
  await t.test('push replies cannot acknowledge changed admission, payload leakage, enlarged bounds or unresolved work',async()=>{
   const ready={...notificationReadiness(),evidence_file_sha256:'8'.repeat(64)},normal=notificationReply();
   const candidates=[validReply,{...normal,notification_admission:{...notificationAdmission(),project_id:'another-project'}},
    {...normal,notifications:{...normal.notifications,processed:2,results:[{state:'accepted'},{state:'accepted'}]}},
    {...normal,notifications:{...normal.notifications,results:[{state:'accepted',provider_message_id:'not in scheduler response'}]}},
    {...normal,notifications:{...normal.notifications,results:[{state:'sending'}]}},
    {...normal,notifications:{...normal.notifications,status:'unconfirmed'}},
    {...normal,notifications:{...normal.notifications,recovered_unknown:101}},
    {...normal,notifications:{...normal.notifications,recovered_unknown:'1'}}];
   for(const payload of candidates){const p=await probe(randomUUID(),ready);await reply(p.dispatch_id,payload);
    assert.equal((await value('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1',[p.dispatch_id])).state,'unconfirmed');
    assert.equal((await value('SELECT collect_ops.jobs_state() AS v')).v.enabled,false);await review(p.dispatch_id);
   }
   const maintenance=await probe();await reply(maintenance.dispatch_id,normal);
   assert.equal((await value('SELECT reason FROM collect_ops.jobs_dispatches WHERE id=$1',[maintenance.dispatch_id])).reason,'runtime_gate_changed');await review(maintenance.dispatch_id);
  });
  await t.test('notification approval or source drift requires a fresh qualified probe before a periodic send',async()=>{
   const ready={...notificationReadiness(),evidence_file_sha256:'8'.repeat(64)},p=await probe(randomUUID(),ready);await reply(p.dispatch_id,notificationReply());
   await db.query('SELECT collect_ops.activate_jobs($1)',['8'.repeat(64)]);
   await db.query("UPDATE collect_ops.jobs_dispatches SET slot=slot-interval '7 days' WHERE kind='scheduled' AND slot>clock_timestamp()-interval '10 minutes'");
   await db.query("UPDATE collect_ops.jobs_config SET readiness=jsonb_set(readiness,'{notification_admission,approval_sha256}',$1::jsonb)",[JSON.stringify('e'.repeat(64))]);
   assert.equal((await value('SELECT collect_ops.tick_jobs() AS v')).v.state,'processing_admission_requires_probe');
   await db.query("UPDATE collect_ops.jobs_config SET readiness=jsonb_set(readiness,'{notification_admission,source_sha256}',$1::jsonb)",[JSON.stringify('f'.repeat(64))]);
   assert.equal((await value("SELECT collect_ops.dispatch_jobs('probe',$1) AS v",[randomUUID()])).v.state,'notification_source_requires_review');
   assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,0);
  });
  await t.test('the local monthly scheduler budget fails closed without claiming organization-wide quota control',async()=>{await db.query("INSERT INTO collect_ops.jobs_dispatches(id,kind,state,reason) SELECT gen_random_uuid(),'probe','confirmed','synthetic_budget_fixture' FROM generate_series(1,10000-(SELECT count(*)::integer FROM collect_ops.jobs_dispatches WHERE created_at>=date_trunc('month',clock_timestamp() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'))");assert.equal((await probe()).state,'monthly_budget_exhausted');assert.equal((await value('SELECT count(*)::int AS n FROM net.http_request_queue')).n,0);});
  await t.test('real fence denies every scheduler mutator before effects and retains legacy unknown blockers',async()=>{
   const witness=async()=>value("SELECT (SELECT pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(d) ORDER BY d.id),'[]'::jsonb)::text,'UTF8')),'hex') FROM collect_ops.jobs_dispatches d) AS dispatches,(SELECT pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.to_jsonb(c)::text,'UTF8')),'hex') FROM collect_ops.jobs_config c WHERE singleton) AS config,(SELECT count(*)::text FROM net.http_request_queue) AS queued,(SELECT count(*)::text FROM net._http_response) AS replies");
   const before=await witness(),operation=randomUUID();
   const stopped=(await value('SELECT private.collect_fence_begin_quiesce($1,$2,$3) AS value',[operation,1,fixtureSource])).value;assert.equal(stopped.mode,'quiescing');
   for(const [sql,args]of [['SELECT collect_ops.record_jobs_readiness($1)',[r]],['SELECT collect_ops.reconcile_jobs()',[]],["SELECT collect_ops.dispatch_jobs('probe',$1)",[randomUUID()]],['SELECT collect_ops.activate_jobs($1)',['6'.repeat(64)]],['SELECT collect_ops.review_unknown_jobs($1,$2)',[randomUUID(),'7'.repeat(64)]],['SELECT collect_ops.tick_jobs()',[]]])await assert.rejects(()=>db.query(sql,args),/collect_fence_closed/);
   assert.deepEqual(await witness(),before,'Closed scheduler must preserve journal/config/native queue/reply witness');
   await db.query('BEGIN');try{await db.query('SET LOCAL ROLE collect_runtime');await db.query("SELECT set_config('collect.edge_verified','true',true)");await assert.rejects(()=>db.query('SELECT private.collect_fence_register($1,$2,$3)',[randomUUID(),fixtureSource,'jobs']),/collect_fence_closed/);}finally{await db.query('ROLLBACK');}
   await db.query('SELECT collect_ops.pause_jobs()');assert.equal((await value('SELECT collect_ops.jobs_state() AS v')).v.enabled,false);
   const drained=(await value('SELECT private.collect_fence_drain($1,$2,$3) AS value',[operation,1,fixtureSource])).value;
   assert.equal(drained.mode,'quiescing');assert.equal(drained.applicationFenceComplete,false);assert.equal(drained.schedulerStatus.coverageVerified,true);assert(drained.schedulerStatus.lifecycleUnproven>0,'Retained legacy unknown history cannot be declared settled without actual separate evidence');assert.equal(drained.wholeSystemAcceptance,false);assert.equal(drained.sb29Satisfied,false);
   assert.deepEqual(await witness(),before,'Owner pause/status/drain may not erase old uncertainty or enqueue new work');
  });
 }finally{await db.end();}
});
