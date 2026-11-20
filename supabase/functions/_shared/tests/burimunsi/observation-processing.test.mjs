import test from 'node:test';
import assert from 'node:assert/strict';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
import {PostgresNativeObservations} from '../../domain/burimunsi/postgres-observations.js';
import {bindNativeResponse,validateNativeRequest} from '../../domain/burimunsi/wire/native-contract.mjs';

const actorId='11111111-1111-4111-8111-111111111111',install='22222222-2222-4222-8222-222222222222',source='33333333-3333-5333-8333-333333333333',requestId='44444444-4444-4444-8444-444444444444';
const binding={requestId:actorId,generation:'1',installationId:install,groupId:'group-1',actorId};
const status={groupId:'group-1',statuses:[{sourceId:source,status:'retrying',canRetry:true}]};
const retry={groupId:'group-1',sourceId:source,requestId,result:'scheduled'};

test('new strict contracts preserve source identity and reject inconsistent statuses',()=>{
 assert.doesNotThrow(()=>validateNativeRequest('observationProcessingStatus',{sourceIds:[source]}));
 assert.throws(()=>validateNativeRequest('observationProcessingStatus',{sourceIds:[source,source]}));
 assert.throws(()=>validateNativeRequest('observationProcessingStatus',{sourceIds:[]}));
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationProcessingStatus'},binding,{sourceIds:[source]},status));
 assert.throws(()=>bindNativeResponse({operation:'observationProcessingStatus'},binding,{sourceIds:[source]},{...status,statuses:[{...status.statuses[0],sourceId:requestId}]}));
 assert.throws(()=>bindNativeResponse({operation:'observationProcessingStatus'},binding,{sourceIds:[source]},{...status,statuses:[{...status.statuses[0],status:'parsed'}]}));
 assert.throws(()=>bindNativeResponse({operation:'observationProcessingStatus'},binding,{sourceIds:[source]},{...status,statuses:[{...status.statuses[0],rawBody:'sensitive'}]}));
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationProcessingRetry',recordId:source},binding,{requestId},retry));
 assert.throws(()=>bindNativeResponse({operation:'observationProcessingRetry',recordId:source},binding,{requestId},{...retry,requestId:actorId}));
});

test('HTTP uses additive batched status and retry routes without changing old observation page',async()=>{
 const noop=async()=>({});const calls=[];
 const handler=createNativeHandler({auth:{login:noop,authenticate:async()=>({id:actorId,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  observations:{processingStatus:async(_,input)=>{calls.push(input);return status;},processingRetry:async(_,id,input)=>{calls.push([id,input]);return retry;}},
  origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop});
 const req=(path,body)=>new Request('https://example.invalid/v1/burimunsi'+path,{method:'POST',headers:{'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':actorId,'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json'},body:JSON.stringify(body)});
 assert.equal((await handler(req('/sms/observations/processing-status',{sourceIds:[source]}))).status,200);
 assert.equal((await handler(req('/sms/observations/'+source+'/retry',{requestId}))).status,200);
 assert.equal((await handler(req('/sms/observations/processing-status',{sourceIds:[source,source]}))).status,400);
 assert.equal(calls.length,2);
});

test('adapter denies staff and switched groups before either database operation',async()=>{
 const session={id:actorId,sessionId:requestId,groupId:'group-1',principalUserId:'principal-a',installationId:install,role:'admin',installationProfile:'internal_receiver',active:true,revoked:false};
 const input={...session};let queries=0;
 const tx={unsafe:async(query,args)=>{queries++;if(query.includes('processing_status'))return [{result:status}];if(query.includes('processing_retry'))return [{result:retry}];throw Error('unexpected');}};
 const adapter=Object.create(PostgresNativeObservations.prototype);adapter.groupId='group-1';
 adapter.authority={session:async()=>session,read:async(fn)=>fn(tx),write:async(fn)=>fn(tx)};
 assert.deepEqual(await adapter.processingStatus(input,{sourceIds:[source]}),status);
 assert.deepEqual(await adapter.processingRetry(input,source,{requestId}),retry);
 for(const changes of [{role:'staff'},{installationProfile:'staff'},{groupId:'other'},{revoked:true},{id:requestId}]){
  Object.assign(session,changes);await assert.rejects(adapter.processingStatus(input,{sourceIds:[source]}),{code:'access_denied'});Object.assign(session,input);
 }
 assert.equal(queries,2);
});
