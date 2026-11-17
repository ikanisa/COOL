import {ApiError,uuid,digest} from '../core.js';
import {encrypt,decrypt} from '../encryption.js';
import {PostgresNativeAuthority} from './postgres-authority.js';
import {canonicalJson,requirePin,normalizePhone} from './values.js';
import {CAPABILITIES} from './policy.js';
import {newBearer,equalSecret} from './pin.js';
import {nativePinHasher} from './native-secrets.js';

const fail=(status,code,message)=>{throw new ApiError(status,code,message);};
const invalid=()=>fail(400,'invalid_provisioning','Check the exact approved account, versions and installation.');
const positive=v=>Number.isSafeInteger(v)&&v>0;
const version=v=>Number.isSafeInteger(v)&&v>=0&&v<Number.MAX_SAFE_INTEGER;
const id=v=>typeof v==='string'&&uuid(v)===v;
const exact=(v,keys)=>v&&Object.getPrototypeOf(v)===Object.prototype&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
const COMMON=['requestId','collectionId','scopeVersion','principalId','approvalVersion','expectedAccountVersion','reason','operation'];
export const PROVISIONING_DELIVERY_TTL_MS=15*60*1000;

export function provisioningCommand(input,groupId) {
  const fields=input?.operation==='set_pin'?['pin']:
    ['grant_installation','revoke_installation'].includes(input?.operation)?['accountId','grantId','installationId','profile','expectedGrantVersion']:null;
  if(!fields||!exact(input,[...COMMON,...fields])||!id(input.requestId)||!id(input.principalId)||
    !positive(input.scopeVersion)||!positive(input.approvalVersion)||!version(input.expectedAccountVersion)||
    typeof input.reason!=='string'||input.reason.trim()!==input.reason||input.reason.length<8||input.reason.length>300||
    /[\x00-\x1f\x7f]/.test(input.reason)||/[a-f0-9]{64}/i.test(input.reason))invalid();
  if(input.collectionId!==groupId)fail(409,'burimunsi_scope_changed','The BuriMunsi group changed. Refresh before continuing.');
  if(input.operation==='set_pin'){
    try{requirePin(input.pin);}catch{invalid();}
    if(input.reason.includes(input.pin))invalid();
  } else if(!id(input.accountId)||!positive(input.expectedAccountVersion)||!id(input.installationId)||
    !['staff','internal_receiver'].includes(input.profile)||!version(input.expectedGrantVersion)||
    !(input.expectedGrantVersion===0&&input.grantId===null||input.expectedGrantVersion>0&&id(input.grantId))||
    input.operation==='revoke_installation'&&input.expectedGrantVersion===0)invalid();
  return {...input};
}

export function checkProvisioningReceipt(value,groupId,requestId) {
  if(value?.operation==='cancelled'){
    if(!exact(value,['contractVersion','requestId','collectionId','operation','applied'])||value.contractVersion!==1||
      value.requestId!==requestId||value.collectionId!==groupId||value.applied!==false)throw Error('Invalid provisioning cancellation');
    return value;
  }
  const common=['contractVersion','requestId','collectionId','operation','principalId','accountId','accountVersion','credentialVersion','approvalVersion','scopeVersion','applied'];
  const grant=value?.operation!=='set_pin';
  if(!exact(value,[...common,...(grant?['grantId','installationId','profile','grantVersion','active','deliveryExpiresAt']:[])])||
    value.contractVersion!==1||value.requestId!==requestId||value.collectionId!==groupId||
    !['set_pin','grant_installation','revoke_installation'].includes(value.operation)||value.applied!==true||
    !id(value.principalId)||!id(value.accountId)||!positive(value.accountVersion)||!positive(value.credentialVersion)||
    !positive(value.approvalVersion)||!positive(value.scopeVersion)||grant&&(!id(value.grantId)||!id(value.installationId)||
    !['staff','internal_receiver'].includes(value.profile)||!positive(value.grantVersion)||typeof value.active!=='boolean'||
    value.active!==(value.operation==='grant_installation')||!(value.operation==='grant_installation'?
      positive(value.deliveryExpiresAt):value.deliveryExpiresAt===null)))throw Error('Invalid BuriMunsi provisioning receipt');
  return value;
}

const custodyContext=(profileSha,actorId,sessionId,receipt)=>'burimunsi-native-delivery-v1:'+canonicalJson([
  profileSha,actorId,sessionId,receipt.collectionId,receipt.requestId,receipt.accountId,
  receipt.grantId,receipt.installationId,receipt.profile,receipt.grantVersion,receipt.accountVersion,receipt.approvalVersion,receipt.scopeVersion,
]);

/** This adapter has no auth, ledger, pool or transaction of its own. Every SQL
 * helper rechecks the current owner/BFF/fresh-email tuple under Collect's lock.
 * Until the reviewed SQL proposal is installed the route fails closed. */
export class AdminNativeProvisioning extends PostgresNativeAuthority {
  constructor({env,groupId,actorArgs,actorId,sessionId,profileSha}) {
    super({db:env.DB,groupId});
    if(!Array.isArray(actorArgs)||actorArgs.length!==4||!id(actorId)||!id(sessionId)||
      !/^[a-f0-9]{64}$/.test(profileSha??''))throw Error('Invalid provisioning authority');
    Object.assign(this,{env,actorArgs:[...actorArgs],actorId,sessionId,profileSha});
  }
  async invoke(name,args) {
    if(!['directory','lookup','apply','delivery','cancel'].includes(name))throw Error('Invalid provisioning command');
    // apply's command is already JSON text; infer text at the driver boundary so
    // postgres.js does not serialize it a second time as a JSON string value.
    const parameters=args.map((_,i)=>',$'+(i+6)+(name==='apply'&&i===0?'::text::jsonb':''));
    return this.write(async sql=>(await sql.unsafe(`SELECT private.burimunsi_provisioning_${name}($1,$2,$3,$4,$5${parameters.join('')}) AS result`,
      [...this.actorArgs,this.groupId,...args]))[0]?.result);
  }
  async directory() {
    const value=await this.invoke('directory',[]);
    if(!exact(value,['contractVersion','collectionId','configured','scopeEnabled','scopeVersion','accounts','grants'])||value.contractVersion!==1||value.collectionId!==this.groupId||typeof value.configured!=='boolean'||
      typeof value.scopeEnabled!=='boolean'||!(value.scopeVersion===null||positive(value.scopeVersion))||
      !Array.isArray(value.accounts)||!Array.isArray(value.grants)||value.accounts.length>500||value.grants.length>500)
      throw Error('Invalid provisioning directory');
    for(const a of value.accounts)if(!exact(a,['principalId','accountId','phone','name','role','capabilities','approvalVersion','approved','version','credentialVersion','active','removed'])||
      !id(a.principalId)||!(a.accountId===null||id(a.accountId))||normalizePhone(a.phone)!==a.phone||
      typeof a.name!=='string'||a.name.length<2||a.name.length>100||/[\x00-\x1f\x7f]/.test(a.name)||
      !['admin','staff'].includes(a.role)||!Array.isArray(a.capabilities)||!a.capabilities.includes('records.read')||
      new Set(a.capabilities).size!==a.capabilities.length||a.capabilities.some(c=>!CAPABILITIES.includes(c)||a.role==='staff'&&!CAPABILITIES.slice(0,3).includes(c))||
      !positive(a.approvalVersion)||!Number.isSafeInteger(a.version)||!Number.isSafeInteger(a.credentialVersion)||
      !(a.accountId===null?a.version===0&&a.credentialVersion===0:positive(a.version)&&positive(a.credentialVersion))||
      !['approved','active','removed'].every(k=>typeof a[k]==='boolean'))throw Error('Invalid provisioning account');
    for(const g of value.grants)if(!exact(g,['id','accountId','installationId','profile','version','active'])||!id(g.id)||
      !(g.accountId===null||id(g.accountId))||!id(g.installationId)||!['staff','internal_receiver'].includes(g.profile)||
      !positive(g.version)||typeof g.active!=='boolean')throw Error('Invalid provisioning grant');
    if(new Set(value.accounts.map(a=>a.principalId)).size!==value.accounts.length||
      new Set(value.grants.map(g=>g.installationId)).size!==value.grants.length||
      new Set(value.grants.map(g=>g.id)).size!==value.grants.length||value.configured&&value.scopeVersion===null)
      throw Error('Ambiguous provisioning directory');
    return value;
  }
  async lookup(requestId) {
    if(!id(requestId))invalid();
    const value=await this.invoke('lookup',[requestId]);
    if(!exact(value,['contractVersion','collectionId','requestId','found',...(value?.found===true?['receipt']:[])])||
      value.contractVersion!==1||value.collectionId!==this.groupId||value.requestId!==requestId||typeof value.found!=='boolean')
      throw Error('Invalid provisioning outcome');
    if(value.found)checkProvisioningReceipt(value.receipt,this.groupId,requestId);
    return value;
  }
  async apply(input) {
    const command=provisioningCommand(input,this.groupId),hasher=nativePinHasher(this.env);
    // HMAC includes the original PIN, but its low-entropy plaintext/digest never
    // enters SQL, audit, pending intent, delivery custody or the response.
    const fingerprint=await hasher.commandFingerprint(canonicalJson(command));
    // Avoid new secrets/work when the original commit already has a receipt.
    const prior=await this.lookup(command.requestId);
    if(prior.found){
      if(prior.receipt.operation==='cancelled')fail(409,'burimunsi_provisioning_changed','This original request was cancelled. Refresh before starting again.');
      const result=await this.invoke('apply',[JSON.stringify({operation:command.operation,requestId:command.requestId}),fingerprint,null]);
      return this.commandReceipt(result,command);
    }
    const prepared={...command};let ciphertext=null;
    if(command.operation==='set_pin'){
      prepared.pinHash=await hasher.hash(await this.phone(command),command.pin);
      delete prepared.pin;prepared.accountId=crypto.randomUUID();
    } else if(command.operation==='grant_installation') {
      prepared.grantId=command.grantId??crypto.randomUUID();
      const token=newBearer();prepared.tokenHash=await digest(token);
      // AAD is derived only from the command's exact immutable tuple. The DB
      // validates all versions before retaining this custody and receipt.
      const binding={...command,grantId:prepared.grantId,accountVersion:command.expectedAccountVersion,grantVersion:command.expectedGrantVersion+1};
      ciphertext=await encrypt(this.env,new TextEncoder().encode(token),custodyContext(this.profileSha,this.actorId,this.sessionId,binding));
    }
    const result=await this.invoke('apply',[JSON.stringify(prepared),fingerprint,ciphertext]);
    return this.commandReceipt(result,command);
  }
  commandReceipt(result,command) {
    const receipt=checkProvisioningReceipt(result,this.groupId,command.requestId);
    if(receipt.operation!==command.operation||receipt.principalId!==command.principalId||receipt.scopeVersion!==command.scopeVersion||
      receipt.approvalVersion!==command.approvalVersion||receipt.accountVersion!==command.expectedAccountVersion+(command.operation==='set_pin'?1:0)||
      command.operation!=='set_pin'&&(receipt.accountId!==command.accountId||receipt.installationId!==command.installationId||
       receipt.profile!==command.profile||receipt.grantVersion!==command.expectedGrantVersion+1||command.grantId!==null&&receipt.grantId!==command.grantId))
      throw Error('Provisioning receipt does not match original command');
    return receipt;
  }
  async cancel(requestId) {
    if(!id(requestId))invalid();
    return checkProvisioningReceipt(await this.invoke('cancel',[requestId]),this.groupId,requestId);
  }
  async phone(command) {
    // Directory values are public operator metadata, not an authority override.
    // apply rechecks the same exact approval version under the writer lock.
    const directory=await this.directory();
    const current=directory.accounts.find(a=>a.principalId===command.principalId&&a.approvalVersion===command.approvalVersion);
    if(!current||typeof current.phone!=='string')fail(409,'burimunsi_provisioning_changed','The approved account changed. Refresh before continuing.');
    return current.phone;
  }
  async delivery(requestId,input) {
    if(!id(requestId)||!exact(input,['collectionId','installationId','profile','grantVersion'])||input.collectionId!==this.groupId||
      !id(input.installationId)||!['staff','internal_receiver'].includes(input.profile)||!positive(input.grantVersion))invalid();
    const value=await this.invoke('delivery',[requestId,input.installationId,input.profile,input.grantVersion]);
    const receipt=checkProvisioningReceipt(value?.receipt,this.groupId,requestId);
    if(receipt.operation!=='grant_installation'||receipt.installationId!==input.installationId||receipt.profile!==input.profile||
      receipt.grantVersion!==input.grantVersion||receipt.deliveryExpiresAt<=Date.now()||typeof value.ciphertext!=='string'||
      !/^[a-f0-9]{64}$/.test(value.tokenHash??''))throw Error('Invalid provisioning delivery');
    const token=new TextDecoder('utf-8',{fatal:true}).decode(await decrypt(this.env,value.ciphertext,
      custodyContext(this.profileSha,this.actorId,this.sessionId,receipt)));
    if(!/^[a-f0-9]{64}$/.test(token)||!equalSecret(await digest(token),value.tokenHash))throw Error('Invalid provisioning delivery');
    await this.assertOwned();
    return {contractVersion:1,collectionId:this.groupId,requestId,installationId:input.installationId,
      profile:input.profile,grantVersion:input.grantVersion,expiresAt:receipt.deliveryExpiresAt,installationToken:token};
  }
}
