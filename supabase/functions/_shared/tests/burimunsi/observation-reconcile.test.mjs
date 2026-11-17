import test from 'node:test';
import assert from 'node:assert/strict';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
import {BuriError} from '../../domain/burimunsi/errors.js';
import {bindNativeResponse,validateNativeRequest} from '../../domain/burimunsi/wire/native-contract.mjs';
import {sha256} from '../../domain/burimunsi/values.js';

const actor='11111111-1111-4111-8111-111111111111',install='22222222-2222-4222-8222-222222222222',source='33333333-3333-5333-8333-333333333333';
const input={sourceKey:'a'.repeat(64),bodySha256:'b'.repeat(64),rawSender:'Example Money',serviceCentreAt:null,
 inboxReceivedAt:'2026-11-11T12:00:00.000Z',subscriptionId:null};
const binding={requestId:actor,generation:'1',installationId:install,groupId:'group-1',actorId:actor};
const matched={groupId:'group-1',sourceKey:input.sourceKey,state:'matched',sourceId:source,latestRecordedSourceId:source};

test('held recovery wire requires a non-financial acknowledgement bound to the original request',async()=>{
 const request={requestId:actor,rawSender:'Example Money',rawBody:'Received 250 RWF. Reference: 1234.',
  sourceMode:'catch_up',complete:false,capturedAt:'2026-11-11T12:01:00.000Z',
  serviceCentreAt:null,inboxReceivedAt:input.inboxReceivedAt,subscriptionId:null,sourceKey:input.sourceKey,expectedConsentGeneration:1};
 const result={requestId:actor,sourceId:source,bodySha256:input.bodySha256,status:'source_unresolved',financialEffects:0,autoProcessing:'held'};
 assert.doesNotThrow(()=>validateNativeRequest('observationRecoverHeld',request));
 for(const bad of [{...request,inboxReceivedAt:null},{...request,sourceKey:undefined},
  {...request,expectedConsentGeneration:undefined},{...request,expectedConsentGeneration:0},
  {...request,expectedConsentGeneration:1.5},{...request,expectedConsentGeneration:9007199254740992},
  {...request,sourceMode:'live',complete:true},{...request,unapproved:true}])
  assert.throws(()=>validateNativeRequest('observationRecoverHeld',bad));
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationRecoverHeld'},binding,request,result));
 for(const bad of [{...result,requestId:install},{...result,financialEffects:1},{...result,autoProcessing:'automatic'},
  {...result,rawBody:request.rawBody}])assert.throws(()=>bindNativeResponse({operation:'observationRecoverHeld'},binding,request,bad));
 const noop=async()=>({}),calls=[];
 const handler=createNativeHandler({auth:{login:noop,authenticate:async()=>({id:actor,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  observations:{recoverHeld:async(_actor,body)=>{calls.push(body);return result;}},
  origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop,heldRecoveryEnabled:true});
 const req=body=>new Request('https://example.invalid/v1/burimunsi/sms/observations/recover-held',{method:'POST',headers:{
  'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':actor,
  'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json'},body:JSON.stringify(body)});
 const ok=await handler(req(request));assert.equal(ok.status,200);assert.deepEqual((await ok.json()).data,result);
 assert.equal((await handler(req({...request,inboxReceivedAt:null}))).status,400);assert.equal(calls.length,1);
});

test('held recovery route is unavailable unless the server explicitly enables it',async()=>{
 const noop=async()=>({});let invoked=0;
 const handler=createNativeHandler({auth:{login:noop,authenticate:async()=>({id:actor,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  observations:{recoverHeld:async()=>{invoked++;return {};}},origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop});
 const headers={
  'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':actor,
  'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json'};
 const request={requestId:actor,rawSender:'Example Money',rawBody:'Received 250 RWF. Reference: 1234.',
  sourceMode:'catch_up',complete:false,capturedAt:'2026-11-11T12:01:00.000Z',serviceCentreAt:null,
  inboxReceivedAt:input.inboxReceivedAt,subscriptionId:null,sourceKey:input.sourceKey,expectedConsentGeneration:1};
 const {expectedConsentGeneration,...oldClient}=request;
 for(const body of [{},oldClient,request]){
  const response=await handler(new Request('https://example.invalid/v1/burimunsi/sms/observations/recover-held',{
   method:'POST',headers,body:JSON.stringify(body)}));
  assert.equal(response.status,404);
 }
 assert.equal(invoked,0);
});

test('held acknowledgement wire is request-bound, read-only and disabled by default',async()=>{
 const request={requestId:actor,rawSender:'Example Money',rawBody:'Received 250 RWF. Reference: 1234.',
  sourceMode:'catch_up',complete:false,capturedAt:'2026-11-11T12:01:00.000Z',
  serviceCentreAt:null,inboxReceivedAt:input.inboxReceivedAt,subscriptionId:null,sourceKey:input.sourceKey,expectedConsentGeneration:1};
 const data={requestId:actor,sourceKey:request.sourceKey,bodySha256:await sha256(request.rawBody),
  state:'acknowledged',sourceId:source,autoProcessing:'held',financialEffects:0,retryAllowed:false};
 const pending={...data,state:'unconfirmed',sourceId:null,autoProcessing:'unknown'};
 assert.doesNotThrow(()=>validateNativeRequest('observationRecoverHeldAck',request));
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationRecoverHeldAck'},binding,request,data));
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationRecoverHeldAck'},binding,request,pending));
 for(const bad of [{...data,requestId:install},{...data,sourceKey:'d'.repeat(64)},{...data,sourceId:null},
  {...data,state:'unconfirmed'},{...data,autoProcessing:'unknown'},{...data,retryAllowed:true},
  {...pending,sourceId:source},{...pending,autoProcessing:'held'},{...data,rawBody:request.rawBody}])
  assert.throws(()=>bindNativeResponse({operation:'observationRecoverHeldAck'},binding,request,bad));
 const noop=async()=>({});let calls=0,received=null;
 const options={auth:{login:noop,authenticate:async()=>({id:actor,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},contributions:{allocate:noop},
  members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  observations:{recoverHeldAck:async(_actor,body)=>{calls++;received=body;return data;}},
  origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop};
 const headers={'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':actor,
  'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json'};
 const url='https://example.invalid/v1/burimunsi/sms/observations/recover-held-ack';
 const req=()=>new Request(url,{method:'POST',headers,body:JSON.stringify(request)});
 assert.equal((await createNativeHandler(options)(req())).status,404);assert.equal(calls,0);
 const enabled=createNativeHandler({...options,heldRecoveryEnabled:true});
 const ok=await enabled(req());assert.equal(ok.status,200);assert.deepEqual((await ok.json()).data,data);assert.equal(calls,1);
 assert.equal(JSON.stringify(received),JSON.stringify(request));
 const {expectedConsentGeneration,...oldClient}=request;
 const legacy=await enabled(new Request(url,{method:'POST',headers,body:JSON.stringify(oldClient)}));
 assert.equal(legacy.status,400);assert.equal(calls,1);
 const wrongHash=createNativeHandler({...options,heldRecoveryEnabled:true,
  observations:{recoverHeldAck:async()=>({...data,bodySha256:'0'.repeat(64)})}});
 assert.equal((await wrongHash(req())).status,503);
});

test('reconciliation wire contract binds the source key and source outcome',()=>{
 assert.doesNotThrow(()=>validateNativeRequest('observationReconcile',input));
 for(const bad of [{...input,sourceKey:'a'}, {...input,inboxReceivedAt:null}, {...input,rawBody:'private'}])
  assert.throws(()=>validateNativeRequest('observationReconcile',bad));
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationReconcile'},binding,input,matched));
 assert.throws(()=>bindNativeResponse({operation:'observationReconcile'},binding,input,{...matched,sourceKey:'c'.repeat(64)}));
 assert.throws(()=>bindNativeResponse({operation:'observationReconcile'},binding,input,{...matched,state:'missing'}));
 assert.throws(()=>bindNativeResponse({operation:'observationReconcile'},binding,input,{...matched,rawBody:'private'}));
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationReconcile'},binding,input,
  {...matched,state:'missing',sourceId:null,latestRecordedSourceId:null}));
});

test('strict HTTP reconciliation route forwards metadata only',async()=>{
 const noop=async()=>({});const calls=[];
 const handler=createNativeHandler({auth:{login:noop,authenticate:async()=>({id:actor,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  observations:{reconcile:async(_actor,body)=>{calls.push(body);return matched;}},
  origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop});
 const req=body=>new Request('https://example.invalid/v1/burimunsi/sms/observations/reconcile',{method:'POST',headers:{
  'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':actor,
  'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json'},body:JSON.stringify(body)});
 const ok=await handler(req(input));assert.equal(ok.status,200);assert.deepEqual((await ok.json()).data,matched);
 assert.equal((await handler(req({...input,rawBody:'private'}))).status,400);assert.equal(calls.length,1);
 assert.equal(JSON.stringify(calls[0]),JSON.stringify(input));
});

test('batch wire binds ordered source identities and rejects ambiguous outcomes',()=>{
 const second={...input,sourceKey:'c'.repeat(64)},body={items:[input,second]};
 const items=[{sourceKey:input.sourceKey,state:'matched',sourceId:source},
  {sourceKey:second.sourceKey,state:'missing',sourceId:null}];
 const result={groupId:'group-1',items};
 assert.doesNotThrow(()=>validateNativeRequest('observationReconcileBatch',body));
 for(const bad of [{items:[]},{items:[input,input]}, {items:Array(21).fill(input)},
  {items:[{...input,rawBody:'private'}]}])
  assert.throws(()=>validateNativeRequest('observationReconcileBatch',bad));
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationReconcileBatch'},binding,body,result));
 for(const bad of [
  {...result,items:[...items].reverse()},
  {...result,items:[items[0]]},
  {...result,items:[items[0],{...items[1],sourceKey:'d'.repeat(64)}]},
  {...result,items:[{...items[0],sourceId:null},items[1]]},
  {...result,items:[items[0],{...items[1],sourceId:source}]},
  {...result,items:[{...items[0],rawBody:'private'},items[1]]},
  {...result,groupId:'another-group'}
 ])assert.throws(()=>bindNativeResponse({operation:'observationReconcileBatch'},binding,body,bad));
});

test('batch HTTP forwards only bounded metadata and rejects oversize and duplicate keys',async()=>{
 const noop=async()=>({}),calls=[];
 const handler=createNativeHandler({auth:{login:noop,authenticate:async()=>({id:actor,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  observations:{reconcileBatch:async(_actor,body)=>{calls.push(body);return {groupId:'group-1',items:body.items.map(item=>
   ({sourceKey:item.sourceKey,state:'missing',sourceId:null}))};}},
  origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop});
 const req=body=>new Request('https://example.invalid/v1/burimunsi/sms/observations/reconcile-batch',{method:'POST',headers:{
  'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':actor,
  'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json'},body:JSON.stringify(body)});
 const good={items:[input,{...input,sourceKey:'c'.repeat(64)}]};
 const ok=await handler(req(good));assert.equal(ok.status,200);
 assert.deepEqual((await ok.json()).data.items.map(x=>x.sourceKey),good.items.map(x=>x.sourceKey));
 assert.equal((await handler(req({items:[input,input]}))).status,400);
 const twenty={items:Array.from({length:20},(_,i)=>({...input,sourceKey:i.toString(16).padStart(64,'0')}))};
 assert.ok(Buffer.byteLength(JSON.stringify(twenty))<=8192);
 const full=await handler(req(twenty));assert.equal(full.status,200);
 assert.deepEqual((await full.json()).data.items.map(x=>x.sourceKey),twenty.items.map(x=>x.sourceKey));
 const large={items:Array.from({length:20},(_,i)=>({...input,sourceKey:i.toString(16).padStart(64,'0'),rawSender:'é'.repeat(96)}))};
 assert.ok(Buffer.byteLength(JSON.stringify(large))>8192);
 assert.equal((await handler(req(large))).status,413);
 assert.equal(calls.length,2);assert.equal(JSON.stringify(calls[0]),JSON.stringify(good));
});

test('batch HTTP preserves item and authority errors for Android',async()=>{
 const noop=async()=>({});let failure;
 const handler=createNativeHandler({auth:{login:noop,authenticate:async()=>({id:actor,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  observations:{reconcileBatch:async()=>{throw failure;}},origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop});
 for(const [code,status] of [['observation_item_conflict',409],['observation_item_unavailable',503],['access_denied',403],['observation_unavailable',503]]){
  failure=new BuriError(code,status);
  const response=await handler(new Request('https://example.invalid/v1/burimunsi/sms/observations/reconcile-batch',{method:'POST',headers:{
   'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':actor,
   'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json'},body:JSON.stringify({items:[input]})}));
  assert.equal(response.status,status);assert.equal((await response.json()).error.code,code);
 }
});

test('collection status binds group, validates count and has no body or query',async()=>{
 const data={groupId:'group-1',hasPending:false,hasRecorded:true,recordedCount:1,hasUnmatchedCanonical:false,revision:'a'.repeat(64)};
 assert.doesNotThrow(()=>validateNativeRequest('observationReconcileStatus',null));
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationReconcileStatus'},binding,null,data));
 for(const bad of [{...data,hasRecorded:false},{...data,revision:'bad'},{...data,groupId:'other'},{...data,recordedCount:100001},
  {...data,privateValue:'not allowed'}])assert.throws(()=>bindNativeResponse({operation:'observationReconcileStatus'},binding,null,bad));
 const noop=async()=>({});let calls=0;
 const handler=createNativeHandler({auth:{login:noop,authenticate:async()=>({id:actor,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  observations:{reconcileStatus:async()=>{calls++;return data;}},origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop});
 const headers={'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':actor,
  'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64)};
 const url='https://example.invalid/v1/burimunsi/sms/observations/reconcile-status';
 const ok=await handler(new Request(url,{headers}));assert.equal(ok.status,200);assert.deepEqual((await ok.json()).data,{...data,hasPending:true});
 assert.equal((await handler(new Request(url+'?q=private',{headers}))).status,400);assert.equal(calls,1);
});

test('installed v47 legacy status remains unconfirmed regardless of the recovery flag',async()=>{
 const noop=async()=>({});let legacyCalls=0,verifiedCalls=0;
 const baseline={groupId:'group-1',hasPending:false,hasRecorded:true,recordedCount:1,
  hasUnmatchedCanonical:false,revision:'a'.repeat(64)};
 const options={auth:{login:noop,authenticate:async()=>({id:actor,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},contributions:{allocate:noop},
  members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  observations:{reconcileStatus:async()=>{legacyCalls++;return baseline;},reconcileVerifiedStatus:async()=>{verifiedCalls++;return {...baseline,scope:'verified_collection'};}},
  origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop};
 const headers={'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1',
  'x-burimunsi-request':actor,'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64)};
 const url='https://example.invalid/v1/burimunsi/sms/observations/reconcile-status';
 for(const heldRecoveryEnabled of [false,true]){
  const response=await createNativeHandler({...options,heldRecoveryEnabled})(new Request(url,{headers}));
  assert.equal(response.status,200);const data=(await response.json()).data;
  assert.deepEqual(data,{...baseline,hasPending:true});assert.equal(Object.hasOwn(data,'scope'),false);
  assert.doesNotThrow(()=>bindNativeResponse({operation:'observationReconcileStatus'},binding,null,data));
 }
 assert.equal(legacyCalls,2);assert.equal(verifiedCalls,0);
});

test('verified collection status is an explicit opt-in route with a strict, backwards-compatible response',async()=>{
 const data={groupId:'group-1',hasPending:false,hasRecorded:true,recordedCount:1,
  hasUnmatchedCanonical:false,revision:'a'.repeat(64)},verified={...data,scope:'verified_collection'};
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationReconcileStatus'},binding,null,data));
 assert.throws(()=>bindNativeResponse({operation:'observationReconcileStatus'},binding,null,verified));
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationReconcileVerifiedStatus'},binding,null,verified));
 for(const bad of [data,{...verified,scope:'all_receipts'}, {...verified,hasRecorded:false},
  {...verified,groupId:'other'}])
  assert.throws(()=>bindNativeResponse({operation:'observationReconcileVerifiedStatus'},binding,null,bad));
 const noop=async()=>({});let calls=0;
 const options={auth:{login:noop,authenticate:async()=>({id:actor,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},contributions:{allocate:noop},
  members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  observations:{reconcileVerifiedStatus:async()=>{calls++;return verified;}},origin:'https://example.invalid',
  groupId:'group-1',strictContract:true,networkBucket:noop};
 const headers={'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1',
  'x-burimunsi-request':actor,'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64)};
 const url='https://example.invalid/v1/burimunsi/sms/observations/reconcile-verified-status';
 assert.equal((await createNativeHandler(options)(new Request(url,{headers}))).status,404);assert.equal(calls,0);
 const enabled=createNativeHandler({...options,heldRecoveryEnabled:true});
 const ok=await enabled(new Request(url,{headers}));assert.equal(ok.status,200);assert.deepEqual((await ok.json()).data,verified);
 assert.equal((await enabled(new Request(url+'?q=private',{headers}))).status,400);assert.equal(calls,1);
});
