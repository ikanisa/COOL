// ROOT ONLY. UNEXECUTED SOURCE. Each case needs a NEW separately prepared local
// DB with fixture00 + eight unchanged migrations + current candidate + source a64
// explicit initialization. Never deletes receipt/proof history or resets schemas.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
const raw=process.env.COLLECT_FENCE_SQL_CAPACITY_DATABASE_URL;
let target;try{target=new URL(raw);}catch{throw new Error('FENCE_CAPACITY_LOCAL_FIXTURE_REQUIRED');}
const ci=process.env.COLLECT_CI_SYNTHETIC==='true'&&target.hostname==='127.0.0.1';
const unique=/^\/collect_fence_capacity_(proof|release)_[a-f0-9]{8,32}_test$/.exec(target.pathname);
const fixed=ci?/^\/collect_fence_(proof|release)_test$/.exec(target.pathname):null;
const scenario=unique?.[1]??fixed?.[1];
if(!['postgres:','postgresql:'].includes(target.protocol)||!target.username||!target.password||!target.port||!['127.0.0.1','localhost','[::1]'].includes(target.hostname)||!scenario||target.search||target.hash)throw new Error('FENCE_CAPACITY_LOCAL_FIXTURE_REQUIRED');
const require=createRequire(import.meta.url);const {Client}=require(process.env.COLLECT_PG_MODULE??'pg');
const options={connectionString:raw,connectionTimeoutMillis:5000,statement_timeout:120000};
const owner=new Client(options),left=new Client(options),right=new Client(options),stale=new Client(options);
const clients=[owner,left,right,stale],source='a'.repeat(64);let checks=0;
const check=value=>{assert(value);checks++;};
async function denied(call,message){await assert.rejects(call,error=>error.message.includes(message));checks++;}
async function status(){return(await owner.query('SELECT private.collect_fence_owner_status() AS value')).rows[0].value;}
async function appHashes(){
 const names=(await owner.query("SELECT tablename FROM pg_tables WHERE schemaname='app' ORDER BY tablename COLLATE \"C\"")).rows;
 const out=[];for(const {tablename}of names){
  assert(/^[a-z0-9_]+$/.test(tablename));
  const row=(await owner.query(`SELECT count(*)::text AS count,encode(sha256(convert_to(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text COLLATE "C"),'[]'::jsonb)::text,'UTF8')),'hex') AS sha256 FROM app."${tablename}" t`)).rows[0];out.push({table:tablename,...row});
 }return out;
}
async function insertProof(client,id){
 await client.query('BEGIN ISOLATION LEVEL READ COMMITTED');
 try{
  await client.query('INSERT INTO private.collect_fence_scheduler_lifecycle(dispatch_id,native_epoch,evidence_sha256,review_operation_id) VALUES($1,$2,$3,$4)',[id,source,'b'.repeat(64),randomUUID()]);
  await client.query('COMMIT');
 }catch(error){await client.query('ROLLBACK').catch(()=>{});throw error;}
}
async function rrInsertDenied(table){
 await stale.query('BEGIN ISOLATION LEVEL REPEATABLE READ');
 await stale.query('SELECT count(*) FROM private.'+table);
 if(table==='collect_fence_scheduler_lifecycle')await denied(()=>stale.query('INSERT INTO private.collect_fence_scheduler_lifecycle(dispatch_id,native_epoch,evidence_sha256,review_operation_id) VALUES($1,$2,$3,$4)',[randomUUID(),source,'b'.repeat(64),randomUUID()]),'collect_fence_unavailable');
 else await denied(()=>stale.query('INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) VALUES($1,$2,$3,$4)',[randomUUID(),'drain',1,source]),'collect_fence_unavailable');
 await stale.query('ROLLBACK');
}
try{
 for(const client of clients)await client.connect();
 const identity=(await owner.query("SELECT current_database() AS db,host(inet_server_addr()) AS host,current_setting('server_version_num') AS version,current_setting('default_transaction_isolation') AS isolation")).rows[0];
 check(identity.db===decodeURIComponent(target.pathname.slice(1))&&['127.0.0.1','::1'].includes(identity.host)&&/^17/.test(identity.version)&&identity.isolation==='read committed');
 const initial=await status();check(initial.mode==='open'&&initial.epoch===1&&initial.sourceSha256===source&&initial.activeAdmissions===0&&initial.unresolvedAdmissions===0&&initial.schedulerStatus.blocking===false);
 check(initial.resourceLimits.retainedAdmissions===0&&initial.resourceLimits.operationReceipts===1&&initial.resourceLimits.schedulerLifecycleProofs===0);
 const before=await appHashes();check(before.length===97);
 // Shared direct-insert trigger must enforce isolation on BOTH target tables.
 // No admission, helper or client grant is fabricated to make this pass.
 await rrInsertDenied('collect_fence_scheduler_lifecycle');
 await rrInsertDenied('collect_fence_operations');
 if(scenario==='proof'){
  // Synthetic owner-only history population is capacity data, never evidence
  // of real provider settlement. Every row passes the actual RC capacity trigger.
  await owner.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  await owner.query("INSERT INTO private.collect_fence_scheduler_lifecycle(dispatch_id,native_epoch,evidence_sha256,review_operation_id) SELECT md5('capacity-proof:'||n)::uuid,repeat('a',64),repeat('b',64),md5('capacity-proof-review:'||n)::uuid FROM generate_series(1,9999)n");
  await owner.query('COMMIT');
  await stale.query('BEGIN ISOLATION LEVEL REPEATABLE READ');
  check((await stale.query('SELECT count(*)::text AS count FROM private.collect_fence_scheduler_lifecycle')).rows[0].count==='9999');
  const raced=await Promise.allSettled([insertProof(left,randomUUID()),insertProof(right,randomUUID())]);
  check(raced.filter(r=>r.status==='fulfilled').length===1);
  check(raced.filter(r=>r.status==='rejected'&&r.reason.message.includes('collect_fence_capacity')).length===1);
  check((await status()).resourceLimits.schedulerLifecycleProofs===10000);
  // Prior broken source could see9999 after waiting for the unchanged control
  // row, then insert10001. Corrected source refuses RR before count/row lock.
  check((await stale.query('SELECT count(*)::text AS count FROM private.collect_fence_scheduler_lifecycle')).rows[0].count==='9999');
  await denied(()=>stale.query('INSERT INTO private.collect_fence_scheduler_lifecycle(dispatch_id,native_epoch,evidence_sha256,review_operation_id) VALUES($1,$2,$3,$4)',[randomUUID(),source,'b'.repeat(64),randomUUID()]),'collect_fence_unavailable');
  await stale.query('ROLLBACK');
  check((await status()).resourceLimits.schedulerLifecycleProofs===10000);
  await denied(()=>owner.query('DELETE FROM private.collect_fence_scheduler_lifecycle WHERE false'),'collect_fence_history_immutable');
  const operation=randomUUID();await owner.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3)',[operation,1,source]);
  const fenced=(await owner.query('SELECT private.collect_fence_drain($1,$2,$3) AS value',[operation,1,source])).rows[0].value;
  check(fenced.mode==='fenced'&&fenced.applicationFenceComplete===true&&fenced.resourceLimits.capacityBlocked===true);
  await denied(()=>owner.query('SELECT private.collect_fence_release($1,$2,$3)',[randomUUID(),1,source]),'collect_fence_capacity');
 }else{
  const operation=randomUUID();await owner.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3)',[operation,1,source]);
  await owner.query('SELECT private.collect_fence_drain($1,$2,$3)',[operation,1,source]);
  check((await status()).resourceLimits.operationReceipts===3);
  // Reach the exact post-release boundary using synthetic local owner audit
  // rows. All retained rows remain immutable; no controller history is deleted.
  await owner.query('BEGIN ISOLATION LEVEL READ COMMITTED');
  await owner.query("INSERT INTO private.collect_fence_operations(operation_id,action,epoch,source_sha256) SELECT md5('capacity-operation:'||n)::uuid,'drain',1,repeat('a',64) FROM generate_series(1,9994)n");
  await owner.query('COMMIT');
  const boundary=await status();check(boundary.mode==='fenced'&&boundary.resourceLimits.operationReceipts===9997&&boundary.resourceLimits.capacityBlocked===false);
  // Adding one release receipt would reach9998 and immediately block new
  // admissions. Successful release must not return such an OPEN state.
  await denied(()=>owner.query('SELECT private.collect_fence_release($1,$2,$3)',[randomUUID(),1,source]),'collect_fence_capacity');
  const preserved=await status();check(preserved.mode==='fenced'&&preserved.epoch===1&&preserved.operationId===operation&&preserved.resourceLimits.operationReceipts===9997);
 }
 assert.deepEqual(await appHashes(),before);checks++;
 console.log(JSON.stringify({status:'PASS',scenario,checks,app_tables_unchanged:97,provider_calls:0,managed_writes:0,fixture:'new_loopback_only',hosted_capacity_accepted:false,sb29Satisfied:false}));
}finally{
 for(const client of clients)await client.query('ROLLBACK').catch(()=>{});
 await Promise.allSettled(clients.map(client=>client.end()));
}
