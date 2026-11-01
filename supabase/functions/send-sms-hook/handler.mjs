/** Supabase Send SMS Hook -> the existing OpenSMS v0.3 transport API.
 * No Supabase service-role key or alternative OTP authority is involved.
 * Runtime dependencies: standard Fetch + Web Crypto APIs (Deno / Node 22+).
 */
const encoder = new TextEncoder();
const BODY_LIMIT = 65536;
const RESPONSE_LIMIT = 65536;
const ACCEPTED_STATES = new Set([
  'accepted', 'assigned', 'phone_accepted', 'queued', 'handoff_started',
  'sent', 'delivered', 'delivery_unconfirmed',
]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const UTC = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/;

class HookError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

function base64Bytes(value) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(value) || value.length % 4) throw new Error('base64');
  const decoded = atob(value);
  if (btoa(decoded) !== value) throw new Error('base64');
  return Uint8Array.from(decoded, c => c.charCodeAt(0));
}

function localHttpHost(host) {
  if (['localhost', '127.0.0.1', '[::1]', 'host.docker.internal'].includes(host)) return true;
  const fields = host.split('.').map(Number);
  if (fields.length !== 4 || fields.some(x => !Number.isInteger(x) || x < 0 || x > 255)) return false;
  return fields[0] === 10 || fields[0] === 192 && fields[1] === 168 || fields[0] === 172 && fields[1] >= 16 && fields[1] <= 31;
}

function configuration(env) {
  if (!['local', 'staging', 'qualification', 'production'].includes(env.APP_ENVIRONMENT)) throw new Error('environment');
  const endpoint = new URL(env.OPENSMS_BASE_URL);
  if (endpoint.username || endpoint.password || endpoint.search || endpoint.hash || !['', '/', '/functions/v1/collect-sms'].includes(endpoint.pathname)) throw new Error('origin');
  // The self-hosted gateway preserves /v1 behind its exact Functions prefix.
  // A leading-slash URL resolution would silently drop that required prefix.
  const prefix = endpoint.pathname === '/functions/v1/collect-sms' ? endpoint.pathname : '';
  if (endpoint.hostname.endsWith('.invalid') || endpoint.hostname === 'example.com') throw new Error('placeholder');
  if (endpoint.protocol !== 'https:' && !(endpoint.protocol === 'http:' && env.APP_ENVIRONMENT === 'local' && env.OPENSMS_ALLOW_LOCAL_HTTP === 'true' && localHttpHost(endpoint.hostname))) throw new Error('scheme');
  const appId = env.OPENSMS_APPLICATION_ID;
  const projectId = env.AUTH_PROJECT_ID;
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(appId || '') || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(projectId || '')) throw new Error('namespace');
  const token = env.OPENSMS_APPLICATION_TOKEN;
  if (!/^app_[A-Za-z0-9_-]{32,252}$/.test(token || '')) throw new Error('application token');
  const label = env.OPENSMS_SENDER_LABEL || 'Your app';
  if (!/^[A-Za-z0-9][A-Za-z0-9 ._'-]{0,39}$/.test(label)) throw new Error('label');
  const ttlText = env.OPENSMS_DISPATCH_TTL_SECONDS || '120';
  if (!/^\d{2,3}$/.test(ttlText)) throw new Error('ttl');
  const ttl = Number(ttlText);
  if (ttl < 30 || ttl > 300) throw new Error('ttl');
  const secretStrings = (env.AUTH_SEND_SMS_SECRET || '').split('|');
  if (!secretStrings.length || secretStrings.length > 3) throw new Error('secrets');
  const secrets = secretStrings.map(secret => {
    if (!secret.startsWith('v1,whsec_')) throw new Error('secret format');
    const bytes = base64Bytes(secret.slice(9));
    if (bytes.length < 24 || bytes.length > 64) throw new Error('secret length');
    return bytes;
  });
  return { endpoint, prefix, appId, projectId, token, label, ttl, secrets };
}

function response(status, message) {
  return new Response(status === 200 ? '{}' : JSON.stringify({ error: { http_code: status, message } }), {
    status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
}

async function boundedBytes(input, limit, signal) {
  const declared = input.headers.get('content-length');
  if (declared && (!/^\d+$/.test(declared) || Number(declared) > limit)) throw new HookError(413, 'Payload too large.');
  const reader = input.body?.getReader();
  if (!reader) return new Uint8Array();
  let aborted;
  const abort = new Promise((_, reject) => {
    aborted = () => { void reader.cancel().catch(() => {}); reject(new HookError(503, 'SMS service unavailable.')); };
    if (signal.aborted) aborted(); else signal.addEventListener('abort', aborted, { once: true });
  });
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { value, done } = await Promise.race([reader.read(), abort]);
      if (done) break;
      size += value.byteLength;
      if (size > limit) throw new HookError(413, 'Payload too large.');
      chunks.push(value);
    }
  } catch (error) { void reader.cancel().catch(() => {}); throw error; }
  finally { signal.removeEventListener('abort', aborted); reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

function parseMetadata(headers, now) {
  const id = headers.get('webhook-id') || '';
  const timestampText = headers.get('webhook-timestamp') || '';
  const signatureText = headers.get('webhook-signature') || '';
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(id) || !/^[1-9]\d{0,12}$/.test(timestampText) || signatureText.length > 1024) throw new HookError(401, 'Invalid hook signature.');
  const timestamp = Number(timestampText);
  if (!Number.isSafeInteger(timestamp) || Math.abs(now / 1000 - timestamp) > 300) throw new HookError(401, 'Invalid hook signature.');
  const pieces = signatureText.split(/\s+/);
  if (pieces.length > 8) throw new HookError(401, 'Invalid hook signature.');
  const signatures = [];
  for (const piece of pieces) {
    if (!piece.startsWith('v1,')) continue;
    try { const bytes = base64Bytes(piece.slice(3)); if (bytes.length === 32) signatures.push(bytes); } catch { /* Ignore an unsupported/malformed candidate, never trust it. */ }
  }
  if (!signatures.length) throw new HookError(401, 'Invalid hook signature.');
  return { id, timestamp, timestampText, signatures };
}

async function verify(raw, meta, secrets, cryptography) {
  const prefix = encoder.encode(`${meta.id}.${meta.timestampText}.`);
  const signed = new Uint8Array(prefix.length + raw.length);
  signed.set(prefix); signed.set(raw, prefix.length);
  for (const secret of secrets) {
    const key = await cryptography.subtle.importKey('raw', secret, { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']);
    for (const signature of meta.signatures) {
      // Web Crypto performs HMAC verification; no hand-written secret comparison.
      if (await cryptography.subtle.verify('HMAC', key, signature, signed)) return;
    }
  }
  throw new HookError(401, 'Invalid hook signature.');
}

function eventData(raw) {
  let event;
  try { event = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(raw)); } catch { throw new HookError(400, 'Invalid hook payload.'); }
  if (!event || Array.isArray(event) || typeof event !== 'object' || !UUID.test(event.user?.id || '') || typeof event.sms?.phone !== 'string' || !/^\+?[1-9]\d{7,14}$/.test(event.sms.phone) || !/^\d{6,10}$/.test(event.sms?.otp || '') || typeof event.sms?.otp !== 'string') throw new HookError(400, 'Invalid hook payload.');
  // Auth v2.197.0 passes the actual send destination in sms.phone. During
  // phone_change/anonymous upgrades, user.phone still contains the old phone
  // or is empty. Never fall back to that field or infer from phone_change.
  // Older hooks without an explicit sms.phone fail closed instead of risking
  // sending an account-linking code to the wrong number.
  return { userId: event.user.id, phone: event.sms.phone.startsWith('+') ? event.sms.phone : `+${event.sms.phone}`, otp: event.sms.otp };
}

async function digest(text, cryptography) {
  return [...new Uint8Array(await cryptography.subtle.digest('SHA-256', encoder.encode(text)))].map(x => x.toString(16).padStart(2, '0')).join('');
}

function validUtc(value) { return typeof value === 'string' && UTC.test(value) && Number.isFinite(Date.parse(value)); }

async function inspectExisting(record, expected, config, now, cryptography) {
  const message = record?.message;
  if (!message || message.message_id !== expected.id || message.application_id !== config.appId || message.kind !== 'otp' || message.to !== expected.phone || message.priority !== 120 || message.campaign_id !== null || !validUtc(message.not_after) || !validUtc(message.available_at) || !/^[a-f0-9]{64}$/.test(message.payload_digest || '')) throw new HookError(503, 'SMS service response invalid.');
  // OpenSMS hides OTP text in reads. Its documented source payload digest lets
  // us verify that this accepted job contains exactly the same OTP and target.
  const fields = [expected.id, config.appId, 'otp', expected.phone, expected.text, '120', message.not_after, message.available_at, ''];
  const fingerprint = await digest('collect-sms-payload-v1\n' + fields.map(value => `${encoder.encode(value).length}:${value}`).join(''), cryptography);
  if (fingerprint !== message.payload_digest) throw new HookError(409, 'Hook event conflicts with an existing SMS.');
  if (message.cancel_requested || !ACCEPTED_STATES.has(message.state) || Date.parse(message.not_after) <= now) throw new HookError(503, 'SMS service has not accepted an active message.');
}

async function readJson(reply, signal) {
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(await boundedBytes(reply, RESPONSE_LIMIT, signal))); }
  catch { throw new HookError(503, 'SMS service response invalid.'); }
}

async function deliver(config, event, meta, transport, signal, now, cryptography) {
  const eventDigest = await digest(`${config.projectId}\n${meta.id}`, cryptography);
  const expected = {
    id: `${config.appId}:sbauth:${eventDigest}`,
    phone: event.phone,
    text: `${config.label}: Your verification code is ${event.otp}. Do not share this code.`,
  };
  const baseHeaders = { authorization: `Bearer ${config.token}`, accept: 'application/json' };
  const detailUrl = new URL(`${config.prefix}/v1/messages/${encodeURIComponent(expected.id)}`, config.endpoint);
  const checkActive = () => { if (signal.aborted) throw new HookError(503, 'SMS service unavailable.'); };
  const findExisting = async () => {
    checkActive();
    const reply = await transport(detailUrl, { method: 'GET', headers: baseHeaders, redirect: 'error', cache: 'no-store', signal });
    checkActive();
    if (reply.status === 404) { await reply.body?.cancel(); return false; }
    if (reply.status !== 200) { await reply.body?.cancel(); throw new HookError(503, 'SMS service unavailable.'); }
    await inspectExisting(await readJson(reply, signal), expected, config, now(), cryptography);
    return true;
  };
  if (await findExisting()) return;
  const deadline = meta.timestamp * 1000 + config.ttl * 1000;
  if (deadline <= now()) throw new HookError(400, 'SMS dispatch window expired. Request a new code.');
  const body = {
    message_id: expected.id, kind: 'otp', to: event.phone, text: expected.text,
    not_after: new Date(deadline).toISOString(), priority: 120,
    metadata: { source: 'supabase_auth', project_id: config.projectId },
  };
  checkActive();
  const reply = await transport(new URL(config.prefix + '/v1/messages', config.endpoint), {
    method: 'POST', headers: { ...baseHeaders, 'content-type': 'application/json', 'idempotency-key': `sbauth-${eventDigest}` },
    body: JSON.stringify(body), redirect: 'error', cache: 'no-store', signal,
  });
  checkActive();
  if (reply.status === 409) {
    await reply.body?.cancel();
    // Concurrent attempts can choose different not_after values. Read back the
    // already accepted immutable job, verify its digest, and never create anew.
    if (await findExisting()) return;
    throw new HookError(503, 'SMS service unavailable.');
  }
  if (reply.status !== 202) { await reply.body?.cancel(); throw new HookError(503, 'SMS service unavailable.'); }
  const accepted = await readJson(reply, signal);
  if (accepted?.message_id !== expected.id || !ACCEPTED_STATES.has(accepted?.state)) throw new HookError(503, 'SMS service response invalid.');
}

/** All calls in one invocation share a 4-second budget, below Auth's 5 seconds. */
export function createHandler(env, { transport = fetch, cryptography = globalThis.crypto, now = Date.now, timeoutMs = 4000 } = {}) {
  let config;
  try { config = configuration(env); } catch { config = null; }
  if (!Number.isFinite(timeoutMs) || timeoutMs < 1 || timeoutMs > 4000) throw new Error('timeoutMs must be within 1..4000');
  return async function handle(request) {
    if (request.method !== 'POST') return response(405, 'Method not allowed.');
    if (request.headers.has('origin')) return response(403, 'Server-to-server requests only.');
    if (!/^application\/json(?:\s*;|$)/i.test(request.headers.get('content-type') || '')) return response(415, 'JSON required.');
    if (!config) return response(503, 'SMS hook is not configured.');
    const controller = new AbortController();
    const abort = () => controller.abort();
    request.signal.addEventListener('abort', abort, { once: true });
    if (request.signal.aborted) controller.abort();
    const timer = setTimeout(abort, timeoutMs);
    let rejectOnAbort;
    const deadline = new Promise((_, reject) => {
      rejectOnAbort = () => reject(new HookError(503, 'SMS service unavailable.'));
      if (controller.signal.aborted) rejectOnAbort(); else controller.signal.addEventListener('abort', rejectOnAbort, { once: true });
    });
    const work = async () => {
      const meta = parseMetadata(request.headers, now());
      const raw = await boundedBytes(request, BODY_LIMIT, controller.signal);
      await verify(raw, meta, config.secrets, cryptography);
      const event = eventData(raw);
      await deliver(config, event, meta, transport, controller.signal, now, cryptography);
      return response(200);
    };
    try { return await Promise.race([work(), deadline]); }
    catch (error) { return error instanceof HookError ? response(error.status, error.message) : response(503, 'SMS service unavailable.'); }
    finally {
      clearTimeout(timer);
      request.signal.removeEventListener('abort', abort);
      controller.signal.removeEventListener('abort', rejectOnAbort);
    }
  };
}
