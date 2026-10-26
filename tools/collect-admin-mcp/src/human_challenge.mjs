import { createServer } from 'node:http';
import { generateKeyPairSync, randomBytes, randomUUID, sign, timingSafeEqual } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { ADMIN_ORIGIN, SafeError, object, UUID } from './config.mjs';

const APPROVED_ORIGINS = new Set([ADMIN_ORIGIN, 'https://admin-supabase-qa.collect.ikanisa.com']);
const OFFER = '/v1/collect-admin/human-challenge/offer';
const COMPLETE = '/v1/collect-admin/human-challenge/complete';
const OPERATIONS = new Set(['admin.email_otp.send', 'admin.email_otp.verify', 'admin.password.sign_in']);
const ERRORS = new Set(['cancelled', 'expired', 'unavailable', 'timeout', 'invalid_token']);
const TTL = 120_000, BODY_MAX = 16_384, HEADER_MAX = 8192, REQUEST_MAX = 4;
const B64 = /^[A-Za-z0-9_-]{43}$/;
let active = false;

const safe = code => new SafeError(code, code === 'challenge_cancelled'
  ? 'Security verification was cancelled. No request was retried.'
  : code === 'challenge_expired'
    ? 'Security verification expired. No request was retried.'
    : 'Security verification could not be confirmed. No request was retried.');
const canonical = value => JSON.stringify(Object.fromEntries(Object.keys(value).sort().map(key => [key, value[key]])));

// Completion envelopes are flat string maps. Parsing that grammar explicitly
// rejects duplicate decoded keys without imposing canonical order on browsers.
function completionJson(bytes) {
  const text = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  let at = 0;
  const ws = () => { while (/[\x20\t\r\n]/.test(text[at] ?? '\0')) at++; };
  function string() {
    if (text[at] !== '"') throw safe('invalid_challenge');
    const start = at++;
    while (at < text.length) {
      if (text[at] === '\\') { at += 2; continue; }
      if (text[at++] === '"') return JSON.parse(text.slice(start, at));
    }
    throw safe('invalid_challenge');
  }
  ws(); if (text[at++] !== '{') throw safe('invalid_challenge');
  ws(); const value = Object.create(null), seen = new Set();
  if (text[at] !== '}') for (;;) {
    const key = string(); ws();
    if (seen.has(key) || text[at++] !== ':') throw safe('invalid_challenge');
    seen.add(key); ws(); value[key] = string(); ws();
    if (text[at] !== ',') break;
    at++; ws();
  }
  if (text[at++] !== '}') throw safe('invalid_challenge');
  ws(); if (at !== text.length) throw safe('invalid_challenge');
  return value;
}

function uniqueHeaders(request) {
  const names = new Set(); let bytes = 0;
  if (request.rawHeaders.length > 64) return false;
  for (let i = 0; i < request.rawHeaders.length; i += 2) {
    const name = request.rawHeaders[i].toLowerCase();
    bytes += Buffer.byteLength(request.rawHeaders[i]) + Buffer.byteLength(request.rawHeaders[i + 1]) + 4;
    if (names.has(name)) return false;
    names.add(name);
  }
  return bytes <= HEADER_MAX;
}

/** Human-only acquisition. This never calls Auth or reads/saves any credential. */
export async function acquireHumanChallenge(config, options) {
  if (!object(config) || !APPROVED_ORIGINS.has(config.origin) || !object(options) ||
      Object.keys(options).some(key => !['operation', 'onPairing', 'signal'].includes(key)) ||
      !OPERATIONS.has(options.operation) || typeof options.onPairing !== 'function' ||
      options.signal !== undefined && !(options.signal instanceof AbortSignal)) throw safe('invalid_challenge');
  const { operation, onPairing, signal } = options;
  const origin = config.origin;
  if (signal?.aborted) throw safe('challenge_cancelled');
  if (active) throw safe('challenge_pending');
  active = true;
  const started = performance.now(), issued = Date.now();
  const sockets = new Set();
  let attempt, nonce = Buffer.alloc(0), keys, server, timer, closeTimer, offered = false, posting = false, terminal = false;
  let requests = 0, preflights = 0, connections = 0, port, resolveResult;
  const result = new Promise(resolve => { resolveResult = resolve; });
  const expired = () => performance.now() - started >= TTL;
  function finish(error, token) {
    if (terminal) return;
    terminal = true;
    resolveResult(error ? { error } : { token });
  }
  const abort = () => finish(safe('challenge_cancelled'));
  function reply(request, response, status, value, after) {
    const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', Vary: 'Origin', Connection: 'close' };
    if (request.headers.origin === origin) headers['Access-Control-Allow-Origin'] = origin;
    const bytes = value === undefined ? Buffer.alloc(0) : Buffer.from(JSON.stringify(value));
    headers['Content-Length'] = String(bytes.length);
    response.once('error', () => finish(safe('challenge_unconfirmed')));
    if (after) response.once('finish', after);
    response.writeHead(status, headers); response.end(bytes);
  }
  const refusal = (request, response, status, end = false) => reply(request, response, status,
    { error: { code: 'challenge_refused' } }, end ? () => finish(safe('invalid_challenge')) : undefined);
  try {
    attempt = randomUUID(); nonce = randomBytes(32);
    keys = generateKeyPairSync('ed25519');
    server = createServer({ maxHeaderSize: HEADER_MAX, insecureHTTPParser: false }, (request, response) => {
      void handle(request, response).catch(() => {
        if (!response.headersSent && !response.destroyed) refusal(request, response, 400, true);
        else finish(safe('challenge_unconfirmed'));
      });
    });
    server.maxHeadersCount = 32; server.maxConnections = 4;
    server.headersTimeout = 5000; server.requestTimeout = 5000; server.keepAliveTimeout = 1000;
    server.on('connection', socket => {
      sockets.add(socket); socket.once('close', () => sockets.delete(socket));
      socket.setTimeout(5000, () => socket.destroy());
      if (++connections > 8) { socket.destroy(); finish(safe('challenge_unconfirmed')); }
    });
    server.on('clientError', (_error, socket) => {
      socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
      finish(safe('invalid_challenge'));
    });
    server.on('error', () => finish(safe('challenge_unconfirmed')));
    signal?.addEventListener('abort', abort, { once: true });
    timer = setTimeout(() => finish(safe('challenge_expired')), TTL);
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen({ host: '127.0.0.1', port: 0, exclusive: true }, resolve);
    });
    port = server.address().port;
    if (!Number.isInteger(port) || port < 1024 || port > 65535) throw safe('challenge_unconfirmed');
    if (signal?.aborted) abort();
    if (!terminal) {
      const descriptor = Object.freeze({ type: 'collect.admin.human_challenge.pairing.v1', attempt_id: attempt,
        operation, admin_origin: origin, loopback_port: port, expires_at_ms: issued + TTL,
        listener_public_key_ed25519: keys.publicKey.export({ format: 'jwk' }).x });
      const pairing = Object.freeze({ descriptor, parentUrl: `${origin}/admin/auth/local-challenge` });
      // A pending UI callback must never extend the listener deadline.
      Promise.resolve().then(() => onPairing(pairing)).catch(() => finish(safe('challenge_unconfirmed')));
    }
    const outcome = await result;
    if (outcome.error) throw outcome.error;
    return outcome.token;

    async function handle(request, response) {
      request.on('error', () => finish(safe('challenge_unconfirmed')));
      if (terminal || expired()) {
        reply(request, response, 410, { error: { code: 'challenge_refused' } }, () => finish(safe('challenge_expired'))); return;
      }
      if (++requests > REQUEST_MAX) { refusal(request, response, 429, true); return; }
      if (!uniqueHeaders(request) || request.headers['transfer-encoding'] !== undefined) { refusal(request, response, 400); return; }
      if (request.socket.remoteAddress !== '127.0.0.1' || request.headers.host !== `127.0.0.1:${port}` ||
          request.headers.origin !== origin || request.headers.cookie !== undefined || request.headers.authorization !== undefined) {
        refusal(request, response, 403); return;
      }
      if (![OFFER, COMPLETE].includes(request.url)) { refusal(request, response, 404); return; }
      if (request.method === 'OPTIONS') {
        if (++preflights > 2) { refusal(request, response, 429, true); return; }
        const method = request.headers['access-control-request-method'];
        const headers = (request.headers['access-control-request-headers'] ?? '').split(',').map(s => s.trim().toLowerCase());
        const allowed = new Set(['content-type', 'x-collect-handoff-version', 'x-collect-handoff-attempt']);
        if (method !== (request.url === OFFER ? 'GET' : 'POST') || headers.some(h => !allowed.has(h)) ||
            new Set(headers).size !== headers.length || !headers.includes('x-collect-handoff-version') || !headers.includes('x-collect-handoff-attempt') ||
            request.headers['access-control-request-private-network'] !== undefined || request.headers['content-length'] !== undefined) {
          refusal(request, response, 400); return;
        }
        response.writeHead(204, { 'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, X-Collect-Handoff-Version, X-Collect-Handoff-Attempt',
          'Access-Control-Max-Age': '0', Vary: 'Origin, Access-Control-Request-Method, Access-Control-Request-Headers',
          'Cache-Control': 'no-store', 'Content-Length': '0', Connection: 'close' }); response.end(); return;
      }
      if (request.method !== (request.url === OFFER ? 'GET' : 'POST')) { refusal(request, response, 405); return; }
      if (request.headers['x-collect-handoff-version'] !== '1' || request.headers['x-collect-handoff-attempt'] !== attempt) {
        refusal(request, response, 403); return;
      }
      if (request.url === OFFER) {
        if (offered) { refusal(request, response, 409); return; }
        if (request.headers['content-length'] !== undefined) { refusal(request, response, 400); return; }
        offered = true;
        const payload = Buffer.from(canonical({ type: 'collect.admin.human_challenge.offer_payload.v1', attempt_id: attempt,
          operation, admin_origin: origin, loopback_port: port, nonce: nonce.toString('base64url'),
          issued_at_ms: issued, expires_at_ms: issued + TTL }));
        const envelope = { type: 'collect.admin.human_challenge.signed_offer.v1', payload_base64url: payload.toString('base64url'),
          signature_ed25519_base64url: sign(null, payload, keys.privateKey).toString('base64url') };
        if (Buffer.byteLength(JSON.stringify(envelope)) > 8192) throw safe('invalid_challenge');
        reply(request, response, 200, envelope); return;
      }
      if (!offered || posting) { refusal(request, response, 409, true); return; }
      posting = true;
      if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers['content-type'] ?? '')) { refusal(request, response, 415, true); return; }
      const length = request.headers['content-length'];
      if (!/^(0|[1-9][0-9]*)$/.test(length ?? '')) { refusal(request, response, 400, true); return; }
      if (Number(length) > BODY_MAX) { refusal(request, response, 413, true); return; }
      const chunks = []; let size = 0;
      for await (const chunk of request) {
        size += chunk.length;
        if (size > BODY_MAX) { refusal(request, response, 413, true); return; }
        chunks.push(chunk);
      }
      if (terminal || expired()) { reply(request, response, 410, { error: { code: 'challenge_refused' } }, () => finish(safe('challenge_expired'))); return; }
      if (size !== Number(length)) { refusal(request, response, 400, true); return; }
      const value = completionJson(Buffer.concat(chunks, size));
      const field = Object.hasOwn(value, 'token') ? 'token' : 'error';
      const expected = ['type', 'attempt_id', 'operation', 'nonce', 'widget_attempt_id', field].sort();
      if (Object.keys(value).sort().join(',') !== expected.join(',') || value.type !== 'collect.admin.human_challenge.complete.v1' ||
          !UUID.test(value.attempt_id) || !UUID.test(value.widget_attempt_id) || !OPERATIONS.has(value.operation) || !B64.test(value.nonce)) {
        refusal(request, response, 400, true); return;
      }
      if (value.attempt_id !== attempt || value.widget_attempt_id !== attempt || value.operation !== operation) { refusal(request, response, 409, true); return; }
      const candidate = Buffer.from(value.nonce, 'base64url');
      if (candidate.length !== 32 || candidate.toString('base64url') !== value.nonce || !timingSafeEqual(nonce, candidate)) {
        refusal(request, response, 403, true); return;
      }
      if (field === 'token' ? !value.token.length || value.token.length > 2048 || /[\x00-\x20\x7f]/.test(value.token) : !ERRORS.has(value.error)) {
        refusal(request, response, 400, true); return;
      }
      // No await separates the final deadline check from one-shot consumption.
      if (expired()) { reply(request, response, 410, { error: { code: 'challenge_refused' } }, () => finish(safe('challenge_expired'))); return; }
      nonce.fill(0);
      const failure = field === 'error' ? safe(value.error === 'cancelled' ? 'challenge_cancelled'
        : ['expired', 'timeout'].includes(value.error) ? 'challenge_expired' : 'challenge_unconfirmed') : null;
      const status = !failure ? 'accepted_for_one_cli_operation' : value.error === 'cancelled' ? 'cancelled_without_auth'
        : ['expired', 'timeout'].includes(value.error) ? 'expired_without_auth' : 'failed_without_auth';
      reply(request, response, 202, { type: 'collect.admin.human_challenge.ack.v1', attempt_id: attempt, operation,
        status, session_confirmed: false }, () => finish(failure, failure ? undefined : value.token));
    }
  } catch (error) {
    throw error instanceof SafeError ? error : safe('challenge_unconfirmed');
  } finally {
    clearTimeout(timer); signal?.removeEventListener('abort', abort); nonce.fill(0); keys = undefined;
    if (server) {
      await new Promise(resolve => {
        server.close(() => { clearTimeout(closeTimer); resolve(); });
        server.closeIdleConnections();
        // Close only this helper's sockets, including an incomplete request.
        closeTimer = setTimeout(() => { for (const socket of sockets) socket.destroy(); },
          Math.max(0, Math.min(100, TTL - (performance.now() - started))));
      });
      clearTimeout(closeTimer);
    }
    active = false;
  }
}
