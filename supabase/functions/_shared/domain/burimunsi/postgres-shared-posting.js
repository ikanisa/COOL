import {requirePort,requireThat} from './errors.js';
import {requireId,requireRequestId,requireAmount,canonicalJson} from './values.js';
import {pgInteger} from './postgres-values.js';
import {automaticWork} from './automatic-work.js';
import {appendContributionCollision,appendContributionEntry,appendContributionSnapshots} from '../contribution-posting.mjs';

const hash=/^[a-f0-9]{64}$/;
const exact=v=>pgInteger(v,{minimum:0,code:'posting_record_invalid'});
const immutable=value=>{
  const copy=JSON.parse(canonicalJson(value));
  const freeze=v=>{if(v&&typeof v==='object'){Object.values(v).forEach(freeze);Object.freeze(v);}return v;};
  return freeze(copy);
};
// Match only the canonical receiving-route spellings, never arbitrary digit extraction.
function route(v){
  if(typeof v!=='string')return null;
  if(/^07[2389][0-9]{7}$/.test(v))return '250'+v.slice(1);
  if(/^\+?2507[2389][0-9]{7}$/.test(v))return v.replace(/^\+/,'');
  if(/^[0-9]{4,9}$/.test(v))return v;
  return null;
}

/** Transaction-local executor for the REAL shared Collect posting statements.
 * The caller owns rollback/commit and the global Collect mutation lock. The
 * mandatory runtime bridge proves current authority/fence on THIS connection;
 * allocation must use the existing custody-aware allocation commands on it.
 * No connection, transaction, object upload, public route, fabricated reviewer,
 * new ledger or service-role fallback is supplied here. No work during assembly.
 */
export class PostgresSharedPosting {
  constructor({db,groupId,runtime,allocation,evidence}) {
    requireId(groupId);requirePort(db,['prepare','statement']);
    requirePort(db.applicationWork,['assert']);
    requirePort(runtime,['assertInTransaction']);
    requirePort(allocation,['prepareInTransaction']);
    requirePort(evidence,['assertInTransaction']);
    Object.assign(this,{db,groupId,runtime,allocation,evidence,work:db.applicationWork});
  }
  async owned(){
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);
    await this.work.assert();
    requireThat(this.db.applicationWork===this.work,'request_not_admitted',503);
  }
  async authority(sql,cmd,phase,original=null){
    await this.owned();
    const a=await this.runtime.assertInTransaction(sql,{command:cmd,phase});
    await this.owned();
    requireThat(a?.contractVersion===1&&a.groupId===this.groupId&&a.receiptId===cmd.receiptId&&
      a.requestId===cmd.requestId&&a.mode===cmd.mode,'posting_authority_required',503);
    requireId(a.actorId);requireRequestId(a.sessionId);
    requireId(a.principalUserId);requireRequestId(a.principalSessionId);
    if(cmd.mode==='exception')requireThat(a.kind==='native_operator'&&a.actorId===cmd.actorId&&a.sessionId===cmd.sessionId&&a.principalUserId===cmd.actor?.principalUserId,'session_unavailable',401);
    else requireThat(a.kind==='admitted_worker'&&a.policyVersion===cmd.policyVersion,'posting_authority_required',503);
    const binding=immutable({actorId:a.actorId,sessionId:a.sessionId,principalUserId:a.principalUserId,principalSessionId:a.principalSessionId,kind:a.kind,mode:a.mode,groupId:a.groupId,
      receiptId:a.receiptId,requestId:a.requestId,...(cmd.mode==='automatic'?{policyVersion:a.policyVersion}:{})});
    requireThat(original===null||canonicalJson(binding)===canonicalJson(original),'posting_authority_changed',409);
    return binding;
  }
  async record(sql,cmd,paymentId){
    const rows=await sql.unsafe(`SELECT p.*,t.id AS transaction_id,t.version AS transaction_version,
      t.receiving_account_id,t.amount_minor AS source_amount,t.currency AS source_currency,t.provider AS source_provider,
      t.provider_transaction_id,t.event_kind,t.has_conflict,t.allocation_state,t.mode AS source_mode,
      f.beneficiary_member_id,f.historical_existing,
      e.collection_id AS evidence_group,e.amount_minor AS evidence_amount,e.currency AS evidence_currency,
      e.external_reference,e.receiver_network AS evidence_network,e.receiver_momo_number AS evidence_route,
      e.object_key,e.object_sha256,e.size_bytes,
      a.status AS account_status,a.profile_status,a.provider AS account_provider,a.public_code,
      g.status AS group_status,g.receiver_network,g.receiver_momo_number,
      m.active AS membership_active,u.access_status,
      x.source_binding_id,x.source_binding_version,x.policy_version AS scope_policy_version,
      EXISTS(SELECT 1 FROM app.ledger_entries l WHERE l.payment_id=p.id) AS has_entries,
      EXISTS(SELECT 1 FROM app.contribution_posting_snapshots s WHERE s.payment_id=p.id) AS has_snapshot,
      EXISTS(SELECT 1 FROM app.payments other JOIN app.payment_evidence prior ON prior.id=other.evidence_id
        WHERE other.id<>p.id AND prior.receiver_network=a.provider
          AND prior.external_reference IN(t.provider_transaction_id,t.receiving_account_id||':'||t.provider_transaction_id)
          AND (CASE WHEN substr(prior.receiver_momo_number,1,2)='07' AND length(prior.receiver_momo_number)=10
            THEN '250'||substr(prior.receiver_momo_number,2) ELSE replace(prior.receiver_momo_number,'+','') END)=
          (CASE WHEN substr(a.public_code,1,2)='07' AND length(a.public_code)=10
            THEN '250'||substr(a.public_code,2) ELSE replace(a.public_code,'+','') END)) AS has_other_reference
      FROM private.burimunsi_transaction_scopes x
      JOIN private.burimunsi_scopes b ON b.collection_id=x.collection_id AND b.receiving_account_id=x.receiving_account_id AND b.enabled=true
      JOIN app.momo_transactions t ON t.id=x.transaction_id AND t.receiving_account_id=x.receiving_account_id
      JOIN app.momo_financial_links f ON f.transaction_id=t.id
      JOIN app.payments p ON p.id=f.payment_id AND p.collection_id=x.collection_id
      JOIN app.payment_evidence e ON e.id=p.evidence_id
      JOIN app.momo_receiving_accounts a ON a.id=t.receiving_account_id
      JOIN app.collections g ON g.id=p.collection_id
      JOIN app.memberships m ON m.collection_id=g.id AND m.user_id=f.beneficiary_member_id
      JOIN app.users u ON u.id=m.user_id
      WHERE x.collection_id=$1 AND t.id=$2 AND p.id=$3
      FOR UPDATE OF x,b,t,f,p,e,a,g,m,u`,[this.groupId,cmd.receiptId,paymentId]);
    requireThat(rows.length===1,'posting_record_invalid',503);const p=rows[0];
    const receivingRoute=route(p.public_code);
    requireThat(p.id===paymentId&&p.transaction_id===cmd.receiptId&&p.collection_id===this.groupId&&p.evidence_group===this.groupId&&
      p.beneficiary_member_id===cmd.memberId&&p.member_id===null&&p.status==='recorded'&&p.rail==='rwanda_momo'&&
      p.currency==='RWF'&&p.evidence_currency==='RWF'&&p.source_currency==='RWF'&&
      p.event_kind==='incoming_receipt'&&exact(p.has_conflict)===0&&p.allocation_state==='linked'&&
      p.source_mode==='live'&&exact(p.historical_existing)===0&&p.has_entries===false&&p.has_snapshot===false&&p.has_other_reference===false&&
      p.account_status==='active'&&p.profile_status==='approved'&&p.group_status==='active'&&exact(p.membership_active)===1&&p.access_status==='active'&&
      ['mtn_momo','airtel_money'].includes(p.account_provider)&&p.source_provider===p.account_provider&&
      p.receiver_network===p.account_provider&&p.evidence_network===p.account_provider&&receivingRoute!==null&&
      route(p.receiver_momo_number)===receivingRoute&&route(p.evidence_route)===receivingRoute,
      'posting_record_invalid',503);
    // Any other recorded reference is refused, including a compensated original.
    // This new automatic path cannot silently authorize a reversal/recredit.
    // Allocation increments the canonical version once. Historical adoption and
    // unsupported corrections remain separate paths, never guessed here.
    requireThat(exact(p.transaction_version)===cmd.expectedVersion+1,'transaction_changed',409);
    requireThat(exact(p.revision)>=1&&exact(p.amount_minor)===cmd.receipt.amountRwf&&
      exact(p.source_amount)===cmd.receipt.amountRwf&&exact(p.evidence_amount)===cmd.receipt.amountRwf,'posting_record_invalid',503);
    requireThat(p.provider_transaction_id===cmd.receipt.providerTransactionId&&typeof p.provider_transaction_id==='string'&&p.provider_transaction_id.length>0&&p.provider_transaction_id.length<=160&&
      !/[\u0000-\u001f\u007f]/.test(p.provider_transaction_id)&&
      [p.provider_transaction_id,p.receiving_account_id+':'+p.provider_transaction_id].includes(p.external_reference),
      'posting_evidence_mismatch',409);
    requireId(p.evidence_id);requireId(p.receiving_account_id);requireId(p.source_binding_id);
    requireThat(p.receiving_account_id===cmd.receipt.receivingAccountId&&p.source_binding_id===cmd.receipt.sourceBindingId&&
      exact(p.source_binding_version)===cmd.receipt.sourceBindingVersion&&hash.test(p.object_sha256)&&
      typeof p.object_key==='string'&&p.object_key.length>0&&p.object_key.length<=1024&&exact(p.size_bytes)>0,
      'posting_evidence_mismatch',409);
    if(cmd.mode==='automatic')requireThat(p.scope_policy_version===cmd.policyVersion,'identity_changed',409);
    return p;
  }
  async postContribution(sql,input){
    requirePort(sql,['unsafe']);
    // Snapshot before the first await; caller-owned objects cannot change targets.
    const cmd=immutable(input);
    requireThat(cmd.groupId===this.groupId&&['automatic','exception'].includes(cmd.mode),'access_denied',403);
    requireId(cmd.receiptId);requireId(cmd.memberId);requireRequestId(cmd.requestId);
    requireThat(Number.isSafeInteger(cmd.expectedVersion)&&cmd.expectedVersion>=1&&cmd.expectedVersion<Number.MAX_SAFE_INTEGER,'invalid_version');
    requireThat(cmd.receipt?.id===cmd.receiptId&&cmd.receipt.groupId===this.groupId&&cmd.receipt.version===cmd.expectedVersion&&
      cmd.receipt.state==='unallocated'&&cmd.receipt.hasConflict===false&&cmd.receipt.currency==='RWF'&&
      cmd.member?.id===cmd.memberId&&cmd.member.groupId===this.groupId&&cmd.member.active===true&&cmd.member.eligible===true,'posting_record_invalid',503);
    requireAmount(cmd.receipt.amountRwf);
    if(cmd.mode==='automatic'){
      automaticWork(cmd.work);requireThat(typeof cmd.policyVersion==='string'&&cmd.policyVersion.length>0&&
        Array.isArray(cmd.identityIds)&&cmd.identityIds.length>0,'identity_changed',409);
      cmd.identityIds.forEach(requireId);
    }else{
      requireRequestId(cmd.actorId);requireRequestId(cmd.sessionId);
      requireThat(typeof cmd.reason==='string'&&cmd.reason.trim().length>=8&&cmd.reason.length<=500&&!/[\u0000-\u001f\u007f]/.test(cmd.reason),'identification_note_required');
    }
    const principal=await this.authority(sql,cmd,'before_allocation');
    // This bridge must use the current shared allocation/custody commands, not
    // the old manual-review endpoint. Its writes roll back with this callback.
    const prepared=await this.allocation.prepareInTransaction(sql,cmd,principal);
    requireId(prepared?.paymentId);const paymentId=prepared.paymentId;
    await this.authority(sql,cmd,'after_allocation',principal);
    let p=await this.record(sql,cmd,paymentId);
    const proof=await this.evidence.assertInTransaction(sql,{command:cmd,principal,paymentId,evidenceId:p.evidence_id,
      transactionId:p.transaction_id,receivingAccountId:p.receiving_account_id,sourceBindingId:p.source_binding_id,
      sourceBindingVersion:exact(p.source_binding_version),objectKey:p.object_key,objectSha256:p.object_sha256,sizeBytes:exact(p.size_bytes)});
    requireThat(proof?.verified===true,'posting_evidence_required',503);
    // The bridge may await. Re-read the locked records, retaining exactly the
    // same evidence descriptor instead of trusting its response as a mutation.
    const before=canonicalJson(p);p=await this.record(sql,cmd,paymentId);
    requireThat(canonicalJson(p)===before,'posting_record_changed',409);
    await this.authority(sql,cmd,'before_posting',principal);
    const env={DB:{prepare:text=>this.db.prepare(text)}};
    const checkId=crypto.randomUUID(),writes=[];
    // Native account IDs are NOT app.users IDs. The runtime must provide the
    // genuine canonical principal/session; never synthesize or substitute one.
    const actor={userId:principal.principalUserId,sessionId:principal.principalSessionId};
    // The builder's legacy argument name does not represent a review record.
    // Only its beneficiary field is consumed; no reviewer or approval is invented.
    const reconciliation={proposed_member_id:cmd.memberId};
    const now=()=>new Date().toISOString(),id=()=>crypto.randomUUID();
    p={...p,revision:exact(p.revision),amount_minor:exact(p.amount_minor)};
    const args={env,p,checkId,actor,reconciliation,requestId:cmd.requestId,now,id};
    appendContributionCollision(writes,args);appendContributionEntry(writes,args);appendContributionSnapshots(writes,args);
    for(const statement of writes){await this.owned();await this.db.statement(sql,statement);}
    await this.authority(sql,cmd,'after_posting',principal);
    // The original transaction still owns financial/custody locks. Recheck the
    // private preflight and exact source after all awaited writer/authority work
    // and before its caller can retain an outcome or commit. No Storage I/O.
    if(typeof this.evidence.revalidateInTransaction==='function')
      requireThat((await this.evidence.revalidateInTransaction(sql,proof))?.verified===true,'posting_evidence_required',503);
    // No commit or public result here: the outer canonical store MUST verify
    // ledger/snapshot readback and retain the command/rematch outcome atomically.
  }
}
