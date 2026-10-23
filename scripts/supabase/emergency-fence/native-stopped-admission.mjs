// Root-only native contract. Requires a NEW retained loopback PG17 fixture,
// all14 migrations, explicit source a64 initialization; creates no database.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {randomUUID,randomInt} from 'node:crypto';
const raw=process.env.COLLECT_STOPPED_ADMISSION_TEST_DATABASE_URL;
delete process.env.COLLECT_STOPPED_ADMISSION_TEST_DATABASE_URL;
let checks=0,phase='target';
const check=x=>{assert(x);checks++;};
async function main(){
 let target;try{target=new URL(raw);}catch{throw new Error('LOCAL_FIXTURE_REQUIRED');}
 const ci=process.env.COLLECT_CI_SYNTHETIC==='true'&&target.hostname==='127.0.0.1';
 if(!['postgres:','postgresql:'].includes(target.protocol)||!target.username||!target.password||!target.port
  ||!['127.0.0.1','[::1]'].includes(target.hostname)||target.search||target.hash
  ||!(/^\/collect_fence_stopped_[a-f0-9]{8,32}_test$/.test(target.pathname)||(ci&&target.pathname==='/collect_fence_stopped_test')))throw new Error('LOCAL_FIXTURE_REQUIRED');
 const require=createRequire(import.meta.url),{Client}=require(process.env.COLLECT_PG_MODULE??'pg');
 const options={connectionString:raw,ssl:false,connectionTimeoutMillis:5000,statement_timeout:10000};
 const owner=new Client(options),runtime=new Client(options),lease=new Client(options);
 const clients=[owner,runtime,lease];let lost=false,held=false;
 for(const client of clients)client.on('error',()=>{lost=true;});
 const source='a'.repeat(64),next='b'.repeat(64),evidence='c'.repeat(64),absence='d'.repeat(64),obligationEvidence='e'.repeat(64);
 const orphan=randomUUID(),other=randomUUID(),unresolved=randomUUID(),fence=randomUUID(),recovery=randomUUID(),obligation=randomUUID();
 let roleName,roleOid;
 const call='SELECT private.collect_fence_record_stopped_admission_v3($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) AS value';
 const args=()=>[recovery,fence,'rrlduytparvsjfmegalh',orphan,1,source,'jobs',evidence,roleOid,roleName,absence,true,obligation,obligationEvidence];
 async function status(){check(!lost);return(await owner.query('SELECT private.collect_fence_owner_status_v3() AS value')).rows[0].value;}
 async function rt(sql,values=[]){
  await runtime.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  try{await runtime.query('SET LOCAL ROLE collect_runtime');await runtime.query("SELECT set_config('collect.edge_verified','true',true)");
   const r=await runtime.query(sql,values);await runtime.query('COMMIT');return r.rows[0]?.value;
  }catch(error){await runtime.query('ROLLBACK').catch(()=>{});throw error;}
 }
 async function denied(fn,state='55000') {await assert.rejects(fn,e=>e.code===state);checks++;}
 async function record(values=args()){return(await owner.query(call,values)).rows[0].value;}
 async function drain(){return(await owner.query('SELECT private.collect_fence_drain_v3($1,$2,$3) AS value',[fence,1,source])).rows[0].value;}
 async function rawAdmission(){return(await owner.query('SELECT to_jsonb(a) AS value FROM private.collect_fence_admissions a WHERE admission_id=$1',[orphan])).rows[0].value;}
 try{
  phase='identity';for(const client of clients)await client.connect();
  const identity=(await owner.query("SELECT current_database() AS db,host(inet_server_addr()) AS host,current_setting('server_version_num') AS version,current_user AS owner,session_user AS session")).rows[0];
  check(identity.db===decodeURIComponent(target.pathname.slice(1))&&['127.0.0.1','::1'].includes(identity.host)&&/^17/.test(identity.version)&&identity.owner==='postgres'&&identity.session==='postgres');
  const initial=await status();check(initial.contractVersion===3&&initial.mode==='open'&&initial.epoch===1&&initial.sourceSha256===source&&initial.rawActiveAdmissions===0&&initial.schedulerStatus.blocking===false);
  check((await owner.query('SELECT count(*)::int AS n FROM private.collect_fence_stopped_admissions')).rows[0].n===0);
  phase='register';for(const id of [orphan,other,unresolved])await rt('SELECT private.collect_fence_register($1,$2,$3) AS value',[id,source,'jobs']);
  await rt('SELECT private.collect_fence_close($1,$2,$3,$4,$5,$6,$7) AS value',[unresolved,1,source,'unresolved','work_lost',0,0]);
  const before=await rawAdmission();
  roleName='collect_cf_preserve_'+randomInt(10000000,99999999);check(/^[a-z0-9_]+$/.test(roleName));
  const rolePassword=randomUUID();
  await owner.query('CREATE ROLE "'+roleName+'" LOGIN PASSWORD \''+rolePassword+'\' NOINHERIT NOCREATEROLE NOCREATEDB NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 2');
  roleOid=(await owner.query('SELECT oid::text AS oid FROM pg_roles WHERE rolname=$1',[roleName])).rows[0].oid;
  const roleTarget=new URL(raw);roleTarget.username=roleName;roleTarget.password=rolePassword;
  const roleClient=new Client({...options,connectionString:roleTarget.href});roleClient.on('error',()=>{lost=true;});clients.push(roleClient);await roleClient.connect();
  phase='quiesce';
  await owner.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  await owner.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3)',[fence,1,source]);
  await assert.rejects(()=>record(),e=>e.code==='55000'&&e.message==='collect_stopped_committed_quiesce_required');checks++;
  await owner.query('ROLLBACK');
  await owner.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3)',[fence,1,source]);
  await denied(()=>record()); // Actual original role still exists.
  await lease.query('BEGIN ISOLATION LEVEL READ COMMITTED');held=true;
  await lease.query('SET LOCAL ROLE collect_runtime');await lease.query("SELECT set_config('collect.edge_verified','true',true)");
  await lease.query('SELECT pg_advisory_xact_lock_shared(7346371,1)');
  await lease.query('SELECT private.collect_fence_assert_work($1,$2,$3)',[orphan,1,source]);
  await owner.query('BEGIN');await owner.query("SET LOCAL lock_timeout='150ms'");
  await denied(()=>record(),'55P03');await owner.query('ROLLBACK');
  await lease.query('ROLLBACK');held=false;
  await owner.query('DROP ROLE "'+roleName+'"');
  await denied(()=>record()); // OID row absent but original authenticated backend survives.
  await roleClient.end();clients.splice(clients.indexOf(roleClient),1);
  let remaining=1;
  for(let n=0;n<20&&remaining;n++){
   await owner.query('SELECT pg_stat_clear_snapshot()');
   remaining=(await owner.query('SELECT count(*)::int AS n FROM pg_stat_activity WHERE usesysid=$1::oid',[roleOid])).rows[0].n;
   if(remaining)await new Promise(resolve=>setTimeout(resolve,50));
  }check(remaining===0);
  phase='refusals';
  const wrongRole=args();wrongRole[8]=(await owner.query("SELECT oid::text AS oid FROM pg_roles WHERE rolname='postgres'")).rows[0].oid;
  await denied(()=>record(wrongRole)); // Original OID reuse/any live OID refuses.
  for(const [index,value] of [[2,'wrong-project'],[4,2],[5,next],[6,'http_admin']]){const bad=args();bad[index]=value;await denied(()=>record(bad));}
  const badEvidence=args();badEvidence[7]='invalid';await denied(()=>record(badEvidence),'23514');
  const counters=args();counters[11]=false;await denied(()=>record(counters),'22023');
  await denied(()=>rt(call,args()),'42501');
  await owner.query('BEGIN ISOLATION LEVEL REPEATABLE READ');await denied(()=>record());await owner.query('ROLLBACK');
  phase='record';const accepted=await record();check(accepted.contractVersion===3&&accepted.found&&accepted.stoppedLifecycle.recovered_external_dispatches===null&&accepted.stoppedLifecycle.original_counters_unavailable===true);
  check(accepted.unknownObligationSettled===false&&accepted.providerSettlement===false&&accepted.runtimeFinishRecovered===false);
  assert.deepEqual(await rawAdmission(),before);checks++;
  await denied(()=>record(),'23505');
  const conflicting=args();conflicting[0]=randomUUID();conflicting[7]='f'.repeat(64);await denied(()=>record(conflicting),'23505');
  const reconciled=(await owner.query('SELECT private.collect_fence_stopped_admission_status_v3($1) AS value',[recovery])).rows[0].value;
  assert.deepEqual(reconciled,accepted);checks++;
  await denied(()=>owner.query('UPDATE private.collect_fence_stopped_admissions SET evidence_bundle_sha256=repeat(\'f\',64) WHERE recovery_operation_id=$1',[recovery]));
  await denied(()=>owner.query('DELETE FROM private.collect_fence_stopped_admissions WHERE recovery_operation_id=$1',[recovery]));
  await assert.rejects(()=>owner.query("UPDATE private.collect_fence_admissions SET state='settled',reason='completed',external_dispatches=0,uncertain_dispatches=0,closed_at=clock_timestamp() WHERE admission_id=$1",[orphan]),
   e=>e.code==='55000'&&e.message==='collect_stopped_admission_immutable');checks++;
  await denied(()=>rt('SELECT private.collect_fence_assert_write($1,$2,$3)',[orphan,1,source]));
  await denied(()=>rt('SELECT private.collect_fence_close($1,$2,$3,$4,$5,$6,$7)',[orphan,1,source,'settled','completed',0,0]));
  await lease.query('BEGIN');held=true;await lease.query('SET LOCAL ROLE collect_runtime');await lease.query("SELECT set_config('collect.edge_verified','true',true)");await lease.query('SELECT pg_advisory_xact_lock_shared(7346371,1)');
  await denied(()=>lease.query('SELECT private.collect_fence_assert_work($1,$2,$3)',[orphan,1,source]));await lease.query('ROLLBACK');held=false;
  const blocked=await drain();check(blocked.mode==='quiescing'&&blocked.rawActiveAdmissions===2&&blocked.effectiveActiveAdmissions===1&&blocked.effectiveUnresolvedAdmissions===1&&blocked.stoppedLocalAdmissions===1&&blocked.retainedUnquantifiedUnknownObligations===1);
  await denied(()=>owner.query('SELECT private.collect_fence_release_v3($1,$2,$3)',[randomUUID(),1,source]));
  // Close only the genuinely live synthetic OTHER work through its real API.
  await rt('SELECT private.collect_fence_close($1,$2,$3,$4,$5,$6,$7)',[other,1,source,'settled','completed',0,0]);
  check((await drain()).effectiveUnresolvedAdmissions===1);
  // Retain a separate proof for the synthetic unresolved row. Its counters are
  // still unavailable to recovery; no source admission UPDATE is manufactured.
  const second=args();second[0]=randomUUID();second[3]=unresolved;second[12]=randomUUID();await record(second);
  phase='legacy-and-scheduler';
  const legacy=(await owner.query('SELECT private.collect_fence_drain($1,$2,$3) AS value',[fence,1,source])).rows[0].value;
  check(legacy.contractVersion===1&&legacy.mode==='quiescing'&&legacy.activeAdmissions===1&&legacy.unresolvedAdmissions===1&&legacy.applicationFenceComplete===false);
  // Existing scheduler contract regards any queued native request as blocking.
  check((await owner.query("SELECT count(*)::int AS n FROM pg_extension WHERE extname='pg_net'")).rows[0].n===0);
  const queueExists=(await owner.query("SELECT to_regclass('net.http_request_queue') IS NOT NULL AS yes")).rows[0].yes;
  if(!queueExists){
   await owner.query('CREATE SCHEMA IF NOT EXISTS net');
   await owner.query('CREATE TABLE net.http_request_queue(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,method text,url text)');
  }
  const queued=(await owner.query('INSERT INTO net.http_request_queue(method,url) VALUES($1,$2) RETURNING id',['GET','http://127.0.0.1/owned-stopped-fixture'])).rows[0].id;
  check((await drain()).mode==='quiescing');
  // This is an explicitly owned synthetic queue row, no pg_net worker/provider.
  await owner.query('DELETE FROM net.http_request_queue WHERE id=$1',[queued]);
  const fenced=await drain();check(fenced.mode==='fenced'&&fenced.localLeaseDrainComplete===true&&fenced.applicationFenceComplete===false&&fenced.rawActiveAdmissions===1&&fenced.effectiveActiveAdmissions===0&&fenced.retainedUnquantifiedUnknownObligations===2);
  phase='source-upgrade';const upgrade=randomUUID(),upgradeArgs=[upgrade,fence,1,source,next,evidence,absence,obligationEvidence];
  await denied(()=>owner.query('SELECT private.collect_fence_upgrade_source_v2($1,$2,$3,$4,$5,$6,$7,$8)',upgradeArgs));
  await owner.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  await owner.query('SELECT private.collect_fence_upgrade_source_v3($1,$2,$3,$4,$5,$6,$7,$8)',upgradeArgs);
  await denied(()=>owner.query('SELECT private.collect_fence_release_v3($1,$2,$3)',[randomUUID(),2,next]));
  await owner.query('ROLLBACK');
  const upgraded=(await owner.query('SELECT private.collect_fence_upgrade_source_v3($1,$2,$3,$4,$5,$6,$7,$8) AS value',upgradeArgs)).rows[0].value;
  check(upgraded.contractVersion===3&&upgraded.upgrade.lifecycle_protocol_version===3&&upgraded.control.source_sha256===next&&upgraded.control.mode==='fenced'&&upgraded.control.epoch===2);
  // Upgrade and release must be independently committed, never in one tx.
  const released=(await owner.query('SELECT private.collect_fence_release_v3($1,$2,$3) AS value',[randomUUID(),2,next])).rows[0].value;
  check(released.mode==='open'&&released.epoch===3&&released.rawActiveAdmissions===1&&released.effectiveActiveAdmissions===0&&released.providerSettlement===false&&released.retainedUnquantifiedUnknownObligations===2);
  assert.deepEqual(await rawAdmission(),before);checks++;
  console.log(JSON.stringify({status:'PASS',checks,fixture:'new_unique_loopback_only',raw_admission_unchanged:true,stopped_local_proofs:2,unquantified_unknown_obligations:2,counters_recovered:false,provider_calls:0,hosted_acceptance:false,sb29Satisfied:false}));
 }finally{
  if(held)await lease.query('ROLLBACK').catch(()=>{});
  await owner.query('ROLLBACK').catch(()=>{});
  await Promise.allSettled(clients.map(x=>x.end()));
 }
}
main().catch(error=>{
 const code=typeof error?.code==='string'&&/^[0-9A-Z]{5}$/.test(error.code)?error.code:null;
 console.error(JSON.stringify({format:'collect.stopped-admission.native-failure.v1',phase,checks,sqlState:code,type:error?.code==='ERR_ASSERTION'?'assertion':code?'postgres':'error'}));process.exitCode=1;
});
