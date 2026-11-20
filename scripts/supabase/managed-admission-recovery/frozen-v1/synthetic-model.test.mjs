import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {assertSyntheticEnvironment,createSyntheticAdmissionFixture,executeManagedAdmissionRecovery} from './synthetic-fixture.mjs';

const id=()=>randomUUID();
const sql=(name,n)=>`SELECT admission_fixture.${name}(${Array.from({length:n},(_,i)=>'$'+(i+1)).join(',')}) AS result`;
const call=async(db,name,args=[]) => (await db.query(sql(name,args.length),args)).rows[0].result;
const denied=async(p,pattern)=>assert.rejects(p,e=>pattern.test(e.message));
async function usingFixture(fn){const f=await createSyntheticAdmissionFixture();try{return await fn(f);}finally{const result=await f.close();assert.equal(result.removed,true);}}
async function preimage(f,admission){return (await f.db.query('SELECT to_jsonb(a) AS row FROM admission_fixture.admissions a WHERE admission_id=$1',[admission])).rows[0].row;}
async function registered(f){const admission=id();await call(f.db,'register',[admission,f.epoch,f.source]);return admission;}

test('fixture rejects managed options and the installer refuses another database',{timeout:120000},async()=>{
 assert.throws(()=>executeManagedAdmissionRecovery(),e=>e.code==='MANAGED_OR_REAL_EXECUTION_REFUSED');
 for(const env of [{DATABASE_URL:'synthetic-external'},{PGHOST:'synthetic-external'},{SUPABASE_URL:'synthetic-external'},
  {COLLECT_SYNTHETIC_PG_BIN:'/untrusted'}])assert.throws(()=>assertSyntheticEnvironment(env));
 await assert.rejects(createSyntheticAdmissionFixture({connectionString:'synthetic-external'}),e=>e.code==='SYNTHETIC_ONLY_REFUSAL');
 await usingFixture(async f=>{
  assert.equal(f.providerCalls,0);
  await denied(f.admin.query(f.sql),/SYNTHETIC_ONLY_REFUSAL/);
  assert.equal((await f.admin.query("SELECT to_regnamespace('admission_fixture') AS schema")).rows[0].schema,null);
 });
});

test('committed quiescence, exact preimage and immutable unknown obligation',{timeout:120000},async()=>{
 await usingFixture(async f=>{
  const a=await registered(f),before=await preimage(f,a),q=id(),r=id();
  await f.db.query('BEGIN');await call(f.db,'quiesce',[q,f.epoch,f.source]);
  await denied(call(f.db,'tombstone',[r,q,a,before]),/SYNTHETIC_COMMITTED_QUIESCE_REQUIRED/);await f.db.query('ROLLBACK');
  assert.equal((await call(f.db,'status')).mode,'open');assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.used_ids')).rows[0].n,1);
  await call(f.db,'quiesce',[q,f.epoch,f.source]);
  await denied(call(f.db,'tombstone',[r,id(),a,before]),/SYNTHETIC_COMMITTED_QUIESCE_REQUIRED/);
  await denied(call(f.db,'tombstone',[r,null,a,before]),/SYNTHETIC_COMMITTED_QUIESCE_REQUIRED/);
  await denied(call(f.db,'tombstone',[r,q,a,{...before,external_dispatches:1}]),/SYNTHETIC_PREIMAGE_CHANGED/);
  await denied(call(f.db,'tombstone',[a,q,a,before]),/SYNTHETIC_ID_REPLAY/);
  await f.db.query('BEGIN');await call(f.db,'tombstone',[r,q,a,before]);
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.obligations')).rows[0].n,1);await f.db.query('ROLLBACK');
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.obligations')).rows[0].n,0);
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.used_ids WHERE id=$1',[r])).rows[0].n,0);
  const result=await call(f.db,'tombstone',[r,q,a,before]);assert.deepEqual(result,{fixture:true,tombstone_written:true,effect_status:'unknown',actor_closure_proven:false,cutover_authorized:false});
  assert.deepEqual(await preimage(f,a),before);
  const obligation=(await f.db.query('SELECT effect_status,effect_scope,actor_closure_proven FROM admission_fixture.obligations')).rows[0];
  assert.deepEqual(obligation,{effect_status:'unknown',effect_scope:'all_external_effects',actor_closure_proven:false});
  for(const table of ['admissions','tombstones','obligations','used_ids'])await denied(f.db.query(`DELETE FROM admission_fixture.${table}`),/SYNTHETIC_APPEND_ONLY/);
  await denied(f.db.query('TRUNCATE admission_fixture.obligations'),/SYNTHETIC_APPEND_ONLY/);
  const rejected=id();await denied(call(f.db,'tombstone',[rejected,q,a,before]),/duplicate key|SYNTHETIC_ID_REPLAY/);
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.used_ids WHERE id=$1',[rejected])).rows[0].n,0);
  await denied(call(f.db,'tombstone',[r,q,a,before]),/SYNTHETIC_ID_REPLAY/);
  await denied(call(f.db,'close_or_release'),/SYNTHETIC_CLOSE_RELEASE_UNQUALIFIED/);
  await denied(call(f.db,'resolve_unknown_effect'),/SYNTHETIC_EFFECT_RESOLUTION_UNIMPLEMENTED/);
  await denied(call(f.db,'upgrade_source'),/SYNTHETIC_SOURCE_UPGRADE_UNQUALIFIED/);
  const status=await call(f.db,'status');assert.equal(status.unknown_obligations,1);assert.equal(status.provider_settlement_proven,false);
  assert.equal(status.actor_closure_proven,false);assert.equal(status.release_authorized,false);assert.equal(status.cutover_authorized,false);
 });
});

test('a prior assertion acknowledgement cannot be revoked by a later tombstone',{timeout:120000},async()=>{
 await usingFixture(async f=>{
  const a=await registered(f),before=await preimage(f,a),first=await f.actorOne(),second=await f.actorTwo();
  await denied(call(first,'quiesce',[id(),f.epoch,f.source]),/permission denied/);
  await denied(call(first,'claim_id',[id(),'synthetic']),/permission denied/);
  for(const actor of [first,second]){
   const ack=await call(actor,'assert_work',[a,f.epoch,f.source]);assert.equal(ack.asserted,true);assert.equal(ack.external_effect_permit,false);
  }
  let release;const gate=new Promise(resolve=>{release=resolve;});let callbacks=0;
  const late=(async()=>{await gate;callbacks++;})();
  const q=id();await call(f.db,'quiesce',[q,f.epoch,f.source]);await call(f.db,'tombstone',[id(),q,a,before]);
  for(const actor of [first,second])await denied(call(actor,'assert_work',[a,f.epoch,f.source]),/SYNTHETIC_ASSERT_REFUSED/);
  await denied(call(first,'prepare_effect',[a,f.epoch,f.source,id(),id()]),/SYNTHETIC_EFFECT_REFUSED/);
  await denied(call(first,'register',[id(),f.epoch,f.source]),/SYNTHETIC_REGISTER_REFUSED/);
  await denied(first.query("DELETE FROM admission_fixture.obligations"),/permission denied/);
  release();await late;assert.equal(callbacks,1,'a deliberately scheduled in-memory callback can run after the tombstone');
  assert.equal(f.providerCalls,0,'the fixture has no provider client');
  const status=await call(f.db,'status');assert.equal(status.unknown_obligations,1);assert.equal(status.actor_closure_proven,false);assert.equal(status.cutover_authorized,false);
 });
});

test('a snapshot taken before the tombstone cannot authorize stale work',{timeout:120000},async()=>{
 await usingFixture(async f=>{
  const a=await registered(f),before=await preimage(f,a),actor=await f.actorOne();
  await actor.query('BEGIN ISOLATION LEVEL REPEATABLE READ');await actor.query('SELECT 1');
  const q=id();await call(f.db,'quiesce',[q,f.epoch,f.source]);await call(f.db,'tombstone',[id(),q,a,before]);
  await denied(call(actor,'assert_work',[a,f.epoch,f.source]),/SYNTHETIC_READ_COMMITTED_REQUIRED/);await actor.query('ROLLBACK');
  await actor.query('BEGIN ISOLATION LEVEL SERIALIZABLE');await actor.query('SELECT 1');
  await denied(call(actor,'assert_work',[a,f.epoch,f.source]),/SYNTHETIC_READ_COMMITTED_REQUIRED/);await actor.query('ROLLBACK');
  const operator=await f.connect();await operator.query('BEGIN ISOLATION LEVEL REPEATABLE READ');
  await denied(call(operator,'status'),/SYNTHETIC_READ_COMMITTED_REQUIRED/);await operator.query('ROLLBACK');
  const summary=await call(f.db,'status');assert.equal(summary.unknown_obligations,1);assert.equal(summary.cutover_authorized,false);
 });
});

test('every modeled state-reading lifecycle entry point rejects non-read-committed transactions',{timeout:120000},async()=>{
 await usingFixture(async f=>{
  const a=await registered(f),before=await preimage(f,a);
  const requests=[['register',[id(),f.epoch,f.source]],['assert_work',[a,f.epoch,f.source]],
   ['prepare_effect',[a,f.epoch,f.source,id(),id()]],['quiesce',[id(),f.epoch,f.source]],
   ['tombstone',[id(),id(),a,before]],['status',[]]];
  for(const isolation of ['REPEATABLE READ','SERIALIZABLE'])for(const [name,args] of requests){
   await f.db.query('BEGIN ISOLATION LEVEL '+isolation);await f.db.query('SELECT 1');
   await denied(call(f.db,name,args),/SYNTHETIC_READ_COMMITTED_REQUIRED/);await f.db.query('ROLLBACK');
  }
  assert.equal((await call(f.db,'status')).mode,'open');assert.deepEqual(await preimage(f,a),before);
 });
});

test('ambiguous dispatch remains unknown and cannot be repeated with a new operation ID',{timeout:120000},async()=>{
 await usingFixture(async f=>{
  const a=await registered(f),operation=id(),action=id();
  await f.db.query('BEGIN');await call(f.db,'prepare_effect',[a,f.epoch,f.source,operation,action]);await f.db.query('ROLLBACK');
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.effect_intents')).rows[0].n,0);
  let callbacksBeforeRollback=0;await f.db.query('BEGIN');await call(f.db,'prepare_effect',[a,f.epoch,f.source,operation,action]);
  callbacksBeforeRollback++;await f.db.query('ROLLBACK');
  assert.equal(callbacksBeforeRollback,1,'a synthetic callback can happen before a database rollback');
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.effect_intents')).rows[0].n,0);
  assert.equal((await call(f.db,'status')).provider_settlement_proven,false,'rolled-back database rows do not prove no external effect');
  const result=await call(f.db,'prepare_effect',[a,f.epoch,f.source,operation,action]);
  assert.equal(result.effect_status,'unknown');assert.equal(result.provider_called,false);
  // Model a timeout after commit; the data says unknown, not zero or settled.
  await denied(call(f.db,'prepare_effect',[a,f.epoch,f.source,id(),action]),/SYNTHETIC_ID_REPLAY/);
  await denied(call(f.db,'prepare_effect',[a,f.epoch,f.source,operation,id()]),/SYNTHETIC_ID_REPLAY/);
  const freshOperation=id(),freshAction=id();await denied(call(f.db,'prepare_effect',[a,f.epoch,f.source,freshOperation,freshAction]),/SYNTHETIC_UNRESOLVED_EFFECT_BLOCKS_ALL/);
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.used_ids WHERE id=ANY($1::uuid[])',[[freshOperation,freshAction]])).rows[0].n,0);
  const same=id();await denied(call(f.db,'prepare_effect',[a,f.epoch,f.source,same,same]),/SYNTHETIC_EFFECT_REFUSED/);
  const state=(await f.db.query('SELECT effect_status FROM admission_fixture.effect_intents WHERE operation_id=$1',[operation])).rows[0];assert.equal(state.effect_status,'unknown');
  const before=await preimage(f,a),q=id();await call(f.db,'quiesce',[q,f.epoch,f.source]);await call(f.db,'tombstone',[id(),q,a,before]);
  const summary=await call(f.db,'status');assert.equal(summary.unknown_effect_intents,1);assert.equal(summary.unknown_obligations,1);assert.equal(summary.provider_settlement_proven,false);
 });
});

test('WORK precedes WRITE and blocked assertions recheck the committed quiescence',{timeout:120000},async()=>{
 await usingFixture(async f=>{
  const a=await registered(f),actor=await f.actorOne(),other=await f.actorTwo(),operator=await f.connect(),probe=await f.connect();
  const actorPid=(await actor.query('SELECT pg_backend_pid() AS pid')).rows[0].pid,operatorPid=(await operator.query('SELECT pg_backend_pid() AS pid')).rows[0].pid;
  await actor.query('BEGIN');await call(actor,'assert_work',[a,f.epoch,f.source]);await operator.query('BEGIN');
  const pending=call(operator,'quiesce',[id(),f.epoch,f.source]);let blocked=false;
  for(let i=0;i<100;i++){const row=(await f.db.query('SELECT $1::int=ANY(pg_blocking_pids($2::int)) AS blocked',[actorPid,operatorPid])).rows[0];if(row.blocked){blocked=true;break;}await delay(20);}
  assert.equal(blocked,true,'operator must wait for the earlier shared WORK transaction');
  await probe.query('BEGIN');assert.equal((await probe.query('SELECT pg_try_advisory_xact_lock(777702) AS free')).rows[0].free,true,'WRITE is not taken while WORK is blocked');await probe.query('ROLLBACK');
  const later=call(other,'assert_work',[a,f.epoch,f.source]).then(value=>({value}),error=>({error}));await actor.query('COMMIT');await pending;await operator.query('COMMIT');
  const laterResult=await later;assert.match(laterResult.error?.message??'',/SYNTHETIC_ASSERT_REFUSED/);assert.equal((await call(f.db,'status')).mode,'quiescing');
 });
});

test('concurrent effect preparations cannot both pass an unknown-effect barrier',{timeout:120000},async()=>{
 await usingFixture(async f=>{
  const a=await registered(f),first=await f.actorOne(),second=await f.actorTwo();
  const attempts=await Promise.allSettled([call(first,'prepare_effect',[a,f.epoch,f.source,id(),id()]),call(second,'prepare_effect',[a,f.epoch,f.source,id(),id()])]);
  assert.equal(attempts.filter(x=>x.status==='fulfilled').length,1);
  assert.match(attempts.find(x=>x.status==='rejected').reason.message,/SYNTHETIC_UNRESOLVED_EFFECT_BLOCKS_ALL/);
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.effect_intents')).rows[0].n,1);
  assert.equal((await call(f.db,'status')).provider_settlement_proven,false);
 });
});

test('concurrent tombstone attempts preserve one obligation and roll back the loser ID',{timeout:120000},async()=>{
 await usingFixture(async f=>{
  const a=await registered(f),before=await preimage(f,a),q=id(),operations=[id(),id()];await call(f.db,'quiesce',[q,f.epoch,f.source]);
  const clients=[await f.connect(),await f.connect()];
  const attempts=await Promise.allSettled(clients.map((client,i)=>call(client,'tombstone',[operations[i],q,a,before])));
  assert.equal(attempts.filter(x=>x.status==='fulfilled').length,1);
  const loser=attempts.findIndex(x=>x.status==='rejected');assert.match(attempts[loser].reason.message,/duplicate key|SYNTHETIC_ID_REPLAY/);
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.obligations')).rows[0].n,1);
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.used_ids WHERE id=$1',[operations[loser]])).rows[0].n,0);
  assert.deepEqual(await preimage(f,a),before);
 });
});

test('null, stale, duplicate and capacity inputs fail closed without consuming IDs',{timeout:120000},async()=>{
 await usingFixture(async f=>{
  const a=await registered(f),wrong=id();
  for(const [epoch,source] of [[null,f.source],[f.epoch,null],[f.epoch+1,f.source],[f.epoch,'b'.repeat(64)]]){
   await denied(call(f.db,'assert_work',[a,epoch,source]),/SYNTHETIC_ASSERT_REFUSED/);
   await denied(call(f.db,'quiesce',[wrong,epoch,source]),/SYNTHETIC_QUIESCE_REFUSED/);
  }
  await denied(call(f.db,'register',[a,f.epoch,f.source]),/SYNTHETIC_ID_REPLAY/);
  for(let i=0;i<15;i++)await registered(f);
  const extra=id();await denied(call(f.db,'register',[extra,f.epoch,f.source]),/SYNTHETIC_ADMISSION_BOUND/);
  const counts=(await f.db.query('SELECT (SELECT count(*)::int FROM admission_fixture.admissions) AS admissions,(SELECT count(*)::int FROM admission_fixture.used_ids) AS ids')).rows[0];
  assert.deepEqual(counts,{admissions:16,ids:16});assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.used_ids WHERE id=$1',[extra])).rows[0].n,0);
  await call(f.db,'prepare_effect',[a,f.epoch,f.source,id(),id()]);
  const op=id(),action=id();await denied(call(f.db,'prepare_effect',[a,f.epoch,f.source,op,action]),/SYNTHETIC_UNRESOLVED_EFFECT_BLOCKS_ALL/);
  assert.equal((await f.db.query('SELECT count(*)::int AS n FROM admission_fixture.used_ids WHERE id=ANY($1::uuid[])',[[op,action]])).rows[0].n,0);
 });
});
