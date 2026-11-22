import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate} from 'node:timers';
import {openApplicationWork,sqlFenceBackend} from '../application-fence.js';

const SOURCE='a'.repeat(64),ID='11111111-1111-4111-8111-111111111111';
const deferred=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return {promise,resolve,reject};};
const tick=()=>new Promise(resolve=>setImmediate(resolve));
const row=(id=ID)=>({contractVersion:1,admissionId:id,sourceSha256:SOURCE,epoch:1,kind:'http_collect',state:'active',mode:'open'});

function delayedBackend(){
 const gate=deferred(),events=[],rows=new Map();
 const backend={
  async register(id){events.push('register');await gate.promise;const value=row(id);rows.set(id,value);return value;},
  async lease(id){events.push('lease');return {row:rows.get(id),async assert(){return rows.get(id);},async release(){events.push('release');}};},
  async close(id,epoch,source,state,reason,externalDispatches,uncertainDispatches){
   events.push('close');const value={...rows.get(id),epoch,sourceSha256:source,state,reason,externalDispatches,uncertainDispatches};rows.set(id,value);return value;
  },
  async status(id){events.push('status');return {...rows.get(id),found:rows.has(id)};}
 };
 return {backend,gate,events,rows};
}

test('already-disconnected HTTP request never registers or starts a lease',async()=>{
 const f=delayedBackend(),controller=new AbortController();controller.abort();f.gate.resolve();
 const result=await openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id:ID,signal:controller.signal}).then(work=>({work}),error=>({error}));
 if(result.work)await result.work.finish();
 assert.equal(result.error?.code,'application_fence_unavailable');
 assert.deepEqual(f.events,[]);
});

test('disconnect while registration is in flight never starts business work; a verified late commit closes once',async()=>{
 const f=delayedBackend(),controller=new AbortController();
 const pending=openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id:ID,signal:controller.signal}).then(work=>({work}),error=>({error}));
 await tick();controller.abort();f.gate.resolve();
 const result=await pending;await tick();if(result.work)await result.work.finish();
 assert.equal(result.error?.code,'application_fence_unavailable');
 assert.equal(f.events.filter(x=>x==='lease').length,0);
 assert.equal(f.events.filter(x=>x==='close').length,1);
 assert.equal(f.rows.get(ID)?.reason,'cancelled_before_work');
});

test('timed out registration later confirmed by its original commit closes exactly once without a lease',async()=>{
 const gate=deferred(),events=[],rows=new Map(),timers=[];
 const priorSet=globalThis.setTimeout,priorClear=globalThis.clearTimeout;
 globalThis.setTimeout=(fn,ms,...args)=>{if(ms===5000){const token={fn:()=>fn(...args)};timers.push(token);return token;}return priorSet(fn,ms,...args);};
 globalThis.clearTimeout=token=>{if(!timers.includes(token))priorClear(token);};
 const business={async begin(_opts,fn){return fn({async unsafe(text,values=[]){
  if(text.startsWith('SELECT private.collect_fence_register')){events.push('register');await gate.promise;const [id]=values;const value=row(id);rows.set(id,value);return [{result:value}];}
  if(text.startsWith('SELECT private.collect_fence_close')){events.push('close');const [id,epoch,source,state,reason,externalDispatches,uncertainDispatches]=values;const value={...rows.get(id),epoch,sourceSha256:source,state,reason,externalDispatches,uncertainDispatches};rows.set(id,value);return [{result:value}];}
  if(text.startsWith('SELECT private.collect_fence_work_status')){events.push('status');return [{result:{...rows.get(values[0]),found:rows.has(values[0])}}];}
  return [];
 }});}};
 const control={async reserve(){events.push('lease');throw Error('lease must not run');}};
 try{
  const pending=openApplicationWork({backend:sqlFenceBackend(business,control),sourceSha256:SOURCE,kind:'http_collect',id:ID}).then(work=>({work}),error=>({error}));
  await tick();assert.ok(timers.length);timers[0].fn();await tick();gate.resolve();const result=await pending;await tick();
  assert.equal(result.error?.code,'application_fence_unavailable');
  assert.equal(events.filter(x=>x==='lease').length,0);
  assert.equal(events.filter(x=>x==='close').length,1);
  assert.equal(rows.get(ID)?.reason,'cancelled_before_work');
 }finally{gate.resolve();globalThis.setTimeout=priorSet;globalThis.clearTimeout=priorClear;}
});

test('disconnect during lease acquisition closes only the original admission and releases the acquired lease',async()=>{
 const f=delayedBackend(),leaseGate=deferred(),leaseStarted=deferred(),original=f.backend.lease,controller=new AbortController();f.gate.resolve();
 f.backend.lease=async id=>{leaseStarted.resolve();await leaseGate.promise;return original(id);};
 const pending=openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id:ID,signal:controller.signal}).then(work=>({work}),error=>({error}));
 await leaseStarted.promise;controller.abort();leaseGate.resolve();const result=await pending;
 assert.equal(result.error?.code,'application_fence_unavailable');
 assert.equal(f.events.filter(x=>x==='close').length,1);assert.equal(f.events.filter(x=>x==='release').length,1);
 assert.equal(f.rows.get(ID)?.reason,'cancelled_before_work');assert.equal(f.rows.get(ID)?.externalDispatches,0);
});

test('cancelled-before-work close acknowledgement loss is checked once and never retried',async()=>{
 const f=delayedBackend(),controller=new AbortController(),original=f.backend.close;f.gate.resolve();
 f.backend.close=async(...args)=>{await original(...args);throw Error('synthetic lost close acknowledgement');};
 const pending=openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id:ID,signal:controller.signal}).then(work=>({work}),error=>({error}));
 controller.abort();const result=await pending;assert.equal(result.error?.code,'application_fence_unavailable');
 assert.equal(f.events.filter(x=>x==='close').length,1);assert.equal(f.events.filter(x=>x==='status').length,1);
 assert.equal(f.rows.get(ID)?.reason,'cancelled_before_work');assert.equal(f.events.filter(x=>x==='lease').length,0);
});

test('lost registration acknowledgement remains unknown and never closes a possibly foreign admission',async()=>{
 const f=delayedBackend();f.backend.register=async id=>{f.events.push('register');f.rows.set(id,row(id));throw Error('synthetic unknown commit');};
 await assert.rejects(openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id:ID}),{code:'application_fence_unavailable'});
 assert.deepEqual(f.events,['register']);assert.equal(f.rows.get(ID).state,'active');
});

test('client disconnect after provider work begins does not settle or replay the in-flight work',async()=>{
 const f=delayedBackend(),controller=new AbortController(),provider=deferred(),started=deferred();f.gate.resolve();
 const work=await openApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'http_collect',id:ID,signal:controller.signal});
 let sends=0;const original=work.dispatch('provider',()=>{sends++;started.resolve();return provider.promise;});await started.promise;
 controller.abort();const done=work.finish();await tick();assert.equal(f.events.filter(x=>x==='close').length,0);
 provider.resolve('acknowledged');assert.equal(await original,'acknowledged');const result=await done;
 assert.equal(result.state,'settled');assert.equal(result.externalDispatches,1);assert.equal(sends,1);
});

test('Edge runtime retains the exact late commit cleanup after the caller times out',async()=>{
 const gate=deferred(),events=[],rows=new Map(),timers=[],holds=[];
 const priorSet=globalThis.setTimeout,priorClear=globalThis.clearTimeout,had=Object.hasOwn(globalThis,'EdgeRuntime'),previous=globalThis.EdgeRuntime;
 globalThis.setTimeout=(fn,ms,...args)=>{if(ms===5000){const token={fn:()=>fn(...args)};timers.push(token);return token;}return priorSet(fn,ms,...args);};
 globalThis.clearTimeout=token=>{if(!timers.includes(token))priorClear(token);};
 globalThis.EdgeRuntime={waitUntil(promise){holds.push(promise);}};
 const business={async begin(_opts,fn){return fn({async unsafe(text,values=[]){
  if(text.startsWith('SELECT private.collect_fence_register')){events.push('register');await gate.promise;const value=row(values[0]);rows.set(values[0],value);return [{result:value}];}
  if(text.startsWith('SELECT private.collect_fence_close')){events.push('close');const [id,epoch,source,state,reason,externalDispatches,uncertainDispatches]=values;const value={...rows.get(id),epoch,sourceSha256:source,state,reason,externalDispatches,uncertainDispatches};rows.set(id,value);return [{result:value}];}
  return [];
 }});}};
 try{
  const backend=sqlFenceBackend(business,{async reserve(){events.push('lease');throw Error('unexpected lease');}});
  const pending=openApplicationWork({backend,sourceSha256:SOURCE,kind:'http_collect',id:ID}).then(work=>({work}),error=>({error}));
  await tick();timers[0].fn();const outcome=await pending;
  assert.equal(outcome.error?.code,'application_fence_unavailable');assert.equal(holds.length,1);assert.equal(rows.size,0);
  gate.resolve();await holds[0];assert.equal(events.filter(x=>x==='close').length,1);
  assert.equal(events.filter(x=>x==='lease').length,0);assert.equal(rows.get(ID)?.reason,'cancelled_before_work');
 }finally{gate.resolve();globalThis.setTimeout=priorSet;globalThis.clearTimeout=priorClear;if(had)globalThis.EdgeRuntime=previous;else delete globalThis.EdgeRuntime;}
});

test('a mismatched late registration response cannot authorize a cancellation or a lease',async()=>{
 const gate=deferred(),events=[],timers=[];
 const priorSet=globalThis.setTimeout,priorClear=globalThis.clearTimeout;
 globalThis.setTimeout=(fn,ms,...args)=>{if(ms===5000){const token={fn:()=>fn(...args)};timers.push(token);return token;}return priorSet(fn,ms,...args);};
 globalThis.clearTimeout=token=>{if(!timers.includes(token))priorClear(token);};
 const business={async begin(_opts,fn){return fn({async unsafe(text,values=[]){
  if(text.startsWith('SELECT private.collect_fence_register')){events.push('register');await gate.promise;return [{result:{...row(values[0]),sourceSha256:'b'.repeat(64)}}];}
  if(text.startsWith('SELECT private.collect_fence_close'))events.push('close');
  return [];
 }});}};
 try{
  const backend=sqlFenceBackend(business,{async reserve(){events.push('lease');throw Error('unexpected lease');}});
  const pending=openApplicationWork({backend,sourceSha256:SOURCE,kind:'http_collect',id:ID}).then(work=>({work}),error=>({error}));
  await tick();timers[0].fn();await tick();gate.resolve();const result=await pending;
  assert.equal(result.error?.code,'application_fence_unavailable');assert.deepEqual(events,['register']);
 }finally{gate.resolve();globalThis.setTimeout=priorSet;globalThis.clearTimeout=priorClear;}
});

test('a timed out admission returns promptly even when the original registration remains pending',async()=>{
 const gate=deferred(),timers=[],events=[];
 const priorSet=globalThis.setTimeout,priorClear=globalThis.clearTimeout,had=Object.hasOwn(globalThis,'EdgeRuntime'),previous=globalThis.EdgeRuntime;
 delete globalThis.EdgeRuntime;
 globalThis.setTimeout=(fn,ms,...args)=>{if(ms===5000){const token={fn:()=>fn(...args)};timers.push(token);return token;}return priorSet(fn,ms,...args);};
 globalThis.clearTimeout=token=>{if(!timers.includes(token))priorClear(token);};
 const business={async begin(_opts,fn){return fn({async unsafe(text){
  if(text.startsWith('SELECT private.collect_fence_register')){events.push('register');await gate.promise;throw Error('synthetic unresolved original');}
  if(text.startsWith('SELECT private.collect_fence_close'))events.push('close');return [];
 }});}};
 try{
  const backend=sqlFenceBackend(business,{async reserve(){events.push('lease');throw Error('unexpected lease');}});
  const pending=openApplicationWork({backend,sourceSha256:SOURCE,kind:'http_collect',id:ID}).then(work=>({work}),error=>({error}));
  await tick();timers[0].fn();const outcome=await pending;assert.equal(outcome.error?.code,'application_fence_unavailable');
  assert.deepEqual(events,['register']);assert.equal(timers.length,2);
 }finally{gate.resolve();await tick();globalThis.setTimeout=priorSet;globalThis.clearTimeout=priorClear;if(had)globalThis.EdgeRuntime=previous;else delete globalThis.EdgeRuntime;}
});

test('registration acknowledged only after the bounded cleanup window stays unresolved without a lease or close',async()=>{
 const gate=deferred(),events=[],rows=new Map(),timers=[],holds=[];
 const priorSet=globalThis.setTimeout,priorClear=globalThis.clearTimeout,had=Object.hasOwn(globalThis,'EdgeRuntime'),previous=globalThis.EdgeRuntime;
 globalThis.setTimeout=(fn,ms,...args)=>{if(ms===5000){const token={fn:()=>fn(...args)};timers.push(token);return token;}return priorSet(fn,ms,...args);};
 globalThis.clearTimeout=token=>{if(!timers.includes(token))priorClear(token);};globalThis.EdgeRuntime={waitUntil(p){holds.push(p);}};
 const business={async begin(_opts,fn){return fn({async unsafe(text,values=[]){
  if(text.startsWith('SELECT private.collect_fence_register')){events.push('register');await gate.promise;const value=row(values[0]);rows.set(values[0],value);return [{result:value}];}
  if(text.startsWith('SELECT private.collect_fence_close'))events.push('close');return [];
 }});}};
 try{
  const backend=sqlFenceBackend(business,{async reserve(){events.push('lease');throw Error('unexpected lease');}});
  const pending=openApplicationWork({backend,sourceSha256:SOURCE,kind:'http_collect',id:ID}).then(work=>({work}),error=>({error}));
  await tick();timers[0].fn();const result=await pending;assert.equal(result.error?.code,'application_fence_unavailable');assert.equal(holds.length,1);
  assert.equal(timers.length,2);timers[1].fn();await holds[0];gate.resolve();await tick();
  assert.deepEqual(events,['register']);assert.equal(rows.get(ID)?.state,'active');
 }finally{gate.resolve();globalThis.setTimeout=priorSet;globalThis.clearTimeout=priorClear;if(had)globalThis.EdgeRuntime=previous;else delete globalThis.EdgeRuntime;}
});
