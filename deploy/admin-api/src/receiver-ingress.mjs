import { digest } from './security.mjs';
import { verifyGatewaySignedEnvelope, assertGatewayAllowedIdentity } from './gateway.mjs';

export const RECEIVER_READ_PERMISSION = 'gateway.read';
export const RECEIVER_MANAGE_PERMISSION = 'gateway.manage';
export class ReceiverIngressError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
const fail = (status, code, message) => { throw new ReceiverIngressError(status, code, message); };
const require = condition => { if (!condition) fail(400, 'receiver_request_invalid', 'Receiver capture request is invalid.'); };
const q = (env, sql, ...values) => env.ADMIN_DB.prepare(sql).bind(...values);
const uuid = () => crypto.randomUUID(), now = () => Math.floor(Date.now() / 1000);
const iso = seconds => seconds == null ? null : new Date(seconds * 1000).toISOString();
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const keys = (value, expected) => object(value) && Object.keys(value).length === expected.length && expected.every(key => Object.hasOwn(value, key));
const id = value => { require(typeof value === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value)); return value; };
const integer = (value, minimum = 1, maximum = Number.MAX_SAFE_INTEGER) => { require(Number.isSafeInteger(value) && value >= minimum && value <= maximum); return value; };
const reason = value => { require(typeof value === 'string' && value.trim().length >= 8 && value.trim().length <= 1000 && !/[\x00-\x1f\x7f]/.test(value)); return value.trim(); };
const keyValid = value => typeof value === 'string' && /^[A-Za-z0-9_.-]{8,200}$/.test(value);
const canonical = value => JSON.stringify(value, (_, nested) => object(nested) ? Object.fromEntries(Object.keys(nested).sort().map(key => [key, nested[key]])) : nested);
const bytesHash = async bytes => Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), byte => byte.toString(16).padStart(2, '0')).join('');
function base64(bytes) { let output = ''; for (const byte of bytes) output += String.fromCharCode(byte); return btoa(output); }
function utc(value) { require(typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(value)); const ms = Date.parse(value); require(Number.isFinite(ms) && ms > 0 && new Date(ms).toISOString().slice(0, 19) === value.slice(0, 19)); return ms; }
const authSql = writes => `EXISTS(SELECT 1 FROM admin_sessions s JOIN admin_users a ON a.id=s.user_id WHERE s.token_hash=? AND a.id=? AND a.status='active' AND a.role=? AND a.role IN (${writes ? "'owner','admin'" : "'owner','admin','staff'"}) AND s.auth_version=a.auth_version AND s.auth_version=? AND s.expires_at>unixepoch())`;
const authValues = session => [session.token_hash, session.id, session.role, session.auth_version];
const canManage = session => ['owner', 'admin'].includes(session?.role) && session.permissions?.includes(RECEIVER_MANAGE_PERMISSION);
async function read(env, session, statements, writes = false) {
  const [authorization, ...results] = await env.ADMIN_DB.batch([q(env, `SELECT ${authSql(writes)} AS allowed`, ...authValues(session)), ...statements]);
  if (authorization.results[0].allowed !== 1) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.'); return results;
}
function adminAuthority(request, env, session, writes) {
  if (!session || session.status !== 'active' || !['owner', 'admin', 'staff'].includes(session.role)) fail(401, 'unauthenticated', 'Sign in to continue.');
  if (!session.permissions?.includes(writes ? RECEIVER_MANAGE_PERMISSION : RECEIVER_READ_PERMISSION) || (writes && !canManage(session))) fail(403, 'permission_required', 'This action is unavailable for this account.');
  const url = new URL(request.url), supplied = request.headers.get('Origin');
  if (url.origin !== env.ADMIN_ORIGIN || (url.protocol !== 'https:' && !(env.ENVIRONMENT === 'local' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)))
    || (supplied && supplied !== env.ADMIN_ORIGIN) || (writes && supplied !== env.ADMIN_ORIGIN) || request.headers.get('Sec-Fetch-Site') === 'cross-site') fail(403, 'origin_rejected', 'Use the configured Admin website.');
}
async function adminBody(request) {
  require(/^application\/json(?:;\s*charset=utf-8)?$/i.test(request.headers.get('Content-Type') || '') && !request.headers.has('Content-Encoding'));
  const reader = request.body?.getReader(); require(reader); const chunks = []; let size = 0, timeout;
  try { await Promise.race([
    (async () => { while (true) { const next = await reader.read(); if (next.done) break; size += next.value.byteLength; if (size > 16384) fail(413, 'request_too_large', 'Capture grant request is too large.'); chunks.push(next.value); } })(),
    new Promise((_, reject) => { timeout = setTimeout(() => reject(new ReceiverIngressError(408, 'request_timeout', 'Capture grant request timed out.')), 5000); }),
  ]); }
  finally { clearTimeout(timeout); reader.cancel().catch(() => {}); }
  const raw = new Uint8Array(size); let offset = 0; for (const chunk of chunks) { raw.set(chunk, offset); offset += chunk.length; }
  let data; try { data = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(raw)); } catch { require(false); } require(object(data)); return data;
}
function pagination(url, extra = []) {
  for (const key of url.searchParams.keys()) require(['limit', 'offset', ...extra].includes(key) && url.searchParams.getAll(key).length === 1);
  const limit = url.searchParams.get('limit') ?? '25', offset = url.searchParams.get('offset') ?? '0'; require(/^[1-9][0-9]*$/.test(limit) && /^(0|[1-9][0-9]*)$/.test(offset));
  return { limit: integer(Number(limit), 1, 100), offset: integer(Number(offset), 0, 2147483647) };
}
const grantSelect = `SELECT r.*,d.label AS device_label,d.installation_id,d.key_sha256,p.label AS payee_label,p.network AS payee_network,p.momo_number_or_code AS payee_momo_number_or_code FROM collect_gateway_receiver_grants r JOIN collect_gateway_devices d ON d.id=r.device_id JOIN collect_payees p ON p.id=r.payee_id`;
function grantDto(row) { return { id: row.id, device_id: row.device_id, device_label: row.device_label, installation_id: row.installation_id, key_sha256: row.key_sha256,
  payee_id: row.payee_id, payee_label: row.payee_label, payee_network: row.payee_network, payee_momo_number_or_code: row.payee_momo_number_or_code,
  status: row.status, version: row.version, created_by_admin_id: row.created_by_admin_id, created_at: iso(row.created_at), revoked_by_admin_id: row.revoked_by_admin_id, revoked_at: iso(row.revoked_at),
  capture_authority: row.status === 'active', send_authority: false, financial_authority: false }; }
const captureDto = row => ({ id: row.id, request_id: row.request_id, client_sms_id: row.client_sms_id, ingress_id: row.ingress_id, payload_sha256: row.payload_sha256, issued_at: row.issued_at,
  source_received_at: iso(row.source_received_at), accepted_at: iso(row.accepted_at), metadata_accepted: true, provider_confirmation: false, send_authority: false, financial_authority: false });
async function grantRead(env, session, url, grantId) {
  const page = pagination(url, grantId ? [] : ['device_id', 'payee_id', 'status']);
  if (grantId) {
    id(grantId); const [grant, count, captures] = await read(env, session, [q(env, `${grantSelect} WHERE r.id=?`, grantId), q(env, 'SELECT count(*) AS total FROM collect_gateway_receiver_requests WHERE grant_id=?', grantId),
      q(env, 'SELECT id,request_id,client_sms_id,ingress_id,payload_sha256,issued_at,source_received_at,accepted_at FROM collect_gateway_receiver_requests WHERE grant_id=? ORDER BY accepted_at DESC,id DESC LIMIT ? OFFSET ?', grantId, page.limit, page.offset)]);
    if (!grant.results[0]) fail(404, 'not_found', 'This capture grant does not exist.');
    return { resource_type: 'receiver_capture_grants', resource: grantDto(grant.results[0]), current_actor_id: session.id, can_manage: canManage(session), related: { captures: captures.results.map(captureDto) }, related_total: count.results[0].total, related_limit: page.limit, related_offset: page.offset };
  }
  const filters = [], args = []; for (const field of ['device_id', 'payee_id']) if (url.searchParams.has(field)) { filters.push(`r.${field}=?`); args.push(id(url.searchParams.get(field))); }
  const status = url.searchParams.get('status'); if (status !== null) { require(['active', 'revoked'].includes(status)); filters.push('r.status=?'); args.push(status); }
  const where = filters.length ? ` WHERE ${filters.join(' AND ')}` : '';
  const [count, rows] = await read(env, session, [q(env, `SELECT count(*) AS total FROM collect_gateway_receiver_grants r${where}`, ...args), q(env, `${grantSelect}${where} ORDER BY r.created_at DESC,r.id DESC LIMIT ? OFFSET ?`, ...args, page.limit, page.offset)]);
  return { rows: rows.results.map(grantDto), total: count.results[0].total, limit: page.limit, offset: page.offset };
}
async function requestReceipt(env, session, url, key) {
  require(!url.search && keyValid(key)); const [rows] = await read(env, session, [q(env, "SELECT status,response_json FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=? AND scope IN ('gateway.receiver.grant','gateway.receiver.revoke')", session.id, key)]);
  if (!rows.results[0]) return { found: false }; const row = rows.results[0]; if (row.status !== 'succeeded') fail(409, 'request_pending', 'Preserve the original request and check again.'); return { found: true, receipt: JSON.parse(row.response_json) };
}
async function grantMutation(request, env, session, url, grantId) {
  require(!url.search); const data = await adminBody(request), key = request.headers.get('Idempotency-Key'); require(keyValid(key)); const why = reason(data.reason);
  if (grantId) { id(grantId); require(keys(data, ['expected_version', 'reason'])); integer(data.expected_version, 1, Number.MAX_SAFE_INTEGER - 1); }
  else { require(keys(data, ['device_id', 'expected_device_version', 'payee_id', 'expected_payee_version', 'reason'])); id(data.device_id); id(data.payee_id); integer(data.expected_device_version); integer(data.expected_payee_version); }
  const requestHash = await digest(canonical({ path: url.pathname, body: data })), [old] = await read(env, session, [q(env, 'SELECT * FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', session.id, key)], true);
  if (old.results[0]) { const row = old.results[0]; if (row.request_sha256 !== requestHash) fail(409, 'idempotency_conflict', 'This request identifier belongs to different content.'); if (row.status !== 'succeeded') fail(409, 'request_pending', 'Check the original receipt.'); return JSON.parse(row.response_json); }
  if (!grantId) {
    const device = await q(env, 'SELECT app_id,signing_certificate_sha256 FROM collect_gateway_devices WHERE id=?', data.device_id).first();
    if (!device) fail(404, 'not_found', 'This gateway device does not exist.');
    assertGatewayAllowedIdentity(env, device.app_id, device.signing_certificate_sha256);
  }
  const operationId = uuid(), resourceId = grantId ?? uuid(), at = now(), action = grantId ? 'gateway.receiver.revoke' : 'gateway.receiver.grant';
  const owns = 'EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)', guardId = `${operationId}:state`;
  const receipt = { request_id: operationId, resource_type: 'receiver_capture_grants', resource_id: resourceId, version: grantId ? data.expected_version + 1 : 1, status: 'succeeded' };
  const effects = grantId ? [
    q(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN NOT ${owns} OR EXISTS(SELECT 1 FROM collect_gateway_receiver_grants WHERE id=? AND version=? AND status='active') THEN 1 ELSE 0 END`, guardId, operationId, grantId, data.expected_version),
    q(env, `UPDATE collect_gateway_receiver_grants SET status='revoked',version=version+1,revoked_by_admin_id=?,revocation_operation_request_id=?,revocation_reason=?,revoked_at=? WHERE id=? AND ${owns}`, session.id, operationId, why, at, grantId, operationId),
  ] : [
    q(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN NOT ${owns} OR (EXISTS(SELECT 1 FROM collect_gateway_devices WHERE id=? AND state='active' AND version=?) AND EXISTS(SELECT 1 FROM collect_payees p JOIN collect_groups g ON g.id=p.group_id WHERE p.id=? AND p.status='active' AND p.version=? AND g.status='active')) THEN 1 ELSE 0 END`, guardId, operationId, data.device_id, data.expected_device_version, data.payee_id, data.expected_payee_version),
    q(env, `INSERT INTO collect_gateway_receiver_grants(id,device_id,payee_id,created_by_admin_id,creation_operation_request_id,creation_reason,created_at) SELECT ?,?,?,?,?,?,? WHERE ${owns}`, resourceId, data.device_id, data.payee_id, session.id, operationId, why, at, operationId),
  ];
  try {
    const results = await env.ADMIN_DB.batch([
      q(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN ${authSql(true)} THEN 1 ELSE 0 END`, `${operationId}:auth`, ...authValues(session)),
      q(env, 'INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,?,?,?,?) ON CONFLICT(actor_admin_id,idempotency_key) DO NOTHING', operationId, session.id, action, key, requestHash, at),
      q(env, 'INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=? AND request_sha256=?) THEN 1 ELSE 0 END', `${operationId}:key`, session.id, key, requestHash), ...effects,
      q(env, `INSERT INTO collect_operations_audit(id,actor_admin_id,operation_request_id,action,subject_type,subject_id,evidence_json,occurred_at) SELECT ?,?,?,?,?,?,?,? WHERE ${owns}`, uuid(), session.id, operationId, action, 'receiver_capture_grants', resourceId, JSON.stringify({ reason: why, request_sha256: requestHash, device_id: data.device_id ?? null, payee_id: data.payee_id ?? null, previous_version: data.expected_version ?? null, resulting_version: receipt.version, capture_only: true }), at, operationId),
      q(env, `UPDATE collect_operation_requests SET status='succeeded',response_json=?,completed_at=? WHERE id=?`, JSON.stringify(receipt), at, operationId),
      q(env, 'DELETE FROM collect_mutation_guards WHERE id LIKE ?', `${operationId}:%`),
      q(env, 'SELECT response_json FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', session.id, key),
    ]); return JSON.parse(results.at(-1).results[0].response_json);
  } catch (error) {
    await read(env, session, [], true);
    if (/constraint|immutable|CHECK|UNIQUE|FOREIGN KEY|guard_failed/i.test(String(error))) fail(409, 'state_conflict', 'The device, payee or capture grant changed. Refresh before creating a new request.');
    fail(503, 'receiver_outcome_unknown', 'The outcome is unknown. Preserve the original key and check its receipt.');
  }
}
function validateCapture(data) {
  require(keys(data, ['contract_version', 'action', 'device_id', 'request_id', 'issued_at', 'payload']) && data.contract_version === 1 && data.action === 'capture_receipt');
  const payload = data.payload; require(keys(payload, ['installation_id', 'client_sms_id', 'raw_sender', 'raw_body', 'received_at'])); id(payload.installation_id); id(payload.client_sms_id); utc(payload.received_at);
  require(typeof payload.raw_sender === 'string' && payload.raw_sender.trim().length > 0 && payload.raw_sender.length <= 80 && !/[\x00-\x1f\x7f]/.test(payload.raw_sender));
  require(typeof payload.raw_body === 'string' && payload.raw_body.length >= 1 && payload.raw_body.length <= 16000 && !payload.raw_body.includes('\0'));
}
async function ensurePayload(env, key, bytes, expectedHash) {
  const bucket = env.RECEIPT_PAYLOADS; if (!bucket?.get || !bucket?.put) fail(503, 'receiver_storage_unavailable', 'Private receiver receipt storage is not configured.');
  let existing;
  async function matches() {
    let stored; try { stored = await bucket.get(key); } catch { fail(503, 'receiver_storage_unknown', 'Storage outcome is unknown. Preserve the original signed request.'); }
    if (!stored) return false;
    if (!Number.isSafeInteger(stored.size) || stored.size !== bytes.length || stored.size > 131072) fail(409, 'receiver_storage_conflict', 'Stored receiver evidence conflicts with this SMS identifier.');
    let raw; try { raw = new Uint8Array(await stored.arrayBuffer()); } catch { fail(503, 'receiver_storage_unknown', 'Storage outcome is unknown. Preserve the original signed request.'); }
    if (raw.length !== bytes.length || await bytesHash(raw) !== expectedHash || raw.some((byte, i) => byte !== bytes[i])) fail(409, 'receiver_storage_conflict', 'Stored receiver evidence conflicts with this SMS identifier.');
    return true;
  }
  existing = await matches(); if (existing) return;
  // Conditional writes preserve orphan evidence after a lost response or D1 failure.
  // A thrown/null put is acceptable only if a fresh read proves the exact bytes.
  try { await bucket.put(key, bytes, { onlyIf: { etagDoesNotMatch: '*' }, httpMetadata: { contentType: 'application/json' }, customMetadata: { payload_sha256: expectedHash } }); } catch { /* Read authoritative storage below. */ }
  if (!await matches()) fail(503, 'receiver_storage_unknown', 'Storage outcome is unknown. Preserve the original signed request.');
}
async function capture(request, env) {
  const verified = await verifyGatewaySignedEnvelope(request, env, { validateEnvelope: validateCapture, maximumBytes: 131072 });
  const { data, raw, requestHash, signature, device, issuedAtMs, receivedAt, authGuardSql, authGuardArgs } = verified, payload = data.payload;
  if (payload.installation_id !== device.installation_id) fail(401, 'gateway_key_refused', 'Gateway installation could not be verified.');
  const signedBytes = base64(raw), previous = await q(env, 'SELECT * FROM collect_gateway_receiver_requests WHERE device_id=? AND request_id=?', device.id, data.request_id).first();
  if (previous && (previous.request_sha256 !== requestHash || previous.signed_request_base64 !== signedBytes)) fail(409, 'gateway_request_conflict', 'This request identifier belongs to different exact bytes.');
  const sourceMs = utc(payload.received_at), sourceAt = Math.floor(sourceMs / 1000);
  if (!previous && (Math.abs(Date.now() - issuedAtMs) > 120000 || sourceMs > Date.now() + 30000)) fail(400, 'gateway_request_expired', 'The signed request timestamp is outside the accepted window.');
  const grant = await q(env, `SELECT r.*,p.status AS payee_status,g.status AS group_status FROM collect_gateway_receiver_grants r JOIN collect_payees p ON p.id=r.payee_id JOIN collect_groups g ON g.id=p.group_id WHERE r.device_id=? AND r.status='active'${previous ? ' AND r.id=?' : ''}`, device.id, ...(previous ? [previous.grant_id] : [])).first();
  if (!grant || grant.payee_status !== 'active' || grant.group_status !== 'active') fail(403, 'receiver_grant_inactive', 'This device has no active receiver capture grant.');
  const sourceKey = `gateway:${grant.id}:${device.id}`, objectKey = `receiver/v1/${grant.id}/${device.id}/${payload.client_sms_id}.json`;
  const sourceBytes = new TextEncoder().encode(canonical({ raw_sender: payload.raw_sender, raw_body: payload.raw_body })), payloadHash = await bytesHash(sourceBytes);
  await ensurePayload(env, objectKey, sourceBytes, payloadHash);
  const receiptId = uuid(), ingressId = uuid(), guardId = uuid();
  const response = { contract_version: 1, action: 'capture_receipt', device_id: device.id, request_id: data.request_id,
    result: { receipt_id: receiptId, ingress_id: ingressId, client_sms_id: payload.client_sms_id, source_kind: 'receiver', payload_sha256: payloadHash, accepted_at: iso(receivedAt), metadata_accepted: true, provider_confirmation: false, send_authority: false, financial_authority: false } };
  try {
    const results = await env.ADMIN_DB.batch([
      q(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN ${authGuardSql} THEN 1 ELSE 0 END`, `${guardId}:device`, ...authGuardArgs),
      q(env, "INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM collect_gateway_receiver_grants r JOIN collect_payees p ON p.id=r.payee_id JOIN collect_groups g ON g.id=p.group_id WHERE r.id=? AND r.device_id=? AND r.payee_id=? AND r.status='active' AND r.version=? AND p.status='active' AND g.status='active') THEN 1 ELSE 0 END", `${guardId}:grant`, grant.id, device.id, grant.payee_id, grant.version),
      q(env, 'INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM collect_gateway_receiver_requests WHERE device_id=? AND request_id=? AND request_sha256=? AND signed_request_base64=?) OR (abs(unixepoch()*1000-?)<=120000 AND ?<=unixepoch()*1000+30000) THEN 1 ELSE 0 END', `${guardId}:time`, device.id, data.request_id, requestHash, signedBytes, issuedAtMs, sourceMs),
      q(env, 'INSERT INTO collect_receipt_ingress(id,source_key,external_message_id,payee_id,payload_sha256,payload_object_key,received_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(source_key,external_message_id) DO NOTHING', ingressId, sourceKey, payload.client_sms_id, grant.payee_id, payloadHash, objectKey, sourceAt),
      q(env, 'INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM collect_receipt_ingress WHERE source_key=? AND external_message_id=? AND payee_id=? AND payload_sha256=? AND payload_object_key=? AND received_at=?) THEN 1 ELSE 0 END', `${guardId}:source`, sourceKey, payload.client_sms_id, grant.payee_id, payloadHash, objectKey, sourceAt),
      // ingress_id may be from an earlier request for the same stable SMS UUID.
      q(env, `INSERT INTO collect_gateway_receiver_requests(id,device_id,request_id,request_sha256,signed_request_base64,signature_base64,grant_id,payee_id,client_sms_id,ingress_id,payload_sha256,issued_at,source_received_at,accepted_at,response_json)
        SELECT ?,?,?,?,?,?,?,?,?,i.id,?,?,?,?,json_set(?, '$.result.ingress_id', i.id) FROM collect_receipt_ingress i WHERE i.source_key=? AND i.external_message_id=? ON CONFLICT(device_id,request_id) DO NOTHING`,
      receiptId, device.id, data.request_id, requestHash, signedBytes, signature, grant.id, grant.payee_id, payload.client_sms_id, payloadHash, data.issued_at, sourceAt, receivedAt, JSON.stringify(response), sourceKey, payload.client_sms_id),
      q(env, 'INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM collect_gateway_receiver_requests WHERE device_id=? AND request_id=? AND request_sha256=? AND signed_request_base64=? AND grant_id=? AND payload_sha256=?) THEN 1 ELSE 0 END', `${guardId}:replay`, device.id, data.request_id, requestHash, signedBytes, grant.id, payloadHash),
      q(env, 'DELETE FROM collect_mutation_guards WHERE id LIKE ?', `${guardId}:%`),
      q(env, 'SELECT response_json FROM collect_gateway_receiver_requests WHERE device_id=? AND request_id=?', device.id, data.request_id),
    ]); return JSON.parse(results.at(-1).results[0].response_json);
  } catch (error) {
    const current = await q(env, 'SELECT state,version FROM collect_gateway_devices WHERE id=?', device.id).first();
    if (!current || current.state !== 'active' || current.version !== device.version) fail(403, 'gateway_device_inactive', 'The gateway device is no longer active.');
    const active = await q(env, "SELECT r.id FROM collect_gateway_receiver_grants r JOIN collect_payees p ON p.id=r.payee_id JOIN collect_groups g ON g.id=p.group_id WHERE r.id=? AND r.status='active' AND r.version=? AND p.status='active' AND g.status='active'", grant.id, grant.version).first();
    if (!active) fail(403, 'receiver_grant_inactive', 'The receiver capture grant is no longer active.');
    if (/constraint|immutable|CHECK|UNIQUE|FOREIGN KEY|guard_failed/i.test(String(error))) fail(409, 'gateway_request_conflict', 'The signed request or stable SMS identifier conflicts with retained source evidence.');
    fail(503, 'receiver_outcome_unknown', 'The outcome is unknown. Preserve and resend only the original exact signed request.');
  }
}

export async function handleReceiverIngress(request, env, session = null) {
  const url = new URL(request.url);
  if (url.pathname === '/api/gateway/receiver-receipts') { require(!url.search); return capture(request, env); }
  if (!url.pathname.startsWith('/api/admin/gateway/')) fail(404, 'not_found', 'Receiver capture route does not exist.');
  const parts = url.pathname.slice('/api/admin/gateway/'.length).split('/');
  require(parts.every(Boolean)); const writes = request.method === 'POST'; adminAuthority(request, env, session, writes);
  if (parts[0] === 'receiver-requests' && parts.length === 2 && request.method === 'GET') return requestReceipt(env, session, url, parts[1]);
  if (parts[0] === 'receiver-grants') {
    if (request.method === 'GET' && parts.length <= 2) return grantRead(env, session, url, parts[1]);
    if (request.method === 'POST' && (parts.length === 1 || (parts.length === 3 && parts[2] === 'revoke'))) return grantMutation(request, env, session, url, parts[1]);
  }
  fail(405, 'method_not_allowed', 'This receiver capture action is unavailable.');
}
