import {requirePort,requireThat,BuriError} from './errors.js';
import {authorize} from './policy.js';
import {requireId,requireRequestId} from './values.js';
import {pgInteger} from './postgres-values.js';
import {PostgresNativeAuthority} from './postgres-authority.js';

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
    const rows=await tx.unsafe(`SELECT s.id AS session_id,s.expires_at,s.installation_id,a.*,d.profile AS installation_profile
      FROM private.burimunsi_sessions s
      JOIN private.burimunsi_accounts a ON a.id=s.account_id AND a.collection_id=s.collection_id
      JOIN private.burimunsi_device_grants d ON d.id=s.grant_id AND d.collection_id=s.collection_id
      JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.account_id=a.id AND da.collection_id=s.collection_id
      JOIN private.burimunsi_scopes c ON c.collection_id=s.collection_id
      JOIN app.users u ON u.id=a.principal_user_id AND u.access_status='active'
      WHERE s.collection_id=$1 AND ($2::uuid IS NULL OR s.id=$2::uuid) AND ($3::text IS NULL OR s.token_hash=$3)
        AND ($4::uuid IS NULL OR s.installation_id=$4::uuid) AND NOT s.revoked AND s.expires_at>$5
        AND a.active AND NOT a.removed AND d.active AND c.enabled
        AND a.credential_version=s.credential_version AND d.version=s.grant_version
        AND d.installation_id=s.installation_id AND s.principal_user_id=a.principal_user_id
        AND s.created_at<=$5`,[this.groupId,id,tokenHash,installationId,now]);
    requireThat(rows.length<=1,'session_unavailable',401);const r=rows[0];if(!r)return null;
    const actor={id:r.id,principalUserId:r.principal_user_id,sessionId:r.session_id,phone:r.phone,name:r.name,groupId:r.collection_id,
      role:r.role,capabilities:r.capabilities,active:true,revoked:false,expiresAt:pgInteger(r.expires_at,{minimum:now+1,code:'session_unavailable'}),installationId:r.installation_id,installationProfile:r.installation_profile};
    if(this.sessionBinding){const binding=await this.sessionBinding.assertInTransaction(tx,actor);
      actor.expiresAt=binding.expiresAt;actor.principalSessionId=binding.principalSessionId;}
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
    return this.write(async tx=>{
      const actor=await this.session(tx,{id:cmd.sessionId});
      authorize(actor,this.groupId,'records.read',{now:this.clock()});requireThat(actor.id===cmd.actorId&&actor.id===cmd.accountId,'access_denied',403);
      const result=await tx.unsafe('UPDATE private.burimunsi_accounts SET pin_hash=$1::jsonb,credential_version=credential_version+1,version=version+1,updated_at=$2 WHERE collection_id=$3 AND id=$4::uuid AND credential_version=$5 AND active AND NOT removed RETURNING id',
        [cmd.pinHash,this.clock(),this.groupId,cmd.accountId,cmd.expectedCredentialVersion]);
      if(result.length!==1)return false;
      await tx.unsafe('UPDATE private.burimunsi_sessions SET revoked=true WHERE collection_id=$1 AND account_id=$2::uuid',[this.groupId,cmd.accountId]);
      await this.audit(tx,actor.id,'burimunsi.passcode.changed',actor.id,null);return true;
    });
  }
  async retained(tx,actorId,requestId){
    const row=(await tx.unsafe('SELECT session_id,fingerprint,response FROM private.burimunsi_command_receipts WHERE collection_id=$1 AND actor_id=$2::uuid AND request_id=$3::uuid',[this.groupId,actorId,requestId]))[0];
    return row?{sessionId:row.session_id,fingerprint:row.fingerprint,response:row.response}:null;
  }
  async retainedStaffCommand(cmd){
    this.checkGroup(cmd.groupId);
    return this.read(async tx=>{
      const actor=await this.session(tx,{id:cmd.sessionId,now:cmd.now});authorize(actor,this.groupId,'staff.manage',{now:cmd.now});
      requireThat(actor.id===cmd.actorId,'session_unavailable',401);return this.retained(tx,actor.id,cmd.requestId);
    });
  }
  async mutateStaff(cmd){
    this.checkGroup(cmd.groupId);
    return this.write(async tx=>{
      const actor=await this.session(tx,{id:cmd.actorSessionId});authorize(actor,this.groupId,'staff.manage',{now:this.clock()});requireThat(actor.id===cmd.actorId,'session_unavailable',401);
      const prior=await this.retained(tx,actor.id,cmd.requestId);
      if(prior){requireThat(prior.sessionId===actor.sessionId&&prior.fingerprint===cmd.fingerprint,'idempotency_conflict',409);return prior.response;}
      let id=cmd.id,version;
      if(cmd.action==='create'){
        requireThat(cmd.pinHash&&cmd.name&&cmd.phone&&cmd.capabilities,'invalid_staff_command');
        // Carry the exact normalized login identity into the trusted shared
        // Collect resolver. A name/PIN is not a managed identity assertion.
        const principal=await this.createOperatorPrincipal(tx,{groupId:this.groupId,name:cmd.name,phone:cmd.phone,actorId:actor.principalUserId,requestId:cmd.requestId});
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
        if(next.phone!==row.phone)requireThat(cmd.pinHash,'new_passcode_required');
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
    }).catch(error=>{if(error?.code==='23505')throw new BuriError('duplicate_phone',409);throw error;});
  }
}
