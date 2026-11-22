import test from 'node:test';
import assert from 'node:assert/strict';
import {isObservationCandidate} from '../../domain/burimunsi/postgres-observations.js';
import {bindNativeResponse,contractRoute,validateNativeRequest} from '../../domain/burimunsi/wire/native-contract.mjs';
import {createNativeHandler} from '../../domain/burimunsi/http.js';
import {BuriError,ObservationUploadUnresolved} from '../../domain/burimunsi/errors.js';

const id='11111111-1111-4111-8111-111111111111',install='22222222-2222-4222-8222-222222222222',
 source='33333333-3333-5333-8333-333333333333';
const profile={version:'approved-1',senders:['Example Money'],incomingPrefixes:['Received'],
 currencyAliases:['RWF'],transactionIdPrefixes:['Reference:']};
const candidate={rawSender:'Example Money',rawBody:'Received 250 RWF. Reference: 1234.'};
const body={requestId:id,...candidate,sourceMode:'live',complete:true,capturedAt:'2026-11-11T12:00:00.000Z',
 serviceCentreAt:null,inboxReceivedAt:null,subscriptionId:null};
const binding={requestId:id,generation:'1',installationId:install,groupId:'group-1',actorId:id};
const receipt={requestId:id,sourceId:source,bodySha256:'a'.repeat(64),status:'source_unresolved',financialEffects:0};

test('configured senders admit messages regardless of incoming-payment wording',()=>{
 assert.equal(isObservationCandidate(candidate,profile),true);
 for(const rawBody of ['Sent 250 RWF to a payee. Transaction ID 1234.',
  'A provider notice with no amount or reference.',
  'Received 250 RWF. Different transaction marker: 1234.',
  'Received 250 RWF. Reference: 1234. Verification code 4321',
  'Received 250 RWF.\nReference:\t1234.'])
  assert.equal(isObservationCandidate({...candidate,rawBody},profile),true);
 for(const input of [
  {...candidate,rawSender:'Different Provider'},
  {...candidate,rawBody:'Received 250 RWF.\u202eReference: 1234.'},
  {...candidate,rawBody:'Received '+ 'é'.repeat(1500)+' RWF. Reference: 1234.'},
 ])assert.equal(isObservationCandidate(input,profile),false);
 assert.equal(isObservationCandidate(candidate,{...profile,incomingPrefixes:['Other provider only']}),true);
 assert.equal(isObservationCandidate(candidate,{...profile,senders:['Other provider only']}),false);
 assert.equal(isObservationCandidate(candidate,{...profile,version:'unverified'}),false);
 assert.equal(isObservationCandidate(null,profile),false);
});

test('wire requires complete live and dated incomplete catch-up observations',()=>{
 assert.doesNotThrow(()=>validateNativeRequest('observation',body));
 assert.throws(()=>validateNativeRequest('observation',{...body,complete:false}));
 assert.throws(()=>validateNativeRequest('observation',{...body,sourceMode:'catch_up',complete:false}));
 assert.doesNotThrow(()=>validateNativeRequest('observation',{...body,sourceMode:'catch_up',complete:false,inboxReceivedAt:'2026-11-11T11:59:00Z'}));
 assert.throws(()=>validateNativeRequest('observation',{...body,rawBody:'é'.repeat(1501)}));
});

test('optional stable source keys are accepted only for dated catch-up rows',()=>{
 const catchup={...body,sourceMode:'catch_up',complete:false,inboxReceivedAt:'2026-11-11T11:59:00.000Z'};
 assert.doesNotThrow(()=>validateNativeRequest('observation',{...catchup,sourceKey:'a'.repeat(64)}));
 assert.throws(()=>validateNativeRequest('observation',{...catchup,sourceKey:'invalid'}));
 assert.throws(()=>validateNativeRequest('observation',{...body,sourceKey:'a'.repeat(64)}));
 assert.doesNotThrow(()=>validateNativeRequest('observation',catchup)); // retained legacy retry
});

test('capture and consent acknowledgements cannot change request identity',()=>{
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observation'},binding,body,receipt));
 assert.throws(()=>bindNativeResponse({operation:'observation'},binding,body,{...receipt,requestId:install}));
 assert.throws(()=>bindNativeResponse({operation:'observation'},binding,body,{...receipt,financialEffects:1}));
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationConsentSet'},binding,{enabled:false,generation:2},{enabled:false,generation:2}));
 assert.throws(()=>bindNativeResponse({operation:'observationConsentSet'},binding,{enabled:false,generation:2},{enabled:true,generation:2}));
});

test('observation pages and reveal bind source and group without canonical SMS identity',()=>{
 const item={id:source,groupId:'group-1',sourceKind:'observation',sourceId:source,status:'source_unresolved',
  at:'2026-11-11T12:00:00.000Z',financialEffects:0};
 const data={items:[item],totalCount:1,nextCursor:null,revision:'revision',asOf:'2026-11-11T12:00:01.000Z'};
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationPage'},binding,null,data));
 assert.throws(()=>bindNativeResponse({operation:'observationPage'},binding,null,{...data,items:[{...item,sourceId:id}]}));
 assert.throws(()=>bindNativeResponse({operation:'observationPage'},binding,null,{...data,items:[{...item,groupId:'other'}]}));
 const reveal={groupId:'group-1',sourceKind:'observation',sourceId:source,status:'source_unresolved',at:item.at,
  sender:'Example Money',rawBody:candidate.rawBody,financialEffects:0};
 assert.equal(contractRoute('POST','/sms/observations/'+source+'/reveal').operation,'observationReveal');
 assert.doesNotThrow(()=>bindNativeResponse({operation:'observationReveal',recordId:source},binding,{reason:'Review source receipt'},reveal));
 assert.throws(()=>bindNativeResponse({operation:'observationReveal',recordId:source},binding,{reason:'Review source receipt'},{...reveal,sourceId:id}));
});

test('default-off observations do not alter the existing canonical SMS route',async()=>{
 let canonicalReads=0;const noop=async()=>({});
 const handler=createNativeHandler({
  auth:{login:noop,authenticate:async()=>({id,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:async()=>{canonicalReads++;return {items:[]}},detail:noop,exportLedger:noop,commandStatus:noop},
  contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  origin:'https://example.invalid',networkBucket:noop,
 });
 const request=path=>new Request('https://example.invalid/v1/burimunsi'+path,
  {headers:{'x-burimunsi-installation':install,authorization:'Bearer '+'a'.repeat(64)}});
 assert.equal((await handler(request('/sms'))).status,200);assert.equal(canonicalReads,1);
 assert.equal((await handler(request('/sms/observations'))).status,503);assert.equal(canonicalReads,1);
});

test('strict HTTP routes preserve observation consent, capture and disclosure identity',async()=>{
 const noop=async()=>({}),calls=[];
 const item={id:source,groupId:'group-1',sourceKind:'observation',sourceId:source,status:'source_unresolved',
  at:'2026-11-11T12:00:00.000Z',financialEffects:0};
 const observations={
  readConsent:async()=>({enabled:true,generation:1}),
  setConsent:async(_actor,v)=>{calls.push(['consent',v]);return v;},
  profile:async()=>({profileVersion:'approved-1',offsetMinutes:120,senders:['Example Money'],incomingPrefixes:['Received'],
   currencyAliases:['RWF'],transactionIdPrefixes:['Reference:'],issuedAt:1000,expiresAt:86401000}),
  observe:async(_actor,v)=>{calls.push(['observe',v]);return {...receipt,requestId:v.requestId};},
  page:async(_actor,q)=>{calls.push(['page',q]);return {items:[item],totalCount:1,nextCursor:null,revision:'revision',asOf:item.at};},
  reveal:async(_actor,sourceId,input)=>{calls.push(['reveal',sourceId,input]);return {groupId:'group-1',sourceKind:'observation',
   sourceId,status:'source_unresolved',at:item.at,sender:candidate.rawSender,rawBody:candidate.rawBody,financialEffects:0};},
 };
 const handler=createNativeHandler({
  auth:{login:noop,authenticate:async()=>({id,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},
  contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},observations,
  origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop,
 });
 const req=(path,method='GET',value)=>new Request('https://example.invalid/v1/burimunsi'+path,{method,
  headers:{'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1',
   'x-burimunsi-request':id,'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json'},
  ...(value===undefined?{}:{body:JSON.stringify(value)})});
 assert.equal((await handler(req('/sms/observation-consent','POST',{enabled:false,generation:2}))).status,200);
 assert.equal((await handler(req('/sms/observation-profile'))).status,200);
 assert.equal((await handler(req('/sms/observations','POST',body))).status,200);
 assert.equal((await handler(req('/sms/observations?q=333&limit=40'))).status,200);
 assert.equal((await handler(req('/sms/observations/'+source+'/reveal','POST',{reason:'Review source receipt'}))).status,200);
 assert.equal((await handler(req('/sms/observations','POST',{...body,complete:false}))).status,400);
 assert.equal(calls.filter(call=>call[0]==='observe').length,1);
 assert.deepEqual(calls.at(-1),['reveal',source,{reason:'Review source receipt',requestId:id}]);
});

test('only a verified exact observation uncertainty carries versioned request correlation headers',async()=>{
 const noop=async()=>({}),correlation='44444444-4444-4444-8444-444444444444';let failure=new ObservationUploadUnresolved(id);
 const handler=createNativeHandler({
  auth:{login:noop,authenticate:async()=>({id,groupId:'group-1'}),logout:noop,changePasscode:noop,manageStaff:noop},
  records:{home:noop,page:noop,detail:noop,exportLedger:noop,commandStatus:noop},
  contributions:{allocate:noop},members:{enroll:noop,setActive:noop},gateway:{status:noop,replace:noop},
  observations:{observe:async()=>{throw failure;}},origin:'https://example.invalid',groupId:'group-1',strictContract:true,networkBucket:noop,
 });
 const request=()=>new Request('https://example.invalid/v1/burimunsi/sms/observations',{method:'POST',
  headers:{'x-burimunsi-installation':install,'x-burimunsi-contract':'burimunsi.native.v1','x-burimunsi-request':correlation,
   'x-burimunsi-generation':'1',authorization:'Bearer '+'a'.repeat(64),'content-type':'application/json'},body:JSON.stringify(body)});
 let response=await handler(request());assert.equal(response.status,503);
 assert.deepEqual(await response.json(),{contractVersion:'burimunsi.native.v1',ok:false,error:{code:'observation_upload_unresolved'}});
 assert.equal(response.headers.get('x-burimunsi-observation-unresolved'),'v1');
 assert.equal(response.headers.get('x-burimunsi-observation-request-id'),id);
 assert.equal(response.headers.get('x-burimunsi-correlation-id'),correlation);
 assert.equal(response.headers.get('x-burimunsi-observation-body-sha256'),null);
 for(failure of [new ObservationUploadUnresolved(install),new BuriError('observation_upload_unresolved',503),new BuriError('access_denied',403)]){
  response=await handler(request());assert.equal(response.headers.get('x-burimunsi-observation-unresolved'),null);
  assert.equal(response.headers.get('x-burimunsi-observation-request-id'),null);
  assert.equal(response.headers.get('x-burimunsi-correlation-id'),null);
 }
});

test('hint wire is opt-in and requires unique exact UTF-16 quotations',()=>{
 const body='😀 Received 250 RWF. Reference: 1234. Thank you.';
 const data={groupId:'group-1',sourceKind:'observation',sourceId:source,status:'source_unresolved',at:'2026-11-11T12:00:00.000Z',
  sender:'Example Money',rawBody:body,financialEffects:0};
 const hint={kind:'quoted_incoming_amount',text:'Received 250 RWF',start:3,end:19};
 const displayHints={schemaVersion:1,kind:'partial_inbox_display_only',profileVersion:'approved-1',profileSha256:'a'.repeat(64),bodySha256:'b'.repeat(64),hints:[hint]};
 const route={operation:'observationReveal',recordId:source},opt={reason:'Review source receipt',displayHintsVersion:1};
 assert.doesNotThrow(()=>validateNativeRequest('observationReveal',opt));
 assert.doesNotThrow(()=>bindNativeResponse(route,binding,opt,{...data,displayHints}));
 assert.doesNotThrow(()=>bindNativeResponse(route,binding,opt,{...data,displayHints:null}));
 assert.throws(()=>bindNativeResponse(route,binding,opt,data));
 assert.throws(()=>bindNativeResponse(route,binding,{reason:opt.reason},{...data,displayHints}));
 for(const hints of [[{...hint,start:2}],[{...hint,end:18}],[hint,hint]])
  assert.throws(()=>bindNativeResponse(route,binding,opt,{...data,displayHints:{...displayHints,hints}}));
});
