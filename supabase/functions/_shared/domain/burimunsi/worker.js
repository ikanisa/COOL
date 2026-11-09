import {requireThat,requirePort,BuriError} from './errors.js';
import {parseReceipt,receiptFingerprint,transactionKey} from './receipt.js';
import {sha256,canonicalJson,requireId,requireRequestId} from './values.js';
import {safeProcessingCode} from './postgres-receipt-job-store.js';

/** Counts describe durably completed JOBS, not distinct deposits or ledger totals.
 * The concrete store rechecks admission, source and leases within its SQL writes;
 * ContributionService rechecks the posting lease INSIDE the canonical transaction. */
export async function processReceiptBatch({store,contributions,groupId,owner,profile,limit=20,now=()=>Date.now(),leaseMs=180000}){
  requirePort(store,['assertProcessingAdmission','claimNext','loadSource','commitCanonicalReceipt','finishJob','failJob']);
  requirePort(contributions,['automaticallyAllocate']);requireId(groupId);requireId(owner);
  requireThat(Number.isInteger(limit)&&limit>=1&&limit<=100&&Number.isInteger(leaseMs)&&leaseMs>=30000&&leaseMs<=600000,'invalid_worker_config',503);
  await store.assertProcessingAdmission({groupId,profileVersion:profile?.version});
  const result={claimed:0,retained:0,posted:0,unallocated:0,rejected:0,retry:0,deadLetter:0,leaseLost:0,checkpointFailed:0,stopped:false};
  for(let i=0;i<limit;i++){
    const job=await store.claimNext({groupId,owner,profileVersion:profile?.version,now:now(),leaseMs});if(!job)break;
    // An invalid lease contract is a store/configuration failure, not a poison SMS.
    requireRequestId(job.id);
    requireThat(job.groupId===groupId&&job.owner===owner&&job.profileVersion===profile?.version&&
      Number.isSafeInteger(job.leaseVersion)&&job.leaseVersion>0&&Number.isInteger(job.attempt)&&job.attempt>=1&&
      Number.isInteger(job.maxAttempts)&&job.maxAttempts>=4&&job.maxAttempts<=10&&job.attempt<=job.maxAttempts,
      'invalid_job_record',503);
    result.claimed++;
    try{
      const source=await store.loadSource({job,owner,leaseVersion:job.leaseVersion});
      requireThat(source&&source.groupId===groupId&&source.receivingAccountId===job.receivingAccountId,'source_scope_changed',409);
      const receipt=parseReceipt(source,profile),fingerprint=await receiptFingerprint(receipt);
      const canonical=await store.commitCanonicalReceipt({job,owner,leaseVersion:job.leaseVersion,now:now(),
        key:transactionKey(job.receivingAccountId,receipt),fingerprint,receipt});
      requireThat(canonical?.durable===true&&typeof canonical.transactionId==='string'&&canonical.transactionId.length>0,'canonical_ack_missing',503);
      requireThat(!canonical.hasConflict,'transaction_conflict',409);
      const hash=await sha256(canonicalJson(['burimunsi.auto.v1',groupId,job.receivingAccountId,canonical.transactionId]));
      const requestId=hash.slice(0,8)+'-'+hash.slice(8,12)+'-8'+hash.slice(13,16)+'-'+((parseInt(hash[16],16)&3)|8).toString(16)+hash.slice(17,20)+'-'+hash.slice(20,32);
      const work=Object.freeze({kind:'receipt',jobId:job.id,owner,leaseVersion:job.leaseVersion});
      const allocation=await contributions.automaticallyAllocate(canonical.transactionId,requestId,work);
      requireThat(allocation?.transactionId===canonical.transactionId&&
        (allocation.state==='unallocated'||(typeof allocation.ledgerEntryId==='string'&&allocation.ledgerEntryId.length>0)),
        'canonical_posting_outcome_missing',503);
      const finished=await store.finishJob({jobId:job.id,owner,leaseVersion:job.leaseVersion,now:now(),transactionId:canonical.transactionId});
      requireThat(finished?.applied===true,'lease_unavailable',409);
      result.retained++;if(allocation.state==='unallocated')result.unallocated++;else result.posted++;
    }catch(error){
      const exhausted=job.attempt>=job.maxAttempts;
      const permanent=error instanceof BuriError&&error.status<500&&error.status!==409;
      let failure;
      try{
        failure=await store.failJob({jobId:job.id,owner,leaseVersion:job.leaseVersion,now:now(),permanent,
          code:safeProcessingCode(error instanceof BuriError?error.code:'processing_unavailable')});
      }catch{
        // Leave the lease for durable expiry/recovery. Do not claim more jobs when
        // even the failure checkpoint could not be committed.
        result.checkpointFailed++;result.stopped=true;break;
      }
      if(failure?.applied===false){result.leaseLost++;continue;}
      requireThat(failure?.applied===true&&['dead_letter','rejected','retry'].includes(failure.state),'invalid_job_checkpoint',503);
      if(failure.state==='dead_letter')result.deadLetter++;
      else if(failure.state==='rejected')result.rejected++;
      else result.retry++;
      if(error instanceof BuriError&&['processing_on_hold','profile_changed'].includes(error.code)){result.stopped=true;break;}
    }
  }
  return result;
}
