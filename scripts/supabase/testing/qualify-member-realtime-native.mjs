// Local-only preparer. No hosted connection, reset, DROP, retry or test fence bypass.
import {readFile,readdir,realpath,stat,mkdtemp,chmod,open} from 'node:fs/promises';
import {resolve,dirname,join,isAbsolute} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {tmpdir} from 'node:os';
import {createRequire} from 'node:module';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';

const CALLER='scripts/supabase/testing/qualify-member-realtime-native.mjs';
const SQL11_ROLE='supabase/migrations/20261023002500_collect_admin_recent_email_source_upgrade.sql';
const ROOT_SQL11_SHA256='02c93209f546880032cf38382c61e78a3de0b0073dd2cb88699319afc6f0f185';
const SQL12_ROLE='supabase/migrations/20261023072038_collect_admin_initial_email_proof_ack.sql';
const ROOT_SQL12_SHA256='2c31440ae10176e7e9e5f0befefce8e1ca44e06149d3cc4471119920b3abf6df';
const HELPER='scripts/supabase/testing/curated-platform-fixture.mjs';
const RUNTIME='scripts/supabase/emergency-fence/native-runtime.ts';
const REALTIME='scripts/supabase/testing/member-realtime-native.mjs';
const ADMIN_ENV='COLLECT_MEMBER_REALTIME_ADMIN_DATABASE_URL';
export const REALTIME_FAILURE_STAGES=Object.freeze(["preflight", "connect", "fixture_identity", "initial_owner_control", "initial_disabled_publish", "actor_member_setup", "actor_admin_setup", "actor_admin_mfa_projection", "actor_admin_email_proof", "collection_memberships", "first_activation", "no_partition_publish", "partition_setup", "opaque_payload", "topic_authorization", "client_mutation_denial", "policy_drift", "retention_fresh_mfa", "retention_recent_email", "retained_session_attribution", "active_membership_revocation", "member_inventory_denial", "ledger_unchanged", "cleanup"]);
export const REALTIME_FAILURE_CODES=Object.freeze(["REALTIME_NEW_LOCAL_FIXTURE_REQUIRED", "REALTIME_LOCAL_DRIVER_UNAVAILABLE", "REALTIME_LOCAL_CONNECTION_UNAVAILABLE", "REALTIME_LOCAL_CONNECTION_LOST", "REALTIME_LOCAL_CLEANUP_UNCONFIRMED", "REALTIME_ASSERTION_FAILED", "REALTIME_SUBSET_UNCONFIRMED", "SQLSTATE_23503", "SQLSTATE_23505", "SQLSTATE_23502", "SQLSTATE_23514", "SQLSTATE_42501", "SQLSTATE_55000", "SQLSTATE_57014", "SQLSTATE_55P03", "SQLSTATE_40001", "SQLSTATE_40P01", "SQLSTATE_08000", "SQLSTATE_08001", "SQLSTATE_08003", "SQLSTATE_08004", "SQLSTATE_08006", "SQLSTATE_08007", "SQLSTATE_08P01", "SQLSTATE_53300", "SQLSTATE_53400", "SQLSTATE_57P01", "SQLSTATE_57P02", "SQLSTATE_57P03", "SQLSTATE_42P01", "SQLSTATE_42703", "SQLSTATE_42883", "SQLSTATE_42601", "SQLSTATE_P0001"]);
export function projectRealtimeFailure(kind,bytes){
 if(kind!=='realtime'||bytes.length>65536)return null;
 let value;try{value=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{return null;}
 if(!value||Object.keys(value).sort().join(',')!=='code,fixture,stage,status'||value.status!=='UNCONFIRMED'||value.fixture!=='new_unique_loopback_realtime_interface_only'||!REALTIME_FAILURE_STAGES.includes(value.stage)||!REALTIME_FAILURE_CODES.includes(value.code))return null;
 return {status:'UNCONFIRMED',fixture:value.fixture,stage:value.stage,code:value.code};
}

const SOURCE='a'.repeat(64);
const BASELINE='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const EXPECTED=Object.freeze({
 "scripts/supabase/testing/curated-platform-fixture.mjs": "4968f8bde5f3fbe1da28d9b84c0618f9499bee546075e354b8763ae2177169ce",
 "scripts/supabase/testing/member-realtime-fixture-plan.json": "6156561ea1b893b56afcf54d64934ca042dbb3251426ea3d27e532272bf65d6f",
 "scripts/supabase/testing/member-realtime-interface.sql": "074e380664493eea86a56d3f3042460bbb33352bc4f46483fd19d559446b0e1b",
 "scripts/supabase/testing/member-realtime-metadata.sql": "ed97cdf0838100502344d2d54563992df6170c6a64e95843c037aaec4cd703e3",
 "scripts/supabase/testing/member-realtime-native.mjs": "ffdf6b47a062474485d39b4dd06c88ee2be962e6b1b1c51fa932a2d7e87f7809",
 "scripts/supabase/emergency-fence/native-runtime.ts": "a9ebf26603ca2610ab399735f548fd24d7d296a4348018c69724d4ad3ac3771a",
 "supabase/tests/sql/00_local_auth_fixture.sql": "b935e17f44219f018cf1a864505d1895d71903885ca6c61c039d7ab6596117ea",
 "supabase/functions/deno.json": "2c3962bd2c4fac761d154c43b0b48a55622142e02a2be70237361c02032f43e4",
 "supabase/functions/deno.lock": "070d1f79d59faebba520e3d14c1b10f4d73a84584eafa8c34f767c013c628b9b",
 "scripts/supabase/package.json": "9e8be4e3558c58379bdde1710125fbdc66b374d4c4638958119d03fc6f7a1b8f",
 "scripts/supabase/package-lock.json": "aeb77c97700bd9a3c67c8ac339a841513d09a33507b30b163a5cf1ce22643599",
 "supabase/functions/_shared/application-fence.js": "7abbf94ff699f6942619b6a0409a5623a6fa7322b41cdabe72e32d99689184de",
 "supabase/functions/_shared/postgres.js": "ac92b5bc010596f324d06cf3474119626133d2c3adb3e1627261c0deaa1c1e9d",
 "supabase/functions/_shared/workspace-smtp-email.js": "05833369873f15ef71805a351f9868787d97e74a6df7a5a21a303b8feef24eef",
 "supabase/functions/_shared/domain/email_delivery.js": "55e7f5cdfac654b50f02d120737ee82563da2d154294ebf95252b7e8cd534e36",
 "supabase/functions/_shared/domain/core.js": "18ce95c133a4895d13475338089fb00c9ba4c9283ee72c7d4d6f88ae8ea8723e",
 "supabase/migrations/20261020134444_collect_curated_platform_baseline.sql": "0d943d17ddd92e809856831427cfc81b1264301dabdb867e1c90322d46b5a6f0",
 "supabase/migrations/20261020135932_collect_runtime_role_and_function_paths.sql": "59e4b13ddc81abeb39fb59b005c71a29f947023502727c118c9eb00b479e08a1",
 "supabase/migrations/20261020174856_collect_retention_retry_authority.sql": "d3ba38736fa46b70a0bb66520deffa56fd6f7317deb7c0144f8e06d791f8808c",
 "supabase/migrations/20261020184012_collect_admin_invitation_attempts.sql": "c6dc8aa6ac5130162c6e69904aae7221edde6dcb0c898af2cf9e10dba444b665",
 "supabase/migrations/20261020190301_collect_rls_helper_permissions.sql": "dccb79af17182164dc6afe0b8339b70bd35a80fc4a1c1fa7df1a09408310a645",
 "supabase/migrations/20261020191847_collect_privacy_email_reauthentication.sql": "d6f002a6e904226a88e666c70937a142f06aa5a7e29874c6edb564d59c5fcab4",
 "supabase/migrations/20261020193752_collect_admin_invitation_access_notice_v2.sql": "b48a381169e777160a37396539248325e40b331a61db986622514724517f8467",
 "supabase/migrations/20261020195249_collect_admin_invitation_public_id_preservation.sql": "78f8c454a9825b0d9e25622b0659245d9568e7b95f637d3e20160a945b4e0850",
 "supabase/migrations/20261022195747_collect_application_mutation_fence.sql": "714abf2d24ce3d42a36525d18627362b02ff38c30810e988d365b5796d840497",
 "supabase/migrations/20261022200028_collect_private_member_realtime.sql": "ebfd0389e6ba3aa5fe1595f854b25c69b9b31a0500f202b8e0643209ab0ef6e4",
 [SQL11_ROLE]:ROOT_SQL11_SHA256,
 [SQL12_ROLE]:ROOT_SQL12_SHA256
});
export const REVIEWED_INPUT_ROLES=Object.freeze(Object.keys(EXPECTED));
const MIGRATIONS=REVIEWED_INPUT_ROLES.filter(role=>role.startsWith('supabase/migrations/')).map(role=>role.slice('supabase/migrations/'.length)).sort();
const SETUP_MS=150000,RUNNER_MS=150000,OUTPUT_LIMIT=65536;
const sha=value=>createHash('sha256').update(value).digest('hex');
function fail(code){const error=new Error('Local native qualification unconfirmed');error.qualificationCode=code;throw error;}
const need=(value,code)=>{if(!value)fail(code);};
const hex=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);

// Exported refusal boundaries have no source override, driver injection or success
// bypass. Importing this module never loads pg, spawns a child or connects.
export function validateInvocation({argv,env,nodeVersion=process.versions.node}){
 need(Array.isArray(argv)&&argv.length===2,'NO_ARGUMENTS_ALLOWED');
 need(/^24\./.test(nodeVersion),'NODE_24_REQUIRED');
 need(env.COLLECT_CI_SYNTHETIC==='true','EXPLICIT_SYNTHETIC_CI_REQUIRED');
 const raw=env[ADMIN_ENV];
 need(typeof raw==='string'&&raw.length<=8192&&/^postgres(?:ql)?:\/\/collect_test:[^\s/?#@]+@127\.0\.0\.1:[1-9][0-9]{0,4}\/postgres$/.test(raw),'EXACT_LOCAL_ADMIN_URL_REQUIRED');
 let target;try{target=new URL(raw);}catch{fail('EXACT_LOCAL_ADMIN_URL_REQUIRED');}
 let password;try{password=decodeURIComponent(target.password);}catch{fail('EXACT_LOCAL_ADMIN_URL_REQUIRED');}
 need(target.hostname==='127.0.0.1'&&target.username==='collect_test'&&password.length>0&&!/[\x00-\x1f\x7f]/.test(password)&&Number(target.port)>0&&Number(target.port)<=65535&&target.pathname==='/postgres'&&!target.search&&!target.hash,'EXACT_LOCAL_ADMIN_URL_REQUIRED');
 const deno=env.COLLECT_DENO;
 need(typeof deno==='string'&&isAbsolute(deno)&&resolve(deno)===deno&&!/[\x00-\x1f\x7f]/.test(deno),'EXPLICIT_PHYSICAL_DENO_REQUIRED');
 const module=env.COLLECT_PG_MODULE??'pg';
 need(module==='pg'||typeof module==='string'&&isAbsolute(module)&&resolve(module)===module&&!/[\x00-\x1f\x7f]/.test(module),'PINNED_PG_MODULE_REQUIRED');
 const cache=env.DENO_DIR;
 need(cache===undefined||typeof cache==='string'&&isAbsolute(cache)&&resolve(cache)===cache&&!/[\x00-\x1f\x7f]/.test(cache),'PHYSICAL_DENO_CACHE_REQUIRED');
 return {target,deno,module,cache};
}

export async function verifyLocalConnection(client,{target,database,parity=async()=>{}}){
 // The production caller installs the idle-error poison listener before this
 // connect. A bad identity never reaches a CREATE/schema/initialize callback.
 await parity();await client.connect();await parity();
 const result=await client.query(`SELECT current_database()::text AS database,
 pg_catalog.host(pg_catalog.inet_server_addr()) AS address,
 pg_catalog.inet_server_port() AS port,
 current_setting('server_version_num') AS version,
 current_setting('default_transaction_isolation') AS default_isolation,
 current_setting('transaction_isolation') AS isolation,
 current_user::text AS current_role,session_user::text AS session_role,
 (SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname=current_user) AS superuser,
 (SELECT rolbypassrls FROM pg_catalog.pg_roles WHERE rolname=current_user) AS bypass,
 pg_catalog.pg_get_userbyid((SELECT datdba FROM pg_catalog.pg_database WHERE datname=current_database()))::text AS owner`);
 const row=result.rows?.[0];
 need(result.rows?.length===1&&row?.database===database&&row.address==='127.0.0.1'&&row.port===Number(target.port)&&/^17\d{4}$/.test(row.version)&&row.default_isolation==='read committed'&&row.isolation==='read committed'&&row.current_role==='collect_test'&&row.session_role==='collect_test'&&row.superuser===true&&row.bypass===true&&(database==='postgres'||row.owner==='collect_test'),'EXACT_LOCAL_PG17_OWNER_IDENTITY_REQUIRED');
}

export function cleanChildEnvironment(env,{pgEntry,fixtureVariable,fixtureUrl,cache}){
 const clean={};
 for(const key of ['PATH','HOME','TMPDIR','TMP','TEMP','SystemRoot','LANG','LC_ALL'])if(typeof env[key]==='string')clean[key]=env[key];
 if(cache!==undefined)clean.DENO_DIR=cache;
 if(pgEntry!==undefined)clean.COLLECT_PG_MODULE=pgEntry;
 clean.COLLECT_CI_SYNTHETIC='true';
 if(fixtureVariable!==undefined)clean[fixtureVariable]=fixtureUrl;
 return clean;
}

export function validateChildReceipt(kind,receipt,{binding,closureSha256}){
 need(receipt&&receipt.status==='PASS'&&Number.isSafeInteger(receipt.checks)&&receipt.checks>0&&receipt.checks<=20000,'BOUNDED_CHILD_PASS_REQUIRED');
 need(receipt.provider_calls===0,'ZERO_PROVIDER_CALLS_REQUIRED');
 if(kind==='runtime'){
  need(hex(ROOT_SQL11_SHA256)&&receipt.fixture==='new_unique_loopback_actual_runtime_sql11'&&receipt.migration_count===11&&receipt.sql11_sha256===ROOT_SQL11_SHA256&&receipt.source_sha256===SOURCE&&receipt.source_closure_sha256===closureSha256&&receipt.sql10_sha256===binding.hosted_sql_sha256&&receipt.synthetic_sql10_sha256===binding.synthetic_sql_sha256&&receipt.sql9_sha256===EXPECTED['supabase/migrations/20261022195747_collect_application_mutation_fence.sql'],'EXACT_RUNTIME_SOURCE_RECEIPT_REQUIRED');
  need(receipt.actual_smtp_timeout===true&&receipt.synthetic_raw_send_calls===1&&receipt.external_fetch_calls===0&&receipt.app_tables_unchanged_outside_exact_owned_rows===97&&hex(receipt.original_unknown_receipt_sha256)&&receipt.original_unknown_receipt_preserved===true&&receipt.durable_settled_unknown===1&&receipt.retained_unknown_obligations===1&&receipt.held_work_prevented_drain===true&&receipt.final_mode==='fenced'&&receipt.applicationFenceComplete===true&&receipt.preserve_database===true&&receipt.automatic_replay===false,'EXACT_PENDING_RUNTIME_WITNESS_REQUIRED');
  for(const key of ['hosted_capacity_accepted','providerSettlement','wholeSystemAcceptance','managedInternalWritesFenced','humanMessagesFenced','atomicRecoverySnapshot','sb29Satisfied'])need(receipt[key]===false,'RUNTIME_ACCEPTANCE_SCOPE_REQUIRED');
  return {status:'PASS',fixture:receipt.fixture,checks:receipt.checks,migration_count:11,sql11_sha256:ROOT_SQL11_SHA256,source_closure_sha256:closureSha256,sql10_sha256:binding.hosted_sql_sha256,synthetic_sql10_sha256:binding.synthetic_sql_sha256,actual_smtp_timeout:true,synthetic_raw_send_calls:1,provider_calls:0,external_fetch_calls:0,app_tables_unchanged_outside_exact_owned_rows:97,original_unknown_receipt_sha256:receipt.original_unknown_receipt_sha256,original_unknown_receipt_preserved:true,durable_settled_unknown:1,retained_unknown_obligations:1,held_work_prevented_drain:true,final_mode:'fenced',applicationFenceComplete:true,sb29Satisfied:false,wholeSystemAcceptance:false};
 }
 need(kind==='realtime'&&receipt.fixture==='new_unique_loopback_realtime_interface_only'&&receipt.subset===true&&receipt.full_matrix_qualified===false&&receipt.managed_project_writes===0&&receipt.hosted_delivery_accepted===false&&receipt.whole_system_acceptance===false&&receipt.sb22Satisfied===false,'EXACT_REALTIME_SUBSET_SCOPE_REQUIRED');
 // RT deliberately seeds local actors/memberships/messages. Do not copy the
 // runtime witness's 97-table invariant onto this different fixture.
 return {status:'PASS',fixture:receipt.fixture,checks:receipt.checks,subset:true,full_matrix_qualified:false,provider_calls:0,managed_project_writes:0,hosted_delivery_accepted:false,whole_system_acceptance:false,sb22Satisfied:false};
}

async function bounded(promise,ms,onTimeout,code){
 let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>{onTimeout();const error=new Error('Local observation unavailable');error.qualificationCode=code;reject(error);},ms);})]);}finally{clearTimeout(timer);}
}

async function main(){
 process.umask(0o077);
 let output,root,stage='preflight',currentCase=null,poisoned=false,stopChild=null,abortSetup=null;
 const cases=[],clients=new Set(),endings=new WeakMap();
 const healthy=()=>need(!poisoned,'LOCAL_DATABASE_CONNECTION_UNCONFIRMED');
 const poison=()=>{poisoned=true;stopChild?.();abortSetup?.();};
 function beginClose(client){
  if(!endings.has(client)){
   const ending=Promise.resolve().then(()=>client.end());endings.set(client,ending);
   // Preserve rejection custody even when a setup timeout initiates shutdown
   // before the normal finally block observes this exact original promise.
   void ending.catch(()=>{});
  }
  return endings.get(client);
 }
 function terminateSocket(client){try{client.connection?.stream?.destroy();}catch{}}
 async function save(name,value){
  const file=await open(join(output,name),'wx',0o600);
  try{await file.writeFile(JSON.stringify(value,null,2)+'\n');await file.sync();}finally{await file.close();}
  const directory=await open(output,'r');try{await directory.sync();}finally{await directory.close();}
 }
 async function sourceFile(role){
  const path=resolve(root,role);let bytes,physical;
  try{physical=await realpath(path);bytes=await readFile(path);}catch{fail('SOURCE_INPUT_UNAVAILABLE');}
  need(path.startsWith(root+'/')&&physical===path,'PHYSICAL_SOURCE_REQUIRED');
  need(bytes.length>0&&bytes.length<=16000000,'BOUNDED_SOURCE_REQUIRED');
  return {role,path,bytes:bytes.length,sha256:sha(bytes)};
 }
 async function parity(inputs){
  healthy();
  const names=(await readdir(join(root,'supabase/migrations'))).filter(name=>/^\d{14}_.*\.sql$/.test(name)).sort();
  need(MIGRATIONS.length===12&&JSON.stringify(names)===JSON.stringify(MIGRATIONS),'EXACT_CURRENT12_MIGRATIONS_REQUIRED');
  for(const input of inputs){const current=await sourceFile(input.role);need(current.sha256===input.sha256&&current.bytes===input.bytes,'QUALIFIED_SOURCE_CHANGED');}
 }
 async function endClient(client,inputs){
  if(!clients.has(client))return;
  try{await bounded(beginClose(client),5000,()=>{terminateSocket(client);poison();},'LOCAL_CONNECTION_CLOSE_UNCONFIRMED');}
  catch{terminateSocket(client);poison();fail('LOCAL_CONNECTION_CLOSE_UNCONFIRMED');}
  clients.delete(client);
  if(inputs)await parity(inputs);
 }
 // Child bytes never reach logs/files. A single bounded JSON document must
 // satisfy a typed receipt; stderr (including driver warnings) is hash-only.
 async function child(executable,args,env,{budget=RUNNER_MS,limit=OUTPUT_LIMIT}={}){
  healthy();let handle;
  try{handle=spawn(executable,args,{cwd:root??tmpdir(),env,shell:false,stdio:['ignore','pipe','pipe']});}catch{fail('CHILD_DISPATCH_UNCONFIRMED');}
  let timeout=false,overflow=false,spawnError=false,closed=false,term=false;
  let killTimer,reapTimer;let stdoutBytes=0,stderrBytes=0;const buffers=[];
  const stdoutHash=createHash('sha256'),stderrHash=createHash('sha256');
  const terminate=()=>{
   if(closed||term)return;term=true;
   try{handle.kill('SIGTERM');}catch{}
   killTimer=setTimeout(()=>{try{handle.kill('SIGKILL');}catch{}},5000);
  };
  stopChild=terminate;
  const timer=setTimeout(()=>{timeout=true;terminate();},budget);
  const observe=(isOut,chunk)=>{
   if(isOut){stdoutBytes+=chunk.length;stdoutHash.update(chunk);if(stdoutBytes<=limit)buffers.push(chunk);}
   else{stderrBytes+=chunk.length;stderrHash.update(chunk);}
   if(stdoutBytes>limit||stderrBytes>limit){overflow=true;terminate();}
  };
  handle.stdout.on('data',chunk=>observe(true,chunk));handle.stderr.on('data',chunk=>observe(false,chunk));
  handle.stdout.on('error',()=>{spawnError=true;terminate();});
  handle.stderr.on('error',()=>{spawnError=true;terminate();});
  const outcome=await new Promise(resolveDone=>{
   const finish=value=>{if(closed)return;closed=true;resolveDone(value);};
   handle.on('error',()=>{spawnError=true;terminate();});
   handle.on('close',(code,signal)=>finish({code,signal,reaped:true}));
   // Independent hard observation bound, including a child that does not emit
   // close after SIGKILL. Such a child is unconfirmed, never followed by work.
   reapTimer=setTimeout(()=>{
    timeout=true;terminate();
    // Stop observing bounded pipes if the OS has not acknowledged death. This
    // does not assert termination or permit another case to begin.
    handle.stdout.destroy();handle.stderr.destroy();handle.unref();
    finish({code:null,signal:null,reaped:false});
   },budget+12000);
  });
  clearTimeout(timer);clearTimeout(killTimer);clearTimeout(reapTimer);stopChild=null;
  const metadata={exit_code:outcome.code,signal:outcome.signal,timeout,output_limit_exceeded:overflow,spawn_error:spawnError,reaped:outcome.reaped,stdout_bytes:stdoutBytes,stdout_sha256:stdoutHash.digest('hex'),stderr_bytes:stderrBytes,stderr_sha256:stderrHash.digest('hex')};
  return {metadata,stdout:!overflow?Buffer.concat(buffers):Buffer.alloc(0)};
 }
 try{
  // Consume credential input before any source/module/child work; it is never
  // inherited by either runner. Only the returned in-memory URL is retained.
  const environment={...process.env};delete process.env[ADMIN_ENV];
  const invocation=validateInvocation({argv:process.argv,env:environment});delete environment[ADMIN_ENV];
  output=await mkdtemp(join(tmpdir(),'collect-member-realtime-native-'));await chmod(output,0o700);
  const outputParent=await open(dirname(output),'r');try{await outputParent.sync();}finally{await outputParent.close();}
  const here=fileURLToPath(import.meta.url);need(resolve(process.argv[1])===here&&await realpath(here)===here,'PHYSICAL_CALLER_REQUIRED');
  root=await realpath(resolve(dirname(here),'../../..'));need(here===join(root,CALLER),'FIXED_MAINTAINED_CALLER_REQUIRED');
  need(await realpath(invocation.deno)===invocation.deno&&(await stat(invocation.deno)).isFile()&&((await stat(invocation.deno)).mode&0o111)!==0,'PHYSICAL_EXECUTABLE_DENO_REQUIRED');
  if(invocation.cache!==undefined)need(await realpath(invocation.cache)===invocation.cache&&(await stat(invocation.cache)).isDirectory(),'PHYSICAL_DENO_CACHE_REQUIRED');
  const denoPin={path:invocation.deno,sha256:sha(await readFile(invocation.deno))};
  const inputs=[];
  for(const[role,pin]of Object.entries(EXPECTED)){const input=await sourceFile(role);need(input.sha256===pin,'REVIEWED_SOURCE_PIN_MISMATCH');inputs.push(input);}
  inputs.push(await sourceFile(CALLER));await parity(inputs);
  const packageJson=JSON.parse(await readFile(join(root,'scripts/supabase/package.json'),'utf8'));
  need(packageJson.dependencies?.pg==='8.16.3'&&packageJson.devDependencies?.deno==='2.9.6','LOCKED_TOOLING_REQUIRED');
  const {loadReviewedPlatformFixture}=await import(pathToFileURL(join(root,HELPER)).href);
  const fixture=await loadReviewedPlatformFixture(root);await fixture.parity();
  const witnessSource=await readFile(join(root,RUNTIME),'utf8');
  const match=/const PINS:Record<string,string>=(\{[\s\S]*?\n\});/.exec(witnessSource);need(match,'ORIGINAL_RUNTIME_PINS_REQUIRED');
  const original17=JSON.parse(match[1]);need(Object.keys(original17).length===17&&Object.entries(original17).every(([role,pin])=>EXPECTED[role]===pin),'ORIGINAL_RUNTIME_CLOSURE_CHANGED');
  const closureSha256=sha(JSON.stringify({original17,sql10:fixture.binding,sql11:{role:SQL11_ROLE,sha256:ROOT_SQL11_SHA256}}));
  stage='deno_version';
  await parity(inputs);
  const version=await child(invocation.deno,['--version'],cleanChildEnvironment(environment,{cache:invocation.cache}),{budget:5000,limit:4096});
  await save('deno-version.json',version.metadata);
  await parity(inputs);
  need(await realpath(invocation.deno)===invocation.deno&&sha(await readFile(invocation.deno))===denoPin.sha256,'DENO_EXECUTABLE_CHANGED');
  need(version.metadata.exit_code===0&&!version.metadata.signal&&!version.metadata.timeout&&!version.metadata.output_limit_exceeded&&!version.metadata.spawn_error&&version.metadata.reaped,'DENO_VERSION_UNCONFIRMED');
  const firstLine=new TextDecoder('utf-8',{fatal:true}).decode(version.stdout).split(/\r?\n/)[0];
  need(/^deno 2\.9\.6(?: \([^\r\n]*\))?$/.test(firstLine),'EXACT_DENO_2_9_6_REQUIRED');
  // No PostgreSQL module import or connection occurs until Deno/source checks.
  const require=createRequire(import.meta.url);const entry=require.resolve(invocation.module);
  need(isAbsolute(entry)&&await realpath(entry)===entry,'PHYSICAL_PG_MODULE_REQUIRED');
  let packagePath=dirname(entry),installed;
  for(let i=0;i<6;i++){
   try{const value=JSON.parse(await readFile(join(packagePath,'package.json'),'utf8'));if(value.name==='pg'){installed=value;break;}}catch{}
   packagePath=dirname(packagePath);
  }
  need(installed?.name==='pg'&&installed.version==='8.16.3','EXACT_PG_8_16_3_REQUIRED');
  const {Client}=require(entry);need(typeof Client==='function','PG_CLIENT_REQUIRED');
  function makeClient(url){
   healthy();const client=new Client({connectionString:url.href,ssl:false,connectionTimeoutMillis:5000,statement_timeout:120000,query_timeout:125000,application_name:'collect-member-realtime-native-parent'});
   // Attach before connect; raw EventEmitter error values are never retained.
   client.on('error',poison);const query=client.query.bind(client);
   client.query=(...args)=>{healthy();return query(...args);};clients.add(client);return client;
  }
  const suffix=randomBytes(12).toString('hex');
  cases.push({kind:'runtime',database:'collect_fence_runtime_'+suffix+'_test',initialize_operation:randomUUID(),created:false,creation_dispatched:false,initialized:false},
   {kind:'realtime',database:'collect_member_realtime_'+suffix+'_test',initialize_operation:randomUUID(),created:false,creation_dispatched:false,initialized:false});
  need(cases.every(item=>/^[a-z_]+[a-f0-9]{24}_test$/.test(item.database)&&item.database.length<=63),'NEW_DATABASE_IDENTIFIER_REQUIRED');
  await save('PLAN.json',{format:'collect.local.member-realtime.native-qualification.v1',at:new Date().toISOString(),migration_count:11,inputs:inputs.map(({role,bytes,sha256})=>({role,bytes,sha256})),deno:{...denoPin,version:'2.9.6'},pg_version:'8.16.3',source:SOURCE,baseline:BASELINE,sql10_binding:fixture.binding,original_runtime_closure_sha256:closureSha256,cases,fixture_scope:'new_loopback_databases_only',automatic_retry:false,reset_or_drop:false,preserve_all_databases:true,managed_project_writes:0,full_realtime_matrix_qualified:false,sb22Satisfied:false,sb29Satisfied:false});
  for(const item of cases){
   currentCase=item.kind;let admin,db;await parity(inputs);stage=item.kind+'_setup';
   const setup=(async()=>{
    admin=makeClient(invocation.target);await verifyLocalConnection(admin,{target:invocation.target,database:'postgres',parity:()=>parity(inputs)});
    const exists=await admin.query('SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_database WHERE datname=$1) AS found',[item.database]);
    need(exists.rows?.length===1&&exists.rows[0].found===false,'FRESH_DATABASE_NAME_COLLISION');
    await save(item.kind+'-create-intent.json',{database:item.database,template:'template0',owner:'collect_test',creation_may_be_unknown:true,no_retry:true,preserve_database:true});
    await parity(inputs);item.creation_dispatched=true;
    await admin.query('CREATE DATABASE "'+item.database+'" OWNER collect_test TEMPLATE template0 ENCODING \'UTF8\'');item.created=true;
    await save(item.kind+'-created.json',{database:item.database,acknowledged:true,preserve_database:true});
    const target=new URL(invocation.target.href);target.pathname='/'+item.database;
    db=makeClient(target);await verifyLocalConnection(db,{target,database:item.database,parity:()=>parity(inputs)});
    const empty=await db.query("SELECT count(*)::integer AS count FROM pg_catalog.pg_namespace WHERE nspname IN('app','private','api','auth','realtime','collect_ops')");
    need(empty.rows?.[0]?.count===0,'NEW_DATABASE_MUST_BE_EMPTY');
    await fixture.parity();await parity(inputs);
    await fixture.apply(sql=>db.query(sql),{includeAuth:true});item.migrations=11;
    await save(item.kind+'-initialize-intent.json',{database:item.database,operation:item.initialize_operation,source:SOURCE,baseline:BASELINE,no_retry:true,genuine_owner_api:true});
    await parity(inputs);
    await db.query('SELECT private.collect_fence_initialize($1::uuid,$2::text,$3::text)',[item.initialize_operation,SOURCE,BASELINE]);item.initialized=true;
    const row=(await db.query(`SELECT private.collect_fence_owner_status() AS status,
      (SELECT count(*)::int FROM private.collect_fence_operations) AS operations,
      (SELECT count(*)::int FROM private.collect_fence_admissions) AS admissions,
      (SELECT count(*)::int FROM private.collect_fence_scheduler_lifecycle) AS proofs,
      (SELECT baseline_manifest_sha256 FROM private.collect_fence_control WHERE singleton) AS baseline,
      (SELECT count(*)::int FROM app.users) AS users,
      (SELECT count(*)::int FROM app.request_receipts) AS receipts,
      (SELECT count(*)::int FROM realtime.messages) AS messages,
      (SELECT enabled FROM private.member_realtime_control WHERE singleton) AS realtime_enabled`)).rows?.[0];
    const status=row?.status;
    need(row?.operations===1&&row.admissions===0&&row.proofs===0&&row.baseline===BASELINE&&row.users===0&&row.receipts===0&&row.messages===0&&row.realtime_enabled===false,'PRISTINE_TEN_MIGRATION_FIXTURE_REQUIRED');
    need(status?.contractVersion===1&&status.projectRef==='rrlduytparvsjfmegalh'&&status.mode==='open'&&status.epoch===1&&status.sourceSha256===SOURCE&&status.activeAdmissions===0&&status.unresolvedAdmissions===0&&status.retainedUnknownObligations===0&&status.schedulerStatus?.checked===true&&status.schedulerStatus?.coverageVerified===true&&status.schedulerStatus?.blocking===false,'GENUINE_OPEN_OWNER_CONTROL_REQUIRED');
    for(const flag of ['wholeSystemAcceptance','providerSettlement','managedInternalWritesFenced','humanMessagesFenced','atomicRecoverySnapshot','sb29Satisfied'])need(status[flag]===false,'OWNER_SCOPE_FLAGS_REQUIRED');
    await save(item.kind+'-prepared.json',{database:item.database,migrations:11,initialized:true,admissions:0,operations:1,proofs:0,realtime_enabled:false,owner_control:'open',pristine:true,preserve_database:true});
    await endClient(db,inputs);return target;
   })();
   abortSetup=()=>{for(const client of [db,admin])if(client&&clients.has(client))beginClose(client);};
   try{
    const target=await bounded(setup,SETUP_MS,poison,'DATABASE_PREPARATION_UNCONFIRMED');abortSetup=null;
    await parity(inputs);await fixture.parity();
    need(await realpath(invocation.deno)===invocation.deno&&sha(await readFile(invocation.deno))===denoPin.sha256,'DENO_EXECUTABLE_CHANGED');
    stage=item.kind+'_child';
    const fixtureVariable=item.kind==='runtime'?'COLLECT_FENCE_RUNTIME_TEST_DATABASE_URL':'COLLECT_MEMBER_REALTIME_SQL_TEST_DATABASE_URL';
    const env=cleanChildEnvironment(environment,{pgEntry:entry,fixtureVariable,fixtureUrl:target.href,cache:invocation.cache});
    const executable=item.kind==='runtime'?invocation.deno:process.execPath;
    const args=item.kind==='runtime'?['run','--cached-only','--frozen','--config',join(root,'supabase/functions/deno.json'),'--lock',join(root,'supabase/functions/deno.lock'),'--allow-env','--allow-read='+root,'--allow-net=127.0.0.1:'+invocation.target.port,join(root,RUNTIME)]:[join(root,REALTIME)];
    await save(item.kind+'-child-intent.json',{database:item.database,runner:item.kind==='runtime'?RUNTIME:REALTIME,dispatch_may_be_unknown:true,no_retry:true,preserve_database:true});
    await parity(inputs);
    const result=await child(executable,args,env);await save(item.kind+'-child-observation.json',result.metadata);
    const knownFailure=projectRealtimeFailure(item.kind,result.stdout);
    if(knownFailure)await save(item.kind+'-child-failure.json',knownFailure);
    healthy();await parity(inputs);await fixture.parity();
    need(await realpath(invocation.deno)===invocation.deno&&sha(await readFile(invocation.deno))===denoPin.sha256,'DENO_EXECUTABLE_CHANGED');
    const m=result.metadata;need(!knownFailure&&m.exit_code===0&&!m.signal&&!m.timeout&&!m.output_limit_exceeded&&!m.spawn_error&&m.reaped,'CHILD_EXECUTION_UNCONFIRMED');
    let receipt;try{receipt=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(result.stdout));}catch{fail('SINGLE_TYPED_CHILD_RECEIPT_REQUIRED');}
    item.result=validateChildReceipt(item.kind,receipt,{binding:fixture.binding,closureSha256});
    await save(item.kind+'-result.json',{database:item.database,...item.result,output:m,preserve_database:true});
   }finally{abortSetup=null;if(db)await endClient(db,inputs);if(admin)await endClient(admin,inputs);}
   await parity(inputs);
  }
  currentCase=null;stage='complete';await parity(inputs);
  const final={status:'PASS',fixture:'two_new_loopback_runtime_and_realtime_databases',output_directory:output,migration_count:11,cases,provider_calls:0,managed_project_writes:0,automatic_retry:false,preserve_all_databases:true,reset_or_drop:false,full_realtime_matrix_qualified:false,hosted_capacity_accepted:false,providerSettlement:false,wholeSystemAcceptance:false,sb22Satisfied:false,sb29Satisfied:false};
  await save('FINAL.json',final);console.log(JSON.stringify(final));
 }catch(error){
  const code=typeof error?.qualificationCode==='string'&&/^[A-Z0-9_]{1,80}$/.test(error.qualificationCode)?error.qualificationCode:'LOCAL_QUALIFICATION_UNCONFIRMED';
  const final={status:'UNCONFIRMED',code,stage,current_case:currentCase,output_directory:output??null,cases,automatic_retry:false,preserve_all_databases:true,reset_or_drop:false,full_realtime_matrix_qualified:false,sb22Satisfied:false,sb29Satisfied:false};
  if(output)try{await save('FINAL.json',final);}catch{}
  console.error(JSON.stringify(final));process.exitCode=1;
 }finally{
  // Termination only; never repairs rows, closes a durable admission, retries
  // CREATE/initialize, reseeds a schema or erases a successful/failed fixture.
  for(const client of clients)try{await bounded(beginClose(client),5000,()=>terminateSocket(client),'LOCAL_CONNECTION_CLOSE_UNCONFIRMED');}catch{terminateSocket(client);}
 }
}

if(process.argv[1]){
 let entry;try{entry=await realpath(resolve(process.argv[1]));}catch{}
 if(entry===fileURLToPath(import.meta.url))await main();
}
