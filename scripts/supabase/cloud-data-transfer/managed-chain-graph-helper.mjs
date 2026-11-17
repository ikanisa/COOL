// Called only from the private owned managed-chain fixture.
import {randomBytes,randomUUID} from 'node:crypto';
import {captureLocalSource} from './source-reader.mjs';
import {insertGraph,verifyGraph} from './graph-transaction.mjs';
import {rehearseManagedShapeMaintenance} from './maintenance.mjs';

export async function exerciseManagedChainGraph(owner){
 const capture=captureLocalSource(),key=randomBytes(32),operationId=randomUUID(),proofHmac='b'.repeat(64);
 const fence=(await owner.query('SELECT operation_id::text,epoch::text,source_sha256 FROM private.collect_fence_control WHERE singleton')).rows[0];
 const proof=Object.fromEntries(capture.snapshot.tables['private.storage_objects'].map(o=>[o.object_key,{sha256:o.sha256,size:o.size,etag:'fixture-only-etag'}]));
 let inserted;
 try{
  await rehearseManagedShapeMaintenance(owner,{operationId,fenceOperationId:fence.operation_id,epoch:fence.epoch,sourceSha256:fence.source_sha256},
   async db=>{inserted=await insertGraph(db,{capture,key,operationId,cloudPrimaryId:'synthetic-primary',proof,proofHmac});},
   async db=>verifyGraph(db,{capture,key,operationId,proofHmac,inserted}));
  return {commands:inserted.plan.summary.commandCount,objects:inserted.counts.objects,sms:inserted.counts.sms};
 }finally{key.fill(0);}
}
