import {requireThat,requirePort} from './errors.js';
import {automaticWork} from './automatic-work.js';
import {canonicalJson,sha256,requireAmount,requireId,requireRequestId} from './values.js';
import {matchExistingMember} from './policy.js';
import {revalidateCommandActor} from './command-authority.js';

const freeze=value=>{if(value&&typeof value==='object'){Object.values(value).forEach(freeze);Object.freeze(value);}return value;};
const snapshot=value=>freeze(JSON.parse(canonicalJson(value)));
const result=value=>({kind:'result',value});
const missing=()=>({kind:'missing'});

/** Single orchestration port into Collect's canonical writer. Optional protected
 * preparation runs BETWEEN admitted transactions, never under financial locks.
 * Plans are derived by the canonical store; no caller supplies receipt facts,
 * principal bindings, evidence keys or posting commands. All financial effects
 * and durable outcomes remain in the existing canonical transaction.
 */
export class ContributionService {
  constructor({store,groupId,clock=()=>Date.now(),preparation=null}) {
    requirePort(store,['inCanonicalTransaction']);requireThat(groupId,'group_required',503);
    if(preparation!==null)requirePort(preparation,['prepare']);
    Object.assign(this,{store,groupId,clock,preparation});
  }
  async #run(step) {
    if(this.preparation===null)return (await step('commit',null)).value;
    const planned=await step('plan',null);
    if(planned.kind==='result')return planned.value;
    requireThat(planned.kind==='prepare','posting_plan_required',503);
    const command=snapshot(planned.command);
    try {
      // The plan transaction has ended. Provider work must be owned/fenced by
      // the genuine preparation service, not by a transaction-local callback.
      const prepared=await this.preparation.prepare(command);
      requireThat(prepared?.prepared===true&&prepared.contractVersion===1,'posting_preparation_unavailable',503);
      return (await step('commit',command)).value;
    } catch(error) {
      // A concurrent identical request or a lost COMMIT reply may already have
      // succeeded. Only a fresh authorized durable-result read can resolve it.
      // This branch NEVER plans/prepares/posts a new contribution or changes IDs.
      const replay=await step('replay',null);
      if(replay.kind==='result')return replay.value;
      throw error;
    }
  }
  async #plan(tx,command) {
    requirePort(tx,['planCanonicalContribution']);
    return {kind:'prepare',command:snapshot(await tx.planCanonicalContribution(command))};
  }
  async allocate(actor,{transactionId,memberId,expectedVersion,note,requestId}) {
    actor={id:actor?.id,sessionId:actor?.sessionId};
    requireId(transactionId);requireId(memberId);requestId=requireRequestId(requestId);
    requireThat(Number.isSafeInteger(expectedVersion)&&expectedVersion>=1,'invalid_version');
    requireThat(typeof note==='string'&&note.trim().length>=8&&note.length<=500&&!/[\u0000-\u001f\u007f]/.test(note),'identification_note_required');
    const body={operation:'burimunsi.allocate',transactionId,memberId,expectedVersion,note:note.trim()};
    const fingerprint=await sha256(canonicalJson(body));
    return this.#run((stage,planned)=>this.store.inCanonicalTransaction(async tx=>{
      requirePort(tx,['reloadActor','retainedCommand','lockReceipt','lockMember','postCanonicalContribution','retainCommand']);
      const fresh=await revalidateCommandActor(tx,actor,this.groupId,'payments.allocate',this.clock());
      const previous=await tx.retainedCommand(this.groupId,fresh.id,requestId);
      if(previous){requireThat(previous.fingerprint===fingerprint&&previous.sessionId===fresh.sessionId,'idempotency_conflict',409);return result(previous.response);}
      if(stage==='replay')return missing();
      const receipt=await tx.lockReceipt(transactionId,this.groupId);
      requireThat(receipt&&receipt.groupId===this.groupId,'record_unavailable',404);
      requireThat(receipt.version===expectedVersion&&!receipt.hasConflict&&receipt.state==='unallocated','transaction_changed',409);
      requireAmount(receipt.amountRwf);
      const member=await tx.lockMember(memberId,this.groupId);
      requireThat(member?.active&&member.eligible&&member.groupId===this.groupId,'member_unavailable',409);
      const command={receiptId:receipt.id,memberId,groupId:this.groupId,
        expectedVersion,requestId,actorId:fresh.id,sessionId:fresh.sessionId,reason:note.trim(),mode:'exception'};
      if(stage==='plan'){
        const plan=await this.#plan(tx,command);
        await revalidateCommandActor(tx,fresh,this.groupId,'payments.allocate',this.clock());
        return plan;
      }
      const posted=await tx.postCanonicalContribution(command,planned);
      this.verifyResult(posted,receipt,memberId);
      await revalidateCommandActor(tx,fresh,this.groupId,'payments.allocate',this.clock());
      await tx.retainCommand({operation:'burimunsi.allocate',groupId:this.groupId,actorId:fresh.id,sessionId:fresh.sessionId,requestId,fingerprint,response:posted});
      return result(posted);
    }));
  }
  async automaticallyAllocate(transactionId,requestId,work) {
    requireId(transactionId);requestId=requireRequestId(requestId);
    work=automaticWork(work);
    return this.#run((stage,planned)=>this.store.inCanonicalTransaction(async tx=>{
      requirePort(tx,['assertAutomaticAdmission','lockReceipt','loadApprovedPolicy','listEligibleMembers','listVerifiedIdentities','postCanonicalContribution','readCanonicalResult']);
      if(work.kind==='rematch')requirePort(tx,['retainAutomaticOutcome']);
      const finish=async value=>{
        await tx.assertAutomaticAdmission({groupId:this.groupId,transactionId,requestId,work});
        if(work.kind==='rematch')await tx.retainAutomaticOutcome({groupId:this.groupId,transactionId,requestId,work,result:value});
        return result(value);
      };
      await tx.assertAutomaticAdmission({groupId:this.groupId,transactionId,requestId,work});
      const receipt=await tx.lockReceipt(transactionId,this.groupId);
      requireThat(receipt&&receipt.groupId===this.groupId,'record_unavailable',404);
      // A replay lookup only returns a real committed canonical result. It must
      // not turn failed preparation into an unallocated/skipped success.
      if(stage==='replay'&&(receipt.hasConflict||receipt.state!=='posted'))return missing();
      if(work.kind==='rematch'&&(receipt.hasConflict||receipt.state==='reversed'))
        return finish({state:'skipped',transactionId:receipt.id,reason:receipt.hasConflict?'transaction_conflict':'transaction_reversed'});
      requireThat(!receipt.hasConflict,'transaction_unavailable',409);
      if(receipt.state==='posted'){
        const previous=await tx.readCanonicalResult(receipt.id);
        requireThat(typeof receipt.memberId==='string'&&receipt.memberId.length>0,'canonical_writer_contract_violation',503);
        this.verifyResult(previous,receipt,receipt.memberId);
        if(work.kind==='rematch'&&receipt.memberId!==work.memberId)
          return finish({state:'skipped',transactionId:receipt.id,reason:'already_posted'});
        return finish(previous);
      }
      requireThat(!receipt.hasConflict&&receipt.state==='unallocated','transaction_unavailable',409);
      requireAmount(receipt.amountRwf);
      const policy=await tx.loadApprovedPolicy(this.groupId);
      if(work.kind==='rematch')requireThat(policy?.approvedVersion===work.policyVersion,'profile_changed',409);
      const match=matchExistingMember(receipt,await tx.listEligibleMembers(this.groupId),await tx.listVerifiedIdentities(this.groupId),policy);
      if(match.kind!=='matched')return finish({state:'unallocated',transactionId:receipt.id,reason:match.reason});
      // An enrollment event is only a scheduling hint, never a beneficiary override.
      if(work.kind==='rematch'&&match.memberId!==work.memberId)
        return finish({state:'unallocated',transactionId:receipt.id,reason:'different_member'});
      const command={receiptId:receipt.id,memberId:match.memberId,groupId:this.groupId,
        expectedVersion:receipt.version,requestId,mode:'automatic',policyVersion:match.policyVersion,identityIds:match.identityIds,work};
      if(stage==='plan'){
        const plan=await this.#plan(tx,command);
        await tx.assertAutomaticAdmission({groupId:this.groupId,transactionId,requestId,work});
        return plan;
      }
      const posted=await tx.postCanonicalContribution(command,planned);
      this.verifyResult(posted,receipt,match.memberId);
      return finish(posted);
    }));
  }
  verifyResult(result,receipt,memberId) {
    requireThat(result && result.transactionId===receipt.id && result.memberId===memberId &&
      result.amountRwf===receipt.amountRwf && result.currency==='RWF' && typeof result.ledgerEntryId==='string' && /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(result.ledgerEntryId) &&
      Number.isSafeInteger(result.memberBalanceRwf) && result.memberBalanceRwf>=0 && Number.isSafeInteger(result.groupBalanceRwf) && result.groupBalanceRwf>=0,
      'canonical_writer_contract_violation',503);
  }
}
