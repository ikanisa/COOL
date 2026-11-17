import {canonicalManagedActor} from './postgres-managed-actor.js';
import {requirePort,requireThat,BuriError} from './errors.js';
import {requireId,requireRequestId,canonicalJson} from './values.js';
import {authorize} from './policy.js';
import {automaticWork} from './automatic-work.js';

const PHASES=new Set(['before_preparation','after_preparation_source','before_preparation_storage',
  'after_preparation_storage','before_allocation','after_allocation','before_posting','after_posting']);
const copy=value=>{
  const result=JSON.parse(canonicalJson(value));
  const freeze=v=>{if(v&&typeof v==='object'){Object.values(v).forEach(freeze);Object.freeze(v);}return v;};
  return freeze(result);
};

/** Native financial authority on the caller's ALREADY admitted SQL connection.
 * Requires BOTH a valid scoped native session AND the existing canonical managed
 * session for the SAME app.users principal. Resolves the latter via Collect's
 * SQL helpers, never a client claim, actor JSON, copied native ID or a new session.
 * Existing mutation guards retain their permission/assurance/freshness checks.
 * This is not a PIN-to-managed-session exchange or a worker service credential.
 * Missing canonical context refuses posting. It never creates credentials,
 * elevates a role, replaces JWT claims or starts a transaction.
 */
export class PostgresPostingAuthority {
  constructor({authority,workerRuntime=null}) {
    requirePort(authority,['session','assertOwned']);requireId(authority.groupId);
    requirePort(authority.db,['prepare','statement']);
    requireThat(workerRuntime===null||typeof workerRuntime?.assertInTransaction==='function','collect_adapter_required',503);
    this.authority=authority;this.groupId=authority.groupId;this.db=authority.db;this.workerRuntime=workerRuntime;
  }
  async owned(){await this.authority.assertOwned();}
  async canonical(sql){return canonicalManagedActor(this.authority,sql);}
  async native(sql,cmd,canonical){
    const actor=await this.authority.session(sql,{id:cmd.sessionId,now:canonical.nowMs});
    await this.owned();authorize(actor,this.groupId,'payments.allocate',{now:canonical.nowMs});
    requireThat(actor.id===cmd.actorId&&actor.sessionId===cmd.sessionId&&actor.principalUserId===cmd.actor?.principalUserId&&
      actor.principalUserId===canonical.userId,'posting_principal_mismatch',403);
    return copy({id:actor.id,sessionId:actor.sessionId,principalUserId:actor.principalUserId,role:actor.role,
      installationId:actor.installationId??null,installationProfile:actor.installationProfile??null,
      capabilities:[...actor.capabilities].sort()});
  }
  async guard(sql,cmd,canonical){
    // Same mutation_guards contract used by Collect financial commands. Do not
    // weaken this to native capability alone or mark a synthetic reviewer.
    const guardId=crypto.randomUUID();
    const insert=this.db.prepare(`INSERT INTO app.mutation_guards
      (id,user_id,session_id,now_seconds,collection_id,permission,minimum_assurance,expected_mfa_at,fresh_seconds,recipient_user_id,recipient_collection_id)
      VALUES(?,?,?,?,?,?,?,?,?,?,?)`).bind(guardId,canonical.userId,canonical.sessionId,canonical.now,
        this.groupId,'payments.reconcile',canonical.authMethod==='phone_pin'?null:2,canonical.mfa,300,cmd.memberId,this.groupId);
    const remove=this.db.prepare('DELETE FROM app.mutation_guards WHERE id=?').bind(guardId);
    for(const statement of [insert,remove]){
      await this.owned();let result;
      try{result=await this.db.statement(sql,statement);}catch{throw new BuriError('posting_financial_authority_denied',403);}
      await this.owned();requireThat(result?.success===true&&result.meta?.changes===1,'posting_financial_authority_denied',403);
    }
  }
  async assertInTransaction(sql,{command,phase}){
    requirePort(sql,['unsafe']);requireThat(PHASES.has(phase),'posting_phase_invalid',503);
    const cmd=copy(command);
    requireThat(cmd?.groupId===this.groupId&&['exception','automatic'].includes(cmd.mode),'access_denied',403);
    requireId(cmd.receiptId);requireId(cmd.memberId);requireRequestId(cmd.requestId);
    await this.owned();
    if(cmd.mode==='automatic'){
      automaticWork(cmd.work);
      requireThat(this.workerRuntime!==null,'worker_financial_authority_required',503);
      const result=await this.workerRuntime.assertInTransaction(sql,{command:cmd,phase});
      await this.owned();
      requireThat(result?.kind==='admitted_worker'&&result.contractVersion===1&&result.groupId===this.groupId&&
        result.receiptId===cmd.receiptId&&result.requestId===cmd.requestId&&result.mode==='automatic'&&
        result.policyVersion===cmd.policyVersion,'worker_financial_authority_required',503);
      requireId(result.actorId);requireRequestId(result.sessionId);requireId(result.principalUserId);requireRequestId(result.principalSessionId);
      return copy(result);
    }
    requireRequestId(cmd.actorId);requireRequestId(cmd.sessionId);
    const canonical=await this.canonical(sql),actor=await this.native(sql,cmd,canonical);
    await this.guard(sql,cmd,canonical);
    // Never return a stale proof after an awaited SQL/guard/native-session read.
    const final=await this.canonical(sql),native=await this.native(sql,cmd,final);
    requireThat(final.nowMs>=canonical.nowMs&&final.userId===canonical.userId&&final.sessionId===canonical.sessionId&&final.mfa===canonical.mfa&&
      canonicalJson(actor)===canonicalJson(native),'posting_authority_changed',409);
    await this.owned();
    return Object.freeze({contractVersion:1,kind:'native_operator',mode:'exception',groupId:this.groupId,
      receiptId:cmd.receiptId,requestId:cmd.requestId,actorId:actor.id,sessionId:actor.sessionId,
      principalUserId:canonical.userId,principalSessionId:canonical.sessionId});
  }
}
