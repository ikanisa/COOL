// An already-open, drained Cloud runtime revision. No data or keys are replaced.
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {readFileSync,lstatSync} from 'node:fs';
import {connect,management,record,sha,ROOT} from './access.mjs';
import {captureRuntimeSnapshot,checkSnapshot} from './runtime-plan.mjs';
import {applyEntry,history,identity} from './migrations.mjs';

// A checked, complete scheduler inventory is required before closing admission.
// In particular, an active cron or a dispatch without local lifecycle proof
// would leave drain in QUIESCING rather than FENCED.
export function requireRevisionSchedulerReady(status){
 if(!status||typeof status!=='object'||Array.isArray(status)||status.checked!==true||
    status.coverageVerified!==true||status.blocking!==false)throw Error('runtime_revision_scheduler_not_drained');
 return status;
}

// A caller that qualified a particular live source must not silently revise a
// newer deployment. The database quiesce operation also compares this same
// epoch and source, closing the race between this read and admission closure.
export function requireRevisionPreimage(expected,actual){
 if(!expected||typeof expected!=='object'||Array.isArray(expected)||
    !['open','fenced'].includes(expected.mode)||!Number.isSafeInteger(expected.epoch)||expected.epoch<0||
    !/^[a-f0-9]{64}$/.test(expected.source_sha256??'')||
    !actual||actual.mode!==expected.mode||Number(actual.epoch)!==expected.epoch||
    actual.source_sha256!==expected.source_sha256)throw Error('runtime_revision_preimage_changed');
 return actual;
}
export function requireRevisionFunctions(expected,actual){
 const slugs=['admin-api','collect-api','collect-jobs'];
 const summary=rows=>{
  if(!Array.isArray(rows)||rows.length!==slugs.length)throw Error('runtime_revision_functions_changed');
  return slugs.map(slug=>{
   const found=rows.filter(x=>x?.slug===slug);
   if(found.length!==1)throw Error('runtime_revision_functions_changed');
   const x=found[0];
   if(x.status!=='ACTIVE'||x.verify_jwt!==false||!Number.isSafeInteger(x.version)||x.version<1||
      !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(x.id??'')||
      !/^[a-f0-9]{64}$/.test(x.ezbr_sha256??''))
    throw Error('runtime_revision_functions_changed');
   return {slug,id:x.id,status:x.status,version:x.version,verify_jwt:x.verify_jwt,ezbr_sha256:x.ezbr_sha256};
  });
 };
 if(JSON.stringify(summary(expected))!==JSON.stringify(summary(actual)))throw Error('runtime_revision_functions_changed');
 return actual;
}
export async function verifyFencedRevisionPreimage(expectedBefore,expectedFunctions,api){
 if(!expectedBefore||!expectedFunctions)throw Error('runtime_revision_preimage_changed');
 const current=(await api('functions')).json();requireRevisionFunctions(expectedFunctions,current);
 const metadata=(await api('secrets')).json();
 if(!Array.isArray(metadata)||metadata.filter(x=>x?.name==='BUILD_SOURCE_ID').length!==1||
    metadata.find(x=>x.name==='BUILD_SOURCE_ID')?.value!==sha(expectedBefore.source_sha256))
  throw Error('runtime_revision_source_secret_changed');
 return current;
}
function secretPreimages(value){
 if(value===null)return null;
 if(!value||typeof value!=='object'||Array.isArray(value))throw Error('runtime_revision_secret_preimage_invalid');
 const names=Object.keys(value).sort();
 if(names.length<1||names.length>16||names.some(k=>k==='BUILD_SOURCE_ID'||!/^[A-Z][A-Z0-9_]{1,127}$/.test(k)||
     !/^[a-f0-9]{64}$/.test(value[k]??'')))throw Error('runtime_revision_secret_preimage_invalid');
 return Object.fromEntries(names.map(k=>[k,value[k]]));
}
export function requireSecretPreimages(expected,metadata){
 const qualified=secretPreimages(expected);if(qualified===null)return;
 if(!Array.isArray(metadata))throw Error('runtime_revision_secret_preimage_changed');
 for(const [name,digest] of Object.entries(qualified)){
  const rows=metadata.filter(x=>x?.name===name);
  if(rows.length!==1||rows[0].value!==digest)throw Error('runtime_revision_secret_preimage_changed');
 }
}

const SLUGS=['collect-api','admin-api','collect-jobs'];
function readRevisionRecord(name){
 if(!/^[a-z0-9_.-]+\.json$/.test(name))throw Error('revision_record_invalid');
 const path=ROOT+'/'+name;let stat;
 try{stat=lstatSync(path);}catch(error){if(error?.code==='ENOENT')return null;throw error;}
 if(!stat.isFile()||stat.isSymbolicLink()||stat.nlink!==1||stat.uid!==process.getuid()||
    (stat.mode&0o077)!==0||stat.size<2||stat.size>5*1024*1024)throw Error('revision_record_invalid');
 return JSON.parse(readFileSync(path,'utf8'));
}
function historyRows(rows){
 if(!Array.isArray(rows))throw Error('fenced_revision_history_changed');
 const result=rows.map(x=>{
  if(!x||!/^\d{14}$/.test(x.version??'')||typeof x.name!=='string'||!x.name||
     !/^[a-f0-9]{64}$/.test(x.sha256??'')||!Number.isSafeInteger(x.entries)||x.entries<1)
   throw Error('fenced_revision_history_changed');
  return {version:x.version,name:x.name,sha256:x.sha256,entries:x.entries};
 }).sort((a,b)=>a.version.localeCompare(b.version));
 if(new Set(result.map(x=>x.version)).size!==result.length)throw Error('fenced_revision_history_changed');
 return result;
}
const sameHistory=(a,b)=>JSON.stringify(historyRows(a))===JSON.stringify(historyRows(b));

/** Only an exact prefix of the originally reviewed migrations may exist. An
 * intent is persisted before each apply, so a lost COMMIT response is resolved
 * by the actual immutable migration-history row, never by replaying the SQL. */
export function reconcileResumeHistory(prior,entries,observed,readRecord,labels){
 if(!prior||!Array.isArray(prior.migrations)||prior.migrations.length!==entries.length||
    prior.migrations.some((x,i)=>x?.file!==entries[i].file||x.sha256!==entries[i].sha256))
  throw Error('fenced_revision_migrations_changed');
 const base=historyRows(prior.migrationHistory),actual=historyRows(observed);
 if(entries.some(e=>base.some(x=>x.version===e.version)))throw Error('fenced_revision_history_changed');
 if(!Array.isArray(labels)||labels.length<1||new Set(labels).size!==labels.length||
    labels.some(x=>!/^[a-z][a-z0-9-]{3,60}$/.test(x)))throw Error('revision_record_invalid');
 let applied=0,missing=false,expected=[...base];
 for(const entry of entries){
  const found=actual.find(x=>x.version===entry.version);
  let hasIntent=false,hasComplete=false;
  for(const label of labels){
   const intent=readRecord('revision-'+label+'-migration-'+entry.version+'-intent.json');
   const complete=readRecord('revision-'+label+'-migration-'+entry.version+'-complete.json');
   if(intent&&(intent.file!==entry.file||intent.sha256!==entry.sha256||!sameHistory(intent.before,expected)))
    throw Error('fenced_revision_migration_evidence_changed');
   if(complete&&(!intent||complete.file!==entry.file||complete.sha256!==entry.sha256||complete.migrationCount!==expected.length+1))
    throw Error('fenced_revision_migration_evidence_changed');
   hasIntent||=!!intent;hasComplete||=!!complete;
  }
  if(missing&&(hasIntent||hasComplete))throw Error('fenced_revision_migration_evidence_changed');
  if(found){
   if(missing||!hasIntent||found.name!==entry.name||found.sha256!==entry.sha256||found.entries!==1)
    throw Error('fenced_revision_history_changed');
   expected=historyRows([...expected,found]);applied++;
  }else{
   if(hasComplete)throw Error('fenced_revision_history_changed');
   missing=true;
  }
 }
 if(!sameHistory(actual,expected))throw Error('fenced_revision_history_changed');
 return {applied,history:actual};
}

function qualifiedFunction(rows,slug){
 if(!Array.isArray(rows)||rows.length!==SLUGS.length||new Set(rows.map(x=>x?.slug)).size!==SLUGS.length||
    SLUGS.some(s=>!rows.some(x=>x?.slug===s)))throw Error('fenced_revision_functions_changed');
 const x=rows.find(v=>v.slug===slug);
 if(!x||x.status!=='ACTIVE'||x.verify_jwt!==false||!Number.isSafeInteger(x.version)||x.version<1||
    !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(x.id??'')||
    !/^[a-f0-9]{64}$/.test(x.ezbr_sha256??''))throw Error('fenced_revision_functions_changed');
 return x;
}
function sameBundle(expected,current){
 return expected.slug===current.slug&&expected.id===current.id&&expected.status===current.status&&
  expected.verify_jwt===current.verify_jwt&&expected.ezbr_sha256===current.ezbr_sha256&&current.version>=expected.version;
}

/** A completed attempt has an independently persisted provider readback. An
 * unconfirmed attempt with changed bytes is not safely attributable and stops. */
export function reconcileResumeFunctions(prior,current,sourceSha,readRecord,labels,requireChangedBundles=false){
 const confirmed=[];let attempted=false;
 for(const slug of SLUGS){
  const original=qualifiedFunction(prior.functions,slug),actual=qualifiedFunction(current,slug);
  let recorded=null;
  for(const label of labels){
   const attempt=readRecord('revision-'+label+'-'+slug+'-attempt.json');
   const complete=readRecord('revision-'+label+'-'+slug+'-complete.json');
   if(attempt){attempted=true;if(attempt.sourceSha256!==sourceSha)throw Error('fenced_revision_function_evidence_changed');}
   // The provider may still be processing an unacknowledged attempt even if
   // its old bundle remains visible. An unchanged readback is not settlement.
   if(attempt&&!complete)throw Error('fenced_revision_function_outcome_unknown');
   if(complete){
    if(!attempt)throw Error('fenced_revision_function_evidence_changed');
    const candidate=qualifiedFunction(SLUGS.map(s=>s===slug?complete:prior.functions.find(x=>x.slug===s)),slug);
    if(candidate.id!==original.id||candidate.version<=original.version||
       recorded&&(candidate.version<recorded.version||candidate.version===recorded.version&&!sameBundle(recorded,candidate)))
     throw Error('fenced_revision_function_evidence_changed');
    if(requireChangedBundles&&candidate.ezbr_sha256===original.ezbr_sha256)throw Error('revision_bundle_unchanged');
    recorded=candidate;
   }
  }
  if(!sameBundle(recorded??original,actual))throw Error('fenced_revision_function_outcome_unknown');
  if(recorded)confirmed.push(slug);
 }
 return {confirmed,attempted};
}
function sourceSecret(metadata,oldSource,newSource,attempted){
 const rows=Array.isArray(metadata)?metadata.filter(x=>x?.name==='BUILD_SOURCE_ID'):[];
 const old=sha(oldSource),next=sha(newSource),value=rows[0]?.value;
 if(rows.length!==1||![old,next].includes(value)||(attempted&&value!==next))
  throw Error('fenced_revision_source_secret_changed');
 return value===next?'new':'old';
}
function reconcileResumeSecret(labels,oldSource,newSource,readRecord){
 let completed=false;
 for(const label of labels){
  const attempt=readRecord('revision-'+label+'-source-secret-attempt.json');
  const complete=readRecord('revision-'+label+'-source-secret-complete.json');
  if(attempt&&(attempt.previousSourceSha256!==oldSource||attempt.sourceSha256!==newSource))
   throw Error('fenced_revision_secret_evidence_changed');
  // An old or new hash on its own cannot prove a timed-out management call
  // has settled; it may still complete after the readback.
  if(attempt&&!complete)throw Error('fenced_revision_secret_outcome_unknown');
  if(complete&&(!attempt||complete.sourceSha256!==newSource||complete.secretSha256!==sha(newSource)))
   throw Error('fenced_revision_secret_evidence_changed');
  completed||=!!complete;
 }
 return completed;
}

async function requireUpgradeReceipt(c,prior,sourceSha,readback,current){
 if(!readback||readback.sourceSha256!==sourceSha||!Array.isArray(readback.functions)||
    readback.sha256!==sha(JSON.stringify(readback.functions)))throw Error('fenced_revision_upgrade_evidence_changed');
 for(const slug of SLUGS){
  if(!sameBundle(qualifiedFunction(readback.functions,slug),qualifiedFunction(current,slug)))
   throw Error('fenced_revision_functions_changed');
 }
 const rows=(await c.query(`SELECT prior_fence_operation_id::text,old_source_sha256,old_epoch,new_source_sha256,new_epoch,
  plan_sha256,qualification_sha256,deployment_readback_sha256 FROM private.collect_fence_source_upgrades WHERE operation_id=$1::uuid`,[prior.upgradeId])).rows;
 const r=rows[0],oldEpoch=Number(prior.before?.epoch);
 if(rows.length!==1||r.prior_fence_operation_id!==prior.fenceId||r.old_source_sha256!==prior.before?.source_sha256||
    Number(r.old_epoch)!==oldEpoch||r.new_source_sha256!==sourceSha||Number(r.new_epoch)!==oldEpoch+1||
    r.plan_sha256!==sha(JSON.stringify(prior))||r.qualification_sha256!==sha(JSON.stringify({testEvidence:prior.testEvidence,checked:prior.checked}))||
    r.deployment_readback_sha256!==readback.sha256)throw Error('fenced_revision_upgrade_evidence_changed');
}

export async function reviseRuntime({label,testEvidence,migrations=[],resumeFencedRevision=null,expectedBefore=null,expectedFunctions=null,
 requireChangedBundles=false,expectedSecretPreimages=null},{
 captureSnapshot=captureRuntimeSnapshot,check=checkSnapshot,open=connect,api=management,save=record,
 readHistory=history,applyMigration=applyEntry,readRecord=readRevisionRecord
}={}){
 if(!/^[a-z][a-z0-9-]{3,60}$/.test(label)||!testEvidence||testEvidence.passed!==true)throw Error('reviewed_revision_required');
 if(!Array.isArray(migrations)||migrations.length>5)throw Error('reviewed_migrations_required');
 if(typeof requireChangedBundles!=='boolean')throw Error('reviewed_revision_required');
 const expectedSecrets=secretPreimages(expectedSecretPreimages);
 if(expectedFunctions!==null&&expectedBefore===null)throw Error('runtime_revision_preimage_changed');
 const entries=migrations.map(x=>{const e=identity(x.file,x.sql);if(e.sha256!==x.sha256)throw Error('reviewed_migration_changed');return e;});
 if(new Set(entries.map(x=>x.version)).size!==entries.length)throw Error('duplicate_revision_migration');
 if(resumeFencedRevision!==null&&!/^[a-z][a-z0-9-]{3,60}$/.test(resumeFencedRevision))throw Error('reviewed_revision_required');
 if(resumeFencedRevision===label)throw Error('reviewed_revision_required');
 const prior=resumeFencedRevision===null?null:readRecord('revision-'+resumeFencedRevision+'-intent.json');
 if(resumeFencedRevision!==null&&!prior)throw Error('revision_record_invalid');
 const snapshot=captureSnapshot(),checked=check(snapshot),c=await open();
 const name='revision-'+label;
 try{
  const f=(await c.query('SELECT mode,epoch,operation_id,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
  if(expectedBefore!==null){
   requireRevisionPreimage(expectedBefore,f);
   if(testEvidence.sourceSha256!==snapshot.sourceSha)throw Error('runtime_revision_evidence_changed');
  }
  const active=(await c.query("SELECT count(*)::int n FROM private.collect_fence_admissions a WHERE state IN('active','unresolved') AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)")).rows[0].n;
  if(!prior&&(f.mode!=='open'||f.source_sha256===snapshot.sourceSha))throw Error('runtime_revision_precondition');
  const oldEpoch=Number(prior?.before?.epoch),oldSource=prior?.before?.source_sha256;
  const beforeUpgrade=!!prior&&f.mode==='fenced'&&f.operation_id===prior.fenceId&&Number(f.epoch)===oldEpoch&&f.source_sha256===oldSource;
  const upgraded=!!prior&&f.mode==='fenced'&&f.operation_id===prior.upgradeId&&Number(f.epoch)===oldEpoch+1&&f.source_sha256===snapshot.sourceSha;
  const released=!!prior&&f.mode==='open'&&f.operation_id===prior.releaseId&&Number(f.epoch)===oldEpoch+2&&f.source_sha256===snapshot.sourceSha;
  if(prior&&(!(beforeUpgrade||upgraded||released)||(!released&&active!==0)||snapshot.sourceSha!==prior.snapshot?.sourceSha256||
      prior.testEvidence?.passed!==true||prior.testEvidence?.sourceSha256!==snapshot.sourceSha||
      testEvidence.sourceSha256!==snapshot.sourceSha||(prior.requireChangedBundles??false)!==requireChangedBundles||
      JSON.stringify(secretPreimages(prior.expectedSecretPreimages??null))!==JSON.stringify(expectedSecrets)))
   throw Error('fenced_revision_preimage_changed');
  const scheduler=released?null:requireRevisionSchedulerReady((await c.query('SELECT private._collect_fence_scheduler_status() AS status')).rows[0]?.status);
  const before=(await api('functions')).json();if(before.length!==3)throw Error('runtime_function_set_changed');
  if(expectedFunctions!==null)requireRevisionFunctions(expectedFunctions,before);
  const labels=prior?[...(prior.evidenceLabels??[]),resumeFencedRevision]:[];
  if(prior&&(new Set(labels).size!==labels.length||labels.includes(label)))throw Error('revision_record_invalid');
  const fenceId=prior?prior.fenceId:randomUUID(),upgradeId=randomUUID(),releaseId=randomUUID();
  const migrationHistory=await readHistory(c);
  let resumedHistory=null,resumedFunctions=null,resumedSecret=null;
  if(prior){
   resumedHistory=reconcileResumeHistory(prior,entries,migrationHistory,readRecord,labels);
   resumedFunctions=reconcileResumeFunctions(prior,before,snapshot.sourceSha,readRecord,labels,requireChangedBundles);
   const metadata=(await api('secrets')).json();requireSecretPreimages(expectedSecrets,metadata);
   resumedSecret=sourceSecret(metadata,oldSource,snapshot.sourceSha,resumedFunctions.attempted);
   const secretCompleted=reconcileResumeSecret(labels,oldSource,snapshot.sourceSha,readRecord);
   if(secretCompleted!==(resumedSecret==='new'))throw Error('fenced_revision_secret_evidence_changed');
   if((secretCompleted||resumedFunctions.confirmed.length>0)&&resumedHistory.applied!==entries.length)
    throw Error('fenced_revision_history_changed');
  }else if(entries.some(x=>migrationHistory.some(y=>y.version===x.version)))throw Error('revision_migration_already_recorded');
  if(upgraded||released){
   if(resumedHistory.applied!==entries.length||resumedFunctions.confirmed.length!==SLUGS.length||resumedSecret!=='new')
    throw Error('fenced_revision_upgrade_evidence_changed');
   const readback=readRecord('revision-'+resumeFencedRevision+'-deployment-readback.json');
   await requireUpgradeReceipt(c,prior,snapshot.sourceSha,readback,before);
   if(released){
    const rows=(await c.query('SELECT action,epoch,source_sha256 FROM private.collect_fence_operations WHERE operation_id=$1::uuid',[prior.releaseId])).rows;
    if(rows.length!==1||rows[0].action!=='release'||Number(rows[0].epoch)!==oldEpoch+2||rows[0].source_sha256!==snapshot.sourceSha)
     throw Error('fenced_revision_release_evidence_changed');
    return {status:'revision_already_deployed_live',sourceSha256:snapshot.sourceSha,epoch:f.epoch};
   }
   requireRevisionFunctions(before,(await api('functions')).json());
   const metadata=(await api('secrets')).json();requireSecretPreimages(expectedSecrets,metadata);
   if(sourceSecret(metadata,oldSource,snapshot.sourceSha,true)!=='new'||
      !sameHistory(await readHistory(c),migrationHistory))throw Error('fenced_revision_preimage_changed');
   save(name+'-release-resume-intent.json',{priorLabel:resumeFencedRevision,priorIntentSha256:sha(JSON.stringify(prior)),
    releaseId:prior.releaseId,sourceSha256:snapshot.sourceSha,epoch:f.epoch,at:new Date().toISOString()});
   let commit=false;await c.query('BEGIN ISOLATION LEVEL READ COMMITTED');
   try{
    await c.query('SELECT pg_advisory_xact_lock(7346371,1); SELECT pg_advisory_xact_lock(7346371,2)');
    const locked=(await c.query('SELECT mode,epoch,operation_id,source_sha256 FROM private.collect_fence_control WHERE singleton FOR UPDATE')).rows[0];
    if(!locked||locked.mode!=='fenced'||locked.operation_id!==prior.upgradeId||Number(locked.epoch)!==oldEpoch+1||
       locked.source_sha256!==snapshot.sourceSha)throw Error('fenced_revision_preimage_changed');
    await c.query('SELECT private.collect_fence_release_v3($1,$2,$3)',[prior.releaseId,f.epoch,snapshot.sourceSha]);
    commit=true;await c.query('COMMIT');
   }catch(error){if(!commit)await c.query('ROLLBACK').catch(()=>{});else error.outcome='commit_requires_reconciliation';throw error;}
   const end=(await c.query('SELECT mode,epoch,operation_id,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
   if(end.mode!=='open'||end.operation_id!==prior.releaseId||end.source_sha256!==snapshot.sourceSha||Number(end.epoch)!==oldEpoch+2)
    throw Error('revision_release_unconfirmed');
   save(name+'-release-resume-complete.json',{sourceSha256:snapshot.sourceSha,epoch:end.epoch,at:new Date().toISOString()});
   return {status:'revision_deployed_live',sourceSha256:snapshot.sourceSha,epoch:end.epoch};
  }
  const plan={before:f,activeBeforeQuiesce:active,schedulerPreflight:scheduler,functions:prior?prior.functions:before,snapshot:snapshot.summary(),checked,testEvidence,
   migrations:entries.map(({file,sha256})=>({file,sha256})),migrationHistory:prior?prior.migrationHistory:migrationHistory,
   fenceId,upgradeId,releaseId,requireChangedBundles,expectedSecretPreimages:expectedSecrets,evidenceLabels:labels,
   resumes:prior?{label:resumeFencedRevision,intentSha256:sha(JSON.stringify(prior))}:null,at:new Date().toISOString()};
  save(name+'-intent.json',plan);
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
  save(name+'-fenced.json',{fenceId,epoch:f.epoch,at:new Date().toISOString()});
  // The database fence cannot lock Supabase's management API. Recheck the
  // provider preimage immediately before any migration or source mutation.
  if(prior){
   const actual=(await api('functions')).json();requireRevisionFunctions(before,actual);
   const metadata=(await api('secrets')).json();requireSecretPreimages(expectedSecrets,metadata);
   const secret=sourceSecret(metadata,oldSource,snapshot.sourceSha,resumedFunctions.attempted);
   if(secret!==resumedSecret||!sameHistory(await readHistory(c),migrationHistory))throw Error('fenced_revision_preimage_changed');
  }else if(expectedFunctions!==null)await verifyFencedRevisionPreimage(expectedBefore,expectedFunctions,api);
  if(!prior&&expectedSecrets!==null)requireSecretPreimages(expectedSecrets,(await api('secrets')).json());
  let applied=migrationHistory;
  for(const [index,entry] of entries.entries()){
   if(prior&&index<resumedHistory.applied)continue;
   save(name+'-migration-'+entry.version+'-intent.json',{file:entry.file,sha256:entry.sha256,before:applied,at:new Date().toISOString()});
   applied=await applyMigration(c,entry,{before:applied});
   save(name+'-migration-'+entry.version+'-complete.json',{file:entry.file,sha256:entry.sha256,migrationCount:applied.length,at:new Date().toISOString()});
  }
  const changingSecret=!prior||resumedSecret==='old';
  if(changingSecret){
   save(name+'-source-secret-attempt.json',{previousSourceSha256:prior?oldSource:f.source_sha256,sourceSha256:snapshot.sourceSha,at:new Date().toISOString()});
   await api('secrets',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify([{name:'BUILD_SOURCE_ID',value:snapshot.sourceSha}])});
  }
  const secrets=(await api('secrets')).json();
  if(!Array.isArray(secrets)||secrets.filter(x=>x?.name==='BUILD_SOURCE_ID').length!==1||
     secrets.find(x=>x.name==='BUILD_SOURCE_ID')?.value!==sha(snapshot.sourceSha))throw Error('revision_source_secret_unconfirmed');
  if(changingSecret)save(name+'-source-secret-complete.json',{sourceSha256:snapshot.sourceSha,secretSha256:sha(snapshot.sourceSha),at:new Date().toISOString()});
  const deployed=[];
  const deploymentBefore=(await api('functions')).json();
  if(prior)reconcileResumeFunctions(prior,deploymentBefore,snapshot.sourceSha,readRecord,labels,requireChangedBundles);
  else for(const slug of SLUGS){
   if(!sameBundle(qualifiedFunction(before,slug),qualifiedFunction(deploymentBefore,slug)))
    throw Error('runtime_revision_functions_changed');
  }
  let expectedDeployment=deploymentBefore;
  for(const slug of SLUGS){
   if(prior&&resumedFunctions.confirmed.includes(slug)){
    deployed.push(qualifiedFunction(expectedDeployment,slug));continue;
   }
   requireRevisionFunctions(expectedDeployment,(await api('functions')).json());
   save(name+'-'+slug+'-attempt.json',{sourceSha256:snapshot.sourceSha,at:new Date().toISOString()});
   const response=(await api('functions/deploy?slug='+slug,{method:'POST',body:snapshot.makeForm(slug)})).json();
   const observed=(await api('functions')).json(),r=qualifiedFunction(observed,slug);
   const original=qualifiedFunction(prior?prior.functions:before,slug);
   if(r.id!==original.id||r.version!==response.version||r.version<=deploymentBefore.find(x=>x.slug===slug)?.version)
    throw Error('revision_deploy_unconfirmed');
   if(requireChangedBundles&&r.ezbr_sha256===original.ezbr_sha256)
    throw Error('revision_bundle_unchanged');
   expectedDeployment=expectedDeployment.map(x=>x.slug===slug?r:x);
   requireRevisionFunctions(expectedDeployment,observed);
   deployed.push(r);save(name+'-'+slug+'-complete.json',r);
  }
  const actual=(await api('functions')).json();
  requireRevisionFunctions(deployed,actual);
  const preUpgradeSecrets=(await api('secrets')).json();requireSecretPreimages(expectedSecrets,preUpgradeSecrets);
  if(sourceSecret(preUpgradeSecrets,prior?oldSource:f.source_sha256,snapshot.sourceSha,true)!=='new')throw Error('revision_source_secret_unconfirmed');
  requireRevisionFunctions(deployed,(await api('functions')).json());
  if(!sameHistory(await readHistory(c),applied))throw Error('runtime_revision_history_changed');
  save(name+'-deployment-readback.json',{sourceSha256:snapshot.sourceSha,functions:deployed,sha256:sha(JSON.stringify(deployed)),at:new Date().toISOString()});
  await c.query('SELECT private.collect_fence_upgrade_source_v3($1,$2,$3,$4,$5,$6,$7,$8)',[upgradeId,fenceId,f.epoch,f.source_sha256,snapshot.sourceSha,sha(JSON.stringify(plan)),sha(JSON.stringify({testEvidence,checked})),sha(JSON.stringify(deployed))]);
  const mid=(await c.query('SELECT mode,epoch,operation_id,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
  if(mid.mode!=='fenced'||mid.operation_id!==upgradeId||mid.source_sha256!==snapshot.sourceSha||Number(mid.epoch)!==Number(f.epoch)+1)throw Error('revision_upgrade_unconfirmed');
  save(name+'-upgraded.json',mid);
  requireRevisionFunctions(deployed,(await api('functions')).json());
  const preReleaseSecrets=(await api('secrets')).json();requireSecretPreimages(expectedSecrets,preReleaseSecrets);
  if(sourceSecret(preReleaseSecrets,prior?oldSource:f.source_sha256,snapshot.sourceSha,true)!=='new')throw Error('revision_source_secret_unconfirmed');
  if(!sameHistory(await readHistory(c),applied))throw Error('runtime_revision_history_changed');
  await c.query('SELECT private.collect_fence_release_v3($1,$2,$3)',[releaseId,mid.epoch,snapshot.sourceSha]);
  const end=(await c.query('SELECT mode,epoch,operation_id,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
  if(end.mode!=='open'||end.operation_id!==releaseId||end.source_sha256!==snapshot.sourceSha||Number(end.epoch)!==Number(mid.epoch)+1)throw Error('revision_release_unconfirmed');
  const result={sourceSha256:snapshot.sourceSha,epoch:end.epoch,functions:deployed,at:new Date().toISOString()};save(name+'-complete.json',result);
  return {status:'revision_deployed_live',sourceSha256:snapshot.sourceSha,epoch:end.epoch};
 }finally{await c.end();}
}
