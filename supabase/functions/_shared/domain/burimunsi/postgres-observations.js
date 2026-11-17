// Candidate-only, private SMS observations. No wallet or ledger is inferred.
// Not wired into the released runtime until its schema and tests are qualified.
import {BuriError,ObservationUploadUnresolved,requirePort,requireThat} from './errors.js';
import {canonicalJson,exactKeys,requireRequestId,sha256} from './values.js';
import {pgInteger} from './postgres-values.js';
import {hasPhonePinContext} from './phone-pin-request.js';
import {encrypt} from '../encryption.js';
import {digest} from '../core.js';
import {observationDisplayHints} from './observation-display-hints.js';
import {storageEntity,verifyRetainedObject} from '../../storage-identity.js';
import {normalizeListingQuery,selectListing,listingFilterIdentity,listingText} from './listing-query.js';

const ENCODER=new TextEncoder();
const DECODER=new TextDecoder('utf-8',{fatal:true});
const HASH=/^[a-f0-9]{64}$/;
const CONTROL=/[\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/;
// SMS bodies may contain ordinary line breaks or tabs. Other control and bidi
// override characters remain rejected; sender names use the stricter check.
const BODY_CONTROL=/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u202a-\u202e\u2066-\u2069]/;
const REQUIRED_KEYS=['requestId','rawSender','rawBody','sourceMode','complete','capturedAt','serviceCentreAt','inboxReceivedAt','subscriptionId'];
const KEYS=[...REQUIRED_KEYS,'sourceKey'];
const RECONCILE_KEYS=['sourceKey','bodySha256','rawSender','serviceCentreAt','inboxReceivedAt','subscriptionId'];
// Metadata-only check of one deterministic key. The ciphertext itself is never
// returned; PostgreSQL computes its digest solely to validate the reservation.
export const OBSERVATION_UNRESOLVED_SQL=`SELECT i.object_key,i.operation_id,i.fingerprint,i.sha256,i.size,i.scope,
 i.http_metadata,i.custom_metadata,i.state,i.active_attempt,i.upload_unresolved,i.delete_tombstone,
 r.scope AS reservation_scope,r.aad,r.key_id,r.plaintext_sha256,r.source_fingerprint,
 (r.sealed_body IS NOT NULL AND r.cleared_at IS NULL) AS reservation_present,
 CASE WHEN r.sealed_body IS NOT NULL THEN encode(sha256(convert_to(r.sealed_body,'UTF8')),'hex') ELSE NULL END AS reservation_cipher_sha256,
 CASE WHEN r.sealed_body IS NOT NULL THEN octet_length(r.sealed_body) ELSE NULL END AS reservation_cipher_size,
 (m.object_key IS NOT NULL) AS metadata_present,
 CASE WHEN m.object_key IS NOT NULL THEN m.operation_id=i.operation_id AND m.fingerprint=i.fingerprint
  AND m.sha256=i.sha256 AND m.size=i.size AND m.scope=i.scope AND m.http_metadata=i.http_metadata AND m.custom_metadata=i.custom_metadata
  ELSE NULL END AS metadata_matches,
 EXISTS(SELECT 1 FROM private.storage_delete_intents d WHERE d.object_key=i.object_key) AS has_delete
 FROM private.storage_put_intents i LEFT JOIN private.storage_payload_reservations r ON r.object_key=i.object_key
 LEFT JOIN private.storage_objects m ON m.object_key=i.object_key WHERE i.object_key=$1`;
const copy=v=>JSON.parse(canonicalJson(v));
const same=(a,b)=>canonicalJson(a)===canonicalJson(b);
const check=(v,code='observation_unavailable',status=503)=>requireThat(v,code,status);
const int=(v,min=0,max=Number.MAX_SAFE_INTEGER)=>pgInteger(v,{minimum:min,maximum:max,code:'observation_unavailable'});
const text=(v,min,max)=>typeof v==='string'&&v.length>=min&&v.length<=max;
const iso=v=>typeof v==='string'&&/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?Z$/.test(v)&&
  Number.isFinite(Date.parse(v))&&new Date(Date.parse(v)).toISOString().slice(0,19)===v.slice(0,19);
// Preserve all fractional precision while treating equivalent ISO spellings
// (for example .000Z and Z) as the same instant.
const instant=v=>{const [seconds,fraction='']=v.slice(0,-1).split('.');return seconds+'.'+fraction.replace(/0+$/,'')+'Z';};
function mapped(error){
 if(error instanceof BuriError)return error;
 if(error?.code==='23505'||error?.code==='40001')return new BuriError('observation_changed',409);
 if(error?.code==='42501')return new BuriError('access_denied',403);
 if(error?.code==='22023')return new BuriError('invalid_request',400);
 if(error?.code==='54000')return new BuriError('observation_limit',429);
 return new BuriError('observation_unavailable',503);
}
function validateInput(value){
 exactKeys(value,KEYS,REQUIRED_KEYS);const v=copy(value);v.requestId=requireRequestId(v.requestId);
 check(text(v.rawSender,1,96)&&v.rawSender.trim().length>0&&!CONTROL.test(v.rawSender),'invalid_request',400);
 check(text(v.rawBody,1,3000)&&ENCODER.encode(v.rawBody).length<=3000&&!BODY_CONTROL.test(v.rawBody),'invalid_request',400);
 check(iso(v.capturedAt)&&(v.serviceCentreAt===null||iso(v.serviceCentreAt))&&
  (v.inboxReceivedAt===null||iso(v.inboxReceivedAt)),'invalid_request',400);
 check(v.subscriptionId===null||Number.isInteger(v.subscriptionId)&&v.subscriptionId>=0&&v.subscriptionId<=2147483647,'invalid_request',400);
 check((v.sourceMode==='live'&&v.complete===true)||(v.sourceMode==='catch_up'&&v.complete===false&&v.inboxReceivedAt!==null),'invalid_request',400);
 check(v.sourceKey===undefined||(v.sourceMode==='catch_up'&&HASH.test(v.sourceKey)),'invalid_request',400);
 return v;
}
/** Intake is restricted to the dynamically configured provider senders. Do not
 * require incoming-payment wording here: outgoing messages and other provider
 * formats must also reach the parser. Admission itself creates no transaction. */
export function isObservationCandidate(value,profile){
 if(!value||!text(value.rawSender,1,96)||value.rawSender.trim().length===0||CONTROL.test(value.rawSender)||
  !text(value.rawBody,1,3000)||ENCODER.encode(value.rawBody).length>3000||BODY_CONTROL.test(value.rawBody)||
  !profile||!text(profile.version,1,80)||profile.version==='unverified')return false;
 if(!Array.isArray(profile.senders)||profile.senders.length===0||profile.senders.length>30||
  !profile.senders.every(v=>text(v,1,160)&&v.trim().length>0&&!/[\r\n\0]/.test(v)))return false;
 return profile.senders.some(v=>v.toLowerCase()===value.rawSender.toLowerCase());
}
function approvedProfile(ctx,validate){
 check(ctx&&text(ctx.profile_version,1,80)&&ctx.profile_version.trim()===ctx.profile_version&&!CONTROL.test(ctx.profile_version));
 const p=validate(ctx);check(p&&Number.isInteger(p.utc_offset_minutes)&&Math.abs(p.utc_offset_minutes)<=840);
 return {version:ctx.profile_version,offsetMinutes:p.utc_offset_minutes,senders:[...p.sender_allowlist],
  incomingPrefixes:[...p.incoming_prefixes],currencyAliases:[...p.currency_aliases],transactionIdPrefixes:[...p.transaction_id_prefixes]};
}
function consent(v){check(v&&typeof v.enabled==='boolean');return {enabled:v.enabled,generation:int(v.generation)};}
function row(v){
 check(v&&text(v.id,36,36)&&v.sourceId===v.id&&text(v.requestId,36,36)&&HASH.test(v.bodySha256??'')&&
  v.object_key==='sms/'+v.id&&HASH.test(v.object_sha256??'')&&HASH.test(v.fingerprint??'')&&
  text(v.principalUserId,1,128)&&text(v.sessionId,36,36));
 return {...v,size_bytes:int(v.size_bytes,1,131072),createdAt:int(v.createdAt),consentGeneration:int(v.consentGeneration,1)};
}
function target(r){return {ownerId:r.principalUserId,purpose:'sms_receipt',entityId:r.id,
 plaintextSha256:r.object_sha256,aad:`sms:${r.id}:${r.object_sha256}`};}
function payloadFor(v){return {raw_sender:v.rawSender,raw_body:v.rawBody,source_mode:v.sourceMode,
 complete:v.complete,captured_at:v.capturedAt,service_centre_at:v.serviceCentreAt,
 inbox_received_at:v.inboxReceivedAt,subscription_id:v.subscriptionId,provenance:'native_observation_unverified'};}
export async function observationContentFingerprint(value,bodySha){
 return sha256(canonicalJson({rawSender:value.rawSender,bodySha256:bodySha,serviceCentreAt:value.serviceCentreAt,
  inboxReceivedAt:value.inboxReceivedAt,subscriptionId:value.subscriptionId}));
}
function validateReconcileInput(input){
 exactKeys(input,RECONCILE_KEYS);const value=copy(input);
 check(HASH.test(value.sourceKey??'')&&HASH.test(value.bodySha256??'')&&
  text(value.rawSender,1,96)&&value.rawSender.trim().length>0&&!CONTROL.test(value.rawSender)&&
  iso(value.inboxReceivedAt)&&(value.serviceCentreAt===null||iso(value.serviceCentreAt))&&
  (value.subscriptionId===null||Number.isInteger(value.subscriptionId)&&value.subscriptionId>=0&&value.subscriptionId<=2147483647),
  'invalid_request',400);
 return value;
}

/** All authority derives from the existing phone/PIN and installation proof.
 * The SQL functions revalidate and lock it at each write/disclosure boundary. */
export class PostgresNativeObservations {
 constructor({authority,env,validateProviderProfile,custody,storageWitnesses,clock=()=>Date.now()}){
  requirePort(authority,['read','write','session','assertOwned']);requirePort(env?.PRIVATE_MEDIA,['put','get']);
  requirePort(custody,['journal','sameJournal','decrypt']);requirePort(storageWitnesses,['stage','prefetch','sealed','forget']);
  check(typeof validateProviderProfile==='function'&&typeof clock==='function'&&hasPhonePinContext(authority.db));
  Object.assign(this,{authority,env,validateProviderProfile,custody,storageWitnesses,clock,groupId:authority.groupId});
 }
 async current(tx,expected){
  requireRequestId(expected?.id);requireRequestId(expected?.sessionId);
  const a=await this.authority.session(tx,{id:expected.sessionId});
  check(a&&a.id===expected.id&&a.sessionId===expected.sessionId&&a.groupId===this.groupId&&
   a.principalUserId===expected.principalUserId&&a.installationId===expected.installationId&&
   a.role==='admin'&&a.installationProfile==='internal_receiver'&&a.active===true&&a.revoked===false,
   'access_denied',403);
  return a;
 }
 async readConsent(actor){
  try{return await this.authority.read(async tx=>{await this.current(tx,actor);
   const r=await tx.unsafe('SELECT private.burimunsi_observation_consent_current() AS result');
   check(r.length===1);return consent(r[0].result);
  });}catch(error){throw mapped(error);}
 }
 async processingStatus(actor,input){
  exactKeys(input,['sourceIds']);
  check(Array.isArray(input.sourceIds)&&input.sourceIds.length>0&&input.sourceIds.length<=100&&
   new Set(input.sourceIds).size===input.sourceIds.length,'invalid_request',400);
  input.sourceIds.forEach(requireRequestId);
  try{return await this.authority.read(async tx=>{await this.current(tx,actor);
   const r=await tx.unsafe('SELECT private.burimunsi_observation_processing_status($1::jsonb) AS result',[JSON.stringify(input.sourceIds)]);
   const value=r[0]?.result,allowed=new Set(['pending','retrying','parsed','needs_review','conflict','duplicate','security','historical','unknown']);
   check(r.length===1&&value?.groupId===this.groupId&&Array.isArray(value.statuses)&&value.statuses.length===input.sourceIds.length);
   value.statuses.forEach((item,i)=>check(item?.sourceId===input.sourceIds[i]&&allowed.has(item.status)&&typeof item.canRetry==='boolean'&&
    (!item.canRetry||['retrying','needs_review'].includes(item.status))));
   return value;
  });}catch(error){throw mapped(error);}
 }
 async processingRetry(actor,sourceId,input){
  requireRequestId(sourceId);exactKeys(input,['requestId']);requireRequestId(input.requestId);
  try{return await this.authority.write(async tx=>{await this.current(tx,actor);
   const r=await tx.unsafe('SELECT private.burimunsi_observation_processing_retry($1,$2::uuid) AS result',[sourceId,input.requestId]);
   const value=r[0]?.result;
   check(r.length===1&&value?.groupId===this.groupId&&value.sourceId===sourceId&&value.requestId===input.requestId&&
    ['scheduled','not_eligible'].includes(value.result));return value;
  });}catch(error){throw mapped(error);}
 }
 /** Compare only a phone-supplied, opaque inbox identity and content digest.
  * latestRecordedSourceId is current-actor retention order; it is not proof of
  * phone chronology, and a missing key never starts an upload or financial work. */
 async reconcile(actor,input){
  const value=validateReconcileInput(input);
  const contentSha=await observationContentFingerprint(value,value.bodySha256);
  const latest=async tx=>{
   // The page's existing SECURITY DEFINER scopes to the active account and
   // authorized historical grants. It orders by retention time, not SMS time.
   const page=await tx.unsafe('SELECT private.burimunsi_observation_page($1,$2,$3,$4) AS result',['','all',1,0]);
   check(page.length===1&&HASH.test(page[0].result?.revision??''));
   const result=page[0].result,total=int(result.totalCount,0,100000);
   check(Array.isArray(result.items)&&result.items.length===Math.min(total,1));
   return result.items.length?requireRequestId(result.items[0].id):null;
  };
  const snapshot=async(tx,includeLatest)=>{
   const {ctx,profile}=await this.context(tx,actor);
   // Retain the existing dynamic sender admission. No SMS body is sent to this endpoint.
   check(isObservationCandidate({rawSender:value.rawSender,rawBody:'x'},profile),'unsupported_receipt',422);
   const found=await tx.unsafe('SELECT private.burimunsi_observation_key_lookup($1,$2,$3) AS result',
    [value.sourceKey,contentSha,value.bodySha256]);
   check(found.length===1);const record=found[0].result===null?null:row(found[0].result);
   if(record)check(record.bodySha256===value.bodySha256&&record.sessionId===actor.sessionId,'observation_changed',409);
   const candidates=record?[]:await this.legacyCandidates(tx,actor,value.bodySha256);
   const latestRecordedSourceId=includeLatest?await latest(tx):null;
   return {ctx,record,candidates,latestRecordedSourceId};
  };
  try{
   // Repeatable-read snapshots keep the key and latest retained page in one
   // view. A pending reservation or changed storage raises; neither is absence.
   const initial=await this.authority.read(async tx=>{
    const first=await snapshot(tx,false);
    return first.record||first.candidates.length?first:{...first,latestRecordedSourceId:await latest(tx)};
   });
   if(!initial.record&&!initial.candidates.length){
    await this.authority.assertOwned();
    return {groupId:this.groupId,sourceKey:value.sourceKey,state:'missing',sourceId:null,
     latestRecordedSourceId:initial.latestRecordedSourceId};
   }
   // Verify actual retained bytes and custody, not a local "seen" marker.
   const legacy=initial.record?null:await this.checkLegacyCandidates(actor,value,initial.ctx,initial.candidates);
   if(initial.record)await this.checkDuplicate(actor,value,contentSha,value.bodySha256,initial.record);
   if(legacy)await this.authority.write(async tx=>{
    const fenced=await snapshot(tx,false);
    check(same(fenced.ctx,initial.ctx)&&same(fenced.record,initial.record)&&same(fenced.candidates,initial.candidates),'observation_changed',409);
    check(same(await this.namespace(tx),legacy.namespace),'observation_changed',409);
    for(let i=0;i<initial.candidates.length;i++){
     const prior=initial.candidates[i],journal=await this.custody.journal(tx,prior.object_key,target(prior));
     await this.checkJournal(prior,journal);check(this.custody.sameJournal(journal,legacy.journals[i]),'observation_changed',409);
    }
   });
   const final=await this.authority.read(tx=>snapshot(tx,true));
   check(same(final.record,initial.record)&&same(final.candidates,initial.candidates)&&same(final.ctx,initial.ctx),'observation_changed',409);
   await this.authority.assertOwned();
   const matched=final.record??legacy?.match??null;
   return {groupId:this.groupId,sourceKey:value.sourceKey,state:matched?'matched':'missing',sourceId:matched?.id??null,
    latestRecordedSourceId:final.latestRecordedSourceId};
  }catch(error){throw mapped(error);}
 }
 /** Verify a bounded set of phone witnesses. Each result describes the final
  * authorized snapshot; this never writes observations or financial state. */
 async reconcileBatch(actor,input){
  exactKeys(input,['items']);
  check(Array.isArray(input.items)&&input.items.length>=1&&input.items.length<=20,'invalid_request',400);
  const values=input.items.map(validateReconcileInput);
  check(new Set(values.map(v=>v.sourceKey)).size===values.length,'invalid_request',400);
  const hashes=await Promise.all(values.map(v=>observationContentFingerprint(v,v.bodySha256)));
  const snapshot=async tx=>{
   const {ctx,profile}=await this.context(tx,actor),records=[],candidates=[];
   for(let i=0;i<values.length;i++){
    const v=values[i];
    check(isObservationCandidate({rawSender:v.rawSender,rawBody:'x'},profile),'unsupported_receipt',422);
    let found;
    try{found=await tx.unsafe('SELECT private.burimunsi_observation_key_lookup($1,$2,$3) AS result',
     [v.sourceKey,hashes[i],v.bodySha256]);}
    catch(error){
     // SQL gives a definite per-key conflict or an outstanding/invalid
     // reservation. Other database failures remain generic.
     if(error?.code==='23505'&&error.message==='burimunsi_observation_source_conflict')
      throw new BuriError('observation_item_conflict',409);
     if(error?.code==='55000'&&['burimunsi_observation_source_pending','burimunsi_observation_storage_changed'].includes(error.message))
      throw new BuriError('observation_item_unavailable',503);
     throw error;
    }
    check(found.length===1);const record=found[0].result===null?null:row(found[0].result);
    if(record)check(record.bodySha256===v.bodySha256&&record.sessionId===actor.sessionId,'observation_changed',409);
    records.push(record);
    candidates.push(record?[]:await this.legacyCandidates(tx,actor,v.bodySha256));
   }
   return {ctx,records,candidates};
  };
  let initial;const legacy=new Map();
  try{
   initial=await this.authority.read(snapshot);
   check(initial.candidates.reduce((n,items)=>n+items.length,0)<=20,'observation_item_unavailable',503);
   // Both the custody checks and Storage's journal reads acquire the same
   // database mutation lock. Serialize complete item checks within this batch
   // so its own workers cannot exhaust the lock timeout against each other.
   // No transaction or mutation lock is held during network operations.
   const indexes=initial.records.map((record,i)=>record||initial.candidates[i].length?i:-1).filter(i=>i>=0);
   let next=0,failure=null;
   let verificationTail=Promise.resolve();
   const serialize=fn=>{
    const task=verificationTail.then(fn);
    // Drain already-started workers even if one item fails; that prevents an
    // item-specific conflict from hiding an independently observed outage.
    verificationTail=task.then(()=>{},()=>{});
    return task;
   };
   const itemFailure=error=>error instanceof BuriError&&
    ['observation_item_conflict','observation_item_unavailable'].includes(error.code);
   const worker=async()=>{
    while(!failure&&next<indexes.length){
     const i=indexes[next++];
     try{
      if(initial.records[i])await serialize(()=>this.checkDuplicateObject(values[i],hashes[i],values[i].bodySha256,initial.records[i]));
      else legacy.set(i,await serialize(()=>this.checkLegacyCandidates(actor,values[i],initial.ctx,initial.candidates[i],values.length===1)));
     }
     catch(error){
      if(error instanceof BuriError&&error.code==='observation_changed')error=new BuriError('observation_item_conflict',409);
      else if(['receipt_unavailable','receipt_integrity_failed'].includes(error?.code))error=new BuriError('observation_item_unavailable',503);
      // Do not let an item issue mask an independently observed outage or
      // revoked request while other bounded reads are still settling.
      if(!failure||itemFailure(failure)&&!itemFailure(error))failure=error;
     }
    }
   };
   await Promise.all(Array.from({length:Math.min(3,indexes.length)},worker));
   if(failure)throw failure;
   if(indexes.length){
    // The normal custody fence serializes journal verification with storage
    // mutation; it does not itself write an observation or financial record.
    const singleton=legacy.get(indexes[0]);let itemFinalPending=Boolean(singleton?.binding);
    try{
     await this.authority.write(async tx=>{
      if(itemFinalPending){
       // Keep the original item validation and its error boundary ahead of the
       // batch-wide checks. Storage bytes are already prefetched outside SQL.
       await this.verifyLegacyFinal(tx,actor,values[0],initial.ctx,initial.candidates[0],singleton);
       itemFinalPending=false;
      }
      const fenced=await snapshot(tx);
      check(same(fenced.ctx,initial.ctx)&&same(fenced.records,initial.records)&&same(fenced.candidates,initial.candidates),'observation_changed',409);
      if(legacy.size){const namespace=await this.namespace(tx);
       for(const proof of legacy.values())check(same(namespace,proof.namespace),'observation_changed',409);}
      for(const i of indexes){
       const records=initial.records[i]?[initial.records[i]]:initial.candidates[i];
       for(let j=0;j<records.length;j++){
        const prior=records[j],journal=await this.custody.journal(tx,prior.object_key,target(prior));await this.checkJournal(prior,journal);
        if(!initial.records[i])check(this.custody.sameJournal(journal,legacy.get(i).journals[j]),'observation_changed',409);
       }
      }
     });
    }catch(error){
     if(itemFinalPending){
      const failure=mapped(error);
      if(failure.code==='observation_changed')throw new BuriError('observation_item_conflict',409);
      if(failure.status===403||failure.status===409)throw failure;
      throw new BuriError('observation_item_unavailable',503);
     }
     throw error;
    }
    if(singleton?.binding)await this.authority.assertOwned();
   }
   // authority.read is REPEATABLE READ, so the keys and authorization are
   // rechecked together after the network and custody operations.
   const final=await this.authority.read(snapshot);
   check(same(final.ctx,initial.ctx)&&same(final.records,initial.records)&&same(final.candidates,initial.candidates),'observation_changed',409);
   const matches=final.records.map((r,i)=>r??legacy.get(i)?.match??null),ids=matches.filter(Boolean).map(r=>r.id);
   check(new Set(ids).size===ids.length,'observation_item_conflict',409);
   await this.authority.assertOwned();
   return {groupId:this.groupId,items:values.map((v,i)=>({sourceKey:v.sourceKey,
    state:matches[i]?'matched':'missing',sourceId:matches[i]?.id??null}))};
  }catch(error){
   if(error instanceof BuriError&&['observation_item_conflict','observation_item_unavailable'].includes(error.code)){
    // The error itself reveals no key or content. Still recheck current
    // authority and context after any asynchronous read before releasing it.
    try{
     const current=await this.authority.read(tx=>this.context(tx,actor));
     if(initial)check(same(current.ctx,initial.ctx),'observation_changed',409);
     await this.authority.assertOwned();
    }catch(recheckError){throw mapped(recheckError);}
   }
   throw mapped(error);
  }finally{
   for(const proof of legacy.values())if(proof.binding)this.storageWitnesses.forget(proof.binding);
  }
 }
 /** Collection-wide metadata only; actor and consent are current in the same
  * repeatable-read transaction as the underlying reservation snapshot. */
 async reconcileStatus(actor){
  try{
   const result=await this.authority.read(async tx=>{
    await this.context(tx,actor);
    const rows=await tx.unsafe('SELECT private.burimunsi_observation_reconcile_status() AS result');
    check(rows.length===1);const value=rows[0].result;
    check(value&&value.groupId===this.groupId&&typeof value.hasPending==='boolean'&&
     typeof value.hasRecorded==='boolean'&&typeof value.hasUnmatchedCanonical==='boolean'&&
     Number.isSafeInteger(value.recordedCount)&&value.recordedCount>=0&&value.recordedCount<=100000&&
     value.hasRecorded===(value.recordedCount>0)&&HASH.test(value.revision??''));
    return {groupId:this.groupId,hasPending:value.hasPending,hasRecorded:value.hasRecorded,
     recordedCount:value.recordedCount,hasUnmatchedCanonical:value.hasUnmatchedCanonical,revision:value.revision};
   });
   await this.authority.assertOwned();return result;
  }catch(error){throw mapped(error);}
 }
 async setConsent(actor,value){
  exactKeys(value,['enabled','generation']);check(typeof value.enabled==='boolean'&&Number.isSafeInteger(value.generation)&&value.generation>=1,'invalid_request',400);
  try{return await this.authority.write(async tx=>{await this.current(tx,actor);
   const r=await tx.unsafe('SELECT private.burimunsi_observation_set_consent($1,$2::bigint) AS result',[value.enabled,value.generation]);
   check(r.length===1);const result=consent(r[0].result);check(same(result,value));return result;
  });}catch(error){throw mapped(error);}
 }
 async context(tx,actor){
  const a=await this.current(tx,actor),r=await tx.unsafe('SELECT private.burimunsi_observation_context() AS result');
  check(r.length===1&&r[0].result);const ctx=r[0].result;
  check(ctx.collectionId===a.groupId&&ctx.accountId===a.id&&ctx.principalUserId===a.principalUserId&&
   ctx.sessionId===a.sessionId&&ctx.installationId===a.installationId&&HASH.test(ctx.profile_sha256??'')&&HASH.test(ctx.profile_tuple_sha256??''));
  ctx.consentGeneration=int(ctx.consentGeneration,1);return {ctx,profile:approvedProfile(ctx,this.validateProviderProfile)};
 }
 async profile(actor){
  try{return await this.authority.read(async tx=>{const {profile:p}=await this.context(tx,actor),now=this.clock();
   check(Number.isSafeInteger(now)&&now>0&&now<=Number.MAX_SAFE_INTEGER-86400000);
   const legacy=await tx.unsafe('SELECT private.burimunsi_observation_legacy_present() AS result');
   check(legacy.length===1&&typeof legacy[0].result==='boolean');
   return {profileVersion:p.version,offsetMinutes:p.offsetMinutes,senders:p.senders,incomingPrefixes:p.incomingPrefixes,
    currencyAliases:p.currencyAliases,transactionIdPrefixes:p.transactionIdPrefixes,issuedAt:now,expiresAt:now+86400000,legacyHold:legacy[0].result};
  });}catch(error){throw mapped(error);}
 }
 async find(tx,actor,requestId,fingerprint){
  await this.current(tx,actor);const r=await tx.unsafe('SELECT private.burimunsi_observation_lookup($1::uuid,$2) AS result',[requestId,fingerprint]);
  check(r.length===1);return r[0].result===null?null:row(r[0].result);
 }
 async prepare(actor,value,fingerprint,id,initial,contentSha,bodySha){
  return this.authority.write(async tx=>{
   await this.current(tx,actor);
   const result=value.sourceKey?await tx.unsafe('SELECT private.burimunsi_observation_key_prepare($1,$2,$3,$4::uuid,$5,$6,$7,$8,$9::bigint) AS result',
    [value.sourceKey,contentSha,bodySha,value.requestId,fingerprint,id,initial.profile.version,initial.ctx.profile_sha256,initial.ctx.consentGeneration]):
    await tx.unsafe('SELECT private.burimunsi_observation_legacy_retry_prepare($1::uuid,$2,$3,$4,$5,$6::bigint) AS result',
     [value.requestId,fingerprint,id,initial.profile.version,initial.ctx.profile_sha256,initial.ctx.consentGeneration]);
   check(result.length===1&&result[0].result);const selected=result[0].result;
   if(value.sourceKey&&selected.kind==='duplicate')return {kind:'duplicate',record:row(selected.record)};
   if(value.sourceKey)check(selected.kind==='new');const prepared=value.sourceKey?selected.context:selected;
   check(prepared.requestId===value.requestId&&prepared.sourceId===id&&prepared.fingerprint===fingerprint&&
    prepared.collectionId===initial.ctx.collectionId&&prepared.accountId===initial.ctx.accountId&&
    prepared.principalUserId===initial.ctx.principalUserId&&prepared.sessionId===initial.ctx.sessionId&&
    prepared.installationId===initial.ctx.installationId&&prepared.grantId===initial.ctx.grantId&&
    prepared.profile_sha256===initial.ctx.profile_sha256&&prepared.profile_tuple_sha256===initial.ctx.profile_tuple_sha256&&
    int(prepared.consentGeneration,1)===initial.ctx.consentGeneration&&
    same(approvedProfile(prepared,this.validateProviderProfile),initial.profile),'observation_changed',409);
   return {kind:'new'};
  });
 }
 async checkDuplicateObject(value,contentSha,bodySha,prior){
  let bytes;try{
   await this.authority.assertOwned();bytes=await verifyRetainedObject(this.env,prior);await this.authority.assertOwned();
   const p=JSON.parse(DECODER.decode(bytes));
   check(p&&p.provenance==='native_observation_unverified'&&p.source_mode==='catch_up'&&p.complete===false&&
    typeof p.raw_body==='string'&&await sha256(p.raw_body)===bodySha&&
    await observationContentFingerprint({rawSender:p.raw_sender,serviceCentreAt:p.service_centre_at,
     inboxReceivedAt:p.inbox_received_at,subscriptionId:p.subscription_id},bodySha)===contentSha,'observation_changed',409);
  }finally{bytes?.fill(0);}
 }
 /** Internal candidate descriptors never leave the Edge runtime. The SQL
  * lookup requires reveal-authorized current Admin and consent, constrains the
  * imported lineage to this account/collection, and caps the complete set. */
 async legacyCandidates(tx,actor,bodySha){
  let found;
  try{found=await tx.unsafe('SELECT private.burimunsi_observation_legacy_candidates($1) AS result',[bodySha]);}
  catch(error){if(error?.code==='55000')throw new BuriError('observation_item_unavailable',503);throw error;}
  check(found.length===1&&Array.isArray(found[0].result)&&found[0].result.length<=4);
  const records=found[0].result.map(row);
  check(records.every(r=>r.bodySha256===bodySha&&r.sessionId===actor.sessionId)&&
   new Set(records.map(r=>r.id)).size===records.length,'observation_changed',409);
  return records;
 }
 /** Revalidate only a previously staged, decrypted legacy witness. This runs
  * inside an authority fence; sealed() checks local ciphertext and ownership
  * without fetching from Storage. The caller maps errors at its own boundary. */
 async verifyLegacyFinal(tx,actor,value,expectedCtx,candidates,proof){
  const {ctx}=await this.context(tx,actor),current=await this.legacyCandidates(tx,actor,value.bodySha256);
  check(same(ctx,expectedCtx)&&same(current,candidates)&&same(await this.namespace(tx),proof.namespace),'observation_changed',409);
  for(let i=0;i<current.length;i++){
   const record=current[i],journal=await this.custody.journal(tx,record.object_key,target(record));
   await this.checkJournal(record,journal);check(this.custody.sameJournal(journal,proof.journals[i]),'observation_changed',409);
   await this.storageWitnesses.sealed(proof.binding,record.object_key,journal);
  }
 }
 /** Decrypt only after proving the committed ciphertext against its journal.
  * Missing metadata, unavailable objects, multiple exact matches and any
  * changed authority/custody remain unresolved; this method creates no data. */
 async checkLegacyCandidates(actor,value,expectedCtx,candidates,deferValidation=false){
  let binding,release=true;
  try{
   const initial=await this.authority.write(async tx=>{
    const {ctx}=await this.context(tx,actor),current=await this.legacyCandidates(tx,actor,value.bodySha256);
    check(same(ctx,expectedCtx)&&same(current,candidates),'observation_changed',409);
    const namespace=await this.namespace(tx),journals=[];
    for(const record of current){
     const journal=await this.custody.journal(tx,record.object_key,target(record));await this.checkJournal(record,journal);journals.push(journal);
    }
    binding={kind:'legacy_reconcile',groupId:this.groupId,identity:this.identity(actor),sourceKey:value.sourceKey,sources:current};
    const plan=await this.storageWitnesses.stage(binding,current.map((record,i)=>({key:record.object_key,journal:journals[i]})));
    return {namespace,journals,plan};
   });
   await this.storageWitnesses.prefetch(initial.plan);
   const matches=[];
   for(let i=0;i<candidates.length;i++){
    const record=candidates[i];let bytes;
    try{
     const sealed=await this.storageWitnesses.sealed(binding,record.object_key,initial.journals[i]);
     bytes=await this.custody.decrypt(sealed,target(record).aad);
     check(bytes instanceof Uint8Array&&bytes.length===record.size_bytes&&await digest(bytes)===record.object_sha256,
      'observation_item_unavailable',503);
     const p=JSON.parse(DECODER.decode(bytes));
     check(p&&p.provenance==='native_observation_unverified'&&
      (p.source_mode==='live'&&p.complete===true||p.source_mode==='catch_up'&&p.complete===false)&&
      text(p.raw_sender,1,96)&&!CONTROL.test(p.raw_sender)&&text(p.raw_body,1,3000)&&
      ENCODER.encode(p.raw_body).length<=3000&&!BODY_CONTROL.test(p.raw_body)&&await sha256(p.raw_body)===value.bodySha256&&
      iso(p.inbox_received_at)&&Object.hasOwn(p,'service_centre_at')&&
      (p.service_centre_at===null||iso(p.service_centre_at))&&Object.hasOwn(p,'subscription_id')&&
      (p.subscription_id===null||Number.isInteger(p.subscription_id)&&p.subscription_id>=0&&p.subscription_id<=2147483647),
      'observation_item_unavailable',503);
     // Null and present optional metadata cannot be safely compared.
     if((p.service_centre_at===null)!==(value.serviceCentreAt===null)||
      (p.subscription_id===null)!==(value.subscriptionId===null))throw new BuriError('observation_item_unavailable',503);
     if(p.raw_sender===value.rawSender&&instant(p.inbox_received_at)===instant(value.inboxReceivedAt)&&
      (p.service_centre_at===null||instant(p.service_centre_at)===instant(value.serviceCentreAt))&&
      p.subscription_id===value.subscriptionId)matches.push(record);
    }finally{bytes?.fill(0);}
   }
   check(matches.length<=1,'observation_item_conflict',409);
   await this.authority.assertOwned();
   // For the singleton batch only, the caller performs these same final
   // authorization, candidate, namespace, journal and sealed-witness checks
   // in its existing batch-wide transaction, then releases the witness.
   if(deferValidation){
    release=false;
    return {match:matches[0]??null,journals:initial.journals,namespace:initial.namespace,binding};
   }
   await this.authority.write(tx=>this.verifyLegacyFinal(tx,actor,value,expectedCtx,candidates,{...initial,binding}));
   await this.authority.assertOwned();
   return {match:matches[0]??null,journals:initial.journals,namespace:initial.namespace};
  }catch(error){
   const failure=mapped(error);
   if(failure.status===403||failure.status===409)throw failure;
   throw new BuriError('observation_item_unavailable',503);
  }finally{if(binding&&release)this.storageWitnesses.forget(binding);}
 }
 async checkDuplicate(actor,value,contentSha,bodySha,prior){
  await this.checkDuplicateObject(value,contentSha,bodySha,prior);
  await this.authority.write(async tx=>{
    await this.current(tx,actor);
    const rows=await tx.unsafe('SELECT private.burimunsi_observation_key_lookup($1,$2,$3) AS result',[value.sourceKey,contentSha,bodySha]);
    check(rows.length===1&&rows[0].result&&same(row(rows[0].result),prior),'observation_changed',409);
    const journal=await this.custody.journal(tx,prior.object_key,target(prior));await this.checkJournal(prior,journal);
  });
  await this.authority.assertOwned();
 }
 async checkJournal(r,journal){
  const keyId=journal?.reservation?.key_id;
  check(text(keyId,1,128));
  const t=target(r),descriptor={scope:{ownerId:t.ownerId,purpose:t.purpose,entityId:t.entityId},
   aad:t.aad,keyId,plaintextSha256:r.object_sha256,requestDigest:r.fingerprint,
   httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:r.object_sha256,key_id:keyId}};
  check(await sha256(canonicalJson(descriptor))===journal.reservation.source_fingerprint);
 }
 async checkRetained(actor,r,payload,bodySha){
  check(r.bodySha256===bodySha&&r.object_sha256===await digest(ENCODER.encode(JSON.stringify(payload))));
  let bytes;try{
   await this.authority.assertOwned();bytes=await verifyRetainedObject(this.env,r);await this.authority.assertOwned();
   check(same(JSON.parse(DECODER.decode(bytes)),payload));
   await this.authority.write(async tx=>{
    const current=await this.find(tx,actor,r.requestId,r.fingerprint);check(current&&same(current,r),'observation_changed',409);
    const journal=await this.custody.journal(tx,r.object_key,target(r));await this.checkJournal(r,journal);
   });
  }finally{bytes?.fill(0);}
 }
 /** Verify the exact request's durable encrypted reservation, not a remote
  * object or a successful upload. The monotonic unknown flag is never cleared.
  * This method takes the normal fenced authorization transaction, but writes
  * no observation, storage state, acknowledgement or financial record. */
 async uploadUnresolved(actor,value,fingerprint,id,initial,objectSha){
  const result=await this.authority.write(async tx=>{
   const current=await this.context(tx,actor);
   check(same(current.ctx,initial.ctx)&&same(current.profile,initial.profile),'observation_changed',409);
   const retained=await this.find(tx,actor,value.requestId,fingerprint);
   if(retained)return false;
   const rows=await tx.unsafe(OBSERVATION_UNRESOLVED_SQL,['sms/'+id]);
   check(rows.length<=1);if(!rows.length||rows[0].upload_unresolved!==true)return false;
   const r=rows[0],key='sms/'+id,scope={ownerId:actor.principalUserId,purpose:'sms_receipt',entityId:id};
   check(r.object_key===key&&['pending','committed'].includes(r.state)&&r.delete_tombstone===false&&r.has_delete===false&&
    r.reservation_present===true&&typeof r.key_id==='string'&&/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/.test(r.key_id)&&
    HASH.test(r.sha256??'')&&r.sha256===r.reservation_cipher_sha256&&r.plaintext_sha256===objectSha&&
    int(r.size,1,524288)===int(r.reservation_cipher_size,1,524288)&&same(r.scope,scope)&&same(r.reservation_scope,scope)&&
    r.aad===`sms:${id}:${objectSha}`&&r.operation_id===await sha256('collect.storage.put.v1\n'+key)&&
    (r.state==='committed'?r.metadata_present===true&&r.metadata_matches===true:r.metadata_present===false));
   const descriptor={scope,aad:r.aad,keyId:r.key_id,plaintextSha256:objectSha,requestDigest:fingerprint,
    httpMetadata:{contentType:'application/octet-stream'},customMetadata:{sha256:objectSha,key_id:r.key_id}};
   const sourceFingerprint=await sha256(canonicalJson(descriptor));
   const customMetadata={...descriptor.customMetadata,source_fingerprint:sourceFingerprint};
   const objectDescriptor={key,size:int(r.size,1,524288),sha256:r.sha256,scope,httpMetadata:descriptor.httpMetadata,customMetadata};
   check(r.source_fingerprint===sourceFingerprint&&same(r.http_metadata,descriptor.httpMetadata)&&same(r.custom_metadata,customMetadata)&&
    r.fingerprint===await sha256(canonicalJson(objectDescriptor)));
   return true;
  });
  await this.authority.assertOwned();return result;
 }
 async unresolvedAfterFailure(actor,value,fingerprint,id,initial,objectSha,original){
  try{if(await this.uploadUnresolved(actor,value,fingerprint,id,initial,objectSha))throw new ObservationUploadUnresolved(value.requestId);}
  catch(error){
   if(error instanceof ObservationUploadUnresolved||error?.code==='42501'||error instanceof BuriError&&[401,403].includes(error.status))throw error;
   // A missing/changed journal or an unavailable status check is not evidence.
  }
  if(original instanceof BuriError&&original.code==='observation_upload_unresolved')
   throw new BuriError('observation_unavailable',503);
  throw original;
 }
 async observe(actor,input){
  const value=validateInput(input),bodySha=await sha256(value.rawBody),payload=payloadFor(value),
   contentSha=value.sourceKey?await observationContentFingerprint(value,bodySha):null;
  // This identity is stable across a short-lease renewal, but cannot move to a
  // different native account, installation, group, source, or SMS bytes.
  const fingerprint=await sha256(canonicalJson({groupId:this.groupId,accountId:actor.id,installationId:actor.installationId,
   requestId:value.requestId,bodySha256:bodySha,rawSender:value.rawSender,sourceMode:value.sourceMode,complete:value.complete,
   capturedAt:value.capturedAt,serviceCentreAt:value.serviceCentreAt,inboxReceivedAt:value.inboxReceivedAt,subscriptionId:value.subscriptionId,
   ...(value.sourceKey?{sourceKey:value.sourceKey}: {})}));
  try{
   let prior=await this.authority.read(tx=>this.find(tx,actor,value.requestId,fingerprint));
   if(prior){await this.checkRetained(actor,prior,payload,bodySha);
    const final=await this.authority.read(tx=>this.find(tx,actor,value.requestId,fingerprint));
    check(final&&same(final,prior),'observation_changed',409);return {requestId:value.requestId,sourceId:prior.id,bodySha256:bodySha,status:'source_unresolved',financialEffects:0};}
   const initial=await this.authority.read(tx=>this.context(tx,actor));
   check(isObservationCandidate(value,initial.profile),'unsupported_receipt',422);
   const id=await storageEntity('burimunsi.native.observation.v1',actor.principalUserId,value.requestId);
   // The admission is durable before any object reservation or provider call.
   // A retry reuses the same intent; uncertainty never consumes another slot.
   const prepared=await this.prepare(actor,value,fingerprint,id,initial,contentSha,bodySha);
   if(prepared.kind==='duplicate'){
    await this.checkDuplicate(actor,value,contentSha,bodySha,prepared.record);
    return {requestId:value.requestId,sourceId:prepared.record.id,bodySha256:bodySha,status:'source_unresolved',financialEffects:0};
   }
   const bytes=ENCODER.encode(JSON.stringify(payload)),objectSha=await digest(bytes),objectKey='sms/'+id;
   try{
    if(await this.uploadUnresolved(actor,value,fingerprint,id,initial,objectSha))throw new ObservationUploadUnresolved(value.requestId);
    const sealed=await encrypt(this.env,bytes,`sms:${id}:${objectSha}`);await this.authority.assertOwned();
    try{await this.env.PRIVATE_MEDIA.put(objectKey,sealed,{scope:{ownerId:actor.principalUserId,purpose:'sms_receipt',entityId:id},
      aad:`sms:${id}:${objectSha}`,sourceDigest:fingerprint,httpMetadata:{contentType:'application/octet-stream'},
      customMetadata:{sha256:objectSha,key_id:this.env.DATA_KEY_ID}});
    }catch(error){await this.unresolvedAfterFailure(actor,value,fingerprint,id,initial,objectSha,error);}
   }finally{bytes.fill(0);}
   let committed;
   try{committed=await this.authority.write(async tx=>{await this.current(tx,actor);
    // A provider upload whose outcome is unknown is not authority failure and
    // cannot be acknowledged as retained. Preserve the exact admission and
    // ciphertext; an operator must resolve the outstanding storage outcome.
    const state=await tx.unsafe('SELECT state,active_attempt,upload_unresolved,delete_tombstone FROM private.storage_put_intents WHERE object_key=$1 FOR UPDATE',[objectKey]);
    check(state.length===1&&state[0].state==='committed'&&state[0].delete_tombstone===false,'observation_unavailable',503);
    check(state[0].active_attempt===null&&state[0].upload_unresolved===false,'observation_upload_unresolved',503);
    const r=await tx.unsafe('SELECT private.burimunsi_observation_commit($1::uuid,$2,$3,$4,$5,$6::bigint,$7,$8,$9::bigint) AS result',
     [value.requestId,fingerprint,id,bodySha,objectSha,ENCODER.encode(JSON.stringify(payload)).length,
      initial.profile.version,initial.ctx.profile_sha256,initial.ctx.consentGeneration]);
    check(r.length===1);return row(r[0].result);
   });}catch(error){
    // An uncertain transaction outcome is reconciled against the same immutable
    // request, never replayed as a new SMS or acknowledged on a storage PUT.
    prior=await this.authority.read(tx=>this.find(tx,actor,value.requestId,fingerprint));
    if(!prior){if(error instanceof BuriError&&error.code==='observation_upload_unresolved')
      await this.unresolvedAfterFailure(actor,value,fingerprint,id,initial,objectSha,error);
     throw error;}committed=prior;
   }
   await this.checkRetained(actor,committed,payload,bodySha);
   const final=await this.authority.read(tx=>this.find(tx,actor,value.requestId,fingerprint));
   check(final&&same(final,committed),'observation_changed',409);
   return {requestId:value.requestId,sourceId:committed.id,bodySha256:bodySha,status:'source_unresolved',financialEffects:0};
  }catch(error){throw mapped(error);}
 }
 async page(actor,query,cursor){
  requirePort(cursor,['create','read']);
  const listing=normalizeListingQuery('observations',query),{q,limit}=listing;
  if(query.cursor!==undefined)check(typeof query.cursor==='string'&&query.cursor.length>0,'invalid_cursor',400);
  const filterHash=await sha256(canonicalJson({kind:'own_observations',q,installationId:actor.installationId}));
  try{return await this.authority.read(async tx=>{
   await this.current(tx,actor);
   if(listing.advanced){
    // Reuse the existing security-definer's exact own-installation authority
    // and metadata projection, within one read snapshot. No body is read.
    const first=await tx.unsafe('SELECT private.burimunsi_observation_page($1,$2,$3,$4) AS result',[q,'all',100,0]);
    check(first.length===1&&HASH.test(first[0].result?.revision??''));
    const initial=first[0].result,total=int(initial.totalCount,0,100000),raw=[...initial.items];
    for(let offset=100;offset<total;offset+=100){
     const part=await tx.unsafe('SELECT private.burimunsi_observation_page($1,$2,$3,$4) AS result',[q,'all',100,offset]);
     check(part.length===1&&part[0].result?.revision===initial.revision&&part[0].result.totalCount===total&&Array.isArray(part[0].result.items));
     raw.push(...part[0].result.items);
    }
    check(raw.length===total);
    const entries=raw.map(value=>{check(text(value.id,36,36));const at=new Date(int(value.createdAt)).toISOString();
     return {item:{id:value.id,groupId:this.groupId,sourceKind:'observation',sourceId:value.id,status:'source_unresolved',at,financialEffects:0},at,search:listingText(value.id)};});
    const revision=await sha256(canonicalJson({retained:initial.revision,entries})),now=this.clock();
    const scope={groupId:this.groupId,actorId:actor.id,snapshot:revision,filterHash:await sha256(canonicalJson({kind:'own_observations',installationId:actor.installationId,...listingFilterIdentity(listing)})),sort:listing.sort};
    const after=query.cursor?await cursor.read(query.cursor,scope,now):null;
    const selected=selectListing(entries,'observations',listing,after,new Date(now).toISOString());
    const nextCursor=selected.after?await cursor.create({...scope,after:selected.after,expiresAt:now+15*60*1000}):null;
    return {items:selected.items,totalCount:selected.totalCount,nextCursor,revision,asOf:selected.asOf};
   }
   const first=await tx.unsafe('SELECT private.burimunsi_observation_page($1,$2,$3,$4) AS result',[q,'all',limit,0]);
   check(first.length===1&&HASH.test(first[0].result?.revision??''));
   const scope={groupId:this.groupId,actorId:actor.id,snapshot:first[0].result.revision,filterHash,sort:'newest'};
   const after=query.cursor?await cursor.read(query.cursor,scope,this.clock()):null;
   const offset=after?.offset??0;
   check(Number.isSafeInteger(offset)&&offset>=0&&offset<=100000,'invalid_cursor',400);
   const selected=offset===0?first:await tx.unsafe('SELECT private.burimunsi_observation_page($1,$2,$3,$4) AS result',[q,'all',limit,offset]);
   check(selected.length===1&&selected[0].result?.revision===scope.snapshot);
   const result=selected[0].result,total=int(result.totalCount,0,100000),now=this.clock();
   check(Array.isArray(result.items)&&result.items.length===Math.max(0,Math.min(limit,total-offset))&&
    Number.isSafeInteger(now)&&now>0);
   const items=result.items.map(value=>{
    check(text(value.id,36,36));const at=new Date(int(value.createdAt)).toISOString();
    return {id:value.id,groupId:this.groupId,sourceKind:'observation',sourceId:value.id,
     status:'source_unresolved',at,financialEffects:0};
   });
   const nextCursor=offset+items.length<total?await cursor.create({...scope,after:{offset:offset+items.length},expiresAt:now+15*60*1000}):null;
   return {items,totalCount:total,nextCursor,revision:scope.snapshot,asOf:new Date(now).toISOString()};
  });}catch(error){throw mapped(error);}
 }
 async own(tx,actor,id,reveal){
  await this.current(tx,actor);const result=await tx.unsafe('SELECT private.burimunsi_observation_own($1,$2) AS result',[id,reveal]);
  check(result.length===1);return result[0].result===null?null:row(result[0].result);
 }
 async historyOwn(tx,actor,id){
  await this.current(tx,actor);const result=await tx.unsafe('SELECT private.burimunsi_observation_history_own($1) AS result',[id]);
  check(result.length===1);return result[0].result===null?null:row(result[0].result);
 }
 identity(actor){return {id:actor.id,sessionId:actor.sessionId,principalUserId:actor.principalUserId,
  installationId:actor.installationId,groupId:actor.groupId};}
 async namespace(tx){
  const result=await tx.unsafe('SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE');
  check(result.length===1&&same(result[0],this.custody.namespace));return copy(result[0]);
 }
 async reveal(actor,id,input){
  requireRequestId(id);requireRequestId(input?.requestId);exactKeys(input,['reason','requestId','displayHintsVersion'],['reason','requestId']);
  const wantHints=input.displayHintsVersion!==undefined;check(!wantHints||input.displayHintsVersion===1,'invalid_request',400);
  const hintsEnabled=wantHints&&this.env.BURIMUNSI_OBSERVATION_HINTS_ENABLED==='true';
  const reason=typeof input.reason==='string'?input.reason.trim():'';
  check([...reason].length>=8&&[...reason].length<=1000&&!/[\u0000-\u001f\u007f-\u009f]/.test(reason),'review_reason_required',400);
  let binding,bytes;
  try{
   const initial=await this.authority.write(async tx=>{
    const current=await this.current(tx,actor),record=await this.historyOwn(tx,actor,id);
    check(record!==null,'record_unavailable',404);
    const namespace=await this.namespace(tx),journal=await this.custody.journal(tx,record.object_key,target(record));
    const profileResult=hintsEnabled?await tx.unsafe('SELECT private.burimunsi_observation_hint_profile($1) AS result',[id]):null;
    if(hintsEnabled)check(profileResult.length===1);const hintProfile=profileResult?.[0].result??null;
    await this.checkJournal(record,journal);
    binding={kind:'disclosure',groupId:this.groupId,requestId:input.requestId,identity:this.identity(current),source:record};
    const plan=await this.storageWitnesses.stage(binding,[{key:record.object_key,journal}]);
    return {identity:this.identity(current),record,namespace,journal,plan,hintProfile};
   });
   await this.storageWitnesses.prefetch(initial.plan);
   const sealed=await this.storageWitnesses.sealed(binding,initial.record.object_key,initial.journal);
   bytes=await this.custody.decrypt(sealed,target(initial.record).aad);
   check(bytes instanceof Uint8Array&&bytes.length===initial.record.size_bytes&&await digest(bytes)===initial.record.object_sha256);
   const payload=JSON.parse(DECODER.decode(bytes));
   check(payload&&text(payload.raw_sender,1,96)&&!CONTROL.test(payload.raw_sender)&&text(payload.raw_body,1,3000)&&
    ENCODER.encode(payload.raw_body).length<=3000&&!BODY_CONTROL.test(payload.raw_body)&&
    await sha256(payload.raw_body)===initial.record.bodySha256);
   await this.authority.assertOwned();
   const verified=await this.authority.write(async tx=>{
    const current=await this.current(tx,actor);check(same(this.identity(current),initial.identity),'access_denied',403);
    const record=await this.historyOwn(tx,actor,id),namespace=await this.namespace(tx);
    check(record&&same(record,initial.record)&&same(namespace,initial.namespace),'observation_changed',409);
    const journal=await this.custody.journal(tx,record.object_key,target(record));
    await this.checkJournal(record,journal);
    check(this.custody.sameJournal(journal,initial.journal));
    await this.storageWitnesses.sealed(binding,record.object_key,journal);
    const profileResult=hintsEnabled?await tx.unsafe('SELECT private.burimunsi_observation_hint_profile($1) AS result',[id]):null;
    if(hintsEnabled)check(profileResult.length===1);const hintProfile=profileResult?.[0].result??null;
    const result=await tx.unsafe('SELECT private.burimunsi_observation_history_reveal_audit($1,$2::uuid,$3,$4::uuid,$5,$6,$7,$8::bigint) AS result',
     [id,input.requestId,reason,actor.sessionId,record.bodySha256,record.object_sha256,record.fingerprint,record.consentGeneration]);
    check(result.length===1&&same(row(result[0].result),initial.record),'observation_changed',409);
    const last=await this.current(tx,actor);check(same(this.identity(last),initial.identity),'access_denied',403);
    return {record,hintProfile};
   });
   await this.authority.assertOwned();
   const displayHints=hintsEnabled&&initial.hintProfile&&verified.hintProfile&&same(initial.hintProfile,verified.hintProfile)
    ?await observationDisplayHints(payload,verified.hintProfile,verified.record.bodySha256):null;
   return {groupId:this.groupId,sourceKind:'observation',sourceId:id,status:'source_unresolved',
    at:new Date(verified.record.createdAt).toISOString(),sender:payload.raw_sender,rawBody:payload.raw_body,financialEffects:0,
    ...(wantHints?{displayHints}:{} )};
  }catch(error){throw mapped(error);}
  finally{bytes?.fill(0);if(binding)this.storageWitnesses.forget(binding);}
 }
}
