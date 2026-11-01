// Current migration-chain qualification on a fresh clone of the expressly
// owned original16 fixture. Real database identity and normal postgres owner;
// only Cron, Vault and pg_net interfaces are doubles. No provider HTTP exists.
import assert from 'node:assert/strict';
import {createHash,randomUUID} from 'node:crypto';
import {readFile,writeFile,lstat,realpath,readdir,mkdir} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import process from 'node:process';
import postgres from 'npm:postgres@3.4.7';
import {renderEmailSql,runEmailOperation} from '../email_jobs_operator.mjs';
import {renderSql as renderJobsSql,stable,validateReadiness} from '../jobs_config.mjs';
import {connection,fenceConnection,PostgresDatabase} from '../../../supabase/functions/_shared/postgres.js';
import {openApplicationWork,sqlFenceBackend} from '../../../supabase/functions/_shared/application-fence.js';
import {CURRENT_MIGRATION_COUNT,CURRENT_ADDITIONS,reviewedCurrentMigrations} from './self-hosted-current-schema.mjs';

const root=resolve(fileURLToPath(new URL('../../../',import.meta.url)));
const sha=(value:string|Uint8Array)=>createHash('sha256').update(value).digest('hex');
const runId=randomUUID(),cases:any[]=[],observations:Record<string,unknown>={};
const report:any={format:'collect.selfhost.combined-scheduler-native.v1',run_id:runId,status:'running',
 started_at:new Date().toISOString(),normal_postgres_owner:false,real_database_identity:false,
 profile_assertion_double:false,original_migrations:16,current_migrations:[],
 synthetic_interfaces:['cron','vault','pg_net'],provider_calls:0,native_extension_acceptance:false,
 hosted_acceptance:false,production_acceptance:false,tests:cases,observations};
let owner:any,admin:any,business:any,control:any,sourceManifest:any,fixtureRecord:string|undefined;
const originalFetch=globalThis.fetch;
const originalProfile=process.env.COLLECT_DEPLOYMENT_PROFILE,originalDigest=process.env.COLLECT_DEPLOYMENT_PROFILE_SHA256;
globalThis.fetch=()=>{throw Error('combined_scheduler_external_http_forbidden');};
const profile={format:'collect.deployment.v1',id:'combined-scheduler-fixture',mode:'self_hosted',environment:'qualification',
 supabase_origin:'https://supabase.combined.example.invalid',member_api_origin:'https://api.combined.example.invalid',
 admin_origin:'https://admin.combined.example.invalid',public_origin:'https://www.combined.example.invalid',
 google_callback_origin:'https://admin.combined.example.invalid'};
const profileRaw=stable(profile),profileSha=sha(profileRaw);
const env={COLLECT_DEPLOYMENT_PROFILE:profileRaw,COLLECT_DEPLOYMENT_PROFILE_SHA256:profileSha};
async function privateJson(path:string){
 const info=await lstat(path);assert.equal(await realpath(path),resolve(path));assert(info.isFile()&&!info.isSymbolicLink());
 assert.equal(info.nlink,1);assert.equal(info.mode&0o777,0o600);assert.equal(typeof process.getuid,'function');assert.equal(info.uid,process.getuid!());assert(info.size<16384);
 return JSON.parse(await readFile(path,'utf8'));
}
async function verifySource(manifest:any){
 assert.equal(manifest.format,'collect.selfhost.source.v1');assert.equal(sha(stable(manifest.files)),manifest.sha256);
 const changed:string[]=[];
 for(const item of manifest.files){
  assert.equal(typeof item.path,'string');const path=resolve(root,item.path);
  assert(path.startsWith(root+'/')&&await realpath(path)===path);
  const bytes=await readFile(path);if(bytes.length!==item.bytes||sha(bytes)!==item.sha256)changed.push(item.path);
 }
 return changed;
}
async function step(name:string,run:()=>Promise<unknown>,fatal=false){
 try{const detail=await run();cases.push({name,status:'pass',...(detail===undefined?{}:{detail})});console.log('PASS '+name);}
 catch(error){const e=error as any;cases.push({name,status:'fail',failure_class:e?.name??'Error',sqlstate:e?.code??null,
  ...(/^[a-z][a-z0-9_]{0,100}$/.test(e?.message??'')?{refusal_code:e.message}:{})});
  console.log('FAIL '+name+' ('+(e?.name??'Error')+')');if(fatal)throw error;}
}
const query=async(text:string,values:any[]=[])=>await owner.unsafe(text,values);
const value=async(text:string,values:any[]=[])=> (await query(text,values))[0].value;
const coverage=()=>value('SELECT private._collect_fence_scheduler_status()AS value');
async function rollback(run:()=>Promise<void>){
 await query('BEGIN');try{await run();}finally{await query('ROLLBACK');}
}
const email=(operation:string,options:any={})=>runEmailOperation(operation,{sql:owner,env,...options});
try{
 assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');
 const templateFile=Deno.env.get('COLLECT_INTEGRATION_FIXTURE_FILE')!,clusterFile=Deno.env.get('COLLECT_INTEGRATION_CLUSTER_FILE')!;
 assert(templateFile.endsWith('/collect-integration-fixture.private.json'));assert(clusterFile.endsWith('/collect-integration-pg.private.json'));
 const template=await privateJson(templateFile),cluster=await privateJson(clusterFile);
 assert.equal(template.format,'collect.selfhost.fixture.v1');assert.equal(template.migration_count,16);
 assert.equal(template.controller_initialized,false);assert.equal(template.synthetic,true);
 const original=new URL(template.url),clusterUrl=new URL(cluster.url);
 for(const url of [original,clusterUrl]){assert.equal(url.hostname,'127.0.0.1');assert(['55439','55445','55446'].includes(url.port));assert.equal(url.protocol,'postgres:');assert.equal(url.search,'');assert.equal(url.hash,'');assert(url.password);}
 assert.equal(original.port,clusterUrl.port);
 assert.equal(original.username,'postgres');assert.equal(clusterUrl.username,'collect_test');assert.equal(clusterUrl.pathname,'/postgres');
 const templateName=original.pathname.slice(1);assert.match(templateName,/^collect_selfhost_integration_[a-f0-9]+_test$/);
 const sourceFile=resolve(Deno.env.get('COLLECT_COMBINED_SOURCE_MANIFEST')!);assert(sourceFile.startsWith(root+'/.cache/'));
 sourceManifest=JSON.parse(await readFile(sourceFile,'utf8'));assert.deepEqual(await verifySource(sourceManifest),[]);
 report.source_sha256=sourceManifest.sha256;report.source_manifest_sha256=sha(await readFile(sourceFile));
 report.profile_sha256=profileSha;report.profile=profile;
 const database='collect_scheduler_real_'+runId.replaceAll('-','')+'_test';
 admin=postgres(cluster.url,{max:1,prepare:false,ssl:false,onnotice:()=>{}});
 assert.equal((await admin.unsafe('SELECT rolsuper FROM pg_roles WHERE rolname=current_user'))[0].rolsuper,true);
 await admin.unsafe('CREATE DATABASE "'+database+'" WITH TEMPLATE "'+templateName+'" OWNER postgres');
 original.pathname='/'+database;fixtureRecord=join(dirname(templateFile),'collect-scheduler-combined-'+runId+'.private.json');
 await writeFile(fixtureRecord,JSON.stringify({format:'collect.selfhost.scheduler-fixture.v1',url:original.href,database,run_id:runId,
  template_database:templateName,source_sha256:sourceManifest.sha256,synthetic:true,public_acceptance:false})+'\n',{flag:'wx',mode:0o600});
 report.fixture_database_sha256=sha(database);report.fixture_record_basename=fixtureRecord.split('/').at(-1);
 await admin.end({timeout:2});admin=undefined;
 owner=postgres(original.href,{max:1,prepare:false,ssl:false,onnotice:()=>{}});
 Object.assign(process.env,env);
 await step('fresh clone applies the complete reviewed current additions as normal postgres',async()=>{
  const identity=(await query("SELECT current_user,session_user,current_setting('server_version')AS version,rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user"))[0];
  assert.equal(identity.current_user,'postgres');assert.equal(identity.session_user,'postgres');
  assert.equal(identity.rolsuper,false);assert.equal(identity.rolbypassrls,false);assert(identity.version.startsWith('17.'));
  report.normal_postgres_owner=true;report.postgres_version=identity.version;
  assert.equal((await query('SELECT count(*)AS n FROM private.collect_fence_control'))[0].n,'0');
  assert.equal((await query("SELECT count(*)AS n FROM pg_extension WHERE extname IN('pg_cron','pg_net','supabase_vault')"))[0].n,'0');
  await query('ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz;ALTER TABLE auth.users ADD COLUMN is_anonymous boolean NOT NULL DEFAULT false');
  report.synthetic_auth_scaffold_delta=['email_confirmed_at timestamptz','is_anonymous boolean NOT NULL DEFAULT false'];
  const files=await reviewedCurrentMigrations(root);assert.equal(files.length,CURRENT_MIGRATION_COUNT);
  const additions=files.slice(16);assert.equal(additions.length,CURRENT_ADDITIONS.length);
  for(const item of additions){await query(item.sql);report.current_migrations.push({name:item.name,sha256:item.sha256});}
 },true);
 const source=sourceManifest.sha256,initialOperation=randomUUID();
 await step('real immutable deployment binding precedes source initialization and rejects mismatches',async()=>{
  const identityMigration=await readFile(join(root,'supabase/migrations/20261101013157_collect_deployment_identity.sql'),'utf8');
  const body=identityMigration.match(/CREATE FUNCTION private\.collect_assert_deployment\(p_sha256 text\) RETURNS boolean[\s\S]*?AS \$\$([\s\S]*?)\$\$;/)?.[1];assert(body);
  const actual=(await query("SELECT p.prosrc,p.prosecdef,pg_get_userbyid(p.proowner)AS owner FROM pg_proc p WHERE p.oid='private.collect_assert_deployment(text)'::regprocedure"))[0];
  assert.equal(actual.prosrc,body);assert.equal(actual.prosecdef,true);assert.equal(actual.owner,'postgres');
  report.profile_assertion_body_sha256=sha(body);report.identity_migration_sha256=sha(identityMigration);
  await assert.rejects(query('SELECT private.collect_assert_deployment($1::text)',[profileSha]));
  assert.equal(await value('SELECT private.collect_bind_deployment($1::uuid,$2::text,$3::text)AS value',[initialOperation,profileRaw,profileSha]),true);
  await query('SELECT private.collect_fence_initialize($1::uuid,$2::text,$3::text)',[initialOperation,source,'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3']);
  assert.equal(await value('SELECT private.collect_assert_deployment($1::text)AS value',[profileSha]),true);
  await assert.rejects(query('SELECT private.collect_assert_deployment($1::text)',['0'.repeat(64)]));
  await assert.rejects(query('SELECT collect_sms.assert_deployment_profile($1::text)',['0'.repeat(64)]));
  assert.equal(await value('SELECT private.collect_bind_deployment($1::uuid,$2::text,$3::text)AS value',[initialOperation,profileRaw,profileSha]),true);
  await assert.rejects(query('SELECT private.collect_bind_deployment($1::uuid,$2::text,$3::text)',[randomUUID(),profileRaw,profileSha]));
  await assert.rejects(query("UPDATE private.collect_deployment_identity SET profile_sha256=repeat('0',64)"));
  report.real_database_identity=true;
 },true);
 let mainRendered:any,emailRendered:any;
 await step('main jobs then email install inactive with verified combined fence coverage',async()=>{
  await query(await readFile(join(root,'supabase/jobs/test-fixture.sql'),'utf8'));
  mainRendered=await renderJobsSql();await query(mainRendered.sql);
  emailRendered=await renderEmailSql(env);await query(emailRendered.sql);
  report.scheduler_artifacts={main:{config_sha256:mainRendered.configSha,template_sha256:mainRendered.templateSha,rendered_sha256:mainRendered.sqlSha},
   email:{config_sha256:emailRendered.configSha,template_sha256:emailRendered.templateSha,rendered_sha256:emailRendered.sqlSha}};
  const state=await coverage();observations.inactive_coverage=state;
  assert.equal(state.checked,true);assert.equal(state.coverageVerified,true);assert.equal(state.blocking,false);
  assert.equal(state.namedActiveJobs,0);assert.equal(state.pendingNativeRequests,0);assert.equal(state.lifecycleUnproven,0);
  assert.equal((await email('status')).enabled,false);
  for(const role of ['anon','authenticated','service_role','collect_runtime','collect_importer','collect_sms_runtime']){
   assert.equal((await query("SELECT has_schema_privilege($1,'collect_ops','USAGE')AS allowed",[role]))[0].allowed,false);
  }
  assert.equal((await query('SELECT count(*)AS n FROM cron.job WHERE active'))[0].n,'0');
 },true);
 const driftCases=[
  ['unexpected routine',"CREATE FUNCTION collect_ops.email_unreviewed()RETURNS void LANGUAGE sql AS $$SELECT$$;REVOKE ALL ON FUNCTION collect_ops.email_unreviewed()FROM PUBLIC"],
  ['email body',"CREATE OR REPLACE FUNCTION collect_ops.pause_email()RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$BEGIN RETURN '{}'::jsonb;END$$"],
  ['email routine ACL','GRANT EXECUTE ON FUNCTION collect_ops.email_state()TO collect_runtime'],
  ['email relation ACL','GRANT SELECT ON collect_ops.email_config TO collect_runtime'],
  ['main guarded body',"CREATE OR REPLACE FUNCTION collect_ops.tick_jobs()RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$BEGIN\n -- collect_fence_sql2_write_guard_v1\n PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);\n RETURN '{}'::jsonb;END$$"],
  ['main helper body',"CREATE OR REPLACE FUNCTION collect_ops.pause_jobs()RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog AS $$BEGIN RETURN '{}'::jsonb;END$$"],
  ['main security mode','ALTER FUNCTION collect_ops.pause_jobs() SECURITY DEFINER'],
  ['main null-input contract','ALTER FUNCTION collect_ops.dispatch_jobs(text,uuid) STRICT'],
  ['main owner','GRANT CREATE ON SCHEMA collect_ops TO collect_runtime;ALTER FUNCTION collect_ops.pause_jobs() OWNER TO collect_runtime'],
  ['main helper ACL','GRANT EXECUTE ON FUNCTION collect_ops.native_jobs_epoch()TO collect_runtime'],
  ['email cron command',"UPDATE cron.job SET command='SELECT 1' WHERE jobname='collect-email-delivery-v1'"],
 ];
 for(const [name,change]of driftCases)await step('combined coverage refuses '+name+' drift',()=>rollback(async()=>{
  await query(change);const state=await coverage();observations['drift_'+name.replaceAll(' ','_')]=state;
  assert.equal(state.coverageVerified,false);assert.equal(state.blocking,true);
 }));
 const admission={contract:'collect.contribution-email.v1',source_sha256:source,approval_sha256:'b'.repeat(64),admitted_from:Math.floor(Date.now()/1000)-30,batch_limit:1};
 const readiness={format:'collect.email.readiness.v1',profile_sha256:profileSha,endpoint:profile.supabase_origin+'/functions/v1/collect-email-jobs',
  source_sha256:source,deployment_sha256:'c'.repeat(64),runtime_evidence_sha256:'d'.repeat(64),provider_evidence_sha256:'e'.repeat(64),
  token_custody_evidence_sha256:'f'.repeat(64),copy_inventory_evidence_sha256:'a'.repeat(64),quota_evidence_sha256:'b'.repeat(64),
  verified_at:new Date().toISOString(),email_admission:admission,monthly_budget:100};
 const emailEvidence=sha(JSON.stringify(readiness));
 const mainReadiness={format:'collect.jobs.readiness.v1',project_ref:'rrlduytparvsjfmegalh',endpoint:profile.supabase_origin+'/functions/v1/collect-jobs',
  deployment_sha256:'c'.repeat(64),runtime_evidence_sha256:'d'.repeat(64),token_custody_evidence_sha256:'f'.repeat(64),
  copy_inventory_evidence_sha256:'a'.repeat(64),quota_evidence_sha256:'b'.repeat(64),verified_at:new Date().toISOString(),
  momo_processing_paused:true,remaining_invocations:10000};
 const mainEvidence=sha(JSON.stringify(mainReadiness));
 await step('wrong source and independently valid sibling profile cannot admit work',async()=>{
  const before=(await query('SELECT count(*)AS n FROM net.http_request_queue'))[0].n;
  const wrongRaw=stable({...profile,id:'sibling-scheduler-fixture'}),wrongEnv={COLLECT_DEPLOYMENT_PROFILE:wrongRaw,COLLECT_DEPLOYMENT_PROFILE_SHA256:sha(wrongRaw)};
  await assert.rejects(email('status',{env:wrongEnv}));
  await assert.rejects(email('readiness',{readiness:{...readiness,source_sha256:'f'.repeat(64),
   email_admission:{...admission,source_sha256:'f'.repeat(64)},evidence_file_sha256:emailEvidence}}));
  const wrongProcessing={...mainReadiness,format:'collect.jobs.readiness.v2',mode:'receipt_processing_v1',momo_processing_paused:false,
   provider_evidence_sha256:'e'.repeat(64),remaining_provider_requests:10000,
   processing_admission:{contract:'collect.receipt-processing.v1',source_sha256:'f'.repeat(64),approval_sha256:'b'.repeat(64),model_id:'synthetic-model',batch_limit:1},
   evidence_file_sha256:mainEvidence};
  await assert.rejects(query('SELECT collect_ops.record_jobs_readiness($1::text::jsonb)',[JSON.stringify(wrongProcessing)]),/reviewed_processing_source_model_approval_and_quota_required/);
  assert.equal((await query('SELECT count(*)AS n FROM net.http_request_queue'))[0].n,before);
  assert.equal(await value('SELECT private.collect_assert_deployment($1::text)AS value',[profileSha]),true);
 });
 await step('reviewed synthetic readiness remains separate from real provider authorization',async()=>{
  validateReadiness(mainReadiness);
  await query('SELECT collect_ops.record_jobs_readiness($1::text::jsonb)',[JSON.stringify({...mainReadiness,evidence_file_sha256:mainEvidence})]);
  await email('readiness',{readiness:{...readiness,evidence_file_sha256:emailEvidence}});
  await query('INSERT INTO vault.secrets(name,decrypted_secret)VALUES($1,$2),($3,$4)',
   ['collect_job_token_v1','synthetic-main-token-'+ 'x'.repeat(40),'collect_email_job_token_v1','synthetic-email-token-'+ 'y'.repeat(40)]);
 });
 const probeMain=randomUUID(),probeEmail=randomUUID();
 await step('both lanes retain original probe identities and count queued obligations',async()=>{
  assert.equal((await value("SELECT collect_ops.dispatch_jobs('probe',$1::uuid)AS value",[probeMain])).state,'awaiting');
  assert.equal((await email('probe',{id:probeEmail})).state,'awaiting');
  assert.equal((await value("SELECT collect_ops.dispatch_jobs('probe',$1::uuid)AS value",[probeMain])).replayed,true);
  assert.equal((await email('probe',{id:probeEmail})).replayed,true);
  const state=await coverage();observations.two_awaiting=state;
  assert.equal(state.awaitingDispatches,2);assert.equal(state.pendingNativeRequests,2);assert.equal(state.lifecycleUnproven,2);assert.equal(state.blocking,true);
 });
 async function syntheticResponse(lane:'main'|'email',id:string,body:any,timeout=false){
  const table=lane==='main'?'jobs_dispatches':'email_dispatches';
  const row=(await query('SELECT net_request_id FROM collect_ops.'+table+' WHERE id=$1::uuid',[id]))[0];
  // Explicit no-worker model: consume exactly the original synthetic queue
  // row, then retain the supplied response. This performs no HTTP/send.
  assert.equal((await query('DELETE FROM net.http_request_queue WHERE id=$1::bigint RETURNING id',[row.net_request_id])).length,1);
  await query('INSERT INTO net._http_response(id,status_code,content,timed_out)VALUES($1::bigint,200,$2,$3)',
   [row.net_request_id,body===null?null:JSON.stringify(body),timeout]);
 }
 await step('exact synthetic probes admit both schedules and active jobs block fencing',async()=>{
  await syntheticResponse('main',probeMain,{dispatch_id:probeMain,maintenance:{status:'complete',examined_limit:100,provider_calls:0,purged:0},processing:{paused:true,processed:0,results:[]}});
  await syntheticResponse('email',probeEmail,{dispatch_id:probeEmail,email_admission:admission,emails:{status:'complete',processed:0,results:[]}});
  await query('SELECT collect_ops.reconcile_jobs()');await email('reconcile');
  assert.equal((await value('SELECT collect_ops.activate_jobs($1::text)AS value',[mainEvidence])).enabled,true);
  assert.equal((await email('activate',{evidence:emailEvidence})).enabled,true);
  const state=await coverage();observations.two_active=state;
  assert.equal(state.coverageVerified,true);assert.equal(state.namedActiveJobs,2);assert.equal(state.pendingNativeRequests,0);assert.equal(state.blocking,true);
 });
 await step('active email admission refuses a changed configured source without a send',()=>rollback(async()=>{
  await query("UPDATE collect_ops.email_config SET readiness=jsonb_set(jsonb_set(readiness,'{source_sha256}',to_jsonb($1::text)),'{email_admission,source_sha256}',to_jsonb($1::text))WHERE singleton",['f'.repeat(64)]);
  const state=await coverage();observations.source_drift=state;assert.equal(state.coverageVerified,false);assert.equal(state.blocking,true);
  assert.equal((await value("SELECT collect_ops.dispatch_email('scheduled',$1::uuid)AS value",[randomUUID()])).state,'source_requires_review');
  assert.equal((await query('SELECT count(*)AS n FROM net.http_request_queue'))[0].n,'0');
 }));
 await query('SELECT collect_ops.pause_jobs()');await email('pause');
 const unknownMain=randomUUID(),unknownEmail=randomUUID();
 await step('unknown outcomes from both lanes pause work and cannot be replayed as new sends',async()=>{
  await query("SELECT collect_ops.dispatch_jobs('probe',$1::uuid)",[unknownMain]);await email('probe',{id:unknownEmail});
  await syntheticResponse('main',unknownMain,null,true);
  await syntheticResponse('email',unknownEmail,{dispatch_id:unknownEmail,email_admission:admission,emails:{status:'complete',processed:1,results:[{state:'unknown',delivery_confirmed:false}]}});
  await query('SELECT collect_ops.reconcile_jobs()');await email('reconcile');
  const state=await coverage();observations.two_unknown=state;
  assert.equal(state.unconfirmedDispatches,2);assert.equal(state.lifecycleUnproven,2);assert.equal(state.pendingNativeRequests,0);assert.equal(state.namedActiveJobs,0);assert.equal(state.blocking,true);
  assert.equal((await value("SELECT collect_ops.dispatch_jobs('probe',$1::uuid)AS value",[randomUUID()])).state,'blocked_pending_reconciliation');
  assert.equal((await email('probe',{id:randomUUID()})).state,'blocked_pending_reconciliation');
  assert.equal((await value("SELECT collect_ops.dispatch_jobs('probe',$1::uuid)AS value",[unknownMain])).replayed,true);
  assert.equal((await email('probe',{id:unknownEmail})).replayed,true);
  assert.equal((await query('SELECT count(*)AS n FROM net.http_request_queue'))[0].n,'0');
 });
 await step('reviewed unknown labels and wrong-generation proofs never settle either lane',async()=>{
  await query("UPDATE collect_ops.jobs_dispatches SET created_at=clock_timestamp()-interval '6 minutes' WHERE id=$1::uuid",[unknownMain]);
  await query("UPDATE collect_ops.email_dispatches SET created_at=clock_timestamp()-interval '6 minutes' WHERE id=$1::uuid",[unknownEmail]);
  await query('SELECT collect_ops.review_unknown_jobs($1::uuid,$2::text)',[unknownMain,mainEvidence]);
  await email('review-unknown',{id:unknownEmail,evidence:emailEvidence});
  const state=await coverage();observations.two_reviewed_unknown=state;
  assert.equal(state.reviewedUnknownDispatches,2);assert.equal(state.lifecycleUnproven,2);assert.equal(state.blocking,true);
  await rollback(async()=>{
   await query('INSERT INTO private.collect_fence_scheduler_lifecycle(dispatch_id,native_epoch,evidence_sha256,review_operation_id)VALUES($1::uuid,$2,$3,$4::uuid)',
    [unknownMain,'0'.repeat(64),'a'.repeat(64),randomUUID()]);
   assert.equal((await coverage()).lifecycleUnproven,2);
  });
  assert.equal((await query('SELECT count(*)AS n FROM private.collect_fence_scheduler_lifecycle'))[0].n,'0');
 });
 business=connection(original.href);control=fenceConnection(original.href);
 const work=async(fn:(db:any)=>Promise<any>)=>{
  const lease=await (openApplicationWork as any)({backend:sqlFenceBackend(business,control),sourceSha256:source,kind:'http_collect'});
  try{return await fn(new (PostgresDatabase as any)(business,{},lease));}finally{await lease.finish();}
 };
 const admissionRaw=stable(admission);
 await step('real application journal counts orphan uncertainty without double-counting its outer dispatch',async()=>{
  await work(db=>db.prepare('INSERT INTO app.notification_email_job_dispatches(id,admission_sha256,admission_json)VALUES(?,?,?)').bind(unknownEmail,sha(admissionRaw),admissionRaw).run());
  assert.equal((await coverage()).lifecycleUnproven,2);
  const orphan=randomUUID();
  await work(db=>db.prepare('INSERT INTO app.notification_email_job_dispatches(id,admission_sha256,admission_json)VALUES(?,?,?)').bind(orphan,sha(admissionRaw),admissionRaw).run());
  assert.equal((await coverage()).lifecycleUnproven,3);
  await work(db=>db.prepare("UPDATE app.notification_email_job_dispatches SET state='unknown',updated_seconds=unixepoch()WHERE id=?").bind(orphan).run());
  const state=await coverage();observations.with_orphan_unknown=state;assert.equal(state.lifecycleUnproven,3);assert.equal(state.blocking,true);
 });
 await step('actual fence drain remains quiescing with retained unresolved scheduler obligations',async()=>{
  const operation=randomUUID();
  await query('SELECT private.collect_fence_begin_quiesce($1::uuid,1,$2::text)',[operation,source]);
  const state=await value('SELECT private.collect_fence_drain_v3($1::uuid,1,$2::text)AS value',[operation,source]);
  assert.equal(state.mode,'quiescing');assert.equal(state.localLeaseDrainComplete,false);
  assert.equal(state.schedulerStatus.blocking,true);assert.equal(state.schedulerStatus.lifecycleUnproven,3);
  report.final_scheduler_status=state.schedulerStatus;report.final_controller_mode=state.mode;
  assert.equal(await value('SELECT private.collect_assert_deployment($1::text)AS value',[profileSha]),true);
  const body=(await query("SELECT prosrc FROM pg_proc WHERE oid='private.collect_assert_deployment(text)'::regprocedure"))[0].prosrc;
  assert.equal(sha(body),report.profile_assertion_body_sha256);
 });
 const drift=await verifySource(sourceManifest);report.source_drift=drift;
 const current=await new Deno.Command('python3',{cwd:root,args:['-c','import json;from scripts.self_hosted.prepare import source_manifest;print(json.dumps(source_manifest()))'],stdout:'piped',stderr:'piped'}).output();
 assert.equal(current.success,true);const finalManifest=JSON.parse(new TextDecoder().decode(current.stdout));
 report.final_source_sha256=finalManifest.sha256;
 await step('exact recorded runtime source remained unchanged throughout qualification',async()=>{
  assert.deepEqual(drift,[]);assert.equal(finalManifest.sha256,sourceManifest.sha256);
 });
 report.status=cases.every(row=>row.status==='pass')?'pass':'fail';
}catch(error){report.status='fail';const e=error as any;report.fatal={failure_class:e?.name??'Error',sqlstate:e?.code??null};console.log('FAIL combined scheduler setup or dependent operation');}
finally{
 globalThis.fetch=originalFetch;
 if(originalProfile===undefined)delete process.env.COLLECT_DEPLOYMENT_PROFILE;else process.env.COLLECT_DEPLOYMENT_PROFILE=originalProfile;
 if(originalDigest===undefined)delete process.env.COLLECT_DEPLOYMENT_PROFILE_SHA256;else process.env.COLLECT_DEPLOYMENT_PROFILE_SHA256=originalDigest;
 for(const client of [business,control,owner,admin])if(client)await client.end({timeout:2}).catch(()=>{report.cleanup_unconfirmed=true;report.status='fail';});
 report.finished_at=new Date().toISOString();report.passed=cases.filter(row=>row.status==='pass').length;report.failed=cases.filter(row=>row.status==='fail').length;
 const configuredOutput=Deno.env.get('COLLECT_COMBINED_OUTPUT_DIR');
 const evidenceDir=configuredOutput?resolve(configuredOutput):join(root,'docs/implementation/self-hosted-20261101/combined-scheduler');
 if(configuredOutput){assert.equal(evidenceDir,configuredOutput);assert.equal(await realpath(dirname(evidenceDir)),dirname(evidenceDir));}
 await mkdir(evidenceDir,{recursive:true});
 const output=join(evidenceDir,runId+'.json');await writeFile(output,JSON.stringify(report,null,2)+'\n',{flag:'wx'});
 console.log(report.status.toUpperCase()+' combined scheduler: '+report.passed+' passed, '+report.failed+' failed; '+(report.real_database_identity?'real database identity verified':'database identity not verified')+'; synthetic provider interfaces only');
 console.log('Evidence '+output.slice(root.length+1));
}
if(report.status!=='pass')Deno.exit(1);
