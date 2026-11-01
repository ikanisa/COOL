// Automatic current-candidate qualification on one explicitly owned PG17
// cluster. Each substantive harness gets a new original16 clone and installs
// all reviewed additions. No historical packet is relabeled, reused or reset.
import {readFile,readdir,realpath,lstat,mkdir,writeFile} from 'node:fs/promises';
import {resolve,join,dirname,isAbsolute} from 'node:path';
import {createHash,randomBytes,randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {spawn} from 'node:child_process';
import {prepareSelfHostedFixture} from './self-hosted-fixture.mjs';
import {CURRENT_NATIVE_PROFILE,CURRENT_MIGRATION_NAMES,CURRENT_MIGRATION_COUNT,reviewedCurrentMigrations} from './self-hosted-current-schema.mjs';
import {qualify as qualifyInstallation} from './self-hosted-integration.mjs';

const ROOT=resolve(import.meta.dirname,'../../..');
const {Client}=createRequire(import.meta.url)('pg');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const need=(ok,code)=>{if(!ok)throw Error(code);};
const baseline='dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3';
const physical=value=>typeof value==='string'&&isAbsolute(value)&&resolve(value)===value&&!/[\x00-\x1f\x7f]/.test(value);
export const CURRENT_HARNESSES=Object.freeze([
 {name:'control',purpose:'backend',entry:'scripts/supabase/testing/self-hosted-control-concurrency.ts',env:'COLLECT_CONTROL_FIXTURE_DESCRIPTOR',cases:8},
 {name:'runtime',purpose:'backend',entry:'scripts/supabase/testing/self-hosted-runtime.ts',env:'COLLECT_RUNTIME_FIXTURE_DESCRIPTOR',cases:16},
 {name:'backend',purpose:'backend',entry:'scripts/supabase/testing/self-hosted-backend-runtime.ts',env:'COLLECT_SELFHOST_BACKEND_FIXTURE_DESCRIPTOR',cases:10},
 {name:'auth',purpose:'auth',entry:'scripts/supabase/testing/self-hosted-auth-runtime.ts',env:'COLLECT_GUEST_FIXTURE_DESCRIPTOR',cases:10},
 {name:'retention',purpose:'recovery',entry:'scripts/supabase/testing/self-hosted-retention-runtime.ts',env:'COLLECT_SELFHOST_RETENTION_FIXTURE_DESCRIPTOR',cases:15},
 {name:'notifications',purpose:'notifications',entry:'scripts/supabase/testing/notification-channels.ts',env:'COLLECT_NOTIFICATION_FIXTURE_FILE',cases:9},
 {name:'gateway',purpose:'gateway',entry:'deploy/collect-sms/test/gateway.test.ts',env:'COLLECT_SMS_FIXTURE_FILE',cases:34},
 {name:'data_stage',purpose:'backend',runtime:'node',entry:'scripts/supabase/testing/self-hosted-data-stage.mjs',env:'COLLECT_DATA_STAGE_FIXTURE_DESCRIPTOR',cases:5},
]);

export function validateCurrentInvocation(env,nodeVersion=process.versions.node){
 need(/^24\./.test(nodeVersion),'NODE24_REQUIRED');
 need(env.COLLECT_CI_SYNTHETIC==='true','EXPLICIT_SYNTHETIC_CI_REQUIRED');
 need(physical(env.COLLECT_SELFHOST_OUTPUT_DIR)&&physical(env.COLLECT_DENO),'PHYSICAL_CURRENT_PATHS_REQUIRED');
 const local=env.COLLECT_SELFHOST_LOCAL_CLUSTER_DESCRIPTOR;
 if(local)need(physical(local),'PHYSICAL_LOCAL_CLUSTER_DESCRIPTOR_REQUIRED');
 else{
  const target=new URL(env.COLLECT_FENCE_ADMIN_DATABASE_URL);
  need(target.protocol==='postgres:'&&target.hostname==='127.0.0.1'&&target.port==='55439'&&target.username==='collect_test'&&target.password==='collect_local_fixture_only'&&target.pathname==='/postgres'&&!target.search&&!target.hash,'EXACT_CI_BOOTSTRAP_REQUIRED');
 }
 return {output:env.COLLECT_SELFHOST_OUTPUT_DIR,deno:env.COLLECT_DENO,local:local??null};
}

async function exclusive(path,value){await writeFile(path,JSON.stringify(value,null,2)+'\n',{flag:'wx',mode:0o600});}
export async function currentSourceSnapshot(){
 const roots=['supabase/functions','supabase/migrations','supabase/jobs','supabase/retention-inventory.json',
  'scripts/supabase','scripts/self_hosted','deploy/collect-sms','deploy/self-hosted',
  'lib/shared/models','lib/core/data/exact_json_values.dart','lib/shared/repositories/collect_repository_live_reader.dart',
  'test/self_hosted_member_history_sql_receipts_test.dart','.github/workflows/supabase.yml','.fvmrc','pubspec.yaml','pubspec.lock'];
 const files=[];
 async function visit(role){
  const path=join(ROOT,role),info=await lstat(path);need(!info.isSymbolicLink()&&await realpath(path)===path,'PHYSICAL_CURRENT_SOURCE_REQUIRED');
  if(info.isDirectory()){
   for(const item of(await readdir(path)).sort())if(!['node_modules','.git','.temp','__pycache__','.DS_Store'].includes(item)&&!item.startsWith('._'))await visit(role+'/'+item);
  }else{need(info.isFile()&&info.size<=16*1024*1024,'BOUNDED_CURRENT_SOURCE_REQUIRED');const bytes=await readFile(path);files.push({role,bytes:bytes.length,sha256:sha(bytes)});}
 }
 for(const role of roots)await visit(role);
 files.sort((a,b)=>a.role.localeCompare(b.role));need(files.length<4096,'BOUNDED_CURRENT_SOURCE_INVENTORY_REQUIRED');
 return {format:'collect.selfhost.current-native.inputs.v1',profile:CURRENT_NATIVE_PROFILE,files,source_sha256:sha(JSON.stringify(files)),
  migrations:(await reviewedCurrentMigrations()).map(({name,sha256})=>({name,sha256})),historical_current14_or_current16_acceptance:false};
}

async function boundedChild(executable,argv,env,{deadlineMs=240000}={}){
 const child=spawn(executable,argv,{cwd:ROOT,env,shell:false,stdio:['ignore','pipe','pipe']});
 const stdout=[],stderr=[];let outBytes=0,errBytes=0,expired=false,overflow=false,cancelled=false,spawnError=false,kill;
 const stop=()=>{child.kill('SIGTERM');kill??=setTimeout(()=>child.kill('SIGKILL'),5000);};
 const cancel=()=>{cancelled=true;stop();};process.on('SIGTERM',cancel);process.on('SIGINT',cancel);
 const timer=setTimeout(()=>{expired=true;stop();},deadlineMs);
 child.stdout.on('data',bytes=>{outBytes+=bytes.length;if(outBytes<=1024*1024)stdout.push(bytes);else{overflow=true;stop();}});
 child.stderr.on('data',bytes=>{errBytes+=bytes.length;if(errBytes<=1024*1024)stderr.push(bytes);else{overflow=true;stop();}});
 child.on('error',()=>{spawnError=true;stop();});
 const exit=await new Promise(done=>child.once('close',(code,signal)=>done({code,signal})));
 clearTimeout(timer);clearTimeout(kill);process.off('SIGTERM',cancel);process.off('SIGINT',cancel);
 return {stdout:Buffer.concat(stdout),stderr:Buffer.concat(stderr),metadata:{...exit,expired,overflow,cancelled,spawn_error:spawnError,reaped:true,
  stdout_bytes:outBytes,stderr_bytes:errBytes,stdout_sha256:sha(Buffer.concat(stdout)),stderr_sha256:sha(Buffer.concat(stderr))}};
}

export function validateHarnessReceipt(name,value){
 need(value&&typeof value==='object','NATIVE_RECEIPT_REQUIRED');
 if(name==='backend')need(value.format==='collect.selfhost.backend.native.v2'&&value.status==='PASS'&&value.cases.length===10&&value.external_calls===0&&value.production_acceptance===false,'CURRENT_BACKEND_RECEIPT_REQUIRED');
 else if(name==='auth')need(value.format==='collect.selfhost.auth.native.v2'&&value.status==='pass'&&value.passed.length===10&&value.realProviderCalls===0&&value.syntheticProviderCalls>=6&&value.productionAcceptance===false,'CURRENT_AUTH_RECEIPT_REQUIRED');
 else if(name==='retention')need(value.contract==='collect.selfhost.retention.native.v2'&&value.passed===true&&value.scenarios.length===15&&value.external_calls===0&&value.production_acceptance===false,'CURRENT_RETENTION_RECEIPT_REQUIRED');
 else if(name==='notifications')need(value.format==='collect.selfhost.notifications.native.v2'&&value.status==='PASS'&&value.cases===9&&value.external_provider_calls===0&&value.synthetic_email_and_opensms_transports===true&&value.production_acceptance===false,'CURRENT_NOTIFICATION_RECEIPT_REQUIRED');
 else if(name==='control')need(value.format==='collect.selfhost.control.native.v1'&&value.state==='PASS_CURRENT_BOUNDED_CONTROL_NATIVE'&&value.receipts.length===8&&value.provider_calls===0&&value.production_capacity_closed===false,'CURRENT_CONTROL_RECEIPT_REQUIRED');
 else if(name==='runtime')need(value.format==='collect.selfhost.runtime.native.v1'&&value.status==='PASS'&&value.cases===16&&value.normal_owner===true&&value.normal_runtime===true&&value.external_provider_calls===0&&value.synthetic_provider_calls>=4&&value.financial_posting_acceptance===false&&value.hosted_acceptance===false,'CURRENT_RUNTIME_RECEIPT_REQUIRED');
 else if(name==='data_stage')need(value.format==='collect.selfhost.data-stage.native.v1'&&value.status==='PASS'&&value.cases.length===5&&value.provider_calls===0&&value.observed.actual_postgres===true&&value.observed.actual_sqlite===true&&value.current_first_import_supported===false&&value.historical_positive_import_acceptance===false&&value.production_acceptance===false,'CURRENT_DATA_STAGE_RECEIPT_REQUIRED');
 else need(false,'UNKNOWN_CURRENT_HARNESS');
 const schema=value.current_schema??value.observed?.current_schema;
 need(schema?.profile===CURRENT_NATIVE_PROFILE&&schema.migration_count===CURRENT_MIGRATION_COUNT&&
  JSON.stringify(schema.migrations?.map(row=>row.name))===JSON.stringify(CURRENT_MIGRATION_NAMES)&&
  schema.migrations.every(row=>/^[a-f0-9]{64}$/.test(row.sha256))&&schema.production_acceptance===false,'COMPLETE_CURRENT_NATIVE_SCHEMA_REQUIRED');
 return value;
}

export async function qualifyCurrentSelfHosted(env=process.env){
 const config=validateCurrentInvocation(env);process.umask(0o077);
 need(await realpath(config.deno)===config.deno&&await realpath(dirname(config.output))===dirname(config.output),'PHYSICAL_CURRENT_INPUTS_REQUIRED');
 try{await lstat(config.output);need(false,'FRESH_CURRENT_OUTPUT_REQUIRED');}catch(error){if(error.code!=='ENOENT')throw error;}
 await mkdir(config.output,{mode:0o700});const privateDir=join(config.output,'private');await mkdir(privateDir,{mode:0o700});
 const source=await currentSourceSnapshot();await exclusive(join(config.output,'INPUTS.json'),source);
 const parity=async()=>need(JSON.stringify(await currentSourceSnapshot())===JSON.stringify(source),'CURRENT_NATIVE_SOURCE_CHANGED');
 const clusterFile=join(privateDir,'collect-integration-pg.private.json'),templateFile=join(privateDir,'collect-integration-fixture.private.json');
 let cluster={url:env.COLLECT_FENCE_ADMIN_DATABASE_URL};
 if(config.local){const info=await lstat(config.local);need(info.isFile()&&!info.isSymbolicLink()&&(info.mode&0o777)===0o600,'PRIVATE_OWNED_CLUSTER_DESCRIPTOR_REQUIRED');cluster=JSON.parse(await readFile(config.local,'utf8'));const url=new URL(cluster.url);need(url.protocol==='postgres:'&&url.hostname==='127.0.0.1'&&url.port==='55446'&&url.username==='collect_test'&&url.password&&url.pathname==='/postgres'&&!url.search&&!url.hash,'EXACT_LOCAL_CURRENT_CLUSTER_REQUIRED');}
 await exclusive(clusterFile,{url:cluster.url});
 const target=new URL(cluster.url),admin=new Client({connectionString:cluster.url,connectionTimeoutMillis:5000,statement_timeout:60000});
 const results=[];let fatal=null,template,descriptors=new Map();
 try{
  await admin.connect();const identity=(await admin.query("SELECT current_user,session_user,host(inet_server_addr()) AS host,inet_server_port() AS port,current_setting('server_version_num')::int/10000 AS major,current_setting('max_connections')::int AS max,current_setting('superuser_reserved_connections')::int AS super_reserved,current_setting('reserved_connections')::int AS reserved,(SELECT rolsuper AND rolbypassrls FROM pg_roles WHERE rolname=current_user) AS bootstrap")).rows[0];
  need(identity.current_user==='collect_test'&&identity.session_user==='collect_test'&&identity.host==='127.0.0.1'&&identity.port===Number(target.port)&&identity.major===17&&identity.bootstrap&&identity.max===60&&identity.super_reserved===3&&identity.reserved===0,'OWNED_FRESH_CURRENT_PG17_60_3_0_REQUIRED');
  need((await admin.query("SELECT count(*)::int AS n FROM pg_database WHERE datname NOT IN('postgres','template0','template1','collect_schema_test')")).rows[0].n===0&&(await admin.query("SELECT count(*)::int AS n FROM pg_roles WHERE rolname='postgres'")).rows[0].n===0,'FRESH_CURRENT_CLUSTER_REQUIRED');
  await exclusive(join(config.output,'CLUSTER.json'),{identity,provider_calls:0,synthetic:true});
  await prepareSelfHostedFixture({adminUrl:cluster.url,purpose:'integration',output:templateFile,initialize:false});
  template=JSON.parse(await readFile(templateFile,'utf8'));
  // Clone every schema before installing any addition. Shared-role creation
  // cannot silently change the historical template's reviewed SQL10 metadata.
  for(const harness of CURRENT_HARNESSES){
   const database='collect_selfhost_'+harness.purpose+'_'+randomBytes(12).toString('hex')+'_test';
   await admin.query('CREATE DATABASE "'+database+'" TEMPLATE "'+template.database+'" OWNER postgres');
   const url=new URL(template.url);url.pathname='/'+database;
   const owner=new Client({connectionString:url.href,connectionTimeoutMillis:5000,statement_timeout:60000});await owner.connect();
   try{await owner.query('SELECT private.collect_fence_initialize($1,$2,$3)',[randomUUID(),template.source_sha256,baseline]);}finally{await owner.end();}
   const restricted={};
   if(harness.name==='control'){
    const login='collect_control_'+randomBytes(6).toString('hex'),password=randomBytes(24).toString('hex');
    await admin.query('CREATE ROLE "'+login+'" LOGIN NOINHERIT NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD \''+password+'\'');
    await admin.query('GRANT collect_runtime TO "'+login+'" WITH INHERIT FALSE, SET TRUE, ADMIN FALSE');
    const runtime=new URL(url);runtime.username=login;runtime.password=password;restricted.control_runtime_url=runtime.href;
   }
   const file=join(privateDir,'collect-'+(harness.name==='notifications'?'notifications':harness.name==='gateway'?'gateway':harness.name)+'-fixture.private.json');
   await exclusive(file,{...template,url:url.href,database,purpose:harness.purpose,controller_initialized:true,...restricted});descriptors.set(harness.name,file);
  }
  // This read-only monitoring grant is confined to the new synthetic cluster.
  // It lets the normal owner observe actual child-runtime socket states.
  await admin.query('GRANT pg_read_all_stats TO postgres WITH INHERIT TRUE, SET FALSE, ADMIN FALSE');
  await admin.end();
  await parity();
  const installation=await qualifyInstallation({clusterFile,templateFile,output:join(config.output,'INSTALLATION.json'),runtimeDescriptor:join(privateDir,'runtime.private.json')});
  need(installation.status==='pass'&&installation.migrations===CURRENT_MIGRATION_COUNT,'CURRENT_INSTALLATION_UNCONFIRMED');results.push({name:'installation',status:'PASS',cases:installation.cases});
  const childBase={COLLECT_CI_SYNTHETIC:'true',COLLECT_SELFHOST_NATIVE_PROFILE:CURRENT_NATIVE_PROFILE,DENO_NO_UPDATE_CHECK:'1',NO_COLOR:'1'};
  for(const key of ['HOME','PATH','TMPDIR','LANG','LC_ALL','DENO_DIR','DENO_TLS_CA_STORE'])if(env[key]!==undefined)childBase[key]=env[key];
  const redactions=[...descriptors.values()].map(async file=>{const value=JSON.parse(await readFile(file,'utf8'));return [value.url,...(value.control_runtime_url?[value.control_runtime_url]:[])];});
  const secrets=(await Promise.all(redactions)).flat();secrets.push(cluster.url,template.url);
  const redact=bytes=>{let text=bytes.toString('utf8');for(const value of secrets){text=text.replaceAll(value,'[OWNED_SYNTHETIC_DATABASE]');text=text.replaceAll(decodeURIComponent(new URL(value).password),'[OWNED_SYNTHETIC_PASSWORD]');}return text;};
  for(const harness of CURRENT_HARNESSES){
   await parity();const childEnv={...childBase,[harness.env]:descriptors.get(harness.name)};
   if(harness.name==='backend')childEnv.COLLECT_SELFHOST_HISTORY_OUTPUT_DIR=join(config.output,'history');
   if(harness.name==='runtime'){childEnv.COLLECT_RUNTIME_OUTPUT_DIR=join(config.output,'runtime');await mkdir(childEnv.COLLECT_RUNTIME_OUTPUT_DIR,{mode:0o700});}
   if(harness.name==='data_stage')childEnv.COLLECT_DATA_STAGE_OUTPUT_DIR=join(config.output,'data-stage');
   const argv=harness.runtime==='node'?[]:[harness.name==='gateway'?'test':'run','--check','--cached-only','--frozen','--node-modules-dir=none','--config='+join(ROOT,'supabase/functions/deno.json'),'--lock='+join(ROOT,'supabase/functions/deno.lock'),
    '--allow-env','--allow-read='+ROOT+','+config.output,'--allow-write='+config.output,'--allow-net=127.0.0.1:'+target.port];
   if(harness.name==='gateway')argv.push('--junit-path='+join(config.output,'GATEWAY.xml'));
   argv.push(harness.entry);
   const child=await boundedChild(harness.runtime==='node'?process.execPath:config.deno,argv,childEnv);
   await exclusive(join(config.output,harness.name.toUpperCase()+'-CHILD.json'),child.metadata);
   await writeFile(join(config.output,harness.name.toUpperCase()+'.log'),redact(child.stdout)+'\n'+redact(child.stderr),{flag:'wx',mode:0o600});
   let success=false,receipt;
   try{
    need(child.metadata.code===0&&!child.metadata.expired&&!child.metadata.overflow&&!child.metadata.cancelled&&!child.metadata.spawn_error,'CURRENT_NATIVE_CHILD_UNCONFIRMED');
    if(harness.name==='gateway'){
     const xml=await readFile(join(config.output,'GATEWAY.xml'),'utf8');
     need(!/<(?:failure|error|skipped)\b/.test(xml)&&(xml.match(/<testcase\b/g)??[]).length===34,'ALL_CURRENT_GATEWAY_CASES_REQUIRED');
     receipt={format:'collect.selfhost.gateway.native.v1',status:'PASS',cases:34,migration_count:CURRENT_MIGRATION_COUNT,profile:CURRENT_NATIVE_PROFILE,provider_calls:0,
      synthetic_phone_fcm_and_http:true,production_acceptance:false,junit_sha256:sha(xml)};
    }else{
     const text=child.stdout.toString('utf8').trim();receipt=JSON.parse(harness.name==='notifications'?text.split('\n').at(-1):text);
     validateHarnessReceipt(harness.name,receipt);
     need(JSON.stringify((receipt.current_schema??receipt.observed.current_schema).migrations)===JSON.stringify(source.migrations),'CURRENT_HARNESS_MIGRATION_IDENTITY_CHANGED');
    }
    await exclusive(join(config.output,harness.name.toUpperCase()+'.json'),receipt);success=true;
   }catch(error){results.push({name:harness.name,status:'FAIL',code:/^[A-Z0-9_]+$/.test(error.message)?error.message:'CURRENT_RECEIPT_UNCONFIRMED'});}
   if(success)results.push({name:harness.name,status:'PASS',cases:harness.cases});
   console.log(JSON.stringify(results.at(-1)));await parity();
  }
  // The dual-lane scheduler proof uses real deployment identity and normal SQL
  // ownership. Cron, Vault and pg_net remain explicitly synthetic interfaces.
  const manifestChild=await boundedChild('python3',['-c','import json;from scripts.self_hosted.prepare import source_manifest;print(json.dumps(source_manifest()))'],childBase,{deadlineMs:30000});
  need(manifestChild.metadata.code===0,'SCHEDULER_SOURCE_MANIFEST_UNCONFIRMED');
  const sourceManifest=JSON.parse(manifestChild.stdout.toString('utf8'));
  const cache=join(ROOT,'.cache');await mkdir(cache,{recursive:true});need(await realpath(cache)===cache,'PHYSICAL_CURRENT_CACHE_REQUIRED');
  const manifestFile=join(cache,'collect-current-ci-source-'+randomUUID()+'.json');await exclusive(manifestFile,sourceManifest);
  const schedulerEnv={...childBase,COLLECT_INTEGRATION_FIXTURE_FILE:templateFile,COLLECT_INTEGRATION_CLUSTER_FILE:clusterFile,
   COLLECT_COMBINED_SOURCE_MANIFEST:manifestFile,COLLECT_COMBINED_OUTPUT_DIR:join(config.output,'scheduler')};
  const scheduler=await boundedChild(config.deno,['run','--check','--cached-only','--frozen','--node-modules-dir=none','--config='+join(ROOT,'supabase/functions/deno.json'),'--lock='+join(ROOT,'supabase/functions/deno.lock'),
   '--allow-env','--allow-sys=uid','--allow-read='+ROOT+','+config.output,'--allow-write='+config.output,'--allow-run=python3','--allow-net=127.0.0.1:'+target.port,'scripts/supabase/testing/combined-self-hosted-scheduler.ts'],schedulerEnv);
  await exclusive(join(config.output,'SCHEDULER-CHILD.json'),scheduler.metadata);
  await writeFile(join(config.output,'SCHEDULER.log'),redact(scheduler.stdout)+'\n'+redact(scheduler.stderr),{flag:'wx',mode:0o600});
  const schedulerFiles=await readdir(join(config.output,'scheduler')).catch(()=>[]);
  let schedulerPassed=false;
  if(schedulerFiles.length===1&&/^[a-f0-9-]{36}\.json$/.test(schedulerFiles[0])){
   const report=JSON.parse(await readFile(join(config.output,'scheduler',schedulerFiles[0]),'utf8'));
   await exclusive(join(config.output,'SCHEDULER.json'),JSON.parse(redact(Buffer.from(JSON.stringify(report)))));
   schedulerPassed=scheduler.metadata.code===0&&!scheduler.metadata.expired&&!scheduler.metadata.overflow&&!scheduler.metadata.cancelled&&!scheduler.metadata.spawn_error&&
    report.format==='collect.selfhost.combined-scheduler-native.v1'&&report.status==='pass'&&report.passed===24&&report.failed===0&&report.real_database_identity===true&&report.profile_assertion_double===false&&report.provider_calls===0&&report.production_acceptance===false&&report.source_sha256===sourceManifest.sha256;
  }
  results.push({name:'scheduler',status:schedulerPassed?'PASS':'FAIL',cases:24});console.log(JSON.stringify(results.at(-1)));await parity();
  // Separate gateway admission qualification uses actual immutable deployment
  // identity and a dedicated SMS-only login. Protocol tests alone cannot prove
  // source/epoch fencing, drain or uncertain external-effect preservation.
  const gatewayFenceEnv={...childBase,COLLECT_INTEGRATION_FIXTURE_FILE:templateFile,COLLECT_INTEGRATION_CLUSTER_FILE:clusterFile,
   COLLECT_GATEWAY_FENCE_SOURCE_MANIFEST:manifestFile,COLLECT_GATEWAY_FENCE_OUTPUT_DIR:join(config.output,'gateway-fence')};
  const gatewayFence=await boundedChild(config.deno,['run','--check','--cached-only','--frozen','--node-modules-dir=none','--config='+join(ROOT,'supabase/functions/deno.json'),'--lock='+join(ROOT,'supabase/functions/deno.lock'),
   '--allow-env','--allow-sys=uid','--allow-read='+ROOT+','+config.output,'--allow-write='+config.output,'--allow-net=127.0.0.1:'+target.port,'scripts/supabase/testing/gateway-fence.ts'],gatewayFenceEnv);
  await exclusive(join(config.output,'GATEWAY-FENCE-CHILD.json'),gatewayFence.metadata);
  await writeFile(join(config.output,'GATEWAY-FENCE.log'),redact(gatewayFence.stdout)+'\n'+redact(gatewayFence.stderr),{flag:'wx',mode:0o600});
  const gatewayFenceFiles=await readdir(join(config.output,'gateway-fence')).catch(()=>[]);
  let gatewayFencePassed=false;
  if(gatewayFenceFiles.length===1&&/^[a-f0-9-]{36}\.json$/.test(gatewayFenceFiles[0])){
   const report=JSON.parse(await readFile(join(config.output,'gateway-fence',gatewayFenceFiles[0]),'utf8'));
   await exclusive(join(config.output,'GATEWAY-FENCE.json'),JSON.parse(redact(Buffer.from(JSON.stringify(report)))));
   gatewayFencePassed=gatewayFence.metadata.code===0&&!gatewayFence.metadata.expired&&!gatewayFence.metadata.overflow&&!gatewayFence.metadata.cancelled&&!gatewayFence.metadata.spawn_error&&
    report.format==='collect.gateway.fence-native.v1'&&report.status==='pass'&&report.passed===14&&report.failed===0&&
    report.migration_count===CURRENT_MIGRATION_COUNT&&report.original_migrations===16&&report.normal_owner===true&&
    report.real_database_identity===true&&report.profile_assertion_double===false&&report.provider_calls===0&&report.synthetic_provider_attempts===3&&
    report.production_acceptance===false&&report.physical_send_settlement===false&&report.source_sha256===sourceManifest.sha256&&
    JSON.stringify(report.current_migrations)===JSON.stringify(source.migrations.slice(16))&&JSON.stringify(report.source_drift)==='[]';
  }
  results.push({name:'gateway_fence',status:gatewayFencePassed?'PASS':'FAIL',cases:14});console.log(JSON.stringify(results.at(-1)));await parity();
 }catch(error){fatal=/^[A-Z0-9_]+$/.test(error.message)?error.message:'CURRENT_NATIVE_QUALIFICATION_UNCONFIRMED';}
 finally{try{await admin.end();}catch{}}
 try{await parity();}catch{fatal='CURRENT_NATIVE_SOURCE_CHANGED';}
 const result={format:'collect.selfhost.current-native.result.v1',status:!fatal&&results.length===11&&results.every(row=>row.status==='PASS')?'PASS':'FAIL',profile:CURRENT_NATIVE_PROFILE,source_sha256:source.source_sha256,
  migration_count:CURRENT_MIGRATION_COUNT,original16_preserved:true,results,fatal,synthetic_auth:true,synthetic_provider_boundaries:true,actual_postgres:true,
  provider_calls:0,hosted_acceptance:false,native_extensions_acceptance:false,production_acceptance:false,historical_current14_or_current16_acceptance:false,fixtures_preserved:true};
 await exclusive(join(config.output,'RESULT.json'),result);return result;
}
if(process.argv[1]&&resolve(process.argv[1])===new URL(import.meta.url).pathname){
 try{need(process.argv.length===2,'NO_CURRENT_NATIVE_ARGUMENTS_ALLOWED');const result=await qualifyCurrentSelfHosted();console.log(JSON.stringify(result));process.exitCode=result.status==='PASS'?0:1;}
 catch(error){console.error(JSON.stringify({status:'FAIL',code:/^[A-Z0-9_]+$/.test(error.message)?error.message:'CURRENT_NATIVE_PREFLIGHT_UNCONFIRMED'}));process.exitCode=1;}
}
