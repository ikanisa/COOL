import {loadReviewedPlatformFixture,EXACT_CURRENT11} from '../testing/curated-platform-fixture.mjs';
import {readFile,readdir,realpath,mkdtemp,chmod,open} from 'node:fs/promises';
import {resolve,dirname,join,isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {tmpdir} from 'node:os';
import {createRequire} from 'node:module';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {spawn} from 'node:child_process';

const SOURCE='a'.repeat(64),BASELINE='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const MIGRATIONS=Object.freeze([
 '20261020134444_collect_curated_platform_baseline.sql',
 '20261020135932_collect_runtime_role_and_function_paths.sql',
 '20261020174856_collect_retention_retry_authority.sql',
 '20261020184012_collect_admin_invitation_attempts.sql',
 '20261020190301_collect_rls_helper_permissions.sql',
 '20261020191847_collect_privacy_email_reauthentication.sql',
 '20261020193752_collect_admin_invitation_access_notice_v2.sql',
 '20261020195249_collect_admin_invitation_public_id_preservation.sql',
 '20261022195747_collect_application_mutation_fence.sql',
 '20261022200028_collect_private_member_realtime.sql',
 '20261023002500_collect_admin_recent_email_source_upgrade.sql',
]);
const FIXTURE='supabase/tests/sql/00_local_auth_fixture.sql';
const PACKAGE='scripts/supabase/package.json',LOCK='scripts/supabase/package-lock.json',CALLER='scripts/supabase/emergency-fence/qualify.mjs';
const RUNNERS={contract:'scripts/supabase/emergency-fence/native-contract.mjs',proof:'scripts/supabase/emergency-fence/native-capacity.mjs',release:'scripts/supabase/emergency-fence/native-capacity.mjs'};
const SETUP_MS=150000,RUNNER_MS=150000,OUTPUT_LIMIT=65536;
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const fail=code=>{const error=new Error(code);error.fenceCode=code;throw error;};
const need=(condition,code)=>{if(!condition)fail(code);};
const require=createRequire(import.meta.url);
let sourceRoot,out,stage='preflight',currentCase=null;
const cases=[];
let databaseError=false,abortSetup=null,stopChild=null;
function databaseHealthy(){need(!databaseError,'LOCAL_DATABASE_CONNECTION_ERROR');}
function databaseFailed(){databaseError=true;abortSetup?.();stopChild?.();}

function adminTarget(raw){
 let url;try{url=new URL(raw);}catch{fail('LOCAL_ADMIN_URL_REQUIRED');}
 need(['postgres:','postgresql:'].includes(url.protocol)&&['127.0.0.1','[::1]'].includes(url.hostname)&&/^\d{1,5}$/.test(url.port)&&Number(url.port)>0&&Number(url.port)<=65535&&url.pathname==='/postgres'&&!!url.username&&!!url.password&&!url.search&&!url.hash,'LOCAL_ADMIN_URL_REQUIRED');
 return url;
}
async function sourceFile(role){
 const path=resolve(sourceRoot,role);need(await realpath(path)===path,'PHYSICAL_SOURCE_REQUIRED');
 const bytes=await readFile(path);need(bytes.length>0,'EMPTY_QUALIFICATION_INPUT');return{role,path,bytes,sha256:sha(bytes)};
}
async function inputParity(inputs){databaseHealthy();for(const item of inputs)need(await realpath(item.path)===item.path&&sha(await readFile(item.path))===item.sha256,'QUALIFICATION_SOURCE_CHANGED');}
async function save(name,value){
 const file=await open(join(out,name),'wx',0o600);try{await file.writeFile(JSON.stringify(value,null,2)+'\n');await file.sync();}finally{await file.close();}
 const directory=await open(out,'r');try{await directory.sync();}finally{await directory.close();}
}
async function deadline(promise,ms,onTimeout,code){
 let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>{try{void Promise.resolve(onTimeout()).catch(()=>{});}catch{}const error=new Error(code);error.fenceCode=code;reject(error);},ms);})]);}finally{clearTimeout(timer);}
}
async function closeClient(client){try{await deadline(client.end(),5000,()=>{},'LOCAL_CLOSE_UNCONFIRMED');}catch{}}
async function identity(client,name){
 const row=(await client.query("SELECT current_database()::text AS database,pg_catalog.host(pg_catalog.inet_server_addr()) AS address,current_setting('server_version_num') AS version,current_setting('default_transaction_isolation') AS isolation")).rows[0];
 need(row?.database===name&&['127.0.0.1','::1'].includes(row.address)&&/^17\d{4}$/.test(row.version)&&row.isolation==='read committed','LOCAL_DATABASE_IDENTITY_REQUIRED');
}
async function pgClientFactory(){
 const configured=process.env.COLLECT_PG_MODULE??'pg';need(configured==='pg'||isAbsolute(configured),'LOCAL_PG_MODULE_REQUIRED');
 const entry=await realpath(require.resolve(configured));let folder=dirname(entry),metadata;
 for(let n=0;n<5;n++){try{const candidate=JSON.parse(await readFile(join(folder,'package.json'),'utf8'));if(candidate.name==='pg'){metadata=candidate;break;}}catch{}const parent=dirname(folder);if(parent===folder)break;folder=parent;}
 need(metadata?.version==='8.16.3','LOCKED_PG_VERSION_REQUIRED');
 const pkg=JSON.parse(await readFile(join(sourceRoot,PACKAGE),'utf8'));need(pkg.dependencies?.pg==='8.16.3','LOCKED_PG_VERSION_REQUIRED');
 const {Client}=require(entry);need(typeof Client==='function','LOCKED_PG_CLIENT_REQUIRED');
 return{entry,version:metadata.version,make:url=>{
  databaseHealthy();const client=new Client({connectionString:url,ssl:false,connectionTimeoutMillis:5000,statement_timeout:120000,query_timeout:125000});
  // pg emits idle/disconnected errors outside query promises. Attach before
  // connect; retain only a fixed failure flag and stop further fixture work.
  client.on('error',databaseFailed);
  const query=client.query.bind(client);client.query=(...args)=>{databaseHealthy();return query(...args);};
  return client;
 }};
}
function identifier(name){need(/^[a-z_0-9]+$/.test(name)&&Buffer.byteLength(name)<=63,'OWNED_DATABASE_NAME_REQUIRED');return '"'+name+'"';}
async function prepare(target,name,inputs,pg){
 const admin=pg.make(target.href);let db,aborted=false;abortSetup=()=>{aborted=true;};const mark=name=>{databaseHealthy();need(!aborted,'SETUP_TIMEOUT_UNCONFIRMED');stage=name;};
 const task=(async()=>{
  mark('admin_identity');await admin.connect();await identity(admin,'postgres');
  mark('create_database');currentCase.database_creation='dispatched_unconfirmed';await save(currentCase.scenario+'.create-intent.json',{database:name,create_dispatched:true,preserve_if_unknown:true});databaseHealthy();need(!aborted,'SETUP_TIMEOUT_UNCONFIRMED');await admin.query('CREATE DATABASE '+identifier(name)+" TEMPLATE template0 ENCODING 'UTF8'");
  currentCase.database_created=true;currentCase.database_creation='confirmed';await save(currentCase.scenario+'.created.json',{database:name,created:true,reset:false,preserved:true});
  await closeClient(admin);const local=new URL(target);local.pathname='/'+name;db=pg.make(local.href);
  mark('fixture_identity');await db.connect();await identity(db,name);
  const found=await db.query("SELECT count(*)::int AS count FROM pg_namespace WHERE nspname IN('app','private','api','auth','collect_ops')");need(found.rows[0]?.count===0,'NEW_EMPTY_DATABASE_REQUIRED');
  mark('reviewed_platform');const reviewedPlatform=await loadReviewedPlatformFixture(sourceRoot);
  await reviewedPlatform.apply(text=>db.query(text),{includeAuth:true});currentCase.applied_migrations=11;
  const role=(await db.query("SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname='postgres'")).rows[0];need(role&&role.rolsuper===false&&role.rolbypassrls===false,'RESTRICTED_POSTGRES_FIXTURE_REQUIRED');

  mark('initialize_source');await save(currentCase.scenario+'.initialize-intent.json',{database:name,operation_id:currentCase.initialization_operation_id,source_sha256:SOURCE,baseline_sha256:BASELINE,no_retry:true});databaseHealthy();need(!aborted,'SETUP_TIMEOUT_UNCONFIRMED');const initial=(await db.query('SELECT private.collect_fence_initialize($1::uuid,$2::text,$3::text) AS result',[currentCase.initialization_operation_id,SOURCE,BASELINE])).rows[0]?.result;
  need(initial?.contractVersion===1&&initial.mode==='open'&&initial.epoch===1&&initial.sourceSha256===SOURCE,'SYNTHETIC_INITIALIZATION_REQUIRED');
  mark('initial_status');const status=(await db.query('SELECT private.collect_fence_owner_status() AS result')).rows[0]?.result;
  need(status?.mode==='open'&&status.epoch===1&&status.sourceSha256===SOURCE&&status.activeAdmissions===0&&status.unresolvedAdmissions===0&&status.schedulerStatus?.blocking===false,'SYNTHETIC_INITIALIZATION_REQUIRED');
  await closeClient(db);db=null;return local.href;
 })();
 try{return await deadline(task,SETUP_MS,async()=>{aborted=true;await Promise.allSettled([closeClient(admin),db?closeClient(db):Promise.resolve()]);},'SETUP_TIMEOUT_UNCONFIRMED');}
 finally{abortSetup=null;await Promise.allSettled([closeClient(admin),db?closeClient(db):Promise.resolve()]);}
}
function childEnvironment(pg,url,scenario){
 const env={};for(const key of ['PATH','HOME','TMPDIR','TMP','TEMP','SystemRoot','LANG','LC_ALL'])if(process.env[key])env[key]=process.env[key];
 env.COLLECT_PG_MODULE=pg.entry;env.COLLECT_CI_SYNTHETIC='true';
 env[scenario==='contract'?'COLLECT_FENCE_SQL_TEST_DATABASE_URL':'COLLECT_FENCE_SQL_CAPACITY_DATABASE_URL']=url;return env;
}
// Only these fixed diagnostic fields may cross the child-output boundary.
// Raw child output remains memory-only, even when parsing or validation fails.
const NATIVE_FAILURE_FORMAT='collect.emergency-fence.native-failure.v1';
const NATIVE_FAILURE_TYPES=Object.freeze(['assertion','postgres','type_error','range_error','syntax_error','reference_error','error','unknown']);
const NATIVE_FAILURE_KEYS=Object.freeze(['format','version','type','sqlState','checkCount','sourceLine']);
function allowlistedNativeFailure(stderr,sourceLineLimit){
 let found=null,matching=0,invalid=false;
 for(const line of stderr.split(/\r?\n/)){
  let candidate;try{candidate=JSON.parse(line);}catch{continue;}
  if(candidate?.format!==NATIVE_FAILURE_FORMAT)continue;
  matching++;
  if(candidate===null||typeof candidate!=='object'||Array.isArray(candidate)
   ||Object.keys(candidate).length!==NATIVE_FAILURE_KEYS.length
   ||!NATIVE_FAILURE_KEYS.every(key=>Object.hasOwn(candidate,key))
   ||candidate.version!==1||!NATIVE_FAILURE_TYPES.includes(candidate.type)
   ||!(candidate.sqlState===null||(typeof candidate.sqlState==='string'&&/^[0-9A-Z]{5}$/.test(candidate.sqlState)))
   ||!(candidate.checkCount===null||(Number.isSafeInteger(candidate.checkCount)&&candidate.checkCount>=0&&candidate.checkCount<10000))
   ||!(candidate.sourceLine===null||(Number.isSafeInteger(candidate.sourceLine)&&candidate.sourceLine>=1&&candidate.sourceLine<=sourceLineLimit))
   ||(candidate.type==='postgres'&&candidate.sqlState===null)){
   invalid=true;continue;
  }
  found={format:NATIVE_FAILURE_FORMAT,version:1,type:candidate.type,sqlState:candidate.sqlState,
   checkCount:candidate.checkCount,sourceLine:candidate.sourceLine};
 }
 return matching===1&&!invalid?found:null;
}

async function nativeRunner(path,url,scenario,pg){
 databaseHealthy();stage='native_'+scenario;
 const sourceLineLimit=scenario==='contract'?(await readFile(path,'utf8')).split(/\r?\n/).length:0;
 need(scenario!=='contract'||(sourceLineLimit>0&&sourceLineLimit<=10000),'NATIVE_DIAGNOSTIC_SOURCE_BOUND_REQUIRED');
 return new Promise((resolveRun,reject)=>{
  const child=spawn(process.execPath,[path],{cwd:sourceRoot,env:childEnvironment(pg,url,scenario),shell:false,stdio:['ignore','pipe','pipe']});
  let timedOut=false,overflow=false,spawnFailed=false,killTimer;const parts={stdout:[],stderr:[]},sizes={stdout:0,stderr:0},hashes={stdout:createHash('sha256'),stderr:createHash('sha256')};
  const stop=()=>{child.kill('SIGTERM');killTimer??=setTimeout(()=>child.kill('SIGKILL'),5000);};
  stopChild=stop;
  const timer=setTimeout(()=>{timedOut=true;stop();},RUNNER_MS);
  for(const stream of ['stdout','stderr'])child[stream].on('data',bytes=>{hashes[stream].update(bytes);sizes[stream]+=bytes.length;if(sizes[stream]<=OUTPUT_LIMIT)parts[stream].push(bytes);else if(!overflow){overflow=true;stop();}});
  child.on('error',()=>{spawnFailed=true;});
  child.on('close',(code,signal)=>{
   if(stopChild===stop)stopChild=null;clearTimeout(timer);clearTimeout(killTimer);let reported;
   const stdout=Buffer.concat(parts.stdout).toString('utf8');for(const line of stdout.split(/\r?\n/)){try{const candidate=JSON.parse(line);if(candidate?.status==='PASS')reported=candidate;}catch{}}
   const failureDiagnostic=scenario==='contract'?allowlistedNativeFailure(Buffer.concat(parts.stderr).toString('utf8'),sourceLineLimit):null;
   const scopeValid=scenario==='contract'?reported?.fixture==='new_unique_loopback_only'&&reported.hosted_acceptance===false&&reported.final_mode==='quiescing'&&reported.durable_unresolved_preserved===1&&reported.retained_unknown_obligations===1:reported?.fixture==='new_loopback_only'&&reported.hosted_capacity_accepted===false&&reported.managed_writes===0&&reported.scenario===scenario;
   const valid=!databaseError&&failureDiagnostic===null&&scopeValid&&code===0&&!timedOut&&!overflow&&!spawnFailed&&reported?.status==='PASS'&&Number.isSafeInteger(reported.checks)&&reported.checks>0&&reported.checks<10000&&reported.app_tables_unchanged===97&&reported.provider_calls===0&&reported.sb29Satisfied===false&&(scenario==='contract'||reported.scenario===scenario);
   const safe={scenario,database_error:databaseError,exit_code:code,signal:['SIGTERM','SIGKILL','SIGABRT','SIGSEGV'].includes(signal)?signal:null,timed_out:timedOut,output_limit_exceeded:overflow,spawn_failed:spawnFailed,stdout_bytes:sizes.stdout,stderr_bytes:sizes.stderr,stdout_sha256:hashes.stdout.digest('hex'),stderr_sha256:hashes.stderr.digest('hex'),status:valid?'PASS':'UNCONFIRMED',checks:valid?reported.checks:null,failure_diagnostic:failureDiagnostic,...(valid&&scenario==='contract'?{durable_unresolved_preserved:1,retained_unknown_obligations:1}:{}),app_tables_unchanged:valid?97:null,provider_calls:valid?0:null,hosted_acceptance:false,sb29Satisfied:false};
   // Raw output may contain a pg connection detail or assertion operand. Never
   // persist it. Safe byte/hash metadata preserves failure evidence without keys.
   resolveRun(safe);
  });
 });
}

try{
 process.umask(0o077);out=await realpath(await mkdtemp(join(tmpdir(),'collect-emergency-fence-')));await chmod(out,0o700);
 need(process.argv.length===2,'NO_COMMAND_ARGUMENTS_ALLOWED');
 const raw=process.env.COLLECT_FENCE_ADMIN_DATABASE_URL;delete process.env.COLLECT_FENCE_ADMIN_DATABASE_URL;const target=adminTarget(raw);
 const caller=await realpath(fileURLToPath(import.meta.url));sourceRoot=await realpath(resolve(dirname(caller),'../../..'));
 need(caller===join(sourceRoot,'scripts/supabase/emergency-fence/qualify.mjs'),'FIXED_PACKAGE_SOURCE_ROOT_REQUIRED');
 const found=(await readdir(join(sourceRoot,'supabase/migrations'))).filter(name=>/^\d{14}_.*\.sql$/.test(name)).sort();need(JSON.stringify(MIGRATIONS)===JSON.stringify(EXACT_CURRENT11)&&JSON.stringify(found)===JSON.stringify(MIGRATIONS),'EXACT_CURRENT11_MIGRATIONS_REQUIRED');
 const roles=[CALLER,FIXTURE,PACKAGE,LOCK,'scripts/supabase/testing/curated-platform-fixture.mjs','scripts/supabase/testing/member-realtime-fixture-plan.json','scripts/supabase/testing/member-realtime-interface.sql','scripts/supabase/testing/member-realtime-metadata.sql',...MIGRATIONS.map(name=>'supabase/migrations/'+name),...new Set(Object.values(RUNNERS))];const inputs=[];for(const role of roles)inputs.push(await sourceFile(role));
 // Validate all11 exact body pins, including Root's filled SQL11 pin, before
 // loading a driver or creating any fixture database.
 const preflightFixture=await loadReviewedPlatformFixture(sourceRoot);await preflightFixture.parity();
 const pg=await pgClientFactory(),hex=randomBytes(12).toString('hex');
 cases.push({scenario:'contract',database:'collect_fence_sql_'+hex+'_test',database_created:false,database_creation:'not_dispatched',initialization_operation_id:randomUUID(),applied_migrations:0},{scenario:'proof',database:'collect_fence_capacity_proof_'+hex+'_test',database_created:false,database_creation:'not_dispatched',initialization_operation_id:randomUUID(),applied_migrations:0},{scenario:'release',database:'collect_fence_capacity_release_'+hex+'_test',database_created:false,database_creation:'not_dispatched',initialization_operation_id:randomUUID(),applied_migrations:0});
 await save('PLAN.json',{format:'collect.emergency-fence.maintained-qualification.v1',inputs:inputs.map(({role,sha256,bytes})=>({role,sha256,bytes:bytes.length})),pg_version:pg.version,source_sha256:SOURCE,baseline_sha256:BASELINE,cases,local_only:true,destructive_reset:false,automatic_retry:false,preserve_databases:true});
 for(const item of cases){currentCase=item;await inputParity(inputs);stage='setup';const url=await prepare(target,item.database,inputs,pg);await inputParity(inputs);const result=await nativeRunner(join(sourceRoot,RUNNERS[item.scenario]),url,item.scenario,pg);Object.assign(item,result);await save(item.scenario+'.result.json',{...item,preserved:true});need(result.status==='PASS','NATIVE_RUNNER_UNCONFIRMED');await inputParity(inputs);}
 databaseHealthy();stage='complete';const final={status:'PASS',cases,checks:cases.reduce((n,item)=>n+item.checks,0),migration_count:11,synthetic_databases:3,preserved_databases:cases.map(item=>item.database),automatic_retry:false,provider_calls:0,hosted_acceptance:false,sb29Satisfied:false};await save('FINAL.json',final);console.log(JSON.stringify({...final,evidence_directory:out}));
}catch(error){
 const code=typeof error?.fenceCode==='string'&&/^[A-Z_0-9]{1,80}$/.test(error.fenceCode)?error.fenceCode:'QUALIFICATION_UNCONFIRMED';
 const final={status:'UNCONFIRMED',code,stage,scenario:currentCase?.scenario??null,cases,preserve_all_databases:true,automatic_retry:false,reset_or_drop_attempted:false,hosted_acceptance:false,sb29Satisfied:false};
 if(out)await save('FINAL.json',final).catch(()=>{});console.error(JSON.stringify({...final,evidence_directory:out??null}));process.exitCode=1;
}
