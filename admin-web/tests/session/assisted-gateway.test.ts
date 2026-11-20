import {createHash,webcrypto} from 'node:crypto';
import {afterEach,beforeEach,describe,expect,it,vi} from 'vitest';
import {PENDING_KEY,type PendingIdentity} from '../../src/features/core/pendingAttempt';
import type {AssistedJob} from '../../src/features/assisted/AssistedSmsPage';
import {AssistedSmsGateway,parseGatewayObservation,type AssistedGatewayContext} from '../../src/features/assisted/assistedGateway';
import {AssistedOperator,OperatorOutcomeUnknown,type OperatorContext} from '../../src/features/assisted/operatorWorkflow';

const actor='cdd3c1c0-c124-4c8a-9719-bd2435d198d1',principal='53c51330-f311-4519-977b-30f67b47c1f1',session='0f689afa-5a45-4fb5-a147-9aff36f137dd',jobId='6ea1b44a-25b7-4f2a-9d20-5829675211bc',payment='fa1e3f37-1e2b-4e57-9d7d-77f0c13d0d50',claim='0d7bfc80-d88c-4b4c-9f7d-9935f6c5aaf1',attempt='1cb27c41-c93b-4efe-bd7b-a8a52fd81239';
const token='e'.repeat(64),destination='+250788123456',message='Synthetic contribution record; no delivery claim.', evidence='f'.repeat(64),hash=(value:string)=>createHash('sha256').update(value).digest('hex');
const marker={contract_version:1,scope:'assisted_sms_internal_record',delivery_confirmed:false,provider_confirmation:false,settlement_status:'not_asserted'};
const gatewayMarker={contract_version:1,scope:'assisted_sms_gateway_observation',delivery_confirmed:false,provider_confirmation:false,settlement_status:'not_asserted',may_send:false};
const observation=(state='accepted',accepted=true,value:unknown=null)=>({ok:true,result:{...gatewayMarker,attempt_id:attempt,gateway_state:state,provider_accepted:accepted,observation:value,evidence_reference_sha256:evidence}});
const job:AssistedJob={id:jobId,payment_id:payment,state:'queued',fence:0,attempt_id:null,created_at:'2026-10-18T12:34:56.000Z'};
let current=true;
function identity():PendingIdentity&{principalId:string}{return {id:actor,sessionId:session,principalId:principal,email:'admin@example.test',role:'staff',permissions:['assisted_sms.read','assisted_sms.manage'],expiresAt:new Date(Date.now()+3600000).toISOString()};}
function gatewayContext(request:AssistedGatewayContext['request']):AssistedGatewayContext{return {request,identity:identity(),verificationMode:'email',enabled:true,verifyFresh:async()=>true,isCurrent:()=>current};}
function fixture({tokenIssued=true,replay=false,loseStart=false,dispatchFailure=false}:{tokenIssued?:boolean;replay?:boolean;loseStart?:boolean;dispatchFailure?:boolean}={}){
  const expires=new Date(Date.now()+120000).toISOString(),receipts=new Map<string,Record<string,unknown>>();
  const request=vi.fn(async(_path:string,options?:{body?:Record<string,unknown>})=>{
    const data=options?.body??{},action=data.action;
    if(action==='claim'){const value={...marker,job_id:jobId,claim_token:claim,fence_version:1,worker_id:data.worker_id,claim_expires_at:expires,originating_session_id:principal,public_session_id:session};receipts.set(String(data.request_id),value);return {ok:true,result:value};}
    if(action==='get_claimed')return {ok:true,result:{...marker,job_id:jobId,claim_token:claim,fence_version:1,destination_e164:destination,destination_sha256:hash(destination),destination_revision:2,message_body:message,body_sha256:hash(message),payment_id:payment,template_key:'collect.recorded_contribution.v1',claim_expires_at:expires}};
    if(action==='confirm'){const value={...marker,job_id:jobId,confirmation_id:data.confirmation_id,claim_token:claim,fence_version:1,body_sha256:hash(message),destination_sha256:hash(destination),destination_revision:2,expires_at:expires,originating_session_id:principal,public_session_id:session};receipts.set(String(data.request_id),value);return {ok:true,result:value};}
    if(action==='record_send_start'){
      expect(sessionStorage.getItem(PENDING_KEY)).not.toContain(token);expect(sessionStorage.getItem(PENDING_KEY)).not.toContain(destination);expect(sessionStorage.getItem(PENDING_KEY)).not.toContain(message);
      const stored={...marker,attempt_id:attempt,job_id:jobId,confirmation_id:data.confirmation_id,claim_token:claim,fence_version:1,state:'send_started',originating_session_id:principal,public_session_id:session};receipts.set(String(data.request_id),stored);
      if(loseStart)throw new Error('lost response');
      return {ok:true,result:{...stored,replay,may_send:!replay,acknowledgement:replay?'recorded_start_permit_not_reissued':'first_committed_response_only',...(tokenIssued?{dispatch_token:token}:{})}};
    }
    if(action==='dispatch_gateway'){if(dispatchFailure)throw new Error('synthetic unavailable');return observation();}
    if(action==='inspect_gateway')return observation('sent',true,'observed_sent');
    if(action==='get_operation'){const saved=receipts.get(String(data.request_id))??null;return {ok:true,result:{...marker,request_id:data.request_id,observed:saved!==null,receipt:saved,may_send:false}};}
    throw new Error('unexpected synthetic action');
  });
  return {request,receipts};
}
function operatorContext(request:OperatorContext['request']):OperatorContext {
  const actorIdentity=identity(),gateway=new AssistedSmsGateway({request,identity:actorIdentity,verificationMode:'email',enabled:true,verifyFresh:async()=>true,isCurrent:()=>current});
  return {allowWrites:true,allowGateway:true,gatewayVerificationMode:'email',gateway,epoch:1,identity:actorIdentity,request,verifyFresh:async()=>true,isCurrent:()=>current};
}
async function confirmed(operator:AssistedOperator){await operator.claim(job);await operator.loadContent();await operator.confirm(true);}
beforeEach(()=>{vi.stubGlobal('crypto',webcrypto);sessionStorage.clear();localStorage.clear();current=true;});
afterEach(()=>{sessionStorage.clear();localStorage.clear();vi.restoreAllMocks();vi.unstubAllGlobals();});

describe('assisted SMS gateway observation contract',()=>{
  it('accepts only the newer gateway state and observation combinations',()=>{
    expect(parseGatewayObservation(observation('unknown',false,null),attempt)).toMatchObject({providerAccepted:false,observation:null});
    for(const state of ['accepted','assigned','phone_accepted','queued','handoff_started'])expect(parseGatewayObservation(observation(state,true,null),attempt).observation).toBeNull();
    for(const state of ['sent','delivered','delivery_unconfirmed'])expect(parseGatewayObservation(observation(state,true,'observed_sent'),attempt).observation).toBe('observed_sent');
    for(const state of ['failed','partial','outcome_unknown','cancelled','expired'])expect(parseGatewayObservation(observation(state,true,'uncertain'),attempt).observation).toBe('uncertain');
    for(const invalid of [observation('unknown',true,null),observation('sent',false,'observed_sent'),observation('failed',true,'failed_no_send'),observation('sent',true,'uncertain'),{...observation(),result:{...observation().result,delivery_confirmed:true}},{...observation(),result:{...observation().result,attempt_id:jobId}},{...observation(),result:{...observation().result,evidence_reference_sha256:'bad'}}])expect(()=>parseGatewayObservation(invalid,attempt)).toThrow();
  });
  it('requires opt-in, current account, email verification and fresh proof before taking a grant',async()=>{
    const request=vi.fn(),take=vi.fn(()=>({attemptId:attempt,dispatchToken:token})),base=gatewayContext(request);
    for(const value of [{...base,enabled:false},{...base,verificationMode:'authenticator' as const},{...base,isCurrent:()=>false},{...base,verifyFresh:async()=>false},{...base,identity:{...base.identity,permissions:['assisted_sms.read']}}]){
      await expect(new AssistedSmsGateway(value).sendOnce(take)).rejects.toThrow();
    }
    expect(take).not.toHaveBeenCalled();expect(request).not.toHaveBeenCalled();
  });
  it('dispatches once without storing content or token, then explicitly inspects the original attempt',async()=>{
    const request=vi.fn(async(_path:string,options?:{body?:Record<string,unknown>})=>options?.body?.action==='inspect_gateway'?observation('sent',true,'observed_sent'):observation());
    const gateway=new AssistedSmsGateway(gatewayContext(request)),take=()=>({attemptId:attempt,dispatchToken:token});
    expect(await gateway.sendOnce(take)).toMatchObject({attemptId:attempt,gatewayState:'accepted',observation:null});
    expect(request).toHaveBeenNthCalledWith(1,'notification-operator',{authenticated:true,method:'POST',body:{action:'dispatch_gateway',attempt_id:attempt,dispatch_token:token}});
    await expect(gateway.sendOnce(take)).rejects.toThrow(/already attempted/);expect(request).toHaveBeenCalledTimes(1);
    expect(await gateway.inspect(attempt)).toMatchObject({gatewayState:'sent',observation:'observed_sent'});
    expect(request).toHaveBeenNthCalledWith(2,'notification-operator',{authenticated:true,method:'POST',body:{action:'inspect_gateway',attempt_id:attempt}});
    expect(JSON.stringify(sessionStorage)).not.toContain(token);expect(JSON.stringify(localStorage)).not.toContain(token);
  });
  it('does not automatically retry an unconfirmed handoff',async()=>{
    const request=vi.fn().mockRejectedValue(new Error('unavailable')),gateway=new AssistedSmsGateway(gatewayContext(request)),take=()=>({attemptId:attempt,dispatchToken:token});
    await expect(gateway.sendOnce(take)).rejects.toThrow();await expect(gateway.sendOnce(take)).rejects.toThrow(/already attempted/);expect(request).toHaveBeenCalledOnce();
  });
  it('does not take the grant when authority changes during fresh verification',async()=>{
    let complete!:(value:boolean)=>void;const wait=new Promise<boolean>(resolve=>{complete=resolve;}),request=vi.fn(),take=vi.fn(()=>({attemptId:attempt,dispatchToken:token}));
    const gateway=new AssistedSmsGateway({...gatewayContext(request),verifyFresh:()=>wait});const result=gateway.sendOnce(take);current=false;complete(true);
    await expect(result).rejects.toThrow();expect(take).not.toHaveBeenCalled();expect(request).not.toHaveBeenCalled();
  });
});

describe('first-response gateway handoff in the operator',()=>{
  it('keeps the gateway default-off before starting and requires email mode',async()=>{
    const base=fixture(),context=operatorContext(base.request),operator=new AssistedOperator({...context,allowGateway:false});await confirmed(operator);
    await expect(operator.startAndDispatchGateway()).rejects.toThrow(/gateway is unavailable/i);
    expect(base.request.mock.calls.some(([,options])=>options?.body?.action==='record_send_start')).toBe(false);
    operator.dispose();const second=new AssistedOperator({...context,gatewayVerificationMode:'authenticator'});await confirmed(second);
    await expect(second.startAndDispatchGateway()).rejects.toThrow(/gateway is unavailable/i);expect(base.request.mock.calls.some(([,options])=>options?.body?.action==='record_send_start')).toBe(false);
  });
  it('hands only the original first-response token to the server once and requires explicit outcome recording',async()=>{
    const base=fixture(),operator=new AssistedOperator(operatorContext(base.request));await confirmed(operator);
    expect(await operator.startAndDispatchGateway()).toMatchObject({permitIssued:true,tokenIssued:true,handedToGateway:true,gatewayResultUnknown:false,observation:{gatewayState:'accepted',observation:null}});
    expect(operator.view()).toMatchObject({jobId:null,destination:null,message:null,attemptId:attempt,observation:null});
    expect(base.request.mock.calls.filter(([,options])=>options?.body?.action==='dispatch_gateway')).toHaveLength(1);
    expect(base.request.mock.calls.some(([,options])=>options?.body?.action==='record_outcome')).toBe(false);
    expect(await operator.inspectGateway()).toMatchObject({attemptId:attempt,gatewayState:'sent',observation:'observed_sent'});
    expect(operator.view()).toMatchObject({attemptId:attempt,observation:'observed_sent',evidenceReferenceSha256:evidence});
    expect(base.request.mock.calls.some(([,options])=>options?.body?.action==='record_outcome')).toBe(false);expect(JSON.stringify(sessionStorage)).not.toContain(token);
  });
  it('does not dispatch when the backend records a start without a token, as in the newer checkout',async()=>{
    const base=fixture({tokenIssued:false}),operator=new AssistedOperator(operatorContext(base.request));await confirmed(operator);
    expect(await operator.startAndDispatchGateway()).toMatchObject({permitIssued:true,tokenIssued:false,handedToGateway:false,gatewayResultUnknown:false});
    expect(operator.view()).toMatchObject({attemptId:attempt,destination:null,message:null});expect(base.request.mock.calls.some(([,options])=>options?.body?.action==='dispatch_gateway')).toBe(false);
  });
  it('discards a first response token if the gateway gate closes during the start request',async()=>{
    const base=fixture(),original=base.request.getMockImplementation()!;let enabled=true;
    base.request.mockImplementation(async(path,options)=>{const value=await original(path,options);if(options?.body?.action==='record_send_start')enabled=false;return value;});
    const operator=new AssistedOperator({...operatorContext(base.request),isGatewayEnabled:()=>enabled});await confirmed(operator);
    expect(await operator.startAndDispatchGateway()).toMatchObject({permitIssued:true,tokenIssued:true,handedToGateway:false,gatewayResultUnknown:false});
    expect(operator.view()).toMatchObject({attemptId:attempt,destination:null,message:null});expect(base.request.mock.calls.some(([,options])=>options?.body?.action==='dispatch_gateway')).toBe(false);
    expect(JSON.stringify(sessionStorage)).not.toContain(token);
  });
  it('does not submit a start if the gateway gate closes while saving its original reference',async()=>{
    const base=fixture();let enabled=true;
    const storage:Storage={get length(){return sessionStorage.length;},clear:()=>sessionStorage.clear(),key:index=>sessionStorage.key(index),getItem:name=>sessionStorage.getItem(name),removeItem:name=>sessionStorage.removeItem(name),
      setItem:(name,value)=>{sessionStorage.setItem(name,value);if(value.includes('record_send_start'))enabled=false;}};
    const operator=new AssistedOperator({...operatorContext(base.request),storage,isGatewayEnabled:()=>enabled});await confirmed(operator);
    await expect(operator.startAndDispatchGateway()).rejects.toBeInstanceOf(OperatorOutcomeUnknown);
    expect(base.request.mock.calls.some(([,options])=>options?.body?.action==='record_send_start'||options?.body?.action==='dispatch_gateway')).toBe(false);
    expect(sessionStorage.getItem(PENDING_KEY)).toContain('record_send_start');expect(sessionStorage.getItem(PENDING_KEY)).not.toContain(token);
  });
  it('invalidates the one-use token before an asynchronously held adapter can take it',async()=>{
    const base=fixture();let release!:()=>void,ready!:()=>void,taken:unknown='not taken';
    const held=new Promise<void>(resolve=>{release=resolve;}),started=new Promise<void>(resolve=>{ready=resolve;});
    const gateway={matches:()=>true,sendOnce:async(take:()=>unknown)=>{ready();await held;taken=take();return {attemptId:attempt,gatewayState:'accepted',providerAccepted:true,observation:null,evidenceReferenceSha256:evidence};},inspect:async()=>({attemptId:attempt,gatewayState:'accepted',providerAccepted:true,observation:null,evidenceReferenceSha256:evidence})};
    const operator=new AssistedOperator({...operatorContext(base.request),gateway});await confirmed(operator);const result=operator.startAndDispatchGateway();await started;
    operator.invalidate();release();expect(await result).toMatchObject({tokenIssued:true,handedToGateway:false});expect(taken).toBeNull();
  });
  it('keeps a server grant out of the separate native sender payload',async()=>{
    const base=fixture(),seen:unknown[]=[],context=operatorContext(base.request),operator=new AssistedOperator({...context,sender:{sendOnce:async take=>{seen.push(take(),take());return null;}}});
    await confirmed(operator);expect(await operator.startAndSend()).toMatchObject({permitIssued:true,sentToAdapter:true});
    expect(seen).toEqual([{attemptId:attempt,destinationE164:destination,messageBody:message},null]);expect(JSON.stringify(seen)).not.toContain(token);
    expect(base.request.mock.calls.some(([,options])=>options?.body?.action==='dispatch_gateway')).toBe(false);
  });
  it('rejects a replay carrying a token and only retains the original operation reference',async()=>{
    const base=fixture({replay:true}),operator=new AssistedOperator(operatorContext(base.request));await confirmed(operator);
    let failure:OperatorOutcomeUnknown|null=null;try{await operator.startAndDispatchGateway();}catch(error){if(error instanceof OperatorOutcomeUnknown)failure=error;else throw error;}
    expect(failure).not.toBeNull();expect(base.request.mock.calls.some(([,options])=>options?.body?.action==='dispatch_gateway')).toBe(false);
    expect(sessionStorage.getItem(PENDING_KEY)).not.toContain(token);expect(await operator.checkOriginal(failure!.checkpoint)).toMatchObject({observed:true,attemptId:attempt});
  });
  it('does not reissue a lost start response or retry a failed gateway dispatch',async()=>{
    const lost=fixture({loseStart:true}),operator=new AssistedOperator(operatorContext(lost.request));await confirmed(operator);
    let failure:OperatorOutcomeUnknown|null=null;try{await operator.startAndDispatchGateway();}catch(error){if(error instanceof OperatorOutcomeUnknown)failure=error;else throw error;}
    expect(await operator.checkOriginal(failure!.checkpoint)).toMatchObject({observed:true,attemptId:attempt});
    expect(lost.request.mock.calls.some(([,options])=>options?.body?.action==='dispatch_gateway')).toBe(false);operator.dispose();
    const unavailable=fixture({dispatchFailure:true}),next=new AssistedOperator(operatorContext(unavailable.request));await confirmed(next);
    expect(await next.startAndDispatchGateway()).toMatchObject({permitIssued:true,tokenIssued:true,handedToGateway:true,gatewayResultUnknown:true,observation:null});
    await expect(next.startAndDispatchGateway()).rejects.toThrow();expect(unavailable.request.mock.calls.filter(([,options])=>options?.body?.action==='dispatch_gateway')).toHaveLength(1);
  });
});
