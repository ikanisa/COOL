// Explicit qualification only: this starts a fresh synthetic local PG17
// cluster and executes the exact repository fence migration, never Docker or
// an existing application/provider database.
import test,{before,beforeEach,after} from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate} from 'node:timers';
import {openApplicationWork,sqlFenceBackend} from '../../../../supabase/functions/_shared/application-fence.js';
import {createOwnedFixture,FENCE_MIGRATION_SHA256} from './fixture.mjs';

const SOURCE='a'.repeat(64),ID=n=>'11111111-1111-4111-8111-'+String(n).padStart(12,'0');
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return{promise,resolve,reject};};
const tick=()=>new Promise(resolve=>setImmediate(resolve));
// Run this file directly: the process receiving TERM must remain alive until
// creation (including a synchronous startup in progress) and owned cleanup end.
let database,closing,interrupted,readyRelease;
const setupAbort=new AbortController();
function closeOwned(){
 if(database&&!closing){closing=database.close();closing.catch(()=>{});}
 return closing;
}
function interrupt(signal){
 if(interrupted)return;
 interrupted=signal;setupAbort.abort();readyRelease?.();
 if(database)closeOwned();
}
const onTerm=()=>interrupt('SIGTERM'),onInt=()=>interrupt('SIGINT');
process.on('SIGTERM',onTerm);process.on('SIGINT',onInt);
before(async()=>{
 database=await createOwnedFixture(process.env,{signal:setupAbort.signal});
 if(interrupted){await closeOwned();throw Error('HTTP_ADMISSION_TEST_INTERRUPTED: '+interrupted);}
 assert.equal(database.sourceSha256,FENCE_MIGRATION_SHA256);assert.equal(database.providerCalls,0);
 if(process.env.COLLECT_HTTP_ADMISSION_TEST_HOLD_READY==='true'){
  console.log('COLLECT_HTTP_ADMISSION_FIXTURE_READY');
  await new Promise(resolve=>{readyRelease=resolve;if(interrupted)resolve();});
  if(interrupted){await closeOwned();throw Error('HTTP_ADMISSION_TEST_INTERRUPTED: '+interrupted);}
 }
});
beforeEach(()=>{if(interrupted)throw Error('HTTP_ADMISSION_TEST_INTERRUPTED: '+interrupted);});
after(async()=>{
 try{if(database)await closeOwned();if(interrupted)throw Error('HTTP_ADMISSION_TEST_INTERRUPTED: '+interrupted);}
 finally{process.off('SIGTERM',onTerm);process.off('SIGINT',onInt);}
});
function fixture({lostRegister=false,lostClose=false}={}){
 const gate=deferred(),committed=deferred(),events=[];
 const business={async begin(_opts,fn){return fn({async unsafe(text,values=[]){
  if(text.startsWith('SELECT private.collect_fence_register')){
   events.push('register');const result=await database.invoke('register',values);committed.resolve();await gate.promise;
   if(lostRegister)throw Error('synthetic lost COMMIT acknowledgement');return[{result}];
  }
  if(text.startsWith('SELECT private.collect_fence_close')){
   events.push('close');const result=await database.invoke('close',values);
   if(lostClose)throw Error('synthetic lost close acknowledgement');return[{result}];
  }
  if(text.startsWith('SELECT private.collect_fence_work_status')){events.push('status');return[{result:await database.invoke('status',values)}];}
  return [];
 }});}};
 const control={async reserve(){events.push('lease');throw Error('unexpected lease');}};
 return {backend:sqlFenceBackend(business,control),gate,committed,events};
}

test('real PostgreSQL: cancellation after register COMMIT closes the exact pre-work row once',async()=>{
 const id=ID(101),f=fixture(),controller=new AbortController();
 const pending=openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id,signal:controller.signal}).then(work=>({work}),error=>({error}));
 await f.committed.promise;controller.abort();f.gate.resolve();const result=await pending;
 assert.equal(result.error?.code,'application_fence_unavailable');assert.deepEqual(f.events,['register','close']);
 const value=await database.stored(id);assert.equal(value.state,'settled');assert.equal(value.reason,'cancelled_before_work');assert.equal(value.external_dispatches,0);
});
test('real PostgreSQL: timeout with late original COMMIT acknowledgement is retained and closed once',async()=>{
 const id=ID(102),f=fixture(),timers=[],holds=[],priorSet=globalThis.setTimeout,priorClear=globalThis.clearTimeout,had=Object.hasOwn(globalThis,'EdgeRuntime'),prior=globalThis.EdgeRuntime;
 globalThis.setTimeout=(fn,ms,...args)=>{if(ms===5000){const token={fn:()=>fn(...args)};timers.push(token);return token;}return priorSet(fn,ms,...args);};
 globalThis.clearTimeout=token=>{if(!timers.includes(token))priorClear(token);};globalThis.EdgeRuntime={waitUntil(p){holds.push(p);}};
 try{
  const pending=openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id}).then(work=>({work}),error=>({error}));
  await f.committed.promise;timers[0].fn();const result=await pending;assert.equal(result.error?.code,'application_fence_unavailable');assert.equal(holds.length,1);
  f.gate.resolve();await holds[0];assert.deepEqual(f.events,['register','close']);const value=await database.stored(id);assert.equal(value.state,'settled');assert.equal(value.reason,'cancelled_before_work');
 }finally{f.gate.resolve();await tick();globalThis.setTimeout=priorSet;globalThis.clearTimeout=priorClear;if(had)globalThis.EdgeRuntime=prior;else delete globalThis.EdgeRuntime;}
});
test('real PostgreSQL: lost registration acknowledgement is not guessed, closed or retried',async()=>{
 const id=ID(103),f=fixture({lostRegister:true});
 const pending=openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id});
 await f.committed.promise;f.gate.resolve();await assert.rejects(pending,{code:'application_fence_unavailable'});await tick();
 assert.deepEqual(f.events,['register']);assert.equal((await database.stored(id)).state,'active');
});
test('real PostgreSQL: cancelled close with lost acknowledgement is read back and never repeated',async()=>{
 const id=ID(104),f=fixture({lostClose:true}),controller=new AbortController();
 const pending=openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id,signal:controller.signal}).then(work=>({work}),error=>({error}));
 await f.committed.promise;controller.abort();f.gate.resolve();const result=await pending;assert.equal(result.error?.code,'application_fence_unavailable');
 assert.deepEqual(f.events,['register','close','status']);assert.equal((await database.stored(id)).reason,'cancelled_before_work');
});
test('real PostgreSQL: duplicate registration cannot close a pre-existing admission',async()=>{
 const id=ID(105);await database.invoke('register',[id,SOURCE,'http_collect']);const f=fixture();f.gate.resolve();
 await assert.rejects(openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id}),{code:'application_fence_unavailable'});await tick();
 assert.deepEqual(f.events,['register']);assert.equal((await database.stored(id)).state,'active');
});
test('real PostgreSQL: acknowledgement after the bounded cleanup window leaves the original admission active',async()=>{
 const id=ID(106),f=fixture(),timers=[],holds=[],priorSet=globalThis.setTimeout,priorClear=globalThis.clearTimeout,had=Object.hasOwn(globalThis,'EdgeRuntime'),prior=globalThis.EdgeRuntime;
 globalThis.setTimeout=(fn,ms,...args)=>{if(ms===5000){const token={fn:()=>fn(...args)};timers.push(token);return token;}return priorSet(fn,ms,...args);};
 globalThis.clearTimeout=token=>{if(!timers.includes(token))priorClear(token);};globalThis.EdgeRuntime={waitUntil(p){holds.push(p);}};
 try{
  const pending=openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id}).then(work=>({work}),error=>({error}));
  await f.committed.promise;timers[0].fn();const result=await pending;assert.equal(result.error?.code,'application_fence_unavailable');assert.equal(holds.length,1);
  timers[1].fn();await holds[0];f.gate.resolve();await tick();await tick();assert.deepEqual(f.events,['register']);assert.equal((await database.stored(id)).state,'active');
 }finally{f.gate.resolve();await tick();globalThis.setTimeout=priorSet;globalThis.clearTimeout=priorClear;if(had)globalThis.EdgeRuntime=prior;else delete globalThis.EdgeRuntime;}
});
