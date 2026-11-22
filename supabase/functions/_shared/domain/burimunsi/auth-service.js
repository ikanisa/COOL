import {requireThat,requirePort,BuriError} from './errors.js';
import {normalizePhone,requirePin,requireId,requireRequestId,canonicalJson,exactKeys,sha256} from './values.js';
import {newBearer} from './pin.js';
import {authorize} from './policy.js';
import {validOperatorCapabilities} from './operator-access.mjs';
import {cancelledStaffOperation,originalStaffOperation,requireOriginDigest} from './operation-recovery.js';
/** No DB emulator is shipped in runtime. Adapter must use atomic distributed limits,
 * session-version checks and CAS updates in the existing Collect deployment. */
export class NativeAuthService {
  constructor({store,hasher,groupId,clock=()=>Date.now(),sessionTtlMs=30*60*1000,preserveStaffPinOnPhoneChange=false,legacyStaffCreatePin}) {
    requirePort(store,['consumeAttempts','findAccount','findDeviceGrant','createSessionIfCurrent','loadSession','changePinIfCurrent','mutateStaff','findStaff','retainedStaffCommand','revokeSession']);
    requireThat(hasher && typeof hasher.hash==='function' && typeof hasher.verify==='function' && typeof hasher.commandFingerprint==='function' && groupId,'authentication_unconfigured',503);
    requireThat(sessionTtlMs>=60000 && sessionTtlMs<=8*60*60*1000,'invalid_session_policy',503);
    requireThat(typeof preserveStaffPinOnPhoneChange==='boolean','authentication_unconfigured',503);
    Object.assign(this,{store,hasher,groupId,clock,sessionTtlMs,preserveStaffPinOnPhoneChange});this.dummy=null;
    // The historical binding can verify a retained command, never issue a credential.
    this.legacyStaffCreatePin=typeof legacyStaffCreatePin==='string'&&/^[0-9]{4}$/.test(legacyStaffCreatePin)?legacyStaffCreatePin:undefined;
  }
  async login({phone,pin,installationId,installationToken},networkBucket) {
    phone=normalizePhone(phone);requirePin(pin);
    requireThat(typeof installationId==='string' && installationId.length<=128 && /^[a-f0-9]{64}$/.test(installationToken??'') && /^[a-f0-9]{64}$/.test(networkBucket??''),'invalid_credentials',401);
    const now=this.clock(), phoneHash=await sha256(phone), tokenHash=await sha256(installationToken);
    // Charge failures AND successes; do not clear concurrent attack attempts on success.
    const allowed=await this.store.consumeAttempts([
      {key:'account:'+phoneHash,limit:5,windowMs:900000},
      {key:'device:'+installationId,limit:10,windowMs:900000},
      {key:'network:'+networkBucket,limit:50,windowMs:900000}],now);
    if(!allowed)throw new BuriError('try_again_later',429);
    const device=await this.store.findDeviceGrant(this.groupId,installationId,tokenHash);
    requireThat(device?.active&&typeof device.id==='string'&&device.id.length>0,'invalid_credentials',401);
    const account=await this.store.findAccount(this.groupId,phone);
    if(!this.dummy)this.dummy=await this.hasher.hash('+250780000000','0000');
    const record=account?.pinHash??this.dummy;
    const verified=await this.hasher.verify(account?phone:'+250780000000',pin,record);
    if(!verified||!account?.active||account.removed||!device?.active||!device.accountIds?.includes(account.id))throw new BuriError('invalid_credentials',401);
    const token=newBearer(),sessionId=crypto.randomUUID(),expiresAt=now+this.sessionTtlMs;
    const created=await this.store.createSessionIfCurrent({id:sessionId,accountId:account.id,groupId:this.groupId,installationId,
      principalUserId:account.principalUserId,deviceGrantId:device.id,deviceTokenHash:tokenHash,deviceGrantVersion:device.version,credentialVersion:account.credentialVersion,tokenHash:await sha256(token),expiresAt,createdAt:now});
    requireThat(created===true||created?.created===true,'invalid_credentials',401);
    const effectiveExpiry=created===true?expiresAt:created.expiresAt;
    requireThat(Number.isSafeInteger(effectiveExpiry)&&effectiveExpiry>this.clock()&&effectiveExpiry<=expiresAt,'invalid_credentials',401);
    return {token,expiresAt:effectiveExpiry,profile:{id:account.id,name:account.name,phone:account.phone,role:account.role,capabilities:[...account.capabilities]}};
  }
  async authenticate(token,installationId) {
    requireThat(/^[a-f0-9]{64}$/.test(token??'') && typeof installationId==='string','session_unavailable',401);
    // Adapter checks current account state, credential version AND device grant, not JWT claims alone.
    const actor=await this.store.loadSession(await sha256(token),installationId,this.clock());
    authorize(actor,this.groupId,'records.read',{now:this.clock()}); return actor;
  }
  async logout(actor) { await this.store.revokeSession(actor.sessionId);return {signedOut:true}; }
  async changePasscode(actor,{current,newPin,confirm,replacementToken}) {
    authorize(actor,this.groupId,'records.read',{now:this.clock()});
    requirePin(current);requirePin(newPin);requireThat(newPin===confirm,'passcodes_do_not_match');
    requireThat(current!==newPin,'passcode_unchanged');
    requireThat(/^[a-f0-9]{64}$/.test(replacementToken??''),'invalid_credentials',400);
    requireThat(await this.store.consumeAttempts([{key:'pin-change:'+actor.id,limit:5,windowMs:900000}],this.clock()),'try_again_later',429);
    const account=await this.store.findAccount(this.groupId,actor.phone);
    requireThat(account && account.id===actor.id,'session_unavailable',401);
    requireThat(await this.hasher.verify(account.phone,current,account.pinHash),'invalid_current_pin',400);
    const hash=await this.hasher.hash(account.phone,newPin);
    const rotated=await this.store.changePinIfCurrent({accountId:account.id,groupId:this.groupId,expectedCredentialVersion:account.credentialVersion,
      expectedAccountVersion:account.version,pinHash:hash,actorId:actor.id,sessionId:actor.sessionId,
      replacementTokenHash:await sha256(replacementToken),temporaryToken:newBearer(),sessionTtlMs:this.sessionTtlMs});
    // The database transaction has returned; if its acknowledgement is
    // unusable, preserve the client's candidate for recovery rather than
    // claiming the credential change was rejected.
    requireThat(rotated?.rotated===true&&Number.isSafeInteger(rotated.expiresAt)&&rotated.expiresAt>this.clock(),'passcode_change_unconfirmed',503);
    return {reauthenticationRequired:false,expiresAt:rotated.expiresAt};
  }
  async manageStaff(actor,command) {
    authorize(actor,this.groupId,'staff.manage',{now:this.clock()});
    requireThat(command && ['create','edit','disable','enable','remove','reset'].includes(command.action),'invalid_staff_action');
    const action=command.action;
    const fields={create:['action','phone','pin','name','capabilities'],edit:['action','id','expectedVersion','phone','name','pin','capabilities'],
      reset:['action','id','expectedVersion','pin'],disable:['action','id','expectedVersion'],enable:['action','id','expectedVersion'],remove:['action','id','expectedVersion']};
    for(const keys of Object.values(fields))keys.push('requestId');
    const required=action==='create'?fields.create.filter(key=>key!=='pin'):
      action==='edit'?['action','id','expectedVersion','requestId']:fields[action];
    exactKeys(command,fields[action],required);
    const requestId=requireRequestId(command.requestId);
    const predecessor=action==='create'&&!Object.hasOwn(command,'pin');
    if(predecessor)requireThat(this.legacyStaffCreatePin!==undefined,'staff_passcode_required',400);
    const original=predecessor?{...command,pin:this.legacyStaffCreatePin}:command;
    const fingerprint=await this.hasher.commandFingerprint(canonicalJson(original));
    const prior=await this.store.retainedStaffCommand({groupId:this.groupId,actorId:actor.id,sessionId:actor.sessionId,requestId,fingerprint,now:this.clock()});
    if(prior){
      requireThat(!originalStaffOperation(prior.operation),'staff_command_cancelled',409);
      requireThat(prior.sessionId===actor.sessionId&&prior.fingerprint===fingerprint&&
        (!predecessor||prior.operation==='burimunsi.staff.create'&&!Object.hasOwn(prior,'staffCreateInput')),'idempotency_conflict',409);
      const result=prior.response;
      requireThat(result?.applied===true&&typeof result.id==='string'&&/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(result.id)&&
        Number.isSafeInteger(result.version)&&result.version>0,'invalid_recovery_proof',503);
      return {applied:true,id:result.id,version:result.version};
    }
    requireThat(!predecessor,'staff_passcode_required',400);
    const value={action,groupId:this.groupId,actorId:actor.id,actorSessionId:actor.sessionId,requestId,fingerprint};
    let target=null;
    if(action!=='create'){
      requireId(command.id);
      requireThat(Number.isSafeInteger(command.expectedVersion)&&command.expectedVersion>0,'invalid_version');
      target=await this.store.findStaff(this.groupId,command.id);
      requireThat(target && target.groupId===this.groupId && target.role==='staff' && !target.removed,'staff_unavailable',404);
      requireThat(target.version===command.expectedVersion,'staff_changed',409);
      Object.assign(value,{id:target.id,expectedVersion:command.expectedVersion});
    }
    if(Object.hasOwn(command,'name')){
      requireThat(typeof command.name==='string'&&command.name.trim().length>=2&&command.name.trim().length<=100&&!/[\u0000-\u001f\u007f]/.test(command.name),'invalid_name');
      value.name=command.name.trim();
    }
    if(Object.hasOwn(command,'phone'))value.phone=normalizePhone(command.phone);
    const phone=value.phone??target?.phone;
    // Default remains the legacy explicit PIN requirement. The qualified
    // PostgreSQL path may preserve the protected derivation identity atomically.
    if(action==='edit'&&value.phone&&value.phone!==target.phone&&!Object.hasOwn(command,'pin')){
      requireThat(this.preserveStaffPinOnPhoneChange,'new_passcode_required');value.retainPhoneBoundPin=true;
    }
    if(Object.hasOwn(command,'pin'))value.pinHash=await this.hasher.hash(phone,requirePin(command.pin));
    if(Object.hasOwn(command,'capabilities')){
      requireThat(validOperatorCapabilities('staff', command.capabilities),'access_denied',403);
      value.capabilities=[...command.capabilities];
    }
    // The adapter must re-check actor, target version and role within the same transaction,
    // enforce duplicate-number uniqueness, increment revisions, revoke affected sessions and audit.
    const result=await this.store.mutateStaff(value);
    requireThat(result && result.applied===true,'staff_changed',409);
    // Never return credential hashes or adapter internals.
    return {applied:true,id:result.id,version:result.version};
  }
  async resolveStaffCommand(actor,{requestId,originDigest,operation}) {
    authorize(actor,this.groupId,'staff.manage',{now:this.clock()});
    requireRequestId(requestId);requireOriginDigest(originDigest);cancelledStaffOperation(operation);
    requirePort(this.store,['resolveStaffCommand']);
    return this.store.resolveStaffCommand({groupId:this.groupId,actorId:actor.id,
      sessionId:actor.sessionId,requestId,originDigest,operation});
  }
}
