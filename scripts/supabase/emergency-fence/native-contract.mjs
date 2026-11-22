// ROOT-ONLY EXECUTABLE PLAN. UNEXECUTED by candidate author.
// Requires a NEW loopback collect_fence_sql_<hex>_test DB already prepared with
// fixture00 + eight unchanged migrations + candidate9 + explicit source a64 init.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
// Failure diagnostics are a closed, non-authorizing schema. Never print an
// Error object, message, stack, query, assertion operand, connection URL or code
// other than a shape-checked SQLSTATE from a PostgreSQL severity-bearing error.
let checks=0;
const FAILURE_FORMAT='collect.emergency-fence.native-failure.v1';
const FAILURE_TYPES=Object.freeze(['assertion','postgres','type_error','range_error','syntax_error','reference_error','error','unknown']);
function failureField(value,key){try{return value?.[key];}catch{return undefined;}}
function failureSqlState(error){
 for(const item of [error,failureField(error,'cause'),failureField(error,'actual')]){
  const code=failureField(item,'code'),severity=failureField(item,'severity');
  if(typeof code==='string'&&/^[0-9A-Z]{5}$/.test(code)&&['ERROR','FATAL','PANIC'].includes(severity))return code;
 }return null;
}
function failureSourceLine(error){
 const stack=failureField(error,'stack');if(typeof stack!=='string')return null;
 const ownUrl=import.meta.url.replace(/[.*+?^${}()|[\]\\]/g,'\\$&');
 const framePattern=new RegExp('^\\s+at (?:async )?(?:[^\\n()]+ \\()?'+ownUrl+':([1-9][0-9]{0,4}):[1-9][0-9]{0,4}\\)?$');
 let first=null;
 for(const frame of stack.split(/\r?\n/).slice(1,80)){
  const matched=frame.match(framePattern);if(!matched)continue;
  const line=Number(matched[1]);if(!Number.isSafeInteger(line)||line<1||line>10000)continue;
  first??=line;
  // Prefer the contract call site to the two shared assertion helpers.
  if(!/^\s+at (?:async )?(?:check|deny) \(/.test(frame))return line;
 }return first;
}
function safeFailure(error){
 const sqlState=failureSqlState(error);let type='unknown';
 if(failureField(error,'code')==='ERR_ASSERTION')type='assertion';
 else if(sqlState!==null)type='postgres';
 else if(error instanceof TypeError)type='type_error';
 else if(error instanceof RangeError)type='range_error';
 else if(error instanceof SyntaxError)type='syntax_error';
 else if(error instanceof ReferenceError)type='reference_error';
 else if(error instanceof Error)type='error';
 return{format:FAILURE_FORMAT,version:1,type:FAILURE_TYPES.includes(type)?type:'unknown',sqlState,
  checkCount:Number.isSafeInteger(checks)&&checks>=0&&checks<10000?checks:null,sourceLine:failureSourceLine(error)};
}

async function main(){
const url=process.env.COLLECT_FENCE_SQL_TEST_DATABASE_URL;
let parsed;try{parsed=new URL(url);}catch{throw new Error('FENCE_LOCAL_FIXTURE_URL_REQUIRED');}
const ciSynthetic=process.env.COLLECT_CI_SYNTHETIC==='true'&&parsed.hostname==='127.0.0.1';
const named=/^\/collect_fence_sql_[a-f0-9]{8,32}_test$/.test(parsed.pathname)||(ciSynthetic&&parsed.pathname==='/collect_fence_sql_test');
if(!['postgres:','postgresql:'].includes(parsed.protocol)||!parsed.username||!parsed.password||!parsed.port||!['127.0.0.1','localhost','[::1]'].includes(parsed.hostname)||!named||parsed.search||parsed.hash)throw new Error('FENCE_LOCAL_FIXTURE_URL_REQUIRED');
const require=createRequire(import.meta.url);const {Client}=require(process.env.COLLECT_PG_MODULE??'pg');
const options={connectionString:url,connectionTimeoutMillis:5000,statement_timeout:10000};
const owner=new Client(options),runtime=new Client(options),lease=new Client(options),stale=new Client(options);
const source='a'.repeat(64);let leaseHeld=false;
const check=(value)=>{assert(value);checks++;};
async function rt(text,values=[]){
 await runtime.query('BEGIN ISOLATION LEVEL READ COMMITTED');
 try{
  await runtime.query('SET LOCAL ROLE collect_runtime');
  await runtime.query("SELECT set_config('collect.edge_verified','true',true)");
  const result=await runtime.query(text,values);await runtime.query('COMMIT');return result.rows[0]?.value;
 }catch(error){await runtime.query('ROLLBACK').catch(()=>{});throw error;}
}
async function deny(operation,message){await assert.rejects(operation,error=>error.message.includes(message));checks++;}
async function beginWork(id,epoch){
 await lease.query('BEGIN ISOLATION LEVEL READ COMMITTED');leaseHeld=true;
 await lease.query("SET LOCAL idle_in_transaction_session_timeout='60s'");
 await lease.query('SET LOCAL ROLE collect_runtime');
 await lease.query("SELECT set_config('collect.edge_verified','true',true)");
 await lease.query('SELECT pg_advisory_xact_lock_shared(7346371,1)');
 return (await lease.query('SELECT private.collect_fence_assert_work($1,$2,$3) AS value',[id,epoch,source])).rows[0].value;
}
async function write(id,epoch){
 await runtime.query('BEGIN ISOLATION LEVEL READ COMMITTED');
 try{
  await runtime.query('SET LOCAL ROLE collect_runtime');
  await runtime.query("SELECT set_config('collect.edge_verified','true',true),set_config('collect.fence_admission_id',$1,true),set_config('collect.fence_epoch',$2,true),set_config('collect.fence_source_sha256',$3,true)",[id,String(epoch),source]);
  await runtime.query('SELECT private.collect_fence_assert_write($1,$2,$3)',[id,epoch,source]);
  await runtime.query('UPDATE app.auth_rate_buckets SET used=used WHERE false');
  await runtime.query('COMMIT');
 }catch(error){await runtime.query('ROLLBACK').catch(()=>{});throw error;}
}
async function status(){return(await owner.query('SELECT private.collect_fence_owner_status() AS value')).rows[0].value;}
async function tempShadowDenied(id,epoch){
 // The local fixture owner prepares malicious session-temp relations without
 // broadening runtime TEMP/table privileges. Calls execute as collect_runtime.
 // No native shared WORK lock exists on this business connection.
 await runtime.query('BEGIN ISOLATION LEVEL READ COMMITTED');
 await runtime.query('CREATE TEMP TABLE pg_locks(locktype text,pid integer,database oid,classid oid,objid oid,objsubid smallint,mode text,granted boolean)');
 await runtime.query("INSERT INTO pg_temp.pg_locks SELECT 'advisory',pg_catalog.pg_backend_pid(),d.oid,7346371::oid,1::oid,2::smallint,'ShareLock',true FROM pg_catalog.pg_database d WHERE d.datname=pg_catalog.current_database()");
 await runtime.query('SET LOCAL ROLE collect_runtime');
 await runtime.query("SELECT pg_catalog.set_config('collect.edge_verified','true',true)");
 await deny(()=>runtime.query('SELECT private.collect_fence_assert_work($1,$2,$3)',[id,epoch,source]),'collect_fence_unavailable');
 await runtime.query('ROLLBACK');
 // Forge the control-owner catalog projection. Safe SECURITY DEFINER paths
 // must still use real pg_catalog relations and deny the runtime null bypass.
 await runtime.query('BEGIN ISOLATION LEVEL READ COMMITTED');
 await runtime.query('CREATE TEMP TABLE pg_namespace(oid oid,nspname name)');
 await runtime.query('CREATE TEMP TABLE pg_class(relowner oid,relnamespace oid,relname name)');
 await runtime.query("INSERT INTO pg_temp.pg_namespace VALUES(1::oid,'private')");
 await runtime.query("INSERT INTO pg_temp.pg_class SELECT r.oid,1::oid,'collect_fence_control' FROM pg_catalog.pg_roles r WHERE r.rolname='collect_runtime'");
 await runtime.query('SET LOCAL ROLE collect_runtime');
 await runtime.query("SELECT pg_catalog.set_config('collect.edge_verified','true',true)");
 await deny(()=>runtime.query('SELECT private.collect_fence_assert_write(NULL,NULL,NULL)'),'collect_fence_forbidden');
 await runtime.query('ROLLBACK');
}
async function appHashes(){
 const tables=(await owner.query("SELECT tablename FROM pg_tables WHERE schemaname='app' ORDER BY tablename COLLATE \"C\"")).rows;
 const results=[];for(const {tablename}of tables){
  assert(/^[a-z0-9_]+$/.test(tablename));
  const row=(await owner.query(`SELECT count(*)::text AS count,encode(sha256(convert_to(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text COLLATE "C"),'[]'::jsonb)::text,'UTF8')),'hex') AS sha256 FROM app."${tablename}" t`)).rows[0];
  results.push({table:tablename,...row});
 }return results;
}
try{
 await owner.connect();await runtime.connect();await lease.connect();await stale.connect();
 const identity=(await owner.query("SELECT current_database() AS db,host(inet_server_addr()) AS host,current_setting('server_version_num') AS version")).rows[0];
 check(identity.db===decodeURIComponent(parsed.pathname.slice(1))&&['127.0.0.1','::1'].includes(identity.host)&&/^17/.test(identity.version));
 const initial=await status();check(initial.mode==='open'&&initial.epoch===1&&initial.sourceSha256===source&&initial.activeAdmissions===0&&initial.unresolvedAdmissions===0&&initial.schedulerStatus.blocking===false);
 const pristine=(await owner.query('SELECT (SELECT count(*)::text FROM private.collect_fence_admissions) AS admissions,(SELECT count(*)::text FROM private.collect_fence_operations) AS operations')).rows[0];
 check(pristine.admissions==='0'&&pristine.operations==='1');
 const before=await appHashes();check(before.length===97);
 check(initial.resourceLimits.retainedAdmissionLimit===100000&&initial.resourceLimits.activeWorkLimit===8&&initial.resourceLimits.settledRetentionEnabled===false);
 const pending=[];for(let n=0;n<8;n++){const id=randomUUID();pending.push(id);await rt('SELECT private.collect_fence_register($1,$2,$3) AS value',[id,source,'jobs']);}
 await deny(()=>rt('SELECT private.collect_fence_register($1,$2,$3) AS value',[randomUUID(),source,'jobs']),'collect_fence_capacity');
 check((await status()).resourceLimits.activeAndUnresolvedAdmissions===8);
 for(const id of pending)await rt('SELECT private.collect_fence_close($1,$2,$3,$4,$5,$6,$7) AS value',[id,1,source,'settled','cancelled_before_work',0,0]);
 check((await status()).activeAdmissions===0);
 await stale.query('BEGIN ISOLATION LEVEL REPEATABLE READ');
 check((await stale.query('SELECT mode FROM private.collect_fence_control')).rows[0].mode==='open');
 const first=randomUUID();check((await rt('SELECT private.collect_fence_register($1,$2,$3) AS value',[first,source,'jobs'])).state==='active');
 await tempShadowDenied(first,1);
 await deny(()=>rt('SELECT private.collect_fence_register($1,$2,$3) AS value',[first,source,'jobs']),'collect_fence_conflict');
 await deny(()=>rt('SELECT private.collect_fence_assert_write(NULL,NULL,NULL) AS value'),'collect_fence_forbidden');
 check((await beginWork(first,1)).mode==='open');await write(first,1);checks++;
 const quiesce=randomUUID();check((await owner.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3) AS value',[quiesce,1,source])).rows[0].value.mode==='quiescing');
 await deny(()=>rt('SELECT private.collect_fence_register($1,$2,$3) AS value',[randomUUID(),source,'jobs']),'collect_fence_closed');
 check((await lease.query('SELECT private.collect_fence_assert_work($1,$2,$3) AS value',[first,1,source])).rows[0].value.mode==='quiescing');
 await write(first,1);checks++;
 await deny(()=>owner.query('UPDATE app.auth_rate_buckets SET used=used WHERE false'),'collect_fence_closed');
 await owner.query('BEGIN');await owner.query("SET LOCAL lock_timeout='150ms'");
 await deny(()=>owner.query('SELECT private.collect_fence_drain($1,$2,$3)',[quiesce,1,source]),'lock timeout');await owner.query('ROLLBACK');
 check((await status()).mode==='quiescing');
 check((await rt('SELECT private.collect_fence_close($1,$2,$3,$4,$5,$6,$7) AS value',[first,1,source,'settled','completed_with_unknown_obligation',1,1])).state==='settled');
 await lease.query('ROLLBACK');leaseHeld=false;
 const fenced=(await owner.query('SELECT private.collect_fence_drain($1,$2,$3) AS value',[quiesce,1,source])).rows[0].value;
 check(fenced.mode==='fenced'&&fenced.applicationFenceComplete===true&&fenced.retainedUnknownObligations===1&&fenced.providerSettlement===false&&fenced.wholeSystemAcceptance===false);
 // SQL11 first requires exclusive WORK then WRITE before a source change.
 // Preserve both independent refusals: no lock authority, then forged lineage.
 const controlBeforeSourceDenials=(await owner.query('SELECT to_jsonb(c) AS row FROM private.collect_fence_control c WHERE singleton')).rows;
 const lineageBeforeSourceDenials=(await owner.query('SELECT to_jsonb(u) AS row FROM private.collect_fence_source_upgrades u ORDER BY operation_id')).rows;
 await assert.rejects(()=>owner.query("UPDATE private.collect_fence_control SET source_sha256=repeat('b',64) WHERE singleton"),
  error=>error.code==='55000'&&error.message==='collect_fence_upgrade_locks_required');checks++;
 await owner.query('BEGIN ISOLATION LEVEL READ COMMITTED');
 try{
  await owner.query('SELECT pg_advisory_xact_lock(7346371,1)');
  await owner.query('SELECT pg_advisory_xact_lock(7346371,2)');
  await assert.rejects(()=>owner.query("UPDATE private.collect_fence_control SET source_sha256=repeat('b',64) WHERE singleton"),
   error=>error.code==='55000'&&error.message==='collect_fence_conflict');checks++;
 }finally{assert.equal((await owner.query('ROLLBACK')).command,'ROLLBACK');checks++;}
 assert.deepEqual((await owner.query('SELECT to_jsonb(c) AS row FROM private.collect_fence_control c WHERE singleton')).rows,controlBeforeSourceDenials);checks++;
 assert.deepEqual((await owner.query('SELECT to_jsonb(u) AS row FROM private.collect_fence_source_upgrades u ORDER BY operation_id')).rows,lineageBeforeSourceDenials);checks++;
 // An old MVCC snapshot still sees OPEN, but is never admitted to write.
 check((await stale.query('SELECT mode FROM private.collect_fence_control')).rows[0].mode==='open');
 await deny(()=>stale.query('UPDATE app.runtime_config SET value_json=value_json WHERE false'),'collect_fence_unavailable');await stale.query('ROLLBACK');
 for(const sql of ['UPDATE app.runtime_config SET value_json=value_json WHERE false','DELETE FROM app.runtime_config WHERE false','INSERT INTO app.runtime_config SELECT * FROM app.runtime_config WHERE false','TRUNCATE app.runtime_config'])await deny(()=>owner.query(sql),'collect_fence_closed');
 const release=randomUUID();const open=(await owner.query('SELECT private.collect_fence_release($1,$2,$3) AS value',[release,1,source])).rows[0].value;
 check(open.mode==='open'&&open.epoch===2&&open.retainedUnknownObligations===1&&open.resourceLimits.capacityBlocked===false);
 await deny(()=>write(first,1),'collect_fence_conflict');
 const lost=randomUUID();await rt('SELECT private.collect_fence_register($1,$2,$3) AS value',[lost,source,'jobs']);check((await beginWork(lost,2)).mode==='open');
 // Losing this connection releases a native lock but NOT the durable admission.
 await lease.end();leaseHeld=false;
 const second=randomUUID();await owner.query('SELECT private.collect_fence_begin_quiesce($1,$2,$3)',[second,2,source]);
 const blocked=(await owner.query('SELECT private.collect_fence_drain($1,$2,$3) AS value',[second,2,source])).rows[0].value;
 check(blocked.mode==='quiescing'&&blocked.activeAdmissions===1&&blocked.applicationFenceComplete===false);
 await rt('SELECT private.collect_fence_close($1,$2,$3,$4,$5,$6,$7) AS value',[lost,2,source,'unresolved','lease_lost',0,0]);
 const unresolved=(await owner.query('SELECT private.collect_fence_drain($1,$2,$3) AS value',[second,2,source])).rows[0].value;
 check(unresolved.mode==='quiescing'&&unresolved.unresolvedAdmissions===1&&unresolved.applicationFenceComplete===false);
 await deny(()=>rt('SELECT private.collect_fence_close($1,$2,$3,$4,$5,$6,$7) AS value',[lost,2,source,'settled','completed',0,0]),'collect_fence_conflict');
 await deny(()=>owner.query('DELETE FROM private.collect_fence_admissions WHERE admission_id=$1',[lost]),'collect_fence_history_immutable');
 await deny(()=>owner.query('SELECT private.collect_fence_release($1,$2,$3)',[randomUUID(),2,source]),'collect_fence_conflict');
 assert.deepEqual(await appHashes(),before);checks++;
 console.log(JSON.stringify({status:'PASS',checks,fixture:'new_unique_loopback_only',app_tables_unchanged:97,final_mode:'quiescing',durable_unresolved_preserved:1,retained_unknown_obligations:1,provider_calls:0,hosted_acceptance:false,sb29Satisfied:false}));
}finally{
 if(leaseHeld)await lease.query('ROLLBACK').catch(()=>{});
 await stale.query('ROLLBACK').catch(()=>{});
 await Promise.allSettled([owner.end(),runtime.end(),lease.end(),stale.end()]);
}
}

await main().catch(error=>{
 process.exitCode=1;console.error(JSON.stringify(safeFailure(error)));
});
