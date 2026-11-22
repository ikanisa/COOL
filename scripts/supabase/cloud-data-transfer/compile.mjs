// In-memory preparation only. No database connection or external write exists here.
import {createCipheriv, createDecipheriv, createHash, createHmac, hkdfSync, randomBytes, timingSafeEqual} from 'node:crypto';

export class TransferError extends Error {
  constructor(code) { super(code); this.name = 'TransferError'; this.code = code; }
}
const fail = code => { throw new TransferError(code); };
const OWN = (x, k) => Object.prototype.hasOwnProperty.call(x, k);
const IDENT = /^[a-z_][a-z0-9_]*$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const HASH = /^[a-f0-9]{64}$/;
const MAX_ROWS = 256;
const MAX_BYTES = 16 * 1024 * 1024;

// Explicit source graph. Authentication, active controller state and bulk
// admission history are intentionally not imported as working authority.
export const GRAPH = Object.freeze([
  'app.users', 'app.collections', 'app.memberships', 'app.momo_receiving_accounts',
  'app.sms_receipts', 'app.momo_parse_attempts', 'app.momo_transactions',
  'app.momo_transaction_sources', 'app.payment_evidence', 'app.payments',
  'app.ledger_entries', 'app.momo_financial_links', 'app.contribution_posting_snapshots',
  'private.burimunsi_scopes', 'private.burimunsi_accounts', 'private.burimunsi_device_grants',
  'private.burimunsi_device_accounts', 'private.burimunsi_sessions',
  'private.burimunsi_observation_requests', 'private.burimunsi_unresolved_observations',
  'private.burimunsi_native_receipt_origins', 'private.burimunsi_auto_sms_jobs',
  'private.burimunsi_transaction_scopes', 'private.burimunsi_detection_profiles',
  'private.burimunsi_observation_consents', 'private.storage_payload_reservations',
  'private.storage_put_intents', 'private.storage_upload_attempts', 'private.storage_objects',
]);

function plain(x) { return x !== null && typeof x === 'object' && !Array.isArray(x) && Object.getPrototypeOf(x) === Object.prototype; }
function canonical(value) {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'number' && Number.isSafeInteger(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(canonical).join(',') + ']';
  if (!plain(value)) fail('unsupported_snapshot_value');
  return '{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + canonical(value[k])).join(',') + '}';
}
function snapshotBytes(snapshot) {
  if (!plain(snapshot) || !plain(snapshot.tables) || Object.keys(snapshot.tables).sort().join('|') !== [...GRAPH].sort().join('|')) fail('graph_table_set_changed');
  const data = {};
  for (const table of GRAPH) {
    const rows = snapshot.tables[table];
    if (!Array.isArray(rows) || rows.length > MAX_ROWS || rows.some(row => !plain(row))) fail('graph_row_limit');
    data[table] = rows.map(canonical).sort();
  }
  const bytes = Buffer.from(canonical(data));
  if (bytes.length > MAX_BYTES) fail('graph_byte_limit');
  return bytes;
}
function keyCopy(key) { if (!Buffer.isBuffer(key) || key.length !== 32) fail('invalid_custody_key'); return Buffer.from(key); }
function derived(key, op, domain) { return Buffer.from(hkdfSync('sha256', key, Buffer.from(op), Buffer.from(domain), 32)); }
function mac(key, bytes) { return createHmac('sha256', key).update(bytes).digest('hex'); }
export function sourceSnapshotHmac(snapshot, custodyKey, operationId) {
  if (!UUID.test(operationId)) fail('invalid_operation');
  const key = keyCopy(custodyKey), hkey = derived(key, operationId, 'collect.graph.snapshot.v1');
  try { return mac(hkey, snapshotBytes(snapshot)); } finally { key.fill(0); hkey.fill(0); }
}
function equalHash(a, b) { return HASH.test(a ?? '') && HASH.test(b ?? '') && timingSafeEqual(Buffer.from(a, 'hex'), Buffer.from(b, 'hex')); }
export function verifyActorLineage({envelope, operationId, sourceOwnerId, cloudPrimaryId, custodyKey, originalUser, originalAccounts}) {
  if (!UUID.test(operationId ?? '') || typeof sourceOwnerId !== 'string' || typeof cloudPrimaryId !== 'string' ||
      !plain(envelope) || envelope.version !== 1 || envelope.algorithm !== 'AES-256-GCM' ||
      typeof envelope.nonce !== 'string' || typeof envelope.ciphertext !== 'string' || typeof envelope.tag !== 'string' ||
      !plain(originalUser) || !Array.isArray(originalAccounts)) return false;
  const key=keyCopy(custodyKey), aes=derived(key,operationId,'collect.actor.lineage.encryption.v1');
  let plaintext;
  try {
    const nonce=Buffer.from(envelope.nonce,'base64'),tag=Buffer.from(envelope.tag,'base64'),ciphertext=Buffer.from(envelope.ciphertext,'base64');
    if (nonce.length!==12 || tag.length!==16 || !ciphertext.length || ciphertext.length>MAX_BYTES) return false;
    const decipher=createDecipheriv('aes-256-gcm',aes,nonce);
    decipher.setAAD(Buffer.from(canonical(['collect.actor.lineage.v1',operationId,sourceOwnerId,cloudPrimaryId]))); decipher.setAuthTag(tag);
    plaintext=Buffer.concat([decipher.update(ciphertext),decipher.final()]);
    const expected=Buffer.from(canonical({user:originalUser,native_accounts:originalAccounts}));
    try { return timingSafeEqual(createHash('sha256').update(plaintext).digest(),createHash('sha256').update(expected).digest()); }
    finally { expected.fill(0); }
  } catch { return false; } finally { plaintext?.fill(0); key.fill(0); aes.fill(0); }
}
function uniqueMap(rows, column, code) {
  const map = new Map();
  for (const row of rows) {
    const key = row[column];
    if (typeof key !== 'string' || !key || map.has(key)) fail(code);
    map.set(key, row);
  }
  return map;
}
function same(a, b) { return canonical(a) === canonical(b); }
function quote(id) { if (!IDENT.test(id)) fail('invalid_catalogue_identifier'); return '"' + id + '"'; }
function relation(name) { const parts = name.split('.'); if (parts.length !== 2) fail('invalid_catalogue_identifier'); return parts.map(quote).join('.'); }

function validateGraph(t) {
  const receipts = uniqueMap(t['app.sms_receipts'], 'id', 'sms_key_conflict');
  const origins = uniqueMap(t['private.burimunsi_native_receipt_origins'], 'source_id', 'origin_key_conflict');
  const jobs = uniqueMap(t['private.burimunsi_auto_sms_jobs'], 'source_id', 'job_key_conflict');
  const objects = uniqueMap(t['private.storage_objects'], 'object_key', 'object_key_conflict');
  const reservations = uniqueMap(t['private.storage_payload_reservations'], 'object_key', 'reservation_key_conflict');
  const puts = uniqueMap(t['private.storage_put_intents'], 'operation_id', 'put_key_conflict');
  if (receipts.size !== origins.size || origins.size !== jobs.size) fail('native_sms_graph_incomplete');
  const objectKeys = new Set();
  function objectFor(row, purpose, prefix) {
    const obj = objects.get(row.object_key), reservation = reservations.get(row.object_key);
    const put = obj && puts.get(obj.operation_id);
    const scope = {ownerId: row.owner_user_id, purpose, entityId: row.id};
    if (!obj || !reservation || !put || objectKeys.has(row.object_key) || !same(obj.scope, scope) ||
        !same(put.scope, scope) || !same(reservation.scope, scope) || put.object_key !== row.object_key ||
        put.sha256 !== obj.sha256 || String(put.size) !== String(obj.size) || put.state !== 'committed' ||
        put.upload_unresolved !== false || put.delete_tombstone !== false || put.active_attempt !== null ||
        reservation.sealed_body !== null || reservation.plaintext_sha256 !== row.object_sha256 ||
        reservation.aad !== `${prefix}:${row.id}:${row.object_sha256}`) fail('protected_object_graph_mismatch');
    objectKeys.add(row.object_key);
  }
  for (const [id, receipt] of receipts) {
    const origin = origins.get(id), job = jobs.get(id);
    if (!origin || !job || receipt.owner_user_id !== origin.principal_user_id ||
        receipt.client_envelope_id !== origin.request_id || receipt.body_sha256 !== origin.body_sha256 ||
        receipt.object_sha256 !== origin.object_sha256 || receipt.object_key !== 'sms/' + id ||
        receipt.originating_session_id !== null || receipt.receiver_hash !== null || receipt.evidence_level !== 'client_received' ||
        job.collection_id !== origin.collection_id || job.source_fingerprint !== origin.fingerprint ||
        job.state !== 'completed' || job.phase !== 'finished' || job.lease_token !== null || job.lease_until !== null ||
        job.retry_lease !== null || job.next_attempt_at !== null) fail('native_sms_graph_mismatch');
    objectFor(receipt, 'sms_receipt', 'sms');
  }
  const evidence = uniqueMap(t['app.payment_evidence'], 'id', 'evidence_key_conflict');
  for (const row of evidence.values()) objectFor(row, 'payment_evidence', 'evidence');
  if (objectKeys.size !== objects.size || objectKeys.size !== reservations.size || puts.size !== objects.size) fail('unclassified_storage_object');
  const payments = uniqueMap(t['app.payments'], 'id', 'payment_key_conflict');
  const entries = uniqueMap(t['app.ledger_entries'], 'id', 'ledger_key_conflict');
  const byPayment = new Map();
  for (const entry of entries.values()) {
    if (entry.kind !== 'contribution' || byPayment.has(entry.payment_id)) fail('unsupported_ledger_shape');
    byPayment.set(entry.payment_id, entry);
  }
  if (payments.size !== byPayment.size || payments.size !== evidence.size) fail('financial_graph_incomplete');
  for (const p of payments.values()) {
    const e = byPayment.get(p.id), v = evidence.get(p.evidence_id);
    if (!e || !v || p.collection_id !== e.collection_id || p.collection_id !== v.collection_id ||
        p.member_id !== e.member_id || String(p.amount_minor) !== String(e.amount_minor) ||
        p.currency !== e.currency || p.evidence_id !== e.evidence_id) fail('financial_graph_mismatch');
  }
  const links = uniqueMap(t['app.momo_financial_links'], 'transaction_id', 'financial_link_conflict');
  const snapshots = uniqueMap(t['app.contribution_posting_snapshots'], 'ledger_entry_id', 'posting_snapshot_conflict');
  if (links.size !== payments.size || snapshots.size !== entries.size) fail('financial_history_incomplete');
  const linkedPayments = new Set();
  for (const l of links.values()) {
    const p = payments.get(l.payment_id);
    if (!p || linkedPayments.has(l.payment_id) || l.beneficiary_member_id !== p.member_id) fail('financial_link_mismatch');
    linkedPayments.add(l.payment_id);
  }
  for (const s of snapshots.values()) if (!entries.has(s.ledger_entry_id) || entries.get(s.ledger_entry_id).payment_id !== s.payment_id) fail('posting_snapshot_mismatch');
  for (const scope of t['private.burimunsi_scopes']) if (scope.enabled !== false || scope.active_binding_id !== null) fail('active_receiving_scope');
  return {sms: receipts.size, evidence: evidence.size, payments: payments.size, ledgerEntries: entries.size, objects: objectKeys.size};
}
export function inspectSourceGraph(snapshot) {
  snapshotBytes(snapshot);
  return {...validateGraph(snapshot.tables), readOnly: true, executionAuthorized: false};
}

function validateUsers(source, target, sourceOwnerId, cloudPrimaryId, aliasPublicId) {
  if (typeof sourceOwnerId !== 'string' || typeof cloudPrimaryId !== 'string' || !sourceOwnerId || !cloudPrimaryId || sourceOwnerId === cloudPrimaryId || !/^\d{6}$/.test(aliasPublicId)) fail('identity_selection_invalid');
  const sources = uniqueMap(source, 'id', 'source_user_key_conflict'), targets = uniqueMap(target, 'id', 'target_user_key_conflict');
  const owner = sources.get(sourceOwnerId), primary = targets.get(cloudPrimaryId);
  if (!owner || !primary || targets.has(sourceOwnerId)) fail('owner_identity_unavailable');
  const imported = source.map(row => row.id === sourceOwnerId ? {...row, phone: null, email: null, public_id: aliasPublicId, access_status: 'suspended'} : {...row});
  const seen = {id: new Set(), public_id: new Set(), phone: new Set(), email: new Set()};
  for (const row of [...target, ...imported]) for (const k of Object.keys(seen)) {
    if (row[k] == null) continue;
    if (typeof row[k] !== 'string' || !row[k]) fail('user_key_invalid');
    const value = k === 'email' ? row[k].trim().toLowerCase() : row[k];
    if (seen[k].has(value)) fail('user_key_collision');
    seen[k].add(value);
  }
  return {owner, imported};
}

function orderTables(catalog, rows) {
  const nodes = new Set(GRAPH), outgoing = new Map(GRAPH.map(t => [t, new Map()])), incoming = new Map(GRAPH.map(t => [t, 0]));
  const external = new Set();
  for (const table of GRAPH) {
    const info = catalog[table];
    if (!plain(info) || !Array.isArray(info.columns) || !Array.isArray(info.foreignKeys)) fail('catalogue_incomplete');
    relation(table);
    for (const fk of info.foreignKeys) {
      if (!plain(fk) || typeof fk.target !== 'string' || typeof fk.deferrable !== 'boolean' || !Array.isArray(fk.columns) || !Array.isArray(fk.targetColumns) || !fk.columns.length || fk.columns.length !== fk.targetColumns.length || [...fk.columns,...fk.targetColumns].some(c => typeof c !== 'string' || !IDENT.test(c))) fail('catalogue_incomplete');
      relation(fk.target);
      const tuples = rows[table].map(row => fk.columns.map(c => {if (!OWN(row,c)) fail('source_row_shape_changed'); return row[c];})).filter(values => values.every(value => value !== null));
      if (!nodes.has(fk.target)) { if (tuples.length) external.add(fk.target); continue; }
      const parents = new Set(rows[fk.target].map(row => canonical(fk.targetColumns.map(c => {if (!OWN(row,c)) fail('source_row_shape_changed'); return row[c];}))));
      if (tuples.some(tuple => !parents.has(canonical(tuple)))) fail('source_foreign_key_missing');
      if (fk.target === table && !fk.deferrable && tuples.length) fail('nondeferrable_self_dependency_unqualified');
      if (!tuples.length || fk.target === table) continue;
      const links = outgoing.get(fk.target);
      if (!links.has(table)) { links.set(table,!fk.deferrable); incoming.set(table, incoming.get(table) + 1); }
      else if (!fk.deferrable) links.set(table,true);
    }
  }
  // Actual row triggers require committed object journals before the
  // corresponding SMS/evidence insert, although these are not FK edges.
  for (const [parent, child] of [
    ['private.storage_payload_reservations','private.storage_put_intents'],
    ['private.storage_put_intents','private.storage_objects'],
    ['private.storage_payload_reservations','private.storage_objects'],
    ['private.storage_objects','app.sms_receipts'],
    ['private.storage_objects','app.payment_evidence'],
    ['private.storage_objects','private.burimunsi_unresolved_observations'],
  ]) if (rows[parent].length && rows[child].length) {
    const links=outgoing.get(parent);
    if (!links.has(child)) { links.set(child,true); incoming.set(child,incoming.get(child)+1); }
    else links.set(child,true);
  }
  const ready = GRAPH.filter(t => incoming.get(t) === 0).sort(), order = [], done = new Set();
  while (order.length < GRAPH.length) {
    if (!ready.length) {
      // Preserve deferrable edges where possible; break only a deferrable edge
      // in a remaining cycle. SET CONSTRAINTS ALL DEFERRED is mandatory.
      let broken = false;
      for (const parent of [...nodes].sort()) {
        if (done.has(parent)) continue;
        for (const [child, mandatory] of outgoing.get(parent)) {
          if (!done.has(child) && !mandatory) {
            outgoing.get(parent).delete(child); incoming.set(child,incoming.get(child)-1);
            if (incoming.get(child) === 0) ready.push(child);
            broken = true; break;
          }
        }
        if (broken) break;
      }
      if (!broken) fail('nondeferrable_dependency_cycle');
      ready.sort(); continue;
    }
    const next = ready.shift(); order.push(next);
    done.add(next);
    for (const dependent of outgoing.get(next).keys()) { incoming.set(dependent, incoming.get(dependent) - 1); if (incoming.get(dependent) === 0) { ready.push(dependent); ready.sort(); } }
  }
  return {order, external: [...external].sort()};
}

/** Produces private parameterized INSERTs, never executes them or contacts a service.
 * The result contains confidential row values and MUST NOT be logged or serialized.
 * Independent source/target catalogues, target identity/collisions, encrypted
 * custody, Storage proof, exclusions and writer fencing remain caller obligations.
 */
export function compileTransfer({snapshot, sourceCatalog, targetCatalog, targetUsers, sourceOwnerId, cloudPrimaryId, aliasPublicId, operationId, custodyKey, expectedSourceHmac, verifiedTargetObjects = null}) {
  if (!UUID.test(operationId) || !plain(sourceCatalog) || !plain(targetCatalog) || !Array.isArray(targetUsers)) fail('invalid_input');
  const key = keyCopy(custodyKey), actual = sourceSnapshotHmac(snapshot, key, operationId);
  if (!equalHash(actual, expectedSourceHmac)) { key.fill(0); fail('source_snapshot_changed'); }
  let tokenKey, encryptionKey;
  try {
    const t = snapshot.tables, counts = validateGraph(t);
    const {owner, imported} = validateUsers(t['app.users'], targetUsers, sourceOwnerId, cloudPrimaryId, aliasPublicId);
    const {order, external} = orderTables(sourceCatalog, t);
    const staged = Object.fromEntries(GRAPH.map(name => [name, t[name].map(row => structuredClone(row))]));
    staged['app.users'] = imported;
    const ownerAccounts = t['private.burimunsi_accounts'].filter(row => row.principal_user_id === sourceOwnerId);
    if (ownerAccounts.length !== 1 || ownerAccounts[0].removed !== false || t['private.burimunsi_accounts'].some(row => row.principal_user_id === cloudPrimaryId)) fail('native_owner_account_mapping_unavailable');
    tokenKey = derived(key, operationId, 'collect.historical.tokens.v1');
    for (const row of staged['private.burimunsi_accounts']) {
      if (row.principal_user_id === sourceOwnerId) row.principal_user_id = cloudPrimaryId;
      row.active = false; row.pin_hash = {};
    }
    for (const row of staged['private.burimunsi_device_grants']) {
      if (typeof row.id !== 'string' || !HASH.test(row.token_hash ?? '')) fail('grant_shape_invalid');
      const previous = row.token_hash; row.active = false; row.token_hash = mac(tokenKey, Buffer.from('grant\0' + row.id + '\0' + previous));
      if (row.token_hash === previous) fail('historical_token_not_retired');
    }
    for (const row of staged['private.burimunsi_sessions']) {
      if (typeof row.id !== 'string' || !HASH.test(row.token_hash ?? '')) fail('session_shape_invalid');
      const previous = row.token_hash; row.revoked = true;
      // The genuine lease guard forbids importing any lease on INSERT. Original
      // session metadata remains in the separately protected source capture.
      if (OWN(row,'pin_renewed_at')) row.pin_renewed_at = null;
      if (OWN(row,'pin_lease_expires_at')) row.pin_lease_expires_at = null;
      row.token_hash = mac(tokenKey, Buffer.from('session\0' + row.id + '\0' + previous));
      if (row.token_hash === previous) fail('historical_token_not_retired');
    }
    encryptionKey = derived(key, operationId, 'collect.actor.lineage.encryption.v1');
    const nonce = randomBytes(12), aad = Buffer.from(canonical(['collect.actor.lineage.v1', operationId, sourceOwnerId, cloudPrimaryId]));
    const cipher = createCipheriv('aes-256-gcm', encryptionKey, nonce); cipher.setAAD(aad);
    const plaintext = Buffer.from(canonical({user:owner,native_accounts:ownerAccounts}));
    let ciphertext;
    try { ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]); } finally { plaintext.fill(0); }
    const envelope = {version: 1, algorithm: 'AES-256-GCM', nonce: nonce.toString('base64'), ciphertext: ciphertext.toString('base64'), tag: cipher.getAuthTag().toString('base64')};
    const commands = [], missingStorage = [];
    for (const table of order) {
      const sc = sourceCatalog[table], tc = targetCatalog[table];
      if (!tc || !same(sc.columns, tc.columns)) fail('target_column_catalogue_mismatch');
      if (!same(sc.foreignKeys, tc.foreignKeys)) fail('target_fk_catalogue_mismatch');
      const columns = sc.columns.filter(c => c.generated !== true).map(c => c.name);
      if (!columns.length || new Set(columns).size !== columns.length || columns.some(c => !IDENT.test(c))) fail('catalogue_columns_invalid');
      for (const row of staged[table]) {
        if (Object.keys(row).some(k => !sc.columns.some(c => c.name === k)) || sc.columns.some(c => !OWN(row, c.name))) fail('source_row_shape_changed');
        if (table === 'private.storage_objects') {
          const proof = verifiedTargetObjects?.[row.object_key];
          if (!proof || proof.sha256 !== row.sha256 || String(proof.size) !== String(row.size) || typeof proof.etag !== 'string' || !proof.etag) { missingStorage.push(row.object_key); continue; }
          row.etag = proof.etag;
        }
        const context = table.startsWith('private.burimunsi_') && typeof row.collection_id === 'string' ? {collectionId:row.collection_id} : null;
        commands.push({table, sql: `INSERT INTO ${relation(table)} (${columns.map(quote).join(',')}) VALUES (${columns.map((_, i) => '$' + (i + 1)).join(',')})`, params: columns.map(c => row[c]), context});
      }
      if (table === 'app.users') commands.push({table: 'private.collect_migration_actor_lineage', sql: 'INSERT INTO private.collect_migration_actor_lineage (source_actor_id,cloud_primary_id,operation_id,snapshot_hmac,envelope) VALUES ($1,$2,$3,$4,$5)', params: [sourceOwnerId,cloudPrimaryId,operationId,actual,envelope]});
    }
    const historyJobs = uniqueMap(staged['private.burimunsi_auto_sms_jobs'], 'source_id', 'job_key_conflict');
    for (const origin of staged['private.burimunsi_native_receipt_origins']) {
      const job = historyJobs.get(origin.source_id);
      if (!job || !(job.transaction_id === null || typeof job.transaction_id === 'string')) fail('history_transaction_unavailable');
      commands.push({table: 'private.collect_imported_native_history', sql: 'INSERT INTO private.collect_imported_native_history (source_id,collection_id,request_id,transaction_id,body_sha256,object_sha256,source_fingerprint,operation_id) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)', params: [origin.source_id,origin.collection_id,origin.request_id,job.transaction_id,origin.body_sha256,origin.object_sha256,origin.fingerprint,operationId]});
    }
    return {summary: {...counts, tableCount: order.length, commandCount: commands.length, externalDependencyCount: external.length,
      missingObjectProofCount: missingStorage.length, executionAuthorized: false},
      transactionPrefix: ['BEGIN', 'SET CONSTRAINTS ALL DEFERRED'], commands, transactionSuffix: ['COMMIT'], externalDependencies: external};
  } finally { key.fill(0); tokenKey?.fill(0); encryptionKey?.fill(0); }
}
