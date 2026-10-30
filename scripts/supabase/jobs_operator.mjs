// No secret-file input and no Vault plaintext query exists in this operator.
// A caller must explicitly authorize application; all default actions are plans.
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {loadConfig,renderSql,validateConnection,readReadiness,projectRef,previousScheduler} from './jobs_config.mjs';

const requiredExtensions=['pg_cron','pg_net','supabase_vault'];
export async function preflight(db){
 const metadata=(await db.query("SELECT current_database() AS database,current_user AS owner,current_setting('cron.timezone',true) AS cron_timezone,coalesce((SELECT array_agg(extname ORDER BY extname) FROM pg_extension WHERE extname=ANY($1)),ARRAY[]::text[]) AS extensions,to_regclass('vault.decrypted_secrets') IS NOT NULL AS vault,to_regclass('net.http_request_queue') IS NOT NULL AND to_regclass('net._http_response') IS NOT NULL AS net,to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') IS NOT NULL AS post,to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') IS NOT NULL AS alter_job",[requiredExtensions])).rows[0];
 if(metadata.database!=='postgres'||requiredExtensions.some(x=>!metadata.extensions.includes(x))||!metadata.vault||!metadata.net||!metadata.post||!metadata.alter_job||!['UTC','GMT','Etc/UTC','Etc/GMT'].includes(metadata.cron_timezone))throw Error('Scheduler extensions/signatures/database require operator qualification');
 const columns=(await db.query("SELECT n.nspname||'.'||c.relname AS relation,array_agg(a.attname::text) AS names FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped WHERE (n.nspname='vault' AND c.relname='decrypted_secrets') OR(n.nspname='net' AND c.relname IN('http_request_queue','_http_response')) GROUP BY n.nspname,c.relname")).rows;
 const expected={'vault.decrypted_secrets':['id','name','decrypted_secret','updated_at'],'net.http_request_queue':['id','method','url','headers','body','timeout_milliseconds'],'net._http_response':['id','status_code','content','timed_out','error_msg','created']};
 for(const [relation,names]of Object.entries(expected))if(names.some(name=>!columns.find(x=>x.relation===relation)?.names.includes(name)))throw Error('Native provider interface changed; reviewed adapter qualification required');
 const denied=(await db.query(`SELECT rolname,has_schema_privilege(rolname,'vault','USAGE') AS vault_read,has_schema_privilege(rolname,'net','USAGE') AS net_usage,has_table_privilege(rolname,'net.http_request_queue','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AS queue_access,has_table_privilege(rolname,'net._http_response','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AS response_access FROM pg_roles WHERE rolname IN('anon','authenticated','service_role','collect_runtime','collect_importer')`)).rows;
 if(denied.some(x=>x.vault_read||x.net_usage||x.queue_access||x.response_access))throw Error('Provider-supported restriction of Vault/net dependencies is required before scheduler use');
 if(!(await db.query("SELECT has_table_privilege(current_user,'vault.decrypted_secrets','SELECT') AND has_table_privilege(current_user,'net._http_response','SELECT') AS allowed")).rows[0].allowed)throw Error('Trusted scheduler operator dependency access required');
 return {extensions:metadata.extensions,restricted_roles:denied.map(x=>x.rolname)};
}
export async function verifyInstalled(db,rendered,{allowPredecessor=false}={}){
 const exists=(await db.query("SELECT to_regnamespace('collect_ops') IS NOT NULL AS present")).rows[0].present;if(!exists)return {installed:false};
 const row=(await db.query("SELECT current_database() AS expected_database,c.config_sha256,c.template_sha256,c.project_ref,j.jobname,j.schedule,j.command,j.database,j.username,j.active FROM collect_ops.jobs_config c LEFT JOIN cron.job j ON j.jobid=c.cron_job_id WHERE c.singleton")).rows[0];
 const predecessor=allowPredecessor&&row?.config_sha256===previousScheduler.configSha&&row?.template_sha256===previousScheduler.templateSha;
 if(!row||(!predecessor&&(row.config_sha256!==rendered.configSha||row.template_sha256!==rendered.templateSha))||row.project_ref!==projectRef||row.jobname!=='collect-jobs-maintenance-v1'||row.schedule!=='*/5 * * * *'||row.command!=='SELECT collect_ops.tick_jobs();'||row.database!==row.expected_database)throw Error('Installed scheduler identity drift; no replacement was attempted');
 const acl=(await db.query("SELECT count(*)::int AS n FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE s.nspname='collect_ops' AND a.grantee=0 AND a.privilege_type='EXECUTE'")).rows[0];if(acl.n)throw Error('Scheduler function PUBLIC access requires correction');
 return {installed:true,active:row.active,predecessor};
}
export async function operate(db,action,{rendered,readiness,dispatchId= randomUUID(),evidenceSha256}={}){
 if(!rendered)rendered=await renderSql();
 // Recovery/status operations must remain available for the exact reviewed
 // predecessor. New probes and activation require the upgraded contract.
 const installed=await verifyInstalled(db,rendered,{allowPredecessor:['upgrade-inactive','status','deactivate','reconcile','review-unknown'].includes(action)});
 if(action==='upgrade-inactive'){
  if(!installed.installed)throw Error('An exact inactive predecessor installation is required');
  if(installed.active)throw Error('Deactivate and reconcile the existing scheduler before upgrade');
  if(!installed.predecessor)return {upgraded:false,reconciled_existing:true,...(await db.query('SELECT collect_ops.jobs_state() AS state')).rows[0]};
  try{await db.query(rendered.upgradeSql);}catch(error){await db.query('ROLLBACK').catch(()=>{});throw error;}
  return {upgraded:true,...(await db.query('SELECT collect_ops.jobs_state() AS state')).rows[0]};
 }
 if(action==='install-inactive'){
  if(installed.installed){if(installed.active)throw Error('Existing active job requires explicit deactivate, not replacement');return {installed:true,reconciled_existing:true,...(await db.query('SELECT collect_ops.jobs_state() AS state')).rows[0]};}
  await db.query(rendered.sql);return {installed:true,...(await db.query('SELECT collect_ops.jobs_state() AS state')).rows[0]};
 }
 if(!installed.installed)throw Error('Inactive installation must be verified first');
 if(action==='status')return (await db.query('SELECT collect_ops.jobs_state() AS state')).rows[0];
 if(action==='deactivate')return (await db.query('SELECT collect_ops.pause_jobs() AS state')).rows[0];
 if(action==='reconcile')return {reconciliation:(await db.query('SELECT collect_ops.reconcile_jobs() AS result')).rows[0].result,...(await db.query('SELECT collect_ops.jobs_state() AS state')).rows[0]};
 if(action==='probe'){
  if(!readiness)throw Error('Reviewed private readiness file required');
  await db.query('SELECT collect_ops.record_jobs_readiness($1::jsonb)',[readiness]);
  return {dispatch_id:dispatchId,...(await db.query("SELECT collect_ops.dispatch_jobs('probe',$1::uuid) AS dispatch",[dispatchId])).rows[0]};
 }
 if(action==='activate'){
  if(!readiness)throw Error('Same reviewed readiness file required');
  return (await db.query('SELECT collect_ops.activate_jobs($1) AS state',[readiness.evidence_file_sha256])).rows[0];
 }
 if(action==='review-unknown'){
  if(!/^[a-f0-9]{64}$/.test(evidenceSha256??''))throw Error('Independent outcome review digest required');
  return (await db.query('SELECT collect_ops.review_unknown_jobs($1::uuid,$2) AS state',[dispatchId,evidenceSha256])).rows[0];
 }
 throw Error('Unsupported scheduler action');
}
async function main(){
 const args=process.argv.slice(2),action=args.shift()??'status',options={};
 for(let i=0;i<args.length;i++){const key=args[i];if(key==='--apply')options.apply=true;else if(['--readiness','--dispatch-id','--evidence-sha256'].includes(key)&&args[i+1])options[key.slice(2)]=args[++i];else throw Error('Unsupported argument; no secret-file or token argument is accepted');}
 if(!['install-inactive','upgrade-inactive','status','probe','reconcile','activate','deactivate','review-unknown'].includes(action))throw Error('Unsupported scheduler action');
 const c=await loadConfig(),rendered=await renderSql(c),mutates=action!=='status';
 if(mutates&&!options.apply){console.log(JSON.stringify({action,planned:true,applied:false,project_ref:projectRef,config_sha256:rendered.configSha,sql_sha256:rendered.sqlSha,credential_input:'Vault reference only'}));return;}
 const url=validateConnection(process.env.COLLECT_JOBS_DATABASE_URL);
 const require=createRequire(import.meta.url),{Client}=require(process.env.COLLECT_PG_MODULE??'pg');
 const db=new Client({connectionString:url.href,ssl:{rejectUnauthorized:true},connectionTimeoutMillis:10000,statement_timeout:30000});let id=options['dispatch-id']??randomUUID();
 if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(id))throw Error('Valid dispatch identity required');
 try{
  await db.connect();if(['install-inactive','upgrade-inactive','probe','activate'].includes(action))await preflight(db);
  const readiness=options.readiness?await readReadiness(options.readiness):undefined;
  if(action==='probe')console.log(JSON.stringify({dispatch_id:id,phase:'attempting',effects:readiness?.mode==='receipt_and_push_v1'?'one reviewed receipt attempt and one reviewed notification attempt':readiness?.notification_admission?'one explicitly reviewed bounded notification probe':readiness?.mode==='receipt_processing_v1'?'one reviewed bounded receipt-processing probe':'one reviewed maintenance probe'}));
  const result=await operate(db,action,{rendered,readiness,dispatchId:id,evidenceSha256:options['evidence-sha256']});console.log(JSON.stringify({action,...result,hosted_acceptance:'operator must retain provider/readback evidence'}));
 }catch{
  // A database commit response may be lost. Never repeat the HTTP dispatch
  // under a new ID or print driver SQL/parameters/connection credentials.
  console.error(JSON.stringify({action,dispatch_id:action==='probe'?id:undefined,outcome:'unconfirmed',next:'Use status/reconcile and the same dispatch id before any retry; secret/SQL details suppressed.'}));process.exitCode=1;
 }finally{await db.end();}
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href)main().catch(()=>{console.error('Scheduler input validation failed; no secret or driver details emitted.');process.exitCode=1;});
