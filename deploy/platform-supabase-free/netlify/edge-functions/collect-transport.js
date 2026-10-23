import {createCollectTransport} from '../../transport.mjs';
import {PUBLIC_CONFIG, validatePublicConfiguration} from '../../public-config.mjs';
import {renderLocalChallengeDocument} from '../../local-challenge.mjs';

function failure(status, code) {
  return Response.json({code}, {status, headers: {
    'Cache-Control': 'private, no-store, max-age=0',
    'CDN-Cache-Control': 'no-store', 'Surrogate-Control': 'no-store',
    'Netlify-CDN-Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
    'Cross-Origin-Resource-Policy': 'same-origin',
  }});
}
function managed(path) {
  return ['/api', '/v1', '/functions', '/privacy/account-deletion'].some(prefix =>
    path === prefix || path.startsWith(prefix + '/'));
}

export function createFreeHost({configuration = PUBLIC_CONFIG, fetchImpl = globalThis.fetch,
  transportOptions = {}} = {}) {
  const selected = validatePublicConfiguration(configuration);
  const transport = createCollectTransport({...transportOptions,
    frontendOrigin: selected.frontendOrigin, fetchImpl});
  return async function handle(request, context) {
    const url = new URL(request.url);
    if (url.origin !== selected.frontendOrigin || url.username || url.password || url.hash ||
        request.headers.has('host') && request.headers.get('host') !== url.host) {
      return failure(421, 'proxy_origin_invalid');
    }
    let segments;
    try { segments = url.pathname.split('/').map(decodeURIComponent); }
    catch { return failure(400, 'proxy_path_invalid'); }
    if (segments.some(part => part.startsWith('._') || part === '.DS_Store')) return failure(404, 'filesystem_metadata_unavailable');
    const challengeParent = renderLocalChallengeDocument(request);
    if (challengeParent) return challengeParent;
    if (url.pathname.startsWith('/admin/auth/local-challenge/')) return failure(404, 'parent_path_invalid');
    if (managed(url.pathname)) {
      // An unknown path in an API namespace cannot fall through to the SPA.
      return await transport(request) ?? failure(404, 'proxy_route_not_allowed');
    }
    if (!['GET', 'HEAD'].includes(request.method)) return failure(405, 'proxy_method_invalid');
    if (!context || typeof context.next !== 'function') return failure(503, 'static_host_unavailable');
    try {
      const response = await context.next();
      if (!(response instanceof Response)) return failure(503, 'static_host_unavailable');
      if (response.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() !== 'text/html') return response;
      // The existing Flutter HTML is in an exact-byte service-worker manifest.
      const headers = new Headers(response.headers);
      headers.set('Cache-Control', 'no-store, no-transform');
      headers.set('CDN-Cache-Control', 'no-store');
      headers.set('Netlify-CDN-Cache-Control', 'no-store');
      return new Response(request.method === 'HEAD' ? null : response.body,
        {status: response.status, statusText: response.statusText, headers});
    } catch {
      return failure(503, 'static_host_unavailable');
    }
  };
}

export default createFreeHost();

// The API classifier above owns only exact reserved namespaces. The catch-all
// also lets context.next preserve static/deep-link HTML bytes and no-transform
// semantics consistently; non-HTML asset bodies stream through unchanged.
export const config = {
  path: '/*',
  onError: 'fail',
};
