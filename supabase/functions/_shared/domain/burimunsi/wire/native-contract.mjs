import {profile,defs} from './burimunsi.generated.mjs';
import {ContractViolation,parseWire,validateSchema,semantics,validateQuery} from './runtime.mjs';
export {ContractViolation,parseWire};
export const CONTRACT_VERSION=profile.contractVersion;
export function contractRoute(method,path){
 for(const [verb,pattern,operation] of profile.routes){if(method!==verb)continue;const m=new RegExp(pattern).exec(path);if(m)return {operation,recordId:m[1]};}
 throw new ContractViolation('CONTRACT_OPERATION');
}
export function requestBinding(request,installationId,groupId){
 if(request.headers.get('X-BuriMunsi-Contract')!==CONTRACT_VERSION)throw new ContractViolation('CONTRACT_VERSION');
 const b={requestId:request.headers.get('X-BuriMunsi-Request'),generation:request.headers.get('X-BuriMunsi-Generation'),installationId,groupId,actorId:'not-yet-authenticated'};
 validateSchema(defs,'binding',b);return b;
}
export function validateNativeRequest(operation,value){
 validateSchema(defs,operation+'.request',value);
 if(['observation','observationRecoverHeld','observationRecoverHeldAck','observationRecoveryV2Hold','observationRecoveryV2Ack'].includes(operation)&&(!((value.sourceMode==='live'&&value.complete===true)||
   (value.sourceMode==='catch_up'&&value.complete===false&&value.inboxReceivedAt!==null))||
   new TextEncoder().encode(value.rawBody).length>3000||
   Object.hasOwn(value,'sourceKey')&&value.sourceMode!=='catch_up'))throw new ContractViolation('CONTRACT_STATE');
 if(operation==='observationReconcileBatch'&&new Set(value.items.map(item=>item.sourceKey)).size!==value.items.length)
  throw new ContractViolation('CONTRACT_DUPLICATE');
 return value;
}
export function nativeExpected(binding,route,body,originDigest,handoffFingerprint){
 return {...binding,recordId:route.recordId,memberId:body?.memberId,phone:body?.phone,
  staffId:body?.id,commandRequestId:body?.requestId,staffOperation:body?.operation,
  consentEnabled:body?.enabled,consentGeneration:body?.generation,expectedConsentGeneration:body?.expectedConsentGeneration,displayHintsVersion:body?.displayHintsVersion,
  importRows:body?.rows?.map(row=>row.row),sourceIds:body?.sourceIds,sourceKey:body?.sourceKey,
  sourceKeys:Array.isArray(body?.items)?body.items.map(item=>item.sourceKey):undefined,originDigest,handoffFingerprint};
}
export function bindNativeResponse(route,binding,body,data,originDigest,handoffFingerprint){
 // Project only the public acknowledgement fields promised by canonical bridge ports.
 const publicFields={enroll:['id','phone','groupId'],membership:['applied'],replace:['retired','handoffId','requestId','reauthenticationRequired']}[route.operation];
 if(publicFields&&data&&typeof data==='object')data=Object.fromEntries(publicFields.filter(k=>Object.hasOwn(data,k)).map(k=>[k,data[k]]));
 const value={contractVersion:CONTRACT_VERSION,ok:true,binding,data};
 validateSchema(defs,route.operation+'.response',value);
 semantics('burimunsi',route.operation,value,nativeExpected(binding,route,body,originDigest,handoffFingerprint));
 return value;
}

export function validateNativeQuery(operation,raw){
 const query=validateQuery(defs,operation,raw);
 return Object.hasOwn(query,'limit')?{...query,limit:Number(query.limit)}:query;
}
