// Scheduler state-machine/SQL recording tests, NOT PostgreSQL concurrency tests.
import test from 'node:test';import assert from 'node:assert/strict';
import {PostgresSchedulerStore,runSchedulerCycle,receiptFields,rematchFields} from '../../domain/burimunsi/postgres-scheduler.js';
import {BuriError} from '../../domain/burimunsi/errors.js';
const runId='10000000-0000-4000-8000-000000000001',admissionId='10000000-0000-4000-8000-000000000002';
const batch=(fields,values={})=>({...Object.fromEntries(fields.map(f=>[f,0])),stopped:false,...values});
function cycleFixture(){const state={calls:[],finished:[],busy:false,now:0,receipt:batch(receiptFields,{claimed:1,retained:1,unallocated:1}),rematch:batch(rematchFields,{claimed:1,completed:1})};
 const lease={runId,owner:'worker-1',version:1,profileVersion:'profile-1',policyVersion:'policy-1'};
 const profile={version:'profile-1',offsetMinutes:120,senders:['M-Money']};
 const store={claim:async c=>{state.calls.push(['claim',c]);return state.busy?null:{lease,profile};},renew:async(l,ms)=>{state.calls.push(['renew',l]);return true;},
 finish:async(l,s)=>{state.finished.push(structuredClone(s));return {applied:true};}};
 const workers={processReceipts:async c=>{state.calls.push(['receipt',c]);return structuredClone(state.receipt);},processRematches:async c=>{state.calls.push(['rematch',c]);return structuredClone(state.rematch);}};
 const options={store,workers,owner:'worker-1',receiptLimit:2,rematchLimit:1,budgetMs:1000,monotonic:()=>state.now};
 return {state,store,workers,options,run:()=>runSchedulerCycle(options)};
}
test('one bounded cycle aggregates one-job slices and finalizes once',async()=>{const f=cycleFixture(),r=await f.run();assert.equal(r.receipts.claimed,2);assert.equal(r.rematches.claimed,1);assert.equal(f.state.finished.length,1);
 assert(f.state.calls.filter(x=>['receipt','rematch'].includes(x[0])).every(x=>x[1].limit===1));assert.equal(f.state.calls.filter(x=>x[0]==='renew').length,3);
});
test('busy scheduler starts no workers',async()=>{const f=cycleFixture();f.state.busy=true;assert.deepEqual(await f.run(),{status:'busy'});assert.equal(f.state.calls.length,1);assert.equal(f.state.finished.length,0);});
test('budget expiry yields without starting another financial operation',async()=>{const f=cycleFixture();f.workers.processReceipts=async()=>{f.state.now=1001;return f.state.receipt;};
 const r=await f.run();assert.equal(r.status,'yielded');assert.equal(r.receipts.claimed,1);assert.deepEqual(r.rematches,{});
});
test('stop flag ends both queues',async()=>{const f=cycleFixture();f.state.receipt.stopped=true;const r=await f.run();assert.equal(r.status,'stopped');assert.equal(r.receipts.claimed,1);assert.deepEqual(r.rematches,{});});
test('empty receipt queue allows rematch queue',async()=>{const f=cycleFixture();f.state.receipt=batch(receiptFields);const r=await f.run();assert.equal(r.receipts.claimed,0);assert.equal(r.rematches.claimed,1);});
test('worker error is sanitized and checkpointed once',async()=>{const f=cycleFixture();f.workers.processReceipts=async()=>{throw Error('PRIVATE SECRET');};
 await assert.rejects(f.run(),e=>e.code==='scheduler_failed'&&!e.message.includes('PRIVATE'));assert.equal(f.state.finished.length,1);assert.equal(f.state.finished[0].code,'scheduler_failed');
});
test('pause at renewal prevents worker starts',async()=>{const f=cycleFixture();f.store.renew=async()=>{throw new BuriError('processing_on_hold',503);};await assert.rejects(f.run(),/processing_on_hold/);assert(!f.state.calls.some(x=>x[0]==='receipt'));});
for(const failure of ['throw','negative-ack'])test('finalization '+failure+' is not blindly retried',async()=>{const f=cycleFixture();let attempts=0;f.store.finish=async()=>{attempts++;if(failure==='throw')throw Error('lost ACK');return {applied:false};};
 await assert.rejects(f.run(),/scheduler_outcome_unknown/);assert.equal(attempts,1);
});
test('failed error-checkpoint reports unknown instead of success',async()=>{const f=cycleFixture();f.workers.processReceipts=async()=>{throw Error('failed');};f.store.finish=async()=>{throw Error('lost ACK');};await assert.rejects(f.run(),/scheduler_outcome_unknown/);});
for(const [field,value]of [['claimed',2],['posted',-1],['retry',NaN],['retained',undefined]])test('invalid worker counter '+field,async()=>{const f=cycleFixture();f.state.receipt[field]=value;await assert.rejects(f.run());});
test('backwards monotonic clock stops new work',async()=>{const f=cycleFixture();let n=0;f.options.monotonic=()=>n++===0?10:9;await assert.rejects(f.run(),/scheduler_failed/);assert(!f.state.calls.some(x=>x[0]==='receipt'));});
for(const [field,value]of [['receiptLimit',101],['rematchLimit',21],['targetsPerJob',0],['leaseMs',29999],['budgetMs',999],['owner','bad/owner']])test('invalid scheduler configuration '+field,async()=>{const f=cycleFixture();f.options[field]=value;await assert.rejects(f.run());assert.equal(f.state.calls.length,0);});
function storeFixture(){const state={row:null,now:100000,policy:{schedulerEnabled:true,policyVersion:'policy-1',profile:{version:'profile-1',offsetMinutes:120,senders:['M-Money']}},queries:[]};
 const work={kind:'jobs',assert:async()=>{}},tuple=[admissionId,1,'a'.repeat(64)],db={applicationWork:work};
 const sql={unsafe:async(q,v=[])=>{state.queries.push({q,v});
  if(q.startsWith('SELECT floor'))return [{now_ms:String(state.now)}];
  if(q.startsWith('INSERT INTO private.burimunsi_schedulers')){state.row??={collection_id:v[0],state:'idle',lease_version:0};return [];}
  if(q.startsWith('SELECT * FROM private.burimunsi_schedulers'))return state.row?[structuredClone(state.row)]:[];
  if(q.includes("SET state='running'")){Object.assign(state.row,{state:'running',run_id:v[1],lease_owner:v[2],lease_version:state.row.lease_version+1,lease_expires_at:v[3],profile_version:v[4],policy_version:v[5],admission_id:v[6],source_sha256:v[7],started_at:v[8]});return [structuredClone(state.row)];}
  if(q.includes('SET lease_expires_at=$2')){state.row.lease_expires_at=v[1];return [{run_id:state.row.run_id}];}
  if(q.includes("SET state='idle'")){Object.assign(state.row,{state:'idle',lease_expires_at:null,completed_at:v[1],last_outcome:v[2],summary:v[3]});return [{run_id:state.row.run_id}];}
  throw Error('unrecognized SQL');}};
 const authority={db,groupId:'group-1',assertOwned:async()=>{assert.equal(db.applicationWork,work);},write:async f=>{const prior=structuredClone(state.row);try{return await f(sql);}catch(e){state.row=prior;throw e;}}};
 const admission={assertInTransaction:async()=>structuredClone(state.policy)};
 const store=new PostgresSchedulerStore({authority,admission,applicationWorkTuple:()=>tuple});
 return {state,db,tuple,store,claim:()=>store.claim({owner:'worker-1',leaseMs:30000})};
}
test('store claims, renews and finishes exact leased run',async()=>{const f=storeFixture(),c=await f.claim();assert.equal(c.lease.version,1);f.state.now+=1;
 assert.equal(await f.store.renew(c.lease,30000),true);assert.equal((await f.store.finish(c.lease,{runId:c.lease.runId,status:'completed',receipts:{claimed:1},rematches:{}})).applied,true);assert.equal(f.state.row.state,'idle');
});
test('live scheduler lease excludes second claim',async()=>{const f=storeFixture();await f.claim();assert.equal(await f.claim(),null);assert.equal(f.state.row.lease_version,1);});
test('expired lease takeover increments fence and rejects stale finish',async()=>{const f=storeFixture(),old=await f.claim();f.state.now+=30001;const newer=await f.claim();assert.equal(newer.lease.version,2);assert.notEqual(newer.lease.runId,old.lease.runId);
 await assert.rejects(f.store.finish(old.lease,{runId:old.lease.runId,status:'completed',receipts:{},rematches:{}}),/lease_unavailable/);assert.equal(f.state.row.run_id,newer.lease.runId);
});
test('policy change stops renewal but permits final checkpoint',async()=>{const f=storeFixture(),c=await f.claim();f.state.policy.policyVersion='policy-2';await assert.rejects(f.store.renew(c.lease,30000),/profile_changed/);
 assert.equal((await f.store.finish(c.lease,{runId:c.lease.runId,status:'stopped',receipts:{},rematches:{}})).applied,true);
});
test('disabled scheduler policy refuses claim',async()=>{const f=storeFixture();f.state.policy.schedulerEnabled=false;await assert.rejects(f.claim(),/processing_on_hold/);assert.equal(f.state.row,null);});
test('changed work epoch refuses scheduler renewal',async()=>{const f=storeFixture(),c=await f.claim();f.tuple[1]++;await assert.rejects(f.store.renew(c.lease,30000),/worker_admission_required/);});
test('scheduler summary cannot contain raw messages or tokens',async()=>{const f=storeFixture(),c=await f.claim();await assert.rejects(f.store.finish(c.lease,{runId:c.lease.runId,status:'completed',receipts:{raw_body:'private'},rematches:{}}),/invalid_scheduler_result/);assert.equal(f.state.row.state,'running');});
