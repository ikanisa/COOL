// TEST ONLY. Real setup service/AES with explicit SQL/fence/owner-policy doubles.
// No provider, real identity, database, phone or production secret is used.
import {AdminScopeSetup} from '../../domain/burimunsi/admin-scope-setup.js';
import {sha256,canonicalJson} from '../../domain/burimunsi/values.js';
export const SETUP={actor:'fd100000-0000-4000-8000-000000000001',session:'fd200000-0000-4000-8000-000000000001',
 group:'buri-qualification-group',wallet:'fd300000-0000-4000-8000-000000000001',installation:'fd400000-0000-4000-8000-000000000001',
 grant:'fd400000-0000-4000-8000-000000000002',custodian:'fd500000-0000-4000-8000-000000000001',
 prepare:'fd600000-0000-4000-8000-000000000001',activate:'fd600000-0000-4000-8000-000000000002'};
export function setupFixture(){
 const state={scope:{collectionId:SETUP.group,receivingAccountId:SETUP.wallet,version:1,enabled:false,bindingId:null,bindingVersion:1,paired:false,receiverKeyId:null,receiverInstallationId:null,pendingReplacement:null},
  commands:new Map(),calls:[],unknown:false,denyDelivery:false,afterLookup:null,revoked:false};
 const work={assert:async()=>{if(state.revoked)throw Error('work revoked');}};
 const db={applicationWork:work,prepare:sql=>({bind:(...values)=>({sql,values})}),batch:async([statement])=>{
  state.calls.push(statement);const a=statement.values;let result;
  if(statement.sql.includes('burimunsi_setup_directory'))result={contractVersion:1,
   collections:[{id:SETUP.group,title:'QUALIFICATION GROUP',receiverNetwork:'mtn_momo',receiverNumber:'00000',version:1}],
   accounts:[{id:SETUP.wallet,provider:'mtn_momo',publicCode:'00000',recipientName:'QUALIFICATION RECEIVER',profileStatus:'unverified',profileVersion:null}],
   scopes:state.scope?[{...state.scope}]:[],installations:[{grantId:SETUP.grant,grantVersion:1,installationId:SETUP.installation,custodianAccountId:SETUP.custodian,custodianName:'QUALIFICATION OWNER',custodyAssigned:false}]};
  else if(statement.sql.includes('burimunsi_setup_lookup')){
   const stored=state.commands.get(a[5]);result={contractVersion:1,collectionId:a[4],requestId:a[5],found:!!stored};
   if(stored)result={...result,receipt:stored.receipt,fingerprint:stored.fingerprint,
    ...(a[6]&&stored.delivery?{ciphertext:stored.delivery.ciphertext,binding:stored.delivery.binding,codeHash:stored.delivery.codeHash,
     ...(stored.receipt.operation==='prepare_replacement'?{phase:stored.phase??'prepared'}:{})}:{})};
   if(a[6]&&state.denyDelivery)throw Error('burimunsi_setup_delivery_expired');
   await state.afterLookup?.(a[6],result);
  }else if(statement.sql.includes('burimunsi_setup_cancel')){
   const prior=state.commands.get(a[5]);
   if(prior)result=prior.receipt;
   else {
    result={contractVersion:1,collectionId:a[4],requestId:a[5],operation:'cancelled',applied:false};
    state.commands.set(a[5],{receipt:result,fingerprint:await sha256(canonicalJson(result)),delivery:null});
   }
   if(state.unknown)throw Error('PRIVATE lost COMMIT');
  }else if(statement.sql.includes('burimunsi_setup_apply')){
   const c=JSON.parse(a[4]),delivery=a[6]===null?null:JSON.parse(a[6]);
   if(state.commands.has(c.requestId))throw Error('burimunsi_setup_request_conflict');
   const retiring=c.operation==='prepare_replacement',finalizing=c.operation==='finalize_replacement';
   const original=finalizing?state.commands.get(c.handoffId):null;
   const receipt={contractVersion:1,requestId:c.requestId,collectionId:c.collectionId,operation:c.operation,receivingAccountId:c.receivingAccountId,
    scopeVersion:c.expectedScopeVersion+(retiring?0:1),enabled:c.operation!=='prepare',bindingId:finalizing?original.delivery.bindingId:(delivery?.bindingId??null),
    ...(delivery?{pairingId:delivery.pairingId,bindingVersion:1,installationId:c.installationId,custodianAccountId:c.custodianAccountId,
     grantId:c.grantId,grantVersion:c.expectedGrantVersion,subscriptionId:c.subscriptionId,deliveryExpiresAt:Date.now()+600000}:{}),
    ...(retiring?{handoffId:c.requestId,expectedBindingId:c.expectedBindingId,expectedBindingVersion:c.expectedBindingVersion,
      expectedReceiverKeyId:c.expectedReceiverKeyId,retirementRequired:true}:{}),
    ...(finalizing?{bindingVersion:1,handoffId:c.handoffId,retirementMethod:'owner_lost',reauthenticationRequired:true}:{})};
   state.commands.set(c.requestId,{command:c,receipt,fingerprint:a[5],delivery});
   if(!retiring)state.scope={...state.scope,version:receipt.scopeVersion,enabled:receipt.enabled,bindingId:receipt.bindingId};
   if(finalizing)original.phase='retired';result=receipt;
   if(state.unknown)throw Error('PRIVATE lost COMMIT');
  }else throw Error('Unexpected setup SQL');
  return [{success:true,results:[{result}],meta:{changes:1}}];
 }};
 const env={DB:db,DATA_KEY_ID:'qualification-only',DATA_ENCRYPTION_KEY:Buffer.alloc(32,79).toString('base64'),COLLECT_DEPLOYMENT_PROFILE_SHA256:'a'.repeat(64)};
 const service=new AdminScopeSetup({env,actorArgs:['owner','a'.repeat(64),'https://qualification.invalid','public-session'],actorId:SETUP.actor,sessionId:SETUP.session});
 const prepare={operation:'prepare',requestId:SETUP.prepare,collectionId:SETUP.group,receivingAccountId:SETUP.wallet,expectedScopeVersion:1,reason:'Qualification setup only'};
 const activate={...prepare,operation:'activate',requestId:SETUP.activate,expectedScopeVersion:1,installationId:SETUP.installation,
  grantId:SETUP.grant,custodianAccountId:SETUP.custodian,expectedGrantVersion:1,subscriptionId:7};
 return {state,db,env,service,prepare,activate};
}
