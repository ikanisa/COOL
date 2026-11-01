import {createHash,randomUUID} from 'node:crypto';
import {readFile,writeFile,lstat,realpath} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {resolveDeploymentProfile,canonicalProfile} from '../../supabase/functions/_shared/deployment-profile.js';
import {renderSql as renderJobsSql} from './jobs_config.mjs';
import {render as renderGoogleMaintenance} from './sql-maintenance/operator.mjs';
const sha=value=>createHash('sha256').update(value).digest('hex');
const stable=value=>Array.isArray(value)?'['+value.map(stable).join(',')+']':value&&typeof value==='object'?'{'+Object.keys(value).sort().map(key=>JSON.stringify(key)+':'+stable(value[key])).join(',')+'}':JSON.stringify(value);
export function emailDeployment(env=process.env){
 const profile=resolveDeploymentProfile(env);
 if(!env.COLLECT_DEPLOYMENT_PROFILE||profile.mode!=='self_hosted'||sha(canonicalProfile(profile))!==env.COLLECT_DEPLOYMENT_PROFILE_SHA256)throw Error('Verified self-hosted email deployment required');
 return {format:'collect.email.scheduler.v1',profile_sha256:env.COLLECT_DEPLOYMENT_PROFILE_SHA256,endpoint:profile.supabase_origin+'/functions/v1/collect-email-jobs',vault_name:'collect_email_job_token_v1',cron:'*/5 * * * *',install_active:false,max_monthly_budget:10000,batch_limit:1};
}
export async function renderEmailSql(env=process.env){
 const config=emailDeployment(env),template=await readFile(new URL('../../supabase/jobs/email-bootstrap.sql',import.meta.url),'utf8'),configSha=sha(stable(config)),templateSha=sha(template);
 let sql=template.replaceAll('__PROFILE_SHA256__',config.profile_sha256).replaceAll('__ENDPOINT__',config.endpoint).replaceAll('__CONFIG_SHA256__',configSha).replaceAll('__TEMPLATE_SHA256__',templateSha);
 const types={text:25,jsonb:3802,uuid:2950,void:2278};
 const routinesOf=source=>[...source.matchAll(/CREATE FUNCTION collect_ops\.([a-z_]+)\(([^)]*)\) RETURNS (text|jsonb|void) LANGUAGE (sql|plpgsql)( STABLE)? SET search_path=pg_catalog AS \$\$([\s\S]*?)\$\$;/g)].map(([,name,args,result,language,stableFlag,body])=>{
  const parameters=args?args.split(',').map(arg=>arg.trim().split(/\s+/)):[];
  if(parameters.some(parts=>parts.length!==2||!types[parts[1]]))throw Error('Review exact email routine parameters');
  return {name,arguments:parameters.map(parts=>types[parts[1]]).join(' '),argument_names:parameters.map(parts=>parts[0]),return_type:String(types[result]),language,volatility:stableFlag?'s':'v',body_sha256:sha(body)};
 });
 const routines=routinesOf(sql);
 if(routines.length!==9)throw Error('Review exact email routine set');
 const jobs=await renderJobsSql(undefined,env),main=routinesOf(jobs.sql);
 const expectedMain=['activate_jobs','dispatch_jobs','jobs_state','native_jobs_epoch','pause_jobs','reconcile_jobs','record_jobs_readiness','review_unknown_jobs','tick_jobs'];
 if(main.length!==9||main.map(r=>r.name).sort().join()!==expectedMain.join())throw Error('Review exact main scheduler routine set');
 // This helper is optional, but its presence never becomes a prefix-only
 // exemption. Bind the existing production SQL-maintenance source exactly.
 const google=await renderGoogleMaintenance();
 main.push({name:'cleanup_google_expired',arguments:'',argument_names:[],return_type:'3802',language:'plpgsql',volatility:'v',body_sha256:google.functionSha});
 sql=sql.replace('__EMAIL_ROUTINE_MANIFEST__',stable(routines)).replace('__MAIN_ROUTINE_MANIFEST__',stable(main));
 if(/__[A-Z_]+__/.test(sql)||config.endpoint.includes("'"))throw Error('Invalid email template');return {sql,configSha,templateSha,sqlSha:sha(sql)};
}
export function validateEmailReadiness(value,env=process.env,now=Date.now()){
 const deployment=emailDeployment(env),keys=['format','profile_sha256','endpoint','source_sha256','deployment_sha256','runtime_evidence_sha256','provider_evidence_sha256','token_custody_evidence_sha256','copy_inventory_evidence_sha256','quota_evidence_sha256','verified_at','email_admission','monthly_budget'];
 if(!value||Object.keys(value).sort().join()!==keys.sort().join()||value.format!=='collect.email.readiness.v1'||value.profile_sha256!==deployment.profile_sha256||value.endpoint!==deployment.endpoint||!Number.isSafeInteger(value.monthly_budget)||value.monthly_budget<1||value.monthly_budget>10000)throw Error('Exact reviewed email readiness required');
 for(const key of keys.filter(k=>k.endsWith('_sha256')))if(!/^[a-f0-9]{64}$/.test(value[key]))throw Error('Evidence hashes required');
 const at=Date.parse(value.verified_at);if(!Number.isFinite(at)||new Date(at).toISOString()!==value.verified_at||at<now-3600000||at>now+30000)throw Error('Fresh canonical readiness timestamp required');
 const a=value.email_admission;if(!a||Object.keys(a).sort().join()!==['contract','source_sha256','approval_sha256','admitted_from','batch_limit'].sort().join()||a.contract!=='collect.contribution-email.v1'||a.source_sha256!==value.source_sha256||!/^[a-f0-9]{64}$/.test(a.approval_sha256)||a.batch_limit!==1||!Number.isSafeInteger(a.admitted_from)||a.admitted_from<=0||a.admitted_from>=4102444800)throw Error('Bounded source-approved email admission required');return value;
}
export async function readEmailReadiness(file,env=process.env){
 const stat=await lstat(file);if(await realpath(file)!==resolve(file)||!stat.isFile()||stat.isSymbolicLink()||stat.nlink!==1||(stat.mode&0o777)!==0o600||stat.uid!==process.getuid()||stat.size>16384)throw Error('Owned independent 0600 readiness file required');
 const raw=await readFile(file,'utf8'),value=validateEmailReadiness(JSON.parse(raw),env);return {...value,evidence_file_sha256:sha(raw)};
}
// Invocation is owner-only. Secrets come from a private process environment;
// never place the database URL, Vault token or SMTP key in command arguments.
export async function runEmailOperation(operation,{sql,readiness,id,evidence,env=process.env}={}){
 const deployment=emailDeployment(env);if(!sql)throw Error('Verified owner connection required');
 const owner=(await sql.unsafe('SELECT current_user AS current,session_user AS session'))[0];if(owner.current!=='postgres'||owner.session!=='postgres')throw Error('Owner connection required');
 if((await sql.unsafe('SELECT private.collect_assert_deployment($1::text) AS verified',[deployment.profile_sha256]))[0]?.verified!==true)throw Error('Database deployment identity mismatch');
 switch(operation){
  case 'status':return (await sql.unsafe('SELECT collect_ops.email_state() AS value'))[0].value;
  case 'pause':return (await sql.unsafe('SELECT collect_ops.pause_email() AS value'))[0].value;
  case 'readiness':await sql.unsafe('SELECT collect_ops.record_email_readiness($1::text::jsonb)',[JSON.stringify(readiness)]);return {recorded:true,enabled:false};
  case 'probe':if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(id??''))throw Error('Retained original dispatch UUID required');return (await sql.unsafe("SELECT collect_ops.dispatch_email('probe',$1::uuid) AS value",[id]))[0].value;
  case 'reconcile':return (await sql.unsafe('SELECT collect_ops.reconcile_email() AS value'))[0].value;
  case 'activate':if(!/^[a-f0-9]{64}$/.test(evidence??''))throw Error('Exact readiness evidence required');return (await sql.unsafe('SELECT collect_ops.activate_email($1::text) AS value',[evidence]))[0].value;
 case 'review-unknown':if(!/^[a-f0-9]{64}$/.test(evidence??'')||!/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(id??''))throw Error('Original UUID and review evidence required');return (await sql.unsafe('SELECT collect_ops.review_email_unknown($1::uuid,$2::text) AS value',[id,evidence]))[0].value;
  default:throw Error('Unsupported owner operation');
 }
}
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 try{
  const [operation,arg,extra]=process.argv.slice(2);
  if(operation==='render'&&arg&&!extra){const rendered=await renderEmailSql();await writeFile(arg,rendered.sql,{flag:'wx',mode:0o600});console.log(JSON.stringify({config_sha256:rendered.configSha,template_sha256:rendered.templateSha,sql_sha256:rendered.sqlSha,active:false}));}
  else if(operation==='new-dispatch-id'&&!arg)console.log(JSON.stringify({dispatch_id:randomUUID(),submitted:false}));
  else{
   emailDeployment();const value=process.env.COLLECT_EMAIL_JOBS_DATABASE_URL;delete process.env.COLLECT_EMAIL_JOBS_DATABASE_URL;const target=new URL(value);
   if(!['postgres:','postgresql:'].includes(target.protocol)||target.hostname!=='db'||!['','5432'].includes(target.port)||target.username!=='postgres'||!target.password||target.pathname!=='/postgres'||target.search||target.hash||!process.env.COLLECT_DB_CA_PEM?.startsWith('-----BEGIN CERTIFICATE-----\n'))throw Error('Verified private owner database required');
   const pg=createRequire(import.meta.url)('pg');const client=new pg.Client({connectionString:value,ssl:{ca:process.env.COLLECT_DB_CA_PEM,rejectUnauthorized:true,servername:'db'},connectionTimeoutMillis:10000,statement_timeout:15000});await client.connect();
   const sql={unsafe:async(text,values)=>(await client.query(text,values)).rows};
   try{const readiness=operation==='readiness'?await readEmailReadiness(arg):undefined;console.log(JSON.stringify(await runEmailOperation(operation,{sql,readiness,id:arg,evidence:operation==='review-unknown'?extra:arg})));}finally{await client.end();}
  }
 }catch{console.error('Email scheduler operation refused; no secret values emitted.');process.exitCode=1;}
}
