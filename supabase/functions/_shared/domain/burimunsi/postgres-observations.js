// Native observation capture, authority, and audited disclosure.
import { BuriError, ObservationUploadUnresolved, requirePort } from './errors.js';
import { canonicalJson, exactKeys, requireRequestId, sha256 } from './values.js';
import { hasPhonePinContext } from './phone-pin-request.js';
import { encrypt } from '../encryption.js';
import { digest } from '../core.js';
import { observationDisplayHints } from './observation-display-hints.js';
import { storageEntity, verifyRetainedObject } from '../../storage-identity.js';
import { readObservationListing } from './postgres-observation-listing.js';
import { PostgresObservationReconciliation } from './postgres-observation-reconciliation.js';
import {
 approvedObservationProfile as approvedProfile,
 copyObservationValue as copy,
 decodeObservationPayload,
 decodeObservationRecord as row,
 encodeObservationPayload,
 hasObservationContent,
 isObservationCandidate,
 mapObservationError as mapped,
 OBSERVATION_HASH as HASH,
 observationActorIdentity,
 observationContentFingerprint,
 observationInteger as int,
 observationPayload as payloadFor,
 observationStorageTarget as target,
 requireObservation as check,
 sameObservationValue as same,
 validateObservationInput,
 verifyObservationJournal,
} from './observation-evidence.js';

export { isObservationCandidate, observationContentFingerprint } from './observation-evidence.js';

// Metadata-only check of one deterministic key. The ciphertext itself is never
// returned; PostgreSQL computes its digest solely to validate the reservation.
export const OBSERVATION_UNRESOLVED_SQL =
 `SELECT i.object_key,i.operation_id,i.fingerprint,i.sha256,i.size,i.scope,
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

function consent(value) {
 check(value && typeof value.enabled === 'boolean');
 return { enabled: value.enabled, generation: int(value.generation) };
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
 #reconciliation;

 constructor(
  { authority, env, validateProviderProfile, custody, storageWitnesses, clock = () => Date.now() },
 ) {
  requirePort(authority, ['read', 'write', 'session', 'assertOwned']);
  requirePort(env?.PRIVATE_MEDIA, ['put', 'get']);
  requirePort(custody, ['journal', 'sameJournal', 'decrypt']);
  requirePort(storageWitnesses, ['stage', 'prefetch', 'sealed', 'forget']);
  check(
   typeof validateProviderProfile === 'function' && typeof clock === 'function' &&
    hasPhonePinContext(authority.db),
  );
  Object.assign(this, {
   authority,
   env,
   validateProviderProfile,
   custody,
   storageWitnesses,
   clock,
   groupId: authority.groupId,
  });
  this.#reconciliation = new PostgresObservationReconciliation({
   authority,
   env,
   custody,
   getStorageWitnesses: () => this.storageWitnesses,
   current: (tx, actor) => this.current(tx, actor),
   context: (tx, actor) => this.context(tx, actor),
   namespace: (tx) => this.namespace(tx),
  });
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
 reconcile(actor, input) {
  return this.#reconciliation.reconcile(actor, input);
 }
 reconcileBatch(actor, input) {
  return this.#reconciliation.reconcileBatch(actor, input);
 }
 reconcileStatus(actor) {
  return this.#reconciliation.reconcileStatus(actor);
 }
 reconcileVerifiedStatus(actor) {
  return this.#reconciliation.reconcileVerifiedStatus(actor);
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
 async checkJournal(record, journal) {
  return verifyObservationJournal(record, journal);
 }
 async checkRetained(actor, r, payload, bodySha) {
  check(r.bodySha256 === bodySha && r.object_sha256 === await digest(encodeObservationPayload(payload)));
  let bytes;
  try {
   await this.authority.assertOwned();
   bytes = await verifyRetainedObject(this.env, r);
   await this.authority.assertOwned();
   check(same(decodeObservationPayload(bytes), payload));
   await this.authority.write(async (tx) => {
    const current = await this.find(tx, actor, r.requestId, r.fingerprint);
    check(current && same(current, r), 'observation_changed', 409);
    const journal = await this.custody.journal(tx, r.object_key, target(r));
    await this.checkJournal(r, journal);
   });
  } finally {
   bytes?.fill(0);
  }
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
 async observe(actor, input) {
  const value = validateObservationInput(input),
   bodySha = await sha256(value.rawBody),
   payload = payloadFor(value),
   contentSha = value.sourceKey ? await observationContentFingerprint(value, bodySha) : null;
  // This identity is stable across a short-lease renewal, but cannot move to a
  // different native account, installation, group, source, or SMS bytes.
  const fingerprint = await sha256(
   canonicalJson({
    groupId: this.groupId,
    accountId: actor.id,
    installationId: actor.installationId,
    requestId: value.requestId,
    bodySha256: bodySha,
    rawSender: value.rawSender,
    sourceMode: value.sourceMode,
    complete: value.complete,
    capturedAt: value.capturedAt,
    serviceCentreAt: value.serviceCentreAt,
    inboxReceivedAt: value.inboxReceivedAt,
    subscriptionId: value.subscriptionId,
    ...(value.sourceKey ? { sourceKey: value.sourceKey } : {}),
   }),
  );
  try {
   let prior = await this.authority.read((tx) => this.find(tx, actor, value.requestId, fingerprint));
   if (prior) {
    await this.checkRetained(actor, prior, payload, bodySha);
    const final = await this.authority.read((tx) => this.find(tx, actor, value.requestId, fingerprint));
    check(final && same(final, prior), 'observation_changed', 409);
    return {
     requestId: value.requestId,
     sourceId: prior.id,
     bodySha256: bodySha,
     status: 'source_unresolved',
     financialEffects: 0,
    };
   }
   const initial = await this.authority.read((tx) => this.context(tx, actor));
   check(isObservationCandidate(value, initial.profile), 'unsupported_receipt', 422);
   const id = await storageEntity(
    'burimunsi.native.observation.v1',
    actor.principalUserId,
    value.requestId,
   );
   // The admission is durable before any object reservation or provider call.
   // A retry reuses the same intent; uncertainty never consumes another slot.
   const prepared = await this.prepare(actor, value, fingerprint, id, initial, contentSha, bodySha);
   if (prepared.kind === 'duplicate') {
    await this.#reconciliation.checkDuplicate(actor, value, contentSha, bodySha, prepared.record);
    return {
     requestId: value.requestId,
     sourceId: prepared.record.id,
     bodySha256: bodySha,
     status: 'source_unresolved',
     financialEffects: 0,
    };
   }
   const bytes = encodeObservationPayload(payload),
    objectSize = bytes.length,
    objectSha = await digest(bytes),
    objectKey = 'sms/' + id;
   try {
    if (await this.uploadUnresolved(actor, value, fingerprint, id, initial, objectSha)) {
     throw new ObservationUploadUnresolved(value.requestId);
    }
    const sealed = await encrypt(this.env, bytes, `sms:${id}:${objectSha}`);
    await this.authority.assertOwned();
    try {
     await this.env.PRIVATE_MEDIA.put(objectKey, sealed, {
      scope: { ownerId: actor.principalUserId, purpose: 'sms_receipt', entityId: id },
      aad: `sms:${id}:${objectSha}`,
      sourceDigest: fingerprint,
      httpMetadata: { contentType: 'application/octet-stream' },
      customMetadata: { sha256: objectSha, key_id: this.env.DATA_KEY_ID },
     });
    } catch (error) {
     await this.unresolvedAfterFailure(actor, value, fingerprint, id, initial, objectSha, error);
    }
   } finally {
    bytes.fill(0);
   }
   let committed;
   try {
    committed = await this.authority.write(async (tx) => {
     await this.current(tx, actor);
     // A provider upload whose outcome is unknown is not authority failure and
     // cannot be acknowledged as retained. Preserve the exact admission and
     // ciphertext; an operator must resolve the outstanding storage outcome.
     const state = await tx.unsafe(
      'SELECT state,active_attempt,upload_unresolved,delete_tombstone FROM private.storage_put_intents WHERE object_key=$1 FOR UPDATE',
      [objectKey],
     );
     check(
      state.length === 1 && state[0].state === 'committed' && state[0].delete_tombstone === false,
      'observation_unavailable',
      503,
     );
     check(
      state[0].active_attempt === null && state[0].upload_unresolved === false,
      'observation_upload_unresolved',
      503,
     );
     const r = await tx.unsafe(
      'SELECT private.burimunsi_observation_commit($1::uuid,$2,$3,$4,$5,$6::bigint,$7,$8,$9::bigint) AS result',
      [
       value.requestId,
       fingerprint,
       id,
       bodySha,
       objectSha,
       objectSize,
       initial.profile.version,
       initial.ctx.profile_sha256,
       initial.ctx.consentGeneration,
      ],
     );
     check(r.length === 1);
     return row(r[0].result);
    });
   } catch (error) {
    // An uncertain transaction outcome is reconciled against the same immutable
    // request, never replayed as a new SMS or acknowledged on a storage PUT.
    prior = await this.authority.read((tx) => this.find(tx, actor, value.requestId, fingerprint));
    if (!prior) {
     if (error instanceof BuriError && error.code === 'observation_upload_unresolved') {
      await this.unresolvedAfterFailure(actor, value, fingerprint, id, initial, objectSha, error);
     }
     throw error;
    }
    committed = prior;
   }
   await this.checkRetained(actor, committed, payload, bodySha);
   const final = await this.authority.read((tx) => this.find(tx, actor, value.requestId, fingerprint));
   check(final && same(final, committed), 'observation_changed', 409);
   return {
    requestId: value.requestId,
    sourceId: committed.id,
    bodySha256: bodySha,
    status: 'source_unresolved',
    financialEffects: 0,
   };
  } catch (error) {
   throw mapped(error);
  }
 }
 page(actor, query, cursor) {
  return readObservationListing(
   {
    groupId: this.groupId,
    clock: () => this.clock(),
    readSnapshot: (readPage) =>
     this.authority.read(async (tx) => {
      await this.current(tx, actor);
      return readPage(tx);
     }),
   },
   actor,
   query,
   cursor,
  );
 }

 async own(tx,actor,id,reveal){
  await this.current(tx,actor);const result=await tx.unsafe('SELECT private.burimunsi_observation_own($1,$2) AS result',[id,reveal]);
  check(result.length===1);return result[0].result===null?null:row(result[0].result);
 }
 async historyOwn(tx,actor,id){
  await this.current(tx,actor);const result=await tx.unsafe('SELECT private.burimunsi_observation_history_own($1) AS result',[id]);
  check(result.length===1);return result[0].result===null?null:row(result[0].result);
 }
 identity(actor) {
  return observationActorIdentity(actor);
 }
 async namespace(tx){
  const result=await tx.unsafe('SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true FOR SHARE');
  check(result.length===1&&same(result[0],this.custody.namespace));return copy(result[0]);
 }
 async reveal(actor, id, input) {
  requireRequestId(id);
  requireRequestId(input?.requestId);
  exactKeys(input, ['reason', 'requestId', 'displayHintsVersion'], ['reason', 'requestId']);
  const wantHints = input.displayHintsVersion !== undefined;
  check(!wantHints || input.displayHintsVersion === 1, 'invalid_request', 400);
  const hintsEnabled = wantHints && this.env.BURIMUNSI_OBSERVATION_HINTS_ENABLED === 'true';
  const reason = typeof input.reason === 'string' ? input.reason.trim() : '';
  check(
   [...reason].length >= 8 && [...reason].length <= 1000 && !/[\u0000-\u001f\u007f-\u009f]/.test(reason),
   'review_reason_required',
   400,
  );
  let binding, bytes;
  try {
   const initial = await this.authority.write(async (tx) => {
    const current = await this.current(tx, actor), record = await this.historyOwn(tx, actor, id);
    check(record !== null, 'record_unavailable', 404);
    const namespace = await this.namespace(tx),
     journal = await this.custody.journal(tx, record.object_key, target(record));
    const profileResult = hintsEnabled
     ? await tx.unsafe('SELECT private.burimunsi_observation_hint_profile($1) AS result', [id])
     : null;
    if (hintsEnabled) check(profileResult.length === 1);
    const hintProfile = profileResult?.[0].result ?? null;
    await this.checkJournal(record, journal);
    binding = {
     kind: 'disclosure',
     groupId: this.groupId,
     requestId: input.requestId,
     identity: this.identity(current),
     source: record,
    };
    const plan = await this.storageWitnesses.stage(binding, [{ key: record.object_key, journal }]);
    return { identity: this.identity(current), record, namespace, journal, plan, hintProfile };
   });
   await this.storageWitnesses.prefetch(initial.plan);
   const sealed = await this.storageWitnesses.sealed(binding, initial.record.object_key, initial.journal);
   bytes = await this.custody.decrypt(sealed, target(initial.record).aad);
   check(
    bytes instanceof Uint8Array && bytes.length === initial.record.size_bytes &&
     await digest(bytes) === initial.record.object_sha256,
   );
   const payload = decodeObservationPayload(bytes);
   check(hasObservationContent(payload) && await sha256(payload.raw_body) === initial.record.bodySha256);
   await this.authority.assertOwned();
   const verified = await this.authority.write(async (tx) => {
    const current = await this.current(tx, actor);
    check(same(this.identity(current), initial.identity), 'access_denied', 403);
    const record = await this.historyOwn(tx, actor, id), namespace = await this.namespace(tx);
    check(
     record && same(record, initial.record) && same(namespace, initial.namespace),
     'observation_changed',
     409,
    );
    const journal = await this.custody.journal(tx, record.object_key, target(record));
    await this.checkJournal(record, journal);
    check(this.custody.sameJournal(journal, initial.journal));
    await this.storageWitnesses.sealed(binding, record.object_key, journal);
    const profileResult = hintsEnabled
     ? await tx.unsafe('SELECT private.burimunsi_observation_hint_profile($1) AS result', [id])
     : null;
    if (hintsEnabled) check(profileResult.length === 1);
    const hintProfile = profileResult?.[0].result ?? null;
    const result = await tx.unsafe(
     'SELECT private.burimunsi_observation_history_reveal_audit($1,$2::uuid,$3,$4::uuid,$5,$6,$7,$8::bigint) AS result',
     [
      id,
      input.requestId,
      reason,
      actor.sessionId,
      record.bodySha256,
      record.object_sha256,
      record.fingerprint,
      record.consentGeneration,
     ],
    );
    check(result.length === 1 && same(row(result[0].result), initial.record), 'observation_changed', 409);
    const last = await this.current(tx, actor);
    check(same(this.identity(last), initial.identity), 'access_denied', 403);
    return { record, hintProfile };
   });
   await this.authority.assertOwned();
   const displayHints = hintsEnabled && initial.hintProfile && verified.hintProfile &&
     same(initial.hintProfile, verified.hintProfile)
    ? await observationDisplayHints(payload, verified.hintProfile, verified.record.bodySha256)
    : null;
   return {
    groupId: this.groupId,
    sourceKind: 'observation',
    sourceId: id,
    status: 'source_unresolved',
    at: new Date(verified.record.createdAt).toISOString(),
    sender: payload.raw_sender,
    rawBody: payload.raw_body,
    financialEffects: 0,
    ...(wantHints ? { displayHints } : {}),
   };
  } catch (error) {
   throw mapped(error);
  } finally {
   bytes?.fill(0);
   if (binding) this.storageWitnesses.forget(binding);
  }
 }
}
