import test from 'node:test';
import assert from 'node:assert/strict';
import {Worker} from 'node:worker_threads';

// Real monotonic time and real timers, isolated from the test runner/UI. The
// negative worker pauses only its own event loop; no CPU spin or host pause.
const workerSource=String.raw`
import {parentPort,workerData} from 'node:worker_threads';
const {openApplicationWork,sqlFenceBackend,FENCE_IO_TIMEOUT_MS}=await import(workerData.moduleUrl);
const SOURCE='a'.repeat(64),ID='11111111-1111-4111-8111-111111111111';
let release,windowStart,ackAt,closeCount=0,leases=0,providerCalls=0,cleanupTimerExecuted=false,timerCount=0;
const gate=new Promise(resolve=>{release=resolve;}),holds=[],rows=new Map();
const originalSet=globalThis.setTimeout;
globalThis.setTimeout=(fn,ms,...args)=>{
 const current=ms===FENCE_IO_TIMEOUT_MS?++timerCount:0;
 return originalSet(()=>{if(current===2)cleanupTimerExecuted=true;fn(...args);},ms);
};
globalThis.EdgeRuntime={waitUntil(promise){windowStart=performance.now();holds.push(promise);}};
globalThis.fetch=async()=>{providerCalls++;throw Error('unexpected provider');};
const business={async begin(_options,fn){return fn({async unsafe(sql,values=[]){
 if(sql.startsWith('SELECT private.collect_fence_register')){
  await gate;ackAt=performance.now();const value={contractVersion:1,admissionId:ID,sourceSha256:SOURCE,epoch:1,kind:'http_collect',state:'active',mode:'open'};
  rows.set(ID,value);return [{result:value}];
 }
 if(sql.startsWith('SELECT private.collect_fence_close')){
  closeCount++;const value={...rows.get(ID),state:'settled',reason:'cancelled_before_work',externalDispatches:0,uncertainDispatches:0};
  rows.set(ID,value);return [{result:value}];
 }
 if(sql.startsWith('SELECT private.collect_fence_work_status'))return [{result:{...rows.get(ID),found:rows.has(ID)}}];
 return [];
}});}};
const control={async reserve(){leases++;throw Error('unexpected lease');}};
const outcome=await openApplicationWork({backend:sqlFenceBackend(business,control),sourceSha256:SOURCE,kind:'http_collect',id:ID})
 .then(()=>({unexpectedSuccess:true}),error=>({code:error.code}));
if(holds.length!==1||!Number.isFinite(windowStart))throw Error('late ownership was not retained');
if(workerData.starveTimer){
 const wait=Math.max(0,windowStart+FENCE_IO_TIMEOUT_MS+125-performance.now());
 Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,wait);
}
release();await holds[0];
parentPort.postMessage({outcome,windowMs:FENCE_IO_TIMEOUT_MS,ackAfterWindowStartMs:ackAt-windowStart,
 cleanupTimerExecuted,closeCount,leases,providerCalls,row:rows.get(ID)});
parentPort.close();
`;

function scenario(starveTimer){
 return new Promise((resolve,reject)=>{
  const worker=new Worker(new URL('data:text/javascript,'+encodeURIComponent(workerSource)),{
   workerData:{starveTimer,moduleUrl:new URL('../application-fence.js',import.meta.url).href},
  });
  let result;worker.once('message',value=>{result=value;});worker.once('error',reject);
  worker.once('exit',code=>{if(code===0&&result)resolve(result);else reject(Error('isolated deadline worker failed'));});
 });
}

test('elapsed late-registration deadline blocks cleanup before a starved timer runs; within-window ACK still closes once',
 {timeout:25000},async()=>{
  const [late,within]=await Promise.all([scenario(true),scenario(false)]);
  for(const value of [late,within]){
   assert.equal(value.outcome.code,'application_fence_unavailable');assert.equal(value.windowMs,5000);
   assert.equal(value.leases,0);assert.equal(value.providerCalls,0);assert.equal(value.cleanupTimerExecuted,false);
  }
  assert.ok(late.ackAfterWindowStartMs>=late.windowMs);
  assert.equal(late.closeCount,0,'elapsed deadline must be checked before cleanup, independently of timeout callback order');
  assert.equal(late.row.state,'active');
  assert.ok(within.ackAfterWindowStartMs<within.windowMs);assert.equal(within.closeCount,1);
  assert.equal(within.row.state,'settled');assert.equal(within.row.reason,'cancelled_before_work');
 });
