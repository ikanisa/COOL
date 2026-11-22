import {revalidateCommandActor} from './command-authority.js';
import {requirePort,requireThat,BuriError} from './errors.js';
import {normalizePhone,requireId,requireRequestId,canonicalJson,sha256,exactKeys} from './values.js';
// One stable request identifier per imported row. The batch receipt still binds
// the complete ordered request; row IDs exist only for canonical audit/rematch.
async function importRowRequestId(groupId,actorId,requestId,row){
  const h=await sha256(canonicalJson({operation:'burimunsi.members_import.row',groupId,actorId,requestId,row}));
  return `${h.slice(0,8)}-${h.slice(8,12)}-4${h.slice(13,16)}-8${h.slice(17,20)}-${h.slice(20,32)}`;
}
/** Existing Collect Direct-member command is mandatory. No standalone person table. */
export class MemberService {
  constructor({store,groupId,clock=()=>Date.now()}){requirePort(store,['inMemberTransaction']);Object.assign(this,{store,groupId,clock});}
  async enroll(actor,{name,phone,requestId}){
    actor={id:actor?.id,sessionId:actor?.sessionId};
    requireThat(typeof name==='string'&&name.trim().length>=2&&name.trim().length<=100&&!/[\u0000-\u001f\u007f]/.test(name),'invalid_name');
    phone=normalizePhone(phone);requestId=requireRequestId(requestId);name=name.trim();
    const fingerprint=await sha256(canonicalJson({operation:'burimunsi.enroll',name,phone}));
    return this.store.inMemberTransaction(async tx=>{
      requirePort(tx,['reloadActor','retainedCommand','retainCommand','createDirectMember','enqueueEligibleRematch']);
      const fresh=await revalidateCommandActor(tx,actor,this.groupId,'members.enroll',this.clock());
      const previous=await tx.retainedCommand(this.groupId,fresh.id,requestId);
      if(previous){requireThat(previous.fingerprint===fingerprint&&previous.sessionId===fresh.sessionId,'idempotency_conflict',409);return previous.response;}
      const result=await tx.createDirectMember({groupId:this.groupId,name,phone,requestId,actorId:fresh.id,sessionId:fresh.sessionId});
      requireThat(result?.id&&result.phone===phone&&result.groupId===this.groupId&&
        (result.existing===undefined||result.existing===true),'member_contract_violation',503);
      // Opening an existing member is not an enrollment and must not queue a
      // fresh rematch. The internal marker is not part of the public member DTO.
      const {existing,...response}=result;
      if(!existing)await tx.enqueueEligibleRematch({groupId:this.groupId,memberId:result.id,requestId,cause:'enrollment'});
      await revalidateCommandActor(tx,fresh,this.groupId,'members.enroll',this.clock());
      await tx.retainCommand({operation:'burimunsi.enroll',groupId:this.groupId,actorId:fresh.id,sessionId:fresh.sessionId,requestId,fingerprint,response});return response;
    });
  }
  /** A batch is one recoverable command, not 500 independently replayable
   * requests. Any infrastructure failure rolls back every member and receipt. */
  async importMembers(actor,input){
    exactKeys(input,['requestId','rows']);
    const requestId=requireRequestId(input.requestId), rows=input.rows;
    requireThat(Array.isArray(rows)&&rows.length>=1&&rows.length<=500,'invalid_import');
    actor={id:actor?.id,sessionId:actor?.sessionId};
    const fingerprint=await sha256(canonicalJson({operation:'burimunsi.members_import',rows}));
    const seenRows=new Set(),seenPhones=new Set(),prepared=[];
    for(const item of rows){
      exactKeys(item,['row','name','phone','verifiedOwnership','acceptedTerms','consentRecorded','candidateId'],
        ['row','name','phone','verifiedOwnership','acceptedTerms','consentRecorded']);
      requireThat(Number.isSafeInteger(item.row)&&item.row>=1&&item.row<=500&&!seenRows.has(item.row),'invalid_import');
      seenRows.add(item.row);
      requireThat([item.verifiedOwnership,item.acceptedTerms,item.consentRecorded].every(v=>typeof v==='boolean'),'invalid_import');
      const candidateId=item.candidateId??null;if(candidateId!==null)requireId(candidateId);
      let phone=null;try{phone=normalizePhone(item.phone)}catch(e){if(!(e instanceof BuriError))throw e;}
      const name=typeof item.name==='string'?item.name.trim():'';
      let status=null;
      if(name.length<2||name.length>100||/[\u0000-\u001f\u007f]/.test(name)||phone===null)status='invalid';
      else if(!item.verifiedOwnership||!item.acceptedTerms||!item.consentRecorded)status='needs_verification';
      else if(seenPhones.has(phone))status='duplicate_in_batch';
      if(phone!==null)seenPhones.add(phone);
      prepared.push({row:item.row,name,phone,candidateId,status});
    }
    return this.store.inMemberTransaction(async tx=>{
      requirePort(tx,['reloadActor','retainedCommand','retainCommand','createDirectMember','enqueueEligibleRematch','recordMemberImportAttestation']);
      const fresh=await revalidateCommandActor(tx,actor,this.groupId,'members.enroll',this.clock());
      const prior=await tx.retainedCommand(this.groupId,fresh.id,requestId);
      if(prior){requireThat(prior.operation==='burimunsi.members_import'&&prior.fingerprint===fingerprint&&prior.sessionId===fresh.sessionId,'idempotency_conflict',409);return prior.response;}
      const results=[];
      for(const row of prepared){
        let status=row.status,memberId=null;
        if(!status&&row.candidateId!==null){
          requirePort(tx,['onboardingCandidate']);
          const candidate=await tx.onboardingCandidate({groupId:this.groupId,candidateId:row.candidateId,phone:row.phone,actorId:fresh.id,sessionId:fresh.sessionId});
          if(!candidate||candidate.last3!==row.phone.slice(-3))status='candidate_changed';
        }
        if(!status){
          const rowRequestId=await importRowRequestId(this.groupId,fresh.id,requestId,row.row);
          const member=await tx.createDirectMember({groupId:this.groupId,name:row.name,phone:row.phone,requestId:rowRequestId,actorId:fresh.id,sessionId:fresh.sessionId});
          requireThat(member?.id&&member.groupId===this.groupId&&member.phone===row.phone&&
            (member.existing===undefined||member.existing===true),'member_contract_violation',503);
          memberId=member.id;status=member.existing?'already_registered':'created';
          await tx.recordMemberImportAttestation({groupId:this.groupId,memberId,requestId:rowRequestId,actorId:fresh.id,sessionId:fresh.sessionId});
          if(!member.existing)await tx.enqueueEligibleRematch({groupId:this.groupId,memberId,requestId:rowRequestId,cause:'enrollment'});
        }
        results.push({row:row.row,status,memberId});
      }
      const response={requestId,results,created:results.filter(r=>r.status==='created').length};
      await revalidateCommandActor(tx,fresh,this.groupId,'members.enroll',this.clock());
      await tx.retainCommand({operation:'burimunsi.members_import',groupId:this.groupId,actorId:fresh.id,sessionId:fresh.sessionId,requestId,fingerprint,response});
      return response;
    });
  }
  async setActive(actor,{memberId,active,expectedVersion,requestId}){
    actor={id:actor?.id,sessionId:actor?.sessionId};
    requireId(memberId);requestId=requireRequestId(requestId);
    requireThat(typeof active==='boolean'&&Number.isSafeInteger(expectedVersion)&&expectedVersion>0,'invalid_membership_change');
    const fingerprint=await sha256(canonicalJson({operation:'burimunsi.membership',memberId,active,expectedVersion}));
    return this.store.inMemberTransaction(async tx=>{
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
