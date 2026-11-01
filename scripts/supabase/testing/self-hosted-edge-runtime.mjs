// Real pinned Supabase Edge binary + current application handlers on owned
// loopback PG. The source mount is injected; production router defaults remain
// unchanged. No Supabase cloud account, real provider or public host is used.
import {readFile,writeFile,mkdir,cp,readdir} from 'node:fs/promises';import {resolve,join} from 'node:path';
import {createHash,randomBytes} from 'node:crypto';import {spawn} from 'node:child_process';import {createWriteStream} from 'node:fs';
import {createRequire} from 'node:module';import {createServer} from 'node:net';
import assert from 'node:assert/strict';
import {canonicalProfile} from '../../../supabase/functions/_shared/deployment-profile.js';
const ROOT=resolve(import.meta.dirname,'../../..'),sha=value=>createHash('sha256').update(value).digest('hex');
const expectedBinary='7883510fe308b4b5c49ec0a8e2020ec81c5fa41133239f3969a372b1cbf107ba';
const sleep=milliseconds=>new Promise(resolve=>setTimeout(resolve,milliseconds));
const {Client}=createRequire(import.meta.url)('pg');
const address='http://127.0.0.1:9000';
async function files(root,paths,{skip=[]}={}){
 const inputs=[];
 async function walk(name){let entries;try{entries=await readdir(join(root,name),{withFileTypes:true});}catch(error){if(error.code!=='ENOTDIR')throw error;inputs.push({path:name,sha256:sha(await readFile(join(root,name)))});return;}
  for(const item of entries.sort((a,b)=>a.name.localeCompare(b.name))){assert(!item.isSymbolicLink(),'Qualification source cannot contain symbolic links');if(!skip.includes(item.name))await walk(name+'/'+item.name);}}
 for(const name of paths)await walk(name);inputs.sort((a,b)=>a.path.localeCompare(b.path));return{inputs,sha256:sha(JSON.stringify(inputs))};
}
const applicationSnapshot=()=>files(ROOT,['supabase/functions','supabase/migrations','deploy/collect-sms/src','deploy/self-hosted/migrations.lock.json','scripts/supabase/testing/self-hosted-integration.mjs'],{skip:['node_modules','.temp','tests']});
async function run(binary,descriptorFile,directory,resultFile,dependencyCache){
 assert.equal(process.env.COLLECT_CI_SYNTHETIC,'true');assert.equal(sha(await readFile(binary)),expectedBinary);
 const descriptor=JSON.parse(await readFile(descriptorFile,'utf8')),url=new URL(descriptor.runtime_url);
 assert.equal(descriptor.synthetic,true);assert.equal(descriptor.profile.environment,'qualification');assert.equal(url.hostname,'127.0.0.1');assert.equal(url.port,'55445');assert.equal(url.username,'collect_edge');
 assert.equal(sha(canonicalProfile(descriptor.profile)),descriptor.profile_sha256);
 const application=await applicationSnapshot();assert.equal(application.sha256,descriptor.source_sha256,'Exact reviewed database source must match the current application graph');
 const portProbe=createServer();await new Promise((resolve,reject)=>{portProbe.once('error',reject);portProbe.listen(9000,'127.0.0.1',resolve);});await new Promise(resolve=>portProbe.close(resolve));
 await mkdir(directory,{mode:0o700});await mkdir(join(directory,'main'),{mode:0o700});await mkdir(join(directory,'cache'),{mode:0o700});
 for(const [name,version]of [['postgres','3.4.7'],['nodemailer','10.1.7'],['hono','4.13.13']]){
  const from=join(dependencyCache,'npm/registry.npmjs.org',name),to=join(directory,'cache/npm/registry.npmjs.org',name);
  assert.equal(JSON.parse(await readFile(join(from,version,'package.json'),'utf8')).version,version);
  await mkdir(to,{recursive:true,mode:0o700});await cp(join(from,version),join(to,version),{recursive:true,errorOnExist:true,force:false});
  await cp(join(from,'registry.json'),join(to,'registry.json'),{errorOnExist:true,force:false});
 }
 const dependencyPins=await files(join(directory,'cache/npm/registry.npmjs.org'),['postgres/3.4.7','nodemailer/10.1.7','hono/4.13.13']);
 const inputs=['deploy/self-hosted/edge-main/router.ts','deploy/self-hosted/edge-main/environment.mjs','scripts/supabase/testing/self-hosted-edge-runtime.mjs',
  'supabase/functions/_shared/serve.js','supabase/functions/_shared/postgres.js','supabase/functions/_shared/runtime-env.js',
  'supabase/functions/_shared/deployment-profile.js','supabase/functions/_shared/deployment-database.js'];
 const before=Object.fromEntries(await Promise.all(inputs.map(async name=>[name,sha(await readFile(join(ROOT,name)))])));
 const env={COLLECT_DEPLOYMENT_PROFILE:canonicalProfile(descriptor.profile),COLLECT_DEPLOYMENT_PROFILE_SHA256:descriptor.profile_sha256,
  APP_ENVIRONMENT:'test',SUPABASE_URL:descriptor.profile.supabase_origin,SUPABASE_AUTH_ISSUER:descriptor.profile.supabase_origin+'/auth/v1',
  SUPABASE_INTERNAL_URL:'http://api-gw:8000',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_synthetic_native_qualification',SUPABASE_SECRET_KEY:'sb_secret_synthetic_native_qualification',
  COLLECT_DATABASE_URL:descriptor.runtime_url,BUILD_SOURCE_ID:descriptor.source_sha256,COLLECT_SMS_ENABLED:'false',
  COLLECT_JOB_TOKEN:randomBytes(40).toString('base64url'),COLLECT_EMAIL_JOB_TOKEN:randomBytes(40).toString('base64url'),
  AUTH_SMS_ENABLED:'true',AUTH_WHATSAPP_ENABLED:'false',AUTH_PHONE_DELIVERY_MODE:'opensms_hook',AUTH_PROJECT_ID:descriptor.profile.id,
  AUTH_SEND_SMS_SECRET:'v1,whsec_'+randomBytes(32).toString('base64'),OPENSMS_BASE_URL:descriptor.profile.supabase_origin+'/functions/v1/collect-sms',
  OPENSMS_APPLICATION_ID:'synthetic-otp',OPENSMS_APPLICATION_TOKEN:'app_'+randomBytes(40).toString('base64url'),OPENSMS_SENDER_LABEL:'Collect',OPENSMS_DISPATCH_TTL_SECONDS:'120'};
 await writeFile(join(directory,'runtime.private.json'),JSON.stringify(env)+'\n',{flag:'wx',mode:0o600});
 // Native main services bundle relative modules in their service graph. Keep
 // these exact production bytes adjacent, as in the fixed production mount.
 for(const name of ['router.ts','environment.mjs'])await writeFile(join(directory,'main',name),await readFile(join(ROOT,'deploy/self-hosted/edge-main',name)),{flag:'wx',mode:0o600});
 // The SQL adapter requires its existing `test` alias for loopback fixtures;
 // the signed hook requires the real profile environment. Supply the two
 // configurations explicitly without changing either production handler.
 const projectionProbe=`import {workerEnvironment} from './environment.mjs';
const syntheticProjection={FCM_PROJECT_ID:'synthetic-member-project',FCM_SERVICE_ACCOUNT_JSON:'SYNTHETIC_MEMBER_SERVICE_ACCOUNT',OPENSMS_FCM_PROJECT_ID:'synthetic-device-project',OPENSMS_FCM_CLIENT_EMAIL:'synthetic-device@example.invalid',OPENSMS_FCM_PRIVATE_KEY:'SYNTHETIC_DEVICE_PRIVATE_KEY'};
const gatewayProjection=Object.fromEntries(workerEnvironment('collect-sms',syntheticProjection));
for(const suffix of ['PROJECT_ID','CLIENT_EMAIL','PRIVATE_KEY']){
 if(gatewayProjection['FCM_'+suffix]!==syntheticProjection['OPENSMS_FCM_'+suffix]||Object.hasOwn(gatewayProjection,'OPENSMS_FCM_'+suffix))throw Error('Gateway FCM identity projection failed');
}
if(Object.hasOwn(gatewayProjection,'FCM_SERVICE_ACCOUNT_JSON'))throw Error('Member FCM credential entered the device gateway');
for(const name of ['collect-api','admin-api','collect-jobs','collect-email-jobs','send-sms-hook']){
 const other=Object.fromEntries(workerEnvironment(name,syntheticProjection));
 if(Object.keys(other).some(key=>key.startsWith('OPENSMS_FCM_'))||Object.values(other).some(value=>value.startsWith('synthetic-device')||value==='SYNTHETIC_DEVICE_PRIVATE_KEY'))throw Error('Device FCM identity entered another worker');
 if(name!=='send-sms-hook'&&(other.FCM_PROJECT_ID!==syntheticProjection.FCM_PROJECT_ID||other.FCM_SERVICE_ACCOUNT_JSON!==syntheticProjection.FCM_SERVICE_ACCOUNT_JSON))throw Error('Member FCM identity projection changed');
}
`;
 const entry="import {createRouter} from './router.ts';\n"+projectionProbe+"\nconst env=JSON.parse(await Deno.readTextFile("+JSON.stringify(join(directory,'runtime.private.json'))+"));\nconst options={sourceRoot:"+JSON.stringify(ROOT)+"};\nconst normal=createRouter(env,options),hook=createRouter({...env,APP_ENVIRONMENT:'qualification'},options);\nDeno.serve(request=>/^\\/(?:functions\\/v1\\/)?send-sms-hook(?:\\/|$)/.test(new URL(request.url).pathname)?hook(request):normal(request));\n";
 await writeFile(join(directory,'main/index.ts'),entry,{flag:'wx',mode:0o600});
 const output=createWriteStream(join(directory,'runtime.private.log'),{flags:'wx',mode:0o600});
 const child=spawn(binary,['start','--ip','127.0.0.1','--port','9000','--main-service',join(directory,'main'),'--max-parallelism','8','--user-worker-request-idle-timeout','150000'],
  {cwd:directory,env:{PATH:process.env.PATH,DENO_DIR:join(directory,'cache'),DENO_NO_UPDATE_CHECK:'1'},stdio:['ignore','pipe','pipe']});child.stdout.pipe(output,{end:false});child.stderr.pipe(output,{end:false});
 let failure;const checks=[];const ownerTarget=new URL(descriptor.owner_url);assert.equal(ownerTarget.hostname,'127.0.0.1');assert.equal(ownerTarget.port,'55445');assert.equal(ownerTarget.pathname,url.pathname);assert.equal(ownerTarget.username,'postgres');
 const owner=new Client({connectionString:descriptor.owner_url,statement_timeout:10000});let admissionStart,observedAdmissions;
 const request=async(path,method='GET',body)=>{
  const response=await fetch(address+path,{method,headers:{...(body?{'Content-Type':'application/json'}:{})},body,signal:AbortSignal.timeout(45000)});
  const bytes=await response.text();assert.ok(bytes.length<=32768);let value;try{value=JSON.parse(bytes);}catch{value=null;}
  return {status:response.status,value};
 };
 try{
  await owner.connect();assert.equal((await owner.query("SELECT current_setting('server_version_num')::int/10000 AS major")).rows[0].major,17);
  const control=(await owner.query('SELECT private.collect_fence_owner_status_v3() AS state')).rows[0].state;assert.equal(control.mode,'open');assert.equal(control.sourceSha256,descriptor.source_sha256);assert.equal(control.rawActiveAdmissions,0);
  admissionStart=(await owner.query('SELECT admission_id FROM private.collect_fence_admissions')).rows.map(row=>row.admission_id);
  let ready=false;const deadline=Date.now()+30000;while(Date.now()<deadline){if(child.exitCode!==null||child.signalCode!==null)throw Error('native_runtime_exited');try{const response=await fetch(address+'/not-a-function',{signal:AbortSignal.timeout(1000)});await response.arrayBuffer();if(response.status===404){ready=true;break;}}catch{}await sleep(100);}assert.equal(ready,true,'Native runtime must listen within30seconds');
  checks.push({case:'closed_native_router',status:'pass',http_status:404});
  checks.push({case:'native_worker_environment_keeps_member_and_device_FCM_identities_separate',status:'pass',executed_before_native_main_started:true,synthetic_values_only:true});
  for(const path of ['/functions/v1/collect-api/health','/collect-api/health']){
   const r=await request(path);assert.equal(r.status,200,path);assert.equal(r.value?.database,'available');assert.equal(r.value?.release,descriptor.source_sha256);
   checks.push({case:path,status:'pass',http_status:r.status,real_database_query:true});
  }
  const publicAdmin=await request('/functions/v1/admin-api/health');assert.equal(publicAdmin.status,404);checks.push({case:'admin_public_health_not_exposed',status:'pass',http_status:publicAdmin.status});
  const protectedAdmin=await request('/functions/v1/admin-api/api/admin/oversight/health');assert.equal(protectedAdmin.status,401);assert.equal(protectedAdmin.value?.error?.code,'unauthenticated');checks.push({case:'admin_operational_health_requires_session',status:'pass',http_status:protectedAdmin.status,authenticated_health_query_executed:false});
  for(const path of ['/collect-jobs','/collect-email-jobs']){
   const r=await request(path,'POST','{}');assert.equal(r.status,401,path);checks.push({case:path,status:'pass',http_status:r.status});
  }
  const sms=await request('/collect-sms/v1/health');assert.equal(sms.status,503);assert.equal(sms.value?.error?.code,'gateway_unavailable');checks.push({case:'disabled_gateway_stays_closed',status:'pass',http_status:sms.status});
  const hook=await request('/send-sms-hook','POST','{}');assert.equal(hook.status,401);assert.equal(hook.value?.error?.http_code,401);checks.push({case:'unsigned_hook_denied_before_effect',status:'pass',http_status:hook.status});
  const closeDeadline=Date.now()+10000;
  do{observedAdmissions=(await owner.query('SELECT kind,state,source_sha256,external_dispatches,uncertain_dispatches FROM private.collect_fence_admissions WHERE NOT(admission_id=ANY($1::uuid[])) ORDER BY kind',[admissionStart])).rows;if(observedAdmissions.length===3&&observedAdmissions.every(row=>row.state==='settled'))break;await sleep(100);}while(Date.now()<closeDeadline);
  assert.equal(observedAdmissions.length,3);assert.deepEqual(observedAdmissions.map(row=>row.kind),['http_admin','http_collect','http_collect']);
  for(const row of observedAdmissions){assert.equal(row.state,'settled');assert.equal(row.source_sha256,descriptor.source_sha256);assert.equal(row.external_dispatches,0);assert.equal(row.uncertain_dispatches,0);}
  checks.push({case:'native_http_admissions_settle_without_provider_effects',status:'pass',member_admissions:2,admin_admissions:1,other_admissions:0,external_dispatches:0,uncertain_dispatches:0});
 }catch(error){failure={code:error.code??error.name,message:error instanceof assert.AssertionError?error.message.slice(0,200):String(error.message).slice(0,160)};}
 finally{
  await owner.end();
  if(child.exitCode===null&&child.signalCode===null){child.kill('SIGTERM');for(let i=0;i<200&&child.exitCode===null&&child.signalCode===null;i++)await sleep(100);if(child.exitCode===null&&child.signalCode===null)child.kill('SIGKILL');}
  await new Promise(resolve=>output.end(resolve));
 }
 for(const name of inputs)assert.equal(sha(await readFile(join(ROOT,name))),before[name],'Qualification source changed');
 assert.equal((await applicationSnapshot()).sha256,application.sha256,'Application graph changed during qualification');
 assert.equal((await files(join(directory,'cache/npm/registry.npmjs.org'),['postgres/3.4.7','nodemailer/10.1.7','hono/4.13.13'])).sha256,dependencyPins.sha256,'Actual dependency bytes changed during qualification');
 const result={format:'collect.selfhost.native-edge.v2',status:failure?'fail':'pass',binary_sha256:expectedBinary,image:'supabase/edge-runtime:v1.77.4',
  native_deno:'2.1.4',source_sha256:descriptor.source_sha256,profile_sha256:descriptor.profile_sha256,inputs:before,qualification_entry_sha256:sha(entry),
  synthetic_auth_interface:true,real_runtime_logins:true,real_pg_major:17,checks,failure:failure??null,external_provider_calls:0,
  application_inputs:application.inputs,dependency_source_sha256:dependencyPins.sha256,dependency_inputs:dependencyPins.inputs,
  internal_transport_origin:address,protected_admin_health_authenticated:false,
  fixture_environment_alias:'test',signed_hook_environment:'qualification',
  production_mount_replaced_by_exact_test_source_path:true,docker_stack_acceptance:false,production_acceptance:false};
 await writeFile(resultFile,JSON.stringify(result,null,2)+'\n',{flag:'wx'});
 console.log(JSON.stringify({status:result.status,checks:checks.length,failure:result.failure,provider_calls:0,docker_acceptance:false}));if(failure)process.exitCode=1;
}
if(process.argv.length!==7)throw Error('binary private-runtime-descriptor fresh-private-directory safe-result dependency-cache required');
await run(...process.argv.slice(2).map(value=>resolve(value)));
