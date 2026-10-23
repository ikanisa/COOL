/** Provider-neutral Fetch transport. Copy provenance is recorded in PROVENANCE.json.
 * No credentials are minted or persisted; upstream remains the sole authority. */
export const SUPABASE_ORIGIN = 'https://rrlduytparvsjfmegalh.supabase.co';
const FRONTENDS = new Set(['https://collect.ikanisa.com', 'https://admin.collect.ikanisa.com', 'https://platform-admin.collect.ikanisa.com']);
const METHODS = new Set(['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']);
const FORWARD_HEADERS = new Set([
  'accept', 'accept-language', 'authorization', 'apikey', 'cookie', 'origin',
  'content-type', 'idempotency-key', 'x-request-id', 'range', 'if-match',
  'x-collect-admin', 'x-collect-requested-with', 'x-collect-csrf',
  'x-collect-review-reason', 'x-collect-gateway-key-id', 'x-collect-gateway-signature',
  'sec-fetch-site', 'sec-fetch-mode', 'sec-fetch-dest',
]);
const SPOOFED_AUTHORITY = new Set([
  'x-collect-actor', 'x-collect-original-path', 'x-collect-user-id',
  'x-collect-session-id', 'x-collect-authenticated-user', 'x-collect-verified',
  'x-forwarded-host', 'x-original-url', 'x-rewrite-url', 'forwarded',
]);
const DROP_RESPONSE = new Set([
  'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
  'te', 'trailer', 'transfer-encoding', 'upgrade', 'content-length',
  'content-encoding', 'etag', 'last-modified', 'age', 'expires',
  'access-control-allow-origin', 'access-control-allow-credentials',
  'access-control-allow-methods', 'access-control-allow-headers',
  'netlify-cdn-cache-control',
]);
const DOCUMENTS = new Map([
  ['/v1/security/challenge', 'collect.turnstile.v1'],
  ['/v1/auth/google/callback', 'collect.google.callback.v1'],
  ['/privacy/account-deletion', 'collect.privacy.portal.v1'],
  ['/privacy/account-deletion/', 'collect.privacy.portal.v1'],
]);
const GOOGLE_CALLBACK = '/v1/auth/google/callback';
// Exact token-free errors emitted by the current shared Google callback helper.
const GOOGLE_NATIVE_ERRORS = new Set([
  'invalid_google_sign_in', 'google_cancelled', 'google_use_email_sign_in',
  'google_sign_in_unconfirmed',
]);

function nativeGoogleRedirect(upstream, route, method) {
  if (method !== 'GET' || route.functionName !== 'collect-api' || route.logicalPath !== GOOGLE_CALLBACK ||
      upstream.status !== 302 || upstream.headers.get('X-Collect-Document') !== 'collect.google.native.v1') return false;
  const location = upstream.headers.get('location');
  if (!location) return false;
  let target;
  try { target = new URL(location); } catch { return false; }
  if (target.href !== location || target.protocol !== 'collect:' || target.host !== 'auth' ||
      target.pathname !== '/google' || target.username || target.password || target.port || target.hash) return false;
  const keys = [...target.searchParams.keys()];
  if (keys.length !== 2 || new Set(keys).size !== 2 || !/^[A-Za-z0-9_-]{43}$/.test(target.searchParams.get('state') ?? '')) return false;
  return keys.includes('code') ? /^[A-Za-z0-9_-]{43}$/.test(target.searchParams.get('code') ?? '') :
    keys.includes('error') && GOOGLE_NATIVE_ERRORS.has(target.searchParams.get('error'));
}

class ProxyFailure extends Error {
  constructor(status, code) { super(code); this.status = status; this.code = code; }
}
function refuse(status, code) { throw new ProxyFailure(status, code); }
function protectedHeaders(headers = new Headers()) {
  headers.set('Cache-Control', 'private, no-store, max-age=0');
  headers.set('CDN-Cache-Control', 'no-store');
  headers.set('Netlify-CDN-Cache-Control', 'no-store');
  headers.set('Surrogate-Control', 'no-store');
  headers.set('Pragma', 'no-cache');
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('Referrer-Policy', 'no-referrer');
  headers.set('Cross-Origin-Resource-Policy', 'same-origin');
  return headers;
}
function failure(status, code, reason) {
  const headers = protectedHeaders(); headers.set('Content-Type', 'application/json; charset=utf-8');
  return new Response(JSON.stringify({code, ...(reason ? {reason} : {})}), {status, headers});
}

/** Validate the original raw path when the frontend host exposes it. Never
 * percent-decode a route into a second protocol or silently normalize dots. */
export function routeCollectTarget(rawTarget) {
  if (typeof rawTarget !== 'string' || !rawTarget.startsWith('/') || rawTarget.startsWith('//') ||
      /[\\\x00-\x20\x7f#]/.test(rawTarget)) refuse(400, 'proxy_path_invalid');
  const question = rawTarget.indexOf('?');
  const path = question < 0 ? rawTarget : rawTarget.slice(0, question);
  if (path.includes('%') || path.includes('//') || path.split('/').some(segment => segment === '.' || segment === '..') ||
      !/^\/[A-Za-z0-9._~\/-]*$/.test(path)) refuse(400, 'proxy_path_invalid');
  const query = question < 0 ? '' : rawTarget.slice(question);
  let functionName; let logicalPath = path;
  for (const name of ['collect-api', 'admin-api']) {
    const prefix = '/functions/v1/' + name;
    if (path.startsWith(prefix + '/')) { functionName = name; logicalPath = path.slice(prefix.length); break; }
  }
  if (path.startsWith('/functions/') && !functionName) refuse(404, 'proxy_route_not_allowed');
  if (functionName === 'admin-api' && !logicalPath.startsWith('/api/admin/')) refuse(404, 'proxy_route_not_allowed');
  const memberRoute = logicalPath.startsWith('/v1/') || logicalPath === '/privacy/account-deletion' || logicalPath.startsWith('/privacy/account-deletion/');
  if (functionName === 'collect-api' && !memberRoute) refuse(404, 'proxy_route_not_allowed');
  if (!functionName) {
    if (path.startsWith('/api/admin/')) functionName = 'admin-api';
    else if (memberRoute) functionName = 'collect-api';
    else return null;
  }
  return {path, logicalPath, query, functionName,
    upstream: SUPABASE_ORIGIN + '/functions/v1/' + functionName + logicalPath + query};
}

async function boundedBytes(stream, limit, signal, status, code) {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader(); const chunks = []; let total = 0;
  const abort = () => { void reader.cancel().catch(() => {}); };
  signal.addEventListener('abort', abort, {once: true});
  try {
    while (true) {
      if (signal.aborted) refuse(504, 'proxy_deadline');
      const {done, value} = await reader.read(); if (done) break;
      total += value.byteLength;
      if (total > limit) { await reader.cancel(); refuse(status, code); }
      chunks.push(value);
    }
    if (signal.aborted) refuse(504, 'proxy_deadline');
    const bytes = new Uint8Array(total); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    return bytes;
  } finally { signal.removeEventListener('abort', abort); reader.releaseLock(); }
}
function cookiesOf(headers) {
  if (typeof headers.getSetCookie === 'function') return headers.getSetCookie();
  const value = headers.get('set-cookie'); return value === null ? [] : [value];
}
function validateCookie(cookie, route) {
  if (route.functionName !== 'admin-api' || cookie.length > 4096 || /[\r\n]/.test(cookie)) refuse(502, 'proxy_cookie_invalid');
  const pieces = cookie.split(';').map(value => value.trim());
  if (!/^__Host-collect_admin=[A-Za-z0-9_-]*$/.test(pieces[0])) refuse(502, 'proxy_cookie_invalid');
  const attrs = new Map();
  for (const attribute of pieces.slice(1)) {
    const split = attribute.indexOf('=');
    const name = (split < 0 ? attribute : attribute.slice(0, split)).trim().toLowerCase();
    if (!name || attrs.has(name)) refuse(502, 'proxy_cookie_invalid');
    attrs.set(name, split < 0 ? null : attribute.slice(split + 1).trim().toLowerCase());
  }
  if (attrs.has('domain') || !attrs.has('secure') || attrs.get('secure') !== null ||
      !attrs.has('httponly') || attrs.get('httponly') !== null || attrs.get('path') !== '/' ||
      !['strict', 'lax'].includes(attrs.get('samesite'))) refuse(502, 'proxy_cookie_invalid');
}
function responseHeaders(upstream, route) {
  const headers = new Headers();
  for (const [name, value] of upstream.headers) {
    if (name === 'set-cookie' || DROP_RESPONSE.has(name)) continue;
    headers.append(name, value);
  }
  const cookies = cookiesOf(upstream.headers);
  if (cookies.length > 1) refuse(502, 'proxy_cookie_invalid');
  for (const cookie of cookies) { validateCookie(cookie, route); headers.append('Set-Cookie', cookie); }
  return protectedHeaders(headers);
}

export function createCollectTransport({frontendOrigin, fetchImpl = globalThis.fetch,
  timeoutMs = 30000, maxRequestBytes = 16 * 1024 * 1024, maxResponseBytes = 16 * 1024 * 1024} = {}) {
  if (!FRONTENDS.has(frontendOrigin) || typeof fetchImpl !== 'function' ||
      !Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 60000 ||
      !Number.isSafeInteger(maxRequestBytes) || maxRequestBytes < 1 ||
      !Number.isSafeInteger(maxResponseBytes) || maxResponseBytes < 1) throw new TypeError('Invalid static-host proxy configuration');
  /** null means the existing static host handles this route. Pass rawTarget
   * from the host only when it exposes the original, unnormalized request target. */
  return async function handle(request, {rawTarget} = {}) {
    let attempted = false; let effectful = !['GET', 'HEAD', 'OPTIONS'].includes(request.method); let timer; let abortListener;
    const controller = new AbortController();
    try {
      const url = new URL(request.url);
      if (url.origin !== frontendOrigin || url.username || url.password || url.hash) refuse(421, 'proxy_origin_invalid');
      const host = request.headers.get('host'); if (host && host !== url.host) refuse(421, 'proxy_origin_invalid');
      const canonical = url.pathname + url.search;
      const route = routeCollectTarget(rawTarget ?? canonical);
      if (!route) return null;
      // Admin reads can rotate managed credentials or revoke stale custody.
      // A missing response after dispatch cannot prove that no effect occurred.
      if (route.functionName === 'admin-api' && request.method !== 'OPTIONS') effectful = true;
      if (route.path + route.query !== canonical) refuse(400, 'proxy_path_invalid');
      if (!METHODS.has(request.method)) refuse(405, 'proxy_method_invalid');
      for (const name of SPOOFED_AUTHORITY) if (request.headers.has(name)) refuse(400, 'proxy_authority_invalid');
      const callback = route.functionName === 'collect-api' && route.logicalPath === GOOGLE_CALLBACK && request.method === 'GET';
      // This GET performs the provider exchange and may already have committed
      // managed-token custody when response qualification fails.
      if (callback) effectful = true;
      const providerNavigation = callback && request.headers.get('sec-fetch-mode') === 'navigate' && request.headers.get('sec-fetch-dest') === 'document';
      const origin = request.headers.get('origin');
      if (origin && origin !== frontendOrigin && !(providerNavigation && origin === SUPABASE_ORIGIN)) refuse(403, 'proxy_origin_denied');
      if (request.headers.get('sec-fetch-site') === 'cross-site' &&
          !providerNavigation) refuse(403, 'proxy_origin_denied');
      const adminRead = route.functionName === 'admin-api' && ['GET', 'HEAD'].includes(request.method);
      // A browser's same-origin GET often omits Origin. Bind Admin lookup to
      // the configured public host, never to forwarded host/authority metadata.
      // Originless cross-origin sibling requests must not be promoted to it.
      if (adminRead && !origin && ![null, 'none', 'same-origin'].includes(request.headers.get('sec-fetch-site'))) refuse(403, 'proxy_origin_denied');
      if (route.functionName === 'admin-api' && !['GET', 'HEAD', 'OPTIONS'].includes(request.method) && origin !== frontendOrigin) refuse(403, 'proxy_origin_denied');
      if (route.logicalPath === '/v1/security/challenge') {
        for (const key of ['attempt_id', 'parent_origin', 'theme']) if (url.searchParams.getAll(key).length > 1) refuse(400, 'proxy_path_invalid');
        const parent = url.searchParams.get('parent_origin'); if (parent && parent !== frontendOrigin) refuse(403, 'proxy_origin_denied');
      }
      const declared = request.headers.get('content-length');
      if (declared !== null && (!/^[0-9]+$/.test(declared) || Number(declared) > maxRequestBytes)) refuse(413, 'proxy_request_too_large');
      abortListener = () => controller.abort();
      request.signal.addEventListener('abort', abortListener, {once: true});
      if (request.signal.aborted) controller.abort();
      timer = setTimeout(() => controller.abort(), timeoutMs);
      const bytes = await boundedBytes(request.body, maxRequestBytes, controller.signal, 413, 'proxy_request_too_large');
      const headers = new Headers();
      for (const [name, value] of request.headers) if (FORWARD_HEADERS.has(name)) headers.set(name, value);
      if (adminRead && !origin) headers.set('Origin', frontendOrigin);
      headers.set('Cache-Control', 'no-store');
      // Do not assume all Fetch runtimes expose decoded bodies identically.
      headers.set('Accept-Encoding', 'identity');
      const outgoing = new Request(route.upstream, {method: request.method, headers,
        body: ['GET', 'HEAD'].includes(request.method) ? undefined : bytes,
        redirect: 'manual', cache: 'no-store', signal: controller.signal});
      attempted = true;
      const upstream = await fetchImpl(outgoing);
      const nativeCallback = nativeGoogleRedirect(upstream, route, request.method);
      if (!nativeCallback && (upstream.status >= 300 && upstream.status < 400 || upstream.headers.has('location'))) {
        await upstream.body?.cancel(); refuse(502, 'proxy_redirect_denied');
      }
      const encoding = upstream.headers.get('content-encoding');
      if (encoding && encoding.trim().toLowerCase() !== 'identity') {
        await upstream.body?.cancel(); refuse(502, 'proxy_encoding_unqualified');
      }
      const size = upstream.headers.get('content-length');
      if (size !== null && (!/^[0-9]+$/.test(size) || Number(size) > maxResponseBytes)) {
        await upstream.body?.cancel(); refuse(502, 'proxy_response_too_large');
      }
      const output = await boundedBytes(upstream.body, maxResponseBytes, controller.signal, 502, 'proxy_response_too_large');
      const response = responseHeaders(upstream, route);
      const mime = upstream.headers.get('content-type')?.split(';')[0].trim().toLowerCase();
      const document = DOCUMENTS.get(route.logicalPath);
      if (upstream.ok && document) {
        if (upstream.headers.get('X-Collect-Document') !== document || !response.has('Content-Security-Policy')) refuse(502, 'proxy_document_unqualified');
        if (request.method !== 'HEAD') {
          const text = new TextDecoder('utf-8', {fatal: true}).decode(output);
          if (!/^\s*(?:<!doctype html[^>]*>\s*)?<html\b/i.test(text)) refuse(502, 'proxy_document_unqualified');
        }
        response.set('Content-Type', 'text/html; charset=utf-8');
      } else if (!nativeCallback && mime === 'text/html') refuse(502, 'proxy_document_unqualified');
      return new Response(['HEAD'].includes(request.method) || [204, 205, 304].includes(upstream.status) ? null : output,
        {status: upstream.status, statusText: upstream.statusText, headers: response});
    } catch (error) {
      const unknown = attempted && effectful;
      if (error instanceof ProxyFailure) return failure(error.status,
        unknown ? 'proxy_outcome_unknown' : error.code, unknown ? error.code : undefined);
      return failure(controller.signal.aborted ? 504 : 502,
        unknown ? 'proxy_outcome_unknown' : 'proxy_unavailable',
        unknown ? controller.signal.aborted ? 'proxy_deadline' : 'proxy_upstream_failure' : undefined);
    } finally {
      clearTimeout(timer);
      if (abortListener) request.signal.removeEventListener('abort', abortListener);
    }
  };
}
