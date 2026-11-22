// Local-only maintained caller. A dedicated fresh cluster is required because
// its explicit owner-profile preparation changes the synthetic postgres role.
import {readFile,realpath,mkdtemp,open} from 'node:fs/promises';
import {resolve,join,dirname,isAbsolute} from 'node:path';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash,randomUUID,randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {loadReviewedPlatformFixture,ROOT_SQL14_SHA256,MIGRATION_FOURTEEN_ROLE} from './curated-platform-fixture.mjs';
import {snapshotMemberHistorySources,admitMemberHistoryOutput} from './current14-member-history.mjs';
const ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');
const RUNNER='scripts/supabase/emergency-fence/native-stopped-admission.mjs';
const INSTALL_RUNNER='scripts/supabase/emergency-fence/native-stopped-install.mjs';
const HELPER='scripts/supabase/testing/curated-platform-fixture.mjs';
const PINS=Object.freeze({
 'supabase/retention-inventory.json':'6b1229d9a01957a3e88e8f9b247b8781f3e2c6a1fc71ae52640a84ea7c48d585',
 'supabase/functions/_shared/private-retention.js':'eaab9655a3753d9fbd662dd057c032a7f716b914a9de36748f1443053c78ab61',
 'supabase/functions/_shared/member-realtime-retention.js':'2c29da6f8748bf98c4d4accc1c0e28d1a95e3ee42860c4c7bef505ba45c11bc6',
 'supabase/functions/_shared/domain/core.js':'18ce95c133a4895d13475338089fb00c9ba4c9283ee72c7d4d6f88ae8ea8723e',
 [HELPER]:'d7414577c68c94937c6fc49734c2a7197ec96db6367ca686e6d6b7844a5e008e',
 [INSTALL_RUNNER]:'727b5cd60c44bd5e62f7686bd5ff2bbf9775d274249ce81ff9e7e111920a133e',
 [RUNNER]:'959b39b063725f13e4a88da8a2b381bd58e97b23b5edca89923814cd3a5049c6',
 [MIGRATION_FOURTEEN_ROLE]:ROOT_SQL14_SHA256,
});
const sha=x=>createHash('sha256').update(x).digest('hex');
const need=(ok,code)=>{if(!ok){const e=new Error('Local stopped-admission qualification unconfirmed');e.qualificationCode=code;throw e;}};
export function validateInvocation({argv,env,nodeVersion=process.versions.node}){
 const memberHistory=argv.length===3&&argv[2]==='--with-member-history';
 need(argv.length===2||memberHistory,'NO_ARGUMENTS_ALLOWED');need(/^24\./.test(nodeVersion),'NODE_24_REQUIRED');
 need(env.COLLECT_CI_SYNTHETIC==='true','EXPLICIT_SYNTHETIC_CI_REQUIRED');
 const raw=env.COLLECT_STOPPED_ADMISSION_ADMIN_DATABASE_URL;
 need(typeof raw==='string'&&raw.length<=8192&&/^postgres:\/\/collect_test:[^\s/?#@]+@127\.0\.0\.1:[1-9][0-9]{0,4}\/postgres$/.test(raw),'EXACT_LOCAL_ADMIN_URL_REQUIRED');
 let url,password;try{url=new URL(raw);password=decodeURIComponent(url.password);}catch{need(false,'EXACT_LOCAL_ADMIN_URL_REQUIRED');}
 need(Number(url.port)<=65535&&password.length>0&&!/[\x00-\x1f\x7f]/.test(password),'EXACT_LOCAL_ADMIN_URL_REQUIRED');
 const module=env.COLLECT_PG_MODULE??'pg';
 need(module==='pg'||isAbsolute(module)&&resolve(module)===module&&!/[\x00-\x1f\x7f]/.test(module),'PHYSICAL_PG_MODULE_REQUIRED');
 if(memberHistory)for(const key of ['COLLECT_DENO','COLLECT_MEMBER_HISTORY_OUTPUT_DIR'])need(typeof env[key]==='string'&&isAbsolute(env[key])&&resolve(env[key])===env[key]&&!/[\x00-\x1f\x7f]/.test(env[key]),'MEMBER_HISTORY_EXECUTABLE_AND_OUTPUT_REQUIRED');
 return{url,module,...(memberHistory?{memberHistory:true,deno:env.COLLECT_DENO,historyOutput:env.COLLECT_MEMBER_HISTORY_OUTPUT_DIR}:{})};
}
export function validateReceipt(value){
 need(value&&Object.keys(value).sort().join(',')==='checks,counters_recovered,fixture,hosted_acceptance,provider_calls,raw_admission_unchanged,sb29Satisfied,status,stopped_local_proofs,unquantified_unknown_obligations','EXACT_NATIVE_RECEIPT_SHAPE_REQUIRED');
 need(value?.status==='PASS'&&Number.isSafeInteger(value.checks)&&value.checks===43&&value.fixture==='new_unique_loopback_only','EXACT_NATIVE_RECEIPT_REQUIRED');
 need(value.raw_admission_unchanged===true&&value.stopped_local_proofs===2&&value.unquantified_unknown_obligations===2&&value.counters_recovered===false&&value.provider_calls===0&&value.hosted_acceptance===false&&value.sb29Satisfied===false,'EXACT_NATIVE_SCOPE_REQUIRED');
 return value;
}
export function validateInstallReceipt(value){
 need(value&&Object.keys(value).sort().join(',')==='actual_work_lease_blocked_install,checks,committed_quiesce_install_passed,fixture,hosted_acceptance,open_install_refused,proofs_created,provider_calls,raw_admission_unchanged,sb29Satisfied,status,uncommitted_quiesce_refused','EXACT_INSTALL_NATIVE_RECEIPT_SHAPE_REQUIRED');
 need(value?.status==='PASS'&&value.fixture==='new_unique_loopback_existing_orphan_install'&&value.checks===29,'EXACT_INSTALL_NATIVE_RECEIPT_REQUIRED');
 for(const key of ['open_install_refused','uncommitted_quiesce_refused','actual_work_lease_blocked_install','committed_quiesce_install_passed','raw_admission_unchanged'])need(value[key]===true,'EXACT_INSTALL_NATIVE_SCOPE_REQUIRED');
 need(value.proofs_created===0&&value.provider_calls===0&&value.hosted_acceptance===false&&value.sb29Satisfied===false,'EXACT_INSTALL_NATIVE_SCOPE_REQUIRED');return value;
}
export function projectFailure(bytes){
 if(bytes.length>65536)return null;let v;try{v=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{return null;}
 const stages=['preflight','identity','open_refusal','uncommitted_quiesce_refusal','held_real_work','committed_quiesce_install','actual_current_retention_catalog'];
 const phases=['target','identity','register','uncommitted-quiesce','quiesce','refusals','record','legacy-and-scheduler','source-upgrade'];
 if(!v||!Number.isSafeInteger(v.checks)||v.checks<0||v.checks>1000||!(v.sqlState===null||typeof v.sqlState==='string'&&/^[0-9A-Z]{5}$/.test(v.sqlState)))return null;
 if(v.format==='collect.stopped-install.native-failure.v1'&&Object.keys(v).sort().join(',')==='checks,format,sqlState,stage'&&stages.includes(v.stage))return v;
 if(v.format==='collect.stopped-admission.native-failure.v1'&&Object.keys(v).sort().join(',')==='checks,format,phase,sqlState,type'&&phases.includes(v.phase)&&['assertion','postgres','error'].includes(v.type))return v;
 return null;
}
async function native(env,runner=RUNNER,args=[]){
 const child=spawn(process.execPath,[runner,...args],{cwd:ROOT,env,shell:false,stdio:['ignore','pipe','pipe']});
 let out=[],errors=[],bytes=0,errBytes=0,expired=false,overflow=false,spawnError=false,reaped=false;
 const errHash=createHash('sha256');let kill;
 const stop=()=>{child.kill('SIGTERM');kill??=setTimeout(()=>child.kill('SIGKILL'),5000);};
 const timer=setTimeout(()=>{expired=true;stop();},120000);
 child.stdout.on('data',data=>{bytes+=data.length;if(bytes<=65536)out.push(data);else{overflow=true;stop();}});
 child.stderr.on('data',data=>{errBytes+=data.length;errHash.update(data);if(errBytes<=65536)errors.push(data);else{overflow=true;stop();}});
 child.on('error',()=>{spawnError=true;stop();});
 const exit=await new Promise(done=>child.once('close',(code,signal)=>{reaped=true;done({code,signal});}));
 clearTimeout(timer);clearTimeout(kill);
 const metadata={...exit,reaped,expired,overflow,spawn_error:spawnError,stdout_bytes:bytes,stderr_bytes:errBytes,stderr_sha256:errHash.digest('hex'),failure_diagnostic:overflow?null:projectFailure(Buffer.concat(errors))};
 let value;try{value=JSON.parse(Buffer.concat(out).toString('utf8'));}catch{}
 return{metadata,value};
}
export async function main(){
 process.umask(0o077);let output,stage='preflight',fixture,child,installation,history,config,failed,poisoned=false;
 const clients=[];const inputs=[];let historyFiles=[];
 const healthy=()=>need(!poisoned,'CONNECTION_LOST');
 async function save(name,value){const f=await open(join(output,name),'wx',0o600);try{await f.writeFile(JSON.stringify(value,null,2)+'\n');await f.sync();}finally{await f.close();}}
 async function parity(){healthy();for(const[role,pin]of Object.entries(PINS)){const path=join(ROOT,role);need(await realpath(path)===path&&sha(await readFile(path))===pin,'REVIEWED_SOURCE_CHANGED');}for(const pin of historyFiles)need(await realpath(pin.path)===pin.path&&sha(await readFile(pin.path))===pin.sha256,'MEMBER_HISTORY_SOURCE_CHANGED');if(fixture)await fixture.parity();}
 try{
  config=validateInvocation({argv:process.argv,env:process.env});
  if(config.memberHistory){await admitMemberHistoryOutput(config.historyOutput);historyFiles=await snapshotMemberHistorySources(ROOT);need(await realpath(config.deno)===config.deno,'PHYSICAL_MEMBER_HISTORY_DENO_REQUIRED');}
  await parity();fixture=await loadReviewedPlatformFixture(ROOT,{includeStoppedAdmissionLifecycleMigration:true});
  for(const item of fixture.rawMigrations)inputs.push({role:'supabase/migrations/'+item.name,sha256:item.sha256});
  inputs.push(...Object.entries(PINS).map(([role,sha256])=>({role,sha256})));
  const require=createRequire(import.meta.url),{Client}=require(config.module);
  need(require(join(dirname(require.resolve(config.module)),'../package.json')).version==='8.16.3','EXACT_PG_DRIVER_REQUIRED');
  output=await realpath(await mkdtemp(join(tmpdir(),'collect-stopped-native-')));
  await save('INTENT.json',{format:'collect.stopped-admission.qualification.v1',inputs,provider_calls:0,preserve_database:true,automatic_retry:false,reset_or_drop:false,...(config.memberHistory?{member_history_source_files:historyFiles,member_history_output:config.historyOutput}:{})});
  const connect=async url=>{const c=new Client({connectionString:url,ssl:false,connectionTimeoutMillis:5000,statement_timeout:15000,lock_timeout:5000});clients.push(c);c.on('error',()=>{poisoned=true;});await c.connect();return c;};
  stage='cluster_identity';const admin=await connect(config.url.href);
  const observed=(await admin.query("SELECT current_database() db,current_user owner,session_user session,host(inet_server_addr()) host,inet_server_port() port,current_setting('server_version_num') version,current_setting('transaction_isolation') isolation,current_setting('default_transaction_isolation') default_isolation,(SELECT rolsuper AND rolbypassrls FROM pg_roles WHERE rolname=current_user) superuser,pg_get_userbyid((SELECT datdba FROM pg_database WHERE datname=current_database())) dbowner")).rows[0];
  need(observed.db==='postgres'&&observed.owner==='collect_test'&&observed.session==='collect_test'&&observed.host==='127.0.0.1'&&observed.port===Number(config.url.port)&&/^17\d{4}$/.test(observed.version)&&observed.isolation==='read committed'&&observed.default_isolation==='read committed'&&observed.superuser&&observed.dbowner==='collect_test','EXACT_FRESH_PG17_IDENTITY_REQUIRED');
  need((await admin.query("SELECT count(*)::int n FROM pg_roles WHERE rolname='postgres'")).rows[0].n===0,'FRESH_DEDICATED_CLUSTER_REQUIRED');
  need((await admin.query("SELECT count(*)::int n FROM pg_database WHERE datname NOT IN('postgres','template0','template1','collect_schema_test')")).rows[0].n===0,'FRESH_DEDICATED_CLUSTER_REQUIRED');
  await parity();const suffix=randomBytes(12).toString('hex'),name='collect_fence_stopped_'+suffix+'_test',installName='collect_fence_stopped_install_'+suffix+'_test',historyName=config.memberHistory?'collect_fence_stopped_history_'+suffix+'_test':null;
  const preparations=[];let sql14;
  for(const database of [name,installName,...(historyName?[historyName]:[])]){
   stage='create_unique_fixture';await admin.query('CREATE DATABASE "'+database+'" OWNER collect_test TEMPLATE template0 ENCODING \'UTF8\'');
   const local=new URL(config.url);local.pathname='/'+database;const setup=await connect(local.href);preparations.push({database,setup});
   stage='apply_exact_predecessors';let withheld=0;
   await fixture.apply(async sql=>{healthy();if(sha(sql)===ROOT_SQL14_SHA256){withheld++;sql14=sql;return;}return setup.query(sql);},{includeAuth:true});
   need(withheld===1,'SQL14_DISPATCH_REQUIRED');
  }
  await parity();
  stage='explicit_local_owner_profile';
  // Only this newly created DB is rebound. REASSIGN OWNED would also alter
  // shared database ownership; use catalog-selected current-DB objects instead.
  for(const {database,setup}of preparations){
  await setup.query(`DO $local_owner$
   DECLARE r record;BEGIN
    IF current_user<>'collect_test' OR session_user<>'collect_test' OR current_database() !~ '^collect_fence_stopped_((install|history)_)?[a-f0-9]{24}_test$' OR host(inet_server_addr())<>'127.0.0.1' THEN RAISE EXCEPTION 'OWNED_LOCAL_PROFILE_REQUIRED';END IF;
    FOR r IN SELECT nspname FROM pg_namespace WHERE nspowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND nspname NOT LIKE 'pg_%' AND nspname<>'information_schema' LOOP EXECUTE format('ALTER SCHEMA %I OWNER TO postgres',r.nspname);END LOOP;
    FOR r IN SELECT c.oid::regclass object,c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND c.relkind IN('r','p','v','m','f') LOOP EXECUTE format('ALTER %s %s OWNER TO postgres',CASE r.relkind WHEN 'S' THEN 'SEQUENCE' WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END,r.object);END LOOP;
    -- Linked sequences follow table ownership automatically. A fresh second
    -- scan transfers only independent sequences still owned by the bootstrap.
    FOR r IN SELECT c.oid::regclass object FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND c.relkind='S' LOOP EXECUTE format('ALTER SEQUENCE %s OWNER TO postgres',r.object);END LOOP;
    FOR r IN SELECT p.oid::regprocedure object FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND p.prokind='f' LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',r.object);END LOOP;
   END;$local_owner$;`);
  await admin.query('ALTER DATABASE "'+database+'" OWNER TO postgres');
  }
  const password=randomBytes(24).toString('hex');
  await admin.query("ALTER ROLE postgres LOGIN NOSUPERUSER NOINHERIT CREATEROLE NOCREATEDB NOBYPASSRLS NOREPLICATION PASSWORD '"+password+"'");
  const target=new URL(config.url);target.pathname='/'+name;target.username='postgres';target.password=password;const owner=await connect(target.href);
  const profile=(await owner.query("SELECT current_user owner,session_user session,rolsuper,rolbypassrls,rolcreaterole,rolcreatedb,rolinherit FROM pg_roles WHERE rolname=current_user")).rows[0];
  need(profile.owner==='postgres'&&profile.session==='postgres'&&!profile.rolsuper&&!profile.rolbypassrls&&profile.rolcreaterole&&!profile.rolcreatedb&&!profile.rolinherit,'EXACT_LOCAL_OWNER_PROFILE_REQUIRED');
  await save('LOCAL-OWNER-PROFILE.json',{databases:[name,installName,...(historyName?[historyName]:[])],observed_bootstrap:observed,profile,production_sql_rewritten:false,shared_ownership_reassigned:false,synthetic_only:true});
  stage='apply_exact_sql14';await owner.query(sql14);await parity();
  await owner.query('SELECT private.collect_fence_initialize($1,$2,$3)',[randomUUID(),'a'.repeat(64),'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3']);
  let historyTarget;
  if(historyName){historyTarget=new URL(target);historyTarget.pathname='/'+historyName;const historyOwner=await connect(historyTarget.href);await historyOwner.query(sql14);await historyOwner.query('SELECT private.collect_fence_initialize($1,$2,$3)',[randomUUID(),'a'.repeat(64),'dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3']);await parity();}
  // Child owns its three test connections. Close all setup sockets beforehand.
  for(const c of clients.splice(0))await c.end();healthy();
  const env={COLLECT_CI_SYNTHETIC:'true',COLLECT_PG_MODULE:config.module,COLLECT_STOPPED_ADMISSION_TEST_DATABASE_URL:target.href};
  for(const key of ['HOME','PATH','TMPDIR','LANG','LC_ALL'])if(process.env[key]!==undefined)env[key]=process.env[key];
  stage='existing_orphan_install_contract';const installTarget=new URL(target);installTarget.pathname='/'+installName;
  const installEnv={...env};delete installEnv.COLLECT_STOPPED_ADMISSION_TEST_DATABASE_URL;installEnv.COLLECT_STOPPED_ADMISSION_INSTALL_TEST_DATABASE_URL=installTarget.href;
  installation=await native(installEnv,INSTALL_RUNNER);await save('INSTALL-CHILD-METADATA.json',installation.metadata);
  need(installation.metadata.code===0&&installation.metadata.reaped&&!installation.metadata.expired&&!installation.metadata.overflow&&!installation.metadata.spawn_error,'INSTALL_NATIVE_CHILD_UNCONFIRMED');
  validateInstallReceipt(installation.value);await parity();await save('INSTALL-NATIVE-RECEIPT.json',installation.value);
  stage='native_contract';child=await native(env);await save('CHILD-METADATA.json',child.metadata);
  need(child.metadata.code===0&&child.metadata.reaped&&!child.metadata.expired&&!child.metadata.overflow&&!child.metadata.spawn_error,'NATIVE_CHILD_UNCONFIRMED');validateReceipt(child.value);await parity();
  await save('NATIVE-RECEIPT.json',child.value);
  if(historyTarget){
   stage='current14_member_history';
   const historyEnv={COLLECT_CI_SYNTHETIC:'true',COLLECT_DENO:config.deno,COLLECT_MEMBER_HISTORY_DATABASE_URL:historyTarget.href,COLLECT_MEMBER_HISTORY_OUTPUT_DIR:config.historyOutput};
   for(const key of ['HOME','PATH','TMPDIR','LANG','LC_ALL','DENO_DIR','GITHUB_SHA'])if(process.env[key]!==undefined)historyEnv[key]=process.env[key];
   history=await native(historyEnv,'scripts/supabase/test_schema.mjs',['--case=current14-member-history']);await save('MEMBER-HISTORY-CHILD-METADATA.json',history.metadata);
   need(history.metadata.code===0&&history.metadata.reaped&&!history.metadata.expired&&!history.metadata.overflow&&!history.metadata.spawn_error,'MEMBER_HISTORY_CHILD_UNCONFIRMED');
   need(history.value?.format==='collect.current14.history.capture.v1'&&history.value.status==='PASS'&&history.value.provider_calls===0&&history.value.hosted_acceptance===false&&history.value.legacy_gates_closed===false,'EXACT_MEMBER_HISTORY_SCOPE_REQUIRED');
   for(const key of ['packet','inputs','SQL','defines','native_result']){const artifact=history.value[key];need(artifact&&dirname(artifact.path)===config.historyOutput&&/^[a-f0-9]{64}$/.test(artifact.sha256)&&await realpath(artifact.path)===artifact.path&&sha(await readFile(artifact.path))===artifact.sha256,'MEMBER_HISTORY_ARTIFACT_CHANGED');}
   await parity();await save('MEMBER-HISTORY-RECEIPT.json',history.value);
  }
 }catch(error){failed={stage,code:error?.qualificationCode??(typeof error?.code==='string'&&/^[0-9A-Z]{5}$/.test(error.code)?'SQLSTATE_'+error.code:'QUALIFICATION_UNCONFIRMED')};}
 finally{
  for(const client of clients){try{await client.end();}catch{failed??={stage:'cleanup',code:'LOCAL_CONNECTION_CLOSE_UNCONFIRMED'};}}
 }
 const result={status:failed?'UNCONFIRMED':'PASS',stage,output_directory:output??null,failure:failed??null,native:failed?null:child.value,installation:failed?null:installation.value,sql14_sha256:ROOT_SQL14_SHA256,inputs,preserve_database:true,provider_calls:0,reset_or_drop:false,automatic_retry:false,hosted_acceptance:false,sb29Satisfied:false,...(config?.memberHistory?{member_history:history?.value??null}:{})};
 if(output)await save('RESULT.json',result);
 (failed?console.error:console.log)(JSON.stringify(result));if(failed)process.exitCode=1;return result;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))await main();
