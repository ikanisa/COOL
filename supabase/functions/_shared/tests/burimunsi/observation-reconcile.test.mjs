import test from 'node:test';
import assert from 'node:assert/strict';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
import {bindNativeResponse,validateNativeRequest} from '../../domain/burimunsi/wire/native-contract.mjs';

const actor='11111111-1111-4111-8111-111111111111',install='22222222-2222-4222-8222-222222222222',source='33333333-3333-5333-8333-333333333333';
const input={sourceKey:'a'.repeat(64),bodySha256:'b'.repeat(64),rawSender:'Example Money',serviceCentreAt:null,
 inboxReceivedAt:'2026-11-11T12:00:00.000Z',subscriptionId:null};
const binding={requestId:actor,generation:'1',installationId:install,groupId:'group-1',actorId:actor};
const matched={groupId:'group-1',sourceKey:input.sourceKey,state:'matched',sourceId:source,latestRecordedSourceId:source};

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
 const ok=await handler(new Request(url,{headers}));assert.equal(ok.status,200);assert.deepEqual((await ok.json()).data,data);
 assert.equal((await handler(new Request(url+'?q=private',{headers}))).status,400);assert.equal(calls,1);
});
