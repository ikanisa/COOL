// This transport is deliberately limited to an owned synthetic database and
// fake project. Do not wire it into Collect's production Edge entrypoints.
import {canonical,parseCanonical,rawPublicKey,keyFingerprint,signDomain,signEnvelope,validateFresh,verifyCommand,verifyEnvelope} from './protocol.mjs';
const headers={'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff'};
const response=(body,status=200)=>new Response(canonical(body),{status,headers});
const UUID=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const eq=(a,b)=>canonical(a)===canonical(b);
async function bodyOf(request,timeoutMs){
 if(request.headers.get('content-type')!=='application/json'||!request.body)throw Error('invalid');
 const declared=request.headers.get('content-length');if(declared!==null&&(!/^[0-9]+$/.test(declared)||Number(declared)>16384))throw Error('invalid');
 const reader=request.body.getReader(),parts=[];let size=0,timer;
 try{
  const result=await Promise.race([
   (async()=>{for(;;){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>16384)throw Error('invalid');parts.push(part.value);}return true;})(),
   new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('timeout')),timeoutMs);})
  ]);
  if(!result||request.signal.aborted||(declared!==null&&Number(declared)!==size))throw Error('invalid');
  const merged=new Uint8Array(size);let offset=0;for(const part of parts){merged.set(part,offset);offset+=part.byteLength;}
  return parseCanonical(new TextDecoder('utf-8',{fatal:true}).decode(merged));
 }finally{clearTimeout(timer);try{void reader.cancel().catch(()=>{});}catch{}}
}
function receiptPayload(payload,binding){
 if(!payload||Object.keys(payload).sort().join()!=='binding,receipt_id'||!UUID.test(payload.receipt_id??'')||!eq(payload.binding,binding))throw Error('unconfirmed');
 return payload;
}
function ackPayload(payload,binding,id,consumeId){
 const expected={consume_id:consumeId,installation_sha256:binding.installation_sha256,receipt_id:id,
  target_device_key_sha256:binding.target_device_key_sha256,transition_id:binding.transition_id};
 if(!eq(payload,expected))throw Error('unconfirmed');return payload;
}
export async function createSyntheticTransport({policy,operatorPublicKey,targetPrivateKey,targetPublicKey,targetKeyId,store,authorize,clock=()=>Date.now(),adapterTimeoutMs=5000,bodyTimeoutMs=5000}={}){
 if(policy?.targetProject!=='synthetic-project-only'||Object.keys(policy??{}).sort().join()!=='operatorSha256,primaryAccountSha256,targetApiSha256,targetAuthSha256,targetGatewaySha256,targetProject'
  ||['operatorSha256','primaryAccountSha256','targetApiSha256','targetAuthSha256','targetGatewaySha256'].some(name=>!/^[a-f0-9]{64}$/.test(policy[name]??''))
  ||!Number.isSafeInteger(adapterTimeoutMs)||adapterTimeoutMs<10||adapterTimeoutMs>10000||!Number.isSafeInteger(bodyTimeoutMs)||bodyTimeoutMs<10||bodyTimeoutMs>10000||typeof authorize!=='function'
  ||typeof store?.issue!=='function'||typeof store?.consume!=='function'||typeof store?.status!=='function')throw Error('synthetic_transport_refused');
 const pinnedPolicy=Object.freeze({...policy}),issue=store.issue.bind(store),consume=store.consume.bind(store),status=store.status.bind(store);
 const bounded=async operation=>{let timer;try{return await Promise.race([Promise.resolve().then(operation),new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('timeout')),adapterTimeoutMs);})]);}finally{clearTimeout(timer);}};
 const test={proof:'commissioning-key-pair-check'};
 const probe={format:'collect.commissioning-receipt.v1',key_id:targetKeyId,payload:test,signature:await signDomain(targetPrivateKey,'collect.commissioning.target-receipt.v1',{format:'collect.commissioning-receipt.v1',key_id:targetKeyId,payload:test})};
 await verifyEnvelope(probe,targetPublicKey,targetKeyId,'receipt');
 const targetKeyFingerprint=await keyFingerprint(await rawPublicKey(targetPublicKey));
 if(targetKeyFingerprint===await keyFingerprint(await rawPublicKey(operatorPublicKey)))throw Error('synthetic_transport_refused');
 return async request=>{
  const url=new URL(request.url);
  if(request.method!=='POST'||url.origin!=='https://synthetic-only.invalid'||url.pathname!=='/commissioning/v1'||url.search!==''||url.hash!=='')return response({code:'not_found'},404);
  let command;try{command=await bodyOf(request,bodyTimeoutMs);await verifyCommand(command,pinnedPolicy,operatorPublicKey,clock());if(command.binding.target_device_key_sha256===targetKeyFingerprint)throw Error('invalid');Object.freeze(command.binding);}
  catch{return response({code:'invalid_request'},400);}
  try{
   if(await bounded(()=>authorize({action:command.action,binding:command.binding}))!==true||request.signal.aborted)return response({code:'unavailable'},503);
   if(command.action==='issue'){
    const result=await bounded(()=>issue(command.binding,async id=>{
     if(!UUID.test(id??'')||request.signal.aborted)throw Error('unconfirmed');validateFresh(command.binding,clock());
     return signEnvelope(targetPrivateKey,targetKeyId,'receipt',{binding:command.binding,receipt_id:id});
    }));
    if(result?.state!=='committed')throw Error('unconfirmed');
    receiptPayload(await verifyEnvelope(result.receipt,targetPublicKey,targetKeyId,'receipt'),command.binding);
    // A commit may have succeeded after the deadline; return an unknown
    // outcome rather than a usable-looking expired success. Status remains
    // available for authenticated readback of the committed result.
    validateFresh(command.binding,clock());
    return response({receipt:result.receipt,state:'committed'});
   }
   if(command.action==='status'){
    const result=await bounded(()=>status(command.binding));
    if(result?.state!=='found')throw Error('unconfirmed');
    const prior=receiptPayload(await verifyEnvelope(result.receipt,targetPublicKey,targetKeyId,'receipt'),command.binding);
    const output={receipt:result.receipt,state:'found'};
    if(result.ack){const ack=await verifyEnvelope(result.ack,targetPublicKey,targetKeyId,'ack');ackPayload(ack,command.binding,prior.receipt_id,ack.consume_id);output.ack=result.ack;}
    return response(output);
   }
   const original=receiptPayload(await verifyEnvelope(command.receipt,targetPublicKey,targetKeyId,'receipt'),command.binding);
   const expected={consume_id:command.consume_id,installation_sha256:command.binding.installation_sha256,receipt_id:original.receipt_id,
    target_device_key_sha256:command.binding.target_device_key_sha256,transition_id:command.binding.transition_id};
   const result=await bounded(()=>consume(command.binding,original.receipt_id,command.consume_id,async()=>{
    if(request.signal.aborted)throw Error('unconfirmed');validateFresh(command.binding,clock());return signEnvelope(targetPrivateKey,targetKeyId,'ack',expected);
   }));
   if(result?.state!=='committed')throw Error('unconfirmed');ackPayload(await verifyEnvelope(result.ack,targetPublicKey,targetKeyId,'ack'),command.binding,original.receipt_id,command.consume_id);
   validateFresh(command.binding,clock());
   return response({ack:result.ack,state:'committed'});
  }catch{return response({code:'unconfirmed'},503);}
 };
}
// There is no production authority adapter yet. Expose an explicitly closed
// function rather than accepting caller-supplied digests as proof.
export function closedProductionTransport(){return async()=>response({code:'commissioning_unavailable'},503);}
