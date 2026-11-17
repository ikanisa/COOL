// An already-open, drained Cloud runtime revision. No data or keys are replaced.
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {readFileSync} from 'node:fs';
import {connect,management,record,sha,ROOT} from './access.mjs';
import {captureRuntimeSnapshot,checkSnapshot} from './runtime-plan.mjs';
import {applyEntry,history,identity} from './migrations.mjs';
export async function reviseRuntime({label,testEvidence,migrations=[],resumeFencedRevision=null}){
 if(!/^[a-z][a-z0-9-]{3,60}$/.test(label)||!testEvidence||testEvidence.passed!==true)throw Error('reviewed_revision_required');
 if(!Array.isArray(migrations)||migrations.length>5)throw Error('reviewed_migrations_required');
 const entries=migrations.map(x=>{const e=identity(x.file,x.sql);if(e.sha256!==x.sha256)throw Error('reviewed_migration_changed');return e;});
 if(new Set(entries.map(x=>x.version)).size!==entries.length)throw Error('duplicate_revision_migration');
 if(resumeFencedRevision!==null&&!/^[a-z][a-z0-9-]{3,60}$/.test(resumeFencedRevision))throw Error('reviewed_revision_required');
 const prior=resumeFencedRevision===null?null:JSON.parse(readFileSync(ROOT+'/revision-'+resumeFencedRevision+'-intent.json','utf8'));
 const snapshot=captureRuntimeSnapshot(),checked=checkSnapshot(snapshot),c=await connect();
 const name='revision-'+label;
 try{
  const f=(await c.query('SELECT mode,epoch,operation_id,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
  const active=(await c.query("SELECT count(*)::int n FROM private.collect_fence_admissions a WHERE state IN('active','unresolved') AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)")).rows[0].n;
  if((prior?f.mode!=='fenced':f.mode!=='open')||f.source_sha256===snapshot.sourceSha)throw Error('runtime_revision_precondition');
  if(prior&&(active!==0||f.operation_id!==prior.fenceId||f.epoch!==prior.before.epoch||f.source_sha256!==prior.before.source_sha256||snapshot.sourceSha!==prior.snapshot.sourceSha256))throw Error('fenced_revision_preimage_changed');
  const before=(await management('functions')).json();if(before.length!==3)throw Error('runtime_function_set_changed');
  if(prior&&JSON.stringify(before)!==JSON.stringify(prior.functions))throw Error('fenced_revision_functions_changed');
  const fenceId=prior?prior.fenceId:randomUUID(),upgradeId=randomUUID(),releaseId=randomUUID();
  const migrationHistory=await history(c);
  if(entries.some(x=>migrationHistory.some(y=>y.version===x.version)))throw Error('revision_migration_already_recorded');
  const plan={before:f,activeBeforeQuiesce:active,functions:before,snapshot:snapshot.summary(),checked,testEvidence,migrations:entries.map(({file,sha256})=>({file,sha256})),migrationHistory,fenceId,upgradeId,releaseId,resumes:prior?{label:resumeFencedRevision,intentSha256:sha(JSON.stringify(prior))}:null,at:new Date().toISOString()};
  record(name+'-intent.json',plan);
  if(!prior){const quiesce=(await c.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3) v',[fenceId,f.epoch,f.source_sha256])).rows[0].v;
   if(quiesce.mode!=='quiescing')throw Error('revision_quiesce_unconfirmed');}
  // Quiescing blocks new admissions; existing phone requests must settle
  // naturally. Never retire a live request or infer settlement from elapsed time.
  const deadline=Date.now()+60000;
  for(;;){
   const remaining=(await c.query("SELECT count(*)::int n FROM private.collect_fence_admissions a WHERE state IN('active','unresolved') AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)")).rows[0].n;
   if(remaining===0)break;
   if(Date.now()>=deadline)throw Error('revision_admissions_not_drained');
   await delay(1000);
  }
  const drained=(await c.query('SELECT private.collect_fence_drain_v3($1,$2,$3) v',[fenceId,f.epoch,f.source_sha256])).rows[0].v;
  if(drained.mode!=='fenced')throw Error('revision_drain_unconfirmed');
  record(name+'-fenced.json',{fenceId,epoch:f.epoch,at:new Date().toISOString()});
  let applied=migrationHistory;
  for(const entry of entries){
   record(name+'-migration-'+entry.version+'-intent.json',{file:entry.file,sha256:entry.sha256,before:applied,at:new Date().toISOString()});
   applied=await applyEntry(c,entry,{before:applied});
   record(name+'-migration-'+entry.version+'-complete.json',{file:entry.file,sha256:entry.sha256,migrationCount:applied.length,at:new Date().toISOString()});
  }
  await management('secrets',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify([{name:'BUILD_SOURCE_ID',value:snapshot.sourceSha}])});
  const secrets=(await management('secrets')).json();
  if(secrets.find(x=>x.name==='BUILD_SOURCE_ID')?.value!==sha(snapshot.sourceSha))throw Error('revision_source_secret_unconfirmed');
  const deployed=[];
  for(const slug of ['collect-api','admin-api','collect-jobs']){
   record(name+'-'+slug+'-attempt.json',{sourceSha256:snapshot.sourceSha,at:new Date().toISOString()});
   const response=(await management('functions/deploy?slug='+slug,{method:'POST',body:snapshot.makeForm(slug)})).json();
   const r=(await management('functions')).json().find(x=>x.slug===slug);
   if(!r||r.status!=='ACTIVE'||r.verify_jwt!==false||r.version!==response.version||r.version<=before.find(x=>x.slug===slug)?.version||!r.ezbr_sha256)throw Error('revision_deploy_unconfirmed');
   deployed.push(r);record(name+'-'+slug+'-complete.json',r);
  }
  const actual=(await management('functions')).json();
  if(actual.length!==3||deployed.some(x=>!actual.some(a=>a.slug===x.slug&&a.version===x.version&&a.ezbr_sha256===x.ezbr_sha256)))throw Error('revision_readback_changed');
  await c.query('SELECT private.collect_fence_upgrade_source_v3($1,$2,$3,$4,$5,$6,$7,$8)',[upgradeId,fenceId,f.epoch,f.source_sha256,snapshot.sourceSha,sha(JSON.stringify(plan)),sha(JSON.stringify({testEvidence,checked})),sha(JSON.stringify(deployed))]);
  const mid=(await c.query('SELECT mode,epoch,operation_id,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
  if(mid.mode!=='fenced'||mid.operation_id!==upgradeId||mid.source_sha256!==snapshot.sourceSha||Number(mid.epoch)!==Number(f.epoch)+1)throw Error('revision_upgrade_unconfirmed');
  record(name+'-upgraded.json',mid);
  await c.query('SELECT private.collect_fence_release_v3($1,$2,$3)',[releaseId,mid.epoch,snapshot.sourceSha]);
  const end=(await c.query('SELECT mode,epoch,operation_id,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
  if(end.mode!=='open'||end.operation_id!==releaseId||end.source_sha256!==snapshot.sourceSha||Number(end.epoch)!==Number(mid.epoch)+1)throw Error('revision_release_unconfirmed');
  const result={sourceSha256:snapshot.sourceSha,epoch:end.epoch,functions:deployed,at:new Date().toISOString()};record(name+'-complete.json',result);
  return {status:'revision_deployed_live',sourceSha256:snapshot.sourceSha,epoch:end.epoch};
 }finally{await c.end();}
}
