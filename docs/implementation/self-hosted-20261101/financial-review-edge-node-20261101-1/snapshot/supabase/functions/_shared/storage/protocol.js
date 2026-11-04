const encoder = new TextEncoder();
export class StorageProtocolError extends Error {
  constructor(code, {operationId = null, retryable = false, status = 503} = {}) {
    super(code); this.name = 'StorageProtocolError'; this.code = code;
    this.operationId = operationId; this.retryable = retryable; this.status = status;
  }
}
export const sha256 = async value => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', typeof value === 'string' ? encoder.encode(value) : value)), x => x.toString(16).padStart(2, '0')).join('');
export function canonical(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
}
function fail(code, operationId, retryable = false, status = 503) { throw new StorageProtocolError(code, {operationId, retryable, status}); }
export function validKey(key) {
  if (typeof key !== 'string' || !key.length || encoder.encode(key).length > 1024 || key.startsWith('/') || key.includes('\0') || key.split('/').some(x => !x || x === '.' || x === '..')) fail('invalid_object_key', null, false, 400);
  return key;
}
export function validScope(scope) {
  if (!scope || typeof scope !== 'object' || Array.isArray(scope) || Object.keys(scope).sort().join(',') !== 'entityId,ownerId,purpose' || Object.values(scope).some(v => typeof v !== 'string' || !v.length || v.length > 200 || /[\0-\x1f]/.test(v))) fail('invalid_authoritative_scope', null, false, 400);
  return {...scope};
}
async function bytesOf(value, maxBytes) {
  let bytes;
  if (typeof value === 'string') bytes = encoder.encode(value);
  else if (value instanceof Uint8Array) bytes = new Uint8Array(value);
  else if (value instanceof ArrayBuffer) bytes = new Uint8Array(value.slice(0));
  else fail('unsupported_object_body', null, false, 400);
  if (!bytes.length || bytes.length > maxBytes) fail('invalid_object_size', null, false, 413);
  return bytes;
}
function matchesMetadata(meta, intent) {
  return !!meta && meta.operationId === intent.operationId && meta.fingerprint === intent.fingerprint && meta.sha256 === intent.sha256 && meta.size === intent.size && meta.key === intent.key;
}
function acknowledgement(intent) {
  return {stored: true, metadataCommitted: true, operationId: intent.operationId, key: intent.key, size: intent.size, sha256: intent.sha256};
}

// The journal must be DURABLE and must atomically commit canonical metadata +
// committed intent. An in-memory journal is suitable for tests only.
export class ProtectedStorageProtocol {
  constructor({transport, journal, maxBytes = 8_000_000, maxAttempts = 5}) {
    if (!transport || !journal) throw new TypeError('transport and durable journal are required');
    this.transport = transport; this.journal = journal; this.maxBytes = maxBytes; this.maxAttempts = maxAttempts;
  }
  async describe(key, value, options) {
    validKey(key); const scope = validScope(options?.scope), bytes = await bytesOf(value, this.maxBytes);
    const descriptor = {key, size: bytes.length, sha256: await sha256(bytes), scope,
      httpMetadata: options.httpMetadata ?? {}, customMetadata: options.customMetadata ?? {}};
    const metadataBytes = encoder.encode(canonical(descriptor));
    if (metadataBytes.length > 32_768) fail('object_metadata_too_large', null, false, 413);
    const operationId = options.operationId ?? await sha256('collect.storage.put.v1\n' + key);
    if (typeof operationId !== 'string' || !/^[A-Za-z0-9:._-]{8,200}$/.test(operationId)) fail('invalid_storage_operation', null, false, 400);
    return {intent: {...descriptor, operationId, fingerprint: await sha256(canonical(descriptor))}, bytes};
  }
  async put(key, value, options) {
    const {intent: requested, bytes} = await this.describe(key, value, options);
    // Reserve BEFORE any provider request, including an upload probe. Its
    // operation/key/fingerprint uniqueness is enforced inside the database.
    const intent = await this.journal.beginPut(requested);
    if (intent.fingerprint !== requested.fingerprint) fail('storage_request_conflict', intent.operationId, false, 409);
    if (intent.state === 'committed') return this.confirmCommitted(intent);
    if (intent.attempts > 0) {
      const reconciled = await this.reconcilePut(intent.operationId, {allowMissing: true});
      if (reconciled) return reconciled;
    }
    const started = await this.journal.startUpload(intent.operationId, this.maxAttempts);
    if (started.state === 'committed') return this.confirmCommitted(started);
    if (!started.started) fail(started.reason ?? 'storage_upload_inflight', intent.operationId, true, 409);
    let reply;
    try { reply = await this.transport.uploadImmutable(intent.key, bytes, intent.httpMetadata); }
    catch {
      await this.recordOutcome(intent.operationId, 'upload_unknown', started.attemptId);
      fail('storage_upload_outcome_unknown', intent.operationId, true);
    }
    // Every non-2xx status, INCLUDING 404 and 409, is an unconfirmed attempt.
    // A later explicit reconcile/retry may establish exact retained bytes.
    if (!reply || !Number.isInteger(reply.status) || reply.status < 200 || reply.status >= 300) {
      await this.recordOutcome(intent.operationId, reply?.status === 409 ? 'upload_conflict' : 'upload_rejected', started.attemptId);
      fail('storage_upload_not_confirmed', intent.operationId, reply?.status === 429 || reply?.status >= 500, reply?.status === 409 ? 409 : 503);
    }
    await this.recordOutcome(intent.operationId, 'upload_accepted', started.attemptId);
    return this.reconcilePut(intent.operationId);
  }
  async recordOutcome(operationId, outcome, attemptId = null) {
    // Failure to journal an unknown provider outcome is itself unknown. No ACK
    // is produced. The already durable pre-upload intent still reserves it.
    try { await this.journal.recordOutcome(operationId, outcome, attemptId); }
    catch { fail('storage_journal_outcome_unknown', operationId, true); }
  }
  async readAndVerify(intent, {allowMissing = false} = {}) {
    const observed = await this.transport.probe(intent.key, {maxBytes: this.maxBytes});
    if (observed?.absent === true && observed.headStatus === 404 && observed.getStatus === 404 && observed.bucketVerified === true) {
      if (allowMissing) return null;
      fail('storage_object_not_retained', intent.operationId, true);
    }
    if (observed?.headStatus !== 200 || observed?.getStatus !== 200 || !(observed.bytes instanceof Uint8Array)) fail('storage_probe_inconclusive', intent.operationId, true);
    if (observed.bytes.length !== intent.size || await sha256(observed.bytes) !== intent.sha256) {
      await this.recordOutcome(intent.operationId, 'content_conflict');
      fail('storage_content_conflict', intent.operationId, false, 409);
    }
    return observed;
  }
  async reconcilePut(operationId, {allowMissing = false} = {}) {
    const intent = await this.journal.getPut(operationId);
    if (!intent) fail('storage_intent_not_found', operationId, false, 404);
    if (intent.state === 'committed') return this.confirmCommitted(intent);
    if (intent.deleteTombstone) fail('storage_delete_tombstone', operationId, false, 409);
    if (intent.state === 'erased') fail('storage_intent_erased', operationId, false, 409);
    const observed = await this.readAndVerify(intent, {allowMissing});
    if (!observed) return null;
    try {
      const committed = await this.journal.commitPut(intent, {etag: observed.etag ?? null, verifiedSha256: intent.sha256});
      if (!matchesMetadata(committed.metadata, intent) || committed.intent.state !== 'committed') fail('storage_commit_inconsistent', operationId, true);
      return acknowledgement(intent);
    } catch (error) {
      // The commit can have succeeded while its reply was lost. Lookup only;
      // never repeat the provider upload or generate a new object identity.
      let state; try { state = await this.journal.getPutStatus(operationId); } catch { fail('storage_metadata_commit_unknown', operationId, true); }
      if (state?.intent?.state === 'committed' && !state.intent.deleteTombstone && matchesMetadata(state.metadata, intent)) return acknowledgement(intent);
      if (error instanceof StorageProtocolError && !error.retryable) throw error;
      const failure=new StorageProtocolError('storage_metadata_commit_unknown',{operationId,retryable:true});failure.cause=error;throw failure;
    }
  }
  async confirmCommitted(intent) {
    const status = await this.journal.getPutStatus(intent.operationId);
    if (status?.intent?.state !== 'committed' || status.intent.deleteTombstone || !matchesMetadata(status.metadata, intent)) fail('storage_commit_inconsistent', intent.operationId, true);
    // Do not return a durable-retention ACK for missing or corrupted bytes just
    // because a metadata row exists. This also detects out-of-band replacement.
    await this.readAndVerify(intent);
    const finalStatus=await this.journal.getPutStatus(intent.operationId);
    if(finalStatus?.intent?.state!=='committed'||finalStatus.intent.deleteTombstone||!matchesMetadata(finalStatus.metadata,intent))fail('storage_delete_tombstone',intent.operationId,false,409);
    return acknowledgement(intent);
  }
  async inventory() {
    const records = await this.journal.listAll();
    const remote = await this.transport.listAll();
    const byKey = new Map(records.metadata.map(x => [x.key, x]));
    const intents = new Map(records.puts.map(x => [x.key, x]));
    const seen = new Set(); const objects = [], anomalies = [];
    for (const object of remote.objects) {
      validKey(object.key); if (seen.has(object.key)) { anomalies.push({kind: 'duplicate_remote_key', key: object.key}); continue; }
      seen.add(object.key); const metadata = byKey.get(object.key), intent = intents.get(object.key);
      const classification = intent?.state==='erased'?'resurrected_after_delete':intent?.deleteTombstone?'deletion_pending':metadata ? 'committed' : intent ? 'pending_intent' : 'untracked';
      objects.push({...object, classification, operationId: intent?.operationId ?? metadata?.operationId ?? null});
      if (classification !== 'committed') anomalies.push({kind: classification, key: object.key});
    }
    for (const metadata of records.metadata) if (!seen.has(metadata.key)) anomalies.push({kind: 'missing_committed_object', key: metadata.key});
    for (const intent of records.puts) if (intent.state !== 'committed' && intent.state !== 'erased' && !seen.has(intent.key)) anomalies.push({kind: 'pending_intent_without_object', key: intent.key, operationId: intent.operationId});
    return {complete: remote.complete === true, objects, puts: records.puts, deletes: records.deletes, metadata: records.metadata, anomalies};
  }
  /** Missing options are accepted only to produce the existing fail-closed
   * validation error. A callback still authorizes the complete exact intent.
   * @param {string} key
   * @param {{operationId?:string,scope?:{ownerId:string,entityId:string,purpose:string},expectedSha256?:string,authorize?:(intent:{key:string,operationId:string,scope:{ownerId:string,entityId:string,purpose:string},expectedSha256:string,fingerprint:string,state?:string})=>boolean|Promise<boolean>,requireAbsent?:boolean}} [options]
   */
  async delete(key, {operationId, scope, expectedSha256, authorize, requireAbsent = false} = {}) {
    validKey(key); validScope(scope);
    if(typeof requireAbsent!=='boolean')fail('delete_authority_required',operationId,false,403);
    if (!/^[a-f0-9]{64}$/.test(expectedSha256 ?? '') || typeof operationId !== 'string' || !/^[A-Za-z0-9:._-]{8,200}$/.test(operationId) || typeof authorize !== 'function') fail('delete_authority_required', operationId, false, 403);
    const descriptor = {key, operationId, scope, expectedSha256};
    const requested={...descriptor,fingerprint:await sha256(canonical(descriptor))};
    if(await authorize(requested)!==true)fail('delete_not_authorized',operationId,false,403);
    const intent = await this.journal.beginDelete(requested);
    if (intent.state === 'committed') return this.confirmDeleted(intent);
    // This callback must be supplied by the trusted retention/application
    // boundary. Caller JSON is not authority. See integration contract.
    if (await authorize(intent) !== true) fail('delete_not_authorized', operationId, false, 403);
    const observed = await this.transport.probe(key, {maxBytes: this.maxBytes});
    if (!this.provesAbsent(observed)) {
      // Reconciliation is observation/journal-only: a present, resurrected or
      // inconclusive object must never turn this path into another DELETE.
      if(requireAbsent)fail('storage_absence_unconfirmed',operationId,true);
      if (observed?.headStatus !== 200 || observed?.getStatus !== 200 || !(observed.bytes instanceof Uint8Array) || await sha256(observed.bytes) !== expectedSha256) fail('delete_object_identity_changed', operationId, false, 409);
      if (await authorize(intent) !== true) fail('delete_not_authorized', operationId, false, 403);
      await this.journal.recordDeleteOutcome(operationId, 'delete_started');
      let reply; try { reply = await this.transport.remove(key); } catch { reply = null; }
      await this.journal.recordDeleteOutcome(operationId, reply && reply.status >= 200 && reply.status < 300 ? 'delete_accepted' : 'delete_unknown');
    }
    // DELETE status alone is never proof. Keep canonical metadata and intent on
    // partial delete, inaccessible bucket, timeout or contradictory HEAD/GET.
    const absence = await this.transport.probe(key, {maxBytes: this.maxBytes});
    if (!this.provesAbsent(absence)) fail('storage_absence_unconfirmed', operationId, true);
    if (await authorize(intent) !== true) fail('delete_authority_changed', operationId, false, 403);
    try { await this.journal.commitDelete(intent, {headStatus: 404, getStatus: 404, bucketVerified: true}); }
    catch {
      const status = await this.journal.getDeleteStatus(operationId);
      if (status?.intent?.state !== 'committed' || status.metadata !== null) fail('storage_delete_commit_unknown', operationId, true);
    }
    return this.confirmDeleted(intent);
  }
  provesAbsent(probe) { return probe?.absent === true && probe.headStatus === 404 && probe.getStatus === 404 && probe.bucketVerified === true; }
  async confirmDeleted(intent) {
    const status = await this.journal.getDeleteStatus(intent.operationId);
    if (status?.intent?.state !== 'committed' || status.metadata !== null || !this.provesAbsent(await this.transport.probe(intent.key, {maxBytes: this.maxBytes}))) fail('storage_delete_commit_unknown', intent.operationId, true);
    return {deleted: true, operationId: intent.operationId, key: intent.key, absenceVerified: true};
  }
  async cleanupPending({olderThan, authorize}) {
    if (!Number.isFinite(olderThan) || typeof authorize !== 'function') fail('cleanup_authority_required', null, false, 403);
    const inventory = await this.inventory();
    if (!inventory.complete) fail('storage_inventory_incomplete', null, true);
    const outcomes = [];
    for (const intent of inventory.puts) {
      if (intent.state === 'committed' || intent.state === 'erased' || intent.createdAt > olderThan) continue;
      if (await authorize(intent) !== true) { outcomes.push({operationId: intent.operationId, state: 'retained'}); continue; }
      // Untracked actual objects never qualify for automatic cleanup.
      const operationId = await sha256('collect.storage.cleanup.v1\n' + intent.operationId);
      try { const result = await this.delete(intent.key, {operationId, scope: intent.scope, expectedSha256: intent.sha256, authorize}); outcomes.push({...result, state: 'deleted'}); }
      catch (error) { outcomes.push({operationId: intent.operationId, state: 'unresolved', code: error.code ?? 'cleanup_failed'}); }
    }
    return {outcomes, untracked: inventory.objects.filter(x => x.classification === 'untracked').map(x => x.key)};
  }
}
