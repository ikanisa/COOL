import {StorageProtocolError, canonical} from './protocol.js';
const conflict = code => { throw new StorageProtocolError(code, {status: 409}); };
function put(row) {
  return row && {operationId: row.operation_id, key: row.object_key, fingerprint: row.fingerprint, sha256: row.sha256, size: Number(row.size), scope: row.scope, httpMetadata: row.http_metadata, customMetadata: row.custom_metadata, state: row.state, attempts: row.attempts, activeAttempt: row.active_attempt, uploadUnresolved: row.upload_unresolved, deleteTombstone: row.delete_tombstone, createdAt: new Date(row.created_at).getTime()};
}
function meta(row) { return row && {key: row.object_key, operationId: row.operation_id, fingerprint: row.fingerprint, sha256: row.sha256, size: Number(row.size), scope: row.scope, httpMetadata: row.http_metadata, customMetadata: row.custom_metadata}; }
function deletion(row) { return row && {operationId: row.operation_id, key: row.object_key, fingerprint: row.fingerprint, expectedSha256: row.expected_sha256, scope: row.scope, state: row.state}; }
export class PostgresStorageJournal {
  constructor(pool, {namespace,deleteGuards=null,inventoryLimits={entries:10000,bytes:8000000}}={}) { this.pool = pool; if(!namespace)throw new TypeError('Storage namespace is required');if(!Number.isSafeInteger(inventoryLimits.entries)||inventoryLimits.entries<1||inventoryLimits.entries>100000||!Number.isSafeInteger(inventoryLimits.bytes)||inventoryLimits.bytes<1||inventoryLimits.bytes>64000000)throw new TypeError('Storage inventory limits are invalid');this.namespace=namespace;this.deleteGuards=deleteGuards;this.inventoryLimits=inventoryLimits; }
  async bindNamespace(c){await c.query('INSERT INTO private.storage_namespace(singleton,origin,bucket)VALUES(true,$1,$2)ON CONFLICT DO NOTHING',[this.namespace.origin,this.namespace.bucket]);const row=(await c.query('SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true')).rows[0];if(!row||row.origin!==this.namespace.origin||row.bucket!==this.namespace.bucket)conflict('storage_namespace_conflict');}
  async transaction(key, fn) {
    const client = await this.pool.connect();
    try { await client.query('BEGIN'); await client.query("SET LOCAL lock_timeout='5s'"); await client.query("SET LOCAL statement_timeout='15s'");await this.bindNamespace(client);
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 7346369))', [key]);
      const result = await fn(client);if(client.storageGuardCleanup?.length)await client.query('SET CONSTRAINTS ALL IMMEDIATE');for(const cleanup of client.storageGuardCleanup??[])await cleanup(); await client.query('COMMIT'); return result;
    } catch (error) { await client.query('ROLLBACK').catch(() => {}); if (error.code === '23505') conflict('storage_request_conflict'); throw error; }
    finally { client.release(); }
  }
  async getPayloadBinding(key){return this.transaction(key,async c=>{const row=(await c.query('SELECT key_id FROM private.storage_payload_reservations WHERE object_key=$1',[key])).rows[0];return row?{keyId:row.key_id}:null;});}
  async reservePayload(key,descriptor,sealedBody){
    const sourceFingerprint=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(canonical(descriptor))).then(b=>Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join(''));
    if(typeof sealedBody!=='string'||!sealedBody.length||new TextEncoder().encode(sealedBody).length>10_700_000)conflict('storage_payload_size_invalid');
    return this.transaction(key,async c=>{
      await c.query('SELECT pg_advisory_xact_lock(hashtextextended($1,7346370))',[descriptor.scope.ownerId]);
      const old=(await c.query('SELECT * FROM private.storage_payload_reservations WHERE object_key=$1 FOR UPDATE',[key])).rows[0];
      if(old){if(old.source_fingerprint!==sourceFingerprint)conflict('storage_source_conflict');return {sealedBody:old.sealed_body,sourceFingerprint};}
      if((await c.query('SELECT 1 FROM app.privacy_retention_barriers WHERE subject_id=$1',[descriptor.scope.ownerId])).rows.length)conflict('storage_retention_barrier_active');
      const usage=(await c.query("SELECT count(*) AS n,coalesce(sum(octet_length(sealed_body)),0) AS bytes FROM private.storage_payload_reservations WHERE scope->>'ownerId'=$1 AND sealed_body IS NOT NULL",[descriptor.scope.ownerId])).rows[0];
      if(Number(usage.n)>=128||Number(usage.bytes)+new TextEncoder().encode(sealedBody).length>64_000_000)conflict('storage_pending_budget_exceeded');
      await c.query('INSERT INTO private.storage_payload_reservations(object_key,source_fingerprint,scope,aad,key_id,plaintext_sha256,sealed_body)VALUES($1,$2,$3,$4,$5,$6,$7)',[key,sourceFingerprint,descriptor.scope,descriptor.aad,descriptor.keyId,descriptor.plaintextSha256,sealedBody]);
      return{sealedBody,sourceFingerprint};
    });
  }
  async getObject(key){return this.transaction(key,async c=>meta((await c.query('SELECT * FROM private.storage_objects WHERE object_key=$1',[key])).rows[0])??null);}
  async getPutByKey(key){return this.transaction(key,async c=>put((await c.query('SELECT * FROM private.storage_put_intents WHERE object_key=$1',[key])).rows[0])??null);}
  async beginPut(intent) {
    return this.transaction(intent.key, async c => {
      await c.query(`INSERT INTO private.storage_put_intents(operation_id,object_key,fingerprint,sha256,size,scope,http_metadata,custom_metadata) VALUES($1,$2,$3,$4,$5,$6,$7,$8) ON CONFLICT DO NOTHING`, [intent.operationId,intent.key,intent.fingerprint,intent.sha256,intent.size,intent.scope,intent.httpMetadata,intent.customMetadata]);
      const row = (await c.query('SELECT * FROM private.storage_put_intents WHERE operation_id=$1 FOR UPDATE', [intent.operationId])).rows[0];
      if (!row || row.object_key !== intent.key || row.fingerprint !== intent.fingerprint) conflict('storage_request_conflict');
      if (row.delete_tombstone || row.state === 'erased') conflict('storage_delete_tombstone'); return put(row);
    });
  }
  async getPut(operationId) {return this.transaction(operationId, async c=>put((await c.query('SELECT * FROM private.storage_put_intents WHERE operation_id=$1',[operationId])).rows[0])??null);}
  async startUpload(operationId, maximum) {
    const current = await this.getPut(operationId); if (!current) conflict('storage_intent_not_found');
    return this.transaction(current.key, async c => {
      const row = (await c.query('SELECT * FROM private.storage_put_intents WHERE operation_id=$1 FOR UPDATE', [operationId])).rows[0];
      if (row.delete_tombstone || row.state === 'erased') conflict('storage_delete_tombstone');
      if (row.state === 'committed') return {...put(row), started: false};
      if (row.active_attempt || row.upload_unresolved) return {...put(row), started: false, reason: 'storage_upload_unsettled'};
      if (row.attempts >= maximum) return {...put(row), started: false, reason: 'storage_attempt_budget_exhausted'};
      const attemptId = crypto.randomUUID();
      await c.query('INSERT INTO private.storage_upload_attempts(id,operation_id)VALUES($1,$2)', [attemptId,operationId]);
      const updated = (await c.query('UPDATE private.storage_put_intents SET active_attempt=$2,attempts=attempts+1,last_outcome=\'upload_started\',updated_at=clock_timestamp() WHERE operation_id=$1 RETURNING *', [operationId,attemptId])).rows[0];
      return {...put(updated), started: true, attemptId};
    });
  }
  async recordOutcome(operationId, outcome, attemptId = null) {
    const current = await this.getPut(operationId); if (!current) conflict('storage_intent_not_found');
    return this.transaction(current.key, async c => {
      if (attemptId) {
        const known = ['upload_accepted','upload_conflict'].includes(outcome);
        await c.query('UPDATE private.storage_upload_attempts SET outcome=$3,completed_at=clock_timestamp() WHERE id=$1 AND operation_id=$2', [attemptId,operationId,outcome]);
        await c.query('UPDATE private.storage_put_intents SET last_outcome=$3,active_attempt=NULL,upload_unresolved=upload_unresolved OR NOT $4,updated_at=clock_timestamp() WHERE operation_id=$1 AND active_attempt=$2', [operationId,attemptId,outcome,known]);
      } else await c.query('UPDATE private.storage_put_intents SET last_outcome=$2,updated_at=clock_timestamp() WHERE operation_id=$1', [operationId,outcome]);
    });
  }
  async commitPut(intent, proof) {
    return this.transaction(intent.key, async c => {
      const row = (await c.query('SELECT * FROM private.storage_put_intents WHERE operation_id=$1 FOR UPDATE', [intent.operationId])).rows[0];
      if (!row || row.fingerprint !== intent.fingerprint || proof.verifiedSha256 !== row.sha256) conflict('storage_request_conflict');
      if (row.delete_tombstone || row.state === 'erased') conflict('storage_delete_tombstone');
      await c.query(`INSERT INTO private.storage_objects(object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata,etag) SELECT object_key,operation_id,fingerprint,sha256,size,scope,http_metadata,custom_metadata,$2 FROM private.storage_put_intents WHERE operation_id=$1 ON CONFLICT DO NOTHING`, [intent.operationId,proof.etag]);
      const metadata = (await c.query('SELECT * FROM private.storage_objects WHERE object_key=$1', [intent.key])).rows[0];
      if (!metadata || metadata.operation_id !== intent.operationId || metadata.fingerprint !== intent.fingerprint) conflict('storage_request_conflict');
      const changed = (await c.query("UPDATE private.storage_put_intents SET state='committed',updated_at=clock_timestamp() WHERE operation_id=$1 RETURNING *", [intent.operationId])).rows[0];
      return {intent: put(changed), metadata: meta(metadata)};
    });
  }
  async getPutStatus(operationId) {
    const current = await this.getPut(operationId); if (!current) return null;
    return this.transaction(current.key, async c => ({intent: put((await c.query('SELECT * FROM private.storage_put_intents WHERE operation_id=$1', [operationId])).rows[0]), metadata: meta((await c.query('SELECT * FROM private.storage_objects WHERE operation_id=$1', [operationId])).rows[0]) ?? null}));
  }
  async runDeleteGuards(c,intent){if(!this.deleteGuards)conflict('delete_authority_required');const cleanup=await this.deleteGuards(c,intent);if(cleanup)(c.storageGuardCleanup??=[]).push(cleanup);}
  async beginDelete(intent) {
    return this.transaction(intent.key, async c => {
      await this.runDeleteGuards(c,intent);
      const source = (await c.query('SELECT * FROM private.storage_put_intents WHERE object_key=$1 FOR UPDATE', [intent.key])).rows[0];
      if (!source || source.sha256 !== intent.expectedSha256 || canonical(source.scope) !== canonical(intent.scope)) conflict('delete_object_identity_changed');
      // A 404 probe or elapsed timeout cannot prove an old PUT is terminal.
      // No automatic clearing of these flags is provided by this library.
      if (source.active_attempt || source.upload_unresolved) conflict('unsettled_upload_blocks_delete');
      await c.query('INSERT INTO private.storage_delete_intents(operation_id,object_key,fingerprint,expected_sha256,scope)VALUES($1,$2,$3,$4,$5)ON CONFLICT DO NOTHING', [intent.operationId,intent.key,intent.fingerprint,intent.expectedSha256,intent.scope]);
      const row = (await c.query('SELECT * FROM private.storage_delete_intents WHERE operation_id=$1 FOR UPDATE', [intent.operationId])).rows[0];
      if (!row || row.object_key !== intent.key || row.fingerprint !== intent.fingerprint) conflict('delete_request_conflict');
      await c.query('UPDATE private.storage_put_intents SET delete_tombstone=true,updated_at=clock_timestamp()WHERE object_key=$1', [intent.key]);
      return deletion(row);
    });
  }
  async recordDeleteOutcome(operationId,outcome){await this.transaction(operationId,c=>c.query("UPDATE private.storage_delete_intents SET last_outcome=$2 WHERE operation_id=$1 AND state<>'committed'",[operationId,outcome]));}
  async commitDelete(intent, absenceProof) {
    if (absenceProof.headStatus !== 404 || absenceProof.getStatus !== 404 || absenceProof.bucketVerified !== true) conflict('absence_proof_required');
    return this.transaction(intent.key, async c => {
      await this.runDeleteGuards(c,intent);
      const source = (await c.query('SELECT * FROM private.storage_put_intents WHERE object_key=$1 FOR UPDATE', [intent.key])).rows[0];
      if (!source || source.active_attempt || source.upload_unresolved || !source.delete_tombstone || source.sha256 !== intent.expectedSha256) conflict('delete_source_changed');
      const deletionRow = (await c.query('SELECT * FROM private.storage_delete_intents WHERE operation_id=$1 FOR UPDATE', [intent.operationId])).rows[0];
      if (!deletionRow || deletionRow.fingerprint !== intent.fingerprint) conflict('delete_request_conflict');
      await c.query('DELETE FROM private.storage_objects WHERE object_key=$1 AND sha256=$2', [intent.key,intent.expectedSha256]);
      await c.query("UPDATE private.storage_put_intents SET state='erased',updated_at=clock_timestamp()WHERE object_key=$1", [intent.key]);
      await c.query("UPDATE private.storage_delete_intents SET state='committed',absence_proof=$2,committed_at=clock_timestamp()WHERE operation_id=$1", [intent.operationId,absenceProof]);
    });
  }
  async getDeleteByKey(key) {
    return this.transaction(key,async c=>deletion((await c.query('SELECT * FROM private.storage_delete_intents WHERE object_key=$1',[key])).rows[0]));
  }
  async getDeleteStatus(operationId) {
    const d = await this.transaction(operationId,async c=>(await c.query('SELECT * FROM private.storage_delete_intents WHERE operation_id=$1',[operationId])).rows[0]); if (!d) return null;
    return this.transaction(d.object_key, async c => ({intent: deletion((await c.query('SELECT * FROM private.storage_delete_intents WHERE operation_id=$1', [operationId])).rows[0]), metadata: meta((await c.query('SELECT * FROM private.storage_objects WHERE object_key=$1', [d.object_key])).rows[0]) ?? null}));
  }
  async listAll() {
    // The service must hold a writer fence for destructive interpretation.
    // Namespace creation is a genuine guarded READ COMMITTED mutation. Keep it
    // out of the immutable snapshot, whose READ ONLY setting is server-enforced.
    await this.transaction('storage_inventory_namespace',async()=>{});
    const c = await this.pool.connect(); try { await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');await c.query("SET LOCAL lock_timeout='5s'");await c.query("SET LOCAL statement_timeout='15s'");
      const binding=(await c.query('SELECT origin,bucket FROM private.storage_namespace WHERE singleton=true')).rows[0];
      if(!binding||binding.origin!==this.namespace.origin||binding.bucket!==this.namespace.bucket)conflict('storage_namespace_conflict');
      let count=0,bytes=0;const collect=async(table,map)=>{let after='',rows=[];while(true){const page=(await c.query('SELECT * FROM private.'+table+' WHERE object_key>$1 ORDER BY object_key LIMIT 100',[after])).rows;for(const item of page){const value=map(item);bytes+=new TextEncoder().encode(JSON.stringify(value)).length;if(++count>this.inventoryLimits.entries||bytes>this.inventoryLimits.bytes)conflict('storage_journal_inventory_limit');rows.push(value);}if(page.length<100)break;after=page.at(-1).object_key;}return rows;};
      const puts=await collect('storage_put_intents',put),metadata=await collect('storage_objects',meta),deletes=await collect('storage_delete_intents',deletion);
      await c.query('COMMIT'); return {puts,metadata,deletes};
    } catch (error) { await c.query('ROLLBACK').catch(() => {}); throw error; } finally { c.release(); }
  }
}
