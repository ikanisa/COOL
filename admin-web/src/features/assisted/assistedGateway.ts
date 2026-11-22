import type {AdminRequest, JsonObject} from '../../api/client';
import type {PendingIdentity} from '../core/pendingAttempt';
import type {AssistedObservation} from './assistedContracts';

const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i, HASH=/^[a-f0-9]{64}$/;
const PENDING=['accepted','assigned','phone_accepted','queued','handoff_started'] as const;
const SENT=['sent','delivered','delivery_unconfirmed'] as const;
const UNCERTAIN=['failed','partial','outcome_unknown','cancelled','expired'] as const;
export interface AssistedGatewayPayload {attemptId:string; dispatchToken:string;}
export interface AssistedGatewayObservation {attemptId:string; gatewayState:string; providerAccepted:boolean; observation:AssistedObservation|null; evidenceReferenceSha256:string;}
export interface AssistedGateway {
  matches:(identity:PendingIdentity&{principalId:string})=>boolean;
  sendOnce:(take:()=>AssistedGatewayPayload|null)=>Promise<AssistedGatewayObservation>;
  inspect:(attemptId:string)=>Promise<AssistedGatewayObservation>;
}
export interface AssistedGatewayContext {
  request:AdminRequest; identity:PendingIdentity&{principalId:string}; verificationMode:'email'|'authenticator';
  enabled?:boolean; isEnabled?:()=>boolean; verifyFresh:()=>Promise<boolean>; isCurrent:()=>boolean;
}
function fail():never {throw new Error('The original gateway observation could not be verified.');}
function object(value:unknown):value is JsonObject{return value!==null&&typeof value==='object'&&!Array.isArray(value);}
function exact(value:JsonObject,keys:string[]){return Object.keys(value).length===keys.length&&keys.every(key=>Object.hasOwn(value,key));}
function sameIdentity(left:PendingIdentity&{principalId:string},right:PendingIdentity&{principalId:string}){
  return left.id.toLowerCase()===right.id.toLowerCase()&&left.sessionId.toLowerCase()===right.sessionId.toLowerCase()&&left.principalId.toLowerCase()===right.principalId.toLowerCase()&&
    left.email===right.email&&left.role===right.role&&left.expiresAt===right.expiresAt&&JSON.stringify([...new Set(left.permissions)].sort())===JSON.stringify([...new Set(right.permissions)].sort());
}
export function parseGatewayObservation(value:unknown,attemptId:string):AssistedGatewayObservation{
  if(!UUID.test(attemptId)||!object(value)||!exact(value,['ok','result'])||value.ok!==true||!object(value.result))fail();
  const data=value.result,keys=['contract_version','scope','delivery_confirmed','provider_confirmation','settlement_status','may_send','attempt_id','gateway_state','provider_accepted','observation','evidence_reference_sha256'];
  if(!exact(data,keys)||data.contract_version!==1||data.scope!=='assisted_sms_gateway_observation'||data.delivery_confirmed!==false||data.provider_confirmation!==false||data.settlement_status!=='not_asserted'||data.may_send!==false||
      typeof data.attempt_id!=='string'||data.attempt_id.toLowerCase()!==attemptId.toLowerCase()||typeof data.gateway_state!=='string'||typeof data.provider_accepted!=='boolean'||
      typeof data.evidence_reference_sha256!=='string'||!HASH.test(data.evidence_reference_sha256))fail();
  const state=data.gateway_state,observation=data.observation;
  if(data.provider_accepted===false ? state!=='unknown'||observation!==null :
      !((PENDING as readonly string[]).includes(state)&&observation===null||(SENT as readonly string[]).includes(state)&&observation==='observed_sent'||(UNCERTAIN as readonly string[]).includes(state)&&observation==='uncertain'))fail();
  return {attemptId:attemptId.toLowerCase(),gatewayState:state,providerAccepted:data.provider_accepted,observation:observation as AssistedObservation|null,evidenceReferenceSha256:data.evidence_reference_sha256};
}
export function validateGatewayObservation(value:unknown,attemptId:string):AssistedGatewayObservation{
  if(!object(value)||!exact(value,['attemptId','gatewayState','providerAccepted','observation','evidenceReferenceSha256']))fail();
  return parseGatewayObservation({ok:true,result:{contract_version:1,scope:'assisted_sms_gateway_observation',delivery_confirmed:false,provider_confirmation:false,
    settlement_status:'not_asserted',may_send:false,attempt_id:value.attemptId,gateway_state:value.gatewayState,provider_accepted:value.providerAccepted,
    observation:value.observation,evidence_reference_sha256:value.evidenceReferenceSha256}},attemptId);
}

/** Supabase server handoff; callers must explicitly qualify and enable it. */
export class AssistedSmsGateway implements AssistedGateway {
  private readonly dispatched=new Set<string>();
  constructor(private readonly context:AssistedGatewayContext){}
  matches(identity:PendingIdentity&{principalId:string}){return sameIdentity(this.context.identity,identity);}
  private guard(){
    const actor=this.context.identity,expires=Date.parse(actor.expiresAt);
    if(this.context.enabled!==true||this.context.isEnabled&&!this.context.isEnabled()||this.context.verificationMode!=='email'||!this.context.isCurrent()||
       !UUID.test(actor.id)||!UUID.test(actor.sessionId)||!UUID.test(actor.principalId)||!['assisted_sms.read','assisted_sms.manage'].every(permission=>actor.permissions.includes(permission))||!Number.isFinite(expires)||expires<=Date.now())
      throw new Error('Reopen the original gateway review with current email verification.');
  }
  private async authorize(){this.guard();if(!await this.context.verifyFresh())throw new Error('Verify your email before using the gateway.');this.guard();}
  async sendOnce(take:()=>AssistedGatewayPayload|null):Promise<AssistedGatewayObservation>{
    await this.authorize();const payload=take();this.guard();
    if(!payload||!UUID.test(payload.attemptId)||!HASH.test(payload.dispatchToken))throw new Error('The original gateway sending grant is unavailable.');
    const id=payload.attemptId.toLowerCase();if(this.dispatched.has(id))throw new Error('The gateway handoff was already attempted. Check the original attempt.');
    this.dispatched.add(id);
    // No retry, token persistence, raw message, or provider credential in the client.
    let result:JsonObject;
    try{result=await this.context.request('notification-operator',{authenticated:true,method:'POST',body:{action:'dispatch_gateway',attempt_id:id,dispatch_token:payload.dispatchToken}});}
    catch{throw new Error('The gateway result is unconfirmed. Check the original attempt.');}
    this.guard();return parseGatewayObservation(result,id);
  }
  async inspect(attemptId:string):Promise<AssistedGatewayObservation>{
    await this.authorize();if(!UUID.test(attemptId))fail();const id=attemptId.toLowerCase();
    // This is a server-side inspection which may update gateway state; it is
    // never an automatic resend or a confirmation of delivery.
    let result:JsonObject;
    try{result=await this.context.request('notification-operator',{authenticated:true,method:'POST',body:{action:'inspect_gateway',attempt_id:id}});}
    catch{throw new Error('The gateway status is unconfirmed. Check the original attempt.');}
    this.guard();return parseGatewayObservation(result,id);
  }
}
