import {requirePort,requireThat} from './errors.js';
import {requireId,requireRequestId,sha256,canonicalJson} from './values.js';
import {pgInteger} from './postgres-values.js';
import {automaticWork} from './automatic-work.js';

const TABLE='private.burimunsi_rematch_jobs';
const n=(v,min=0)=>pgInteger(v,{minimum:min,code:'invalid_rematch_job'});
const REASONS=new Set(['policy_unavailable','scope_mismatch','identity_data_unavailable','masked_identity','invalid_time',
  'invalid_identity','ambiguous_identity','no_verified_identity','member_ineligible','different_member',
  'transaction_conflict','transaction_reversed','already_posted']);
const ERRORS=new Set(['processing_on_hold','profile_changed','scope_unavailable','lease_unavailable','transaction_unavailable',
  'identity_changed','source_scope_changed','record_unavailable','rematch_outcome_missing','job_exhausted']);
const safeCode=code=>ERRORS.has(code)?code:'processing_unavailable';
const resultKind=r=>r?.state==='unallocated'?'unallocated':r?.state==='skipped'?'skipped':r?.ledgerEntryId?'posted':null;
export async function rematchRequestId(groupId,jobId,transactionId) {
  requireId(groupId);requireRequestId(jobId);requireId(transactionId);
  const h=await sha256(canonicalJson(['burimunsi.rematch.v1',groupId,jobId,transactionId]));
  return `${h.slice(0,8)}-${h.slice(8,12)}-8${h.slice(13,16)}-${((parseInt(h[16],16)&3)|8).toString(16)}${h.slice(17,20)}-${h.slice(20,32)}`;
}
function project(r) {
  if(!r)return null;
  return Object.freeze({id:r.id,groupId:r.collection_id,receivingAccountId:r.receiving_account_id,memberId:r.member_id,
    requestId:r.request_id,cause:r.cause,cutoffAt:n(r.cutoff_at),after:r.after_transaction_id,
    targetId:r.target_transaction_id??null,targetOutcome:r.target_outcome??null,targetReason:r.target_reason??null,
    policyVersion:r.policy_version??null,owner:r.lease_owner??null,leaseVersion:n(r.lease_version),
    leaseExpiresAt:r.lease_expires_at==null?null:n(r.lease_expires_at),attempt:n(r.attempt),maxAttempts:n(r.max_attempts,4),
    processedCount:n(r.processed_count),leaseStartCount:n(r.lease_start_count),state:r.state});
}

/** Durable scheduling metadata, never proof of phone ownership or a second
 * ledger. All writes use the current Collect transaction/fence/locking context.
 * The mandatory admission bridge must retain the processing hold and approved
 * identity-policy authority through this same SQL transaction. */
export class PostgresRematchJobStore {
  constructor({authority,admission,canonical,maxAttempts=4}) {
    requirePort(authority,['write']);requireId(authority.groupId);
    requirePort(admission,['assertInTransaction']);requirePort(canonical,['outcome']);
    requireThat(Number.isInteger(maxAttempts)&&maxAttempts>=4&&maxAttempts<=10,'invalid_worker_config',503);
    Object.assign(this,{authority,admission,canonical,maxAttempts});this.groupId=authority.groupId;
  }
  group(g){requireThat(g===this.groupId,'access_denied',403);}
  async time(tx){return n((await tx.unsafe('SELECT floor(extract(epoch FROM clock_timestamp())*1000)::text AS now_ms'))[0]?.now_ms);}
  async scope(tx,{allowDisabled=false}={}) {
    const rows=await tx.unsafe(`SELECT collection_id,receiving_account_id,enabled FROM private.burimunsi_scopes WHERE collection_id=$1 FOR UPDATE`,[this.groupId]);
    requireThat(rows.length===1&&rows[0].collection_id===this.groupId&&(allowDisabled||rows[0].enabled===true),'scope_unavailable',503);
    requireId(rows[0].receiving_account_id);return rows[0];
  }
  async admitted(tx,job=null) {
    const a=await this.admission.assertInTransaction(tx,{kind:'rematch',groupId:this.groupId,job});
    requireThat(a?.processingEnabled===true,'processing_on_hold',503);
    requireThat(typeof a.policyVersion==='string'&&a.policyVersion.length>=1&&a.policyVersion.length<=128&&
      !/[\u0000-\u001f\u007f]/.test(a.policyVersion),'profile_changed',409);
    if(job)requireThat(a.policyVersion===job.policyVersion,'profile_changed',409);
    return a;
  }
  /** Enqueue in the member command's existing transaction, even under a worker
   * pause. A replay keeps the original cutoff and never broadens old authority. */
  async enqueueInTransaction(tx,{groupId,memberId,requestId,cause='enrollment'}) {
    requirePort(tx,['unsafe']);this.group(groupId);requireId(memberId);requireRequestId(requestId);
    requireThat(['enrollment','reactivation','verified_identity'].includes(cause),'invalid_rematch_event',503);
    const scope=await this.scope(tx,{allowDisabled:true});
    const members=await tx.unsafe(`SELECT m.user_id,m.active,u.access_status FROM app.memberships m JOIN app.users u ON u.id=m.user_id
      WHERE m.collection_id=$1 AND m.user_id=$2 FOR UPDATE OF m,u`,[groupId,memberId]);
    requireThat(members.length===1&&members[0].user_id===memberId&&n(members[0].active)===1&&members[0].access_status==='active','member_unavailable',409);
    const now=await this.time(tx);
    await tx.unsafe(`INSERT INTO ${TABLE}(id,collection_id,receiving_account_id,member_id,request_id,cause,cutoff_at,created_at,updated_at,next_attempt_at,max_attempts)
      VALUES($1::uuid,$2,$3,$4,$5::uuid,$6,$7,$7,$7,$7,$8) ON CONFLICT(collection_id,request_id) DO NOTHING`,
      [crypto.randomUUID(),groupId,scope.receiving_account_id,memberId,requestId,cause,now,this.maxAttempts]);
    const rows=await tx.unsafe(`SELECT * FROM ${TABLE} WHERE collection_id=$1 AND request_id=$2::uuid FOR UPDATE`,[groupId,requestId]);
    requireThat(rows.length===1,'invalid_rematch_job',503);const job=project(rows[0]);
    requireThat(job.groupId===groupId&&job.requestId===requestId&&job.memberId===memberId&&job.receivingAccountId===scope.receiving_account_id&&job.cause===cause,'idempotency_conflict',409);
    return {durable:true,jobId:job.id,state:job.state};
  }
  async claimNext({groupId,owner,leaseMs=180000}) {
    this.group(groupId);requireId(owner);
    requireThat(Number.isInteger(leaseMs)&&leaseMs>=30000&&leaseMs<=600000,'invalid_worker_config',503);
    return this.authority.write(async tx=>{
      await this.scope(tx);const a=await this.admitted(tx);let now=await this.time(tx);
      await tx.unsafe(`WITH exhausted AS (SELECT id FROM ${TABLE} WHERE collection_id=$1 AND attempt>=max_attempts
        AND (state IN('queued','retry') OR (state='running' AND lease_expires_at<=$2)) FOR UPDATE SKIP LOCKED)
        UPDATE ${TABLE} j SET state='dead_letter',lease_owner=NULL,lease_expires_at=NULL,last_error='job_exhausted',updated_at=$2
        FROM exhausted e WHERE j.id=e.id`,[groupId,now]);
      now=await this.time(tx);
      const rows=await tx.unsafe(`WITH candidate AS (SELECT id FROM ${TABLE} WHERE collection_id=$1 AND attempt<max_attempts
        AND ((state IN('queued','retry') AND next_attempt_at<=$2) OR (state='running' AND lease_expires_at<=$2))
        ORDER BY next_attempt_at,created_at,id LIMIT 1 FOR UPDATE SKIP LOCKED)
        UPDATE ${TABLE} j SET state='running',lease_owner=$3,lease_version=j.lease_version+1,lease_expires_at=$2+$4,
          attempt=j.attempt+1,policy_version=$5,lease_start_count=j.processed_count,updated_at=$2
        FROM candidate c WHERE j.id=c.id AND j.collection_id=$1 RETURNING j.*`,[groupId,now,owner,leaseMs,a.policyVersion]);
      requireThat(rows.length<=1,'invalid_rematch_job',503);return project(rows[0]);
    });
  }
  async locked(tx,{jobId,owner,leaseVersion},admit=true) {
    requireRequestId(jobId);requireId(owner);requireThat(Number.isSafeInteger(leaseVersion)&&leaseVersion>0,'lease_unavailable',409);
    const scope=await this.scope(tx);
    const rows=await tx.unsafe(`SELECT * FROM ${TABLE} WHERE collection_id=$1 AND id=$2::uuid FOR UPDATE`,[this.groupId,jobId]);
    requireThat(rows.length<=1,'invalid_rematch_job',503);const job=project(rows[0]),now=await this.time(tx);
    requireThat(job&&job.id===jobId&&job.groupId===this.groupId&&job.state==='running'&&job.owner===owner&&job.leaseVersion===leaseVersion&&job.leaseExpiresAt>now,'lease_unavailable',409);
    requireThat(job.receivingAccountId===scope.receiving_account_id,'source_scope_changed',409);
    if(admit) {
      await this.admitted(tx,job);
      requireThat(job.leaseExpiresAt>await this.time(tx),'lease_unavailable',409);
    }
    return job;
  }
  async nextTarget(witness) {
    return this.authority.write(async tx=>{
      const job=await this.locked(tx,witness);
      if(job.targetId)return {transactionId:job.targetId,outcome:job.targetOutcome,reason:job.targetReason};
      // Fixed database cutoff, immutable scope creation time and C-collated ID
      // cursor. Do not paginate by mutable payer names, amounts or statuses.
      const rows=await tx.unsafe(`SELECT t.id FROM private.burimunsi_transaction_scopes x
        JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
        WHERE x.collection_id=$1 AND x.receiving_account_id=$2 AND x.created_at<=$3
          AND t.id COLLATE "C">$4 COLLATE "C" AND t.event_kind='incoming_receipt' AND t.currency='RWF'
          AND t.has_conflict=0 AND t.allocation_state='unallocated'
        ORDER BY t.id COLLATE "C" LIMIT 1 FOR UPDATE OF x,t`,[this.groupId,job.receivingAccountId,job.cutoffAt,job.after]);
      const now=await this.time(tx);
      if(!rows.length) {
        const updated=await tx.unsafe(`UPDATE ${TABLE} SET state='completed',lease_owner=NULL,lease_expires_at=NULL,updated_at=$4,last_error=NULL
          WHERE collection_id=$1 AND id=$2::uuid AND lease_owner=$3 AND lease_version=$5 AND state='running' AND lease_expires_at>$4 RETURNING id`,
          [this.groupId,job.id,job.owner,now,job.leaseVersion]);
        requireThat(updated.length===1,'lease_unavailable',409);return null;
      }
      requireThat(rows.length===1,'invalid_rematch_job',503);requireId(rows[0].id);
      const updated=await tx.unsafe(`UPDATE ${TABLE} SET target_transaction_id=$6,updated_at=$4
        WHERE collection_id=$1 AND id=$2::uuid AND lease_owner=$3 AND lease_version=$5 AND state='running' AND lease_expires_at>$4
          AND target_transaction_id IS NULL RETURNING id`,[this.groupId,job.id,job.owner,now,job.leaseVersion,rows[0].id]);
      requireThat(updated.length===1,'lease_unavailable',409);return {transactionId:rows[0].id,outcome:null,reason:null};
    });
  }
  async assertPostingLease(tx,{groupId,transactionId,requestId,work}) {
    this.group(groupId);requireId(transactionId);work=automaticWork(work);
    requireThat(work.kind==='rematch','automatic_work_required',503);
    const job=await this.locked(tx,work);
    requireThat(job.memberId===work.memberId&&job.policyVersion===work.policyVersion&&job.targetId===transactionId&&job.targetOutcome===null,
      'automatic_work_required',503);
    requireThat(requestId===await rematchRequestId(groupId,job.id,transactionId),'automatic_work_required',503);
    return job;
  }
  /** This checkpoint shares the CANONICAL financial transaction. A lost worker
   * reply cannot separate a posted contribution from its rematch disposition. */
  async retainAutomaticOutcome(tx,command) {
    const job=await this.assertPostingLease(tx,command),result=command.result,kind=resultKind(result);
    requireThat(result?.transactionId===command.transactionId&&kind!==null,'rematch_outcome_missing',503);
    const outcome=await this.canonical.outcome(tx,{groupId:this.groupId,transactionId:command.transactionId});
    requireThat(outcome?.groupId===this.groupId&&outcome.transactionId===command.transactionId,'rematch_outcome_missing',503);
    const reason=kind==='posted'?null:result.reason;
    if(kind!=='posted')requireThat(REASONS.has(reason),'rematch_outcome_missing',503);
    if(kind==='posted'||reason==='already_posted') {requireId(outcome.memberId);requireId(outcome.ledgerEntryId);}
    if(kind==='posted')requireThat(outcome.hasConflict===false&&outcome.state==='posted'&&outcome.memberId===job.memberId&&
      result.memberId===job.memberId&&outcome.ledgerEntryId===result.ledgerEntryId,'rematch_outcome_missing',503);
    if(kind==='unallocated')requireThat(outcome.hasConflict===false&&outcome.state==='unallocated','rematch_outcome_missing',503);
    if(kind==='skipped')requireThat((reason==='transaction_conflict'&&outcome.hasConflict===true)||
      (reason==='transaction_reversed'&&outcome.state==='reversed')||
      (reason==='already_posted'&&outcome.state==='posted'&&outcome.hasConflict===false&&outcome.memberId!==job.memberId),'rematch_outcome_missing',503);
    const now=await this.time(tx);
    const rows=await tx.unsafe(`UPDATE ${TABLE} SET target_outcome=$7,target_reason=$8,updated_at=$4
      WHERE collection_id=$1 AND id=$2::uuid AND lease_owner=$3 AND lease_version=$5 AND state='running' AND lease_expires_at>$4
        AND target_transaction_id=$6 AND target_outcome IS NULL RETURNING id`,
        [this.groupId,job.id,job.owner,now,job.leaseVersion,command.transactionId,kind,reason]);
    requireThat(rows.length===1,'lease_unavailable',409);return {durable:true};
  }
  async advanceTarget({...witness}) {
    requireId(witness.transactionId);
    return this.authority.write(async tx=>{
      const job=await this.locked(tx,witness);
      if(job.targetId===null&&job.after===witness.transactionId)return {applied:true,replayed:true};
      requireThat(job.targetId===witness.transactionId&&job.targetOutcome!==null,'rematch_outcome_missing',503);
      const now=await this.time(tx);
      const rows=await tx.unsafe(`UPDATE ${TABLE} SET after_transaction_id=target_transaction_id,target_transaction_id=NULL,
        target_outcome=NULL,target_reason=NULL,processed_count=processed_count+1,attempt=1,last_error=NULL,updated_at=$4
        WHERE collection_id=$1 AND id=$2::uuid AND lease_owner=$3 AND lease_version=$5 AND state='running' AND lease_expires_at>$4 RETURNING id`,
        [this.groupId,job.id,job.owner,now,job.leaseVersion]);
      requireThat(rows.length===1,'lease_unavailable',409);return {applied:true,replayed:false,outcome:job.targetOutcome};
    });
  }
  async yieldJob(witness) {
    return this.authority.write(async tx=>{
      const job=await this.locked(tx,witness);
      requireThat(job.targetId===null&&job.processedCount>job.leaseStartCount,'rematch_progress_required',503);
      const now=await this.time(tx);
      const rows=await tx.unsafe(`UPDATE ${TABLE} SET state='queued',attempt=0,lease_owner=NULL,lease_expires_at=NULL,
        next_attempt_at=$4,updated_at=$4 WHERE collection_id=$1 AND id=$2::uuid AND lease_owner=$3 AND lease_version=$5
        AND state='running' AND lease_expires_at>$4 RETURNING id`,[this.groupId,job.id,job.owner,now,job.leaseVersion]);
      requireThat(rows.length===1,'lease_unavailable',409);return {applied:true};
    });
  }
  async failJob({jobId,owner,leaseVersion,code}) {
    requireRequestId(jobId);requireId(owner);requireThat(Number.isSafeInteger(leaseVersion)&&leaseVersion>0,'lease_unavailable',409);
    return this.authority.write(async tx=>{
      // Lock first, THEN read the clock. A pre-lock clock can authorize cleanup
      // after a lock wait has consumed the lease. Cleanup never lifts a hold.
      const rows=await tx.unsafe(`SELECT * FROM ${TABLE} WHERE collection_id=$1 AND id=$2::uuid FOR UPDATE`,[this.groupId,jobId]);
      requireThat(rows.length<=1,'invalid_rematch_job',503);const job=project(rows[0]),now=await this.time(tx);
      if(!job||job.state!=='running'||job.owner!==owner||job.leaseVersion!==leaseVersion||job.leaseExpiresAt<=now)
        return {applied:false,state:'lease_lost'};
      const updated=await tx.unsafe(`UPDATE ${TABLE} SET state=CASE WHEN attempt>=max_attempts THEN 'dead_letter' ELSE 'retry' END,
        next_attempt_at=$4+least(3600000::bigint,1000::bigint*(1::bigint<<least(attempt,12))),lease_owner=NULL,lease_expires_at=NULL,
        last_error=$6,updated_at=$4 WHERE collection_id=$1 AND id=$2::uuid AND lease_owner=$3 AND lease_version=$5
        AND state='running' AND lease_expires_at>$4 RETURNING state`,[this.groupId,jobId,owner,now,leaseVersion,safeCode(code)]);
      return updated.length===1?{applied:true,state:updated[0].state}:{applied:false,state:'lease_lost'};
    });
  }
}
