// Disabled, server-only preparation for typed native receipt provenance.
// This does not promote a source, create a managed session, post a transaction,
// or grant financial authority. No HTTP route currently calls this module.
import {BuriError,requireThat} from './errors.js';
import {canonicalJson,exactKeys,requireRequestId,sha256} from './values.js';
import {PostgresNativeObservations} from './postgres-observations.js';
import {nativePromotionEvidence} from './native-promotion-evidence.js';
import {digest} from '../core.js';

const check=(v,code='native_assessment_unavailable',status=503)=>requireThat(v,code,status);
const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const decoder=new TextDecoder('utf-8',{fatal:true});
const target=r=>({ownerId:r.principalUserId,purpose:'sms_receipt',entityId:r.id,
 plaintextSha256:r.object_sha256,aad:`sms:${r.id}:${r.object_sha256}`});

export class PostgresNativePromotionAssessment {
 constructor({observations}){
  check(observations instanceof PostgresNativeObservations);
  this.observations=observations;
 }
 async context(tx,actor,record){
  const r=await tx.unsafe('SELECT private.burimunsi_native_promotion_context($1) AS result',[record.id]);
  check(r.length===1&&r[0].result,'record_unavailable',404);const ctx=r[0].result,o=ctx.observation;
  check(ctx.contextVersion===1&&o?.sourceId===record.id&&o.collectionId===actor.groupId&&
   o.nativeAccountId===actor.id&&o.installationId===actor.installationId&&
   o.bodySha256===record.bodySha256&&o.objectSha256===record.object_sha256&&
   ctx.scope?.collectionId===actor.groupId,'native_assessment_changed',409);
  return ctx;
 }
 async assess(actor,id,input){
  const o=this.observations;check(o.env.BURIMUNSI_NATIVE_PROMOTION_ASSESSMENT_ENABLED==='true');
  requireRequestId(id);requireRequestId(input?.requestId);exactKeys(input,['requestId','reason']);
  const reason=typeof input.reason==='string'?input.reason.trim():'';
  check([...reason].length>=8&&[...reason].length<=1000&&!/[\u0000-\u001f\u007f-\u009f]/.test(reason),'review_reason_required',400);
  let binding,bytes;
  try{
   const initial=await o.authority.write(async tx=>{
    const current=await o.current(tx,actor),record=await o.own(tx,actor,id,true);
    check(record!==null,'record_unavailable',404);
    const context=await this.context(tx,actor,record),namespace=await o.namespace(tx);
    const journal=await o.custody.journal(tx,record.object_key,target(record));await o.checkJournal(record,journal);
    binding={kind:'native_promotion_assessment',groupId:o.groupId,requestId:input.requestId,identity:o.identity(current),source:record};
    const plan=await o.storageWitnesses.stage(binding,[{key:record.object_key,journal}]);
    return {identity:o.identity(current),record,context,namespace,journal,plan};
   });
   await o.storageWitnesses.prefetch(initial.plan);
   const sealed=await o.storageWitnesses.sealed(binding,initial.record.object_key,initial.journal);
   bytes=await o.custody.decrypt(sealed,target(initial.record).aad);
   check(bytes instanceof Uint8Array&&bytes.length===initial.record.size_bytes&&await digest(bytes)===initial.record.object_sha256);
   const payload=JSON.parse(decoder.decode(bytes));
   check(payload&&typeof payload.raw_body==='string'&&typeof payload.raw_sender==='string'&&
    await sha256(payload.raw_body)===initial.record.bodySha256);
   const evidence=await nativePromotionEvidence({...initial.context,source:payload});
   await o.authority.assertOwned();
   await o.authority.write(async tx=>{
    const current=await o.current(tx,actor);check(same(o.identity(current),initial.identity),'access_denied',403);
    const record=await o.own(tx,actor,id,true),namespace=await o.namespace(tx);
    check(record&&same(record,initial.record)&&same(namespace,initial.namespace),'native_assessment_changed',409);
    const context=await this.context(tx,actor,record);check(same(context,initial.context),'native_assessment_changed',409);
    const journal=await o.custody.journal(tx,record.object_key,target(record));await o.checkJournal(record,journal);
    check(o.custody.sameJournal(journal,initial.journal));await o.storageWitnesses.sealed(binding,record.object_key,journal);
    const audit=await tx.unsafe('SELECT private.burimunsi_observation_reveal_audit($1,$2::uuid,$3,$4::uuid,$5,$6,$7,$8::bigint) AS result',
     [id,input.requestId,reason,actor.sessionId,record.bodySha256,record.object_sha256,record.fingerprint,record.consentGeneration]);
    check(audit.length===1&&audit[0].result?.sourceId===record.id&&audit[0].result?.bodySha256===record.bodySha256&&
     audit[0].result?.fingerprint===record.fingerprint,'native_assessment_changed',409);
    const last=await o.current(tx,actor);check(same(o.identity(last),initial.identity),'access_denied',403);
   });
   await o.authority.assertOwned();return evidence;
  }catch(error){
   if(error instanceof BuriError)throw error;
   if(error?.code==='42501')throw new BuriError('access_denied',403);
   if(error?.code==='40001'||error?.code==='23505')throw new BuriError('native_assessment_changed',409);
   throw new BuriError('native_assessment_unavailable',503);
  }finally{bytes?.fill(0);if(binding)o.storageWitnesses.forget(binding);}
 }
}
