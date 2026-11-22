import {requirePort,requireThat,BuriError} from './errors.js';
import {requireId,requireRequestId} from './values.js';
import {automaticWork} from './automatic-work.js';
import {rematchRequestId} from './postgres-rematch-job-store.js';

/** Counts are durable target observations, NOT newly credited deposits. Each
 * bounded slice yields the durable cursor; one long group scan is not four
 * failed attempts. Restarts resume a reserved target/outcome before scanning. */
export async function processRematchBatch({store,contributions,groupId,owner,limit=5,targetsPerJob=20,leaseMs=180000}) {
  requirePort(store,['claimNext','nextTarget','advanceTarget','yieldJob','failJob']);
  requirePort(contributions,['automaticallyAllocate']);requireId(groupId);requireId(owner);
  requireThat(Number.isInteger(limit)&&limit>=1&&limit<=20&&Number.isInteger(targetsPerJob)&&targetsPerJob>=1&&targetsPerJob<=100&&
    Number.isInteger(leaseMs)&&leaseMs>=30000&&leaseMs<=600000,'invalid_worker_config',503);
  const counts={claimed:0,completed:0,yielded:0,postedObservations:0,unallocated:0,skipped:0,resumedOutcomes:0,
    replayedCheckpoints:0,retry:0,deadLetter:0,leaseLost:0,checkpointFailed:0,stopped:false};
  for(let i=0;i<limit;i++) {
    const job=await store.claimNext({groupId,owner,leaseMs});if(!job)break;
    requireRequestId(job.id);
    requireThat(job.groupId===groupId&&job.owner===owner&&job.state==='running'&&Number.isSafeInteger(job.attempt)&&job.attempt>=1&&
      Number.isSafeInteger(job.maxAttempts)&&job.maxAttempts>=4&&job.maxAttempts<=10&&job.attempt<=job.maxAttempts,'invalid_rematch_job',503);
    const work=automaticWork({kind:'rematch',jobId:job.id,owner,leaseVersion:job.leaseVersion,memberId:job.memberId,policyVersion:job.policyVersion});
    const witness={jobId:job.id,owner,leaseVersion:job.leaseVersion};counts.claimed++;
    try {
      let completed=false;
      for(let t=0;t<targetsPerJob;t++) {
        const target=await store.nextTarget(witness);
        if(target===null){counts.completed++;completed=true;break;}
        requireId(target.transactionId);
        requireThat(target.outcome===null||['posted','unallocated','skipped'].includes(target.outcome),'invalid_rematch_job',503);
        if(target.outcome===null) {
          const requestId=await rematchRequestId(groupId,job.id,target.transactionId);
          // Ignore its claimed financial response. advanceTarget requires the
          // outcome retained INSIDE the canonical transaction, not caller data.
          await contributions.automaticallyAllocate(target.transactionId,requestId,work);
        }else counts.resumedOutcomes++;
        const advanced=await store.advanceTarget({...witness,transactionId:target.transactionId});
        requireThat(advanced?.applied===true,'lease_unavailable',409);
        if(advanced.replayed===true){counts.replayedCheckpoints++;continue;}
        requireThat(['posted','unallocated','skipped'].includes(advanced.outcome),'rematch_outcome_missing',503);
        if(advanced.outcome==='posted')counts.postedObservations++;
        else counts[advanced.outcome]++;
      }
      if(!completed) {
        requireThat((await store.yieldJob(witness))?.applied===true,'lease_unavailable',409);counts.yielded++;
      }
    } catch(error) {
      let failed;
      try{failed=await store.failJob({...witness,code:error instanceof BuriError?error.code:'processing_unavailable'});}
      catch{counts.checkpointFailed++;counts.stopped=true;break;}
      if(failed?.applied===false){counts.leaseLost++;continue;}
      requireThat(failed?.applied===true&&['retry','dead_letter'].includes(failed.state),'invalid_job_checkpoint',503);
      if(failed.state==='dead_letter')counts.deadLetter++;else counts.retry++;
      if(error instanceof BuriError&&['processing_on_hold','profile_changed','scope_unavailable'].includes(error.code)) {counts.stopped=true;break;}
    }
  }
  return counts;
}
