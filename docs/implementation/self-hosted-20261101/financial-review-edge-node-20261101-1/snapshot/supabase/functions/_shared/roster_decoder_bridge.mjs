// Explicitly configured signed decoder transport; no filesystem or ambient environment access.
const POLICY = 'collect-roster-decoder-v1';
const LOGICAL_URL = 'https://roster-decoder.internal/decode';
const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const UTF8 = new TextEncoder();
const TOOLCHAIN = Object.freeze({
  python: '3.12', pillow: '12.3.0', pypdfium2: '5.2.0',
  pypdf: '6.19.0', openpyxl: '3.1.5', defusedxml: '0.7.1',
});
const KINDS = Object.freeze({
  'image/png': 'image', 'image/jpeg': 'image', 'image/webp': 'image',
  'application/pdf': 'pdf',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
});
export const ROSTER_DECODER_BRIDGE_LIMITS = Object.freeze({
  sourceBytes: 5 * 1024 * 1024,
  requestBytes: 8 * 1024 * 1024,
  responseBytes: 600000,
  payloadBytes: 560000,
  directResponseBytes: 7100000,
  textBytes: 64000,
  freshnessSeconds: 30,
  timeoutMilliseconds: 20000,
});

export class RosterDecoderBridgeError extends Error {
  constructor(code) {
    super(code);
    this.name = 'RosterDecoderBridgeError';
    this.code = code;
  }
}

function fail(code) { throw new RosterDecoderBridgeError(code); }
function exact(value, keys) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length === keys.length
    && keys.every(key => Object.hasOwn(value, key));
}
function integer(value, min, max) {
  return Number.isSafeInteger(value) && value >= min && value <= max;
}
function abortCheck(signal) {
  if (signal.aborted) fail('roster_decoder_aborted');
}
function abortable(value, signal, trackPromise) {
  // Own the original operation before any abort check/race can abandon it.
  value=trackPromise(Promise.resolve(value));void value.catch(()=>{});
  abortCheck(signal);
  return new Promise((resolve, reject) => {
    const aborted = () => {
      signal.removeEventListener('abort', aborted);
      reject(new RosterDecoderBridgeError('roster_decoder_aborted'));
    };
    signal.addEventListener('abort', aborted, {once: true});
    Promise.resolve(value).then(result => {
      signal.removeEventListener('abort', aborted);
      if (signal.aborted) aborted(); else resolve(result);
    }, error => {
      signal.removeEventListener('abort', aborted);
      reject(signal.aborted ? new RosterDecoderBridgeError('roster_decoder_aborted') : error);
    });
  });
}
function parseJSON(bytes, code) {
  try { return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes)); }
  catch { fail(code); }
}
async function boundedBytes(message, limit, signal, code, trackPromise, onUncertain) {
  const declared = message.headers.get('content-length');
  if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > limit)) fail(code);
  const reader = message.body?.getReader();
  if (!reader) fail(code);
  const chunks = [];
  let size = 0,complete=false;
  try {
    while (true) {
      const {done, value} = await abortable(reader.read(), signal, trackPromise);
      if (done) {complete=true;break;}
      if (!(value instanceof Uint8Array) || value.byteLength > limit - size) fail(code);
      size += value.byteLength;
      chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return bytes;
  } finally {
    // Caller refusal remains bounded, while the real work owner retains both
    // original read and cancellation promises until their actual settlement.
    if(!complete)onUncertain();
    const raw=reader.cancel();trackPromise(raw).catch(()=>onUncertain());
    reader.releaseLock();
  }
}
function jsonContentType(message) {
  return message.headers.get('content-type')?.split(';', 1)[0].trim().toLowerCase() === 'application/json';
}
function hex(bytes) {
  return Array.from(new Uint8Array(bytes), value => value.toString(16).padStart(2, '0')).join('');
}
function unhex(value) {
  return Uint8Array.from(value.match(/../g), pair => Number.parseInt(pair, 16));
}
function sourceBytes(value) {
  const max = ROSTER_DECODER_BRIDGE_LIMITS.sourceBytes;
  if (typeof value !== 'string' || value.length === 0 || value.length % 4 !== 0
      || value.length > 4 * Math.ceil(max / 3) || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) {
    fail('roster_decoder_request_invalid');
  }
  let binary;
  try { binary = atob(value); }
  catch { fail('roster_decoder_request_invalid'); }
  if (binary.length < 1 || binary.length > max || btoa(binary) !== value) fail('roster_decoder_request_invalid');
  return Uint8Array.from(binary, character => character.charCodeAt(0));
}

/**
 * Build a fixed-destination adapter for the existing five-field logical Request.
 * requestId/reservationId are trusted caller context, never recovered from source.
 * The caller supplies a dedicated supervisor key, not a provider/Bearer token.
 */
export function createRosterDecoderBridge({
  protocol, endpoint, secret, approvedBuildSha256,
  fetchImpl = globalThis.fetch, cryptoImpl = globalThis.crypto,
  now = Date.now, nonceFactory, trackPromise=promise=>promise, onUncertain=()=>{},
} = {}) {
  if (typeof endpoint !== 'string') fail('roster_decoder_config_invalid');
  let target;
  try { target = new URL(endpoint); }
  catch { fail('roster_decoder_config_invalid'); }
  if (protocol !== 'roster-hmac-v1' || typeof endpoint !== 'string'
      || target.href !== endpoint || target.protocol !== 'https:' || !target.hostname
      || target.username || target.password || target.search || target.hash
      || endpoint.includes('?') || endpoint.includes('#')
      || target.pathname !== '/decode' || (target.port && target.port !== '443')
      || typeof secret !== 'string' || UTF8.encode(secret).byteLength < 32
      || UTF8.encode(secret).byteLength > 4096 || secret.includes('\0')
      || typeof approvedBuildSha256 !== 'string' || !SHA256.test(approvedBuildSha256)
      || typeof fetchImpl !== 'function' || typeof now !== 'function'
      || typeof trackPromise !== 'function' || typeof onUncertain !== 'function'
      || !cryptoImpl?.subtle || typeof cryptoImpl.subtle.importKey !== 'function'
      || typeof cryptoImpl.subtle.sign !== 'function' || typeof cryptoImpl.subtle.verify !== 'function'
      || typeof cryptoImpl.subtle.digest !== 'function'
      || (nonceFactory !== undefined && typeof nonceFactory !== 'function')
      || (nonceFactory === undefined && typeof cryptoImpl.randomUUID !== 'function')) {
    fail('roster_decoder_config_invalid');
  }
  const makeNonce = nonceFactory ?? (() => cryptoImpl.randomUUID());
  let key;
  const recentNonces = new Map();
  const clock = () => {
    const value = now();
    if (typeof value !== 'number' || !Number.isFinite(value)
        || !integer(Math.floor(value / 1000), 0, Number.MAX_SAFE_INTEGER)) fail('roster_decoder_config_invalid');
    return Math.floor(value / 1000);
  };
  const digest = async bytes => hex(await cryptoImpl.subtle.digest('SHA-256', bytes));
  const hmacKey = () => {
    key ??= cryptoImpl.subtle.importKey('raw', UTF8.encode(secret),
      {name: 'HMAC', hash: 'SHA-256'}, false, ['sign', 'verify']);
    return key;
  };

  return Object.freeze({
    async fetch(logicalRequest, context) {
      const controller = new AbortController();
      const signal = controller.signal;
      const cancelled = () => controller.abort();
      let timer,dispatched=false;
      const observe=value=>abortable(value,signal,trackPromise);
      try {
        if (!(logicalRequest instanceof Request) || logicalRequest.url !== LOGICAL_URL
            || logicalRequest.method !== 'POST' || !jsonContentType(logicalRequest)
            || !exact(context, ['requestId', 'reservationId'])
            || typeof context.requestId !== 'string' || !UUID.test(context.requestId)
            || typeof context.reservationId !== 'string' || !UUID.test(context.reservationId)) {
          fail('roster_decoder_request_invalid');
        }
        logicalRequest.signal.addEventListener('abort', cancelled, {once: true});
        if (logicalRequest.signal.aborted) cancelled();
        timer = setTimeout(cancelled, ROSTER_DECODER_BRIDGE_LIMITS.timeoutMilliseconds);
        abortCheck(signal);
        const logical = parseJSON(await boundedBytes(logicalRequest,
          ROSTER_DECODER_BRIDGE_LIMITS.requestBytes, signal, 'roster_decoder_request_invalid',trackPromise,()=>{}),
        'roster_decoder_request_invalid');
        if (!exact(logical, ['schema_version', 'source_sha256', 'decoder_build_sha256', 'mime_type', 'content_base64'])
            || logical.schema_version !== 1 || typeof logical.source_sha256 !== 'string'
            || !SHA256.test(logical.source_sha256) || logical.decoder_build_sha256 !== approvedBuildSha256
            || typeof logical.mime_type !== 'string' || !Object.hasOwn(KINDS, logical.mime_type)) {
          fail('roster_decoder_request_invalid');
        }
        const bytes = sourceBytes(logical.content_base64);
        if (await observe(digest(bytes)) !== logical.source_sha256) fail('roster_decoder_source_mismatch');
        const issuedAt = clock();
        const nonce = makeNonce();
        if (typeof nonce !== 'string' || !UUID.test(nonce)) fail('roster_decoder_config_invalid');
        for (const [previous, at] of recentNonces) if (at < issuedAt - 60) recentNonces.delete(previous);
        if (recentNonces.has(nonce)) fail('roster_decoder_nonce_reused');
        if (recentNonces.size >= 5000) fail('roster_decoder_unavailable');
        recentNonces.set(nonce, issuedAt);
        const kind = KINDS[logical.mime_type];
        const supervisorBody = JSON.stringify({
          request_id: context.requestId, reservation_id: context.reservationId,
          source_sha256: logical.source_sha256, mime: logical.mime_type, kind,
          content_base64: logical.content_base64, policy_version: POLICY, nonce, issued_at: issuedAt,
        });
        const bodyBytes = UTF8.encode(supervisorBody);
        if (bodyBytes.byteLength > ROSTER_DECODER_BRIDGE_LIMITS.requestBytes) fail('roster_decoder_request_invalid');
        const signingKey = await observe(hmacKey());
        const signature = hex(await observe(cryptoImpl.subtle.sign('HMAC', signingKey, bodyBytes)));
        dispatched=true;const response = await observe(fetchImpl(endpoint, {
          method: 'POST', redirect: 'error', signal,
          headers: {'Content-Type': 'application/json', 'Content-Length': String(bodyBytes.byteLength),
            Authorization: `Roster-HMAC ${signature}`},
          body: supervisorBody,
        }));
        if (!(response instanceof Response) || response.status !== 200) fail('roster_decoder_unavailable');
        if (response.redirected || (response.url && response.url !== endpoint)
            || !jsonContentType(response)) fail('roster_decoder_response_invalid');
        const envelope = parseJSON(await boundedBytes(response,
          ROSTER_DECODER_BRIDGE_LIMITS.responseBytes, signal, 'roster_decoder_response_invalid',trackPromise,onUncertain),
        'roster_decoder_response_invalid');
        if (!exact(envelope, ['payload', 'signature']) || typeof envelope.payload !== 'string'
            || UTF8.encode(envelope.payload).byteLength > ROSTER_DECODER_BRIDGE_LIMITS.payloadBytes
            || typeof envelope.signature !== 'string' || !SHA256.test(envelope.signature)) {
          fail('roster_decoder_response_invalid');
        }
        const payloadBytes = UTF8.encode(envelope.payload);
        // WebCrypto verifies HMAC without a JavaScript equality comparison of secrets.
        if (!await observe(cryptoImpl.subtle.verify('HMAC', signingKey,
          unhex(envelope.signature), payloadBytes))) fail('roster_decoder_authentication_failed');
        const decoded = parseJSON(payloadBytes, 'roster_decoder_response_invalid');
        if (!exact(decoded, ['contract_version', 'request_id', 'reservation_id', 'nonce', 'issued_at',
          'kind', 'mime', 'decoder_build_sha256', 'ok', 'policy_version', 'toolchain',
          'source_sha256', 'source_size', 'derived_sha256', 'frames', 'pages', 'pixels',
          'expanded_bytes', 'derived_content']) || decoded.contract_version !== 1 || decoded.ok !== true
            || !exact(decoded.toolchain, Object.keys(TOOLCHAIN))
            || !Object.entries(TOOLCHAIN).every(([name, version]) => decoded.toolchain[name] === version)
            || !integer(decoded.frames, 0, 20) || !integer(decoded.pages, 0, 20)
            || !integer(decoded.pixels, 0, 16000000) || !integer(decoded.expanded_bytes, 0, 64000000)) {
          fail('roster_decoder_response_invalid');
        }
        if (decoded.request_id !== context.requestId || decoded.reservation_id !== context.reservationId
            || decoded.nonce !== nonce || decoded.source_sha256 !== logical.source_sha256
            || decoded.source_size !== bytes.byteLength || decoded.kind !== kind
            || decoded.mime !== logical.mime_type || decoded.policy_version !== POLICY
            || decoded.decoder_build_sha256 !== approvedBuildSha256) fail('roster_decoder_response_mismatch');
        if (!integer(decoded.issued_at, 0, Number.MAX_SAFE_INTEGER)
            || Math.abs(clock() - decoded.issued_at) > ROSTER_DECODER_BRIDGE_LIMITS.freshnessSeconds
            || decoded.issued_at < issuedAt - ROSTER_DECODER_BRIDGE_LIMITS.freshnessSeconds) {
          fail('roster_decoder_response_stale');
        }
        let content;
        if (kind === 'image') {
          if (decoded.frames < 1 || decoded.pages !== 0 || decoded.pixels < 1
              || decoded.expanded_bytes !== decoded.pixels * 4
              || decoded.derived_content !== null || decoded.derived_sha256 !== null) {
            fail('roster_decoder_response_invalid');
          }
          if (decoded.frames !== 1) fail('roster_decoder_content_unavailable');
          // The signed supervisor validated precisely these original source bytes.
          content = [{type: 'input_image', image_url: `data:${logical.mime_type};base64,${logical.content_base64}`}];
        } else if (kind === 'pdf') {
          if (decoded.frames !== 0 || decoded.pages < 1 || decoded.pixels < 1
              || decoded.expanded_bytes > 32 * 1024 * 1024
              || decoded.derived_content !== null || decoded.derived_sha256 !== null) {
            fail('roster_decoder_response_invalid');
          }
          // Explicit caller contract: original PDF only, after signed validation.
          content = [{type: 'input_file', filename: 'roster.pdf',
            file_data: `data:application/pdf;base64,${logical.content_base64}`}];
        } else {
          if (decoded.frames !== 0 || decoded.pages !== 0 || decoded.pixels !== 0
              || decoded.expanded_bytes > 32 * 1024 * 1024
              || typeof decoded.derived_content !== 'string' || typeof decoded.derived_sha256 !== 'string'
              || !SHA256.test(decoded.derived_sha256)) fail('roster_decoder_response_invalid');
          const text = decoded.derived_content;
          if (UTF8.encode(text).byteLength > ROSTER_DECODER_BRIDGE_LIMITS.textBytes) fail('roster_decoder_content_limit');
          const rows = text.split('\n');
          if (rows.length < 2 || rows.length > 501 || rows[0] !== 'Member name\tMoMo name\tMoMo number'
              || /[\0\r]/.test(text) || rows.some(row => row.split('\t').length !== 3)) {
            fail('roster_decoder_response_invalid');
          }
          if (await observe(digest(UTF8.encode(text))) !== decoded.derived_sha256) {
            fail('roster_decoder_response_mismatch');
          }
          content = [{type: 'input_text', text}];
        }
        const directBody = JSON.stringify({source_sha256: logical.source_sha256,
          decoder_build_sha256: approvedBuildSha256, content});
        if (UTF8.encode(directBody).byteLength > ROSTER_DECODER_BRIDGE_LIMITS.directResponseBytes) {
          fail('roster_decoder_content_limit');
        }
        abortCheck(signal);
        return new Response(directBody, {status: 200,
          headers: {'Content-Type': 'application/json', 'Cache-Control': 'no-store'}});
      } catch (error) {
        if(dispatched)onUncertain();
        if (signal.aborted) fail('roster_decoder_aborted');
        if (error instanceof RosterDecoderBridgeError) throw error;
        fail('roster_decoder_unavailable');
      } finally {
        if (timer !== undefined) clearTimeout(timer);
        if (logicalRequest instanceof Request) logicalRequest.signal.removeEventListener('abort', cancelled);
        // Also close unread error/redirect bodies; the returned Response is local.
        controller.abort();
      }
    },
  });
}
