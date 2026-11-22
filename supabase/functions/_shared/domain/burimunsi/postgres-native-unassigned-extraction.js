// Request-scoped provisional extraction for a retained native observation.
// This adapter cannot choose a wallet, create a payment, or write the ledger.
import {digest} from '../core.js';
import {MOMO_MODEL,momoExtractionRequest,validateMomoExtraction,validateProviderProfile} from '../momo_pipeline.js';
import {BuriError,requireThat} from './errors.js';
import {canonicalJson,requireRequestId,sha256} from './values.js';
import {PostgresNativeObservations} from './postgres-observations.js';
import {PostgresNativeCanonicalIntake} from './postgres-native-canonical-intake.js';

const HASH=/^[a-f0-9]{64}$/;
const MODEL=/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$/;
const CONTROL=/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/u;
const encoder=new TextEncoder(),decoder=new TextDecoder('utf-8',{fatal:true});
const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const check=(value,code='native_extraction_unavailable',status=503)=>requireThat(value,code,status);
const target=r=>({ownerId:r.principalUserId,purpose:'sms_receipt',entityId:r.id,
 plaintextSha256:r.object_sha256,aad:`sms:${r.id}:${r.object_sha256}`});

// The approval is a non-secret operator-supplied digest of the exact build and
// model. A pause, disabled provider, changed deployment or absent approval
// holds extraction without preventing the already-committed capture ACK.
export async function nativeExtractionApproval(env){
 if(env?.BURIMUNSI_NATIVE_UNASSIGNED_EXTRACTION_ENABLED!=='true'||env.MOMO_PROCESSING_PAUSED!=='false'||
  env.MOMO_AI_ENABLED!=='true'||!HASH.test(env.BUILD_SOURCE_ID??'')||!MODEL.test(env.MOMO_AI_MODEL??'')||
  typeof env.OPENAI_API_KEY!=='string'||!env.OPENAI_API_KEY.trim()||typeof env.AI?.run!=='function')return false;
 const expected=await sha256(canonicalJson({contract:'burimunsi.native-unassigned-extraction.v1',
  sourceSha256:env.BUILD_SOURCE_ID,modelId:env.MOMO_AI_MODEL}));
 return env.BURIMUNSI_NATIVE_EXTRACTION_APPROVAL_SHA256===expected;
}

export class PostgresNativeUnassignedExtraction {
 constructor({observations,intake}){
  check(observations instanceof PostgresNativeObservations&&intake instanceof PostgresNativeCanonicalIntake&&
   intake.observations===observations);
  this.observations=observations;this.intake=intake;
 }

 async snapshot(tx,actor,sourceId){
  const o=this.observations,current=await o.current(tx,actor),record=await o.own(tx,actor,sourceId,true);
  check(record!==null,'record_unavailable',404);
  const namespace=await o.namespace(tx),journal=await o.custody.journal(tx,record.object_key,target(record));
  await o.checkJournal(record,journal);
  const rows=await tx.unsafe('SELECT private.burimunsi_observation_hint_profile($1) AS result',[sourceId]);
  check(rows.length===1&&rows[0].result,'native_extraction_profile_changed',409);
  const profile=rows[0].result;
  check(HASH.test(profile.profileSha256??'')&&profile.profile&&validateProviderProfile(profile.profile),
   'native_extraction_profile_changed',409);
  return {identity:o.identity(current),record,namespace,journal,profile};
 }

 async verify(tx,actor,sourceId,initial,binding){
  const o=this.observations,next=await this.snapshot(tx,actor,sourceId);
  check(same(next.identity,initial.identity)&&same(next.record,initial.record)&&same(next.namespace,initial.namespace)&&
   same(next.profile,initial.profile)&&o.custody.sameJournal(next.journal,initial.journal),'native_extraction_changed',409);
  await o.storageWitnesses.sealed(binding,next.record.object_key,next.journal);
  return next;
 }

 /** Runs at most once per source; provider dispatch is committed before I/O.
  * A lost dispatch/finish acknowledgement never causes a second provider call.
  * Provider or authority uncertainty remains visible as a parked review job. */
 async process(actor,sourceId){
  const o=this.observations;requireRequestId(sourceId);
  if(!await nativeExtractionApproval(o.env))return {state:'disabled',financialEffects:0};
  let binding,bytes;
  try{
   await this.intake.stage(actor,sourceId);
   const initial=await o.authority.write(async tx=>{
    const snapshot=await this.snapshot(tx,actor,sourceId);
    binding={kind:'native_provisional_extraction',groupId:o.groupId,requestId:crypto.randomUUID(),
     identity:snapshot.identity,source:snapshot.record};
    const plan=await o.storageWitnesses.stage(binding,[{key:snapshot.record.object_key,journal:snapshot.journal}]);
    return {...snapshot,plan};
   });
   await o.storageWitnesses.prefetch(initial.plan);
   const sealed=await o.storageWitnesses.sealed(binding,initial.record.object_key,initial.journal);
   bytes=await o.custody.decrypt(sealed,target(initial.record).aad);
   check(bytes instanceof Uint8Array&&bytes.length===initial.record.size_bytes&&await digest(bytes)===initial.record.object_sha256);
   const payload=JSON.parse(decoder.decode(bytes));
   check(payload&&payload.provenance==='native_observation_unverified'&&payload.source_mode==='catch_up'&&payload.complete===false&&
    typeof payload.raw_sender==='string'&&payload.raw_sender.length>0&&payload.raw_sender.length<=96&&!CONTROL.test(payload.raw_sender)&&
    typeof payload.raw_body==='string'&&payload.raw_body.length>0&&encoder.encode(payload.raw_body).length<=3000&&
    !CONTROL.test(payload.raw_body)&&await sha256(payload.raw_body)===initial.record.bodySha256,'native_extraction_changed',409);
   const lease=crypto.randomUUID(),profileSha=initial.profile.profileSha256;
   const begun=await o.authority.write(async tx=>{
    await this.verify(tx,actor,sourceId,initial,binding);
    const rows=await tx.unsafe('SELECT private.burimunsi_native_parse_begin($1,$2::uuid,$3) AS result',[sourceId,lease,profileSha]);
    check(rows.length===1&&rows[0].result);return rows[0].result;
   });
   check(begun.sourceId===sourceId&&typeof begun.started==='boolean'&&begun.financialEffects===0&&
    ['processing','needs_review'].includes(begun.state));
   if(!begun.started)return {state:begun.state,financialEffects:0};
   // A lost COMMIT response must throw here before the provider is contacted.
   await o.authority.write(async tx=>{
    await this.verify(tx,actor,sourceId,initial,binding);
    const rows=await tx.unsafe('SELECT private.burimunsi_native_parse_dispatch($1,$2::uuid,$3) AS result',[sourceId,lease,profileSha]);
    check(rows.length===1&&rows[0].result===true);
   });
   let output=null,unknown=false,errors;
   try{
    const result=await o.env.AI.run(MOMO_MODEL,{...momoExtractionRequest(payload),provider_timeout_ms:8000});
    output=result?.response;if(typeof output==='string')output=JSON.parse(output);
    const source={...payload,completeness:'incomplete'},account=initial.profile.profile;
    const validation=validateMomoExtraction(output,source,account,validateProviderProfile(account),{allowIncompleteForReview:true});
    check(validation.accepted===false&&Array.isArray(validation.errors));errors=validation.errors;
    // Never retain hallucinated, malformed, or free-form model issues as facts.
    if(errors.some(e=>['invalid_schema','unsupported_evidence','unsupported_fact','model_reported_issues'].includes(e.code)))output=null;
   }catch{unknown=true;output=null;errors=[{code:'provider_outcome_unknown'}];}
   const codes=new Set(errors.map(e=>e.code));
   if(!codes.has('incomplete_source'))errors.unshift({code:'incomplete_source'});
   if(!codes.has('receiving_account_unverified'))errors.push({code:'receiving_account_unverified'});
   const attempt=crypto.randomUUID();
   return await o.authority.write(async tx=>{
    await this.verify(tx,actor,sourceId,initial,binding);
    const rows=await tx.unsafe('SELECT private.burimunsi_native_parse_finish($1,$2::uuid,$3,$4::uuid,$5,$6::jsonb,$7::jsonb,$8) AS result',
     [sourceId,lease,profileSha,attempt,o.env.MOMO_AI_MODEL,output===null?null:JSON.stringify(output),JSON.stringify(errors),unknown]);
    check(rows.length===1&&rows[0].result?.sourceId===sourceId&&rows[0].result.state==='needs_review'&&
     rows[0].result.financialEffects===0);return rows[0].result;
   });
  }catch(error){
   if(error instanceof BuriError)throw error;
   if(error?.code==='42501')throw new BuriError('access_denied',403);
   if(['40001','23505'].includes(error?.code))throw new BuriError('native_extraction_changed',409);
   throw new BuriError('native_extraction_unavailable',503);
  }finally{bytes?.fill(0);if(binding)o.storageWitnesses.forget(binding);}
 }
}
