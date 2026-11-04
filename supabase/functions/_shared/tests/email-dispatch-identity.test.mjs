import test from 'node:test';
import assert from 'node:assert/strict';
import {setImmediate} from 'node:timers';
import {openApplicationWork,deferredApplicationWork,guardedFetch} from '../application-fence.js';
import {createWorkspaceSmtpEmail} from '../workspace-smtp-email.js';
import {sendTransactionalEmail} from '../domain/email_delivery.js';
import {registerBuiltinEmailBinding} from '../email-binding-registry.js';

const SOURCE='a'.repeat(64);
const deferred=()=>{let resolve;const promise=new Promise(done=>resolve=done);return {promise,resolve};};
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function fixture({assertion=async()=>{}}={}){
 const rows=new Map();
 return {backend:{
  async register(id,source,kind){const row={contractVersion:1,admissionId:id,sourceSha256:source,epoch:1,state:'active',mode:'open',kind};rows.set(id,row);return {...row};},
  async lease(id){return {row:{...rows.get(id)},async assert(){await assertion();return {...rows.get(id)};},async release(){}};},
  async close(id,_epoch,_source,state,reason,externalDispatches,uncertainDispatches){return {...rows.get(id),state,reason,externalDispatches,uncertainDispatches};},
  async status(){throw Error('unexpected status');}
 }};
}
const open=backend=>openApplicationWork({backend,sourceSha256:SOURCE,kind:'jobs'});
const message={to:'synthetic@example.invalid',subject:'Synthetic',text:'Synthetic'};
const accepted=mail=>({response:'250 accepted',accepted:mail.envelope.to,rejected:[],envelope:mail.envelope,messageId:'synthetic-id'});
function envFor(work,sendMail){const env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,COLLECT_NOTICE_SMTP_PASSWORD:'synthetic',AUTH_EMAIL_FROM:'info@ikanisa.com'};env.AUTH_EMAIL=createWorkspaceSmtpEmail(env,{createTransport:()=>({sendMail,close(){}})});return env;}

test('reserved dispatch is work-bound, single-use and keeps finish pending until released or sent',async()=>{
 const a=fixture(),b=fixture(),work=await open(a.backend),other=await open(b.backend),token=work.reserveDispatch('smtp');let closed=false,calls=0;
 const completion=work.finish().then(value=>{closed=true;return value;});await tick();assert.equal(closed,false);
 assert.throws(()=>work.reserveDispatch('smtp'));assert.throws(()=>other.dispatchReserved(token,'smtp',()=>{}));
 assert.throws(()=>work.dispatchReserved({},'smtp',()=>{}));assert.throws(()=>work.dispatchReserved(token,'push',()=>{}));
 work.unknownReserved(token);await work.dispatchReserved(token,'smtp',()=>{calls++;return 'accepted';});
 assert.throws(()=>work.dispatchReserved(token,'smtp',()=>{}));const result=await completion;
 assert.equal(calls,1);assert.equal(result.externalDispatches,1);assert.equal(result.uncertainDispatches,1);assert.equal(result.reason,'completed_with_unknown_obligation');await other.finish();
});

test('deferred work and unstarted releases preserve zero dispatches',async()=>{
 const f=fixture(),work=deferredApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'jobs'});await work.assert();
 const token=work.reserveDispatch('smtp');work.unknownReserved(token);work.releaseReserved(token);
 assert.throws(()=>work.dispatchReserved(token,'smtp',()=>{}));const result=await work.finish();assert.equal(result.externalDispatches,0);assert.equal(result.uncertainDispatches,0);
});

test('denied reserved dispatch never counts a provider call even after early uncertainty',async()=>{
 let deny=false,calls=0;const f=fixture({assertion:async()=>{if(deny)throw Error('synthetic lost lease');}}),work=await open(f.backend),token=work.reserveDispatch('smtp');work.unknownReserved(token);deny=true;
 await assert.rejects(work.dispatchReserved(token,'smtp',()=>{calls++;}));const result=await work.finish();assert.equal(calls,0);assert.equal(result.state,'unresolved');assert.equal(result.externalDispatches,0);assert.equal(result.uncertainDispatches,0);
});

test('built-in validation and transport-construction failures release reservations without dispatch',async()=>{
 for(const invalidAddress of [true,false]){
  const f=fixture(),work=await open(f.backend);let sends=0;
  const env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,COLLECT_NOTICE_SMTP_PASSWORD:'synthetic',AUTH_EMAIL_FROM:'info@ikanisa.com'};
  env.AUTH_EMAIL=createWorkspaceSmtpEmail(env,{createTransport:()=>{if(!invalidAddress)throw Error('synthetic setup failure');return {sendMail(){sends++;},close(){}};}});
  await assert.rejects(sendTransactionalEmail(env,{...message,to:invalidAddress?'x..y@example.invalid':message.to}),{code:'email_unavailable'});
  const result=await work.finish();assert.equal(sends,0);assert.equal(result.externalDispatches,0);assert.equal(result.uncertainDispatches,0);
 }
});

test('generic email binding retains its existing invocation behavior',async()=>{
 for(const fallback of [false,true]){
  const f=fixture(),work=await open(f.backend);let calls=0;const binding={async send(...args){calls++;assert.equal(this,binding);assert.equal(args.length,1);assert.equal(args[0].from.email,fallback?'info@ikanisa.com':'sender@example.invalid');return {messageId:'generic-synthetic'};}};
  const env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,...(fallback?{EMAIL:binding}:{AUTH_EMAIL_FROM:'sender@example.invalid',AUTH_EMAIL:binding})};
  assert.deepEqual(await sendTransactionalEmail(env,message),{messageId:'generic-synthetic'});const result=await work.finish();assert.equal(calls,1);assert.equal(result.externalDispatches,0);assert.equal(result.state,'settled');
 }
});

test('generic binding errors retain the existing safe failure behavior',async()=>{
 const f=fixture(),work=await open(f.backend);let calls=0;
 const env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,AUTH_EMAIL_FROM:'sender@example.invalid',AUTH_EMAIL:{async send(){calls++;throw Error('synthetic private detail');}}};
 await assert.rejects(sendTransactionalEmail(env,message),{code:'email_unavailable'});const result=await work.finish();assert.equal(calls,1);assert.equal(result.externalDispatches,0);assert.equal(result.uncertainDispatches,0);assert.equal(result.state,'unresolved');assert.equal(result.reason,'dispatch_unconfirmed');
});

test('generic synchronous throw and malformed response close unresolved without invented effects',async()=>{
 for(const malformed of [false,true]){
  const f=fixture(),work=await open(f.backend);let calls=0;
  const env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,AUTH_EMAIL_FROM:'sender@example.invalid',AUTH_EMAIL:{send(){calls++;if(!malformed)throw Error('synthetic synchronous failure');return {messageId:''};}}};
  const send=sendTransactionalEmail(env,message),finish=work.finish();await assert.rejects(send,{code:'email_unavailable'});const result=await finish;
  assert.equal(calls,1);assert.equal(result.state,'unresolved');assert.equal(result.reason,'dispatch_unconfirmed');assert.equal(result.externalDispatches,0);assert.equal(result.uncertainDispatches,0);
 }
});

test('generic validation before invocation does not add an unconfirmed outcome',async()=>{
 const f=fixture(),work=await open(f.backend);let calls=0;const env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,AUTH_EMAIL_FROM:'sender@example.invalid',AUTH_EMAIL:{send(){calls++;}}};
 await assert.rejects(sendTransactionalEmail(env,{...message,to:'invalid'}),{code:'email_unavailable'});const result=await work.finish();assert.equal(calls,0);assert.equal(result.state,'settled');assert.equal(result.reason,'completed');
});

test('generic timeout before nested SMTP dispatch retains unresolved outcome and lets it finish',async()=>{
 const gates=[deferred(),deferred(),deferred()],entered=deferred();let checks=0,sends=0;
 const f=fixture({assertion:async()=>{const n=++checks;if(n===2)entered.resolve();if(n>=2&&n<=4)await gates[n-2].promise;}}),work=await open(f.backend);
 const env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,AUTH_EMAIL_FROM:'sender@example.invalid',AUTH_EMAIL:{send(){return work.dispatch('smtp',()=>{sends++;return {messageId:'late-synthetic'};});}}};
 const previousSet=globalThis.setTimeout,previousClear=globalThis.clearTimeout,installed=deferred();let deadline;
 globalThis.setTimeout=(fn,ms,...args)=>ms===10000?(deadline={fn:()=>fn(...args)},installed.resolve(),deadline):previousSet(fn,ms,...args);
 globalThis.clearTimeout=value=>{if(value!==deadline)previousClear(value);};
 try{
  const sending=sendTransactionalEmail(env,message),prior=[work.assert(),work.assert(),work.assert()];await Promise.all([installed.promise,entered.promise]);assert.equal(sends,0);deadline.fn();await assert.rejects(sending,{code:'email_unavailable'});
  let closed=false;const completion=work.finish().then(value=>{closed=true;return value;});await tick();assert.equal(closed,false);
  for(const gate of gates)gate.resolve();await Promise.all(prior);const result=await completion;assert.equal(sends,1);assert.equal(result.state,'unresolved');assert.equal(result.reason,'dispatch_unconfirmed');assert.equal(result.externalDispatches,1);assert.equal(result.uncertainDispatches,0);
 }finally{for(const gate of gates)gate.resolve();globalThis.setTimeout=previousSet;globalThis.clearTimeout=previousClear;}
});

test('generic timeout after nested dispatch waits for the original late result',async()=>{
 const f=fixture(),work=await open(f.backend),started=deferred(),raw=deferred();let sends=0;
 const env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,AUTH_EMAIL_FROM:'sender@example.invalid',AUTH_EMAIL:{send(){return work.dispatch('smtp',()=>{sends++;started.resolve();return raw.promise;});}}};
 const previousSet=globalThis.setTimeout,previousClear=globalThis.clearTimeout;let deadline;
 globalThis.setTimeout=(fn,ms,...args)=>ms===10000?(deadline={fn:()=>fn(...args)}):previousSet(fn,ms,...args);
 globalThis.clearTimeout=value=>{if(value!==deadline)previousClear(value);};
 try{const sending=sendTransactionalEmail(env,message);await started.promise;deadline.fn();await assert.rejects(sending,{code:'email_unavailable'});let closed=false;const finish=work.finish().then(value=>{closed=true;return value;});await tick();assert.equal(closed,false);raw.resolve({messageId:'late-synthetic'});const result=await finish;assert.equal(sends,1);assert.equal(result.state,'unresolved');assert.equal(result.reason,'dispatch_unconfirmed');assert.equal(result.externalDispatches,1);assert.equal(result.uncertainDispatches,0);}finally{raw.resolve({messageId:'cleanup'});globalThis.setTimeout=previousSet;globalThis.clearTimeout=previousClear;}
});

test('generic failure does not mark an unrelated same-label dispatch',async()=>{
 const f=fixture(),work=await open(f.backend),started=deferred(),raw=deferred();const unrelated=work.dispatch('smtp',()=>{started.resolve();return raw.promise;});await started.promise;
 const env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,AUTH_EMAIL_FROM:'sender@example.invalid',AUTH_EMAIL:{send(){throw Error('synthetic failure');}}};
 await assert.rejects(sendTransactionalEmail(env,message),{code:'email_unavailable'});const completion=work.finish();raw.resolve('synthetic success');await unrelated;const result=await completion;assert.equal(result.state,'unresolved');assert.equal(result.reason,'dispatch_unconfirmed');assert.equal(result.externalDispatches,1);assert.equal(result.uncertainDispatches,0);
});

test('deferred work preserves generic uncertainty and genuine work loss takes precedence',async()=>{
 for(const lost of [false,true]){
  const f=fixture(),work=deferredApplicationWork({backend:f.backend,sourceSha256:SOURCE,kind:'jobs'});await work.assert();
  const env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,AUTH_EMAIL_FROM:'sender@example.invalid',AUTH_EMAIL:{send(){throw Error('synthetic failure');}}};
  await assert.rejects(sendTransactionalEmail(env,message),{code:'email_unavailable'});if(lost)work.abandon('work_lost');const result=await work.finish();assert.equal(result.state,'unresolved');assert.equal(result.reason,lost?'work_lost':'dispatch_unconfirmed');assert.equal(result.externalDispatches,0);
 }
});

test('queued SMTP timeout remains unknown after the original late successful effect',async()=>{
 const gates=[deferred(),deferred(),deferred()],entered=deferred();let checks=0,sends=0;
 const f=fixture({assertion:async()=>{const n=++checks;if(n===2)entered.resolve();if(n>=2&&n<=4)await gates[n-2].promise;}}),work=await open(f.backend),env=envFor(work,mail=>{sends++;return accepted(mail);});
 const previousSet=globalThis.setTimeout,previousClear=globalThis.clearTimeout,installed=deferred();let deadline;
 globalThis.setTimeout=(fn,ms,...args)=>ms===10000?(deadline={fn:()=>fn(...args)},installed.resolve(),deadline):previousSet(fn,ms,...args);
 globalThis.clearTimeout=value=>{if(value!==deadline)previousClear(value);};
 try{
  const sending=sendTransactionalEmail(env,message);const prior=[work.assert(),work.assert(),work.assert()];await Promise.all([installed.promise,entered.promise]);assert.equal(sends,0);deadline.fn();await assert.rejects(sending,{code:'email_unavailable'});
  for(const gate of gates)gate.resolve();await Promise.all(prior);const result=await work.finish();assert.equal(sends,1);assert.equal(result.externalDispatches,1);assert.equal(result.uncertainDispatches,1);assert.equal(result.reason,'completed_with_unknown_obligation');
 }finally{for(const gate of gates)gate.resolve();globalThis.setTimeout=previousSet;globalThis.clearTimeout=previousClear;}
});

test('finish cannot overtake malformed built-in reply validation',async()=>{
 const f=fixture(),work=await open(f.backend),started=deferred(),raw=deferred();
 const binding=registerBuiltinEmailBinding({send(_mail,token){return work.dispatchReserved(token,'smtp',()=>{started.resolve();return raw.promise;});}});
 const env={APP_ENVIRONMENT:'test',COLLECT_FENCE_WORK:work,AUTH_EMAIL_FROM:'sender@example.invalid',AUTH_EMAIL:binding};
 const result=sendTransactionalEmail(env,message);await started.promise;const completion=work.finish();raw.resolve({messageId:''});
 await assert.rejects(result,{code:'email_unavailable'});const closed=await completion;assert.equal(closed.externalDispatches,1);assert.equal(closed.uncertainDispatches,1);assert.equal(closed.reason,'completed_with_unknown_obligation');
});

test('same-label operations retain separate uncertainty and late failure never clears it',async()=>{
 const f=fixture(),work=await open(f.backend),a=work.reserveDispatch('smtp'),b=work.reserveDispatch('smtp'),first=deferred(),second=deferred();let calls=0;
 const pa=work.dispatchReserved(a,'smtp',()=>{calls++;return first.promise;}),pb=work.dispatchReserved(b,'smtp',()=>{calls++;return second.promise;});
 await tick();assert.equal(calls,2);work.unknownReserved(a);first.resolve('late success');second.resolve('success');await Promise.all([pa,pb]);const result=await work.finish();assert.equal(result.externalDispatches,2);assert.equal(result.uncertainDispatches,1);
 const g=fixture(),next=await open(g.backend),token=next.reserveDispatch('smtp');next.unknownReserved(token);await assert.rejects(next.dispatchReserved(token,'smtp',()=>{throw Error('synthetic late failure');}));const failed=await next.finish();assert.equal(failed.externalDispatches,1);assert.equal(failed.uncertainDispatches,1);
});

test('identity-bound HTTP body failure marks only its own same-label dispatch',async()=>{
 const f=fixture(),work=await open(f.backend),env={COLLECT_FENCE_WORK:work},a=work.reserveDispatch('smtp'),b=work.reserveDispatch('smtp'),previous=globalThis.fetch;let calls=0;
 globalThis.fetch=async()=>{calls++;if(calls===1)return new Response(new ReadableStream({start(c){c.error(Error('synthetic body failure'));}}));return Response.json({id:'synthetic'});};
 try{const bad=await guardedFetch(env,'smtp','https://example.invalid',{},a),good=await guardedFetch(env,'smtp','https://example.invalid',{},b);await good.json();await assert.rejects(bad.text());const result=await work.finish();assert.equal(calls,2);assert.equal(result.externalDispatches,2);assert.equal(result.uncertainDispatches,1);}finally{globalThis.fetch=previous;}
});

test('unread HTTP cleanup marks only the originating reservation',async()=>{
 const f=fixture(),work=await open(f.backend),env={COLLECT_FENCE_WORK:work},a=work.reserveDispatch('smtp'),b=work.reserveDispatch('smtp'),previous=globalThis.fetch;let cancelled=0;
 globalThis.fetch=async()=>new Response(new ReadableStream({cancel(){cancelled++;}}));
 try{await guardedFetch(env,'smtp','https://example.invalid',{},a);const good=await guardedFetch(env,'smtp','https://example.invalid',{},b);await good.body.cancel();const result=await work.finish();assert.equal(cancelled,2);assert.equal(result.externalDispatches,2);assert.equal(result.uncertainDispatches,1);}finally{globalThis.fetch=previous;}
});
