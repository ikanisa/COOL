// Source/configuration contracts only. Native SQL remains in jobs_test.mjs.
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

const sha=v=>createHash('sha256').update(v).digest('hex');
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
