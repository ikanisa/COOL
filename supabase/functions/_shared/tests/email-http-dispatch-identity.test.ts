// Real adapter/fence code, synthetic in-memory backend and fetch only.
// No provider, database or network access.
// @ts-nocheck
import assert from 'node:assert/strict';
import {openApplicationWork} from '../application-fence.js';
import {providerAdapters} from '../adapters.js';
import {sendTransactionalEmail} from '../domain/email_delivery.js';
const SOURCE='a'.repeat(64);
const deferred=()=>{let resolve;const promise=new Promise(done=>resolve=done);return {promise,resolve};};
Deno.test('built-in HTTP sends keep concurrent timeout uncertainty on the original operation',async()=>{
 const rows=new Map(),backend={
  async register(id,source,kind){const row={contractVersion:1,admissionId:id,sourceSha256:source,epoch:1,state:'active',mode:'open',kind};rows.set(id,row);return {...row};},
  async lease(id){return {row:{...rows.get(id)},async assert(){return {...rows.get(id)};},async release(){}};},
  async close(id,_epoch,_source,state,reason,externalDispatches,uncertainDispatches){return {...rows.get(id),state,reason,externalDispatches,uncertainDispatches};},
  async status(){throw Error('unexpected status');}
 };
 const work=await openApplicationWork({backend,sourceSha256:SOURCE,kind:'jobs'}),env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,AUTH_EMAIL_FROM:'receipt@example.invalid',TRANSACTIONAL_EMAIL_URL:'https://email.example.invalid/send',TRANSACTIONAL_EMAIL_TOKEN:'synthetic'};
 Object.assign(env,providerAdapters(env));
 const priorFetch=globalThis.fetch,priorSet=globalThis.setTimeout,priorClear=globalThis.clearTimeout,ready=deferred(),responses=[deferred(),deferred()],timers=[];let calls=0;
 globalThis.fetch=async()=>{const index=calls++;if(calls===2)ready.resolve();return await responses[index].promise;};
 globalThis.setTimeout=(fn,ms,...args)=>{if(ms===10000){const timer={fn:()=>fn(...args)};timers.push(timer);return timer;}return priorSet(fn,ms,...args);};
 globalThis.clearTimeout=value=>{if(!timers.includes(value))priorClear(value);};
 try{
  const message={to:'synthetic@example.invalid',subject:'Synthetic',text:'Synthetic'};
  const first=sendTransactionalEmail(env,message),second=sendTransactionalEmail(env,message);await ready.promise;assert.equal(timers.length,2);timers[0].fn();await assert.rejects(first,{code:'email_unavailable'});
  responses[0].resolve(Response.json({messageId:'late-synthetic'}));responses[1].resolve(Response.json({messageId:'other-synthetic'}));assert.deepEqual(await second,{messageId:'other-synthetic'});
  const result=await work.finish();assert.equal(calls,2);assert.equal(result.externalDispatches,2);assert.equal(result.uncertainDispatches,1);assert.equal(result.reason,'completed_with_unknown_obligation');
 }finally{for(const item of responses)item.resolve(Response.json({messageId:'cleanup'}));globalThis.fetch=priorFetch;globalThis.setTimeout=priorSet;globalThis.clearTimeout=priorClear;}
});

Deno.test('queued HTTP timeout remains unknown when the original late request fails',async()=>{
 const gates=[deferred(),deferred(),deferred()],entered=deferred(),rows=new Map();let checks=0,calls=0;
 const backend={
  async register(id,source,kind){const row={contractVersion:1,admissionId:id,sourceSha256:source,epoch:1,state:'active',mode:'open',kind};rows.set(id,row);return {...row};},
  async lease(id){return {row:{...rows.get(id)},async assert(){const n=++checks;if(n===2)entered.resolve();if(n>=2&&n<=4)await gates[n-2].promise;return {...rows.get(id)};},async release(){}};},
  async close(id,_epoch,_source,state,reason,externalDispatches,uncertainDispatches){return {...rows.get(id),state,reason,externalDispatches,uncertainDispatches};},
  async status(){throw Error('unexpected status');}
 };
 const work=await openApplicationWork({backend,sourceSha256:SOURCE,kind:'jobs'}),env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,AUTH_EMAIL_FROM:'receipt@example.invalid',TRANSACTIONAL_EMAIL_URL:'https://email.example.invalid/send',TRANSACTIONAL_EMAIL_TOKEN:'synthetic'};Object.assign(env,providerAdapters(env));
 const priorFetch=globalThis.fetch,priorSet=globalThis.setTimeout,priorClear=globalThis.clearTimeout,installed=deferred();let deadline;
 globalThis.fetch=async()=>{calls++;throw Error('synthetic network result');};
 globalThis.setTimeout=(fn,ms,...args)=>{if(ms===10000){deadline={fn:()=>fn(...args)};installed.resolve();return deadline;}return priorSet(fn,ms,...args);};
 globalThis.clearTimeout=value=>{if(value!==deadline)priorClear(value);};
 try{
  const sending=sendTransactionalEmail(env,{to:'synthetic@example.invalid',subject:'Synthetic',text:'Synthetic'}),prior=[work.assert(),work.assert(),work.assert()];await Promise.all([installed.promise,entered.promise]);assert.equal(calls,0);deadline.fn();await assert.rejects(sending,{code:'email_unavailable'});
  for(const gate of gates)gate.resolve();await Promise.all(prior);const result=await work.finish();assert.equal(calls,1);assert.equal(result.externalDispatches,1);assert.equal(result.uncertainDispatches,1);assert.equal(result.reason,'completed_with_unknown_obligation');
 }finally{for(const gate of gates)gate.resolve();globalThis.fetch=priorFetch;globalThis.setTimeout=priorSet;globalThis.clearTimeout=priorClear;}
});
