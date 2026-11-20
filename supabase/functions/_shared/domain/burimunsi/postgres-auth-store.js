import {requirePort,requireThat,BuriError} from './errors.js';
import {authorize} from './policy.js';
import {requireId,requireRequestId,canonicalJson,sha256} from './values.js';
import {pgInteger} from './postgres-values.js';
import {PostgresNativeAuthority} from './postgres-authority.js';
import {hasPhonePinContext,PIN_CLOCK_SKEW_MS} from './phone-pin-request.js';
import {readRecoveryProof} from './postgres-operation-recovery.js';
import {retainPhoneBoundPin} from './pin.js';
import {requireOriginDigest,projectRecoveredOutcome,cancelledStaffOperation,originalStaffOperation} from './operation-recovery.js';

const account=r=>r?({id:r.id,groupId:r.collection_id,principalUserId:r.principal_user_id,phone:r.phone,name:r.name,
  role:r.role,capabilities:r.capabilities,active:r.active,removed:r.removed,pinHash:r.pin_hash,
  credentialVersion:Number(r.credential_version),version:Number(r.version)}):null;

/** PostgreSQL adapter for the NEW isolated native operator realm.
 * Uses the existing PostgresDatabase and its application work fence. It never
 * opens its own unrestricted connection or modifies global auth settings.
 * This candidate requires the reviewed additive schema and private-table grants.
 * Canonical composition supplies a closed owner-approved shared-identity resolver
 * in the SAME tx. Legacy source adapters still require an explicit trusted port.
 */
export class PostgresNativeAuthStore extends PostgresNativeAuthority {
  constructor({db,groupId,createOperatorPrincipal,clock=()=>Date.now(),sessionBinding=null,operatorDirectory=null}){
    super({db,groupId});
    requireThat(typeof groupId==='string'&&groupId.length>0&&typeof createOperatorPrincipal==='function','collect_adapter_required',503);
    if(sessionBinding!==null)requirePort(sessionBinding,['prepareInTransaction','bindInTransaction','assertInTransaction']);
    if(operatorDirectory!==null)requirePort(operatorDirectory,['permits','assertInTransaction']);
    Object.assign(this,{db,groupId,createOperatorPrincipal,clock,sessionBinding,operatorDirectory});
  }
  checkGroup(group){requireThat(group===this.groupId,'access_denied',403);}
  async session(tx,{id=null,tokenHash=null,installationId=null,now=this.clock()}){
    // Never let an absent selector turn into an arbitrary valid operator session.
    requireThat((typeof id==='string'&&id.length>0) ||
      (typeof tokenHash==='string'&&/^[a-f0-9]{64}$/.test(tokenHash)&&typeof installationId==='string'&&installationId.length>0),
      'session_unavailable',401);
    if(id!==null)requireRequestId(id);
    if(installationId!==null)requireRequestId(installationId);
    requireThat(Number.isSafeInteger(now)&&now>=0,'invalid_session_clock',503);
    // Phone/PIN requests get their current short lease only from the
    // independently revalidated, device-bound SQL context. The immutable
    // original expiry remains authoritative for managed-email sessions. Only a
    // SQL-proven PIN context may use the bounded edge/database clock skew;
    // the expiry check remains strict against the edge clock for both paths.
    const pin=hasPhonePinContext(this.db),expiry=pin?'pin.expires_at':'s.expires_at';
    const pinJoin=pin?'JOIN LATERAL private.burimunsi_pin_context() pin ON pin.native_session_id=s.id':'';
    const rows=await tx.unsafe(`SELECT s.id AS session_id,${expiry} AS expires_at,s.installation_id,a.*,d.profile AS installation_profile
      FROM private.burimunsi_sessions s
      ${pinJoin}
      JOIN private.burimunsi_accounts a ON a.id=s.account_id AND a.collection_id=s.collection_id
      JOIN private.burimunsi_device_grants d ON d.id=s.grant_id AND d.collection_id=s.collection_id
      JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.account_id=a.id AND da.collection_id=s.collection_id
      JOIN private.burimunsi_scopes c ON c.collection_id=s.collection_id
      JOIN app.users u ON u.id=a.principal_user_id AND u.access_status='active'
      WHERE s.collection_id=$1 AND ($2::uuid IS NULL OR s.id=$2::uuid) AND ($3::text IS NULL OR s.token_hash=$3)
        AND ($4::uuid IS NULL OR s.installation_id=$4::uuid) AND NOT s.revoked AND ${expiry}>$5
        AND a.active AND NOT a.removed AND d.active AND ${pin?"(c.enabled OR s.auth_method='phone_pin')":'c.enabled'}
        AND a.credential_version=s.credential_version AND d.version=s.grant_version
        AND d.installation_id=s.installation_id AND s.principal_user_id=a.principal_user_id
        AND s.created_at<=$5${pin?`+${PIN_CLOCK_SKEW_MS}`:''}`,[this.groupId,id,tokenHash,installationId,now]);
    requireThat(rows.length<=1,'session_unavailable',401);const r=rows[0];if(!r)return null;
    const actor={id:r.id,principalUserId:r.principal_user_id,sessionId:r.session_id,phone:r.phone,name:r.name,groupId:r.collection_id,
      role:r.role,capabilities:r.capabilities,active:true,revoked:false,expiresAt:pgInteger(r.expires_at,{minimum:now+1,code:'session_unavailable'}),installationId:r.installation_id,installationProfile:r.installation_profile};
    if(this.sessionBinding){const binding=await this.sessionBinding.assertInTransaction(tx,actor);
      actor.expiresAt=binding.expiresAt;actor.principalSessionId=binding.principalSessionId;
      if(binding.authMethod)actor.authMethod=binding.authMethod;}
    if(this.operatorDirectory)await this.operatorDirectory.assertInTransaction(tx,actor);
    return actor;
  }
  async loadSession(tokenHash,installationId,now){return this.read(tx=>this.session(tx,{tokenHash,installationId,now}));}
  async findAccount(groupId,phone){this.checkGroup(groupId);return this.read(async tx=>{
    const found=account((await tx.unsafe('SELECT * FROM private.burimunsi_accounts WHERE collection_id=$1 AND phone=$2',[groupId,phone]))[0]);
    return found&&(!this.operatorDirectory||await this.operatorDirectory.permits(tx,found))?found:null;
  });}
  async findStaff(groupId,id){this.checkGroup(groupId);return this.read(async tx=>account((await tx.unsafe('SELECT * FROM private.burimunsi_accounts WHERE collection_id=$1 AND id=$2::uuid',[groupId,id]))[0]));}
  async findDeviceGrant(groupId,installationId,tokenHash){
    this.checkGroup(groupId);
    return this.read(async tx=>{
      const d=(await tx.unsafe('SELECT * FROM private.burimunsi_device_grants WHERE collection_id=$1 AND installation_id=$2::uuid AND token_hash=$3',[groupId,installationId,tokenHash]))[0];
      if(!d)return null;
      const accounts=await tx.unsafe('SELECT account_id FROM private.burimunsi_device_accounts WHERE collection_id=$1 AND grant_id=$2::uuid',[groupId,d.id]);
      return {id:d.id,active:d.active,version:Number(d.version),profile:d.profile,accountIds:accounts.map(x=>x.account_id)};
    });
  }
  async consumeAttempts(buckets,now){
    requireThat(Array.isArray(buckets)&&buckets.length>=1&&buckets.length<=8&&Number.isSafeInteger(now),'invalid_rate_policy',503);
    return this.write(async tx=>{
      let admitted=true;
      for(const {key,limit,windowMs} of [...buckets].sort((a,b)=>a.key.localeCompare(b.key))){
        requireThat(typeof key==='string'&&key.length<=200&&Number.isInteger(limit)&&limit>0&&Number.isSafeInteger(windowMs)&&windowMs>=1000,'invalid_rate_policy',503);
        const start=Math.floor(now/windowMs)*windowMs;
        const result=await tx.unsafe(`INSERT INTO private.burimunsi_rate_limits(collection_id,bucket,window_start,window_ms,attempts,expires_at)
          VALUES($1,$2,$3,$4,1,$5) ON CONFLICT(collection_id,bucket,window_start)
          DO UPDATE SET attempts=private.burimunsi_rate_limits.attempts+1 RETURNING attempts`,[this.groupId,key,start,windowMs,start+windowMs]);
        if(Number(result[0].attempts)>limit)admitted=false;
      }
      return admitted; // Denied attempts are committed, not rolled back or reset by successful sign-in.
    });
  }
  async createSessionIfCurrent(s){
    this.checkGroup(s.groupId);
    requireThat(typeof s.deviceGrantId==='string'&&s.deviceGrantId.length>0&&/^[a-f0-9]{64}$/.test(s.deviceTokenHash??''),'invalid_credentials',401);
    requireId(s.principalUserId);requireRequestId(s.id);requireRequestId(s.accountId);requireRequestId(s.installationId);requireRequestId(s.deviceGrantId);
    requireThat(Number.isSafeInteger(s.createdAt)&&s.createdAt>=0&&Number.isSafeInteger(s.expiresAt)&&s.expiresAt>s.createdAt&&
      s.expiresAt-s.createdAt<=8*60*60*1000&&Number.isSafeInteger(s.credentialVersion)&&s.credentialVersion>0&&
      Number.isSafeInteger(s.deviceGrantVersion)&&s.deviceGrantVersion>0&&/^[a-f0-9]{64}$/.test(s.tokenHash??''),'invalid_credentials',401);
    return this.write(async tx=>{
      const binding=this.sessionBinding?await this.sessionBinding.prepareInTransaction(tx,s):null;
      const expiresAt=binding?.expiresAt??s.expiresAt;
      const result=await tx.unsafe(`INSERT INTO private.burimunsi_sessions(id,collection_id,account_id,grant_id,installation_id,credential_version,grant_version,token_hash,created_at,expires_at,principal_user_id)
        SELECT $1::uuid,a.collection_id,a.id,d.id,d.installation_id,a.credential_version,d.version,$7,$8,$9,a.principal_user_id
        FROM private.burimunsi_accounts a
        JOIN private.burimunsi_device_accounts da ON da.account_id=a.id AND da.collection_id=a.collection_id
        JOIN private.burimunsi_device_grants d ON d.id=da.grant_id AND d.collection_id=da.collection_id
        JOIN private.burimunsi_scopes c ON c.collection_id=a.collection_id
        JOIN app.users u ON u.id=a.principal_user_id AND u.access_status='active'
        WHERE a.collection_id=$2 AND a.id=$3::uuid AND d.installation_id=$4::uuid AND a.credential_version=$5 AND d.version=$6
          AND d.id=$10::uuid AND d.token_hash=$11 AND a.principal_user_id=$12 AND a.active AND NOT a.removed AND d.active AND c.enabled RETURNING id`,
      [s.id,this.groupId,s.accountId,s.installationId,s.credentialVersion,s.deviceGrantVersion,s.tokenHash,s.createdAt,expiresAt,s.deviceGrantId,s.deviceTokenHash,s.principalUserId]);
      if(result.length!==1)return false;
      if(this.operatorDirectory){
        const current=account((await tx.unsafe('SELECT * FROM private.burimunsi_accounts WHERE collection_id=$1 AND id=$2::uuid',[this.groupId,s.accountId]))[0]);
        await this.operatorDirectory.assertInTransaction(tx,current);
      }
      if(binding)await this.sessionBinding.bindInTransaction(tx,binding);
      await this.audit(tx,s.accountId,'burimunsi.session.created',s.id,null);
      return binding?{created:true,expiresAt}:true;
    });
  }
  async audit(tx,actorId,action,entityId,requestId){
    await tx.unsafe('INSERT INTO private.burimunsi_audit(id,collection_id,actor_id,action,entity_id,request_id,at_ms) VALUES($1::uuid,$2,$3::uuid,$4,$5,$6::uuid,$7)',
      [crypto.randomUUID(),this.groupId,actorId,action,entityId,requestId,this.clock()]);
  }
  async revokeSession(id){return this.write(async tx=>{await tx.unsafe('UPDATE private.burimunsi_sessions SET revoked=true WHERE collection_id=$1 AND id=$2::uuid',[this.groupId,id]);});}
  async changePinIfCurrent(cmd){
    this.checkGroup(cmd.groupId);
    requireThat(hasPhonePinContext(this.db),'session_unavailable',401);
    requireThat(Number.isSafeInteger(cmd.expectedCredentialVersion)&&cmd.expectedCredentialVersion>0&&
      Number.isSafeInteger(cmd.expectedAccountVersion)&&cmd.expectedAccountVersion>0&&
      /^[a-f0-9]{64}$/.test(cmd.replacementTokenHash??'')&&/^[a-f0-9]{64}$/.test(cmd.temporaryToken??'')&&
      Number.isSafeInteger(cmd.sessionTtlMs)&&cmd.sessionTtlMs>=60000&&cmd.sessionTtlMs<=28800000,'session_unavailable',401);
    try{return await this.write(async tx=>{
      const actor=await this.session(tx,{id:cmd.sessionId});
      authorize(actor,this.groupId,'records.read',{now:this.clock()});requireThat(actor.id===cmd.actorId&&actor.id===cmd.accountId,'access_denied',403);
      const result=await tx.unsafe('SELECT private.burimunsi_pin_rotate_passcode($1::uuid,$2::uuid,$3,$4,$5::jsonb,$6,$7,$8) AS result',
        [cmd.accountId,cmd.sessionId,cmd.expectedCredentialVersion,cmd.expectedAccountVersion,cmd.pinHash,
          cmd.replacementTokenHash,cmd.temporaryToken,cmd.sessionTtlMs]);
      const value=result[0]?.result;
      requireThat(result.length===1&&value?.rotated===true,'session_unavailable',401);
      const expiresAt=pgInteger(value.expiresAt,{minimum:this.clock()+1,code:'session_unavailable'});
      requireThat(expiresAt<=this.clock()+cmd.sessionTtlMs+5000,'session_unavailable',401);
      await this.audit(tx,actor.id,'burimunsi.passcode.changed',actor.id,null);return {rotated:true,expiresAt};
    });}catch(error){
      // A database rejection aborts the transaction and is not a lost COMMIT.
      // Leave unknown connection/commit outcomes untouched for client recovery.
      if(error?.code==='42501')throw new BuriError('session_unavailable',401);
      if(error?.code==='23505')throw new BuriError('invalid_session_candidate',400);
      throw error;
    }
  }
  async retained(tx,actorId,requestId){
    const row=(await tx.unsafe('SELECT session_id,operation,fingerprint,response FROM private.burimunsi_command_receipts WHERE collection_id=$1 AND actor_id=$2::uuid AND request_id=$3::uuid',[this.groupId,actorId,requestId]))[0];
    return row?{sessionId:row.session_id,operation:row.operation,fingerprint:row.fingerprint,response:row.response}:null;
  }
  async retainedStaffCommand(cmd){
    this.checkGroup(cmd.groupId);
    return this.read(async tx=>{
      const actor=await this.session(tx,{id:cmd.sessionId,now:cmd.now});authorize(actor,this.groupId,'staff.manage',{now:cmd.now});
      requireThat(actor.id===cmd.actorId,'session_unavailable',401);return this.retained(tx,actor.id,cmd.requestId);
    });
  }
  async resolveStaffCommand(cmd){
    this.checkGroup(cmd.groupId);requireRequestId(cmd.requestId);requireOriginDigest(cmd.originDigest);
    const cancellationOperation=cancelledStaffOperation(cmd.operation);
    return this.write(async tx=>{
      // The same write transaction and Collect mutation lock also guard staff apply.
      const now=this.clock(),actor=await this.session(tx,{id:cmd.sessionId,now});
      authorize(actor,this.groupId,'staff.manage',{now});
      requireThat(actor.id===cmd.actorId&&actor.sessionId===cmd.sessionId,'session_unavailable',401);
      const proof=await readRecoveryProof(tx,{groupId:this.groupId,actorId:actor.id,
        currentSessionId:actor.sessionId,requestId:cmd.requestId,originDigest:cmd.originDigest});
      const project=()=>projectRecoveredOutcome({proof,actor,groupId:this.groupId,
        requestId:cmd.requestId,originDigest:cmd.originDigest,now});
      const prior=project(); // Validates the original and current identity before any write.
      if(proof.receipt){
        requireThat([cmd.operation,cancellationOperation].includes(proof.receipt.operation),'idempotency_conflict',409);
        return prior;
      }
      const fingerprint=await sha256(canonicalJson({protocol:'burimunsi.staff-cancellation.v1',
        groupId:this.groupId,actorId:actor.id,requestId:cmd.requestId,
        originSessionId:proof.origin.sessionId,operation:cmd.operation}));
      await tx.unsafe(`INSERT INTO private.burimunsi_command_receipts(collection_id,actor_id,request_id,session_id,operation,fingerprint,response,created_at)
        VALUES($1,$2::uuid,$3::uuid,$4::uuid,$5,$6,'{}'::jsonb,$7)`,
        [this.groupId,actor.id,cmd.requestId,proof.origin.sessionId,cancellationOperation,fingerprint,now]);
      await this.audit(tx,actor.id,'burimunsi.staff.cancelled',cmd.requestId,cmd.requestId);
      proof.receipt={groupId:this.groupId,actorId:actor.id,requestId:cmd.requestId,
        sessionId:proof.origin.sessionId,operation:cancellationOperation,createdAt:now,cancellationMarkerValid:true};
      return project();
    });
  }
  async mutateStaff(cmd){
    this.checkGroup(cmd.groupId);
    return this.write(async tx=>{
      const actor=await this.session(tx,{id:cmd.actorSessionId});authorize(actor,this.groupId,'staff.manage',{now:this.clock()});requireThat(actor.id===cmd.actorId,'session_unavailable',401);
      const prior=await this.retained(tx,actor.id,cmd.requestId);
      if(prior){requireThat(!originalStaffOperation(prior.operation),'staff_command_cancelled',409);
        requireThat(prior.sessionId===actor.sessionId&&prior.fingerprint===cmd.fingerprint,'idempotency_conflict',409);return prior.response;}
      let id=cmd.id,version;
      if(cmd.action==='create'){
        requireThat(cmd.pinHash&&cmd.name&&cmd.phone&&cmd.capabilities,'invalid_staff_command');
        // Carry the exact normalized login identity into the trusted shared
        // Collect resolver. A name/PIN is not a managed identity assertion.
        const principal=await this.createOperatorPrincipal(tx,{groupId:this.groupId,name:cmd.name,phone:cmd.phone,capabilities:cmd.capabilities,
          actorId:actor.principalUserId,actorNativeSessionId:actor.sessionId,requestId:cmd.requestId});
        requireThat(typeof principal?.id==='string','principal_unavailable',503);
        if(this.operatorDirectory)await this.operatorDirectory.assertInTransaction(tx,{
          groupId:this.groupId,principalUserId:principal.id,phone:cmd.phone,role:'staff',capabilities:cmd.capabilities});
        id=crypto.randomUUID();version=1;
        await tx.unsafe(`INSERT INTO private.burimunsi_accounts(id,collection_id,principal_user_id,phone,name,role,capabilities,pin_hash,created_at,updated_at)
          VALUES($1::uuid,$2,$3,$4,$5,'staff',$6::text[],$7::jsonb,$8,$8)`,[id,this.groupId,principal.id,cmd.phone,cmd.name,cmd.capabilities,cmd.pinHash,this.clock()]);
      }else{
        const row=(await tx.unsafe('SELECT * FROM private.burimunsi_accounts WHERE collection_id=$1 AND id=$2::uuid FOR UPDATE',[this.groupId,id]))[0];
        requireThat(row&&row.role==='staff'&&!row.removed&&Number(row.version)===cmd.expectedVersion,'staff_changed',409);
        const next={name:cmd.name??row.name,phone:cmd.phone??row.phone,capabilities:cmd.capabilities??row.capabilities,pinHash:cmd.pinHash??row.pin_hash,active:row.active,removed:row.removed};
        if(cmd.action==='disable'||cmd.action==='remove')next.active=false;if(cmd.action==='enable')next.active=true;if(cmd.action==='remove')next.removed=true;
        requireThat(['edit','reset','disable','enable','remove'].includes(cmd.action),'invalid_staff_action');
        if(cmd.action==='reset')requireThat(cmd.pinHash,'invalid_staff_command');
        if(next.phone!==row.phone&&!cmd.pinHash){
          requireThat(cmd.action==='edit'&&cmd.retainPhoneBoundPin===true,'new_passcode_required');
          requireThat(row.active&&!row.removed&&this.operatorDirectory,'staff_authority_unavailable',503);
          // The additive helper rechecks current native authority and global
          // phone availability while holding the shared mutation lock. Its
          // absence blocks this opt-in path before any credential update.
          const guard=await tx.unsafe('SELECT private.burimunsi_pin_staff_phone_available($1,$2::uuid,$3) AS available',
            [this.groupId,id,next.phone]);
          requireThat(guard.length===1&&guard[0].available===true,'duplicate_phone',409);
          await this.operatorDirectory.assertInTransaction(tx,{groupId:this.groupId,principalUserId:row.principal_user_id,
            phone:row.phone,role:row.role,capabilities:row.capabilities});
          next.pinHash=retainPhoneBoundPin(row.pin_hash,row.phone,next.phone);
        }
        if(next.active&&!next.removed&&this.operatorDirectory)await this.operatorDirectory.assertInTransaction(tx,{
          groupId:this.groupId,principalUserId:row.principal_user_id,phone:next.phone,role:row.role,capabilities:next.capabilities});
        version=Number(row.version)+1;
        await tx.unsafe(`UPDATE private.burimunsi_accounts SET name=$1,phone=$2,capabilities=$3::text[],pin_hash=$4::jsonb,active=$5,removed=$6,
          version=version+1,credential_version=credential_version+1,updated_at=$7 WHERE collection_id=$8 AND id=$9::uuid`,
          [next.name,next.phone,next.capabilities,next.pinHash,next.active,next.removed,this.clock(),this.groupId,id]);
        await tx.unsafe('UPDATE private.burimunsi_sessions SET revoked=true WHERE collection_id=$1 AND account_id=$2::uuid',[this.groupId,id]);
      }
      const response={applied:true,id,version};
      await this.audit(tx,actor.id,'burimunsi.staff.'+cmd.action,id,cmd.requestId);
      await tx.unsafe('INSERT INTO private.burimunsi_command_receipts(collection_id,actor_id,request_id,session_id,operation,fingerprint,response,created_at) VALUES($1,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7::jsonb,$8)',
        [this.groupId,actor.id,cmd.requestId,actor.sessionId,'burimunsi.staff.'+cmd.action,cmd.fingerprint,response,this.clock()]);
      return response;
    }).catch(error=>{
      // Map only the database's exact staff-creation freshness failure after
      // the transaction has rolled back; other permission errors stay opaque.
      if(cmd.action==='create'&&error?.code==='42501'&&error?.message==='fresh_auth_required')
        throw new BuriError('fresh_auth_required',403);
      if(cmd.action==='edit'&&error?.code==='42501'&&error?.message==='burimunsi_staff_phone_denied')
        throw new BuriError('access_denied',403);
      if(error?.code==='23505')throw new BuriError('duplicate_phone',409);
      throw error;
    });
  }
}
