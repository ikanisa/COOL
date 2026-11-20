import {bindingJson,gatewayToken,momoGuard} from '../momo_gateway.js';
import {encrypt,decrypt} from '../encryption.js';
import {auditStatement} from '../core.js';
import {PostgresNativeAuthority} from './postgres-authority.js';
import {canonicalManagedActor} from './postgres-managed-actor.js';
import {MANAGED_SESSION_SQL} from './postgres-managed-sessions.js';
import {authorize} from './policy.js';
import {requireThat,requirePort,BuriError} from './errors.js';
import {canonicalJson,exactKeys,requireId,requireRequestId,sha256} from './values.js';
import {pgInteger} from './postgres-values.js';
import {GATEWAY_REPLACEMENT,gatewayReplacementResponse,readGatewayReplacementOutcome} from './postgres-gateway-outcome.js';
import {hasPhonePinContext} from './phone-pin-request.js';

const enc=new TextEncoder(),dec=new TextDecoder('utf-8',{fatal:true});
const positive=v=>pgInteger(v,{minimum:1,code:'gateway_data_unavailable'});
const integer=v=>pgInteger(v,{minimum:0,code:'gateway_data_unavailable'});
const time=v=>{if(v===null)return null;
 requireThat(typeof v==='string'&&v.length<=40&&/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?(?:Z|[+-]\d\d:\d\d)$/.test(v)&&Number.isFinite(Date.parse(v)),'gateway_data_unavailable',503);
 return new Date(v).toISOString();};
const identity=a=>canonicalJson({id:a.id,sessionId:a.sessionId,principalUserId:a.principalUserId,
 principalSessionId:a.principalSessionId,installationId:a.installationId,installationProfile:a.installationProfile,
 role:a.role,capabilities:[...a.capabilities].sort(),expiresAt:a.expiresAt});

// A read-only permission/proof projection over the SAME tuple already verified
// by the managed native session. Unlike the existing assisted-SMS view, this
// query invokes no helper that takes FOR SHARE locks in a READ ONLY snapshot.
export const GATEWAY_READ_PERMISSION_SQL=`WITH current AS MATERIALIZED (${MANAGED_SESSION_SQL})
 SELECT c.principal_user_id,c.principal_session_id,c.shared_role FROM current c
 JOIN app.admin_users a ON a.id=c.admin_id AND a.status='active' AND a.role=c.shared_role
 JOIN app.admin_grants g ON g.user_id=c.principal_user_id AND g.permission='receivers.read'
 JOIN app.admin_account_role_capabilities cap ON cap.role=a.role AND cap.permission=g.permission
 WHERE c.principal_user_id=$1 AND c.principal_session_id=$2 AND c.shared_role IN('owner','admin')
 AND EXISTS(SELECT 1 FROM private.admin_sensitive_email_proofs p
  JOIN private.admin_email_operations o ON o.challenge_id=p.challenge_id
  JOIN private.auth_principal_links principal ON principal.user_id=c.principal_user_id AND principal.auth_user_id=p.auth_user_id
  WHERE p.admin_id=a.id AND p.principal_id=c.principal_user_id AND p.original_session_id::text=c.principal_session_id
   AND p.cookie_hash=c.cookie_hash AND p.public_session_id=c.public_session_id AND p.auth_version=a.auth_version
   AND p.origin=c.origin AND p.identity_value=lower(a.email) AND p.purpose='admin_sensitive_operations'
   AND o.verification_state='verified' AND o.cleanup_state IN('confirmed','not_required')
   AND p.verified_session_id=o.verified_session_id AND p.verified_at=o.verified_amr_at
   AND p.verified_at BETWEEN floor(c.now_ms::numeric/1000)-300 AND floor(c.now_ms::numeric/1000)) LIMIT 2`;

const BINDING_SQL=`SELECT s.collection_id,s.receiving_account_id,s.active_binding_id,s.binding_version,s.version AS scope_version,s.enabled,
 b.id AS binding_id,b.owner_user_id,b.version AS canonical_version,b.status AS binding_status,b.subscription_evidence,b.created_at AS binding_created_at,
 a.provider,a.public_code,a.recipient_name,a.currency,a.timezone,a.status AS account_status,
 c.id AS credential_id,c.installation_id,c.revoked_at,c.pending_count,c.oldest_pending_at,c.last_sms_at,c.last_contact_at
 FROM private.burimunsi_scopes s JOIN app.momo_gateway_bindings b ON b.id=s.active_binding_id AND b.receiving_account_id=s.receiving_account_id
 JOIN app.momo_receiving_accounts a ON a.id=b.receiving_account_id
 LEFT JOIN app.momo_gateway_credentials c ON c.binding_id=b.id WHERE s.collection_id=$1`;

/** Shared canonical receiver authority. Target custody is selected by the real
 * Admin setup command; native retirement returns an ACK, never its credential. */
export class PostgresCollectGateway {
 constructor({authority,env,clock=()=>Date.now()}){
  requirePort(authority,['read','write','session','assertOwned']);requireId(authority.groupId);
  requirePort(authority.db,['prepare','statement']);requireThat(env?.DB===authority.db,'collect_adapter_required',503);
  Object.assign(this,{authority,db:authority.db,env,groupId:authority.groupId,clock});
 }
 async owned(){requireThat(this.env.DB===this.db,'request_not_admitted',503);await this.authority.assertOwned();}
 scope(group){requireThat(group===this.groupId,'access_denied',403);}
 async query(sql,text,values=[]){await this.owned();const rows=await sql.unsafe(text,values);await this.owned();return rows;}
 async statement(sql,value){await this.owned();const out=await this.db.statement(sql,value);await this.owned();requireThat(out?.success===true&&out.meta?.changes===1,'gateway_changed',409);return out;}
 async guard(sql,canonical){
  const id=crypto.randomUUID();
  try{
   await this.statement(sql,this.db.prepare(`INSERT INTO app.mutation_guards
    (id,user_id,session_id,now_seconds,collection_id,permission,minimum_assurance,expected_mfa_at,fresh_seconds)
    VALUES(?,?,?,?,?,?,?,?,?)`).bind(id,canonical.userId,canonical.sessionId,canonical.now,
     canonical.authMethod==='phone_pin'?this.groupId:null,'receivers.manage',canonical.authMethod==='phone_pin'?null:2,canonical.mfa,300));
   await this.statement(sql,this.db.prepare('DELETE FROM app.mutation_guards WHERE id=?').bind(id));
  }catch(error){if(['request_not_admitted','application_fenced','application_fence_unavailable'].includes(error?.code))throw error;throw new BuriError('access_denied',403);}
 }
 async binding(sql){
  const rows=await this.query(sql,BINDING_SQL,[this.groupId]);requireThat(rows.length===1,'gateway_unavailable',409);
  const row=rows[0];requireThat(row.collection_id===this.groupId&&row.enabled===true&&row.binding_status==='active'&&row.account_status==='active'&&
   row.active_binding_id===row.binding_id&&positive(row.binding_version)===positive(row.canonical_version),'gateway_unavailable',409);
  const active=await this.query(sql,"SELECT id FROM app.momo_gateway_bindings WHERE receiving_account_id=$1 AND status='active' ORDER BY id LIMIT 2",[row.receiving_account_id]);
  requireThat(active.length===1&&active[0].id===row.binding_id,'gateway_changed',409);return row;
 }
 withReadSnapshot(fn){return this.run(false,fn);}
 async pair(actor,command){
  requireThat(hasPhonePinContext(this.db),'session_unavailable',401);
  requireRequestId(command.requestId);requireThat(command.replace===false,'invalid_pairing_code',400);
  const authorizePair=async(sql,{readOnly=false}={})=>{
   const current=await this.authority.session(sql,{id:actor.sessionId});
   authorize(current,this.groupId,'records.read',{now:this.clock()});
   requireThat(current.id===actor.id&&current.role==='admin'&&current.installationProfile==='internal_receiver'&&
    current.capabilities.includes('gateway.manage'),'access_denied',403);
   const canonical=await canonicalManagedActor(this.authority,sql);
   requireThat(canonical.authMethod==='phone_pin'&&canonical.userId===current.principalUserId&&canonical.sessionId===current.sessionId,'access_denied',403);
   if(readOnly){
    requireThat(Number.isSafeInteger(canonical.authenticatedAt)&&canonical.authenticatedAt<=canonical.now&&
     canonical.authenticatedAt>=canonical.now-300,'fresh_auth_required',403);
   }else await this.guard(sql,canonical);
   return canonical;
  };
  const claimCustody=async sql=>{
   const claims=await this.query(sql,NATIVE_PIN_CUSTODY_SQL,[this.groupId,actor.sessionId,actor.installationId,actor.id]);
   requireThat(claims.length===1&&claims[0].result?.claimed===true,'installation_not_authorized',403);
  };
  // The code was issued through existing Collect Admin to the actual canonical
  // binding/SIM. Replacing a working phone requires a new Admin-authorized code;
  // this method never revokes an old receiver or discards its pending captures.
  return createCanonicalGatewayPair({env:this.env,groupId:this.groupId,nativePair:{authorize:authorizePair,claimCustody,requestId:command.requestId,replace:command.replace}})(
   {pairing_code:command.pairingCode,installation_id:actor.installationId});
 }
 async retire(actor,command,fingerprint){
  requireThat(hasPhonePinContext(this.db),'session_unavailable',401);
  exactKeys(command,['replacementCode','requestId']);requireRequestId(command.requestId);
  requireThat(/^[a-f0-9]{64}$/.test(command.replacementCode??'')&&
   fingerprint===await sha256('burimunsi.gateway.retire.v1:'+await sha256(command.replacementCode)+':'+command.requestId.toLowerCase()),'invalid_pairing_code',400);
  // The ordinary native proof is required exactly once before this write.
  // Retirement intentionally invalidates that scope version. Only request-work
  // ownership may be checked after it; no new session or target token is made.
  return this.authority.write(async sql=>{
   const current=await this.authority.session(sql,{id:actor.sessionId});
   authorize(current,this.groupId,'records.read',{now:this.clock()});
   requireThat(current.id===actor.id&&current.role==='admin'&&current.installationProfile==='internal_receiver'&&
    current.capabilities.includes('gateway.manage'), 'access_denied',403);
   const canonical=await canonicalManagedActor(this.authority,sql);
   requireThat(canonical.authMethod==='phone_pin'&&canonical.userId===current.principalUserId&&canonical.sessionId===current.sessionId,'access_denied',403);
   // SQL33 locks scope first, then performs the real receivers.manage/fresh
   // native assertion. An earlier mutation guard would take shared scope locks
   // and create a conflicting lock upgrade for simultaneous retirements.
   let rows;
   try{rows=await this.query(sql,'SELECT private.burimunsi_gateway_retire($1,$2,$3::uuid,$4) AS result',
     [this.groupId,command.replacementCode,command.requestId,fingerprint]);}
   catch(error){if(error?.code==='42501')throw new BuriError('gateway_changed',409);throw error;}
   const result=rows.length===1?rows[0].result:null;
   exactKeys(result,['retired','handoffId','requestId','reauthenticationRequired']);
   requireThat(result.retired===true&&result.reauthenticationRequired===true&&result.requestId===command.requestId,'gateway_outcome_inconsistent',503);
   requireRequestId(result.handoffId);await this.owned();return result;
  });
 }
 withAuthorityTransaction(fn){return this.run(true,fn);}
 async run(write,fn){
  requireThat(typeof fn==='function','collect_adapter_required',503);
  if(write){
   // A replacement would revoke the working credential before delivering its
   // new pairing challenge. Neither protected delivery nor a public status-only
   // recovery contract is commissioned. Refuse BEFORE entering any SQL callback,
   // locking/writing business rows, generating secrets or retaining a receipt.
   await this.owned();throw new BuriError('gateway_handoff_unavailable',503);
  }
  return this.authority[write?'write':'read'](async sql=>{
   let actor=null,canonical=null,initial=null,locked=null,approved=null;
   const current=()=>{requireThat(actor,'session_unavailable',401);return actor;};
   const ops={
    reloadActor:async id=>{
     const next=await this.authority.session(sql,{id});
     authorize(next,this.groupId,write?'staff.manage':'records.read',{now:this.clock()});
     requireThat(next.role==='admin'&&next.principalSessionId,'access_denied',403);
     if(write){canonical=await canonicalManagedActor(this.authority,sql);
      requireThat(canonical.userId===next.principalUserId&&canonical.sessionId===next.principalSessionId,'access_denied',403);await this.guard(sql,canonical);
     }else{
      const permission=await this.query(sql,hasPhonePinContext(this.db)?
       `SELECT principal_user_id,native_session_id AS principal_session_id,shared_role FROM private.burimunsi_pin_context()
        WHERE role='admin' AND 'gateway.manage'=ANY(capabilities)`:GATEWAY_READ_PERMISSION_SQL,[...(hasPhonePinContext(this.db)?[]:[next.principalUserId,next.principalSessionId])]);
      requireThat(permission.length===1&&permission[0].principal_user_id===next.principalUserId&&
       permission[0].principal_session_id===next.principalSessionId&&['owner','admin'].includes(permission[0].shared_role),'access_denied',403);
     }
     if(initial)requireThat(initial===identity(next),'access_denied',403);
     actor=next;initial??=identity(next);return next;
    },
    loadBinding:async group=>{this.scope(group);const row=await this.binding(sql),a=current();
     requireThat(row.owner_user_id===a.principalUserId&&row.credential_id&&row.revoked_at===null,'gateway_unavailable',409);
     return {id:row.binding_id,groupId:group,installationId:row.installation_id,active:true};
    },
    gatewayHealth:async(group,id)=>{this.scope(group);const row=await this.binding(sql);
     requireThat(row.binding_id===id&&row.owner_user_id===current().principalUserId&&row.credential_id&&row.revoked_at===null,'gateway_unavailable',409);
     const uploaded=await this.query(sql,`SELECT max(g.created_at) AS last_upload FROM app.momo_gateway_captures g
      JOIN app.momo_gateway_credentials c ON c.id=g.credential_id WHERE c.binding_id=$1`,[id]);
     return {pending:integer(row.pending_count),oldest:time(row.oldest_pending_at),lastCapture:time(row.last_sms_at),
      lastUpload:time(uploaded[0]?.last_upload??null),lastContact:time(row.last_contact_at),problem:'gateway_upload_held'};
    },
    lockScope:async group=>{this.scope(group);requireThat(write,'access_denied',403);
     const scopes=await this.query(sql,'SELECT collection_id FROM private.burimunsi_scopes WHERE collection_id=$1 FOR UPDATE',[group]);
     requireThat(scopes.length===1,'gateway_unavailable',409);locked=await this.binding(sql);
     requireThat(locked.owner_user_id===current().principalUserId,'access_denied',403);
     return {activeBindingId:locked.binding_id,bindingVersion:positive(locked.binding_version),receivingAccountId:locked.receiving_account_id,version:positive(locked.scope_version)};
    },
    approvedInstallation:async(group,installationId)=>{this.scope(group);requireRequestId(installationId);
     const rows=await this.query(sql,`SELECT d.id,d.installation_id,d.profile,d.active,d.version,d.custodian_account_id
      FROM private.burimunsi_device_grants d JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.collection_id=d.collection_id
       AND da.account_id=d.custodian_account_id JOIN private.burimunsi_accounts a ON a.id=d.custodian_account_id AND a.collection_id=d.collection_id
      WHERE d.collection_id=$1 AND d.installation_id=$2::uuid AND d.active AND a.active AND NOT a.removed AND a.role='admin'
       AND a.principal_user_id=$3 AND private.burimunsi_operator_is_current(a.collection_id,a.principal_user_id,a.phone,a.role,a.capabilities) LIMIT 2`,
     [group,installationId,current().principalUserId]);
     requireThat(rows.length===1,'installation_not_authorized',403);approved=rows[0];
     return {active:approved.active,profile:approved.profile,custodianAccountId:approved.custodian_account_id};
    },
    retainedCommand:async(group,actorId,requestId)=>{this.scope(group);requireRequestId(requestId);requireThat(actorId===current().id,'access_denied',403);
     const rows=await this.query(sql,`SELECT session_id,fingerprint,response,operation FROM private.burimunsi_command_receipts
      WHERE collection_id=$1 AND actor_id=$2::uuid AND request_id=$3::uuid`,[group,actorId,requestId]);
     requireThat(rows.length<=1,'gateway_outcome_inconsistent',503);if(!rows.length)return null;const row=rows[0];
     requireThat(row.operation===GATEWAY_REPLACEMENT,'idempotency_conflict',409);
     return {sessionId:row.session_id,fingerprint:row.fingerprint,response:gatewayReplacementResponse(row.response)};
    },
    revokeGateway:async(id,version)=>{requireThat(write&&locked?.binding_id===id&&positive(locked.binding_version)===version,'gateway_changed',409);
     await this.statement(sql,this.db.prepare("UPDATE app.momo_gateway_bindings SET status='revoked',revoked_at=? WHERE id=? AND version=? AND status='active'").bind(new Date(canonical.nowMs).toISOString(),id,version));
     await this.query(sql,'UPDATE app.momo_gateway_credentials SET revoked_at=$1 WHERE binding_id=$2 AND revoked_at IS NULL',[new Date(canonical.nowMs).toISOString(),id]);
    },
    activateGateway:async command=>{
     requireThat(write&&locked&&approved&&command.groupId===this.groupId&&command.actorId===current().id&&
      command.previousBindingId===locked.binding_id&&command.receivingAccountId===locked.receiving_account_id&&
      command.expectedScopeVersion===positive(locked.scope_version)&&command.installationId===approved.installation_id&&
      approved.active===true&&approved.profile==='internal_receiver'&&approved.custodian_account_id===current().id,'gateway_changed',409);
     const active=await this.query(sql,"SELECT id FROM app.momo_gateway_bindings WHERE receiving_account_id=$1 AND status='active' LIMIT 1",[locked.receiving_account_id]);
     requireThat(active.length===0,'gateway_changed',409);
     const id=crypto.randomUUID(),pairing=crypto.randomUUID(),challenge=gatewayToken(),stamp=new Date(canonical.nowMs).toISOString();
     const gate=momoGuard({DB:this.db},"EXISTS(SELECT 1 FROM app.momo_receiving_accounts WHERE id=? AND status='active')",[locked.receiving_account_id]);
     await this.statement(sql,gate[0]);
     await this.statement(sql,this.db.prepare(`INSERT INTO app.momo_gateway_bindings(id,owner_user_id,receiving_account_id,subscription_evidence,created_at) VALUES(?,?,?,?,?)`)
      .bind(id,canonical.userId,locked.receiving_account_id,locked.subscription_evidence,stamp));
     // Challenge is not returned or retained in the generic command receipt.
     // Delivery is intentionally uncommissioned; this is control-plane rotation.
     await this.statement(sql,this.db.prepare(`INSERT INTO app.momo_gateway_pairings(id,binding_id,code_sha256,originating_session_id,expires_at,created_at) VALUES(?,?,?,?,?,?)`)
      .bind(pairing,id,await sha256(challenge),canonical.sessionId,canonical.now+600,stamp));
     await this.statement(sql,gate[1]);
     const updated=await this.query(sql,`UPDATE private.burimunsi_scopes SET active_binding_id=$1,binding_version=1,version=version+1
      WHERE collection_id=$2 AND version=$3 AND active_binding_id=$4 AND binding_version=$5 AND enabled RETURNING collection_id`,
     [id,this.groupId,command.expectedScopeVersion,locked.binding_id,positive(locked.binding_version)]);
     requireThat(updated.length===1,'gateway_changed',409);
     return gatewayReplacementResponse({id,installationId:command.installationId,receivingAccountId:locked.receiving_account_id});
    },
    audit:async details=>{requireThat(write&&details.actorId===current().id,'access_denied',403);
     await this.statement(sql,auditStatement({DB:this.db},canonical,'burimunsi.gateway.replaced','momo_binding',details.newBindingId,
      {collection_id:this.groupId,old_binding_id:details.oldBindingId,native_actor_id:current().id,native_session_id:current().sessionId},details.requestId));
    },
    retainCommand:async command=>{this.scope(command.groupId);requireThat(write&&command.actorId===current().id&&command.sessionId===current().sessionId,'access_denied',403);
     requireRequestId(command.requestId);requireThat(/^[a-f0-9]{64}$/.test(command.fingerprint),'gateway_contract_violation',503);
     await this.query(sql,`INSERT INTO private.burimunsi_command_receipts(collection_id,actor_id,request_id,session_id,operation,fingerprint,response,created_at)
      VALUES($1,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7::jsonb,$8)`,
     [this.groupId,command.actorId,command.requestId,command.sessionId,GATEWAY_REPLACEMENT,command.fingerprint,gatewayReplacementResponse(command.response),canonical.nowMs]);
    }
   };
   const result=await fn(Object.freeze(ops));
   requireThat(actor,'session_unavailable',401);await ops.reloadActor(actor.sessionId);
   return result;
  });
 }
 // Retained history helper only, deliberately not mounted as a generic native
 // recovery route. The unavailable writer above creates no new uncertain commit.
 async replacementOutcome(selector,requestId){
  requireRequestId(selector?.id);requireRequestId(selector?.sessionId);requireRequestId(requestId);
  return this.authority.read(async sql=>{
   requireThat((await this.query(sql,'SELECT pg_is_in_recovery() AS replica'))[0]?.replica===false,'command_primary_required',503);
   const actor=await this.authority.session(sql,{id:selector.sessionId});authorize(actor,this.groupId,'records.read',{now:this.clock()});
   requireThat(actor.id===selector.id,'session_unavailable',401);
   const outcome=await readGatewayReplacementOutcome(sql,{groupId:this.groupId,actorId:actor.id,requestId,principalUserId:actor.principalUserId});
   await this.owned();return outcome??{groupId:this.groupId,actorId:actor.id,requestId,state:'pending',financialState:'unresolved'};
  });
 }
}

// The existing anonymous pairing protocol is a secret code plus an exact
// approved installation. Existing shared owner/session/fresh-email authority is
// proved from server rows, never manufactured as the caller's JWT/native actor.
export const CANONICAL_PAIR_SQL=`SELECT p.*,b.owner_user_id,b.receiving_account_id,b.version AS binding_version,
 b.subscription_evidence,b.created_at AS binding_created_at,a.provider,a.public_code,a.recipient_name,a.currency,a.timezone
 FROM app.momo_gateway_pairings p JOIN app.momo_gateway_bindings b ON b.id=p.binding_id
 JOIN app.momo_receiving_accounts a ON a.id=b.receiving_account_id
 JOIN private.burimunsi_scopes scope ON scope.active_binding_id=b.id AND scope.receiving_account_id=b.receiving_account_id
 WHERE p.code_sha256=$1 AND scope.collection_id=$2 AND scope.enabled AND scope.binding_version=b.version
  AND b.status='active' AND a.status='active' AND p.expires_at>floor(extract(epoch FROM clock_timestamp()))
  AND EXISTS(SELECT 1 FROM app.assisted_sms_current_sessions owner WHERE owner.user_id=b.owner_user_id
   AND owner.auth_session_id=p.originating_session_id AND owner.role IN('owner','admin') AND owner.permission='receivers.manage')
  AND EXISTS(SELECT 1 FROM private.burimunsi_device_grants d
   JOIN private.burimunsi_accounts native ON native.id=d.custodian_account_id AND native.collection_id=d.collection_id
   JOIN private.burimunsi_device_accounts da ON da.grant_id=d.id AND da.account_id=native.id AND da.collection_id=d.collection_id
   WHERE d.collection_id=scope.collection_id AND d.installation_id=$3::uuid AND d.active AND d.profile='internal_receiver'
    AND native.active AND NOT native.removed AND native.role='admin' AND native.principal_user_id=b.owner_user_id
    AND private.burimunsi_operator_is_current(native.collection_id,native.principal_user_id,native.phone,native.role,native.capabilities)) LIMIT 2`;

export const NATIVE_PIN_PAIR_SQL=`SELECT p.*,b.owner_user_id,b.receiving_account_id,b.version AS binding_version,
 b.subscription_evidence,b.created_at AS binding_created_at,a.provider,a.public_code,a.recipient_name,a.currency,a.timezone
 FROM app.momo_gateway_pairings p JOIN app.momo_gateway_bindings b ON b.id=p.binding_id
 JOIN app.momo_receiving_accounts a ON a.id=b.receiving_account_id
 JOIN private.burimunsi_scopes scope ON scope.active_binding_id=b.id AND scope.receiving_account_id=b.receiving_account_id
 JOIN private.burimunsi_pin_context() native ON native.collection_id=scope.collection_id AND native.principal_user_id=b.owner_user_id
 JOIN private.burimunsi_device_grants d ON d.id=native.grant_id AND d.collection_id=scope.collection_id
 WHERE p.code_sha256=$1 AND scope.collection_id=$2 AND scope.enabled AND scope.binding_version=b.version
  AND b.status='active' AND a.status='active' AND p.expires_at>floor(extract(epoch FROM clock_timestamp()))
  AND native.installation_id=$3::uuid AND native.role='admin' AND native.profile='internal_receiver'
  AND 'gateway.manage'=ANY(native.capabilities) AND d.custodian_account_id=native.account_id AND d.active LIMIT 2`;
export const PAIR_TARGET_SQL='SELECT private.burimunsi_gateway_pair_target($1,$2::uuid) AS allowed';
export const NATIVE_PIN_CUSTODY_SQL=`SELECT private.burimunsi_pin_claim_custody($1,c.grant_id,c.account_id) AS result
 FROM private.burimunsi_pin_context() c WHERE c.native_session_id=$2::uuid AND c.installation_id=$3::uuid AND c.account_id=$4::uuid`;

/** Construct during admitted canonical route assembly, then invoke only for the
 * configured Buri scope's existing pairing code. No route or upload hold is
 * installed here. Root owns mounting into momoGatewayRoute. */
export function createCanonicalGatewayPair({env,groupId,nativePair=null}){
 requireId(groupId);const authority=new PostgresNativeAuthority({db:env?.DB,groupId});
 requirePort(env.DB,['prepare','statement']);
 const db=env.DB,owned=async()=>{requireThat(env.DB===db,'request_not_admitted',503);await authority.assertOwned();};
 const read=async(sql,text,values=[])=>{await owned();const result=await sql.unsafe(text,values);await owned();return result;};
 const select=async(sql,digest,installation,rawCode,recovering=false)=>{
  if(nativePair)await nativePair.authorize(sql,{readOnly:recovering});
  // This gate also covers the reachable legacy pairing surface. SQL33 codes
  // require the exact target's current four-proof native context there too.
  const target=await read(sql,PAIR_TARGET_SQL,[rawCode,installation]);
  requireThat(target.length===1&&target[0].allowed===true,'pairing_unavailable',401);
  // Custody is claimed only by the exact selected native target, after the raw
  // code guard, within this same write transaction. Historical reconciliation
  // executes SELECTs only and never claims/reissues anything.
  if(nativePair&&!recovering)await nativePair.claimCustody(sql);
  const rows=await read(sql,nativePair?NATIVE_PIN_PAIR_SQL:CANONICAL_PAIR_SQL,[digest,groupId,installation]);
  requireThat(rows.length===1,'pairing_unavailable',401);const row=rows[0];
  const active=await read(sql,"SELECT id FROM app.momo_gateway_bindings WHERE receiving_account_id=$1 AND status='active' ORDER BY id LIMIT 2",[row.receiving_account_id]);
  requireThat(active.length===1&&active[0].id===row.binding_id,'gateway_changed',409);
  requireThat(row.claimed_installation_id===null||row.claimed_installation_id===installation,'pairing_claimed',409);return row;
 };
 const credential=async(sql,row,installation)=>{
  const rows=await read(sql,'SELECT * FROM app.momo_gateway_credentials WHERE pairing_id=$1',[row.id]);
  requireThat(rows.length<=1,'gateway_data_unavailable',503);if(!rows.length)return null;const prior=rows[0];
  requireThat(prior.binding_id===row.binding_id&&prior.installation_id===installation&&prior.revoked_at===null&&row.claimed_installation_id===installation,'pairing_claimed',409);
  const secret=dec.decode(await decrypt(env,prior.token_ciphertext,`momo-gateway:${prior.id}`));
  requireThat(/^[a-f0-9]{64}$/.test(secret)&&await sha256(secret)===prior.token_sha256,'gateway_data_unavailable',503);
  // The receiving app requires the Buri scope extension. groupId is the exact
  // server-selected scope revalidated by CANONICAL_PAIR_SQL, never request JSON.
  await owned();return {binding:{...bindingJson(row),collection_id:groupId},gateway_token:secret};
 };
 return async body=>{
  exactKeys(body,['pairing_code','installation_id']);requireRequestId(body.installation_id);
  requireThat(typeof body.pairing_code==='string'&&/^[a-f0-9]{64}$/.test(body.pairing_code),'invalid_pairing_code',400);
  const digest=await sha256(body.pairing_code),installation=body.installation_id;
  try{return await authority.write(async sql=>{
   const row=await select(sql,digest,installation,body.pairing_code),prior=await credential(sql,row,installation);if(prior)return prior;
   requireThat(row.claimed_installation_id===null,'pairing_claimed',409);
   const id=crypto.randomUUID(),secret=gatewayToken(),cipher=await encrypt(env,enc.encode(secret),`momo-gateway:${id}`);
   const stamp=await read(sql,"SELECT to_char(clock_timestamp() AT TIME ZONE 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS.MS\"Z\"') AS at");
   const statement=async st=>{await owned();const out=await db.statement(sql,st);await owned();requireThat(out?.success===true&&out.meta?.changes===1,'pairing_changed',409);};
   await statement(db.prepare('UPDATE app.momo_gateway_pairings SET claimed_installation_id=? WHERE id=? AND claimed_installation_id IS NULL').bind(installation,row.id));
   await statement(db.prepare(`INSERT INTO app.momo_gateway_credentials(id,binding_id,pairing_id,installation_id,token_sha256,token_ciphertext,created_at,last_contact_at) VALUES(?,?,?,?,?,?,?,?)`)
    .bind(id,row.binding_id,row.id,installation,await sha256(secret),cipher,time(stamp[0]?.at),time(stamp[0]?.at)));
   if(nativePair){
    const canonical=await nativePair.authorize(sql);
    await statement(auditStatement({DB:db},canonical,nativePair.replace?'burimunsi.gateway.repaired':'burimunsi.gateway.paired',
     'momo_binding',row.binding_id,{collection_id:groupId,installation_id:installation,receiving_account_id:row.receiving_account_id},nativePair.requestId));
   }
   const current=await select(sql,digest,installation,body.pairing_code);return credential(sql,current,installation);
  });}catch(error){
   if(error instanceof BuriError&&error.status<500)throw error;
   // The existing owner-proof view takes row locks. Reconcile in the same
   // fenced/global-lock transaction mode, but execute SELECTs only: no claim,
   // credential INSERT, heartbeat, guard write or recursive pair retry.
   try{return await authority.write(async sql=>{
    const row=await select(sql,digest,installation,body.pairing_code,true),prior=await credential(sql,row,installation);
    requireThat(prior,'gateway_pairing_unconfirmed',503);return prior;
   });}catch{throw new BuriError('gateway_pairing_unconfirmed',503);}
  }
 };
}
