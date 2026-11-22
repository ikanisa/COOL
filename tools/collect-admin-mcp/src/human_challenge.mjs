import { createServer } from 'node:http';
import { generateKeyPairSync, randomBytes, randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { ADMIN_ORIGIN, SafeError, object } from './config.mjs';
import { OPERATIONS, challengeError as safe, pairingDescriptor, signedOffer, validateCompletion } from './human_challenge_protocol.mjs';

const APPROVED_ORIGINS = new Set([ADMIN_ORIGIN, 'https://admin-supabase-qa.collect.ikanisa.com']);
const OFFER = '/v1/collect-admin/human-challenge/offer';
const COMPLETE = '/v1/collect-admin/human-challenge/complete';
const TTL = 120_000, BODY_MAX = 16_384, HEADER_MAX = 8192, REQUEST_MAX = 4;
let active = false;

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
      const descriptor = pairingDescriptor({ attempt, operation, origin, port, expiresAt: issued + TTL,
        publicKey: keys.publicKey });
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
        const envelope = signedOffer({ attempt, operation, origin, port, nonce, issuedAt: issued,
          expiresAt: issued + TTL, privateKey: keys.privateKey });
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
      const completion = validateCompletion(Buffer.concat(chunks, size), { attempt, operation, nonce });
      if (completion.refusal) { refusal(request, response, completion.refusal, true); return; }
      // No await separates the final deadline check from one-shot consumption.
      if (expired()) { reply(request, response, 410, { error: { code: 'challenge_refused' } }, () => finish(safe('challenge_expired'))); return; }
      nonce.fill(0);
      reply(request, response, 202, { type: 'collect.admin.human_challenge.ack.v1', attempt_id: attempt, operation,
        status: completion.status, session_confirmed: false }, () => finish(completion.error, completion.token));
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
