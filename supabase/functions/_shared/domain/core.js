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
  let bytes = new Uint8Array(0), size = 0; const signal = request.signal; const aborted = Symbol('request_aborted');
  let onAbort, wakeRead;
  const cancelReader = () => { try { void Promise.resolve(reader.cancel()).catch(() => {}); } catch {} };
  if (signal) {
    onAbort = () => {
      wakeRead?.();
      // Cancellation is best-effort; a source may reject or never settle.
      cancelReader();
    };
    signal.addEventListener('abort', onAbort, {once: true});
    if (signal.aborted) onAbort();
  }
  try {
    while (true) {
      if (signal?.aborted) throw new ApiError(400, 'request_aborted', 'The request was interrupted.');
      const pending = reader.read();
      const next = signal ? await new Promise((resolve, reject) => {
        let settled = false;
        const finish = (callback, value) => { if (!settled) { settled = true; callback(value); } };
        wakeRead = () => finish(resolve, aborted);
        // Observe a late rejection even if the abort wins this read.
        Promise.resolve(pending).then(value => finish(resolve, value), error => finish(reject, error));
        if (signal.aborted) wakeRead();
      }) : await pending;
      wakeRead = undefined;
      if (next === aborted || signal?.aborted) throw new ApiError(400, 'request_aborted', 'The request was interrupted.');
      const {done, value} = next; if (done) break;
      if (!ArrayBuffer.isView(value) || Object.prototype.toString.call(value) !== '[object Uint8Array]') {
        cancelReader(); throw new ApiError(400, 'invalid_request', 'A JSON object is required.');
      }
      const required = size + value.byteLength;
      if (required > maxBytes) {
        // Cancellation is best-effort: a stream's underlying cancel callback
        // can reject or remain pending. Do not let it hide or delay the 413.
        cancelReader();
        throw new ApiError(413, 'request_too_large', 'The request is too large.');
      }
      if (!value.byteLength) continue;
      if (required > bytes.byteLength) {
        const capacity = Math.min(maxBytes, Math.max(required, bytes.byteLength ? bytes.byteLength * 2 : 256));
        const grown = new Uint8Array(capacity); grown.set(bytes.subarray(0, size)); bytes = grown;
      }
      bytes.set(value, size); size = required;
    }
  } finally { wakeRead = undefined; if (onAbort) signal.removeEventListener('abort', onAbort); reader.releaseLock(); }
  let data;
  try { data = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes.subarray(0, size))); }
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
