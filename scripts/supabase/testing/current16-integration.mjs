// Local-only qualification of the complete, exact current16 candidate.
// Historical packets, migration bytes and reviewed fixture bindings stay intact.
import {readFile,readdir,realpath,lstat,mkdir,open,unlink} from 'node:fs/promises';
import {resolve,join,dirname,isAbsolute} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {loadReviewedPlatformFixture,EXACT_CURRENT16,ROOT_SQL14_SHA256,renderSyntheticSql} from './curated-platform-fixture.mjs';
import {captureBoundedHistoryChild} from './current14-member-history.mjs';

export const CURRENT16_ROOT=resolve(dirname(fileURLToPath(import.meta.url)),'../../..');
export const CURRENT16_RUNTIME='scripts/supabase/testing/current16-runtime.ts';
const ENTRY='scripts/supabase/testing/current16-integration.mjs';
const BASELINE='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
function need(ok,code){if(!ok)throw Object.assign(new Error('Current16 local qualification is unconfirmed'),{qualificationCode:code});}
const physical=value=>typeof value==='string'&&isAbsolute(value)&&resolve(value)===value&&!/[\x00-\x1f\x7f]/.test(value);
export function validateCurrent16Target(raw,{owner=false,database=false}={}){
 need(typeof raw==='string'&&raw.length<=8192,'EXACT_CURRENT16_LOOPBACK_URL_REQUIRED');
 let url,password;try{url=new URL(raw);password=decodeURIComponent(url.password);}catch{need(false,'EXACT_CURRENT16_LOOPBACK_URL_REQUIRED');}
 need(url.protocol==='postgres:'&&url.hostname==='127.0.0.1'&&url.username===(owner?'postgres':'collect_test')&&
  ['55439','55443'].includes(url.port)&&!url.search&&!url.hash&&password.length>0&&password.length<=2048&&!/[\x00-\x20\x7f]/.test(password)&&
  (database?/^\/collect_current16_integration_[a-f0-9]{24}_test$/.test(url.pathname):url.pathname==='/postgres'),
  'EXACT_CURRENT16_LOOPBACK_URL_REQUIRED');
 return url;
}
export function validateCurrent16Invocation({argv,env,nodeVersion=process.versions.node}){
 need(argv.length===2,'NO_ARGUMENTS_ALLOWED');need(/^24\./.test(nodeVersion),'NODE_24_REQUIRED');
 need(env.COLLECT_CI_SYNTHETIC==='true','EXPLICIT_SYNTHETIC_CI_REQUIRED');
 const admin=validateCurrent16Target(env.COLLECT_CURRENT16_ADMIN_DATABASE_URL);
 const owner=env.COLLECT_CURRENT16_OWNER_DATABASE_URL===undefined?null:validateCurrent16Target(env.COLLECT_CURRENT16_OWNER_DATABASE_URL,{owner:true});
 need(!owner||owner.port===admin.port,'MATCHING_CURRENT16_OWNER_REQUIRED');
 for(const key of ['COLLECT_DENO','COLLECT_CURRENT16_OUTPUT_DIR'])need(physical(env[key]),'PHYSICAL_CURRENT16_PATH_REQUIRED');
 const module=env.COLLECT_PG_MODULE??'pg';need(module==='pg'||physical(module),'PHYSICAL_PG_MODULE_REQUIRED');
 return {admin,owner,deno:env.COLLECT_DENO,output:env.COLLECT_CURRENT16_OUTPUT_DIR,module};
}
export function validateCurrent16RunSpec(spec,path){
 need(spec&&Object.keys(spec).sort().join(',')==='format,inputs,inputs_sha256,output,source,source_sha256,url','EXACT_CURRENT16_SPEC_REQUIRED');
 need(spec.format==='collect.current16.run-spec.v1'&&spec.source===CURRENT16_ROOT&&physical(spec.output)&&
  path===join(spec.output,'RUN-SPEC.private.json')&&spec.inputs===join(spec.output,'INPUTS.json')&&
  /^[a-f0-9]{64}$/.test(spec.inputs_sha256)&&/^[a-f0-9]{64}$/.test(spec.source_sha256),'EXACT_CURRENT16_SPEC_REQUIRED');
 return validateCurrent16Target(spec.url,{owner:true,database:true});
}
export async function admitCurrent16Output(path){
 need(physical(path)&&await realpath(dirname(path))===dirname(path),'PHYSICAL_CURRENT16_OUTPUT_PARENT_REQUIRED');
 try{await lstat(path);}catch(error){if(error.code==='ENOENT')return;throw error;}
 need(false,'FRESH_CURRENT16_OUTPUT_REQUIRED');
}
export async function current16RuntimeRoles(root=CURRENT16_ROOT){
 const roles=[];let entries=0;
 async function visit(directory){for(const item of await readdir(join(root,directory),{withFileTypes:true})){
  need(++entries<=4096,'BOUNDED_CURRENT16_SOURCE_TREE_REQUIRED');need(!item.isSymbolicLink(),'PHYSICAL_CURRENT16_SOURCE_REQUIRED');if(item.name==='tests')continue;
  const role=directory+'/'+item.name;if(item.isDirectory())await visit(role);else if(item.isFile()&&/\.(?:js|mjs)$/.test(item.name))roles.push(role);
  else need(item.isFile(),'REGULAR_CURRENT16_SOURCE_REQUIRED');}}
 await visit('supabase/functions');
 return roles.sort();
}
export function verifyCurrent16RoleInventory(files,observed){
 need(Array.isArray(observed)&&JSON.stringify(files.map(item=>item.role).sort())===JSON.stringify([...observed].sort()),'CURRENT16_SOURCE_INVENTORY_CHANGED');
}
export async function current16Sources(root=CURRENT16_ROOT){
 const roles=await current16RuntimeRoles(root);
 roles.push(...EXACT_CURRENT16.map(name=>'supabase/migrations/'+name),ENTRY,CURRENT16_RUNTIME,
  'scripts/supabase/testing/curated-platform-fixture.mjs','scripts/supabase/testing/current14-member-history.mjs',
  'scripts/supabase/testing/member-realtime-fixture-plan.json','scripts/supabase/testing/member-realtime-interface.sql',
  'scripts/supabase/testing/member-realtime-metadata.sql','supabase/tests/sql/00_local_auth_fixture.sql',
  'supabase/retention-inventory.json','supabase/functions/deno.json','supabase/functions/deno.lock',
  'scripts/supabase/package.json','scripts/supabase/package-lock.json','.dvmrc');
 const files=[];let totalBytes=0;need(roles.length<=1024,'BOUNDED_CURRENT16_SOURCE_TREE_REQUIRED');for(const role of [...new Set(roles)].sort()){
  const path=resolve(root,role);need(path.startsWith(root+'/')&&await realpath(path)===path,'PHYSICAL_CURRENT16_SOURCE_REQUIRED');
  const size=(await lstat(path)).size;need(size>0&&size<=8*1024*1024&&totalBytes+size<=32*1024*1024,'BOUNDED_CURRENT16_SOURCE_BYTES_REQUIRED');
  const bytes=await readFile(path);totalBytes+=bytes.length;need(bytes.length===size,'CURRENT16_SOURCE_CHANGED');files.push({role,bytes:bytes.length,sha256:sha(bytes)});
 }return files;
}
export async function verifyCurrent16Sources(files,root=CURRENT16_ROOT){
 need(Array.isArray(files)&&files.length>0,'CURRENT16_SOURCE_MANIFEST_REQUIRED');
 const seen=new Set();for(const item of files){
  need(item&&typeof item.role==='string'&&!seen.has(item.role)&&/^[a-f0-9]{64}$/.test(item.sha256)&&Number.isSafeInteger(item.bytes)&&item.bytes>0,'CURRENT16_SOURCE_MANIFEST_REQUIRED');
  const path=resolve(root,item.role);need(path.startsWith(root+'/')&&item.role===path.slice(root.length+1)&&await realpath(path)===path,'PHYSICAL_CURRENT16_SOURCE_REQUIRED');
  const bytes=await readFile(path);need(bytes.length===item.bytes&&sha(bytes)===item.sha256,'CURRENT16_SOURCE_CHANGED');seen.add(item.role);
 }
 // Re-enumeration detects an added/deleted runtime source, not only changes to
 // the files that happened to exist at capture time.
 if(root===CURRENT16_ROOT){const current=await current16Sources(root);verifyCurrent16RoleInventory(files,current.map(item=>item.role));need(JSON.stringify(files)===JSON.stringify(current),'CURRENT16_SOURCE_CHANGED');}
}
export function validateCurrent16Receipt(value){
 need(value&&Object.keys(value).sort().join(',')==='cases,external_provider_calls,failure,financial_posting_acceptance,fixture_preserved,format,hosted_acceptance,legacy_sql_gates_closed,migration_count,normal_owner,normal_runtime,source_sha256,status,synthetic_provider_calls','EXACT_CURRENT16_RECEIPT_REQUIRED');
 need(value.format==='collect.current16.native.v1'&&value.status==='PASS'&&value.failure===null&&value.migration_count===16&&
  value.normal_owner===true&&value.normal_runtime===true&&value.fixture_preserved===true&&value.external_provider_calls===0&&
  value.hosted_acceptance===false&&value.legacy_sql_gates_closed===false&&value.financial_posting_acceptance===false&&
  value.cases===16&&Number.isSafeInteger(value.synthetic_provider_calls)&&value.synthetic_provider_calls>=4&&
  /^[a-f0-9]{64}$/.test(value.source_sha256),'EXACT_CURRENT16_SCOPE_REQUIRED');return value;
}
async function writeExclusive(path,value){const file=await open(path,'wx',0o600);try{await file.writeFile(JSON.stringify(value,null,2)+'\n');await file.sync();}finally{await file.close();}}
export async function removeCurrent16PrivateSpec(path,{remove=unlink,inspect=lstat}={}){
 try{await remove(path);}catch(error){need(error.code==='ENOENT','CURRENT16_PRIVATE_SPEC_CLEANUP_UNCONFIRMED');}
 try{await inspect(path);}catch(error){need(error.code==='ENOENT','CURRENT16_PRIVATE_SPEC_CLEANUP_UNCONFIRMED');return true;}
 // An acknowledged unlink alone does not establish absence. Any retained file,
 // directory or link disqualifies the result before public PASS is written.
 need(false,'CURRENT16_PRIVATE_SPEC_CLEANUP_UNCONFIRMED');
}
const roleQuery="SELECT rolcanlogin,rolsuper,rolinherit,rolcreaterole,rolcreatedb,rolbypassrls,rolreplication FROM pg_roles WHERE rolname='postgres'";
export function current16OwnerProfile(row){
 if(!row)return 'absent';
 const keys=['rolcanlogin','rolsuper','rolinherit','rolcreaterole','rolcreatedb','rolbypassrls','rolreplication'];
 if(keys.every(key=>row[key]===false))return 'restricted';
 if(row.rolcanlogin===true&&row.rolcreaterole===true&&keys.filter(key=>!['rolcanlogin','rolcreaterole'].includes(key)).every(key=>row[key]===false))return 'normal';
 need(false,'EXACT_CURRENT16_OWNER_PROFILE_REQUIRED');
}
// This applies the same exact, pre-admitted inputs under an independently
// observed prepared-owner cluster. It never weakens fixture.apply()'s distinct
// restricted-role profile or edits its historic callers/pin.
async function applyPreparedPredecessors(setup,fixture){
 await setup.query(fixture.auth);
 for(const item of fixture.rawMigrations.slice(0,9))await setup.query(item.sql);
 const interfaceSql=await readFile(join(CURRENT16_ROOT,'scripts/supabase/testing/member-realtime-interface.sql'),'utf8');
 need(sha(interfaceSql)===fixture.binding.interface_sha256,'CURRENT16_REALTIME_SOURCE_CHANGED');await setup.query(interfaceSql);
 const hosted=fixture.rawMigrations[9].sql;let refused=false;
 try{await setup.query(hosted);}catch(error){refused=error.code==='55000'&&error.message==='member_realtime_metadata_not_reviewed';}
 finally{await setup.query('ROLLBACK');}
 need(refused,'HOSTED_REALTIME_BINDING_MUST_REFUSE_LOCAL_PROFILE');
 need((await setup.query("SELECT to_regclass('private.member_realtime_control') IS NULL AS clean,NOT EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='realtime.messages'::regclass) AS policies")).rows.every(row=>row.clean&&row.policies),'HOSTED_REALTIME_REFUSAL_MUST_ROLL_BACK');
 await setup.query(renderSyntheticSql(hosted,fixture.binding));
 for(const item of fixture.rawMigrations.slice(10,13))await setup.query(item.sql);
}
async function transferNewDatabaseObjects(setup,database){
 need(/^collect_current16_integration_[a-f0-9]{24}_test$/.test(database),'EXACT_CURRENT16_DATABASE_NAME_REQUIRED');
 await setup.query(`DO $owner$ DECLARE r record;BEGIN
  IF current_user<>'collect_test' OR session_user<>'collect_test' OR current_database()<>'${database}' OR host(inet_server_addr())<>'127.0.0.1' THEN RAISE EXCEPTION 'OWNED_CURRENT16_PROFILE_REQUIRED';END IF;
  FOR r IN SELECT nspname FROM pg_namespace WHERE nspowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND nspname NOT LIKE 'pg_%' AND nspname<>'information_schema' LOOP EXECUTE format('ALTER SCHEMA %I OWNER TO postgres',r.nspname);END LOOP;
  FOR r IN SELECT c.oid::regclass object,c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND c.relkind IN('r','p','v','m','f') LOOP EXECUTE format('ALTER %s %s OWNER TO postgres',CASE r.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END,r.object);END LOOP;
  FOR r IN SELECT c.oid::regclass object FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND c.relkind='S' LOOP EXECUTE format('ALTER SEQUENCE %s OWNER TO postgres',r.object);END LOOP;
  FOR r IN SELECT p.oid::regprocedure object FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE p.proowner=(SELECT oid FROM pg_roles WHERE rolname='collect_test') AND n.nspname NOT LIKE 'pg_%' AND n.nspname<>'information_schema' AND p.prokind='f' LOOP EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',r.object);END LOOP;
 END;$owner$;`);
}

export async function qualifyCurrent16(env=process.env,argv=process.argv){
 process.umask(0o077);let config,output,stage='preflight',failure=null,database=null,receipt=null,child=null,privateSpecRemoved=false;const clients=[];
 let poisoned=false,inputs;
 const save=(name,value)=>writeExclusive(join(output,name),value);
 try{
  config=validateCurrent16Invocation({argv,env});await admitCurrent16Output(config.output);
  need(await realpath(CURRENT16_ROOT)===CURRENT16_ROOT&&await realpath(config.deno)===config.deno,'PHYSICAL_CURRENT16_EXECUTABLE_REQUIRED');
  const fixture=await loadReviewedPlatformFixture(CURRENT16_ROOT,{includeStoppedAdmissionLifecycleMigration:true});
  need(JSON.stringify(fixture.diskNames)===JSON.stringify(EXACT_CURRENT16)&&fixture.clientDiagnostics&&fixture.notificationDelivery,'EXACT_CURRENT16_CHAIN_REQUIRED');
  const files=await current16Sources();await verifyCurrent16Sources(files);await fixture.parity();
  const version=await promisify(execFile)(config.deno,['--version'],{timeout:5000,maxBuffer:2048});need(/^deno 2\.9\.6\s/m.test(version.stdout),'PINNED_DENO_2_9_6_REQUIRED');
  const head=(await promisify(execFile)('git',['rev-parse','HEAD'],{cwd:CURRENT16_ROOT,timeout:5000,maxBuffer:256})).stdout.trim();need(/^[a-f0-9]{40}$/.test(head)&&(!env.GITHUB_SHA||head===env.GITHUB_SHA),'CURRENT16_SOURCE_COMMIT_REQUIRED');
  const require=createRequire(import.meta.url),{Client}=require(config.module);need(require(join(dirname(require.resolve(config.module)),'../package.json')).version==='8.16.3','PINNED_PG_DRIVER_REQUIRED');
  await mkdir(config.output,{mode:0o700});output=config.output;
  const sourceSha=sha(JSON.stringify(files));inputs={format:'collect.current16.inputs.v1',source_commit:head,source_sha256:sourceSha,files,
   deno:{version:'2.9.6',sha256:sha(await readFile(config.deno))},migrations:[...fixture.rawMigrations,fixture.clientDiagnostics,fixture.notificationDelivery].map(({name,sha256})=>({name,sha256})),
   local_sql10:{hosted_sha256:fixture.binding.hosted_sql_sha256,applied_sha256:fixture.binding.synthetic_sql_sha256,metadata_literal_occurrences:2},
   source_scope:'Exact current working source bytes; git HEAD alone is not the candidate identity. No production approval is created.'};
  await save('INPUTS.json',inputs);
  const connect=async url=>{const c=new Client({connectionString:url,ssl:false,connectionTimeoutMillis:5000,statement_timeout:15000,lock_timeout:5000});c.on('error',()=>{poisoned=true;});clients.push(c);await c.connect();return c;};
  const parity=async()=>{need(!poisoned,'CURRENT16_CONNECTION_LOST');await verifyCurrent16Sources(files);await fixture.parity();};
  stage='cluster_identity';const admin=await connect(config.admin.href);
  const observed=(await admin.query("SELECT current_user AS owner,session_user AS session,current_database() AS database,host(inet_server_addr()) AS host,inet_server_port() AS port,current_setting('server_version_num') AS version,current_setting('default_transaction_isolation') AS isolation,(SELECT rolsuper AND rolbypassrls FROM pg_roles WHERE rolname=current_user) AS bootstrap,pg_get_userbyid((SELECT datdba FROM pg_database WHERE datname=current_database())) AS database_owner")).rows[0];
  need(observed.owner==='collect_test'&&observed.session==='collect_test'&&observed.database==='postgres'&&observed.host==='127.0.0.1'&&observed.port===Number(config.admin.port)&&observed.version==='170010'&&observed.isolation==='read committed'&&observed.bootstrap&&observed.database_owner==='collect_test','EXACT_CURRENT16_NATIVE_IDENTITY_REQUIRED');
  const beforeRole=(await admin.query(roleQuery)).rows[0],profile=current16OwnerProfile(beforeRole);
  let ownerBase;
  if(profile==='normal'){
   need(config.owner,'PREPARED_CURRENT16_OWNER_URL_REQUIRED');ownerBase=config.owner;
   const probe=await connect(ownerBase.href);const who=(await probe.query('SELECT current_user AS owner,session_user AS session')).rows[0];need(who.owner==='postgres'&&who.session==='postgres','ACTUAL_CURRENT16_OWNER_CONNECTION_REQUIRED');
  }else{
   need(!config.owner,'FRESH_CURRENT16_OWNER_URL_FORBIDDEN');
   const others=(await admin.query("SELECT count(*)::int AS n FROM pg_database WHERE datname NOT IN('postgres','template0','template1','collect_schema_test')")).rows[0].n;
   need(others===0,'FRESH_CURRENT16_CLUSTER_REQUIRED');
  }
  database='collect_current16_integration_'+randomBytes(12).toString('hex')+'_test';
  await save('CREATE-INTENT.json',{database,profile,observed,source_sha256:sourceSha,create_once:true,reset_or_drop:false,preserve_failed_fixture:true});
  need((await admin.query('SELECT count(*)::int AS n FROM pg_database WHERE datname=$1',[database])).rows[0].n===0,'FRESH_CURRENT16_DATABASE_REQUIRED');await parity();
  stage='create_database';await admin.query('CREATE DATABASE "'+database+'" OWNER collect_test TEMPLATE template0 ENCODING \'UTF8\'');
  const setupUrl=new URL(config.admin);setupUrl.pathname='/'+database;const setup=await connect(setupUrl.href);
  need((await setup.query("SELECT NOT EXISTS(SELECT 1 FROM pg_namespace WHERE nspname IN('app','private','api','auth','realtime')) AS empty,pg_get_userbyid((SELECT datdba FROM pg_database WHERE datname=current_database()))='collect_test' AS owned")).rows.every(row=>row.empty&&row.owned),'PRISTINE_CURRENT16_DATABASE_REQUIRED');
  stage='apply_exact_predecessors';
  if(profile==='normal')await applyPreparedPredecessors(setup,fixture);
  else{let withheld=0;await fixture.apply(async sql=>{if(sha(sql)===ROOT_SQL14_SHA256){withheld++;return;}await setup.query(sql);},{includeAuth:true});need(withheld===1,'SQL14_OWNER_APPLICATION_REQUIRED');}
  need((await setup.query("SELECT (SELECT count(*)::int FROM pg_tables WHERE schemaname='app') AS app,(SELECT count(*)::int FROM pg_tables WHERE schemaname='private') AS private,(SELECT count(*)::int FROM pg_trigger WHERE tgname='collect_fence_statement_v1' AND tgenabled='A' AND tgtype=62) AS guards,NOT EXISTS(SELECT 1 FROM private.collect_fence_control) AS uninitialized,(SELECT NOT enabled FROM private.member_realtime_control WHERE singleton) AS realtime_disabled")).rows.every(row=>row.app===97&&row.private===21&&row.guards===113&&row.uninitialized&&row.realtime_disabled),'EXACT_CURRENT13_PREDECESSOR_REQUIRED');
  stage='new_database_owner_profile';await transferNewDatabaseObjects(setup,database);await admin.query('ALTER DATABASE "'+database+'" OWNER TO postgres');
  if(profile!=='normal'){
   const password=randomBytes(24).toString('hex');await admin.query("ALTER ROLE postgres LOGIN NOSUPERUSER NOINHERIT CREATEROLE NOCREATEDB NOBYPASSRLS NOREPLICATION PASSWORD '"+password+"'");
   ownerBase=new URL(config.admin);ownerBase.username='postgres';ownerBase.password=password;
  }
  const ownerUrl=new URL(ownerBase);ownerUrl.pathname='/'+database;const owner=await connect(ownerUrl.href);
  need(current16OwnerProfile((await owner.query(roleQuery)).rows[0])==='normal','EXACT_CURRENT16_OWNER_PROFILE_REQUIRED');
  stage='apply_exact_sql14_15_16';await owner.query(fixture.stoppedAdmissionLifecycle.sql);await owner.query(fixture.clientDiagnostics.sql);await owner.query(fixture.notificationDelivery.sql);
  await owner.query('SELECT private.collect_fence_initialize($1,$2,$3)',[randomUUID(),sourceSha,BASELINE]);
  await parity();await save('PREPARATION.json',{format:'collect.current16.preparation.v1',database,owner_profile:'normal_non_superuser_no_bypassrls',initial_owner_profile:profile,postgres_login_profile_changed:profile!=='normal',original_role_membership_sql_executed:true,new_database_objects_only:true,source_sha256:sourceSha,applied_migrations:inputs.migrations,local_sql10:inputs.local_sql10,source_migration_files_edited:false,sql10_metadata_only_substitution:true,reset_or_drop:false,provider_calls:0});
  // Private transport state is removed after the child; public evidence contains
  // only native identity and source hashes, never connection credentials.
  const specPath=join(output,'RUN-SPEC.private.json'),inputPath=join(output,'INPUTS.json');
  const spec={format:'collect.current16.run-spec.v1',source:CURRENT16_ROOT,output,inputs:inputPath,inputs_sha256:sha(await readFile(inputPath)),source_sha256:sourceSha,url:ownerUrl.href};
  await save('RUN-SPEC.private.json',spec);
  for(const c of clients.splice(0))await c.end();need(!poisoned,'CURRENT16_CONNECTION_LOST');
  stage='native_runtime';
  const childEnv={NO_COLOR:'1'};for(const key of ['HOME','PATH','TMPDIR','LANG','LC_ALL','DENO_DIR','DENO_TLS_CA_STORE'])if(env[key]!==undefined)childEnv[key]=env[key];
  const args=['run','--check','--cached-only','--frozen','--node-modules-dir=none','--config='+join(CURRENT16_ROOT,'supabase/functions/deno.json'),'--lock='+join(CURRENT16_ROOT,'supabase/functions/deno.lock'),'--allow-env','--allow-read='+CURRENT16_ROOT+','+output,'--allow-write='+output,'--allow-net=127.0.0.1:'+ownerUrl.port,join(CURRENT16_ROOT,CURRENT16_RUNTIME),specPath,sha(await readFile(specPath))];
  child=await captureBoundedHistoryChild(config.deno,args,{cwd:CURRENT16_ROOT,env:childEnv});
  const redact=bytes=>bytes.toString('utf8').replaceAll(ownerUrl.href,'[LOCAL_SYNTHETIC_URL]').replaceAll(decodeURIComponent(ownerUrl.password),'[LOCAL_SYNTHETIC_PASSWORD]');
  for(const [name,bytes]of [['CHILD-STDOUT.log',child.stdout],['CHILD-STDERR.log',child.stderr]]){const file=await open(join(output,name),'wx',0o600);try{await file.writeFile(redact(bytes));await file.sync();}finally{await file.close();}}
  await save('CHILD-METADATA.json',child.metadata);
  need(child.metadata.code===0&&child.metadata.reaped&&!child.metadata.expired&&!child.metadata.overflow&&!child.metadata.spawn_error&&!child.metadata.cancelled,'CURRENT16_NATIVE_CHILD_UNCONFIRMED');
  receipt=validateCurrent16Receipt(JSON.parse(await readFile(join(output,'NATIVE-RESULT.json'),'utf8')));
  need(receipt.source_sha256===sourceSha,'CURRENT16_NATIVE_SOURCE_MISMATCH');await parity();stage='complete';
 }catch(error){failure={stage,code:error.qualificationCode??(typeof error.code==='string'&&/^[0-9A-Z]{5}$/.test(error.code)?'SQLSTATE_'+error.code:'CURRENT16_QUALIFICATION_UNCONFIRMED')};}
 finally{
  for(const c of clients)try{await c.end();}catch{failure??={stage:'cleanup',code:'CURRENT16_CONNECTION_CLOSE_UNCONFIRMED'};}
  if(output)try{privateSpecRemoved=await removeCurrent16PrivateSpec(join(output,'RUN-SPEC.private.json'));}catch{failure??={stage:'cleanup',code:'CURRENT16_PRIVATE_SPEC_CLEANUP_UNCONFIRMED'};}
 }
 const result={format:'collect.current16.qualification.v1',status:failure?'UNCONFIRMED':'PASS',failure,database,output:output??null,
  source_sha256:inputs?.source_sha256??null,receipt:failure?null:receipt,child:child?.metadata??null,private_spec_removed:privateSpecRemoved,preserve_database:true,reset_or_drop:false,automatic_retry:false,provider_calls:0,hosted_acceptance:false,legacy_sql_gates_closed:false};
 if(output)await save('RESULT.json',result);return result;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const result=await qualifyCurrent16();(result.status==='PASS'?console.log:console.error)(JSON.stringify(result));if(result.status!=='PASS')process.exitCode=1;
}
