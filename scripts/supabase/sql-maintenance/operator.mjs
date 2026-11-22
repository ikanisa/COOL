// PRIVATE PROPOSAL. Caller owns verified TLS, exact hosted project admission,
// stable SET ROLE postgres and retained evidence. No connection/secret/CLI input.
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const sha=value=>createHash('sha256').update(value).digest('hex');
export const job={name:'collect-google-ciphertext-expiry-v1',schedule:'*/5 * * * *',command:'SELECT collect_ops.cleanup_google_expired();'};
const denied=['anon','authenticated','service_role','collect_runtime','collect_importer'];
export async function render({fixture=false}={}){
 const template=await readFile(new URL('./install.sql.in',import.meta.url),'utf8');
 const operatorRole='postgres',database=fixture?'collect_sql_maintenance_test':'postgres';
 const sql=template.replaceAll('__OPERATOR_ROLE__',operatorRole).replaceAll('__DATABASE__',database);
 const functionBody=sql.split('$cleanup$')[1];
 if(!functionBody||/__[A-Z_]+__/.test(sql))throw Error('Invalid maintenance template');
 return {sql,functionBody,functionSha:sha(functionBody),sqlSha:sha(sql),operatorRole,database,fixture};
}
export async function preflight(db,r){
 const row=(await db.query("SELECT current_user AS owner,current_database() AS database,current_setting('cron.timezone',true) AS timezone,EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron') AS native,to_regprocedure('cron.schedule(text,text,text)') IS NOT NULL AS schedule,to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') IS NOT NULL AS alter_job,(SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid=to_regclass('app.auth_google_flows')) AS source_owner,(SELECT relforcerowsecurity FROM pg_class WHERE oid=to_regclass('app.auth_google_flows')) AS source_force_rls")).rows[0];
 if(row.owner!==r.operatorRole||row.database!==r.database||(!r.fixture&&!row.native)||!['UTC','GMT','Etc/UTC','Etc/GMT'].includes(row.timezone)||!row.schedule||!row.alter_job||row.source_owner!==r.operatorRole||row.source_force_rls!==false)throw Error('Native SQL maintenance dependencies/identity require qualification');
 return row;
}
export async function status(db,r){
 await preflight(db,r);
 const rows=(await db.query('SELECT jobid,jobname,schedule,command,database,username,active FROM cron.job WHERE jobname=$1',[job.name])).rows;
 const present=(await db.query("SELECT to_regnamespace('collect_ops') IS NOT NULL AS present")).rows[0].present;
 if(!present&&!rows.length)return {installed:false};
 if(rows.length!==1)throw Error('Named Cron identity drift');
 const j=rows[0];
 if(j.schedule!==job.schedule||j.command!==job.command||j.database!==r.database||j.username!==r.operatorRole)throw Error('Named Cron identity drift');
 const functions=(await db.query("SELECT pg_get_userbyid(p.proowner) AS owner,p.prosrc,p.prosecdef,p.pronargs,p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='collect_ops' AND p.proname='cleanup_google_expired'")).rows;
 if(functions.length!==1)throw Error('Maintenance function identity drift');
 const p=functions[0];
 if(p.owner!==r.operatorRole||p.prosrc!==r.functionBody||p.prosecdef||p.pronargs!==0||JSON.stringify(p.proconfig)!==JSON.stringify(['search_path=pg_catalog']))throw Error('Maintenance function identity drift');
 const schemas=(await db.query("SELECT pg_get_userbyid(nspowner) AS owner FROM pg_namespace WHERE nspname='collect_ops'")).rows;
 if(schemas.length!==1||schemas[0].owner!==r.operatorRole)throw Error('Maintenance schema owner drift');
 const extras=(await db.query("SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='collect_ops' AND c.relkind IN('r','p','v','m','f'))::integer AS relations,(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='collect_ops')::integer AS functions")).rows[0];
 if(extras.relations!==0||extras.functions!==1)throw Error('Unknown maintenance schema object');
 const publicAcl=(await db.query("SELECT count(*)::integer AS n FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE n.nspname='collect_ops' AND p.proname='cleanup_google_expired' AND a.grantee<>p.proowner AND a.privilege_type='EXECUTE'")).rows[0];
 const schemaAcl=(await db.query("SELECT count(*)::integer AS n FROM pg_namespace n CROSS JOIN LATERAL aclexplode(coalesce(n.nspacl,acldefault('n',n.nspowner))) a WHERE n.nspname='collect_ops' AND a.grantee<>n.nspowner")).rows[0];
 const roles=(await db.query("SELECT rolname,has_schema_privilege(rolname,'collect_ops','USAGE') AS usage,has_function_privilege(rolname,'collect_ops.cleanup_google_expired()','EXECUTE') AS execute FROM pg_roles WHERE rolname=ANY($1)",[denied])).rows;
 if(publicAcl.n||schemaAcl.n||roles.some(x=>x.usage||x.execute))throw Error('Maintenance application/PUBLIC access drift');
 return {installed:true,job_id:String(j.jobid),active:j.active,operator_role:r.operatorRole,database:r.database,function_sha256:r.functionSha};
}
export async function operate(db,action,{rendered,probeEvidence}={}){
 const r=rendered??await render();
 if(action==='install-inactive'){
  const current=await status(db,r);
  if(current.installed){if(current.active)throw Error('Explicitly deactivate active installation first');return {...current,reconciled_existing:true};}
  try{await db.query(r.sql);}catch(error){await db.query('ROLLBACK').catch(()=>{});throw error;}
  return status(db,r);
 }
 const current=await status(db,r);
 if(!current.installed)throw Error('Inactive installation required');
 if(action==='status')return current;
 if(action==='probe'){
  if(current.active)throw Error('Inactive probe required');
  const result=(await db.query('SELECT collect_ops.cleanup_google_expired() AS result')).rows[0]?.result;
  if(!result||result.status!=='complete'||result.examined_limit!==100||result.provider_calls!==0||!Number.isSafeInteger(result.purged)||result.purged<0||result.purged>100)throw Error('Cleanup result unconfirmed; retain unknown outcome and read back');
  return {...current,action:'probe',outcome:'committed',checked_at:new Date().toISOString(),result};
 }
 if(action==='activate'){
  const age=Date.now()-Date.parse(probeEvidence?.checked_at);
  const value=probeEvidence?.result;
  if(probeEvidence?.action!=='probe'||probeEvidence?.outcome!=='committed'||probeEvidence?.active!==false||probeEvidence?.job_id!==current.job_id||probeEvidence?.function_sha256!==current.function_sha256||probeEvidence?.operator_role!==current.operator_role||probeEvidence?.database!==current.database||value?.status!=='complete'||value?.examined_limit!==100||value?.provider_calls!==0||!Number.isSafeInteger(value?.purged)||value.purged<0||value.purged>100||!Number.isFinite(age)||age< -30000||age>900000)throw Error('Same-identity fresh committed probe evidence required');
 }else if(action!=='deactivate')throw Error('Unsupported maintenance action');
 // Root's wrapper retains the exact reviewed source/copy disposition and native
 // run evidence. This owner-only API is not application authorization.
 await db.query('SELECT cron.alter_job($1::bigint,active:=$2::boolean)',[current.job_id,action==='activate']);
 const result=await status(db,r);
 if(result.active!==(action==='activate'))throw Error('Cron active state unconfirmed');
 return result;
}
