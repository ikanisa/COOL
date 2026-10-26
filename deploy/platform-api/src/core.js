export class ApiError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}
export function json(data, status = 200, headers = {}) {
  return Response.json(data, {status, headers: {
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer', ...headers,
  }});
}
export async function readJson(request, maxBytes = 65536) {
  if (!(request.headers.get('content-type') ?? '').split(';')[0].trim().match(/^application\/json$/i))
    throw new ApiError(415, 'unsupported_media_type', 'Use application/json.');
  const length = request.headers.get('content-length');
  if (length && (!/^\d+$/.test(length) || Number(length) > maxBytes))
    throw new ApiError(413, 'request_too_large', 'The request is too large.');
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError(400, 'invalid_request', 'A JSON object is required.');
  const chunks = []; let size = 0;
  try {
    while (true) {
      const {done, value} = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > maxBytes) { await reader.cancel(); throw new ApiError(413, 'request_too_large', 'The request is too large.'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  let data;
  try { data = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes)); }
  catch { throw new ApiError(400, 'invalid_json', 'The JSON request is invalid.'); }
  if (!data || Array.isArray(data) || typeof data !== 'object') throw new ApiError(400, 'invalid_request', 'A JSON object is required.');
  return data;
}
export function text(value, field, maxLength = 200, {optional = false} = {}) {
  if (optional && (value === null || value === undefined)) return null;
  if (typeof value !== 'string' || value.trim().length === 0 || value.length > maxLength || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value))
    throw new ApiError(400, 'invalid_parameter', `Invalid ${field}.`);
  return value.trim();
}
export function uuid(value, field = 'identifier') {
  const result = text(value, field, 36);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result))
    throw new ApiError(400, 'invalid_parameter', `Invalid ${field}.`);
  return result.toLowerCase();
}
export function integer(value, field, minimum = 0, maximum = 9007199254740991) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum)
    throw new ApiError(400, 'invalid_parameter', `Invalid ${field}.`);
  return value;
}
export function now() { return new Date().toISOString(); }
export function id() { return crypto.randomUUID(); }
export function requirePermission(actor, permission) {
  if (!actor?.permissions?.has(permission)) throw new ApiError(403, '42501', 'You do not have access to this action.');
}
export function requireFreshAuth(actor, maximumAge = 300) {
  if (!actor || Math.floor(Date.now()/1000) - actor.authAt > maximumAge)
    throw new ApiError(403, 'fresh_auth_required', 'Verify your sign-in before continuing.');
}
export async function digest(value) {
  const data = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', data))].map(v => v.toString(16).padStart(2, '0')).join('');
}
export function stableJson(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(stableJson).join(',') + ']';
  return '{' + Object.keys(value).sort().map(k => JSON.stringify(k)+':'+stableJson(value[k])).join(',') + '}';
}
export function auditStatement(env, actor, action, entityType, entityId, details, requestId = null) {
  return env.DB.prepare(`INSERT INTO audit_log (actor_user_id,actor_session_id,action,entity_type,entity_id,request_id,details_json,created_at) VALUES (?,?,?,?,?,?,?,?)`)
    .bind(actor?.userId ?? null, actor?.sessionId ?? null, action, entityType, entityId, requestId, JSON.stringify(details ?? {}), now());
}
export async function rows(env, sql, ...values) {
  const result = await env.DB.prepare(sql).bind(...values).all();
  return result.results;
}
export async function first(env, sql, ...values) { return env.DB.prepare(sql).bind(...values).first(); }
export function pagination(body, maximum = 100) {
  return {limit: integer(body.p_limit ?? body.limit ?? 50, 'limit', 1, maximum), offset: integer(body.p_offset ?? body.offset ?? 0, 'offset', 0, 10000)};
}
export function decode(row, field = 'data_json') {
  if (!row) return null;
  const { [field]: raw, ...rest } = row;
  return {...(raw ? JSON.parse(raw) : {}), ...rest};
}
