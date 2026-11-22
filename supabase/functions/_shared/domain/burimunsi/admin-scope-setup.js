import {ApiError} from '../core.js';
import {encrypt,decrypt} from '../encryption.js';
import {canonicalJson,exactKeys,requireId,requireRequestId,sha256} from './values.js';
import {requirePort,requireThat} from './errors.js';

const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const changed=()=>fail(409,'burimunsi_scope_changed','The group, receiving account or approved device changed. Refresh before continuing.');
const validId=value=>typeof value==='string'&&value.trim()===value&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(value);
const positive=value=>Number.isSafeInteger(value)&&value>0;
const SQL={directory:'SELECT private.burimunsi_setup_directory(?,?,?,?,?) AS result',
 // These values are already JSON text. Tell postgres.js to bind them as text
 // before casting to jsonb; binding directly as jsonb would encode them again.
 apply:'SELECT private.burimunsi_setup_apply(?,?,?,?,?::text::jsonb,?,?::text::jsonb) AS result',
 lookup:'SELECT private.burimunsi_setup_lookup(?,?,?,?,?,?::uuid,?) AS result',
 cancel:'SELECT private.burimunsi_setup_cancel(?,?,?,?,?,?::uuid) AS result'};
const purpose=binding=>'burimunsi-scope-pair-v1:'+canonicalJson(binding);
function receipt(value,group,request){
 if(value?.operation==='cancelled'){
  exactKeys(value,['contractVersion','collectionId','requestId','operation','applied']);
  if(value.contractVersion!==1||value.collectionId!==group||value.requestId!==request||value.applied!==false)throw Error('Invalid setup cancellation');
  return value;
 }
 const base=['contractVersion','requestId','collectionId','operation','receivingAccountId','scopeVersion','enabled','bindingId'];
 const extra=['pairingId','bindingVersion','installationId','custodianAccountId','grantId','grantVersion','subscriptionId','deliveryExpiresAt'];
 const replacement=['handoffId','expectedBindingId','expectedBindingVersion','expectedReceiverKeyId','retirementRequired'];
 if(!value||!['prepare','activate','prepare_replacement','finalize_replacement'].includes(value.operation))throw Error('Invalid scope receipt');
 exactKeys(value,value.operation==='prepare_replacement'?[...base,...extra,...replacement]:value.operation==='activate'?[...base,...extra]:
  value.operation==='finalize_replacement'?[...base,'bindingVersion','handoffId','retirementMethod','reauthenticationRequired']:base);
 if(value.contractVersion!==1||value.collectionId!==group||value.requestId!==request||!validId(value.receivingAccountId)||
  !positive(value.scopeVersion)||typeof value.enabled!=='boolean'||!(value.bindingId===null||validId(value.bindingId)))throw Error('Invalid scope receipt');
 if(['activate','prepare_replacement'].includes(value.operation)&&(!value.enabled||!positive(value.bindingVersion)||!positive(value.grantVersion)||!positive(value.deliveryExpiresAt)||
  !Number.isSafeInteger(value.subscriptionId)||value.subscriptionId<0||value.subscriptionId>=2147483647||
  ['pairingId','installationId','custodianAccountId','grantId'].some(k=>requireRequestId(value[k])!==value[k])))throw Error('Invalid activation receipt');
 if(value.operation==='prepare_replacement'&&(value.handoffId!==request||!validId(value.expectedBindingId)||!positive(value.expectedBindingVersion)||
  !validId(value.expectedReceiverKeyId)||value.retirementRequired!==true))throw Error('Invalid replacement receipt');
 if(value.operation==='finalize_replacement'&&(!value.enabled||!positive(value.bindingVersion)||requireRequestId(value.handoffId)!==value.handoffId||
  value.retirementMethod!=='owner_lost'||value.reauthenticationRequired!==true))throw Error('Invalid finalization receipt');
 return value;
}
export function scopeCommand(input){
 const base=['operation','requestId','collectionId','expectedScopeVersion','receivingAccountId','reason'];
 const extra=['installationId','grantId','custodianAccountId','expectedGrantVersion','subscriptionId'];
 const replacement=['expectedBindingId','expectedBindingVersion','expectedReceiverKeyId'];
 if(!input||!['prepare','activate','prepare_replacement','finalize_replacement'].includes(input.operation))fail(400,'invalid_setup','Choose the setup action.');
 try{exactKeys(input,input.operation==='prepare_replacement'?[...base,...extra,...replacement]:input.operation==='activate'?[...base,...extra]:
    input.operation==='finalize_replacement'?[...base,'handoffId']:base);requireRequestId(input.requestId);requireId(input.collectionId);requireId(input.receivingAccountId);
  if(!validId(input.collectionId)||!Number.isSafeInteger(input.expectedScopeVersion)||input.expectedScopeVersion<0||input.expectedScopeVersion>=Number.MAX_SAFE_INTEGER||
   typeof input.reason!=='string'||input.reason.trim()!==input.reason||input.reason.length<8||input.reason.length>500||/[\x00-\x1f\x7f-\x9f]/.test(input.reason)||/[a-f0-9]{64}/i.test(input.reason))throw Error();
  if(['activate','prepare_replacement'].includes(input.operation)&&(!positive(input.expectedGrantVersion)||!Number.isSafeInteger(input.subscriptionId)||input.subscriptionId<0||input.subscriptionId>=2147483647||
   extra.slice(0,3).some(k=>requireRequestId(input[k])!==input[k])))throw Error();
  if(input.operation==='prepare_replacement'&&(!validId(input.expectedBindingId)||!positive(input.expectedBindingVersion)||!validId(input.expectedReceiverKeyId)))throw Error();
  if(input.operation==='finalize_replacement')requireRequestId(input.handoffId);
 }catch{fail(400,'invalid_setup','Check the exact setup fields and review reason.');}
 return Object.freeze({...input});
}

/** Existing shared owner authority, DB/fence and AES. No separate auth, ledger,
 * pool or credential generator can be injected by a request. */
export class AdminScopeSetup{
 constructor({env,actorArgs,actorId,sessionId}){
  requirePort(env?.DB,['prepare','batch']);requirePort(env.DB.applicationWork,['assert']);
  requireThat(Array.isArray(actorArgs)&&actorArgs.length===4,'collect_adapter_required',503);
  requireId(actorId);requireRequestId(sessionId);
  Object.assign(this,{env,db:env.DB,work:env.DB.applicationWork,actorArgs:[...actorArgs],actorId,sessionId});
 }
 async owned(){requireThat(this.env.DB===this.db&&this.db.applicationWork===this.work,'request_not_admitted',503);await this.work.assert();
  requireThat(this.env.DB===this.db&&this.db.applicationWork===this.work,'request_not_admitted',503);}
 async invoke(name,args){
  requireThat(Object.hasOwn(SQL,name),'collect_adapter_required',503);await this.owned();
  const out=await this.db.batch([this.db.prepare(SQL[name]).bind(...this.actorArgs,...args)]);await this.owned();
  if(out?.length!==1||out[0]?.success!==true||out[0]?.results?.length!==1)throw Error('Scope setup unavailable');
  return out[0].results[0].result;
 }
 async directory(collectionId=null){
  if(collectionId!==null)requireId(collectionId);
  const value=await this.invoke('directory',[collectionId]);
  exactKeys(value,['contractVersion','collections','accounts','scopes','installations']);
  if(value.contractVersion!==1||['collections','accounts','scopes','installations'].some(k=>!Array.isArray(value[k])||value[k].length>500))throw Error('Invalid setup directory');
  for(const row of value.collections)if(!validId(row.id)||typeof row.title!=='string'||!positive(row.version))throw Error('Invalid setup group');
  for(const row of value.accounts)if(!validId(row.id)||!['mtn_momo','airtel_money'].includes(row.provider)||typeof row.publicCode!=='string'||typeof row.recipientName!=='string')throw Error('Invalid receiving account');
  for(const row of value.scopes){
   if(!validId(row.collectionId)||!validId(row.receivingAccountId)||!positive(row.version)||typeof row.enabled!=='boolean'||typeof row.paired!=='boolean'||
    !(row.receiverKeyId===null||validId(row.receiverKeyId))||!(row.receiverInstallationId===null||requireRequestId(row.receiverInstallationId)===row.receiverInstallationId))throw Error('Invalid setup scope');
   if(row.pendingReplacement!==null){
    const pending=row.pendingReplacement;
    exactKeys(pending,['handoffId','targetInstallationId','targetGrantId','targetGrantVersion','targetCustodianAccountId','expectedScopeVersion',
     'expectedBindingId','expectedBindingVersion','expectedReceiverKeyId','expiresAt','phase','subscriptionId']);
    if(['handoffId','targetInstallationId','targetGrantId','targetCustodianAccountId'].some(k=>requireRequestId(pending[k])!==pending[k])||
     !positive(pending.targetGrantVersion)||!positive(pending.expectedScopeVersion)||!validId(pending.expectedBindingId)||!positive(pending.expectedBindingVersion)||
     !validId(pending.expectedReceiverKeyId)||!positive(pending.expiresAt)||!['prepared','retired'].includes(pending.phase)||
     !Number.isSafeInteger(pending.subscriptionId)||pending.subscriptionId<0||pending.subscriptionId>=2147483647)throw Error('Invalid pending replacement');
   }
  }
  for(const row of value.installations)if(['grantId','installationId','custodianAccountId'].some(k=>requireRequestId(row[k])!==row[k])||!positive(row.grantVersion)||typeof row.custodianName!=='string'||typeof row.custodyAssigned!=='boolean')throw Error('Invalid receiving installation');
  return value;
 }
 async rawLookup(collectionId,requestId,delivery=false){
  requireId(collectionId);requireRequestId(requestId);
  const value=await this.invoke('lookup',[collectionId,requestId,delivery]);
  if(value?.contractVersion!==1||value.collectionId!==collectionId||value.requestId!==requestId||typeof value.found!=='boolean')throw Error('Invalid setup outcome');
  if(value.found){receipt(value.receipt,collectionId,requestId);if(!/^[a-f0-9]{64}$/.test(value.fingerprint??''))throw Error('Invalid setup fingerprint');}
  return value;
 }
 async lookup(collectionId,requestId){
  const value=await this.rawLookup(collectionId,requestId);
  return {contractVersion:1,collectionId,requestId,found:value.found,...(value.found?{receipt:value.receipt}:{})};
 }
 async apply(input){
  const command=scopeCommand(input),fingerprint=await sha256(canonicalJson(command));
  const prior=await this.rawLookup(command.collectionId,command.requestId);
  if(prior.found){if(prior.receipt.operation==='cancelled')fail(409,'burimunsi_setup_cancelled','The original request was cancelled before application.');
   if(prior.fingerprint!==fingerprint)changed();return prior.receipt;}
  let delivery=null;
  if(['activate','prepare_replacement'].includes(command.operation)){
   const directory=await this.directory(command.collectionId),scope=directory.scopes.find(s=>s.collectionId===command.collectionId);
   if(!scope||scope.version!==command.expectedScopeVersion||scope.receivingAccountId!==command.receivingAccountId)changed();
   const replacement=command.operation==='prepare_replacement';
   // paired reports current capture authority, not whether this scope has an
   // old receiver. A revoked old phone still requires the exact historical
   // source tuple and explicit Owner-lost finalization, never initial activate.
   if(replacement?(scope.enabled!==true||scope.bindingId!==command.expectedBindingId||scope.bindingVersion!==command.expectedBindingVersion||
      scope.receiverKeyId!==command.expectedReceiverKeyId||typeof scope.receiverInstallationId!=='string'||
      scope.receiverInstallationId===command.installationId):scope.paired)changed();
   const bindingId=replacement?crypto.randomUUID():(scope.bindingId??crypto.randomUUID()),pairingId=crypto.randomUUID();
   const binding={profileSha:this.env.COLLECT_DEPLOYMENT_PROFILE_SHA256,actorId:this.actorId,sessionId:this.sessionId,
    collectionId:command.collectionId,requestId:command.requestId,receivingAccountId:command.receivingAccountId,
    expectedScopeVersion:command.expectedScopeVersion,bindingId,pairingId,installationId:command.installationId,
    custodianAccountId:command.custodianAccountId,grantId:command.grantId,grantVersion:command.expectedGrantVersion,subscriptionId:command.subscriptionId,
    ...(replacement?{expectedBindingId:command.expectedBindingId,expectedBindingVersion:command.expectedBindingVersion,expectedReceiverKeyId:command.expectedReceiverKeyId}:{})};
   if(!/^[a-f0-9]{64}$/.test(binding.profileSha??''))throw Error('Deployment profile unavailable');
   const code=Array.from(crypto.getRandomValues(new Uint8Array(32)),b=>b.toString(16).padStart(2,'0')).join('');
   delivery={bindingId,pairingId,codeHash:await sha256(code),binding,
    ciphertext:await encrypt(this.env,new TextEncoder().encode(code),purpose(binding))};
  }
  const value=await this.invoke('apply',[JSON.stringify(command),fingerprint,delivery===null?null:JSON.stringify(delivery)]);
  receipt(value,command.collectionId,command.requestId);
  if(value.operation!==command.operation||value.receivingAccountId!==command.receivingAccountId||
   value.scopeVersion!==command.expectedScopeVersion+(command.operation==='prepare_replacement'?0:1)||
   command.operation==='finalize_replacement'&&value.handoffId!==command.handoffId)changed();
  return value;
 }
 async delivery(collectionId,requestId){
  const value=await this.rawLookup(collectionId,requestId,true),r=value.receipt,b=value.binding;
  const replacement=r?.operation==='prepare_replacement';
  if(!value.found||!['activate','prepare_replacement'].includes(r.operation)||r.deliveryExpiresAt<=Date.now()||typeof value.ciphertext!=='string'||
   b?.profileSha!==this.env.COLLECT_DEPLOYMENT_PROFILE_SHA256||b.actorId!==this.actorId||b.sessionId!==this.sessionId||
   b.collectionId!==collectionId||b.requestId!==requestId||b.bindingId!==r.bindingId||b.pairingId!==r.pairingId||
   b.installationId!==r.installationId||b.custodianAccountId!==r.custodianAccountId||b.grantId!==r.grantId||b.grantVersion!==r.grantVersion||
   b.subscriptionId!==r.subscriptionId||b.receivingAccountId!==r.receivingAccountId||b.expectedScopeVersion+(replacement?0:1)!==r.scopeVersion||
   replacement&&(b.expectedBindingId!==r.expectedBindingId||b.expectedBindingVersion!==r.expectedBindingVersion||b.expectedReceiverKeyId!==r.expectedReceiverKeyId||
    !['prepared','retired'].includes(value.phase)))throw Error('Invalid setup delivery');
  const code=new TextDecoder('utf-8',{fatal:true}).decode(await decrypt(this.env,value.ciphertext,purpose(b)));
  if(code.length!==64||!/^[a-f0-9]{64}$/.test(code)||await sha256(code)!==value.codeHash)throw Error('Invalid pairing challenge');
  const current=await this.rawLookup(collectionId,requestId,true);
  if(canonicalJson(current)!==canonicalJson(value))changed();
  await this.owned();return {contractVersion:1,collectionId,requestId,bindingId:r.bindingId,installationId:r.installationId,
   subscriptionId:r.subscriptionId,pairingCode:code,expiresAt:r.deliveryExpiresAt,
   ...(replacement?{handoffId:r.handoffId,retirementRequired:value.phase==='prepared',phase:value.phase}:{})};
 }
 async cancel(collectionId,requestId){
  requireId(collectionId);requireRequestId(requestId);
  return receipt(await this.invoke('cancel',[collectionId,requestId]),collectionId,requestId);
 }
}
