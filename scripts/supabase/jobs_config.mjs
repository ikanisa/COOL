import {createHash} from 'node:crypto';
import {readFile,writeFile,lstat,realpath} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {parseScheduledDispatch,RECEIPT_PROCESSING_MODE,RECEIPT_PROCESSING_CONTRACT,RECEIPT_PROCESSING_LIMIT,NOTIFICATION_PROCESSING_MODE,COMBINED_PROCESSING_MODE} from '../../supabase/functions/_shared/scheduled-processing.js';
import {PUSH_CONTRACT,PUSH_BATCH_LIMIT} from '../../supabase/functions/_shared/fcm-notifications.js';

export const projectRef='rrlduytparvsjfmegalh';
export const configFile=new URL('../../supabase/jobs/config.json',import.meta.url);
export const templateFile=new URL('../../supabase/jobs/bootstrap.sql',import.meta.url);
export const previousScheduler={configSha:'b2cede1f2c0eea79f31fcb7e731ec816320f24a677954bd19ebbeba5781f5169',templateSha:'590273dc8710e32c46933d03a9f9e7fcce8ebb0269328f51ef97d82e614d6cd4'};
const sha=value=>createHash('sha256').update(value).digest('hex');
export const stable=value=>Array.isArray(value)?'['+value.map(stable).join(',')+']':value&&typeof value==='object'?'{'+Object.keys(value).sort().map(k=>JSON.stringify(k)+':'+stable(value[k])).join(',')+'}':JSON.stringify(value);
export function validateConfig(c){
 if(c?.format!=='collect.jobs.scheduler.v3'||c.project_ref!==projectRef||c.function_name!=='collect-jobs'||c.endpoint!==`https://${projectRef}.supabase.co/functions/v1/collect-jobs`||c.method!=='POST')throw Error('Exact Collect project/function/method required');
 if(stable(c.authorization)!==stable({header:'Authorization',scheme:'Bearer',vault_secret_name:'collect_job_token_v1'})||stable(c.cron)!==stable({name:'collect-jobs-maintenance-v1',expression:'*/5 * * * *',timezone:'UTC',install_active:false})||stable(c.request)!==stable({body_template:{dispatch_id:'original_dispatch_id'},timeout_ms:120000}))throw Error('Fixed disabled schedule and Vault reference required');
 if(stable(c.budgets)!==stable({max_dispatches_per_utc_month:10000,unconfirmed_after_seconds:180,review_wait_seconds:300,history_days:30,cron_history_days:7,prune_limit:500,response_bytes:16384})||stable(c.activation)!==stable({mode:'maintenance_only',momo_processing_paused:true,readiness_max_age_seconds:3600,probe_max_age_seconds:900}))throw Error('Reviewed bounded maintenance contract required');
 if(stable(c.processing)!==stable({mode:RECEIPT_PROCESSING_MODE,contract:RECEIPT_PROCESSING_CONTRACT,enabled_by_default:false,batch_limit:RECEIPT_PROCESSING_LIMIT,max_provider_requests_per_utc_month:10000,requires_source_model_and_approval_binding:true}))throw Error('Reviewed bounded processing admission required');
 if(stable(c.notifications)!==stable({modes:[NOTIFICATION_PROCESSING_MODE,COMBINED_PROCESSING_MODE],contract:PUSH_CONTRACT,enabled_by_default:false,batch_limit:PUSH_BATCH_LIMIT,max_delivery_attempts_per_utc_month:10000,max_provider_http_requests_per_utc_month:20000,requires_source_project_package_start_and_approval_binding:true}))throw Error('Reviewed bounded notification admission required');
 const keys=['format','project_ref','function_name','endpoint','method','authorization','cron','request','budgets','activation','processing','notifications','qualification'];if(Object.keys(c).some(k=>!keys.includes(k)))throw Error('Unexpected configuration field');
 return c;
}
export async function loadConfig(){return validateConfig(JSON.parse(await readFile(configFile,'utf8')));}
export async function renderSql(c){
 c??=await loadConfig();validateConfig(c);let template=await readFile(templateFile,'utf8');
 const configSha=sha(stable(c)),templateSha=sha(template);
 template=template.replaceAll('__TEMPLATE_SHA256__',templateSha).replaceAll('__CONFIG_SHA256__',configSha).replaceAll('__PROJECT_REF__',c.project_ref).replaceAll('__ENDPOINT__',c.endpoint).replaceAll('__VAULT_NAME__',c.authorization.vault_secret_name).replaceAll('__JOB_NAME__',c.cron.name).replaceAll('__SCHEDULE__',c.cron.expression);
 if(/__[A-Z0-9_]+__/.test(template))throw Error('Unresolved SQL template token');
 const upgradeSql=renderInactiveUpgrade(template,{configSha,templateSha});
 return {sql:template,configSha,templateSha,sqlSha:sha(template),upgradeSql,upgradeSha:sha(upgradeSql)};
}
function renderInactiveUpgrade(template,{configSha,templateSha}){
 const functions=[...template.matchAll(/CREATE FUNCTION collect_ops\.[\s\S]*?\$\$;/g)].map(match=>match[0].replace('CREATE FUNCTION','CREATE OR REPLACE FUNCTION'));
 if(functions.length!==9)throw Error('Review the exact scheduler function set before upgrading');
 return `-- Explicit inactive upgrade only; no extension, credential or HTTP work.\nBEGIN;
DO $upgrade$ BEGIN
 PERFORM private.collect_fence_assert_write(NULL,NULL,NULL);
 PERFORM pg_advisory_xact_lock(hashtextextended('collect.scheduler.${projectRef}',0));
 PERFORM 1 FROM collect_ops.jobs_config WHERE singleton FOR UPDATE;
 IF NOT EXISTS(SELECT 1 FROM collect_ops.jobs_config c JOIN cron.job j ON j.jobid=c.cron_job_id
  WHERE c.singleton AND c.config_sha256='${previousScheduler.configSha}' AND c.template_sha256='${previousScheduler.templateSha}'
   AND c.project_ref='${projectRef}' AND NOT c.enabled AND NOT j.active
   AND j.jobname='collect-jobs-maintenance-v1' AND j.schedule='*/5 * * * *' AND j.command='SELECT collect_ops.tick_jobs();'
   AND j.database=current_database() AND j.username=current_user)
  OR EXISTS(SELECT 1 FROM collect_ops.jobs_dispatches WHERE state IN('awaiting','unconfirmed'))
 THEN RAISE EXCEPTION 'inactive_exact_predecessor_without_pending_work_required';END IF;
END $upgrade$;
ALTER TABLE collect_ops.jobs_dispatches ADD COLUMN runtime_contract jsonb CHECK(runtime_contract IS NULL OR jsonb_typeof(runtime_contract)='object');
ALTER TABLE collect_ops.jobs_dispatches ADD COLUMN notification_contract jsonb CHECK(notification_contract IS NULL OR jsonb_typeof(notification_contract)='object');
ALTER TABLE collect_ops.jobs_config DROP CONSTRAINT jobs_config_config_sha256_check;
ALTER TABLE collect_ops.jobs_config DROP CONSTRAINT jobs_config_template_sha256_check;
UPDATE collect_ops.jobs_config SET config_sha256='${configSha}',template_sha256='${templateSha}',readiness=NULL,last_probe_id=NULL,enabled=false WHERE singleton;
ALTER TABLE collect_ops.jobs_config ADD CONSTRAINT jobs_config_config_sha256_check CHECK(config_sha256='${configSha}');
ALTER TABLE collect_ops.jobs_config ADD CONSTRAINT jobs_config_template_sha256_check CHECK(template_sha256='${templateSha}');
${functions.join('\n')}
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA collect_ops FROM PUBLIC;
COMMIT;\n`;
}
export function validateConnection(value,{localTest=false}={}){
 const u=new URL(value);if(!['postgres:','postgresql:'].includes(u.protocol)||!u.username||!u.password)throw Error('Expected PostgreSQL connection in private process environment');
 if(localTest){
  const owned=u.pathname==='/collect_jobs_test'&&decodeURIComponent(u.username)==='collect_test'&&!u.hash&&!u.search;
  const legacy=['localhost','127.0.0.1'].includes(u.hostname)&&u.port==='55439';
  const synthetic=process.env.COLLECT_CI_SYNTHETIC==='true'&&u.hostname==='127.0.0.1'&&/^[1-9][0-9]{0,4}$/.test(u.port)&&Number(u.port)<=65535;
  if(!owned||(!legacy&&!synthetic))throw Error('Only the owned loopback collect_jobs_test fixture is allowed');
 }
 else if(u.hostname!==`db.${projectRef}.supabase.co`&&!(u.hostname.endsWith('.pooler.supabase.com')&&decodeURIComponent(u.username).endsWith('.'+projectRef)))throw Error('Unexpected scheduler database project');
 if([...u.searchParams].some(([key,value])=>key!=='sslmode'||value!=='verify-full'))throw Error('Unreviewed connection options are not allowed');
 u.search='';
 if(!localTest&&u.pathname!=='/postgres')throw Error('Hosted pg_net targets the postgres database');
 return u;
}
export async function readReadiness(file){
 const physical=await realpath(file),info=await lstat(file);
 if(physical!==resolve(file)||info.isSymbolicLink()||!info.isFile()||info.nlink!==1||(info.mode&0o777)!==0o600||info.uid!==process.getuid()||info.size>16384)throw Error('Readiness requires an owned independent 0600 regular file');
 const body=await readFile(file,'utf8'),value=JSON.parse(body);validateReadiness(value);return {...value,evidence_file_sha256:sha(body)};
}
export function validateReadiness(r,now=Date.now()){
 const notifications=r?.format==='collect.jobs.readiness.v3',processing=r?.format==='collect.jobs.readiness.v2'||notifications&&r.mode===COMBINED_PROCESSING_MODE;
 const keys=['format','project_ref','endpoint','deployment_sha256','runtime_evidence_sha256','token_custody_evidence_sha256','copy_inventory_evidence_sha256','quota_evidence_sha256','verified_at','momo_processing_paused','remaining_invocations',
  ...(processing||notifications?['mode']:[]),...(processing?['processing_admission','provider_evidence_sha256','remaining_provider_requests']:[]),
  ...(notifications?['notification_admission','notification_provider_evidence_sha256','remaining_notification_attempts','remaining_notification_provider_requests']:[])];
 if(!r||Object.keys(r).sort().join()!==keys.sort().join()||!['collect.jobs.readiness.v1','collect.jobs.readiness.v2','collect.jobs.readiness.v3'].includes(r.format)||r.project_ref!==projectRef||r.endpoint!==`https://${projectRef}.supabase.co/functions/v1/collect-jobs`||r.momo_processing_paused!==!processing||!Number.isSafeInteger(r.remaining_invocations)||r.remaining_invocations<10000)throw Error('Reviewed bounded job readiness required');
 if(processing){
  if(r.mode!==(notifications?COMBINED_PROCESSING_MODE:RECEIPT_PROCESSING_MODE)||!Number.isSafeInteger(r.remaining_provider_requests)||r.remaining_provider_requests<10000)throw Error('Reviewed processing mode and provider quota required');
  parseScheduledDispatch({dispatch_id:'00000000-0000-4000-8000-000000000001',processing_admission:r.processing_admission});
 }
 if(notifications){
  if(![NOTIFICATION_PROCESSING_MODE,COMBINED_PROCESSING_MODE].includes(r.mode)||!Number.isSafeInteger(r.remaining_notification_attempts)||r.remaining_notification_attempts<10000||!Number.isSafeInteger(r.remaining_notification_provider_requests)||r.remaining_notification_provider_requests<20000)throw Error('Reviewed notification mode and provider quota required');
  parseScheduledDispatch({dispatch_id:'00000000-0000-4000-8000-000000000001',notification_admission:r.notification_admission});
 }
 for(const key of keys.filter(x=>x.endsWith('_sha256')))if(!/^[a-f0-9]{64}$/.test(r[key]))throw Error('Evidence digests required');
 const at=Date.parse(r.verified_at);if(!Number.isFinite(at)||at>now+30000||at<now-3600000)throw Error('Readiness must be verified within the last hour');
 return r;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 try{const c=await loadConfig(),r=await renderSql(c);if(['--output','--upgrade-output'].includes(process.argv[2])&&process.argv[3]&&process.argv.length===4){const upgrade=process.argv[2]==='--upgrade-output';await writeFile(process.argv[3],upgrade?r.upgradeSql:r.sql,{flag:'wx',mode:0o600});console.log(JSON.stringify({config_sha256:r.configSha,sql_sha256:upgrade?r.upgradeSha:r.sqlSha,upgrade,contains_job_token:false,active:false}));}else if(process.argv.length===2)console.log(JSON.stringify({config_sha256:r.configSha,sql_sha256:r.sqlSha,endpoint:c.endpoint,active:false,monthly_scheduled_invocations_31_days:8928}));else throw Error('Usage: node jobs_config.mjs [--output|--upgrade-output NEW_PRIVATE_SQL_FILE]');}catch{console.error('Scheduler configuration failed validation; no secret values emitted.');process.exitCode=1;}
}
