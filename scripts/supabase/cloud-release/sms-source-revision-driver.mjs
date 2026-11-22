// Explicit library entry point. Importing performs no actions; only a caller
// with reviewed source, evidence and existing revision journals may invoke it.
import {connect,management,record} from './access.mjs';
import {readAncillaryRegistration} from './ancillary-inventory.mjs';
import {reviseRuntime} from './revise-runtime.mjs';
import {createSmsSourceRevisionApi,smsRevisionFenceReader} from './sms-source-revision-api.mjs';

export async function reviseCoreWithSms({revision,oldSource,newSource,oldEpoch,gatewayReleaseSha256,unchangedSecrets={}},deps={}) {
 if(!revision||revision.testEvidence?.passed!==true||revision.testEvidence?.sourceSha256!==newSource||
  (revision.expectedBefore&&(revision.expectedBefore.source_sha256!==oldSource||revision.expectedBefore.epoch!==oldEpoch)))
  throw Error('sms_revision_evidence_mismatch');
 const immutable={...unchangedSecrets,...(revision.expectedSecretPreimages??{})};
 for(const [name,value] of Object.entries(unchangedSecrets))if(immutable[name]!==value)throw Error('sms_revision_evidence_mismatch');
 const open=deps.open??connect,request=deps.api??management,save=deps.save??record;
 const readRegistration=deps.readRegistration??readAncillaryRegistration;
 let client=null,fenceId=null;
 const adapter=createSmsSourceRevisionApi({request,oldSource,newSource,gatewayReleaseSha256,oldEpoch,unchangedSecrets:immutable,
  readRegistration,expectedFenceId:()=>fenceId,readFence:async()=>smsRevisionFenceReader(client)(),
  withFenceLock:async action=>{
   if(!client)throw Error('sms_revision_fence_unconfirmed');
   await client.query('BEGIN ISOLATION LEVEL READ COMMITTED');
   try {
    await client.query("SET LOCAL lock_timeout='5s'; SELECT pg_advisory_xact_lock(7346371,1); SELECT pg_advisory_xact_lock(7346371,2)");
    const result=await action();await client.query('COMMIT');return result;
   } catch(error) {await client.query('ROLLBACK').catch(()=>{});throw error;}
  }});
 const wrappedSave=(name,value)=>{
  save(name,value); // The existing fsync'd journal is the authority; never invent an intent.
  if(name==='revision-'+revision.label+'-intent.json')fenceId=value.fenceId;
 };
 return reviseRuntime(revision,{...deps,api:adapter,readRegistration,save:wrappedSave,
  open:async()=>{client=await open();return client;}});
}
