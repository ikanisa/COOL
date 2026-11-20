// One-use retirement of the existing source before the Cloud-only cutover.
// Originals and unknown external effects remain retained, never settled here.
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,existsSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {ROOT,record,sha} from './access.mjs';

const D='/Applications/Docker.app/Contents/Resources/bin/docker';
const db='supabase_db_local-app',edge='supabase_edge_runtime_local-app';
const docker=(args,opts={})=>execFileSync(D,['--context','colima-supabase-local',...args],{maxBuffer:20000000,timeout:60000,...opts});
const lit=x=>"'"+String(x).replaceAll("'","''")+"'";
const sql=s=>docker(['exec','-i',db,'psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:s,encoding:'utf8'}).trim();
const json=s=>JSON.parse(sql(s));
const inspect=n=>{const x=JSON.parse(docker(['inspect',n],{encoding:'utf8'}))[0];return{id:x.Id,name:x.Name,image:x.Image,running:x.State.Running,started:x.State.StartedAt,finished:x.State.FinishedAt,mounts:x.Mounts.map(m=>({type:m.Type,source:m.Source,destination:m.Destination,rw:m.RW}))};};
const status=()=>json(`SELECT jsonb_build_object('control',(SELECT to_jsonb(c) FROM private.collect_fence_control c WHERE singleton),'scheduler',private._collect_fence_scheduler_status(),'unmatched',(SELECT coalesce(jsonb_agg(to_jsonb(a)),'[]') FROM private.collect_fence_admissions a WHERE state<>'settled' AND NOT private._collect_stopped_matches(a.admission_id,a.epoch,a.source_sha256,a.kind)),'originalCount',(SELECT count(*) FROM private.collect_fence_admissions WHERE state<>'settled'));`);
const phase=process.argv[2];if(process.argv.length!==3||!['--quiesce','--retire'].includes(phase))throw Error('source_phase_required');
if(phase==='--quiesce'){
 const before=status(),database=inspect(db),runtime=inspect(edge);
 if(before.control.mode!=='open'||before.control.epoch!==56||before.unmatched.length!==1||before.scheduler.blocking!==false||database.id!=='2b1edd8ffa8f4149445d1af4042d6d10f6dfdb44a6ecd839e8ed0d94ce43abb6'||runtime.id!=='7fec198386959bb537a16dfb30692b3031f1f244a4616cc26449fedeeea60903')throw Error('source_preimage_changed');
 let operation=randomUUID();
 if(existsSync(ROOT+'/source-hold-intent.json')){
  const original=JSON.parse(readFileSync(ROOT+'/source-hold-intent.json','utf8'));
  if(existsSync(ROOT+'/source-quiesce-complete.json')||JSON.stringify(original.before)!==JSON.stringify(before)||original.database.id!==database.id||original.runtime.id!==runtime.id)throw Error('prior_source_hold_requires_reconciliation');
  operation=original.operation;
 }else record('source-hold-intent.json',{operation,before,database,runtime});
 for(const label of ['com.ikanisa.collect.runtime-startup','com.ikanisa.collect.burimunsi-auto-sms']){
  const target='gui/'+process.getuid()+'/'+label;
  spawnSync('launchctl',['bootout',target]);
  for(let i=0;i<10&&spawnSync('launchctl',['print',target]).status===0;i++)await new Promise(r=>setTimeout(r,300));
  if(spawnSync('launchctl',['print',target]).status===0)throw Error('source_agent_still_loaded');
  execFileSync('launchctl',['disable',target]);
 }
 const q=json(`SELECT private.collect_fence_begin_quiesce(${lit(operation)},${before.control.epoch},${lit(before.control.source_sha256)});`);
 if(q.mode!=='quiescing')throw Error('source_quiesce_unconfirmed');
 record('source-quiesce-complete.json',{operation,result:q,at:new Date().toISOString()});
 // Stop every existing application/provider writer; keep the database only
 // for owner-controlled reads, custody and the final graph snapshot.
 const names=docker(['ps','--format','{{.Names}}'],{encoding:'utf8'}).trim().split('\n').filter(n=>n.startsWith('supabase_')&&n.endsWith('_local-app')&&n!==db);
 for(const name of names){const before=inspect(name);docker(['stop','--time','20',name]);const after=inspect(name);if(after.running||before.id!==after.id)throw Error('source_stop_unconfirmed');record('source-stopped-'+name.replaceAll('_','-')+'.json',{before,after});}
 const held=status();if(held.control.mode!=='quiescing'||held.control.operation_id!==operation||JSON.stringify(held.unmatched)!==JSON.stringify(before.unmatched)||held.scheduler.blocking!==false)throw Error('source_hold_changed');
 record('source-writers-stopped.json',{operation,containers:names,unmatched:held.unmatched.length,originalCount:held.originalCount,at:new Date().toISOString()});
 console.log(JSON.stringify({status:'source_quiesced_writers_stopped',containers:names.length,originalAdmissionsRetained:held.originalCount}));
}else{
 const intent=JSON.parse(readFileSync(ROOT+'/source-hold-intent.json','utf8'));
 const stopped=JSON.parse(readFileSync(ROOT+'/source-writers-stopped.json','utf8'));
 const custody=JSON.parse(readFileSync(ROOT+'/source-final-custody-result.json','utf8'));
 if(custody.status!=='encrypted_source_database_custody_verified'||custody.readbackMatches!==true||custody.archiveDecrypts!==true)throw Error('source_custody_required');
 const before=status();if(before.control.mode!=='quiescing'||before.control.operation_id!==intent.operation||before.scheduler.blocking!==false||before.unmatched.length!==1)throw Error('source_retirement_precondition');
 for(const n of stopped.containers)if(inspect(n).running)throw Error('source_writer_running');
 const dbBefore=inspect(db);record('source-db-restart-intent.json',{id:dbBefore.id,at:new Date().toISOString()});
 docker(['stop','--time','30',db]);const dbStopped=inspect(db);if(dbStopped.running)throw Error('source_db_stop_unconfirmed');record('source-db-stopped.json',dbStopped);
 docker(['start',db]);
 let boot;for(let i=0;i<30;i++){try{boot=json("SELECT to_jsonb(pg_postmaster_start_time());");break;}catch{await new Promise(r=>setTimeout(r,1000));}}
 if(!boot||Date.parse(boot)<=Date.parse(before.unmatched[0].created_at))throw Error('source_db_restart_unconfirmed');
 // Briefly start the same edge process behind committed QUIESCING solely to
 // prove the old process is gone, then stop it permanently before snapshot.
 docker(['start',edge]);const restarted=inspect(edge);docker(['stop','--time','20',edge]);const edgeStopped=inspect(edge);
 if(!restarted.running||edgeStopped.running||restarted.id!==intent.runtime.id||Date.parse(restarted.started)<=Date.parse(before.unmatched[0].created_at))throw Error('source_edge_restart_unconfirmed');
 record('source-executors-retired.json',{database:inspect(db),boot,edgeStarted:restarted,edgeStopped,at:new Date().toISOString()});
 const settings=JSON.parse(readFileSync('/Volumes/PRO-G40/Projects/COLLECT-Production/2026-11-10/runtime-startup-001/settings-storage-v1901-3ba874bee879.private.json','utf8'));
 const vm=Object.fromEntries(['profile','lima_instance','volume_uuid','image_path'].map(k=>[k,settings[k]]));
 const witness={format:'collect.local-vm-executor-stopped.v1',vmIdentitySha256:sha(JSON.stringify(vm)),runtimeVolumeUuid:vm.volume_uuid,databaseId:dbBefore.id,databaseBootAt:boot,edgeContainerId:restarted.id,edgeStartedAt:restarted.started,stoppedBindingSha256:sha(readFileSync(ROOT+'/source-db-stopped.json')),custodyReceiptSha256:sha(readFileSync(ROOT+'/source-final-custody-result.json')),resumedReceiptSha256:sha(readFileSync(ROOT+'/source-executors-retired.json'))};
 record('source-retirement-witness.json',witness);
 const a=before.unmatched[0],recovery=randomUUID(),unknown=randomUUID();
 const obligation={admission:a.admission_id,unknownObligationId:unknown,originalEffectsUnknown:true,providerSettlement:false};record('source-retained-unknown.json',obligation);
 const result=json(`BEGIN; SELECT pg_advisory_xact_lock(7346371,1); SELECT pg_advisory_xact_lock(7346371,2); SELECT private.collect_fence_record_local_stopped_v1(${lit(recovery)},${lit(intent.operation)},${lit(a.admission_id)},${a.epoch},${lit(a.source_sha256)},${lit(a.kind)},${lit(sha(JSON.stringify({a,witness})))},${lit(unknown)},${lit(sha(JSON.stringify(obligation)))},${lit(JSON.stringify(witness))}::jsonb); COMMIT;`);
 if(result.originalAdmission.admission_id!==a.admission_id||result.originalCountersRecovered!==false)throw Error('source_retirement_readback');
 record('source-retirement-recorded.json',{recovery,unknown,originalAdmissionRetained:true,externalEffectsSettled:false});
 const drained=json(`SELECT private.collect_fence_drain_v3(${lit(intent.operation)},${a.epoch},${lit(a.source_sha256)});`);
 const final=status();if(drained.mode!=='fenced'||final.control.mode!=='fenced'||final.unmatched.length!==0||final.originalCount!==before.originalCount)throw Error('source_fence_unconfirmed');
 record('source-fenced-complete.json',{operation:intent.operation,control:final.control,originalCount:final.originalCount,retainedUnknown:true,at:new Date().toISOString()});
 console.log(JSON.stringify({status:'source_fenced_executors_retired',originalAdmissionsRetained:final.originalCount,externalEffectsSettled:false}));
}
