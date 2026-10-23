import {renderLocalChallengeDocument} from '../../platform-supabase-free/local-challenge.mjs';
import {createCollectTransport, SUPABASE_ORIGIN} from './supabase-transport.js';

function failure(status, code, message) {
  return Response.json({error: {code, message}}, {status, headers: {
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
  }});
}

export function createAdminWorker({fetchImpl = (request, init) => globalThis.fetch(request, init)} = {}) {
  return {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.origin !== env.ADMIN_ORIGIN) {
      return failure(403, 'origin_denied', 'This workspace origin is unavailable.');
    }
    const backend = env.COLLECT_BACKEND ?? 'supabase';
    if (backend !== 'cloudflare' && backend !== 'supabase') {
      return failure(503, 'backend_configuration_invalid', 'The workspace backend is unavailable.');
    }
    if (backend === 'supabase') {
      // The target is compiled into the transport. A configuration mismatch
      // fails closed instead of choosing a different project or legacy API.
      if (env.SUPABASE_URL !== SUPABASE_ORIGIN) {
        return failure(503, 'backend_configuration_invalid', 'The workspace backend is unavailable.');
      }
      let transport;
      try {
        transport = createCollectTransport({frontendOrigin: env.ADMIN_ORIGIN, fetchImpl});
      } catch {
        return failure(503, 'backend_configuration_invalid', 'The workspace backend is unavailable.');
      }
      // Presentation only: use the validated configured frontend, never the URL as authority.
      const parent = renderLocalChallengeDocument(request, {origin: env.ADMIN_ORIGIN});
      if (parent) return parent;
      const managed = url.pathname === '/api' || url.pathname.startsWith('/api/') ||
        url.pathname === '/v1' || url.pathname.startsWith('/v1/') ||
        url.pathname === '/functions' || url.pathname.startsWith('/functions/') ||
        url.pathname === '/privacy/account-deletion' || url.pathname.startsWith('/privacy/account-deletion/');
      if (managed) {
        const response = await transport(request);
        return response ?? failure(404, 'not_found', 'This service route is unavailable.');
      }
    }
    if (backend === 'cloudflare' && (url.pathname === '/api' || url.pathname.startsWith('/api/'))) {
      if (!url.pathname.startsWith('/api/admin/')) {
        return failure(404, 'not_found', 'This service route is unavailable.');
      }
      if (!env.PLATFORM_API?.fetch) {
        return failure(503, 'service_unavailable', 'The workspace service is unavailable.');
      }
      try {
        // Preserve the original Admin URL, Origin and cookie. Rewriting to the
        // API hostname would break the account's origin-bound authority.
        const response = await env.PLATFORM_API.fetch(request);
        const output = new Response(response.body, response);
        output.headers.set('Cache-Control', 'no-store');
        output.headers.set('X-Content-Type-Options', 'nosniff');
        output.headers.set('Referrer-Policy', 'no-referrer');
        return output;
      } catch {
        return failure(503, 'service_unavailable', 'The workspace service is unavailable.');
      }
    }
    const response = await env.ASSETS.fetch(request);
    if (response.headers.get('Content-Type')?.split(';', 1)[0].trim().toLowerCase() === 'text/html') {
      // Static HTML participates in the service worker's exact-byte manifest.
      // Preserve it through intermediaries, including on SPA fallback routes.
      const output = new Response(response.body, response);
      output.headers.set('Cache-Control', 'no-store, no-transform');
      return output;
    }
    return response;
  },
  };
}

export default createAdminWorker();
