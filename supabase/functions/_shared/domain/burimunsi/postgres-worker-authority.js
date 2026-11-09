import {requirePort,requireThat} from './errors.js';
import {requireId,requireRequestId,canonicalJson} from './values.js';
import {automaticWork} from './automatic-work.js';
import {PostgresPostingAuthority} from './postgres-posting-authority.js';
import {pgInteger} from './postgres-values.js';
const PHASES=new Set(['before_preparation','after_preparation_source','before_preparation_storage',
 'after_preparation_storage','before_allocation','after_allocation','before_posting','after_posting']);

/** Real managed principal + explicit approved grant + branded jobs fence +
 * durable job lease + UNCHANGED canonical permission/assurance/freshness guard.
 * This is not a service credential issuer or permission to impersonate an admin.
 */
export class PostgresWorkerAuthority {
  constructor({authority,jobs,applicationWorkTuple}) {
    requirePort(authority,['session','assertOwned']);requirePort(jobs,['assertPostingLease']);
    requireThat(typeof applicationWorkTuple==='function','collect_adapter_required',503);
    this.authority=authority;this.db=authority.db;this.groupId=authority.groupId;this.jobs=jobs;
    this.applicationWorkTuple=applicationWorkTuple;this.work=this.db.applicationWork;
    this.context=new PostgresPostingAuthority({authority});
    this.tuple=Object.freeze([...applicationWorkTuple(this.work)]);
    requireThat(this.work.kind==='jobs'&&this.tuple.length===3&&/^[a-f0-9]{64}$/.test(this.tuple[2]),'worker_admission_required',503);
    requireRequestId(this.tuple[0]);requireThat(Number.isSafeInteger(this.tuple[1])&&this.tuple[1]>0,'worker_admission_required',503);
  }
  async owned() {
    await this.authority.assertOwned();
    requireThat(this.db.applicationWork===this.work&&this.work.kind==='jobs'&&
      canonicalJson(this.applicationWorkTuple(this.work))===canonicalJson(this.tuple),'worker_admission_required',503);
  }
  async grant(sql,cmd,canonical) {
    await this.owned();const rows=await sql.unsafe(`SELECT g.*,
      floor(extract(epoch FROM clock_timestamp())*1000)::text AS now_ms
      FROM private.burimunsi_worker_grants g JOIN private.burimunsi_integration_policies p USING(collection_id)
      JOIN private.burimunsi_scopes s USING(collection_id)
      WHERE g.collection_id=$1 AND g.owner=$2 AND g.enabled AND s.enabled
       AND p.processing_enabled AND p.revoked_at IS NULL AND p.approved_version=g.policy_version
       AND p.approved_at<=floor(extract(epoch FROM clock_timestamp())*1000)
       AND p.expires_at>floor(extract(epoch FROM clock_timestamp())*1000) FOR SHARE OF g,p,s`,[this.groupId,cmd.work.owner]);
    await this.owned();requireThat(rows.length===1,'worker_financial_authority_required',403);const g=rows[0];
    requireThat(g.principal_user_id===canonical.userId&&g.principal_session_id===canonical.sessionId&&
      g.source_sha256===this.tuple[2]&&g.policy_version===cmd.policyVersion&&g.revoked_at===null&&
      pgInteger(g.approved_at,{minimum:0})<=pgInteger(g.now_ms,{minimum:0})&&
      pgInteger(g.expires_at,{minimum:0})>pgInteger(g.now_ms,{minimum:0}),'worker_financial_authority_required',403);
    requireThat(Array.isArray(g.work_kinds)&&g.work_kinds.includes(cmd.work.kind),'worker_financial_authority_required',403);
    return canonicalJson([g.id,g.version,g.principal_user_id,g.principal_session_id,g.source_sha256,g.policy_version,g.expires_at,g.work_kinds]);
  }
  async assertInTransaction(sql,{command,phase}) {
    const cmd=JSON.parse(canonicalJson(command));cmd.work=automaticWork(cmd.work);
    requireThat(PHASES.has(phase)&&cmd.mode==='automatic'&&cmd.groupId===this.groupId,'worker_admission_required',503);
    requireId(cmd.receiptId);requireId(cmd.memberId);requireRequestId(cmd.requestId);
    if(cmd.work.kind==='rematch')requireThat(cmd.work.memberId===cmd.memberId&&cmd.work.policyVersion===cmd.policyVersion,'identity_changed',409);
    await this.owned();const before=await this.context.canonical(sql),grant=await this.grant(sql,cmd,before);
    const lease={groupId:this.groupId,transactionId:cmd.receiptId,work:cmd.work};
    await this.jobs.assertPostingLease(sql,lease);
    await this.context.guard(sql,cmd,before);
    const after=await this.context.canonical(sql);
    requireThat(after.userId===before.userId&&after.sessionId===before.sessionId&&after.mfa===before.mfa&&after.nowMs>=before.nowMs,
      'posting_authority_changed',409);
    requireThat(await this.grant(sql,cmd,after)===grant,'posting_authority_changed',409);
    await this.jobs.assertPostingLease(sql,lease);await this.owned();
    return Object.freeze({contractVersion:1,kind:'admitted_worker',mode:'automatic',groupId:this.groupId,
      receiptId:cmd.receiptId,requestId:cmd.requestId,policyVersion:cmd.policyVersion,actorId:after.userId,sessionId:after.sessionId,
      principalUserId:after.userId,principalSessionId:after.sessionId});
  }
}
