// SQL-side contracts for the synthetic scheduler fixture.
import {randomUUID} from 'node:crypto';
import {renderSql,projectRef,previousScheduler} from './jobs_config.mjs';

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
