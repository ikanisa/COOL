// Native correction qualification. Fresh task-owned original16 clone + exact
// current additions, actual immutable identity and a separate restricted login.
// GoTrue catalogs and provider HTTP are explicit synthetic boundaries.
import assert from 'node:assert/strict';
import {createHash,randomUUID,randomBytes,generateKeyPairSync} from 'node:crypto';
import {readFile,writeFile,lstat,realpath,readdir,mkdir} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import process from 'node:process';
import postgres from 'npm:postgres@3.4.7';
import {GatewayDatabase,gatewayConnection} from '../../../deploy/collect-sms/src/postgres.ts';
import {smsFenceBackend,smsRuntimeRole} from '../../../deploy/collect-sms/src/fence.ts';
import {createSmsGatewayHandler} from '../../../deploy/collect-sms/src/edge.ts';
import {maintenance} from '../../../deploy/collect-sms/src/index.ts';
import {flushWakeups} from '../../../deploy/collect-sms/src/fcm.ts';
import {openApplicationWork,sqlFenceBackend,guardedFetch} from '../../../supabase/functions/_shared/application-fence.js';
import {stable} from '../jobs_config.mjs';

const root=resolve(fileURLToPath(new URL('../../../',import.meta.url))),sha=(v:string|Uint8Array)=>createHash('sha256').update(v).digest('hex');
const runId=randomUUID(),tests:any[]=[],observations:any={};
const report:any={format:'collect.gateway.fence-native.v1',run_id:runId,status:'running',started_at:new Date().toISOString(),
 tests,observations,provider_calls:0,synthetic_provider_attempts:0,production_acceptance:false,physical_send_settlement:false,
 real_database_identity:false,profile_assertion_double:false,original_migrations:16,current_migrations:[]};
let owner:any,admin:any,business:any,control:any,mainControl:any,db:GatewayDatabase,backend:any;
let source:string,sourceManifest:any,ownerUrl:URL,runtimeUrl:URL,fixtureFile:string,providerCalls=0;
const originalFetch=globalThis.fetch;
let provider:(input:RequestInfo|URL,init?:RequestInit)=>Promise<Response>=async()=>{throw Error('unexpected_provider_attempt');};
globalThis.fetch=async(input,init)=>{providerCalls++;return provider(input,init);};
const profile={format:'collect.deployment.v1',id:'gateway-fence-fixture',mode:'self_hosted',environment:'qualification',
 supabase_origin:'https://supabase.gateway.example.invalid',member_api_origin:'https://api.gateway.example.invalid',
 admin_origin:'https://admin.gateway.example.invalid',public_origin:'https://www.gateway.example.invalid',google_callback_origin:'https://admin.gateway.example.invalid'};
const profileRaw=stable(profile),profileSha=sha(profileRaw),rootToken='fixture-root-'+randomBytes(32).toString('hex'),maintenanceToken='fixture-maintenance-'+randomBytes(32).toString('hex');
let settings:Record<string,string>,handler:ReturnType<typeof createSmsGatewayHandler>;
const query=(text:string,values:any[]=[])=>owner.unsafe(text,values);
const value=async(text:string,values:any[]=[])=> (await query(text,values))[0].value;
async function privateJson(path:string){const st=await lstat(path);assert.equal(await realpath(path),resolve(path));assert(st.isFile()&&!st.isSymbolicLink());assert.equal(st.mode&0o777,0o600);assert.equal(st.nlink,1);assert.equal(st.uid,process.getuid!());return JSON.parse(await readFile(path,'utf8'));}
async function step(name:string,run:()=>Promise<unknown>,fatal=false){try{const detail=await run();tests.push({name,status:'pass',...(detail===undefined?{}:{detail})});console.log('PASS '+name);}catch(error){const e=error as any;const location=String(e?.stack??'').split('\n').find(line=>line.includes(root));tests.push({name,status:'fail',error_class:e?.constructor?.name,sqlstate:e?.code??null,test_location:location,...(/^[a-z][a-z0-9_]{0,100}$/.test(e?.message??'')?{code:e.message}:{})});console.log('FAIL '+name+' ('+e?.constructor?.name+') '+(location??''));if(fatal)throw e;}}
async function rollback(run:(tx:any)=>Promise<void>){const stop=Error('rollback_probe');try{await owner.begin(async(tx:any)=>{await run(tx);throw stop;});}catch(e){if(e!==stop)throw e;}}
async function work(kind='http_collect',currentSource=source){return await (openApplicationWork as any)({backend,sourceSha256:currentSource,kind});}
function environment(w:any,extra:any={}){const env:any={...settings,...extra,DB:db.withApplicationWork(w),COLLECT_FENCE_WORK:w,ENVIRONMENT:'production',ADMIN_ORIGIN:profile.admin_origin,DISPATCH_PAUSED:'true'};env.FETCH=(input:RequestInfo|URL,init?:RequestInit)=>guardedFetch(env,'gateway_http',input,init);return env;}
async function admitted<T>(fn:(env:any,w:any)=>Promise<T>,extra:any={}){const w=await work();try{return await fn(environment(w,extra),w);}finally{await w.finish();}}
async function request(path:string,init:RequestInit={},fetcher=handler){const res=await fetcher(new Request(profile.supabase_origin+'/functions/v1/collect-sms'+path,init));return {status:res.status,body:await res.json().catch(()=>null)};}
async function post(path:string,token:string,body:any,fetcher=handler){return request(path,{method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body)},fetcher);}
const closePools=async()=>{for(const pool of [business,control,mainControl,owner,admin])try{await pool?.end({timeout:1});}catch{}};
try{
 assert.equal(Deno.env.get('COLLECT_CI_SYNTHETIC'),'true');
 const templateFile=Deno.env.get('COLLECT_INTEGRATION_FIXTURE_FILE')!,clusterFile=Deno.env.get('COLLECT_INTEGRATION_CLUSTER_FILE')!;
 assert(templateFile.endsWith('/collect-integration-fixture.private.json'));assert(clusterFile.endsWith('/collect-integration-pg.private.json'));
 const template=await privateJson(templateFile),cluster=await privateJson(clusterFile);
 assert.equal(template.migration_count,16);assert.equal(template.controller_initialized,false);assert.equal(template.synthetic,true);
 ownerUrl=new URL(template.url);const clusterUrl=new URL(cluster.url);
 for(const url of [ownerUrl,clusterUrl]){assert.equal(url.hostname,'127.0.0.1');assert(['55439','55445','55446'].includes(url.port));assert.equal(url.protocol,'postgres:');assert(url.password);assert.equal(url.search,'');assert.equal(url.hash,'');}
 assert.equal(ownerUrl.port,clusterUrl.port);assert.equal(ownerUrl.username,'postgres');assert.equal(clusterUrl.username,'collect_test');
 assert.match(ownerUrl.pathname,/^\/collect_selfhost_integration_[a-f0-9]+_test$/);assert.equal(clusterUrl.pathname,'/postgres');
 const sourceFile=resolve(Deno.env.get('COLLECT_GATEWAY_FENCE_SOURCE_MANIFEST')!);assert(sourceFile.startsWith(root+'/.cache/'));
 sourceManifest=JSON.parse(await readFile(sourceFile,'utf8'));assert.equal(sourceManifest.format,'collect.selfhost.source.v1');assert.equal(sha(stable(sourceManifest.files)),sourceManifest.sha256);
 for(const file of sourceManifest.files)assert.equal(sha(await readFile(join(root,file.path))),file.sha256,file.path);
 source=sourceManifest.sha256;report.source_sha256=source;report.profile_sha256=profileSha;report.profile=profile;
 const database='collect_sms_fence_'+runId.replaceAll('-','')+'_test',templateName=ownerUrl.pathname.slice(1);
 admin=postgres(cluster.url,{max:1,prepare:false,onnotice:()=>{}});
 await admin.unsafe('CREATE DATABASE "'+database+'" WITH TEMPLATE "'+templateName+'" OWNER postgres');ownerUrl.pathname='/'+database;
 owner=postgres(ownerUrl.href,{max:1,prepare:false,onnotice:()=>{},types:{bigint:{to:20,from:[20],serialize:String,parse:Number}}});
 fixtureFile=join(dirname(templateFile),'collect-gateway-fence-'+runId+'.private.json');
 await writeFile(fixtureFile,JSON.stringify({format:'collect.gateway.fence-fixture.v1',url:ownerUrl.href,database,source_sha256:source,synthetic:true})+'\n',{flag:'wx',mode:0o600});
 report.fixture_record_basename=fixtureFile.split('/').at(-1);report.fixture_database_sha256=sha(database);
 await step('fresh current chain installs as normal owner without changing prior migration bytes',async()=>{
  const flags=(await query('SELECT current_user AS role,rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user'))[0];assert.equal(flags.role,'postgres');assert.equal(flags.rolsuper,false);assert.equal(flags.rolbypassrls,false);
  await query('ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz;ALTER TABLE auth.users ADD COLUMN is_anonymous boolean NOT NULL DEFAULT false');
  const files=(await readdir(join(root,'supabase/migrations'))).filter(n=>/^\d{14}_[a-z0-9_]+\.sql$/.test(n)).sort();assert.equal(files.length,25);
  const lock=JSON.parse(await readFile(join(root,'deploy/self-hosted/migrations.lock.json'),'utf8'));
  for(const prior of lock.migrations.slice(0,24))assert.equal(sha(await readFile(join(root,'supabase/migrations',prior.name))),prior.sha256);
  for(const name of files.slice(16)){const raw=await readFile(join(root,'supabase/migrations',name));await query(raw.toString('utf8'));report.current_migrations.push({name,sha256:sha(raw)});}
  report.normal_owner=true;report.migration_count=files.length;
 },true);
 await step('real identity binds before source initialization and runtime has only the gateway role',async()=>{
  const operation=randomUUID();await query('SELECT private.collect_bind_deployment($1::uuid,$2,$3)',[operation,profileRaw,profileSha]);
  await query('SELECT private.collect_fence_initialize($1::uuid,$2,$3)',[operation,source,'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3']);
  const login='collect_sms_qa_'+runId.replaceAll('-',''),password=randomBytes(32).toString('hex');
  await admin.unsafe('CREATE ROLE "'+login+'" LOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD \''+password+'\';GRANT collect_sms_runtime TO "'+login+'" WITH INHERIT FALSE,SET TRUE,ADMIN FALSE');
  runtimeUrl=new URL(ownerUrl.href);runtimeUrl.username=login;runtimeUrl.password=password;
  business=gatewayConnection(runtimeUrl.href,{COLLECT_SMS_FIXTURE:'true'});control=gatewayConnection(runtimeUrl.href,{COLLECT_SMS_FIXTURE:'true'});
  db=new GatewayDatabase(business);backend=smsFenceBackend(business,control,profileSha);
  settings={COLLECT_SMS_ENABLED:'true',COLLECT_SMS_APPROVAL_SHA256:'a'.repeat(64),BUILD_SOURCE_ID:source,COLLECT_DEPLOYMENT_PROFILE:profileRaw,COLLECT_DEPLOYMENT_PROFILE_SHA256:profileSha,
   COLLECT_SMS_DATABASE_URL:runtimeUrl.href,COLLECT_SMS_FIXTURE:'true',ROOT_ADMIN_TOKEN:rootToken,OTP_HMAC_KEY:'fixture-hmac-'+randomBytes(32).toString('hex'),COLLECT_SMS_MAINTENANCE_TOKEN:maintenanceToken,
   DISPATCH_PAUSED:'true',FCM_ENABLED:'false',RETENTION_AUTO_PURGE:'false',CALLBACK_ALLOWED_HOSTS:'hooks.example.invalid',CALLBACK_ENCRYPTION_KEY:randomBytes(32).toString('hex')};
  handler=createSmsGatewayHandler(settings,{database:db,fenceBackend:backend});
  const roles=await query('SELECT p.rolname FROM pg_auth_members m JOIN pg_roles p ON p.oid=m.roleid JOIN pg_roles u ON u.oid=m.member WHERE u.rolname=$1',[login]);assert.deepEqual(roles.map((x:any)=>x.rolname),['collect_sms_runtime']);
  for(const role of ['postgres','collect_runtime'])await assert.rejects(business.begin(async(tx:any)=>{await tx.unsafe('SET LOCAL ROLE '+role);}));
  await assert.rejects(business.unsafe('SELECT * FROM app.users'));await assert.rejects(business.unsafe('SELECT * FROM private.collect_fence_control'));
  await assert.rejects(business.begin(async(tx:any)=>{await tx.unsafe('SET LOCAL ROLE collect_sms_runtime');await tx.unsafe('SELECT collect_sms.work_register($1,$2,$3,$4)',[randomUUID(),source,'http_collect',profileSha]);}));
  report.real_database_identity=true;
 },true);
 await step('unadmitted direct SQL writes and database reads fail closed',async()=>{
  await assert.rejects(db.prepare('SELECT 1 AS ok').first());
  await assert.rejects(business.begin(async(tx:any)=>{await smsRuntimeRole(tx);await tx.unsafe("INSERT INTO collect_sms.applications(application_id,name,token_hash,allowed_kinds,scopes,created_at)VALUES('unadmitted','Synthetic','unadmitted','[]','[]','2026-11-01T00:00:00.000Z')");}));
  assert.equal((await query("SELECT count(*)AS n FROM collect_sms.applications WHERE application_id='unadmitted'"))[0].n,0);
 });
 await step('each request binds actual profile and current source rather than cached identity',async()=>{
  const stale=createSmsGatewayHandler({...settings,BUILD_SOURCE_ID:'f'.repeat(64)},{database:db,fenceBackend:backend});assert.equal((await request('/health',{},stale)).status,503);
  const otherProfile=stable({...profile,id:'wrong-installation'}),otherSha=sha(otherProfile);
  const wrong=createSmsGatewayHandler({...settings,COLLECT_DEPLOYMENT_PROFILE:otherProfile,COLLECT_DEPLOYMENT_PROFILE_SHA256:otherSha},{database:db,fenceBackend:smsFenceBackend(business,control,otherSha)});
  assert.equal((await request('/health',{},wrong)).status,503);assert.equal((await request('/health')).status,200);
 });
 await step('exact ingress aliases preserve authority, browser origin and token checks',async()=>{
  for(const origin of [profile.supabase_origin,'http://supabase.gateway.example.invalid','http://api-gw:8000','http://functions:9000','http://127.0.0.1:9000'])for(const prefix of ['/functions/v1/collect-sms','/collect-sms']){
   const res=await handler(new Request(origin+prefix+'/health?probe=one'));assert.equal(res.status,200);await res.arrayBuffer();}
  for(const origin of ['http://evil.example.invalid','https://evil.example.invalid'])assert.equal((await handler(new Request(origin+'/collect-sms/health',{headers:{'x-forwarded-host':'supabase.gateway.example.invalid','x-forwarded-proto':'https'}}))).status,403);
  assert.equal((await request('/health',{headers:{Origin:'https://evil.example.invalid'}})).status,403);
  assert.equal((await request('/v1/messages',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'})).status,401);
  assert.equal((await request('/internal/maintenance',{method:'POST'})).status,404);
 });
 await step('gateway wrappers cannot inspect or close an application admission',async()=>{
  mainControl=postgres(ownerUrl.href,{max:1,prepare:false,onnotice:()=>{}});
  const main=await (openApplicationWork as any)({backend:sqlFenceBackend(owner,mainControl),sourceSha256:source,kind:'http_collect'});
  try{assert.equal((await backend.status(main.id)).found,false);await assert.rejects(backend.close(main.id,main.epoch,source,'settled','completed',0,0));await assert.rejects(backend.lease(main.id,main.epoch,source));}finally{await main.finish();}
 });
 let applicationToken:string,deviceToken:string,deviceId:string,applicationId:string;
 await step('real gateway API writes use owned admissions and retain the original protocol',async()=>{
  const a=await post('/v1/admin/applications',rootToken,{name:'Synthetic fenced application',allowed_kinds:['receipt','operation'],scopes:['messages:write','messages:read','messages:cancel']});assert.equal(a.status,201);applicationToken=a.body.application_token;applicationId=a.body.application_id;
  const d=await post('/v1/admin/devices',rootToken,{name:'Synthetic fenced device',allowed_kinds:['receipt','operation'],sim_slot:0});assert.equal(d.status,201);deviceToken=d.body.device_token;deviceId=d.body.installation_id;
  assert.equal((await post('/v1/device/registration',deviceToken,{ready:true,sim_slot:0,app_version:'synthetic',os_version:'synthetic'})).status,200);
  assert.equal((await post('/v1/admin/callbacks',rootToken,{application_id:applicationId,url:'https://hooks.example.invalid/events'})).status,201);
  const message=await request('/v1/messages',{method:'POST',headers:{Authorization:'Bearer '+applicationToken,'Content-Type':'application/json','Idempotency-Key':'original-fenced-message'},body:JSON.stringify({kind:'receipt',to:'+250788000001',text:'Synthetic fence evidence',not_after:new Date(Date.now()+3600000).toISOString()})});assert.equal(message.status,202);
  assert.equal((await query('SELECT count(*)AS n FROM private.collect_sms_fence_admissions'))[0].n>10,true);
 });
 await step('uncertain FCM is retained and never reported as phone settlement',async()=>{
  const keys=generateKeyPairSync('rsa',{modulusLength:2048});
  const extra={FCM_ENABLED:'true',FCM_PROJECT_ID:'synthetic-project',FCM_CLIENT_EMAIL:'fixture@synthetic-project.iam.gserviceaccount.com',FCM_PRIVATE_KEY:keys.privateKey.export({type:'pkcs8',format:'pem'}).toString()};
  provider=async input=>{if(String(input)==='https://oauth2.googleapis.com/token')return Response.json({access_token:'synthetic-access',expires_in:3600});if(String(input).startsWith('https://fcm.googleapis.com/'))throw Error('synthetic_unknown_fcm_ack');throw Error('unexpected_provider_attempt');};
  const w=await work();const env=environment(w,extra);let closed:any,pending:any;
  try{await env.DB.prepare("UPDATE devices SET fcm_token='synthetic-registration',fcm_pending=1,fcm_next_at=NULL WHERE installation_id=?").bind(deviceId).run();
   await flushWakeups(env);pending=await env.DB.prepare('SELECT fcm_pending FROM devices WHERE installation_id=?').bind(deviceId).first();}finally{closed=await w.finish();}
  assert.equal(closed.uncertainDispatches,1);assert.equal(closed.providerSettlement,false);
  const row=(await query('SELECT state,reason,external_dispatches,uncertain_dispatches FROM private.collect_fence_admissions WHERE admission_id=$1',[w.id]))[0];assert.equal(row.state,'settled');assert.equal(row.reason,'completed_with_unknown_obligation');assert.equal(row.uncertain_dispatches,1);observations.unknown_fcm=row;
  assert.equal(pending.fcm_pending,1);
 });
 let quiesceOperation:string,oldWork:any;
 await step('in-flight callback work blocks drain while new HTTP and maintenance admissions close',async()=>{
  let release!:()=>void,entered!:()=>void;const hold=new Promise<void>(r=>release=r),started=new Promise<void>(r=>entered=r);
  provider=async input=>{assert.equal(String(input),'https://hooks.example.invalid/events');entered();await hold;throw Error('synthetic_unknown_callback_ack');};
  oldWork=await work('jobs');const env=environment(oldWork);const running=maintenance(env);await Promise.race([started,running.then(()=>{throw Error('callback_not_started');})]);
  quiesceOperation=randomUUID();await query('SELECT private.collect_fence_begin_quiesce($1::uuid,1,$2)',[quiesceOperation,source]);
  await assert.rejects(owner.begin(async(tx:any)=>{await tx.unsafe("SET LOCAL lock_timeout='100ms'");await tx.unsafe('SELECT private.collect_fence_drain_v3($1::uuid,1,$2)',[quiesceOperation,source]);}),(error:any)=>error?.code==='55P03');
  const pending=await value('SELECT private.collect_fence_owner_status_v3()AS value');assert.equal(pending.mode,'quiescing');assert.equal(pending.localLeaseDrainComplete,false);
  assert.equal((await request('/health')).status,503);assert.equal((await request('/internal/maintenance',{method:'POST',headers:{Authorization:'Bearer '+maintenanceToken}})).status,503);
  // The original admitted work may finish/read back in quiescing; a new
  // request never acquires another identity to continue it.
  assert.equal((await env.DB.prepare('SELECT 1 AS ok').first()).ok,1);
  release();await running;
  assert.equal((await env.DB.prepare("SELECT count(*)AS n FROM webhook_deliveries WHERE state='pending'").first()).n,1);
  const closed=await oldWork.finish();assert.equal(closed.uncertainDispatches,1);assert.equal(closed.providerSettlement,false);
  const done=await value('SELECT private.collect_fence_drain_v3($1::uuid,1,$2)AS value',[quiesceOperation,source]);assert.equal(done.mode,'fenced');assert.equal(done.localLeaseDrainComplete,true);assert.equal(done.unknownObligationSettled,false);observations.quiesced=done;
  const row=(await query('SELECT state,uncertain_dispatches FROM private.collect_fence_admissions WHERE admission_id=$1',[oldWork.id]))[0];assert.equal(row.uncertain_dispatches,1);observations.unknown_callback=row;
 });
 await step('fenced work cannot write or restart maintenance and ownership history is immutable',async()=>{
  await assert.rejects(db.withApplicationWork(oldWork).prepare("UPDATE devices SET ready=0").run());
  await assert.rejects(query('DELETE FROM private.collect_sms_fence_admissions WHERE admission_id=$1',[oldWork.id]));
  assert.equal((await request('/health')).status,503);assert.equal((await request('/internal/maintenance',{method:'POST',headers:{Authorization:'Bearer '+maintenanceToken}})).status,503);
 });
 await step('actual source upgrade and new epoch reject a still-running old gateway instance',async()=>{
  const next='d'.repeat(64),upgrade=randomUUID();
  await query('SELECT private.collect_fence_upgrade_source_v3($1::uuid,$2::uuid,1,$3,$4,$5,$6,$7)',[upgrade,quiesceOperation,source,next,'1'.repeat(64),'2'.repeat(64),'3'.repeat(64)]);
  const state=await value('SELECT private.collect_fence_release_v3($1::uuid,2,$2)AS value',[randomUUID(),next]);assert.equal(state.mode,'open');assert.equal(state.epoch,3);
  assert.equal((await request('/health')).status,503);await assert.rejects(backend.lease(oldWork.id,1,source));
  const newer=createSmsGatewayHandler({...settings,BUILD_SOURCE_ID:next},{database:db,fenceBackend:backend});assert.equal((await request('/health',{},newer)).status,200);
  source=next;settings={...settings,BUILD_SOURCE_ID:next};handler=newer;report.synthetic_source_upgrade=true;
 });
 await step('lost close acknowledgement reads the original receipt without replaying close',async()=>{
  let closes=0;const uncertainBackend={...backend,async close(...args:any[]){closes++;await backend.close(...args);throw Error('synthetic_lost_close_ack');}};
  const w=await (openApplicationWork as any)({backend:uncertainBackend,sourceSha256:source,kind:'http_collect'});await db.withApplicationWork(w).prepare('SELECT 1 AS ok').first();
  const closed=await w.finish();assert.equal(closed.state,'settled');assert.equal(closes,1);assert.equal((await backend.status(w.id)).found,true);
 });
 await step('lost registration acknowledgement retains one original obligation and blocks drain',async()=>{
  let registrations=0,registeredId:string|undefined;const uncertainBackend={...backend,async register(...args:any[]){registrations++;registeredId=args[0];await backend.register(...args);throw Error('synthetic_lost_register_ack');}};
  await assert.rejects((openApplicationWork as any)({backend:uncertainBackend,sourceSha256:source,kind:'http_collect'}));assert.equal(registrations,1);
  assert.equal((await backend.status(registeredId)).state,'active');
  const operation=randomUUID();await query('SELECT private.collect_fence_begin_quiesce($1::uuid,3,$2)',[operation,source]);
  const state=await value('SELECT private.collect_fence_drain_v3($1::uuid,3,$2)AS value',[operation,source]);assert.equal(state.mode,'quiescing');assert.equal(state.localLeaseDrainComplete,false);report.final_controller_mode=state.mode;observations.unknown_register=state;
 });
 await step('runtime source remains exact and no actual provider was contacted',async()=>{
  const changed=[];for(const file of sourceManifest.files)if(sha(await readFile(join(root,file.path)))!==file.sha256)changed.push(file.path);
  report.source_drift=changed;assert.deepEqual(changed,[]);report.synthetic_provider_attempts=providerCalls;assert.equal(providerCalls,3);
 });
}catch(error){report.status='blocked';report.fatal_class=(error as any)?.constructor?.name;report.fatal_sqlstate=(error as any)?.code??null;}
finally{
 globalThis.fetch=originalFetch;await closePools();
 report.finished_at=new Date().toISOString();report.passed=tests.filter(t=>t.status==='pass').length;report.failed=tests.filter(t=>t.status==='fail').length;
 if(report.status==='running')report.status=report.failed?'fail':'pass';
 const configuredOutput=Deno.env.get('COLLECT_GATEWAY_FENCE_OUTPUT_DIR');
 const output=configuredOutput?resolve(configuredOutput):join(root,'docs/implementation/self-hosted-20261101/gateway-fence');
 if(configuredOutput){assert.equal(output,configuredOutput);assert.equal(await realpath(dirname(output)),dirname(output));}await mkdir(output,{recursive:true});
 await writeFile(join(output,runId+'.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});console.log(JSON.stringify({status:report.status,passed:report.passed,failed:report.failed,provider_calls:0,run_id:runId}));
 if(report.status!=='pass')Deno.exitCode=1;
}
