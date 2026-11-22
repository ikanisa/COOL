// Disabled, unregistered canonical intake for an already retained observation.
// This does not assign a receiving account, process a payment, create a managed
// session or write the ledger.  The draft migration intentionally parks its job.
import {BuriError,requireThat} from './errors.js';
import {canonicalJson,requireRequestId} from './values.js';
import {PostgresNativeObservations} from './postgres-observations.js';

const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const check=(ok,code='native_intake_unavailable',status=503)=>requireThat(ok,code,status);
const target=r=>({ownerId:r.principalUserId,purpose:'sms_receipt',entityId:r.id,
 plaintextSha256:r.object_sha256,aad:`sms:${r.id}:${r.object_sha256}`});

export class PostgresNativeCanonicalIntake {
 constructor({observations}){
  check(observations instanceof PostgresNativeObservations);
  this.observations=observations;
 }

 /**
  * Reuse the original committed object and authenticated observation.  The
  * actor/source/scope are always resolved from current server-side authority.
  * A lost COMMIT response is not an acknowledgement: an exact retry asks the
  * same database operation for its retained outcome and never uploads again.
  */
 async stage(actor,sourceId){
  const o=this.observations;
  check(o.env.BURIMUNSI_NATIVE_CANONICAL_INTAKE_ENABLED==='true');
  requireRequestId(sourceId);
  try{
   await o.authority.assertOwned();
   return await o.authority.write(async tx=>{
    const initial=await o.current(tx,actor),record=await o.own(tx,actor,sourceId,false);
    check(record!==null,'record_unavailable',404);
    const namespace=await o.namespace(tx),journal=await o.custody.journal(tx,record.object_key,target(record));
    await o.checkJournal(record,journal);
    const rows=await tx.unsafe('SELECT private.burimunsi_stage_native_receipt($1) AS result',[sourceId]);
    check(rows.length===1&&rows[0].result);
    const result=rows[0].result;
    check(Object.keys(result).sort().join(',')==='collectionId,created,financialEffects,sourceId,state'&&
     result.sourceId===sourceId&&result.collectionId===o.groupId&&result.state==='source_unresolved'&&
     result.financialEffects===0&&typeof result.created==='boolean','native_intake_changed',409);
    const final=await o.current(tx,actor),after=await o.own(tx,actor,sourceId,false),afterNamespace=await o.namespace(tx);
    check(same(o.identity(initial),o.identity(final))&&after&&same(record,after)&&same(namespace,afterNamespace),
     'native_intake_changed',409);
    const afterJournal=await o.custody.journal(tx,after.object_key,target(after));
    await o.checkJournal(after,afterJournal);check(o.custody.sameJournal(journal,afterJournal),'native_intake_changed',409);
    await o.authority.assertOwned();
    return Object.freeze({...result});
   });
  }catch(error){
   if(error instanceof BuriError)throw error;
   if(error?.code==='42501')throw new BuriError('access_denied',403);
   if(['40001','23505'].includes(error?.code))throw new BuriError('native_intake_changed',409);
   throw new BuriError('native_intake_unavailable',503);
  }
 }
}
