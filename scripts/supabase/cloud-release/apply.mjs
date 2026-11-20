import {readFileSync,existsSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {connect,management,record,ROOT,PROJECT} from './access.mjs';
import {SOURCE,chain,history,resolveEntry,applyEntry,identity,retirement} from './migrations.mjs';

if(process.argv.length!==3||!['--retire','--schema'].includes(process.argv[2]))throw Error('explicit_phase_required');
const phase=process.argv[2],c=await connect();
try{
 const hold=JSON.parse(readFileSync(ROOT+'/hold-complete.json','utf8'));
 const live=(await management('functions')).json();
 if(live.length!==3||hold.after.some(f=>!live.some(x=>x.slug===f.slug&&x.id===f.id&&x.version===f.version&&x.ezbr_sha256===f.ezbr_sha256)))throw Error('maintenance_deployment_changed');
 if(Date.now()<Date.parse(hold.retirementNotBefore))throw Error('worker_retirement_wait_required');
 const initial=JSON.parse(readFileSync(ROOT+'/initial-history.json','utf8'));
 const entries=await chain();
 if(initial.length!==14||initial.some((h,i)=>h.version!==entries[i].version||h.sha256!==entries[i].sha256||h.entries!==1))throw Error('original_history_source_mismatch');
 let before=await history(c);
 async function apply(entry,afterBody){
  let name='migration-'+entry.version;
  if(existsSync(ROOT+'/'+name+'-intent.json')){
   const prior=JSON.parse(readFileSync(ROOT+'/'+name+'-intent.json','utf8'));
   const failure=JSON.parse(readFileSync(ROOT+'/'+name+'-failure.json','utf8'));
   // This one failure happened before sending the migration body. ROLLBACK
   // and connection closure completed; require its unchanged history again.
   if(entry.version!=='20261113130200'||failure.message!=='migration_transaction_shape'||failure.outcome!=='rolled_back'
    ||prior.sha256!==entry.sha256||JSON.stringify(prior.before)!==JSON.stringify(before))throw Error('prior_attempt_requires_reconciliation_'+entry.version);
   name+='-frame-fix';
   record(name+'-reconciliation.json',{previousOutcome:'rolled_back_before_body',historyUnchanged:true,at:new Date().toISOString()});
  }
  record(name+'.sql',entry.sql);
  record(name+'-intent.json',{file:entry.file,sha256:entry.sha256,before,at:new Date().toISOString()});
  try{
   before=await applyEntry(c,entry,{before,afterBody});
   record(name+'-complete.json',{file:entry.file,sha256:entry.sha256,migrationCount:before.length,at:new Date().toISOString()});
   console.log(JSON.stringify({status:'applied_and_read_back',migration:entry.file,count:before.length}));
  }catch(e){record(name+'-failure.json',{code:e.code??null,message:String(e.message).slice(0,200),outcome:e.outcome??'rolled_back',at:new Date().toISOString()});throw e;}
 }
 if(phase==='--retire'){
  if(JSON.stringify(before)!==JSON.stringify(initial))throw Error('retirement_history_changed');
  const entry=identity(retirement,readFileSync(SOURCE+'/supabase/migrations/'+retirement,'utf8'));
  await apply(entry,async db=>{
   const state=(await db.query('select * from private.collect_fence_control where singleton')).rows[0];
   if(state.mode!=='quiescing'||state.operation_id!==hold.operation)throw Error('hold_changed');
   const pending=(await db.query("select to_jsonb(a) snapshot from private.collect_fence_admissions a where state<>'settled' and not private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)")).rows;
   if(pending.length!==1||pending[0].snapshot.kind!=='http_collect'||pending[0].snapshot.epoch!==13)throw Error('unexpected_retirement_graph');
   const evidence={format:'collect.managed-executor-retirement.v1',project:PROJECT,fenceOperationId:hold.operation,
    maintenanceVerifiedAt:hold.verifiedAt,maximumWorkerLifetimeSeconds:400,externalEffectsSettled:false,
    limitsSource:'https://supabase.com/docs/guides/functions/limits',functions:hold.after.map(f=>({slug:f.slug,status:f.status,version:String(f.version),previousVersion:String(hold.before.find(x=>x.slug===f.slug).version),bundleSha256:f.ezbr_sha256,previousBundleSha256:hold.before.find(x=>x.slug===f.slug).ezbr_sha256}))};
   for(const {snapshot:a} of pending)await db.query(`INSERT INTO private.collect_managed_executor_retirements(operation_id,admission_id,fence_operation_id,epoch,source_sha256,kind,project_ref,maintenance_verified_at,evidence_sha256,evidence,original_admission,retained_unknown_obligation_id)
    VALUES($1,$2,$3,$4,$5,$6,$7,$8,encode(sha256(convert_to($9::jsonb::text,'UTF8')),'hex'),$9,$10,$11)`,[randomUUID(),a.admission_id,hold.operation,a.epoch,a.source_sha256,a.kind,PROJECT,hold.verifiedAt,JSON.stringify(evidence),JSON.stringify(a),randomUUID()]);
   const r=(await db.query('select private.collect_fence_drain_managed_v1($1,$2,$3) value',[hold.operation,state.epoch,state.source_sha256])).rows[0].value;
   if(r.mode!=='fenced'||r.managedExecutorsRetired!==1||r.externalEffectsSettled!==false)throw Error('retirement_drain_failed');
  });
 }else{
  for(const candidate of entries.slice(14)){
   const existing=before.find(h=>h.version===candidate.version);
   if(existing){if(existing.sha256!==candidate.sha256||existing.name!==candidate.name||existing.entries!==1)throw Error('recorded_source_mismatch');continue;}
   const entry=await resolveEntry(c,candidate);
   await apply(entry);
  }
  record('schema-complete.json',{migrations:before.length,at:new Date().toISOString(),accountsPresent:(await c.query("select to_regclass('private.burimunsi_accounts') is not null value")).rows[0].value});
 }
}finally{await c.end();}
