// Explicit operator action only. The fresh signing key stays in memory, Vault
// and Supabase Edge secrets; it is never emitted to logs or evidence files.
import {randomBytes,randomUUID} from 'node:crypto';
import {lstatSync,readFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {connect,management,record,ROOT,PROJECT,sha} from './access.mjs';
import {managedJobsHandlerFiles,renderManagedJobsHandler} from './managed-jobs-handler-patch.mjs';
import {renderManagedScheduler} from './managed-jobs-scheduler.mjs';
import {readAncillaryRegistration,requireSameRegistration,scopedInventory,evidenceCore} from './ancillary-inventory.mjs';

const KEY='collect_job_signing_key_v1',MODE='supabase_dispatch_hmac_v1',HASH=/^[a-f0-9]{64}$/,UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const SCHEDULE_FILE='20261117135049_collect_sms_schedule_one_minute.sql',SCHEDULE_SHA='df5ff3ec33e8e8d02c182072abd99e0c24705fb74f1f85514b46f9da9149300c';
const slugs=['collect-api','admin-api','collect-jobs'];
export function qualifiedSchedule(historyDigest,fileDigest){
 if(historyDigest===undefined)return '*/5 * * * *';
 if(historyDigest!==SCHEDULE_SHA||fileDigest!==SCHEDULE_SHA)throw Error('scheduler_migration_changed');
 return '* * * * *';
}
function privateJson(name){
 if(!/^[a-z0-9_.-]+\.json$/.test(name))throw Error('invalid_evidence_name');
 const p=join(ROOT,name),s=lstatSync(p);if(!s.isFile()||s.isSymbolicLink()||s.nlink!==1||s.uid!==process.getuid()||(s.mode&0o077)!==0||s.size>5*1024*1024)throw Error('private_evidence_required');
 return JSON.parse(readFileSync(p,'utf8'));
}
const summary=x=>({slug:x.slug,id:x.id,status:x.status,version:x.version,verify_jwt:x.verify_jwt,ezbr_sha256:x.ezbr_sha256});
export function keyEvidenceForSource(source){
 if(!HASH.test(source??''))throw Error('deployment_evidence_invalid');
 const original=privateJson('managed-jobs-key-complete.json');
 return original.sourceSha256===source?original:privateJson('managed-jobs-key-source-'+source+'.json');
}
export function sameDeployedFunctions(expected,current,registration=null){
 let expectedCore,currentCore;try{expectedCore=evidenceCore(expected,registration);currentCore=scopedInventory(current,registration).core;}catch{return false;}
 return slugs.every(slug=>{const a=expectedCore.filter(x=>x.slug===slug),b=currentCore.filter(x=>x.slug===slug);
  if(a.length!==1||b.length!==1)return false;const old=a[0],now=b[0];
  // Supabase secret updates create a new version of the unchanged bundle.
  // Bind executable identity and configuration, while rejecting rollbacks.
  return old.status==='ACTIVE'&&old.verify_jwt===false&&UUID.test(old.id??'')&&HASH.test(old.ezbr_sha256??'')&&
   Number.isSafeInteger(old.version)&&old.version>=1&&Number.isSafeInteger(now.version)&&now.version>=old.version&&
   JSON.stringify({...summary(old),version:now.version})===JSON.stringify(summary(now));
 });
}
export function verifyDeploymentEvidence({intent,deployment,currentFunctions,currentSource,handler,ancillaryRegistration=null}){
 const manifest=intent?.snapshot?.manifest,source=intent?.sourceSha256??intent?.snapshot?.sourceSha256;
 if(!HASH.test(source??'')||source!==currentSource||source!==deployment?.sourceSha256||!manifest||manifest.project!==PROJECT||
  sha(JSON.stringify(manifest))!==source||!Array.isArray(manifest.files)||!Array.isArray(deployment.functions)||!Array.isArray(currentFunctions))throw Error('deployment_evidence_invalid');
 const files=new Map();for(const f of manifest.files){if(files.has(f.path))throw Error('deployment_manifest_duplicate');files.set(f.path,f.sha256);}
 for(const [key,name] of Object.entries(managedJobsHandlerFiles)){
  const digest=handler?.hashes?.[key];
  if(!HASH.test(digest??'')||files.get('functions/_shared/'+name)!==digest)throw Error('managed_handler_not_deployed');
 }
 if(!sameDeployedFunctions(deployment.functions,currentFunctions,ancillaryRegistration))throw Error('deployed_function_changed');
 return source;
}
async function preflight(db,intent,deployment,{rebind=false}={}){
 const ancillaryRegistration=readAncillaryRegistration();
 const fence=(await db.query('SELECT mode,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
 if(fence?.mode!=='open')throw Error('open_qualified_runtime_required');
 const [f,s,h,scheduler]=await Promise.all([management('functions'),management('secrets'),renderManagedJobsHandler(),renderManagedScheduler()]);
 const source=verifyDeploymentEvidence({intent,deployment,currentFunctions:f.json(),currentSource:fence.source_sha256,handler:h,ancillaryRegistration});
 const secrets=new Map();for(const row of s.json()){if(secrets.has(row.name)||!HASH.test(row.value??''))throw Error('invalid_cloud_secret_metadata');secrets.set(row.name,row.value);}
 if(secrets.get('BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED')!==sha('false')||secrets.get('BUILD_SOURCE_ID')!==sha(source))throw Error('native_automation_must_remain_disabled');
 if(sha(readFileSync(new URL('../../../supabase/migrations/20261117073850_collect_managed_jobs_hmac.sql',import.meta.url)))!==scheduler.sqlSha)throw Error('scheduler_migration_changed');
 const exists=(await db.query("SELECT to_regclass('collect_ops.jobs_config') IS NOT NULL AS installed")).rows[0].installed;
 if(!exists)throw Error('inactive_scheduler_required');
 const scheduleHistory=(await db.query("SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') digest FROM supabase_migrations.schema_migrations WHERE version=$1",[SCHEDULE_FILE.slice(0,14)])).rows[0];
 const expectedSchedule=qualifiedSchedule(scheduleHistory?.digest,scheduleHistory?sha(readFileSync(new URL('../../../supabase/migrations/'+SCHEDULE_FILE,import.meta.url))):undefined);
 const status=(await db.query(`SELECT c.enabled,c.config_sha256,c.template_sha256,j.jobname,j.schedule,j.command,j.database,j.username,j.active,
  (SELECT count(*)::int FROM collect_ops.jobs_dispatches) AS dispatches,
  (SELECT count(*)::int FROM private.collect_managed_job_tickets) AS tickets,
  (SELECT count(*)::int FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed')) AS pending,
  (SELECT count(*)::int FROM vault.decrypted_secrets WHERE name=$1) AS vault_count,
  (SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') FROM supabase_migrations.schema_migrations WHERE version='20261117073850') AS migration_sha
  FROM collect_ops.jobs_config c JOIN cron.job j ON j.jobid=c.cron_job_id WHERE c.singleton`,[KEY])).rows[0];
 if(!status||status.enabled||status.active||status.config_sha256!==scheduler.configSha||status.template_sha256!==scheduler.templateSha||
  status.jobname!=='collect-jobs-maintenance-v1'||status.schedule!==expectedSchedule||status.command!=='SELECT collect_ops.tick_jobs();'||
  status.database!=='postgres'||status.username!=='postgres'||(rebind?status.pending!==0:status.dispatches!==0||status.tickets!==0)||status.migration_sha!==scheduler.sqlSha)throw Error('inactive_scheduler_identity_changed');
 requireSameRegistration(ancillaryRegistration,readAncillaryRegistration());
 // Key custody remains bound to the core; ancillary identities are qualified
 // independently by their digest-addressed registration.
 return {source,secrets,vaultCount:status.vault_count,functions:scopedInventory(f.json(),ancillaryRegistration).core,ancillaryRegistration};
}
export function requireKeyInventoryCheckpoint(pre,current,registration){
 requireSameRegistration(pre.ancillaryRegistration??null,registration);
 if(!sameDeployedFunctions(pre.functions,current,registration))throw Error('deployed_function_changed');
}
async function verifyKeyInventoryCheckpoint(pre){
 const registration=readAncillaryRegistration(),current=(await management('functions')).json();
 requireKeyInventoryCheckpoint(pre,current,registration);requireSameRegistration(registration,readAncillaryRegistration());
}
async function confirmSecrets(key){
 const metadata=(await management('secrets')).json(),map=new Map(metadata.map(x=>[x.name,x.value]));
 return map.get('COLLECT_JOB_SIGNING_KEY')===sha(key)&&map.get('COLLECT_JOB_AUTH_MODE')===sha(MODE)&&map.get('BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED')===sha('false');
}
async function main(){
 const [action,intentName,deploymentName]=process.argv.slice(2);
 if(!['--prepare-key','--recover-key','--bind-source'].includes(action)||!intentName||!deploymentName||process.argv.length!==5)throw Error('explicit_action_and_deployment_evidence_required');
 if(action!=='--bind-source'&&existsSync(join(ROOT,'managed-jobs-key-complete.json')))throw Error('key_already_qualified');
 const intent=privateJson(intentName),deployment=privateJson(deploymentName),db=await connect();
 try{
  const pre=await preflight(db,intent,deployment,{rebind:action==='--bind-source'});let key,operation,keySha,vaultId;
  await verifyKeyInventoryCheckpoint(pre);
  if(action==='--bind-source'){
   const original=privateJson('managed-jobs-key-complete.json');
   const rows=(await db.query("SELECT id,encode(sha256(convert_to(decrypted_secret,'UTF8')),'hex') digest,description FROM vault.decrypted_secrets WHERE name=$1",[KEY])).rows;
   if(pre.vaultCount!==1||rows.length!==1||rows[0].id!==original.vaultId||rows[0].digest!==original.keySha256||rows[0].description!=='collect.jobs.key.v1:'+original.operation||
    pre.secrets.get('COLLECT_JOB_SIGNING_KEY')!==original.keySha256||pre.secrets.get('COLLECT_JOB_AUTH_MODE')!==sha(MODE))throw Error('cloud_key_recovery_mismatch');
   await verifyKeyInventoryCheckpoint(pre);
   record('managed-jobs-key-source-'+pre.source+'.json',{...original,sourceSha256:pre.source,functions:pre.functions,at:new Date().toISOString(),sourceRevisionEvidence:deploymentName,keyChanged:false});
   console.log(JSON.stringify({status:'existing_key_bound_to_verified_source',sourceSha256:pre.source}));return;
  }
  if(action==='--prepare-key'){
   if(pre.vaultCount!==0||pre.secrets.has('COLLECT_JOB_SIGNING_KEY')||existsSync(join(ROOT,'managed-jobs-key-intent.json')))throw Error('existing_key_requires_reconciliation');
   key=randomBytes(32).toString('hex');keySha=sha(key);operation=randomUUID();
   record('managed-jobs-key-intent.json',{format:'collect.jobs.key.v1',project:PROJECT,sourceSha256:pre.source,operation,keySha256:keySha,at:new Date().toISOString()});
   await db.query('BEGIN');try{const row=(await db.query('SELECT vault.create_secret($1,$2,$3) AS id',[key,KEY,'collect.jobs.key.v1:'+operation])).rows[0];vaultId=row.id;
    const proof=(await db.query("SELECT count(*)::int n,min(id::text) id,min(encode(sha256(convert_to(decrypted_secret,'UTF8')),'hex')) digest FROM vault.decrypted_secrets WHERE name=$1",[KEY])).rows[0];
    if(proof.n!==1||proof.id!==vaultId||proof.digest!==keySha)throw Error('vault_key_readback_failed');await db.query('COMMIT');
   }catch(e){await db.query('ROLLBACK').catch(()=>{});throw e;}
  }else{
   const previous=privateJson('managed-jobs-key-intent.json');
   if(previous.format!=='collect.jobs.key.v1'||previous.project!==PROJECT||previous.sourceSha256!==pre.source||!HASH.test(previous.keySha256??'')||pre.vaultCount!==1)throw Error('key_recovery_identity_changed');
   const rows=(await db.query('SELECT id,decrypted_secret,description FROM vault.decrypted_secrets WHERE name=$1',[KEY])).rows;
   if(rows.length!==1||rows[0].description!=='collect.jobs.key.v1:'+previous.operation||!HASH.test(rows[0].decrypted_secret??'')||sha(rows[0].decrypted_secret)!==previous.keySha256)throw Error('vault_key_recovery_mismatch');
   ({decrypted_secret:key,id:vaultId}=rows[0]);operation=previous.operation;keySha=previous.keySha256;
   if(pre.secrets.has('COLLECT_JOB_SIGNING_KEY')&&pre.secrets.get('COLLECT_JOB_SIGNING_KEY')!==keySha)throw Error('cloud_key_recovery_mismatch');
  }
  if(!(await confirmSecrets(key))){
   try{await management('secrets',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify([
    {name:'COLLECT_JOB_SIGNING_KEY',value:key},{name:'COLLECT_JOB_AUTH_MODE',value:MODE}])});}catch{if(!(await confirmSecrets(key)))throw Error('secret_mutation_unconfirmed');}
  }
  if(!(await confirmSecrets(key)))throw Error('secret_readback_unconfirmed');
  await verifyKeyInventoryCheckpoint(pre);
  record('managed-jobs-key-complete.json',{format:'collect.jobs.key.v1',project:PROJECT,sourceSha256:pre.source,operation,vaultId,keySha256:keySha,functions:pre.functions,at:new Date().toISOString(),nativeAutomationEnabled:false});
  console.log(JSON.stringify({status:'signing_key_verified',project:PROJECT,sourceSha256:pre.source,nativeAutomationEnabled:false}));
 }finally{await db.end();}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main().catch(e=>{
 const safe=new Set(['explicit_action_and_deployment_evidence_required','key_already_qualified','open_qualified_runtime_required','deployment_evidence_invalid','deployment_manifest_duplicate','managed_handler_not_deployed','unexpected_deployed_function_set','deployed_function_changed','invalid_cloud_secret_metadata','native_automation_must_remain_disabled','inactive_scheduler_required','inactive_scheduler_identity_changed','scheduler_migration_changed','existing_key_requires_reconciliation','vault_key_readback_failed','key_recovery_identity_changed','vault_key_recovery_mismatch','cloud_key_recovery_mismatch','secret_mutation_unconfirmed','secret_readback_unconfirmed','invalid_evidence_name','private_evidence_required']);
 console.error(JSON.stringify({outcome:'unconfirmed',reason:safe.has(e.message)?e.message:'provider_or_database_unavailable',detail:'No secret values are emitted; reconcile the existing intent before any retry.'}));process.exitCode=1;});
