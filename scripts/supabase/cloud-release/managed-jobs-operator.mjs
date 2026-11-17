// Explicit, evidenced cloud actions. No action is taken merely by importing.
// A native probe can process one new SMS and one ledger candidate; imported
// history remains denied by the independently verified database guard.
import {randomUUID} from 'node:crypto';
import {lstatSync,readFileSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {connect,management,record,ROOT,PROJECT,sha} from './access.mjs';
import {validateReadiness} from '../jobs_config.mjs';
import {renderManagedScheduler} from './managed-jobs-scheduler.mjs';
import {sameDeployedFunctions,keyEvidenceForSource} from './managed-jobs-key-operator.mjs';
import {renderNativeProviderBudget} from './native-provider-budget-render.mjs';

const HASH=/^[a-f0-9]{64}$/,MODEL=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/;
const GUARDS={
 'private.collect_imported_native_source(text)':'3de5a1c984b9cf3d3e00f0ae8930a85b89cdc9f74f6e70c4744df96717ba2cde',
 'private.collect_imported_native_transaction(text)':'78d4c3a94b6bb10afe1fd7156e3ee6c0499eda4ba6787395ebcc2aea41d8ad0a',
 'private.collect_imported_native_job_transaction(text)':'8d2e921adc9cd1dd424dd80d4f54fe69f8de9ad3b9d10cd7fd14b06823f80878',
 'private.burimunsi_auto_snapshot(text)':'29bcd9f8440ab6d99571871ca7dc0203ec516d6f4d673a91bfc20eb5cef227f6',
 'private.burimunsi_auto_candidates(text)':'de95126024a114bc696bb570b866aece8d2334bd4db5f742428270c71c682e28',
 'private.burimunsi_native_work_candidates(uuid,integer)':'7f6186d02734c5e40ef0e66051d271d1d67e183b2c78ebbe86e7233b78fc729e',
 'private.burimunsi_native_sms_post_candidates(integer)':'9e1a2a348a06f270afb65055c58edc7e88181385adac3dd24991384b86fe0adc',
 'private.collect_imported_native_history_write_guard()':'899374fa5c194daa82a75e16159dbc36811591af55f533c83cafae9fce95e840',
 'private.collect_imported_native_history_link_guard()':'7091ccc5139d763829e9443ad94b8c5ac936fb1677281bb6017f865e92bee24a',
 'private.collect_imported_native_history_ledger_guard()':'828e7dbff6706d23b068836e7d3926810d28aad753a89b3db7acd19acea9e548'};
function privateBytes(name){if(!/^[a-z0-9_.-]+\.json$/.test(name))throw Error('invalid_evidence_name');const p=join(ROOT,name),s=lstatSync(p);
 if(!s.isFile()||s.isSymbolicLink()||s.nlink!==1||s.uid!==process.getuid()||(s.mode&0o077)!==0||s.size<2||s.size>1024*1024)throw Error('private_evidence_required');return readFileSync(p);}
const privateJson=name=>JSON.parse(privateBytes(name).toString('utf8'));
export function parseManagedReadiness(bytes,now=Date.now()){
 const r=JSON.parse(bytes.toString('utf8')),native=Object.hasOwn(r,'native_sms_admission'),base={...r};
 for(const k of ['native_sms_admission','native_provider_evidence_sha256','native_guard_evidence_sha256','remaining_native_provider_requests'])delete base[k];
 if(base.format!=='collect.jobs.readiness.v1')throw Error('maintenance_readiness_required');validateReadiness(base,now);
 const optional=['native_sms_admission','native_provider_evidence_sha256','native_guard_evidence_sha256','remaining_native_provider_requests'];
 if(native){const a=r.native_sms_admission,keys=['contract','source_sha256','approval_sha256','model_id','batch_limit'];
  if(optional.some(k=>!Object.hasOwn(r,k))||!a||typeof a!=='object'||Array.isArray(a)||Object.keys(a).length!==keys.length||Object.keys(a).some(k=>!keys.includes(k))||
   a.contract!=='collect.native-sms-automation.v1'||!HASH.test(a.source_sha256??'')||!HASH.test(a.approval_sha256??'')||!MODEL.test(a.model_id??'')||a.batch_limit!==1||
   !HASH.test(r.native_provider_evidence_sha256??'')||!HASH.test(r.native_guard_evidence_sha256??'')||!Number.isSafeInteger(r.remaining_native_provider_requests)||r.remaining_native_provider_requests<2||r.remaining_native_provider_requests>400)throw Error('native_readiness_invalid');
 }else if(optional.some(k=>Object.hasOwn(r,k)))throw Error('native_readiness_invalid');
 return {readiness:{...r,evidence_file_sha256:sha(bytes)},native};
}
export function expectedSchedulerBodies(sql){
 const matches=[...sql.matchAll(/CREATE FUNCTION collect_ops\.([a-z_]+)\([^]*?\) RETURNS [^]*? AS \$\$([^]*?)\$\$;/g)];
 const expected=new Map(matches.map(m=>[m[1],sha(m[2])]));
 if(expected.size!==9||matches.length!==9)throw Error('scheduler_source_shape_changed');
 const claim=/CREATE FUNCTION private\.collect_managed_job_claim\([^]*?AS \$claim\$([^]*?)\$claim\$;/.exec(sql);
 const complete=/CREATE FUNCTION private\.collect_managed_job_complete\([^]*?AS \$complete\$([^]*?)\$complete\$;/.exec(sql);
 if(!claim||!complete)throw Error('scheduler_source_shape_changed');
 return {ops:Object.fromEntries(expected),private:{collect_managed_job_claim:sha(claim[1]),collect_managed_job_complete:sha(complete[1])}};
}
async function inspect(db){
 const [scheduler,graph]=await Promise.all([renderManagedScheduler(),Promise.resolve(privateJson('graph-import-attempt-002-result.json'))]);
 if(sha(readFileSync(new URL('../../../supabase/migrations/20261117073850_collect_managed_jobs_hmac.sql',import.meta.url)))!==scheduler.sqlSha)throw Error('scheduler_migration_changed');
 const f=(await db.query('SELECT mode,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
 const key=keyEvidenceForSource(f?.source_sha256);
 if(f?.mode!=='open'||f.source_sha256!==key.sourceSha256||key.project!==PROJECT||!HASH.test(key.keySha256??'')||!Array.isArray(key.functions))throw Error('runtime_or_key_changed');
 const [functionResult,secretResult]=await Promise.all([management('functions'),management('secrets')]);
 const funcs=functionResult.json();if(!sameDeployedFunctions(key.functions,funcs))throw Error('deployed_function_changed');
 const secrets=new Map(secretResult.json().map(x=>[x.name,x.value]));
 if(secrets.get('BUILD_SOURCE_ID')!==sha(f.source_sha256)||secrets.get('COLLECT_JOB_AUTH_MODE')!==sha('supabase_dispatch_hmac_v1')||secrets.get('COLLECT_JOB_SIGNING_KEY')!==key.keySha256||
  secrets.get('MOMO_PROCESSING_PAUSED')!==sha('true'))throw Error('runtime_or_key_changed');
 const row=(await db.query(`SELECT c.enabled,c.config_sha256,c.template_sha256,c.readiness,c.last_probe_id,
  c.native_provider_source_sha256,c.native_provider_model_id,c.native_provider_approval_sha256,c.native_provider_expires_at,c.native_provider_limit,c.native_provider_used,
  j.jobname,j.schedule,j.command,j.database,j.username,j.active,
  (SELECT count(*)::int FROM vault.decrypted_secrets WHERE name='collect_job_signing_key_v1') AS keys,
  (SELECT encode(sha256(convert_to(decrypted_secret,'UTF8')),'hex') FROM vault.decrypted_secrets WHERE id=$1::uuid AND name='collect_job_signing_key_v1') AS key_sha,
  (SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') FROM supabase_migrations.schema_migrations WHERE version='20261117073850') AS migration_sha,
  (SELECT count(*)::int FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed')) AS pending,
  (SELECT count(*)::int FROM private.collect_imported_native_history) AS historical,
  (SELECT count(*)=4 AND bool_and(tgenabled='A') FROM pg_trigger WHERE NOT tgisinternal AND tgname='collect_imported_native_history_guard' AND tgrelid IN('private.burimunsi_auto_sms_jobs'::regclass,'private.burimunsi_native_financial_work'::regclass,'app.momo_financial_links'::regclass,'app.ledger_entries'::regclass)) AS triggers_ok,
  private._collect_fence_scheduler_status()->'coverageVerified' AS scheduler_coverage
  FROM collect_ops.jobs_config c JOIN cron.job j ON j.jobid=c.cron_job_id WHERE c.singleton`,[key.vaultId])).rows[0];
 if(!row||row.config_sha256!==scheduler.configSha||row.template_sha256!==scheduler.templateSha||row.migration_sha!==scheduler.sqlSha||row.keys!==1||row.key_sha!==key.keySha256||
  row.jobname!=='collect-jobs-maintenance-v1'||row.schedule!=='*/5 * * * *'||row.command!=='SELECT collect_ops.tick_jobs();'||row.database!=='postgres'||row.username!=='postgres'||
  row.historical!==graph.counts?.sms||row.historical!==37||row.triggers_ok!==true||row.scheduler_coverage!==true)throw Error('scheduler_or_history_guard_changed');
 const guard=(await db.query(`SELECT x.signature,p.proowner::regrole::text owner,p.prosecdef,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') digest
  FROM unnest($1::text[]) x(signature) LEFT JOIN pg_proc p ON p.oid=to_regprocedure(x.signature)`,[Object.keys(GUARDS)])).rows;
 if(guard.length!==Object.keys(GUARDS).length||guard.some(x=>x.owner!=='postgres'||x.prosecdef!==true||x.digest!==GUARDS[x.signature]))throw Error('scheduler_or_history_guard_changed');
 const expected=expectedSchedulerBodies(scheduler.sql);
 const budget=await renderNativeProviderBudget();
 const budgetFile='20261117081411_collect_native_provider_budget.sql';
 if(sha(readFileSync(new URL('../../../supabase/migrations/'+budgetFile,import.meta.url)))!==budget.sqlSha256)throw Error('scheduler_migration_changed');
 const budgetHistory=(await db.query("SELECT encode(sha256(convert_to(statements[1],'UTF8')),'hex') digest FROM supabase_migrations.schema_migrations WHERE version=$1",[budgetFile.slice(0,14)])).rows[0];
 const readiness=/CREATE OR REPLACE FUNCTION collect_ops\.record_jobs_readiness\([^]*? AS \$\$([^]*?)\$\$;/.exec(budget.sql);
 const setup=/CREATE FUNCTION collect_ops\.configure_native_provider_budget\([^]*? AS \$budget_setup\$([^]*?)\$budget_setup\$;/.exec(budget.sql);
 const reserve=/CREATE FUNCTION private\.collect_native_provider_reserve\([^]*? AS \$budget_reserve\$([^]*?)\$budget_reserve\$;/.exec(budget.sql);
 if(budgetHistory?.digest!==budget.sqlSha256||!readiness||!setup||!reserve)throw Error('scheduler_source_shape_changed');
 const schedulerBody=/AS \$fn\$([^]*?)\$fn\$;/.exec(budget.schedulerStatus);
 const schedulerStatus=(await db.query("SELECT encode(sha256(convert_to(prosrc,'UTF8')),'hex') digest FROM pg_proc WHERE oid='private._collect_fence_scheduler_status()'::regprocedure")).rows[0];
 if(!schedulerBody||schedulerStatus?.digest!==sha(schedulerBody[1]))throw Error('scheduler_source_shape_changed');
 expected.ops.record_jobs_readiness=sha(readiness[1]);
 const budgetFns=(await db.query(`SELECT p.proname,p.proowner::regrole::text owner,p.prosecdef,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') digest,
  has_function_privilege('collect_runtime',p.oid,'EXECUTE') runtime_execute,has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,has_function_privilege('service_role',p.oid,'EXECUTE') service_execute
  FROM pg_proc p WHERE p.oid IN('collect_ops.configure_native_provider_budget(text,text,text,timestamptz)'::regprocedure,'private.collect_native_provider_reserve(uuid,text,text,text)'::regprocedure)`)).rows;
 if(budgetFns.length!==2||budgetFns.some(x=>x.owner!=='postgres'||x.anon_execute||x.authenticated_execute||x.service_execute||
  (x.proname==='collect_native_provider_reserve'?(x.digest!==sha(reserve[1])||!x.prosecdef||!x.runtime_execute):(x.digest!==sha(setup[1])||x.prosecdef||x.runtime_execute))))throw Error('scheduler_source_shape_changed');
 const ops=(await db.query(`SELECT p.proname,p.proowner::regrole::text owner,p.prosecdef,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') digest
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='collect_ops' AND p.proname=ANY($1::text[])`,[Object.keys(expected.ops)])).rows;
 if(ops.length!==9||ops.some(x=>x.owner!=='postgres'||x.prosecdef!==false||x.digest!==expected.ops[x.proname]))throw Error('scheduler_source_shape_changed');
 const claims=(await db.query(`SELECT p.proname,p.proowner::regrole::text owner,p.prosecdef,encode(sha256(convert_to(p.prosrc,'UTF8')),'hex') digest,
  has_function_privilege('collect_runtime',p.oid,'EXECUTE') runtime_execute,has_function_privilege('anon',p.oid,'EXECUTE') anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') authenticated_execute,has_function_privilege('service_role',p.oid,'EXECUTE') service_execute
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname=ANY($1::text[])`,[Object.keys(expected.private)])).rows;
 const ticket=(await db.query(`SELECT c.relrowsecurity,c.relforcerowsecurity,pg_get_userbyid(c.relowner) owner,
  has_table_privilege('collect_runtime',c.oid,'SELECT,INSERT,UPDATE,DELETE,TRUNCATE') runtime_access,
  (SELECT count(*)=1 AND bool_and(tgenabled='A') FROM pg_trigger WHERE tgrelid=c.oid AND tgname='collect_fence_statement_v1' AND NOT tgisinternal) guarded
  FROM pg_class c WHERE c.oid='private.collect_managed_job_tickets'::regclass`)).rows[0];
 if(claims.length!==2||claims.some(x=>x.owner!=='postgres'||x.prosecdef!==true||x.digest!==expected.private[x.proname]||!x.runtime_execute||x.anon_execute||x.authenticated_execute||x.service_execute)||
  !ticket||ticket.owner!=='postgres'||!ticket.relrowsecurity||!ticket.relforcerowsecurity||ticket.runtime_access||!ticket.guarded)throw Error('scheduler_source_shape_changed');
 return {row,secrets,source:f.source_sha256};
}
function verifyNativeBudget(pre,r){
 const a=r.native_sms_admission,c=pre.row;
 if(c.native_provider_source_sha256!==pre.source||c.native_provider_model_id!==a.model_id||c.native_provider_approval_sha256!==a.approval_sha256||
  c.native_provider_limit!==400||!Number.isSafeInteger(c.native_provider_used)||c.native_provider_used<0||c.native_provider_used>398||
  Date.parse(c.native_provider_expires_at)<=Date.now()||r.remaining_native_provider_requests>400-c.native_provider_used)throw Error('native_readiness_invalid');
}
function verifyMode(pre,r,native){
 if(r.project_ref!==PROJECT||r.endpoint!==`https://${PROJECT}.supabase.co/functions/v1/collect-jobs`)throw Error('readiness_project_changed');
 if(native){verifyNativeBudget(pre,r);const a=r.native_sms_admission;if(a.source_sha256!==pre.source||pre.secrets.get('BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED')!==sha('true')||
  pre.secrets.get('MOMO_AI_ENABLED')!==sha('true')||pre.secrets.get('MOMO_AI_MODEL')!==sha(a.model_id)||
  pre.secrets.get('COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256')!==sha(a.approval_sha256)||!pre.secrets.has('OPENAI_API_KEY'))throw Error('native_config_not_qualified');
 }else if(pre.secrets.get('BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED')!==sha('false'))throw Error('maintenance_requires_native_disabled');
}
async function main(){
 const [action,evidenceName]=process.argv.slice(2);if(!['--status','--pause','--configure-native','--recover-native-config','--probe','--reconcile','--activate'].includes(action))throw Error('explicit_action_required');
 if(['--configure-native','--recover-native-config','--probe','--activate'].includes(action)!==Boolean(evidenceName)||process.argv.length!==(evidenceName?4:3))throw Error('evidence_argument_required');
 const input=evidenceName?parseManagedReadiness(privateBytes(evidenceName)):null,db=await connect();
 try{
  let pre=await inspect(db);
  if(action==='--status'){console.log(JSON.stringify({project:PROJECT,sourceSha256:pre.source,enabled:pre.row.enabled,cronActive:pre.row.active,pending:pre.row.pending,historicalProtected:pre.row.historical}));return;}
  if(action==='--pause'){const s=(await db.query('SELECT collect_ops.pause_jobs() AS state')).rows[0].state;console.log(JSON.stringify({enabled:s.enabled,cronActive:s.cron_active}));return;}
  if(action==='--reconcile'){const r=(await db.query('SELECT collect_ops.reconcile_jobs() AS result')).rows[0].result;const s=(await db.query('SELECT collect_ops.jobs_state() AS state')).rows[0].state;console.log(JSON.stringify({reconciliation:r,enabled:s.enabled,cronActive:s.cron_active,awaiting:s.awaiting,unconfirmed:s.unconfirmed}));return;}
  if(action==='--configure-native'||action==='--recover-native-config'){
   if(!input.native||input.readiness.native_sms_admission.source_sha256!==pre.source||!pre.secrets.has('OPENAI_API_KEY'))throw Error('native_readiness_invalid');
   verifyNativeBudget(pre,input.readiness);
   const configName='managed-jobs-native-config-intent.json',a=input.readiness.native_sms_admission;
   if(action==='--configure-native'){
    if(existsSync(join(ROOT,configName))||pre.secrets.get('BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED')!==sha('false'))throw Error('native_config_requires_reconciliation');
    if(!pre.row.last_probe_id||!pre.row.enabled||!pre.row.active||pre.row.pending!==0)throw Error('confirmed_maintenance_activation_required');
    record(configName,{project:PROJECT,sourceSha256:pre.source,evidenceSha256:input.readiness.evidence_file_sha256,at:new Date().toISOString()});
    await db.query('SELECT collect_ops.pause_jobs()');await db.query('SELECT collect_ops.reconcile_jobs()');
    pre=await inspect(db);if(pre.row.enabled||pre.row.active||pre.row.pending!==0)throw Error('scheduler_not_drained');
   }else{const previous=privateJson(configName);if(previous.project!==PROJECT||previous.sourceSha256!==pre.source||previous.evidenceSha256!==input.readiness.evidence_file_sha256||pre.row.enabled||pre.row.active||pre.row.pending!==0)throw Error('native_config_requires_reconciliation');}
   const changes=[{name:'MOMO_AI_ENABLED',value:'true'},{name:'MOMO_AI_MODEL',value:a.model_id},
    {name:'COLLECT_JOB_NATIVE_SMS_APPROVAL_SHA256',value:a.approval_sha256},{name:'BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED',value:'true'}];
   if(changes.some(x=>pre.secrets.has(x.name)&&![sha(x.value),...(['BURIMUNSI_NATIVE_AUTO_TRANSACTIONS_ENABLED','MOMO_AI_ENABLED'].includes(x.name)?[sha('false')]:[])].includes(pre.secrets.get(x.name))))throw Error('native_config_preimage_changed');
   try{await management('secrets',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(changes)});}catch{}
   pre=await inspect(db);verifyMode(pre,input.readiness,true);
   if(!existsSync(join(ROOT,'managed-jobs-native-config-complete.json')))record('managed-jobs-native-config-complete.json',{project:PROJECT,sourceSha256:pre.source,evidenceSha256:input.readiness.evidence_file_sha256,cronActive:false,at:new Date().toISOString()});
   console.log(JSON.stringify({status:'native_config_verified',cronActive:false}));return;
  }
  verifyMode(pre,input?.readiness,input?.native);
  const kind=input.native?'native':'maintenance',stem='managed-jobs-'+kind+'-probe-'+pre.source.slice(0,16);
  if(action==='--probe'){
   if(pre.row.enabled||pre.row.active||pre.row.pending!==0||existsSync(join(ROOT,stem+'-intent.json')))throw Error('disabled_fresh_probe_required');
   const id=randomUUID();record(stem+'-intent.json',{project:PROJECT,sourceSha256:pre.source,dispatchId:id,evidenceSha256:input.readiness.evidence_file_sha256,at:new Date().toISOString()});
   await db.query('SELECT collect_ops.record_jobs_readiness($1::jsonb)',[input.readiness]);
   const dispatch=(await db.query("SELECT collect_ops.dispatch_jobs('probe',$1::uuid) AS result",[id])).rows[0].result;
   record(stem+'-dispatched.json',{project:PROJECT,dispatchId:id,state:dispatch.state,at:new Date().toISOString()});
   if(dispatch.state!=='awaiting')throw Error('probe_not_dispatched');
   console.log(JSON.stringify({status:'probe_dispatched',kind,dispatchId:id}));return;
  }
  if(action==='--activate'){
   const intent=privateJson(stem+'-intent.json');if(intent.sourceSha256!==pre.source||intent.evidenceSha256!==input.readiness.evidence_file_sha256||pre.row.pending!==0)throw Error('confirmed_probe_required');
   const d=(await db.query('SELECT state FROM collect_ops.jobs_dispatches WHERE id=$1::uuid',[intent.dispatchId])).rows[0];if(d?.state!=='confirmed')throw Error('confirmed_probe_required');
   const state=(await db.query('SELECT collect_ops.activate_jobs($1) AS state',[input.readiness.evidence_file_sha256])).rows[0].state;
   if(!state.enabled||!state.cron_active)throw Error('activation_unconfirmed');
   record('managed-jobs-'+kind+'-activated.json',{project:PROJECT,sourceSha256:pre.source,dispatchId:intent.dispatchId,evidenceSha256:intent.evidenceSha256,at:new Date().toISOString()});
   console.log(JSON.stringify({status:'scheduler_active',kind,sourceSha256:pre.source}));
  }
 }finally{await db.end();}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main().catch(e=>{
 const safe=new Set(['explicit_action_required','evidence_argument_required','invalid_evidence_name','private_evidence_required','maintenance_readiness_required','native_readiness_invalid','scheduler_migration_changed','runtime_or_key_changed','deployed_function_changed','scheduler_or_history_guard_changed','scheduler_source_shape_changed','readiness_project_changed','native_config_not_qualified','maintenance_requires_native_disabled','native_config_requires_reconciliation','confirmed_maintenance_activation_required','scheduler_not_drained','native_config_preimage_changed','disabled_fresh_probe_required','probe_not_dispatched','confirmed_probe_required','activation_unconfirmed']);
 console.error(JSON.stringify({outcome:'unconfirmed',reason:safe.has(e.message)?e.message:'provider_or_database_unavailable',detail:'Use status and reconcile the original recorded dispatch before retrying.'}));process.exitCode=1;});
