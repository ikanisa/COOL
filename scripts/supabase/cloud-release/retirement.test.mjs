import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {withOwnedArchiveFixture} from '../managed-migration-next/synthetic-fixture.mjs';

let checks=0;
await withOwnedArchiveFixture(async({owner,watcher,admin,backendPid})=>{
 const source='a'.repeat(64),fence=randomUUID(),admission=randomUUID();
 const verified=new Date(Date.now()-600000).toISOString();
 await owner.query(`INSERT INTO private.collect_fence_control(singleton,project_ref,baseline_manifest_sha256,source_sha256,epoch,mode,operation_id,changed_at)
 VALUES(true,'rrlduytparvsjfmegalh','dfc7a4fafb696f73d207251c9f35cb892528eecd1929552fa575996874adc3e3',$1,1,'quiescing',$2,clock_timestamp()-interval '1000 seconds')`,[source,fence]);
 await owner.query(`INSERT INTO private.collect_fence_admissions(admission_id,epoch,source_sha256,kind,created_at,state)
 VALUES($1,1,$2,'http_collect',clock_timestamp()-interval '2000 seconds','active')`,[admission,source]);
 await owner.query(await readFile(new URL('../../../supabase/migrations/20261117064828_collect_managed_executor_retirement.sql',import.meta.url),'utf8'));
 const snapshot=(await owner.query('SELECT to_jsonb(a) value FROM private.collect_fence_admissions a WHERE admission_id=$1',[admission])).rows[0].value;
 const proof={format:'collect.managed-executor-retirement.v1',project:'rrlduytparvsjfmegalh',fenceOperationId:fence,
  maintenanceVerifiedAt:verified,maximumWorkerLifetimeSeconds:400,externalEffectsSettled:false,
  limitsSource:'https://supabase.com/docs/guides/functions/limits',functions:['collect-api','admin-api','collect-jobs'].map(slug=>({slug,status:'ACTIVE',version:'2',previousVersion:'1',bundleSha256:'b'.repeat(64),previousBundleSha256:'c'.repeat(64)}))};
 const insert=`INSERT INTO private.collect_managed_executor_retirements(operation_id,admission_id,fence_operation_id,epoch,source_sha256,kind,project_ref,maintenance_verified_at,evidence_sha256,evidence,original_admission,retained_unknown_obligation_id)
 VALUES($1,$2,$3,1,$4,'http_collect','rrlduytparvsjfmegalh',$5,encode(sha256(convert_to($6::jsonb::text,'UTF8')),'hex'),$6::jsonb,$7::jsonb,$8)`;
 const values=(p=proof,s=snapshot)=>[randomUUID(),admission,fence,source,p.maintenanceVerifiedAt,JSON.stringify(p),JSON.stringify(s),randomUUID()];
 const denied=async(fn)=>{await assert.rejects(fn,e=>['55000','42501','23505'].includes(e.code));checks++;};
 await denied(()=>owner.query('SELECT private.collect_fence_drain_managed_v1($1,1,$2)',[fence,source]));
 await denied(()=>owner.query(insert,values({...proof,maintenanceVerifiedAt:new Date().toISOString()})));
 await denied(()=>owner.query(insert,values({...proof,project:'another-project'})));
 await denied(()=>owner.query(insert,values({...proof,externalEffectsSettled:true})));
 await denied(()=>owner.query(insert,values({...proof,functions:proof.functions.slice(1)})));
 await denied(()=>owner.query(insert,values({...proof,functions:proof.functions.map(x=>({...x,bundleSha256:null}))})));
 await denied(()=>owner.query(insert,values(proof,{...snapshot,state:'settled'})));
 await owner.query('BEGIN');await owner.query('SET LOCAL ROLE collect_runtime');
 await denied(()=>owner.query(insert,values()));await owner.query('ROLLBACK');
 // A surviving old worker can assert while quiescing, so the owner must wait
 // for its existing WORK lease before recording retirement. The next worker
 // then waits behind the same owner transaction until both retirement and
 // FENCED commit. This uses the original SQL functions and two real sessions.
 await watcher.query('BEGIN');await watcher.query('SET LOCAL ROLE collect_runtime');
 await watcher.query("SELECT set_config('collect.edge_verified','true',true)");
 await watcher.query('SELECT pg_advisory_xact_lock_shared(7346371,1)');
 const prior=(await watcher.query('SELECT private.collect_fence_assert_work($1,1,$2) AS value',[admission,source])).rows[0].value;
 assert.equal(prior.mode,'quiescing');checks++;
 await owner.query('BEGIN');let finished=false;
 const retirement=owner.query(insert,values()).then(v=>{finished=true;return v;});
 async function waits(pid){
  for(let i=0;i<100;i++){
   const row=(await admin.query("SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid=$1 AND locktype='advisory' AND NOT granted) AS blocked",[pid])).rows[0];
   if(row.blocked)return true;if(finished)return false;await new Promise(resolve=>setTimeout(resolve,20));
  }
  return false;
 }
 assert.equal(await waits(backendPid),true,'retirement must wait for the existing WORK lease');checks++;
 await watcher.query('COMMIT');await retirement;checks++;
 const watcherPid=(await watcher.query('SELECT pg_backend_pid() pid')).rows[0].pid;
 await watcher.query('BEGIN');await watcher.query('SET LOCAL ROLE collect_runtime');
 await watcher.query("SELECT set_config('collect.edge_verified','true',true)");
 finished=false;const pendingWork=watcher.query('SELECT pg_advisory_xact_lock_shared(7346371,1)').then(v=>{finished=true;return v;});
 assert.equal(await waits(watcherPid),true,'new old-tuple WORK must wait until the owner transaction commits');checks++;
 const result=(await owner.query('SELECT private.collect_fence_drain_managed_v1($1,1,$2) value',[fence,source])).rows[0].value;
 assert.equal(result.mode,'fenced');assert.equal(result.managedExecutorsRetired,1);assert.equal(result.externalEffectsSettled,false);checks+=3;
 await owner.query('COMMIT');await pendingWork;
 await denied(()=>watcher.query('SELECT private.collect_fence_assert_work($1,1,$2)',[admission,source]));
 await watcher.query('ROLLBACK');
 await watcher.query('BEGIN');await watcher.query('SET LOCAL ROLE collect_runtime');
 await watcher.query("SELECT set_config('collect.edge_verified','true',true)");
 await denied(()=>watcher.query('SELECT private.collect_fence_assert_write($1,1,$2)',[admission,source]));
 await watcher.query('ROLLBACK');
 await denied(()=>owner.query(insert,values()));
 assert.deepEqual((await owner.query('SELECT to_jsonb(a) value FROM private.collect_fence_admissions a WHERE admission_id=$1',[admission])).rows[0].value,snapshot);checks++;
 await denied(()=>owner.query("UPDATE private.collect_fence_admissions SET state='settled',reason='completed',closed_at=clock_timestamp() WHERE admission_id=$1",[admission]));
 await denied(()=>owner.query('DELETE FROM private.collect_managed_executor_retirements'));
 const repeat=(await owner.query('SELECT private.collect_fence_drain_managed_v1($1,1,$2) value',[fence,source])).rows[0].value;
 assert.equal(repeat.mode,'fenced');assert.equal(repeat.externalEffectsSettled,false);checks+=2;
 await denied(()=>owner.query('SELECT private.collect_fence_release_v3($1,1,$2)',[randomUUID(),source]));
});
console.log(JSON.stringify({status:'PASS',checks,productionDispatched:false,originalAdmissionPreserved:true}));
