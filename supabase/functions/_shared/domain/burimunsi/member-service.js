import {revalidateCommandActor} from './command-authority.js';
import {requirePort,requireThat} from './errors.js';
import {normalizePhone,requireId,requireRequestId,canonicalJson,sha256} from './values.js';
/** Existing Collect Direct-member command is mandatory. No standalone person table. */
export class MemberService {
  constructor({store,groupId,clock=()=>Date.now()}){requirePort(store,['inCanonicalTransaction']);Object.assign(this,{store,groupId,clock});}
  async enroll(actor,{name,phone,requestId}){
    actor={id:actor?.id,sessionId:actor?.sessionId};
    requireThat(typeof name==='string'&&name.trim().length>=2&&name.trim().length<=100&&!/[\u0000-\u001f\u007f]/.test(name),'invalid_name');
    phone=normalizePhone(phone);requestId=requireRequestId(requestId);name=name.trim();
    const fingerprint=await sha256(canonicalJson({operation:'burimunsi.enroll',name,phone}));
    return this.store.inCanonicalTransaction(async tx=>{
      requirePort(tx,['reloadActor','retainedCommand','retainCommand','createDirectMember','enqueueEligibleRematch']);
      const fresh=await revalidateCommandActor(tx,actor,this.groupId,'members.enroll',this.clock());
      const previous=await tx.retainedCommand(this.groupId,fresh.id,requestId);
      if(previous){requireThat(previous.fingerprint===fingerprint&&previous.sessionId===fresh.sessionId,'idempotency_conflict',409);return previous.response;}
      const result=await tx.createDirectMember({groupId:this.groupId,name,phone,requestId,actorId:fresh.id,sessionId:fresh.sessionId});
      requireThat(result?.id&&result.phone===phone&&result.groupId===this.groupId,'member_contract_violation',503);
      // This schedules the SAME approved matcher. Enrollment is not proof of payer ownership.
      await tx.enqueueEligibleRematch({groupId:this.groupId,memberId:result.id,requestId,cause:'enrollment'});
      await revalidateCommandActor(tx,fresh,this.groupId,'members.enroll',this.clock());
      await tx.retainCommand({operation:'burimunsi.enroll',groupId:this.groupId,actorId:fresh.id,sessionId:fresh.sessionId,requestId,fingerprint,response:result});return result;
    });
  }
  async setActive(actor,{memberId,active,expectedVersion,requestId}){
    actor={id:actor?.id,sessionId:actor?.sessionId};
    requireId(memberId);requestId=requireRequestId(requestId);
    requireThat(typeof active==='boolean'&&Number.isSafeInteger(expectedVersion)&&expectedVersion>0,'invalid_membership_change');
    const fingerprint=await sha256(canonicalJson({operation:'burimunsi.membership',memberId,active,expectedVersion}));
    return this.store.inCanonicalTransaction(async tx=>{
      requirePort(tx,['reloadActor','retainedCommand','retainCommand','setMembershipActive']);
      const fresh=await revalidateCommandActor(tx,actor,this.groupId,'members.enroll',this.clock());
      requireThat(fresh.role==='admin','access_denied',403);
      const previous=await tx.retainedCommand(this.groupId,fresh.id,requestId);
      if(previous){requireThat(previous.fingerprint===fingerprint&&previous.sessionId===fresh.sessionId,'idempotency_conflict',409);return previous.response;}
      const result=await tx.setMembershipActive({groupId:this.groupId,memberId,active,expectedVersion,requestId,actorId:fresh.id,sessionId:fresh.sessionId});
      requireThat(result?.applied===true,'membership_changed',409);
      if(active) {
        requirePort(tx,['enqueueEligibleRematch']);
        await tx.enqueueEligibleRematch({groupId:this.groupId,memberId,requestId,cause:'reactivation'});
      }
      const finalActor=await revalidateCommandActor(tx,fresh,this.groupId,'members.enroll',this.clock());
      requireThat(finalActor.role==='admin','access_denied',403);
      await tx.retainCommand({operation:'burimunsi.membership',groupId:this.groupId,actorId:fresh.id,sessionId:fresh.sessionId,requestId,fingerprint,response:result});return result;
    });
  }
}
