import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash,createHmac,webcrypto} from 'node:crypto';
import {setImmediate} from 'node:timers';
import {join} from 'node:path';
import {pathToFileURL,fileURLToPath} from 'node:url';
const root=process.env.COLLECT_FENCE_BODY_SOURCE_ROOT??fileURLToPath(new URL('../',import.meta.url));
const actual=name=>import(pathToFileURL(join(root,name)).href);
const {openApplicationWork,guardedFetch,noteUnknownEffect}=await actual('application-fence.js');
const {createRosterDecoderBridge}=await actual('roster_decoder_bridge.mjs');
const SOURCE='a'.repeat(64),BUILD='b'.repeat(64),ENDPOINT='https://decoder.synthetic.invalid/decode';
const defer=()=>{let resolve,reject;const promise=new Promise((yes,no)=>{resolve=yes;reject=no;});return{promise,resolve,reject};};
const tick=()=>new Promise(resolve=>setImmediate(resolve));
function backend(){const rows=new Map(),events=[];return{rows,events,async register(id,source,kind){const row={contractVersion:1,admissionId:id,sourceSha256:source,epoch:1,state:'active',mode:'open',kind};rows.set(id,row);return{...row};},async lease(id){return{row:{...rows.get(id)},assert:async()=>({...rows.get(id)}),release:async()=>{events.push('release');}};},async close(id,epoch,source,state,reason,externalDispatches,uncertainDispatches){events.push('close');const row={...rows.get(id),state,reason,externalDispatches,uncertainDispatches};rows.set(id,row);return{...row};},async status(id){return{...rows.get(id),found:rows.has(id)};}};}
async function fixture(respond,extra={}){
 const state=backend(),work=await openApplicationWork({backend:state,sourceSha256:SOURCE,kind:'http_collect'}),env={COLLECT_FENCE_WORK:work},previous=globalThis.fetch;let calls=0;
 globalThis.fetch=(url,init)=>{assert.equal(String(url),ENDPOINT);calls++;return respond(url,init);};
 const bridge=createRosterDecoderBridge({protocol:'roster-hmac-v1',endpoint:ENDPOINT,secret:'synthetic-decoder-secret-32-bytes-minimum',approvedBuildSha256:BUILD,fetchImpl:(url,options)=>guardedFetch(env,'decoder',url,options),trackPromise:promise=>work.waitUntil(promise),onUncertain:()=>noteUnknownEffect(env,'decoder'),...extra});
 const request=signal=>new Request('https://roster-decoder.internal/decode',{method:'POST',headers:{'Content-Type':'application/json'},signal,body:JSON.stringify({schema_version:1,source_sha256:createHash('sha256').update('A').digest('hex'),decoder_build_sha256:BUILD,mime_type:'image/png',content_base64:'QQ=='})});
 return{state,work,calls:()=>calls,call:signal=>bridge.fetch(request(signal),{requestId:'11111111-1111-4111-8111-111111111111',reservationId:'22222222-2222-4222-8222-222222222222'}),restore:()=>{globalThis.fetch=previous;}};
}

test('actual decoder post-header abort retains original body read and deferred cancellation through refusal',async()=>{
 const read=defer(),cancelled=defer(),cancel=defer(),pull=defer(),control=new AbortController();
 const f=await fixture(()=>Promise.resolve(new Response(new ReadableStream({pull(){read.resolve();return pull.promise;},cancel(){cancelled.resolve();return cancel.promise;}},{highWaterMark:0}),{headers:{'Content-Type':'application/json'}})));
 let completion;try{const observed=f.call(control.signal);await read.promise;control.abort();await assert.rejects(observed,{code:'roster_decoder_aborted'});await cancelled.promise;completion=f.work.finish();await tick();assert.equal(f.state.events.includes('close'),false,'Caller refusal is not raw cancellation settlement');assert.equal([...f.state.rows.values()][0].state,'active');cancel.resolve();pull.resolve();const result=await completion;assert.equal(result.state,'settled');assert.equal(result.reason,'completed_with_unknown_obligation');assert.equal(result.externalDispatches,1);assert.equal(result.uncertainDispatches,1);assert.equal(f.calls(),1);assert.deepEqual(f.state.events,['close','release']);}finally{cancel.resolve();pull.resolve();await f.work.finish().catch(()=>{});f.restore();}
});

for(const [name,headers,chunk]of [
 ['declared oversize',{'Content-Type':'application/json','Content-Length':'600001'},null],
 ['invalid response type',{'Content-Type':'text/plain'},null],
 ['oversized received chunk',{'Content-Type':'application/json'},new Uint8Array(600001)],
])test('actual decoder '+name+' retains cancellation after refusing the response',async()=>{
 const cancel=defer(),started=defer();const f=await fixture(()=>Promise.resolve(new Response(new ReadableStream({pull(controller){if(chunk)controller.enqueue(chunk);},cancel(){started.resolve();return cancel.promise;}},{highWaterMark:0}),{headers})));
 try{await assert.rejects(f.call(),{code:'roster_decoder_response_invalid'});const closing=f.work.finish();await tick();assert.equal(f.state.events.includes('close'),false);await started.promise;cancel.resolve();const result=await closing;assert.equal(result.state,'settled');assert.equal(result.uncertainDispatches,1);assert.equal(f.calls(),1);}finally{cancel.resolve();await f.work.finish().catch(()=>{});f.restore();}
});

test('late response after caller abort is owned and cancelled before the durable work closes',async()=>{
 const started=defer(),headers=defer(),cancelStarted=defer(),cancel=defer(),control=new AbortController();const f=await fixture(()=>{started.resolve();return headers.promise;});
 try{const observed=f.call(control.signal);await started.promise;control.abort();await assert.rejects(observed,{code:'roster_decoder_aborted'});const closing=f.work.finish();await tick();assert.equal(f.state.events.includes('close'),false);headers.resolve(new Response(new ReadableStream({cancel(){cancelStarted.resolve();return cancel.promise;}},{highWaterMark:0}),{headers:{'Content-Type':'application/json'}}));await tick();assert.equal(f.state.events.includes('close'),false);await cancelStarted.promise;cancel.resolve();const result=await closing;assert.equal(result.reason,'completed_with_unknown_obligation');assert.equal(result.uncertainDispatches,1);assert.equal(f.calls(),1);}finally{cancel.resolve();headers.resolve(Response.json({}));await f.work.finish().catch(()=>{});f.restore();}
});

test('actual decoder original cryptographic promise is retained across pre-dispatch abort without inventing provider work',async()=>{
 const signing=defer(),started=defer(),control=new AbortController();const cryptoImpl={subtle:{importKey:(...args)=>webcrypto.subtle.importKey(...args),digest:(...args)=>webcrypto.subtle.digest(...args),verify:(...args)=>webcrypto.subtle.verify(...args),sign(){started.resolve();return signing.promise;}},randomUUID:()=> '33333333-3333-4333-8333-333333333333'};
 const f=await fixture(()=>{throw Error('No decoder dispatch permitted');},{cryptoImpl});
 try{const observed=f.call(control.signal);await started.promise;control.abort();await assert.rejects(observed,{code:'roster_decoder_aborted'});const closing=f.work.finish();await tick();assert.equal(f.state.events.includes('close'),false);signing.resolve(new Uint8Array(32).buffer);const result=await closing;assert.equal(result.state,'settled');assert.equal(result.externalDispatches,0);assert.equal(result.uncertainDispatches,0);assert.equal(f.calls(),0);}finally{signing.resolve(new Uint8Array(32).buffer);await f.work.finish().catch(()=>{});f.restore();}
});

test('native Response body methods remain tracked after caller observation ends; URL/redirect/status/headers retain original meaning',async()=>{
 const state=backend(),work=await openApplicationWork({backend:state,sourceSha256:SOURCE,kind:'http_collect'}),previous=globalThis.fetch;let body,calls=0;
 const raw=new Response(new ReadableStream({start(controller){body=controller;}},{highWaterMark:0}),{status:200,headers:{'Content-Type':'application/json','X-Synthetic':'unchanged'}});Object.defineProperties(raw,{url:{value:ENDPOINT+'/foreign'},redirected:{value:true}});globalThis.fetch=async()=>{calls++;return raw;};
 try{const response=await guardedFetch({COLLECT_FENCE_WORK:work},'decoder',ENDPOINT);assert.ok(response instanceof Response);assert.equal(response.url,ENDPOINT+'/foreign');assert.equal(response.redirected,true);assert.equal(response.status,200);assert.equal(response.headers.get('X-Synthetic'),'unchanged');const reading=response.json(),closing=work.finish();await tick();assert.equal(state.events.includes('close'),false);body.enqueue(new TextEncoder().encode('{"ok":true}'));body.close();assert.deepEqual(await reading,{ok:true});assert.equal((await closing).state,'settled');assert.equal(calls,1);}finally{try{body.close();}catch{}await work.finish().catch(()=>{});globalThis.fetch=previous;}
});


test('valid signed decoder response fully settles once with no invented unknown obligation',async()=>{
 const f=await fixture((_url,init)=>{const wire=JSON.parse(init.body),payload=JSON.stringify({contract_version:1,request_id:wire.request_id,reservation_id:wire.reservation_id,nonce:wire.nonce,issued_at:wire.issued_at,kind:'image',mime:'image/png',decoder_build_sha256:BUILD,ok:true,policy_version:'collect-roster-decoder-v1',toolchain:{python:'3.12',pillow:'12.3.0',pypdfium2:'5.2.0',pypdf:'6.19.0',openpyxl:'3.1.5',defusedxml:'0.7.1'},source_sha256:wire.source_sha256,source_size:1,derived_sha256:null,frames:1,pages:0,pixels:1,expanded_bytes:4,derived_content:null});return Response.json({payload,signature:createHmac('sha256','synthetic-decoder-secret-32-bytes-minimum').update(payload).digest('hex')});});
 try{const response=await f.call();assert.equal(response.status,200);assert.equal((await response.json()).content[0].type,'input_image');const result=await f.work.finish();assert.equal(result.state,'settled');assert.equal(result.reason,'completed');assert.equal(result.externalDispatches,1);assert.equal(result.uncertainDispatches,0);assert.equal(result.providerSettlement,false);assert.equal(f.calls(),1);assert.deepEqual(f.state.events,['close','release']);}finally{await f.work.finish().catch(()=>{});f.restore();}
});
