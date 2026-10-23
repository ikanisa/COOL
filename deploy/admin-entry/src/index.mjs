// A separate, reviewable replacement for the legacy assets-only Admin entry.
// No service/data bindings, upstream fetches, session migration or account logic.
const LEGACY_ORIGIN = 'https://admin.collect.ikanisa.com';
const ADMIN_ORIGIN = 'https://platform-admin.collect.ikanisa.com';

// Natural activation waits for the previous worker's controlled clients to close.
// Leave caches, localStorage, IndexedDB, open forms and request journals untouched.
const RETIREMENT_WORKER = `'use strict';
self.addEventListener('activate', (event) => {
  event.waitUntil(self.registration.unregister());
});
`;

function headers() {
  return new Headers({
    'Cache-Control': 'no-store, no-transform',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
    'X-Frame-Options': 'DENY',
    'Cross-Origin-Resource-Policy': 'same-origin',
  });
}

function denied(request, status, code) {
  const output = headers();
  output.set('Content-Type', 'application/json; charset=utf-8');
  return new Response(request.method === 'HEAD' ? null : JSON.stringify({error: {code}}), {
    status, headers: output,
  });
}

function acceptsHtml(value) {
  return value.split(',').some((range) => {
    const [type, ...parameters] = range.toLowerCase().trim().split(';');
    if (type !== 'text/html' && type !== 'application/xhtml+xml') return false;
    const quality = parameters.find((item) => item.trim().startsWith('q='));
    if (!quality) return true;
    const q = quality.trim().slice(2);
    return /^(?:0(?:\.\d{1,3})?|1(?:\.0{1,3})?)$/.test(q) && Number(q) > 0;
  });
}

export default {
  fetch(request) {
    const url = new URL(request.url);
    if (url.origin !== LEGACY_ORIGIN) return denied(request, 403, 'origin_denied');
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      const response = denied(request, 405, 'legacy_write_denied');
      response.headers.set('Allow', 'GET, HEAD');
      return response;
    }
    if (request.headers.has('Authorization') || request.headers.has('Proxy-Authorization')) {
      return denied(request, 403, 'credential_request_denied');
    }
    // Reject ambiguous path encodings before deciding whether a route is a UI.
    let decoded;
    try { decoded = decodeURIComponent(url.pathname); }
    catch { return denied(request, 400, 'invalid_path'); }
    if (/[\\\u0000-\u0020\u007f%]/.test(decoded) || /%2f/i.test(url.pathname)) {
      return denied(request, 400, 'invalid_path');
    }
    // Historical bootstraps register both names, sometimes with a version query.
    // These exact JS resources must never redirect to another origin or to HTML.
    if (url.pathname === '/custom-sw.js' || url.pathname === '/flutter_service_worker.js') {
      const output = headers();
      output.set('Content-Type', 'text/javascript; charset=utf-8');
      output.set('Service-Worker-Allowed', '/');
      return new Response(request.method === 'HEAD' ? null : RETIREMENT_WORKER, {headers: output});
    }
    // A fetch/XHR or stale subresource must not acquire the new application's
    // code or credentials through the entry redirect. No request is forwarded.
    const destination = request.headers.get('Sec-Fetch-Dest');
    const mode = request.headers.get('Sec-Fetch-Mode');
    const accept = request.headers.get('Accept') ?? '';
    const documentMetadata = destination === 'document' && mode === 'navigate';
    const absentMetadata = destination === null && mode === null;
    const legacyDocument = absentMetadata && (acceptsHtml(accept) ||
      (request.method === 'HEAD' && (accept === '' || accept.trim() === '*/*')));
    if (!documentMetadata && !legacyDocument) {
      return denied(request, 410, 'legacy_resource_retired');
    }
    // Only documented UI entry paths are redirected. All API/auth/function and
    // asset aliases fall through to a non-HTML denial, including encoded aliases.
    if (!(url.pathname === '/' || url.pathname === '/index.html' ||
        url.pathname === '/admin' || url.pathname.startsWith('/admin/'))) {
      return denied(request, 410, 'legacy_resource_retired');
    }
    if (/(?:^|\/)(?:api|auth|functions|rest|graphql|rpc)(?:\/|$)/i.test(decoded) ||
        /\.(?:js|mjs|css|json|wasm|bin|png|jpe?g|gif|webp|svg|ico|woff2?|ttf|otf|map|xml|txt|html?)$/i.test(decoded) &&
        url.pathname !== '/index.html') {
      return denied(request, 410, 'legacy_resource_retired');
    }
    const output = headers();
    // Concatenation to a fixed origin cannot interpret a query as another host.
    // The destination uses hash routing. A path entry must become its canonical
    // fragment so login retains the task/query. For mixed path+hash URLs the
    // explicit path takes priority; an HTTP handler cannot see the original hash.
    // Root/index entries leave Location's fragment absent, preserving old hashes.
    const pathEntry = url.pathname === '/admin' || url.pathname.startsWith('/admin/');
    output.set('Location', pathEntry
      ? ADMIN_ORIGIN + '/#' + url.pathname + url.search
      : ADMIN_ORIGIN + url.pathname + url.search);
    return new Response(null, {status: 302, headers: output});
  },
};
