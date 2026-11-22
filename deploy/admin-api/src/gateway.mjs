import { digest } from './security.mjs';
import { reviewedMemberSmsLinkStatements } from './admin-sms.mjs';
export const GATEWAY_READ_PERMISSION = 'gateway.read';
export const GATEWAY_MANAGE_PERMISSION = 'gateway.manage';
export class GatewayError extends Error { constructor(status, code, message) { super(message); this.status = status; this.code = code; } }
const fail = (status, code, message) => { throw new GatewayError(status, code, message); };
const invalid = (message = 'Gateway request is invalid.') => fail(400, 'gateway_request_invalid', message);
const require = condition => { if (!condition) invalid(); };
const q = (env, sql, ...values) => env.ADMIN_DB.prepare(sql).bind(...values);
const now = () => Math.floor(Date.now() / 1000), uuid = () => crypto.randomUUID(), iso = seconds => seconds == null ? null : new Date(seconds * 1000).toISOString();
const isId = value => typeof value === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(value);
const isHash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const id = value => { require(isId(value)); return value; };
const hash = value => { require(isHash(value)); return value; };
const str = (value, min, max) => { require(typeof value === 'string' && value.trim().length >= min && value.trim().length <= max && !/[\x00-\x1f\x7f]/.test(value)); return value.trim(); };
const integer = (value, minimum = 1, maximum = Number.MAX_SAFE_INTEGER) => { require(Number.isSafeInteger(value) && value >= minimum && value <= maximum); return value; };
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const keys = (value, expected) => object(value) && Object.keys(value).length === expected.length && expected.every(key => Object.hasOwn(value, key));
const canonical = value => JSON.stringify(value, (_, nested) => object(nested) ? Object.fromEntries(Object.keys(nested).sort().map(key => [key, nested[key]])) : nested);
const keyValid = value => typeof value === 'string' && /^[A-Za-z0-9_.-]{8,200}$/.test(value);
const canManage = (session, permission = GATEWAY_MANAGE_PERMISSION) => ['owner', 'admin'].includes(session?.role) && session.permissions?.includes(permission);
const authSql = writes => `EXISTS(SELECT 1 FROM admin_sessions s JOIN admin_users a ON a.id=s.user_id WHERE s.token_hash=? AND a.id=? AND a.status='active' AND a.role=? AND a.role IN (${writes ? "'owner','admin'" : "'owner','admin','staff'"}) AND s.auth_version=a.auth_version AND s.auth_version=? AND s.expires_at>unixepoch())`;
const authValues = session => [session.token_hash, session.id, session.role, session.auth_version];
async function read(env, session, statements, writes = false) {
  const [authorization, ...results] = await env.ADMIN_DB.batch([q(env, `SELECT ${authSql(writes)} AS allowed`, ...authValues(session)), ...statements]);
  if (authorization.results[0].allowed !== 1) fail(401, 'unauthenticated', 'Your session has ended. Sign in again.'); return results;
}
function sessionRequired(session, permission, writes = false) {
  if (!session || session.status !== 'active' || !['owner', 'admin', 'staff'].includes(session.role)) fail(401, 'unauthenticated', 'Sign in to continue.');
  if (!session.permissions?.includes(permission) || (writes && !canManage(session, permission))) fail(403, 'permission_required', 'This action is unavailable for this account.');
}
function base64(value, maximum) {
  require(typeof value === 'string' && value.length > 0 && value.length <= maximum && /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value));
  let decoded; try { decoded = atob(value); } catch { invalid(); } require(btoa(decoded) === value);
  return Uint8Array.from(decoded, character => character.charCodeAt(0));
}
const hex = bytes => Array.from(bytes, byte => byte.toString(16).padStart(2, '0')).join('');
const bytesHash = async bytes => hex(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)));
export function gatewayDerToP1363(der) {
  require(der.length >= 8 && der.length <= 72 && der[0] === 0x30 && der[1] === der.length - 2);
  let offset = 2; const output = new Uint8Array(64);
  for (let component = 0; component < 2; component++) {
    require(der[offset++] === 2); const size = der[offset++]; require(size >= 1 && size <= 33 && offset + size <= der.length);
    let value = der.slice(offset, offset + size); offset += size;
    require(!(value[0] & 0x80) && (value.length === 1 || value[0] !== 0 || Boolean(value[1] & 0x80)));
    if (value[0] === 0) value = value.slice(1); require(value.length > 0 && value.length <= 32);
    const number = BigInt(`0x${hex(value)}`); require(number > 0n && number < 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551n);
    output.set(value, component * 32 + 32 - value.length);
  }
  require(offset === der.length); return output;
}
async function publicKey(spkiBase64, fingerprint) {
  const bytes = base64(spkiBase64, 124);
  require(bytes.length === 91 && hex(bytes.slice(0, 27)) === '3059301306072a8648ce3d020106082a8648ce3d03010703420004' && await bytesHash(bytes) === fingerprint);
  try { return await crypto.subtle.importKey('spki', bytes, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']); } catch { invalid('The enrolled public key is not a valid P-256 key.'); }
}
function allowedIdentity(env, appId, certificate) {
  let policy; try { policy = JSON.parse(env.GATEWAY_ALLOWED_IDENTITIES || 'null'); } catch { policy = null; }
  if (!Array.isArray(policy) || policy.length < 1 || policy.length > 20 || policy.some(item => !keys(item, ['app_id', 'signing_certificate_sha256']) || typeof item.app_id !== 'string' || !/^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$/.test(item.app_id) || !isHash(item.signing_certificate_sha256))) fail(503, 'gateway_identity_policy_unavailable', 'Gateway identity approval is not configured.');
  if (!policy.some(item => item.app_id === appId && item.signing_certificate_sha256 === certificate)) fail(403, 'gateway_identity_not_allowed', 'This app and signing identity are not approved for gateway enrollment.');
}
export const assertGatewayAllowedIdentity=(env,appId,certificate)=>allowedIdentity(env,appId,certificate);
// Native signatures bind the bytes before parsing. Duplicate-key and nesting
// checks prevent ambiguous interpretations between Kotlin and the Worker.
function parseStrict(source) {
  let offset = 0;
  const whitespace = () => { while (/[\t\r\n ]/.test(source[offset] ?? 'x')) offset++; };
  const string = () => {
    require(source[offset] === '"'); const start = offset++;
    while (offset < source.length) { const char = source[offset++]; if (char === '\\') { offset++; continue; } if (char === '"') { try { return JSON.parse(source.slice(start, offset)); } catch { invalid(); } } }
    invalid();
  };
  const value = depth => {
    require(depth <= 8); whitespace();
    if (source[offset] === '{') { offset++; whitespace(); const seen = new Set(); if (source[offset] === '}') { offset++; return; }
      while (true) { whitespace(); const key = string(); require(!seen.has(key)); seen.add(key); whitespace(); require(source[offset++] === ':'); value(depth + 1); whitespace(); if (source[offset] === '}') { offset++; return; } require(source[offset++] === ','); }
    } else if (source[offset] === '[') { offset++; whitespace(); if (source[offset] === ']') { offset++; return; } while (true) { value(depth + 1); whitespace(); if (source[offset] === ']') { offset++; return; } require(source[offset++] === ','); } }
    else if (source[offset] === '"') string();
    else { const token = /^(?:true|false|null|-?(?:0|[1-9][0-9]*))/.exec(source.slice(offset)); require(token); offset += token[0].length; }
  };
  value(0); whitespace(); require(offset === source.length);
  try { return JSON.parse(source); } catch { invalid(); }
}
async function streamBytes(stream, maximum) {
  if (!stream) invalid(); const reader = stream.getReader(); let total = 0; const chunks = []; let timeout;
  try {
    return await Promise.race([
      (async () => { while (true) { const next = await reader.read(); if (next.done) break; total += next.value.byteLength; if (total > maximum) fail(413, 'request_too_large', 'Gateway request is too large.'); chunks.push(next.value); }
        require(total > 0); const output = new Uint8Array(total); let offset = 0; for (const chunk of chunks) { output.set(chunk, offset); offset += chunk.length; } return output; })(),
      new Promise((_, reject) => { timeout = setTimeout(() => reject(new GatewayError(408, 'request_timeout', 'Gateway request timed out.')), 5000); }),
    ]);
  } finally { clearTimeout(timeout); reader.cancel().catch(() => {}); }
}
async function body(request,maximum=32768) {
  require(/^application\/json(?:;\s*charset=utf-8)?$/i.test(request.headers.get('Content-Type') || '') && !request.headers.has('Content-Encoding'));
  const raw = await streamBytes(request.body, maximum); require(!(raw[0] === 0xef && raw[1] === 0xbb && raw[2] === 0xbf));
  let source; try { source = new TextDecoder('utf-8', { fatal: true }).decode(raw); } catch { invalid(); }
  return { raw, data: parseStrict(source) };
}
function utc(value) {
  require(typeof value === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/.test(value));
  const ms = Date.parse(value); require(Number.isFinite(ms) && new Date(ms).toISOString().slice(0, 19) === value.slice(0, 19)); return ms;
}
function page(url, statuses, filterName = 'state') {
  for (const key of url.searchParams.keys()) require(['limit', 'offset', filterName].includes(key) && url.searchParams.getAll(key).length === 1);
  const rawLimit = url.searchParams.get('limit') ?? '25', rawOffset = url.searchParams.get('offset') ?? '0';
  require(/^[1-9][0-9]*$/.test(rawLimit) && /^(0|[1-9][0-9]*)$/.test(rawOffset));
  const status = url.searchParams.get(filterName) ?? ''; require(status === '' || statuses.includes(status));
  return { limit: integer(Number(rawLimit), 1, 100), offset: integer(Number(rawOffset), 0, 2147483647), status };
}
const deviceSelect = `SELECT d.*,(SELECT max(ingested_at) FROM collect_gateway_heartbeats h WHERE h.device_id=d.id) AS last_heartbeat_at FROM collect_gateway_devices d`;
function deviceDto(row, detail = false) {
  return { id: row.id, label: row.label, app_id: row.app_id, installation_id: row.installation_id, key_sha256: row.key_sha256, signing_certificate_sha256: row.signing_certificate_sha256,
    state: row.state, version: row.version, created_at: iso(row.created_at), activated_at: iso(row.activated_at), revoked_at: iso(row.revoked_at), last_heartbeat_at: iso(row.last_heartbeat_at), carrier_proof: false, send_authority: false,
    ...(detail ? { public_key_spki_base64: row.public_key_spki_base64 } : {}) };
}
async function deviceRead(env, session, url, deviceId) {
  if (deviceId) {
    require(!url.search); id(deviceId);
    const [device, beats] = await read(env, session, [q(env, `${deviceSelect} WHERE d.id=?`, deviceId), q(env, 'SELECT * FROM collect_gateway_heartbeats WHERE device_id=? ORDER BY ingested_at DESC,id DESC LIMIT 101', deviceId)]);
    const row = device.results[0]; if (!row) fail(404, 'not_found', 'This device does not exist.');
    return { resource_type: 'gateway_devices', resource: deviceDto(row, true), current_actor_id: session.id, can_manage: canManage(session),
      related: { heartbeats: beats.results.slice(0, 100).map(beat => ({ observation_id: beat.id, request_id: beat.request_id, issued_at: beat.issued_at, reported_at: beat.reported_at, ingested_at: iso(beat.ingested_at), ...JSON.parse(beat.observations_json), carrier_proof: false, send_authority: false })) }, related_truncated: beats.results.length > 100,
      enrollment: { contract_version: 1, device_id: row.id, installation_id: row.installation_id, key_sha256: row.key_sha256, signing_certificate_sha256: row.signing_certificate_sha256 } };
  }
  const filter = page(url, ['pending', 'active', 'revoked']); const where = filter.status ? ' WHERE state=?' : ''; const args = filter.status ? [filter.status] : [];
  const [count, rows] = await read(env, session, [q(env, `SELECT count(*) AS total FROM collect_gateway_devices${where}`, ...args), q(env, `${deviceSelect}${where} ORDER BY created_at DESC,id DESC LIMIT ? OFFSET ?`, ...args, filter.limit, filter.offset)]);
  return { rows: rows.results.map(row => deviceDto(row)), total: count.results[0].total };
}
function mutationPlan(env, operationId) {
  const exists = 'EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)'; const statements = []; let index = 0;
  return { statements,
    assert(sql, ...args) { statements.push(q(env, `INSERT INTO collect_mutation_guards(id,passed) VALUES(?,CASE WHEN NOT ${exists} OR (${sql}) THEN 1 ELSE 0 END)`, `${operationId}:${++index}`, operationId, ...args)); },
    insert(table, data) { const names = Object.keys(data); statements.push(q(env, `INSERT INTO ${table}(${names.join(',')}) SELECT ${names.map(() => '?').join(',')} WHERE ${exists}`, ...Object.values(data), operationId)); },
    update(table, data, where, ...args) { statements.push(q(env, `UPDATE ${table} SET ${Object.keys(data).map(key => `${key}=?`).join(',')} WHERE ${where} AND ${exists}`, ...Object.values(data), ...args, operationId)); },
  };
}
async function commitMutation(env, session, request, parts, data, build) {
  const key = request.headers.get('Idempotency-Key'); require(keyValid(key)); const reason = str(data.reason, 8, 1000);
  const inputHash = await digest(canonical({ path: parts.join('/'), body: data }));
  const [replay] = await read(env, session, [q(env, 'SELECT * FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', session.id, key)], true);
  if (replay.results[0]) { const old = replay.results[0]; if (old.request_sha256 !== inputHash) fail(409, 'idempotency_conflict', 'This request key belongs to different content.'); if (old.status !== 'succeeded') fail(409, 'request_pending', 'Check the original request before continuing.'); return JSON.parse(old.response_json); }
  const requestId = uuid(), p = mutationPlan(env, requestId), at = now(); const result = await build(p, requestId, at);
  const receipt = { request_id: requestId, resource_type: result.type, resource_id: result.id, version: result.version, status: 'succeeded' };
  const statements = [q(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN ${authSql(true)} THEN 1 ELSE 0 END`, `${requestId}:auth`, ...authValues(session)),
    q(env, 'INSERT INTO collect_operation_requests(id,actor_admin_id,scope,idempotency_key,request_sha256,created_at) VALUES(?,?,?,?,?,?) ON CONFLICT(actor_admin_id,idempotency_key) DO NOTHING', requestId, session.id, result.action, key, inputHash, at),
    q(env, 'INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=? AND request_sha256=?) THEN 1 ELSE 0 END', `${requestId}:key`, session.id, key, inputHash),
    ...p.statements,
    q(env, 'INSERT INTO collect_operations_audit(id,actor_admin_id,operation_request_id,action,subject_type,subject_id,evidence_json,occurred_at) SELECT ?,?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM collect_operation_requests WHERE id=?)', uuid(), session.id, requestId, result.action, result.type, result.id, JSON.stringify({ reason, request_sha256: inputHash, previous_version: data.expected_version ?? null, resulting_version: result.version }), at, requestId),
    q(env, "UPDATE collect_operation_requests SET status='succeeded',response_json=?,completed_at=? WHERE id=?", JSON.stringify(receipt), at, requestId),
    q(env, 'DELETE FROM collect_mutation_guards WHERE id LIKE ?', `${requestId}:%`),
    q(env, 'SELECT response_json FROM collect_operation_requests WHERE actor_admin_id=? AND idempotency_key=?', session.id, key)];
  try { const saved = await env.ADMIN_DB.batch(statements); return JSON.parse(saved.at(-1).results[0].response_json); }
  catch (error) {
    if (error instanceof GatewayError) throw error;
    await read(env, session, [], true);
    if (/constraint|immutable|invalid|CHECK|UNIQUE|FOREIGN KEY|guard_failed/i.test(String(error))) fail(409, 'state_conflict', 'The gateway identity, version or review state conflicts with this action. Refresh and check the record.');
    fail(503, 'service_unavailable', 'The outcome is unknown. Check the request receipt before continuing.');
  }
}
async function deviceMutation(env, session, request, parts) {
  const { data } = await body(request); require(object(data));
  return commitMutation(env, session, request, parts, data, async (p, requestId, at) => {
    if (parts.length === 1) {
      require(keys(data, ['label', 'app_id', 'installation_id', 'public_key_spki_base64', 'key_sha256', 'signing_certificate_sha256', 'reason']));
      const appId = str(data.app_id, 3, 160); require(/^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$/.test(appId));
      const certificate = hash(data.signing_certificate_sha256), fingerprint = hash(data.key_sha256);
      allowedIdentity(env, appId, certificate); await publicKey(data.public_key_spki_base64, fingerprint);
      const deviceId = uuid(); p.insert('collect_gateway_devices', { id: deviceId, label: str(data.label, 2, 120), app_id: appId, installation_id: id(data.installation_id), public_key_spki_base64: data.public_key_spki_base64, key_sha256: fingerprint, signing_certificate_sha256: certificate, created_by_admin_id: session.id, created_at: at });
      return { id: deviceId, version: 1, type: 'gateway_devices', action: 'gateway.enroll' };
    }
    require(parts.length === 3 && ['activate', 'revoke'].includes(parts[2]));
    require(keys(data, ['expected_version', 'expected_key_sha256', 'expected_signing_certificate_sha256', 'reason']));
    const deviceId = id(parts[1]), version = integer(data.expected_version, 1, Number.MAX_SAFE_INTEGER - 1), fingerprint = hash(data.expected_key_sha256), certificate = hash(data.expected_signing_certificate_sha256);
    const device = await q(env, 'SELECT * FROM collect_gateway_devices WHERE id=?', deviceId).first(); if (!device) fail(404, 'not_found', 'This device does not exist.');
    if (parts[2] === 'activate') allowedIdentity(env, device.app_id, certificate);
    p.assert(`EXISTS(SELECT 1 FROM collect_gateway_devices WHERE id=? AND version=? AND key_sha256=? AND signing_certificate_sha256=? AND state ${parts[2] === 'activate' ? "='pending'" : "IN ('pending','active')"})`, deviceId, version, fingerprint, certificate);
    p.update('collect_gateway_devices', parts[2] === 'activate' ? { state: 'active', version: version + 1, activated_by_admin_id: session.id, activated_at: at } : { state: 'revoked', version: version + 1, revoked_by_admin_id: session.id, revoked_at: at }, 'id=?', deviceId);
    return { id: deviceId, version: version + 1, type: 'gateway_devices', action: `gateway.${parts[2]}` };
  });
}
async function limited(env, identity) {
  const time = now(), bucket = Math.floor(time / 60);
  const row = await q(env, 'INSERT INTO admin_rate_limits(key_hash,bucket,count,expires_at) VALUES(?,?,1,?) ON CONFLICT(key_hash,bucket) DO UPDATE SET count=count+1 RETURNING count', await digest(`gateway:${identity}`), bucket, time + 120).first();
  if (row.count > 120) fail(429, 'gateway_rate_limited', 'Too many gateway observations. Wait before sending another request.');
}
// Freshness, action-specific payload and replay semantics belong to the caller.
// This proves possession of an active enrolled key, never carrier provenance.
export async function verifyGatewaySignedEnvelope(request,env,{validateEnvelope,maximumBytes=32768}={}) {
  if(request.method!=='POST')fail(405,'method_not_allowed','Gateway observations require POST.');
  const url=new URL(request.url),origin=request.headers.get('Origin');
  if(!env.ADMIN_ORIGIN||url.origin!==env.ADMIN_ORIGIN||(origin&&origin!==env.ADMIN_ORIGIN)
    ||(url.protocol!=='https:'&&!(env.ENVIRONMENT==='local'&&['localhost','127.0.0.1','[::1]'].includes(url.hostname))))
    fail(403,'origin_rejected','Use the configured HTTPS gateway endpoint.');
  integer(maximumBytes,1,131072);await limited(env,`ip:${request.headers.get('CF-Connecting-IP')||'unknown'}`);
  const {raw,data}=await body(request,maximumBytes);
  require(object(data)&&data.contract_version===1&&typeof data.action==='string');
  id(data.device_id);id(data.request_id);const issuedAtMs=utc(data.issued_at);
  if(typeof validateEnvelope==='function')validateEnvelope(data);
  else require(keys(data,['contract_version','action','device_id','request_id','issued_at','payload']));
  const fingerprint=hash(request.headers.get('X-Collect-Gateway-Key-Id')),signature=request.headers.get('X-Collect-Gateway-Signature');
  const decoded=gatewayDerToP1363(base64(signature,100));
  const device=await q(env,'SELECT * FROM collect_gateway_devices WHERE id=? AND key_sha256=?',data.device_id,fingerprint).first();
  if(!device)fail(401,'gateway_key_refused','Gateway identity could not be verified.');
  if(device.state!=='active')fail(403,'gateway_device_inactive','Gateway device is not active.');
  if(Object.hasOwn(data,'installation_id')&&id(data.installation_id)!==device.installation_id)fail(401,'gateway_key_refused','Gateway installation could not be verified.');
  allowedIdentity(env,device.app_id,device.signing_certificate_sha256);
  const key=await publicKey(device.public_key_spki_base64,device.key_sha256);let verified=false;
  try{verified=await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},key,decoded,raw);}catch{}
  if(!verified)fail(401,'gateway_signature_refused','Gateway signature could not be verified.');
  await limited(env,`device:${device.id}`);
  return {data,raw,requestHash:await bytesHash(raw),signature,device,issuedAtMs,receivedAt:now(),
    authGuardSql:"EXISTS(SELECT 1 FROM collect_gateway_devices WHERE id=? AND key_sha256=? AND installation_id=? AND version=? AND state='active')",
    authGuardArgs:[device.id,device.key_sha256,device.installation_id,device.version]};
}
async function heartbeat(request, env) {
  const {data,device,requestHash,issuedAtMs:issued,receivedAt:at,authGuardSql,authGuardArgs}=await verifyGatewaySignedEnvelope(request,env);
  require(keys(data, ['contract_version', 'action', 'device_id', 'request_id', 'issued_at', 'payload']) && data.contract_version === 1 && data.action === 'heartbeat');
  const observation = data.payload;
  require(keys(observation, ['sms_permission', 'network', 'telephony', 'sim_selected', 'sim_revision_sha256', 'local_pause', 'reported_at']));
  require(['sms_permission', 'sim_selected', 'local_pause'].every(key => typeof observation[key] === 'boolean'));
  require(['validated', 'unvalidated', 'offline', 'unknown'].includes(observation.network) && ['ready', 'unavailable', 'unknown'].includes(observation.telephony));
  require(observation.sim_selected ? isHash(observation.sim_revision_sha256) : observation.sim_revision_sha256 === null);
  const reported = utc(observation.reported_at); require(Math.abs(reported - issued) <= 120000);
  const observationId = uuid(), guardId = uuid();
  const previous = await q(env, 'SELECT * FROM collect_gateway_heartbeats WHERE device_id=? AND request_id=?', device.id, data.request_id).first();
  if (previous && previous.request_sha256 !== requestHash) fail(409, 'gateway_request_conflict', 'The request identifier already belongs to different exact bytes.');
  if (!previous && (Math.abs(Date.now() - issued) > 120000 || reported > Date.now() + 30000)) fail(400, 'gateway_request_expired', 'The observation timestamp is outside the accepted window.');
  try {
    const results = await env.ADMIN_DB.batch([
      q(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN ${authGuardSql} THEN 1 ELSE 0 END`, guardId, ...authGuardArgs),
      q(env, 'INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM collect_gateway_heartbeats WHERE device_id=? AND request_id=? AND request_sha256=?) OR (abs(unixepoch()*1000-?)<=120000 AND ?<=unixepoch()*1000+30000) THEN 1 ELSE 0 END', `${guardId}:time`, device.id, data.request_id, requestHash, issued, reported),
      q(env, 'INSERT INTO collect_gateway_heartbeats(id,device_id,request_id,request_sha256,issued_at,reported_at,observations_json,ingested_at) VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(device_id,request_id) DO NOTHING', observationId, device.id, data.request_id, requestHash, data.issued_at, observation.reported_at, JSON.stringify(observation), at),
      q(env, 'INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM collect_gateway_heartbeats WHERE device_id=? AND request_id=? AND request_sha256=?) THEN 1 ELSE 0 END', `${guardId}:replay`, device.id, data.request_id, requestHash),
      q(env, 'DELETE FROM collect_mutation_guards WHERE id IN (?,?,?)', guardId, `${guardId}:replay`, `${guardId}:time`),
      q(env, 'SELECT * FROM collect_gateway_heartbeats WHERE device_id=? AND request_id=?', device.id, data.request_id),
    ]);
    const saved = results.at(-1).results[0];
    return { contract_version: 1, action: 'heartbeat', device_id: device.id, request_id: data.request_id, result: { observation_id: saved.id, ingested_at: iso(saved.ingested_at), replay: saved.id !== observationId, carrier_proof: false } };
  } catch (error) {
    if (error instanceof GatewayError) throw error;
    const current = await q(env, 'SELECT state,version FROM collect_gateway_devices WHERE id=?', device.id).first();
    if (current?.state !== 'active' || current.version !== device.version) fail(403, 'gateway_device_inactive', 'Gateway device is no longer active.');
    if (/constraint|guard_failed/i.test(String(error))) fail(409, 'gateway_request_conflict', 'The request identifier conflicts with existing evidence.');
    fail(503, 'gateway_outcome_unknown', 'The gateway observation outcome is unknown. Preserve the original request.');
  }
}
const receiptSelect = `SELECT s.id,s.user_id,s.body_hash AS body_sha256,s.status,s.version,s.received_at,s.created_at,p.public_id,p.display_name,r.transaction_id,r.reviewed_at
  FROM member_receipt_submissions s LEFT JOIN collect_profiles p ON p.user_id=s.user_id LEFT JOIN collect_member_receipt_reviews r ON r.submission_id=s.id`;
const receiptDto = row => ({ ...row, received_at: iso(row.received_at), created_at: iso(row.created_at), reviewed_at: iso(row.reviewed_at) });
async function receiptRead(env, session, url, submissionId) {
  if (submissionId) {
    require(!url.search); id(submissionId);
    const [receipt, reviews] = await read(env, session, [q(env, `${receiptSelect} WHERE s.id=?`, submissionId), q(env, 'SELECT id,outcome,transaction_id,evidence_id,actor_admin_id,reason,reviewed_at FROM collect_member_receipt_reviews WHERE submission_id=?', submissionId)]);
    if (!receipt.results[0]) fail(404, 'not_found', 'This receipt does not exist.');
    return { resource_type: 'member_receipts', resource: receiptDto(receipt.results[0]), current_actor_id: session.id, can_manage: canManage(session, 'payments.manage'), related: { reviews: reviews.results.map(row => ({ ...row, reviewed_at: iso(row.reviewed_at) })) }, related_truncated: false };
  }
  const filter = page(url, ['needs_review', 'reviewed', 'rejected'], 'status'), where = filter.status ? ' WHERE s.status=?' : '', args = filter.status ? [filter.status] : [];
  const [count, rows] = await read(env, session, [q(env, `SELECT count(*) AS total FROM member_receipt_submissions s${where}`, ...args), q(env, `${receiptSelect}${where} ORDER BY s.created_at DESC,s.id DESC LIMIT ? OFFSET ?`, ...args, filter.limit, filter.offset)]);
  return { rows: rows.results.map(receiptDto), total: count.results[0].total };
}
async function receiptTransactions(env, session, url, submissionId) {
  id(submissionId);
  for (const key of url.searchParams.keys()) require(['search', 'limit'].includes(key) && url.searchParams.getAll(key).length === 1);
  const search = str(url.searchParams.get('search') || '', 0, 200), rawLimit = url.searchParams.get('limit') ?? '50';
  require(/^[1-9][0-9]*$/.test(rawLimit)); const limit = integer(Number(rawLimit), 1, 100);
  const [receipt, result] = await read(env, session, [q(env, 'SELECT id FROM member_receipt_submissions WHERE id=?', submissionId), q(env,
    `SELECT t.id,t.provider_reference||' · RWF '||t.amount_rwf||' · '||g.title AS label,t.version,t.amount_rwf,t.group_id,g.title AS group_name,t.provider_reference
     FROM collect_transactions t JOIN collect_groups g ON g.id=t.group_id WHERE t.verification_status='pending' AND g.status='active'
     AND EXISTS(SELECT 1 FROM member_receipt_submissions s JOIN collect_memberships m ON m.user_id=s.user_id JOIN collect_users u ON u.id=m.user_id
       WHERE s.id=? AND m.group_id=t.group_id AND m.status='active' AND u.status='active')
     AND (instr(lower(t.provider_reference),lower(?))>0 OR instr(lower(g.title),lower(?))>0) ORDER BY t.created_at DESC,t.id LIMIT ?`, submissionId, search, search, limit)]);
  if (!receipt.results[0]) fail(404, 'not_found', 'This receipt does not exist.'); return { rows: result.results };
}
async function receiptSource(env, submissionId) {
  const stored = await q(env, 'SELECT * FROM member_receipt_submissions WHERE id=?', submissionId).first(); if (!stored) fail(404, 'not_found', 'This receipt does not exist.');
  if (!env.MEMBER_MEDIA?.get) fail(503, 'receipt_source_unavailable', 'Private receipt storage is unavailable.');
  const source = await env.MEMBER_MEDIA.get(stored.payload_object_key);
  if (!source || !Number.isSafeInteger(source.size) || source.size < 1 || source.size > 131072) fail(503, 'receipt_source_unavailable', 'The original receipt could not be verified.');
  let content;
  try { const bytes = await streamBytes(source.body, 131072); content = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); } catch { fail(503, 'receipt_source_unavailable', 'The original receipt could not be verified.'); }
  if (!keys(content, ['raw_sender', 'raw_body']) || typeof content.raw_body !== 'string' || content.raw_body.length < 1 || content.raw_body.length > 16000 || content.raw_sender !== stored.raw_sender || await digest(content.raw_body) !== stored.body_hash) fail(503, 'receipt_source_mismatch', 'The original receipt does not match its stored evidence digest.');
  return { stored, content };
}
async function receiptContent(env, session, request, submissionId) {
  const reason = str(request.headers.get('X-Collect-Review-Reason'), 8, 1000), guardId = uuid();
  await read(env, session, [], true); const { stored, content } = await receiptSource(env, id(submissionId));
  try { await env.ADMIN_DB.batch([
    q(env, `INSERT INTO collect_mutation_guards(id,passed) SELECT ?,CASE WHEN ${authSql(true)} THEN 1 ELSE 0 END`, guardId, ...authValues(session)),
    q(env, 'INSERT INTO collect_operations_audit(id,actor_admin_id,action,subject_type,subject_id,evidence_json,occurred_at) VALUES(?,?,?,?,?,?,?)', uuid(), session.id, 'receipt.reveal', 'member_receipts', submissionId, JSON.stringify({ reason, body_sha256: stored.body_hash }), now()),
    q(env, 'DELETE FROM collect_mutation_guards WHERE id=?', guardId),
  ]); } catch { await read(env, session, [], true); fail(503, 'receipt_audit_unavailable', 'Receipt access could not be recorded. Try again later.'); }
  return { submission_id: submissionId, ...content, body_sha256: stored.body_hash, evidence_level: 'member_submitted' };
}
async function receiptReview(env, session, request, parts) {
  const { data } = await body(request); require(keys(data, ['expected_version', 'outcome', 'transaction_id', 'reason']));
  const submissionId = id(parts[1]), version = integer(data.expected_version, 1, Number.MAX_SAFE_INTEGER - 1);
  require(['reviewed', 'rejected'].includes(data.outcome) && (data.transaction_id === null || isId(data.transaction_id)) && (data.outcome !== 'rejected' || data.transaction_id === null));
  return commitMutation(env, session, request, parts, data, async (p, requestId, at) => {
    const { stored } = await receiptSource(env, submissionId);
    p.assert("EXISTS(SELECT 1 FROM member_receipt_submissions WHERE id=? AND version=? AND status='needs_review')", submissionId, version);
    let evidenceId = null;
    if (data.transaction_id) {
      evidenceId = uuid();
      p.assert("EXISTS(SELECT 1 FROM collect_transactions t JOIN collect_groups g ON g.id=t.group_id JOIN collect_memberships m ON m.group_id=t.group_id JOIN collect_users u ON u.id=m.user_id WHERE t.id=? AND t.verification_status='pending' AND g.status='active' AND m.user_id=? AND m.status='active' AND u.status='active')", data.transaction_id, stored.user_id);
      p.insert('collect_transaction_evidence', { id: evidenceId, transaction_id: data.transaction_id, kind: 'payer_receipt', reference: `Member receipt ${submissionId}`, artifact_sha256: stored.body_hash, recorded_by_admin_id: session.id, operation_request_id: requestId, recorded_at: at });
      const transaction = await q(env, 'SELECT version FROM collect_transactions WHERE id=?', data.transaction_id).first();
      if (!transaction) fail(404, 'not_found', 'This transaction does not exist.');
      p.assert('EXISTS(SELECT 1 FROM collect_transactions WHERE id=? AND version=?)', data.transaction_id, transaction.version);
      p.update('collect_transactions', { version: integer(transaction.version, 1, Number.MAX_SAFE_INTEGER - 1) + 1 }, 'id=?', data.transaction_id);
    }
    p.insert('collect_member_receipt_reviews', { id: uuid(), submission_id: submissionId, outcome: data.outcome, transaction_id: data.transaction_id, evidence_id: evidenceId, actor_admin_id: session.id, operation_request_id: requestId, reason: data.reason.trim(), reviewed_at: at });
    p.update('member_receipt_submissions', { status: data.outcome, version: version + 1 }, 'id=?', submissionId);
    p.statements.push(...reviewedMemberSmsLinkStatements(env,{submission_id:submissionId,actor_admin_id:session.id,operation_request_id:requestId,created_at:at}));
    return { id: submissionId, version: version + 1, type: 'member_receipts', action: 'receipt.review' };
  });
}
export async function handleGateway(request, env, session = null) {
  const url = new URL(request.url);
  if (!env.ADMIN_DB) fail(503, 'service_unavailable', 'Gateway storage is unavailable.');
  if (url.pathname === '/api/gateway' || url.pathname === '/api/gateway/heartbeat') {
    if (!env.ADMIN_ORIGIN || url.origin !== env.ADMIN_ORIGIN || (url.protocol !== 'https:' && !(env.ENVIRONMENT === 'local' && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname))))
      fail(403, 'origin_rejected', 'Use the configured HTTPS gateway endpoint.');
    require(!url.search); return heartbeat(request, env);
  }
  const prefix = '/api/admin/gateway/'; if (!url.pathname.startsWith(prefix)) fail(404, 'not_found', 'This gateway endpoint does not exist.');
  const parts = url.pathname.slice(prefix.length).split('/');
  if (!['devices', 'receipts'].includes(parts[0])) fail(404, 'not_found', 'This gateway endpoint does not exist.');
  const sensitiveRead = parts[0] === 'receipts' && parts[2] === 'content'; const writes = request.method !== 'GET' || sensitiveRead;
  sessionRequired(session, parts[0] === 'devices' ? writes ? GATEWAY_MANAGE_PERMISSION : GATEWAY_READ_PERMISSION : writes ? 'payments.manage' : 'payments.read', writes);
  if (parts[0] === 'devices' && request.method === 'GET' && parts.length <= 2) return deviceRead(env, session, url, parts[1]);
  if (parts[0] === 'receipts' && request.method === 'GET' && parts.length <= 2) return receiptRead(env, session, url, parts[1]);
  if (parts[0] === 'receipts' && request.method === 'GET' && parts.length === 3 && parts[2] === 'transactions') return receiptTransactions(env, session, url, parts[1]);
  require(!url.search);
  if (sensitiveRead && request.method === 'GET' && parts.length === 3) return receiptContent(env, session, request, parts[1]);
  if (request.method !== 'POST') fail(405, 'method_not_allowed', 'This gateway method is unavailable.');
  if (parts[0] === 'devices' && (parts.length === 1 || (parts.length === 3 && ['activate', 'revoke'].includes(parts[2])))) return deviceMutation(env, session, request, parts);
  if (parts[0] === 'receipts' && parts.length === 3 && parts[2] === 'review') return receiptReview(env, session, request, parts);
  fail(404, 'not_found', 'This gateway action does not exist.');
}
